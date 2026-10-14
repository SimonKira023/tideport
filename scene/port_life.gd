# 丰收后的小餐桌, 傍晚闲暇的伙伴会聚过来, 不占劳动也不额外扣资源。
extends Node2D

var _game: Node
var _cell := Vector2i.ZERO
var _placed := false

func _ready() -> void:
	add_to_group("port_life")
	_game = get_tree().get_first_node_in_group("game")
	Quests.changed.connect(_refresh)
	TimeManager.time_tick.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not _placed and _game != null:
		var house: Node2D = _game.get_node_or_null("House")
		if house != null:
			var base: Vector2i = _game._world_to_cell(house.global_position)
			for radius in range(4, 13):
				for offset in [Vector2i(-radius, 4), Vector2i(radius, 4), Vector2i(-4, radius), Vector2i(4, radius)]:
					var test: Vector2i = base + offset
					if _free_cell(test) and _free_cell(test + Vector2i.LEFT) and _free_cell(test + Vector2i.RIGHT):
						_cell = test
						global_position = Farm.grid_origin + Vector2(_cell) * Farm.TILE_SIZE
						_placed = true
						break
				if _placed:
					break
	visible = _placed and Quests.has_milestone("ms_harvest") and Slaves.count > 0
	queue_redraw()

func gathering() -> bool:
	return visible and TimeManager.hour >= 18 and TimeManager.hour < 20 and not Voyage.traveling

func seat_for(index: int) -> Vector2:
	var side := -1 if index % 2 == 0 else 1
	var offset := Vector2i(side, (index / 2) % 3 - 1)
	return Farm.grid_origin + Vector2(_cell + offset) * Farm.TILE_SIZE

func seat_available(pos: Vector2) -> bool:
	return _free_cell(Vector2i((pos - Farm.grid_origin) / Farm.TILE_SIZE))

func _free_cell(cell: Vector2i) -> bool:
	return _game != null and _game._land_set.has(cell) and not _game.is_water(cell) \
		and not Structures.is_blocked(cell) and not _game.station_footprint_blocked(cell) \
		and not Trees.is_blocked(cell) and not OreVein.is_blocked(cell) and not Farm.is_tilled(cell)

func _draw() -> void:
	draw_rect(Rect2(-12, -14, 24, 12), Color(0.40, 0.27, 0.16))
	draw_rect(Rect2(-12, -14, 24, 2), Color(0.64, 0.46, 0.28))
	draw_rect(Rect2(-10, -2, 3, 3), Color(0.28, 0.18, 0.12))
	draw_rect(Rect2(7, -2, 3, 3), Color(0.28, 0.18, 0.12))
	if gathering():
		for x in [-7, 7]:
			draw_circle(Vector2(x, -8), 3, Color(0.90, 0.85, 0.68))
			draw_circle(Vector2(x, -8), 1, Color(0.67, 0.37, 0.17))
