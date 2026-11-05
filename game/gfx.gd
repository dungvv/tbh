extends RefCounted
## Loads pixelfx sprite sheets (MIT), 0x72 item icons (CC0) and 3D hero portraits, and plays effects.

static var _tex := {}
static var _sheets := {}
static var _portraits := {}


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


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
## Hero portrait rendered by tools/build_models.py, resized once to `px` screen pixels: the game draws
## with nearest filtering for its pixel art, which would make a scaled-down render look ragged.
static func portrait(cls: String, px: int) -> Texture2D:
	var key := "%s:%d" % [cls, px]
	if not _portraits.has(key):
		var t := tex("res://art3d/portraits/%s.png" % cls)
		var out: Texture2D = null
		if t != null:
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			img.resize(px, px, Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(img)
		_portraits[key] = out
	return _portraits[key]
