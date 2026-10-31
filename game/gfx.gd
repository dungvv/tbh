extends RefCounted
## Loads 0x72 sprite frames (CC0) and pixelfx sprite sheets (MIT), and plays effects.

static var _tex := {}
static var _anim := {}
static var _sheets := {}


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


## Frames of a 0x72 animation: "<name>_<kind>_anim_fN.png", or "<name>_anim_fN.png" for single-animation sprites.
static func anim(name: String, kind := "idle") -> Array:
	var key := name + ":" + kind
	if _anim.has(key):
		return _anim[key]
	var frames := []
	for pattern in ["res://art/0x72/%s_%s_anim_f%d.png", "res://art/0x72/%s_anim_f%d.png"]:
		for i in 4:
			var p: String = pattern % [name, kind, i] if pattern.count("%s") == 2 else pattern % [name, i]
			var t := tex(p)
			if t != null:
				frames.append(t)
		if not frames.is_empty():
			break
	if frames.is_empty() and kind != "idle":
		frames = anim(name, "idle")
	_anim[key] = frames
	return frames


static func frame(name: String, kind: String, t: float, fps := 8.0) -> Texture2D:
	var fr := anim(name, kind)
	if fr.is_empty():
		return null
	return fr[int(t * fps) % fr.size()]


## A pixelfx sheet: {tex, w, h, cols, n, dur (s), loop}.
static func sheet(id: String) -> Dictionary:
	if _sheets.has(id):
		return _sheets[id]
	var s := {}
	var jp := "res://fx/%s.json" % id
	if FileAccess.file_exists(jp):
		var j = JSON.parse_string(FileAccess.get_file_as_string(jp))
		var t := tex("res://fx/%s.png" % id)
		if typeof(j) == TYPE_DICTIONARY and t != null and j.frames.size() > 0:
			var f0: Dictionary = j.frames[0].frame
			var total := 0.0
			for f in j.frames:
				total += f.duration
			s = {"tex": t, "w": f0.w, "h": f0.h, "cols": int(t.get_width() / f0.w), "n": j.frames.size(),
				"dur": total / 1000.0}
	_sheets[id] = s
	return s


## Draw one frame of an effect, centered at `pos`. `p` = progress 0..1 (wraps for loops).
static func draw_fx(ci: CanvasItem, id: String, pos: Vector2, p: float, scale := 1.0, flip := false, mod := Color.WHITE) -> void:
	var s := sheet(id)
	if s.is_empty():
		return
	var i := clampi(int(fposmod(p, 1.0) * s.n), 0, s.n - 1)
	var src := Rect2((i % s.cols) * s.w, (i / s.cols) * s.h, s.w, s.h)
	var size := Vector2(s.w, s.h) * scale
	var dst := Rect2(pos - size / 2.0, size)
	if flip:
		dst = Rect2(Vector2(pos.x + size.x / 2.0, pos.y - size.y / 2.0), Vector2(-size.x, size.y))
	ci.draw_texture_rect_region(s.tex, dst, src, mod)


## Draw a sprite frame with its feet at `feet` (bottom center), optionally mirrored.
static func draw_sprite(ci: CanvasItem, t: Texture2D, feet: Vector2, scale: float, flip := false, mod := Color.WHITE) -> Rect2:
	if t == null:
		return Rect2(feet, Vector2.ZERO)
	var size := t.get_size() * scale
	var r := Rect2(feet - Vector2(size.x / 2.0, size.y), size)
	var dst := r
	if flip:
		dst = Rect2(Vector2(r.end.x, r.position.y), Vector2(-size.x, size.y))
	ci.draw_texture_rect(t, dst, false, mod)
	return r
