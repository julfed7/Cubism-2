extends SceneTree
# godot --headless --path . --script res://tests/inventory_action_regression_test.gd

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


func _child(parent: Node, child: Node, child_name: String) -> Node:
	child.name = child_name
	parent.add_child(child)
	return child


func _slot_with_item(player: GamePlayer, item_id: String) -> int:
	for index: int in range(player.inventory.max_slots):
		if str(player.inventory.get_slot(index).get("id", "")) == item_id:
			return index
	return -1


func _run() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	var game: Arena = Arena.new()
	var map_container: Node = _child(game, Node2D.new(), "MapContainer")
	var navigation: Node = _child(map_container, NavigationRegion2D.new(), "NavigationRegion2D")
	_child(navigation, Node2D.new(), "MapRoot")
	var entities: Node = _child(map_container, Node2D.new(), "Entities")
	for node_name: String in ["PlayerSpawner", "BulletSpawner", "PickupSpawner", "ChestSpawner"]:
		_child(game, MultiplayerSpawner.new(), node_name)
	_child(game, AudioStreamPlayer.new(), "MatchMusic")
	root.add_child(game)
	current_scene = game

	var player: GamePlayer = load("res://scenes/objects/Player.tscn").instantiate() as GamePlayer
	entities.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector2(100, 100)
	await physics_frame

	_check(player.inventory.add_item("tar_bomb", 1), "Could not add the resin bomb to inventory")
	var resin_slot: int = _slot_with_item(player, "tar_bomb")
	game.throw_resin_bomb(player, Vector2.RIGHT, resin_slot)
	_check(_slot_with_item(player, "tar_bomb") == -1, "Using a resin bomb did not consume it")
	var thrown_bomb_visible: bool = false
	for entity: Node in entities.get_children():
		if entity is GameThrownItemVisual:
			thrown_bomb_visible = true
	_check(thrown_bomb_visible, "Throwing a resin bomb did not show its animated sprite")
	await create_timer(0.55).timeout
	_check(get_nodes_in_group("resin_patch").size() == 1, "Using a resin bomb did not create a resin patch")

	_check(player.inventory.add_item("sentry_tower", 1), "Could not add the sentry tower to inventory")
	var tower_slot: int = _slot_with_item(player, "sentry_tower")
	player.select_inventory_slot(tower_slot)
	var action: Dictionary = player.get_selected_action_info()
	_check(str(action.get("action", "")) == "use" and str(action.get("icon", "")) == "place", "Tower is not exposed as a place action")
	_check(entities.get_node_or_null("SentryTower_1") == null, "Selecting the tower slot used it immediately")
	_check(int(player.inventory.get_slot(tower_slot).get("amount", 0)) == 1, "Selecting the tower slot consumed it")
	game.place_inventory_item(player, "sentry_tower", tower_slot, Vector2.RIGHT)
	var tower: GameSentryTower = entities.get_node_or_null("SentryTower_1") as GameSentryTower
	_check(tower != null, "Using the tower did not place it in the world")
	_check(_slot_with_item(player, "sentry_tower") == -1, "Placing the tower did not consume it")

	player.play_melee_effect(Vector2.RIGHT, player.global_position + Vector2(70, 0))
	_check(player.melee_sprite.visible and player.melee_sprite.sprite_frames != null, "Melee effect is not using its animated sprite")
	_check(player.melee_sprite.sprite_frames.get_frame_count("slash") == 6, "Melee slash does not contain all six animation frames")
	_check(player.current_weapon.get("id", "") == "pistol" and player._current_loaded_ammo() > 0, "Starting pistol should have ammunition in its magazine")
	_check(not player.has_node("MeleeSwing"), "Procedural melee line was not removed")
	var hud: GameHUD = load("res://scenes/ui/HUD.tscn").instantiate() as GameHUD
	root.add_child(hud)
	await process_frame
	_check(not hud.virtual_joystick.visible and not hud.reload_button.visible and not hud.action_button.visible, "Touch controls should be hidden on desktop")

	await process_frame
	print("Inventory action regression failures: %d" % failures)
	quit(1 if failures > 0 else 0)
