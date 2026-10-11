extends Node2D
class_name GameSentryTower

@export var owner_peer_id: int = 1
@export var attack_radius: float = 300.0
@export var attack_damage: float = 8.0
@export var fire_interval: float = 0.65
@export var lifetime: float = 25.0

var _remaining: float = 25.0
var _shot_timer: float = 0.0
var _last_synced_angle: float = 0.0


func _ready() -> void:
	_remaining = maxf(lifetime, 1.0)
	add_to_group("sentry_tower")


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		if NetworkManager.is_host:
			var game: Node = get_tree().current_scene
			if game != null and game.has_method("sync_sentry_tower_removed"):
				game.rpc("sync_sentry_tower_removed", name)
		queue_free()
		return
	_shot_timer = maxf(0.0, _shot_timer - delta)
	var target: GameZombie = _find_target()
	if target == null:
		return
	var direction: Vector2 = (target.global_position - global_position).normalized()
	rotation = direction.angle()
	if NetworkManager.is_host and absf(wrapf(rotation - _last_synced_angle, -PI, PI)) >= 0.08:
		_last_synced_angle = rotation
		var game: Node = get_tree().current_scene
		if game != null:
			game.rpc("sync_sentry_tower_aim", str(name), rotation)
	if _shot_timer > 0.0:
		return
	_shot_timer = maxf(fire_interval, 0.1)
	var current_game: Node = get_tree().current_scene
	if current_game != null and current_game.has_method("_spawn_projectile"):
		var weapon: Dictionary = {"bullet_speed": 620.0, "damage": attack_damage}
		current_game.call("_spawn_projectile", owner_peer_id, global_position + direction * 22.0, direction, weapon)


func _find_target() -> GameZombie:
	var nearest: GameZombie = null
	var nearest_distance_squared: float = attack_radius * attack_radius
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var zombie: GameZombie = node as GameZombie
		if zombie == null or zombie.dead or zombie.hp <= 0.0 or not zombie.is_inside_tree():
			continue
		var distance_squared: float = global_position.distance_squared_to(zombie.global_position)
		if distance_squared >= nearest_distance_squared:
			continue
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
			global_position,
			zombie.global_position,
			1,
			[]
		)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		if not get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			continue
		nearest = zombie
		nearest_distance_squared = distance_squared
	return nearest
