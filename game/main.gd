extends Node2D
## Transparent strip at the bottom of the screen. Only the HUD box (and the open panel) catches the mouse.

const Sim := preload("res://sim.gd")
const Art := preload("res://art.gd")
const Sfx := preload("res://sfx.gd")
const Music := preload("res://music.gd")
const MUSIC_DB := -20.0  # quiet: this plays next to work apps all day
const PX := 3  # screen pixels per art pixel
const SAVE_PATH := "user://save.json"
const STRIP_H := 120
const HUD_W := 250
const PANEL_W := 560
const PANEL_HEIGHTS := {"bag": 196, "rune": 308, "forge": 226, "portal": 176}
const RUNE_NODE := 22
const ARROW_SEC := 0.15
const FIRE_SEC := 0.3
const HERO_SPRITES := ["hero", "ranger", "sorcerer"]  # sprite name prefix per party slot
## Per act: mob types (2 frames each) cycling by wave, the first one doubles as the stage boss, the act boss, and the ground color.
const ACT_ART := [
	{"mobs": [["slime_a", "slime_b"], ["bat_a", "bat_b"]], "boss": "boss", "ground": Color(0.22, 0.72, 0.39, 0.8)},
	{"mobs": [["scorpion_a", "scorpion_b"], ["mummy_a", "mummy_b"]], "boss": "worm", "ground": Color(1.0, 0.8, 0.46, 0.8)},
	{"mobs": [["spider_a", "spider_b"], ["troll", "troll"], ["pixie_a", "pixie_b"], ["wraith_a", "wraith_b"]],
		"boss": "basilisk", "ground": Color(0.15, 0.4, 0.3, 0.8)},
]
const GRID_X := 80
const GRID_Y := 30
const CELL := Vector2(76, 30)
const SAVE_EVERY_SEC := 30.0
const SLOT_NAMES := {"weapon": "Kiếm", "gloves": "Găng", "ring": "Nhẫn"}
const TIER_COLORS := [
	Color(0.85, 0.85, 0.85), Color(0.3, 0.75, 0.3), Color(0.3, 0.55, 1.0),
	Color(0.7, 0.35, 0.95), Color(1.0, 0.6, 0.1), Color(0.95, 0.2, 0.25),
]

var sim := Sim.new()
var sfx := Sfx.new()
var music := AudioStreamPlayer.new()
var music_on := true
var _music_act := 0  # act whose loop is loaded, 0 = none
var panel := ""  # "", "bag" or "rune"
var sel_rune := "growth"
var sel_slot := ""
var sel_tier := -1
var _save_timer := 0.0
var _toast := ""
var _toast_left := 0.0
var _hit_flash := 0.0
var _swing := [0.0, 0.0, 0.0]  # per-hero attack pose timer
var _fire_t := -1.0  # seconds since the last fireball, -1 = none
var _arrow_t := -1.0  # seconds since the last Ranger shot, -1 = none
var sel_hero := 0  # whose gear the bag panel shows
var sel_enh_hero := 0
var sel_enh_slot := "weapon"
var _font := ThemeDB.fallback_font


func _ready() -> void:
	Engine.max_fps = 30  # runs all day next to work apps
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel art
	add_child(sfx)
	add_child(music)
	_place_window()
	_load()
	_update_music()


## screen_get_scale() is only implemented on macOS, Wayland and mobile; Windows always returns 1.0,
## so there the scale comes from DPI (96 = 100%).
func _ui_scale(screen: int) -> float:
	if OS.get_name() == "Windows":
		return maxf(1.0, DisplayServer.screen_get_dpi(screen) / 96.0)
	return DisplayServer.screen_get_scale(screen)


func _place_window() -> void:
	var win := get_window()
	var screen := win.current_screen
	var scale := _ui_scale(screen)
	var r := DisplayServer.screen_get_usable_rect(screen)
	var ph := _panel_h()
	var h := STRIP_H + ph
	win.content_scale_factor = scale
	win.size = Vector2i(r.size.x, int(h * scale))
	win.position = Vector2i(r.position.x, r.end.y - int(h * scale))
	var poly := PackedVector2Array([Vector2(0, ph), Vector2(HUD_W, ph), Vector2(HUD_W, h), Vector2(0, h)])
	if ph > 0:  # L-shape: panel on top, HUD below
		poly = PackedVector2Array([Vector2(0, 0), Vector2(PANEL_W, 0), Vector2(PANEL_W, ph),
			Vector2(HUD_W, ph), Vector2(HUD_W, h), Vector2(0, h)])
	for i in poly.size():
		poly[i] *= scale
	DisplayServer.window_set_mouse_passthrough(poly)
	print_verbose("window rect (logical): ", Rect2(Vector2(win.position) / scale, Vector2(win.size) / scale))


func _process(delta: float) -> void:
	var act_before := sim.act()
	var before := sim.heroes.map(func(h): return h.attacks)
	var casts_before: int = sim.heroes[2].casts
	var snap := _snapshot()
	sim.step(delta, Time.get_unix_time_from_system())
	_play_events(snap, before)
	_update_music()
	if sim.act() != act_before:
		_show_toast("Act %d: %s" % [sim.act(), Sim.ACT_NAMES[sim.act() - 1]])
	for i in sim.heroes.size():
		_swing[i] = maxf(_swing[i] - delta, 0.0)
		if sim.heroes[i].attacks > before[i]:
			_swing[i] = 0.12
			_hit_flash = 0.1
			if i == 1:
				_arrow_t = 0.0
	if sim.heroes[2].casts > casts_before:
		_fire_t = 0.0
		_swing[2] = 0.3
		_hit_flash = 0.1
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	if _arrow_t >= 0.0:
		_arrow_t += delta
	if _fire_t >= 0.0:
		_fire_t += delta
	_toast_left = maxf(_toast_left - delta, 0.0)
	_save_timer += delta
	if _save_timer >= SAVE_EVERY_SEC:
		_save_timer = 0.0
		_save()
	queue_redraw()


# --- buttons: one list drives both drawing and clicks ---

func _buttons() -> Array:
	var top := get_viewport_rect().size.y - STRIP_H
	var chest_col := Color(0.35, 0.25, 0.12) if sim.chests > 0 else Color(0.2, 0.2, 0.24)
	var tab_col := Color(0.35, 0.35, 0.5)
	var b := [
		{"r": Rect2(4, top + 4, 138, 22), "t": _stage_text(), "a": _toggle_panel.bind("portal"),
			"c": tab_col if panel == "portal" else Color(0.16, 0.16, 0.22)},
		{"r": Rect2(146, top + 6, 70, 22), "t": "Túi %d" % sim.bag_total(), "a": _toggle_panel.bind("bag"),
			"c": tab_col if panel == "bag" else Color(0.25, 0.25, 0.32)},
		{"r": Rect2(146, top + 31, 70, 22), "t": "Rune", "a": _toggle_panel.bind("rune"),
			"c": tab_col if panel == "rune" else Color(0.25, 0.25, 0.32)},
		{"r": Rect2(146, top + 56, 70, 22), "t": "Rèn", "a": _toggle_panel.bind("forge"),
			"c": tab_col if panel == "forge" else Color(0.25, 0.25, 0.32)},
		{"r": Rect2(146, top + 81, 70, 34), "t": "x%d" % sim.chests, "a": _open_chest, "c": chest_col, "icon": "chest",
			"icon_col": Color.WHITE if sim.chests > 0 else Color(0.5, 0.5, 0.5)},
		{"r": Rect2(HUD_W - 20, top + 24, 16, 16), "t": "", "a": _cycle_sound, "c": Color(0.2, 0.2, 0.26), "icon": "icon_sound",
			"icon_col": {"on": Color.WHITE, "low": Color(0.6, 0.6, 0.65), "off": Color(0.9, 0.3, 0.3)}[sfx.mode]},
		{"r": Rect2(HUD_W - 20, top + 44, 16, 16), "t": "", "a": _toggle_music, "c": Color(0.2, 0.2, 0.26), "icon": "icon_music",
			"icon_col": Color.WHITE if music_on else Color(0.9, 0.3, 0.3)},
		{"r": Rect2(HUD_W - 20, top + 4, 16, 16), "t": "×", "a": _quit, "c": Color(0.5, 0.15, 0.15)},
	]
	if panel == "bag":
		var acts := [["Ghép 9", _do_synth], ["Bán 1", _do_sell_one], ["Bán hết ô", _do_sell_all],
			["Mặc", _do_equip], ["Tự ghép", _do_auto]]
		for i in acts.size():
			b.append({"r": Rect2(10 + i * 92, _panel_h() - 34, 86, 26), "t": acts[i][0], "a": acts[i][1]})
		if sim.party_size() > 1:
			b.append({"r": Rect2(10 + 5 * 92, _panel_h() - 34, 86, 26), "t": "%s ▸" % Sim.CLASSES[sim.heroes[sel_hero].cls].name,
				"a": func(): sel_hero = (sel_hero + 1) % sim.party_size()})
	elif panel == "rune":
		b.append({"r": Rect2(PANEL_W - 110, _panel_h() - 34, 100, 26), "t": "Nâng", "a": _do_buy_rune,
			"c": Color(0.2, 0.5, 0.25) if sim.can_buy_rune(sel_rune) else Color(0.25, 0.25, 0.32)})
	elif panel == "portal":
		for s in Sim.MAX_STAGE:
			var st := s + 1
			var col := Color(0.18, 0.18, 0.22)
			if st == sim.stage:
				col = Color(0.85, 0.6, 0.15)
			elif st <= sim.max_stage:
				col = Color(0.2, 0.4, 0.75)
			b.append({"r": _portal_rect(st), "t": "%d-%d" % [(st - 1) / Sim.STAGES_PER_ACT + 1, (st - 1) % Sim.STAGES_PER_ACT + 1],
				"a": _go.bind(st), "c": col})
		b.append({"r": Rect2(10, _panel_h() - 34, 170, 26), "t": "Lặp màn: %s" % ("Bật" if sim.repeat else "Tắt"),
			"a": func(): sim.repeat = not sim.repeat, "c": Color(0.2, 0.5, 0.25) if sim.repeat else Color(0.25, 0.25, 0.32)})
	elif panel == "forge":
		b.append({"r": Rect2(PANEL_W - 130, _panel_h() - 34, 120, 26), "t": "Cường hóa", "a": _do_enhance,
			"c": Color(0.2, 0.5, 0.25) if sim.gold >= sim.enh_cost(sel_enh_hero, sel_enh_slot) else Color(0.25, 0.25, 0.32)})
	return b


func _forge_rect(hero_i: int, slot_i: int) -> Rect2:
	return Rect2(80 + slot_i * 156, 26 + hero_i * 46, 150, 40)


func _panel_h() -> int:
	return PANEL_HEIGHTS.get(panel, 0)


func _rune_rect(r: Dictionary) -> Rect2:
	return Rect2(14 + r.at[0] * 108, 24 + r.at[1] * 38, RUNE_NODE, RUNE_NODE)


func _cell_rect(slot_i: int, tier: int) -> Rect2:
	return Rect2(GRID_X + tier * CELL.x, GRID_Y + slot_i * (CELL.y + 4), CELL.x - 4, CELL.y)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for b in _buttons():
		if b.r.has_point(event.position):
			sfx.play("click")
			b.a.call()
			return
	if panel == "forge":
		for hi in sim.party_size():
			for si in Sim.SLOTS.size():
				if _forge_rect(hi, si).has_point(event.position):
					sel_enh_hero = hi
					sel_enh_slot = Sim.SLOTS[si]
					return
	if panel == "rune":
		for r in Sim.RUNES:
			if _rune_rect(r).grow(4).has_point(event.position):
				sel_rune = r.id
				return
	if panel == "bag":
		for si in Sim.SLOTS.size():
			for t in Sim.TIERS.size():
				if _cell_rect(si, t).has_point(event.position):
					sel_slot = Sim.SLOTS[si]
					sel_tier = t
					return


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


# --- actions ---

func _open_chest() -> void:
	if sim.open_chest():
		sfx.play("chest")
		_show_toast("Rương: +%d vàng, +%d món" % [20 * sim.stage, Sim.CHEST_ITEMS])


func _toggle_music() -> void:
	music_on = not music_on
	_update_music()
	_show_toast("Nhạc nền: %s" % ("bật" if music_on else "tắt"))


## Keep the current act's loop playing. Building a loop takes ~0.3 s, done once per act change.
func _update_music() -> void:
	if not music_on:
		music.stop()
		_music_act = 0
		return
	if _music_act != sim.act():
		_music_act = sim.act()
		music.stream = Music.build(_music_act - 1)
		music.volume_db = MUSIC_DB
		music.play()


func _cycle_sound() -> void:
	_show_toast("Âm thanh: %s" % {"on": "bật", "low": "nhỏ", "off": "tắt"}[sfx.cycle_mode()])
	sfx.play("click")


func _toggle_panel(name: String) -> void:
	panel = "" if panel == name else name
	_place_window()


func _do_enhance() -> void:
	var name := "%s của %s" % [SLOT_NAMES[sel_enh_slot], Sim.CLASSES[sim.heroes[sel_enh_hero].cls].name]
	var res := sim.enhance(sel_enh_hero, sel_enh_slot)
	if res.is_empty():
		sfx.play("fail")
		_show_toast("Thiếu vàng: cần %d" % sim.enh_cost(sel_enh_hero, sel_enh_slot))
	elif res.ok:
		sfx.play("success")
		_show_toast("%s lên +%d" % [name, res.level])
	else:
		sfx.play("fail")
		_show_toast("Thất bại, %s vẫn +%d" % [name, res.level])


func _do_buy_rune() -> void:
	var r := Sim.rune_def(sel_rune)
	if sim.buy_rune(sel_rune):
		sfx.play("success")
		_show_toast("%s lên cấp %d" % [r.name, sim.rune_level(sel_rune)])
	elif not sim.rune_unlocked(sel_rune):
		_show_toast("Cần rune %s trước" % Sim.rune_def(r.req).name)
	elif Sim.is_maxed(r, sim.rune_level(sel_rune)):
		_show_toast("Đã tối đa")
	else:
		_show_toast("Thiếu vàng: cần %d" % sim.rune_cost(sel_rune))


func _quit() -> void:
	_save()
	get_tree().quit()


func _do_synth() -> void:
	if sel_slot == "":
		return
	var r := sim.synth(sel_slot, sel_tier)
	if r.is_empty():
		_show_toast("Cần 9 món cùng loại, cùng phẩm")
		return
	sfx.play({"up": "success", "great": "great", "fail": "fail"}[r.kind])
	var msg: String = {"up": "Thành công", "great": "ĐẠI THÀNH CÔNG", "fail": "Thất bại"}[r.kind]
	_show_toast("%s: %s %s" % [msg, Sim.TIERS[r.tier], SLOT_NAMES[sel_slot]])


func _do_sell_one() -> void:
	if sel_slot != "":
		_show_toast("+%d vàng" % sim.sell(sel_slot, sel_tier, 1))


func _do_sell_all() -> void:
	if sel_slot != "":
		_show_toast("+%d vàng" % sim.sell(sel_slot, sel_tier, sim.count(sel_slot, sel_tier)))


func _do_equip() -> void:
	if sel_slot != "" and sim.equip(sel_slot, sel_tier, sel_hero):
		_show_toast("%s mặc %s %s" % [Sim.CLASSES[sim.heroes[sel_hero].cls].name, Sim.TIERS[sel_tier], SLOT_NAMES[sel_slot]])


func _do_auto() -> void:
	_show_toast("Tự ghép %d lần (chỉ bậc không thể fail)" % sim.auto_synth())


func _show_toast(text: String) -> void:
	_toast = text
	_toast_left = 4.0


# --- save ---

func _save() -> void:
	var d := sim.to_dict()
	d["saved_at"] = Time.get_unix_time_from_system()
	d["sound_mode"] = sfx.mode
	d["music_on"] = music_on
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return  # corrupt save: start fresh rather than crash
	sim.from_dict(d)
	if d.get("sound_mode") in Sfx.MODES:
		sfx.mode = d.sound_mode
	music_on = bool(d.get("music_on", true))
	var r := sim.apply_offline(Time.get_unix_time_from_system() - float(d.get("saved_at", 0.0)))
	if r.gold > 0:
		_show_toast("Offline: +%d vàng, +%d EXP" % [r.gold, r.xp])
	elif sim.rune_level("repose") == 0:
		_show_toast("Mở rune Nghỉ ngơi để nhận thưởng khi tắt game")


# --- drawing ---

func _bonus_text(slot: String, tier: int) -> String:
	var v := Sim.item_bonus(slot, tier)
	match slot:
		"weapon": return "+%d ATK" % v
		"gloves": return "+%d%% tốc đánh" % roundi(v * 100)
		_: return "+%d%% vàng" % roundi(v * 100)


func _draw() -> void:
	var size := get_viewport_rect().size
	var top := size.y - STRIP_H
	var ground := size.y - 6
	var t := Time.get_ticks_msec() / 1000.0

	if panel == "bag":
		_draw_bag()
	elif panel == "rune":
		_draw_runes()
	elif panel == "forge":
		_draw_forge()
	elif panel == "portal":
		_draw_portal()

	# HUD
	draw_rect(Rect2(0, top, HUD_W, STRIP_H), Color(0.08, 0.08, 0.12, 0.85))
	var lvs := []
	for i in sim.party_size():
		lvs.append("%s%d" % [Sim.CLASSES[sim.heroes[i].cls].name[0], sim.heroes[i].level])
	var lv_txt := ("Knight Lv %d" % sim.heroes[0].level) if sim.party_size() == 1 else "Lv " + " · ".join(lvs)
	var worst := 1.0
	for i in sim.party_size():
		worst = minf(worst, sim.hero_exp_mult(i))
	_text(Vector2(10, top + 40), lv_txt, Color.WHITE if worst >= 0.8 else Color(1.0, 0.55, 0.3), 12)  # orange: losing EXP to the level gap
	_text(Vector2(10, top + 60), "Vàng %d" % sim.gold, Color.GOLD)
	_text(Vector2(10, top + 80), "DPS đội %d" % sim.team_dps())
	var next_chest := maxi(0, ceili(sim.chest_ready_at - Time.get_unix_time_from_system()))
	_text(Vector2(10, top + 100), "Rương sau %d:%02d" % [next_chest / 60, next_chest % 60], Color(0.7, 0.7, 0.7))
	for b in _buttons():
		draw_rect(b.r, b.get("c", Color(0.25, 0.25, 0.32)))
		var text_x := 5.0
		if b.has("icon"):
			var icon := Art.tex(b.icon)
			var isz := icon.get_size() * 2
			var ix: float = 4.0 if b.t != "" else (b.r.size.x - isz.x) / 2  # icon-only buttons center the icon
			draw_texture_rect(icon, Rect2(b.r.position + Vector2(ix, (b.r.size.y - isz.y) / 2), isz), false, b.get("icon_col", Color.WHITE))
			text_x = isz.x + 6
		_text(b.r.position + Vector2(text_x, b.r.size.y / 2 + 5), b.t, Color.WHITE, 12)

	# Battlefield (click-through)
	var walk := int(t * 4) % 2 == 0
	# Back to front: Sorcerer, Ranger, Knight. Each hero takes one sprite width.
	var xs := {}
	var x0 := HUD_W + 30.0
	for i in range(sim.party_size() - 1, -1, -1):
		xs[i] = x0
		x0 += 16 * PX + 4
	for i in xs:
		var pre: String = HERO_SPRITES[i]
		var pose: String = pre + ("_cast" if i == 2 else "_attack") if _swing[i] > 0.0 else pre + ("_walk_a" if walk else "_walk_b")
		_sprite(pose, Vector2(xs[i], ground))
	var hero_x: float = xs[0]

	var art: Dictionary = ACT_ART[sim.act() - 1]
	draw_rect(Rect2(HUD_W, ground, 520, 3), art.ground)
	var m_name: String = art.boss
	var m_scale := float(PX)
	var m_tint := Color.WHITE
	if not sim.is_act_boss():  # regular mobs alternate by wave; a stage boss is the first mob, bigger and redder
		var frames: Array = art.mobs[0 if sim.is_boss() else (sim.wave - 1) % art.mobs.size()]
		m_name = frames[int(t * 2.5) % 2]
		if sim.is_boss():
			m_scale = PX * 1.6
			m_tint = Color(1.4, 0.8, 0.8)
	var m_tex := Art.tex(m_name)
	var m_size := m_tex.get_size() * m_scale
	var m_pos := Vector2(hero_x + 16 * PX + 6, ground - m_size.y + Art.top_row(m_name) * m_scale)
	_sprite(m_name, Vector2(m_pos.x, ground), Color(4, 4, 4) if _hit_flash > 0.0 else m_tint, m_scale)
	var hp_frac := clampf(sim.monster_hp / sim.monster_max_hp, 0.0, 1.0)
	draw_rect(Rect2(m_pos + Vector2(0, -8), Vector2(m_size.x, 4)), Color(0.2, 0.2, 0.2, 0.8))
	draw_rect(Rect2(m_pos + Vector2(0, -8), Vector2(m_size.x * hp_frac, 4)), Color(0.3, 0.9, 0.3))

	if xs.has(2) and _fire_t >= 0.0 and _fire_t < FIRE_SEC:
		var fx := lerpf(xs[2] + 14 * PX, m_pos.x, _fire_t / FIRE_SEC)
		var arc := sin(_fire_t / FIRE_SEC * PI) * 8 * PX  # lob it over the front line
		_sprite("fireball", Vector2(fx, ground - 8 * PX - arc))
	if xs.has(1) and _arrow_t >= 0.0 and _arrow_t < ARROW_SEC:
		var from: float = xs[1] + 14 * PX
		var x := lerpf(from, m_pos.x, _arrow_t / ARROW_SEC)
		_sprite("arrow", Vector2(x, ground - 7 * PX), Color(1.6, 1.3, 0.5) if sim.last_crit else Color.WHITE)

	if _toast_left > 0.0:
		_text(Vector2(hero_x + 160, ground - 10), _toast, Color.GOLD)


func _draw_bag() -> void:
	draw_rect(Rect2(0, 0, PANEL_W, _panel_h()), Color(0.08, 0.08, 0.12, 0.92))
	_text(Vector2(10, 18), "Túi %d/%d" % [sim.bag_total(), sim.bag_cap()])
	for ti in Sim.TIERS.size():
		_text(Vector2(GRID_X + ti * CELL.x + 2, 18), Sim.TIERS[ti], TIER_COLORS[ti], 11)
	for si in Sim.SLOTS.size():
		var slot: String = Sim.SLOTS[si]
		_text(Vector2(10, GRID_Y + si * (CELL.y + 4) + 20), SLOT_NAMES[slot])
		for ti in Sim.TIERS.size():
			var r := _cell_rect(si, ti)
			var n := sim.count(slot, ti)
			var col: Color = TIER_COLORS[ti]
			draw_rect(r, col.darkened(0.75) if n > 0 else Color(0.18, 0.18, 0.22))
			draw_texture_rect(Art.tex("icon_" + slot), Rect2(r.position + Vector2(3, 3), Vector2(24, 24)), false,
				col if n > 0 else Color(1, 1, 1, 0.12))
			if n > 0:
				_text(r.position + Vector2(32, 20), "x%d" % n, Color.WHITE if n < 9 else Color.YELLOW)
			if sim.heroes[sel_hero].equipped[slot] == ti:
				_text(r.position + Vector2(r.size.x - 14, 20), "E", Color.WHITE)
			if slot == sel_slot and ti == sel_tier:
				draw_rect(r, Color.WHITE, false, 2.0)

	var info := "Chọn một ô. Ghép cần 9 món cùng loại, cùng phẩm."
	if sel_slot != "":
		info = "%s %s: %s · bán %d vàng" % [Sim.TIERS[sel_tier], SLOT_NAMES[sel_slot],
			_bonus_text(sel_slot, sel_tier), sim.sell_price(sel_tier)]
		if sel_tier < Sim.SYNTH.size():
			var rate: Array = Sim.SYNTH[sel_tier]
			info += " · ghép: %.1f%% lên, %.2f%% đại" % [rate[0] * 100, rate[1] * 100]
			var fail: float = 1.0 - rate[0] - rate[1]
			if fail > 0.0:
				info += ", %.1f%% fail" % (fail * 100)
	_text(Vector2(10, _panel_h() - 44), info, Color(0.85, 0.85, 0.85), 12)


func _text(pos: Vector2, s: String, col := Color.WHITE, font_size := 13) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Draw an art sprite scaled by PX with its bottom-left at `feet`.
func _sprite(name: String, feet: Vector2, modulate_col := Color.WHITE, scale: float = PX) -> void:
	var tex := Art.tex(name)
	var sz := tex.get_size() * scale
	draw_texture_rect(tex, Rect2(feet - Vector2(0, sz.y), sz), false, modulate_col)


func _rune_desc(r: Dictionary, lv: int) -> String:
	return r.fmt if r.per == 0 else r.fmt % (r.per * lv)


func _draw_runes() -> void:
	var ph := _panel_h()
	draw_rect(Rect2(0, 0, PANEL_W, ph), Color(0.08, 0.08, 0.12, 0.92))
	_text(Vector2(10, 16), "Cây rune · Vàng %d" % sim.gold, Color.GOLD, 12)
	var half := RUNE_NODE / 2.0
	for r in Sim.RUNES:  # links first, nodes on top
		if r.req == "":
			continue
		var a := _rune_rect(Sim.rune_def(r.req))
		var b := _rune_rect(r)
		var mid_x := a.end.x + (b.position.x - a.end.x) / 2.0
		var col := Color(0.75, 0.75, 0.85) if sim.rune_level(r.req) > 0 else Color(0.3, 0.3, 0.36)
		draw_polyline(PackedVector2Array([Vector2(a.end.x, a.position.y + half), Vector2(mid_x, a.position.y + half),
			Vector2(mid_x, b.position.y + half), Vector2(b.position.x, b.position.y + half)]), col, 2.0)
	for r in Sim.RUNES:
		var rect := _rune_rect(r)
		var lv := sim.rune_level(r.id)
		var fill := Color(0.2, 0.2, 0.24)
		if Sim.is_maxed(r, lv):
			fill = Color(0.6, 0.45, 0.1)
		elif sim.can_buy_rune(r.id):
			fill = Color(0.2, 0.45, 0.85)
		elif sim.rune_unlocked(r.id):
			fill = Color(0.18, 0.28, 0.45)
		draw_rect(rect, fill)
		draw_rect(rect, Color.WHITE if r.id == sel_rune else Color(0.05, 0.05, 0.08), false, 2.0 if r.id == sel_rune else 1.0)
		_text(rect.position + Vector2(3, 15), ("%d/%d" % [lv, r.max] if r.max > 0 else "%d/∞" % lv), Color.WHITE, 9)
		_text(rect.position + Vector2(0, RUNE_NODE + 11), r.name,
			Color(0.9, 0.9, 0.9) if sim.rune_unlocked(r.id) else Color(0.5, 0.5, 0.55), 11)

	var s := Sim.rune_def(sel_rune)
	var lv := sim.rune_level(sel_rune)
	var info := "%s (%s): " % [s.name, "%d/%d" % [lv, s.max] if s.max > 0 else "cấp %d, không giới hạn" % lv]
	if Sim.is_maxed(s, lv):
		info += "%s · đã tối đa" % _rune_desc(s, lv)
	else:
		info += "%s → %s · giá %d vàng" % [_rune_desc(s, lv) if lv > 0 else "chưa có", _rune_desc(s, lv + 1), sim.rune_cost(sel_rune)]
		if not sim.rune_unlocked(sel_rune):
			info += " · cần %s" % Sim.rune_def(s.req).name
	_text(Vector2(10, ph - 44), info, Color(0.85, 0.85, 0.85), 12)


func _enh_effect(slot: String, lv: int) -> String:
	match slot:
		"weapon": return "ATK x%.2f" % pow(Sim.ENH_WEAPON_MULT, lv)
		"gloves": return "+%d%% tốc đánh" % roundi(Sim.ENH_GLOVES_APS * lv * 100)
		_: return "+%d%% vàng" % roundi(Sim.ENH_RING_GOLD * lv * 100)


func _draw_forge() -> void:
	var ph := _panel_h()
	draw_rect(Rect2(0, 0, PANEL_W, ph), Color(0.08, 0.08, 0.12, 0.92))
	_text(Vector2(10, 16), "Lò rèn · Vàng %d" % sim.gold, Color.GOLD, 12)
	for hi in sim.party_size():
		var h: Dictionary = sim.heroes[hi]
		_text(Vector2(10, 26 + hi * 46 + 25), Sim.CLASSES[h.cls].name)
		for si in Sim.SLOTS.size():
			var slot: String = Sim.SLOTS[si]
			var r := _forge_rect(hi, si)
			var lv: int = h.enh[slot]
			var affordable := sim.gold >= sim.enh_cost(hi, slot)
			draw_rect(r, Color(0.16, 0.26, 0.4) if affordable else Color(0.18, 0.18, 0.22))
			var eq: int = h.equipped[slot]
			draw_texture_rect(Art.tex("icon_" + slot), Rect2(r.position + Vector2(4, 8), Vector2(24, 24)), false,
				TIER_COLORS[eq] if eq >= 0 else Color(1, 1, 1, 0.25))
			_text(r.position + Vector2(32, 16), "%s +%d" % [SLOT_NAMES[slot], lv], Color.WHITE, 12)
			_text(r.position + Vector2(32, 32), _enh_effect(slot, lv), Color(0.75, 0.85, 1.0), 10)
			if hi == sel_enh_hero and slot == sel_enh_slot:
				draw_rect(r, Color.WHITE, false, 2.0)

	var lv: int = sim.heroes[sel_enh_hero].enh[sel_enh_slot]
	var info := "%s của %s +%d → +%d: %s → %s · tỉ lệ %d%% · giá %d vàng" % [
		SLOT_NAMES[sel_enh_slot], Sim.CLASSES[sim.heroes[sel_enh_hero].cls].name, lv, lv + 1,
		_enh_effect(sel_enh_slot, lv), _enh_effect(sel_enh_slot, lv + 1),
		roundi(Sim.enh_chance(lv) * 100), sim.enh_cost(sel_enh_hero, sel_enh_slot)]
	_text(Vector2(10, ph - 44), info, Color(0.85, 0.85, 0.85), 11)
	_text(Vector2(10, ph - 16), "Từ +%d có thể thất bại; thất bại chỉ mất vàng, không tụt cấp." % (Sim.ENH_SAFE_LEVEL + 1),
		Color(0.6, 0.6, 0.65), 10)


func _stage_text() -> String:
	var wave_txt := "Sóng %d/%d" % [sim.wave, Sim.WAVES_PER_STAGE]
	if sim.is_boss():
		wave_txt = ("BOSS ACT %ds" if sim.is_act_boss() else "BOSS %ds") % ceili(sim.boss_time_left)
	return "%d-%d · %s" % [sim.act(), sim.local_stage(), wave_txt]


func _portal_rect(st: int) -> Rect2:
	return Rect2(96 + ((st - 1) % Sim.STAGES_PER_ACT) * 45, 26 + ((st - 1) / Sim.STAGES_PER_ACT) * 38, 41, 30)


func _go(st: int) -> void:
	if sim.go_to_stage(st):
		_show_toast("Đến màn %d-%d (Lv %d) · %s" % [sim.act(), sim.local_stage(), sim.stage_level(), _exp_text()])
	else:
		_show_toast("Màn này chưa mở")


func _draw_portal() -> void:
	var ph := _panel_h()
	draw_rect(Rect2(0, 0, PANEL_W, ph), Color(0.08, 0.08, 0.12, 0.92))
	_text(Vector2(10, 16), "Portal · đã mở tới %d-%d · màn này Lv %d · %s" % [(sim.max_stage - 1) / Sim.STAGES_PER_ACT + 1,
		(sim.max_stage - 1) % Sim.STAGES_PER_ACT + 1, sim.stage_level(), _exp_text()], Color(0.6, 0.8, 1.0), 12)
	for a in Sim.ACT_NAMES.size():
		_text(Vector2(10, 26 + a * 38 + 20), Sim.ACT_NAMES[a], Color.WHITE if a * Sim.STAGES_PER_ACT < sim.max_stage else Color(0.5, 0.5, 0.55), 12)
	var hint := "Bật: hạ boss xong ở lại màn này để cày; màn kế vẫn được mở." if sim.repeat else "Tắt: hạ boss xong tự sang màn kế."
	_text(Vector2(190, ph - 16), hint, Color(0.7, 0.7, 0.75), 11)


## "EXP Knight 100%, Ranger 50%": how much EXP each active hero keeps on this stage.
func _exp_text() -> String:
	var parts := []
	for i in sim.party_size():
		parts.append("%s %d%%" % [Sim.CLASSES[sim.heroes[i].cls].name, roundi(sim.hero_exp_mult(i) * 100)])
	return "EXP " + ", ".join(parts)


# --- sound events: diff the sim before/after a step ---

func _snapshot() -> Dictionary:
	var lv := 0
	for h in sim.heroes:
		lv += h.level
	return {"kills": sim.kills, "boss": sim.is_boss(), "levels": lv, "items": sim.bag_total(),
		"chests": sim.chests, "casts": sim.heroes[2].casts}


func _play_events(s: Dictionary, attacks_before: Array) -> void:
	var now := _snapshot()
	if now.kills > s.kills:
		sfx.play("boss_win" if s.boss else "kill")
	if now.levels > s.levels:
		sfx.play("level")
	if now.items > s.items or now.chests > s.chests:
		sfx.play("drop")
	if now.casts > s.casts:
		sfx.play("fireball")
	for i in sim.party_size():
		if sim.heroes[i].attacks > attacks_before[i]:
			match sim.heroes[i].cls:
				"knight": sfx.play("pierce" if sim.heroes[i].attacks % Sim.PIERCE_EVERY == 0 else "hit")
				"ranger": sfx.play("arrow")
				_: sfx.play("hit")
