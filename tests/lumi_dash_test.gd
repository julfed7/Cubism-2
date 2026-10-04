extends SceneTree
# Run after importing: godot --headless --path . --script res://tests/lumi_dash_test.gd

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
	player.brawler_id = "lumi"
	player.position = at
	arena.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.is_local = false
	return player


func _charge(player: GamePlayer) -> void:
	player.super_charge = 100.0
	player.super_ready = true


func _run() -> void:
	NetworkManager.is_single = true
	NetworkManager.is_host = false
	NetworkManager.is_client = false
	arena = Arena.new()
	root.add_child(arena)
	current_scene = arena
	var lumi: GamePlayer = _player(Vector2(100, 100))
	var first: GamePlayer = _player(Vector2(180, 100))
	var second: GamePlayer = _player(Vector2(320, 100))
	await physics_frame

	_charge(lumi)
	for invalid: Vector2 in [Vector2.ZERO, Vector2(INF, 0), Vector2(NAN, 1)]:
		lumi.activate_super(invalid)
		_check(not lumi.lumi_dash_active and lumi.super_charge == 100.0, "Invalid aim spent charge")
	lumi.brawler_id = "colt"
	lumi.activate_super(Vector2.RIGHT)
	_check(not lumi.lumi_dash_active and lumi.super_ready, "Another brawler activated Lumi's dash")
	lumi.brawler_id = "lumi"
	lumi.super_charge = 99.0
	lumi.activate_super(Vector2.RIGHT)
	_check(not lumi.lumi_dash_active, "Ready flag bypassed the required charge")
	_charge(lumi)
	lumi.activate_super(Vector2(20, 0))
	_check(lumi.lumi_dash_active and lumi.super_charge == 0.0 and not lumi.super_ready, "Activation failed")
	_check(lumi.collision_mask == 1 and lumi.collision_layer == 2, "Dash disabled world or projectile collision")
	var revision: int = lumi.lumi_dash_revision
	lumi.activate_super(Vector2.LEFT)
	_check(lumi.lumi_dash_revision == revision, "Repeated activation restarted dash")
	_check(not lumi.accepts_client_movement(revision), "Movement accepted during dash")
	_check(not lumi.take_contact_damage(10.0, Vector2(80, 100), 100.0), "Contact hurt dashing Lumi")
	_check(lumi.take_damage(5.0), "Dash blocked non-contact damage")
	# Run the actual physics entry point with a non-local player and large steps.
	lumi._physics_process(0.04)
	first._process_hurt(0.2) # Remove normal hit immunity to test per-dash deduplication.
	lumi._physics_process(0.04)
	lumi._physics_process(0.5)
	_check(lumi.global_position.is_equal_approx(Vector2(420, 100)), "Dash did not stop at its distance limit")
	_check(is_equal_approx(first.hp, 60.0) and is_equal_approx(second.hp, 60.0), "Sweep missed or hit a target twice")
	_check(lumi.super_charge == 0.0, "Super damage recharged the super")
	_check(not lumi.lumi_dash_active and lumi.collision_mask == 5, "Collision mask was not restored")
	_check(not lumi.accepts_client_movement(revision), "Pre-finish movement revision was accepted")
	_check(lumi.accepts_client_movement(lumi.lumi_dash_revision), "Post-finish movement remained locked")
	_check(lumi.take_contact_damage(1.0), "Contact immunity persisted after dash")

	# A local victim must receive exactly the configured forward impulse.
	first.is_local = true
	first._process_hurt(0.2)
	first.global_position = Vector2(180, 260)
	lumi.global_position = Vector2(100, 260)
	await physics_frame
	_charge(lumi)
	lumi.activate_super(Vector2.RIGHT)
	lumi._physics_process(0.3)
	_check(first.knockback_velocity.is_equal_approx(Vector2(500, 0)), "Wrong dash knockback")

	var wall: StaticBody2D = StaticBody2D.new()
	var wall_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(20, 160)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	wall.position = Vector2(240, 400)
	arena.add_child(wall)
	lumi.global_position = Vector2(100, 400)
	second.global_position = Vector2(300, 400)
	var before: float = second.hp
	await physics_frame
	_charge(lumi)
	lumi.activate_super(Vector2.RIGHT)
	lumi._physics_process(0.5)
	_check(lumi.global_position.x <= 210.1 and not lumi.lumi_dash_active, "Dash passed through a wall")
	_check(second.hp == before, "Dash damaged a victim behind a wall")

	_charge(lumi)
	lumi.activate_super(Vector2.LEFT)
	lumi._invuln_timer = 0.0
	lumi.take_damage(1000.0)
	_check(lumi._dead and not lumi.lumi_dash_active and lumi.collision_mask == 5, "Death did not cancel dash")
	lumi.restore_respawn_state()
	_check(not lumi.lumi_dash_active and lumi.super_charge == 0.0, "Respawn retained super state")

	# No peer is needed to test client guards or forged direct RPC calls.
	NetworkManager.is_single = false
	NetworkManager.is_client = true
	_charge(lumi)
	lumi.activate_super(Vector2.RIGHT)
	_check(not lumi.lumi_dash_active, "Client activated authoritative dash")
	before = lumi.hp
	_check(not lumi.take_damage(40.0) and lumi.hp == before, "Client assigned damage")
	lumi.super_charge = 0.0
	lumi.register_damage_dealt(200.0)
	_check(lumi.super_charge == 0.0, "Client assigned super charge")
	revision = lumi.lumi_dash_revision + 1
	lumi.apply_lumi_dash_snapshot(revision, true, Vector2(110, 100))
	lumi.apply_lumi_dash_snapshot(revision + 1, false, Vector2(420, 100))
	lumi.apply_lumi_dash_snapshot(revision, true, Vector2(200, 100))
	lumi.sync_lumi_dash(revision + 2, true, Vector2(900, 100))
	_check(not lumi.lumi_dash_active and lumi.global_position == Vector2(420, 100), "Stale or forged result overwrote dash finish")
	_check(lumi.collision_mask == 5, "Client did not restore collision mask")
	NetworkManager.is_single = true
	NetworkManager.is_client = false
	print("Lumi dash regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
