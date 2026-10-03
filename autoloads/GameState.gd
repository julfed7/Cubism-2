extends Node

var nickname: String = ""
var current_level: int = 0
var current_mode: String = "battle_royale"
var session_id: int = 0
var selected_brawler: String = "shelly"
var trophies: int = 0
var coins: int = 0
var wins: int = 0
var matches_played: int = 0

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		nickname = str(config.get_value("player", "nickname", "")).strip_edges()
		selected_brawler = str(config.get_value("player", "brawler", selected_brawler))
		trophies = int(config.get_value("progress", "trophies", trophies))
		coins = int(config.get_value("progress", "coins", coins))
		wins = int(config.get_value("progress", "wins", wins))
		matches_played = int(config.get_value("progress", "matches", matches_played))
	if nickname.is_empty():
		nickname = "Player"
	if not BrawlerDB.has_brawler(selected_brawler):
		selected_brawler = BrawlerDB.DEFAULT_ID

func set_nickname(value: String) -> void:
	nickname = value.strip_edges()
	if nickname.is_empty():
		nickname = "Player"
	_save_progress()

func set_brawler(value: String) -> void:
	if not BrawlerDB.has_brawler(value):
		return
	selected_brawler = value
	_save_progress()

func record_match(won: bool) -> void:
	matches_played += 1
	if won:
		wins += 1
		trophies += 8
		coins += 25
	else:
		trophies = maxi(0, trophies - 2)
		coins += 5
	_save_progress()

func _save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "nickname", nickname)
	config.set_value("player", "brawler", selected_brawler)
	config.set_value("progress", "trophies", trophies)
	config.set_value("progress", "coins", coins)
	config.set_value("progress", "wins", wins)
	config.set_value("progress", "matches", matches_played)
	config.save(SETTINGS_PATH)
