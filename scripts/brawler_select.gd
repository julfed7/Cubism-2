extends Control

@onready var cards: Array[Button] = [$Center/Content/Cards/Shelly, $Center/Content/Cards/Colt, $Center/Content/Cards/Spike]
@onready var description_label: Label = $Center/Content/Description
@onready var stats_label: Label = $Center/Content/Stats
@onready var selected_label: Label = $Center/Content/Selected
var selected_id: String = "shelly"

func _ready() -> void:
	selected_id = GameState.selected_brawler
	for index: int in range(cards.size()):
		cards[index].pressed.connect(_select.bind(["shelly", "colt", "spike"][index]))
	_select(selected_id)
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")

func _select(brawler_id: String) -> void:
	selected_id = brawler_id if BrawlerDB.has_brawler(brawler_id) else BrawlerDB.DEFAULT_ID
	var data: Dictionary = BrawlerDB.get_brawler(selected_id)
	GameState.set_brawler(selected_id)
	description_label.text = str(data.get("description", ""))
	stats_label.text = "Роль: %s    Здоровье: %d    Скорость: %d" % [data.get("role", ""), int(data.get("max_health", 100)), int(data.get("speed", 500))]
	selected_label.text = "%s  •  %s" % [data.get("name", ""), data.get("super_name", "")]
	for card: Button in cards:
		card.modulate = Color.WHITE
	cards[["shelly", "colt", "spike"].find(selected_id)].modulate = Color(1.0, 0.86, 0.48, 1.0)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
