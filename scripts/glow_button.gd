extends Button

@export var pulse_delay: float = 0.0
@export var cycle_duration: float = 2.4
@export var dim_brightness: float = 0.78
@export var glow_color: Color = Color(0.35, 0.82, 1.0, 1.0)

var _glow_styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	# Each button gets its own styles so the animated glow does not change the
	# shared menu theme or buttons on other screens.
	for style_name in [&"normal", &"hover", &"pressed", &"focus"]:
		var style := get_theme_stylebox(style_name)
		if style is StyleBoxFlat:
			var glow_style := style.duplicate() as StyleBoxFlat
			glow_style.shadow_offset = Vector2.ZERO
			add_theme_stylebox_override(style_name, glow_style)
			_glow_styles.append(glow_style)

	set_glow_strength(1.0)

	var pulse := create_tween().set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_interval(pulse_delay)
	pulse.tween_method(set_glow_strength, 1.0, 0.0, cycle_duration)
	pulse.tween_method(set_glow_strength, 0.0, 1.0, cycle_duration)


func set_glow_strength(strength: float) -> void:
	var amount := clampf(strength, 0.0, 1.0)
	var brightness := lerpf(dim_brightness, 1.0, amount)
	modulate = Color(brightness, brightness, brightness, 1.0)

	for style in _glow_styles:
		style.shadow_color = Color(glow_color, lerpf(0.03, 0.62, amount))
		style.shadow_size = roundi(lerpf(2.0, 18.0, amount))
