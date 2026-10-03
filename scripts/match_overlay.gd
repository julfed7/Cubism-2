extends Node2D
class_name MatchOverlay

var zone_center: Vector2 = Vector2.ZERO
var zone_radius: float = 1200.0
var zone_enabled: bool = false
var danger_alpha: float = 0.0


func configure(center: Vector2, radius: float, enabled: bool) -> void:
	zone_center = center
	zone_radius = maxf(radius, 64.0)
	zone_enabled = enabled
	queue_redraw()


func _draw() -> void:
	if not zone_enabled:
		return
	# The ring stays readable above the tilemap without hiding the arena.
	draw_arc(zone_center, zone_radius, 0.0, TAU, 96, Color(0.22, 0.86, 1.0, 0.9), 8.0)
	draw_arc(zone_center, zone_radius + 7.0, 0.0, TAU, 96, Color(0.05, 0.23, 0.38, 0.45), 3.0)
	if danger_alpha > 0.01:
		draw_circle(zone_center, zone_radius, Color(0.15, 0.5, 0.72, danger_alpha))
