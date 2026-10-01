extends Control

@onready var room_id_label: Label = $RoomId
@onready var players_list: ItemList = $Center/Panel/PlayersList
@onready var start_button: Button = $Bottom/StartButton


func _ready() -> void:
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")
	if NetworkManager.game_started:
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
		return
	room_id_label.text = "ID комнаты: %s" % NetworkManager.room_id
	room_id_label.visible = true
	start_button.visible = NetworkManager.is_host
	if not NetworkManager.lobby_updated.is_connected(_on_lobby_updated):
		NetworkManager.lobby_updated.connect(_on_lobby_updated)
	if not NetworkManager.game_started_received.is_connected(_on_game_started):
		NetworkManager.game_started_received.connect(_on_game_started)
	_refresh_players()


func _on_lobby_updated(_players: Dictionary) -> void:
	start_button.visible = NetworkManager.is_host
	_refresh_players()


func _on_game_started(_map_name: String, _game_mode: String) -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")


func _refresh_players() -> void:
	players_list.clear()
	var ids: Array = NetworkManager.room_players.keys()
	if ids.is_empty():
		players_list.add_item("Ожидание подключения")
		return
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for raw_id: Variant in ids:
		var data: Dictionary = NetworkManager.room_players.get(raw_id, {}) as Dictionary
		var player_id: int = int(raw_id)
		var player_name: String = str(data.get("nickname", "Player%d" % player_id))
		var suffix: String = " (хост)" if player_id == NetworkManager.room_host_id else ""
		if player_id == NetworkManager.my_id:
			suffix += " (вы)"
		players_list.add_item(player_name + suffix)


func _on_start_button_pressed() -> void:
	if NetworkManager.is_host:
		NetworkManager.start_game()


func _on_back_button_pressed() -> void:
	UISoundManager.play_ui_sound("menu_close.wav")
	NetworkManager.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
