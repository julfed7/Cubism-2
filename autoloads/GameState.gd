extends Node

var nickname: String = ""
var current_level: int = 0
var session_id: int = 0

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		nickname = str(config.get_value("player", "nickname", "")).strip_edges()
	if nickname.is_empty():
		nickname = "Player"


func set_nickname(value: String) -> void:
	nickname = value.strip_edges()
	if nickname.is_empty():
		nickname = "Player"
	var config := ConfigFile.new()
	config.set_value("player", "nickname", nickname)
	config.save(SETTINGS_PATH)
