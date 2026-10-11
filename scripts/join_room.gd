extends Control

var searching: bool = false
var selected_mode: String = ""

@onready var title_label: Label = $Title
@onready var mode_screen: VBoxContainer = $Center/ModeScreen
@onready var map_screen: VBoxContainer = $Center/MapScreen
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
	map_option.clear()
	map_option.add_item("Island")
	map_option.add_item("City")
	map_option.select(0)
	_show_modes()


func _on_island_pressed() -> void:
	map_option.select(0)


func _on_city_pressed() -> void:
	map_option.select(1)


func _on_classic_pressed() -> void:
	selected_mode = "classic"
	_show_maps()


func _on_battle_royale_pressed() -> void:
	selected_mode = "battle_royale"
	_show_maps()


func _on_play_pressed() -> void:
	var selected_map: String = map_option.get_item_text(map_option.selected)
	print("[JoinRoom] Нажата кнопка Играть. mode=", selected_mode, " map=", selected_map)
	if selected_mode.is_empty():
		return
	if searching:
		return
	searching = true
	status_label.text = "Подключение к матчмейкеру…"
	NetworkManager.find_match(selected_mode, selected_map)


func _show_modes() -> void:
	mode_screen.visible = true
	map_screen.visible = false
	title_label.text = "ВЫБЕРИ РЕЖИМ"
	status_label.text = ""


func _show_maps() -> void:
	mode_screen.visible = false
	map_screen.visible = true
	title_label.text = "ВЫБЕРИ КАРТУ"
	status_label.text = "Режим: %s" % ("Классический" if selected_mode == "classic" else "Королевская битва")


func _on_back_to_modes_pressed() -> void:
	_show_modes()


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
