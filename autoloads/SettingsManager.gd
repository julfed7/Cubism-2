extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

var nickname: String = "Player"
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var footsteps_volume: float = 0.65


func _ready() -> void:
	_ensure_audio_bus("Music")
	_ensure_audio_bus("SFX")
	_ensure_audio_bus("Footsteps")
	_load_settings()
	apply_audio_settings()


func set_nickname(value: String) -> void:
	nickname = value.strip_edges()
	if nickname.is_empty():
		nickname = "Player"
	GameState.set_nickname(nickname)
	_save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("Music", music_volume)
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("SFX", sfx_volume)
	_save_settings()


func set_footsteps_volume(value: float) -> void:
	footsteps_volume = clampf(value, 0.0, 1.0)
	_set_bus_volume("Footsteps", footsteps_volume)
	_save_settings()


func apply_audio_settings() -> void:
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Footsteps", footsteps_volume)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		nickname = GameState.nickname if not GameState.nickname.is_empty() else "Player"
		return
	nickname = str(config.get_value("player", "nickname", GameState.nickname))
	music_volume = float(config.get_value("audio", "music", music_volume))
	sfx_volume = float(config.get_value("audio", "sfx", sfx_volume))
	footsteps_volume = float(config.get_value("audio", "footsteps", footsteps_volume))
	GameState.set_nickname(nickname)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "nickname", nickname)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "footsteps", footsteps_volume)
	var error: int = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Cannot save settings.cfg: %d" % error)


func _ensure_audio_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _set_bus_volume(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))
