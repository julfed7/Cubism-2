extends SceneTree
# godot --headless --path . --script res://tests/noise_lure_test.gd

var failures: int = 0
var arena: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _zombie(at: Vector2) -> GameZombie:
	var zombie: GameZombie = load("res://scenes/objects/Zombie.tscn").instantiate() as GameZombie
	zombie.position = at
	arena.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.set_process(false)
	return zombie


func _lure(at: Vector2 = Vector2.ZERO) -> NoiseLure:
	var lure: NoiseLure = load("res://scenes/objects/NoiseLure.tscn").instantiate() as NoiseLure
	lure.position = at
	arena.add_child(lure)
	lure.set_physics_process(false)
	return lure


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var inner: GameZombie = _zombie(Vector2.ZERO)
	var edge: GameZombie = _zombie(Vector2(360, 0))
	var outside: GameZombie = _zombie(Vector2(361, 0))
	var dead_zombie: GameZombie = _zombie(Vector2(10, 0))
	dead_zombie.dead = true
	var no_health: GameZombie = _zombie(Vector2(20, 0))
	no_health.hp = 0.0
	var lure: NoiseLure = _lure()
	_check(inner._find_noise_lure() == lure, "Inner zombie did not hear lure")
	_check(edge._find_noise_lure() == lure, "Boundary zombie did not hear lure")
	_check(outside._find_noise_lure() == null, "Lure exceeded radius")
	_check(dead_zombie._noise_lures.is_empty() and no_health._noise_lures.is_empty(), "Dead zombie heard lure")
	outside.global_position = Vector2(100, 0)
	lure._emit_noise()
	_check(outside._find_noise_lure() == lure, "New arrival did not hear active lure")
	edge.global_position = Vector2(500, 0)
	_check(edge._find_noise_lure() == null, "Zombie retained lure outside radius")
	var second: NoiseLure = _lure(Vector2(90, 0))
	_check(outside._find_noise_lure() == second, "Nearest overlapping lure was not selected")
	second.free()
	_check(outside._find_noise_lure() == lure, "Removing one lure cancelled another")

	# A player in contact range must lose priority to the lure.
	var player: GamePlayer = load("res://scenes/objects/Player.tscn").instantiate() as GamePlayer
	player.position = Vector2(20, 0)
	arena.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.is_hidden = false
	inner._process_authoritative_ai()
	_check(not inner.is_attacking and inner.navigation_agent.target_desired_distance == 12.0, "Zombie attacked player instead of gathering at lure")
	lure._physics_process(7.0)
	_check(not lure.is_active() and inner._find_noise_lure() == null, "Expired lure retained priority")
	inner._process_authoritative_ai()
	_check(inner.is_attacking, "Zombie did not return to player targeting after expiration")
	await process_frame
	_check(not is_instance_valid(lure), "Expired lure was not freed")

	NetworkManager.set_mode(NetworkManager.Mode.HOST)
	var host_lure: NoiseLure = _lure()
	_check(inner._find_noise_lure() == host_lure, "Host did not assign lure")
	host_lure.free()
	NetworkManager.set_mode(NetworkManager.Mode.CLIENT)
	var client_lure: NoiseLure = _lure()
	inner.hear_noise_lure(client_lure)
	_check(inner._noise_lures.is_empty() and inner._find_noise_lure() == null, "Client assigned authoritative lure")
	client_lure.free()
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	var invalid: NoiseLure = load("res://scenes/objects/NoiseLure.tscn").instantiate() as NoiseLure
	invalid.duration = NAN
	arena.add_child(invalid)
	_check(not invalid.is_active(), "Invalid duration activated lure")
	await process_frame
	print("Noise lure regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
