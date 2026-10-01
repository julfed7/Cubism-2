extends Area2D
class_name GamePickup

@export var item_id: String = "medkit"
@export var amount: int = 1
@export var pickup_id: String = ""

@onready var sprite: Sprite2D = $Sprite2D
@onready var pickup_audio: AudioStreamPlayer2D = $PickupAudio
@onready var legacy_animation: AnimatedSprite2D = $AnimatedSprite2D

var _collected: bool = false
var _request_pending: bool = false
var velocity: Vector2 = Vector2.ZERO
# Новый выброшенный предмет стартует в режиме полёта; обычный предмет с
# нулевой скоростью освобождает мониторинг на первом физическом кадре.
var flying: bool = true
var throw_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if pickup_id.is_empty():
		pickup_id = str(name)
	body_entered.connect(_on_body_entered)
	legacy_animation.visible = false
	apply_item_visual()
	if throw_velocity.length_squared() > 0.0:
		start_flight(throw_velocity)
	elif flying:
		set_deferred("monitoring", false)
		$CollisionShape2D.set_deferred("disabled", true)


func _physics_process(delta: float) -> void:
	if not flying:
		return
	global_position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	throw_velocity = velocity
	if velocity.length() < 10.0:
		velocity = Vector2.ZERO
		throw_velocity = Vector2.ZERO
		flying = false
		set_deferred("monitoring", true)
		$CollisionShape2D.set_deferred("disabled", false)


func start_flight(initial_velocity: Vector2) -> void:
	velocity = initial_velocity
	throw_velocity = initial_velocity
	flying = velocity.length_squared() > 0.0
	if flying:
		set_deferred("monitoring", false)
		$CollisionShape2D.set_deferred("disabled", true)


func apply_item_visual() -> void:
	var data: Dictionary = ItemDB.get_item(item_id)
	var sprite_path: String = str(data.get("sprite", ""))
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path) as Texture2D


func _on_body_entered(body: Node2D) -> void:
	if flying or _collected or _request_pending or not body.is_in_group("player") or not body is GamePlayer:
		return
	var player: GamePlayer = body as GamePlayer
	if not player.is_local:
		return
	if NetworkManager.is_single:
		if player.inventory.add_item(item_id, amount):
			play_collected()
		return
	if NetworkManager.is_host:
		var game: Node = get_tree().current_scene
		if game != null and game.has_method("collect_pickup_authoritative"):
			game.collect_pickup_authoritative(pickup_id, player.get_multiplayer_authority())
		return
	_request_pending = true
	NetworkManager.request_pickup(pickup_id)
	await get_tree().create_timer(0.75).timeout
	_request_pending = false


func server_collected() -> void:
	play_collected()


func play_collected() -> void:
	if _collected:
		return
	_collected = true
	flying = false
	velocity = Vector2.ZERO
	set_deferred("monitoring", false)
	$CollisionShape2D.set_deferred("disabled", true)
	sprite.visible = false
	UISoundManager.play_ui_sound("pickup.wav")
	queue_free()
