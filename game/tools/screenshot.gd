extends SceneTree
## Render the game in a chosen state and save the left part as a PNG. Run (not headless):
## godot --path . --script res://tools/screenshot.gd -- /tmp/shot.png [bag|hero|forge|rune|portal|settings] [stage=13] [diff=1] [boss] [t=3]
## Builds a sample mid-game save in memory. Does not touch the real save file.

const Sim := preload("res://sim.gd")
const D := preload("res://data.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var s = main.sim
	s.rng.seed = 42
	s.gold = 5_000_000
	for r in ["growth", "unlock_ranger", "command", "unlock_cleric", "unlock_sorcerer", "command2", "vitality", "greed", "might"]:
		s.buy_rune(r)
	s.gold = 1_234_567
	s.max_stage = [30, 30, 12, 0]
	s.stones = [12, 5, 3, 1, 0]
	for c in s.owned:
		s.heroes[c].level = 34
		for sk in D.SKILLS[c]:
			s.learn(c, sk.id, 25)
	s.set_party_slot(0, "knight")
	s.set_party_slot(1, "ranger")
	s.set_party_slot(2, "sorcerer")
	for c in s.party:
		for sl in D.SLOTS:
			var it: Dictionary = s.make_item(sl, 2 + s.rng.randi() % 4)
			if sl == "weapon":
				it.kind = D.CLASSES[c].weapon
			if sl == "armor":
				it.kind = D.CLASSES[c].armor_kind
			it.enh = s.rng.randi() % 12
			s.bag.append(it)
			s.equip(c, it.uid)
	for i in 30:
		s._receive(s.make_item(D.SLOTS[i % 6], s.roll_rarity()))
	s.bag[3].locked = true
	main.sel_item = s.heroes.knight.equip.weapon.uid
	var t := 2.0
	for a in args:
		if a.begins_with("stage="):
			s.stage = int(a.substr(6))
		elif a.begins_with("diff="):
			s.diff = int(a.substr(5))
		elif a.begins_with("t="):
			t = float(a.substr(2))
		elif a in ["bag", "hero", "forge", "rune", "portal", "settings"]:
			main.toggle_panel(a)
	s._start_stage()
	if "boss" in args:
		s.wave = s.waves_in_stage() + 1
	main._toast_left = 0.0
	for i in int(t * 30):  # let the battle run a little so effects are on screen
		main._process(1.0 / 30.0)
		await process_frame
	var path: String = args[0] if args.size() > 0 and args[0].ends_with(".png") else "/tmp/shot.png"
	var img := root.get_texture().get_image()
	img.get_region(Rect2i(0, 0, mini(img.get_width(), 1700), img.get_height())).save_png(path)
	print("saved ", path)
	quit()
