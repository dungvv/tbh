extends RefCounted
## Panels drawn above the HUD. Each takes the main node `m` and uses its immediate-mode widgets.

const D := preload("res://data.gd")
const Sim := preload("res://sim.gd")
const Art := preload("res://art.gd")
const Gfx := preload("res://gfx.gd")
const Ui := preload("res://ui.gd")

const WEAPON_ICONS := {"sword": "weapon_knight_sword", "bow": "weapon_bow", "staff": "weapon_red_magic_staff",
	"holy": "weapon_green_magic_staff", "axe": "weapon_waraxe", "dagger": "weapon_duel_sword"}
const STAT_LABELS := {"atk": "ATK", "hp": "Máu", "armor": "Giáp", "mres": "Kháng phép", "aspd_pct": "Tốc đánh",
	"crit": "Chí mạng", "atk_pct": "ATK"}


static func draw(m, name: String) -> void:
	match name:
		"bag": _bag(m)
		"hero": _hero(m)
		"forge": _forge(m)
		"rune": _rune(m)
		"portal": _portal(m)
		"settings": _settings(m)


# --------------------------------------------------------------- items

static func item_name(it: Dictionary) -> String:
	var base: String = D.SLOT_NAMES[it.slot]
	if it.slot == "weapon":
		base = D.WEAPON_NAMES.get(it.kind, base)
	elif it.slot == "armor":
		base = D.ARMOR_NAMES.get(it.kind, base)
	return "%s %s%s" % [base, D.RARITIES[it.rarity].vn, " +%d" % it.enh if it.enh > 0 else ""]


static func _fmt_stat(st: String, v: float) -> String:
	var a: Dictionary = D.AFFIXES.get(st, {})
	var label: String = a.get("name", STAT_LABELS.get(st, st))
	var pct: bool = a.get("pct", st in ["aspd_pct", "crit", "atk_pct"])
	return ("+%.1f%% %s" % [v * 100.0, label]) if pct else ("+%d %s" % [roundi(v), label])


static func item_icon(m, it, r: Rect2) -> void:
	if it == null:
		return
	var col: Color = D.RARITIES[it.rarity].color
	Ui.slot(m._ci, r, col, it.uid == m.sel_item)
	var pad := 3.0
	var inner := r.grow(-pad)
	if it.slot == "weapon":
		var t := Gfx.tex("res://art/0x72/%s.png" % WEAPON_ICONS.get(it.kind, "weapon_knight_sword"))
		if t != null:
			var s := minf(inner.size.y / t.get_height(), inner.size.x / t.get_width())
			var sz := t.get_size() * s
			m._ci.draw_texture_rect(t, Rect2(inner.get_center() - sz / 2.0, sz), false, Color.WHITE.lerp(col, 0.4))
	else:
		m._ci.draw_texture_rect(Art.tex("icon_" + it.slot), inner, false, col.lightened(0.2))
	if it.enh > 0:
		m.text(r.position + Vector2(1, r.size.y - 2), "+%d" % it.enh, Color.WHITE, 9)
	if it.get("locked", false):
		m._ci.draw_texture_rect(Art.tex("icon_lock"), Rect2(r.end - Vector2(9, r.size.y - 1), Vector2(8, 10)), false)


## Name, main stat and affix lines (colored by quality, MU style). Returns the y after the last line.
static func item_details(m, it: Dictionary, pos: Vector2, with_locks := false) -> float:
	var y := pos.y
	m.text(Vector2(pos.x, y + 14), item_name(it), D.RARITIES[it.rarity].color, 14)
	y += 20
	var k := 1.0 + Sim.enh_bonus(it.enh)
	for st in it.main:
		m.text(Vector2(pos.x, y + 13), _fmt_stat(st, it.main[st] * k), Color.WHITE, 12)
		y += 16
	for i in it.affixes.size():
		var a: Dictionary = it.affixes[i]
		var qc: Color = D.QUALITY_COLORS[clampi((a.q - 1) / 2, 0, 4)]
		var lx := pos.x
		if with_locks:
			m.button(Rect2(pos.x, y + 2, 14, 13), "", m.sim.toggle_lock.bind(it.uid, i), Color(0.5, 0.4, 0.1) if a.locked else Color(0.2, 0.2, 0.26))
			if a.locked:
				m._ci.draw_texture_rect(Art.tex("icon_lock"), Rect2(pos.x + 3, y + 3, 8, 10), false)
			lx += 18
		m.text(Vector2(lx, y + 13), "%s  [%d]" % [_fmt_stat(a.stat, a.val), a.q], qc, 12)
		y += 16
	if it.affixes.is_empty() and it.rarity < 2:
		m.text(Vector2(pos.x, y + 13), "Không có dòng phụ", Color(0.55, 0.55, 0.6), 11)
		y += 16
	return y


static func _wearer(m, uid: int) -> String:
	for c in m.sim.heroes:
		for s in D.SLOTS:
			var it = m.sim.heroes[c].equip[s]
			if it != null and it.uid == uid:
				return c
	return ""


static func _class_tabs(m, y: float, owned_only := true) -> void:
	var x := 10.0
	for c in D.CLASS_ORDER:
		if owned_only and not c in m.sim.owned:
			continue
		var on: bool = m.sel_class == c
		m.button(Rect2(x, y, 92, 20), D.CLASSES[c].name, func(): m.sel_class = c, Color(0.35, 0.35, 0.55) if on else Color(0.2, 0.2, 0.28), true, 11)
		x += 96


# --------------------------------------------------------------- bag

static func _bag(m) -> void:
	var sim = m.sim
	_class_tabs(m, 8)
	var cls: String = m.sel_class if m.sel_class in sim.owned else "knight"
	m.text(Vector2(10, 46), "Đang mặc:", Color(0.7, 0.7, 0.75), 11)
	for i in D.SLOTS.size():
		var s: String = D.SLOTS[i]
		var r := Rect2(70 + i * 40, 32, 34, 34)
		var it = sim.heroes[cls].equip[s]
		Ui.slot(m._ci, r, Color(0.45, 0.4, 0.55))
		if it == null:
			m._ci.draw_texture_rect(Art.tex("icon_" + s if s != "weapon" else "icon_weapon"), r.grow(-6), false, Color(1, 1, 1, 0.15))
		else:
			item_icon(m, it, r)
			m.area(r, func(): m.sel_item = it.uid)
	m.text(Vector2(320, 54), "Túi %d/%d" % [sim.bag.size(), sim.bag_cap()], Color.WHITE, 12)
	var cols := 15
	var cell := 30.0
	for i in mini(sim.bag.size(), cols * 7):
		var it: Dictionary = sim.bag[i]
		var r := Rect2(10 + (i % cols) * cell, 76 + (i / cols) * cell, cell - 3, cell - 3)
		item_icon(m, it, r)
		m.area(r, func(): m.sel_item = it.uid)
	var by := 296.0
	m.button(Rect2(10, by, 80, 24), "Sắp xếp", sim.sort_bag)
	var below: int = clampi(sim.auto_sell_below, 0, 4)
	m.button(Rect2(96, by, 150, 24), "Phân rã ≤ %s" % D.RARITIES[maxi(below, 0)].vn, func():
		m.show_toast("Phân rã %d món" % sim.dismantle_below(maxi(below, 0))))
	m.button(Rect2(252, by, 200, 24), "Ngưỡng: %s" % ("tắt" if sim.auto_sell_below < 0 else "≤ " + D.RARITIES[sim.auto_sell_below].vn),
		func(): sim.auto_sell_below = (sim.auto_sell_below + 2) % 6 - 1, Color(0.25, 0.25, 0.32), true, 11)
	if sim.rune_level("auto_sell") == 0:
		m.text(Vector2(258, by - 4), "tự phân rã cần rune Thương Nhân", Color(0.6, 0.6, 0.65), 9)
	# selected item
	var it: Dictionary = sim.find_item(m.sel_item)
	if it.is_empty():
		m.text(Vector2(480, 30), "Chọn một món để xem.", Color(0.7, 0.7, 0.75), 12)
		return
	var y: float = item_details(m, it, Vector2(480, 24))
	var wearer := _wearer(m, it.uid)
	y += 8
	if wearer != "":
		m.text(Vector2(480, y + 12), "Đang mặc: %s" % D.CLASSES[wearer].name, Color(0.6, 0.85, 0.6), 11)
		m.button(Rect2(480, y + 20, 90, 24), "Tháo", func(): sim.unequip(wearer, it.slot))
	else:
		var ok: bool = sim.can_wear(cls, it)
		m.button(Rect2(480, y + 20, 150, 24), "Mặc cho %s" % D.CLASSES[cls].name, func(): sim.equip(cls, it.uid), Color(0.2, 0.45, 0.3), ok)
		if not ok:
			m.text(Vector2(636, y + 37), "class khác", Color(0.7, 0.5, 0.5), 10)
		m.button(Rect2(480, y + 50, 90, 24), "Mở khóa" if it.locked else "Khóa", func(): it.locked = not it.locked)
		m.button(Rect2(576, y + 50, 150, 24), "Phân rã +%d vàng" % Sim.item_gold(it), func(): sim.dismantle(it.uid), Color(0.45, 0.2, 0.2), not it.locked, 11)
	m.button(Rect2(480, y + 80, 90, 24), "Rèn", func(): m.toggle_panel("forge"), Color(0.3, 0.3, 0.45), sim.feature_unlocked("forge"))


# --------------------------------------------------------------- hero / skills

static func _hero(m) -> void:
	var sim = m.sim
	m.text(Vector2(10, 18), "Đội hình (trước → sau):", Color(0.75, 0.75, 0.8), 11)
	for i in D.PARTY_SLOTS:
		var r := Rect2(150 + i * 110, 4, 104, 22)
		var open: bool = i < sim.party_size()
		var lab: String = D.CLASSES[sim.party[i]].name if i < sim.party.size() else ("Trống" if open else "🔒 Rune")
		var col := Color(0.45, 0.4, 0.15) if m.sel_party_slot == i else Color(0.22, 0.22, 0.3)
		m.button(r, "%d. %s" % [i + 1, lab], func(): m.sel_party_slot = i, col, open, 11)
	if m.sel_party_slot >= 0:
		m.text(Vector2(490, 18), "Chọn class bên dưới để đặt vào ô %d" % (m.sel_party_slot + 1), Color.GOLD, 11)
	# class list
	for k in D.CLASS_ORDER.size():
		var c: String = D.CLASS_ORDER[k]
		var cd: Dictionary = D.CLASSES[c]
		var r := Rect2(10, 36 + k * 44, 200, 40)
		var owned: bool = c in sim.owned
		Ui.card(m._ci, r, m.sel_class == c)
		var pt := Gfx.portrait(c, int(38 * m.get_window().content_scale_factor))
		if pt != null:
			m._ci.draw_texture_rect(pt, Rect2(r.position.x + 1, r.position.y + 1, 38, 38), false, Color.WHITE if owned else Color(0.3, 0.3, 0.3))
		m.text(Vector2(r.position.x + 40, r.position.y + 16), cd.name, Color.WHITE if owned else Color(0.55, 0.55, 0.6), 13)
		m.text(Vector2(r.position.x + 40, r.position.y + 32), ("Lv %d · %s" % [sim.heroes[c].level, cd.role]) if owned else
			"Mở bằng rune %s" % Sim.rune_def(cd.unlock).name, Color(0.7, 0.7, 0.75), 10)
		m.area(r, func():
			m.sel_class = c
			if m.sel_party_slot >= 0 and owned:
				sim.set_party_slot(m.sel_party_slot, c)
				m.sel_party_slot = -1)
	var cls: String = m.sel_class
	var h: Dictionary = sim.heroes[cls]
	var s: Dictionary = sim.stats(cls)
	var x := 220.0
	m.text(Vector2(x, 46), "%s Lv %d/%d" % [D.CLASSES[cls].name, h.level, D.LEVEL_CAP], Color.WHITE, 14)
	m._bar(Vector2(x, 52), 180.0, float(h.xp) / sim.exp_to_next(h.level), Color(0.4, 0.6, 1.0))
	m.button(Rect2(x + 190, 36, 90, 20), "Trang phục %d" % (h.outfit + 1), func():
		h.outfit = (h.outfit + 1) % 2, Color(0.25, 0.25, 0.32), true, 10)  # Q15.4 B: outfit layer
	var lines := [["Máu", "%d" % s.hp], ["ATK", "%d" % s.atk], ["Giáp", "%d" % s.armor], ["Kháng phép", "%d" % s.mres],
		["Tốc đánh", "%.2f/s" % s.aspd], ["Chí mạng", "%d%%" % roundi(s.crit * 100)], ["ST chí mạng", "%d%%" % roundi(s.critdmg * 100)],
		["Chặn / Né", "%d%% / %d%%" % [roundi(s.block * 100), roundi(s.dodge * 100)]], ["Loại ST", "Phép" if s.dmg == "magic" else "Vật lý"]]
	for i in lines.size():
		m.text(Vector2(x, 76 + i * 16), lines[i][0], Color(0.7, 0.7, 0.75), 11)
		m.text(Vector2(x + 80, 76 + i * 16), lines[i][1], Color.WHITE, 11)
	# skills
	var sx := 400.0
	var pts: int = sim.skill_points(cls)
	m.text(Vector2(sx, 74), "Điểm skill: %d  (5 điểm mỗi level, tối đa 25 mỗi skill)" % pts, Color.GOLD, 11)
	m.button(Rect2(PANEL_W() - 90, 60, 80, 20), "Tẩy điểm", func(): sim.reset_skills(cls), Color(0.4, 0.25, 0.2), true, 10)
	var rows: Array = D.SKILLS[cls] + D.PASSIVES
	for i in rows.size():
		var sk: Dictionary = rows[i]
		var y := 84.0 + i * 25
		var lv: int = h.skills.get(sk.id, 0)
		var active: bool = i < D.SKILLS[cls].size()
		var can: bool = sim.can_learn(cls, sk.id)
		var locked: bool = sim.points_spent(cls) < sk.get("req", 0)
		Ui.card(m._ci, Rect2(sx, y, 380, 22), false, Color(0.1, 0.08, 0.15, 0.0 if active else 0.5))
		m.text(Vector2(sx + 4, y + 15), sk.name, Color.WHITE if not locked else Color(0.5, 0.5, 0.55), 12)
		m.text(Vector2(sx + 110, y + 15), "%d/25" % lv, Color(0.8, 0.8, 0.85), 11)
		var desc := _skill_desc(sim, cls, sk, maxi(lv, 1)) if not locked else "cần %d điểm đã dùng" % sk.req
		m.text(Vector2(sx + 152, y + 15), desc, Color(0.65, 0.75, 0.9) if lv > 0 else Color(0.55, 0.55, 0.6), 10)
		m.button(Rect2(sx + 316, y + 2, 28, 18), "+1", func(): sim.learn(cls, sk.id, 1), Color(0.2, 0.4, 0.3), can, 10)
		m.button(Rect2(sx + 348, y + 2, 28, 18), "+5", func(): sim.learn(cls, sk.id, 5), Color(0.2, 0.4, 0.3), can, 10)


static func PANEL_W() -> float:
	return 800.0


static func _skill_desc(sim, cls: String, sk: Dictionary, lv: int) -> String:
	if not sk.has("kind"):
		var v: float = sk.per * lv
		return ("+%.1f%%" % (v * 100.0)) if sk.stat != "mres" else ("+%.1f" % v)
	var v: float = sk.base + sk.per * (lv - 1)
	var trig: String = ("mỗi %d đòn" % sk.n) if sk.trigger == "hits" else (("hồi %ds" % sk.n) if sk.trigger == "cd" else "nội tại")
	match sk.kind:
		"dmg": return "%d%% ST, %s" % [roundi(v * 100), trig]
		"aoe": return "%d%% ST cả sóng, %s" % [roundi(v * 100), trig]
		"multi": return "%d × %d%% ST, %s" % [sk.hits, roundi(v * 100), trig]
		"execute": return "%d%% chí mạng chắc, %s" % [roundi(v * 100), trig]
		"heal": return "hồi %d%% ATK, %s" % [roundi(v * 100), trig]
		"revive": return "hồi sinh %d%% máu, %s" % [roundi(minf(v, 1.0) * 100), trig]
		"buff": return "+%d%% trong %ds, %s" % [roundi(v * 100), sk.dur, trig]
		"berserk": return "tới +%d%% ATK khi máu thấp" % roundi(v * 100)
	return trig


# --------------------------------------------------------------- forge

static func _forge(m) -> void:
	var sim = m.sim
	var it: Dictionary = sim.find_item(m.sel_item)
	if it.is_empty():
		m.text(Vector2(12, 30), "Chọn một món trong Túi (hoặc đồ đang mặc) rồi bấm Rèn.", Color(0.75, 0.75, 0.8), 13)
		m.button(Rect2(12, 44, 100, 24), "Mở Túi", func(): m.toggle_panel("bag"))
		return
	item_icon(m, it, Rect2(12, 12, 44, 44))
	item_details(m, it, Vector2(66, 8))
	# enhancement
	var x := 300.0
	m.text(Vector2(x, 22), "Cường hóa (+%d/%d)" % [it.enh, D.ENH_MAX], Color.WHITE, 14)
	if it.enh >= D.ENH_MAX:
		m.text(Vector2(x, 44), "Đã tối đa.", Color.GOLD, 12)
	else:
		m.text(Vector2(x, 44), "Đá:", Color(0.7, 0.7, 0.75), 11)
		for i in 5:
			var on: bool = m.forge_stone == i + 1
			m.button(Rect2(x + 28 + i * 52, 30, 48, 20), "C%d ×%d" % [i + 1, sim.stones[i]], func(): m.forge_stone = i + 1,
				Color(0.25, 0.4, 0.6) if on else Color(0.2, 0.2, 0.28), true, 10)
		m.text(Vector2(x, 72), "Số viên:", Color(0.7, 0.7, 0.75), 11)
		for n in range(1, 4):
			m.button(Rect2(x + 56 + (n - 1) * 30, 58, 26, 20), str(n), func(): m.forge_count = n,
				Color(0.25, 0.4, 0.6) if m.forge_count == n else Color(0.2, 0.2, 0.28), true, 11)
		var risky: bool = it.enh + 1 >= 7
		if risky:
			m.button(Rect2(x + 160, 58, 200, 20), ("☑" if m.forge_protect else "☐") + " Bảo vệ bằng vàng +%s" % m.fmt(sim.protect_cost(it)),
				func(): m.forge_protect = not m.forge_protect, Color(0.3, 0.25, 0.15), true, 10)
		var chance: float = sim.enh_chance(it, m.forge_stone, m.forge_count)
		var cost: int = sim.enh_cost(it) + (sim.protect_cost(it) if risky and m.forge_protect else 0)
		var floor_txt := "" if not risky or m.forge_protect else " · thất bại lùi về +%d" % maxi(it.enh - 1, Sim.enh_floor(it.enh))
		m.text(Vector2(x, 98), "Tỉ lệ %d%% (pity +%d%%) · giá %s vàng%s" % [roundi(chance * 100), roundi(it.pity * 100), m.fmt(cost), floor_txt],
			Color(0.85, 0.85, 0.9), 11)
		var have: bool = sim.stones[m.forge_stone - 1] >= m.forge_count and sim.gold >= cost
		m.button(Rect2(x, 106, 140, 26), "Cường hóa", func():
			var r: Dictionary = sim.enhance(it.uid, m.forge_stone, m.forge_count, risky and m.forge_protect)
			if r.is_empty():
				return
			m.sfx.play("success" if r.ok else "fail")
			m.show_toast(("Thành công: +%d" % r.enh) if r.ok else ("Thất bại%s" % (", lùi về +%d" % r.enh if r.dropped else ""))),
			Color(0.2, 0.5, 0.3), have)
	# reroll and lock (Q11)
	if not sim.feature_unlocked("reroll"):
		m.text(Vector2(x, 160), "Tẩy dòng mở ở Act 2.", Color(0.6, 0.6, 0.65), 11)
		return
	if it.affixes.is_empty():
		m.text(Vector2(x, 160), "Món này không có dòng phụ để tẩy (cần phẩm Hiếm trở lên).", Color(0.6, 0.6, 0.65), 11)
		return
	m.text(Vector2(x, 160), "Tẩy dòng — bấm ô vuông để khóa dòng (giá ×2 mỗi dòng khóa)", Color.WHITE, 12)
	var y := 170.0
	for i in it.affixes.size():
		var a: Dictionary = it.affixes[i]
		var qc: Color = D.QUALITY_COLORS[clampi((a.q - 1) / 2, 0, 4)]
		m.button(Rect2(x, y + 2, 14, 14), "", sim.toggle_lock.bind(it.uid, i), Color(0.5, 0.4, 0.1) if a.locked else Color(0.2, 0.2, 0.26))
		if a.locked:
			m._ci.draw_texture_rect(Art.tex("icon_lock"), Rect2(x + 3, y + 4, 8, 10), false)
		m.text(Vector2(x + 20, y + 14), "%s  [%d]" % [_fmt_stat(a.stat, a.val), a.q], qc, 12)
		var c1: int = sim.reroll_cost(it, it.affixes.size() - 1)
		m.button(Rect2(x + 270, y, 200, 18), "Tẩy riêng dòng này · %s" % m.fmt(c1), func(): sim.reroll(it.uid, i), Color(0.3, 0.25, 0.45),
			sim.gold >= c1, 10)
		y += 22
	var c_all: int = sim.reroll_cost(it, sim.locked_count(it))
	var can_all: bool = sim.locked_count(it) < it.affixes.size() and sim.gold >= c_all
	m.button(Rect2(x, y + 6, 260, 24), "Tẩy các dòng chưa khóa · %s vàng" % m.fmt(c_all), func(): sim.reroll(it.uid), Color(0.35, 0.25, 0.5), can_all, 11)


# --------------------------------------------------------------- runes

static func _rune_rect(r: Dictionary) -> Rect2:
	return Rect2(14 + r.at[0] * 110, 24 + r.at[1] * 44, 22, 22)


static func _rune(m) -> void:
	var sim = m.sim
	m.text(Vector2(10, 16), "Cây rune · Vàng %s" % m.fmt(sim.gold), Color.GOLD, 12)
	for r in D.RUNES:
		if r.req == "":
			continue
		var a := _rune_rect(Sim.rune_def(r.req))
		var b := _rune_rect(r)
		var mid := a.end.x + (b.position.x - a.end.x) / 2.0
		var col := Color(0.75, 0.75, 0.85) if sim.rune_level(r.req) > 0 else Color(0.3, 0.3, 0.36)
		m._ci.draw_polyline(PackedVector2Array([Vector2(a.end.x, a.position.y + 11), Vector2(mid, a.position.y + 11),
			Vector2(mid, b.position.y + 11), Vector2(b.position.x, b.position.y + 11)]), col, 2.0)
	for r in D.RUNES:
		var rect := _rune_rect(r)
		var lv: int = sim.rune_level(r.id)
		var fill := Color(0.3, 0.27, 0.36)
		if Sim.is_maxed(r, lv):
			fill = Ui.GOLD
		elif sim.can_buy_rune(r.id):
			fill = Color(0.35, 0.62, 1.0)
		elif sim.rune_unlocked(r.id):
			fill = Color(0.3, 0.38, 0.6)
		Ui.gem(m._ci, rect.get_center(), 11.0 if r.id == m.sel_rune else 9.0, fill)
		if r.id == m.sel_rune:
			m._ci.draw_arc(rect.get_center(), 13.0, 0, TAU, 24, Color.WHITE, 1.5, true)
		var badge: String = ("%d" % lv) if r.max != 1 else ("✓" if lv > 0 else "")
		if badge != "":
			m.text(rect.position + Vector2(15, 25), badge, Ui.GOLD if Sim.is_maxed(r, lv) else Ui.TEXT, 9)
		var lw: float = m.text_w(r.name, 11)
		Ui.card(m._ci, Rect2(rect.position + Vector2(24, 2), Vector2(lw + 8, 18)))  # covers the link line behind the name
		m.text(rect.position + Vector2(28, 15), r.name, Ui.TEXT if sim.rune_unlocked(r.id) else Ui.TEXT_DIM, 11)
		m.area(Rect2(rect.position, Vector2(100, 22)), func(): m.sel_rune = r.id)
	var s := Sim.rune_def(m.sel_rune)
	var lv: int = sim.rune_level(m.sel_rune)
	var desc: String = s.fmt if s.per == 0 else s.fmt % (s.per * maxi(lv, 1))
	var info := "%s (%s): %s" % [s.name, ("%d/%d" % [lv, s.max]) if s.max > 0 else "cấp %d, không giới hạn" % lv, desc]
	if not Sim.is_maxed(s, lv):
		info += " · giá %s vàng" % m.fmt(sim.rune_cost(m.sel_rune))
		if not sim.rune_unlocked(m.sel_rune):
			info += " · cần %s" % Sim.rune_def(s.req).name
	m.text(Vector2(10, 300), info, Color(0.85, 0.85, 0.85), 12)
	m.button(Rect2(PANEL_W() - 120, 290, 110, 26), "Nâng", func(): sim.buy_rune(m.sel_rune), Color(0.2, 0.5, 0.25), sim.can_buy_rune(m.sel_rune))


# --------------------------------------------------------------- portal

static func _portal(m) -> void:
	var sim = m.sim
	for d in 4:
		var open: bool = sim.max_stage[d] > 0
		m.button(Rect2(10 + d * 110, 6, 104, 22), D.DIFFS[d].name if open else "🔒 " + D.DIFFS[d].name,
			func(): m.sel_portal_diff = d, Color(0.35, 0.35, 0.55) if m.sel_portal_diff == d else Color(0.2, 0.2, 0.28), open, 11)
	var d: int = m.sel_portal_diff
	m.text(Vector2(460, 22), "Level màn %d – %d · kháng phép −%d" % [D.DIFFS[d].lv[0], D.DIFFS[d].lv[1], D.DIFFS[d].mres_pen], Color(0.7, 0.8, 1.0), 11)
	for a in 3:
		m.text(Vector2(10, 52 + a * 34), D.ACT_NAMES[a], Color.WHITE, 12)
		for k in 10:
			var st := a * 10 + k + 1
			var here: bool = sim.mode == "campaign" and sim.diff == d and sim.stage == st
			var open: bool = st <= sim.max_stage[d]
			var col := Color(0.85, 0.6, 0.15) if here else (Color(0.2, 0.4, 0.75) if open else Color(0.18, 0.18, 0.22))
			m.button(Rect2(90 + k * 46, 36 + a * 34, 42, 28), "%d-%d" % [a + 1, k + 1], func():
				sim.go_to(d, st)
				m.show_toast("Đến %s %d-%d (Lv %d)" % [D.DIFFS[d].name, a + 1, k + 1, sim.stage_level()]), col, open, 11)
	m.button(Rect2(10, 144, 150, 24), "Lặp màn: %s" % ("Bật" if sim.repeat else "Tắt"), func(): sim.repeat = not sim.repeat,
		Color(0.2, 0.5, 0.25) if sim.repeat else Color(0.25, 0.25, 0.32))
	# endgame
	m.text(Vector2(10, 196), "Vùng Hỗn Mang (cường độ 1–20)", Color(0.85, 0.6, 1.0), 12)
	var zone_ok: bool = sim.feature_unlocked("zone")
	if zone_ok:
		for i in range(1, sim.zone_max + 1):
			if i > 20:
				break
			m.button(Rect2(10 + (i - 1) * 28, 204, 24, 22), str(i), sim.go_zone.bind(i), Color(0.4, 0.25, 0.55), true, 10)
	else:
		m.text(Vector2(230, 196), "mở khi qua Ác Mộng 1-10", Color(0.6, 0.6, 0.65), 10)
	m.text(Vector2(600, 196), "Tháp vô tận", Color(1.0, 0.75, 0.4), 12)
	m.button(Rect2(600, 204, 180, 22), "Tầng %d (kỷ lục %d)" % [sim.tower_best + 1, sim.tower_best], sim.go_tower, Color(0.45, 0.3, 0.15),
		sim.feature_unlocked("tower"), 11)


# --------------------------------------------------------------- settings

static func _settings(m) -> void:
	var modes := {"on": "bật", "low": "nhỏ", "off": "tắt"}
	m.button(Rect2(10, 10, 180, 24), "Âm thanh: %s" % modes[m.sfx.mode], func(): m.sfx.cycle_mode())
	m.button(Rect2(200, 10, 180, 24), "Nhạc nền: %s" % ("bật" if m.music_on else "tắt"), func():
		m.music_on = not m.music_on
		m._update_music())
	m.text(Vector2(10, 62), "Độ đậm nền: %d%%" % roundi(m.bg_alpha * 100), Color.WHITE, 12)
	m.button(Rect2(150, 48, 30, 22), "−", func(): m.bg_alpha = maxf(0.0, m.bg_alpha - 0.1))
	m.button(Rect2(186, 48, 30, 22), "+", func(): m.bg_alpha = minf(1.0, m.bg_alpha + 0.1))
	m.text(Vector2(10, 100), "Nhân vật 3D: KayKit, Quaternius (CC0). Icon: 0x72 (CC0). Hiệu ứng: pixelfx (MIT). Âm thanh, nhạc: tạo bằng code.", Color(0.6, 0.6, 0.65), 11)
