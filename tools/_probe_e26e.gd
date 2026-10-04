extends Node
# tools/_probe_e26e.gd —— e26e 动画增强实机探针: 飘字 / 水花 / 换旗波纹 / 播报滑入 /
# 面板弹入 / 掉落物浮动
# 跑法（带窗口跑, 要截图）:
#   & $exe --path . --log-file w32_e26e.log res://tools/_probe_e26e.tscn
#
# 站点:
#   [1] 飘字 —— _float_text 生成 Label -> 上浮 -> 1.1 秒散场自回收
#   [2] 水花 —— _splash 直喷一发自回收 + 头像入水切换沿自动喷
#   [3] 换旗波纹 —— _flag_ring 圆环 0.4 倍炸到 2.6 倍淡出消散
#   [4] 播报滑入 —— announce 从 y=44 滑到 60 淡入, 停留淡出退场
#   [5] 商队面板弹入 —— _pop_panel 0.85 倍回弹到 1.0
#   [6] 掉落物浮动 —— item_pickup 循环起伏 + 捡起飘字
#   [7] 命名面板弹入 —— 国家命名弹窗同一套弹入

const OUT := "res://outputs"
var fails := 0

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _float_label()
	await _water_splash()
	await _flag_ring()
	await _announce_slide()
	await _caravan_panel_pop()
	await _pickup_bob()
	await _naming_panel_pop()
	print("\n[e26e] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

func _fresh() -> void:
	Wallet.add_money(99999)
	Wallet.money = 0
	Inventory.reset_for_new_game()
	Nations.reset_for_new_game()

func _new_wm() -> Node:
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	return wm

func _force_caravan(wm: Node) -> Dictionary:
	for t in 40:
		wm._spawn_caravans()
		for p in wm.parties:
			if String(p.get("type", "")) == "商队" and not bool(p.get("gone", false)):
				return p
	return {}

# 按文字找 Label（播报 / 飘字都是 Label, 树遍历顺序不可靠一律按文字找）
func _label_by_text(root: Node, kw: String) -> Label:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label and String((n as Label).text).contains(kw):
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _count_particles(root: Node) -> int:
	var n := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CPUParticles2D:
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n

func _new_child(of: Node, before: Array) -> Node:
	for c in of.get_children():
		if not before.has(c):
			return c
	return null

func _water_pos(wm: Node) -> Vector2:
	for c in wm._water:
		return wm._cell_center(c as Vector2i)
	return Vector2.ZERO

# ---------------- 1. 飘字 ----------------
func _float_label() -> void:
	print("\n========== [1] 飘字 ==========")
	var wm := _new_wm()
	await _wait(0.8)
	wm._float_text(wm.avatar.position, "测试飘字", Color(1, 0.9, 0.6))
	await get_tree().process_frame
	var l := _label_by_text(wm, "测试飘字")
	_ck(l != null, "飘字 Label 生成")
	if l != null:
		var y0: float = (l as Label).position.y
		await _wait(0.5)
		if is_instance_valid(l):
			_ck((l as Label).position.y < y0 - 8.0,
					"飘字上浮 (%.1f -> %.1f)" % [y0, (l as Label).position.y])
		else:
			_ck(false, "飘字上浮 (Label 提前没了)")
	await _shot("float_text")
	await _wait(1.0)
	_ck(_label_by_text(wm, "测试飘字") == null, "1.1 秒后飘字散场自回收")
	wm.free()
	await get_tree().process_frame

# ---------------- 2. 水花 ----------------
func _water_splash() -> void:
	print("\n========== [2] 水花 ==========")
	var wm := _new_wm()
	await _wait(0.8)
	var n0 := _count_particles(wm)
	wm._splash(wm.avatar.position)
	await get_tree().process_frame
	_ck(_count_particles(wm) == n0 + 1, "水花粒子直喷生成")
	await _wait(1.6)
	_ck(_count_particles(wm) == n0, "水花 1.4 秒后自回收")
	# 切换沿: 把头像扔到水面上, 下一帧物理该自动喷一发
	var n1 := _count_particles(wm)
	wm._was_water = false
	wm.avatar.position = _water_pos(wm)
	await _wait(0.35)
	_ck(wm._was_water, "入水切换沿被记录 (_was_water=true)")
	_ck(_count_particles(wm) >= n1 + 1, "入水瞬间自动喷水花")
	wm.free()
	await get_tree().process_frame

# ---------------- 3. 换旗波纹 ----------------
func _flag_ring() -> void:
	print("\n========== [3] 换旗波纹 ==========")
	var wm := _new_wm()
	await _wait(0.8)
	var before: Array = wm.get_children()
	wm._flag_ring(wm.avatar.position, Color(0.9, 0.4, 0.3))
	await get_tree().process_frame
	var ring := _new_child(wm, before)
	_ck(ring is Sprite2D, "波纹圆环 Sprite2D 生成")
	if ring is Sprite2D:
		var s0: float = (ring as Sprite2D).scale.x
		await _wait(0.45)
		_ck((ring as Sprite2D).scale.x > s0 + 0.4,
				"波纹扩散 (%.2f -> %.2f)" % [s0, (ring as Sprite2D).scale.x])
	await _shot("flag_ring")
	await _wait(0.8)
	_ck(not is_instance_valid(ring), "0.9 秒后波纹消散")
	wm.free()
	await get_tree().process_frame

# ---------------- 4. 播报滑入 ----------------
func _announce_slide() -> void:
	print("\n========== [4] 播报滑入 ==========")
	var wm := _new_wm()
	await _wait(0.8)
	wm.announce("测试播报", 0.8)
	await get_tree().process_frame
	var l := _label_by_text(wm, "测试播报")
	_ck(l != null, "播报 Label 生成")
	if l != null:
		var y0: float = (l as Label).position.y
		_ck(y0 < 60.0, "从上方滑入 (起始 y=%.1f)" % y0)
		await _wait(0.4)
		_ck(absf((l as Label).position.y - 60.0) < 2.0,
				"落位到 y=60 (y=%.1f)" % (l as Label).position.y)
		_ck((l as Label).modulate.a > 0.9,
				"滑入时已淡入 (a=%.2f)" % (l as Label).modulate.a)
	await _shot("announce_slide")
	await _wait(1.2)
	_ck(_label_by_text(wm, "测试播报") == null, "停留淡出完整退场")
	wm.free()
	await get_tree().process_frame

# ---------------- 5. 商队面板弹入 ----------------
func _caravan_panel_pop() -> void:
	print("\n========== [5] 商队面板弹入 ==========")
	var wm := _new_wm()
	await _wait(0.8)
	_fresh()
	var cd := _force_caravan(wm)
	_ck(not cd.is_empty(), "商队上地图")
	if cd.is_empty():
		wm.free()
		return
	var before: Array = wm._hud.get_children()
	wm._open_caravan_panel(cd)
	# 同步检查: _pop_panel 先把面板缩到 0.85 + 透明, deferred 才起跑弹入 tween
	var wrap := _new_child(wm._hud, before)
	_ck(wrap is CenterContainer, "弹窗挂上 _hud")
	var panel: Control = null
	if wrap != null:
		for c in (wrap as Node).get_children():
			if c is PanelContainer:
				panel = c
	_ck(panel != null, "面板容器找到")
	if panel != null:
		var s0: float = panel.scale.x
		_ck(s0 < 0.99, "弹入从缩小的面板起步 (scale=%.2f)" % s0)
		_ck(panel.modulate.a < 0.1, "透明起步 (a=%.2f)" % panel.modulate.a)
		await _wait(0.4)
		_ck(panel.scale.x > 0.97, "回弹到原大 (scale=%.2f)" % panel.scale.x)
		_ck(panel.modulate.a > 0.9, "淡入完成 (a=%.2f)" % panel.modulate.a)
	await _shot("panel_pop")
	wm._close_caravan_panel(wrap)
	wm.free()
	await get_tree().process_frame

# ---------------- 6. 掉落物浮动 ----------------
func _pickup_bob() -> void:
	print("\n========== [6] 掉落物浮动 ==========")
	var it: ItemData = load("res://item/perch.tres")
	_ck(it != null, "测试物品鲤鱼就位")
	var pk: Area2D = load("res://item_pickup.gd").new()
	pk.item = it
	pk.amount = 1
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.position = Vector2(0, -6)
	pk.add_child(spr)
	add_child(pk)      # item 要在 add_child 之前赋值, _ready 里要用
	await get_tree().process_frame
	_ck((spr as Sprite2D).texture == it.icon, "掉落物贴图挂上")
	var y0: float = spr.position.y
	await _wait(0.4)
	_ck(spr.position.y < y0 - 0.5, "掉落物轻轻浮动 (%.2f -> %.2f)" % [y0, spr.position.y])
	# 捡起飘字: 挂在父节点上, 自己 freed 也不影响
	pk._float_text("测试掉落")
	await get_tree().process_frame
	var l := _label_by_text(self, "测试掉落")
	_ck(l != null, "捡起时飘字生成（挂在父节点）")
	pk.queue_free()
	await _wait(1.5)      # 飘字总程 1.1 秒, 等 >1.1s 再断言散场
	_ck(_label_by_text(self, "测试掉落") == null, "飘字飘完自回收")

# ---------------- 7. 命名面板弹入 ----------------
func _naming_panel_pop() -> void:
	print("\n========== [7] 命名面板弹入 ==========")
	var wm := _new_wm()
	await _wait(0.8)
	var before: Array = wm._hud.get_children()
	wm._open_nation_naming()
	# 同步检查: _pop_panel 先把面板缩到 0.85 + 透明, deferred 才起跑弹入 tween
	var wrap := _new_child(wm._hud, before)
	_ck(wrap is CenterContainer, "命名弹窗挂上 _hud")
	var panel: Control = null
	if wrap != null:
		for c in (wrap as Node).get_children():
			if c is PanelContainer:
				panel = c
	if panel != null:
		var s0: float = panel.scale.x
		_ck(s0 < 0.99, "弹入从缩小的面板起步 (scale=%.2f)" % s0)
		_ck(panel.modulate.a < 0.1, "透明起步 (a=%.2f)" % panel.modulate.a)
		await _wait(0.4)
		_ck(panel.scale.x > 0.97, "回弹到原大 (scale=%.2f)" % panel.scale.x)
		_ck(panel.modulate.a > 0.9, "淡入完成 (a=%.2f)" % panel.modulate.a)
	if wrap != null:
		(wrap as Node).queue_free()      # 不点按钮, 免得真把国家改了名
	wm.free()
	await get_tree().process_frame

# ---------------- 工具 ----------------
func _shot(nm: String) -> void:
	await _wait(0.7)      # 等淡入结束再拍, 别截到中间帧
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		img.save_png(ProjectSettings.globalize_path("%s/e26e_%s.png" % [OUT, nm]))
		print("  [shot] e26e_%s.png" % nm)
	else:
		print("  [!!] 截图失败: viewport 纹理为空")

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame
