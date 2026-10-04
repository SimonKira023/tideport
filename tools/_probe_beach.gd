# tools/_probe_beach.gd —— 沙滩 + 海浪视觉探针（只印事实 + 截图，不下结论）
# 截 4 张图到 outputs/：
#   probe_beach_spawn_close  出生点特写（实心沙杂点 + 湿沙带 + 朝草淡出带）
#   probe_beach_spawn_wide   出生点广角（整片沙滩 + 岸线渐变）
#   probe_waves_t0 / t1      贴岸水格白浪线（隔 1.5s 两张，浪线位置应不同）
extends Node

var game: Node = null

func _ready() -> void:
	SaveManager.enabled = false
	TimeManager.hour = 10
	TimeManager.time_running = true
	game = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame

	var pl: Node2D = game.get("player")
	var cam: Camera2D = pl.get_node("Camera2D")
	cam.position_smoothing_enabled = false

	var sand: Dictionary = game.get("_sand_set")
	var waves: Node2D = game.get_node("WavesLayer")
	print("[fact] 沙地格数=%d  出生格=%s  is_sand=%s  is_tillable=%s" % [
		sand.size(), str(game.SPAWN_CELL),
		str(game.is_sand(game.SPAWN_CELL)), str(game.is_tillable(game.SPAWN_CELL))])
	print("[fact] 浪线段数=%d" % waves._segs.size())

	# 坐标系体检：各层位置 + 出生格上到底铺了什么 tile
	var gridl: TileMapLayer = game.get("grid_layer")
	var waterl: TileMapLayer = game.get("water_layer")
	var beachl: TileMapLayer = game.get("beach_layer")
	print("[fact] grid pos=%s gpos=%s  water gpos=%s  beach pos=%s  Farm.grid_origin=%s" % [
		str(gridl.position), str(gridl.global_position),
		str(waterl.global_position), str(beachl.position), str(Farm.grid_origin)])
	print("[fact] SPAWN: 草src=%d 水src=%d  is_water=%s" % [
		gridl.get_cell_source_id(game.SPAWN_CELL),
		waterl.get_cell_source_id(game.SPAWN_CELL),
		str(game.is_water(game.SPAWN_CELL))])

	# 决定性对照：核心陆地中心格必是草地，先站那里截一张
	var core := Vector2i((game.ISLAND_FROM.x + game.ISLAND_TO.x) / 2 - 6,
		(game.ISLAND_FROM.y + game.ISLAND_TO.y) / 2)
	print("[fact] 核心对照格=%s is_water=%s" % [str(core), str(game.is_water(core))])
	_place(pl, core)
	cam.zoom = Vector2(4, 4)
	cam.reset_smoothing()
	await _snap("core_check")
	print("[fact] 核心对照: 玩家world=%s 反算格=%s" % [str(pl.global_position),
		str(_cell_of(pl.global_position))])

	# 1) 出生点特写
	_place(pl, game.SPAWN_CELL)
	cam.zoom = Vector2(4, 4)
	cam.reset_smoothing()
	await _snap("beach_spawn_close")

	# 2) 出生点广角
	cam.zoom = Vector2(1.2, 1.2)
	cam.reset_smoothing()
	await _snap("beach_spawn_wide")

	# 3) 找「沙地格 + 东边是草地」的格子：看朝草淡出带
	var edge_grass := _find_edge(sand, Vector2i(1, 0), true)
	if edge_grass != Vector2i(-999, -999):
		_place(pl, edge_grass)
		cam.zoom = Vector2(4, 4)
		cam.reset_smoothing()
		await _snap("beach_grass_edge")
		print("[fact] 草侧样格=%s" % str(edge_grass))

	# 4) 找「沙地格 + 西边是水」的格子：看湿沙带 + 白浪线
	var edge_water := _find_edge(sand, Vector2i(-1, 0), false)
	if edge_water != Vector2i(-999, -999):
		_place(pl, edge_water)
		cam.zoom = Vector2(5, 5)
		cam.reset_smoothing()
		await _snap("waves_t0")
		await get_tree().create_timer(1.5).timeout
		await _snap("waves_t1")
		print("[fact] 水侧样格=%s" % str(edge_water))

	get_tree().quit()

func _place(pl: Node2D, c: Vector2i) -> void:
	var origin: Vector2 = game.grid_layer.global_position   # ❗global 坐标要配 global 原点
	pl.global_position = origin + Vector2(c.x * 16 + 8, c.y * 16 + 8)
	pl.velocity = Vector2.ZERO

# 在沙地里找一格，其 dir 邻居是 want（true=陆地非沙 / false=水）
func _find_edge(sand: Dictionary, dir: Vector2i, want_land: bool) -> Vector2i:
	for c in sand.keys():
		var nb: Vector2i = c + dir
		if want_land:
			if game._land_set.has(nb) and not sand.has(nb):
				return c
		else:
			if game.is_water(nb):
				return c
	return Vector2i(-999, -999)

func _cell_of(w: Vector2) -> Vector2i:
	var local: Vector2 = w - Farm.grid_origin
	return Vector2i(floori(local.x / 16.0), floori(local.y / 16.0))

func _snap(tag: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var shot := tex.get_image()
	var out := "res://outputs/probe_%s.png" % tag
	shot.save_png(ProjectSettings.globalize_path(out))
	print("[probe] saved ", out)
