extends SceneTree
# godot --headless --path . --script res://tests/pulse_beacon_test.gd

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


func _player(id: int, at: Vector2, hidden: bool = true) -> GamePlayer:
	var player: GamePlayer = load("res://scenes/objects/Player.tscn").instantiate() as GamePlayer
	player.set_multiplayer_authority(id)
	player.position = at
	arena.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.is_local = id == 1
	player._set_hidden_state(hidden)
	return player


func _beacon(duration: float = 4.0) -> PulseBeacon:
	var beacon: PulseBeacon = load("res://scenes/objects/PulseBeacon.tscn").instantiate() as PulseBeacon
	beacon.detection_duration = duration
	arena.add_child(beacon)
	return beacon


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	arena = Arena.new()
	root.add_child(arena)
	current_scene = arena
	var owner: GamePlayer = _player(1, Vector2(100, 100))
	var target: GamePlayer = _player(2, Vector2(200, 100))
	var edge: GamePlayer = _player(3, Vector2(380, 100))
	var outside: GamePlayer = _player(4, Vector2(381, 100))
	var exposed: GamePlayer = _player(5, Vector2(120, 100), false)
	var dead: GamePlayer = _player(6, Vector2(130, 100))
	dead._dead = true
	_check(not target.get_node("Sprite2D").visible, "Hidden opponent visible before pulse")
	var pulse: PulseBeacon = _beacon()
	_check(pulse.emit_pulse(owner), "Pulse did not activate")
	_check(not pulse.emit_pulse(owner), "Pulse activated twice")
	_check(target.is_pulse_detected_by(1) and edge.is_pulse_detected_by(1), "Radius missed inner or boundary target")
	_check(not outside.is_pulse_detected_by(1), "Pulse exceeded radius")
	_check(not exposed.is_pulse_detected_by(1) and not dead.is_pulse_detected_by(1), "Pulse marked exposed or dead fighter")
	_check(not owner.is_pulse_detected_by(1), "Pulse marked its owner")
	_check(not target.is_pulse_detected_by(3), "Detection leaked to another viewer")
	_check(target.is_hidden and target.visible and target.get_node("Sprite2D").visible, "Reveal changed replicated stealth or failed to show target")
	outside.global_position = Vector2(150, 100)
	_check(not outside.is_pulse_detected_by(1), "Pulse continuously scanned new arrivals")

	# Removing one source must not cancel another source's reveal.
	var second: PulseBeacon = _beacon()
	_check(second.emit_pulse(owner), "Second pulse failed")
	pulse.free()
	_check(target.is_pulse_detected_by(1), "Overlapping pulse expired prematurely")
	second.free()
	_check(not target.is_pulse_detected_by(1) and not target.get_node("Sprite2D").visible, "Early removal retained detection")

	# The host must not see a remote owner's detections.
	var remote: PulseBeacon = _beacon()
	_check(remote.emit_pulse(edge), "Remote owner's pulse failed")
	_check(target.is_pulse_detected_by(3) and not target.is_pulse_detected_by(1), "Remote detection shared with host")
	_check(not target.get_node("Sprite2D").visible, "Remote detection rendered on host")
	remote.free()

	var short_pulse: PulseBeacon = _beacon(0.05)
	short_pulse.emit_pulse(owner)
	await create_timer(0.12).timeout
	target._expire_pulse_detections()
	target._update_stealth_visual()
	_check(not is_instance_valid(short_pulse), "Expired beacon remained alive")
	_check(target._pulse_detections.is_empty() and not target.get_node("Sprite2D").visible, "Timer did not remove detections")

	var death_pulse: PulseBeacon = _beacon()
	death_pulse.emit_pulse(owner)
	target.take_damage(10000.0)
	target.restore_respawn_state()
	_check(not target.is_pulse_detected_by(1), "Detection survived death and respawn")
	death_pulse.free()

	# Client-side activation and calls without a server sender are rejected.
	NetworkManager.set_mode(NetworkManager.Mode.CLIENT)
	var forbidden: PulseBeacon = _beacon()
	_check(not forbidden.emit_pulse(owner), "Client emitted authoritative pulse")
	target.grant_pulse_detection(1, 123, 4.0)
	target.sync_pulse_detection(123, 4.0)
	_check(not target.is_pulse_detected_by(1), "Client or forged RPC assigned detection")
	forbidden.free()
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	var invalid: PulseBeacon = _beacon()
	invalid.detection_radius = NAN
	_check(not invalid.emit_pulse(owner), "Invalid radius accepted")
	invalid.free()
	print("Pulse beacon regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
