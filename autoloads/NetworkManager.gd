extends Node

## Матчмейкер + noray + ENet.
## Хост создаёт комнату (create_room), клиенты подключаются (find_match).

signal queued()
signal waiting_for_host(host_nickname: String)
signal match_found()
signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal network_error(message: String)
signal player_connected(id: int, player_name: String)
signal player_disconnected(id: int)
signal lobby_updated(players: Dictionary)
signal game_started_received(map_name: String, game_mode: String)
signal room_created(match_id: String)

enum Mode { SINGLE, HOST, CLIENT }

const NORAY_HOST: String = "tomfol.io"
const NORAY_PORT: int = 8890
const MAX_PLAYERS: int = 20
const SNAPSHOT_BUFFER_MAX: int = 8

var matchmaker_url: String = "wss://matchmaker-jpk1.onrender.com"
var _mm_socket: WebSocketPeer = null
var _mm_connected: bool = false
var _pending_action: String = ""  # "create" или "find"
var _queue_mode: String = "battle_royale"
var _queue_map: String = "Island"
var _queue_max: int = 20
var my_match_id: String = ""
var _reconnect_attempted: bool = false

var mode: Mode = Mode.SINGLE
var is_single: bool = true
var is_host: bool = false
var is_client: bool = false
var nickname: String = "Player"
var room_id: String = ""
var room_name: String = "Match"
var room_host_id: int = 1
var game_mode: String = "battle_royale"
var map_name: String = "Island"
var map_path: String = "res://scenes/maps/Island.tscn"
var current_map_index: int = 0
var game_started: bool = false
var my_id: int = 1
var room_players: Dictionary = {}

var _enet_peer: ENetMultiplayerPeer = null
var _noray_busy: bool = false
var _identity_ready: bool = false
var _got_noray_oid: bool = false
var _got_noray_pid: bool = false
var _endpoint_address: String = ""
var _endpoint_port: int = 0
var _match_emitted: bool = false
var _ping_timer: float = 20.0
var _snapshot_buffer: Array[Dictionary] = []
var _last_snapshot: Dictionary = {}
var _prev_snapshot: Dictionary = {}


func _ready() -> void:
	Noray.on_oid.connect(_on_noray_oid)
	Noray.on_pid.connect(_on_noray_pid)
	Noray.on_connect_nat.connect(_on_noray_endpoint)
	Noray.on_connect_relay.connect(_on_noray_endpoint)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_enet_connected)
	multiplayer.connection_failed.connect(_on_enet_connection_failed)
	multiplayer.server_disconnected.connect(_on_enet_server_disconnected)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	is_single = new_mode == Mode.SINGLE
	is_host = new_mode == Mode.HOST
	is_client = new_mode == Mode.CLIENT


# ============ MATCHMAKER CONNECTION ============

func connect_to_matchmaker() -> void:
	if _mm_socket != null:
		var st: int = _mm_socket.get_ready_state()
		if st == WebSocketPeer.STATE_CONNECTING or st == WebSocketPeer.STATE_OPEN:
			return
	_mm_socket = WebSocketPeer.new()
	_mm_connected = false
	_reconnect_attempted = false
	var error: int = _mm_socket.connect_to_url(matchmaker_url)
	if error != OK:
		_mm_socket = null
		_fail("Матчмейкер недоступен, код: %d" % error)
		return
	print("[Matchmaker] Подключение к ", matchmaker_url)


func _process(delta: float) -> void:
	if _mm_socket == null:
		return
	_mm_socket.poll()
	var state: int = _mm_socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _mm_connected:
			_mm_connected = true
			print("[Matchmaker] Подключено")
			# Если ждали действие — выполняем
			if _pending_action == "create":
				_send_create_room()
			elif _pending_action == "find":
				_send_find_match()
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 20.0
			_send_mm({"type": "ping"})
		while _mm_socket.get_available_packet_count() > 0:
			var packet: PackedByteArray = _mm_socket.get_packet()
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if parsed is Dictionary:
				_handle_mm_message(parsed as Dictionary)
	elif state == WebSocketPeer.STATE_CLOSED:
		var close_code: int = _mm_socket.get_close_code()
		var close_reason: String = _mm_socket.get_close_reason()
		print("[Matchmaker] Соединение закрыто. Код: %d, причина: %s" % [close_code, close_reason])
		_mm_socket = null
		_mm_connected = false
		if _pending_action != "" and not _reconnect_attempted:
			_reconnect_attempted = true
			connect_to_matchmaker()


func _send_mm(message: Dictionary) -> void:
	if _mm_socket == null or _mm_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_mm_socket.send_text(JSON.stringify(message))


# ============ SNAPSHOT TRAJECTORY BUFFER ============

func push_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var snapshot_copy: Dictionary = snapshot.duplicate(true)
	_prev_snapshot = _last_snapshot
	_last_snapshot = snapshot_copy
	_snapshot_buffer.append(snapshot_copy)
	while _snapshot_buffer.size() > SNAPSHOT_BUFFER_MAX:
		_snapshot_buffer.pop_front()


func get_trajectory_for(id: String, is_zombie: bool) -> Dictionary:
	if _last_snapshot.is_empty() or _prev_snapshot.is_empty():
		return {}
	var key: String = "zombies" if is_zombie else "players"
	var last_group: Dictionary = _last_snapshot.get(key, {}) as Dictionary
	var prev_group: Dictionary = _prev_snapshot.get(key, {}) as Dictionary
	var last_data: Dictionary = last_group.get(id, {}) as Dictionary
	var prev_data: Dictionary = prev_group.get(id, {}) as Dictionary
	if last_data.is_empty():
		return {}
	var pos: Vector2 = Vector2(float(last_data.get("x", 0.0)), float(last_data.get("y", 0.0)))
	var vel: Vector2 = Vector2.ZERO
	if not prev_data.is_empty():
		vel = Vector2(
			float(last_data.get("x", 0.0)) - float(prev_data.get("x", 0.0)),
			float(last_data.get("y", 0.0)) - float(prev_data.get("y", 0.0))
		)
	return {"pos": pos, "vel": vel}


func clear_snapshots() -> void:
	_snapshot_buffer.clear()
	_last_snapshot.clear()
	_prev_snapshot.clear()


# ============ CREATE ROOM (хост) ============

func create_room(p_mode: String = "battle_royale", p_map_name: String = "Island", p_max: int = 20) -> void:
	_queue_mode = _normalize_mode(p_mode)
	_queue_map = p_map_name if p_map_name in ["Island", "City", "CrystalArena"] else "Island"
	if _queue_mode == "crystal_capture":
		_queue_map = "CrystalArena"
	_queue_max = clampi(p_max, 2, 20)
	game_mode = _queue_mode
	map_name = _queue_map
	map_path = "res://scenes/maps/%s.tscn" % map_name
	current_map_index = 0 if map_name == "Island" else 1
	nickname = SettingsManager.nickname
	_pending_action = "create"
	_reconnect_attempted = false
	_match_emitted = false
	game_started = false

	if _mm_connected:
		_send_create_room()
	else:
		connect_to_matchmaker()


func _send_create_room() -> void:
	_pending_action = ""
	# 1. Сначала создаём noray-комнату, получаем OID
	await _host_room_via_noray()
	# 2. Отправляем OID матчмейкеру
	if _noray_busy:
		# ещё занят — ждём
		while _noray_busy:
			await get_tree().create_timer(0.2).timeout
	_send_mm({
		"type": "create_room",
		"noray_oid": room_id,
		"mode": _queue_mode,
		"map": _queue_map,
		"host_nickname": nickname,
		"max_players": _queue_max,
	})


# ============ FIND MATCH (клиент) ============

func find_match(p_mode: String = "battle_royale", p_map_name: String = "Island") -> void:
	print("[Matchmaker] find_match: mode=", p_mode, " map=", p_map_name)
	_queue_mode = _normalize_mode(p_mode)
	_queue_map = p_map_name if p_map_name in ["Island", "City", "CrystalArena"] else "Island"
	if _queue_mode == "crystal_capture":
		_queue_map = "CrystalArena"
	game_mode = _queue_mode
	map_name = _queue_map
	map_path = "res://scenes/maps/%s.tscn" % map_name
	current_map_index = 0 if map_name == "Island" else 1
	nickname = SettingsManager.nickname
	_pending_action = "find"
	_reconnect_attempted = false
	_match_emitted = false
	game_started = false

	if _mm_connected:
		_send_find_match()
	else:
		connect_to_matchmaker()


func _send_find_match() -> void:
	_pending_action = ""
	_send_mm({
		"type": "find_match",
		"nickname": nickname,
		"mode": _queue_mode,
		"map": _queue_map,
	})


# ============ MESSAGE HANDLING ============

func _handle_mm_message(message: Dictionary) -> void:
	var t: String = str(message.get("type", ""))
	match t:
		"room_created":
			my_match_id = str(message.get("match_id", ""))
			print("[Matchmaker] Комната создана: ", my_match_id, " OID=", room_id)
			room_created.emit(my_match_id)
			_emit_match_found()
		"no_room":
			if _match_emitted:
				return
			_fail(str(message.get("message", "Нет комнат")))
		"match_ready":
			_pending_action = ""
			_match_emitted = true
			my_match_id = str(message.get("match_id", my_match_id))
			apply_game_config(str(message.get("mode", _queue_mode)), str(message.get("map", _queue_map)), false)
			var host_oid: String = str(message.get("noray_oid", ""))
			if host_oid.is_empty():
				_fail("Матч найден, но сервер не прислал Noray OID")
				return
			set_mode(Mode.CLIENT)
			await _join_room_via_noray(host_oid)
			if _enet_peer != null:
				var current_scene: Node = get_tree().current_scene
				if current_scene == null or current_scene.scene_file_path != "res://scenes/Lobby.tscn":
					get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
		"start_match":
			pass  # хост сам запустит
		"pong":
			pass
		"room_closed":
			_fail("Комната закрыта хостом")
		"error":
			_fail(str(message.get("message", "Ошибка матчмейкера")))
		_:
			print("[Matchmaker] Неизвестное сообщение: ", t)


# ============ NORAY HOST ============

func _host_room_via_noray() -> void:
	if _noray_busy:
		return
	_noray_busy = true
	var error: int = await _prepare_noray()
	if error != OK:
		_noray_busy = false
		_fail("Noray host setup failed: %d" % error)
		return
	_enet_peer = ENetMultiplayerPeer.new()
	error = _enet_peer.create_server(Noray.local_port, MAX_PLAYERS)
	if error != OK:
		_noray_busy = false
		_fail("ENet create_server failed: %d" % error)
		return
	multiplayer.multiplayer_peer = _enet_peer
	set_mode(Mode.HOST)
	my_id = 1
	room_host_id = 1
	room_id = Noray.oid
	room_players = {1: {"id": 1, "nickname": nickname}}
	lobby_updated.emit(room_players)
	_noray_busy = false
	print("[Noray] Хост готов. OID: ", room_id, ", UDP-порт: ", Noray.local_port)


# ============ NORAY CLIENT ============

func _join_room_via_noray(host_oid: String) -> void:
	if _noray_busy:
		return
	_noray_busy = true
	var error: int = await _prepare_noray()
	if error != OK:
		_noray_busy = false
		_fail("Noray client setup failed: %d" % error)
		return
	_endpoint_address = ""
	_endpoint_port = 0
	error = Noray.connect_nat(host_oid)
	if error == OK:
		await _wait_for_endpoint(3.5)
	if _endpoint_address.is_empty():
		error = Noray.connect_relay(host_oid)
		if error == OK:
			await _wait_for_endpoint(8.0)
	if _endpoint_address.is_empty():
		_noray_busy = false
		_fail("Не получен NAT или relay адрес")
		return
	error = await _perform_client_handshake(_endpoint_address, _endpoint_port)
	print("[Noray] Client handshake result: ", error, " via ", _endpoint_address, ":", _endpoint_port)
	if error != OK and error != ERR_BUSY:
		_noray_busy = false
		_fail("PacketHandshake failed: %d" % error)
		return
	_enet_peer = ENetMultiplayerPeer.new()
	error = _enet_peer.create_client(_endpoint_address, _endpoint_port, 0, 0, 0, Noray.local_port)
	if error != OK:
		print("[Noray] ENet create_client failed: ", error, " address=", _endpoint_address, ":", _endpoint_port)
		_noray_busy = false
		_fail("ENet create_client failed: %d" % error)
		return
	multiplayer.multiplayer_peer = _enet_peer
	set_mode(Mode.CLIENT)
	room_id = host_oid
	_noray_busy = false
	print("[Noray] ENet client -> ", _endpoint_address, ":", _endpoint_port)


# ============ NORAY HELPERS ============

func _prepare_noray() -> int:
	if not Noray.is_connected_to_host():
		var connect_error: int = await Noray.connect_to_host(NORAY_HOST, NORAY_PORT)
		if connect_error != OK:
			return connect_error
	_identity_ready = false
	_got_noray_oid = false
	_got_noray_pid = false
	var register_error: int = Noray.register_host()
	if register_error != OK:
		return register_error
	var identity_error: int = await _wait_for_identity(8.0)
	if identity_error != OK:
		return identity_error
	return await Noray.register_remote()


func _wait_for_identity(timeout: float) -> int:
	while timeout > 0.0:
		if _identity_ready and not Noray.oid.is_empty() and not Noray.pid.is_empty():
			return OK
		await get_tree().create_timer(0.1).timeout
		timeout -= 0.1
	return ERR_TIMEOUT


func _wait_for_endpoint(timeout: float) -> void:
	while timeout > 0.0 and _endpoint_address.is_empty():
		await get_tree().create_timer(0.1).timeout
		timeout -= 0.1


func _perform_client_handshake(address: String, port: int) -> int:
	var udp := PacketPeerUDP.new()
	var error: int = udp.bind(Noray.local_port)
	if error != OK:
		return error
	error = udp.set_dest_address(address, port)
	if error != OK:
		udp.close()
		return error
	error = await PacketHandshake.over_packet_peer(udp, 4.0, 0.1)
	udp.close()
	return error


func _on_noray_oid(_oid: String) -> void:
	_got_noray_oid = true
	_identity_ready = _got_noray_oid and _got_noray_pid


func _on_noray_pid(_pid: String) -> void:
	_got_noray_pid = true
	_identity_ready = _got_noray_oid and _got_noray_pid


func _on_noray_endpoint(address: String, port: int) -> void:
	print("[Noray] on_noray_endpoint: ", address, ":", port, " is_host=", is_host, " has_peer=", _enet_peer != null)
	if is_host and _enet_peer != null:
		print("[Noray] Хост отвечает handshake")
		await _answer_host_handshake(address, port)
	else:
		_endpoint_address = address
		_endpoint_port = port


func _answer_host_handshake(address: String, port: int) -> void:
	if _enet_peer == null:
		print("[Noray] _enet_peer null, не могу ответить")
		return
	print("[Noray] Host handshake start: ", address, ":", port)
	var result: Variant = await PacketHandshake.over_enet_peer(_enet_peer, address, port, 4.0, 0.1)
	print("[Noray] Host handshake result: ", result)


# ============ ENet EVENTS ============

func _on_enet_connected() -> void:
	my_id = multiplayer.get_unique_id()
	print("[ENet] Connected. Peer ID: ", my_id, ", nickname: ", nickname)
	connected_to_server.emit()
	register_player.rpc_id(1, nickname)
	UISoundManager.play_ui_sound("connect.wav")


func _on_enet_connection_failed() -> void:
	_fail("ENet не смог подключиться к хосту")


func _on_enet_server_disconnected() -> void:
	server_disconnected.emit()
	UISoundManager.play_ui_sound("error.wav")
	reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		room_players[peer_id] = {"id": peer_id, "nickname": "Player%d" % peer_id}
		_sync_roster.rpc(room_players)
	var peer_data: Dictionary = room_players.get(peer_id, {}) as Dictionary
	player_connected.emit(peer_id, str(peer_data.get("nickname", "")))


func _on_peer_disconnected(peer_id: int) -> void:
	var peer_data: Dictionary = room_players.get(peer_id, {}) as Dictionary
	print("[ENet] Отключился: %s (#%d)" % [str(peer_data.get("nickname", "Player")), peer_id])
	room_players.erase(peer_id)
	if is_host:
		_sync_roster.rpc(room_players)
	player_disconnected.emit(peer_id)
	lobby_updated.emit(room_players)


@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	if not is_host:
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	room_players[sender_id] = {"id": sender_id, "nickname": player_name}
	print("[ENet] Подключился: %s (#%d)" % [player_name, sender_id])
	_sync_roster.rpc(room_players)
	if game_started:
		_start_game.rpc_id(sender_id, map_name, game_mode)
	else:
		_enter_lobby.rpc_id(sender_id)


@rpc("authority", "call_remote", "reliable")
func _enter_lobby() -> void:
	_emit_match_found()


@rpc("authority", "call_local", "reliable")
func _sync_roster(players: Dictionary) -> void:
	room_players = players.duplicate(true)
	my_id = multiplayer.get_unique_id()
	lobby_updated.emit(room_players)


# ============ GAME START ============

func start_game() -> void:
	if is_host:
		_start_game.rpc(map_name, game_mode)


@rpc("authority", "call_local", "reliable")
func _start_game(p_map_name: String, p_game_mode: String) -> void:
	apply_game_config(p_game_mode, p_map_name, true)
	game_started_received.emit(map_name, game_mode)
	var current_scene: Node = get_tree().current_scene
	if current_scene == null or current_scene.scene_file_path != "res://scenes/Game.tscn":
		get_tree().change_scene_to_file("res://scenes/Game.tscn")


func _emit_match_found() -> void:
	if _match_emitted:
		return
	_match_emitted = true
	match_found.emit()


# ============ ACTIONS ============

func quantize(value: float) -> int:
	# Godot Variant int переносит квантованное значение без потери диапазона карты.
	return roundi(value * 100.0)


func dequantize(value: int) -> float:
	return float(value) / 100.0


func send_move(quantized_x: int, quantized_y: int) -> void:
	if not is_client:
		return
	var game: Node = get_tree().current_scene
	if game != null:
		game.rpc_id(1, "request_move", Vector2i(quantized_x, quantized_y))


func send_shoot(direction: Vector2) -> void:
	var game: Node = get_tree().current_scene
	if game == null or is_single:
		return
	if is_host and game.has_method("request_shoot_for_player"):
		game.request_shoot_for_player(1, direction)
	else:
		game.rpc_id(1, "request_shoot", direction)


func send_action(action: Dictionary) -> void:
	var game: Node = get_tree().current_scene
	if game == null or is_single:
		return
	if is_host and game.has_method("handle_network_action"):
		game.handle_network_action(1, action)
	else:
		game.rpc_id(1, "request_action", action)


func request_pickup(pickup_id: String) -> void:
	send_action({"type": "pickup", "entity_id": pickup_id})


func request_open_chest(chest_id: String) -> void:
	send_action({"type": "open_chest", "entity_id": chest_id})


func use_item(slot_index: int) -> void:
	send_action({"type": "use_item", "slot": slot_index})


# ============ UTILITY ============

func apply_game_config(p_game_mode: String, p_map_name: String, p_started: bool = true) -> void:
	game_mode = _normalize_mode(p_game_mode)
	map_name = p_map_name if p_map_name in ["Island", "City", "CrystalArena"] else "Island"
	if game_mode == "crystal_capture":
		map_name = "CrystalArena"
	map_path = "res://scenes/maps/%s.tscn" % map_name
	current_map_index = 0 if map_name == "Island" else 1
	game_started = p_started


func leave_game() -> void:
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = null
	multiplayer.multiplayer_peer = null
	clear_snapshots()
	if _mm_socket != null:
		_mm_socket.close(1000, "leave")
	_mm_socket = null
	_mm_connected = false
	if Noray.is_connected_to_host():
		Noray.disconnect_from_host()
	reset_state()


func reset() -> void:
	leave_game()


func reset_state() -> void:
	set_mode(Mode.SINGLE)
	clear_snapshots()
	my_id = 1
	my_match_id = ""
	room_id = ""
	room_players = {}
	game_started = false
	game_mode = "battle_royale"
	map_name = "Island"
	map_path = "res://scenes/maps/Island.tscn"
	_pending_action = ""
	_reconnect_attempted = false
	_match_emitted = false
	_noray_busy = false
	_identity_ready = false
	_got_noray_oid = false
	_got_noray_pid = false
	_endpoint_address = ""
	_endpoint_port = 0


func _normalize_mode(value: String) -> String:
	var normalized: String = value.to_lower().strip_edges()
	if normalized in ["crystal_capture", "захват кристаллов", "захват кристалла", "кристаллы"]:
		return "crystal_capture"
	if normalized in ["classic", "классический", "классика"]:
		return "classic"
	return "battle_royale"


func _fail(message: String) -> void:
	if _match_emitted and message == "Нет комнат":
		return
	push_error("[NetworkManager] " + message)
	network_error.emit(message)
	connection_failed.emit()
	UISoundManager.play_ui_sound("error.wav")
