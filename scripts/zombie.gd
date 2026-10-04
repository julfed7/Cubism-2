extends CharacterBody2D
class_name GameZombie

const SNAPSHOT_INTERVAL: float = 0.033

@export var speed: float = 55.0
@export var attack_range: float = 80.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var zombie_id: String = ""

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health: Node = $Health
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var network_position: Vector2 = Vector2.ZERO
var network_health: float = 30.0
var trajectory_pos: Vector2 = Vector2.ZERO
var trajectory_vel: Vector2 = Vector2.ZERO
var has_trajectory: bool = false
var hp: float = 30.0
var max_hp: float = 30.0
var network_alive: bool = true
var is_attacking: bool = false
var facing_left: bool = false
var dead: bool = false
var _can_attack: bool = true
var knockback_velocity: Vector2 = Vector2.ZERO
var _resin_slows: Dictionary = {}
var _hurt_flash_timer: float = 0.0
var _invuln_timer: float = 0.0
var _last_network_health: float = 30.0


func _ready() -> void:
	if zombie_id.is_empty():
		zombie_id = str(name)
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1 | 2
	navigation_agent.path_desired_distance = 8.0
	navigation_agent.target_desired_distance = attack_range * 0.75
	navigation_agent.radius = 20.0
	navigation_agent.avoidance_enabled = true
	if not navigation_agent.velocity_computed.is_connected(_on_safe_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_safe_velocity_computed)
	if network_position == Vector2.ZERO:
		network_position = global_position
	_last_network_health = float(health.get("current_health"))
	hp = _last_network_health
	max_hp = float(health.get("max_health"))


func _physics_process(delta: float) -> void:
	if dead:
		return
	if NetworkManager.is_client:
		return
	_process_hurt(delta)
	if knockback_velocity.length_squared() > 1.0:
		velocity = knockback_velocity
		move_and_slide()
		network_position = global_position
		return
	_process_authoritative_ai()


func _process(delta: float) -> void:
	if dead:
		return
	if NetworkManager.is_client:
		_process_hurt(delta)
	if is_multiplayer_authority():
		return
	if not has_trajectory:
		_apply_network_state()
		_update_animation(false)
		return
	var old_position: Vector2 = global_position
	var snapshot_step: float = delta / SNAPSHOT_INTERVAL
	trajectory_pos += trajectory_vel * snapshot_step
	var damping: float = 1.0 - pow(0.9, snapshot_step)
	trajectory_vel = trajectory_vel.lerp(Vector2.ZERO, damping)
	global_position = global_position.lerp(trajectory_pos, clampf(15.0 * delta, 0.0, 1.0))
	_apply_network_state()
	_update_animation(old_position.distance_squared_to(global_position) > 0.05)


func add_resin_slow(source_id: int, multiplier: float) -> void:
	_resin_slows[source_id] = clampf(multiplier, 0.1, 1.0)


func remove_resin_slow(source_id: int) -> void:
	_resin_slows.erase(source_id)


func _resin_speed_multiplier() -> float:
	var multiplier: float = 1.0
	for value: Variant in _resin_slows.values():
		multiplier = minf(multiplier, float(value))
	return multiplier


func set_trajectory(pos: Vector2, vel: Vector2) -> void:
	trajectory_pos = pos
	trajectory_vel = vel
	has_trajectory = true


func _process_authoritative_ai() -> void:
	var target: GamePlayer = _find_nearest_alive_player()
	if target == null:
		velocity = Vector2.ZERO
		_update_animation(false)
		return
	var offset: Vector2 = target.global_position - global_position
	if offset.length() <= attack_range:
		velocity = Vector2.ZERO
		if _can_attack:
			_attack(target)
		_update_animation(false)
		return
	navigation_agent.target_position = target.global_position
	var next_position: Vector2 = navigation_agent.get_next_path_position()
	var direction: Vector2 = (next_position - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = offset.normalized()
	facing_left = direction.x < 0.0
	navigation_agent.velocity = direction * speed * _resin_speed_multiplier()
	_update_animation(true)


func _on_safe_velocity_computed(safe_velocity: Vector2) -> void:
	if dead or NetworkManager.is_client or is_attacking:
		return
	velocity = safe_velocity
	move_and_slide()
	network_position = global_position


func _find_nearest_alive_player() -> GamePlayer:
	var nearest: GamePlayer = null
	var nearest_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group("player"):
		if not node is GamePlayer:
			continue
		var candidate := node as GamePlayer
		if not candidate.visible or candidate.is_hidden or candidate.hp <= 0.0:
			continue
		var distance: float = global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate
	return nearest


func take_damage(amount: float, source_pos: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if NetworkManager.is_client or dead or hp <= 0.0 or _invuln_timer > 0.0 or amount <= 0.0:
		return
	_invuln_timer = 0.1
	_hurt_flash_timer = 0.15
	if knockback_force > 0.0 and source_pos != Vector2.ZERO:
		var direction: Vector2 = (global_position - source_pos).normalized()
		knockback_velocity = direction * knockback_force
	modulate = Color(1.5, 0.3, 0.3, 1.0)
	health.call("take_damage", amount)
	network_health = float(health.get("current_health"))
	hp = network_health
	_last_network_health = network_health
	UISoundManager.play_ui_sound("zombie_hit.wav")
	if hp <= 0.0:
		_on_death(source_pos)


func _process_hurt(delta: float) -> void:
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	if _hurt_flash_timer > 0.0:
		_hurt_flash_timer = maxf(0.0, _hurt_flash_timer - delta)
		if _hurt_flash_timer <= 0.0 and not dead:
			modulate = Color.WHITE
	if knockback_velocity.length() > 5.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	else:
		knockback_velocity = Vector2.ZERO


func _on_death(_source_pos: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return
	if NetworkManager.is_single:
		_die()
	else:
		die_network.rpc()


@rpc("authority", "call_local", "reliable")
func die_network() -> void:
	_die()


func _die() -> void:
	if dead:
		return
	dead = true
	network_alive = false
	hp = 0.0
	network_health = 0.0
	modulate = Color(0.5, 0.5, 0.5, 0.5)
	velocity = Vector2.ZERO
	collision_shape.set_deferred("disabled", true)
	navigation_agent.avoidance_enabled = false
	UISoundManager.play_ui_sound("zombie_death.wav")
	if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("death"):
		animated_sprite.play("death")
		await animated_sprite.animation_finished
	if is_instance_valid(self):
		queue_free()


func _apply_network_state() -> void:
	if absf(network_health - _last_network_health) > 0.01:
		var was_hurt: bool = network_health < _last_network_health
		_last_network_health = network_health
		hp = network_health
		if health.has_method("set_network_health"):
			health.call("set_network_health", network_health)
		if was_hurt and hp > 0.0:
			_hurt_flash_timer = 0.15
			modulate = Color(1.5, 0.3, 0.3, 1.0)
	if not network_alive:
		_die()


func _attack(target: GamePlayer) -> void:
	_can_attack = false
	is_attacking = true
	_update_animation(false)
	if is_instance_valid(target):
		target.take_damage(attack_damage, global_position, 180.0)
	await get_tree().create_timer(attack_cooldown).timeout
	if is_instance_valid(self) and not dead:
		_can_attack = true
		is_attacking = false


func _update_animation(moving: bool) -> void:
	animated_sprite.flip_h = facing_left
	if is_attacking and animated_sprite.sprite_frames.has_animation("attack"):
		if animated_sprite.animation != "attack":
			animated_sprite.play("attack")
	elif moving and animated_sprite.sprite_frames.has_animation("walk"):
		if animated_sprite.animation != "walk":
			animated_sprite.play("walk")
	elif animated_sprite.sprite_frames.has_animation("idle") and animated_sprite.animation != "idle":
		animated_sprite.play("idle")
