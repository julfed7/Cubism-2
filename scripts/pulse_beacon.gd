extends Node2D
class_name PulseBeacon

## Server-only, one-shot detection. After adding the scene to the match, call
## emit_pulse(player). Inventory consumption and spawning belong to the caller.
@export var detection_radius: float = 280.0
@export var detection_duration: float = 4.0

var owner_peer_id: int = 0
var _emitted: bool = false
var _remaining: float = 0.0
var _targets: Array[WeakRef] = []


func _ready() -> void:
	set_process(false)


func emit_pulse(player: GamePlayer) -> bool:
	if not is_inside_tree() or _emitted:
		return false
	if not NetworkManager.is_single and not NetworkManager.is_host:
		return false
	if not is_instance_valid(player) or not player.is_inside_tree() or player._dead or player.hp <= 0.0:
		return false
	if not is_finite(detection_radius) or not is_finite(detection_duration):
		return false
	if detection_radius <= 0.0 or detection_duration <= 0.0:
		return false
	owner_peer_id = player.get_multiplayer_authority()
	global_position = player.global_position
	_emitted = true
	_remaining = detection_duration
	# Sample once: walking into the area after this instant does not reveal you.
	# Keep is_hidden unchanged; it is replicated to every participant.
	for node: Node in get_tree().get_nodes_in_group("player"):
		var target: GamePlayer = node as GamePlayer
		if target == null or target == player or target.get_multiplayer_authority() == owner_peer_id:
			continue
		if target._dead or target.hp <= 0.0 or not target.is_in_stealth_bush():
			continue
		if global_position.distance_to(target.global_position) > detection_radius:
			continue
		target.grant_pulse_detection(owner_peer_id, get_instance_id(), detection_duration)
		_targets.append(weakref(target))
	set_process(true)
	return true


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()


func _exit_tree() -> void:
	# Also clear detections if the match removes the beacon early.
	for reference: WeakRef in _targets:
		var target: GamePlayer = reference.get_ref() as GamePlayer
		if is_instance_valid(target) and target.is_inside_tree():
			target.revoke_pulse_detection(owner_peer_id, get_instance_id())
	_targets.clear()
