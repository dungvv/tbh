extends SceneTree
## Greedy bot that plays N hours and prints progress per hour. Use it to tune numbers in sim.gd.
## Run: godot --headless --path . --script res://tools/balance.gd -- 12

const Sim := preload("res://sim.gd")
const DT := 0.5
const CHORE_EVERY := 60.0  # the bot checks in once a minute, like a player glancing at the taskbar


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var hours := int(args[0]) if args.size() > 0 else 12
	var s := Sim.new()
	s.rng.seed = 1
	var now := 0.0
	var next_chore := 0.0
	var first_clear := {}  # stage -> minute it was first reached
	print("hour  stage  lv(K/R)  dps       monster_hp  gold      runes")
	for step in int(hours * 3600 / DT):
		s.step(DT, now)
		now += DT
		if not first_clear.has(s.stage):
			first_clear[s.stage] = [int(now / 60), s.heroes[0].level]
		if now >= next_chore:
			next_chore += CHORE_EVERY
			_chores(s)
		if fmod(now, 3600.0) < DT:
			var rl := 0
			for v in s.runes.values():
				rl += v
			print("%4d  %d-%-2d   %3d/%-3d  %-8d  %-10d  %-8d  %d" % [now / 3600, s.act(), s.local_stage(),
				s.heroes[0].level, s.heroes[1].level, s.team_dps(), s.monster_max_hp, s.gold, rl])
	var line := "first reached (minute, Knight level): "
	for st in first_clear:
		line += "%d-%d@%dm(L%d) " % [(st - 1) / Sim.STAGES_PER_ACT + 1, (st - 1) % Sim.STAGES_PER_ACT + 1, first_clear[st][0], first_clear[st][1]]
	print(line)
	quit()


func _chores(s) -> void:
	while s.open_chest():
		pass
	s.auto_synth()
	for tier in range(Sim.SAFE_SYNTH_TIERS, Sim.SYNTH.size()):  # gamble the risky tiers too
		for slot in Sim.SLOTS:
			while s.count(slot, tier) >= 9:
				s.synth(slot, tier)
	for i in s.party_size():
		for slot in Sim.SLOTS:
			for tier in range(Sim.TIERS.size() - 1, -1, -1):
				if tier > s.heroes[i].equipped[slot] and s.count(slot, tier) > 0:
					s.equip(slot, tier, i)
					break
	while true:  # buy the cheapest rune or enhancement we can afford
		var best := []
		var best_cost := INF
		for r in Sim.RUNES:
			if s.can_buy_rune(r.id) and s.rune_cost(r.id) < best_cost:
				best = ["rune", r.id]
				best_cost = s.rune_cost(r.id)
		for i in s.party_size():
			for slot in Sim.SLOTS:
				if s.enh_cost(i, slot) <= s.gold and s.enh_cost(i, slot) < best_cost:
					best = ["enh", i, slot]
					best_cost = s.enh_cost(i, slot)
		if best.is_empty():
			break
		if best[0] == "rune":
			s.buy_rune(best[1])
		else:
			s.enhance(best[1], best[2])
