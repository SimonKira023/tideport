# tools/_probe_voyage.gd —— 可视化探针：截屏大地图 / 战役地图 / 指挥
extends Node

func _ready() -> void:
	await get_tree().process_frame

	# 1) 大地图
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await get_tree().create_timer(1.0).timeout
	await _snap("world_map")
	# 全景：相机拉远看整体布局（岛东南 / 大陆西北）
	wm._cam.zoom = Vector2(0.85, 0.85)
	wm.avatar.position = Vector2(75, 50) * 16.0
	await get_tree().create_timer(0.5).timeout
	await _snap("world_full")
	wm.queue_free()
	await get_tree().process_frame

	# 3) 海寇遭遇 = 甲板（h-m）：船板接舷战，四周全是海
	var bm: Node = load("res://scene/battle_map.gd").new()
	bm.party = {"id": 0, "pos": Vector2.ZERO, "dir": Vector2.ZERO, "t": 0.0,
		"type": "海寇", "size": 3, "node": null}
	add_child(bm)
	await get_tree().create_timer(1.0).timeout
	await _snap("battle_deck")
	# 挪到甲板中央看船板纹理和船舷
	bm.hero.global_position = Vector2(22, 13) * 16.0
	await get_tree().create_timer(0.3).timeout
	await _snap("battle_deck_mid")
	bm.queue_free()
	await get_tree().process_frame

	# 3.5) 河谷涉水（h-m）：手动重铺河谷，主角按进贴岸浅水 -> 半身入水
	var bm4: Node = load("res://scene/battle_map.gd").new()
	bm4.party = {"id": 3, "pos": Vector2.ZERO, "dir": Vector2.ZERO, "t": 0.0,
		"type": "山贼", "size": 3, "node": null}
	add_child(bm4)
	# _ready 画的是树林/草原：清掉地形图层和树（troop 保留），重铺河谷
	var keep: Array = bm4.units.duplicate()
	for ch in bm4.get_children():
		if ch is TileMapLayer:
			ch.free()
	for ch in bm4.world.get_children():
		if not keep.has(ch):
			ch.queue_free()
	bm4.blocked = {}
	bm4.template = "河谷"
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = hash("河谷")
	bm4.call("_build_terrain", rng4)
	# 清掉 _ready 那条旧公告（树林/草原），再播河谷的
	var ann4: Array = bm4.get("_announces")
	while not ann4.is_empty():
		bm4.call("_drop_announce", ann4[0])
	bm4.call("_announce", "河谷 - 遭遇山贼!")
	# 主角按进视野中部的一块贴岸浅水：水位贴片亮起、移速降到 0.55 倍
	var sh4 := Vector2i(22, 13)
	for c in bm4.shallow.keys():
		if int(c.x) >= 12 and int(c.x) <= 32 and int(c.y) >= 8 and int(c.y) <= 18:
			sh4 = c
			break
	bm4.hero.global_position = Vector2(sh4.x * 16.0 + 8.0, sh4.y * 16.0 + 8.0)
	await get_tree().create_timer(0.4).timeout
	print("[probe] hero in_water = ", bm4.hero.get("_in_water"))
	await _snap("battle_ford")
	bm4.queue_free()
	await get_tree().process_frame

	# 3.6) 攻城战（h-n）：国家正规军守军披国甲 —— 晨曦城守军清一色晨曦甲
	var bm5: Node = load("res://scene/battle_map.gd").new()
	bm5.party = {"type": "攻城", "size": 5, "siege": "chenxi_cap"}
	add_child(bm5)
	Engine.time_scale = 1.0          # 攻城 _ready 也放慢动作, 截图不等
	# 主角往右挪半程, 相机跟过去, 守军那排国甲看得更清楚
	bm5.hero.global_position = Vector2(24, 13) * 16.0
	await get_tree().create_timer(1.0).timeout
	for t in bm5.units:
		if String(t.side) == "enemy":
			print("[probe] guard nation_id = ", t.get("nation_id"))
			break
	await _snap("battle_siege_armor")
	bm5.queue_free()
	await get_tree().process_frame

	# 4) 树林战役
	var bm2: Node = load("res://scene/battle_map.gd").new()
	bm2.party = {"id": 1, "pos": Vector2.ZERO, "dir": Vector2.ZERO, "t": 0.0,
		"type": "山贼", "size": 3, "node": null}
	add_child(bm2)
	await get_tree().create_timer(1.0).timeout
	await _snap("battle_forest")
	bm2.queue_free()
	await get_tree().process_frame

	# 5) 指挥：编队（1/2/3 三个自定义编队）+ 左键拖拽列阵 + 左下角按钮条
	var old_slaves: Array = Slaves.slaves.duplicate(true)
	var old_exp: Array = Slaves.expedition.duplicate()
	var old_count: int = Slaves.count
	Slaves.slaves = [
		{"name": "甲", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1},
		{"name": "乙", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 2},
		{"name": "丙", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "弓手", "squad": 2},
		{"name": "丁", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 3},
	]
	Slaves.count = Slaves.slaves.size()
	Slaves.expedition = [0, 1, 2, 3]
	var bm3: Node = load("res://scene/battle_map.gd").new()
	bm3.party = {"id": 2, "pos": Vector2.ZERO, "dir": Vector2.ZERO, "t": 0.0,
		"type": "海寇", "size": 3, "node": null}
	add_child(bm3)
	await get_tree().process_frame
	print("[probe] battle time_scale = ", Engine.time_scale)
	Engine.time_scale = 1.0          # 截图不等慢动作（慢放本身已在自检里断言）
	bm3.hero.global_position = Vector2(10, 15) * 16.0
	await get_tree().create_timer(0.5).timeout
	await _snap("cmd_all")                 # 全体：四人都有圈，颜色 = 各自编队色
	# 点「1队」按钮 = 选编队 1：只有 1 队的人有圈
	Voyage.toggle_squad(1)
	bm3._refresh_selection()
	await get_tree().create_timer(0.4).timeout
	await _snap("cmd_squad1")
	# 左键拖一条阵型线：预览线 + 沿线队位小方块
	bm3._drag_from = Vector2(6, 13) * 16.0
	bm3._drag_to = Vector2(14, 16) * 16.0
	bm3._update_formation_preview()
	await get_tree().create_timer(0.4).timeout
	await _snap("cmd_line_preview")
	# 松手：编队 1 沿线展开（正面朝敌人那侧）
	bm3._cast_line(bm3._drag_from, bm3._drag_to)
	await get_tree().create_timer(2.4).timeout
	await _snap("cmd_line")
	# 再按 2 换编队 2 画第二条线（验证各队独立听令）
	Voyage.set_squad_selection(0)
	Voyage.toggle_squad(2)
	bm3._refresh_selection()
	await get_tree().create_timer(0.3).timeout
	await _snap("cmd_squad2_ring")
	bm3._drag_from = Vector2(8, 18) * 16.0
	bm3._drag_to = Vector2(16, 17) * 16.0
	bm3._update_formation_preview()
	await get_tree().create_timer(0.3).timeout
	await _snap("cmd_line2_preview")
	bm3._cast_line(bm3._drag_from, bm3._drag_to)
	await get_tree().create_timer(3.0).timeout
	await _snap("cmd_two_lines")
	bm3.queue_free()
	Slaves.slaves = old_slaves
	Slaves.expedition = old_exp
	Slaves.count = old_count
	await get_tree().process_frame
	get_tree().quit()

func _snap(tag: String) -> void:
	# ❗取窗口截图前先强制画一帧：`get_viewport().get_texture()` 拿到的是「上一帧画完的」
	#   图纸，光 await process_frame 可能还取到改设置之前的那张（改 zoom 后连拍两张
	#   会一模一样）。踩过，见 _probe_island.gd 的同名函数。
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var shot := tex.get_image()
	var out := "res://outputs/probe_%s.png" % tag
	shot.save_png(ProjectSettings.globalize_path(out))
	print("[probe] saved ", out)
