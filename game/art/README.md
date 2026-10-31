# Art

| Thư mục / file | Nguồn | Giấy phép |
| --- | --- | --- |
| `0x72/` (nhân vật, quái, vũ khí, rương, xu) | [16x16 DungeonTileset II v1.7](https://0x72.itch.io/dungeontileset-ii) của 0x72 (Robert) | CC0 |
| `../fx/*.png`, `../fx/*.json` | Render từ [pixelfx](https://github.com/patch-gg/pixelfx) bằng `node tools/render.mjs <id> --sheet --no-actor --bg none` | MIT (`../fx/LICENSE-pixelfx.txt`) |
| Icon ô đồ, khóa, đá trong `../art.gd` | Vẽ cho dự án bằng lưới ký tự, bảng màu Sweetie 16 của GrafxKid | CC0 / của dự án |

Chỉ chép những frame game dùng. Thêm sprite 0x72: chép `<tên>_idle_anim_f0..3.png` và `<tên>_run_anim_f0..3.png` vào `0x72/`, rồi khai báo trong `data.gd`.

Thêm hiệu ứng pixelfx: render sheet như trên, chép `<id>.png` và `<id>.json` vào `../fx/`, rồi dùng id đó trong trường `fx` của skill. File JSON được đóng gói nhờ `include_filter="fx/*.json"` trong `export_presets.cfg`.

Ghi nguồn và giấy phép của mọi file mới vào bảng trên.
