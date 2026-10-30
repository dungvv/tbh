extends SceneTree
## Run: godot --headless --path . --script res://test_sim.gd  -- passes only if it prints a line starting with OK (Godot exits 0 on parse errors)

const Sim := preload("res://sim.gd")


var _passed := false


func _init() -> void:
	_finish.call_deferred()  # runs even if an assert aborts _init, so a failure exits instead of hanging
	var s := Sim.new()
	s.rng.seed = 42
	var now := 1_000_000.0
	for i in 6000:  # 10 minutes at 0.1s ticks
		s.step(0.1, now)
		now += 0.1
	assert(s.kills > 0 and s.gold > 0, "hero should kill and earn")
	assert(s.stage > 1, "should clear stage 1 within 10 minutes")
	assert(s.chests == 2, "4-minute chest timer over 10 minutes = 2 chests, got %d" % s.chests)
	var before := s.bag_total()
	assert(s.open_chest() and s.chests == 1)
	assert(s.bag_total() == before + Sim.CHEST_ITEMS, "chest gives items")

	# Offline
	var off := Sim.new()
	assert(off.offline_reward(3600).gold == 0, "offline locked until the repose rune")
	off.runes = {"growth": 1, "repose": 1}
	assert(off.offline_reward(3600).gold > 0)
	assert(off.offline_reward(10 * 3600).gold == off.offline_reward(4 * 3600).gold, "base cap 4h")
	off.runes.hoard = 4
	assert(off.offline_reward(10 * 3600).gold == off.offline_reward(8 * 3600).gold, "max cap 8h with hoard 4")
	assert(off.offline_reward(8 * 3600).gold > off.offline_reward(4 * 3600).gold)
	assert(off.offline_reward(31 * 86400).gold == 0, "30+ days away gives nothing")
	assert(off.offline_reward(-50).gold == 0, "clock rolled back gives nothing")

	# Runes: requirement, cost, max level, effects
	var ru := Sim.new()
	ru.gold = 100000
	assert(not ru.buy_rune("repose"), "needs growth first")
	var c0 := ru.rune_cost("growth")
	assert(c0 == int(50 * Sim.RUNE_COST_MULT))
	assert(ru.buy_rune("growth") and ru.gold == 100000 - c0)
	assert(ru.rune_cost("growth") == int(50 * Sim.RUNE_COST_MULT * 1.6), "cost grows x1.6")
	var atk1 := ru.hero_atk()
	assert(ru.buy_rune("growth") and ru.hero_atk() > atk1)
	assert(ru.buy_rune("repose") and not ru.buy_rune("repose"), "repose max 1")
	ru.gold = 0
	assert(not ru.buy_rune("training"), "cannot afford")
	for r in Sim.RUNES:
		assert(r.req == "" or not Sim.rune_def(r.req).is_empty(), "%s requires unknown rune %s" % [r.id, r.req])
	ru.runes = {"chest_time": 4, "chest_cap": 4, "bag": 4, "alchemy": 5}
	assert(ru.chest_interval() == 180.0, "4 levels of chest_time = 3 min, the TBH number")
	assert(ru.chest_cap() == 40 and ru.bag_cap() == 100)
	assert(ru.sell_price(1) == 45, "alchemy +50% sell price")
	ru.runes.auto_chest = 1
	ru.step(0.1, 5000.0)
	var n0 := ru.bag_total()
	ru.step(0.1, 5000.0 + 181.0)
	assert(ru.chests == 0 and ru.bag_total() == n0 + Sim.CHEST_ITEMS, "auto chest opens on arrival")
	# Uncapped runes keep taking gold
	var inf := Sim.new()
	inf.runes = {"growth": 1, "haste": 1, "might": 1, "focus": 1}
	inf.gold = 10_000_000
	var atk_before := inf.hero_atk()
	for i in 30:
		assert(inf.buy_rune("mastery"), "mastery has no cap")
	assert(inf.rune_level("mastery") == 30 and inf.hero_atk() > atk_before * 1.5)
	assert(inf.rune_cost("mastery") > Sim.rune_def("mastery").cost * Sim.RUNE_COST_MULT * pow(Sim.rune_def("mastery").grow, 29), "cost keeps growing")
	var inf2 := Sim.new()
	inf2.from_dict({"runes": {"mastery": 250}})
	assert(inf2.rune_level("mastery") == 250, "uncapped levels survive load")

	var hacked := Sim.new()
	hacked.from_dict({"runes": {"growth": 99, "nope": 3}})
	assert(hacked.runes == {"growth": 5}, "save load clamps runes")

	# Synthesis: 9 in, 1 out, rates match the table
	var b := Sim.new()
	b.rng.seed = 7
	b.bag[Sim.key("weapon", 0)] = 9
	assert(b.synth("weapon", 0).kind != "fail", "Common cannot fail")
	assert(b.bag_total() == 1, "9 -> 1")
	assert(b.synth("weapon", 0).is_empty(), "needs 9")
	var ups := 0
	for i in 2000:
		b.bag = {Sim.key("ring", 3): 9}
		if b.synth("ring", 3).kind != "fail":
			ups += 1
	assert(absf(ups / 2000.0 - 0.8025) < 0.03, "Epic success ~80%%, got %d/2000" % ups)
	b.bag = {Sim.key("gloves", 5): 9}
	assert(b.synth("gloves", 5).is_empty(), "Mythic cannot be synthesized")

	# Selling 9 is worth more than the synth result: no free gold loop
	for t in 5:
		assert(9 * Sim.sell_value(t) > Sim.sell_value(t + 1))

	# Auto synth only touches tiers that cannot fail
	b.bag = {Sim.key("weapon", 0): 81, Sim.key("weapon", 3): 9}
	b.auto_synth()
	assert(b.count("weapon", 3) >= 9, "auto synth must not risk Epic")
	assert(b.count("weapon", 0) == 0)

	# Equip swaps with the bag and changes stats
	b.bag = {Sim.key("weapon", 2): 1, Sim.key("weapon", 1): 1}
	var atk0 := b.hero_atk()
	assert(b.equip("weapon", 2) and b.hero_atk() > atk0)
	assert(b.equip("weapon", 1) and b.count("weapon", 2) == 1, "old item returns to bag")
	assert(not b.equip("weapon", 4))

	# Full bag sells the drop instead of losing it
	b.bag = {Sim.key("ring", 0): Sim.BAG_CAP}
	var g := b.gold
	assert(not b.add_item("ring", 1) and b.gold == g + Sim.sell_value(1))

	# Sell
	b.bag = {Sim.key("ring", 2): 3}
	assert(b.sell("ring", 2, 5) == 3 * Sim.sell_value(2) and b.count("ring", 2) == 0)

	# Save roundtrip through JSON (ints come back as floats)
	if s.count("weapon", 0) > 0:
		s.equip("weapon", 0)
	var copy := Sim.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert(copy.gold == s.gold and copy.stage == s.stage and copy.bag == s.bag and copy.heroes[0].equipped == s.heroes[0].equipped and copy.heroes[0].level == s.heroes[0].level, "save roundtrip")
	# Party: Ranger joins only with the command rune, gear is per hero
	var p := Sim.new()
	p.rng.seed = 3
	assert(p.party_size() == 1)
	var solo := p.team_dps()
	p.runes = {"growth": 1, "command": 1}
	assert(p.party_size() == 2 and p.team_dps() > solo * 1.5, "ranger adds damage")
	p.bag = {Sim.key("weapon", 2): 1}
	assert(p.equip("weapon", 2, 1) and p.heroes[1].equipped.weapon == 2 and p.heroes[0].equipped.weapon == -1)
	var t0 := 1000.0
	for i in 600:
		p.step(0.1, t0 + i * 0.1)
	assert(p.heroes[1].attacks > p.heroes[0].attacks, "ranger attacks faster")
	assert(p.heroes[1].level > 1 and p.heroes[1].level == p.heroes[0].level, "both heroes level together")
	# Knight pierce: every 5th hit is x3
	var k := Sim.new()
	var hits := []
	for i in 5:
		k.heroes[0].attacks += 1
		hits.append(k._hit_damage(0))
	assert(hits[4] == hits[0] * Sim.PIERCE_MULT and hits[3] == hits[0])
	# Old single-hero save migrates into the Knight
	var old := Sim.new()
	old.from_dict({"level": 7, "xp": 3, "equipped": {"weapon": 2}})
	assert(old.heroes[0].level == 7 and old.heroes[0].equipped.weapon == 2 and old.heroes[1].level == 1)
	var rt := Sim.new()
	rt.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert(rt.heroes[1].level == p.heroes[1].level and rt.heroes[1].equipped == p.heroes[1].equipped)

	# Acts: 2-3 is stage 13, X-10 ends with the act boss, act 1 never drops above Epic
	var a := Sim.new()
	a.rng.seed = 5
	a.stage = 13
	assert(a.act() == 2 and a.local_stage() == 3)
	a.stage = 10
	a.wave = Sim.WAVES_PER_STAGE + 1
	a._spawn()
	assert(a.is_act_boss())
	a.stage = 9
	a._spawn()
	assert(a.is_boss() and not a.is_act_boss())
	assert(a.mobs_per_wave() > 1)
	a.stage = 1
	assert(a.mobs_per_wave() == 1)
	for i in 3000:
		assert(a._roll_tier(1) <= 3, "act 1 caps at Epic")
	a.stage = 20
	var legendary := false
	for i in 3000:
		legendary = legendary or a._roll_tier(1) == 4
	assert(legendary, "act 2 can drop Legendary")
	a.stage = 30
	assert(a.act() == 3 and a.local_stage() == 10 and Sim.MAX_STAGE == Sim.STAGES_PER_ACT * Sim.ACT_NAMES.size())
	var mythic := false
	for i in 5000:
		mythic = mythic or a._roll_tier(1) == 5
	assert(mythic, "act 3 can drop Mythic")
	var clamp := Sim.new()
	clamp.from_dict({"stage": 99})
	assert(clamp.stage == Sim.MAX_STAGE)

	# Enhancement: pays gold, safe up to +5, weapon compounds ATK, failure keeps the level, survives save
	var e := Sim.new()
	e.rng.seed = 11
	e.gold = 0
	assert(e.enhance(0, "weapon").is_empty(), "no gold, no roll")
	e.gold = 100_000_000
	var base_atk := e.hero_atk()
	for i in 5:
		assert(e.enhance(0, "weapon").ok, "+1..+5 never fail")
	assert(is_equal_approx(e.hero_atk(), base_atk * pow(Sim.ENH_WEAPON_MULT, 5)))
	assert(Sim.enh_chance(5) < 1.0 and Sim.enh_chance(100) == Sim.ENH_MIN_CHANCE)
	var fails := 0
	for i in 300:
		var lv: int = e.heroes[0].enh.ring
		var g0 := e.gold
		var res := e.enhance(0, "ring")
		if res.is_empty():
			assert(e.gold == g0, "a refused try costs nothing")
			break
		assert(e.gold < g0, "every try costs gold")
		if not res.ok:
			fails += 1
			assert(e.heroes[0].enh.ring == lv, "failure never drops a level")
	assert(fails > 0)
	var g1 := e.gold_mult()
	e.heroes[0].enh.gloves = 10
	assert(e.hero_aps() > Sim.CLASSES.knight.aps * 1.19)
	var ce := Sim.new()
	ce.from_dict(JSON.parse_string(JSON.stringify(e.to_dict())))
	assert(ce.heroes[0].enh == e.heroes[0].enh and ce.gold_mult() == g1)
	var oe := Sim.new()
	oe.from_dict({"heroes": [{"level": 3}]})
	assert(oe.heroes[0].enh.weapon == 0, "saves without enh load as +0")

	# Portal: only unlocked stages, repeat keeps the stage but still unlocks the next
	var pt := Sim.new()
	assert(not pt.go_to_stage(2) and not pt.go_to_stage(0), "locked")
	pt.repeat = true
	_kill_boss(pt)
	assert(pt.stage == 1 and pt.max_stage == 2, "repeat stays, next stage unlocks")
	assert(pt.go_to_stage(2) and pt.stage == 2 and pt.wave == 1)
	pt.repeat = false
	_kill_boss(pt)
	assert(pt.stage == 3 and pt.max_stage == 3)
	assert(pt.go_to_stage(1) and pt.max_stage == 3, "going back keeps progress")
	var ptc := Sim.new()
	ptc.from_dict(JSON.parse_string(JSON.stringify(pt.to_dict())))
	assert(ptc.max_stage == 3 and ptc.stage == 1 and not ptc.repeat)
	var pto := Sim.new()
	pto.from_dict({"stage": 7})
	assert(pto.max_stage == 7, "old saves unlock up to their current stage")

	# Level gap penalty follows the TBH table (hero 30): -4 94%, -6 78%, -8 50%, -10 23%, -12 10%, -15 3%
	var tbh := {0: 1.0, 2: 1.0, 4: 0.94, 6: 0.78, 8: 0.50, 10: 0.23, 12: 0.10, 15: 0.03}
	for d in tbh:
		assert(absf(Sim.exp_mult(d) - tbh[d]) <= 0.04, "over by %d: %.3f vs TBH %.2f" % [d, Sim.exp_mult(d), tbh[d]])
	assert(Sim.exp_mult(-5) == 1.0 and Sim.exp_mult(-10) == 0.75 and Sim.exp_mult(-40) == Sim.UNDER_LEVEL_MIN)
	var lg := Sim.new()
	lg.stage = 10
	lg.heroes[0].level = lg.stage_level() + 8
	lg.wave = 2
	lg._spawn()
	lg.monster_hp = 0.001
	var xp0: int = lg.heroes[0].xp
	lg.heroes[0].cd = 0.0
	lg.step(0.01, 1.0)
	assert(lg.heroes[0].xp - xp0 == int(lg._exp_per_kill() * 0.5), "over-levelled hero gets half EXP")

	# Sorcerer: slot 3 needs both command runes, fireball every 4s for x4
	var so := Sim.new()
	so.rng.seed = 9
	so.gold = 1_000_000
	assert(not so.buy_rune("command2"), "needs command first")
	so.runes = {"growth": 1, "command": 1}
	var duo := so.team_dps()
	assert(so.buy_rune("command2") and so.party_size() == 3 and so.team_dps() > duo)
	so.stage = 30
	so.wave = 1
	so._spawn()
	so.monster_hp = 1e12  # unkillable: count raw damage
	var hp0 := so.monster_hp
	for i in 400:  # 40 s
		so.step(0.1, 2000.0 + i * 0.1)
	assert(so.heroes[2].casts == 10, "fireball every 4 s, got %d" % so.heroes[2].casts)
	var dealt := hp0 - so.monster_hp
	assert(absf(dealt / 40.0 - so.team_dps()) < so.team_dps() * 0.1, "team_dps matches the sim: %.0f vs %.0f" % [dealt / 40.0, so.team_dps()])
	var so2 := Sim.new()
	so2.from_dict({"heroes": [{"level": 9}, {"level": 4}]})
	assert(so2.heroes[2].cls == "sorcerer" and so2.heroes[2].level == 1, "2-hero saves get a fresh Sorcerer")

	# Sounds: every synth renders the right length, is audible, and never clips
	var Sfx := preload("res://sfx.gd")
	for name in Sfx.SOUNDS:
		var w: AudioStreamWAV = Sfx.build(name)
		var samples := 0
		for note in Sfx.SOUNDS[name][0]:
			samples += int(note[3] * Sfx.RATE)
		assert(w.data.size() == samples * 2, "%s: %d bytes, expected %d" % [name, w.data.size(), samples * 2])
		var peak := 0
		for i in range(0, w.data.size(), 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		assert(peak > 3000, "%s is near silent (peak %d)" % [name, peak])
		assert(Sfx.MODE_DB.has("off") and Sfx.SOUNDS[name][2] > 0.0)

	# Music: each act loop has the right length, is audible without clipping, has no click at the seam, and is deterministic
	var Music := preload("res://music.gd")
	for ai in Music.THEMES.size():
		var mu_t0 := Time.get_ticks_msec()
		var mu: AudioStreamWAV = Music.build(ai)
		var mu_ms := Time.get_ticks_msec() - mu_t0
		var mu_n := Music.loop_samples(ai)
		assert(mu.data.size() == mu_n * 2 and mu.loop_end == mu_n and mu.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		var mu_peak := 0
		var mu_clip := 0
		for i in range(0, mu.data.size(), 2):
			var mu_v := absi(mu.data.decode_s16(i))
			mu_peak = maxi(mu_peak, mu_v)
			if mu_v >= 32767:
				mu_clip += 1
		assert(mu_peak > 5000 and mu_clip == 0, "act %d: peak %d, mu_clip %d" % [ai + 1, mu_peak, mu_clip])
		assert(absi(mu.data.decode_s16(0)) < 1500 and absi(mu.data.decode_s16(mu.data.size() - 2)) < 1500, "act %d clicks at the loop seam" % [ai + 1])
		assert(Music.build(ai).data == mu.data, "act %d music is not deterministic" % [ai + 1])
		print("music act %d: %.1f s loop, peak %d, built in %d ms" % [ai + 1, float(mu_n) / Music.RATE, mu_peak, mu_ms])

	# Sprites: every row the same width, every char in the palette
	var Art := preload("res://art.gd")
	for n in Art.SPRITES:
		var rows: Array = Art.SPRITES[n]
		for y in rows.size():
			assert(rows[y].length() == rows[0].length(), "%s row %d: width %d, expected %d" % [n, y, rows[y].length(), rows[0].length()])
			for ch in rows[y]:
				assert(ch == "." or Art.PALETTE.has(ch), "%s row %d: unknown color %s" % [n, y, ch])

	print("OK stage=%d lv=%d gold=%d kills=%d bag=%d %s" % [s.stage, s.heroes[0].level, s.gold, s.kills, s.bag_total(), s.bag])
	_passed = true


func _kill_boss(s) -> void:
	s.wave = s.WAVES_PER_STAGE + 1
	s._spawn()
	s.monster_hp = 0.001
	s.heroes[0].cd = 0.0
	s.step(0.01, 1.0)


func _finish() -> void:
	quit(0 if _passed else 1)
