extends Node

## Небольшой локальный каталог бойцов. Все значения хранятся в данных, поэтому
## новые бойцы добавляются без переписывания логики матча.
const DEFAULT_ID: String = "shelly"

var brawlers: Dictionary = {
	"shelly": {
		"name": "ШЕЛЛИ",
		"role": "Штурмовик",
		"description": "Дробовик и супер-выстрел, который отбрасывает врагов.",
		"color": Color("d95768"),
		"max_health": 115.0,
		"speed": 500.0,
		"super_name": "СУПЕР: РАЗНОС",
		"super_description": "Широкая волна урона и отбрасывание.",
	},
	"colt": {
		"name": "КОЛЬТ",
		"role": "Стрелок",
		"description": "Быстрый стрелок. Супер выпускает серию усиленных пуль.",
		"color": Color("4d8fe8"),
		"max_health": 95.0,
		"speed": 540.0,
		"super_name": "СУПЕР: ШКВАЛ",
		"super_description": "Серия из семи усиленных пуль вперёд.",
	},
	"spike": {
		"name": "СПАЙК",
		"role": "Контроль",
		"description": "Кристальная энергия лечит союзника и задевает врагов вокруг.",
		"color": Color("75c85a"),
		"max_health": 100.0,
		"speed": 470.0,
		"super_name": "СУПЕР: САД",
		"super_description": "Восстановление здоровья и урон по области.",
	},
}

func get_brawler(brawler_id: String) -> Dictionary:
	var data: Dictionary = brawlers.get(brawler_id, brawlers[DEFAULT_ID]) as Dictionary
	return data.duplicate(true)

func has_brawler(brawler_id: String) -> bool:
	return brawlers.has(brawler_id)

func get_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in brawlers.keys():
		result.append(str(key))
	return result
