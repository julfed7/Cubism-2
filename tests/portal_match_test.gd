extends SceneTree
# godot --headless --path . --script res://tests/portal_match_test.gd

class Arena extends "res://scripts/game.gd":
	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func advance_portals(delta: float) -> void:
		super._physics_process(delta)

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _child(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	return node


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	GameState.current_level = 1
	var arena: Arena = Arena.new()
	var container: Node = _child(arena, Node2D.new(), "MapContainer")
	var navigation: Node = _child(container, NavigationRegion2D.new(), "NavigationRegion2D")
	_child(navigation, Node2D.new(), "MapRoot")
	_child(container, Node2D.new(), "Entities")
	for spawner_name: String in ["PlayerSpawner", "BulletSpawner", "PickupSpawner", "ChestSpawner", "CrystalSpawner"]:
		_child(arena, MultiplayerSpawner.new(), spawner_name)
	_child(arena, AudioStreamPlayer.new(), "MatchMusic")
	root.add_child(arena)
	current_scene = arena
	var pair: PortalPair = load("res://scenes/objects/PortalPair.tscn").instantiate() as PortalPair
	arena.map_root.add_child(pair)
	NetworkManager.game_mode = "classic"
	arena._configure_portals()
	var player: GamePlayer = load("res://scenes/objects/Player.tscn").instantiate() as GamePlayer
	player.peer_id = "1"
	arena.entities.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var a: Vector2 = pair.to_global(pair.point_a)
	var b: Vector2 = pair.to_global(pair.point_b)
	player.global_position = a
	arena.advance_portals(pair.initial_delay - 0.1)
	_check(not pair.is_open and player.global_position == a, "Match opened portals before schedule")
	arena.advance_portals(0.1)
	_check(pair.is_open and player.global_position == b, "Match failed to teleport at opening")
	_check(player.lumi_dash_revision == 1, "Transfer did not advance movement revision")
	_check(not player.accepts_client_movement(0) and player.accepts_client_movement(1), "Old movement can undo transfer")
	_check(player.network_position_q == Vector2i(NetworkManager.quantize(b.x), NetworkManager.quantize(b.y)), "Network position missed transfer")
	_check(arena.can_respawn(1), "Classic respawn changed")
	player._dead = true
	player.global_position = a
	_check(not pair.try_teleport(player), "Dead player used portal")
	player._dead = false
	NetworkManager.game_mode = "battle_royale"
	_check(not arena.can_respawn(1), "Royale allowed respawn")
	player.global_position = a + Vector2(100, 0)
	arena.advance_portals(0.0)
	player.global_position = a
	arena.advance_portals(0.0)
	_check(player.global_position == b and player.lumi_dash_revision == 2, "Royale transfer failed")

	arena.match_finished = true
	var stopped_elapsed: float = pair._elapsed
	arena.advance_portals(100.0)
	_check(pair._elapsed == stopped_elapsed, "Finished match advanced portals")
	arena.match_finished = false

	var pair_id: String = str(arena.map_root.get_path_to(pair))
	var server_states: Dictionary = arena._portal_states()
	NetworkManager.set_mode(NetworkManager.Mode.CLIENT)
	pair.is_open = false
	arena.sync_portal_states(server_states)
	_check(pair.is_open, "Client did not apply server portal state")
	var elapsed: float = pair._elapsed
	arena.advance_portals(100.0)
	_check(pair._elapsed == elapsed, "Client advanced portal schedule")
	player.global_position = a
	player.knockback_velocity = Vector2(10, 20)
	var effect_count: int = pair.get_child_count()
	arena.sync_portal_transfer(pair_id, 1, a, b, 3, false)
	_check(player.global_position == b and player.trajectory_pos == b and player.knockback_velocity == Vector2.ZERO, "Client transfer retained old movement")
	arena.sync_portal_transfer(pair_id, 1, a, b, 3, false)
	_check(pair.get_child_count() == effect_count + 1, "Reliable transfer played duplicate effects")
	arena._apply_snapshot({"players": {"1": {"x": a.x, "y": a.y, "dash_revision": 2}}})
	_check(player.global_position == b, "Stale snapshot undid transfer")
	# Simulate the snapshot arriving before its reliable effect.
	arena._apply_snapshot({"players": {"1": {"x": a.x, "y": a.y, "dash_revision": 4}}})
	player.global_position = a + Vector2(10, 0)
	arena.sync_portal_transfer(pair_id, 1, b, a, 4, false)
	_check(player.global_position == a + Vector2(10, 0), "Late effect rewound newer movement")

	# An event may precede its player's MultiplayerSpawner replication.
	player.peer_id = "2"
	arena.sync_portal_transfer(pair_id, 1, a, b, 5, false)
	_check(arena._pending_portal_transfers.has(1), "Transfer before spawn was lost")
	player.peer_id = "1"
	arena._apply_pending_portal_transfer(player)
	_check(player.global_position == b and player.lumi_dash_revision == 5, "Pending transfer was not applied")
	_check(arena._pending_portal_transfers.is_empty(), "Pending transfer was not cleared")

	NetworkManager.clear_snapshots()
	NetworkManager.push_snapshot({"players": {"1": {"x": a.x, "y": a.y, "dash_revision": 3}}})
	NetworkManager.push_snapshot({"players": {"1": {"x": b.x, "y": b.y, "dash_revision": 4}}})
	_check(NetworkManager.get_trajectory_for("1", false)["vel"] == Vector2.ZERO, "Trajectory extrapolated across portal gap")
	NetworkManager.push_snapshot({"players": {"1": {"x": b.x + 5, "y": b.y, "dash_revision": 4}}})
	_check(NetworkManager.get_trajectory_for("1", false)["vel"] == Vector2(5, 0), "Normal movement lost interpolation")

	NetworkManager.game_mode = "crystal_capture"
	player.global_position = b
	arena.sync_portal_transfer(pair_id, 1, b, a, 6, false)
	_check(player.global_position == b, "Crystal mode accepted transfer RPC")
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	arena._configure_portals()
	arena.advance_portals(100.0)
	_check(arena._portal_pairs.is_empty() and not pair.is_open and not pair.visible, "Crystal mode retained portals")
	_check(arena.can_respawn(1), "Crystal respawn changed")
	NetworkManager.clear_snapshots()
	print("Portal match regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
