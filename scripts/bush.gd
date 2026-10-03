extends Area2D
class_name StealthBush

var _players_inside: Array[GamePlayer] = []

func _ready() -> void:
	add_to_group("stealth_bush")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	for body: Node2D in get_overlapping_bodies():
		_on_body_entered(body)
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if not body is GamePlayer:
		return
	var player := body as GamePlayer
	if _players_inside.has(player):
		return
	_players_inside.append(player)
	player.enter_stealth_bush(self)

func _on_body_exited(body: Node2D) -> void:
	if not body is GamePlayer:
		return
	var player := body as GamePlayer
	_players_inside.erase(player)
	if is_instance_valid(player):
		player.exit_stealth_bush(self)

func _exit_tree() -> void:
	for player: GamePlayer in _players_inside:
		if is_instance_valid(player):
			player.exit_stealth_bush(self)
	_players_inside.clear()

func _draw() -> void:
	# Процедурная графика не требует отдельного ассета и хорошо масштабируется.
	draw_set_transform(Vector2(0.0, 18.0), 0.0, Vector2(1.0, 0.68))
	draw_circle(Vector2(0.0, 4.0), 88.0, Color(0.04, 0.16, 0.08, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(-58.0, 10.0), 39.0, Color("245c35"))
	draw_circle(Vector2(-20.0, -8.0), 51.0, Color("347c42"))
	draw_circle(Vector2(27.0, -15.0), 50.0, Color("2d713c"))
	draw_circle(Vector2(67.0, 10.0), 35.0, Color("205a34"))
	draw_circle(Vector2(-42.0, -28.0), 31.0, Color("4e964b"))
	draw_circle(Vector2(3.0, -42.0), 38.0, Color("56a34e"))
	draw_circle(Vector2(43.0, -34.0), 30.0, Color("438c45"))
	draw_circle(Vector2(-63.0, 23.0), 20.0, Color("173f2b"))
	draw_circle(Vector2(55.0, 28.0), 21.0, Color("173f2b"))
