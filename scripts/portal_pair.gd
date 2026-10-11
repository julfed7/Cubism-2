extends Node2D
class_name PortalPair

## Endpoints are local to this node. The match owns mode selection, spawning
## and network transport, including movement revisions after teleportation.
## Connect these signals there; clients only apply trusted state and effects.
signal open_state_changed(open: bool)
signal player_teleported(player: GamePlayer, departure: Vector2, arrival: Vector2)

@export var point_a: Vector2 = Vector2.ZERO
@export var point_b: Vector2 = Vector2(400.0, 0.0)
@export var entry_radius: float = 38.0
@export var initial_delay: float = 8.0
@export var open_duration: float = 6.0
@export var closed_duration: float = 12.0

var is_open: bool = false
var _elapsed: float = 0.0
var _remaining: float = 0.0
var _revision: int = 0
var _received_revision: int = -1
var _blocked: Dictionary = {}
var _sound: AudioStreamWAV


func _ready() -> void:
	# Sample positions after normal player movement.
	process_physics_priority = 10
	if _is_authoritative() and _configuration_valid():
		_update_schedule()


func _is_authoritative() -> bool:
	return NetworkManager.is_single or NetworkManager.is_host


func _configuration_valid() -> bool:
	if not point_a.is_finite() or not point_b.is_finite():
		return false
	if not is_finite(entry_radius) or entry_radius <= 0.0:
		return false
	if not is_finite(initial_delay) or initial_delay < 0.0:
		return false
	if not is_finite(open_duration) or not is_finite(closed_duration):
		return false
	if open_duration <= 0.0 or closed_duration <= 0.0:
		return false
	var separation: float = to_global(point_a).distance_to(to_global(point_b))
	# Overlapping entrances cannot provide an unambiguous exit/re-entry.
	return is_finite(separation) and separation > entry_radius * 2.0


## Set world-space coordinates without removing existing exit locks.
func set_endpoints(world_a: Vector2, world_b: Vector2) -> bool:
	if not _is_authoritative() or not world_a.is_finite() or not world_b.is_finite():
		return false
	if not is_finite(entry_radius) or entry_radius <= 0.0:
		return false
	if world_a.distance_to(world_b) <= entry_radius * 2.0:
		return false
	var local_a: Vector2 = to_local(world_a)
	var local_b: Vector2 = to_local(world_b)
	if not local_a.is_finite() or not local_b.is_finite():
		return false
	point_a = local_a
	point_b = local_b
	_revision += 1
	return true


func _physics_process(delta: float) -> void:
	if not _is_authoritative():
		return
	if not _configuration_valid():
		_remaining = 0.0
		_set_open(false)
		return
	_elapsed += delta
	_update_schedule()
	_release_exit_locks()
	if not is_open:
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		try_teleport(node as GamePlayer)


func _update_schedule() -> void:
	if _elapsed < initial_delay:
		_remaining = initial_delay - _elapsed
		_set_open(false)
		return
	# Absolute phase handles long frames without looping over missed cycles.
	var phase: float = fmod(_elapsed - initial_delay, open_duration + closed_duration)
	var open: bool = phase < open_duration
	_remaining = open_duration - phase if open else open_duration + closed_duration - phase
	_set_open(open)


func _set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	_revision += 1
	open_state_changed.emit(is_open)


func _entrance_at(world_position: Vector2) -> int:
	if world_position.distance_to(to_global(point_a)) <= entry_radius:
		return 0
	if world_position.distance_to(to_global(point_b)) <= entry_radius:
		return 1
	return -1


func _release_exit_locks() -> void:
	# Closing/reopening alone never clears a lock.
	for id: int in _blocked.keys():
		var reference: WeakRef = _blocked[id]
		var player: GamePlayer = reference.get_ref() as GamePlayer
		if not is_instance_valid(player) or not player.is_inside_tree():
			_blocked.erase(id)
		elif _entrance_at(player.global_position) == -1:
			_blocked.erase(id)


## Can also be called by future Area2D entrances; checks stay on the server.
func try_teleport(player: GamePlayer) -> bool:
	if not _is_authoritative() or not is_inside_tree() or not is_open:
		return false
	if not _configuration_valid() or not is_instance_valid(player):
		return false
	if not player.is_inside_tree() or not player.is_in_group("player"):
		return false
	if player._dead or not is_finite(player.hp) or player.hp <= 0.0 or not player.visible:
		return false
	if not player.global_position.is_finite():
		return false
	_release_exit_locks()
	var entrance: int = _entrance_at(player.global_position)
	if entrance == -1 or _blocked.has(player.get_instance_id()):
		return false
	var departure: Vector2 = player.global_position
	var arrival: Vector2 = to_global(point_b if entrance == 0 else point_a)
	# Lock before moving/emitting signals, including reentrant callbacks.
	_blocked[player.get_instance_id()] = weakref(player)
	player.global_position = arrival
	player.velocity = Vector2.ZERO
	player.knockback_velocity = Vector2.ZERO
	player.set_trajectory(arrival, Vector2.ZERO)
	player.network_position_q = Vector2i(
		NetworkManager.quantize(arrival.x), NetworkManager.quantize(arrival.y)
	)
	play_transfer_effect(departure, arrival)
	player_teleported.emit(player, departure, arrival)
	return true


## Snapshot for a future match RPC / late join. Clients do not advance the cycle.
func get_open_state() -> Dictionary:
	return {
		"open": is_open, "remaining": _remaining, "revision": _revision,
		"point_a": to_global(point_a), "point_b": to_global(point_b),
	}


## Cosmetic state only. The caller must authenticate the server RPC sender.
## This never moves players or permits client-side teleportation.
func apply_open_state(state: Dictionary) -> bool:
	if _is_authoritative():
		return false
	if not state.get("open") is bool or not state.get("revision") is int:
		return false
	var remaining: Variant = state.get("remaining")
	if not (remaining is float or remaining is int):
		return false
	if not is_finite(float(remaining)) or float(remaining) < 0.0:
		return false
	if not state.get("point_a") is Vector2 or not state.get("point_b") is Vector2:
		return false
	var world_a: Vector2 = state["point_a"]
	var world_b: Vector2 = state["point_b"]
	if not world_a.is_finite() or not world_b.is_finite():
		return false
	var revision: int = state["revision"]
	if revision < 0 or revision < _received_revision:
		return false
	_received_revision = revision
	_remaining = float(remaining)
	point_a = to_local(world_a)
	point_b = to_local(world_b)
	var changed: bool = is_open != bool(state["open"])
	is_open = bool(state["open"])
	_revision = revision
	if changed:
		open_state_changed.emit(is_open)
	return true


## Local visual/audio hook, also usable by a future trusted teleport RPC.
func play_transfer_effect(departure: Vector2, arrival: Vector2) -> void:
	if not is_inside_tree() or not departure.is_finite() or not arrival.is_finite():
		return
	var flash: TransferFlash = TransferFlash.new()
	flash.top_level = true
	flash.departure = departure
	flash.arrival = arrival
	flash.z_index = 50
	add_child(flash)
	flash.global_position = Vector2.ZERO
	# Original synthesized chirp: a placeholder without imported assets.
	if _sound == null:
		_sound = _make_transfer_sound()
	var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	audio.stream = _sound
	audio.volume_db = -10.0
	if AudioServer.get_bus_index("SFX") >= 0:
		audio.bus = "SFX"
	flash.add_child(audio)
	audio.global_position = arrival
	audio.play()


func _make_transfer_sound() -> AudioStreamWAV:
	var sound: AudioStreamWAV = AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples: int = 3969 # 0.18 seconds.
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples * 2)
	for index: int in range(samples):
		var time: float = float(index) / float(sound.mix_rate)
		var progress: float = float(index) / float(samples)
		var envelope: float = minf(progress * 20.0, 1.0) * pow(1.0 - progress, 2.0)
		var wave: float = sin(TAU * (520.0 * time + 1800.0 * time * time))
		data.encode_s16(index * 2, int(wave * envelope * 18000.0))
	sound.data = data
	return sound


class TransferFlash extends Node2D:
	var departure: Vector2
	var arrival: Vector2
	var age: float = 0.0


	func _process(delta: float) -> void:
		age += delta
		if age >= 0.5:
			queue_free()
		else:
			queue_redraw()


	func _draw() -> void:
		var progress: float = clampf(age / 0.5, 0.0, 1.0)
		var alpha: float = 1.0 - progress
		var spark: Color = Color(1.0, 0.85, 0.18, alpha)
		if progress < 0.35:
			draw_line(departure, arrival, Color(0.25, 0.9, 1.0, alpha * 0.7), 5.0, true)
		for center: Vector2 in [departure, arrival]:
			draw_circle(center, 18.0 * alpha, Color(1.0, 1.0, 1.0, alpha))
			draw_arc(center, 20.0 + progress * 55.0, 0.0, TAU, 40,
				Color(0.08, 0.03, 0.18, alpha), 10.0, true)
			draw_arc(center, 20.0 + progress * 55.0, 0.0, TAU, 40, spark, 5.0, true)
			for index: int in range(8):
				var direction: Vector2 = Vector2.RIGHT.rotated(float(index) * TAU / 8.0)
				draw_line(center + direction * (25.0 + progress * 50.0),
					center + direction * (35.0 + progress * 60.0), spark, 3.0, true)
