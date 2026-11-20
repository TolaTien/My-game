# Big-War AI Proxy Server (FastAPI)

Máy chủ trung gian giữ `GEMINI_API_KEY` phía server để ứng dụng Flutter (Android APK / Web) **không bao giờ chứa khóa API trong mã nguồn hoặc gói cài đặt**.

## Cài đặt & chạy cục bộ

```bash
cd server/ai_proxy
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
# source .venv/bin/activate

pip install -r requirements.txt
copy .env.example .env   # Điền GEMINI_API_KEY thật vào file .env này
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## Kết nối từ Flutter

Truyền địa chỉ proxy khi chạy hoặc build Flutter:

```bash
# Trên Android Emulator (10.0.2.2 trỏ tới localhost của máy tính)
flutter run --dart-define=AI_PROXY_URL=http://10.0.2.2:8000

# Trên Chrome Web
flutter run -d chrome --dart-define=AI_PROXY_URL=http://localhost:8000
```

Nếu không truyền `AI_PROXY_URL` (hoặc server tắt), ứng dụng tự động chạy **Chế độ Demo (FAQ & Keyword NLP Offline)** mà không bị lỗi.
