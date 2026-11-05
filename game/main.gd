extends Node2D
## Transparent strip at the bottom of the screen. Only the HUD box and the open panel catch the mouse.
## Immediate-mode UI: everything is drawn in _draw(); buttons register themselves while drawing.

const Sim := preload("res://sim.gd")
const D := preload("res://data.gd")
const Art := preload("res://art.gd")
const Gfx := preload("res://gfx.gd")
const Sfx := preload("res://sfx.gd")
const Music := preload("res://music.gd")
const Panels := preload("res://panels.gd")
const View3D := preload("res://view3d.gd")
const Ui := preload("res://ui.gd")
const Field := preload("res://field.gd")
const UI_REDRAW_SEC := 0.25  # HUD and panels refresh 4 times a second, and at once on mouse input
const MUSIC_DB := -20.0  # quiet: this plays next to work apps all day
const SAVE_PATH := "user://save.json"
const STRIP_H := 140
const HUD_W := 250
const PANEL_W := 800
const PANEL_HEIGHTS := {"bag": 330, "hero": 330, "forge": 300, "rune": 330, "portal": 250, "settings": 150}
const HERO_GAP := 58.0
const MOB_GAP := 62.0
const SAVE_EVERY_SEC := 30.0

var sim := Sim.new()
var sfx := Sfx.new()
var music := AudioStreamPlayer.new()
var music_on := true
var bg_alpha := 0.35  # Q14.2 B: background opacity slider
var panel := ""
var sel_item := -1  # uid
var sel_class := "knight"
var sel_party_slot := -1
var sel_rune := "growth"
var sel_portal_diff := 0
var forge_stone := 1
var forge_count := 1
var forge_protect := true
var _music_act := -1
var _save_timer := 0.0
var _toast := ""
var _toast_left := 0.0
var _font := Ui.font()
var _btns := []  # [{r, a}] registered during the last draw
var _mouse := Vector2(-1, -1)
var _t := 0.0
# battlefield visuals
var _fx := []  # {id, pos, from, t, dur, scale, flip, kind}
var _nums := []  # floating numbers {text, pos, t, col}
var _mob_x := {}  # uid -> current x
var _hero_anim := {}  # slot -> {swing, hurt}
var _mob_anim := {}  # uid -> {swing, hurt}
var view := View3D.new()  # the 3D battle, drawn as a texture under bars and effects
var field := Field.new()  # battlefield layer, redrawn every frame
var _ci: CanvasItem = self  # where text() and _bar() draw: this node, or the field while it draws
var _ui_timer := 0.0
## HUD and panels render into this texture only when they change: rounded boxes and outlined text are
## costly for the canvas renderer, and redrawing them 30 times a second tripled the game's idle CPU.
var ui_vp := SubViewport.new()
var ui_canvas := Field.new()


func _ready() -> void:
	Engine.max_fps = 30  # runs all day next to work apps
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel art
	add_child(sfx)
	add_child(music)
	add_child(view)
	field.m = self
	field.show_behind_parent = true
	add_child(field)
	ui_vp.transparent_bg = true
	ui_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	ui_canvas.m = self
	ui_canvas.ui = true
	ui_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_vp.add_child(ui_canvas)
	add_child(ui_vp)
	_place_window()
	_load()
	_update_music()


## screen_get_scale() is only implemented on macOS, Wayland and mobile; Windows always returns 1.0,
## so there the scale comes from DPI (96 = 100%).
func _ui_scale(screen: int) -> float:
	if OS.get_name() == "Windows":
		return maxf(1.0, DisplayServer.screen_get_dpi(screen) / 96.0)
	return DisplayServer.screen_get_scale(screen)


func _panel_h() -> int:
	return PANEL_HEIGHTS.get(panel, 0)


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
	redraw_ui.call_deferred()  # the window size changed


func toggle_panel(name: String) -> void:
	panel = "" if panel == name else name
	redraw_ui()
	_place_window()


# =========================================================== loop

func _process(delta: float) -> void:
	_t += delta
	sim.step(delta, Time.get_unix_time_from_system())
	for e in sim.events:
		_on_event(e)
	sim.events.clear()
	_update_music()
	for k in _hero_anim:
		_hero_anim[k].swing = maxf(0.0, _hero_anim[k].swing - delta)
		_hero_anim[k].hurt = maxf(0.0, _hero_anim[k].hurt - delta)
	for k in _mob_anim:
		_mob_anim[k].swing = maxf(0.0, _mob_anim[k].swing - delta)
		_mob_anim[k].hurt = maxf(0.0, _mob_anim[k].hurt - delta)
	for f in _fx:
		f.t += delta
	_fx = _fx.filter(func(f): return f.t < f.dur)
	for n in _nums:
		n.t += delta
	_nums = _nums.filter(func(n): return n.t < 0.9)
	_update_view(delta)
	_toast_left = maxf(_toast_left - delta, 0.0)
	_save_timer += delta
	if _save_timer >= SAVE_EVERY_SEC:
		_save_timer = 0.0
		_save()
	field.queue_redraw()
	_ui_timer += delta
	if _ui_timer >= UI_REDRAW_SEC:
		_ui_timer = 0.0
		redraw_ui()
	queue_redraw()


func show_toast(text: String) -> void:
	_toast = text
	_toast_left = 4.0


# =========================================================== events -> visuals and sound

func _ground() -> float:
	return get_viewport_rect().size.y - 10.0


func hero_x(slot: int) -> float:
	# back to front: the last slot stands furthest left
	return HUD_W + 50.0 + (sim.party.size() - 1 - slot) * HERO_GAP


func _mob_target_x(i: int) -> float:
	return hero_x(0) + 80.0 + i * MOB_GAP


func mob_pos(uid: int) -> Vector2:
	return Vector2(_mob_x.get(uid, hero_x(0) + 90.0), _ground() - 30.0)


func hero_pos(slot: int) -> Vector2:
	return Vector2(hero_x(slot), _ground() - 40.0)


func _add_fx(id: String, pos: Vector2, scale := 0.8, speed := 1.0, from := Vector2.INF, flip := false) -> void:
	var s := Gfx.sheet(id)
	if s.is_empty():
		return
	var dur: float = s.dur / speed
	_fx.append({"id": id, "pos": pos, "from": from, "t": 0.0, "dur": dur, "scale": scale, "flip": flip, "loop": dur})
	if from != Vector2.INF:  # a projectile: fly for 0.3 s, then a hit spark
		_fx[-1].dur = 0.3
		_fx[-1].loop = s.dur


func _on_event(e: Dictionary) -> void:
	match e.t:
		"attack":
			_anim_hero(e.slot).swing = 0.15
			var cls: String = sim.party[e.slot] if e.slot < sim.party.size() else "knight"
			view.act(cls, "attack", sim.stats(cls).aspd)
			if D.CLASSES[cls].range == "ranged" and e.mob >= 0:
				var id := "arrow" if cls == "ranger" else "magic-missile"
				_add_fx(id, mob_pos(e.mob), 0.45, 1.0, hero_pos(e.slot))
			sfx.play("arrow" if cls == "ranger" else "hit")
		"skill":
			_anim_hero(e.slot).swing = 0.3
			if e.slot < sim.party.size():
				view.act(sim.party[e.slot], "skill")
			var target := mob_pos(e.mob) if e.mob >= 0 else _mobs_center()
			match e.fx:
				"fireball", "magic-missile", "arrow":
					_add_fx(e.fx, target, 0.6, 1.0, hero_pos(e.slot))
				_:
					var s := Gfx.sheet(e.fx)
					_add_fx(e.fx, target, 0.8, maxf(1.0, s.get("dur", 1.0) / 0.8))
			sfx.play("fireball" if e.fx in ["fireball", "fire-ring"] else "pierce")
		"buff":
			_add_fx(e.fx, hero_pos(e.slot), 0.7, 1.5)
		"heal":
			_add_fx(e.fx, hero_pos(e.target), 0.7, 1.5)
			sfx.play("success")
		"dmg":
			var col := Color(1.0, 0.9, 0.3) if e.crit else Color.WHITE
			_num("MISS" if e.miss else str(e.v), mob_pos(e.mob) + Vector2(0, -30), col)
			_anim_mob(e.mob).hurt = 0.12
		"hurt":
			_num("MISS" if e.miss else ("-%d" % e.v), hero_pos(e.slot) + Vector2(0, -40), Color(1.0, 0.4, 0.4))
			_anim_hero(e.slot).hurt = 0.15
		"mob_attack":
			_anim_mob(e.mob).swing = 0.15
			view.act(e.mob, "attack", 1.0)
			if e.role != "melee":
				var j := 0
				_add_fx("magic-missile", hero_pos(j), 0.4, 1.0, mob_pos(e.mob), true)
		"mob_die":
			_add_fx("poof", mob_pos(e.mob) + Vector2(0, 10), 0.4, 1.5)
			sfx.play("boss_win" if e.boss else "kill")
		"slam_warn":
			show_toast("Boss chuẩn bị đập đất!")
		"slam":
			view.act(e.mob, "skill")
			for i in sim.party.size():
				_add_fx("ground-slam", hero_pos(i) + Vector2(0, 20), 0.5, 2.5)
		"summon":
			show_toast("Boss gọi thêm lính")
		"enrage":
			_add_fx("rage", mob_pos(e.mob), 0.8)
		"die":
			_add_fx("poof", hero_pos(e.slot), 0.6, 1.5)
		"revive":
			_add_fx("respawn-beam", hero_pos(e.slot), 0.5, 2.0)
		"wipe":
			show_toast("Cả đội gục ngã — đánh lại từ sóng 1")
			sfx.play("fail")
		"clear":
			view.cheer()
			show_toast("Qua màn! +%d vàng%s" % [e.gold, " (lần đầu)" if e.first else ""])
		"diff_unlock":
			show_toast("Mở độ khó %s" % D.DIFFS[e.d].name)
			sfx.play("great")
		"levelup":
			sfx.play("level")
		"drop":
			sfx.play("drop")
			if e.rarity >= 3:
				show_toast("Rơi đồ %s!" % D.RARITIES[e.rarity].vn)
		"open_chest":
			sfx.play("chest")
		"boss":
			show_toast(e.name)
		"stage":
			_mob_x.clear()


func _anim_hero(slot: int) -> Dictionary:
	if not _hero_anim.has(slot):
		_hero_anim[slot] = {"swing": 0.0, "hurt": 0.0}
	return _hero_anim[slot]


func _anim_mob(uid: int) -> Dictionary:
	if not _mob_anim.has(uid):
		_mob_anim[uid] = {"swing": 0.0, "hurt": 0.0}
	return _mob_anim[uid]


func _num(text: String, pos: Vector2, col: Color) -> void:
	_nums.append({"text": text, "pos": pos + Vector2(randf_range(-8, 8), 0), "t": 0.0, "col": col})
	if _nums.size() > 40:
		_nums.pop_front()


func _mobs_center() -> Vector2:
	var live := sim._alive_mobs()
	if live.is_empty():
		return Vector2(hero_x(0) + 150, _ground() - 30)
	var x := 0.0
	for m in live:
		x += mob_pos(sim.mobs[m].uid).x
	return Vector2(x / live.size(), _ground() - 30)


# =========================================================== immediate-mode widgets

func text(pos: Vector2, s: String, col := Color.WHITE, size := 13) -> void:
	_ci.draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(Ui.INK, col.a * 0.85))
	_ci.draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func text_w(s: String, size := 13) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Draw a button and register its click. Disabled buttons are drawn dim and do nothing.
## `col` picks the face color: a Ui.BUTTONS key, or a Color (old dark colors are brightened to fit the style).
func button(r: Rect2, label: String, action: Callable, col: Variant = "normal", enabled := true, size := 12) -> void:
	var face_col: Color = Ui.BUTTONS.get(col, Ui.BUTTONS.normal) if typeof(col) == TYPE_STRING else _bright(col)
	var hover := r.has_point(_mouse) and enabled
	var face := Ui.button_face(_ci, r, face_col, hover, enabled)
	if label != "":
		var tw := text_w(label, size)
		text(Vector2(face.position.x + maxf(4.0, (face.size.x - tw) / 2.0), face.position.y + face.size.y / 2.0 + size * 0.36),
			label, Ui.TEXT if enabled else Ui.TEXT_DIM, size)
	if enabled:
		_btns.append({"r": r, "a": action})


## Panels were written with dark flat colors; lift them into the brighter button palette, keeping the hue.
static func _bright(c: Color) -> Color:
	if c.s < 0.15:
		return Ui.BUTTONS.normal.lerp(c, 0.25)
	return Color.from_hsv(c.h, clampf(c.s * 1.15, 0.35, 0.8), clampf(c.v * 1.6, 0.5, 0.92))


## A clickable area without drawing.
func area(r: Rect2, action: Callable) -> void:
	_btns.append({"r": r, "a": action})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		redraw_ui()  # hover highlights
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	for i in range(_btns.size() - 1, -1, -1):  # topmost first
		if _btns[i].r.has_point(event.position):
			sfx.play("click")
			_btns[i].a.call()
			redraw_ui()
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


# =========================================================== drawing

func _draw() -> void:
	draw_texture_rect(ui_vp.get_texture(), Rect2(Vector2.ZERO, get_viewport_rect().size), false)


## Ask for a fresh HUD and panel texture: re-run their drawing at full screen resolution and render it once.
func redraw_ui() -> void:
	var scale := get_window().content_scale_factor
	var logical := get_viewport_rect().size
	var px := Vector2i(int(logical.x * scale), int(logical.y * scale))
	if ui_vp.size != px:
		ui_vp.size = px
	ui_vp.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(scale, scale))
	ui_canvas.queue_redraw()
	ui_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Called by the UI layer when redraw_ui() asked for it.
func draw_ui(ci: CanvasItem) -> void:
	_ci = ci
	_btns.clear()
	var size := get_viewport_rect().size
	_draw_hud(size.y - STRIP_H)
	if panel != "":
		Ui.frame(ci, Rect2(0, 0, PANEL_W, _panel_h() - 2))
		Panels.draw(self, panel)
	_ci = self


## Called by the field layer every frame.
func draw_field(ci: CanvasItem) -> void:
	_ci = ci
	var size := get_viewport_rect().size
	_draw_background(size.y - STRIP_H, size)
	_draw_battlefield()
	_ci = self


## Q14.2 B: layered hills seeded by the stage, behind the battlefield, at a user-set opacity.
func _draw_background(top: float, size: Vector2) -> void:
	if bg_alpha <= 0.01:
		return
	var a_i := sim.act() - 1 if sim.mode == "campaign" else 2
	var palettes := [[Color("2f5d3a"), Color("3f7a4a"), Color("6bbf59")], [Color("8a6a3c"), Color("b8894e"), Color("e0b872")],
		[Color("1d2b2a"), Color("27403a"), Color("3d5e4f")]]
	var pal: Array = palettes[a_i]
	var r := RandomNumberGenerator.new()
	r.seed = hash([sim.mode, sim.diff, sim.stage])
	var x0 := HUD_W + 6.0
	var w := minf(size.x, x0 + 760.0) - x0
	for layer in 3:
		var pts := PackedVector2Array([Vector2(x0, size.y)])
		var base := size.y - 24.0 - (2 - layer) * 16.0
		var n := 10 + layer * 4
		for i in n + 1:
			var x := x0 + w * i / n
			pts.append(Vector2(x, base - r.randf_range(4.0, 26.0 - layer * 5.0)))
		pts.append(Vector2(x0 + w, size.y))
		var c: Color = pal[layer]
		c.a = bg_alpha * (0.6 + 0.2 * layer)
		_ci.draw_colored_polygon(pts, c)
	var g: Color = pal[2]
	g.a = minf(1.0, bg_alpha + 0.3)
	_ci.draw_rect(Rect2(x0, size.y - 10, w, 3), g)


## Battlefield rectangle in canvas units: the 3D view renders here.
func _field_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(HUD_W, size.y - STRIP_H, minf(size.x - HUD_W, 820.0), STRIP_H)


## Move monsters toward their slots and mirror heroes and monsters into the 3D view.
func _update_view(delta: float) -> void:
	var ground := _ground()
	view.layout(_field_rect(), get_window().content_scale_factor, ground)
	view.begin_frame()
	for i in sim.fighters.size():
		var f: Dictionary = sim.fighters[i]
		view.hero(f.cls, Vector2(hero_x(i), ground), sim.heroes[f.cls], f.hp <= 0.0, _anim_hero(i).hurt > 0.0)
	var live := sim._alive_mobs()
	for k in live.size():
		var mob: Dictionary = sim.mobs[live[k]]
		var tx := _mob_target_x(k)
		var x: float = _mob_x.get(mob.uid, tx + 60.0)
		_mob_x[mob.uid] = move_toward(x, tx, 120.0 * delta)
		view.mob(mob, Vector2(_mob_x[mob.uid], ground), absf(_mob_x[mob.uid] - tx) > 1.0, _anim_mob(mob.uid).hurt > 0.0, _t)
	view.end_frame(delta)


func _draw_battlefield() -> void:
	var ground := _ground()
	# ground shadows and the armor rarity ring (Q15.1 B) go under the 3D view
	for i in sim.fighters.size():
		var feet := Vector2(hero_x(i), ground)
		_ci.draw_set_transform(feet, 0.0, Vector2(1.0, 0.3))
		_ci.draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.3))
		var armor = sim.heroes[sim.fighters[i].cls].equip.armor
		if armor != null:
			var ac: Color = D.RARITIES[armor.rarity].color
			ac.a = 0.6
			_ci.draw_arc(Vector2.ZERO, 22.0, 0, TAU, 32, ac, 3.0)
		_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var live := sim._alive_mobs()
	for m in live:
		var mob: Dictionary = sim.mobs[m]
		var feet := Vector2(_mob_x.get(mob.uid, 0.0), ground)
		_ci.draw_set_transform(feet, 0.0, Vector2(1.0, 0.3))
		_ci.draw_circle(Vector2.ZERO, 16.0 * mob.size * (1.0 if mob.act_boss else mob.scale), Color(0, 0, 0, 0.3))
		if mob.warn > 0.0:  # telegraph: pulsing red ring under the boss
			_ci.draw_arc(Vector2.ZERO, 40.0 + sin(_t * 20.0) * 4.0, 0, TAU, 24, Color(1, 0.2, 0.2, 0.8), 4.0)
		_ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_ci.draw_texture_rect(view.get_texture(), _field_rect(), false)
	# bars and names above heads
	for i in sim.fighters.size():
		var f: Dictionary = sim.fighters[i]
		var top := ground - view.px_height(f.cls) - 6.0
		var x := hero_x(i)
		if f.hp > 0.0:
			_bar(Vector2(x - 20, top), 40.0, f.hp / sim.stats(f.cls).hp, Color(0.3, 0.9, 0.4))
		else:
			text(Vector2(x - 4, top + 4), "%d" % ceili(f.dead_t), Color(1, 0.5, 0.5), 12)
	for m in live:
		var mob: Dictionary = sim.mobs[m]
		var x: float = _mob_x.get(mob.uid, 0.0)
		var top: float = ground - view.px_height(mob.uid) - (14.0 if mob.fly else 4.0)
		_bar(Vector2(x - 18, top), 36.0 if not mob.boss else 60.0, mob.hp / mob.max, Color(0.95, 0.3, 0.3))
		if mob.boss or mob.elite.size() > 0:
			var nm: String = mob.name
			text(Vector2(x - text_w(nm, 10) / 2.0, top - 3), nm, Color(1, 0.85, 0.4), 10)
	# effects and floating numbers on top
	for f in _fx:
		var p: float = f.t / f.loop
		var pos: Vector2 = f.pos
		if f.from != Vector2.INF:
			pos = f.from.lerp(f.pos, f.t / f.dur)
		Gfx.draw_fx(_ci, f.id, pos, p, f.scale, f.flip)
	for n in _nums:
		var c: Color = n.col
		c.a = 1.0 - n.t / 0.9
		text(n.pos + Vector2(0, -24.0 * n.t), n.text, c, 13)
	if _toast_left > 0.0:
		text(Vector2(HUD_W + 12, get_viewport_rect().size.y - STRIP_H + 18), _toast, Color.GOLD, 14)


func _bar(pos: Vector2, w: float, frac: float, col: Color) -> void:
	Ui.bar(_ci, pos, w, 5.0, frac, col)


func stage_text() -> String:
	var wave_txt := "Sóng %d/%d" % [sim.wave, sim.waves_in_stage()]
	if sim.is_boss_wave():
		wave_txt = "BOSS"
	match sim.mode:
		"zone": return "Vùng Hỗn Mang %d · %s" % [sim.zone_int, wave_txt]
		"tower": return "Tháp tầng %d · %s" % [sim.tower_floor, wave_txt]
	return "%s %d-%d · %s" % [D.DIFFS[sim.diff].name, sim.act(), sim.local_stage(), wave_txt]


func _draw_hud(top: float) -> void:
	Ui.frame(_ci, Rect2(2, top + 2, HUD_W - 4, STRIP_H - 4))
	# stage ribbon (opens the Portal), settings and quit
	button(Rect2(8, top + 7, 186, 24), stage_text(), toggle_panel.bind("portal"), "active" if panel == "portal" else "normal",
		sim.feature_unlocked("portal"), 11)
	button(Rect2(198, top + 7, 22, 24), "⚙", toggle_panel.bind("settings"), "active" if panel == "settings" else "normal", true, 11)
	button(Rect2(222, top + 7, 22, 24), "×", _quit, "danger", true, 12)
	# party portraits with level and HP
	for i in sim.party.size():
		var c: String = sim.party[i]
		var ctr := Vector2(28 + i * 44, top + 54)
		var f: Dictionary = sim.fighters[i] if i < sim.fighters.size() else {}
		var alive: bool = f.is_empty() or f.hp > 0.0
		Ui.medallion(_ci, ctr, 17.0, Ui.GOLD if alive else Color(0.5, 0.3, 0.3))
		var pt := Gfx.portrait(c, int(34 * get_window().content_scale_factor))
		if pt != null:
			_ci.draw_texture_rect(pt, Rect2(ctr - Vector2(17, 19), Vector2(34, 34)), false, Color.WHITE if alive else Color(0.45, 0.4, 0.45))
		text(ctr + Vector2(-17, 19), "%d" % sim.heroes[c].level, Ui.TEXT, 10)
		if not f.is_empty():
			Ui.bar(_ci, ctr + Vector2(-16, 22), 32.0, 4.0, f.hp / sim.stats(c).hp, Color(0.4, 0.9, 0.45))
	# gold, dps, chest timer, stones
	Ui.coin(_ci, Vector2(16, top + 91), 7.0)
	text(Vector2(26, top + 97), fmt(sim.gold), Ui.GOLD, 15)
	var next_chest := maxi(0, ceili(sim.chest_ready_at - Time.get_unix_time_from_system()))
	text(Vector2(8, top + 113), "DPS %s · rương %d:%02d" % [fmt(int(sim.team_dps())), next_chest / 60, next_chest % 60], Ui.TEXT_DIM, 10)
	for k in 5:
		Ui.gem(_ci, Vector2(13 + k * 27, top + 126), 5.0, Ui.GEMS[k])
		text(Vector2(20 + k * 27, top + 130), fmt(sim.stones[k]), Ui.TEXT, 9)
	# panel tabs and the chest
	var tabs := [["Túi %d" % sim.bag.size(), "bag", ""], ["Đội", "hero", "hero"], ["Rèn", "forge", "forge"], ["Rune", "rune", "rune"]]
	for i in tabs.size():
		var tb: Array = tabs[i]
		var ok: bool = tb[2] == "" or sim.feature_unlocked(tb[2])
		button(Rect2(148 + (i % 2) * 48, top + 36 + (i / 2) * 28, 46, 26), tb[0] if ok else "🔒", toggle_panel.bind(tb[1]),
			"active" if panel == tb[1] else "normal", ok, 11)
	button(Rect2(148, top + 94, 94, 26), "Rương x%d" % sim.chests, func(): sim.open_chest(), "chest", sim.chests > 0, 11)


static func fmt(n: int) -> String:
	if n >= 1_000_000_000:
		return "%.2fB" % (n / 1e9)
	if n >= 1_000_000:
		return "%.2fM" % (n / 1e6)
	if n >= 10_000:
		return "%.1fK" % (n / 1e3)
	return str(n)


func _quit() -> void:
	_save()
	get_tree().quit()


# =========================================================== music, save

func _update_music() -> void:
	var want := sim.act() - 1 if sim.mode == "campaign" else 2
	if not music_on:
		if music.playing:
			music.stop()
		_music_act = -1
		return
	if want != _music_act:
		_music_act = want
		music.stream = Music.build(want)
		music.volume_db = MUSIC_DB
		music.play()


func _save() -> void:
	var d := sim.to_dict()
	d["saved_at"] = Time.get_unix_time_from_system()
	d["ui"] = {"sound": sfx.mode, "music": music_on, "bg": bg_alpha}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return  # corrupt save: start fresh rather than crash
	var ui: Dictionary = d.get("ui", {})
	if ui.get("sound") in Sfx.MODES:
		sfx.mode = ui.sound
	music_on = bool(ui.get("music", true))
	bg_alpha = clampf(float(ui.get("bg", 0.35)), 0.0, 1.0)
	if not sim.from_dict(d):
		show_toast("Phiên bản mới: bắt đầu lại từ đầu")
		return
	var r := sim.apply_offline(Time.get_unix_time_from_system() - float(d.get("saved_at", 0.0)))
	if r.gold > 0:
		show_toast("Offline: +%s vàng, +%s EXP" % [fmt(r.gold), fmt(r.xp)])
