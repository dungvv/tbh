extends SceneTree
## Measure how tall each art3d model really stands on screen in its idle pose and write it to
## art3d/manifest.json: "height" and "foot" (lowest visible point relative to the model origin), world units. Blender's rest-pose numbers can be off for rigs with scaled
## bones, so the game sizes actors from this render instead. Run (not headless) after tools/build_models.py:
## godot --path . --script res://tools/measure_models.gd

const D := preload("res://data.gd")
const RES := 512
const VIEW := 16.0  # world units seen top to bottom, centered on the model origin


func _initialize() -> void:
	var path := "res://art3d/manifest.json"
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = VIEW
	cam.position = Vector3(0, 0, 20)
	vp.add_child(cam)
	vp.add_child(DirectionalLight3D.new())
	for name in man:
		var node: Node3D = load("res://art3d/%s.glb" % name).instantiate()
		vp.add_child(node)
		for g in D.HERO_MODELS.get(name, {}).get("gear", []):  # heroes: body only, gear changes with items
			var m: Node3D = node.find_child(g, true, false)
			if m != null:
				m.visible = false
		var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
		ap.play("idle")
		ap.seek(0.0, true)
		await process_frame
		await process_frame
		var r := _visible_rows(vp.get_texture().get_image())
		var unit := VIEW / RES  # world units per pixel row
		var h := (r.y - r.x + 1) * unit
		var foot := (RES / 2.0 - r.y - 1) * unit
		print("%-14s blender %.2f  godot %.2f  foot %.2f" % [name, man[name].height, h, foot])
		man[name].height = snappedf(h, 0.001)
		man[name].foot = snappedf(foot, 0.001)
		node.queue_free()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(man, " ", true))
	quit()


## First and last pixel rows that show anything.
static func _visible_rows(img: Image) -> Vector2i:
	var top := -1
	var bottom := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				if top < 0:
					top = y
				bottom = y
				break
	return Vector2i(top, bottom)
