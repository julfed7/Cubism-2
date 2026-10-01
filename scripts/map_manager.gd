extends Node

var maps: Array[PackedScene] = [
	preload("res://scenes/maps/Island.tscn"),
	preload("res://scenes/maps/City.tscn")
]

func get_map_by_index(i: int) -> PackedScene:
	if i < 0 or i >= maps.size():
		return null
	return maps[i]

func get_random_map() -> PackedScene:
	if maps.is_empty():
		return null
	return maps[randi_range(0, maps.size() - 1)]
