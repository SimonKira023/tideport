# tools/_probe_fx.gd —— h-l 唯美滤镜 + 光尘视觉探针（只印事实 + 截图，不下结论）
# ❗必须去掉 --headless 跑：dummy 渲染器不执行 shader，截出来全是灰图
# 截 4 张图到 outputs/：
#   probe_fx_noon_on / noon_off   白天滤镜开/关对照（像素差应为正，证明滤镜真的上屏）
#   probe_fx_dusk                 黄昏 19 点：橙金光尘最浓
#   probe_fx_night                深夜 23 点：冷蓝光尘 + 夜色
extends Node

var game: Node = null

func _ready() -> void:
	SaveManager.enabled = false
	game = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame

	var pl: Node2D = game.get("player")
	var cam: Camera2D = pl.get_node("Camera2D")
	cam.position_smoothing_enabled = false
	cam.zoom = Vector2(3, 3)
	pl.global_position = Farm.grid_origin \
		+ Vector2(game.SPAWN_CELL.x * 16 + 8, game.SPAWN_CELL.y * 16 + 8)
	cam.reset_smoothing()

	# 事实：滤镜节点在（光尘/萤火虫层已整体删除）
	var fx: ColorRect = game.get_node("HUD/PostFX")
	print("[fact] PostFX material=%s  visible=%s" % [str(fx.material != null), str(fx.visible)])

	# 拨时间的小工具：day_night 的目标色只在 time_tick 里刷新，手动 emit 一次
	var set_hour := func(h: int) -> void:
		TimeManager.time_running = false
		TimeManager.hour = h
		TimeManager.time_running = true
		TimeManager.time_tick.emit()

	# 1) 白天正午：滤镜开关对照
	await set_hour.call(12)
	for i in 90:   # 等 day_night lerp / 光尘颜色 lerp 收敛
		await get_tree().process_frame
	var img_on := await _snap("fx_noon_on")
	fx.visible = false
	var img_off := await _snap("fx_noon_off")
	fx.visible = true
	var diff := _mean_diff(img_on, img_off)
	print("[fact] 滤镜开关像素平均差=%.4f (0=滤镜没生效)" % diff)

	# 2) 黄昏 19 点
	await set_hour.call(19)
	for i in 90:
		await get_tree().process_frame
	await _snap("fx_dusk")

	# 3) 深夜 23 点
	await set_hour.call(23)
	for i in 90:
		await get_tree().process_frame
	await _snap("fx_night")

	get_tree().quit()

func _snap(tag: String) -> Image:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		return null
	var shot := tex.get_image()
	shot.save_png(ProjectSettings.globalize_path("res://outputs/probe_%s.png" % tag))
	print("[probe] saved probe_%s.png" % tag)
	return shot

# 两张截图隔点采样的 RGB 平均差
func _mean_diff(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return -1.0
	var acc := 0.0
	var n := 0
	for y in range(0, a.get_height(), 16):
		for x in range(0, a.get_width(), 16):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			acc += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return acc / float(maxi(n, 1) * 3)
