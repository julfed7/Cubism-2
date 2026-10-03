extends Area2D
class_name GameCrystal

@export var crystal_id: String = "crystal_0"
@onready var sprite: Sprite2D = $Sprite2D
var _captured: bool = false
var _request_pending: bool = false

func _ready() -> void:
    body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
    if _captured or _request_pending or not body.is_in_group("player") or not body is GamePlayer:
        return
    var player: GamePlayer = body as GamePlayer
    if not player.is_local:
        return
    var game: Node = get_tree().current_scene
    if game == null or not game.has_method("capture_crystal_authoritative"):
        return
    if NetworkManager.is_single or NetworkManager.is_host:
        game.capture_crystal_authoritative(crystal_id, player.get_multiplayer_authority())
        return
    _request_pending = true
    NetworkManager.send_action({"type": "capture_crystal", "entity_id": crystal_id})
    await get_tree().create_timer(0.75).timeout
    _request_pending = false

func play_captured() -> void:
    if _captured:
        return
    _captured = true
    monitoring = false
    $CollisionShape2D.set_deferred("disabled", true)
    sprite.visible = false
    UISoundManager.play_ui_sound("pickup.wav")
    queue_free()
