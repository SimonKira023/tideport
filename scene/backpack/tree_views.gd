# tree_views.gd —— 背包面板（backpack_ui.gd）里的三个「树状图」视图
# A3-1 拆出：原为 backpack_ui.gd 的内嵌 class，三者互不引用、只依赖 autoload
# （Legion / Slaves / Research），因此整块搬走即可，行为逐字节不变。
#   SkillTreeView    —— 角色页技能树（e20）
#   ClassTreeView    —— 团队页战斗/劳动职业树（e12）
#   ResearchTreeView —— 科技/行政页文明6式树图
# 宿主用 const 别名 preload(...).Xxx 引用，调用点零改动。

# ═══════════════ 技能树视图（e20: 跟科技树一样摆开, 替代旧的三行卡片）═══════════════
# 五条主干各一棵横树: 主干 Lv1..5 一排 → 5 级分叉 → A/B 两排各 Lv6..10。
# 节点状态: 金底=已点亮 / 绿边=下一个可点(点它升级) / 青边=5 级选支 / 灰=未解锁。
# 5 级未选支时 A/B 首节点就是「选支」按钮, 点了锁死另一条(老规矩)。
class SkillTreeView:
	extends Control

	const FONT := preload("res://resources/font/IPix.ttf")
	const NODE_W := 56.0
	const NODE_H := 22.0
	const GAP_X := 64.0
	const ROW_H := 100.0
	const LEFT_X := 96.0
	const FORK_DY := 24.0

	signal node_clicked(id: String, which: String)   # which="" 升级 / "a"/"b" 选支

	func _init() -> void:
		# 与 _build_hero_page 里的覆盖值保持一致（760, 508）：宽度到第 9 列节点，
		# 高度 = 22 顶距 + 5x100 行距 + 24 分叉下探 + 22 节点高 + 行底小字
		custom_minimum_size = Vector2(760, 508)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func refresh() -> void:
		queue_redraw()

	# 第 idx 棵树的局部原点 y
	func _origin(idx: int) -> float:
		return 22.0 + float(idx) * ROW_H

	# 节点矩形: kind="trunk"(主干 Lv1..5) / "branch"(支线 Lv6..10, which="a"/"b")
	func _rect(id: String, kind: String, which: String, t: int) -> Rect2:
		var row := 0
		for key in Legion.SKILLS.keys():
			if String(key) == id:
				break
			row += 1
		var oy := _origin(row)
		if kind == "trunk":
			return Rect2(LEFT_X + float(t) * GAP_X, oy, NODE_W, NODE_H)
		return Rect2(LEFT_X + float(Legion.SKILL_SPLIT + t) * GAP_X,
			oy - FORK_DY if which == "a" else oy + FORK_DY, NODE_W, NODE_H)

	func _draw() -> void:
		var ids: Array = Legion.SKILLS.keys()
		for row in ids.size():
			var id: String = String(ids[row])
			var info: Dictionary = Legion.SKILLS[id]
			var oy := _origin(row)
			var lv := Legion.skill_lv(id)
			var br := Legion.branch_of(id)
			# 主干名
			draw_string(FONT, Vector2(6, oy + 6), String(info["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, 84, 13, Color(0.95, 0.86, 0.62))
			# 主干连线
			for t in Legion.SKILL_SPLIT - 1:
				var a := _rect(id, "trunk", "", t)
				var b := _rect(id, "trunk", "", t + 1)
				draw_line(Vector2(a.end.x, a.get_center().y),
					Vector2(b.position.x, b.get_center().y),
					Color(0.5, 0.42, 0.3), 2.0)
			# 分叉连线: 主干末节点 → A 首 / B 首(曼哈顿)
			var last := _rect(id, "trunk", "", Legion.SKILL_SPLIT - 1)
			var fa := _rect(id, "branch", "a", 0)
			var fb := _rect(id, "branch", "b", 0)
			var fork_x := last.end.x + 16.0
			var mid := Vector2(fork_x, last.get_center().y)
			draw_line(Vector2(last.end.x, last.get_center().y), mid,
				Color(0.5, 0.42, 0.3), 2.0)
			draw_line(mid, Vector2(fork_x, fa.get_center().y), Color(0.5, 0.42, 0.3), 2.0)
			draw_line(Vector2(fork_x, fa.get_center().y), fa.position, Color(0.5, 0.42, 0.3), 2.0)
			draw_line(mid, Vector2(fork_x, fb.get_center().y), Color(0.5, 0.42, 0.3), 2.0)
			draw_line(Vector2(fork_x, fb.get_center().y), fb.position, Color(0.5, 0.42, 0.3), 2.0)
			# 主干节点
			for t in Legion.SKILL_SPLIT:
				_draw_node(id, "trunk", "", t, lv, br, info)
			# 分支节点
			for t in Legion.SKILL_MAX - Legion.SKILL_SPLIT:
				_draw_node(id, "branch", "a", t, lv, br, info)
				_draw_node(id, "branch", "b", t, lv, br, info)
			# e24: 行底收益标注 —— 主干每级收益 + 已选/两条分支的收益
			# (行内节点带占 oy-24..oy+46, oy+56 往下是行间空带, 正好放一行小字)
			var tip := String(info["desc"])
			var a_info: Dictionary = info["a"]
			var b_info: Dictionary = info["b"]
			if br == "a":
				tip += "   |   %s: %s" % [String(a_info["name"]), String(a_info["desc"])]
			elif br == "b":
				tip += "   |   %s: %s" % [String(b_info["name"]), String(b_info["desc"])]
			else:
				tip += "   |   %s: %s  /  %s: %s" % [String(a_info["name"]),
					String(a_info["desc"]), String(b_info["name"]), String(b_info["desc"])]
			draw_string(FONT, Vector2(LEFT_X, oy + 66), tip,
				HORIZONTAL_ALIGNMENT_LEFT, 660, 10, Color(0.72, 0.66, 0.52))

	func _node_state(id: String, kind: String, which: String, t: int,
			lv: int, br: String) -> Dictionary:
		# 返回 {lit, clickable, dim, text}
		var absolute := t + 1 if kind == "trunk" else Legion.SKILL_SPLIT + t + 1
		var lit := lv >= absolute
		var dim := false
		var clickable := false
		var text := "Lv.%d" % absolute
		if kind == "branch":
			var bn: Dictionary = Legion.SKILLS[id][which]
			text = "%s %d" % [String(bn["name"]), absolute]
			if br != "" and br != which:
				dim = true                     # 没选的那条整排褪色
		if lit:
			return {"lit": true, "clickable": false, "dim": dim, "text": text}
		var sp := Legion.skill_points > 0
		if lv < Legion.SKILL_SPLIT:
			# 主干区: 下一个 = 第 lv+1 级(分支节点全锁)
			if kind == "trunk" and t == lv and sp:
				clickable = true
		else:
			if br == "":
				# 5 级未选支: A/B 首节点 = 选支按钮
				if kind == "branch" and t == 0 and sp:
					clickable = true
					text = "选 %s" % which.to_upper()
			else:
				# 已选支: 选中那条的下一个可升
				if kind == "branch" and which == br and t == lv - Legion.SKILL_SPLIT and sp:
					clickable = true
		return {"lit": false, "clickable": clickable, "dim": dim, "text": text}

	func _draw_node(id: String, kind: String, which: String, t: int,
			lv: int, br: String, info: Dictionary) -> void:
		var r := _rect(id, kind, which, t)
		var st: Dictionary = _node_state(id, kind, which, t, lv, br)
		var bg := Color(0.32, 0.30, 0.27)
		var border := Color(0.45, 0.40, 0.34)
		var txt := Color(0.62, 0.58, 0.52)
		if bool(st["lit"]):
			bg = Color(0.85, 0.68, 0.25)
			border = Color(0.55, 0.40, 0.10)
			txt = Color(0.25, 0.16, 0.05)
		elif bool(st["clickable"]):
			bg = Color(0.30, 0.42, 0.30)
			border = Color(0.55, 0.9, 0.45)
			txt = Color(0.9, 0.95, 0.85)
		if bool(st["dim"]):
			bg.a = 0.4
			border.a = 0.3
			txt.a = 0.35
		draw_rect(r, bg)
		draw_rect(r, border, false, 2.0)
		var ts := FONT.get_string_size(String(st["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(FONT, Vector2(r.position.x + (r.size.x - ts.x) * 0.5,
			r.position.y + r.size.y * 0.5 + 4.0), String(st["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, txt)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var ids: Array = Legion.SKILLS.keys()
		for row in ids.size():
			var id: String = String(ids[row])
			var lv := Legion.skill_lv(id)
			var br := Legion.branch_of(id)
			for t in Legion.SKILL_SPLIT:
				if _rect(id, "trunk", "", t).has_point(mb.position):
					var st: Dictionary = _node_state(id, "trunk", "", t, lv, br)
					if bool(st["clickable"]):
						node_clicked.emit(id, "")
					return
			for which in ["a", "b"]:
				for t in Legion.SKILL_MAX - Legion.SKILL_SPLIT:
					if _rect(id, "branch", which, t).has_point(mb.position):
						var st2: Dictionary = _node_state(id, "branch", which, t, lv, br)
						if bool(st2["clickable"]):
							# 5 级未选支时 A/B 首节点 = 选支(发 which); 已选支 = 升级(发 "")
							node_clicked.emit(id, which if (lv >= Legion.SKILL_SPLIT
								and br == "") else "")
						return

# ═══════════════ 科技/行政树视图（文明6 式）═══════════════
# 一整块 Control：tier 分列的节点卡片 + 前置连线 + 时代列标题 + 淡点阵底。
# 节点可点（点击 = 研究），状态四档：已研究金 / 可研究绿 / 点数未满米 / 前置未开灰。
# 布局算法：先把各列竖排，然后迭代几轮「子节点往父节点中线均值靠拢」，
# 同列按目标 y 排序后自上而下排（挤了就顺延），最后每列整体垂直居中 ——
# 数据量小，几轮就能摆出文明6 那种主干分叉的缠绕感。
# ============ 职业树视图（e12: 团队页两棵树, 摆法仿下面的 ResearchTreeView） ============
# 战斗树（新兵 -> 三岔 -> 二线 -> 满阶）/ 劳动树（帮工起步）都从 CLASSES 表自动推 tier。
# 节点皮肤按「晋升对象」画: 当前职业金边 / 走过的链亮棕 / 可转且钱够绿 / 可转缺钱暗黄 / 无关灰。
class ClassTreeView:
	extends Control

	const FONT := preload("res://resources/font/IPix.ttf")
	const COL_NAMES := ["起步", "一线", "二线", "三线", "四线"]
	# e27g: 尺寸改成变量 —— 详情弹窗里用窄版(compact)把两棵树收进 600 宽的卡片
	var NODE_W := 168.0
	var NODE_H := 42.0
	var COL_GAP := 44.0
	var ROW_GAP := 10.0
	var HEAD_H := 24.0
	var _name_fs := 13
	var _cost_fs := 10

	var labor := false
	var _cb: Callable
	var _cards := {}        # 职业名 -> PanelContainer
	var _rects := {}        # 职业名 -> Rect2
	var _tiers: Array = []  # 每层职业名列表（布局 + 列标题用）
	var _chain: Array = []  # 晋升对象走过的链（根 -> 当前）
	var _cur := ""          # 晋升对象当前职业
	var _targets: Array = []    # 可转职业
	var _afford := {}           # 职业 -> 钱料够不够

	func setup(is_labor: bool, cb: Callable, compact := false) -> void:
		labor = is_labor
		_cb = cb
		if compact:
			# e27g: 详情弹窗里的窄版 —— 卡片收窄/列距收紧/字号小一档
			NODE_W = 136.0
			NODE_H = 38.0
			COL_GAP = 18.0
			ROW_GAP = 8.0
			HEAD_H = 18.0
			_name_fs = 12
			_cost_fs = 9
		mouse_filter = Control.MOUSE_FILTER_PASS
		_build_cards()
		refresh()

	func _table() -> Dictionary:
		return Slaves.LABOR_CLASSES if labor else Slaves.CLASSES

	func _root_id() -> String:
		return "帮工" if labor else "新兵"

	func _prev_of(sid: String) -> String:
		return Slaves.labor_prev_of(sid) if labor else Slaves.prev_of(sid)

	# b10: 这份职业给的具体加成 —— 劳动树念 build/study/labor, 战斗树念攻
	func _benefit_text(sid: String) -> String:
		if labor:
			var d: Dictionary = Slaves.LABOR_CLASSES.get(sid, {})
			var parts: Array = []
			for k in ["build", "study", "labor"]:
				if d.has(k):
					parts.append("%s +%d" % [Slaves.ATTR_NAMES[k], int(d[k])])
			return " / ".join(parts) if not parts.is_empty() else "无特殊收益"
		return "攻 +%d" % int(Slaves.CLASSES.get(sid, {}).get("atk", 0))

	# 外部把晋升对象的上下文喂进来（backpack_ui._refresh_class_trees）
	func set_target(chain: Array, cur: String, targets: Array, afford: Dictionary) -> void:
		_chain = chain
		_cur = cur
		_targets = targets
		_afford = afford
		refresh()

	func _build_cards() -> void:
		for c in get_children():
			c.queue_free()
		_cards.clear()
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(5)
			sb.set_border_width_all(2)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			panel.add_theme_stylebox_override("panel", sb)
			panel.gui_input.connect(_on_card_input.bind(sid))
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(v)
			# e52e: 名字行 = 小图标 + 职业名（图标 16x16 像素风, NEAREST 防糊）
			var name_row := HBoxContainer.new()
			name_row.add_theme_constant_override("separation", 4)
			name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(name_row)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(16, 16)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_row.add_child(icon)
			var name_l := _card_label(_name_fs)
			name_row.add_child(name_l)
			var cost_l := _card_label(_cost_fs)
			cost_l.clip_text = true
			v.add_child(cost_l)
			add_child(panel)
			_cards[sid] = panel
			panel.set_meta("name", name_l)
			panel.set_meta("icon", icon)
			panel.set_meta("cost", cost_l)

	func _card_label(sz: int) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", FONT)
		l.add_theme_font_size_override("font_size", sz)
		return l

	func _on_card_input(ev: InputEvent, sid: String) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _cb.is_valid():
				_cb.call(sid, labor)

	func refresh() -> void:
		var table := _table()
		_layout()
		for id in table.keys():
			var sid := String(id)
			if not _cards.has(sid):
				continue
			var panel: PanelContainer = _cards[sid]
			var on_chain: bool = _chain.has(sid)
			var is_cur := sid == _cur
			var is_target: bool = _targets.has(sid)
			# 四档皮肤: 当前金 / 可转(绿=钱够, 暗黄=缺钱) / 走过亮棕 / 无关灰
			var bg := Color(0.15, 0.125, 0.105, 0.98)
			var border := Color(0.34, 0.3, 0.26)
			var bw := 2
			var name_col := Color(0.62, 0.59, 0.54)
			if is_cur:
				bg = Color(0.34, 0.27, 0.12, 0.98)
				border = Color(1, 0.85, 0.4)
				bw = 3
				name_col = Color(1, 0.9, 0.55)
			elif is_target:
				if bool(_afford.get(sid, false)):
					bg = Color(0.13, 0.22, 0.11, 0.98)
					border = Color(0.55, 0.9, 0.45)
					bw = 3
					name_col = Color(0.78, 0.95, 0.62)
				else:
					bg = Color(0.2, 0.17, 0.1, 0.98)
					border = Color(0.72, 0.6, 0.34)
					name_col = Color(0.9, 0.84, 0.68)
			elif on_chain:
				bg = Color(0.22, 0.18, 0.13, 0.98)
				border = Color(0.85, 0.7, 0.35)
				name_col = Color(0.9, 0.84, 0.68)
			var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
			sb.bg_color = bg
			sb.border_color = border
			sb.set_border_width_all(bw)
			var name_l: Label = panel.get_meta("name")
			name_l.text = sid
			name_l.add_theme_color_override("font_color", name_col)
			# e52e: 职业小图 —— 表里没配或素材缺失时隐藏, 只留名字
			var ic: TextureRect = panel.get_meta("icon")
			ic.texture = Slaves.class_icon_for(sid)
			ic.visible = ic.texture != null
			var cost: Dictionary = table[sid]["cost"]
			var cost_l: Label = panel.get_meta("cost")
			var ct := Slaves.cost_text(cost)
			cost_l.text = "  " + (ct if ct != "" else "免费")
			cost_l.add_theme_color_override("font_color",
				name_col.darkened(0.22) if is_cur or is_target or on_chain
				else Color(0.5, 0.46, 0.42))
			panel.tooltip_text = "%s\n收益: %s\n点一下 = 给晋升对象转到这份职业\n消耗: %s" \
				% [sid, _benefit_text(sid), ct if ct != "" else "免费"]
			panel.position = (_rects[sid] as Rect2).position
		queue_redraw()

	# 布局: 沿 next 推 tier 分列, 子节点往父节点中线靠（同 ResearchTreeView 的收法）
	func _layout() -> void:
		var table := _table()
		var tm := {_root_id(): 0}
		var frontier: Array = [_root_id()]
		var t := 0
		while not frontier.is_empty():
			t += 1
			var nxt: Array = []
			for f in frontier:
				for n in table[String(f)]["next"]:
					if not tm.has(n):
						tm[n] = t
						nxt.append(String(n))
			frontier = nxt
		var maxt := 0
		for id in tm:
			maxt = maxi(maxt, int(tm[id]))
		_tiers.clear()
		for i in maxt + 1:
			_tiers.append([])
		for id in tm:
			_tiers[int(tm[id])].append(String(id))
		for ti in _tiers.size():
			for i in (_tiers[ti] as Array).size():
				_rects[String(_tiers[ti][i])] = Rect2(
					ti * (NODE_W + COL_GAP), HEAD_H + i * (NODE_H + ROW_GAP), NODE_W, NODE_H)
		# 子节点往父节点中线靠, 同列挤了就顺延
		for _i in 3:
			var want := {}
			for id in tm:
				var sid := String(id)
				var req := _prev_of(sid)
				if req == "" or not _rects.has(req):
					continue
				want[sid] = (_rects[req] as Rect2).get_center().y - NODE_H * 0.5
			for ti in _tiers.size():
				var list: Array = _tiers[ti]
				list.sort_custom(func(a, b) -> bool:
					var wa: float = float(want.get(a, (_rects[a] as Rect2).position.y))
					var wb: float = float(want.get(b, (_rects[b] as Rect2).position.y))
					return wa < wb)
				var prev_bottom := -1.0e9
				for id in list:
					var sid := String(id)
					var rc: Rect2 = _rects[sid]
					rc.position.y = maxf(float(want.get(sid, rc.position.y)),
						prev_bottom + ROW_GAP)
					_rects[sid] = rc
					prev_bottom = rc.position.y + NODE_H
		var max_h := 0.0
		for ti in _tiers.size():
			var list: Array = _tiers[ti]
			max_h = maxf(max_h, (_rects[String(list[list.size() - 1])] as Rect2).end.y)
		var cols: int = _tiers.size()
		custom_minimum_size = Vector2(cols * (NODE_W + COL_GAP) - COL_GAP, max_h + 6.0)

	func _draw() -> void:
		var sz := custom_minimum_size
		var dot := Color(1, 1, 1, 0.045)
		var gx := 14.0
		while gx < sz.x:
			var gy := 14.0
			while gy < sz.y:
				draw_rect(Rect2(gx, gy, 1.5, 1.5), dot)
				gy += 26.0
			gx += 26.0
		# 列标题（起步/一线/二线/...）
		for ti in _tiers.size():
			var x := float(ti) * (NODE_W + COL_GAP)
			draw_rect(Rect2(x, 4, NODE_W - 10, 3), Color(0.45, 0.38, 0.26, 0.5))
			draw_string(FONT, Vector2(x, HEAD_H - 4.0),
				String(COL_NAMES[mini(ti, COL_NAMES.size() - 1)]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.62, 0.46))
		# 父 -> 子连线（曼哈顿折线 + 箭头）: 两端都在链上就描金
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var req := _prev_of(sid)
			if req == "" or not _rects.has(req):
				continue
			var ra: Rect2 = _rects[req]
			var rb: Rect2 = _rects[sid]
			var p0 := Vector2(ra.end.x, ra.get_center().y)
			var p3 := Vector2(rb.position.x, rb.get_center().y)
			var mid := (p0.x + p3.x) * 0.5
			var col := Color(0.33, 0.28, 0.21, 0.85)
			var w := 2.0
			var both_on: bool = _chain.has(sid) and (_chain.has(String(req)) or _cur == req)
			var gold: bool = _chain.has(sid) and _chain.has(String(req))
			if gold:
				col = Color(0.98, 0.83, 0.4, 0.95)
				w = 3.0
			elif _targets.has(sid):
				col = Color(0.5, 0.7, 0.38, 0.75) if bool(_afford.get(sid, false)) \
					else Color(0.72, 0.6, 0.34, 0.75)
			elif both_on:
				col = Color(0.85, 0.7, 0.35, 0.8)
			draw_line(p0, Vector2(mid, p0.y), col, w)
			draw_line(Vector2(mid, p0.y), Vector2(mid, p3.y), col, w)
			draw_line(Vector2(mid, p3.y), p3 + Vector2(2, 0), col, w)
			var tri := PackedVector2Array([
				p3 + Vector2(8, 0), p3 + Vector2(-1, -4.5), p3 + Vector2(-1, 4.5)])
			draw_colored_polygon(tri, col)

class ResearchTreeView:
	extends Control

	const FONT := preload("res://resources/font/IPix.ttf")

	const NODE_W := 174.0
	const NODE_H := 66.0
	const COL_GAP := 34.0        # 列间距（留出连线走廊）
	const ROW_GAP := 14.0
	const HEAD_H := 26.0         # 顶部：时代列标题占的高度

	const TIER_NAMES := {
		"tech": ["初启", "革新", "跃迁"],
		"admin": ["奠基", "建制", "扩张", "中枢"],
	}

	var kind := "tech"
	var _cb: Callable
	var _cards := {}             # id -> PanelContainer（节点卡）
	var _rects := {}             # id -> Rect2（当前布局）

	func setup(k: String, cb: Callable) -> void:
		kind = k
		_cb = cb
		mouse_filter = Control.MOUSE_FILTER_PASS
		_build_cards()
		refresh()

	func card_of(id: String) -> PanelContainer:
		return _cards.get(id)

	func _table() -> Dictionary:
		return Research.TECHS if kind == "tech" else Research.ADMINS

	func _done(id: String) -> bool:
		return Research.has_tech(id) if kind == "tech" else Research.has_admin(id)

	func _ready_ok(id: String) -> bool:
		return Research.tech_ready(id) if kind == "tech" else Research.admin_ready(id)

	func _can(id: String) -> bool:
		return Research.can_research_tech(id) if kind == "tech" \
			else Research.can_research_admin(id)

	func _summary(id: String) -> String:
		return Research.tech_summary(id) if kind == "tech" else Research.admin_summary(id)

	# ---------------- 建节点卡 ----------------
	func _build_cards() -> void:
		for c in get_children():
			c.queue_free()
		_cards.clear()
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(5)
			sb.set_border_width_all(2)
			sb.content_margin_left = 9
			sb.content_margin_right = 9
			sb.content_margin_top = 5
			sb.content_margin_bottom = 5
			panel.add_theme_stylebox_override("panel", sb)
			panel.gui_input.connect(_on_card_input.bind(sid))
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			panel.mouse_entered.connect(_on_card_hover.bind(panel, true))
			panel.mouse_exited.connect(_on_card_hover.bind(panel, false))

			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(v)
			var nh := HBoxContainer.new()
			nh.add_theme_constant_override("separation", 5)
			nh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(nh)
			var icon := TextureRect.new()
			icon.texture = Research.icon_for(sid)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(16, 16)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nh.add_child(icon)
			var name_l := _card_label(13)
			nh.add_child(name_l)
			var desc_l := _card_label(10)
			desc_l.clip_text = true
			v.add_child(desc_l)
			var st_l := _card_label(10)
			v.add_child(st_l)
			add_child(panel)
			_cards[sid] = panel
			panel.set_meta("name", name_l)
			panel.set_meta("desc", desc_l)
			panel.set_meta("state", st_l)

	func _card_label(sz: int) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", FONT)
		l.add_theme_font_size_override("font_size", sz)
		return l

	func _on_card_hover(panel: Control, over: bool) -> void:
		panel.modulate = Color(1.14, 1.12, 1.04) if over else Color(1, 1, 1)

	func _on_card_input(ev: InputEvent, id: String) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _cb.is_valid():
				_cb.call(id, kind)

	# ---------------- 刷新：重摆位置 + 换状态皮肤 ----------------
	func refresh() -> void:
		var table := _table()
		_layout()
		for id in table.keys():
			var sid := String(id)
			if not _cards.has(sid):
				continue
			var panel: PanelContainer = _cards[sid]
			var info: Dictionary = table[sid]
			var done := _done(sid)
			var ready := _ready_ok(sid)
			var can := _can(sid)
			# 四档配色
			var bg := Color(0.15, 0.125, 0.105, 0.98)
			var border := Color(0.34, 0.3, 0.26)
			var bw := 2
			var name_col := Color(0.62, 0.59, 0.54)
			var st_col := Color(0.5, 0.46, 0.42)
			if done:
				bg = Color(0.34, 0.27, 0.12, 0.98)
				border = Color(1, 0.85, 0.4)
				bw = 3
				name_col = Color(1, 0.9, 0.55)
				st_col = Color(0.95, 0.82, 0.45)
			elif can:
				bg = Color(0.13, 0.22, 0.11, 0.98)
				border = Color(0.55, 0.9, 0.45)
				bw = 3
				name_col = Color(0.78, 0.95, 0.62)
				st_col = Color(0.6, 0.9, 0.48)
			elif ready:
				bg = Color(0.19, 0.155, 0.11, 0.98)
				border = Color(0.72, 0.6, 0.34)
				name_col = Color(0.9, 0.84, 0.68)
				st_col = Color(0.8, 0.72, 0.55)
			var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
			sb.bg_color = bg
			sb.border_color = border
			sb.set_border_width_all(bw)
			var name_l: Label = panel.get_meta("name")
			name_l.text = "%s  %d 点" % [info["name"], int(info["cost"])]
			name_l.add_theme_color_override("font_color", name_col)
			var desc_l: Label = panel.get_meta("desc")
			desc_l.text = "  " + str(info["desc"])
			desc_l.add_theme_color_override("font_color",
				Color(0.85, 0.76, 0.5) if done else name_col.darkened(0.22))
			var st_l: Label = panel.get_meta("state")
			st_l.text = "  " + _summary(sid)
			st_l.add_theme_color_override("font_color", st_col)
			panel.tooltip_text = "%s\n%s\n%s" % [info["name"], info["desc"], _summary(sid)]
			panel.position = (_rects[sid] as Rect2).position
		queue_redraw()

	# ---------------- 布局：tier 分列 + 朝父节点中线收敛 ----------------
	func _layout() -> void:
		var table := _table()
		var tiers := {}
		for id in table.keys():
			var t := int(table[id]["tier"])
			if not tiers.has(t):
				tiers[t] = []
			tiers[t].append(String(id))
		# 第一遍：每列自上而下堆
		for t in tiers.keys():
			var list: Array = tiers[t]
			for i in list.size():
				_rects[String(list[i])] = Rect2(
					(int(t) - 1) * (NODE_W + COL_GAP), HEAD_H + i * (NODE_H + ROW_GAP),
					NODE_W, NODE_H)
		# 迭代对齐：子节点往「各前置节点中线均值」靠，同列挤了就顺延
		for _i in 3:
			var want := {}
			for id in table.keys():
				var sid := String(id)
				var reqs: Array = table[sid]["req"]
				if reqs.is_empty():
					continue
				var sum := 0.0
				for r in reqs:
					sum += (_rects[String(r)] as Rect2).get_center().y
				want[sid] = sum / float(reqs.size()) - NODE_H * 0.5
			for t in tiers.keys():
				var list: Array = tiers[t]
				list.sort_custom(func(a, b) -> bool:
					var wa: float = float(want.get(a, (_rects[a] as Rect2).position.y))
					var wb: float = float(want.get(b, (_rects[b] as Rect2).position.y))
					return wa < wb)
				var prev_bottom := -1.0e9
				for id in list:
					var sid := String(id)
					var rc: Rect2 = _rects[sid]
					rc.position.y = maxf(float(want.get(sid, rc.position.y)),
						prev_bottom + ROW_GAP)
					_rects[sid] = rc
					prev_bottom = rc.position.y + NODE_H
		# 每列整体垂直居中（相对最高的那列）
		var max_h := 0.0
		for t in tiers.keys():
			var list: Array = tiers[t]
			max_h = maxf(max_h, (_rects[String(list[list.size() - 1])] as Rect2).end.y)
		for t in tiers.keys():
			var list: Array = tiers[t]
			var top := (_rects[String(list[0])] as Rect2).position.y
			var bottom := (_rects[String(list[list.size() - 1])] as Rect2).end.y
			var off := (max_h - (bottom - top)) * 0.5 - top
			for id in list:
				var sid := String(id)
				var rc: Rect2 = _rects[sid]
				rc.position.y += off
				_rects[sid] = rc
		var cols := tiers.keys().size()
		custom_minimum_size = Vector2(cols * (NODE_W + COL_GAP) - COL_GAP, max_h + 6.0)

	# ---------------- 画：点阵底 + 列标题 + 前置连线 + 箭头 ----------------
	func _draw() -> void:
		var sz := custom_minimum_size
		var dot := Color(1, 1, 1, 0.045)
		var gx := 14.0
		while gx < sz.x:
			var gy := 14.0
			while gy < sz.y:
				draw_rect(Rect2(gx, gy, 1.5, 1.5), dot)
				gy += 26.0
			gx += 26.0
		# 时代列标题（短横线 + 字）
		var names: Array = TIER_NAMES.get(kind, [])
		for t in names.size():
			var x := float(t) * (NODE_W + COL_GAP)
			draw_rect(Rect2(x, 4, NODE_W - 10, 3), Color(0.45, 0.38, 0.26, 0.5))
			draw_string(FONT, Vector2(x, 23), str(names[t]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.62, 0.46))
		# 前置连线：曼哈顿折线（右出 -> 中途拐 -> 左进）+ 箭头
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var done_id := _done(sid)
			for r in table[sid]["req"]:
				var rid := String(r)
				if not _rects.has(rid):
					continue
				var ra: Rect2 = _rects[rid]
				var rb: Rect2 = _rects[sid]
				var p0 := Vector2(ra.end.x, ra.get_center().y)
				var p3 := Vector2(rb.position.x, rb.get_center().y)
				var mid := (p0.x + p3.x) * 0.5
				var col := Color(0.33, 0.28, 0.21, 0.85)
				var w := 2.0
				if done_id and _done(rid):
					col = Color(0.98, 0.83, 0.4, 0.95)
					w = 3.0
				elif done_id or _done(rid):
					col = Color(0.85, 0.7, 0.35, 0.8)
				elif _ready_ok(sid):
					col = Color(0.5, 0.7, 0.38, 0.75)
				draw_line(p0, Vector2(mid, p0.y), col, w)
				draw_line(Vector2(mid, p0.y), Vector2(mid, p3.y), col, w)
				draw_line(Vector2(mid, p3.y), p3 + Vector2(2, 0), col, w)
				var tri := PackedVector2Array([
					p3 + Vector2(8, 0), p3 + Vector2(-1, -4.5), p3 + Vector2(-1, 4.5)])
				draw_colored_polygon(tri, col)
