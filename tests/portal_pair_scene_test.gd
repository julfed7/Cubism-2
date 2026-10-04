extends SceneTree
# godot --headless --path . --script res://tests/portal_pair_scene_test.gd

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	var scene: PackedScene = load("res://scenes/objects/PortalPair.tscn")
	var pair: PortalPair = scene.instantiate() as PortalPair
	pair.position = Vector2(100.0, 80.0)
	root.add_child(pair)
	pair.set_physics_process(false)
	var a: Area2D = pair.get_node("PortalA") as Area2D
	var b: Area2D = pair.get_node("PortalB") as Area2D
	var shape_a: CollisionShape2D = a.get_node("EntryShape") as CollisionShape2D
	var shape_b: CollisionShape2D = b.get_node("EntryShape") as CollisionShape2D
	await process_frame
	_check(not bool(a.get("_open")) and not bool(b.get("_open")), "Initial closed visuals missing")
	_check(shape_a.disabled and shape_b.disabled, "Closed entrances enabled")
	_check(a.get("endpoint_index") != b.get("endpoint_index"), "Endpoints share the same visual identity")
	_check(pair.set_endpoints(Vector2(230.0, 210.0), Vector2(650.0, 410.0)),
		"Scene rejected match coordinates")
	pair.entry_radius = 46.0
	pair._physics_process(pair.initial_delay)
	a.call("_process", 0.0)
	b.call("_process", 0.0)
	await process_frame
	_check(a.global_position.is_equal_approx(Vector2(230.0, 210.0)), "A missed world position")
	_check(b.global_position.is_equal_approx(Vector2(650.0, 410.0)), "B missed world position")
	_check(bool(a.get("_open")) and bool(b.get("_open")) and a.monitoring and b.monitoring, "Open entrances inactive")
	_check(not shape_a.disabled and not shape_b.disabled, "Open shapes disabled")
	_check(is_equal_approx((shape_a.shape as CircleShape2D).radius, 46.0), "Entry radius not synchronized")
	var other: PortalPair = scene.instantiate() as PortalPair
	root.add_child(other)
	other.set_physics_process(false)
	_check(is_equal_approx((other.get_node("PortalA/EntryShape") as CollisionShape2D).shape.get("radius"), 38.0),
		"Radius leaked into another scene instance")
	pair._physics_process(pair.open_duration)
	a.call("_process", 0.0)
	b.call("_process", 0.0)
	await process_frame
	_check(not bool(a.get("_open")) and shape_a.disabled and not a.monitoring, "Closing did not seal A")
	_check(not bool(b.get("_open")) and shape_b.disabled and not b.monitoring, "Closing did not seal B")
	NetworkManager.set_mode(NetworkManager.Mode.CLIENT)
	_check(pair.apply_open_state({
		"open": true, "remaining": 3.0, "revision": 100,
		"point_a": Vector2(300.0, 200.0), "point_b": Vector2(700.0, 500.0),
	}), "Scene rejected trusted visual snapshot")
	a.call("_process", 0.0)
	b.call("_process", 0.0)
	await process_frame
	_check(bool(a.get("_open")) and bool(b.get("_open")), "Snapshot did not open visuals")
	_check(b.global_position.is_equal_approx(Vector2(700.0, 500.0)),
		"Snapshot did not reposition endpoint")
	pair.free()
	other.free()
	print("Portal pair scene failures: %d" % failures)
	quit(1 if failures > 0 else 0)
