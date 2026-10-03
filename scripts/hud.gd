extends CanvasLayer
class_name GameHUD

@export var player: GamePlayer

@onready var health_background: Panel = $HUDRoot/HealthBackground
@onready var health_fill: Panel = $HUDRoot/HealthBackground/HealthFill
@onready var weapon_label: Label = $HUDRoot/WeaponLabel
@onready var ammo_label: Label = $HUDRoot/AmmoLabel
@onready var slot_container: HBoxContainer = $HUDRoot/SlotContainer
@onready var selected_item_label: Label = $HUDRoot/SelectedItemLabel
@onready var crystal_panel: Panel = $HUDRoot/CrystalPanel
@onready var crystal_count_label: Label = $HUDRoot/CrystalPanel/CrystalCount
@onready var detection_panel: Panel = $HUDRoot/DetectionPanel
@onready var detection_value: Label = $HUDRoot/DetectionPanel/DetectionValue
@onready var detection_fill: Panel = $HUDRoot/DetectionPanel/DetectionBackground/DetectionFill
@onready var match_panel: Panel = $HUDRoot/MatchPanel
@onready var match_mode_label: Label = $HUDRoot/MatchPanel/MatchMode
@onready var match_time_label: Label = $HUDRoot/MatchPanel/MatchTime
@onready var match_zone_label: Label = $HUDRoot/MatchPanel/MatchZone

var slot_panels: Array[Panel] = []
var slot_icons: Array[TextureRect] = []
var slot_amounts: Array[Label] = []
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat
var _health_bg_style: StyleBoxFlat
var _health_fill_style: StyleBoxFlat
var _detection_fill_style: StyleBoxFlat
var _bound_inventory: Inventory
var _bound_health: Node
var _warned_sprite_ids: Dictionary = {}


func _ready() -> void:
	_normal_style = _make_panel_style(Color(0.08, 0.09, 0.11, 0.88), Color(0.45, 0.48, 0.52, 1.0), 1)
	_selected_style = _make_panel_style(Color(0.16, 0.17, 0.19, 0.96), Color(1.0, 0.78, 0.22, 1.0), 3)
	_health_bg_style = _make_panel_style(Color(0.18, 0.18, 0.18, 1.0), Color(0.08, 0.08, 0.08, 1.0), 1)
	_health_fill_style = _make_panel_style(Color(0.8, 0.2, 0.2, 1.0), Color(0.8, 0.2, 0.2, 1.0), 0)
	_detection_fill_style = _make_panel_style(Color("48b85b"), Color("48b85b"), 0)
	health_background.add_theme_stylebox_override("panel", _health_bg_style)
	health_fill.add_theme_stylebox_override("panel", _health_fill_style)
	crystal_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.12, 0.25, 0.94), Color(0.38, 0.82, 1.0, 1.0), 2))
	detection_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.07, 0.06, 0.92), Color(0.25, 0.45, 0.29, 1.0), 2))
	detection_panel.get_node("DetectionBackground").add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.1, 0.08, 0.94), Color(0.22, 0.32, 0.24, 1.0), 1))
	detection_fill.add_theme_stylebox_override("panel", _detection_fill_style)
	match_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.08, 0.14, 0.94), Color(0.16, 0.62, 0.82, 1.0), 2))
	crystal_panel.visible = false
	for child: Node in slot_container.get_children():
		if child is Panel:
			var panel: Panel = child as Panel
			var slot_index: int = slot_panels.size()
			slot_panels.append(panel)
			slot_amounts.append(panel.get_node("Amount") as Label)
			var icon: TextureRect = panel.get_node("Icon") as TextureRect
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			slot_icons.append(icon)
			for child_control: Node in panel.get_children():
				if child_control is Control:
					(child_control as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			panel.gui_input.connect(_on_slot_gui_input.bind(slot_index))


func _process(_delta: float) -> void:
	var game: Node = get_tree().current_scene
	if game != null and game.has_method("get_match_time_text"):
		match_time_label.text = str(game.call("get_match_time_text"))
		match_mode_label.text = str(game.call("get_match_status_text"))
		match_zone_label.text = str(game.call("get_zone_text"))
		match_zone_label.visible = not match_zone_label.text.is_empty()
		match_panel.modulate = Color(1.0, 0.55, 0.45) if match_mode_label.text.begins_with("ПОРАЖЕНИЕ") else Color.WHITE
	var capture_mode: bool = game != null and game.has_method("is_crystal_capture_mode") and game.is_crystal_capture_mode()
	crystal_panel.visible = capture_mode
	if capture_mode and is_instance_valid(player):
		crystal_count_label.text = "%02d" % player.crystals
	if not is_instance_valid(player):
		return
	_bind_player_if_needed()
	_update_detection_indicator()
	var weapon: Dictionary = player.current_weapon
	if weapon.is_empty():
		weapon_label.text = "Оружие: нет"
		ammo_label.text = "Магазин: — / Запас: —"
		return
	var weapon_id: String = str(weapon.get("id", ""))
	weapon_label.text = str(weapon.get("name", weapon_id))
	if weapon_id == "crystal_blade":
		ammo_label.text = "Атака: ближний бой"
	else:
		ammo_label.text = "Магазин: %d / Запас: %d" % [int(player.magazine.get(weapon_id, 0)), int(player.ammo_reserve.get(weapon_id, 0))]


func update_ammo(ammo: int, reserve: int) -> void:
	if is_instance_valid(ammo_label):
		ammo_label.text = "Магазин: %d / Запас: %d" % [ammo, reserve]


func _update_detection_indicator() -> void:
	if not is_instance_valid(player):
		return
	const detection_distance: float = 450.0
	var nearest_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if not node is GameZombie:
			continue
		var zombie := node as GameZombie
		if zombie.dead or zombie.hp <= 0.0:
			continue
		nearest_distance = minf(nearest_distance, player.global_position.distance_to(zombie.global_position))

	var ratio: float = 0.0
	if not player.is_hidden and nearest_distance < detection_distance:
		ratio = clampf(1.0 - nearest_distance / detection_distance, 0.0, 1.0)
	detection_fill.offset_right = 176.0 * ratio
	if player.is_hidden:
		detection_value.text = "СКРЫТНОСТЬ: В КУСТАХ"
		_detection_fill_style.bg_color = Color("48b85b")
	elif nearest_distance == INF:
		detection_value.text = "ОБНАРУЖЕНИЕ: НЕТ ВРАГОВ"
		_detection_fill_style.bg_color = Color("48b85b")
	else:
		detection_value.text = "ОБНАРУЖЕНИЕ: %d%%" % roundi(ratio * 100.0)
		_detection_fill_style.bg_color = Color("d14a43") if ratio > 0.65 else Color("e0ad45") if ratio > 0.25 else Color("48b85b")
	detection_fill.add_theme_stylebox_override("panel", _detection_fill_style)


func _bind_player_if_needed() -> void:
	if _bound_inventory == player.inventory:
		return
	if is_instance_valid(_bound_inventory) and _bound_inventory.changed.is_connected(_on_inventory_changed):
		_bound_inventory.changed.disconnect(_on_inventory_changed)
	if is_instance_valid(_bound_health) and _bound_health.is_connected("health_changed", Callable(self, "_on_health_changed")):
		_bound_health.disconnect("health_changed", Callable(self, "_on_health_changed"))
	_bound_inventory = player.inventory
	_bound_health = player.health
	if not _bound_inventory.changed.is_connected(_on_inventory_changed):
		_bound_inventory.changed.connect(_on_inventory_changed)
	if not _bound_health.is_connected("health_changed", Callable(self, "_on_health_changed")):
		_bound_health.connect("health_changed", Callable(self, "_on_health_changed"))
	_on_health_changed(float(_bound_health.current_health))
	_on_inventory_changed()


func _on_inventory_changed() -> void:
	if not is_instance_valid(player):
		return
	for i: int in range(slot_panels.size()):
		var item: Dictionary = player.inventory.get_slot(i)
		var item_id: String = str(item.get("id", ""))
		var data: Dictionary = ItemDB.get_item(item_id)
		var icon: TextureRect = slot_icons[i]
		if not item.is_empty():
			var sprite_path: String = str(data.get("sprite", ""))
			if sprite_path.is_empty():
				if not _warned_sprite_ids.has(item_id):
					push_warning("У предмета '%s' не задан путь к спрайту" % str(data.get("name", item_id)))
					_warned_sprite_ids[item_id] = true
				icon.texture = null
				icon.visible = false
			elif ResourceLoader.exists(sprite_path):
				icon.texture = load(sprite_path) as Texture2D
				icon.visible = icon.texture != null
			else:
				if not _warned_sprite_ids.has(item_id):
					push_warning("Спрайт предмета '%s' не найден: %s" % [str(data.get("name", item_id)), sprite_path])
					_warned_sprite_ids[item_id] = true
				icon.texture = null
				icon.visible = false
		else:
			icon.texture = null
			icon.visible = false
		var quantity: int = int(item.get("amount", 0))
		slot_amounts[i].text = str(quantity) if quantity > 1 else ""
		slot_amounts[i].visible = quantity > 1
		slot_panels[i].add_theme_stylebox_override("panel", _selected_style if i == player.inventory.selected_slot else _normal_style)
	_update_selected_item_label()


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		pressed = mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed and is_instance_valid(player):
		player.select_inventory_slot(index)
		get_viewport().set_input_as_handled()


func _update_selected_item_label() -> void:
	if not is_instance_valid(player) or not is_instance_valid(selected_item_label):
		return
	var item: Dictionary = player.inventory.get_selected()
	if item.is_empty():
		selected_item_label.text = "Выберите предмет"
		return
	var data: Dictionary = ItemDB.get_item(str(item.get("id", "")))
	selected_item_label.text = str(data.get("name", item.get("id", "")))


func _on_health_changed(value: float) -> void:
	if not is_instance_valid(player):
		return
	var maximum: float = maxf(float(player.health.max_health), 1.0)
	var ratio: float = clampf(value / maximum, 0.0, 1.0)
	health_fill.offset_right = 200.0 * ratio


func _make_panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	return style


func _on_exit_button_pressed() -> void:
	get_node("/root/NetworkManager").leave_game()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
