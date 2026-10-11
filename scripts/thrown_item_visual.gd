extends Node2D
class_name GameThrownItemVisual

signal landed(world_position: Vector2)

@onready var item_sprite: Sprite2D = $Sprite2D

var _start_position: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _flight_time: float = 0.48


func launch(item_id: String, start_position: Vector2, target_position: Vector2) -> bool:
	var item_data: Dictionary = ItemDB.get_item(item_id)
	var sprite_path: String = str(item_data.get("sprite", ""))
	if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
		push_warning("Не найден спрайт брошенного предмета: %s" % item_id)
		return false
	var texture: Texture2D = load(sprite_path) as Texture2D
	if texture == null:
		push_warning("Не удалось загрузить спрайт брошенного предмета: %s" % sprite_path)
		return false
	item_sprite.texture = texture
	item_sprite.visible = true
	item_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_start_position = start_position
	_target_position = target_position
	_elapsed = 0.0
	global_position = start_position
	set_process(true)
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	var progress: float = clampf(_elapsed / _flight_time, 0.0, 1.0)
	var arc: float = sin(progress * PI)
	global_position = _start_position.lerp(_target_position, progress)
	item_sprite.position = Vector2(0.0, -arc * 42.0)
	item_sprite.scale = Vector2.ONE * (0.78 + arc * 0.48)
	item_sprite.z_index = roundi(arc * 12.0)
	if progress >= 1.0:
		set_process(false)
		landed.emit(_target_position)
		queue_free()
