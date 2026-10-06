extends Node
# tools/_probe_daytone.gd —— 岛上「全天颜色渲染提前两小时」实机可视回归。
#
# 背景: 2026-10-06 作者要求全天颜色渲染提前 2 小时(黄昏更早到、早上更像中午),
# 实现是把各处渲染器统一读 TimeManager.TONE_ADVANCE（见 time_manager.gd）。
# 本探针把真实钟拨到若干时刻各拍一张, 并打印「旧色调基准(真实钟) vs 新色调(+TONE_ADVANCE)」
# 的目标色 —— 同一真实钟下新旧两色一对比, 就能看出暮色是不是真的提早了。
#
# 跑法(必须带窗口, 不能 --headless；headless 是 dummy 渲染器, 截图拿不到纹理):
#   & $exe --path . res://tools/_probe_daytone.tscn
# 产出: outputs/daytone_*.png + 控制台断言/事实

const OUT := "res://outputs"
var fails := 0
var game: Variant = null

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	# 万一有写档路径, 也重定向到临时目录, 绝不碰玩家真档
	_redirect_save()
	Weather.current = Weather.SUNNY
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	game = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().process_frame

	var pl: Node2D = game.get("player")
	var cam: Camera2D = pl.get_node("Camera2D")
	cam.position_smoothing_enabled = false
	cam.zoom = Vector2(3, 3)
	pl.global_position = Farm.grid_origin + Vector2(game.SPAWN_CELL.x * 16 + 8, game.SPAWN_CELL.y * 16 + 8)
	cam.reset_smoothing()
	var dn: Variant = game.get_node_or_null("DayNight")
	_ck(dn != null, "DayNight(CanvasModulate) 节点在")
	print("[事实] TONE_ADVANCE = %.1f 小时（旧基准=真实钟, 新基准=真实钟+%.1f）"
		% [float(TimeManager.TONE_ADVANCE), float(TimeManager.TONE_ADVANCE)])

	# 纯函数断言: 加偏移后, 同一真实钟的色调确实更「晚」(更暗/更暖) -> 色系提早
	if dn != null:
		var t12_old: Color = dn._color_at(12.0)
		var t12_new: Color = dn._color_at(12.0 + float(TimeManager.TONE_ADVANCE))
		_ck(t12_old.is_equal_approx(t12_new), "正午 12 点: 新旧色调都是纯白（+2 后仍在白天段）")
		var t17_old: Color = dn._color_at(17.0)
		var t17_new: Color = dn._color_at(17.0 + float(TimeManager.TONE_ADVANCE))
		print("[事实] 真实 17:00 旧色调 %s -> 新色调 %s" % [str(t17_old), str(t17_new)])
		_ck(t17_new.get_luminance() < t17_old.get_luminance() - 0.02,
			"真实 17:00 新色调比旧色调更晚（黄昏色提前到来, 亮度 %.3f -> %.3f）"
				% [t17_old.get_luminance(), t17_new.get_luminance()])

	# 逐时刻拍照: 6:30 晨光 / 9 上午 / 13 正午 / 16 该开始转暮 / 17:30 明显橙 / 19 全暮 / 22 夜
	for h in [6.5, 9.0, 13.0, 16.0, 17.5, 19.0, 22.0]:
		TimeManager.time_running = false
		TimeManager.hour = int(floor(h))
		TimeManager.minute = int(round((h - floor(h)) * 60.0))
		TimeManager.time_tick.emit()
		# 后处理夜度按 delta*0.5 慢慢过渡, 探针直接 snap 到目标(新色调钟)再喂一次材质
		game.set("_post_night", game._night_at(fmod(h + 2.0 + float(TimeManager.TONE_ADVANCE), 24.0)))
		game.call("_sync_post", 0.0)
		for i in 110:
			await get_tree().process_frame
		var old_c: Color = dn._color_at(h)
		var new_c: Color = dn._color_at(h + float(TimeManager.TONE_ADVANCE))
		print("[色调] 真实 %05.2f: 旧 %s -> 新 %s" % [h, str(old_c), str(new_c)])
		await _snap("daytone_%05.2f" % h)

	print("\n[岛上基调探针] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _redirect_save() -> void:
	# 把写档路径(若存在这些属性)重定向到临时目录; 不存在时 Object.set 静默忽略, 不炸
	SaveManager.set("save_path", "user://_probe_daytone_slots/save.json")
	SaveManager.set("history_dir", "user://_probe_daytone_slots/history")
	SaveManager.set("slot_dir", "user://_probe_daytone_slots/slots")

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

func _snap(tag: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		fails += 1
		print("  [!!] 截图失败: viewport 纹理为空 (%s)" % tag)
		return
	var img := tex.get_image()
	if img == null:
		fails += 1
		print("  [!!] 截图失败: get_image() 返回 null (%s)" % tag)
		return
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, tag]))
	print("  [shot] %s.png %dx%d" % [tag, img.get_width(), img.get_height()])
