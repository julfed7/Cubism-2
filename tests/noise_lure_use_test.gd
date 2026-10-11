extends SceneTree
# godot --headless --path . --script res://tests/noise_lure_use_test.gd

class Arena extends "res://scripts/game.gd":
	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

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


func _slot(player: GamePlayer) -> int:
	for i: int in range(player.inventory.max_slots):
		if str(player.inventory.get_slot(i).get("id", "")) == "noise_lure":
			return i
	return -1


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	var arena: Arena = Arena.new()
	var container: Node = _child(arena, Node2D.new(), "MapContainer")
	var navigation: Node = _child(container, NavigationRegion2D.new(), "NavigationRegion2D")
	_child(navigation, Node2D.new(), "MapRoot")
	var entities := _child(container, Node2D.new(), "Entities") as Node2D
	entities.position = Vector2(40, 30)
	for spawner_name: String in ["PlayerSpawner", "BulletSpawner", "PickupSpawner", "ChestSpawner", "CrystalSpawner"]:
		_child(arena, MultiplayerSpawner.new(), spawner_name)
	_child(arena, AudioStreamPlayer.new(), "MatchMusic")
	root.add_child(arena)
	current_scene = arena
	var player: GamePlayer = load("res://scenes/objects/Player.tscn").instantiate() as GamePlayer
	player.peer_id = "1"
	entities.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2(400, 300)
	player.inventory.add_item("noise_lure", 3)
	var slot: int = _slot(player)
	await physics_frame

	for mode: String in ["classic", "battle_royale"]:
		NetworkManager.game_mode = mode
		arena.handle_network_action(1, {"type": "use_item", "slot": slot, "direction": [-2.0, 0.0]})
	var first := entities.get_node_or_null("NoiseLure_1") as NoiseLure
	var second := entities.get_node_or_null("NoiseLure_2") as NoiseLure
	_check(first != null and second != null, "Both modes must spawn lures")
	if first != null:
		_check(first.global_position.is_equal_approx(Vector2(140, 300)), "Throw ignored player position, direction or parent transform")
		var data: Dictionary = ItemDB.get_item("noise_lure")
		_check(is_equal_approx(first.duration, float(data["duration"])) and is_equal_approx(first.attraction_radius, float(data["attraction_radius"])), "Spawn ignored catalogue parameters")
	_check(int(player.inventory.get_slot(slot).get("amount", 0)) == 1, "Each throw must consume exactly one item")
	for aim: Variant in [[NAN, 0.0], [INF, 0.0], ["bad", 0.0], [0.0], {}]:
		arena.handle_network_action(1, {"type": "use_item", "slot": slot, "direction": aim})
	player._dead = true
	arena.throw_noise_lure(player, Vector2.RIGHT, slot)
	player._dead = false
	arena.match_finished = true
	arena.throw_noise_lure(player, Vector2.RIGHT, slot)
	arena.match_finished = false
	arena.throw_noise_lure(player, Vector2.RIGHT, -1)
	_check(int(player.inventory.get_slot(slot).get("amount", 0)) == 1, "Invalid requests consumed the lure")

	# Inventory delegates to the player and consumes the last item only once.
	player.inventory.use_item(slot)
	_check(player.inventory.get_slot(slot).is_empty() and entities.has_node("NoiseLure_3"), "Inventory use did not consume and spawn")
	arena.throw_noise_lure(player, Vector2.RIGHT, slot)
	_check(not entities.has_node("NoiseLure_4"), "Empty inventory spawned a lure")

	# Walls stop both throwable types at the same point.
	player.global_position = Vector2(100, 100)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(240, 100)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20, 200)
	collision.shape = shape
	wall.add_child(collision)
	arena.add_child(wall)
	await physics_frame
	await physics_frame
	var landing: Vector2 = arena._throw_landing_position(player, Vector2.RIGHT, 260.0)
	_check(landing.is_equal_approx(Vector2(218, 100)), "Throw passed through the wall")
	_check(arena._throw_landing_position(player, Vector2.ZERO, 260.0).is_equal_approx(landing), "Zero aim did not use fallback direction")
	player.inventory.add_item("noise_lure", 1)
	slot = _slot(player)
	arena.throw_noise_lure(player, Vector2.RIGHT, slot)
	var blocked := entities.get_node_or_null("NoiseLure_4") as NoiseLure
	_check(blocked != null and blocked.global_position.is_equal_approx(landing), "Lure ignored obstacle clipping")

	# Clients only reproduce the authoritative spawn, never spend inventory.
	player.inventory.add_item("noise_lure", 1)
	slot = _slot(player)
	NetworkManager.set_mode(NetworkManager.Mode.CLIENT)
	arena.throw_noise_lure(player, Vector2.RIGHT, slot)
	_check(int(player.inventory.get_slot(slot).get("amount", 0)) == 1 and not entities.has_node("NoiseLure_5"), "Client made an authoritative throw")
	arena.sync_noise_lure(Vector2(500, 500), 2.5, 123.0, "NoiseLure_99")
	arena.sync_noise_lure(Vector2.ZERO, 7.0, 360.0, "NoiseLure_99")
	var replicated := entities.get_node_or_null("NoiseLure_99") as NoiseLure
	_check(replicated != null and replicated.global_position == Vector2(500, 500), "RPC spawn or duplicate protection failed")
	if replicated != null:
		_check(replicated.duration == 2.5 and replicated.attraction_radius == 123.0, "RPC lost lifetime or radius")
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	print("Noise lure use regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
