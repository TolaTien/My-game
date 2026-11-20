# 🏆 Big-War (Gold Rush Mobile) — 2D Pixel-Art Action RPG (Flutter + Flame)

> **Học phần INT1449 · Lập trình di động**  
> **Nhóm chủ đề:** Nhóm A — Game 2D với Flame (phát triển mở rộng từ dự án mẫu **Gold Rush**) kết hợp mở rộng **Trợ lý AI qua máy chủ Proxy giữ khóa + Chế độ Demo offline**.

---

## 1. Mục đích & Tính năng nổi bật

**Big-War (Gold Rush Mobile)** là tựa game 2D Action RPG đa nền tảng (Android & Web) xây dựng bằng **Flutter + Flame Engine**, gồm đầy đủ tính năng cốt lõi và mở rộng:

1. **Hệ thống Assets Data-Driven (`assets/data/*.json`)**:
   - Quản lý tách biệt Nhân vật (`heroes.json`), Kỹ năng (`skills.json`), Trợ thủ AI (`companions.json`), Quái vật (`enemies.json`) và Bản đồ (`maps.json`) qua `GameAssetRegistry`.
2. **Hệ thống Level Nhân Vật Vĩnh Viễn (Level 1 → 100)**:
   - Nhận EXP Thông Thạo sau mỗi trận PvE/PvP, cộng vĩnh viễn HP / Ki / ATK theo công thức tăng trưởng riêng của từng hệ tướng (`stat_growth_formula.dart`).
3. **PvE Vượt Ải Hầm Ngục & AI Tìm Đường A\***:
   - Quái cận chiến (Zombie) và Boss tìm đường tránh tường bằng thuật toán **A\*** (`astar_pathfinder.dart`), Skeleton bắn tỉa giữ khoảng cách (**Kiting AI**), có unit test thuần cho thuật toán A\*.
4. **PvP Đấu Trường Rank Online (1v1 / 2v2 / 4v4) + Kết Bạn & Tổ Đội (Party)**:
   - Kết bạn qua Mã ID (`Player Code`), lập tổ đội 2v2/4v4 đồng bộ thời gian thực qua **Firebase Realtime Database**, tự động bù **AI Bot A\* + FSM** khi thiếu người chơi hoặc khi offline.
5. **Kinh Tế (`1 Xu = 1.000 Vàng`), Cửa Hàng, Vòng Quay May Mắn (Reset 00:00 UTC) & Trợ Lý Chat AI**:
   - Trợ lý AI sử dụng kiến trúc **2 lớp tiết kiệm token**: lọc từ khóa tiếng Việt có dấu/không dấu + chặn câu hỏi ngoài phạm vi game ngay ở client (0 token), và gọi **AI Proxy Server (FastAPI)** giữ `GEMINI_API_KEY` phía máy chủ cho các câu hỏi mở. Khi không cấu hình server, tự động chạy **Chế độ Demo (FAQ Offline)**.

---

## 2. Yêu cầu môi trường & Cài đặt (trong < 15 phút)

- **Flutter SDK:** `>= 3.24` (Dart SDK `^3.13.5`)
- **Android Studio / Android SDK** (để chạy trên máy thật hoặc máy ảo Android)
- **Python 3.10+** *(tùy chọn — chỉ cần khi muốn chạy máy chủ AI Proxy cục bộ)*

```bash
# 1. Clone repo và cài thư viện Flutter
git clone <url-repo>
cd my-game
flutter pub get
```

---

## 3. Cấu hình môi trường (KHÔNG chứa khóa trong mã nguồn / APK)

1. **Cấu hình ứng dụng Flutter (tùy chọn cho Firebase & AI Proxy):**
   ```bash
   copy .env.example .env
   ```
   Điền các thông số dự án vào `.env` (file `.env` đã được khai báo trong `.gitignore` và **không** đóng gói vào `assets` của APK).  
   - Nếu để trống `AI_PROXY_URL`, Trợ lý AI tự động chạy **Chế độ Demo** không cần khóa API.
   - Nếu để trống `FIREBASE_*`, game vẫn chạy được ở chế độ offline với lưu trữ cục bộ (`SharedPreferences`).

2. **Cấu hình & chạy máy chủ AI Proxy giữ khóa Gemini (tùy chọn):**
   Xem chi tiết tại [server/ai_proxy/README.md](server/ai_proxy/README.md):
   ```bash
   cd server/ai_proxy
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt
   copy .env.example .env   # Điền GEMINI_API_KEY thật vào file này (chỉ nằm ở server)
   uvicorn main:app --host 0.0.0.0 --port 8000
   ```

---

## 4. Cách chạy & Đóng gói APK

```bash
# Chạy trên điện thoại Android thật / máy ảo (không cần khóa, chạy Demo Mode)
flutter run

# Chạy có nạp cấu hình từ .env (qua compile-time --dart-define-from-file)
flutter run --dart-define-from-file=.env

# Chạy trên trình duyệt Chrome
flutter run -d chrome --dart-define-from-file=.env

# Đóng gói file APK Release cho Android
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=.env
```

File APK sau khi đóng gói nằm tại: `build/app/outputs/flutter-apk/app-release.apk`.

---

## 5. Cách chạy kiểm thử & phân tích tĩnh

Dự án tích hợp GitHub Actions CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) tự động chạy `flutter analyze` và `flutter test` mỗi lần push/PR.

```bash
# Kiểm tra phân tích tĩnh (0 lỗi, 0 cảnh báo)
flutter analyze

# Chạy toàn bộ 23 unit test, widget test & test trợ năng (meetsGuideline)
flutter test --reporter expanded
```

---

## 6. Dữ liệu lưu ở đâu & Quyền riêng tư

### Vị trí lưu trữ dữ liệu
| Loại dữ liệu | Nơi lưu trữ | Mục đích |
|---|---|---|
| Hồ sơ người chơi offline, vàng/xu, cấp độ tướng, cài đặt âm thanh/điều khiển | Cục bộ trên thiết bị (`SharedPreferences`) | Giữ tiến trình khi tắt app hoặc mất mạng |
| Tài khoản đăng nhập (Email/UID) | `Firebase Authentication` | Xác thực người chơi khi chơi online |
| Bảng xếp hạng, Bạn bè, Tổ đội (Party), Phòng PvP thời gian thực | `Firebase Realtime Database` (bảo vệ bởi `database.rules.json`) | Đồng bộ PvP 1v1/2v2/4v4 & xếp hạng |
| Khóa `GEMINI_API_KEY` | **Chỉ nằm trên máy chủ** `server/ai_proxy/.env` | Không xuất hiện trong mã nguồn Flutter, lịch sử client hay APK |
| Lịch sử chat Trợ lý AI | Bộ nhớ tạm RAM trong phiên hộp thoại | Tự xóa khi đóng hộp thoại, không lưu dữ liệu nhạy cảm |

### Quyền Android (`AndroidManifest.xml`)
Ứng dụng chỉ khai báo đúng **2 quyền tối thiểu cần thiết**:
- `android.permission.INTERNET`: kết nối Firebase online và AI Proxy Server (khi bật).
- `android.permission.ACCESS_NETWORK_STATE`: kiểm tra trạng thái mạng để tự chuyển chế độ offline mượt mà.

---

## 7. Mục "Dùng AI"

Trong quá trình phát triển, nhóm có sử dụng trợ lý AI theo đúng quy định học phần:
- **Công cụ sử dụng:** Antigravity / Gemini, GitHub Copilot.
- **Phần hỗ trợ:**
  - Gợi ý cấu trúc tách tầng (`services/`, `registry/`, `game/ai/`), tối ưu thuật toán A\* và đồng bộ phòng PvP.
  - Hỗ trợ viết unit test, widget test và test trợ năng (`meetsGuideline`).
  - Hỗ trợ thiết kế kiến trúc AI Proxy Server (FastAPI) để tách khóa API khỏi ứng dụng Android/Web, lọc từ khóa tiếng Việt và giới hạn phạm vi trả lời tiết kiệm token.
  - Rà soát lỗi tĩnh (`flutter analyze`) và hoàn thiện tài liệu kỹ thuật.
- **Lưu trữ hội thoại quan trọng:** lưu trong thư mục `docs/ai/` khi nộp báo cáo cuối kỳ.
- Mọi dòng mã trong repository đều đã được thành viên trong nhóm tự chạy thử, kiểm tra và có thể giải thích chi tiết khi vấn đáp.
