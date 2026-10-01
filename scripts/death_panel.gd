extends Control

@onready var countdown_label: Label = $VBox/CountdownLabel

var _timer: float = 0.0
var _active: bool = false
var _respawn_time: float = 5.0

signal respawn_requested


func show_death(seconds: float = 5.0) -> void:
	_respawn_time = seconds
	_timer = _respawn_time
	_active = true
	visible = true
	countdown_label.text = "Возрождение через: " + str(int(_timer))


func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_active = false
		visible = false
		respawn_requested.emit()
	else:
		countdown_label.text = "Возрождение через: " + str(int(ceil(_timer)))
