@tool
extends Area2D

## Presentation only: PortalPair owns entry checks and authoritative movement.
## Areas expose its radius for future integration, without a teleport callback.
@export_enum("A: lightning", "B: diamond") var endpoint_index: int = 0

const PORTAL_SHEET_PATH: String = "res://sprites/effects/portal_animation.png"
const PORTAL_COLUMNS: int = 4
const PORTAL_ROWS: int = 2
const PORTAL_ANIMATION_FPS: float = 8.0

var _radius: float = 38.0
var _open: bool = false

@onready var _entry_shape: CollisionShape2D = $EntryShape
@onready var _portal_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# Isolate radius changes between instances of the scene.
	_entry_shape.shape = _entry_shape.shape.duplicate()
	_configure_sprite_animation()
	_sync_pair()
	_update_sprite_state()


func _process(_delta: float) -> void:
	_sync_pair()


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
	var was_open: bool = _open
	_open = bool(pair.get("is_open")) and valid
	if was_open != _open:
		_update_sprite_state()
	if not Engine.is_editor_hint():
		if _entry_shape.disabled == _open:
			_entry_shape.set_deferred("disabled", not _open)
		if monitoring != _open:
			set_deferred("monitoring", _open)


func _configure_sprite_animation() -> void:
	var sheet: Texture2D = load(PORTAL_SHEET_PATH) as Texture2D
	if sheet == null:
		push_warning("Portal animation sheet is missing: " + PORTAL_SHEET_PATH)
		return

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_animation_row(frames, sheet, "cyan", 0)
	_add_animation_row(frames, sheet, "pink", 1)
	_portal_sprite.sprite_frames = frames
	_portal_sprite.animation = "cyan" if endpoint_index == 0 else "pink"
	_portal_sprite.centered = true


func _add_animation_row(frames: SpriteFrames, sheet: Texture2D, animation_name: StringName, row: int) -> void:
	frames.add_animation(animation_name)
	frames.set_animation_speed(animation_name, PORTAL_ANIMATION_FPS)
	frames.set_animation_loop(animation_name, true)
	for column: int in range(PORTAL_COLUMNS):
		var left: int = floori(float(sheet.get_width() * column) / float(PORTAL_COLUMNS))
		var right: int = floori(float(sheet.get_width() * (column + 1)) / float(PORTAL_COLUMNS))
		var top: int = floori(float(sheet.get_height() * row) / float(PORTAL_ROWS))
		var bottom: int = floori(float(sheet.get_height() * (row + 1)) / float(PORTAL_ROWS))
		var frame_texture := AtlasTexture.new()
		frame_texture.atlas = sheet
		frame_texture.region = Rect2i(left, top, right - left, bottom - top)
		frames.add_frame(animation_name, frame_texture)


func _update_sprite_state() -> void:
	if _portal_sprite.sprite_frames == null:
		return
	if _open:
		_portal_sprite.modulate = Color.WHITE
		_portal_sprite.play()
	else:
		_portal_sprite.stop()
		_portal_sprite.frame = 0
		_portal_sprite.modulate = Color(0.38, 0.38, 0.45, 0.85)
