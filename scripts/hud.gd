extends CanvasLayer
class_name GameHUD

@export var player: GamePlayer

@onready var health_background: Panel = $HUDRoot/HealthBackground
@onready var health_fill: Panel = $HUDRoot/HealthBackground/HealthFill
@onready var weapon_label: Label = $HUDRoot/WeaponLabel
@onready var ammo_label: Label = $HUDRoot/AmmoLabel
@onready var slot_container: HBoxContainer = $HUDRoot/SlotContainer
@onready var selected_item_label: Label = $HUDRoot/SelectedItemLabel
@onready var reload_button: Button = $HUDRoot/ReloadButton
@onready var match_panel: Panel = $HUDRoot/MatchPanel
@onready var match_mode_label: Label = $HUDRoot/MatchPanel/MatchMode
@onready var match_time_label: Label = $HUDRoot/MatchPanel/MatchTime
@onready var match_zone_label: Label = $HUDRoot/MatchPanel/MatchZone
@onready var portal_panel: Panel = $HUDRoot/PortalPanel
@onready var portal_status: Label = $HUDRoot/PortalPanel/PortalStatus
@onready var portal_hint: Label = $HUDRoot/PortalPanel/PortalHint

var slot_panels: Array[Panel] = []
var slot_icons: Array[TextureRect] = []
var slot_amounts: Array[Label] = []
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat
var _health_bg_style: StyleBoxFlat
var _health_fill_style: StyleBoxFlat
var _bound_inventory: Inventory
var _bound_health: Node
var _warned_sprite_ids: Dictionary = {}


func _ready() -> void:
	_normal_style = _make_panel_style(Color(0.08, 0.09, 0.11, 0.88), Color(0.45, 0.48, 0.52, 1.0), 1)
	_selected_style = _make_panel_style(Color(0.16, 0.17, 0.19, 0.96), Color(1.0, 0.78, 0.22, 1.0), 3)
	_health_bg_style = _make_panel_style(Color(0.18, 0.18, 0.18, 1.0), Color(0.08, 0.08, 0.08, 1.0), 1)
	_health_fill_style = _make_panel_style(Color(0.8, 0.2, 0.2, 1.0), Color(0.8, 0.2, 0.2, 1.0), 0)
	health_background.add_theme_stylebox_override("panel", _health_bg_style)
	health_fill.add_theme_stylebox_override("panel", _health_fill_style)
	reload_button.pressed.connect(_on_reload_pressed)
	reload_button.add_theme_stylebox_override("normal", _make_panel_style(Color("263d4f"), Color("4f91b8"), 5))
	reload_button.add_theme_stylebox_override("hover", _make_panel_style(Color("31566e"), Color("70c4ec"), 5))
	reload_button.add_theme_stylebox_override("pressed", _make_panel_style(Color("1b2d3b"), Color("4f91b8"), 5))
	reload_button.add_theme_stylebox_override("disabled", _make_panel_style(Color("25282d"), Color("3c4249"), 4))
	reload_button.add_theme_color_override("font_color", Color("d9f3ff"))
	reload_button.add_theme_color_override("font_disabled_color", Color("8a9096"))
	match_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.08, 0.14, 0.94), Color(0.16, 0.62, 0.82, 1.0), 2))
	portal_panel.add_theme_stylebox_override("panel", _make_panel_style(Color("211450"), Color("8e68e8"), 3))
	portal_panel.hide()
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
	_update_portal_hint(game)
	if game != null and game.has_method("get_match_time_text"):
		match_time_label.text = str(game.call("get_match_time_text"))
		match_mode_label.text = str(game.call("get_match_status_text"))
		match_zone_label.text = str(game.call("get_zone_text"))
		match_zone_label.visible = not match_zone_label.text.is_empty()
		match_panel.modulate = Color(1.0, 0.55, 0.45) if match_mode_label.text.begins_with("ПОРАЖЕНИЕ") else Color.WHITE
	if not is_instance_valid(player):
		return
	_bind_player_if_needed()
	var weapon: Dictionary = player.current_weapon
	if weapon.is_empty():
		weapon_label.text = "Оружие: нет"
		ammo_label.text = "Магазин: — / Запас: —"
		reload_button.disabled = true
		return
	var weapon_id: String = str(weapon.get("id", ""))
	weapon_label.text = str(weapon.get("name", weapon_id))
	var loaded: int = int(player.magazine.get(weapon_id, 0))
	var reserve: int = int(player.ammo_reserve.get(weapon_id, 0))
	ammo_label.text = "Магазин: %d / Запас: %d" % [loaded, reserve]
	reload_button.disabled = loaded >= int(weapon.get("magazine_size", 0)) or reserve <= 0


func _update_portal_hint(game: Node) -> void:
	if game == null or not game.has_method("get_portal_hud_state"):
		portal_panel.hide()
		return
	var state: Dictionary = game.call("get_portal_hud_state") as Dictionary
	if not bool(state.get("available", false)):
		portal_panel.hide()
		return
	portal_panel.show()
	var seconds: int = maxi(0, ceili(float(state.get("remaining", 0.0))))
	if bool(state.get("open", false)):
		portal_status.text = "⚡ ИСКРОВОЙ МАРШРУТ: ОТКРЫТ"
		portal_hint.text = "Войдите в сияние — %d с" % seconds
		portal_status.add_theme_color_override("font_color", Color("fff08a"))
		portal_hint.add_theme_color_override("font_color", Color("e8ddff"))
	else:
		portal_status.text = "ИСКРОВОЙ МАРШРУТ: ЗАРЯДКА"
		portal_hint.text = "Парные порталы через %d с" % seconds
		portal_status.add_theme_color_override("font_color", Color("a98cff"))
		portal_hint.add_theme_color_override("font_color", Color("d7ccf8"))

func update_ammo(ammo: int, reserve: int) -> void:
	if is_instance_valid(ammo_label):
		ammo_label.text = "Магазин: %d / Запас: %d" % [ammo, reserve]


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
	var item_name: String = str(data.get("name", item.get("id", "")))
	var amount: int = int(item.get("amount", 1))
	if str(item.get("id", "")) == "tar_bomb":
		var seconds: int = roundi(float(data.get("puddle_duration", 6.0)))
		var slow_percent: int = roundi((1.0 - float(data.get("slow_multiplier", 0.55))) * 100.0)
		selected_item_label.text = "%s  ×%d  • %dс замедления • -%d%% скорости" % [item_name, amount, seconds, slow_percent]
	elif str(item.get("id", "")) == "noise_lure":
		var lure_seconds: int = roundi(float(data.get("duration", 7.0)))
		var lure_radius: int = roundi(float(data.get("attraction_radius", 360.0)))
		selected_item_label.text = "%s  ×%d  • %dс шума • зовёт зомби (%d)" % [item_name, amount, lure_seconds, lure_radius]
	else:
		selected_item_label.text = "%s  ×%d" % [item_name, amount] if amount > 1 else item_name


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

func _on_reload_pressed() -> void:
	if is_instance_valid(player):
		player.reload()
