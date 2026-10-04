extends Area2D
class_name ResinPatch

@export var radius: float = 92.0
@export var duration: float = 6.0
@export var slow_multiplier: float = 0.55
var _remaining: float = 0.0
var _affected: Dictionary = {}
var _phase: float = 0.0
var _age: float = 0.0
var _entered_bodies: Dictionary = {}
var _fade_started: bool = false

func _ready() -> void:
	_remaining = duration
	_age = 0.0
	UISoundManager.play_ui_sound("pickup.wav")
	add_to_group("resin_patch")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	monitoring = true
	monitorable = true
	queue_redraw()

func _process(delta: float) -> void:
	_remaining -= delta
	_age += delta
	if _remaining <= 0.65 and not _fade_started:
		_fade_started = true
		UISoundManager.play_ui_sound("menu_close.wav")
	_phase += delta
	queue_redraw()
	if _remaining <= 0.0:
		queue_free()

func _draw() -> void:
	var intro: float = clampf(_age / 0.32, 0.0, 1.0)
	var fade: float = clampf(_remaining / 0.65, 0.0, 1.0)
	var pulse: float = 1.0 + sin(_phase * 3.0) * 0.035
	var draw_scale: float = lerpf(0.35, 1.0, ease(intro, 0.65))
	var alpha: float = fade * (0.82 + intro * 0.18)
	var patch_radius: float = radius * pulse * draw_scale
	draw_circle(Vector2(0, 7), patch_radius, Color(0.06, 0.03, 0.02, 0.26 * alpha))
	draw_circle(Vector2.ZERO, patch_radius, Color(0.28, 0.09, 0.035, alpha))
	draw_arc(Vector2.ZERO, patch_radius - 5.0, 0.0, TAU, 48, Color(1.0, 0.43, 0.08, alpha), 5.0, true)
	for i: int in range(5):
		var angle: float = float(i) * TAU / 5.0 + _phase * 0.08
		var center: Vector2 = Vector2.RIGHT.rotated(angle) * (patch_radius * 0.45)
		draw_circle(center, 4.0 + float(i % 2) * 2.0, Color(1.0, 0.72, 0.16, alpha))

	if _age < 0.55:
		var ring: float = lerpf(18.0, radius * 0.92, clampf(_age / 0.55, 0.0, 1.0))
		draw_arc(Vector2.ZERO, ring, 0.0, TAU, 40, Color(1.0, 0.82, 0.28, (1.0 - _age / 0.55) * 0.9), 4.0, true)
	if not _entered_bodies.is_empty() and fade > 0.0:
		draw_arc(Vector2.ZERO, patch_radius * 0.72, -_phase, -_phase + PI * 0.7, 24, Color(0.48, 0.9, 1.0, 0.85 * fade), 3.0, true)

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("add_resin_slow") and not _affected.has(body.get_instance_id()):
		var id: int = get_instance_id()
		_affected[body.get_instance_id()] = weakref(body)
		body.call("add_resin_slow", id, slow_multiplier)
		_entered_bodies[body.get_instance_id()] = true
		UISoundManager.play_ui_sound("hit.wav")

func _on_body_exited(body: Node2D) -> void:
	_remove_affected(body.get_instance_id())

func _remove_affected(instance_id: int) -> void:
	if not _affected.has(instance_id):
		return
	var ref: WeakRef = _affected[instance_id]
	var body: Object = ref.get_ref()
	if body != null and is_instance_valid(body) and body.has_method("remove_resin_slow"):
		body.call("remove_resin_slow", get_instance_id())
	_affected.erase(instance_id)
	_entered_bodies.erase(instance_id)

func _exit_tree() -> void:
	for instance_id: int in _affected.keys():
		_remove_affected(int(instance_id))
