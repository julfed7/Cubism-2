extends Node
class_name Inventory

signal changed

@export var max_slots: int = 9
var slots: Array[Dictionary] = []
var selected_slot: int = -1
var owner_player: Node

func _ready() -> void:
	owner_player = get_parent()
	slots.resize(max_slots)
	for i: int in range(max_slots):
		slots[i] = {}
	changed.emit()

func add_item(item_id: String, amount: int = 1) -> bool:
	var data: Dictionary = ItemDB.get_item(item_id)
	if data.is_empty() or amount <= 0:
		return false
	var type_name: String = str(data.get("type", ""))
	var weapon_type: String = str(data.get("weapon_type", type_name))
	if type_name == "weapon" or weapon_type in ["pistol", "smg", "shotgun", "rifle"]:
		return _add_weapon(item_id)
	if data.get("stackable", false):
		return _add_stackable(item_id, amount, data)
	var empty_index: int = _find_empty_slot()
	if empty_index == -1:
		return false
	slots[empty_index] = {"id": item_id, "amount": amount}
	changed.emit()
	return true

func _add_stackable(item_id: String, amount: int, data: Dictionary) -> bool:
	var stack_limit: int = maxi(1, int(data.get("max_stack", 1)))
	var capacity: int = 0
	for slot: Dictionary in slots:
		if str(slot.get("id", "")) == item_id:
			capacity += maxi(0, stack_limit - int(slot.get("amount", 0)))
		elif slot.is_empty():
			capacity += stack_limit
	if capacity < amount:
		return false
	var remaining: int = amount
	for i: int in range(max_slots):
		if str(slots[i].get("id", "")) != item_id:
			continue
		var stored: int = int(slots[i].get("amount", 0))
		var space: int = maxi(0, stack_limit - stored)
		if space == 0:
			continue
		var added: int = mini(space, remaining)
		slots[i]["amount"] = stored + added
		remaining -= added
		if remaining == 0:
			changed.emit()
			return true
	while remaining > 0:
		var empty_index: int = _find_empty_slot()
		var added: int = mini(stack_limit, remaining)
		slots[empty_index] = {"id": item_id, "amount": added}
		remaining -= added
	changed.emit()
	return true

func _add_weapon(item_id: String) -> bool:
	for slot: Dictionary in slots:
		if str(slot.get("id", "")) == item_id:
			return false
	var target_index: int = _find_empty_slot()
	if target_index == -1:
		return false
	slots[target_index] = {"id": item_id, "amount": 1}
	if owner_player != null and owner_player.has_method("on_weapon_picked"):
		owner_player.on_weapon_picked(item_id)
	changed.emit()
	return true

func _find_empty_slot() -> int:
	for i: int in range(max_slots):
		if slots[i].is_empty():
			return i
	return -1

func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var available: int = 0
	for slot: Dictionary in slots:
		if str(slot.get("id", "")) == item_id:
			available += int(slot.get("amount", 0))
	if available < amount:
		return false
	var remaining: int = amount
	for i: int in range(max_slots):
		if str(slots[i].get("id", "")) != item_id:
			continue
		var stored: int = int(slots[i].get("amount", 0))
		var removed: int = mini(stored, remaining)
		stored -= removed
		remaining -= removed
		if stored <= 0:
			slots[i] = {}
		else:
			slots[i]["amount"] = stored
	changed.emit()
	return true

func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= max_slots:
		return {}
	return slots[index].duplicate(true)

func select_slot(index: int) -> void:
	if index < 0 or index >= max_slots or selected_slot == index:
		return
	selected_slot = index
	changed.emit()

func get_selected() -> Dictionary:
	return get_slot(selected_slot)

func make_snapshot() -> Array:
	var result: Array = []
	for slot: Dictionary in slots:
		result.append(slot.duplicate(true))
	return result

func apply_snapshot(snapshot: Array, new_selected_slot: int) -> void:
	slots.resize(max_slots)
	for i: int in range(max_slots):
		if i < snapshot.size() and snapshot[i] is Dictionary:
			slots[i] = (snapshot[i] as Dictionary).duplicate(true)
		else:
			slots[i] = {}
	selected_slot = new_selected_slot if new_selected_slot >= 0 and new_selected_slot < max_slots else -1
	changed.emit()

func use_item(index: int) -> void:
	var slot: Dictionary = get_slot(index)
	if slot.is_empty() or owner_player == null:
		return
	var item_id: String = str(slot.get("id", ""))
	var data: Dictionary = ItemDB.get_item(item_id)
	match str(data.get("type", "")):
		"healing":
			owner_player.heal(float(data.get("heal", 50.0)))
			remove_item(item_id, 1)
		"ammo":
			owner_player.add_reserve_ammo(str(data.get("ammo_for", "")), int(slot.get("amount", 0)))
			remove_item(item_id, int(slot.get("amount", 0)))
		"currency":
			owner_player.coins += int(slot.get("amount", 0))
			remove_item(item_id, int(slot.get("amount", 0)))
		"weapon", "pistol", "smg", "shotgun", "rifle":
			if owner_player.has_method("on_weapon_picked"):
				owner_player.on_weapon_picked(item_id)
