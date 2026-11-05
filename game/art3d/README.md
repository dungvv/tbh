# Art 3D

Nhân vật và quái 3D chibi fantasy. Game dùng các file `.glb` đã được làm gọn trong thư mục này; file gốc không nằm trong repo.

| Model | Nguồn | Giấy phép |
| --- | --- | --- |
| `knight`, `ranger`, `sorcerer`, `cleric` (Pháp Sư đổi màu áo), `berserker`, `assassin` | [KayKit Character Pack: Adventurers 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) của Kay Lousberg | CC0 |
| `skeleton`, `skeleton_mage` (gắn kiếm, gậy từ cùng gói) | [KayKit Character Pack: Skeletons 1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) | CC0 |
| `slime`, `mushnub`, `frog`, `goleling`, `mushroom_king`, `orc`, `cactoro`, `tribal`, `cactus_king`, `blue_demon`, `ghost`, `yeti`, `dragon` | [Ultimate Monsters](https://quaternius.com/packs/ultimatemonsters.html) của Quaternius, tải từng model trên [Poly Pizza](https://poly.pizza/u/Quaternius) | CC0 |
| `portraits/*.png` | Render từ các model trên bằng `tools/build_models.py` | CC0 |

## Làm lại model

1. Tải nguồn vào một thư mục, ví dụ `src3d/`:
   - `src3d/kaykit_adv/`: các file `Characters/gltf/*.glb` của gói Adventurers.
   - `src3d/kaykit_skel/`: `Characters/gltf/Skeleton_Minion.glb`, `Skeleton_Mage.glb`, cùng `Assets/gltf/Skeleton_Blade.*`, `Skeleton_Staff.*` và `skeleton_texture.png`.
   - `src3d/polypizza/`: các file Quaternius, đặt tên như cột `src` trong `tools/models3d.json`. Thư mục Google Drive gốc của Quaternius hay bị chặn tải ẩn danh, nên tải từ Poly Pizza.
2. Build bằng Blender (đã thử với 5.2):

   ```bash
   blender -b -P tools/build_models.py -- <src3d> art3d [tên model ...]
   ```

   Script giữ đúng các animation khai báo trong `tools/models3d.json`, đổi tên chúng thành `idle`, `run`, `attack`, `skill`, `hit`, `death`, `cheer`, giảm lưới skinned còn khoảng 1.600 tam giác, gộp các mảnh thân thành một lưới `Body`, gắn vũ khí vào xương, đổi màu (Tu Sĩ) và render chân dung hero.
3. Mở Godot một lần (hoặc chạy `godot --headless --path . --import`) để import, rồi đo lại chiều cao thật:

   ```bash
   godot --path . --script res://tools/measure_models.gd
   ```

   Script ghi `height` và `foot` vào `manifest.json`. Một số model Quaternius có gốc tọa độ ở giữa thân, nên game dùng `foot` để đặt chân lên mặt đất.

## Quy ước

- Thêm model: thêm một dòng vào `tools/models3d.json`, build, đo, rồi khai báo trong `data.gd` (`MOBS`, `ACT_BOSSES` hoặc `HERO_MODELS`).
- Hero: các mảnh vũ khí và khiên giữ nguyên tên gốc của KayKit; `HERO_MODELS` trong `data.gd` chọn mảnh nào hiện theo đồ đang mặc.
- Ghi nguồn và giấy phép của mọi model mới vào bảng trên.
