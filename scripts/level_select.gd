extends Control

func _on_level_1_pressed() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	GameState.current_mode = "classic"
	_open_level(1)

func _on_level_2_pressed() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	GameState.current_mode = "battle_royale"
	_open_level(2)

func _on_crystal_capture_pressed() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	GameState.current_mode = "crystal_capture"
	NetworkManager.game_mode = "crystal_capture"
	_open_level(3)

func _open_level(level: int) -> void:
	GameState.current_level = level
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
