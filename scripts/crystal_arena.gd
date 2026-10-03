extends Node2D

const TILE_SIZE: int = 50
const WIDTH: int = 28
const HEIGHT: int = 16
@onready var tile_map: TileMapLayer = $TileMapLayer

func _ready() -> void:
    _build_arena()
    queue_redraw()

func _build_arena() -> void:
    for y: int in range(-8, 8):
        for x: int in range(-14, 14):
            var is_border: bool = x == -14 or x == 13 or y == -8 or y == 7
            var atlas: Vector2i = Vector2i(5, 6) if is_border else Vector2i(1 + posmod(x + y, 3), 1)
            tile_map.set_cell(Vector2i(x, y), 0, atlas, 0)
    for cell: Vector2i in [Vector2i(-6, -3), Vector2i(5, -3), Vector2i(-6, 3), Vector2i(5, 3)]:
        tile_map.set_cell(cell, 0, Vector2i(5, 6), 0)

func _draw() -> void:
    for point: Vector2 in [Vector2(-275, -125), Vector2(275, -125), Vector2(-275, 125), Vector2(275, 125)]:
        draw_circle(point, 72.0, Color(0.12, 0.52, 0.70, 0.18))
        draw_arc(point, 72.0, 0.0, TAU, 32, Color(0.31, 0.87, 1.0, 0.65), 3.0)
    draw_circle(Vector2.ZERO, 104.0, Color(0.28, 0.15, 0.62, 0.18))
    draw_arc(Vector2.ZERO, 104.0, 0.0, TAU, 48, Color(0.65, 0.48, 1.0, 0.7), 3.0)
