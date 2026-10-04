extends Area2D
class_name GameChest

@export var pickup_scene: PackedScene = preload("res://scenes/objects/Pickup.tscn")
@export var chest_id: String = ""

var opened: bool = false
var _open_requested: bool = false

const LOOT_TABLE: Array[Dictionary] = [
	{"id": "pistol", "weight": 20},
	{"id": "smg", "weight": 15},
	{"id": "shotgun", "weight": 10},
	{"id": "rifle", "weight": 5},
	{"id": "medkit", "weight": 25},
	{"id": "tar_bomb", "weight": 12},
	{"id": "ammo_pistol", "weight": 20},
	{"id": "ammo_smg", "weight": 15},
	{"id": "ammo_shotgun", "weight": 10},
]

const WEAPON_IDS: Array[String] = ["pistol", "smg", "shotgun", "rifle"]
const CONSUMABLE_IDS: Array[String] = ["medkit", "tar_bomb", "ammo_pistol", "ammo_smg", "ammo_shotgun"]


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if opened or _open_requested or not body is GamePlayer:
		return
	if NetworkManager.is_single or NetworkManager.is_host:
		_open()
	elif NetworkManager.is_client:
		_open_requested = true
		NetworkManager.request_open_chest(chest_id)


func _open() -> void:
	if opened:
		return
	opened = true
	if NetworkManager.is_host:
		var game: Node = get_tree().current_scene
		if game != null and game.has_method("notify_chest_opened"):
			game.notify_chest_opened(chest_id)
	_spawn_loot()
	play_open_animation()


func _spawn_loot() -> void:
	var game := get_tree().current_scene
	if game == null or not game.has_method("spawn_pickup"):
		return
	var count := randi_range(2, 4)
	var loot: Array[String] = []
	# Every chest contains at least one weapon and one consumable.
	loot.append(WEAPON_IDS[randi_range(0, WEAPON_IDS.size() - 1)])
	var consumable_count := randi_range(1, mini(2, count - 1))
	for _index in consumable_count:
		loot.append(CONSUMABLE_IDS[randi_range(0, CONSUMABLE_IDS.size() - 1)])
	while loot.size() < count:
		loot.append(_pick_random_loot())
	loot.shuffle()
	for index in loot.size():
		var item_id := loot[index]
		var amount := 1 if item_id in WEAPON_IDS else randi_range(1, 3)
		var angle := TAU * float(index) / float(count) + randf_range(-0.25, 0.25)
		var offset := Vector2.from_angle(angle) * randf_range(28.0, 58.0)
		game.spawn_pickup(item_id, amount, global_position + offset)


func _pick_random_loot() -> String:
	var total := 0
	for item: Dictionary in LOOT_TABLE:
		total += int(item.get("weight", 0))
	if total <= 0:
		return LOOT_TABLE[0].id
	var roll := randi() % total
	var acc := 0
	for item: Dictionary in LOOT_TABLE:
		acc += int(item.get("weight", 0))
		if roll < acc:
			return str(item.get("id", LOOT_TABLE[0].id))
	return str(LOOT_TABLE[0].id)


func play_open_animation() -> void:
	play_open()
	await $AnimatedSprite2D.animation_finished
	if is_instance_valid(self):
		queue_free()


func play_open() -> void:
	UISoundManager.play_ui_sound("chest_open.wav")
	$AnimatedSprite2D.play("opening")

func server_opened() -> void:
	if not opened:
		opened = true
		_open_requested = false
		play_open_animation()
