# Art

| Thư mục / file | Nguồn | Giấy phép |
| --- | --- | --- |
| `0x72/` (icon vũ khí trong túi đồ) | [16x16 DungeonTileset II v1.7](https://0x72.itch.io/dungeontileset-ii) của 0x72 (Robert) | CC0 |
| `../fx/*.png`, `../fx/*.json` | Render từ [pixelfx](https://github.com/patch-gg/pixelfx) bằng `node tools/render.mjs <id> --sheet --no-actor --bg none` | MIT (`../fx/LICENSE-pixelfx.txt`) |
| Nhân vật và quái 3D trong `../art3d/` | KayKit, Quaternius, xem `../art3d/README.md` | CC0 |
| Icon ô đồ, khóa, đá trong `../art.gd` | Vẽ cho dự án bằng lưới ký tự, bảng màu Sweetie 16 của GrafxKid | CC0 / của dự án |

Chỉ chép những file game dùng. Nhân vật và quái giờ là model 3D, xem `../art3d/README.md`.

Thêm hiệu ứng pixelfx: render sheet như trên, chép `<id>.png` và `<id>.json` vào `../fx/`, rồi dùng id đó trong trường `fx` của skill. File JSON được đóng gói nhờ `include_filter="fx/*.json"` trong `export_presets.cfg`.

Ghi nguồn và giấy phép của mọi file mới vào bảng trên.
