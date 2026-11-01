extends SceneTree
## Bot that plays N hours and prints progress per hour. Use it to tune numbers in data.gd (Q5.5 C, Q6.9).
## Run: godot --headless --path . --script res://tools/balance.gd -- 24 [seed]

const Sim := preload("res://sim.gd")
const D := preload("res://data.gd")
const DT := 0.25
const CHORE_EVERY := 60.0  # the bot checks in once a minute, like a player glancing at the taskbar

var _last_wipes := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var hours := float(args[0]) if args.size() > 0 else 24.0
	var s := Sim.new()
	s.rng.seed = int(args[1]) if args.size() > 1 else 1
	var now := 0.0
	var next_chore := 0.0
	var wipes := 0
	var last_boss := 1.0
	var last_mobs := []
	var killers := {}  # monsters still standing when the party wiped on the last difficulty
	var boss_left := 1.0  # lowest boss HP fraction seen at a wipe this hour: how close the wall is
	var reached := {}
	var farm_until := 0.0  # after repeated wipes the bot farms the previous stage for a while, like a player would
	print("hour  diff stage  lv(party)        dps        gold      wipes  bag  best-rarity  boss-hp-at-wipe")
	for i in int(hours * 3600 / DT):
		last_boss = 1.0
		last_mobs = []
		for m in s.mobs:
			if m.hp > 0.0:
				last_mobs.append("%s%s" % [m.id, "*%d" % m.elite.size() if m.elite.size() > 0 else ""])
		for m in s.mobs:
			if m.boss:
				last_boss = m.hp / m.max
		s.step(DT, now)
		now += DT
		for e in s.events:
			if e.t == "wipe":
				wipes += 1
				boss_left = minf(boss_left, last_boss)
				if s.diff == 3:
					for id in last_mobs:
						killers[id] = killers.get(id, 0) + 1  # mobs are already cleared here, use the frame before
		s.events.clear()
		for d in 4:
			if not reached.has("done%d" % d) and s.first_kills.has("campaign:%d:30:0" % d):
				reached["done%d" % d] = [int(now / 60), 60]
		var key := "%d-%d" % [s.diff, s.stage]
		if s.mode == "campaign" and not reached.has(key):
			reached[key] = [int(now / 60), s.heroes[s.party[0]].level]
		if now >= next_chore:
			next_chore += CHORE_EVERY
			_chores(s)
			var w_now := wipes
			if s.mode == "campaign" and w_now - _last_wipes >= 2 and s.stage > 1:
				s.go_to(s.diff, s.stage - 1)
				s.repeat = true
				farm_until = now + 1800.0
			elif s.repeat and now >= farm_until:
				s.repeat = false
				s.go_to(s.diff, s.max_stage[s.diff])
			_last_wipes = w_now
		if fmod(now, 3600.0) < DT:
			var lvs := s.party.map(func(c): return s.heroes[c].level)
			var best := -1
			for c in s.party:
				for sl in D.SLOTS:
					var it = s.heroes[c].equip[sl]
					if it != null:
						best = maxi(best, it.rarity)
			print("%4d  %d    %d-%-2d   %-16s %-10d %-9d %-6d %-4d %d     %.2f" % [now / 3600, s.diff, s.act(), s.local_stage(),
				str(lvs), s.team_dps(), s.gold, wipes, s.bag.size(), best, boss_left])
			boss_left = 1.0
	var line := "first reached (min, lv): "
	for k in reached:
		var st: int = 1 if k.begins_with("done") else int(k.split("-")[1])
		if st % 5 == 0 or st == 1:
			line += "%s@%d(L%d) " % [k, reached[k][0], reached[k][1]]
	print(line)
	print("runes: ", s.runes)
	for c in s.party:
		print(c, " ", D.SLOTS.map(func(sl): return "%s r%d +%d" % [sl, s.heroes[c].equip[sl].rarity, s.heroes[c].equip[sl].enh] if s.heroes[c].equip[sl] != null else "-"), " ", s.stats(c))
	print("stones ", s.stones)
	print("alive at wipe (diff 3): ", killers)
	quit()


static func _score(s, cls: String, it) -> float:
	if it == null:
		return 0.0
	var st: Dictionary = Sim.item_stats(it)
	var c: Dictionary = D.CLASSES[cls]
	return st.get("atk", 0.0) * 2.0 + st.get("hp", 0.0) * 0.2 + st.get("armor", 0.0) + st.get("mres", 0.0) * 5.0 \
		+ (st.get("atk_pct", 0.0) + st.get("aspd_pct", 0.0) + st.get("crit", 0.0) + st.get("hp_pct", 0.0)) * 60.0 \
		+ (st.get("critdmg", 0.0) + st.get("skill_dmg", 0.0) + st.get("dmg_boss", 0.0) + st.get("armor_pct", 0.0)) * 25.0 \
		+ (st.get("dmg_reduce", 0.0) + st.get("block", 0.0)) * 80.0 + c.atk * 0.0


func _chores(s) -> void:
	while s.open_chest():
		pass
	# equip the best item per slot for each party hero
	for cls in s.party:
		for sl in D.SLOTS:
			var best = s.heroes[cls].equip[sl]
			var best_uid := -1
			for it in s.bag:
				if it.slot == sl and s.can_wear(cls, it) and _score(s, cls, it) > _score(s, cls, best):
					best = it
					best_uid = it.uid
			if best_uid >= 0:
				s.equip(cls, best_uid)
	# keep the bag small: dismantle what is not better than worn gear
	for it in s.bag.duplicate():
		if it.rarity <= 2 or s.bag.size() > 30:
			s.dismantle(it.uid)
	# spend skill points: actives in order, then passives
	for cls in s.party:
		var ids: Array = D.SKILLS[cls].map(func(x): return x.id) + D.PASSIVES.map(func(x): return x.id)
		var guard := 0
		while s.skill_points(cls) > 0 and guard < 400:
			guard += 1
			var learned := false
			for id in ids:
				if s.learn(cls, id) > 0:
					learned = true
					break
			if not learned:
				break
	# enhance worn weapon and armor while cheap, then buy the cheapest rune
	for k in 300:
		var best_cost := INF
		var pick := {}
		for r in D.RUNES:
			var capped: bool = s.party.all(func(c): return s.heroes[c].level >= D.LEVEL_CAP)
			if capped and r.id in ["training", "wisdom"]:
				continue  # EXP is useless once the party is at the level cap
			if s.can_buy_rune(r.id) and s.rune_cost(r.id) < best_cost:
				best_cost = s.rune_cost(r.id)
				pick = {"rune": r.id}
		for cls in s.party:
			for sl in D.SLOTS:
				var it = s.heroes[cls].equip[sl]
				if it == null or it.enh >= D.ENH_MAX:
					continue
				var lvl := 0
				for i in 5:
					if s.stones[i] > 0:
						lvl = i + 1
				if lvl == 0:
					continue
				var c: int = s.enh_cost(it) + (s.protect_cost(it) if it.enh >= 6 else 0)
				if c < best_cost and c <= s.gold:
					best_cost = c
					pick = {"enh": it.uid, "lvl": lvl}
		if pick.is_empty() or best_cost > s.gold:
			break
		if pick.has("rune"):
			s.buy_rune(pick.rune)
		else:
			s.enhance(pick.enh, pick.lvl, mini(3, s.stones[pick.lvl - 1]), true)
	# best party order: tank first, healer and casters behind
	# a player who keeps wiping brings the healer
	var order := ["knight", "berserker", "assassin", "ranger", "sorcerer", "cleric"]
	if s.repeat and "cleric" in s.owned:
		order = ["knight", "cleric", "berserker", "assassin", "ranger", "sorcerer"]
	var want := []
	for c in order:
		if c in s.owned and want.size() < s.party_size():
			want.append(c)
	if want != s.party:
		for i in want.size():
			s.set_party_slot(i, want[i])
	# move up a difficulty once it opens
	for d in range(3, -1, -1):
		if s.max_stage[d] > 0 and d > s.diff and s.stage == D.STAGES:
			s.go_to(d, 1)
			break
