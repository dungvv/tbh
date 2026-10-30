extends SceneTree
## Render the game in a chosen state and save the left part as a PNG. Run (not headless):
## godot --path . --script res://tools/screenshot.gd -- /tmp/shot.png [bag|rune|forge|portal] [stage=13] [wave=11]
## Uses sample bag/runes/party so panels have something to show. Does not touch the save file.

const Sim := preload("res://sim.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var s = main.sim
	s.bag = {Sim.key("weapon", 0): 12, Sim.key("weapon", 2): 3, Sim.key("gloves", 1): 9,
		Sim.key("ring", 3): 2, Sim.key("ring", 4): 1}
	s.equip("weapon", 2)
	s.runes = {"growth": 5, "repose": 1, "greed": 2, "chest_time": 1, "haste": 1, "command": 1, "command2": 1, "might": 2, "focus": 1, "mastery": 12}
	s.heroes[1].level = 4
	s.heroes[2].level = 3
	s.heroes[0].enh = {"weapon": 8, "gloves": 3, "ring": 2}
	s.heroes[1].enh = {"weapon": 5, "gloves": 0, "ring": 0}
	s.gold = 2000
	s.max_stage = 14
	main.sel_slot = "ring"
	main.sel_tier = 3
	main.sel_rune = "mastery"
	for a in args:
		if a.begins_with("stage="):
			s.stage = int(a.substr(6))
		elif a.begins_with("wave="):
			s.wave = int(a.substr(5))
		elif a in ["bag", "rune", "forge", "portal"]:
			main._toggle_panel(a)
	s._spawn()
	main._toast_left = 0.0  # hide toasts left over from loading the real save
	for i in 5:
		await process_frame
	if "fire" in args:  # freeze projectiles mid-flight
		main._fire_t = 0.12
		main._swing[2] = 0.3
		main._arrow_t = 0.07
		main._swing[1] = 0.1
		await process_frame
	var path: String = args[0] if args.size() > 0 and args[0].ends_with(".png") else "/tmp/shot.png"
	var img := root.get_texture().get_image()
	img.get_region(Rect2i(0, 0, mini(img.get_width(), 1300), img.get_height())).save_png(path)  # left side: HUD + panels
	print("saved ", path)
	quit()
