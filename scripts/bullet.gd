extends Area2D
class_name GameBullet

const BULLET_LAYER: int = 8
const WALL_LAYER: int = 1
const PLAYER_LAYER: int = 2
const ENEMY_LAYER: int = 4

@export var lifetime: float = 5.0
var network_position: Vector2 = Vector2.ZERO
var local_direction: Vector2 = Vector2.RIGHT
var local_speed: float = 700.0
var local_damage: float = 10.0
var owner_id: int = 0
var _lifetime_left: float = 0.0
var _spent: bool = false


func _ready() -> void:
	collision_layer = BULLET_LAYER
	collision_mask = WALL_LAYER | PLAYER_LAYER | ENEMY_LAYER
	_lifetime_left = lifetime
	if network_position != Vector2.ZERO:
		global_position = network_position
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if NetworkManager.is_client:
		global_position = global_position.lerp(network_position, clampf(delta * 24.0, 0.0, 1.0))
		return
	if _spent:
		return
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		queue_free()
		return
	var previous_position: Vector2 = global_position
	var next_position: Vector2 = previous_position + local_direction.normalized() * local_speed * delta
	var query := PhysicsRayQueryParameters2D.create(previous_position, next_position, collision_mask)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit.get("collider") as Object
		if _is_owner(collider):
			global_position = next_position
			network_position = global_position
			return
		_resolve_hit(collider)
		return
	global_position = next_position
	network_position = global_position


func _on_body_entered(body: Node2D) -> void:
	if NetworkManager.is_client or _spent:
		return
	if body is GameBullet:
		return
	if body is GamePlayer and body.get_multiplayer_authority() == owner_id:
		return
	if body is GameZombie and (body as GameZombie).dead:
		return
	_resolve_hit(body)


func _is_owner(collider: Object) -> bool:
	return collider is GamePlayer and (collider as GamePlayer).get_multiplayer_authority() == owner_id


func _resolve_hit(collider: Object) -> void:
	if _spent:
		return
	if collider is GameZombie and (collider as GameZombie).dead:
		return
	if collider is GamePlayer and (collider as GamePlayer).get_multiplayer_authority() == owner_id:
		return
	if collider != null and collider.has_method("take_damage"):
		var owner_player: GamePlayer = null
		for player_node: Node in get_tree().get_nodes_in_group("player"):
			if player_node is GamePlayer and (player_node as GamePlayer).get_multiplayer_authority() == owner_id:
				owner_player = player_node as GamePlayer
				break
		var health_before: float = -1.0
		if collider is GamePlayer:
			health_before = (collider as GamePlayer).hp
		elif collider is GameZombie:
			health_before = (collider as GameZombie).hp
		collider.call("take_damage", local_damage, global_position, 100.0)
		var health_after: float = health_before
		if collider is GamePlayer:
			health_after = (collider as GamePlayer).hp
		elif collider is GameZombie:
			health_after = (collider as GameZombie).hp
		if owner_player != null:
			owner_player.register_damage_dealt(maxf(0.0, health_before - health_after))
		UISoundManager.play_ui_sound("hit.wav")
	_spent = true
	set_deferred("monitoring", false)
	$CollisionShape2D.set_deferred("disabled", true)
	queue_free()
