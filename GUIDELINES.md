# Guidelines

Quy ước khi sửa code trong `game/`. Mục tiêu: luật chơi dễ cân bằng, dễ test, và game nhẹ đủ để chạy cả ngày cạnh ứng dụng làm việc.

## 1. Kiến trúc: luật chơi tách khỏi phần vẽ

- `sim.gd` chứa **toàn bộ** luật chơi và số liệu. Nó không vẽ, không phát tiếng, không đọc input, không gọi `DisplayServer`.
- `main.gd` chỉ đọc trạng thái từ `sim`, vẽ, nhận click rồi gọi hàm của `sim`.
- Âm thanh phát ra bằng cách so sánh trạng thái `sim` trước và sau mỗi `step()` (`_snapshot()` / `_play_events()` trong `main.gd`). Đừng gọi âm thanh từ trong `sim.gd`.
- Thưởng offline dùng chung công thức với lúc chơi (`team_dps()`), nên mọi thay đổi về sát thương phải đi qua `team_dps()`. Test có kiểm tra `team_dps()` khớp với sát thương đo thực tế trong 40 giây.

Nhờ tách như vậy, bot cân bằng và test chạy được ở chế độ `--headless`, nhanh hơn chơi thật hàng nghìn lần.

## 2. Số cân bằng

- Mọi hằng số cân bằng đặt ở **đầu `sim.gd`**, có comment nói đơn vị. Không rải số ma thuật trong logic.
- Rune nằm trong bảng `RUNES`, class trong `CLASSES`. Thêm rune hay class là thêm một dòng dữ liệu, không thêm nhánh `if` mới khi tránh được.
- Sau khi đổi số, **chạy bot** và ghi lại kết quả trong commit message:

```bash
godot --headless --path game --script res://tools/balance.gd -- 48
```

- Mục tiêu nhịp chơi hiện tại: act 1 khoảng 30–50 phút, act 2 vài giờ, act 3 kéo dài nhiều ngày nhưng không đứng yên hoàn toàn.
- Nếu cố ý chấp nhận một giới hạn (ví dụ công thức ước lượng gần đúng), ghi comment bắt đầu bằng `ponytail:`, nói rõ giới hạn và cách nâng cấp khi cần.

## 3. Test

- Test nằm trong `test_sim.gd` (một hàm `_init` dài, chạy từ trên xuống).
- **Test chỉ qua khi in ra dòng bắt đầu bằng `OK`.** Godot trả exit code 0 cả khi script lỗi parse, nên đừng tin exit code.
- Mỗi logic không tầm thường (nhánh, vòng lặp, xác suất, tiền, save) cần một assert. Logic xác suất: cố định `rng.seed`, chạy vài nghìn lần, so với tỉ lệ kỳ vọng kèm sai số.
- Vì cả file là một hàm, tên biến cục bộ không được trùng nhau. Khi thêm khối test mới, dùng tiền tố riêng (`mu_`, `pt`, …).
- Đổi định dạng save thì thêm test cho **save cũ**: `from_dict()` phải đọc được save thiếu trường mới mà không lỗi.

## 4. Save

- `to_dict()` / `from_dict()` trong `sim.gd`; cài đặt giao diện (âm thanh, nhạc) do `main.gd` thêm vào cùng file.
- JSON biến số nguyên thành số thực: luôn ép kiểu `int(...)` khi đọc.
- Giá trị đọc từ save phải được kẹp vào khoảng hợp lệ (cấp rune, số màn…). Save có thể bị sửa tay.
- Không bao giờ xóa trường cũ mà không có bước chuyển đổi trong `from_dict()`.

## 5. Sprite

- Sprite là lưới ký tự trong `art.gd`, mỗi ký tự là một pixel, `.` là trong suốt. Màu phải có trong `PALETTE`.
- Mọi hàng của một sprite phải dài bằng nhau. Test có kiểm tra điều này và báo đúng hàng sai.
- Nhân vật và quái quay mặt: hero nhìn sang phải, quái nhìn sang trái.
- Quái và hero dùng 2 frame (`_a`, `_b`); hero có thêm frame tấn công.
- Icon đồ vẽ bằng màu xám để game tô theo phẩm.
- Muốn thay bằng art thật: đặt PNG cùng tên vào `game/art/` (xem `game/art/README.md`) và ghi nguồn, giấy phép vào bảng trong file đó.
- Sau khi vẽ, render kiểm tra bằng `tools/screenshot.gd` ở đúng tỉ lệ trong game trước khi coi là xong.

## 6. Âm thanh và nhạc

- Hiệu ứng âm thanh là một dòng trong bảng `SOUNDS` (`sfx.gd`): danh sách nốt, âm lượng dB, khoảng cách tối thiểu giữa hai lần phát.
- Âm thanh chiến đấu phải nhỏ và có giới hạn tần suất; người chơi nghe nó hàng giờ.
- Nhạc mỗi act là một dòng trong `THEMES` (`music.gd`). Giữ nhạc ở mức nhỏ (`MUSIC_DB`).
- Mọi nốt có attack/release để không có tiếng tách; test kiểm tra không vỡ tiếng và không tách ở điểm lặp.

## 7. Hiệu năng

Game chạy cả ngày, nên:

- Giữ `Engine.max_fps = 30`.
- Không tạo node mới mỗi frame; vẽ bằng `_draw()`.
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
