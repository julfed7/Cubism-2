extends Node

signal died
signal health_changed(new_value: float)

@export var max_health: float = 100.0
var current_health: float
var _dead := false

func _ready() -> void:
	current_health = max_health

func take_damage(amount: float) -> void:
	if _dead:
		return
	current_health = clampf(current_health - maxf(amount, 0.0), 0.0, max_health)
	health_changed.emit(current_health)
	if current_health <= 0.0:
		_dead = true
		died.emit()

func heal(amount: float) -> void:
	if _dead:
		return
	current_health = clampf(current_health + maxf(amount, 0.0), 0.0, max_health)
	health_changed.emit(current_health)


func set_network_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	_dead = current_health <= 0.0
	health_changed.emit(current_health)
