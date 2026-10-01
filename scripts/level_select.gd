extends Control

func _on_level_1_pressed() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	_open_level(1)

func _on_level_2_pressed() -> void:
	NetworkManager.set_mode(NetworkManager.Mode.SINGLE)
	_open_level(2)

func _open_level(level: int) -> void:
	GameState.current_level = level
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
