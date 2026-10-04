extends Control
class_name ScreenJoystick

## Floating movement joystick with a dedicated touch activation zone.

@export var radius: float = 78.0
@export var knob_radius: float = 30.0
@export var deadzone: float = 0.12
@export var zone_margin: float = 24.0
@export_range(0.25, 0.75, 0.01) var zone_width_ratio: float = 0.32
@export_range(0.35, 0.9, 0.01) var zone_height_ratio: float = 0.45

signal value_changed(direction: Vector2)

signal aim_position_changed(screen_position: Vector2)

var value: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _mouse_pressed: bool = false
var _base_position: Vector2


func _ready() -> void:
	add_to_group("virtual_joystick")
	# Pass touches outside the movement zone to the player's touch-aim handler.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_base_position = _zone_rect().get_center()
	queue_redraw()


func _draw() -> void:
	if not is_input_active():
		return
	var outer_color := Color(0.04, 0.06, 0.08, 0.58)
	var ring_color := Color(0.55, 0.70, 0.82, 0.82)
	var knob_color := Color(0.86, 0.94, 1.0, 0.9)
	draw_circle(_base_position, radius + 4.0, Color(0.01, 0.02, 0.03, 0.32))
	draw_circle(_base_position, radius, outer_color)
	draw_arc(_base_position, radius, 0.0, TAU, 64, ring_color, 3.0, true)
	draw_circle(_base_position + value * radius * 0.62, knob_radius, knob_color)
	draw_arc(_base_position + value * radius * 0.62, knob_radius, 0.0, TAU, 48, Color(0.16, 0.28, 0.38, 0.95), 3.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var local_position := _to_local_position(touch.position)
		if touch.pressed and _touch_index == -1 and is_position_in_zone(touch.position):
			_touch_index = touch.index
			_begin_at_position(local_position)
			accept_event()
		elif touch.pressed and not is_position_in_zone(touch.position):
			_emit_aim_position(touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			_reset_value()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_set_value_from_position(_to_local_position(drag.position))
			accept_event()
		else:
			_emit_aim_position(drag.position)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			var local_position := _to_local_position(mouse_button.position)
			if mouse_button.pressed and is_position_in_zone(mouse_button.position):
				_mouse_pressed = true
				_begin_at_position(local_position)
				accept_event()
			elif mouse_button.pressed:
				_emit_aim_position(mouse_button.position)
			elif not mouse_button.pressed and _mouse_pressed:
				_mouse_pressed = false
				_reset_value()
				accept_event()
	elif event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if _mouse_pressed:
			_set_value_from_position(_to_local_position(mouse_motion.position))
			accept_event()
		else:
			_emit_aim_position(mouse_motion.position)


func is_input_active() -> bool:
	return _touch_index != -1 or _mouse_pressed


func is_position_in_zone(p_position: Vector2) -> bool:
	return _zone_rect().has_point(_to_local_position(p_position))


func get_touch_index() -> int:
	return _touch_index


func _emit_aim_position(screen_position: Vector2) -> void:
	# A touch captured by the joystick must never update the player's aim.
	aim_position_changed.emit(screen_position)


func _begin_at_position(p_position: Vector2) -> void:
	_base_position = _clamp_base_position(p_position)
	_set_value_from_position(p_position)


func _set_value_from_position(p_position: Vector2) -> void:
	var offset: Vector2 = p_position - _base_position
	if offset.length() > radius:
		offset = offset.normalized() * radius
	var next_value: Vector2 = offset / radius
	if next_value.length() < deadzone:
		next_value = Vector2.ZERO
	if next_value.distance_squared_to(value) > 0.000001:
		value = next_value
		value_changed.emit(value)
	queue_redraw()


func _reset_value() -> void:
	_base_position = _zone_rect().get_center()
	if value == Vector2.ZERO:
		queue_redraw()
		return
	value = Vector2.ZERO
	value_changed.emit(value)
	queue_redraw()


func _clamp_base_position(p_position: Vector2) -> Vector2:
	var zone := _zone_rect()
	var padding := Vector2(radius + zone_margin, radius + zone_margin)
	var min_position := zone.position + padding
	var max_position := zone.end - padding
	return Vector2(
		clampf(p_position.x, min_position.x, max_position.x),
		clampf(p_position.y, min_position.y, max_position.y)
	)


func _zone_rect() -> Rect2:
	var zone_size := Vector2(size.x * zone_width_ratio, size.y * zone_height_ratio)
	return Rect2(Vector2(zone_margin, size.y - zone_size.y - zone_margin), zone_size)


func _to_local_position(p_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p_position
