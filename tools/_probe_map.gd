extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var main = load("res://scene/game.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var g = main
	print("陆地 %d 格 / 水 %d 格（水占比 %.0f%%）" % [g._land_set.size(), g._water_set.size(),
		100.0 * g._water_set.size() / float(g._land_set.size() + g._water_set.size())])
	# 房子 5x6
	var house = main.get_node("House")
	var hc = Vector2i(int(floor((house.global_position.x - Farm.grid_origin.x) / 16.0)),
		int(floor((house.global_position.y - Farm.grid_origin.y) / 16.0)))
	var bad = []
	for dx in range(5):
		for dy in range(6):
			var c = hc + Vector2i(dx, dy)
			if g._water_set.has(c):
				bad.append(c)
	print("房子格子起点 %s，水里格 %s" % [str(hc), str(bad)])
	# 桥
	for y in g.BRIDGE_ROWS:
		var x0 = g._bridge_x0(y); var x1 = g._bridge_x1(y)
		var row = ""
		for x in range(x0 - 4, x1 + 5):
			row += "~" if g._water_set.has(Vector2i(x, y)) else "."
		var endL = not g._water_set.has(Vector2i(x0, y))
		var endR = not g._water_set.has(Vector2i(x1, y))
		print("桥 y=%d  x=%d..%d  两端是陆地: 左%s 右%s   该行: %s" % [y, x0, x1, endL, endR, row])
	# 栅格总览（每 3 格采样一个字符）
	print("=== 全图概览（每 2 格取 1，@陆地 .水 河/）===")
	for y in range(-24, 58, 2):
		var line = ""
		for x in range(-48, 64, 2):
			var c = Vector2i(x, y)
			if c.x < g.YARD_FROM.x or c.x > g.YARD_TO.x or c.y < g.YARD_FROM.y or c.y > g.YARD_TO.y:
				line += "?"
			elif g._is_river(c):
				line += "~"
			elif g._water_set.has(c):
				line += "."
			elif Farm.tilled.has(c):
				line += "@"
			else:
				line += "#"
		print("%3d %s" % [y, line])
	get_tree().quit()
