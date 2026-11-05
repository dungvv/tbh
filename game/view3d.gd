extends SubViewport
## The battle drawn in 3D (KayKit and Quaternius chibi models, CC0; see art3d/README.md).
## sim.gd stays 2D: main.gd decides where each hero and monster stands on the strip, this viewport puts a
## 3D actor there and plays its animations, and main.gd draws the result under bars, numbers and effects.
## An orthographic camera keeps the mapping linear: PX_PER_UNIT canvas pixels per world unit, ground at y = 0.

const D := preload("res://data.gd")
const PX_PER_UNIT := 40.0
const HERO_PX := 62.0  # standing height of a hero on screen; monsters use MOB_PX × their size
const MOB_PX := 56.0
const YAW := 35.0  # heroes face right, monsters left, both turned this far from side-on toward the camera
const PITCH := -12.0  # camera looks slightly down
const FLY_UNITS := 0.35  # flying monsters hover above the ground
const HIGH_WEAPON := 3  # weapons from this rarity use the bigger model (two-handed axe, staff, crossbow)
const LOOPS := ["idle", "idle2", "run"]
## Skeleton animation and the 3D render run at this rate (bars, numbers and effects stay at 30 fps).
## At 30 fps the 3D layer took about 3/4 of the game's idle CPU; chibi motion still reads well at 15.
const ANIM_FPS := 15.0
const OVERLAY := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, depth_test_disabled;
uniform vec4 tint : source_color = vec4(0.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb * tint.a * (0.3 + rim);
}
"""

## Matte cel shading instead of the imported PBR materials, which looked glossy at this size: two soft tones
## from a fixed light in view space, no specular, a faint warm rim. Unshaded, so scene lights do not matter.
const TOON := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vcol = false;
uniform vec3 light_dir = vec3(-0.35, 0.75, 0.55);
uniform float shade = 0.74;
void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo;
	if (use_vcol) {
		c *= COLOR;
	}
	float l = dot(normalize(NORMAL), normalize(light_dir));
	vec3 col = c.rgb * mix(shade, 1.0, smoothstep(-0.1, 0.2, l));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col + vec3(1.0, 0.95, 0.85) * rim * 0.1;
}
"""

var cam := Camera3D.new()
var _manifest := {}
var _scenes := {}
var _shader := Shader.new()
var _toon := Shader.new()
var _toon_mats := {}  # imported material -> its cel-shaded replacement
var _white: ImageTexture
var _actors := {}  # key (class name or monster uid) -> actor dictionary, see _make()
var _rect := Rect2()
var _acc := 0.0  # time not yet given to the animation players


func _init() -> void:
	own_world_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	msaa_3d = Viewport.MSAA_2X
	_shader.code = OVERLAY
	_toon.code = TOON
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.rotation_degrees = Vector3(PITCH, 0, 0)
	cam.far = 100.0
	add_child(cam)
	var f := FileAccess.get_file_as_string("res://art3d/manifest.json")
	_manifest = JSON.parse_string(f) if f != "" else {}


## Place the viewport over `rect` (canvas units, main.gd draws the texture there) at `scale` pixels per unit,
## with the ground line at canvas y = `ground`.
func layout(rect: Rect2, scale: float, ground: float) -> void:
	_rect = rect
	var want := Vector2i(maxi(1, int(rect.size.x * scale)), maxi(1, int(rect.size.y * scale)))
	if size != want:
		size = want
	cam.size = rect.size.y / PX_PER_UNIT
	# world (0, 0, 0) must land at the canvas point (rect center x, ground). A point X shows at
	# dot(X - cam.position, cam up) world units above the view center, so with the camera at
	# 20 units back plus k along its up axis, the origin shows k below the center.
	var drop := (ground - rect.get_center().y) / PX_PER_UNIT
	cam.position = cam.basis.z * 20.0 + cam.basis.y * drop


func world_x(canvas_x: float) -> float:
	return (canvas_x - _rect.get_center().x) / PX_PER_UNIT


## Height in canvas pixels of an actor, for bars and names drawn above its head.
func px_height(key) -> float:
	return _actors[key].px if _actors.has(key) else HERO_PX


# =========================================================== actors

func _make(key, model: String, px: float, right: bool) -> Dictionary:
	if _actors.has(key):
		if _actors[key].model == model:
			return _actors[key]
		_actors[key].node.queue_free()
	if not _scenes.has(model):
		var p := "res://art3d/%s.glb" % model
		_scenes[model] = load(p) if ResourceLoader.exists(p) else null
	var node: Node3D = _scenes[model].instantiate() if _scenes[model] != null else Node3D.new()
	add_child(node)
	_toonify(node)
	var aps := node.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if aps.size() > 0 else null
	var a := {"key": key, "model": model, "node": node, "ap": ap, "px": px, "base": "idle", "busy": false, "dead": false,
		"seen": true, "gone": -1.0, "mat": ShaderMaterial.new(), "weapon_mat": ShaderMaterial.new(), "tint": Color(0, 0, 0, 0),
		"meshes": node.find_children("*", "MeshInstance3D", true, false), "gear": ""}
	a.mat.shader = _shader
	a.weapon_mat.shader = _shader
	if ap != null:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL  # advanced in end_frame()
		for n in LOOPS:
			if ap.has_animation(n):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		ap.animation_finished.connect(func(_n): _finished(a))
		ap.play("idle")
		ap.seek(randf() * 0.8)
	var info: Dictionary = _manifest.get(model, {})
	var k: float = (px / PX_PER_UNIT) / info.get("height", 2.4)
	node.scale = Vector3.ONE * k
	a["lift"] = -info.get("foot", 0.0) * k  # some models have their origin mid-body (tools/measure_models.gd)
	node.rotation_degrees.y = (90.0 - YAW) * (1.0 if right else -1.0)
	_actors[key] = a
	return a


func _toonify(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			if not src is BaseMaterial3D:
				continue
			if not _toon_mats.has(src):
				var t := ShaderMaterial.new()
				t.shader = _toon
				t.set_shader_parameter("albedo_tex", src.albedo_texture if src.albedo_texture != null else _white)
				t.set_shader_parameter("albedo", src.albedo_color)
				t.set_shader_parameter("use_vcol", src.vertex_color_use_as_albedo)
				_toon_mats[src] = t
			mi.set_surface_override_material(i, _toon_mats[src])


func _finished(a: Dictionary) -> void:
	a.busy = false
	if not a.dead and a.ap != null:
		a.ap.play(a.base, 0.15)


## Call before placing actors each frame; actors not placed again are removed in end_frame().
func begin_frame() -> void:
	for k in _actors:
		_actors[k].seen = false


func end_frame(delta: float) -> void:
	_acc += delta
	if _acc >= 1.0 / ANIM_FPS:
		for k in _actors:
			if _actors[k].ap != null:
				_actors[k].ap.advance(_acc)
		_acc = 0.0
		render_target_update_mode = SubViewport.UPDATE_ONCE
	for k in _actors.keys():
		var a: Dictionary = _actors[k]
		if a.seen:
			continue
		if typeof(k) == TYPE_STRING:  # a hero left the party
			a.node.queue_free()
			_actors.erase(k)
			continue
		if a.gone < 0.0:  # a monster died: play its death, then shrink away
			a.gone = 0.0
			_play(a, "death", 1.0, true)
			a.dead = true
			_tint(a, Color(0, 0, 0, 0))
		a.gone += delta
		if a.gone > 0.9:
			a.node.scale *= 0.75
		if a.gone > 1.3:
			a.node.queue_free()
			_actors.erase(k)


func _play(a: Dictionary, anim: String, speed := 1.0, force := false) -> void:
	if a.ap == null or (a.dead and not force):
		return
	if not a.ap.has_animation(anim):
		anim = "attack" if anim in ["skill", "attack2"] and a.ap.has_animation("attack") else a.base
	a.busy = not anim in LOOPS
	a.ap.play(anim, 0.08, speed)


func _tint(a: Dictionary, c: Color) -> void:
	if c == a.tint:
		return
	a.tint = c
	a.mat.set_shader_parameter("tint", c)
	for m in a.meshes:
		if m.material_overlay != a.weapon_mat:
			m.material_overlay = a.mat if c.a > 0.0 else null


## One hero standing with its feet at canvas `feet`.
func hero(cls: String, feet: Vector2, h: Dictionary, dead: bool, hurt: bool) -> void:
	var a := _make(cls, cls, HERO_PX, true)
	a.seen = true
	a.node.position = Vector3(world_x(feet.x), a.lift, 0)
	var g: Dictionary = D.HERO_MODELS[cls]
	var w = h.equip.weapon
	var heavy: bool = w != null and w.rarity >= HIGH_WEAPON
	var armor_r: int = h.equip.armor.rarity if h.equip.armor != null else 0
	var gear := "%s/%s/%d/%d/%d" % [heavy, armor_r, h.outfit, w.rarity if w != null else -1, w.enh if w != null else 0]
	if gear != a.gear:  # Q15.1 B: what the hero wears shows on the model
		a.gear = gear
		var show: Array = g.high if heavy else g.low
		if g.has("shields"):
			show = show + [g.shields[armor_r]]
		for n in g.gear:
			var m: Node3D = a.node.find_child(n, true, false)
			if m != null:
				m.visible = n in show
		if g.hat != "":
			var hat: Node3D = a.node.find_child(g.hat, true, false)
			if hat != null:
				hat.visible = h.outfit == 0
		a.base = "idle2" if heavy and a.ap != null and a.ap.has_animation("idle2") else "idle"
		var glow := Color(0, 0, 0, 0)
		if w != null and w.enh >= 7:  # Q15.3 B: weapon glow from +7, brighter at +10 and +13
			glow = D.RARITIES[w.rarity].color if w.enh < 13 else Color(1.0, 0.95, 0.5)
			glow.a = 0.6 + (0.5 if w.enh >= 10 else 0.0) + (0.5 if w.enh >= 13 else 0.0)
		a.weapon_mat.set_shader_parameter("tint", glow)
		for n in show:
			var wm: Node = a.node.find_child(n, true, false)
			for mi in ([wm] if wm is MeshInstance3D else (wm.find_children("*", "MeshInstance3D", true, false) if wm != null else [])):
				mi.material_overlay = a.weapon_mat if glow.a > 0.0 else null
		if not a.busy and not a.dead and a.ap != null:
			a.ap.play(a.base, 0.15)
	if dead and not a.dead:
		a.dead = true
		_play(a, "death", 1.0, true)
	elif not dead and a.dead:
		a.dead = false
		_play(a, a.base)
	_tint(a, Color(1, 0.3, 0.3, 0.9) if hurt else Color(0, 0, 0, 0))


## One monster. `moving` while it slides into place.
func mob(m: Dictionary, feet: Vector2, moving: bool, hurt: bool, t: float) -> void:
	var size: float = m.size * (m.scale if not m.act_boss else 1.0)
	var a := _make(m.uid, m.model, MOB_PX * size, false)
	a.seen = true
	a.node.position = Vector3(world_x(feet.x), a.lift + (FLY_UNITS if m.fly else 0.0), 0.3)
	var base := "run" if moving else "idle"
	if base != a.base:
		a.base = base
		if not a.busy and a.ap != null:
			a.ap.play(base, 0.2)
	var c := Color(0, 0, 0, 0)
	if hurt:
		c = Color(1, 1, 1, 1.2)
	elif m.elite.size() > 0:
		c = Color(1.0, 0.75, 0.2, 0.7 + 0.3 * sin(t * 4.0))
	elif m.boss and not m.act_boss:
		c = Color(1.0, 0.25, 0.2, 0.6)
	if m.warn > 0.0:
		c = Color(1.0, 0.1, 0.1, 1.0 + 0.6 * sin(t * 20.0))
	_tint(a, c)


## Animation triggers from battle events. rate = attacks per second, so a swing finishes before the next one.
func act(key, anim: String, rate := 1.0) -> void:
	if not _actors.has(key):
		return
	var a: Dictionary = _actors[key]
	if a.ap == null or not a.ap.has_animation(anim if a.ap.has_animation(anim) else "attack"):
		return
	if anim == "attack" and a.base == "idle2" and a.ap.has_animation("attack2"):
		anim = "attack2"
	var len: float = a.ap.get_animation(anim if a.ap.has_animation(anim) else "attack").length
	_play(a, anim, maxf(1.0, len * rate * 1.1))


func cheer() -> void:
	for k in _actors:
		if typeof(k) == TYPE_STRING and not _actors[k].dead:
			_play(_actors[k], "cheer")
