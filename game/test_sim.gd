extends SceneTree
## Run: godot --headless --path . --script res://test_sim.gd
## Passes only if the last line starts with OK (Godot exits 0 even on parse errors).

const Sim := preload("res://sim.gd")
const D := preload("res://data.gd")

var _passed := false


func _init() -> void:
	_finish.call_deferred()  # runs even if an assert aborts _init, so a failure exits instead of hanging
	test_progress()
	test_damage()
	test_party_and_runes()
	test_skills()
	test_items()
	test_enhance()
	test_reroll()
	test_chest_pity()
	test_deaths()
	test_offline()
	test_save()
	test_assets()
	test_audio()
	print("OK")
	_passed = true


func _finish() -> void:
	quit(0 if _passed else 1)


func _run(s, seconds: float) -> void:
	var now := 1_000_000.0
	for i in int(seconds / 0.1):
		s.step(0.1, now)
		now += 0.1


func test_progress() -> void:
	var s := Sim.new()
	s.rng.seed = 1
	_run(s, 600)
	assert(s.kills > 20, "knight alone should kill, got %d" % s.kills)
	assert(s.max_stage[0] >= 3, "should clear the first stages in 10 min, at %d" % s.max_stage[0])
	assert(s.heroes.knight.level > 3)
	assert(s.chests == 2, "4-minute chest timer: 2 chests in 10 min, got %d" % s.chests)
	assert(s.feature_unlocked("rune") and not s.feature_unlocked("portal"))
	# a wave puts several monsters on the field (Q3.2 B), seeded per stage (Q14.6 A)
	var a := Sim.new()
	a.stage = 7
	a._spawn_wave()
	var b := Sim.new()
	b.stage = 7
	b._spawn_wave()
	assert(a.mobs.size() >= 3 and a.mobs.map(func(m): return m.id) == b.mobs.map(func(m): return m.id))
	# difficulty and stage levels follow TBH ranges
	assert(s.stage_level(0, 1) == 1 and s.stage_level(0, 30) == 32 and s.stage_level(3, 30) == 95)
	assert(not s.go_to(1, 1) and s.go_to(0, 1))
	# monster curves bend at MOB_KNEE_LV: past it each level adds the slower *_GROWTH2
	var k := D.MOB_KNEE_LV
	assert(is_equal_approx(Sim.mob_hp(k + 1) / Sim.mob_hp(k), D.MOB_HP_GROWTH2))
	assert(is_equal_approx(Sim.mob_hp(k) / Sim.mob_hp(k - 1), D.MOB_HP_GROWTH))
	assert(is_equal_approx(Sim.mob_atk(k + 1) / Sim.mob_atk(k), D.MOB_ATK_GROWTH2))
	assert(is_equal_approx(Sim.mob_gold(1), D.GOLD0))
	# elite affixes weaken when stacked: a 4-affix elite stays below the full product of its multipliers
	var r := RandomNumberGenerator.new()
	for seed in 50:
		r.seed = seed
		var e := s._make_mob("orc", 80, r, 4)
		var full := Sim.mob_hp(80) * D.MOBS.orc.hp * D.ELITE_HP
		for ak in e.elite:
			full *= D.ELITE_AFFIXES[ak].get("hp", 1.0)
		assert(e.elite.size() == 4 and e.max <= full * (1.0 + 0.04 * (s.wave - 1)) + 0.01)
		if "tough" in e.elite:
			assert(e.max < full, "tough at 4 affixes is weaker than ×2")


func test_damage() -> void:
	var s := Sim.new()
	s.rng.seed = 2
	var att := {"atk": 100.0, "dmg": "phys", "crit": 0.0, "critdmg": 1.5}
	assert(s.hit(att, {}, 1.0, false, 1).dmg == 100)
	var armored: int = s.hit(att, {"armor": 200.0}, 1.0, false, 1).dmg
	assert(armored < 100 and armored >= 25, "armor reduces up to 75%%, got %d" % armored)
	assert(Sim.armor_reduction(1e9, 1, 1.0) == D.ARMOR_CAP)
	var mag := {"atk": 100.0, "dmg": "magic", "crit": 0.0}
	assert(s.hit(mag, {"armor": 1e6, "mres": 30.0}, 1.0, false, 1).dmg == 70, "magic ignores armor, uses resist")
	assert(s.hit(mag, {"mres": -20.0}, 1.0, false, 1).dmg == 120, "negative resist amplifies")
	assert(s.hit({"atk": 0.001, "dmg": "phys"}, {"armor": 50.0}, 1.0, false, 1).dmg == 1, "Q6.7 B: at least 1")
	assert(s.hit(att, {"dodge": 1.0}, 1.0, false, 1).dodged)
	assert(s.hit(att, {"block": 1.0}, 1.0, false, 1).dmg == 50)
	assert(s.hit(att, {"boss": true}, 1.0, false, 1, true).dmg == 150, "forced crit")
	assert(s.hit({"atk": 100.0, "dmg": "phys", "dmg_boss": 0.5}, {"boss": true}, 1.0, false, 1).dmg == 150)
	# Nightmare lowers hero magic resist by 20 (TBH)
	var r0: float = s.stats("knight").mres
	s.max_stage[1] = 1
	s.diff = 1
	s._dirty()
	assert(is_equal_approx(s.stats("knight").mres, r0 - 20))


func test_party_and_runes() -> void:
	var s := Sim.new()
	s.gold = 10_000_000
	assert(s.owned == ["knight"] and s.party_size() == 1)
	assert(not s.set_party_slot(1, "ranger"), "slot 2 locked, ranger not owned")
	assert(s.buy_rune("growth") and s.buy_rune("unlock_ranger") and "ranger" in s.owned)
	assert(s.buy_rune("command") and s.party_size() == 2 and s.party == ["knight", "ranger"], "new slot auto-filled")
	assert(s.set_party_slot(0, "ranger") and s.party == ["ranger", "knight"], "swap order")
	assert(s.buy_rune("unlock_cleric") and s.buy_rune("command2") and s.party.size() == 3)
	s.gold = 1_000_000_000
	var c0 := s.rune_cost("mastery")
	s.runes["haste"] = 1
	for i in 20:
		assert(s.buy_rune("mastery"), "mastery has no cap")
	assert(s.rune_cost("mastery") > c0 * 9)
	var h := Sim.new()
	h.from_dict({"v": 2, "runes": {"growth": 99, "nope": 3}})
	assert(h.runes == {"growth": 5}, "save load clamps runes")


func test_skills() -> void:
	var s := Sim.new()
	assert(s.skill_points("knight") == 5, "5 points per level (Q4.5 note)")
	assert(s.learn("knight", "k_pierce", 5) == 5 and s.skill_points("knight") == 0)
	assert(s.learn("knight", "k_pierce") == 0, "no points left")
	s.heroes.knight.level = 10
	assert(not s.can_learn("knight", "k_slam"), "tier needs 25 points spent")
	assert(s.learn("knight", "k_pierce", 30) == 20, "capped at 25")
	assert(s.can_learn("knight", "k_slam"))
	assert(is_equal_approx(s.skill_value("knight", "k_pierce"), 3.0 + 0.08 * 24))
	var atk0: float = s.stats("knight").atk
	s.learn("knight", "p_atk", 10)
	assert(s.stats("knight").atk > atk0)
	s.reset_skills("knight")
	assert(s.skill_points("knight") == 50)


func test_items() -> void:
	var s := Sim.new()
	s.rng.seed = 3
	for r in D.RARITIES.size():
		var it := s.make_item("helm", r)
		assert(it.affixes.size() == D.RARITIES[r].affixes, "Q7.4 C affix count")
		for a in it.affixes:
			assert(a.q >= 1 and a.q <= D.RARITIES[r].qmax, "quality capped by rarity")
		var stats: Array = it.affixes.map(func(a): return a.stat)
		for st in stats:
			assert(stats.count(st) == 1, "no duplicate affix")
	var sw := s.make_item("weapon", 2, "sword")
	var bow := s.make_item("weapon", 2, "bow")
	s.bag = [sw, bow]
	assert(not s.equip("knight", bow.uid), "knights cannot use bows")
	var atk0: float = s.stats("knight").atk
	assert(s.equip("knight", sw.uid) and s.stats("knight").atk > atk0 and s.bag.size() == 1)
	var sw2 := s.make_item("weapon", 0, "sword")
	s.bag.append(sw2)
	assert(s.equip("knight", sw2.uid) and s.find_item(sw.uid).uid == sw.uid and s.bag.has(sw), "old item back to bag")
	# dismantle gives gold and stones (Q8.4 B); locked items stay
	var g := s.gold
	sw.locked = true
	assert(not s.dismantle(sw.uid))
	sw.locked = false
	assert(s.dismantle(sw.uid) and s.gold > g and s.stones[0] == 2)
	# bag full: the drop is dismantled instead of lost
	s.bag = []
	for i in s.bag_cap():
		s.bag.append(s.make_item("boots", 0))
	var g2 := s.gold
	s._receive(s.make_item("boots", 0))
	assert(s.bag.size() == s.bag_cap() and s.gold > g2)
	# auto-sell rune catches low rarity drops
	s.bag = []
	s.runes["auto_sell"] = 1
	s.auto_sell_below = 1
	s._receive(s.make_item("boots", 1))
	s._receive(s.make_item("boots", 2))
	assert(s.bag.size() == 1 and s.bag[0].rarity == 2)
	# drop rarity follows weights; Mythic tier is rare
	var counts := [0, 0, 0, 0, 0, 0]
	for i in 20000:
		counts[s.roll_rarity()] += 1
	assert(counts[0] > counts[1] and counts[1] > counts[2] and counts[5] < 100, str(counts))


func test_enhance() -> void:
	var s := Sim.new()
	s.rng.seed = 4
	s.gold = 100_000_000
	s.stones = [999, 999, 999, 999, 999]
	var it := s.make_item("weapon", 3, "sword")
	s.bag = [it]
	assert(s.enhance(it.uid, 1, 0, false).is_empty(), "needs at least one stone")
	s.stones[0] = 0
	assert(s.enhance(it.uid, 1, 1, false).is_empty(), "no stones of that level")
	var low := s.make_item("weapon", 0, "sword")
	assert(s.enh_cost(it) > s.enh_cost(low), "higher rarity costs more to enhance (late gold sink)")
	s.stones[0] = 999
	assert(s.enhance(it.uid, 1, 1, false).ok, "+1 never fails")
	# failing from +7 up drops a level but never below the floors +6 / +9 / +12
	it.enh = 6
	s.rng.seed = 99
	var res := {}
	for i in 50:
		res = s.enhance(it.uid, 1, 1, false)
		assert(it.enh >= 6, "never below floor 6")
		if it.enh >= 9:
			break
	it.enh = 9
	it.pity = 0.0
	for i in 10:
		var r := s.enhance(it.uid, 1, 1, false)
		if not r.ok:
			assert(it.enh == 9, "floor 9 holds")
			break
	# pity adds 3% per fail; protection stops the drop
	it.enh = 13
	it.pity = 0.0
	var fails := 0
	for i in 20:
		var r := s.enhance(it.uid, 1, 1, true)
		if r.ok:
			break
		fails += 1
		assert(it.enh == 13 and is_equal_approx(it.pity, D.ENH_PITY * fails), "protected: no drop, pity grows")
	assert(Sim.enh_floor(8) == 6 and Sim.enh_floor(12) == 12 and Sim.enh_floor(5) == 0)
	assert(s.protect_cost(it) > 0)
	it.enh = 0
	assert(s.protect_cost(it) == 0, "no protection below +7")
	# stones raise the chance; main stat grows with enhancement
	it.enh = 10
	it.pity = 0.0
	assert(s.enh_chance(it, 5, 3) > s.enh_chance(it, 1, 1))
	assert(is_equal_approx(Sim.enh_bonus(15), 0.25 + 0.18 + 0.14 + 0.40))


func test_reroll() -> void:
	var s := Sim.new()
	s.rng.seed = 5
	s.gold = 100_000_000
	var it := s.make_item("gloves", 5)
	s.bag = [it]
	assert(s.toggle_lock(it.uid, 0))
	var kept: Dictionary = it.affixes[0].duplicate()
	var c1 := s.reroll_cost(it, 1)
	assert(c1 == s.reroll_cost(it, 0) * 2, "Q11.2 A: x2 per locked line")
	var g := s.gold
	assert(s.reroll(it.uid) and s.gold == g - c1)
	assert(it.affixes[0].stat == kept.stat and it.affixes[0].q == kept.q, "locked line kept")
	assert(it.affixes.size() == 4)
	var stats: Array = it.affixes.map(func(a): return a.stat)
	for st in stats:
		assert(stats.count(st) == 1)
	# single-line reroll is priced as if the other lines were locked
	var others: Array = it.affixes.slice(1).map(func(a): return a.duplicate())
	g = s.gold
	assert(s.reroll(it.uid, 0) and s.gold == g - s.reroll_cost(it, 3))
	for i in 3:
		assert(it.affixes[i + 1].stat == others[i].stat)
	assert(s.reroll_cost(s.make_item("gloves", 5), 0) < 200_000, "cheaper than Master's 1M")


func test_chest_pity() -> void:
	var s := Sim.new()
	s.rng.seed = 6
	s.pity_chests = D.IMMORTAL_PITY - 1
	s.chests = 1
	s.open_chest()
	assert(s.bag.any(func(it): return it.rarity == 5), "Q7.5 note: guaranteed Immortal at 1000 chests")
	assert(s.pity_chests == 0)


func test_deaths() -> void:
	var s := Sim.new()
	s.rng.seed = 7
	s.stage = 30
	s.max_stage[0] = 30
	s._start_stage()
	var died := false
	var wiped := false
	var now := 0.0
	for i in 600:
		s.step(0.1, now)
		now += 0.1
		for e in s.events:
			died = died or e.t == "die"
			wiped = wiped or e.t == "wipe"
		s.events.clear()
	assert(died and wiped, "a level 1 knight at 1-30 must die and wipe")
	assert(s.wave == 1 or s.mobs.size() > 0)
	# a fallen hero revives after REVIVE_SEC when someone else holds the line
	var t := Sim.new()
	t.gold = 10_000_000
	t.buy_rune("growth")
	t.buy_rune("unlock_ranger")
	t.buy_rune("command")
	t._hero_died(1)
	t.mobs = []
	t.fighters[1].dead_t = 0.05
	t._tick_heroes(0.1)
	assert(t.fighters[1].hp > 0.0)


func test_offline() -> void:
	var s := Sim.new()
	assert(s.offline_reward(3600).gold > 0, "Q2.2 B: available from the start")
	assert(s.offline_reward(20 * 3600).gold == s.offline_reward(8 * 3600).gold, "base cap 8h")
	s.runes["hoard"] = 4
	assert(s.offline_cap() == 12 * 3600.0, "Q2.3 B: 12h with runes")
	assert(s.offline_reward(31 * 86400).gold == 0 and s.offline_reward(-5).gold == 0)


func test_save() -> void:
	var s := Sim.new()
	s.rng.seed = 8
	s.gold = 1_000_000
	s.buy_rune("growth")
	s.buy_rune("unlock_ranger")
	s.buy_rune("command")
	var it := s.make_item("weapon", 4, "sword")
	it.enh = 7
	s.bag = [it, s.make_item("helm", 3)]
	s.equip("knight", it.uid)
	s.learn("knight", "k_pierce", 3)
	s.max_stage[0] = 12
	s.stage = 11
	var c := Sim.new()
	assert(c.from_dict(JSON.parse_string(JSON.stringify(s.to_dict()))))
	assert(c.gold == s.gold and c.party == s.party and c.owned == s.owned and c.stage == 11)
	assert(c.heroes.knight.equip.weapon.enh == 7 and c.heroes.knight.equip.weapon.rarity == 4)
	assert(c.bag.size() == 1 and c.bag[0].affixes.size() == 2)
	assert(c.heroes.knight.skills.k_pierce == 3)
	assert(is_equal_approx(c.stats("knight").atk, s.stats("knight").atk))
	assert(not Sim.new().from_dict({"level": 7}), "prototype saves start fresh")


func test_assets() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art3d/manifest.json"))
	var models := []
	for c in D.CLASSES:
		models.append(c)
		assert(D.HERO_MODELS.has(c), "no gear table for " + c)
		assert(ResourceLoader.exists("res://art3d/portraits/%s.png" % c), "missing portrait " + c)
		var g: Dictionary = D.HERO_MODELS[c]
		var node: Node = load("res://art3d/%s.glb" % c).instantiate()
		for n in g.gear + ([g.hat] if g.hat != "" else []):  # every mesh named in the gear table exists in the model
			assert(node.find_child(n, true, false) != null, "%s has no mesh %s" % [c, n])
		node.free()
		for sk in D.SKILLS[c]:
			if sk.fx != "":
				assert(FileAccess.file_exists("res://fx/%s.json" % sk.fx), "missing fx " + sk.fx)
	for id in D.MOBS:
		models.append(D.MOBS[id].model)
	for b in D.ACT_BOSSES:
		models.append(b.model)
	for mdl in models:
		assert(ResourceLoader.exists("res://art3d/%s.glb" % mdl), "missing model " + mdl)
		assert(man.has(mdl) and man[mdl].height > 0.5, "manifest height for " + mdl)
		for a in ["idle", "run", "attack", "hit", "death"]:
			assert(a in man[mdl].anims, "%s has no %s animation" % [mdl, a])
	var Art := preload("res://art.gd")
	for n in Art.SPRITES:
		var rows: Array = Art.SPRITES[n]
		for y in rows.size():
			assert(rows[y].length() == rows[0].length(), "%s row %d: width %d, expected %d" % [n, y, rows[y].length(), rows[0].length()])
			for ch in rows[y]:
				assert(ch == "." or Art.PALETTE.has(ch), "%s row %d: unknown color %s" % [n, y, ch])


func test_audio() -> void:
	var Sfx := preload("res://sfx.gd")
	for name in Sfx.SOUNDS:
		var w: AudioStreamWAV = Sfx.build(name)
		var peak := 0
		for i in range(0, w.data.size(), 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		assert(peak > 3000, "%s is near silent" % name)
	var Music := preload("res://music.gd")
	for ai in Music.THEMES.size():
		var mu: AudioStreamWAV = Music.build(ai)
		assert(mu.data.size() == Music.loop_samples(ai) * 2 and mu.loop_mode == AudioStreamWAV.LOOP_FORWARD)
