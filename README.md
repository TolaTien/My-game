# 🏆 Gold Rush Mobile — 2D Pixel-Art Action RPG (Flutter + Flame)

Dự án **Gold Rush** được xây dựng hoàn chỉnh từ A–Z trên nền tảng **Flutter & Flame Engine**, đáp ứng toàn bộ 4 Phase trong lộ trình phát triển:

## ✨ Tính Năng Nổi Bật
1. **Hệ thống Assets Tách Rời & Data-Driven Registry (`assets/data/*.json`)**:
   - Dễ dàng thêm/chỉnh sửa Nhân vật (`heroes.json`), Kỹ năng (`skills.json`), Trợ thủ AI (`companions.json`), Quái vật (`enemies.json`), và Bản đồ (`maps.json`) chỉ bằng cách thêm file vào `assets/` (xem chi tiết tại [assets/HOW_TO_ADD_ASSETS.md](assets/HOW_TO_ADD_ASSETS.md)).
2. **Hệ thống Level Nhân Vật Vĩnh Viễn (Level 1 → 100)**:
   - Sau mỗi trận đấu (PvE / PvP), nhân vật nhận được **EXP Thông Thạo**, tự động lên cấp từ **1 đến 100** và được cộng vĩnh viễn **HP, Ki, Sức Đánh (ATK)** theo công thức tăng trưởng riêng của từng hệ tướng.
3. **PvE Vượt Ải Hầm Ngục (6+ Stages) & AI Tìm Đường A***:
   - Quái Zombie cận chiến dùng thuật toán **A*** tránh tường, Skeleton bắn xa giữ khoảng cách (**Kiting AI**), Boss cuối màn có thanh máu riêng & nhiều pattern tấn công, cùng 15 cấp độ tăng sức mạnh trong trận.
4. **PvP Đấu Trường Rank Online (1v1 / 2v2 / 4v4) + Kết Bạn & Mời Tổ Đội (Party Invite)**:
   - Kết bạn qua **Mã ID (`Player Code`)**, lập phòng **Tổ Đội (Party 2v2 / 4v4)** mời bạn bè vào chung team để ghép trận trên **Firebase Realtime Database**, tự động bù **AI Bot thông minh** sau 60s chờ.
5. **Kinh Tế (`1 Xu = 1000 Vàng`), Cửa Hàng, Vòng Quay May Mắn (Reset 00:00 UTC) & Trợ Lý Chat AI**:
   - Đổi `1 Xu = 1.000 Vàng`, mua Tướng/Trợ thủ/Skin, quay thưởng mỗi ngày và hỏi đáp trực tiếp với **Trợ Lý Chat AI (FAQ + Keyword NLP)**.

## 🚀 Cách Chạy & Đóng Gói APK Cho Mobile
```bash
# 1. Cài đặt thư viện
flutter pub get

# 2. Chạy kiểm thử tự động
flutter test

# 3. Đóng gói file cài đặt Android (.apk) để nhiều người cài đặt và chơi online cùng nhau
flutter build apk --release
```
File cài đặt `.apk` sau khi đóng gói sẽ nằm tại:
`build/app/outputs/flutter-apk/app-release.apk`
