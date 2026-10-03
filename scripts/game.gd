extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/objects/Player.tscn")
const BULLET_SCENE: PackedScene = preload("res://scenes/objects/Bullet.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/objects/Pickup.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/objects/Chest.tscn")
const CRYSTAL_SCENE: PackedScene = preload("res://scenes/objects/Crystal.tscn")

@export var map_scene: PackedScene = preload("res://scenes/maps/Island.tscn")

@onready var map_root: Node2D = $MapContainer/NavigationRegion2D/MapRoot
@onready var entities: Node2D = $MapContainer/Entities
@onready var navigation_region: NavigationRegion2D = $MapContainer/NavigationRegion2D
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var bullet_spawner: MultiplayerSpawner = $BulletSpawner
@onready var pickup_spawner: MultiplayerSpawner = $PickupSpawner
@onready var chest_spawner: MultiplayerSpawner = $ChestSpawner
@onready var crystal_spawner: MultiplayerSpawner = $CrystalSpawner
@onready var match_music: AudioStreamPlayer = $MatchMusic

var _next_pickup_id: int = 1
var _next_bullet_id: int = 1
var _crystal_positions: Array[Vector2] = [Vector2(0, 0), Vector2(-275, -125), Vector2(275, -125), Vector2(-275, 125), Vector2(275, 125)]
var _server_fire_at: Dictionary = {}
var sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.033


func _ready() -> void:
	NetworkManager.clear_snapshots()
	_configure_spawners()
	_start_music()
	_select_and_load_map()
	call_deferred("_configure_existing_entity_synchronizers")
	_setup_navigation.call_deferred()
	if NetworkManager.is_single:
		var player: GamePlayer = _spawn_player({"peer_id": 1, "position": _spawn_position(0)}) as GamePlayer
		entities.add_child(player, true)
		_bind_local_player(player)
		_spawn_chests()
		_spawn_crystals()
		return
	if not NetworkManager.player_connected.is_connected(_on_peer_joined_game):
		NetworkManager.player_connected.connect(_on_peer_joined_game)
	if not NetworkManager.player_disconnected.is_connected(_on_peer_left_game):
		NetworkManager.player_disconnected.connect(_on_peer_left_game)
	await get_tree().process_frame
	await get_tree().process_frame
	if NetworkManager.is_host:
		_spawn_online_player(1)
		for peer: int in multiplayer.get_peers():
			_spawn_online_player(peer)
		_spawn_chests()
		_spawn_crystals()
	else:
		await get_tree().process_frame
		_bind_existing_local_player()
		client_game_ready.rpc_id(1)


func _process(delta: float) -> void:
	if NetworkManager.is_host:
		_update_adaptive_sync_rates()
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = fmod(sync_timer, SYNC_INTERVAL)
			_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	var tick: int = Time.get_ticks_msec()
	var players_state: Dictionary = {}
	var zombies_state: Dictionary = {}
	for node: Node in entities.get_children():
		if not node is GamePlayer:
			continue
		var player: GamePlayer = node as GamePlayer
		var player_id: int = player.get_multiplayer_authority()
		var world_position: Vector2 = player.global_position
		players_state[str(player_id)] = {
			"x": world_position.x,
			"y": world_position.y,
			"rot": player.rotation,
			"hp": player.hp,
			"crystals": player.crystals,
		}
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if not node is GameZombie:
			continue
		var zombie: GameZombie = node as GameZombie
		var world_position: Vector2 = zombie.global_position
		zombies_state[str(zombie.get_instance_id())] = {
			"x": world_position.x,
			"y": world_position.y,
			"hp": zombie.hp,
			"zombie_id": zombie.zombie_id,
		}

	for peer_id: int in multiplayer.get_peers():
		var viewer: GamePlayer = _find_player(peer_id)
		if viewer == null:
			continue
		var visible_players: Dictionary = {}
		var visible_zombies: Dictionary = {}
		for raw_id: Variant in players_state.keys():
			var player: GamePlayer = _find_player(int(raw_id))
			if player != null and viewer.global_position.distance_to(player.global_position) < 800.0:
				visible_players[raw_id] = players_state[raw_id]
		for raw_id: Variant in zombies_state.keys():
			var zombie_state: Dictionary = zombies_state[raw_id] as Dictionary
			var zombie_id: String = str(zombie_state.get("zombie_id", ""))
			var zombie: GameZombie = _find_zombie(zombie_id)
			if zombie != null and viewer.global_position.distance_to(zombie.global_position) < 800.0:
				visible_zombies[raw_id] = zombie_state
		_receive_snapshot.rpc_id(peer_id, {
			"tick": tick,
			"players": visible_players,
			"zombies": visible_zombies,
		})

func _find_zombie(p_zombie_id: String) -> GameZombie:
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if node is GameZombie and (node as GameZombie).zombie_id == p_zombie_id:
			return node as GameZombie
	return null


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_snapshot(snapshot: Dictionary) -> void:
	NetworkManager.push_snapshot(snapshot)
	_apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary) -> void:
	var players_state: Dictionary = snapshot.get("players", {}) as Dictionary
	for raw_id: Variant in players_state.keys():
		var player_id: int = int(raw_id)
		var player: GamePlayer = _find_player(player_id)
		if player == null:
			continue
		var player_state: Dictionary = players_state.get(raw_id, {}) as Dictionary
		var server_position: Vector2 = Vector2(float(player_state.get("x", 0.0)), float(player_state.get("y", 0.0)))
		if player_id == multiplayer.get_unique_id():
			if player.global_position.distance_to(server_position) > 50.0:
				player.global_position = server_position
		else:
			var trajectory: Dictionary = NetworkManager.get_trajectory_for(str(raw_id), false)
			if not trajectory.is_empty():
				var trajectory_position: Vector2 = Vector2(trajectory.get("pos", Vector2.ZERO))
				var trajectory_velocity: Vector2 = Vector2(trajectory.get("vel", Vector2.ZERO))
				player.set_trajectory(trajectory_position, trajectory_velocity)
		player.hp = float(player_state.get("hp", player.hp))
		player.crystals = int(player_state.get("crystals", player.crystals))

	var zombies_state: Dictionary = snapshot.get("zombies", {}) as Dictionary
	for raw_id: Variant in zombies_state.keys():
		var zombie_state: Dictionary = zombies_state.get(raw_id, {}) as Dictionary
		var zombie: GameZombie = instance_from_id(int(raw_id)) as GameZombie
		var snapshot_zombie_id: String = str(zombie_state.get("zombie_id", ""))
		if zombie == null or zombie.zombie_id != snapshot_zombie_id:
			zombie = _find_zombie(snapshot_zombie_id)
		if zombie == null:
			continue
		var trajectory: Dictionary = NetworkManager.get_trajectory_for(str(raw_id), true)
		if not trajectory.is_empty():
			var trajectory_position: Vector2 = Vector2(trajectory.get("pos", Vector2.ZERO))
			var trajectory_velocity: Vector2 = Vector2(trajectory.get("vel", Vector2.ZERO))
			zombie.set_trajectory(trajectory_position, trajectory_velocity)
		zombie.hp = float(zombie_state.get("hp", zombie.hp))
		zombie.network_health = zombie.hp


func _configure_spawners() -> void:
	player_spawner.spawn_function = _spawn_player
	bullet_spawner.spawn_function = _spawn_bullet
	pickup_spawner.spawn_function = _spawn_pickup
	chest_spawner.spawn_function = _spawn_chest
	crystal_spawner.spawn_function = _spawn_crystal


func _configure_existing_entity_synchronizers() -> void:
	if not NetworkManager.is_host:
		return
	for entity: Node in get_tree().get_nodes_in_group("player"):
		if entity is Node2D:
			_configure_synchronizers_for_entity(entity as Node2D)
	for entity: Node in get_tree().get_nodes_in_group("enemy"):
		if entity is Node2D:
			_configure_synchronizers_for_entity(entity as Node2D)


func _configure_synchronizers_for_entity(entity: Node2D) -> void:
	if not NetworkManager.is_host or not is_instance_valid(entity):
		return
	for child: Node in entity.find_children("*", "MultiplayerSynchronizer", true, false):
		var synchronizer: MultiplayerSynchronizer = child as MultiplayerSynchronizer
		if synchronizer == null:
			continue
		if not synchronizer.has_meta("distance_filter_added"):
			synchronizer.add_visibility_filter(_make_visibility_filter(entity))
			synchronizer.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_IDLE
			synchronizer.set_meta("distance_filter_added", true)
		synchronizer.update_visibility()


func _make_visibility_filter(entity: Node2D) -> Callable:
	return func(peer_id: int) -> bool:
		return distance_to_peer(peer_id, entity) < 800.0


func distance_to_peer(peer_id: int, entity: Node2D) -> float:
	var peer_player: GamePlayer = _find_player(peer_id)
	if peer_player == null:
		# Пока peer не появился в сцене, разрешаем первичную репликацию.
		return 0.0
	return entity.global_position.distance_to(peer_player.global_position)


func _update_adaptive_sync_rates() -> void:
	var entities_to_sync: Array[Node] = []
	entities_to_sync.append_array(get_tree().get_nodes_in_group("player"))
	entities_to_sync.append_array(get_tree().get_nodes_in_group("enemy"))
	for entity_node: Node in entities_to_sync:
		if not entity_node is Node2D:
			continue
		var entity: Node2D = entity_node as Node2D
		var nearest_distance: float = INF
		for player_node: Node in get_tree().get_nodes_in_group("player"):
			if player_node is GamePlayer:
				var tracked_player: GamePlayer = player_node as GamePlayer
				if tracked_player.visible:
					nearest_distance = minf(nearest_distance, entity.global_position.distance_to(tracked_player.global_position))
		var interval: float = 0.5
		if nearest_distance < 200.0:
			interval = 0.05
		elif nearest_distance < 600.0:
			interval = 0.1
		for child: Node in entity.find_children("*", "MultiplayerSynchronizer", true, false):
			var synchronizer: MultiplayerSynchronizer = child as MultiplayerSynchronizer
			if synchronizer == null:
				continue
			if not synchronizer.has_meta("distance_filter_added"):
				_configure_synchronizers_for_entity(entity)
			if not is_equal_approx(synchronizer.replication_interval, interval):
				synchronizer.replication_interval = interval


func is_crystal_capture_mode() -> bool:
	return NetworkManager.game_mode == "crystal_capture" or (NetworkManager.is_single and GameState.current_level == 3)


func _select_and_load_map() -> void:
	if NetworkManager.is_single:
		if GameState.current_level == 3:
			NetworkManager.game_mode = "crystal_capture"
			NetworkManager.map_name = "CrystalArena"
			NetworkManager.map_path = "res://scenes/maps/CrystalArena.tscn"
		else:
			NetworkManager.game_mode = "battle_royale"
			NetworkManager.current_map_index = clampi(GameState.current_level - 1, 0, MapManager.maps.size() - 1)
			NetworkManager.map_name = "Island" if NetworkManager.current_map_index == 0 else "City"
		NetworkManager.map_path = "res://scenes/maps/%s.tscn" % NetworkManager.map_name
	var selected_map: PackedScene = null
	if ResourceLoader.exists(NetworkManager.map_path):
		selected_map = load(NetworkManager.map_path) as PackedScene
	if selected_map == null:
		selected_map = MapManager.get_map_by_index(NetworkManager.current_map_index)
	if selected_map != null:
		map_scene = selected_map
	load_map(map_scene)


func load_map(new_map: PackedScene) -> void:
	if new_map == null:
		return
	for child: Node in map_root.get_children():
		child.queue_free()
	var instance: Node = new_map.instantiate()
	if instance is Node2D:
		map_root.add_child(instance)
	else:
		instance.queue_free()


func _setup_navigation() -> void:
	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.agent_radius = 20.0
	navigation_polygon.parsed_geometry_type = 2
	navigation_polygon.parsed_collision_mask = 1
	navigation_polygon.add_outline(PackedVector2Array([
		Vector2(-5000.0, -5000.0), Vector2(5000.0, -5000.0),
		Vector2(5000.0, 5000.0), Vector2(-5000.0, 5000.0)
	]))
	navigation_region.navigation_polygon = navigation_polygon
	navigation_region.bake_navigation_polygon()


func _spawn_online_player(peer: int) -> void:
	if _find_player(peer) != null:
		return
	player_spawner.spawn({"peer_id": peer, "position": _spawn_position(peer)})


func _spawn_player(data: Variant) -> Node:
	var spawn_data: Dictionary = data as Dictionary
	var player_id: int = int(spawn_data.get("peer_id", 1))
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	player.name = "Player_%d" % player_id
	player.peer_id = str(player_id)
	player.set_multiplayer_authority(player_id, true)
	var state_sync: MultiplayerSynchronizer = player.get_node_or_null("StateSynchronizer") as MultiplayerSynchronizer
	if state_sync != null:
		state_sync.set_multiplayer_authority(1)
	var initial_position: Vector2 = spawn_data.get("position", Vector2.ZERO)
	player.global_position = initial_position
	player.network_position_q = Vector2i(
		NetworkManager.quantize(initial_position.x),
		NetworkManager.quantize(initial_position.y)
	)
	player.player_died.connect(_on_player_died)
	if NetworkManager.is_single or player_id == multiplayer.get_unique_id():
		player.is_local = true
		call_deferred("_bind_local_player", player)
	call_deferred("_configure_synchronizers_for_entity", player)
	return player


func _spawn_position(peer: int) -> Vector2:
	var spawn: Node2D = get_tree().get_first_node_in_group("player_spawn") as Node2D
	var base: Vector2 = spawn.global_position if spawn != null else Vector2.ZERO
	return base + Vector2.from_angle(float(peer) * 1.73) * float((peer % 4) * 32)


func _bind_existing_local_player() -> void:
	var player: GamePlayer = _find_player(multiplayer.get_unique_id())
	if player != null:
		_bind_local_player(player)


func _bind_local_player(player: GamePlayer) -> void:
	if has_node("HUD"):
		$HUD.set("player", player)


func _on_peer_joined_game(peer: int, _player_name: String) -> void:
	# A late client is spawned after its Game scene reports that its spawners exist.
	if NetworkManager.is_host:
		print("[Game] Peer %d connected; waiting for Game readiness" % peer)


func _on_peer_left_game(peer: int) -> void:
	var player: GamePlayer = _find_player(peer)
	if player != null:
		player.queue_free()


func _find_player(player_id: int) -> GamePlayer:
	for node: Node in entities.get_children():
		if node is GamePlayer and int((node as GamePlayer).peer_id) == player_id:
			return node as GamePlayer
	return null


@rpc("any_peer", "call_remote", "reliable")
func client_game_ready() -> void:
	if not NetworkManager.is_host:
		return
	var client_id: int = multiplayer.get_remote_sender_id()
	_spawn_online_player(client_id)
	for node: Node in entities.get_children():
		if node is GamePlayer:
			var player := node as GamePlayer
			sync_player_snapshot.rpc_id(client_id, {
				"peer_id": int(player.peer_id),
				"position": player.global_position
			})
		elif node is GameChest:
			var chest := node as GameChest
			sync_chest_snapshot.rpc_id(client_id, {"id": chest.chest_id, "position": chest.global_position})
		elif node is GameCrystal:
			var crystal := node as GameCrystal
			sync_crystal_snapshot.rpc_id(client_id, {"id": crystal.crystal_id, "position": crystal.global_position})
		elif node is GamePickup:
			var pickup := node as GamePickup
			sync_pickup_snapshot.rpc_id(client_id, {
				"id": pickup.pickup_id,
				"item_id": pickup.item_id,
				"amount": pickup.amount,
				"position": pickup.global_position,
				"throw_velocity": Vector2.ZERO
			})


@rpc("authority", "call_remote", "reliable")
func sync_player_snapshot(data: Dictionary) -> void:
	var player_id: int = int(data.get("peer_id", 1))
	if _find_player(player_id) == null:
		entities.add_child(_spawn_player(data), true)


@rpc("authority", "call_remote", "reliable")
func sync_chest_snapshot(data: Dictionary) -> void:
	if _find_chest(str(data.get("id", ""))) == null:
		entities.add_child(_spawn_chest(data), true)


@rpc("authority", "call_remote", "reliable")
func sync_crystal_snapshot(data: Dictionary) -> void:
	if _find_crystal(str(data.get("id", ""))) == null:
		entities.add_child(_spawn_crystal(data), true)


@rpc("authority", "call_remote", "reliable")
func sync_pickup_snapshot(data: Dictionary) -> void:
	if _find_pickup(str(data.get("id", ""))) == null:
		entities.add_child(_spawn_pickup(data), true)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_move(position_q: Vector2i) -> void:
	if not NetworkManager.is_host:
		return
	var player: GamePlayer = _find_player(multiplayer.get_remote_sender_id())
	if player != null:
		player.global_position = Vector2(
			NetworkManager.dequantize(position_q.x),
			NetworkManager.dequantize(position_q.y)
		)
		player.network_position_q = position_q


func request_shoot_for_player(owner_id: int, direction: Vector2) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	var shooter: GamePlayer = _find_player(owner_id)
	if shooter == null or not shooter.visible or direction.length_squared() < 0.001:
		return
	var weapon: Dictionary = shooter.get_current_weapon_data()
	if weapon.is_empty():
		return
	var weapon_id: String = str(weapon.get("id", ""))
	if owner_id != 1:
		var owns_weapon: bool = false
		for slot: Dictionary in shooter.inventory.slots:
			if str(slot.get("id", "")) == weapon_id:
				owns_weapon = true
				break
		if not owns_weapon:
			return
		var server_loaded: int = int(shooter.magazine.get(weapon_id, 0))
		if server_loaded <= 0:
			return
		shooter.magazine[weapon_id] = server_loaded - 1
	var now: int = Time.get_ticks_msec()
	var allowed_at: int = int(_server_fire_at.get(owner_id, 0))
	if now < allowed_at:
		return
	_server_fire_at[owner_id] = now + int(float(weapon.get("fire_rate", 0.25)) * 1000.0)
	_spawn_weapon_projectiles(shooter, owner_id, direction.normalized(), weapon)


@rpc("any_peer", "call_remote", "reliable")
func request_shoot(direction: Vector2) -> void:
	if NetworkManager.is_host:
		request_shoot_for_player(multiplayer.get_remote_sender_id(), direction)


func spawn_local_bullet(origin: Vector2, direction: Vector2, weapon: Dictionary) -> void:
	var owner_id: int = 1 if NetworkManager.is_single else multiplayer.get_unique_id()
	_spawn_projectile(owner_id, origin, direction, weapon)
	if str(weapon.get("weapon_type", "")) == "shotgun":
		for angle_degrees: float in [-15.0, -10.0, -5.0, 5.0, 10.0, 15.0, 0.0]:
			_spawn_projectile(owner_id, origin, direction.rotated(deg_to_rad(angle_degrees)), weapon)


func spawn_network_bullet(direction: Vector2, owner_id: int) -> void:
	request_shoot_for_player(owner_id, direction)


func _spawn_weapon_projectiles(shooter: GamePlayer, owner_id: int, direction: Vector2, weapon: Dictionary) -> void:
	shooter.weapon_pivot.rotation = direction.angle()
	var muzzle: Vector2 = shooter.get_muzzle_position(direction)
	if str(weapon.get("weapon_type", "")) == "shotgun":
		for pellet: int in range(8):
			var spread: float = lerpf(-15.0, 15.0, float(pellet) / 7.0)
			_spawn_projectile(owner_id, muzzle, direction.rotated(deg_to_rad(spread)), weapon)
	else:
		_spawn_projectile(owner_id, muzzle, direction, weapon)


func _spawn_projectile(owner_id: int, origin: Vector2, direction: Vector2, weapon: Dictionary) -> void:
	var data: Dictionary = {
		"id": _next_bullet_id,
		"owner_id": owner_id,
		"position": origin,
		"direction": direction.normalized(),
		"speed": float(weapon.get("bullet_speed", 700.0)),
		"damage": float(weapon.get("damage", 10.0))
	}
	_next_bullet_id += 1
	if NetworkManager.is_single:
		entities.add_child(_spawn_bullet(data), true)
	else:
		bullet_spawner.spawn(data)


func _spawn_bullet(data: Variant) -> Node:
	var bullet_data: Dictionary = data as Dictionary
	var bullet := BULLET_SCENE.instantiate() as GameBullet
	bullet.name = "Bullet_%d" % int(bullet_data.get("id", 0))
	bullet.owner_id = int(bullet_data.get("owner_id", 0))
	var bullet_position: Vector2 = bullet_data.get("position", Vector2.ZERO)
	bullet.global_position = bullet_position
	bullet.network_position = bullet.global_position
	var bullet_direction: Vector2 = bullet_data.get("direction", Vector2.RIGHT)
	bullet.local_direction = bullet_direction
	bullet.local_speed = float(bullet_data.get("speed", 700.0))
	bullet.local_damage = float(bullet_data.get("damage", 10.0))
	bullet.set_multiplayer_authority(1, true)
	return bullet


@rpc("any_peer", "call_remote", "reliable")
func request_melee(direction: Vector2) -> void:
	if NetworkManager.is_host:
		perform_melee(multiplayer.get_remote_sender_id(), direction, 15.0)


func perform_melee(attacker_id: int, direction: Vector2, damage: float = 15.0) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	var attacker: GamePlayer = _find_player(attacker_id)
	if attacker == null:
		return
	var facing: Vector2 = direction.normalized()
	var targets: Array[Node] = get_tree().get_nodes_in_group("enemy")
	targets.append_array(get_tree().get_nodes_in_group("player"))
	for node: Node in targets:
		if node == attacker or not node is Node2D:
			continue
		var target := node as Node2D
		if target is GamePlayer and not (target as GamePlayer).visible:
			continue
		if target is GameZombie and (target as GameZombie).dead:
			continue
		var offset: Vector2 = target.global_position - attacker.global_position
		if offset.length() > 50.0 or offset.length_squared() <= 0.001:
			continue
		if offset.normalized().dot(facing) < cos(deg_to_rad(45.0)):
			continue
		if target.has_method("take_damage"):
			target.call("take_damage", damage, attacker.global_position, 400.0)


func _on_player_died(player_id: int) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	var player: GamePlayer = _find_player(player_id)
	if player == null:
		return
	if not NetworkManager.is_single:
		on_player_died.rpc(player_id)


@rpc("authority", "call_local", "reliable")
func on_player_died(player_id: int) -> void:
	var player: GamePlayer = _find_player(player_id)
	if player != null:
		player.visible = false
		player.set_physics_process(false)
		player.get_node("CollisionShape2D").set_deferred("disabled", true)


func _spawn_crystals() -> void:
	if not is_crystal_capture_mode() or (not NetworkManager.is_single and not NetworkManager.is_host):
		return
	for index: int in range(_crystal_positions.size()):
		var data: Dictionary = {"id": "crystal_%d" % index, "position": _crystal_positions[index]}
		if NetworkManager.is_single:
			entities.add_child(_spawn_crystal(data), true)
		else:
			crystal_spawner.spawn(data)


func _spawn_crystal(data: Variant) -> Node:
	var crystal_data: Dictionary = data as Dictionary
	var crystal := CRYSTAL_SCENE.instantiate() as GameCrystal
	crystal.name = str(crystal_data.get("id", "Crystal"))
	crystal.crystal_id = crystal.name
	crystal.global_position = crystal_data.get("position", Vector2.ZERO)
	crystal.set_multiplayer_authority(1, true)
	return crystal


func _find_crystal(crystal_id: String) -> GameCrystal:
	for node: Node in entities.get_children():
		if node is GameCrystal and (node as GameCrystal).crystal_id == crystal_id:
			return node as GameCrystal
	return null


func capture_crystal_authoritative(crystal_id: String, player_id: int) -> void:
	if not is_crystal_capture_mode() or (not NetworkManager.is_single and not NetworkManager.is_host):
		return
	var player: GamePlayer = _find_player(player_id)
	var crystal: GameCrystal = _find_crystal(crystal_id)
	if player == null or crystal == null or not player.visible or player.global_position.distance_to(crystal.global_position) > 85.0:
		return
	var captured_position: Vector2 = crystal.global_position
	player.crystals += 1
	if not NetworkManager.is_single:
		sync_crystal_captured.rpc(crystal_id, player_id, player.crystals)
	else:
		crystal.play_captured()
	_respawn_crystal_later(captured_position, crystal_id)


@rpc("authority", "call_local", "reliable")
func sync_crystal_captured(crystal_id: String, player_id: int, total: int) -> void:
	var player: GamePlayer = _find_player(player_id)
	if player != null:
		player.crystals = total
	var crystal: GameCrystal = _find_crystal(crystal_id)
	if crystal != null:
		crystal.play_captured()


func _respawn_crystal_later(position: Vector2, crystal_id: String) -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree() or (not NetworkManager.is_single and not NetworkManager.is_host):
		return
	var data: Dictionary = {"id": crystal_id, "position": position}
	if NetworkManager.is_single:
		entities.add_child(_spawn_crystal(data), true)
	else:
		crystal_spawner.spawn(data)


func _spawn_chests() -> void:
	var index: int = 0
	for marker: Node in get_tree().get_nodes_in_group("chest_spawn"):
		if marker is Node2D:
			var data: Dictionary = {"id": "chest_%d" % index, "position": (marker as Node2D).global_position}
			if NetworkManager.is_single:
				entities.add_child(_spawn_chest(data), true)
			else:
				chest_spawner.spawn(data)
			index += 1


func _spawn_chest(data: Variant) -> Node:
	var chest_data: Dictionary = data as Dictionary
	var chest := CHEST_SCENE.instantiate() as GameChest
	chest.name = str(chest_data.get("id", "Chest"))
	chest.chest_id = chest.name
	var chest_position: Vector2 = chest_data.get("position", Vector2.ZERO)
	chest.global_position = chest_position
	chest.set_multiplayer_authority(1, true)
	return chest


func notify_chest_opened(chest_id: String) -> void:
	if NetworkManager.is_host:
		sync_chest_opened.rpc(chest_id)


@rpc("authority", "call_remote", "reliable")
func sync_chest_opened(chest_id: String) -> void:
	var chest: GameChest = _find_chest(chest_id)
	if chest != null:
		chest.server_opened()


func spawn_pickup(item_id: String, amount: int, p_position: Vector2, throw_velocity: Vector2 = Vector2.ZERO, p_pickup_id: String = "") -> GamePickup:
	if NetworkManager.is_client:
		return null
	var data: Dictionary = {
		"id": p_pickup_id if not p_pickup_id.is_empty() else "Pickup_%d" % _next_pickup_id,
		"item_id": item_id,
		"amount": amount,
		"position": p_position,
		"throw_velocity": throw_velocity
	}
	_next_pickup_id += 1
	if NetworkManager.is_single:
		var pickup: GamePickup = _spawn_pickup(data) as GamePickup
		entities.add_child(pickup, true)
		return pickup
	# Выброшенные при смерти предметы приходят клиентам отдельным RPC,
	# поэтому не пропускаем их через MultiplayerSpawner второй раз.
	if throw_velocity.length_squared() > 0.0:
		var dropped_pickup: GamePickup = _spawn_pickup(data) as GamePickup
		entities.add_child(dropped_pickup, true)
		return dropped_pickup
	var spawned: Node = pickup_spawner.spawn(data)
	return spawned as GamePickup


func _spawn_pickup(data: Variant) -> Node:
	var pickup_data: Dictionary = data as Dictionary
	var pickup := PICKUP_SCENE.instantiate() as GamePickup
	pickup.name = str(pickup_data.get("id", "Pickup"))
	pickup.pickup_id = pickup.name
	pickup.item_id = str(pickup_data.get("item_id", "medkit"))
	pickup.amount = int(pickup_data.get("amount", 1))
	var pickup_position: Vector2 = pickup_data.get("position", Vector2.ZERO)
	var pickup_velocity: Vector2 = pickup_data.get("throw_velocity", Vector2.ZERO)
	pickup.global_position = pickup_position
	pickup.throw_velocity = pickup_velocity
	pickup.set_multiplayer_authority(1, true)
	return pickup


func collect_pickup_authoritative(pickup_id: String, player_id: int) -> void:
	var player: GamePlayer = _find_player(player_id)
	var pickup: GamePickup = _find_pickup(pickup_id)
	if player == null or pickup == null or player.global_position.distance_to(pickup.global_position) > 90.0:
		return
	if player.inventory.add_item(pickup.item_id, pickup.amount):
		if not NetworkManager.is_single:
			confirm_pickup.rpc(pickup_id, player_id, player.inventory.make_snapshot())
		pickup.server_collected()


@rpc("authority", "call_remote", "reliable")
func confirm_pickup(pickup_id: String, player_id: int, snapshot: Array) -> void:
	var player: GamePlayer = _find_player(player_id)
	if player != null and player_id == multiplayer.get_unique_id():
		player.inventory.apply_snapshot(snapshot, player.current_weapon_slot)
	var pickup: GamePickup = _find_pickup(pickup_id)
	if pickup != null:
		pickup.play_collected()


@rpc("any_peer", "call_remote", "reliable")
func request_action(action: Dictionary) -> void:
	if NetworkManager.is_host:
		handle_network_action(multiplayer.get_remote_sender_id(), action)


func handle_network_action(player_id: int, action: Dictionary) -> void:
	match str(action.get("type", "")):
		"pickup":
			collect_pickup_authoritative(str(action.get("entity_id", "")), player_id)
		"open_chest":
			var chest: GameChest = _find_chest(str(action.get("entity_id", "")))
			var player: GamePlayer = _find_player(player_id)
			if chest != null and player != null and player.global_position.distance_to(chest.global_position) <= 100.0:
				chest._open()
		"use_item":
			var item_player: GamePlayer = _find_player(player_id)
			if item_player != null:
				item_player.use_item(int(action.get("slot", -1)))
		"reload":
			var reload_player: GamePlayer = _find_player(player_id)
			if reload_player != null:
				var weapon_id: String = str(action.get("weapon_id", ""))
				var loaded: int = reload_player._reload_weapon(weapon_id)
				confirm_reload.rpc_id(player_id, weapon_id, loaded, reload_player.inventory.make_snapshot())
		"capture_crystal":
			if is_crystal_capture_mode():
				capture_crystal_authoritative(str(action.get("entity_id", "")), player_id)
		"melee_attack":
			var attacker: GamePlayer = _find_player(player_id)
			if attacker == null or not attacker.visible or attacker.hp <= 0.0:
				return
			if not attacker.current_weapon.is_empty() and attacker._current_loaded_ammo() > 0:
				return
			var target_id: String = str(action.get("target_id", ""))
			var target: Node2D = _find_combat_target(target_id)
			if target == null or not target.has_method("take_damage") or target == attacker:
				return
			if target is GamePlayer and (not (target as GamePlayer).visible or (target as GamePlayer).hp <= 0.0):
				return
			if target is GameZombie and (target as GameZombie).dead:
				return
			var raw_direction: Variant = action.get("dir", [0.0, 0.0])
			if not raw_direction is Array or (raw_direction as Array).size() < 2:
				return
			var direction_values: Array = raw_direction as Array
			var direction: Vector2 = Vector2(
				float(direction_values[0]),
				float(direction_values[1])
			).normalized()
			var offset: Vector2 = target.global_position - attacker.global_position
			var is_crystal_blade: bool = str(attacker.current_weapon.get("id", "")) == "crystal_blade"
			var max_range: float = 72.0 if is_crystal_blade else 60.0
			if direction.length_squared() <= 0.001 or offset.length() > max_range or offset.length_squared() <= 0.001:
				return
			if absf(direction.angle_to(offset)) > deg_to_rad(60.0):
				return
			var damage: float = 26.0 if is_crystal_blade else (15.0 if attacker.current_weapon.is_empty() else 10.0)
			target.call("take_damage", damage, attacker.global_position, 400.0)


@rpc("authority", "call_remote", "reliable")
func confirm_reload(weapon_id: String, loaded: int, snapshot: Array) -> void:
	var player: GamePlayer = _find_player(multiplayer.get_unique_id())
	if player != null:
		player.magazine[weapon_id] = loaded
		player.inventory.apply_snapshot(snapshot, player.current_weapon_slot)


func _find_pickup(pickup_id: String) -> GamePickup:
	for node: Node in entities.get_children():
		if node is GamePickup and (node as GamePickup).pickup_id == pickup_id:
			return node as GamePickup
	return null


func _find_combat_target(target_id: String) -> Node2D:
	if target_id.begins_with("player:"):
		return _find_player(int(target_id.trim_prefix("player:")))
	if target_id.begins_with("zombie:"):
		return _find_zombie(target_id.trim_prefix("zombie:"))
	if target_id.begins_with("node:"):
		var path: NodePath = NodePath(target_id.trim_prefix("node:"))
		return get_node_or_null(path) as Node2D
	return null


func _find_chest(chest_id: String) -> GameChest:
	for node: Node in entities.get_children():
		if node is GameChest and (node as GameChest).chest_id == chest_id:
			return node as GameChest
	return null


func _start_music() -> void:
	var track: AudioStreamOggVorbis = match_music.stream as AudioStreamOggVorbis
	if track != null:
		track.loop = true
	if match_music.stream != null:
		match_music.play()


func _on_exit_pressed() -> void:
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
