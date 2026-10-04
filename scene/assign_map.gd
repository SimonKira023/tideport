# assign_map.gd —— 夜晚任务分配面板里那张「能涂色的地图」
#
# 它继承 scene/terrain_map.gd（真实地形 + 滚轮放缩 + 拖拽平移），在上面加了「涂色派活」：
#   · 左键（按住拖）  = 给这一片地派活
#   · 右键单击        = 擦掉这一格；右键**拖** = 平移视角
#   · 中键拖拽        = 平移视角
#   · 滚轮            = 放缩
#
# 只能往**农田**上派（耕地 / 已播种）；水面和草地都不行（见 can_paint）。
#
# ❗底图跟「格子实际状态」会变（白天新锄的地、刚播的种），所以**每次开面板都要重画**
#   （refresh），不能只在 setup 时画一次。
extends "res://scene/terrain_map.gd"

var tool := 0                  # 当前工种；0 = 橡皮
var hover := Vector2i(9999, 9999)
var _painting := 0             # 1 = 左键正按着涂
var deny_cell := Vector2i(9999, 9999)   # e28e: 最后一次「额度已满」吃瘪的格子（挪开鼠标/涂上了就消）

# ---------------- 画（在地形之上再画「已派活」和高亮）----------------
func _draw() -> void:
	super._draw()
	var o := _draw_origin()
	# 已涂的格子
	for c in Slaves.assignments.keys():
		var cv: Vector2i = c
		if not _in_rect(cv):
			continue
		var col: Color = Slaves.TASK_COLORS.get(int(Slaves.assignments[cv]), Color.WHITE)
		var p := o + (Vector2(cv) - Vector2(map_from)) * float(tile)
		# 今天已经干完的：压暗 + 中间点一个亮点，白天回来一看就知道进度
		if Slaves.is_done(cv):
			col = col.darkened(0.55)
			draw_rect(Rect2(p, Vector2(tile, tile)), col, true)
			var d: float = maxf(2.0, tile / 3.0)
			draw_rect(Rect2(p + Vector2(tile * 0.5 - d * 0.5, tile * 0.5 - d * 0.5),
				Vector2(d, d)), Color(1, 1, 1, 0.9), true)
		else:
			draw_rect(Rect2(p, Vector2(tile, tile)), col, true)
	# 鼠标高亮的格子（不能派活的格子用红框提示）
	if _in_rect(hover):
		var p2 := o + (Vector2(hover) - Vector2(map_from)) * float(tile)
		var ok := can_paint(hover)
		draw_rect(Rect2(p2, Vector2(tile, tile)),
			Color(1, 1, 1, 0.85) if ok else Color(1, 0.35, 0.35, 0.9), false, 1.0)
	# e28e: 刚才「额度已满」吃瘪的格子 —— 蒙一层红罩子，让玩家知道刚才点它没涂上
	if _in_rect(deny_cell):
		var p3 := o + (Vector2(deny_cell) - Vector2(map_from)) * float(tile)
		draw_rect(Rect2(p3, Vector2(tile, tile)), Color(1, 0.2, 0.2, 0.45), true)
		draw_rect(Rect2(p3, Vector2(tile, tile)), Color(1, 0.3, 0.3, 0.95), false, 2.0)

# ---------------- 输入 ----------------
# ❗基类的「左键拖拽 = 平移」在这里被改写掉了：左键要留给涂色。
#   平移改走中键，以及「右键拖」（右键只是点一下的话仍然算擦除）。
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_by(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			accept_event()
			return
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					_painting = 1
					_paint(cell_at(mb.position))
				MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
					_drag_btn = mb.button_index
					_drag_last = mb.position
					_dragged = false
			accept_event()
			return
		# —— 松开 ——
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = 0
		elif _drag_btn == mb.button_index:
			# 右键按下后没怎么动 -> 当成「擦掉这一格」；拖过了就是在平移视角
			if mb.button_index == MOUSE_BUTTON_RIGHT and not _dragged:
				if Slaves.erase(cell_at(mb.position)):
					queue_redraw()
			_drag_btn = -1
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _drag_btn >= 0:
			var d := mm.position - _drag_last
			_drag_last = mm.position
			if d.length() > DRAG_DEAD:
				_dragged = true
			pan_by(d)
			accept_event()
			return
		var nc := cell_at(mm.position)
		if nc != hover:
			hover = nc
			if nc != deny_cell:
				deny_cell = Vector2i(9999, 9999)   # e28e: 鼠标挪走了红罩就消
			queue_redraw()
		if _painting == 1:
			_paint(nc)

# ---------------- 哪些格子能派活 ----------------
# 只能是**农田**：耕过的地（含已经播了种的）。
#   · 水面不行 —— 伙伴没法站水里干活
#   · 草地不行 —— 野草地上浇什么水？先自己锄成耕地再说
func is_farmland(c: Vector2i) -> bool:
	return Farm.tilled.has(c) or Farm.crops.has(c)

func can_paint(c: Vector2i) -> bool:
	if not _in_rect(c):
		return false
	if game != null and game.has_method("is_water") and game.is_water(c):
		return false
	return is_farmland(c)

# 涂一格；额度用完了就蒙红罩提示（Slaves 会拦）
func _paint(c: Vector2i) -> void:
	if tool == 0:
		if Slaves.erase(c):
			queue_redraw()
		return
	if not can_paint(c):
		return
	if Slaves.assign(c, tool):
		deny_cell = Vector2i(9999, 9999)   # e28e: 涂上了就把红罩收掉
		queue_redraw()
	elif deny_cell != c:
		deny_cell = c                      # e28e: 没涂上多半是额度满了，标记这格
		queue_redraw()

func _notification(what: int) -> void:
	# 鼠标移出地图：把高亮收掉
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = Vector2i(9999, 9999)
		deny_cell = Vector2i(9999, 9999)   # e28e: 红罩一并收掉
		queue_redraw()
