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
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest").strip()
RATE_LIMIT_PER_MINUTE = int(os.getenv("RATE_LIMIT_PER_MINUTE", "20"))

SYSTEM_PROMPT = (
    "Bạn là Trợ Lý AI độc quyền của game 2D Action RPG Big-War. "
    "QUY TẮC BẮT BUỘC: CHỈ trả lời câu hỏi liên quan trực tiếp đến game Big-War. "
    "Nếu người dùng hỏi bất kỳ chủ đề nào ngoài game (thời tiết, học tập, lập trình, đời sống, chính trị...), "
    "từ chối lịch sự trong đúng 1 câu ngắn và nhắc họ chỉ hỏi về game Big-War. "
    "Trả lời cực ngắn gọn (tối đa 2–4 câu) bằng tiếng Việt để tiết kiệm token. "
    "Dữ liệu game: Level tướng 1-100 tăng HP/Ki/ATK; 1 Xu = 1.000 Vàng; "
    "PvP 1v1/2v2/4v4 có tổ đội & AI Bot A*; Tướng: George, Nova Blade, Shadow, Ember, Lyra, Braum, Hayate; "
    "Trợ thủ AI bay: Aegis-X9, Hỏa/Thổ/Băng Linh; Vòng quay miễn phí mỗi ngày 07:00 VN."
)

app = FastAPI(title="Big-War AI Proxy Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Simple in-memory per-IP rate limiter
_request_timestamps: dict[str, list[float]] = defaultdict(list)


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


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": GEMINI_MODEL,
        "api_key_configured": bool(GEMINI_API_KEY),
    }


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    _check_rate_limit(client_ip)

    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="Máy chủ AI chưa cấu hình GEMINI_API_KEY. Ứng dụng sẽ dùng chế độ demo offline.",
        )

    contents = [
        {"role": msg.role, "parts": [{"text": msg.text}]}
        for msg in req.history[-2:]
    ]
    contents.append({"role": "user", "parts": [{"text": req.message.strip()}]})

    payload = {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": contents,
        "generationConfig": {
            "temperature": 0.4,
            "maxOutputTokens": 220,
        },
    }

    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL}:generateContent"
    )

    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            resp = await client.post(
                url,
                headers={
                    "Content-Type": "application/json; charset=utf-8",
                    "x-goog-api-key": GEMINI_API_KEY,
                },
                json=payload,
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Hết thời gian chờ phản hồi từ Gemini.")
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Lỗi kết nối tới Gemini: {exc}")

    if resp.status_code < 200 or resp.status_code >= 300:
        raise HTTPException(
            status_code=502,
            detail=f"Gemini API trả về mã lỗi {resp.status_code}.",
        )

    data = resp.json()
    candidates = data.get("candidates") or []
    if not candidates:
        raise HTTPException(status_code=502, detail="Không nhận được câu trả lời từ mô hình.")

    parts = candidates[0].get("content", {}).get("parts", [])
    reply_text = "".join(p.get("text", "") for p in parts).strip()
    if not reply_text:
        raise HTTPException(status_code=502, detail="Phản hồi từ mô hình bị rỗng.")

    return ChatResponse(reply=reply_text, model=GEMINI_MODEL)
