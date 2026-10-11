extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/objects/Player.tscn")
const BULLET_SCENE: PackedScene = preload("res://scenes/objects/Bullet.tscn")
const PICKUP_SCENE: PackedScene = preload("res://scenes/objects/Pickup.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/objects/Chest.tscn")
const NOISE_LURE_SCENE: PackedScene = preload("res://scenes/objects/NoiseLure.tscn")
const RESIN_PATCH_SCENE: PackedScene = preload("res://scenes/objects/ResinPatch.tscn")
const PULSE_BEACON_SCENE: PackedScene = preload("res://scenes/objects/PulseBeacon.tscn")
const THROWN_ITEM_VISUAL_SCENE: PackedScene = preload("res://scenes/objects/ThrownItemVisual.tscn")

@export var map_scene: PackedScene = preload("res://scenes/maps/Island.tscn")

@onready var map_root: Node2D = $MapContainer/NavigationRegion2D/MapRoot
@onready var entities: Node2D = $MapContainer/Entities
@onready var navigation_region: NavigationRegion2D = $MapContainer/NavigationRegion2D
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var bullet_spawner: MultiplayerSpawner = $BulletSpawner
@onready var pickup_spawner: MultiplayerSpawner = $PickupSpawner
@onready var chest_spawner: MultiplayerSpawner = $ChestSpawner
@onready var match_music: AudioStreamPlayer = $MatchMusic

var _next_pickup_id: int = 1
var _next_bullet_id: int = 1
var _next_noise_lure_id: int = 1
var _next_placed_item_id: int = 1
var _server_fire_at: Dictionary = {}
var sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.033


const MODE_CLASSIC := "classic"
const MODE_BATTLE_ROYALE := "battle_royale"
const ADAPTIVE_SYNC_INTERVAL: float = 0.25

# One shared cadence keeps the portal window readable in both supported modes.
# A short warning period prevents an immediate route change at match start.
const PORTAL_INITIAL_DELAY: float = 12.0
const PORTAL_OPEN_DURATION: float = 7.0
const PORTAL_COOLDOWN_DURATION: float = 15.0

var match_time_left: float = 180.0
var match_elapsed: float = 0.0
var match_finished: bool = false
var match_status: String = "Матч начинается"
var _progress_saved: bool = false
var zone_center: Vector2 = Vector2.ZERO
var zone_radius: float = 1200.0
var zone_start_radius: float = 1200.0
var zone_target_radius: float = 260.0
var _state_sync_timer: float = 0.0
var _zone_damage_timer: float = 0.0
var _adaptive_sync_timer: float = 0.0
var _portal_pairs: Dictionary = {}
var _pending_portal_transfers: Dictionary = {}
var _portal_effect_revisions: Dictionary = {}


func _portals_allowed() -> bool:
	return NetworkManager.game_mode in [MODE_CLASSIC, MODE_BATTLE_ROYALE]


func _configure_portals() -> void:
	_portal_pairs.clear()
	# The match advances pairs after player movement; clients only consume state.
	process_physics_priority = 10
	for node: Node in map_root.find_children("*", "", true, false):
		if not node is PortalPair:
			continue
		var pair: PortalPair = node as PortalPair
		pair.set_physics_process(false)
		if not _portals_allowed():
			pair.is_open = false
			pair.hide()
			pair.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		pair.initial_delay = PORTAL_INITIAL_DELAY
		pair.open_duration = PORTAL_OPEN_DURATION
		pair.closed_duration = PORTAL_COOLDOWN_DURATION
		# Restart the phase so every map gets the same opening warning and cadence.
		pair._elapsed = 0.0
		pair._remaining = PORTAL_INITIAL_DELAY
		pair._set_open(false)
		var pair_id: String = str(map_root.get_path_to(pair))
		_portal_pairs[pair_id] = pair
		pair.open_state_changed.connect(_on_portal_open_changed.bind(pair_id))
		pair.player_teleported.connect(_on_portal_player_teleported.bind(pair_id))


func _physics_process(delta: float) -> void:
	if match_finished or not _portals_allowed():
		return
	if NetworkManager.is_single or NetworkManager.is_host:
		for pair: PortalPair in _portal_pairs.values():
			pair._physics_process(delta)


func _portal_states() -> Dictionary:
	var states: Dictionary = {}
	for pair_id: String in _portal_pairs:
		states[pair_id] = (_portal_pairs[pair_id] as PortalPair).get_open_state()
	return states


func _on_portal_open_changed(_open: bool, _pair_id: String) -> void:
	if NetworkManager.is_host:
		sync_portal_states.rpc(_portal_states())


@rpc("authority", "call_remote", "reliable")
func sync_portal_states(states: Dictionary) -> void:
	if not NetworkManager.is_client or not _portals_allowed():
		return
	for pair_id: Variant in states:
		var pair: PortalPair = _portal_pairs.get(pair_id) as PortalPair
		if pair != null and states[pair_id] is Dictionary:
			pair.apply_open_state(states[pair_id])


func _on_portal_player_teleported(player: GamePlayer, departure: Vector2, arrival: Vector2, pair_id: String) -> void:
	# Advance the movement epoch so old client packets cannot undo a portal transfer.
	player.movement_revision += 1
	if NetworkManager.is_host:
		sync_portal_transfer.rpc(pair_id, int(player.peer_id), departure, arrival, player.movement_revision)


@rpc("authority", "call_remote", "reliable")
func sync_portal_transfer(
	pair_id: String, player_id: int, departure: Vector2, arrival: Vector2,
	revision: int
) -> void:
	if not NetworkManager.is_client or not _portals_allowed():
		return
	var pair: PortalPair = _portal_pairs.get(pair_id) as PortalPair
	if pair == null or not departure.is_finite() or not arrival.is_finite() or revision < 0:
		return
	var effect_key: String = "%s:%d" % [pair_id, player_id]
	if revision <= int(_portal_effect_revisions.get(effect_key, -1)):
		return
	_portal_effect_revisions[effect_key] = revision
	pair.play_transfer_effect(departure, arrival)
	var transfer: Dictionary = {"position": arrival, "revision": revision}
	var player: GamePlayer = _find_player(player_id)
	if player == null:
		_pending_portal_transfers[player_id] = transfer
	else:
		_apply_portal_position(player, transfer)


func _apply_portal_position(player: GamePlayer, transfer: Dictionary) -> void:
	var revision: int = int(transfer["revision"])
	# A newer position snapshot may already have applied this movement epoch.
	if revision <= player.movement_revision:
		return
	var arrival: Vector2 = transfer["position"]
	player.apply_movement_snapshot(revision, arrival)
	player.knockback_velocity = Vector2.ZERO
	player.network_position_q = Vector2i(NetworkManager.quantize(arrival.x), NetworkManager.quantize(arrival.y))


func _apply_pending_portal_transfer(player: GamePlayer) -> void:
	var player_id: int = int(player.peer_id)
	if _pending_portal_transfers.has(player_id):
		_apply_portal_position(player, _pending_portal_transfers[player_id])
		_pending_portal_transfers.erase(player_id)


func is_battle_royale_mode() -> bool:
	return NetworkManager.game_mode == MODE_BATTLE_ROYALE


func can_respawn(_player_id: int = 1) -> bool:
	return not is_battle_royale_mode() and not match_finished


func _configure_match_rules() -> void:
	match_time_left = 150.0 if NetworkManager.game_mode == MODE_CLASSIC else 210.0
	zone_start_radius = 1200.0
	zone_radius = zone_start_radius
	match_status = "Классический бой" if NetworkManager.game_mode == MODE_CLASSIC else "Королевская битва"
	if has_node("MatchOverlay"):
		$MatchOverlay.configure(zone_center, zone_radius, is_battle_royale_mode())

func _ready() -> void:
	NetworkManager.clear_snapshots()
	_configure_spawners()
	_start_music()
	_select_and_load_map()
	_configure_match_rules()
	_configure_portals()
	call_deferred("_configure_existing_entity_synchronizers")
	_setup_navigation.call_deferred()
	if NetworkManager.is_single:
		var player: GamePlayer = _spawn_player({"peer_id": 1, "position": _spawn_position(0)}) as GamePlayer
		entities.add_child(player, true)
		_bind_local_player(player)
		_spawn_chests()
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
	else:
		await get_tree().process_frame
		_bind_existing_local_player()
		client_game_ready.rpc_id(1)


func _process(delta: float) -> void:
	if not match_finished and (NetworkManager.is_single or NetworkManager.is_host):
		_tick_match_rules(delta)
	if NetworkManager.is_host:
		_adaptive_sync_timer -= delta
		if _adaptive_sync_timer <= 0.0:
			_adaptive_sync_timer = ADAPTIVE_SYNC_INTERVAL
			_update_adaptive_sync_rates()
		sync_timer += delta
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = fmod(sync_timer, SYNC_INTERVAL)
			_broadcast_snapshot()


func _tick_match_rules(delta: float) -> void:
	match_elapsed += delta
	match_time_left = maxf(0.0, match_time_left - delta)
	if is_battle_royale_mode():
		var shrink_duration: float = 185.0
		var shrink_ratio: float = clampf((match_elapsed - 20.0) / shrink_duration, 0.0, 1.0)
		zone_radius = lerpf(zone_start_radius, zone_target_radius, shrink_ratio)
		_zone_damage_timer += delta
		if _zone_damage_timer >= 0.25:
			_zone_damage_timer = 0.0
			for player_node: Node in get_tree().get_nodes_in_group("player"):
				if player_node is GamePlayer and (player_node as GamePlayer).visible:
					var player := player_node as GamePlayer
					if player.global_position.distance_to(zone_center) > zone_radius:
						player.take_damage(10.0, zone_center, 0.0)
		if has_node("MatchOverlay"):
			$MatchOverlay.configure(zone_center, zone_radius, true)
	if is_battle_royale_mode() and _remaining_enemies() == 0:
		_finish_match(true, "Все соперники выбиты")
	var local_player: GamePlayer = _find_player(NetworkManager.get_local_player_id())
	if local_player == null and NetworkManager.is_single:
		local_player = _find_player(1)
	if match_time_left <= 0.0:
		_finish_match(true, "Время матча вышло")
	_state_sync_timer += delta
	if _state_sync_timer >= 0.2:
		_state_sync_timer = 0.0
		if NetworkManager.is_host:
			receive_match_state.rpc(match_time_left, zone_radius, match_status, match_finished)


func _remaining_enemies() -> int:
	var remaining: int = 0
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if node is GameZombie and not (node as GameZombie).dead:
			remaining += 1
	return remaining

func _finish_match(won: bool, reason: String) -> void:
	if match_finished:
		return
	match_finished = true
	if NetworkManager.is_single and not _progress_saved:
		_progress_saved = true
		GameState.record_match(won)
	for pair: PortalPair in _portal_pairs.values():
		pair._set_open(false)
	match_status = ("ПОБЕДА — " if won else "ПОРАЖЕНИЕ — ") + reason


func get_match_time_text() -> String:
	var total_seconds: int = maxi(0, ceili(match_time_left))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func get_match_status_text() -> String:
	return match_status


func get_zone_text() -> String:
	if not is_battle_royale_mode():
		return ""
	return "ЗОНА %dm" % roundi(zone_radius)


func get_portal_hud_state() -> Dictionary:
	if not _portals_allowed() or match_finished or _portal_pairs.is_empty():
		return {"available": false}
	var first_pair: PortalPair = _portal_pairs.values().front() as PortalPair
	if first_pair == null:
		return {"available": false}
	return {
		"available": true,
		"open": first_pair.is_open,
		"remaining": maxf(first_pair._remaining, 0.0),
	}


@rpc("authority", "call_remote", "unreliable")
func receive_match_state(time_left: float, radius: float, status: String, finished: bool) -> void:
	match_time_left = time_left
	zone_radius = radius
	match_status = status
	match_finished = finished
	if has_node("MatchOverlay"):
		$MatchOverlay.configure(zone_center, zone_radius, is_battle_royale_mode())
func _broadcast_snapshot() -> void:
	var tick: int = Time.get_ticks_msec()
	var players: Array[GamePlayer] = []
	var zombies: Array[GameZombie] = []
	var players_state: Dictionary = {}
	var zombies_state: Dictionary = {}
	for node: Node in entities.get_children():
		if not node is GamePlayer:
			continue
		var player: GamePlayer = node as GamePlayer
		players.append(player)
		var player_id: int = player.get_multiplayer_authority()
		var world_position: Vector2 = player.global_position
		players_state[str(player_id)] = {
			"x": world_position.x,
			"y": world_position.y,
			"rot": player.rotation,
			"hp": player.hp,
			"coins": player.coins,
			"movement_revision": player.movement_revision,
		}
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if not node is GameZombie:
			continue
		var zombie: GameZombie = node as GameZombie
		zombies.append(zombie)
		var world_position: Vector2 = zombie.global_position
		zombies_state[str(zombie.get_instance_id())] = {
			"x": world_position.x,
			"y": world_position.y,
			"hp": zombie.hp,
			"zombie_id": zombie.zombie_id,
		}

	var portal_states: Dictionary = _portal_states()
	var max_sync_distance_squared: float = 800.0 * 800.0
	for peer_id: int in multiplayer.get_peers():
		var viewer: GamePlayer = null
		for candidate: GamePlayer in players:
			if candidate.get_multiplayer_authority() == peer_id:
				viewer = candidate
				break
		if viewer == null:
			continue
		var visible_players: Dictionary = {}
		var visible_zombies: Dictionary = {}
		for player: GamePlayer in players:
			var player_key: String = str(player.get_multiplayer_authority())
			if viewer.global_position.distance_squared_to(player.global_position) < max_sync_distance_squared:
				visible_players[player_key] = players_state[player_key]
		for zombie: GameZombie in zombies:
			var zombie_key: String = str(zombie.get_instance_id())
			if viewer.global_position.distance_squared_to(zombie.global_position) < max_sync_distance_squared:
				visible_zombies[zombie_key] = zombies_state[zombie_key]
		_receive_snapshot.rpc_id(peer_id, {
			"tick": tick,
			"players": visible_players,
			"zombies": visible_zombies,
			"portals": portal_states,
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
	sync_portal_states(snapshot.get("portals", {}) as Dictionary)
	var players_state: Dictionary = snapshot.get("players", {}) as Dictionary
	for raw_id: Variant in players_state.keys():
		var player_id: int = int(raw_id)
		var player: GamePlayer = _find_player(player_id)
		if player == null:
			continue
		var player_state: Dictionary = players_state.get(raw_id, {}) as Dictionary
		var server_position: Vector2 = Vector2(float(player_state.get("x", 0.0)), float(player_state.get("y", 0.0)))
		var movement_revision: int = int(player_state.get("movement_revision", 0))
		if movement_revision < player.movement_revision:
			continue
		var movement_changed: bool = movement_revision > player.movement_revision
		var movement_applied: bool = player.apply_movement_snapshot(movement_revision, server_position)
		if movement_changed:
			player.knockback_velocity = Vector2.ZERO
			player.network_position_q = Vector2i(NetworkManager.quantize(server_position.x), NetworkManager.quantize(server_position.y))
		if not movement_applied:
			if player_id == NetworkManager.get_local_player_id():
				if player.global_position.distance_to(server_position) > 50.0:
					player.global_position = server_position
			else:
				var trajectory: Dictionary = NetworkManager.get_trajectory_for(str(raw_id), false)
				if not trajectory.is_empty():
					var trajectory_position: Vector2 = Vector2(trajectory.get("pos", Vector2.ZERO))
					var trajectory_velocity: Vector2 = Vector2(trajectory.get("vel", Vector2.ZERO))
					player.set_trajectory(trajectory_position, trajectory_velocity)
		player.hp = float(player_state.get("hp", player.hp))
		player.coins = int(player_state.get("coins", player.coins))

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


func _select_and_load_map() -> void:
	if NetworkManager.is_single:
		var requested_mode: String = GameState.current_mode
		if GameState.current_level == 0 and requested_mode.is_empty():
			requested_mode = NetworkManager.game_mode
		NetworkManager.game_mode = requested_mode if requested_mode in [MODE_CLASSIC, MODE_BATTLE_ROYALE] else MODE_BATTLE_ROYALE
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
	if NetworkManager.is_single or player_id == NetworkManager.get_local_player_id():
		player.is_local = true
		call_deferred("_bind_local_player", player)
	call_deferred("_configure_synchronizers_for_entity", player)
	call_deferred("_apply_pending_portal_transfer", player)
	return player


func _spawn_position(peer: int) -> Vector2:
	var spawn: Node2D = get_tree().get_first_node_in_group("player_spawn") as Node2D
	var base: Vector2 = spawn.global_position if spawn != null else Vector2.ZERO
	return base + Vector2.from_angle(float(peer) * 1.73) * float((peer % 4) * 32)


func _bind_existing_local_player() -> void:
	var player: GamePlayer = _find_player(NetworkManager.get_local_player_id())
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
	sync_portal_states.rpc_id(client_id, _portal_states())
	for node: Node in entities.get_children():
		if node is GamePlayer:
			var player := node as GamePlayer
			sync_player_snapshot.rpc_id(client_id, {
				"peer_id": int(player.peer_id),
				"position": player.global_position,
				"revision": player.movement_revision,
			})
		elif node is GameChest:
			var chest := node as GameChest
			sync_chest_snapshot.rpc_id(client_id, {"id": chest.chest_id, "position": chest.global_position})
		elif node is GamePickup:
			var pickup := node as GamePickup
			sync_pickup_snapshot.rpc_id(client_id, {
				"id": pickup.pickup_id,
				"item_id": pickup.item_id,
				"amount": pickup.amount,
				"position": pickup.global_position,
				"throw_velocity": Vector2.ZERO
			})
		elif node is NoiseLure and (node as NoiseLure).is_active():
			var lure := node as NoiseLure
			sync_noise_lure.rpc_id(client_id, lure.global_position, lure._remaining, lure.attraction_radius, str(lure.name))


@rpc("authority", "call_remote", "reliable")
func sync_player_snapshot(data: Dictionary) -> void:
	var player_id: int = int(data.get("peer_id", 1))
	if _find_player(player_id) == null:
		entities.add_child(_spawn_player(data), true)
	var player: GamePlayer = _find_player(player_id)
	if player != null and data.has("revision"):
		_apply_portal_position(player, data)


@rpc("authority", "call_remote", "reliable")
func sync_chest_snapshot(data: Dictionary) -> void:
	if _find_chest(str(data.get("id", ""))) == null:
		entities.add_child(_spawn_chest(data), true)


@rpc("authority", "call_remote", "reliable")
func sync_pickup_snapshot(data: Dictionary) -> void:
	if _find_pickup(str(data.get("id", ""))) == null:
		entities.call_deferred("add_child", _spawn_pickup(data), true)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_move(position_q: Vector2i, movement_revision: int = 0) -> void:
	if not NetworkManager.is_host:
		return
	var player: GamePlayer = _find_player(multiplayer.get_remote_sender_id())
	if player != null and player.accepts_client_movement(movement_revision):
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
	var owner_id: int = 1 if NetworkManager.is_single else NetworkManager.get_local_player_id()
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
	if attacker == null or not attacker.visible or attacker.hp <= 0.0:
		return
	if not attacker.current_weapon.is_empty() and attacker._current_loaded_ammo() > 0:
		return
	var target: Node2D = attacker.get_melee_raycast_target(direction)
	var impact_position: Vector2 = target.global_position if target != null else attacker.global_position + direction.normalized() * 68.0
	attacker.play_melee_effect(direction, impact_position)
	if NetworkManager.is_host:
		sync_melee_swing.rpc(attacker_id, direction.normalized(), impact_position)
	if target == null:
		return
	var hit_damage: float = 15.0 if attacker.current_weapon.is_empty() else 10.0
	if target is GamePlayer:
		(target as GamePlayer).take_contact_damage(hit_damage, attacker.global_position, 400.0)
	else:
		target.call("take_damage", hit_damage, attacker.global_position, 400.0)


@rpc("authority", "call_remote", "unreliable")
func sync_melee_swing(attacker_id: int, direction: Vector2, impact_position: Vector2) -> void:
	var attacker: GamePlayer = _find_player(attacker_id)
	if attacker == null or attacker.is_local:
		return
	attacker.play_melee_effect(direction, impact_position)



func _on_player_died(player_id: int) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	var player: GamePlayer = _find_player(player_id)
	if player == null:
		return
	if is_battle_royale_mode() and player_id == NetworkManager.get_local_player_id():
		_finish_match(false, "Ты выбыл из арены")
	if not NetworkManager.is_single:
		on_player_died.rpc(player_id)


@rpc("authority", "call_local", "reliable")
func on_player_died(player_id: int) -> void:
	if is_battle_royale_mode() and player_id == NetworkManager.get_local_player_id():
		_finish_match(false, "Ты выбыл из арены")
	var player: GamePlayer = _find_player(player_id)
	if player != null:
		player.visible = false
		player.set_physics_process(false)
		player.get_node("CollisionShape2D").set_deferred("disabled", true)


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


func _throw_landing_position(player: GamePlayer, direction: Vector2, throw_range: float) -> Vector2:
	var throw_direction: Vector2 = direction.normalized()
	if throw_direction.length_squared() < 0.01:
		throw_direction = Vector2.RIGHT
	var origin: Vector2 = player.global_position
	var landing: Vector2 = origin + throw_direction * throw_range
	# Only map walls block throws, not players, zombies or pickups.
	var ray := PhysicsRayQueryParameters2D.create(origin, landing, 1, [player.get_rid()])
	ray.hit_from_inside = true
	var hit: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var impact: Vector2 = hit["position"]
		landing = origin + throw_direction * maxf(0.0, origin.distance_to(impact) - 12.0)
	return landing


func throw_noise_lure(player: GamePlayer, direction: Vector2, slot_index: int) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
	if player == null or player._dead or player.hp <= 0.0 or match_finished:
		return
	if not direction.is_finite() or not player.global_position.is_finite():
		return
	var item: Dictionary = player.inventory.get_slot(slot_index)
	if str(item.get("id", "")) != "noise_lure" or int(item.get("amount", 0)) <= 0:
		return
	var data: Dictionary = ItemDB.get_item("noise_lure")
	var duration: float = float(data.get("duration", 7.0))
	var radius: float = float(data.get("attraction_radius", 360.0))
	var throw_range: float = float(data.get("throw_range", 260.0))
	if not is_finite(duration) or not is_finite(radius) or not is_finite(throw_range):
		return
	if duration <= 0.0 or radius <= 0.0 or throw_range <= 0.0:
		return
	var start_position: Vector2 = player.global_position
	var landing: Vector2 = _throw_landing_position(player, direction, throw_range)
	if not player.inventory.remove_item("noise_lure", 1):
		return
	var lure_id: String = "NoiseLure_%d" % _next_noise_lure_id
	_next_noise_lure_id += 1
	_spawn_thrown_item_visual("noise_lure", start_position, landing, "noise_lure", duration, radius, lure_id)
	if not NetworkManager.is_single:
		sync_thrown_item_visual.rpc("noise_lure", start_position, landing)


func _spawn_noise_lure(p_position: Vector2, duration: float, radius: float, lure_id: String) -> void:
	if entities.has_node(NodePath(lure_id)):
		return
	var lure: NoiseLure = NOISE_LURE_SCENE.instantiate() as NoiseLure
	lure.name = lure_id
	lure.position = entities.to_local(p_position)
	lure.duration = duration
	lure.attraction_radius = radius
	entities.add_child(lure, true)


@rpc("authority", "call_remote", "reliable")
func sync_noise_lure(p_position: Vector2, duration: float, radius: float, lure_id: String) -> void:
	_spawn_noise_lure(p_position, duration, radius, lure_id)


@rpc("authority", "call_remote", "reliable")
func sync_pulse_beacon_visual(world_position: Vector2, radius: float, duration: float) -> void:
	if not NetworkManager.is_client:
		return
	var effect: PulseBeacon = PULSE_BEACON_SCENE.instantiate() as PulseBeacon
	entities.add_child(effect, true)
	effect.show_visual_only(world_position, radius, duration)


func throw_resin_bomb(player: GamePlayer, direction: Vector2, slot_index: int) -> void:
	if player == null or player._dead or (not NetworkManager.is_single and not NetworkManager.is_host):
		return
	var item: Dictionary = player.inventory.get_slot(slot_index)
	if str(item.get("id", "")) != "tar_bomb":
		return
	var item_data: Dictionary = ItemDB.get_item("tar_bomb")
	if not direction.is_finite() or not player.global_position.is_finite():
		return
	var start_position: Vector2 = player.global_position
	var landing: Vector2 = _throw_landing_position(player, direction, float(item_data.get("throw_range", 260.0)))
	if not player.inventory.remove_item("tar_bomb", 1):
		return
	UISoundManager.play_ui_sound("shoot_shotgun.wav")
	var duration: float = float(item_data.get("puddle_duration", 6.0))
	var slow: float = float(item_data.get("slow_multiplier", 0.55))
	_spawn_thrown_item_visual("tar_bomb", start_position, landing, "tar_bomb", duration, slow, "")
	if not NetworkManager.is_single:
		sync_thrown_item_visual.rpc("tar_bomb", start_position, landing)


func _spawn_thrown_item_visual(item_id: String, start_position: Vector2, landing: Vector2, result_kind: String, result_duration: float, result_value: float, result_id: String) -> void:
	var visual: GameThrownItemVisual = THROWN_ITEM_VISUAL_SCENE.instantiate() as GameThrownItemVisual
	if visual == null:
		return
	entities.add_child(visual, true)
	if not visual.launch(item_id, start_position, landing):
		visual.queue_free()
		return
	if not result_kind.is_empty():
		visual.landed.connect(_on_thrown_item_landed.bind(result_kind, result_duration, result_value, result_id))


func _on_thrown_item_landed(world_position: Vector2, result_kind: String, result_duration: float, result_value: float, result_id: String) -> void:
	if result_kind == "tar_bomb":
		_spawn_resin_patch(world_position, result_duration, result_value)
		if NetworkManager.is_host:
			sync_resin_patch.rpc(world_position, result_duration, result_value)
	elif result_kind == "noise_lure":
		_spawn_noise_lure(world_position, result_duration, result_value, result_id)
		if NetworkManager.is_host:
			sync_noise_lure.rpc(world_position, result_duration, result_value, result_id)


@rpc("authority", "call_remote", "reliable")
func sync_thrown_item_visual(item_id: String, start_position: Vector2, landing: Vector2) -> void:
	if not NetworkManager.is_client:
		return
	_spawn_thrown_item_visual(item_id, start_position, landing, "", 0.0, 0.0, "")


func _spawn_resin_patch(p_position: Vector2, duration: float, slow: float) -> void:
	var patch: ResinPatch = RESIN_PATCH_SCENE.instantiate() as ResinPatch
	patch.global_position = p_position
	patch.duration = duration
	patch.slow_multiplier = slow
	entities.add_child(patch, true)


func place_inventory_item(player: GamePlayer, item_id: String, slot_index: int, aim_direction: Vector2) -> void:
	if (not NetworkManager.is_single and not NetworkManager.is_host) or player == null:
		return
	if player._dead or player.hp <= 0.0 or match_finished:
		return
	var slot: Dictionary = player.inventory.get_slot(slot_index)
	if str(slot.get("id", "")) != item_id or int(slot.get("amount", 0)) <= 0:
		return
	var item_data: Dictionary = ItemDB.get_item(item_id)
	var placed_scene_path: String = str(item_data.get("placed_scene", ""))
	if placed_scene_path.is_empty() or not ResourceLoader.exists(placed_scene_path):
		push_warning("У устанавливаемого предмета '%s' нет доступной сцены" % item_id)
		return
	var placed_scene: PackedScene = load(placed_scene_path) as PackedScene
	if placed_scene == null or not placed_scene.can_instantiate():
		return
	if not aim_direction.is_finite() or aim_direction.length_squared() <= 0.001:
		return
	var place_range: float = clampf(float(item_data.get("place_range", 82.0)), 32.0, 128.0)
	var placement: Vector2 = _throw_landing_position(player, aim_direction.normalized(), place_range)
	var placed_prefix: String = "SentryTower" if item_id == "sentry_tower" else item_id.capitalize()
	var tower_id: String = "%s_%d" % [placed_prefix, _next_placed_item_id]
	_next_placed_item_id += 1
	if not player.inventory.remove_item(item_id, 1):
		return
	_spawn_placed_item(item_id, tower_id, placement, player.get_multiplayer_authority())
	if NetworkManager.is_host:
		sync_placed_item.rpc(item_id, tower_id, placement, player.get_multiplayer_authority())


func _spawn_placed_item(item_id: String, placed_id: String, world_position: Vector2, owner_peer_id: int) -> void:
	if entities.has_node(NodePath(placed_id)):
		return
	var item_data: Dictionary = ItemDB.get_item(item_id)
	var scene_path: String = str(item_data.get("placed_scene", ""))
	if item_data.is_empty() or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null or not packed_scene.can_instantiate():
		return
	var placed_node: Node2D = packed_scene.instantiate() as Node2D
	if placed_node == null:
		return
	placed_node.name = placed_id
	placed_node.set_multiplayer_authority(1, true)
	if placed_node is GameSentryTower:
		var tower: GameSentryTower = placed_node as GameSentryTower
		tower.owner_peer_id = owner_peer_id
		tower.attack_radius = float(item_data.get("attack_radius", tower.attack_radius))
		tower.attack_damage = float(item_data.get("attack_damage", tower.attack_damage))
		tower.fire_interval = float(item_data.get("fire_interval", tower.fire_interval))
		tower.lifetime = float(item_data.get("lifetime", tower.lifetime))
	entities.add_child(placed_node, true)
	placed_node.global_position = world_position


@rpc("authority", "call_remote", "reliable")
func sync_placed_item(item_id: String, placed_id: String, world_position: Vector2, owner_peer_id: int) -> void:
	if not NetworkManager.is_client:
		return
	_spawn_placed_item(item_id, placed_id, world_position, owner_peer_id)


@rpc("authority", "call_remote", "unreliable")
func sync_sentry_tower_aim(tower_id: String, aim_angle: float) -> void:
	if not NetworkManager.is_client or not is_finite(aim_angle):
		return
	var tower: Node2D = entities.get_node_or_null(NodePath(tower_id)) as Node2D
	if tower != null:
		tower.rotation = aim_angle


@rpc("authority", "call_remote", "reliable")
func sync_sentry_tower_removed(tower_id: String) -> void:
	if not NetworkManager.is_client:
		return
	var tower: Node = entities.get_node_or_null(NodePath(tower_id))
	if tower != null:
		tower.queue_free()


@rpc("authority", "call_remote", "reliable")
func sync_resin_patch(p_position: Vector2, duration: float, slow: float) -> void:
	_spawn_resin_patch(p_position, duration, slow)


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
		entities.call_deferred("add_child", pickup, true)
		return pickup
	# Выброшенные при смерти предметы приходят клиентам отдельным RPC,
	# поэтому не пропускаем их через MultiplayerSpawner второй раз.
	if throw_velocity.length_squared() > 0.0:
		var dropped_pickup: GamePickup = _spawn_pickup(data) as GamePickup
		entities.call_deferred("add_child", dropped_pickup, true)
		return dropped_pickup
	# MultiplayerSpawner may be triggered from an Area2D callback (for example,
	# when a chest opens). Defer it so physics queries have finished first.
	pickup_spawner.call_deferred("spawn", data)
	return null


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
	if player.collect_item(pickup.item_id, pickup.amount):
		if not NetworkManager.is_single:
			confirm_pickup.rpc(pickup_id, player_id, player.inventory.make_snapshot(), player.coins)
		pickup.server_collected()


@rpc("authority", "call_remote", "reliable")
func confirm_pickup(pickup_id: String, player_id: int, snapshot: Array, coin_total: int) -> void:
	var player: GamePlayer = _find_player(player_id)
	if player != null and player_id == NetworkManager.get_local_player_id():
		player.inventory.apply_snapshot(snapshot, player.current_weapon_slot)
		player.coins = coin_total
	var pickup: GamePickup = _find_pickup(pickup_id)
	if pickup != null:
		pickup.play_collected()


@rpc("any_peer", "call_remote", "reliable")
func request_action(action: Dictionary) -> void:
	if NetworkManager.is_host:
		handle_network_action(multiplayer.get_remote_sender_id(), action)


func handle_network_action(player_id: int, action: Dictionary) -> void:
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return
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
				var requested_slot: int = int(action.get("slot", -1))
				var requested_item: Dictionary = item_player.inventory.get_slot(requested_slot)
				var requested_id: String = str(requested_item.get("id", ""))
				var item_data: Dictionary = ItemDB.get_item(requested_id)
				var raw_direction: Variant = action.get("direction", [])
				var aim_direction: Vector2 = item_player._get_aim_direction()
				var has_direction: bool = raw_direction is Array and (raw_direction as Array).size() == 2
				if has_direction:
					var direction_values: Array = raw_direction as Array
					if not (direction_values[0] is float or direction_values[0] is int) or not (direction_values[1] is float or direction_values[1] is int):
						return
					aim_direction = Vector2(float(direction_values[0]), float(direction_values[1]))
					if not aim_direction.is_finite() or aim_direction.length_squared() <= 0.001:
						return
				var directed_action: bool = str(item_data.get("use_action", "")) in ["throw", "place"] or str(item_data.get("type", "")) in ["throwable", "placeable"]
				if directed_action and not has_direction:
					return
				if requested_id == "noise_lure":
					throw_noise_lure(item_player, aim_direction.normalized(), requested_slot)
				elif requested_id == "tar_bomb":
					throw_resin_bomb(item_player, aim_direction.normalized(), requested_slot)
				else:
					item_player.use_item(requested_slot, aim_direction)
		"reload":
			var reload_player: GamePlayer = _find_player(player_id)
			if reload_player != null:
				var weapon_id: String = str(action.get("weapon_id", ""))
				var loaded: int = reload_player._reload_weapon(weapon_id)
				confirm_reload.rpc_id(player_id, weapon_id, loaded, reload_player.inventory.make_snapshot())
		"melee_attack":
			var attacker: GamePlayer = _find_player(player_id)
			if attacker == null or not attacker.visible or attacker.hp <= 0.0 or attacker._dead:
				return
			if not attacker.current_weapon.is_empty() and attacker._current_loaded_ammo() > 0:
				return
			var raw_direction: Variant = action.get("dir", [0.0, 0.0])
			if not raw_direction is Array or (raw_direction as Array).size() < 2:
				return
			var direction_values: Array = raw_direction as Array
			var direction: Vector2 = Vector2(
				float(direction_values[0]),
				float(direction_values[1])
			).normalized()
			if not direction.is_finite() or direction.length_squared() <= 0.001:
				return
			# The host performs the same 4-tile raycast as the local player, so
			# client-supplied target IDs or distances cannot bypass walls.
			var target: Node2D = attacker.get_melee_raycast_target(direction)
			var impact_position: Vector2 = target.global_position if target != null else attacker.global_position + direction * 68.0
			attacker.play_melee_effect(direction, impact_position)
			sync_melee_swing.rpc(player_id, direction, impact_position)
			if target == null or not target.has_method("take_damage"):
				return
			var damage: float = 15.0 if attacker.current_weapon.is_empty() else 10.0
			if target is GamePlayer:
				(target as GamePlayer).take_contact_damage(damage, attacker.global_position, 400.0)
			else:
				target.call("take_damage", damage, attacker.global_position, 400.0)


@rpc("authority", "call_remote", "reliable")
func confirm_reload(weapon_id: String, loaded: int, snapshot: Array) -> void:
	var player: GamePlayer = _find_player(NetworkManager.get_local_player_id())
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
