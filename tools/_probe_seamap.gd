extends Node
# tools/_probe_seamap.gd —— 海图天色实机探针：world_map.gd 拆出 scene/world_map/sky_layer.gd
# 之后的「可视回归」。跑法（必须带窗口, 不能 --headless；headless 是 dummy 渲染器, 截图拿不到纹理）:
#   & $exe --path . res://tools/_probe_seamap.tscn
# 产出: outputs/seamap_*.png + 控制台断言
#
# 站点:
#   [1] 正午 —— 覆盖色近乎透明, 画面干净
#   [2] 黄昏 —— 橙色调 + 光带偏金
#   [3] 深夜 —— 压暗偏蓝 + 粼光转冷白
#   [4] 观景档拉远 —— 天色根要反向补偿, 始终铺满全屏（拆模块最容易崩的就是这条）

const OUT := "res://outputs"
var fails := 0
var wm: Node2D

# 把天色拨到某个「天色时刻」。偏移不写死: 开局先量一次「天色钟 - 真实钟」,
# 以后加/减 TONE_ADVANCE 探针自动跟。
var sky_ahead := 4.0

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Weather.current = Weather.SUNNY
	TimeManager.time_running = false

	wm = load("res://scene/world_map.gd").new()
	add_child(wm)
	await get_tree().process_frame
	await get_tree().process_frame
	# 清场: 别让巡逻队/叛军撞上来, 把探针踢进战斗场景
	for p in wm.parties:
		if p["node"] != null:
			p["node"].queue_free()
	wm.parties.clear()
	wm._encounter_cd = 999.0
	wm.resume_camera()
	if wm._cam != null:
		wm._cam.position_smoothing_enabled = false
		wm._cam.zoom = Vector2(2, 2)
	if wm.avatar != null:
		wm.avatar.global_position = Vector2(160, 116) * 16.0     # 出发岛岛心附近
	await get_tree().physics_frame
	if wm._cam != null:
		wm._cam.reset_smoothing()
		wm._cam.force_update_scroll()

	# —— 拆模块后最容易「节点还在但字段是 null」: 逐件验 ——
	_ck(wm._sky_root != null and wm._sky_root.name == "Sky", "天色根 Sky 挂上了")
	_ck(wm._dn_rect != null and wm._dn_rect.name == "DayNight", "昼夜覆盖块就位")
	_ck(wm._glow != null and wm._glow.texture != null, "日月光盘就位（带贴图）")
	_ck(wm._band != null and wm._band.texture != null, "海面光带就位（带贴图）")
	_ck(wm._grade_spr != null and wm._grade_spr.texture != null, "暖冷渐变贴图就位")
	_ck(wm.get_node_or_null("Sky/Haze") != null, "顶边远海雾挂在天色根下")
	var fb := wm.get_node_or_null("FarBoats")
	_ck(fb != null and fb.get_child_count() == 3, "远帆剪影 3 艘都建了（%d）" % (0 if fb == null else fb.get_child_count()))

	# A4-2 装饰层拆出后: 这几组必须是**直接挂海图根下**的容器, 且 _trees_root 指的就是它
	# （观景档拉远靠 _trees_root 整体显隐救帧率, 指丢了两档缩放就散了）
	var trees := wm.get_node_or_null("Trees")
	var rocks := wm.get_node_or_null("Rocks")
	var docks := wm.get_node_or_null("DockMarks")
	var bridges := wm.get_node_or_null("Bridges")
	_ck(trees != null and trees.get_parent() == wm and trees.get_child_count() > 0,
		"果树林 Trees 直接挂海图根下（%d 棵）" % (0 if trees == null else trees.get_child_count()))
	# 礁石按 0.92 稠密噪声阈值撒，固定种子下**一块都不出**（A/B 实测: 切分前也是 0 块）
	# → 只验容器就位 + 父级是海图根, 别断言数量（数量是内容问题, 不是结构问题）
	_ck(rocks != null and rocks.get_parent() == wm,
		"远洋礁石 Rocks 直接挂海图根下（本种子 %d 块）" % (0 if rocks == null else rocks.get_child_count()))
	_ck(docks != null and docks.get_child_count() == 2, "两头码头标记 2 个")
	_ck(bridges != null and bridges.get_child_count() > 0,
		"三条河的桥面就位（%d 格）" % (0 if bridges == null else bridges.get_child_count()))
	_ck(wm._trees_root == trees, "_trees_root 仍指着 Trees 容器（观景档显隐靠它）")


	# 量一次「天色钟 - 真实钟」的总偏移(别写死: 以后改 TONE_ADVANCE 探针自动跟)
	wm.set("_voy_clock", -1.0)
	TimeManager.hour = 12
	TimeManager.minute = 0
	sky_ahead = float(wm._sky_hours()) - 12.0
	print("  [天色] 天色钟比真实钟快 %.1f 小时" % sky_ahead)


	await _shot_at(12.0, "1_day", "正午")
	await _shot_at(18.5, "2_dusk", "黄昏")
	await _shot_at(23.0, "3_night", "深夜")
	await _shot_zoomout(0.30, "4_view", "观景档拉远")

	# 远帆会漂: 连刷两帧看 x 有没有动（模块的 refresh_sky 里那段循环）
	if fb != null and fb.get_child_count() > 0:
		var s0: Sprite2D = fb.get_child(0)
		var x0: float = s0.position.x
		for i in 5:
			wm._refresh_sky(0.2)
		_ck(absf(s0.position.x - x0) > 0.01,
			"远帆慢漂（0.2s x 5 帧挪了 %.2f px）" % absf(s0.position.x - x0))

	print("\n[海图天色探针] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

# 把天色拨到某个「天色时刻」。偏移 sky_ahead 在 _ready 里量出(天色钟 - 真实钟), 别写死。
func _shot_at(sky_hour: float, nm: String, label: String) -> void:
	var real := sky_hour - sky_ahead
	TimeManager.hour = int(floor(real))
	TimeManager.minute = int(round(fmod(real, 1.0) * 60.0))
	wm.set("_voy_clock", -1.0)          # 非航行: 天色跟真实钟
	var got: float = wm._sky_hours()
	var s: Array = wm._sky_sample(sky_hour)
	print("  [天色] %s: 真实钟 %02d:%02d -> 天色 %.1f 时, 覆盖 alpha=%.3f 光盘=%.2f 光带=%.2f"
		% [label, TimeManager.hour, TimeManager.minute, got, float(s[0].a), float(s[2]), float(s[3])])
	_ck(absf(got - sky_hour) < 0.05, "%s: 天色时刻取数正确（%.1f）" % [label, got])
	wm._refresh_sky(0.0)
	await _grab(nm, label)

func _shot_zoomout(z: float, nm: String, label: String) -> void:
	wm._cam.zoom = Vector2(z, z)
	wm._refresh_sky(0.0)
	# 断言要贴着 refresh 立刻做: 等帧的话相机已经被 _physics_process 挪走了
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var camc: Vector2 = wm._cam.get_screen_center_position()
	var want := camc - vp * 0.5 / z
	var got: Vector2 = wm._sky_root.global_position
	print("  [天色] %s: zoom=%.2f, 天色根 期望 %s / 实得 %s" % [label, z, str(want), str(got)])
	_ck(got.distance_to(want) < 2.0, "%s: 天色根仍铺满屏幕（偏差 %.2f px）" % [label, got.distance_to(want)])
	_ck(is_equal_approx(wm._sky_root.scale.x, 1.0 / z),
		"%s: 天色根缩放反向补偿（1/%.2f = %.3f, 实得 %.3f）" % [label, z, 1.0 / z, wm._sky_root.scale.x])
	await _grab(nm, label)

func _grab(nm: String, label: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		fails += 1
		print("  [!!] 截图失败: viewport 纹理为空 (%s)" % label)
		return
	var img := tex.get_image()
	if img == null:
		fails += 1
		print("  [!!] 截图失败: get_image() 返回 null (%s)" % label)
		return
	img.save_png(ProjectSettings.globalize_path("%s/seamap_%s.png" % [OUT, nm]))
	print("  [shot] seamap_%s.png (%s) %dx%d" % [nm, label, img.get_width(), img.get_height()])
