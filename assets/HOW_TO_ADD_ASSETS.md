# 🎨 Hướng Dẫn Tùy Chỉnh & Thêm Mới Assets (Nhân Vật, Kỹ Năng, Trợ Thủ, Bản Đồ)

Dự án **Gold Rush** được thiết kế với hệ thống **Data-Driven Asset Registry** (`lib/registry/asset_registry.dart`). Toàn bộ dữ liệu cấu hình nằm tách biệt trong thư mục `assets/data/` và hình ảnh/âm thanh nằm trong `assets/images/`, `assets/audio/`.

Bạn có thể tự do thêm nhân vật, kỹ năng, trợ thủ hoặc bản đồ mới **chỉ bằng cách thêm file vào `assets/` và khai báo trong JSON** mà không cần sửa đổi logic engine.

---

## 📁 1. Cấu Trúc Thư Mục `assets/`

```text
assets/
├── data/
│   ├── heroes.json       # Danh sách & chỉ số Nhân vật (Level 1 -> 100)
│   ├── skills.json       # Danh sách Kỹ năng của từng Nhân vật
│   ├── companions.json   # Danh sách Trợ thủ AI bay
│   ├── maps.json         # Danh sách Bản đồ PvE (6+ Stages) & PvP Arena
│   └── enemies.json      # Danh sách Quái vật & Boss
├── images/
│   ├── heroes/           # Sprite sheet PNG của Nhân vật (Idle, Run, Attack, Skill)
│   ├── skills/           # Icon kỹ năng & hiệu ứng Projectile/AoE
│   ├── companions/       # Sprite sheet PNG của Trợ thủ AI
│   ├── enemies/          # Sprite sheet PNG của Zombie, Skeleton, Boss
│   ├── maps/             # Tileset PNG & file bản đồ (.json/.tmx)
│   ├── pickups/          # Bình máu, ngọc EXP, đồng xu vàng
│   └── ui/               # Khung viền, nút bấm, biểu tượng Rank
└── audio/                # Nhạc nền (.mp3) và hiệu ứng âm thanh (.wav)
```

---

## 🦸 2. Cách Thêm Nhân Vật Mới (Hero)

1. Copy các file sprite sheet PNG của nhân vật vào `assets/images/heroes/` hoặc thư mục con của nhân vật (ví dụ: `assets/images/heroes/my_hero/my_hero_idle.png`). Nếu dùng thư mục con, khai báo chính thư mục đó trong `flutter.assets` của `pubspec.yaml`: Flutter không tự đóng kèm ảnh nằm trong các thư mục con chỉ từ khai báo thư mục cha. Giữ đường dẫn trong JSON và bộ cache đồng bộ với vị trí thực tế. Các thư mục hiện có gồm `ember/`, `garrick/`, `kaelen/`, `nova_blade/`, `shadow/` và `valenria/`.
2. Mở file `assets/data/heroes.json` và thêm một object mới vào mảng `"heroes"`:

```json
{
  "id": "dragon_knight",
  "name": "Long Kỵ Sĩ",
  "role": "Đấu Sĩ / Hỏa Long",
  "classType": "warrior",
  "priceGold": 6500,
  "unlockedByDefault": false,
  "baseStats": {
    "hp": 125,
    "ki": 110,
    "attack": 29,
    "speed": 160
  },
  "growthPerLevel": {
    "hpPerLevel": 16.0,
    "kiPerLevel": 4.0,
    "attackPerLevel": 2.6
  },
  "skillIds": ["dk_skill_1", "dk_skill_2", "dk_skill_3"],
  "sprites": {
    "frameWidth": 48,
    "frameHeight": 48,
    "idleSheet": "assets/images/heroes/dragon_knight_idle.png",
    "runSheet": "assets/images/heroes/dragon_knight_run.png",
    "attackSheet": "assets/images/heroes/dragon_knight_attack.png",
    "useProceduralFallback": true
  }
}
```
> **Lưu ý**: Nếu bạn chưa kịp chuẩn bị file `.png` mà để `"useProceduralFallback": true`, hệ thống sẽ tự động render nhân vật bằng bộ vẽ Pixel-Art Canvas 60 FPS mà không bao giờ báo lỗi thiếu file!

---

## ⚡ 3. Cách Thêm / Chỉnh Sửa Kỹ Năng (Skills)

1. Bỏ icon kỹ năng vào `assets/images/skills/` và file âm thanh vào `assets/audio/`.
2. Mở `assets/data/skills.json` và thêm cấu hình kỹ năng với `"heroId"` trùng với `"id"` của nhân vật và `"slot"` là `1`, `2`, hoặc `3`.

---

## 🛸 4. Cách Thêm Trợ Thủ Bay (Companions)

1. Bỏ sprite sheet của trợ thủ vào `assets/images/companions/`.
2. Mở `assets/data/companions.json` và thêm cấu hình trợ thủ (`id`, `name`, `priceGold`, `autoAttackInterval`, `damageRatio`, `activeSkillName`, ...).
3. Trợ thủ mới sẽ tự động xuất hiện trong **Cửa Hàng (Tab Trợ Thủ AI)** và sẵn sàng trang bị vào trận!

---

## 🗺️ 5. Cách Thêm Bản Đồ Mới (Maps)

1. Bỏ tileset PNG hoặc file bản đồ vào `assets/images/maps/`.
2. Mở `assets/data/maps.json` và khai báo kích thước (`cols`, `rows`, `tileSize`), tọa độ xuất phát (`playerSpawn`, `bossSpawn`, `monsterPortals`, `buffNodes`).
