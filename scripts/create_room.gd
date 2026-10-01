extends Control

@onready var room_name_input: LineEdit = $Center/Form/RoomNameInput
@onready var mode_option: OptionButton = $Center/Form/ModeOption
@onready var map_option: OptionButton = $Center/Form/MapOption
@onready var create_button: Button = $Center/Form/Create
@onready var status_label: Label = $Status


func _ready() -> void:
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")
	mode_option.clear()
	mode_option.add_item("Классический")
	mode_option.add_item("Королевская битва")
	mode_option.select(1)
	map_option.clear()
	map_option.add_item("Island")
	map_option.add_item("City")
	map_option.select(0)
	NetworkManager.queued.connect(_on_queued)
	NetworkManager.waiting_for_host.connect(_on_waiting_for_host)
	NetworkManager.match_found.connect(_on_match_found)
	NetworkManager.network_error.connect(_on_network_error)


func _on_create_pressed() -> void:
	create_button.disabled = true
	NetworkManager.room_name = room_name_input.text.strip_edges()
	var selected_mode: String = mode_option.get_item_text(mode_option.selected)
	var selected_map: String = map_option.get_item_text(map_option.selected)
	status_label.text = "Создание комнаты…"
	NetworkManager.create_room(selected_mode, selected_map, 20)


func _on_queued() -> void:
	status_label.text = "Поиск соперников…"


func _on_waiting_for_host(host_nickname: String) -> void:
	status_label.text = "Ожидание хоста: %s" % host_nickname


func _on_match_found() -> void:
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")


func _on_network_error(message: String) -> void:
	status_label.text = "Ошибка: %s" % message
	create_button.disabled = false


func _on_back_pressed() -> void:
	UISoundManager.play_ui_sound("menu_close.wav")
	NetworkManager.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
