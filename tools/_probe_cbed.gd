# tools/_probe_cbed.gd —— c4 睡觉菜单 / c10 起床站位 / c11 屋前小径 画面验收探针
#
# 跑真实 game.tscn, 只截图不下结论, 输出到 res://outputs/:
#   1) probe_c11_path   屋前小径: 草地为基底 + 鹅卵石点缀
#   2) probe_c10_wake   屋内: 睡醒站在床脚边（不再挪回门口）
#   3) probe_c4_menu    床边按 F: 「今晚怎么睡」主菜单
#   4) probe_c4_hour    小睡挑时刻: 拨到 18 点的表盘 + 事件提示
extends Node

var game: Node = null
var player: Node2D = null


func _ready() -> void:
	SaveManager.enabled = false
	TimeManager.hour = 12
	TimeManager.time_running = true
	game = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame
	var house: Node2D = game.get_node("House")
	player = game.get("player")

	# 1) 屋前小径: 门口往南铺一条 8 格的鹅卵石小径（草地当基底 + 鹅卵石点缀）,
	#    主角站路中间, 镜头贴近看路面
	var door_cell := _cell_of(house.get_node("DoorFront").global_position)
	for i in range(8):
		var c := door_cell + Vector2i(0, i)
		if Floor.is_floored(c):
			Floor.remove(c)
		Floor.place(c, Floor.KIND_PATH)
	player.global_position = house.get_node("DoorFront").global_position \
		+ Vector2(0, 18 + 2 * 32)
	await _settle_cam()
	await _snap("c11_path")
	for i in range(8):
		Floor.remove(door_cell + Vector2i(0, i))

	# 2) 屋内醒来站位: 进屋后把人摆到「床脚边」—— 睡觉醒来的真实落点
	house._enter_house(player)
	await get_tree().physics_frame
	var bed: Node2D = house.get_node("Interior/Bed")
	player.global_position = bed.global_position + house.SLEEP_LAND + Vector2(0, 24)
	await _settle_cam()
	await _snap("c10_wake")

	# 3) 床边按 F: 「今晚怎么睡」主菜单
	var menu: Node = game.get_node("HUD/SleepMenu")
	menu.call("open_panel", player, house)
	await _snap("c4_menu")

	# 4) 小睡挑时刻: 拨到 18 点, 表盘 + 事件提示
	menu.call("choose_nap")
	menu.call("set_hour", 18)
	await _snap("c4_hour")

	# 收尾: 把菜单关掉（开了 ui_pause 不还回去时间就冻住了, 不过反正要退出）
	menu.call("close_panel")
	get_tree().quit()


# 挪完人等相机追上: 关掉平滑直接跳, 再强制画一帧（踩过: 不 force_draw 会截到旧帧）
func _settle_cam() -> void:
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	if cam != null:
		cam.position_smoothing_enabled = false
		cam.reset_smoothing()
	await get_tree().process_frame
	await get_tree().process_frame


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


func _cell_of(world: Vector2) -> Vector2i:
	var local: Vector2 = world - Farm.grid_origin
	return Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE))
