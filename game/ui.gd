extends RefCounted
## Look of the HUD and panels, chibi fantasy style to match the 3D characters: deep plum frames with gold trim,
## chunky rounded buttons with a pressed-down lip, capsule bars and bold outlined text.
## Everything goes through StyleBoxFlat so corners stay smooth at any UI scale.

const INK := Color(0.07, 0.05, 0.11)  # text outline and deepest shadow
const FRAME := Color(0.15, 0.12, 0.23, 0.95)
const CARD := Color(0.23, 0.19, 0.33)
const CARD_HI := Color(0.36, 0.29, 0.5)
const GOLD := Color(0.95, 0.76, 0.33)
const GOLD_DIM := Color(0.62, 0.47, 0.22)
const TEXT := Color(1.0, 0.97, 0.9)
const TEXT_DIM := Color(0.74, 0.7, 0.8)
const BUTTONS := {
	"normal": Color(0.4, 0.33, 0.58),
	"active": Color(0.93, 0.6, 0.24),
	"good": Color(0.33, 0.66, 0.36),
	"danger": Color(0.78, 0.27, 0.27),
	"chest": Color(0.86, 0.62, 0.2),
}
const GEMS := [Color(0.75, 0.75, 0.8), Color(0.4, 0.85, 0.45), Color(0.35, 0.6, 1.0), Color(0.72, 0.4, 0.98), Color(1.0, 0.62, 0.15)]

static var _boxes := {}
static var _font: Font = null


## Bold variant of the default font: rounder and easier to read over the battle.
static func font() -> Font:
	if _font == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 0.55
		_font = f
	return _font


static func _box(bg: Color, border: Color, bw: int, radius: int, shadow := 0) -> StyleBoxFlat:
	var key := [bg, border, bw, radius, shadow]
	if not _boxes.has(key):
		var b := StyleBoxFlat.new()
		b.bg_color = bg
		b.border_color = border
		b.set_border_width_all(bw)
		b.set_corner_radius_all(radius)
		b.anti_aliasing = true
		b.corner_detail = 6
		if shadow > 0:
			b.shadow_color = Color(0, 0, 0, 0.35)
			b.shadow_size = shadow
			b.shadow_offset = Vector2(0, 2)
		_boxes[key] = b
	return _boxes[key]


## Outer window: plum with a gold rim.
static func frame(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_style_box(_box(FRAME, GOLD_DIM, 2, 12, 6), r)
	ci.draw_style_box(_box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), 1, 10), r.grow(-3))


## Inner block (a list row, a stat box). `hi` marks the selected one.
static func card(ci: CanvasItem, r: Rect2, hi := false, tint := Color(0, 0, 0, 0)) -> void:
	var bg := CARD_HI if hi else CARD
	if tint.a > 0.0:
		bg = bg.lerp(tint, tint.a)
	ci.draw_style_box(_box(bg, GOLD if hi else Color(0, 0, 0, 0.35), 2 if hi else 1, 8), r)


## Chunky button: a darker lip under the face, a soft highlight on top. Returns the face rect.
static func button_face(ci: CanvasItem, r: Rect2, col: Color, hover: bool, enabled: bool) -> Rect2:
	if not enabled:
		col = col.lerp(Color(0.3, 0.28, 0.35), 0.7)
	elif hover:
		col = col.lightened(0.15)
	var radius := int(minf(9.0, r.size.y / 2.0))
	ci.draw_style_box(_box(col.darkened(0.45), INK, 1, radius), r)
	var face := Rect2(r.position, r.size - Vector2(0, 3))
	ci.draw_style_box(_box(col, col.darkened(0.3), 1, radius), face)
	var gloss := Rect2(face.position + Vector2(3, 2), Vector2(face.size.x - 6, face.size.y * 0.4))
	ci.draw_style_box(_box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 0, int(radius * 0.7)), gloss)
	return face


## Capsule bar with a dark rim; the fill gets a lighter top half.
static func bar(ci: CanvasItem, pos: Vector2, w: float, h: float, frac: float, col: Color) -> void:
	var r := Rect2(pos, Vector2(w, h))
	var rad := int(h / 2.0 + 1)
	ci.draw_style_box(_box(Color(0.06, 0.05, 0.08, 0.85), INK, 1, rad), r.grow(1))
	frac = clampf(frac, 0.0, 1.0)
	if frac <= 0.0:
		return
	var f := Rect2(pos, Vector2(maxf(h, w * frac), h))
	ci.draw_style_box(_box(col, Color(0, 0, 0, 0), 0, rad), f)
	ci.draw_style_box(_box(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 0, rad), Rect2(f.position, Vector2(f.size.x, h * 0.45)))


## Item slot: rounded square with the rarity as rim and a faint inner glow.
static func slot(ci: CanvasItem, r: Rect2, col: Color, hi := false) -> void:
	ci.draw_style_box(_box(col.darkened(0.78), col.darkened(0.1) if not hi else Color.WHITE, 2, 6), r)
	ci.draw_style_box(_box(Color(col.r, col.g, col.b, 0.14), Color(0, 0, 0, 0), 0, 4), r.grow(-3))


## Round frame for a hero portrait.
static func medallion(ci: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	ci.draw_circle(center, radius + 2.0, INK)
	ci.draw_circle(center, radius + 1.0, col)
	ci.draw_circle(center, radius - 1.0, Color(0.27, 0.22, 0.38))


## Small faceted gem used for enhancement stones. Quads through draw_primitive: draw_colored_polygon
## re-triangulates every frame and five gems cost ~6% CPU on the always-on HUD.
static func gem(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var top := c + Vector2(0, -s)
	var right := c + Vector2(s * 0.8, -s * 0.2)
	var bottom := c + Vector2(0, s)
	var left := c + Vector2(-s * 0.8, -s * 0.2)
	var o := 1.0
	var ink := PackedColorArray([INK, INK, INK, INK])
	ci.draw_primitive(PackedVector2Array([top + Vector2(0, -o), right + Vector2(o, 0), bottom + Vector2(0, o), left + Vector2(-o, 0)]), ink, PackedVector2Array())
	ci.draw_primitive(PackedVector2Array([top, right, bottom, left]), PackedColorArray([col, col, col.darkened(0.3), col]), PackedVector2Array())
	var hi := col.lightened(0.45)
	ci.draw_primitive(PackedVector2Array([top, right, c + Vector2(0, -s * 0.1), left]), PackedColorArray([hi, hi, hi, hi]), PackedVector2Array())


## Gold coin: rim, face and a shine.
static func coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r + 1.0, INK)
	ci.draw_circle(c, r, Color(0.8, 0.52, 0.12))
	ci.draw_circle(c, r * 0.72, GOLD)
	ci.draw_arc(c + Vector2(-r * 0.15, -r * 0.15), r * 0.42, PI * 1.05, PI * 1.6, 8, Color(1, 1, 0.85, 0.9), 1.5, true)
