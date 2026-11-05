extends Node2D
## A drawing layer for main.gd. The battlefield layer: background hills, the 3D view, bars, effects and numbers. Redrawn every frame,
## while main.gd redraws the HUD and panels only a few times a second (their rounded boxes are costly to
## rebuild 30 times a second for a game that runs all day).

var m: Node2D
var ui := false  # this instance is the HUD/panel layer inside main's SubViewport


func _draw() -> void:
	if ui:
		m.draw_ui(self)
	else:
		m.draw_field(self)
