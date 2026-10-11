extends Node

const POOL_SIZE: int = 8
const SOUND_FALLBACKS: Dictionary = {
	# Placeholder until a final bespoke lure SFX is delivered. Keeping this
	# mapping here makes the gameplay event stable and avoids missing-file noise.
	"noise_lure_activate.wav": "pickup.wav",
}
var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}


func _ready() -> void:
	for index: int in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "UISound%d" % index
		player.bus = "SFX"
		add_child(player)
		_players.append(player)


func play_ui_sound(sound_name: String) -> void:
	var path: String = "res://sounds/ui/%s" % sound_name
	if not ResourceLoader.exists(path):
		path = "res://sounds/%s" % sound_name
	if not ResourceLoader.exists(path):
		var fallback_name: String = str(SOUND_FALLBACKS.get(sound_name, ""))
		if fallback_name.is_empty():
			push_warning("UI sound not found: " + sound_name)
			return
		path = "res://sounds/%s" % fallback_name
		if not ResourceLoader.exists(path):
			push_warning("UI sound fallback not found: " + fallback_name)
			return
	if not _cache.has(path):
		_cache[path] = load(path) as AudioStream
	var player: AudioStreamPlayer = _get_available_player()
	player.bus = "Footsteps" if sound_name.begins_with("step") else "SFX"
	player.stream = _cache[path] as AudioStream
	player.play()


func bind_buttons(root: Node) -> void:
	for node: Node in _all_children(root):
		if node is BaseButton:
			var button := node as BaseButton
			if not button.has_meta("ui_sounds_bound"):
				button.pressed.connect(func() -> void: play_ui_sound("click.wav"))
				button.mouse_entered.connect(func() -> void: play_ui_sound("hover.wav"))
				button.set_meta("ui_sounds_bound", true)


func _get_available_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if not player.playing:
			return player
	return _players[0]


func _all_children(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		result.append(child)
		result.append_array(_all_children(child))
	return result
