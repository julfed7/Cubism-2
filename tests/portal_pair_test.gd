extends SceneTree
# godot --headless --path . --script res://tests/portal_pair_test.gd

class Arena extends Node2D:
	func can_respawn(_player_id: int) -> bool:
		return false

var failures: int = 0
var arena: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _player(at: Vector2) -> GamePlayer:
	var player: GamePlayer = load("res://scenes/objects/Player.tscn").instantiate() as GamePlayer
	player.position = at
	arena.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	return player


func _pair() -> PortalPair:
	var pair: PortalPair = load("res://scripts/portal_pair.gd").new() as PortalPair
	pair.position = Vector2(50.0, 50.0)
	pair.initial_delay = 2.0
	pair.open_duration = 3.0
	pair.closed_duration = 4.0
	arena.add_child(pair)
	pair.set_physics_process(false)
	return pair


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	arena = Arena.new()
	root.add_child(arena)
	current_scene = arena
	var pair: PortalPair = _pair()
	_check(not pair.is_open, "Pair started before initial delay")
	pair._physics_process(1.0)
	_check(not pair.is_open, "Pair opened early")
	pair._physics_process(1.0)
	_check(pair.is_open, "Pair failed to open at boundary")
	pair._physics_process(3.0)
	_check(not pair.is_open, "Pair failed to close at boundary")
	pair._physics_process(4.0)
	_check(pair.is_open, "Pair failed to reopen")
	pair._physics_process(700.0)
	_check(pair.is_open, "Long frame lost cycle phase")
	var a: Vector2 = Vector2(120.0, 100.0)
	var b: Vector2 = Vector2(520.0, 100.0)
	_check(pair.set_endpoints(a, b), "World-space endpoint configuration failed")
	_check(pair.to_global(pair.point_a).is_equal_approx(a), "Parent transform corrupted endpoint")
	_check(not pair.set_endpoints(a, a), "Overlapping endpoints accepted")
	_check(not pair.set_endpoints(Vector2(NAN, 0.0), b), "Nonfinite endpoints accepted")

	var player: GamePlayer = _player(a + Vector2(pair.entry_radius, 0.0))
	player.velocity = Vector2(100.0, 0.0)
	player.knockback_velocity = Vector2(50.0, 0.0)
	_check(pair.try_teleport(player), "Radius boundary did not teleport")
	_check(player.global_position.is_equal_approx(b), "Player missed paired endpoint")
	_check(player.velocity == Vector2.ZERO and player.knockback_velocity == Vector2.ZERO,
		"Teleport retained movement impulse")
	_check(player.trajectory_pos == b, "Teleport retained old interpolation target")
	_check(not pair.try_teleport(player), "Player bounced back before exiting")
	_check(pair.get_child_count() == 1, "Transfer effect was not created")
	pair._physics_process(3.0)
	_check(not pair.is_open and not pair.try_teleport(player), "Closed pair teleported")
	pair._physics_process(4.0)
	_check(player.global_position == b and not pair.try_teleport(player),
		"Reopening cleared the exit lock")
	player.global_position = b + Vector2(pair.entry_radius + 1.0, 0.0)
	pair._physics_process(0.0)
	player.global_position = b
	_check(pair.try_teleport(player) and player.global_position == a,
		"Exit and re-entry did not allow reverse transfer")

	var dead: GamePlayer = _player(a)
	dead._dead = true
	_check(not pair.try_teleport(dead), "Dead player teleported")
	dead._dead = false
	dead.hp = 0.0
	_check(not pair.try_teleport(dead), "Zero-health player teleported")
	var outside: GamePlayer = _player(a + Vector2(pair.entry_radius + 1.0, 0.0))
	_check(not pair.try_teleport(outside), "Out-of-radius player teleported")
	outside.global_position = a
	NetworkManager.set_mode(NetworkManager.Mode.HOST)
	_check(pair.try_teleport(outside), "Host could not teleport a player")
	var scanned: GamePlayer = _player(b)
	pair._physics_process(0.0)
	_check(scanned.global_position == a, "Automatic entry scan failed")
	_check(pair._sound.data.size() == 7938, "Short transfer sound was not generated")
	var state: Dictionary = pair.get_open_state()

	NetworkManager.set_mode(NetworkManager.Mode.CLIENT)
	var client: PortalPair = _pair()
	_check(client.apply_open_state(state) and client.is_open, "Client rejected server visual state")
	var before: Vector2 = dead.global_position
	dead.hp = 100.0
	_check(not client.try_teleport(dead), "Client performed authoritative teleport")
	client._physics_process(1000.0)
	_check(dead.global_position == before and client.is_open, "Client advanced gameplay")
	_check(not client.set_endpoints(a, b), "Client changed authoritative endpoints")
	var stale: Dictionary = state.duplicate()
	stale["revision"] = int(state["revision"]) - 1
	stale["open"] = false
	_check(not client.apply_open_state(stale) and client.is_open, "Stale state overwrote client")
	var invalid: Dictionary = state.duplicate()
	invalid["remaining"] = NAN
	_check(not client.apply_open_state(invalid), "Nonfinite state accepted")
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	_check(not pair.apply_open_state(state), "Server accepted external state")
	pair.entry_radius = NAN
	pair._physics_process(0.0)
	_check(not pair.is_open and not pair.try_teleport(dead), "Invalid configuration stayed active")
	await create_timer(0.6).timeout
	_check(pair.get_child_count() == 0, "Transfer effects/audio did not clean up")
	pair.free()
	print("Portal pair regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
