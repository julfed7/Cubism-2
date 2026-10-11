extends Node2D
class_name NoiseLure

## Configure position and exports before adding to the match. Spawning and
## inventory consumption belong to the caller; clients only display the effect.
@export var duration: float = 7.0
@export var attraction_radius: float = 360.0

var _remaining: float = 0.0
var _age: float = 0.0
var _affected: Dictionary = {}


func _ready() -> void:
	if not is_finite(duration) or not is_finite(attraction_radius):
		queue_free()
		return
	if duration <= 0.0 or attraction_radius <= 0.0:
		queue_free()
		return
	_remaining = duration
	add_to_group("noise_lure")
	# Uses a short dedicated cue (with a built-in placeholder fallback) on every
	# peer that receives the replicated lure.
	UISoundManager.play_ui_sound("noise_lure_activate.wav")
	_emit_noise()
	queue_redraw()


func is_active() -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _remaining > 0.0


func can_attract(at: Vector2) -> bool:
	return is_active() and global_position.distance_squared_to(at) <= attraction_radius * attraction_radius


func _physics_process(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	if not is_active():
		queue_free()
		return
	_emit_noise()


func _emit_noise() -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var zombie: GameZombie = node as GameZombie
		if zombie == null or zombie.dead or zombie.hp <= 0.0:
			continue
		if not can_attract(zombie.global_position):
			continue
		zombie.hear_noise_lure(self)
		_affected[zombie.get_instance_id()] = weakref(zombie)


func _exit_tree() -> void:
	for reference: WeakRef in _affected.values():
		var zombie: GameZombie = reference.get_ref() as GameZombie
		if is_instance_valid(zombie):
			zombie.forget_noise_lure(get_instance_id())
	_affected.clear()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	var fade: float = clampf(_remaining / 0.5, 0.0, 1.0)
	var ink := Color(0.07, 0.06, 0.15, fade)
	# Expanding sound waves and a bright, outlined toy siren need no textures.
	for i: int in range(3):
		var phase: float = fposmod(_age * 0.7 + float(i) / 3.0, 1.0)
		var radius: float = lerpf(30.0, attraction_radius, phase)
		var alpha: float = (1.0 - phase) * fade
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.07, 0.06, 0.15, alpha * 0.6), 7.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.25, 0.9, 1.0, alpha), 3.0, true)
	var bounce: float = sin(_age * 12.0) * 2.0
	draw_set_transform(Vector2(0.0, bounce))
	draw_circle(Vector2(0, 9), 24.0, Color(0.0, 0.0, 0.0, 0.3 * fade))
	draw_style_box(_body_style(ink, fade), Rect2(-20, -19, 40, 38))
	draw_line(Vector2(0, -19), Vector2(0, -31), ink, 6.0, true)
	draw_circle(Vector2(0, -32), 7.0, ink)
	draw_circle(Vector2(0, -32), 4.0, Color(1.0, 0.9, 0.25, fade))
	draw_circle(Vector2.ZERO, 13.0, ink)
	draw_circle(Vector2.ZERO, 9.0, Color(1.0, 0.9, 0.45, fade))
	draw_line(Vector2(-5, 0), Vector2(5, 0), ink, 3.0, true)
	draw_line(Vector2(0, -5), Vector2(0, 5), ink, 3.0, true)
	draw_arc(Vector2.ZERO, 25.0, -PI * 0.35, PI * 0.35, 16, Color(1.0, 0.86, 0.2, fade), 4.0, true)
	draw_arc(Vector2.ZERO, 25.0, PI * 0.65, PI * 1.35, 16, Color(1.0, 0.86, 0.2, fade), 4.0, true)
	draw_set_transform(Vector2.ZERO)
	if duration > 0.0:
		var progress: float = clampf(_remaining / duration, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 29.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, Color(1.0, 0.85, 0.15, fade), 3.0, true)


func _body_style(ink: Color, fade: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.28, 0.12, fade)
	style.border_color = ink
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	return style
