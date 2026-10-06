extends Node
# tools/_probe_bridge.gd —— 桥实机探针: 先看现状, 改完再跑同一份截图对比。
# 跑法（必须带窗口, 不能 --headless）:
#   & $exe --path . res://tools/_probe_bridge.tscn
# 产出: outputs/bridge_*.png + 控制台碰撞断言
#
# 站点:
#   [1] 桥面中行道 —— 整桥外观
#   [2] 南行道 (y+1) —— 角色应在南护栏「后面」, 透过栏杆孔看得见
#   [3] 桥南侧 (y+2) —— 角色在护栏「前面」, 应盖住护栏
#   [4] 北行道 (y-1) —— 整桥外观
#   [5] 碰撞 —— 从南行道往下走必须被护栏根薄墙挡住; 东西向过桥必须畅通

const OUT := "res://outputs"
var fails := 0
var g: Node2D
var player: Node2D
var cam: Camera2D
var by := 0          # 桥所在行
var bx0 := 0
var bx1 := 0

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Weather.current = Weather.SUNNY
	TimeManager.hour = 10
	TimeManager.minute = 0
	TimeManager.time_running = false

	g = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	player = g.get_node("Player")
	cam = player.get_node("Camera2D")
	cam.position_smoothing_enabled = false
	cam.zoom = Vector2(3, 3)          # 放大 3 倍看栏杆细节

	by = g.BRIDGE_ROWS[0]
	bx0 = g._bridge_x0(by)
	bx1 = g._bridge_x1(by)
	var mx: int = (bx0 + bx1) / 2
	print("[桥探针] 桥行 %d, x %d..%d, 中列 %d" % [by, bx0, bx1, mx])

	await _stand_and_shot(Vector2i(mx, by), "1_on_deck", "桥面中行道")
	await _stand_and_shot(Vector2i(mx, by - 1), "4_north_lane", "北行道")
	await _stand_and_shot(Vector2i(mx, by + 1), "2_behind_rail", "南行道(应在护栏后)")
	await _stand_and_shot(Vector2i(mx, by + 2), "3_south_of_rail", "桥南侧(应在护栏前)")
	_collision_checks(mx)

	print("\n[桥探针] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

func _stand_and_shot(cell: Vector2i, nm: String, label: String) -> void:
	player.global_position = Farm.grid_origin + Vector2(cell) * 16.0 + Vector2(8, 15)
	cam.reset_smoothing()
	cam.force_update_scroll()
	for i in 4:                                   # 等物理帧刷游泳状态
		await get_tree().physics_frame
	var in_water: bool = player.get("_in_water")
	print("  [状态] %s: 格 %s, _in_water=%s" % [label, str(cell), str(in_water)])
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		img.save_png(ProjectSettings.globalize_path("%s/bridge_%s.png" % [OUT, nm]))
		print("  [shot] bridge_%s.png  (%s)" % [nm, label])
	else:
		fails += 1
		print("  [!!] 截图失败: viewport 纹理为空 (%s)" % label)

func _collision_checks(mx: int) -> void:
	print("\n========== [5] 碰撞 ==========")
	# 南行道往下 (南) 顶护栏根: 从 (mx, by+1) 格底往下挪 12px, 必须走不完
	var feet0: Vector2 = Farm.grid_origin + Vector2(mx, by + 1) * 16.0 + Vector2(8, 15)
	player.global_position = feet0
	await get_tree().physics_frame
	var hit: KinematicCollision2D = player.move_and_collide(Vector2(0, 12))
	var moved_s: float = player.global_position.y - feet0.y
	_ck(hit != null or moved_s < 11.0, "南护栏根挡人 (向下位移 %.1fpx, 应 < 12)" % moved_s)
	# 北行道往上 (北) 顶护栏根
	player.global_position = Farm.grid_origin + Vector2(mx, by - 1) * 16.0 + Vector2(8, 1)
	await get_tree().physics_frame
	hit = player.move_and_collide(Vector2(0, -12))
	var moved_n: float = player.global_position.y - (Farm.grid_origin.y + (by - 1) * 16.0 + 1)
	_ck(hit != null or moved_n > -11.0, "北护栏根挡人 (向上位移 %.1fpx, 应 > -12)" % moved_n)
	# 东西向过桥必须畅通: 从桥西头引道走到东头引道
	player.global_position = Farm.grid_origin + Vector2(bx0 - 1, by) * 16.0 + Vector2(8, 8)
	await get_tree().physics_frame
	var blocked := false
	for i in (bx1 - bx0 + 3) * 2:
		var h: KinematicCollision2D = player.move_and_collide(Vector2(8, 0))
		if h != null:
			blocked = true
			break
	_ck(not blocked, "东西向过桥全程畅通")
