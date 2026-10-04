# tools/_probe_e30k.gd —— e30k 小径/木地板重画的画面验收探针
#
# 跑真实 game.tscn, 输出到 res://outputs/:
#   1) probe_e30k_ground  屋前: 门口往南 8 格「大圆石」小径 + 西侧一块 4x3「错缝板条」木地板
#   2) probe_e30k_icon_floor / probe_e30k_icon_path  两个背包图标放大 4 倍
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

	# 1) 屋前小径: 门口往南 8 格鹅卵石（e30k 大圆石版）
	var door_cell := _cell_of(house.get_node("DoorFront").global_position)
	var placed_path: Array = []
	for i in range(8):
		var c := door_cell + Vector2i(0, i)
		if not game._land_set.has(c):
			continue
		if Floor.is_floored(c):
			Floor.remove(c)
		Floor.place(c, Floor.KIND_PATH)
		placed_path.append(c)
	# 2) 小径西侧并排一块 4x3 木地板（e30k 错缝板条版）
	var placed_wood: Array = []
	for dy in range(3):
		for dx in range(4):
			var c2 := door_cell + Vector2i(-1 - dx, 1 + dy)
			if not game._land_set.has(c2):
				continue
			if Floor.is_floored(c2):
				Floor.remove(c2)
			Floor.place(c2, Floor.KIND_WOOD)
			placed_wood.append(c2)
	player.global_position = house.get_node("DoorFront").global_position \
		+ Vector2(0, 18 + 2 * 32)
	await _settle_cam()
	await _snap("e30k_ground")
	for c in placed_wood:
		Floor.remove(c)
	for c in placed_path:
		Floor.remove(c)

	# 3) 两个背包图标放大 4 倍各存一张
	_save_icon(load("res://item/wood_floor.tres").icon, "e30k_icon_floor")
	_save_icon(load("res://item/stone_path.tres").icon, "e30k_icon_path")
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


# 图标 4 倍放大存 PNG（32x32 太小看不清细节）
func _save_icon(icon: Texture2D, tag: String) -> void:
	if icon == null:
		print("[probe] %s 没有图标!" % tag)
		return
	var src := icon.get_image()
	var w := src.get_width()
	var h := src.get_height()
	var big := Image.create_empty(w * 4, h * 4, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var col := src.get_pixel(x, y)
			for dy in 4:
				for dx in 4:
					big.set_pixel(x * 4 + dx, y * 4 + dy, col)
	var out := "res://outputs/probe_%s.png" % tag
	big.save_png(ProjectSettings.globalize_path(out))
	print("[probe] saved ", out)


func _cell_of(world: Vector2) -> Vector2i:
	var local: Vector2 = world - Farm.grid_origin
	return Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE))
