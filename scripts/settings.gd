extends Control

@onready var nickname_input: LineEdit = $Center/Form/NicknameInput
@onready var music_volume: HSlider = $Center/Form/MusicVolume
@onready var sfx_volume: HSlider = $Center/Form/SFXVolume
@onready var footsteps_volume: HSlider = $Center/Form/FootstepsVolume


func _ready() -> void:
	nickname_input.text = SettingsManager.nickname
	music_volume.value = SettingsManager.music_volume
	sfx_volume.value = SettingsManager.sfx_volume
	footsteps_volume.value = SettingsManager.footsteps_volume
	UISoundManager.bind_buttons(self)
	UISoundManager.play_ui_sound("menu_open.wav")


func _on_nickname_text_changed(new_text: String) -> void:
	SettingsManager.set_nickname(new_text)


func _on_music_volume_value_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)


func _on_sfx_volume_value_changed(value: float) -> void:
	SettingsManager.set_sfx_volume(value)


func _on_footsteps_volume_value_changed(value: float) -> void:
	SettingsManager.set_footsteps_volume(value)


func _on_back_pressed() -> void:
	UISoundManager.play_ui_sound("menu_close.wav")
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
