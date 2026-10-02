extends CharacterBody2D
class_name GamePlayer

signal player_died(player_id: int)

const WEAPON_IDS: Array[String] = ["pistol", "smg", "shotgun", "rifle"]
const SNAPSHOT_INTERVAL: float = 0.033

@export var speed: float = 500.0
@export var peer_id: String = "1"
@export var is_local: bool = true

@onready var health: Node = $Health
@onready var inventory: Inventory = $Inventory
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var weapon_sprite: Sprite2D = $WeaponPivot/WeaponSprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var current_weapon_slot: int = -1
var current_weapon: Dictionary = {}
var magazine: Dictionary = {}
var ammo_reserve: Dictionary = {}
var coins: int = 0
var hp: float = 100.0
var max_hp: float = 100.0
var network_weapon_id: String = ""
var network_aim_angle: float = 0.0
var network_inventory: Array = []
var network_position_q: Vector2i = Vector2i.ZERO
var trajectory_pos: Vector2 = Vector2.ZERO
var trajectory_vel: Vector2 = Vector2.ZERO
var has_trajectory: bool = false

var _fire_timer: float = 0.0
var _melee_timer: float = 0.0
var _step_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var _hurt_flash_timer: float = 0.0
var _invuln_timer: float = 0.0
var _dead: bool = false
var _last_replicated_hp: float = 100.0
var _last_network_inventory_text: String = ""
var _last_remote_weapon_id: String = ""
var _applying_network_inventory: bool = false


func _ready() -> void:
	add_to_group("player")
	is_local = NetworkManager.is_single or get_multiplayer_authority() == multiplayer.get_unique_id()
	$Camera2D.enabled = is_local
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	inventory.changed.connect(_on_inventory_changed)
	hp = float(health.get("current_health"))
	max_hp = float(health.get("max_health"))
	network_position_q = Vector2i(
		NetworkManager.quantize(global_position.x),
		NetworkManager.quantize(global_position.y)
	)
	_last_replicated_hp = hp
	_on_inventory_changed()
	var death_panel: Node = get_tree().current_scene.get_node_or_null("UI/DeathPanel")
	if is_local and death_panel != null and death_panel.has_signal("respawn_requested"):
		death_panel.respawn_requested.connect(_respawn)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_melee_timer = maxf(0.0, _melee_timer - delta)
	if not is_local:
		_process_hurt(delta)
		return
	var direction: Vector2 = _get_move_direction()
	velocity = direction * speed + knockback_velocity
	move_and_slide()
	_process_hurt(delta)
	network_position_q = Vector2i(
		NetworkManager.quantize(global_position.x),
		NetworkManager.quantize(global_position.y)
	)
	if NetworkManager.is_client:
		NetworkManager.send_move(network_position_q.x, network_position_q.y)
	_update_footsteps(direction, delta)


func _get_move_direction() -> Vector2:
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction


func _process(delta: float) -> void:
	if NetworkManager.is_client:
		_apply_replicated_inventory()
		_apply_replicated_health()
	if is_local:
		var aim: Vector2 = get_global_mouse_position() - global_position
		if aim.length_squared() > 0.001:
			weapon_pivot.rotation = aim.angle()
			network_aim_angle = weapon_pivot.rotation
			weapon_sprite.flip_v = aim.x < 0.0
		if not _dead:
			var loaded_ammo: int = _current_loaded_ammo()
			if current_weapon.is_empty() or loaded_ammo <= 0:
				if Input.is_action_just_pressed("shoot"):
					melee_attack()
			elif Input.is_action_pressed("shoot") and _fire_timer <= 0.0:
				shoot()
		return
	weapon_pivot.rotation = network_aim_angle
	_apply_remote_weapon_visual()
	if not NetworkManager.is_client or not has_trajectory:
		return
	var snapshot_step: float = delta / SNAPSHOT_INTERVAL
	trajectory_pos += trajectory_vel * snapshot_step
	var damping: float = 1.0 - pow(0.9, snapshot_step)
	trajectory_vel = trajectory_vel.lerp(Vector2.ZERO, damping)
	global_position = global_position.lerp(trajectory_pos, clampf(15.0 * delta, 0.0, 1.0))


func set_trajectory(pos: Vector2, vel: Vector2) -> void:
	trajectory_pos = pos
	trajectory_vel = vel
	has_trajectory = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or _dead:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key_event := event as InputEventKey
		if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_9:
			select_inventory_slot(int(key_event.keycode - KEY_1))
		elif key_event.keycode == KEY_R:
			reload()
		elif key_event.keycode == KEY_E:
			use_item(inventory.selected_slot)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_next_weapon(-1)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_next_weapon(1)


func select_inventory_slot(index: int) -> void:
	inventory.select_slot(index)
	current_weapon_slot = index
	_update_weapon_sprite()


func _select_next_weapon(step: int) -> void:
	var start: int = inventory.selected_slot if inventory.selected_slot >= 0 else 0
	for offset: int in range(1, inventory.max_slots + 1):
		var index: int = posmod(start + offset * step, inventory.max_slots)
		if _is_weapon_id(str(inventory.get_slot(index).get("id", ""))):
			select_inventory_slot(index)
			return


func _update_weapon_sprite() -> void:
	var item: Dictionary = inventory.get_selected()
	var item_id: String = str(item.get("id", ""))
	if not _is_weapon_id(item_id):
		current_weapon_slot = -1
		current_weapon = {}
		network_weapon_id = ""
		weapon_sprite.texture = null
		weapon_sprite.visible = false
		return
	var data: Dictionary = ItemDB.get_item(item_id).duplicate(true)
	data["id"] = item_id
	current_weapon_slot = inventory.selected_slot
	current_weapon = data
	network_weapon_id = item_id
	var sprite_path: String = str(data.get("sprite", ""))
	if sprite_path.is_empty():
		sprite_path = "res://sprites/weapons/%s.png" % item_id
	if ResourceLoader.exists(sprite_path):
		weapon_sprite.texture = load(sprite_path) as Texture2D
		weapon_sprite.visible = weapon_sprite.texture != null
	else:
		push_warning("Спрайт оружия не найден: %s" % sprite_path)
		weapon_sprite.texture = null
		weapon_sprite.visible = false


func shoot() -> void:
	if current_weapon.is_empty() or current_weapon_slot < 0 or _fire_timer > 0.0:
		return
	var weapon_id: String = str(current_weapon.get("id", ""))
	var loaded: int = int(magazine.get(weapon_id, 0))
	if loaded <= 0:
		UISoundManager.play_ui_sound("empty_click.wav")
		_fire_timer = 0.2
		return
	var direction: Vector2 = (get_global_mouse_position() - global_position).normalized()
	if direction == Vector2.ZERO:
		return
	magazine[weapon_id] = loaded - 1
	_fire_timer = float(current_weapon.get("fire_rate", 0.25))
	var game: Node = get_tree().current_scene
	if NetworkManager.is_single:
		if game.has_method("spawn_local_bullet"):
			game.spawn_local_bullet(get_muzzle_position(direction), direction, current_weapon)
	elif NetworkManager.is_host:
		if game.has_method("request_shoot_for_player"):
			game.request_shoot_for_player(get_multiplayer_authority(), direction)
	else:
		NetworkManager.send_shoot(direction)
	UISoundManager.play_ui_sound("shoot_%s.wav" % weapon_id)


func get_muzzle_position(direction: Vector2) -> Vector2:
	return weapon_sprite.global_position + direction.normalized() * 20.0


func reload() -> void:
	if current_weapon.is_empty():
		return
	var weapon_id: String = str(current_weapon.get("id", ""))
	if NetworkManager.is_client:
		NetworkManager.send_action({"type": "reload", "weapon_id": weapon_id})
		return
	_reload_weapon(weapon_id)


func _reload_weapon(weapon_id: String) -> int:
	var weapon: Dictionary = ItemDB.get_item(weapon_id)
	if weapon.is_empty():
		return int(magazine.get(weapon_id, 0))
	var ammo_id: String = "ammo_%s" % weapon_id
	var magazine_size: int = int(weapon.get("magazine_size", 0))
	var loaded: int = int(magazine.get(weapon_id, 0))
	var needed: int = maxi(0, magazine_size - loaded)
	var available: int = _count_inventory_item(ammo_id)
	var to_load: int = mini(needed, available)
	if to_load <= 0:
		if is_local:
			UISoundManager.play_ui_sound("empty_click.wav")
		return loaded
	if inventory.remove_item(ammo_id, to_load):
		magazine[weapon_id] = loaded + to_load
		_refresh_ammo_reserve()
	return int(magazine.get(weapon_id, loaded))


func use_item(slot_index: int) -> void:
	if NetworkManager.is_client:
		NetworkManager.use_item(slot_index)
		return
	var item: Dictionary = inventory.get_slot(slot_index)
	var item_id: String = str(item.get("id", ""))
	if item_id == "medkit":
		if float(health.get("current_health")) >= float(health.get("max_health")):
			return
		health.call("heal", 50.0)
		inventory.remove_item("medkit", 1)
		UISoundManager.play_ui_sound("heal.wav")
	elif _is_weapon_id(item_id):
		select_inventory_slot(slot_index)


func _get_aim_direction() -> Vector2:
	var direction: Vector2 = get_global_mouse_position() - global_position
	if direction.length_squared() <= 0.001:
		return Vector2.RIGHT
	return direction.normalized()


func _current_loaded_ammo() -> int:
	if current_weapon.is_empty():
		return 0
	var weapon_id: String = str(current_weapon.get("id", ""))
	return int(magazine.get(weapon_id, 0))


func melee_attack() -> void:
	if _dead or _melee_timer > 0.0:
		return
	var direction: Vector2 = _get_aim_direction()
	var my_position: Vector2 = global_position
	var damage: float = 15.0 if current_weapon.is_empty() else 10.0
	var attack_range: float = 60.0
	var knockback_force: float = 400.0
	_melee_timer = 0.45

	var targets: Array[Node] = []
	targets.append_array(get_tree().get_nodes_in_group("enemy"))
	for player_node: Node in get_tree().get_nodes_in_group("player"):
		if player_node != self:
			targets.append(player_node)

	for node: Node in targets:
		if node == self or not node is Node2D or not node.has_method("take_damage"):
			continue
		var target: Node2D = node as Node2D
		if target is GamePlayer and (not (target as GamePlayer).visible or (target as GamePlayer)._dead):
			continue
		if target is GameZombie and (target as GameZombie).dead:
			continue
		var to_target: Vector2 = target.global_position - my_position
		if to_target.length() > attack_range or to_target.length_squared() <= 0.001:
			continue
		if absf(direction.angle_to(to_target)) > deg_to_rad(60.0):
			continue

		if NetworkManager.is_client:
			var target_id: String = ""
			if target is GamePlayer:
				target_id = "player:%d" % (target as GamePlayer).get_multiplayer_authority()
			elif target is GameZombie:
				target_id = "zombie:%s" % (target as GameZombie).zombie_id
			else:
				target_id = "node:%s" % str(target.get_path())
			NetworkManager.send_action({
				"type": "melee_attack",
				"target_id": target_id,
				"damage": damage,
				"knockback": knockback_force,
				"dir": [direction.x, direction.y],
				"source_pos": [my_position.x, my_position.y],
			})
		else:
			target.call("take_damage", damage, my_position, knockback_force)


func take_damage(amount: float, source_pos: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if NetworkManager.is_client or _dead or hp <= 0.0 or _invuln_timer > 0.0 or amount <= 0.0:
		return
	_invuln_timer = 0.1
	_hurt_flash_timer = 0.15
	if knockback_force > 0.0 and source_pos != Vector2.ZERO:
		var direction: Vector2 = (global_position - source_pos).normalized()
		apply_knockback(direction * knockback_force)
	_start_hurt_flash()
	health.call("take_damage", amount)
	hp = float(health.get("current_health"))
	if is_local:
		UISoundManager.play_ui_sound("player_hurt.wav")
	if hp <= 0.0:
		_on_death(source_pos)


func _process_hurt(delta: float) -> void:
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	if _hurt_flash_timer > 0.0:
		_hurt_flash_timer = maxf(0.0, _hurt_flash_timer - delta)
		if _hurt_flash_timer <= 0.0 and not _dead:
			modulate = Color.WHITE
	if knockback_velocity.length() > 5.0:
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	else:
		knockback_velocity = Vector2.ZERO


func _on_death(_source_pos: Vector2 = Vector2.ZERO) -> void:
	if hp <= 0.0 and not _dead:
		_on_died()


func apply_knockback(force: Vector2) -> void:
	if is_local:
		knockback_velocity = force
	elif NetworkManager.is_host:
		apply_network_knockback.rpc_id(get_multiplayer_authority(), force)


func _start_hurt_flash() -> void:
	modulate = Color(1.5, 0.3, 0.3, 1.0)
	_hurt_flash_timer = 0.15
	if NetworkManager.is_host and not is_local:
		show_hurt_flash.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func show_hurt_flash() -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_local:
		modulate = Color(1.5, 0.3, 0.3, 1.0)
		_hurt_flash_timer = 0.15


func heal(amount: float) -> void:
	health.call("heal", amount)
	hp = float(health.get("current_health"))


@rpc("any_peer", "call_remote", "reliable")
func apply_network_knockback(force: Vector2) -> void:
	if multiplayer.get_remote_sender_id() == 1 and is_local:
		knockback_velocity = force


func on_weapon_picked(weapon_id: String) -> void:
	if not magazine.has(weapon_id):
		magazine[weapon_id] = 0


func add_reserve_ammo(weapon_id: String, amount: int) -> void:
	if amount > 0:
		inventory.add_item("ammo_%s" % weapon_id, amount)


func get_current_weapon_data() -> Dictionary:
	if not current_weapon.is_empty():
		return current_weapon.duplicate(true)
	if network_weapon_id.is_empty():
		return {}
	var data: Dictionary = ItemDB.get_item(network_weapon_id).duplicate(true)
	data["id"] = network_weapon_id
	return data


func _on_inventory_changed() -> void:
	if not _applying_network_inventory and not NetworkManager.is_client:
		network_inventory = inventory.make_snapshot()
	_refresh_ammo_reserve()


func _refresh_ammo_reserve() -> void:
	for weapon_id: String in WEAPON_IDS:
		ammo_reserve[weapon_id] = _count_inventory_item("ammo_%s" % weapon_id)


func _count_inventory_item(item_id: String) -> int:
	var total: int = 0
	for slot: Dictionary in inventory.slots:
		if str(slot.get("id", "")) == item_id:
			total += int(slot.get("amount", 0))
	return total


func _is_weapon_id(item_id: String) -> bool:
	return item_id in WEAPON_IDS


func _update_footsteps(direction: Vector2, delta: float) -> void:
	if direction.length_squared() <= 0.01:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = 0.4
		UISoundManager.play_ui_sound(_surface_step_sound())


func _surface_step_sound() -> String:
	var tilemap: TileMapLayer = get_tree().get_first_node_in_group("ground_tiles") as TileMapLayer
	if tilemap != null:
		var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
		var tile_data: TileData = tilemap.get_cell_tile_data(cell)
		if tile_data != null:
			var surface: String = str(tile_data.get_custom_data("surface"))
			if surface in ["grass", "stone", "wood"]:
				return "step_%s.wav" % surface
	return "step.wav"


func _on_health_changed(value: float) -> void:
	hp = value


func _apply_replicated_health() -> void:
	if absf(hp - _last_replicated_hp) < 0.01:
		return
	var was_hurt: bool = hp < _last_replicated_hp
	_last_replicated_hp = hp
	if was_hurt and hp > 0.0:
		_hurt_flash_timer = 0.15
		modulate = Color(1.5, 0.3, 0.3, 1.0)
	if health.has_method("set_network_health"):
		health.call("set_network_health", hp)
	if was_hurt and is_local and hp > 0.0:
		UISoundManager.play_ui_sound("player_hurt.wav")
	if hp <= 0.0:
		_on_died()


func _apply_replicated_inventory() -> void:
	var serialized: String = JSON.stringify(network_inventory)
	if serialized == _last_network_inventory_text:
		return
	_last_network_inventory_text = serialized
	_applying_network_inventory = true
	inventory.apply_snapshot(network_inventory, current_weapon_slot)
	_applying_network_inventory = false


func _apply_remote_weapon_visual() -> void:
	if network_weapon_id == _last_remote_weapon_id:
		return
	_last_remote_weapon_id = network_weapon_id
	if network_weapon_id.is_empty():
		weapon_sprite.texture = null
		weapon_sprite.visible = false
		return
	var data: Dictionary = ItemDB.get_item(network_weapon_id)
	var path: String = str(data.get("sprite", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		weapon_sprite.texture = load(path) as Texture2D
		weapon_sprite.visible = weapon_sprite.texture != null


func _drop_inventory_on_death() -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	var game: Node = get_tree().current_scene
	if game == null or not game.has_method("spawn_pickup"):
		return
	var slots: Array = inventory.make_snapshot()
	for slot_index: int in range(slots.size()):
		var slot_value: Variant = slots[slot_index]
		if not slot_value is Dictionary:
			continue
		var slot: Dictionary = slot_value as Dictionary
		var item_id: String = str(slot.get("id", ""))
		if not (item_id in WEAPON_IDS or item_id.begins_with("ammo_")):
			continue
		var amount: int = int(slot.get("amount", 1))
		var direction: Vector2 = Vector2.from_angle(randf_range(0.0, TAU))
		var force: float = 300.0
		var drop_id: String = "Drop_%d_%d_%d" % [
			get_multiplayer_authority(),
			Time.get_ticks_msec(),
			slot_index,
		]
		game.call(
			"spawn_pickup",
			item_id,
			amount,
			global_position,
			direction * force,
			drop_id
		)
		if not NetworkManager.is_single:
			spawn_dropped_pickup.rpc(
				item_id,
				global_position,
				direction,
				force,
				amount,
				drop_id
			)
		inventory.remove_item(item_id, amount)


@rpc("any_peer", "call_remote", "reliable")
func spawn_dropped_pickup(
	item_id: String,
	p_position: Vector2,
	direction: Vector2,
	force: float,
	amount: int = 1,
	pickup_id: String = ""
) -> void:
	var game: Node = get_tree().current_scene
	if game == null:
		return
	var pickup: GamePickup = null
	if not pickup_id.is_empty() and game.has_method("_find_pickup"):
		pickup = game.call("_find_pickup", pickup_id) as GamePickup
	if pickup == null:
		await get_tree().process_frame
		if not pickup_id.is_empty() and game.has_method("_find_pickup"):
			pickup = game.call("_find_pickup", pickup_id) as GamePickup
	if pickup == null and game.has_method("_spawn_pickup"):
		var data: Dictionary = {
			"id": pickup_id if not pickup_id.is_empty() else "Drop_%d" % Time.get_ticks_msec(),
			"item_id": item_id,
			"amount": amount,
			"position": p_position,
			"throw_velocity": Vector2.ZERO,
		}
		pickup = game.call("_spawn_pickup", data) as GamePickup
		var entities: Node = game.get_node_or_null("MapContainer/Entities")
		if pickup != null and entities != null:
			entities.add_child(pickup, true)
	if pickup != null:
		pickup.item_id = item_id
		pickup.amount = amount
		pickup.global_position = p_position
		pickup.start_flight(direction.normalized() * force)


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	modulate = Color(0.5, 0.5, 0.5, 0.5)
	visible = false
	collision_shape.set_deferred("disabled", true)
	set_physics_process(false)
	_drop_inventory_on_death()
	if NetworkManager.is_single or NetworkManager.is_host:
		player_died.emit(get_multiplayer_authority())
	if is_local:
		UISoundManager.play_ui_sound("player_death.wav")
		var death_panel: Node = get_tree().current_scene.get_node_or_null("UI/DeathPanel")
		if death_panel != null and death_panel.has_method("show_death"):
			death_panel.show_death(5.0)
		elif NetworkManager.is_single or NetworkManager.is_host:
			await get_tree().create_timer(5.0).timeout
			if is_instance_valid(self) and _dead:
				_respawn()
	elif NetworkManager.is_host:
		await get_tree().create_timer(5.0).timeout
		if is_instance_valid(self) and _dead:
			_respawn()


func _respawn() -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	restore_respawn_state()
	if not NetworkManager.is_single:
		on_player_respawned.rpc(get_multiplayer_authority())


func restore_respawn_state() -> void:
	_dead = false
	visible = true
	collision_shape.set_deferred("disabled", false)
	set_physics_process(true)
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO
	_invuln_timer = 0.0
	_hurt_flash_timer = 0.0
	modulate = Color.WHITE
	var spawn: Node2D = get_tree().get_first_node_in_group("player_spawn") as Node2D
	if spawn != null:
		global_position = spawn.global_position
	health.set("_dead", false)
	max_hp = float(health.get("max_health"))
	health.set("current_health", max_hp)
	hp = max_hp
	health.emit_signal("health_changed", hp)
	_last_replicated_hp = hp


@rpc("any_peer", "call_remote", "reliable")
func on_player_respawned(player_id: int) -> void:
	var target: GamePlayer = null
	for node: Node in get_tree().get_nodes_in_group("player"):
		if node is GamePlayer and (node as GamePlayer).get_multiplayer_authority() == player_id:
			target = node as GamePlayer
			break
	if target == null:
		return
	target.restore_respawn_state()
	if target.is_local:
		var death_panel: Node = get_tree().current_scene.get_node_or_null("UI/DeathPanel")
		if death_panel != null:
			death_panel.visible = false
