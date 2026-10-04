@tool
extends Area2D

## Presentation only: PortalPair owns entry checks and authoritative movement.
## Areas expose its radius for future integration, without a teleport callback.
@export_enum("A: lightning", "B: diamond") var endpoint_index: int = 0

const INK: Color = Color("21172f")
const CYAN: Color = Color("24e5ff")
const PINK: Color = Color("ff57b9")

var _radius: float = 38.0
var _open: bool = false
var _age: float = 0.0

@onready var _entry_shape: CollisionShape2D = $EntryShape


func _ready() -> void:
	# Isolate radius changes between instances of the scene.
	_entry_shape.shape = _entry_shape.shape.duplicate()
	_sync_pair()


func _process(delta: float) -> void:
	_age = fmod(_age + delta, TAU * 10.0)
	_sync_pair()
	queue_redraw()


func _sync_pair() -> void:
	var pair: Node2D = get_parent() as Node2D
	if pair == null:
		return
	var point: Vector2 = pair.get("point_a" if endpoint_index == 0 else "point_b")
	if point.is_finite():
		position = point
	var radius: float = float(pair.get("entry_radius"))
	var valid_radius: bool = is_finite(radius) and radius > 0.0
	if valid_radius:
		_radius = radius
		var circle: CircleShape2D = _entry_shape.shape as CircleShape2D
		if circle != null and not is_equal_approx(circle.radius, radius):
			circle.radius = radius
	var a: Vector2 = pair.get("point_a")
	var b: Vector2 = pair.get("point_b")
	var valid: bool = valid_radius and a.is_finite() and b.is_finite()
	if valid:
		valid = pair.to_global(a).distance_to(pair.to_global(b)) > radius * 2.0
	_open = bool(pair.get("is_open")) and valid
	if not Engine.is_editor_hint():
		if _entry_shape.disabled == _open:
			_entry_shape.set_deferred("disabled", not _open)
		if monitoring != _open:
			set_deferred("monitoring", _open)


func _draw() -> void:
	var accent: Color = CYAN if endpoint_index == 0 else PINK
	var r: float = _radius
	draw_circle(Vector2(0.0, r * 0.18), r + 8.0, Color(0.04, 0.02, 0.09, 0.4))
	if _open:
		draw_circle(Vector2.ZERO, r + 14.0, Color(accent, 0.12))
	draw_circle(Vector2.ZERO, r + 7.0, INK)
	draw_circle(Vector2.ZERO, r + 2.0, accent if _open else accent.darkened(0.5))
	draw_circle(Vector2.ZERO, maxf(r - 6.0, 1.0), INK)
	draw_circle(Vector2.ZERO, maxf(r - 10.0, 1.0),
		accent.darkened(0.68) if _open else Color("373344"))
	draw_arc(Vector2.ZERO, r + 1.0, PI * 1.12, PI * 1.78, 24,
		Color(1.0, 1.0, 1.0, 0.8 if _open else 0.25), 3.0, true)
	if _open:
		_draw_energy(accent, r)
	else:
		# Shutters communicate unavailable transfer independently of color.
		var extent: float = r * 0.38
		for direction: float in [-1.0, 1.0]:
			var start: Vector2 = Vector2(-extent, -extent * direction)
			var end: Vector2 = Vector2(extent, extent * direction)
			draw_line(start, end, INK, 10.0, true)
			draw_line(start, end, Color("aaa5b7"), 5.0, true)
	_draw_badge(accent, r)


func _draw_energy(accent: Color, r: float) -> void:
	var turn: float = _age * (1.2 if endpoint_index == 0 else -1.2)
	var pulse: float = 0.5 + 0.5 * sin(_age * 4.0)
	draw_circle(Vector2.ZERO, r * (0.28 + pulse * 0.08), Color(accent, 0.35))
	for index: int in range(3):
		var angle: float = turn + float(index) * TAU / 3.0
		draw_arc(Vector2.ZERO, r * 0.67, angle, angle + 1.0, 12, accent, 3.0, true)
	for index: int in range(4):
		var angle: float = -turn + float(index) * TAU / 4.0
		var at: Vector2 = Vector2.from_angle(angle) * (r + 10.0 + pulse * 3.0)
		draw_line(at - Vector2(3.0, 0.0), at + Vector2(3.0, 0.0), Color.WHITE, 2.0, true)
		draw_line(at - Vector2(0.0, 3.0), at + Vector2(0.0, 3.0), accent, 2.0, true)


func _draw_badge(accent: Color, r: float) -> void:
	var center: Vector2 = Vector2(0.0, -r - 5.0)
	draw_circle(center + Vector2(0.0, 2.0), 13.0, INK)
	draw_circle(center, 10.0, accent if _open else accent.darkened(0.25))
	var glyph: PackedVector2Array
	if endpoint_index == 0:
		glyph = PackedVector2Array([
			Vector2(1.0, -8.0), Vector2(-6.0, 1.0), Vector2(-1.0, 1.0),
			Vector2(-2.0, 8.0), Vector2(6.0, -2.0), Vector2(1.0, -2.0),
		])
	else:
		glyph = PackedVector2Array([
			Vector2(0.0, -7.0), Vector2(6.0, 0.0),
			Vector2(0.0, 7.0), Vector2(-6.0, 0.0),
		])
	for index: int in range(glyph.size()):
		glyph[index] += center
	draw_colored_polygon(glyph, INK)
