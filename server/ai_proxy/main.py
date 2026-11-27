import json
import os
import time
from collections import defaultdict
from typing import AsyncIterator, List

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
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

SYSTEM_PROMPT = """
Bạn là Trợ Lý AI chính thức của tựa game 2D Action RPG "Big-War" (chơi màn hình ngang trên Mobile iOS/Android & Web).
QUY TẮC TRẢ LỜI:
1. CHỈ giải đáp các câu hỏi liên quan đến game Big-War (nhân vật, kỹ năng, trang bị trợ thủ, leo tầng PvE, đấu Rank PvP, kết bạn, tổ đội, phòng Solo cược Vàng, kinh tế, mẹo chiến thuật...). Nếu người chơi hỏi chủ đề ngoài game (thời tiết, bài tập, lập trình, tin tức, đời sống...), hãy từ chối lịch sự trong 1 câu ngắn và mời họ đặt câu hỏi về Big-War.
2. Trả lời bằng tiếng Việt tự nhiên, thân thiện, trình bày súc tích, rõ ý (khoảng 2–5 câu hoặc gạch đầu dòng ngắn), tuyệt đối bám sát số liệu thật bên dưới, không tự bịa tính năng không có trong game (ví dụ: game KHÔNG dùng Kim Cương, chỉ dùng Xu và Vàng).

KIẾN THỨC CHÍNH XÁC VỀ GAME BIG-WAR:
- Điều khiển chiến đấu: Di chuyển bằng Joystick ảo bên trái (hoặc phím WASD / Mũi tên trên PC/Web), nút Đánh thường ATK (phím Space / J), 3 chiêu thức nhân vật [1] [2] [3] tiêu hao năng lượng Ki, và nút [PET] (phím E) kích hoạt tuyệt kỹ Trợ Thủ AI.
- Hệ thống Nhân Vật & Giá mở khóa tại Cửa Hàng:
  1) George (Chiến Binh Búa - Cận chiến/Tanker, Mặc định MIỄN PHÍ 0 Vàng): Máu trâu, dễ chơi cho tân thủ. Chiêu [1] Búa Cuồng Phong (xoay 360° 180% DMG), [2] Nện Đất Chấn Động (240% DMG đẩy lùi), [3] Cơn Cuồng Nộ (6s +45% tốc chạy, +55% DMG, giảm 35% sát thương nhận & nổ AoE).
  2) Xạ Thủ Ranger / Lyra (Tầm xa/Cơ động - 4.000 Vàng): Mạnh thả diều (kiting). Chiêu [1] Tiễn Vũ Liên Châu (bắn 5 tên hình quạt), [2] Nhào Lộn Bẫy Gai (lộn né đòn + đặt bẫy nổ tăng tốc), [3] Mưa Sao Băng (8 mũi tên ánh sao truy đuổi).
  3) Hiệp Sĩ Tanker / Braum (Đỡ đòn/Khống chế - 4.000 Vàng): Cứng cáp nhất giao tranh. Chiêu [1] Húc Khiên Xung Kích, [2] Pháo Đài Sắt (giảm 65% sát thương nhận 4.5s + hồi 12% HP), [3] Địa Chấn Phán Quyết (3 vòng địa chấn hất văng rộng).
  4) Ninja Sát Thủ / Hayate (Chí mạng/Ám sát - 4.500 Vàng): Tốc độ cao, dồn sát thương mục tiêu đơn. Chiêu [1] Phi Tiêu Lướt Ảnh, [2] Khói Ẩn Thân (tàng hình 3.5s, +45% tốc chạy & +40% bạo kích), [3] Ảnh Sát Liên Hoàn (dịch chuyển ra sau lưng chém chữ X 320% DMG).
  5) Nova Blade / NOVA-07 (Đấu sĩ Ánh Sáng cơ động - 6.000 Vàng): Công thủ toàn diện. Chiêu [1] Energy Slash (chém sóng năng lượng đẩy lùi), [2] Shadow Dash (lướt chém tốc độ cao), [3] Quantum Burst (mở trường lượng tử hút địch vào tâm nổ 300% DMG).
  6) Shadow / SHADOW-01 (Sát Thủ Hư Không - 6.000 Vàng): Chiêu [1] Plasma Shot (3 dao hư không), [2] Cyber Spin (xoay lưỡi hái 360° + tăng tốc), [3] Phantom Dash (lướt xuyên chiến trường nổ ấn chú 310% DMG).
  7) Ember / EMBER-02 (Phù Thủy Hỏa Cầu / Pháp Sư - 6.500 Vàng): Sát thương diện rộng cực lớn. Chiêu [1] Hỏa Cầu Liên Hoàn, [2] Cột Lửa Địa Ngục (4 cột lửa nổ 230% DMG), [3] Thái Dương Bộc Phá (nổ đại hỏa cầu + bắn tỏa 8 cầu lửa 8 hướng).
  (Ngoài ra hệ thống còn có Valeria - Pháp Sư Băng Hỏa và Garrick - Chiến Binh Cổ Đại hệ Thổ).
- Hệ thống Cấp Độ:
  • Cấp Nhân Vật Vĩnh Viễn (Lv.1 -> Lv.100): Mỗi tướng có cấp thông thạo riêng, nhận EXP sau mọi trận PvE & PvP (thắng hay thua đều được cộng EXP rèn luyện), mỗi cấp cộng vĩnh viễn HP, Ki và ATK theo hệ tướng.
  • Cấp Trong Trận PvE (Lv.1 -> Lv.15): Nhặt Ngọc EXP rơi ra khi diệt quái để mạnh dần trong màn chơi.
- Hệ thống Trợ Thủ AI Bay (8 loại mở bán tại Cửa Hàng, tự bay theo bắn hỗ trợ & hút vật phẩm, bấm PET/E dùng chiêu riêng):
  • Bậc 1: Trợ Thủ Công Kích (2.000 Vàng - Mưa Đạn Plasma 6 tia 360°), Trợ Thủ Phòng Ngự (2.500 Vàng - giảm 30% DMG nhận, chiêu Lồng Phản Chấn khiên 55% đẩy lùi), Trợ Thủ Khống Chế (3.000 Vàng - làm chậm 40%, chiêu Bão Tuyết đóng băng quái 3s).
  • Bậc 2: Cyber Drone PIXEL-01 (4.000 Vàng - hồi 25% HP + bật khiên 45%), Hồ Ly Luna (4.500 Vàng - làm chậm + hồi 40% Ki & giảm 3s hồi chiêu tướng), ORBIT-03 Drone (5.000 Vàng - Pháo Laser Quỹ Đạo nổ + bắn liên thanh 4s).
  • Bậc 3 Huyền Thoại: Aegis-X9 Lôi Từ (8.000 Vàng - tự hút vàng + Trường Trọng Lực gom quái, hút toàn map & tạo khiên 35%), Pyro-Frost Dragon / Rồng Băng Hỏa (10.000 Vàng - Hơi Thở Bão Tố nổ sát thương, đóng băng 2.5s & tăng 30% ATK trong 5s).
- Kinh tế & Vòng Quay May Mắn:
  • Tiền tệ gồm Xu và Vàng với tỷ giá cố định: 1 Xu = 1.000 Vàng (bấm nút Xu ở Cửa Hàng hoặc Sảnh Chờ để đổi sang Vàng mở khóa tướng & trợ thủ).
  • Cách kiếm Xu & Vàng: Nhặt Xu rơi trong trận PvE; vượt ải tầng N thưởng (200 × N) Vàng; thắng PvP Rank; thắng cược phòng Solo; quay Vòng Quay May Mắn.
  • Vòng Quay May Mắn: Có 6 ô (0 Xu, 1 Xu, 2 Xu, 3 Xu, 5 Xu và Jackpot 10 Xu = 10.000 Vàng), miễn phí 1 lượt mỗi ngày (làm mới lúc 07:00 sáng giờ Việt Nam / 00:00 UTC).
- Bản đồ & Chế độ PvE Vượt Ải:
  • 5 bản đồ chiến trường: Đấu Trường Băng Giá, Đảo Băng Tuyết, Rừng Cây Cổ Thụ, Điện Thờ Cổ Long, Hỏa Ngục Dung Nham (có các cột đá chắn đạn và điểm ăn Buff).
  • Quái vật PvE: Xác Sống Hầm Ngục (Zombie tìm đường thông minh A*), Cung Thủ Xương Khô (Skeleton giữ khoảng cách bắn tỉa), và Chúa Tể Hầm Ngục Hoàng Kim (Boss 2 giai đoạn: gọi đệ ở mốc 70%/50%/30% máu, dưới 50% máu hóa Cuồng Nộ tăng tốc & sát thương). Tầng càng cao số lượng Boss/quái và chỉ số càng mạnh; hạ hết Boss sẽ quét sạch quái còn lại để qua tầng.
- Đấu Trường PvP Rank, Tổ Đội & Phòng Solo Cược Vàng:
  • Đấu Rank PvP thể thức Bo3 (thắng 2 hiệp): Gồm 3 chế độ 1v1 Đấu Đơn (thắng +200 Vàng), 2v2 Song Đấu (+350 Vàng), 4v4 Quân Đoàn (+500 Vàng). Nếu ghép trận quá 20 giây chưa đủ người thật, hệ thống tự bù AI Bot thông minh theo bậc Rank.
  • Hệ thống 7 Bậc Rank & Sao: Đồng -> Bạc -> Vàng -> Bạch Kim -> Kim Cương (mỗi bậc cần 3 sao để thăng hạng; thắng +1 sao, thua -1 sao, không bị trừ dưới 0 sao Đồng) -> Huyền Thoại (từ 15 sao trở lên) -> Thách Đấu (danh hiệu dành riêng cho Top 10 Server có số sao cao nhất bậc Huyền Thoại).
  • Bạn bè, Tổ đội & Phòng Đấu Solo/Tùy chọn: Kết bạn qua Mã ID (Player Code) tại Sảnh Chờ, xem trạng thái Online thời gian thực, mời bạn vào Tổ Đội (Party) đánh 2v2/4v4, hoặc mở Phòng Solo / Đấu Tùy Chọn để chọn bản đồ và đặt mức cược Vàng giao hữu công bằng với bạn bè.
""".strip()

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
                "maxOutputTokens": 360,
            },
        }

    contents.append({"role": "user", "parts": [{"text": user_text}]})
    return {
        "system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
        "contents": contents,
        "generationConfig": {
            "temperature": 0.4,
            "maxOutputTokens": 360,
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


@app.post("/api/chat/stream")
async def chat_stream(req: ChatRequest, request: Request):
    client_ip = request.client.host if request.client else "unknown"
    _check_rate_limit(client_ip)

    if not GEMINI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="Máy chủ AI chưa cấu hình GEMINI_API_KEY. Ứng dụng sẽ dùng chế độ demo offline.",
        )

    candidates_to_try = _get_ordered_candidate_models()

    async def event_generator() -> AsyncIterator[str]:
        last_error_detail = "Không có model nào phản hồi thành công."

        async with httpx.AsyncClient(timeout=httpx.Timeout(15.0, connect=6.0)) as client:
            for model in candidates_to_try:
                url = (
                    f"https://generativelanguage.googleapis.com/v1beta/models/"
                    f"{model}:streamGenerateContent?alt=sse"
                )
                payload = _build_payload_for_model(model, req)
                yielded_any = False

                try:
                    async with client.stream(
                        "POST",
                        url,
                        headers={
                            "Content-Type": "application/json; charset=utf-8",
                            "Accept": "text/event-stream",
                            "x-goog-api-key": GEMINI_API_KEY,
                        },
                        json=payload,
                    ) as resp:
                        if resp.status_code == 429:
                            _model_cooldown_until[model] = time.time() + 60.0
                            last_error_detail = f"Model {model} đã hết hạn mức (429)."
                            continue
                        if resp.status_code == 404:
                            _model_cooldown_until[model] = time.time() + 600.0
                            last_error_detail = f"Model {model} không khả dụng (404)."
                            continue
                        if resp.status_code in (400, 500, 503):
                            _model_cooldown_until[model] = time.time() + 45.0
                            last_error_detail = f"Model {model} trả về lỗi {resp.status_code}."
                            continue
                        if resp.status_code < 200 or resp.status_code >= 300:
                            last_error_detail = f"Gemini API ({model}) lỗi {resp.status_code}."
                            continue

                        async for raw_line in resp.aiter_lines():
                            line = raw_line.strip()
                            if not line or not line.startswith("data:"):
                                continue
                            data_str = line[5:].strip()
                            if not data_str or data_str == "[DONE]":
                                continue
                            try:
                                chunk_json = json.loads(data_str)
                            except json.JSONDecodeError:
                                continue

                            cands = chunk_json.get("candidates") or []
                            if not cands:
                                continue
                            parts = cands[0].get("content", {}).get("parts") or []
                            delta = "".join(p.get("text", "") for p in parts)
                            if delta:
                                yielded_any = True
                                out = json.dumps(
                                    {"delta": delta, "model": model},
                                    ensure_ascii=False,
                                )
                                yield f"data: {out}\n\n"

                        if yielded_any:
                            _model_cooldown_until.pop(model, None)
                            yield "data: [DONE]\n\n"
                            return

                        last_error_detail = f"Model {model} không trả về nội dung."
                except httpx.TimeoutException:
                    _model_cooldown_until[model] = time.time() + 30.0
                    last_error_detail = f"Model {model} quá thời gian chờ."
                    if yielded_any:
                        yield "data: [DONE]\n\n"
                        return
                    continue
                except httpx.HTTPError as exc:
                    _model_cooldown_until[model] = time.time() + 30.0
                    last_error_detail = f"Lỗi kết nối tới {model}: {exc}"
                    if yielded_any:
                        yield "data: [DONE]\n\n"
                        return
                    continue

        err_payload = json.dumps({"error": last_error_detail}, ensure_ascii=False)
        yield f"data: {err_payload}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream; charset=utf-8",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
