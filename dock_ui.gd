# dock_ui.gd —— 废弃码头面板（走到码头按 F 打开）
#
# 一个面板管三件事，按码头当前的状态换内容：
#   · 废墟   —— 列出修码头要的钱和材料，付得起就 [动工]
#   · 待施工 —— 显示施工进度（人天），并提醒去派活面板派人
#   · 建成   —— [出海] 大按钮 + 船队清单 + [造一条船]
# 出海只能从这个面板走（制作台不再造船），船永远停在码头。
extends Control

signal opened
signal closed
signal depart_requested      # 面板上点了「出海」（game.gd 接过去问 Voyage 同不同意）

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const PANEL_W := 420

var _visible := false
var _guard := 0.0             # 刚打开的这一小会儿不吃输入（免得开面板那一下 F 把面板关了）
var _body: VBoxContainer = null
var _root: VBoxContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()
	Voyage.dock_changed.connect(func(): if _visible: _rebuild())
	Slaves.changed.connect(func(): if _visible: _rebuild())

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

# ---------------- 搭界面 ----------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var card := ColorRect.new()
	card.color = Color(0.11, 0.10, 0.13, 0.97)
	card.custom_minimum_size = Vector2(PANEL_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	_root = VBoxContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("margin_left", 18)
	_root.add_theme_constant_override("margin_right", 18)
	_root.add_theme_constant_override("margin_top", 16)
	_root.add_theme_constant_override("margin_bottom", 16)
	_root.add_theme_constant_override("separation", 8)
	card.add_child(_root)

# ---------------- 刷新 ----------------
func _rebuild() -> void:
	if _root == null:
		return
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

	_root.add_child(_label(_title_text(), 19, Color(1, 0.93, 0.76),
		HORIZONTAL_ALIGNMENT_CENTER))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	_root.add_child(_body)

	match Voyage.dock_state:
		Voyage.DOCK_FUNDED:
			_build_funded()
		Voyage.DOCK_BUILT:
			_build_built()
		_:
			_build_ruin()

	_root.add_child(_label(_foot_text(), 11,
		Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))

# 底部那行操作说明。❗只有建成（能出海）时 F 才有「出海」这层意思，
#   废墟/施工中还写着「F 出海」会让玩家以为按一下就走了。
func _foot_text() -> String:
	if Voyage.dock_state == Voyage.DOCK_BUILT:
		return "F 出海 / 再按一次 F 关闭  -  Esc 关闭"
	return "F / Esc 关闭  -  夜里在派活面板安排人手"

func _title_text() -> String:
	match Voyage.dock_state:
		Voyage.DOCK_FUNDED:
			return "废弃码头 - 施工中"
		Voyage.DOCK_BUILT:
			return "码头"
		_:
			return "废弃码头"

# —— 废墟：列出账单，付得起就动工 ——
func _build_ruin() -> void:
	_body.add_child(_label(
		"这码头烂了很多年, 桩子都朽了.\n修好它才能造船, 也才能出海.",
		12, Color(0.82, 0.78, 0.70)))
	_body.add_child(_label("修码头要这些:", 13, Color(1, 0.93, 0.76)))
	var ok := true
	for e in Voyage.dock_bill():
		var have := int(e["have"])
		var need := int(e["need"])
		if have < need:
			ok = false
		_body.add_child(_label("  %s  %d / %d" % [str(e["name"]), have, need],
			12, Color(0.55, 0.85, 0.5) if have >= need else Color(1, 0.55, 0.5)))
	_body.add_child(_label("动工之后, 夜里在派活面板派人来修.", 11,
		Color(0.66, 0.62, 0.55)))
	var b := _button("动工 (付钱和材料)", PANEL_W - 60)
	b.disabled = not ok
	b.pressed.connect(func():
		if Voyage.fund_dock():
			Audio.play_sfx("ui_click", -6.0)
			_rebuild()
		else:
			Audio.play_sfx("error", -8.0))
	_body.add_child(_hwrap(b))

# —— 待施工：进度 + 提醒派人 ——
func _build_funded() -> void:
	_body.add_child(_label("材料和钱都备齐了, 就差人干活.", 12, Color(0.82, 0.78, 0.70)))
	_body.add_child(_label("施工进度   %d / %d 人天" % [Voyage.dock_work, Voyage.DOCK_WORK],
		15, Color(1, 0.88, 0.62), HORIZONTAL_ALIGNMENT_CENTER))
	# 进度条（一根底衬 + 一根填充）
	var bar := ColorRect.new()
	bar.color = Color(0.22, 0.20, 0.24)
	bar.custom_minimum_size = Vector2(PANEL_W - 60, 12)
	var fill := ColorRect.new()
	fill.color = Color(0.85, 0.68, 0.30)
	var w := float(PANEL_W - 60) * clampf(float(Voyage.dock_work) / float(Voyage.DOCK_WORK), 0.0, 1.0)
	fill.custom_minimum_size = Vector2(w, 12)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(fill)
	_body.add_child(_hwrap(bar))
	_body.add_child(_label("今天派了 %d 人" % Slaves.dock_heads(), 12, Color(0.9, 0.86, 0.78),
		HORIZONTAL_ALIGNMENT_CENTER))
	_body.add_child(_label(
		"夜里睡觉前那张派活面板里\n勾上修码头, 派人过来.\n一个人干一天 = 1 人天.",
		11, Color(0.66, 0.62, 0.55)))

# —— 建成：出海 + 船队 + 造船 ——
func _build_built() -> void:
	var why: String = Voyage.depart_block_reason(null)
	var b := _button("出海 (F)", PANEL_W - 60)
	b.disabled = (why != "")
	if why != "":
		_body.add_child(_label(why, 12, Color(1, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
	b.pressed.connect(func(): depart_requested.emit())
	_body.add_child(_hwrap(b))

	_body.add_child(_label(
		"船 %d 艘 - 能载 %d 人\n出海 %d 人 (你 + %d 个伙伴, 全员自动) - 要 %d 艘" % [
			Voyage.boat_count, Voyage.seats(), Voyage.party_size(),
			Slaves.count, Voyage.boats_needed()],
		12, Color(0.86, 0.82, 0.74), HORIZONTAL_ALIGNMENT_CENTER))

	_body.add_child(_label("造一条船 (一船两人):", 13, Color(1, 0.93, 0.76)))
	var ok := true
	for e in Voyage.boat_bill(true):
		var have := int(e["have"])
		var need := int(e["need"])
		if have < need:
			ok = false
		_body.add_child(_label("  %s  %d / %d" % [str(e["name"]), have, need],
			12, Color(0.55, 0.85, 0.5) if have >= need else Color(1, 0.55, 0.5)))
	var bb := _button("造一条船", PANEL_W - 60)
	bb.disabled = not ok
	bb.pressed.connect(func():
		if Voyage.build_boat():
			Audio.play_sfx("plant", -8.0)
			_rebuild()
		else:
			Audio.play_sfx("error", -8.0))
	_body.add_child(_hwrap(bb))
	_body.add_child(_label("船造好就停在码头, 走不掉.", 11, Color(0.66, 0.62, 0.55)))

# ---------------- 小工具 ----------------
func _hwrap(c: Control) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(c)
	return h

func _button(text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 34)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 14)
	return b

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ---------------- 开关 ----------------
func open_panel() -> void:
	if _visible:
		return
	_visible = true
	_rebuild()
	show()
	TimeManager.push_ui_pause()      # 在码头挑船的时候时间停住
	Audio.play_sfx("ui_open", -6.0)
	opened.emit()
	_guard = 0.28

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	TimeManager.pop_ui_pause()
	Audio.play_sfx("ui_close", -8.0)
	closed.emit()

func is_open() -> bool:
	return _visible

func _input(event: InputEvent) -> void:
	if not _visible or _guard > 0.0:
		return
	# 面板开着的时候 F = 出海（跟按钮一个意思），Esc = 关掉。
	# ❗用 _input 而不是 _unhandled_input：这样才能抢在 game.gd 前面把 F 吃掉。
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if Voyage.dock_state == Voyage.DOCK_BUILT:
			depart_requested.emit()
		else:
			close_panel()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
