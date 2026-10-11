extends Control

func _ready() -> void:
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")
	$Profile.text = "%s  •  %d ПОБЕД" % [GameState.nickname, GameState.wins]


func _on_compaign_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/LevelSelect.tscn")

func _on_join_room_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/JoinRoom.tscn")

func _on_create_room_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/CreateRoom.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")

func _on_contracts_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Contracts.tscn")
