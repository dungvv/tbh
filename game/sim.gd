extends RefCounted
## Game rules, no rendering. Numbers live in data.gd. The UI reads state and `events`, and calls the action functions.

const D := preload("res://data.gd")
const SAVE_VERSION := 2

# --- persistent state ---
var gold := 0
var stones := [0, 0, 0, 0, 0]  # enhancement stones level 1..5
var chests := 0
var chest_ready_at := 0.0  # unix time; chests only drop while the game runs (Q2.1 A)
var pity_chests := 0  # chests opened since the last Immortal (Q7.5 note)
var owned := ["knight"]
var heroes := {}  # cls -> {cls, level, xp, skills, equip, outfit}
var party := ["knight"]  # formation, front to back
var bag := []  # unique items (Q7.6 B)
var next_uid := 1
var runes := {}
var auto_sell_below := -1  # rarity index; drops at or below are dismantled when the rune is owned
var diff := 0
var stage := 1
var max_stage := [1, 0, 0, 0]  # highest unlocked stage per difficulty, 0 = locked
var repeat := false
var first_kills := {}
var mode := "campaign"  # campaign | zone | tower
var zone_int := 1
var zone_max := 1
var tower_floor := 1
var tower_best := 0
var kills := 0

# --- battle state (not saved) ---
var wave := 1
var fighters := []  # one per party slot
var mobs := []
var events := []
var rng := RandomNumberGenerator.new()
var _uid := 0
var _stats_cache := {}


func _init() -> void:
	rng.randomize()
	for c in D.CLASS_ORDER:
		heroes[c] = _new_hero(c)
	_reset_fighters()


static func _new_hero(cls: String) -> Dictionary:
	var eq := {}
	for s in D.SLOTS:
		eq[s] = null
	return {"cls": cls, "level": 1, "xp": 0, "skills": {}, "equip": eq, "outfit": 0}


func _emit(e: Dictionary) -> void:
	events.append(e)
	if events.size() > 200:
		events.pop_front()


func _dirty() -> void:
	_stats_cache.clear()


# =========================================================== runes

static func rune_def(id: String) -> Dictionary:
	for r in D.RUNES:
		if r.id == id:
			return r
	return {}


static func is_maxed(r: Dictionary, lv: int) -> bool:
	return r.max > 0 and lv >= r.max


func rune_level(id: String) -> int:
	return runes.get(id, 0)


func rv(id: String) -> float:
	return rune_def(id).per * rune_level(id)


func rune_cost(id: String) -> int:
	var r := rune_def(id)
	if r.max == 0:  # uncapped runes: polynomial price, so gold keeps buying power for weeks instead of stalling
		return int(r.cost * pow(1.0 + rune_level(id), r.grow))
	return int(r.cost * pow(r.grow, rune_level(id)))


func rune_unlocked(id: String) -> bool:
	var req: String = rune_def(id).req
	return req == "" or rune_level(req) > 0


func can_buy_rune(id: String) -> bool:
	return rune_unlocked(id) and not is_maxed(rune_def(id), rune_level(id)) and gold >= rune_cost(id)


func buy_rune(id: String) -> bool:
	if not can_buy_rune(id):
		return false
	gold -= rune_cost(id)
	runes[id] = rune_level(id) + 1
	for c in D.CLASS_ORDER:  # Q4.7 A: classes open through runes
		if D.CLASSES[c].unlock == id and not c in owned:
			owned.append(c)
			if party.size() < party_size():
				party.append(c)
	while party.size() < party_size() and party.size() < owned.size():
		for c in owned:
			if not c in party:
				party.append(c)
				break
	_dirty()
	_reset_fighters()
	return true


func party_size() -> int:
	return 1 + rune_level("command") + rune_level("command2")


func set_party_slot(i: int, cls: String) -> bool:
	if i >= party_size() or not cls in owned or i > party.size():
		return false
	var j := party.find(cls)
	if i == party.size():
		if j >= 0:
			return false
		party.append(cls)
	elif j >= 0:  # swap positions
		party[j] = party[i]
		party[i] = cls
	else:
		party[i] = cls
	_reset_fighters()
	return true


# =========================================================== progression helpers

func act() -> int:
	return (stage - 1) / D.STAGES_PER_ACT + 1


func local_stage() -> int:
	return (stage - 1) % D.STAGES_PER_ACT + 1


func stage_level(d := -1, s := -1) -> int:
	if mode == "zone":
		return D.DIFFS[zone_diff()].lv[1]
	if mode == "tower":
		return 10 + 2 * tower_floor
	d = diff if d < 0 else d
	s = stage if s < 0 else s
	var lv: Array = D.DIFFS[d].lv
	return roundi(lv[0] + (lv[1] - lv[0]) * (s - 1) / float(D.STAGES - 1))


func waves_in_stage() -> int:
	return D.WAVES if mode == "campaign" else 5


func is_boss_wave() -> bool:
	return wave > waves_in_stage()


func is_act_boss_stage() -> bool:
	return mode != "campaign" or local_stage() == D.STAGES_PER_ACT


func feature_unlocked(name: String) -> bool:
	if name == "zone":
		return max_stage[1] > 10
	if name == "tower":
		return max_stage[1] > 0
	return max_stage[0] >= D.UNLOCK_AT.get(name, 0) or max_stage[1] > 0


func zone_diff() -> int:
	var d := 1
	for i in range(1, 4):
		if max_stage[i] > 10:
			d = i
	return d


func go_to(d: int, s: int) -> bool:
	if d < 0 or d > 3 or s < 1 or s > max_stage[d]:
		return false
	mode = "campaign"
	diff = d
	stage = s
	_start_stage()
	return true


func go_zone(intensity: int) -> bool:
	if not feature_unlocked("zone") or intensity < 1 or intensity > zone_max:
		return false
	mode = "zone"
	zone_int = intensity
	_start_stage()
	return true


func go_tower() -> bool:
	if not feature_unlocked("tower"):
		return false
	mode = "tower"
	tower_floor = tower_best + 1
	_start_stage()
	return true


func _start_stage() -> void:
	wave = 1
	mobs.clear()
	_dirty()
	_reset_fighters()
	_emit({"t": "stage"})


# =========================================================== hero stats

func exp_to_next(level: int) -> int:
	return int(D.LEVEL_EXP0 * pow(D.LEVEL_EXP_GROWTH, level - 1))


func skill_points(cls: String) -> int:
	var h: Dictionary = heroes[cls]
	var spent := 0
	for v in h.skills.values():
		spent += v
	return D.SKILL_POINTS_PER_LEVEL * h.level - spent


func points_spent(cls: String) -> int:
	var n := 0
	for v in heroes[cls].skills.values():
		n += v
	return n


func skill_def(cls: String, id: String) -> Dictionary:
	for s in D.SKILLS[cls]:
		if s.id == id:
			return s
	for p in D.PASSIVES:
		if p.id == id:
			return p
	return {}


func can_learn(cls: String, id: String) -> bool:
	var s := skill_def(cls, id)
	if s.is_empty() or skill_points(cls) <= 0 or heroes[cls].skills.get(id, 0) >= D.SKILL_MAX:
		return false
	return points_spent(cls) >= s.get("req", 0)


func learn(cls: String, id: String, n := 1) -> int:
	var done := 0
	while done < n and can_learn(cls, id):
		heroes[cls].skills[id] = heroes[cls].skills.get(id, 0) + 1
		done += 1
	if done > 0:
		_dirty()
	return done


func reset_skills(cls: String) -> void:
	heroes[cls].skills = {}
	_dirty()


func skill_value(cls: String, id: String) -> float:
	var pts: int = heroes[cls].skills.get(id, 0)
	if pts <= 0:
		return 0.0
	var s := skill_def(cls, id)
	return s.base + s.per * (pts - 1)


static func enh_bonus(enh: int) -> float:
	var b := 0.0
	for i in enh:
		b += D.ENH_STEP[i]
	return b


static func item_stats(it) -> Dictionary:
	var out := {}
	if it == null:
		return out
	var k := 1.0 + enh_bonus(it.enh)
	for st in it.main:
		out[st] = out.get(st, 0.0) + it.main[st] * k
	for a in it.affixes:
		out[a.stat] = out.get(a.stat, 0.0) + a.val
	return out


## Final combat stats of a class, damage buckets per Q5.1 A: add inside a bucket, multiply across buckets.
func stats(cls: String) -> Dictionary:
	if _stats_cache.has(cls):
		return _stats_cache[cls]
	var c: Dictionary = D.CLASSES[cls]
	var h: Dictionary = heroes[cls]
	var lv: int = h.level
	var add := {}
	for s in D.SLOTS:
		var st := item_stats(h.equip[s])
		for k in st:
			add[k] = add.get(k, 0.0) + st[k]
	for p in D.PASSIVES:
		var pts: int = h.skills.get(p.id, 0)
		if pts > 0:
			add[p.stat] = add.get(p.stat, 0.0) + p.per * pts
	var g := func(k): return add.get(k, 0.0)
	var rune_atk := (rv("growth") + rv("might") + rv("mastery")) / 100.0
	var s := {
		"cls": cls, "dmg": c.dmg, "range": c.range, "level": lv,
		"hp": (c.hp + c.g_hp * (lv - 1) + g.call("hp")) * (1.0 + g.call("hp_pct") + (rv("vitality") + rv("bulwark")) / 100.0),
		"atk": (c.atk + c.g_atk * (lv - 1) + g.call("atk")) * (1.0 + g.call("atk_pct")) * (1.0 + rune_atk),
		"armor": (c.armor + c.g_armor * (lv - 1) + g.call("armor")) * (1.0 + g.call("armor_pct") + (rv("guard") + rv("bulwark")) / 100.0),
		"mres": minf(D.MRES_CAP, c.mres + g.call("mres") - (D.DIFFS[diff].mres_pen if mode == "campaign" else D.DIFFS[zone_diff()].mres_pen)),
		"aspd": c.aspd * (1.0 + g.call("aspd_pct") + rv("haste") / 100.0),
		"crit": minf(D.CRIT_CAP, c.crit + g.call("crit")),
		"critdmg": c.critdmg + g.call("critdmg"),
		"block": minf(D.BLOCK_CAP, c.get("block", 0.0) + g.call("block")),
		"dodge": minf(D.DODGE_CAP, c.get("dodge", 0.0)),
		"dmg_reduce": minf(D.DMG_REDUCE_CAP, g.call("dmg_reduce")),
		"lifesteal": c.get("lifesteal", 0.0),
		"skill_dmg": g.call("skill_dmg"),
		"dmg_boss": g.call("dmg_boss"),
		"gold": g.call("gold"), "exp": g.call("exp"), "mf": g.call("mf"),
	}
	_stats_cache[cls] = s
	return s


func team_gold_mult() -> float:
	var m := 1.0 + rv("greed") / 100.0
	for c in party:
		m += stats(c).gold
	return m


func team_mf() -> float:
	var m := rv("luck") / 100.0
	for c in party:
		m += stats(c).mf
	return m


## Expected damage per second of the party, skills roughly included. Used for offline rewards and the HUD.
func team_dps() -> float:
	var dps := 0.0
	for c in party:
		var s := stats(c)
		dps += s.atk * s.aspd * (1.0 + s.crit * (s.critdmg - 1.0)) * (1.0 + 0.35 * (1.0 + s.skill_dmg))
	return dps


# =========================================================== damage (Q6)

## TBH armor: A² / (A² + (14L + 12)(A + 0.4 D)), capped at 75%.
static func armor_reduction(armor: float, level: int, dmg: float) -> float:
	if armor <= 0.0:
		return 0.0
	var a2 := armor * armor
	return minf(D.ARMOR_CAP, a2 / (a2 + (14.0 * level + 12.0) * (armor + 0.4 * dmg)))


## One hit, following the steps in Q6.A. att/def are stat dictionaries. Returns {dmg, crit, dodged, blocked}.
func hit(att: Dictionary, def: Dictionary, mult: float, is_skill: bool, level: int, force_crit := false) -> Dictionary:
	var r := {"dmg": 0, "crit": false, "dodged": false, "blocked": false}
	if rng.randf() < def.get("dodge", 0.0):
		r.dodged = true
		return r
	var d: float = att.atk * mult * (1.0 + (att.get("skill_dmg", 0.0) if is_skill else 0.0))
	if force_crit or rng.randf() < att.get("crit", 0.0):
		d *= att.get("critdmg", 1.5)
		r.crit = true
	if def.get("boss", false):
		d *= 1.0 + att.get("dmg_boss", 0.0)
	if att.dmg == "magic":
		d *= 1.0 - clampf(def.get("mres", 0.0), -100.0, D.MRES_CAP) / 100.0
	else:
		d *= 1.0 - armor_reduction(def.get("armor", 0.0), level, d)
	d *= 1.0 - def.get("dmg_reduce", 0.0)
	if rng.randf() < def.get("block", 0.0):
		d *= 1.0 - D.BLOCK_POWER
		r.blocked = true
	r.dmg = maxi(1, int(d))  # Q6.7 B
	return r


# =========================================================== fighters and buffs

func _reset_fighters() -> void:
	fighters.clear()
	for i in party.size():
		var s := stats(party[i])
		var cds := {}
		for sk in D.SKILLS[party[i]]:
			cds[sk.id] = sk.n * 0.5 if sk.trigger == "cd" else 0.0
		fighters.append({"cls": party[i], "hp": s.hp, "cd": rng.randf() * 0.5, "attacks": 0, "cds": cds,
			"buffs": [], "dead_t": 0.0})


func fighter_stats(i: int) -> Dictionary:
	var f: Dictionary = fighters[i]
	var s: Dictionary = stats(f.cls).duplicate()
	for b in f.buffs:
		match b.stat:
			"atk_pct": s.atk *= 1.0 + b.v
			"aspd_pct": s.aspd *= 1.0 + b.v
			"dmg_reduce": s.dmg_reduce = minf(D.DMG_REDUCE_CAP, s.dmg_reduce + b.v)
			"dodge": s.dodge = minf(D.DODGE_CAP, s.dodge + b.v)
	var berserk := skill_value(f.cls, "b_blood")
	if berserk > 0.0:  # stronger the lower the HP
		s.atk *= 1.0 + berserk * (1.0 - f.hp / s.hp)
	return s


func alive(i: int) -> bool:
	return fighters[i].hp > 0.0


func _alive_heroes() -> Array:
	var out := []
	for i in fighters.size():
		if alive(i):
			out.append(i)
	return out


func _alive_mobs() -> Array:
	var out := []
	for i in mobs.size():
		if mobs[i].hp > 0.0:
			out.append(i)
	return out


# =========================================================== monsters

func _wave_rng(w: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()  # Q14.6 A: a stage always rolls the same waves
	r.seed = hash([mode, diff, stage, zone_int, tower_floor, w])
	return r


## Monster curves per level. Growth slows after MOB_KNEE_LV: past the hero level cap, power comes only
## from gear, enhancement and runes, which grow far slower than the early exponential (Q5.5 C, Q7.3 A).
static func _curve(lv: int, g1: float, g2: float) -> float:
	var k := mini(lv, D.MOB_KNEE_LV) - 1
	return pow(g1, k) * pow(g2, maxi(0, lv - D.MOB_KNEE_LV))


static func mob_hp(lv: int) -> float:
	return D.MOB_HP0 * _curve(lv, D.MOB_HP_GROWTH, D.MOB_HP_GROWTH2)


static func mob_atk(lv: int) -> float:
	return D.MOB_ATK0 * _curve(lv, D.MOB_ATK_GROWTH, D.MOB_ATK_GROWTH2)


static func mob_gold(lv: int) -> float:
	return D.GOLD0 * _curve(lv, D.GOLD_GROWTH, D.GOLD_GROWTH2)


static func mob_exp(lv: int) -> float:
	return D.EXP0 * pow(D.EXP_GROWTH, lv - 1)


func _make_mob(id: String, lv: int, r: RandomNumberGenerator, elite_n: int) -> Dictionary:
	var m: Dictionary = D.MOBS[id]
	var w_hp := 1.0 + 0.04 * (wave - 1)
	var mob := {"uid": _next_uid(), "id": id, "name": m.name, "sprite": m.sprite, "role": m.role, "dmg": m.dmg,
		"hp": mob_hp(lv) * m.hp * w_hp,
		"atk": mob_atk(lv) * m.atk,
		"aspd": m.aspd, "armor": D.MOB_ARMOR_PER_LV * lv * m.armor, "mres": minf(D.MRES_CAP, m.mres + lv * 0.3),
		"dodge": m.dodge, "boss": false, "act_boss": false, "elite": [], "cd": 0.5 + r.randf(),
		"gold": 1.0, "loot": false, "regen": 0.0, "thorns": 0.0, "level": lv, "skills": [], "scale": 1.0,
		"slam_t": D.SLAM_CD, "warn": 0.0, "summon_t": D.SUMMON_CD, "enraged": false, "split": false}
	if mode == "zone":
		mob.hp *= 1.0 + D.ZONE_HP_PER_INT * (zone_int - 1)
		mob.atk *= 1.0 + 0.25 * (zone_int - 1)
	if elite_n > 0:
		_make_elite(mob, elite_n, r)
	mob["max"] = mob.hp
	return mob


func _make_elite(mob: Dictionary, n: int, r: RandomNumberGenerator) -> void:
	var keys: Array = D.ELITE_AFFIXES.keys()
	var picked := []
	var tries := 0
	while picked.size() < n and tries < 50:
		tries += 1
		var k: String = keys[r.randi() % keys.size()]
		if k in picked:
			continue
		var bad: Array = D.ELITE_AFFIXES[k].get("bad", [])
		if picked.any(func(p): return p in bad):
			continue
		picked.append(k)
	mob.hp *= D.ELITE_HP
	var pw: float = D.ELITE_AFFIX_POWER[clampi(picked.size(), 1, 4) - 1]
	var scaled := func(a: Dictionary, k: String) -> float: return 1.0 + (a.get(k, 1.0) - 1.0) * pw
	for k in picked:
		var a: Dictionary = D.ELITE_AFFIXES[k]
		mob.hp *= scaled.call(a, "hp")
		mob.atk *= scaled.call(a, "atk")
		mob.aspd *= scaled.call(a, "aspd")
		mob.armor *= scaled.call(a, "armor")
		mob.dodge = minf(D.DODGE_CAP, mob.dodge + a.get("dodge", 0.0) * pw)
		mob.regen += a.get("regen", 0.0) * pw
		mob.thorns += a.get("thorns", 0.0) * pw
		mob.gold *= a.get("gold", 1.0)
		if a.get("magic", false):
			mob.dmg = "magic"
		if a.get("loot", false):
			mob.loot = true
		if k == "splitter":
			mob.split = true
		if k == "summoner":
			mob.skills.append("summon")
	mob.elite = picked
	# Q14.7 B: generated name, e.g. "Yêu Tinh Hung Hãn"
	mob.name = "%s %s" % [mob.name, D.ELITE_AFFIXES[picked[0]].name] if picked.size() > 0 else mob.name


func _next_uid() -> int:
	_uid += 1
	return _uid


func _mob_pool() -> Array:
	if mode == "tower":
		var all := []
		for a in D.ACT_MOBS:
			all.append_array(a)
		return all
	var a_i := act() - 1 if mode == "campaign" else (zone_int - 1) % 3
	var pool := []
	for id in D.ACT_MOBS[a_i]:
		if mode != "campaign" or local_stage() >= D.MOBS[id].get("from", 1):
			pool.append(id)
	return pool


func _spawn_wave() -> void:
	mobs.clear()
	var r := _wave_rng(wave)
	var lv := stage_level()
	var elite_n := (diff if mode == "campaign" else zone_diff()) + 1
	var elite_chance := D.ELITE_CHANCE * (2.0 if mode != "campaign" else 1.0)
	if is_boss_wave():
		var b := _make_boss(lv, r)
		mobs.append(b)
		_emit({"t": "boss", "name": b.name})
		return
	var pool := _mob_pool()
	var n := 2 + (local_stage() - 1) / 3 if mode == "campaign" else 4
	for i in n:
		var id: String = pool[r.randi() % pool.size()]
		mobs.append(_make_mob(id, lv, r, elite_n if r.randf() < elite_chance else 0))
	_emit({"t": "wave", "n": wave})


func _make_boss(lv: int, r: RandomNumberGenerator) -> Dictionary:
	var act_boss := is_act_boss_stage()
	var b: Dictionary
	if act_boss:
		var a_i := act() - 1 if mode == "campaign" else r.randi() % 3
		b = _make_mob(D.ACT_MOBS[a_i][0], lv, r, 0)
		b.name = D.ACT_BOSSES[a_i].name
		b.sprite = D.ACT_BOSSES[a_i].sprite
		b.hp *= D.ACT_BOSS_HP
		b.atk *= D.ACT_BOSS_ATK
		b.skills = D.BOSS_SKILLS.duplicate()
		b.act_boss = true
	else:
		var pool := _mob_pool()
		b = _make_mob(pool[0], lv, r, 0)
		b.name = "Thủ Lĩnh " + b.name
		b.hp *= D.BOSS_HP
		b.atk *= D.BOSS_ATK
		b.skills = [D.BOSS_SKILLS[r.randi() % D.BOSS_SKILLS.size()]]
		b.scale = 1.6
	b.boss = true
	b.aspd *= 0.8
	b.max = b.hp
	return b


# =========================================================== simulation step

## Advance the battle by dt seconds. `now` is unix time, used for chest drops.
func step(dt: float, now: float) -> void:
	_tick_chests(now)
	if fighters.size() != party.size():
		_reset_fighters()
	if _alive_mobs().is_empty():
		_spawn_wave()
	_tick_heroes(dt)
	if _alive_mobs().is_empty():
		_wave_cleared()
		return
	_tick_mobs(dt)
	if _alive_heroes().is_empty():
		_wipe()


func _tick_chests(now: float) -> void:
	if chest_ready_at == 0.0:
		chest_ready_at = now + chest_interval()
	if now >= chest_ready_at:
		chests = mini(chests + 1, chest_cap())
		chest_ready_at = now + chest_interval()
		_emit({"t": "chest"})
		if rune_level("auto_chest") > 0:
			open_chest()


func chest_interval() -> float:
	return D.CHEST_SEC - rv("chest_time")


func chest_cap() -> int:
	return D.CHEST_CAP


func _tick_heroes(dt: float) -> void:
	for i in fighters.size():
		var f: Dictionary = fighters[i]
		if f.hp <= 0.0:
			f.dead_t -= dt
			if f.dead_t <= 0.0:
				f.hp = stats(f.cls).hp * 0.5
				_emit({"t": "revive", "slot": i})
			continue
		for b in f.buffs:
			b.t -= dt
		f.buffs = f.buffs.filter(func(b): return b.t > 0.0)
		var s := fighter_stats(i)
		for sk in D.SKILLS[f.cls]:
			if sk.trigger == "cd" and heroes[f.cls].skills.get(sk.id, 0) > 0:
				f.cds[sk.id] -= dt
				if f.cds[sk.id] <= 0.0 and _cast(i, sk, s):
					f.cds[sk.id] = sk.n
		f.cd -= dt
		while f.cd <= 0.0:
			f.cd += 1.0 / s.aspd
			var targets := _alive_mobs()
			if targets.is_empty():
				break
			f.attacks += 1
			_hero_hit(i, targets[0], 1.0, false, s)
			_emit({"t": "attack", "slot": i, "mob": mobs[targets[0]].uid if targets[0] < mobs.size() else -1})
			for sk in D.SKILLS[f.cls]:
				if sk.trigger == "hits" and heroes[f.cls].skills.get(sk.id, 0) > 0 and f.attacks % int(sk.n) == 0:
					_cast(i, sk, s)


## Returns false when the skill had nothing to do (e.g. heal with everyone full), so its cooldown waits.
func _cast(i: int, sk: Dictionary, s: Dictionary) -> bool:
	var f: Dictionary = fighters[i]
	var v := skill_value(f.cls, sk.id)
	var targets := _alive_mobs()
	match sk.kind:
		"dmg":
			if targets.is_empty():
				return false
			_hero_hit(i, targets[0], v, true, s)
			_emit({"t": "skill", "slot": i, "fx": sk.fx, "mob": mobs[targets[0]].uid if targets[0] < mobs.size() else -1})
		"aoe":
			if targets.is_empty():
				return false
			for m in targets:
				_hero_hit(i, m, v, true, s)
			_emit({"t": "skill", "slot": i, "fx": sk.fx, "mob": -1})
		"multi":
			if targets.is_empty():
				return false
			for k in sk.hits:
				var live := _alive_mobs()
				if live.is_empty():
					break
				_hero_hit(i, live[rng.randi() % live.size()], v, true, s)
			_emit({"t": "skill", "slot": i, "fx": sk.fx, "mob": mobs[targets[0]].uid if targets[0] < mobs.size() else -1})
		"execute":
			if targets.is_empty():
				return false
			var low: int = targets[0]
			for m in targets:
				if mobs[m].hp < mobs[low].hp:
					low = m
			var uid: int = mobs[low].uid
			_hero_hit(i, low, v, true, s, true)
			_emit({"t": "skill", "slot": i, "fx": sk.fx, "mob": uid})
		"heal":
			var worst := -1
			for j in _alive_heroes():
				var ratio: float = fighters[j].hp / stats(fighters[j].cls).hp
				if ratio < 0.9 and (worst < 0 or ratio < fighters[worst].hp / stats(fighters[worst].cls).hp):
					worst = j
			if worst < 0:
				return false
			var mx: float = stats(fighters[worst].cls).hp
			fighters[worst].hp = minf(mx, fighters[worst].hp + s.atk * v * (1.0 + s.skill_dmg))
			_emit({"t": "heal", "slot": i, "target": worst, "fx": sk.fx})
		"revive":
			for j in fighters.size():
				if not alive(j):
					fighters[j].hp = stats(fighters[j].cls).hp * minf(1.0, v)
					_emit({"t": "heal", "slot": i, "target": j, "fx": sk.fx})
					return true
			return false
		"buff":
			f.buffs.append({"stat": sk.stat, "v": v, "t": sk.dur})
			_emit({"t": "buff", "slot": i, "fx": sk.fx})
	return true


func _hero_hit(i: int, m: int, mult: float, is_skill: bool, s: Dictionary, force_crit := false) -> void:
	if m >= mobs.size() or mobs[m].hp <= 0.0:
		return
	var mob: Dictionary = mobs[m]
	var r := hit(s, mob, mult, is_skill, s.level, force_crit)
	mob.hp -= r.dmg
	_emit({"t": "dmg", "mob": mob.uid, "v": r.dmg, "crit": r.crit, "miss": r.dodged})
	var f: Dictionary = fighters[i]
	if s.lifesteal > 0.0 and r.dmg > 0:
		f.hp = minf(stats(f.cls).hp, f.hp + r.dmg * s.lifesteal)
	if mob.thorns > 0.0 and r.dmg > 0:
		f.hp -= r.dmg * mob.thorns
		if f.hp <= 0.0:
			_hero_died(i)
	if mob.hp <= 0.0:
		_mob_died(m)


func _tick_mobs(dt: float) -> void:
	for m in _alive_mobs():
		var mob: Dictionary = mobs[m]
		if mob.regen > 0.0:
			mob.hp = minf(mob.max, mob.hp + mob.max * mob.regen * dt)
		if "enrage" in mob.skills and not mob.enraged and mob.hp < mob.max * 0.3:
			mob.enraged = true
			mob.aspd *= 1.5
			_emit({"t": "enrage", "mob": mob.uid})
		if "slam" in mob.skills:
			if mob.warn > 0.0:
				mob.warn -= dt
				if mob.warn <= 0.0:
					for j in _alive_heroes():
						_mob_hit(m, j, D.SLAM_MULT)
					_emit({"t": "slam", "mob": mob.uid})
			else:
				mob.slam_t -= dt
				if mob.slam_t <= 0.0:
					mob.slam_t = D.SLAM_CD
					mob.warn = D.SLAM_WARN  # telegraph before the hit
					_emit({"t": "slam_warn", "mob": mob.uid})
		if "summon" in mob.skills and mobs.size() < 9:
			mob.summon_t -= dt
			if mob.summon_t <= 0.0:
				mob.summon_t = D.SUMMON_CD
				var pool := _mob_pool()
				for k in 2:
					var add := _make_mob(pool[rng.randi() % pool.size()], mob.level, rng, 0)
					add.hp *= 0.5
					add.max = add.hp
					mobs.append(add)
				_emit({"t": "summon", "mob": mob.uid})
		mob.cd -= dt
		if mob.cd > 0.0:
			continue
		mob.cd += 1.0 / mob.aspd
		var heroes_alive := _alive_heroes()
		if heroes_alive.is_empty():
			return
		match mob.role:
			"melee": _mob_hit(m, heroes_alive[0], 1.0)  # Q6.2 A: the front hero takes melee hits
			"ranged": _mob_hit(m, heroes_alive[rng.randi() % heroes_alive.size()], 1.0)
			"pierce":
				for j in heroes_alive:
					_mob_hit(m, j, 0.6)
		_emit({"t": "mob_attack", "mob": mob.uid, "role": mob.role})


func _mob_hit(m: int, j: int, mult: float) -> void:
	if not alive(j):
		return
	var mob: Dictionary = mobs[m]
	var r := hit(mob, fighter_stats(j), mult, false, mob.level)
	fighters[j].hp -= r.dmg
	_emit({"t": "hurt", "slot": j, "v": r.dmg, "miss": r.dodged, "block": r.blocked})
	if fighters[j].hp <= 0.0:
		_hero_died(j)


func _hero_died(j: int) -> void:
	fighters[j].hp = 0.0
	fighters[j].dead_t = D.REVIVE_SEC
	_emit({"t": "die", "slot": j})


func _wipe() -> void:
	# Q3.3 C: the run is lost only when the whole party is down
	_emit({"t": "wipe"})
	wave = 1
	mobs.clear()
	_reset_fighters()


func _mob_died(m: int) -> void:
	var mob: Dictionary = mobs[m]
	kills += 1
	var lv: int = mob.level
	var g: float = mob_gold(lv) * mob.gold * team_gold_mult()
	var xp := mob_exp(lv)
	var drop_chance := 0.03 * (1.0 + team_mf())
	if mob.boss:
		g *= 8.0
		xp *= 6.0
		drop_chance = 0.0
	elif mob.elite.size() > 0:
		g *= 3.0
		xp *= 3.0
		drop_chance = 0.3
	if mob.loot:
		drop_chance = 1.0
	gold += int(g)
	_gain_exp_party(xp)
	if rng.randf() < drop_chance:
		_drop_item(0)
	if mob.split:
		for k in 2:
			var child := _make_mob(mob.id, lv, rng, 0)
			child.hp *= 0.4
			child.max = child.hp
			mobs.append(child)
	_emit({"t": "mob_die", "mob": mob.uid, "boss": mob.boss, "gold": int(g)})


func _gain_exp_party(xp: float) -> void:
	for c in party:
		var h: Dictionary = heroes[c]
		if h.level >= D.LEVEL_CAP:
			continue
		var gain: float = xp * (1.0 + (rv("training") + rv("wisdom")) / 100.0 + stats(c).exp) * hero_exp_mult(c)
		h.xp += int(gain)
		while h.level < D.LEVEL_CAP and h.xp >= exp_to_next(h.level):
			h.xp -= exp_to_next(h.level)
			h.level += 1
			_dirty()
			_emit({"t": "levelup", "cls": c, "level": h.level})


## Q5.4 A: level gap penalty shaped after the TBH table (hero 30: −4 94%, −8 50%, −10 23%).
static func exp_mult_for_gap(gap: int) -> float:
	if gap > 2:
		return 1.0 / (1.0 + exp((gap - 8.0) / 1.6))
	if gap < -5:
		return maxf(0.5, 1.0 - 0.05 * (-gap - 5))
	return 1.0


func hero_exp_mult(cls: String) -> float:
	return exp_mult_for_gap(heroes[cls].level - stage_level())


func _wave_cleared() -> void:
	if is_boss_wave():
		_stage_cleared()
		return
	wave += 1


func _stage_cleared() -> void:
	var key := "%s:%d:%d:%d" % [mode, diff, stage if mode == "campaign" else (zone_int if mode == "zone" else tower_floor), 0]
	var first := not first_kills.has(key)
	first_kills[key] = true
	var lv := stage_level()
	var bonus := mob_gold(lv) * 20.0 * team_gold_mult()
	if first:
		bonus *= D.FIRST_KILL_GOLD  # Q13.4 note
	gold += int(bonus)
	var n := 2 if is_act_boss_stage() else 1
	for k in n:
		_drop_item(1 if first else 0)
	stones[mini(4, lv / 20)] += 1 + (1 if first else 0)
	_emit({"t": "clear", "first": first, "gold": int(bonus)})
	wave = 1
	match mode:
		"campaign":
			if stage < D.STAGES:
				max_stage[diff] = maxi(max_stage[diff], stage + 1)
				if not repeat:
					stage += 1
			elif diff < 3 and max_stage[diff + 1] == 0:
				max_stage[diff + 1] = 1  # beating 3-10 opens the next difficulty (TBH)
				_emit({"t": "diff_unlock", "d": diff + 1})
		"zone":
			zone_max = maxi(zone_max, mini(D.ZONE_INTENSITY_MAX, zone_int + 1))
			if not repeat and zone_int < zone_max:
				zone_int += 1
		"tower":
			tower_best = maxi(tower_best, tower_floor)
			tower_floor += 1
	_dirty()
	_reset_fighters()


# =========================================================== items

func bag_cap() -> int:
	return D.BAG_CAP + int(rv("bag"))


func roll_rarity(floor_r := 0) -> int:
	var a := act() - 1 if mode == "campaign" else 2
	var d := diff if mode == "campaign" else zone_diff()
	var boost := 1.0 + 0.15 * a + 0.25 * d + rv("fortune") / 100.0
	if mode == "zone":
		boost += D.ZONE_LOOT_PER_INT * zone_int
	var weights := []
	var total := 0.0
	for i in D.RARITIES.size():
		var w: float = D.RARITIES[i].w * (boost if i >= 2 else 1.0) if i >= floor_r else 0.0
		weights.append(w)
		total += w
	var x := rng.randf() * total
	for i in weights.size():
		x -= weights[i]
		if x <= 0.0:
			return i
	return D.RARITIES.size() - 1


func make_item(slot: String, rarity: int, kind := "") -> Dictionary:
	if kind == "":
		if slot == "weapon":
			kind = D.CLASSES[_kind_class()].weapon
		elif slot == "armor":
			kind = D.CLASSES[_kind_class()].armor_kind
	var it := {"uid": next_uid, "slot": slot, "kind": kind, "rarity": rarity, "main": {}, "affixes": [],
		"enh": 0, "pity": 0.0, "locked": false}
	next_uid += 1
	var mult: float = D.RARITIES[rarity].mult * rng.randf_range(0.9, 1.1)
	for st in D.MAIN_STATS[slot]:
		it.main[st] = D.MAIN_STATS[slot][st] * mult
	for i in D.RARITIES[rarity].affixes:
		it.affixes.append(_roll_affix(it))
	return it


## Weapons and armor lean toward classes the player owns, so most drops are wearable.
func _kind_class() -> String:
	if rng.randf() < 0.75:
		return owned[rng.randi() % owned.size()]
	return D.CLASS_ORDER[rng.randi() % D.CLASS_ORDER.size()]


func _roll_affix(it: Dictionary) -> Dictionary:
	var taken: Array = it.affixes.map(func(a): return a.stat)
	var keys := D.AFFIXES.keys().filter(func(k): return not k in taken)
	var stat: String = keys[rng.randi() % keys.size()]
	var qmax: int = D.RARITIES[it.rarity].qmax
	var q := 1
	while q < qmax and rng.randf() < 0.55:  # low quality is common, 9–10 is rare
		q += 1
	return {"stat": stat, "q": q, "val": affix_value(stat, q), "locked": false}


static func affix_value(stat: String, q: int) -> float:
	var a: Dictionary = D.AFFIXES[stat]
	return a.lo + (a.hi - a.lo) * (q - 1) / 9.0


func _drop_item(floor_r: int) -> Dictionary:
	var it := make_item(D.SLOTS[rng.randi() % D.SLOTS.size()], roll_rarity(floor_r))
	return _receive(it)


## Into the bag, or dismantled at once when the bag is full or auto-sell catches it.
func _receive(it: Dictionary) -> Dictionary:
	if bag.size() >= bag_cap() or (rune_level("auto_sell") > 0 and it.rarity <= auto_sell_below):
		_dismantle_rewards(it)
		_emit({"t": "auto_sell", "rarity": it.rarity})
		return it
	bag.append(it)
	_emit({"t": "drop", "rarity": it.rarity})
	return it


func open_chest() -> bool:
	if chests <= 0:
		return false
	chests -= 1
	pity_chests += 1
	gold += int(mob_gold(stage_level()) * 15.0 * team_gold_mult())
	stones[0] += 1 + rng.randi() % 2
	var got_immortal := false
	for k in D.CHEST_ITEMS:
		var r := roll_rarity()
		if k == 0 and pity_chests >= D.IMMORTAL_PITY:
			r = D.RARITIES.size() - 1
		if r == D.RARITIES.size() - 1:
			got_immortal = true
		_receive(make_item(D.SLOTS[rng.randi() % D.SLOTS.size()], r))
	if got_immortal:
		pity_chests = 0
	_emit({"t": "open_chest"})
	return true


func find_item(uid: int) -> Dictionary:
	for it in bag:
		if it.uid == uid:
			return it
	for c in heroes:
		for s in D.SLOTS:
			var it = heroes[c].equip[s]
			if it != null and it.uid == uid:
				return it
	return {}


func can_wear(cls: String, it: Dictionary) -> bool:
	match it.slot:
		"weapon": return it.kind == D.CLASSES[cls].weapon
		"armor": return it.kind == D.CLASSES[cls].armor_kind
	return true


## Move a bag item onto a hero; the previous item goes back to the bag.
func equip(cls: String, uid: int) -> bool:
	var idx := -1
	for i in bag.size():
		if bag[i].uid == uid:
			idx = i
	if idx < 0 or not can_wear(cls, bag[idx]):
		return false
	var it: Dictionary = bag[idx]
	bag.remove_at(idx)
	var old = heroes[cls].equip[it.slot]
	if old != null:
		bag.append(old)
	heroes[cls].equip[it.slot] = it
	_dirty()
	return true


func unequip(cls: String, slot: String) -> bool:
	var it = heroes[cls].equip[slot]
	if it == null or bag.size() >= bag_cap():
		return false
	heroes[cls].equip[slot] = null
	bag.append(it)
	_dirty()
	return true


static func item_gold(it: Dictionary) -> int:
	return int(15.0 * pow(3.0, it.rarity) * (1.0 + 0.3 * it.enh))


## Q8.4 B: gold + enhancement stones by rarity.
static func item_stones(it: Dictionary) -> Array:
	var st := [0, 0, 0, 0, 0]
	match int(it.rarity):
		0, 1: st[0] = 1
		2: st[0] = 2
		3: st[1] = 1
		4: st[2] = 1
		5: st[3] = 1
	return st


func _dismantle_rewards(it: Dictionary) -> void:
	gold += item_gold(it)
	var st := item_stones(it)
	for i in 5:
		stones[i] += st[i]


func dismantle(uid: int) -> bool:
	for i in bag.size():
		if bag[i].uid == uid:
			if bag[i].locked:
				return false
			_dismantle_rewards(bag[i])
			bag.remove_at(i)
			return true
	return false


## Dismantle every unlocked bag item at or below a rarity.
func dismantle_below(rarity: int) -> int:
	var n := 0
	for it in bag.duplicate():
		if not it.locked and it.rarity <= rarity and dismantle(it.uid):
			n += 1
	return n


func sort_bag() -> void:
	bag.sort_custom(func(a, b): return a.rarity > b.rarity or (a.rarity == b.rarity and D.SLOTS.find(a.slot) < D.SLOTS.find(b.slot)))


# =========================================================== enhancement (Q9)

func enh_cost(it: Dictionary) -> int:
	return int(D.ENH_COST0 * pow(D.ENH_COST_GROWTH, it.enh) * D.RARITIES[it.rarity].mult * (1.0 - rv("smith") / 100.0))


func protect_cost(it: Dictionary) -> int:
	var k: int = it.enh + 1
	if k < 7:
		return 0
	return int(1.25 * enh_cost(it) * pow(1.15, k - 6))


func enh_chance(it: Dictionary, stone_lv: int, n_stones: int) -> float:
	return minf(1.0, D.ENH_CHANCE[it.enh] + it.pity + D.STONE_BONUS[stone_lv - 1] * n_stones)


static func enh_floor(enh: int) -> int:
	var f := 0
	for x in D.ENH_FLOORS:
		if enh >= x:
			f = x
	return f


## One try. Needs 1–3 stones of one level (Q9.4 B). Returns {} if not possible, else {ok, enh, dropped}.
func enhance(uid: int, stone_lv: int, n_stones: int, protect: bool) -> Dictionary:
	var it := find_item(uid)
	if it.is_empty() or it.enh >= D.ENH_MAX or n_stones < 1 or n_stones > D.STONES_PER_TRY:
		return {}
	if stone_lv < 1 or stone_lv > 5 or stones[stone_lv - 1] < n_stones:
		return {}
	var cost := enh_cost(it) + (protect_cost(it) if protect else 0)
	if gold < cost:
		return {}
	gold -= cost
	stones[stone_lv - 1] -= n_stones
	var chance := enh_chance(it, stone_lv, n_stones)
	var res := {"ok": false, "enh": it.enh, "dropped": false}
	if rng.randf() < chance:
		it.enh += 1
		it.pity = 0.0
		res.ok = true
	else:
		it.pity += D.ENH_PITY
		if it.enh + 1 >= 7 and not protect:
			var lower := maxi(it.enh - 1, enh_floor(it.enh))
			res.dropped = lower < it.enh
			it.enh = lower
	res.enh = it.enh
	_dirty()
	return res


# =========================================================== reroll and lock (Q11)

func reroll_cost(it: Dictionary, locked: int) -> int:
	return int(D.REROLL_COST0 * pow(D.REROLL_GROWTH, it.rarity) * pow(2.0, locked))


func locked_count(it: Dictionary) -> int:
	return it.affixes.filter(func(a): return a.locked).size()


func toggle_lock(uid: int, idx: int) -> bool:
	var it := find_item(uid)
	if it.is_empty() or idx < 0 or idx >= it.affixes.size():
		return false
	it.affixes[idx].locked = not it.affixes[idx].locked
	return true


## Reroll every unlocked line, or only line `only` (the others count as locked for the price).
func reroll(uid: int, only := -1) -> bool:
	var it := find_item(uid)
	if it.is_empty() or it.affixes.is_empty():
		return false
	var locked: int = locked_count(it) if only < 0 else it.affixes.size() - 1
	if locked >= it.affixes.size():
		return false
	var cost := reroll_cost(it, locked)
	if gold < cost:
		return false
	gold -= cost
	for i in it.affixes.size():
		var a: Dictionary = it.affixes[i]
		if (only >= 0 and i != only) or (only < 0 and a.locked):
			continue
		var others := it.duplicate()  # roll against the other lines only, so this line may keep or change its stat
		others.affixes = it.affixes.filter(func(x): return x != a)
		it.affixes[i] = _roll_affix(others)
	_dirty()
	return true


# =========================================================== offline (Q2.2 B, Q2.3 B)

func offline_cap() -> float:
	return (D.OFFLINE_BASE_H + rv("hoard")) * 3600.0


## Gold and exp for `elapsed` seconds away. No chests offline.
# ponytail: kill rate from team DPS vs the current stage's average mob HP, ignores deaths and bosses
func offline_reward(elapsed: float) -> Dictionary:
	if elapsed <= 0.0 or elapsed > D.OFFLINE_VOID_SEC:
		return {"gold": 0, "xp": 0}
	var t := minf(elapsed, offline_cap())
	var lv := stage_level()
	var hp := mob_hp(lv) * 1.1
	var kps := minf(team_dps() / hp, 2.0) * 0.5
	return {"gold": int(t * kps * mob_gold(lv) * team_gold_mult()), "xp": int(t * kps * mob_exp(lv))}


func apply_offline(elapsed: float) -> Dictionary:
	var r := offline_reward(elapsed)
	gold += r.gold
	_gain_exp_party(r.xp)
	return r


# =========================================================== save

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "gold": gold, "stones": stones, "chests": chests, "pity_chests": pity_chests,
		"owned": owned, "heroes": heroes, "party": party, "bag": bag, "next_uid": next_uid, "runes": runes,
		"auto_sell_below": auto_sell_below, "diff": diff, "stage": stage, "max_stage": max_stage, "repeat": repeat,
		"first_kills": first_kills, "zone_int": zone_int, "zone_max": zone_max, "tower_best": tower_best, "kills": kills}


static func _fix_item(it) -> Variant:
	if typeof(it) != TYPE_DICTIONARY:
		return null
	for k in ["uid", "rarity", "enh"]:
		it[k] = int(it.get(k, 0))
	it["pity"] = float(it.get("pity", 0.0))
	it["locked"] = bool(it.get("locked", false))
	if not it.get("slot", "") in D.SLOTS:
		return null
	it["rarity"] = clampi(it.rarity, 0, D.RARITIES.size() - 1)
	it["enh"] = clampi(it.enh, 0, D.ENH_MAX)
	for a in it.get("affixes", []):
		a["q"] = clampi(int(a.q), 1, 10)
		a["locked"] = bool(a.get("locked", false))
	return it


## Returns false for saves from the old prototype (version 1): they start fresh.
func from_dict(d: Dictionary) -> bool:
	if int(d.get("v", 1)) != SAVE_VERSION:
		return false
	gold = int(d.get("gold", 0))
	var st: Array = d.get("stones", [])
	for i in 5:
		stones[i] = int(st[i]) if i < st.size() else 0
	chests = int(d.get("chests", 0))
	pity_chests = int(d.get("pity_chests", 0))
	runes = {}
	for r in D.RUNES:  # only known ids, clamped: a hand-edited save cannot overshoot
		var lv := clampi(int(d.get("runes", {}).get(r.id, 0)), 0, r.max if r.max > 0 else 100000)
		if lv > 0:
			runes[r.id] = lv
	owned = ["knight"]
	for c in d.get("owned", []):
		if c in D.CLASSES and not c in owned and (D.CLASSES[c].unlock == "" or rune_level(D.CLASSES[c].unlock) > 0):
			owned.append(c)
	for c in D.CLASS_ORDER:
		var src: Dictionary = d.get("heroes", {}).get(c, {})
		var h := _new_hero(c)
		h.level = clampi(int(src.get("level", 1)), 1, D.LEVEL_CAP)
		h.xp = int(src.get("xp", 0))
		h.outfit = int(src.get("outfit", 0)) % 2
		for k in src.get("skills", {}):
			h.skills[k] = clampi(int(src.skills[k]), 0, D.SKILL_MAX)
		for s in D.SLOTS:
			h.equip[s] = _fix_item(src.get("equip", {}).get(s))
		heroes[c] = h
	party = []
	for c in d.get("party", ["knight"]):
		if c in owned and not c in party and party.size() < party_size():
			party.append(c)
	if party.is_empty():
		party = ["knight"]
	bag = []
	for it in d.get("bag", []):
		var f = _fix_item(it)
		if f != null:
			bag.append(f)
	next_uid = int(d.get("next_uid", 1))
	auto_sell_below = int(d.get("auto_sell_below", -1))
	var ms: Array = d.get("max_stage", [1, 0, 0, 0])
	for i in 4:
		max_stage[i] = clampi(int(ms[i]) if i < ms.size() else 0, 0, D.STAGES)
	max_stage[0] = maxi(1, max_stage[0])
	diff = clampi(int(d.get("diff", 0)), 0, 3)
	if max_stage[diff] == 0:
		diff = 0
	stage = clampi(int(d.get("stage", 1)), 1, max_stage[diff])
	repeat = bool(d.get("repeat", false))
	first_kills = d.get("first_kills", {})
	zone_max = clampi(int(d.get("zone_max", 1)), 1, D.ZONE_INTENSITY_MAX)
	zone_int = clampi(int(d.get("zone_int", 1)), 1, zone_max)
	tower_best = int(d.get("tower_best", 0))
	kills = int(d.get("kills", 0))
	mode = "campaign"
	_start_stage()
	return true
