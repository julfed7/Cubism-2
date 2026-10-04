extends Node

signal contracts_changed

const CONTRACT_PERIOD_SECONDS: int = 24 * 60 * 60
const CONTRACT_DEFINITIONS: Array[Dictionary] = [
	{"id": "play_matches", "title": "Сыграть матчи", "target": 5, "reward": 100},
	{"id": "win_matches", "title": "Победить в матчах", "target": 3, "reward": 150},
	{"id": "collect_crystals", "title": "Собрать кристаллы", "target": 20, "reward": 120},
]

var nickname: String = ""
var current_level: int = 0
var current_mode: String = "battle_royale"
var session_id: int = 0
var selected_brawler: String = "shelly"
var trophies: int = 0
var coins: int = 0
var wins: int = 0
var matches_played: int = 0
var contracts: Array[Dictionary] = []
# Unix timestamp of the last reset's UTC midnight; zero means no saved period.
var contracts_last_reset_date: int = 0

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	_initialize_contracts()
	contracts_last_reset_date = 0
	if config.load(SETTINGS_PATH) == OK:
		nickname = str(config.get_value("player", "nickname", "")).strip_edges()
		selected_brawler = str(config.get_value("player", "brawler", selected_brawler))
		trophies = int(config.get_value("progress", "trophies", trophies))
		coins = int(config.get_value("progress", "coins", coins))
		wins = int(config.get_value("progress", "wins", wins))
		matches_played = int(config.get_value("progress", "matches", matches_played))
		contracts_last_reset_date = maxi(0, int(config.get_value("contracts", "last_reset_date", 0)))
		for contract: Dictionary in contracts:
			var id: String = contract["id"]
			contract["progress"] = clampi(
				int(config.get_value("contracts", id + "_progress", 0)), 0, contract["target"]
			)
			contract["claimed"] = (
				bool(config.get_value("contracts", id + "_claimed", false))
				and contract["progress"] >= contract["target"]
			)
	if nickname.is_empty():
		nickname = "Player"
	if not BrawlerDB.has_brawler(selected_brawler):
		selected_brawler = BrawlerDB.DEFAULT_ID
	refresh_contracts()

func _initialize_contracts() -> void:
	contracts.clear()
	for definition: Dictionary in CONTRACT_DEFINITIONS:
		var contract: Dictionary = definition.duplicate(true)
		contract["progress"] = 0
		contract["claimed"] = false
		contracts.append(contract)

# Call before reading or changing contracts, including after returning from a match.
# UTC calendar days keep the reset independent of the device's time zone.
func refresh_contracts() -> bool:
	var now: int = int(Time.get_unix_time_from_system())
	var period_start: int = now - now % CONTRACT_PERIOD_SECONDS
	if contracts_last_reset_date > 0 and period_start < contracts_last_reset_date + CONTRACT_PERIOD_SECONDS:
		return false
	_initialize_contracts()
	contracts_last_reset_date = period_start
	_save_progress()
	contracts_changed.emit()
	return true

# Return a copy so a future screen cannot accidentally mutate saved progress.
func get_contracts() -> Array[Dictionary]:
	refresh_contracts()
	return contracts.duplicate(true)

# IDs: play_matches, win_matches, collect_crystals.
func add_contract_progress(contract_id: String, amount: int = 1) -> bool:
	refresh_contracts()
	if not _advance_contract_progress(contract_id, amount):
		return false
	_save_progress()
	contracts_changed.emit()
	return true

# Update in memory so match results and all contract events can be saved together.
func _advance_contract_progress(contract_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	for contract: Dictionary in contracts:
		if contract["id"] != contract_id:
			continue
		var progress: int = contract["progress"]
		var target: int = contract["target"]
		if contract["claimed"] or progress >= target:
			return false
		contract["progress"] = progress + mini(amount, target - progress)
		return true
	return false

func claim_contract_reward(contract_id: String) -> bool:
	refresh_contracts()
	for contract: Dictionary in contracts:
		if contract["id"] != contract_id:
			continue
		if contract["claimed"] or contract["progress"] < contract["target"]:
			return false
		var reward: int = contract["reward"]
		contract["claimed"] = true
		coins += reward
		# Save the coins and claim together; a failed save must not grant a reward.
		if _save_progress() != OK:
			coins -= reward
			contract["claimed"] = false
			return false
		contracts_changed.emit()
		return true
	return false

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

func record_match(won: bool, collected_crystals: int = 0) -> void:
	refresh_contracts()
	matches_played += 1
	if won:
		wins += 1
		trophies += 8
		coins += 25
	else:
		trophies = maxi(0, trophies - 2)
		coins += 5
	var changed: bool = _advance_contract_progress("play_matches", 1)
	if won:
		if _advance_contract_progress("win_matches", 1):
			changed = true
	if _advance_contract_progress("collect_crystals", collected_crystals):
		changed = true
	_save_progress()
	if changed:
		contracts_changed.emit()

func _save_progress() -> Error:
	var config := ConfigFile.new()
	# Audio settings share this file; retain all existing sections.
	config.load(SETTINGS_PATH)
	config.set_value("player", "nickname", nickname)
	config.set_value("player", "brawler", selected_brawler)
	config.set_value("progress", "trophies", trophies)
	config.set_value("progress", "coins", coins)
	config.set_value("progress", "wins", wins)
	config.set_value("progress", "matches", matches_played)
	config.set_value("contracts", "last_reset_date", contracts_last_reset_date)
	for contract: Dictionary in contracts:
		var id: String = contract["id"]
		config.set_value("contracts", id + "_progress", contract["progress"])
		config.set_value("contracts", id + "_claimed", contract["claimed"])
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Cannot save settings.cfg: %d" % error)
	return error
