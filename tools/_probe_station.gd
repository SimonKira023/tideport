extends Node
# e30o/e30f 验证探针: 工作台重叠拦截 + 云层回收判定
# 跑法: Godot_console.exe --path . res://tools/_probe_station.tscn
const TS := 16
var _pass := 0
var _fail := 0

func chk(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _ready() -> void:
	SaveManager.enabled = false          # 别碰玩家真档
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = g.get("player")
	var wb: ItemData = load("res://item/workbench.tres")
	# ===== e30o: footprint 拦截 =====
	var anchor := Vector2i(2, 2)
	if Structures.has_station(anchor):
		Structures.remove(anchor)
		await get_tree().process_frame
	chk(Structures.place(anchor, Structures.KIND_COOP), "摆下一座鸡舍 (锚点 2,2)")
	await get_tree().process_frame
	chk(g.station_footprint_blocked(Vector2i(3, 2)), "鸡舍身体格 (3,2) 被 footprint 拦下")
	chk(g.station_footprint_blocked(Vector2i(-1, 1)), "鸡舍地基边角 (-1,1) 被拦下")
	chk(not g.station_footprint_blocked(Vector2i(20, 20)), "远处空地 (20,20) 不拦")
	# ===== e30o: 手持工作台点身体格 =====
	Inventory.add_item(wb, 3)
	var n0 := Inventory.count_item(wb)
	player.current_item = wb
	player._place_station(Vector2i(3, 2))
	chk(not Structures.has_station(Vector2i(3, 2)), "点身体格: 工作台没摆出来")
	chk(Inventory.count_item(wb) == n0, "点身体格: 背包没扣")
	# ===== e30o: 脚底下不能摆 =====
	var cs: CollisionShape2D = player.get_node("CollisionShape2D")
	player.global_position = Farm.grid_origin \
		+ Vector2(10 * TS + TS * 0.5, 10 * TS + TS * 0.5) - cs.position
	var pc: Vector2i = g._world_to_cell(player.global_position)
	chk(pc == Vector2i(10, 10), "玩家落在 (10,10)")
	player._place_station(Vector2i(10, 10))
	chk(not Structures.has_station(Vector2i(10, 10)), "点脚底下: 工作台没摆出来")
	# ===== 正常空地能摆 =====
	var spot := Vector2i(-1, -1)
	for y in range(4, 40):
		for x in range(6, 40):
			var c := Vector2i(x, y)
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if Structures.has_station(c + Vector2i(dx, dy)):
						near = true
			if g.is_tillable(c) and not near \
					and not g.station_footprint_blocked(c) and c != pc:
				spot = c
				break
		if spot.x >= 0:
			break
	chk(spot.x >= 0, "找到一块可摆的空地 %s" % spot)
	if spot.x >= 0:
		player._place_station(spot)
		chk(Structures.has_station(spot), "正常空地: 工作台摆出来了")
		chk(Inventory.count_item(wb) == n0 - 1, "正常摆放: 背包扣 1")
	# ===== e30f: 云层 box 跟随 + 左边界回收 =====
	var clouds: Node2D = g.get_node("CloudLayer")
	for i in 12:
		await get_tree().process_frame
	if clouds.get_child_count() == 0:
		chk(clouds._view_rect().size != Vector2.ZERO, "e30f: 相机视野就位")
		clouds._spawn_cloud(true)          # 开场云是 call_deferred 撒的, 探针跑太快就手动补一朵
		await get_tree().process_frame
	var c0: Node2D = null
	for ch in clouds.get_children():
		if ch is Node2D:
			c0 = ch
			break
	chk(c0 != null, "云层里有云")
	if c0 != null:
		var box: Rect2 = c0.get_meta("box")
		chk(box.position.distance_to(c0.position) < 1.0, "e30f: box 跟着云走 (meta 写回)")
		var view: Rect2 = clouds._view_rect()
		c0.set_meta("entered", true)
		c0.position = Vector2(view.position.x - 300.0, view.position.y + 40.0)
		for i in 6:
			await get_tree().process_frame
		chk(not is_instance_valid(c0), "e30f: 从左边界完全飘出的云被回收")
	print("STATION PROBE: pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
