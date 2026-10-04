# tools/ui_dump.gd —— 把某个 Control 界面的**排版结果**导成 JSON + 贴图，
# 交给 tools/render_ui.py 用 PIL 画出来。
#
# 为什么需要它：Godot 的 headless 模式截不了图；world 里那些东西还能靠
# scene_dump.gd 导出「贴图 + 位置」来还原，可 UI 是「矩形 + 边框 + 文字」排出来的，
# 光导贴图什么也看不出来。所以这里直接把排版好的矩形/文字/贴图都记下来。
#
# 跑法（项目根目录）：
#   "<Godot exe>" --headless --path . res://tools/ui_dump.tscn
#   python tools/render_ui.py outputs/夜晚结算.png
extends Node

const OUT_JSON := "res://_ui_dump.json"
const TEX_DIR := "res://_ui_tex"
const VIEW := Vector2(1152, 648)      # 按项目的窗口尺寸来排版

var _tex_ids := {}
var _tex_seq := 0
var _items: Array = []

func _ready() -> void:
	# ❗headless 下窗口尺寸不可靠（实测是 1152x1152）：把窗口钉成项目尺寸，
	#   界面里按 get_viewport_rect() 排版的（assign 的地图等）才会得出真实数字。
	get_tree().root.size = Vector2i(int(VIEW.x), int(VIEW.y))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))

	# 一个固定尺寸的「假视口」——headless 下窗口尺寸不可靠，锚点全按它算
	var root := Control.new()
	root.name = "UiRoot"
	root.position = Vector2.ZERO
	root.size = VIEW
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	await get_tree().process_frame

	# ---------- 场景 1：夜晚结算画面 ----------
	var settle: Control = load("res://settlement_ui.gd").new()
	root.add_child(settle)
	await get_tree().process_frame
	var carrot: ItemData = load("res://item/carrot.tres")
	var potato: ItemData = load("res://item/potato.tres")
	var pumpkin: ItemData = load("res://item/pumpkin.tres")
	var entries := [
		{"item": carrot, "count": 6, "price": carrot.sell_price * 6},
		{"item": potato, "count": 4, "price": potato.sell_price * 4},
		{"item": pumpkin, "count": 1, "price": pumpkin.sell_price},
	]
	var income := 0
	for e in entries:
		income += int(e["price"])
	# 日期按 TimeManager.date_text() 的真实格式写（"秋季 第 12 天"）——
	# 别用 "·" 当分隔符：IPix.ttf 没有这个字形，预览图上会是个小方块，看着像 bug
	settle.show_summary("秋季 第 12 天", 12, entries, income, 1286, "",
		["科技 +16 点 (共 112)  2 人钻研", "行政 +8 点 (共 62)  1 人钻研",
			"可研究: 犁耕法 / 谷仓 / 木匠行会"])
	settle._guard = 0.0
	# ❗结算页有条 0.45s 的入场动画（面板从 +26px 滑进来），等是等不完的 ——
	#   直接掐掉并把面板摆到最终位置，导出的才是玩家真正看到的排版。
	if settle._tw_main != null:
		settle._tw_main.kill()
	if settle._tw_sky != null:
		settle._tw_sky.kill()
	settle._bg.modulate.a = 1.0
	settle._box.modulate.a = 1.0
	settle._recentre()
	for i in 3:
		await get_tree().process_frame
	_dump(settle, "settlement")
	settle.queue_free()
	await get_tree().process_frame

	# ---------- 场景 2：商人交易面板 ----------
	var shop: Control = load("res://shop_ui.gd").new()
	root.add_child(shop)
	await get_tree().process_frame
	shop.open_panel()
	for i in 3:
		await get_tree().process_frame
	_dump(shop, "shop")
	shop.queue_free()
	await get_tree().process_frame

	# ---------- 场景 3：背包面板 ----------
	# 开局物品是 game.gd 发的，这里只有裸面板 → 手动塞几样，预览才看得出图标
	for spec in [["res://item/hoe.tres", 1], ["res://item/watering_can.tres", 1],
			["res://item/seed.tres", 8], ["res://item/carrot.tres", 3],
			["res://item/pumpkin.tres", 2], ["res://item/wood.tres", 5]]:
		var it: ItemData = load(spec[0])
		if it != null:
			Inventory.add_item(it, int(spec[1]))
	var bp: Control = load("res://backpack_ui.gd").new()
	root.add_child(bp)
	await get_tree().process_frame
	bp.open()
	for i in 3:
		await get_tree().process_frame
	_dump(bp, "backpack")
	bp.queue_free()
	await get_tree().process_frame

	# ---------- 场景 3.5：角色页 / 团队页 / 设置页 ----------
	# ❗这里原来会往 user://saves 里塞 8 份「第 9 年」的假快照，只为把设置页那张
	#   每日快照列表撑长、验证限高滚动。现在设置页不再列快照（读档统一收在主页面），
	#   假数据没用了 —— 顺手删掉，也省得再往玩家真正的存档目录里写东西。
	var bp2: Control = load("res://backpack_ui.gd").new()
	root.add_child(bp2)
	await get_tree().process_frame
	bp2.open()
	# 顺手给点等级/技能点，让角色页有东西可看
	Legion.level = 3
	Legion.exp = 15
	Legion.skill_points = 2
	Legion.skills = {"trade": 2, "manage": 1, "leader": 0}
	Legion.stats_changed.emit()
	bp2._select_module("hero")
	for i in 3:
		await get_tree().process_frame
	_dump(bp2, "hero")
	# 团队管理页：造几个伙伴才有行可看（这页顶上的「花钱招募」按钮已经去掉了，
	# 招募只留傍晚野外的篝火）
	Slaves.slaves = []
	for i in 3:
		Slaves.slaves.append({
			"name": ["娜雅", "布恩", "珞琳"][i],
			"affection": [3, 1, 0][i],
			"fed_today": i == 0, "talked_today": i == 1,
			"max_hp": 30, "hp": 30,
			"troop": "弓手" if i == 2 else "刀客",
			"labor": "园丁" if i == 2 else "帮工",
			"squad": 2 if i == 2 else 1,
		})
	Slaves.count = Slaves.slaves.size()
	bp2._select_module("team")
	for i in 3:
		await get_tree().process_frame
	_dump(bp2, "team")
	bp2._select_module("set")
	for i in 3:
		await get_tree().process_frame
	_dump(bp2, "settings")
	bp2.queue_free()
	await get_tree().process_frame

	# ---------- 场景 4：夜晚「给伙伴派活」面板（涂色地图） ----------
	# 面板要读真实地形才画得出底图（哪格是水、哪格是耕地），所以这里真的装一个 game。
	var g4: Node2D = load("res://scene/game.tscn").instantiate()
	add_child(g4)
	await get_tree().process_frame
	await get_tree().process_frame
	# 直接写 assignments（绕过额度限制），方便涂出三片颜色齐全的示范
	Slaves.count = 6
	# 「明天出行」名单要有真伙伴才看得见（勾选框 + 1/2/3 编队小键）→ 造 6 个
	Slaves.slaves = []
	for i in 6:
		Slaves.slaves.append({
			"name": ["阿一", "阿二", "阿三", "阿四", "阿五", "阿六"][i],
			"affection": 0, "fed_today": false, "talked_today": false,
			"max_hp": 30, "hp": 30,
			"troop": "弓手" if i % 3 == 2 else "刀客",
			"labor": ["帮工", "园丁", "学徒"][i % 3],
			"squad": (i % 3) + 1,
		})
	Slaves.count = Slaves.slaves.size()
	Slaves.expedition = [0, 2]      # 阿一、阿三 明天随船出海
	Slaves.assignments.clear()
	var patches := [
		[Slaves.TASK_TILL, Vector2i(1, 2), Vector2i(4, 5)],
		[Slaves.TASK_WATER, Vector2i(1, 8), Vector2i(3, 11)],
		[Slaves.TASK_PLANT, Vector2i(7, 3), Vector2i(10, 5)],
	]
	for spec in patches:
		for x in range(spec[1].x, spec[2].x + 1):
			for y in range(spec[1].y, spec[2].y + 1):
				Slaves.assignments[Vector2i(x, y)] = spec[0]

	# ---------- 场景 4.5：科技页 / 行政页 ----------
	# 两页都要有真数据才看得出样子：给点研究进度 + 卡槽挂卡 + 派几个人去研究
	var res_backup := Research.to_dict()
	var rtech_backup: Array = Slaves.research_tech.duplicate()
	var radmin_backup: Array = Slaves.research_admin.duplicate()
	Research.reset()
	Research.tech_points = 96
	Research.admin_points = 600      # 够把编户/乡勇/楼船/演武场一路点下来
	# e30i: 主角不下场研究了 —— 截图里的人手一律走 Slaves 名单（下面 set_research）
	Research.research_tech("fert")
	Research.research_tech("axe")
	Research.research_tech("well")
	Research.research_admin("admin_hu")
	Research.research_admin("admin_militia")
	Research.research_admin("admin_navy")
	Research.research_admin("admin_drill")
	Research.slot_card("corvee")
	Research.slot_card("ironboat")      # 远征向：出海金币 +50%
	Research.slot_card("drill")         # 远征向：伙伴攻击 +1
	Research._promote_pending()         # 隔周生效: 模拟周初换班, 把已挂的卡送进生效槽
	Research.slot_card("scout")         # 远征向：战场移动 +25% (留在准备槽, 展示隔周生效)
	Slaves.set_research(1, "tech")
	Slaves.set_research(3, "admin")
	var bp3: Control = load("res://backpack_ui.gd").new()
	root.add_child(bp3)
	await get_tree().process_frame
	bp3.open()
	bp3._select_module("tech")
	for i in 3:
		await get_tree().process_frame
	_dump(bp3, "tech")
	bp3._select_module("admin")
	for i in 3:
		await get_tree().process_frame
	_dump(bp3, "admin")
	bp3.queue_free()
	await get_tree().process_frame
	Research.from_dict(res_backup)
	Slaves.research_tech = rtech_backup
	Slaves.research_admin = radmin_backup
	Research.changed.emit()
	await get_tree().process_frame
	# 留两个人在研究里，好让派活面板的 [科]/[行] 标记出现在预览图上
	Slaves.research_tech = [1]
	Slaves.research_admin = [3]
	var ap: Control = load("res://assign_ui.gd").new()
	root.add_child(ap)
	await get_tree().process_frame
	ap.setup(g4, Slaves.map_from, Slaves.map_to)   # 整座岛（game._setup_slaves 已算好）
	ap.open()
	ap._guard = 0.0
	for i in 3:
		await get_tree().process_frame
	_dump(ap, "assign")
	_dump_assign_map(ap)          # 涂色地图是 _draw() 画的，得手工补进来
	ap.queue_free()
	await get_tree().process_frame
	g4.queue_free()
	await get_tree().process_frame
	Slaves.research_tech = rtech_backup
	Slaves.research_admin = radmin_backup

	# ---------- 场景 5：篝火招募面板（招募前先看清这个人） ----------
	# 面板靠 "campfire" 组找「当前这堆火」，所以这里造一堆真篝火 ——
	# 它自己会在火边摆一个「等你搭话」的像素人（campfire.gd _build_visitor）。
	var sl_backup5: Array = Slaves.slaves.duplicate(true)
	var cnt_backup5: int = Slaves.count
	var money_backup5: int = Wallet.money
	Slaves.slaves = [{
		"name": "娜雅", "affection": 3, "fed_today": false,
		"talked_today": false, "max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1,
	}]
	Slaves.count = 1
	Wallet.money = 486
	var fire5: Node2D = load("res://scene/campfire.gd").new()
	fire5.position = Vector2(90, 96)
	root.add_child(fire5)
	await get_tree().process_frame
	var cf5: Control = load("res://campfire_ui.gd").new()
	root.add_child(cf5)
	await get_tree().process_frame
	cf5.open_panel()
	for i in 3:
		await get_tree().process_frame
	_dump(cf5, "campfire")
	cf5.queue_free()
	await get_tree().process_frame
	fire5.queue_free()
	await get_tree().process_frame
	Slaves.slaves = sl_backup5
	Slaves.count = cnt_backup5
	Wallet.money = money_backup5
	Slaves.changed.emit()

	# ---------- 场景 6：废弃码头面板（三种状态各来一张） ----------
	# 面板内容是按码头状态现拼的：废墟（账单）/ 待施工（进度条）/ 建成（出海+造船），
	# 所以要开三次才扫得全，缺字形体检也才看得全。
	var dock_bak := [Voyage.dock_state, Voyage.dock_work, Voyage.boat_count]
	var money_bak6 := Wallet.money
	Wallet.money = 5000
	for spec6 in [
			[Voyage.DOCK_RUIN, 0, 0, "dock-ruin"],
			[Voyage.DOCK_FUNDED, 3, 0, "dock-funded"],
			[Voyage.DOCK_BUILT, Voyage.DOCK_WORK, 3, "dock-built"]]:
		Voyage.dock_state = int(spec6[0])
		Voyage.dock_work = int(spec6[1])
		Voyage.boat_count = int(spec6[2])
		var dp: Control = load("res://dock_ui.gd").new()
		root.add_child(dp)
		await get_tree().process_frame
		dp.open_panel()
		dp._guard = 0.0
		for i in 3:
			await get_tree().process_frame
		_dump(dp, str(spec6[3]))
		dp.close_panel()          # ❗要正常关：open_panel 里有时间暂停栈，白丢会一直停着
		dp.queue_free()
		await get_tree().process_frame
	Voyage.dock_state = int(dock_bak[0])
	Voyage.dock_work = int(dock_bak[1])
	Voyage.boat_count = int(dock_bak[2])
	Wallet.money = money_bak6
	Voyage.dock_changed.emit()

	# ---------- 场景 7：大陆集市 / 酒馆（上岸后才能开的两张面板） ----------
	var money_bak7 := Wallet.money
	var cnt_bak7 := Slaves.count
	var sl_bak7: Array = Slaves.slaves
	Wallet.money = 1200
	Slaves.count = 1
	Slaves.slaves = [{"name": "娜雅", "affection": 0, "fed_today": false,
		"talked_today": false, "max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1}]
	# 背包里塞点作物，集市那张才看得见「能卖多少」那一行
	Inventory.add_item(load("res://item/potato.tres"), 6)
	Inventory.add_item(load("res://item/cabbage.tres"), 2)
	for spec7 in [["res://market_ui.gd", "market"], ["res://tavern_ui.gd", "tavern"]]:
		var p7: Control = load(str(spec7[0])).new()
		root.add_child(p7)
		await get_tree().process_frame
		p7.open_panel()
		p7.set("_guard", 0.0)
		for i in 3:
			await get_tree().process_frame
		_dump(p7, str(spec7[1]))
		p7.close_panel()          # ❗要正常关：open_panel 里有时间暂停栈
		p7.queue_free()
		await get_tree().process_frame
	# 把塞进去的作物拿回来，别污染后面的场景
	Inventory.remove_item(load("res://item/potato.tres"), Inventory.count_item(load("res://item/potato.tres")))
	Inventory.remove_item(load("res://item/cabbage.tres"), Inventory.count_item(load("res://item/cabbage.tres")))
	Slaves.slaves = sl_bak7
	Slaves.count = cnt_bak7
	Wallet.money = money_bak7
	Slaves.changed.emit()

	# ---------- 场景 8：作弊面板（P 唤醒，加钱/加资源） ----------
	var money_bak8 := Wallet.money
	Wallet.money = 888
	var cp8: Control = load("res://cheat_ui.gd").new()
	root.add_child(cp8)
	await get_tree().process_frame
	cp8.open()
	cp8.set("_guard", 0.0)
	for i in 3:
		await get_tree().process_frame
	_dump(cp8, "cheat")
	cp8._dismiss()            # ❗open 里有时间暂停栈，必须正常关
	cp8.queue_free()
	await get_tree().process_frame
	Wallet.money = money_bak8

	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify({"view": [VIEW.x, VIEW.y], "items": _items}, "  "))
	f.close()
	print("[ui dump] 导出 %d 条排版指令" % _items.size())
	get_tree().quit()

# 涂色地图（scene/assign_map.gd）的内容是用 draw_texture_rect / draw_rect 在 _draw() 里画的，
# ui_dump 只认「Control 的矩形 / 文字 / 贴图」，抓不到这些绘制调用。
# 所以这里手工补两条：① 一张底图（1 格 = 1 像素的小图，PIL 会按 NEAREST 放大）
#                    ② 每个涂过色的格子一个纯色小方块
func _dump_assign_map(ap: Control) -> void:
	var m = ap.get("_map")
	if m == null:
		return
	var r: Rect2 = m.get_global_rect()
	var o: Vector2 = m._draw_origin()      # 底图左上角（考虑了放缩和平移）
	var t: float = float(m.tile)
	if m._base != null:
		_items.append({
			"tag": "assign", "node": str(m.get_path()), "type": "ImageTexture",
			"kind": "texture", "tex": _tex_path(m._base), "region": null,
			"keep_aspect": false,
			"rect": [r.position.x + o.x, r.position.y + o.y,
				m.map_size_px().x, m.map_size_px().y],
		})
	for c in Slaves.assignments.keys():
		var cv: Vector2i = c
		if not m._in_rect(cv):
			continue
		var col: Color = Slaves.TASK_COLORS.get(int(Slaves.assignments[cv]), Color.WHITE)
		_items.append({
			"tag": "assign", "node": str(m.get_path()), "type": "ColorRect",
			"kind": "box", "fill": _col(col), "border": [0, 0, 0, 0],
			"border_w": [0, 0, 0, 0], "radius": 0,
			"rect": [r.position.x + o.x + (cv.x - m.map_from.x) * t,
				r.position.y + o.y + (cv.y - m.map_from.y) * t, t, t],
		})

# ---------------- 遍历 ----------------
func _dump(n: Node, tag: String, clip: Rect2 = Rect2()) -> void:
	var next_clip := clip
	if n is ScrollContainer:
		# ❗滚动框里的内容超出可视高度是「滚动可达」不是「被挤出屏幕」——
		#   子孙控件按与滚动框可视矩形的交集导出，交集为空的直接跳过。
		#   不然编队名单一长（6 个伙伴就 200 多像素），整页永远体检不过。
		var sc_rect: Rect2 = (n as ScrollContainer).get_global_rect()
		next_clip = sc_rect if clip.size == Vector2.ZERO else clip.intersection(sc_rect)
	if n is Control:
		_dump_control(n as Control, tag, next_clip)
	for c in n.get_children():
		_dump(c, tag, next_clip)

func _dump_control(c: Control, tag: String, clip: Rect2 = Rect2()) -> void:
	if not c.is_visible_in_tree():
		return
	var r := c.get_global_rect()
	if clip.size != Vector2.ZERO:
		r = clip.intersection(r)
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var base := {
		"tag": tag,
		"node": str(c.get_path()),
		"type": c.get_class(),
		"rect": [r.position.x, r.position.y, r.size.x, r.size.y],
	}

	# 背景 / 边框（PanelContainer、Panel、Button 都有一张 StyleBox）
	var sb := _stylebox(c)
	if sb != null:
		var it := base.duplicate()
		it["kind"] = "box"
		it["fill"] = _col(sb.bg_color)
		it["border"] = _col(sb.border_color)
		it["border_w"] = [sb.border_width_left, sb.border_width_top,
			sb.border_width_right, sb.border_width_bottom]
		it["radius"] = sb.corner_radius_top_left
		_items.append(it)

	if c is ColorRect:
		var it := base.duplicate()
		it["kind"] = "box"
		it["fill"] = _col((c as ColorRect).color)
		it["border"] = [0, 0, 0, 0]
		it["border_w"] = [0, 0, 0, 0]
		it["radius"] = 0
		_items.append(it)

	if c is TextureRect:
		var tr := c as TextureRect
		var it := base.duplicate()
		it["kind"] = "texture"
		# AtlasTexture（工具图标那种「从 32x16 里裁一帧」）没有独立文件，
		# 不能走 resource_path。这里把「图集路径 + region」原样交给 PIL 去裁，
		# 免得在 headless 里读 FigureTexture 的像素（会卡死进程）。
		var tex := tr.texture
		if tex is AtlasTexture:
			var at := tex as AtlasTexture
			it["tex"] = at.atlas.resource_path if at.atlas != null else ""
			it["region"] = [at.region.position.x, at.region.position.y,
				at.region.size.x, at.region.size.y]
		else:
			it["tex"] = "" if tex == null else _tex_path(tex)
		it["keep_aspect"] = tr.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_items.append(it)

	if c is Label:
		var l := c as Label
		var it := base.duplicate()
		it["kind"] = "text"
		it["text"] = l.text
		it["size"] = l.get_theme_font_size("font_size")
		it["color"] = _col(l.get_theme_color("font_color"))
		it["align"] = ["left", "center", "right", "fill"][l.horizontal_alignment] \
			if l.horizontal_alignment >= 0 and l.horizontal_alignment <= 3 else "left"
		it["valign"] = ["top", "center", "bottom", "fill"][l.vertical_alignment] \
			if l.vertical_alignment >= 0 and l.vertical_alignment <= 3 else "top"
		it["outline"] = l.get_theme_constant("outline_size")
		it["outline_color"] = _col(l.get_theme_color("font_outline_color"))
		_items.append(it)

	if c is Button:
		var b := c as Button
		var it := base.duplicate()
		it["kind"] = "button"
		it["text"] = b.text
		it["size"] = b.get_theme_font_size("font_size")
		it["color"] = _col(Color(0.88, 0.88, 0.88))
		_items.append(it)

func _stylebox(c: Control) -> StyleBoxFlat:
	for name in ["panel", "normal"]:
		if not c.has_theme_stylebox_override(name) and not c.has_theme_stylebox(name):
			continue
		var sb := c.get_theme_stylebox(name)
		if sb is StyleBoxFlat:
			return sb
	return null

func _col(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]

func _tex_path(tex: Texture2D) -> String:
	if tex.resource_path != "":
		return tex.resource_path
	var id := tex.get_instance_id()
	if _tex_ids.has(id):
		return _tex_ids[id]
	var p := "%s/gen_%02d.png" % [TEX_DIR, _tex_seq]
	_tex_seq += 1
	tex.get_image().save_png(p)
	_tex_ids[id] = p
	return p
