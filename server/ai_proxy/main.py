import os
import time
from collections import defaultdict
from typing import List

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "20"))

# Danh sách model ưu tiên theo hạn mức RPD/RPM (tự động chuyển model kế tiếp khi 429/503/404)
DEFAULT_FALLBACK_MODELS = [
    "gemini-3.5-flash-lite",      # 15 RPM / 500 RPD
    "gemini-3.1-flash-lite",      # 15 RPM / 500 RPD
    "gemini-flash-lite-latest",   # Alias ổn định
    "gemini-2.5-flash-lite",      # 10 RPM / 20 RPD
    "gemini-2.5-flash",           # 5 RPM / 20 RPD
    "gemini-3-flash",             # 5 RPM / 20 RPD
    "gemini-3.6-flash",           # 5 RPM / 20 RPD
    "gemini-3.8-flash",           # 5 RPM / 20 RPD
    "gemini-4-hydrogen",          # 5 RPM / 20 RPD
    "gemma-4-31b-it",             # 30 RPM / 14.4K RPD
    "gemma-4-26b-it",             # 30 RPM / 14.4K RPD
]


def _build_model_chain() -> list[str]:
    custom_list = os.getenv("GEMINI_MODELS", "").strip()
    primary = os.getenv("GEMINI_MODEL", "").strip()

    raw_models: list[str] = []
    if primary:
        raw_models.append(primary)
    if custom_list:
        raw_models.extend(m.strip() for m in custom_list.split(",") if m.strip())
    else:
        raw_models.extend(DEFAULT_FALLBACK_MODELS)

    seen: set[str] = set()
    chain: list[str] = []
    for m in raw_models:
        if m and m not in seen:
            seen.add(m)
            chain.append(m)
    return chain


MODEL_CHAIN: list[str] = _build_model_chain()

SYSTEM_PROMPT = (
    "Bạn là Trợ Lý AI độc quyền của game 2D Action RPG Big-War. "
    "QUY TẮC BẮT BUỘC: CHỈ trả lời câu hỏi liên quan trực tiếp đến game Big-War. "
    "Nếu người dùng hỏi bất kỳ chủ đề nào ngoài game (thời tiết, học tập, lập trình, đời sống, chính trị...), "
    "từ chối lịch sự trong đúng 1 câu ngắn và nhắc họ chỉ hỏi về game Big-War. "
    "Trả lời ngắn gọn, tự nhiên (tối đa 2–4 câu) bằng tiếng Việt để tiết kiệm token. "
    "Dữ liệu game: Level tướng 1-100 tăng HP/Ki/ATK; 1 Xu = 1.000 Vàng; "
    "PvP 1v1/2v2/4v4 có tổ đội & AI Bot A*; Tướng: George, Nova Blade, Shadow, Ember, Lyra, Braum, Hayate; "
    "Trợ thủ AI bay: Aegis-X9, Hỏa/Thổ/Băng Linh; Vòng quay miễn phí mỗi ngày 07:00 VN."
)

app = FastAPI(title="Big-War AI Proxy Server", version="1.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Simple in-memory per-IP rate limiter
_request_timestamps: dict[str, list[float]] = defaultdict(list)

# Cooldown cho từng model khi gặp 429/503/404 để tránh mất thời gian gọi lại liên tục
_model_cooldown_until: dict[str, float] = {}


class HistoryMessage(BaseModel):
    role: str = Field(pattern="^(user|model)$")
    text: str = Field(max_length=1000)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=600)
    history: List[HistoryMessage] = Field(default_factory=list, max_length=4)


class ChatResponse(BaseModel):
    reply: str
    model: str


def _check_rate_limit(client_ip: str) -> None:
    now = time.time()
    window_start = now - 60.0
    timestamps = [t for t in _request_timestamps[client_ip] if t >= window_start]
    if len(timestamps) >= RATE_LIMIT_PER_MINUTE:
        raise HTTPException(
            status_code=429,
            detail="Bạn đã gửi quá nhiều yêu cầu trong 1 phút. Vui lòng thử lại sau.",
        )
    timestamps.append(now)
    _request_timestamps[client_ip] = timestamps


def _get_ordered_candidate_models() -> list[str]:
    now = time.time()
    ready = [m for m in MODEL_CHAIN if _model_cooldown_until.get(m, 0.0) <= now]
    if ready:
        return ready
    # Nếu tất cả đều đang cooldown, thử lại từ model sắp hết cooldown nhất
    return sorted(MODEL_CHAIN, key=lambda m: _model_cooldown_until.get(m, 0.0))


def _build_payload_for_model(model: str, req: ChatRequest) -> dict:
    is_gemma = model.lower().startswith("gemma-")
    contents = [
        {"role": msg.role, "parts": [{"text": msg.text}]}
        for msg in req.history[-2:]
    ]
    user_text = req.message.strip()

    if is_gemma:
        # Một số model Gemma không hỗ trợ system_instruction riêng -> gộp vào tin nhắn user
        contents.append(
            {
                "role": "user",
                "parts": [{"text": f"[Hướng dẫn hệ thống]\n{SYSTEM_PROMPT}\n\n[Câu hỏi người chơi]\n{user_text}"}],
            }
        )
        return {
            "contents": contents,
            "generationConfig": {
                "temperature": 0.4,
                "maxOutputTokens": 240,
            },
        }

    contents.append({"role": "user", "parts": [{"text": user_text}]})
    return {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": contents,
        "generationConfig": {
            "temperature": 0.4,
            "maxOutputTokens": 240,
        },
    }


def _health_payload() -> dict:
    now = time.time()
    available = [m for m in MODEL_CHAIN if _model_cooldown_until.get(m, 0.0) <= now]
    return {
        "status": "ok",
        "model": available[0] if available else MODEL_CHAIN[0],
        "models": MODEL_CHAIN,
        "available_models": available,
        "api_key_configured": bool(GEMINI_API_KEY),
    }


@app.get("/")
async def root():
    return _health_payload()


@app.get("/health")
async def health():
    return _health_payload()


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    _check_rate_limit(client_ip)

    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="Máy chủ AI chưa cấu hình GEMINI_API_KEY. Ứng dụng sẽ dùng chế độ demo offline.",
        )

    candidates_to_try = _get_ordered_candidate_models()
    last_error_status = 502
    last_error_detail = "Không có model nào phản hồi thành công."

    async with httpx.AsyncClient(timeout=8.0) as client:
        for model in candidates_to_try:
            url = (
                f"https://generativelanguage.googleapis.com/v1beta/models/"
                f"{model}:generateContent"
            )
            payload = _build_payload_for_model(model, req)

            try:
                resp = await client.post(
                    url,
                    headers={
                        "Content-Type": "application/json; charset=utf-8",
                        "x-goog-api-key": GEMINI_API_KEY,
                    },
                    json=payload,
                )
            except httpx.TimeoutException:
                _model_cooldown_until[model] = time.time() + 30.0
                last_error_status = 504
                last_error_detail = f"Model {model} quá thời gian chờ."
                continue
            except httpx.HTTPError as exc:
                _model_cooldown_until[model] = time.time() + 30.0
                last_error_status = 502
                last_error_detail = f"Lỗi kết nối tới {model}: {exc}"
                continue

            if resp.status_code == 429:
                # Hết RPM/TPM/RPD -> tạm bỏ qua model này 60s và chuyển model tiếp theo
                _model_cooldown_until[model] = time.time() + 60.0
                last_error_status = 429
                last_error_detail = f"Model {model} đã hết hạn mức (429)."
                continue

            if resp.status_code == 404:
                # Tên model không tồn tại trên v1beta -> bỏ qua 10 phút và chuyển model tiếp theo
                _model_cooldown_until[model] = time.time() + 600.0
                last_error_status = 502
                last_error_detail = f"Model {model} không khả dụng (404)."
                continue

            if resp.status_code in (400, 500, 503):
                _model_cooldown_until[model] = time.time() + 45.0
                last_error_status = 502
                last_error_detail = f"Model {model} trả về lỗi {resp.status_code}."
                continue

            if resp.status_code < 200 or resp.status_code >= 300:
                last_error_status = 502
                last_error_detail = f"Gemini API ({model}) trả về mã lỗi {resp.status_code}."
                continue

            data = resp.json()
            candidates = data.get("candidates") or []
            if not candidates:
                last_error_detail = f"Model {model} không trả về nội dung."
                continue

            parts = candidates[0].get("content", {}).get("parts", [])
            reply_text = "".join(p.get("text", "") for p in parts).strip()
            if not reply_text:
                last_error_detail = f"Phản hồi từ {model} bị rỗng."
                continue

            # Thành công -> xóa cooldown nếu có và trả kết quả kèm tên model đã dùng
            _model_cooldown_until.pop(model, None)
            return ChatResponse(reply=reply_text, model=model)

    raise HTTPException(status_code=last_error_status, detail=last_error_detail)
