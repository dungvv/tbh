# Guidelines

Quy ước khi sửa code trong `game/`. Mục tiêu: luật chơi dễ cân bằng, dễ test, và game nhẹ đủ để chạy cả ngày cạnh ứng dụng làm việc.

## 1. Kiến trúc: luật chơi tách khỏi phần vẽ

- `data.gd` chứa mọi số thiết kế; `sim.gd` chứa **toàn bộ** luật chơi. Nó không vẽ, không phát tiếng, không đọc input, không gọi `DisplayServer`.
- `main.gd` và `panels.gd` chỉ đọc trạng thái từ `sim`, vẽ, nhận click rồi gọi hàm của `sim`. `sim` báo chuyện xảy ra qua mảng `events`; giao diện đọc nó để phát hiệu ứng và âm thanh.
- Đừng gọi âm thanh hay hiệu ứng từ trong `sim.gd`; hãy thêm một event.
- Thưởng offline dùng chung công thức với lúc chơi (`team_dps()`), nên mọi thay đổi về sát thương phải đi qua `team_dps()`. Test có kiểm tra `team_dps()` khớp với sát thương đo thực tế trong 40 giây.

Nhờ tách như vậy, bot cân bằng và test chạy được ở chế độ `--headless`, nhanh hơn chơi thật hàng nghìn lần.

## 2. Số cân bằng

- Mọi hằng số cân bằng đặt trong **`data.gd`**, có comment nói đơn vị. Không rải số ma thuật trong logic.
- Rune nằm trong bảng `RUNES`, class trong `CLASSES`. Thêm rune hay class là thêm một dòng dữ liệu, không thêm nhánh `if` mới khi tránh được.
- Sau khi đổi số, **chạy bot** và ghi lại kết quả trong commit message:

```bash
godot --headless --path game --script res://tools/balance.gd -- 504
```

- Mục tiêu nhịp chơi (Q1.4 B, 2–4 tuần): hết Thường sau 30–50 phút, hết Ác Mộng trong ngày đầu, hết Địa Ngục trong tuần đầu, hết Đày Đọa sau 2–3 tuần. Bot phải tiến đều, không đứng yên nhiều ngày ở một màn.
- Đường cong quái gãy ở `MOB_KNEE_LV` (cuối Ác Mộng, khi hero chạm trần level). Sau đó sức mạnh chỉ còn đến từ đồ, cường hóa và rune, nên máu, công và vàng của quái tăng chậm hơn hẳn (`*_GROWTH2`). Mọi chỗ cần chỉ số quái theo level gọi `mob_hp()`, `mob_atk()`, `mob_gold()`, `mob_exp()` trong `sim.gd`.
- Nếu cố ý chấp nhận một giới hạn (ví dụ công thức ước lượng gần đúng), ghi comment bắt đầu bằng `ponytail:`, nói rõ giới hạn và cách nâng cấp khi cần.

## 3. Test

- Test nằm trong `test_sim.gd` (một hàm `_init` dài, chạy từ trên xuống).
- **Chạy test bằng `tools/run_tests.sh .`.** Godot trả exit code 0 và chạy tiếp cả khi `assert` thất bại hay script lỗi parse, nên script này chỉ báo PASS khi có dòng `OK` và không có `SCRIPT ERROR`.
- Mỗi logic không tầm thường (nhánh, vòng lặp, xác suất, tiền, save) cần một assert. Logic xác suất: cố định `rng.seed`, chạy vài nghìn lần, so với tỉ lệ kỳ vọng kèm sai số.
- Mỗi nhóm test là một hàm `test_*` riêng, gọi trong `_init`.
- Đổi định dạng save thì thêm test cho **save cũ**: `from_dict()` phải đọc được save thiếu trường mới mà không lỗi.

## 4. Save

- `to_dict()` / `from_dict()` trong `sim.gd`; cài đặt giao diện (âm thanh, nhạc) do `main.gd` thêm vào cùng file.
- JSON biến số nguyên thành số thực: luôn ép kiểu `int(...)` khi đọc.
- Giá trị đọc từ save phải được kẹp vào khoảng hợp lệ (cấp rune, số màn…). Save có thể bị sửa tay.
- Không bao giờ xóa trường cũ mà không có bước chuyển đổi trong `from_dict()`.

## 5. Hình 3D và giao diện

- Nhân vật và quái là model 3D trong `art3d/`, build bằng `tools/build_models.py` (Blender) rồi đo bằng `tools/measure_models.gd`. Quy trình và nguồn ở `art3d/README.md`.
- `sim.gd` vẫn là 2D: `main.gd` quyết định vị trí trên dải, `view3d.gd` chỉ đặt model vào đó. Đừng đưa logic trận đánh vào `view3d.gd`.
- Model dùng shader cel lì (`TOON` trong `view3d.gd`), không dùng vật liệu PBR gốc vì trông bóng ở cỡ nhỏ.
- Hero quay mặt sang phải, quái sang trái, cả hai xoay `YAW` độ về phía camera.
- Đồ đang mặc hiện trên model qua `HERO_MODELS` trong `data.gd`; vũ khí +7 trở lên phát sáng.
- Giao diện vẽ bằng các hàm trong `ui.gd` (khung, nút, thanh, ngọc). Đừng tự `draw_rect` một bảng màu riêng trong panel.
- Icon nhỏ là lưới ký tự trong `art.gd`, mỗi ký tự một pixel, màu phải có trong `PALETTE`; mọi hàng dài bằng nhau (có test).
- Sau khi đổi hình, render kiểm tra bằng `tools/screenshot.gd` trước khi coi là xong.

## 6. Âm thanh và nhạc

- Hiệu ứng âm thanh là một dòng trong bảng `SOUNDS` (`sfx.gd`): danh sách nốt, âm lượng dB, khoảng cách tối thiểu giữa hai lần phát.
- Âm thanh chiến đấu phải nhỏ và có giới hạn tần suất; người chơi nghe nó hàng giờ.
- Nhạc mỗi act là một dòng trong `THEMES` (`music.gd`). Giữ nhạc ở mức nhỏ (`MUSIC_DB`).
- Mọi nốt có attack/release để không có tiếng tách; test kiểm tra không vỡ tiếng và không tách ở điểm lặp.

## 7. Hiệu năng

Game chạy cả ngày, nên:

- Giữ `Engine.max_fps = 30`.
- Không tạo node mới mỗi frame; vẽ bằng `_draw()`.
- HUD và panel vẽ vào texture cache (`redraw_ui()` trong `main.gd`), chỉ cập nhật 4 lần mỗi giây hoặc khi có chuột. `StyleBoxFlat`, chữ có viền và `draw_colored_polygon` đắt với renderer canvas; đừng đưa chúng vào lớp vẽ mỗi frame (`draw_field`).
- Animation và render 3D chạy `ANIM_FPS` (15) lần mỗi giây. Model giữ khoảng 1.600 tam giác skinned và một lưới thân; mỗi lưới skinned thêm vào đều tốn CPU mỗi lần cập nhật.
- Đo CPU bằng thời gian CPU tích lũy của tiến trình trong khoảng 12 giây, không dùng `%cpu` tức thời: con số đó nhiễu tới ±5%.
- Việc nặng (render nhạc, khoảng 0,3 giây) chỉ làm khi thật sự cần, ví dụ khi đổi act.

## 8. Cửa sổ và đa nền tảng

- Vị trí cửa sổ lấy từ `screen_get_usable_rect()`; không hard-code toạ độ taskbar.
- Scale giao diện qua `_ui_scale()`: macOS dùng `screen_get_scale()`, Windows dùng DPI/96 vì `screen_get_scale()` luôn trả 1 trên Windows.
- Khi thêm panel hay nút, kiểm tra vùng bắt chuột (`window_set_mouse_passthrough`) vẫn bao đúng phần cần bấm.

## 9. Nội dung và bản quyền

- Không dùng tên, hình, âm thanh hay chữ của *TBH: Task Bar Hero* hay của thương hiệu khác. Cơ chế được phép giống, thể hiện thì phải là của dự án.
- Sinh vật lấy từ thần thoại dân gian thì được; tên hay thiết kế riêng của một tác phẩm (ví dụ Dementor, Acromantula) thì không.
- Không thêm thư viện hay asset ngoài khi chưa ghi rõ nguồn và giấy phép.

## 10. Commit

- Mỗi commit một việc, message nói việc gì và vì sao, viết tiếng Việt hoặc tiếng Anh đều được.
- Trước khi commit: chạy test (phải thấy `OK`); nếu đụng số cân bằng thì chạy bot; nếu đụng giao diện thì render ảnh kiểm tra.
- Không commit `game/.godot/` và `game/build/` (đã có trong `.gitignore`).
