# tools/_probe_mapdump.gd —— 把岛地形打成 ASCII 图（选码头用）
#
# 目的：`_dock_cell()` 只看「是不是陆地 + 东边有没有水」，结果挑到了外海
#   一块噪声切出来的孤零零小沙洲。先把地图画出来，才知道岸到底长什么样。
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

	var land: Dictionary = game.get("_land_set")
	var water: Dictionary = game.get("_water_set")
	print("陆地 %d 格 / 水 %d 格" % [land.size(), water.size()])

	# 只画东半侧（码头在河东），y 从岛的北边往上留点余量
	var x0 := 24
	var x1 := 58
	var y0 := -4
	var y1 := 40
	print("\n列头: 每 10 格标一次 x")
	var head := "     "
	for x in range(x0, x1 + 1):
		head += str(x % 10)
	print(head)
	for y in range(y0, y1 + 1):
		var line := "%4d " % y
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			if land.has(c):
				# 陆地：靠东是岸的用 A 标出来（一眼看出可选的码头位）
				line += "A" if water.has(Vector2i(x + 1, y)) else "#"
			elif water.has(c):
				line += "."
			else:
				line += " "
		print(line)

	# 每个「东边是水」的陆地格，数一下它 5x5 圈内有多少陆地
	# —— 数目小的就是孤岛碎块，不能当码头
	print("\n候选（cx>=37 且东边是水）：格子 -> 5x5 内陆地数")
	var rows := []
	for c in land.keys():
		if int(c.x) < 37:
			continue
		if not water.has(Vector2i(int(c.x) + 1, int(c.y))):
			continue
		var n := 0
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if land.has(Vector2i(int(c.x) + dx, int(c.y) + dy)):
					n += 1
		rows.append([n, int(c.x), int(c.y)])
	rows.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] > b[1])
	for r in rows.slice(0, 14):
		print("  陆地邻居 %2d  ->  (%d, %d)" % [r[0], r[1], r[2]])
	get_tree().quit()
