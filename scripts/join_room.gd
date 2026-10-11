extends Control

var searching: bool = false

@onready var title_label: Label = $Title
@onready var map_screen: VBoxContainer = $Center/MapScreen
@onready var mode_option: OptionButton = $Center/MapScreen/ModeOption
@onready var map_option: OptionButton = $Center/MapScreen/MapOption
@onready var status_label: Label = $Status


func _ready() -> void:
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")
	NetworkManager.nickname = SettingsManager.nickname
	NetworkManager.queued.connect(_on_queued)
	NetworkManager.waiting_for_host.connect(_on_waiting_for_host)
	NetworkManager.match_found.connect(_on_match_found)
	NetworkManager.network_error.connect(_on_network_error)
	mode_option.clear()
	mode_option.add_item("Классический")
	mode_option.add_item("Королевская битва")
	mode_option.select(1)
	map_option.clear()
	map_option.add_item("Island")
	map_option.add_item("City")
	map_option.select(0)
	_show_maps()


func _on_island_pressed() -> void:
	map_option.select(0)


func _on_city_pressed() -> void:
	map_option.select(1)


func _on_play_pressed() -> void:
	var selected_map: String = map_option.get_item_text(map_option.selected)
	var selected_mode: String = "classic" if mode_option.selected == 0 else "battle_royale"
	print("[JoinRoom] Нажата кнопка Играть. mode=", selected_mode, " map=", selected_map)
	if searching:
		return
	searching = true
	status_label.text = "Подключение к матчмейкеру…"
	NetworkManager.find_match(selected_mode, selected_map)


func _on_mode_selected(index: int) -> void:
	status_label.text = "Режим: %s" % ("Классический" if index == 0 else "Королевская битва")


func _show_maps() -> void:
	map_screen.visible = true
	title_label.text = "ВЫБЕРИ РЕЖИМ И КАРТУ"
	status_label.text = "Режим: Королевская битва"


func _on_back_pressed() -> void:
	UISoundManager.play_ui_sound("menu_close.wav")
	NetworkManager.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_queued() -> void:
	status_label.text = "Поиск игроков…"


func _on_waiting_for_host(host_nickname: String) -> void:
	status_label.text = "Ожидание хоста: %s" % host_nickname


func _on_match_found() -> void:
	UISoundManager.play_ui_sound("connect.wav")
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _on_network_error(message: String) -> void:
	status_label.text = "Ошибка: %s" % message
	searching = false
