# Thiết kế game idle chạy trên taskbar, lấy TBH làm mẫu

Ngày viết: 30/10/2026. Đầu vào là [tbh-chi-tiet.md](tbh-chi-tiet.md) cộng với một vòng tra thêm về kỹ thuật và thị trường. Tài liệu này không chép TBH. Nó tách ra phần nào làm nên game đó, phần nào nên bỏ, rồi chọn con số khởi điểm để cân bằng. Số lấy từ TBH ghi rõ là **TBH**. Số tôi tự đề xuất ghi là **đề xuất**.

---

## 1. Tóm tắt

- **Thể loại:** idle RPG ở dải đáy màn hình ("bottom-of-your-screen"). Game chạy ngay cạnh lúc người chơi làm việc. Người chơi giữ cửa sổ mở, thỉnh thoảng mới ngó qua.
- **Thị trường có thật.** Rusty's Retirement (một người làm, 2024) bán hơn 880 nghìn bản, doanh thu hơn 4,5 triệu USD. Bongo Cat chơi miễn phí, doanh thu hơn 670 nghìn USD. TBH đạt đỉnh 546 nghìn người chơi cùng lúc ngày 18/06/2026. Steam có cả một bundle "Bottom-Of-Your-Screen" và lễ hội Idler Fest riêng.
- **TBH làm bằng Unity (IL2CPP), chỉ chạy Windows.** Họ dùng Anti-Cheat Toolkit (ACTk) và server BACKND.
- **Bài học lớn nhất:** đưa đồ lên Steam Market biến đồ trong game thành tiền thật. Hậu quả là bot, hai đợt khóa 6.180 và 20.406 tài khoản, game bị ép phải luôn online, cùng một đống luật chợ vá liên tục (4 ô, 8 giờ mỗi ô, khóa phẩm cao). **Bản đầu đừng làm chợ.**
- **Đề xuất MVP:** chơi offline, lưu file ở máy, 1 act, 2 class, cơ chế ghép 9→1, 2 loại rương theo giờ thực, thưởng offline. Godot 4 làm được cửa sổ trong suốt, luôn nằm trên cùng và cho click xuyên mà không cần plugin.

---

## 2. Mổ xẻ TBH: vì sao người chơi giữ cửa sổ mở

### 2.1. Ba vòng lặp

| Vòng | Thời gian | Người chơi làm gì | Hệ của TBH |
| --- | --- | --- | --- |
| Ngắn | 3–5 phút | Liếc qua, mở rương, mặc đồ mới | Rương thường 3 phút, rương boss màn 5 phút (vùng có Region Level từ 15 trở lên) |
| Trung | 1 buổi / 1 ngày | Ghép đồ, khảm, cộng rune, qua màn hoặc lên độ khó | Cube (Synthesis, Alchemy, Crafting), rune tree, boss act |
| Dài | Tuần / tháng | Lên độ khó kế, mở Plaguelands, săn đồ Cosmic, bán đồ trên chợ | 4 độ khó, Plaguelands, Relic, Steam Market |

**Mấu chốt thiết kế:** *tắt game thì không rơi rương* (offline chỉ cho vàng và EXP, tối đa 8 giờ). Phần thưởng gắn với việc **giữ cửa sổ sống**, không gắn với việc bấm nhiều. Đó chính là "lý do để mở game trên desktop" mà AppMagic nhắc tới.

### 2.2. Thứ tự mở hệ (onboarding của TBH)

```
Màn 1-1 ──> level 3: Rune Tree ──> level 4: Cube (Alchemy)
   │                                  │
   │                                  ├─ Cube 5 Crafting ─ 8 Decoration ─ 10 Extraction + chợ + ghép Immortal
   │                                  ├─ Cube 15 Engraving ─ 20 Offering ─ 25 Inscription ─ 30 Corrosion
   │                                  └─ Cube 50 ghép Celestial
   ├─ Rune Command 1.000 vàng ──> đội 2 hero; 150.000 vàng ──> đội 3 hero
   ├─ Hạ boss 3-10 ──> Nightmare ──> Hell ──> Torment
   ├─ Clear 1-10 từ Nightmare trở lên ──> Plaguelands ──> clear 1 lần ──> Relic
   └─ Clear 3-10 từ Nightmare trở lên ──> canyon sự kiện
```

Có hai thanh tiến độ tách rời: **level hero** (sức chiến đấu) và **level Cube** (mở hệ chế tạo, lên level bằng cách tiêu hao đồ). Nhờ vậy đồ rác vẫn có giá trị: đem Alchemy ra vàng, Cube lại được EXP.

### 2.3. Tái dùng nội dung

30 màn được dùng 4 lần: cùng bản đồ nhưng level màn khác (Pasture 1 / 33 / 53 / 78), nhiều sóng hơn và bị trừ kháng −20 / −40 / −60. Kết quả là **120 màn từ 30 bản đồ**. Plaguelands lại tái dùng thêm lần nữa, kèm Intensity 1–20. Đây là cách rẻ nhất để kéo dài thời gian chơi.

### 2.4. Kinh tế: phẩm đồ tăng theo cấp số nhân

- 10 phẩm: Common → Uncommon → Rare → Legendary → Immortal → Arcana → Beyond → Celestial → Divine → Cosmic.
- Giá Alchemy mỗi phẩm gấp **×3** phẩm trước, rồi tới ×3,2 và ×3,5 ở các phẩm cao: 10, 30, 90, 270, 810, 2.592, 8.294, 29.029, 101.602, 355.607.
- Ghép 9 món ra 1. Từ Immortal trở lên có thể fail. TBH tăng tỉ lệ Immortal→Arcana từ 49,9% lên 80% ở bản 1.3.0, vì người chơi kẹt quá lâu.
- Cần chừng 9^k món phẩm thấp mới ra 1 món cao hơn k bậc. Cosmic hiếm đến mức thành "mục tiêu cả đời".

### 2.5. Cái giá của Steam Market (thứ không nên chép)

| Hệ quả | Bằng chứng trong báo cáo |
| --- | --- |
| Bot và trainer | Repo GitHub công khai có auto-fuse, auto-box, bypass ACTk |
| Khóa tài khoản hàng loạt | 6.180, rồi thêm 20.406 tài khoản; truyền thông đưa tin "random bans" |
| Phải luôn online | Kho đồ và việc sinh item đều trên server. Có thread "always-online" phàn nàn |
| Vá luật liên tục | 4 ô, cooldown 8 giờ, không hủy được listing, chờ 1 giờ với đồ mới, khóa phẩm cao, Type B bị xóa |
| Pháp lý và dữ liệu | Privacy v1.6, log chống gian lận giữ 1 năm, GDPR |
| Chi phí vận hành | Server BACKND, sự cố server, bảo trì |

Chợ có thể làm TBH lan nhanh (đồ ra tiền thật). Nhưng nó biến một game idle chơi một mình thành một dịch vụ online có kinh tế thật. Với team nhỏ, đó là cái bẫy.

---

## 3. Game của bạn: giữ gì, bỏ gì

| Hệ TBH | MVP | Bản 1.0 | Lý do |
| --- | --- | --- | --- |
| Cửa sổ taskbar, tự đánh | ✅ | ✅ | Đây chính là sản phẩm |
| 3 act × 10 màn × 4 độ khó | 1 act × 10 màn × 2 độ khó | 3 × 10 × 3–4 | Tái dùng map như TBH |
| 6 class, đội 3 hero | 2 class, đội 1→2 | 4 class, đội 3 | Mỗi class cần sprite và 6 skill |
| Rương theo giờ thực, không rơi khi offline | ✅ | ✅ | Lõi của vòng lặp ngắn |
| Thưởng offline (vàng và EXP, trần 8 giờ) | ✅ | ✅ | Để người chơi quay lại |
| Ghép 9→1 + Alchemy | ✅ | ✅ | Lõi kinh tế; dễ code |
| Level Cube mở dần các thao tác | 3 thao tác | 6–8 thao tác | Onboarding kéo dài |
| Rune tree | 15–20 node | 60+ node | Chỗ tiêu vàng |
| Khảm 3 lớp (Decoration / Engraving / Inscription) | 1 lớp | 2–3 lớp | Mỗi lớp cần một pool stat |
| Plaguelands, Relic, Intensity | ❌ | Bản cập nhật sau | Nội dung endgame |
| Steam Market / Trade Ship | ❌ | ❌ (cân nhắc sau) | Xem mục 2.5 |
| Server, chống gian lận | ❌ | ❌ | Game một người: file save trên máy là đủ |
| Pet bonus | 1–2 pet thành tựu | DLC cosmetic | Kiếm tiền nhẹ nhàng |
| Chat, guild, PvP | ❌ | ❌ | TBH cũng chưa có, và không cần |

**Hướng kiếm tiền đề xuất:** bán game giá rẻ (3–5 USD, như Rusty's Retirement) hoặc chơi miễn phí kèm DLC skin, pet, ô kho. TBH dùng mô hình thứ hai: DLC class 4,99 USD, Supporter Pack, Stash Pack. Tránh mọi thứ biến đồ trong game thành tiền thật.

---

## 4. Kỹ thuật

### 4.1. Chọn engine

| | Godot 4 | Unity 6 |
| --- | --- | --- |
| Cửa sổ trong suốt | **Có sẵn:** `display/window/per_pixel_transparency/allowed` + `window/size/transparent` | Phải tự gọi Win32/DWM qua P/Invoke. Unity 6.1 đổi cách làm trong suốt nên nhiều tutorial cũ không còn chạy |
| Luôn trên cùng, không viền | Có sẵn: `always_on_top`, `borderless` | Gọi `SetWindowPos` |
| Click xuyên vùng trống | `DisplayServer.window_set_mouse_passthrough(polygon)` | Tự viết `WS_EX_TRANSPARENT` |
| Đa nền tảng | Windows, macOS, Linux | Code Win32 chỉ chạy trên Windows |
| Pixel art 2D | Tốt, nhẹ | Tốt |
| TBH dùng | — | ✅ |

**Đề xuất: Godot 4** cho team nhỏ, vì cửa sổ taskbar là tính năng có sẵn của engine, không phải code tự viết. Chọn Unity nếu team đã quen Unity. Khi đó dùng script mã nguồn mở [Haoming02/unity-transparent-window](https://github.com/Haoming02/unity-transparent-window/) hoặc theo cách của Code Monkey.

### 4.2. Đặt cửa sổ lên trên taskbar

1. Lấy vùng làm việc của màn hình. Trong Godot là `DisplayServer.screen_get_usable_rect()`; vùng này không tính taskbar.
2. Đặt cửa sổ thành một dải cao khoảng 120–200 px, nằm sát mép dưới của vùng đó, hoặc đè lên taskbar nếu người chơi chọn.
3. Vùng trong suốt cho click xuyên. Chỉ hero, rương và nút bấm mới bắt chuột.
4. Có phím tắt để đặt lại vị trí và tỉ lệ UI (TBH: Shift+F12 / Shift+F11, theo nguồn cộng đồng).
5. Có thanh trượt độ trong suốt, chế độ tự canh khi cửa sổ sát mép trái/phải, và nhớ màn hình đang dùng. TBH phải vá những thứ này ở bản 1.02 và 1.3.1, nên làm ngay từ đầu.

### 4.3. Lưu game và thời gian

- File save JSON trên máy, có thêm Steam Cloud. Ghi mỗi 30–60 giây và khi thoát.
- **Thưởng offline:** `t = min(now - last_save, 8h)`. Nếu `t > 30 ngày` thì cho 0; đây là chặn chỉnh đồng hồ giống TBH. Thưởng = `t × tốc_độ_màn_hiện_tại × hệ_số_rune × phạt_lệch_level`.
- Đồng hồ lùi (`now < last_save`): không thưởng, và lấy `last_save` làm mốc.
- Game một người thì không cần chống gian lận. Người chơi sửa file save chỉ làm hỏng trải nghiệm của chính họ.

### 4.4. Hiệu năng (game chạy cả ngày)

- Giới hạn 30 FPS khi bình thường, 10 FPS hoặc thấp hơn khi bị che hoặc thu nhỏ. Nếu chưa tối ưu được thì cắt ngay từ đầu.
- Mô phỏng combat theo tick cố định, tách khỏi phần vẽ. Nhờ vậy cùng một code dùng được cho thưởng offline.
- Mục tiêu: dưới 2% CPU và dưới 200 MB RAM. Người chơi bật game này lúc đang làm việc.

---

## 5. Số khởi điểm để cân bằng

### 5.1. Màn và độ khó

| Thông số | TBH | Đề xuất MVP |
| --- | --- | --- |
| Màn mỗi act | 10, màn X-10 là boss act | 10 |
| Sóng màn đầu (Normal) | 10 sóng × 1 quái | 8 sóng × 1 |
| Sóng màn 9 (Normal) | 18 sóng × 11 quái | 14 × 6 |
| Boss màn so với quái thường | HP ×3–6, sát thương ×2–3 | HP ×4, sát thương ×2,5 |
| Level màn theo độ khó | Normal 1–32, Nightmare 33–52, Hell 53–77, Torment 78–95 | Normal 1–20, Hard 25–45 |
| Phạt kháng | −20 / −40 / −60 | −25 cho Hard |

### 5.2. Giáp (công thức TBH lấy từ code, nên dùng)

```
Giảm = Armor² / (Armor² + (14 × StageLevel + 12) × (Armor + 0.4 × Damage)),  trần 75%
```

Công thức tự làm giáp yếu đi khi lên độ khó cao, và đòn lớn xuyên giáp tốt hơn. Không cần bảng tra.

### 5.3. Rương

| | TBH | Đề xuất |
| --- | --- | --- |
| Rương thường | 3 phút (Region ≥15), 7 phút trước đó | 4 phút |
| Rương boss màn | 5 phút | 8 phút |
| Rương boss act | Rơi khi clear, tốn 1 soulstone | Rơi khi clear, không cần vé ở MVP |
| Offline | Không rơi rương | Giống TBH |
| Sức chứa kho rương | Có giới hạn, rune nâng thêm | 20 rương, rune nâng thêm |

### 5.4. Ghép 9→1 (TBH sau 1.3.0)

| Ghép 9× | Lên +1 | Great (+2) | Fail (ra 1 món cùng phẩm) |
| --- | --- | --- | --- |
| Common | 95% | 4,8% | — |
| Rare | 98% | 2,4% | — |
| Legendary | 99% | 0,99% | — |
| Immortal | 80% | 0,25% | ~20% |
| Arcana | 50% | 0,17% | 50% |
| Beyond | 23% | 0,077% | 77% |
| Celestial | 17% | 0,017% | 83% |
| Divine | 9,1% | — | 91% |

**Đề xuất cho MVP:** chỉ dùng 6 phẩm (Common → Mythic) và chỉ cho fail ở 2 bậc cuối. Mười phẩm là quá dài khi game mới có 1 act.

### 5.5. Alchemy

`vàng(phẩm) = 10 × 3^bậc`, bậc 0 là Common. EXP Cube = vàng / 5, đúng như TBH. Để tránh "ghép rồi bán lời", ghép 9→1 phải cho **ít** giá trị Alchemy hơn bán thẳng 9 món. TBH làm được điều này vì 9 × 10 = 90 lớn hơn 30.

### 5.6. Level và EXP

- TBH: level 100 cần khoảng 2 tỉ XP tích lũy; EXP màn tăng cực mạnh theo độ khó (Pasture: Hell gấp khoảng 5 lần Nightmare).
- **Phạt lệch level (bảng TBH cho hero level 30):** lệch 0–2 giữ 100%, −4 giữ 94%, −6 giữ 78%, −8 giữ 50%, −10 giữ 23%, −15 giữ 3%. Cơ chế này ép người chơi lên màn mới thay vì cày mãi màn dễ. Nên chép.
- **Đề xuất:** EXP cần lên level `L` là `100 × 1.12^L`, trần 50 ở MVP. Có ô nhớ "level mở tiếp" cho bản cập nhật, vì TBH đã hứa tăng trần.

### 5.7. Slot đội và skill

- Đội: 1 hero lúc đầu. Rune mở hero thứ 2 (khoảng 1.000 vàng, chừng 30–60 phút chơi) và thứ 3 (150.000 vàng).
- Skill: 1 điểm mỗi level. Tier mở theo số điểm đã chi (0 / 10 / 20 / 30 / 40 / 50), không theo level.
- Mỗi class: 1 đòn thường + 6 active. Có hai kiểu kích hoạt: "mỗi N đòn" và "theo cooldown". Cách này dễ cân bằng và người chơi nhìn là hiểu.

---

## 6. Lộ trình

| Giai đoạn | Thời gian (1–2 người) | Xong khi |
| --- | --- | --- |
| 0. Prototype cửa sổ | 1 tuần | Một dải trong suốt nằm trên taskbar, hero chạy, click xuyên chạy được, CPU dưới 2% |
| 1. Vòng lặp combat | 2–3 tuần | 1 hero tự đánh 10 màn, có sóng và boss, có rơi đồ |
| 2. Kinh tế | 2–3 tuần | Rương theo giờ, túi đồ, Alchemy, ghép 9→1, rune tree nhỏ |
| 3. Offline và save | 1 tuần | Save JSON, thưởng offline có trần 8 giờ, Steam Cloud |
| 4. Nội dung MVP | 3–4 tuần | 2 class, 1 act, 2 độ khó, 20 thành tựu |
| 5. Steam Next Fest / demo | — | Trang Steam, demo, tham gia Idler Fest |
| 6. Sau ra mắt | — | Act 2–3, độ khó 3–4, khảm, endgame kiểu Plaguelands |

Tổng chừng 3 tháng tới bản demo, với điều kiện đã có sẵn pixel art hoặc mua asset.

---

## 7. Rủi ro

- **Bản quyền:** không dùng tên, sprite, tên phẩm đặc trưng ("Arcana / Beyond"), tên boss hay UI của TBH. Cơ chế (ghép 9→1, rương theo giờ) không có bản quyền, nhưng hình ảnh và chữ thì có.
- **Thị trường đông:** bundle Bottom-Of-Your-Screen đã có 17 game. Cần một điểm khác: theme, class, hoặc một cơ chế riêng.
- **Hiệu năng:** người chơi sẽ gỡ game nếu quạt máy kêu hay game làm chậm máy lúc họ làm việc.
- **Đa màn hình và taskbar dạt cạnh:** taskbar có thể nằm trái, phải hoặc trên, có thể tự ẩn, có thể là thanh Dock trên macOS. Phải test sớm.
- **Nếu sau này muốn có chợ:** cần server, chống gian lận, phải đăng ký Steam Inventory Service với Valve, và đối mặt với bot. Hãy coi đó là một dự án riêng.

---

## 8. Cần bạn chốt

1. Engine: Godot 4 (đề xuất) hay Unity?
2. Kiếm tiền: bán game hay chơi miễn phí kèm DLC?
3. Theme: fantasy như TBH, hay khác hẳn (sci-fi, nông trại, Việt Nam…)?
4. Nền tảng: chỉ Windows hay có cả macOS?

---

## Nguồn thêm (ngoài tbh-chi-tiet.md)

- [SteamDB — TBH](https://steamdb.info/app/3678970/charts/): Unity, IL2CPP, đỉnh 546.130 người chơi
- [PCGamingWiki — TBH](https://www.pcgamingwiki.com/wiki/TBH:_Task_Bar_Hero)
- [GitHub taskbarhero-bot](https://github.com/matheusbranhann/taskbarhero-bot): trainer có bypass ACTk, chứng tỏ có bot
- [AppMagic — Idle Games in 2026](https://appmagic.rocks/research/idle-steam-games-2026): doanh thu Rusty's Retirement, Bongo Cat
- [Wikipedia — Rusty's Retirement](https://en.wikipedia.org/wiki/Rusty's_Retirement)
- [GamesRadar — Steam Idler Fest](https://www.gamesradar.com/games/simulation/from-farming-sims-to-cat-collecting-games-steams-idler-fest-promises-to-fill-your-desktop-with-stuff-that-totally-wont-hurt-your-productivity/)
- [Haoming02/unity-transparent-window](https://github.com/Haoming02/unity-transparent-window/), [Code Monkey — transparent Unity app](https://unitycodemonkey.com/tutorial_text_contents_tinymce.php?v=RqgsGaMPZTw), [Sunny Valley — Unity 6.1 desktop overlay](https://www.patreon.com/sunnyvalleystudio/posts/desktop-overlay-143876901)
