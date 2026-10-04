# tools/_probe_dock_pos.gd —— 量「码头放下去」和「地形画在哪」到底差多少
#
# 背景：`_dock_cell()` 用 `_land_set`（数据）挑了一格陆地，`dock.setup()` 用
#   `Farm.grid_origin + cell*16` 算世界坐标。截图里码头却立在海中间。
#   这个探针把两边的真实数字全打出来，看到底是哪一环偏了。
extends Node

var game: Node = null

func _ready() -> void:
	Slaves.slaves = []
	Slaves.count = 0
	TimeManager.time_running = false
	SaveManager.enabled = false
	game = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame

	var gl: TileMapLayer = game.get_node("GrassTileMapLayer")
	var wl: TileMapLayer = game.get_node("WaterTileMapLayer")
	var dk: Node2D = game.get("dock")
	var pl: Node2D = game.get("player")

	print("---- 基础 ----")
	print("Game.global_position      = %s" % str((game as Node2D).global_position))
	print("Game.position             = %s" % str((game as Node2D).position))
	print("Farm.grid_origin          = %s" % str(Farm.grid_origin))
	print("Farm.TILE_SIZE            = %d" % Farm.TILE_SIZE)
	print("GrassLayer.global_position= %s  position=%s" % [str(gl.global_position), str(gl.position)])
	print("WaterLayer.global_position= %s  position=%s" % [str(wl.global_position), str(wl.position)])
	print("GrassLayer.tile_size      = %s" % str(gl.tile_set.tile_size))

	print("\n---- 码头 ----")
	print("码头 anchor 格            = %s" % str(dk.anchor))
	print("码头 node.position        = %s" % str(dk.position))
	print("码头 node.global_position = %s" % str(dk.global_position))
	print("反推 grid_origin          = %s" % str(dk.global_position - Vector2(
		dk.anchor.x * 16 + 8, dk.anchor.y * 16 + 8)))

	print("\n---- 两边对不对得上 ----")
	# 关卡数据这一侧：这一格是陆是水
	for c in [Vector2i(45, 17), Vector2i(44, 17), Vector2i(43, 17), Vector2i(40, 17),
			Vector2i(35, 17), Vector2i(33, 17), Vector2i(32, 17), Vector2i(30, 17)]:
		print("  数据: %s  is_water=%s" % [str(c), str(game.is_water(c))])
	# 渲染这一侧：这一格上到底有没有草地/水瓦片
	print("")
	for c in [Vector2i(45, 17), Vector2i(44, 17), Vector2i(43, 17), Vector2i(40, 17),
			Vector2i(35, 17), Vector2i(33, 17), Vector2i(32, 17), Vector2i(30, 17)]:
		print("  渲染: %s  草地瓦片=%d  水瓦片=%d" % [str(c),
			gl.get_cell_source_id(c), wl.get_cell_source_id(c)])

	print("\n---- 用图层自己的换算反查码头 ----")
	# 若两边一致，码头世界坐标换算回格子应该正好是 anchor
	var back := gl.local_to_map(gl.to_local(dk.global_position))
	print("码头位置 -> grass 图层格子 = %s (期望 %s)" % [str(back), str(dk.anchor)])
	print("草地瓦片覆盖的格子范围     = %s" % str(_used_rect(gl)))
	print("水瓦片覆盖的格子范围       = %s" % str(_used_rect(wl)))

	print("\n---- 玩家 ----")
	print("player.global_position    = %s" % str(pl.global_position))

	get_tree().quit()

func _used_rect(layer: TileMapLayer) -> String:
	var cells := layer.get_used_cells()
	if cells.is_empty():
		return "(空)"
	var mn := cells[0]
	var mx := cells[0]
	for c in cells:
		mn = Vector2i(mini(mn.x, c.x), mini(mn.y, c.y))
		mx = Vector2i(maxi(mx.x, c.x), maxi(mx.y, c.y))
	return "x %d..%d  y %d..%d  (%d 格)" % [mn.x, mx.x, mn.y, mx.y, cells.size()]
