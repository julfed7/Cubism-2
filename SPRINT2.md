# Спринт 2 — структура и полный код

Проект обновлён на месте. Для TileMapLayer нужен Godot 4.3 или новее; проверено в Godot 4.7.2.

Кнопки Levels 1 и 2 загружают Island и City. Прямой запуск Game использует экспортированное map_scene (по умолчанию Island). Индексы MapManager: 0 и 1. load_map() вызывается после добавления Game в дерево; при вызове из физического сигнала используйте call_deferred("load_map", ...).

JSON не загружается, генерации/рисования клеток кодом нет. Существующие клетки Island сохранены без изменения. City оставлена пустой со спавном.

TileSet перенесён из tilesets/top-down-shooter.tres в tilemaps/tileset.tres. Удалены определения за границами атласа: допустимы x=0..25, y=0..18 для изображения 1325×968, тайла 50×50 и separation 1×1. Коллизии допустимых тайлов не менялись. Исходная копия сохранена в рабочем резерве.

Слои коллизий: 1 World (стены назначайте в TileSet), 2 Player, 3 Zombie. Сундук обнаруживает только слой Player. Урон и сеть не добавлены. WASD и стрелки уже были в Input Map, сохранены.

```text
Game (Node2D) — game.gd
├── MapContainer (Node2D)
├── Player (CharacterBody2D) — player.gd
│   ├── Sprite2D → sprites/player.png
│   ├── CollisionShape2D → RectangleShape2D(50, 50)
│   └── Camera2D → smoothing: true, speed: 5.0
└── UI (CanvasLayer)
    └── HUD (Control)
        └── Exit (Button)

Island (Node2D)
├── TileMapLayer → tilemaps/tileset.tres (сохранены нарисованные клетки)
├── PlayerSpawn (экземпляр PlayerSpawn.tscn)
├── Chest1 (экземпляр Chest.tscn)
├── Chest2 (экземпляр Chest.tscn)
├── Zombie1 (экземпляр Zombie.tscn)
└── Zombie2 (экземпляр Zombie.tscn)

City (Node2D)
├── TileMapLayer → tilemaps/tileset.tres (пустой)
└── PlayerSpawn (экземпляр PlayerSpawn.tscn)

Chest (Area2D) — chest.gd
├── Sprite2D (коричневая заглушка 50×50)
└── CollisionShape2D (50×50)

Zombie (CharacterBody2D) — zombie.gd
├── Sprite2D (зелёная заглушка 50×50)
└── CollisionShape2D (50×50)

PlayerSpawn (Marker2D) — player_spawn.gd, группа player_spawn

```

## Autoload

- GameState → autoloads/GameState.gd
- NetworkManager → autoloads/NetworkManager.gd
- MapManager → scripts/map_manager.gd

## Проверка

Headless Godot: выбор карты и границы индексов, спавн, сохранение игрока, удаление старой карты, повторная загрузка объектов, диагональная скорость 200, движение зомби, подбор сундука — PASS.

## scripts/game.gd

```gdscript
extends Node2D

@export var map_scene: PackedScene = preload("res://scenes/maps/Island.tscn")

func _ready() -> void:
	# Выбор из меню применяется один раз; прямой запуск использует map_scene.
	var selected_level: int = GameState.current_level
	GameState.current_level = 0
	if selected_level > 0:
		var selected_map: PackedScene = MapManager.get_map_by_index(selected_level - 1)
		if selected_map != null:
			map_scene = selected_map
	load_map(map_scene)

func load_map(new_map: PackedScene) -> void:
	if new_map == null:
		push_warning("Карта не задана")
		return
	var instance: Node = new_map.instantiate()
	if not instance is Node2D:
		instance.free()
		push_error("Корень карты должен быть Node2D")
		return
	for child in $MapContainer.get_children():
		$MapContainer.remove_child(child)
		child.queue_free()
	map_scene = new_map
	$MapContainer.add_child(instance)
	# Ищем спавн только внутри новой карты, а не среди старых узлов.
	var spawn: Node2D = _find_spawn(instance)
	$Player.velocity = Vector2.ZERO
	$Player.global_position = spawn.global_position if spawn != null else instance.global_position
	if spawn == null:
		push_warning("В карте нет player_spawn: использован центр карты")
	$Player/Camera2D.reset_smoothing()

func _find_spawn(node: Node) -> Node2D:
	if node is Node2D and node.is_in_group("player_spawn"):
		return node as Node2D
	for child in node.get_children():
		var found: Node2D = _find_spawn(child)
		if found != null:
			return found
	return null

func _on_exit_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

```

## scripts/map_manager.gd

```gdscript
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

```

## scripts/player.gd

```gdscript
extends CharacterBody2D

@export var speed: float = 200.0

func _ready() -> void:
	add_to_group("player")

func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction.normalized() * speed
	move_and_slide()

```

## scripts/chest.gd

```gdscript
extends Area2D

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not is_queued_for_deletion():
		print("Подобран сундук")
		queue_free()

```

## scripts/zombie.gd

```gdscript
extends CharacterBody2D

@export var speed: float = 100.0

func _physics_process(_delta: float) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		return
	velocity = global_position.direction_to(player.global_position) * speed
	move_and_slide()

```

## scripts/player_spawn.gd

```gdscript
extends Marker2D

func _ready() -> void:
	add_to_group("player_spawn")

```

## scripts/level_select.gd

```gdscript
extends Control

func _on_level_1_pressed() -> void:
	_open_level(1)

func _on_level_2_pressed() -> void:
	_open_level(2)

func _open_level(level: int) -> void:
	GameState.current_level = level
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

```
