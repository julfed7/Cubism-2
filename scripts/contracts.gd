extends Control

const INK := Color(0.025, 0.045, 0.1)
const GOLD := Color(1.0, 0.78, 0.12)
const ACCENTS: Array[Color] = [Color(0.1, 0.64, 1.0), Color(1.0, 0.4, 0.22), Color(0.67, 0.34, 1.0)]
const DESCRIPTIONS: Dictionary = {
	"play_matches": "Завершай матчи в любом режиме.",
	"win_matches": "Побеждай в классическом и королевском режимах или в захвате кристаллов.",
	"collect_crystals": "Подбирай кристаллы в режиме захвата кристаллов.",
}

@onready var cards: HBoxContainer = %Cards
@onready var coins_label: Label = %Coins
@onready var reset_label: Label = %Reset
@onready var feedback: Label = %Feedback
var _rows: Dictionary = {}
var _button_tweens: Dictionary = {}
var _feedback_tween: Tween


func _ready() -> void:
	# Duplicate the theme so other menu screens retain their appearance.
	var local_theme: Theme = theme.duplicate() as Theme
	local_theme.set_color("font_color", "Label", Color.WHITE)
	local_theme.set_color("font_outline_color", "Label", INK)
	local_theme.set_constant("outline_size", "Label", 4)
	theme = local_theme
	_style_button($Margin/Content/Header/Back, Color(0.2, 0.73, 1.0))
	var contracts: Array[Dictionary] = GameState.get_contracts()
	for index: int in range(contracts.size()):
		_create_card(contracts[index], index)
	GameState.contracts_changed.connect(_refresh)
	_refresh()
	_update_reset()
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")
	$Margin.modulate.a = 0.0
	create_tween().tween_property($Margin, "modulate:a", 1.0, 0.3)


func _box(color: Color, radius: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(4)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 5)
	return style


func _label(value: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _create_card(contract: Dictionary, index: int) -> void:
	var id: String = str(contract["id"])
	var accent: Color = ACCENTS[index % ACCENTS.size()]
	var panel := PanelContainer.new()
	panel.name = id
	panel.custom_minimum_size = Vector2(260, 400)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(accent.darkened(0.48)))
	cards.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	content.add_child(_label("КОНТРАКТ %02d" % (index + 1), 19, accent.lightened(0.5)))
	content.add_child(_label(str(contract["title"]).to_upper(), 28))
	var description := _label(str(DESCRIPTIONS.get(id, "Завершай задания в матчах.")), 20)
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(description)
	var progress_text := _label("", 24)
	content.add_child(progress_text)
	var progress := ProgressBar.new()
	progress.custom_minimum_size.y = 28
	progress.show_percentage = false
	var background := _box(INK, 10)
	background.content_margin_top = 0.0
	background.content_margin_bottom = 0.0
	progress.add_theme_stylebox_override("background", background)
	var fill := _box(accent, 10)
	fill.set_border_width_all(0)
	fill.shadow_size = 0
	fill.content_margin_top = 0.0
	fill.content_margin_bottom = 0.0
	progress.add_theme_stylebox_override("fill", fill)
	content.add_child(progress)
	content.add_child(_label("+%d МОНЕТ" % int(contract["reward"]), 28, GOLD))
	var claim := Button.new()
	claim.custom_minimum_size.y = 64
	claim.add_theme_font_size_override("font_size", 23)
	_style_button(claim, GOLD)
	claim.pressed.connect(_claim.bind(id))
	content.add_child(claim)
	_rows[id] = {"progress": progress, "text": progress_text, "claim": claim}


func _style_button(button: Button, color: Color) -> void:
	button.add_theme_stylebox_override("normal", _box(color, 14))
	button.add_theme_stylebox_override("hover", _box(color.lightened(0.15), 14))
	button.add_theme_stylebox_override("pressed", _box(color.darkened(0.12), 14))
	button.add_theme_stylebox_override("disabled", _box(Color(0.22, 0.3, 0.43), 14))
	var focus := _box(Color.TRANSPARENT, 14)
	focus.border_color = Color.WHITE
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", Color(0.76, 0.83, 0.94))
	button.button_down.connect(_animate_button.bind(button, 0.95))
	button.button_up.connect(_animate_button.bind(button, 1.0))


func _animate_button(button: Button, amount: float) -> void:
	if _button_tweens.has(button):
		var previous: Tween = _button_tweens[button]
		previous.kill()
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * amount, 0.18)
	_button_tweens[button] = tween


func _refresh() -> void:
	for contract: Dictionary in GameState.get_contracts():
		var id: String = str(contract["id"])
		if not _rows.has(id):
			continue
		var row: Dictionary = _rows[id]
		var progress: ProgressBar = row["progress"]
		var progress_text: Label = row["text"]
		var claim: Button = row["claim"]
		var target: int = int(contract["target"])
		var current: int = int(contract["progress"])
		var claimed: bool = bool(contract["claimed"])
		progress.max_value = target
		progress.value = current
		progress_text.text = "%d / %d" % [current, target]
		claim.disabled = claimed or current < target
		claim.text = "ПОЛУЧЕНО" if claimed else ("ЗАБРАТЬ" if current >= target else "В ПРОЦЕССЕ")
	coins_label.text = "МОНЕТЫ: %d" % GameState.coins


func _claim(contract_id: String) -> void:
	var coins_before: int = GameState.coins
	if GameState.claim_contract_reward(contract_id):
		_show_feedback("+%d монет! Награда получена." % (GameState.coins - coins_before))
	else:
		_show_feedback("Не удалось получить награду. Попробуй ещё раз.")
	_refresh()


func _show_feedback(message: String) -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	feedback.text = message
	feedback.modulate.a = 1.0
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(3.0)
	_feedback_tween.tween_property(feedback, "modulate:a", 0.0, 0.4)


func _update_reset() -> void:
	GameState.refresh_contracts()
	var remaining: int = maxi(0, GameState.contracts_last_reset_date + GameState.CONTRACT_PERIOD_SECONDS - int(Time.get_unix_time_from_system()))
	var hours: int = int(remaining / 3600.0)
	var minutes: int = int((remaining % 3600) / 60.0)
	reset_label.text = "Новые контракты через %02d:%02d:%02d • Прогресс сохраняется" % [hours, minutes, remaining % 60]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
