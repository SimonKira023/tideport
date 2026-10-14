# romance_ui.gd —— 恋爱界面弹窗（恋爱线专属）
#
# 「恋爱互动」点开后在这里挑一件小事做：
#   · 顶部显示心动值条（* 实格 / . 空格，0..10）
#   · 中间列六个互动（牵手散步/并肩看云/分吃点心/月下相拥/额头轻吻/灯下夜话），
#     按心里话段数逐个解锁，每天一次；「灯下夜话」是婚后专属
#   · 点下去显示一句甜蜜台词反馈，心动值上涨
#   · 只有六位可婚姑娘有恋爱线；其他伙伴显示好感线兜底文案
#
# 调用方（dialogue_ui 对话窗 / backpack_ui 团队详情页）：
#   var rui := preload("res://romance_ui.gd").new()
#   add_child(rui)
#   rui.closed.connect(_refresh)         # 关掉后调用方刷新界面
#   rui.open_for(slave_index)
# ❗数值账全在 Marriage.do_romance 里落，这里只负责挑动作 + 演出台词。
extends Control

signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _slave_index := -1
var _title: Label
var _love_label: Label
var _status_label: Label
var _line_label: Label
var _list_box: VBoxContainer
var _close_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 全屏半透明遮罩
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.14, 0.11, 0.09, 0.97)
	ps.border_color = Color(0.62, 0.47, 0.28)
	ps.set_border_width_all(3)
	ps.set_corner_radius_all(8)
	ps.content_margin_left = 20
	ps.content_margin_right = 20
	ps.content_margin_top = 14
	ps.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", ps)
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title = _mk_label("", 18, Color(1, 0.88, 0.86), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title)
	_love_label = _mk_label("", 14, Color(0.98, 0.75, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_love_label)
	_status_label = _mk_label("", 12, Color(0.80, 0.72, 0.68), HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	vbox.add_child(_mk_label("---", 11, Color(0.72, 0.64, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# 台词反馈区：互动后在这里显示一句甜蜜的话
	_line_label = _mk_label("做点小事情, 攒一点心动.", 13,
		Color(0.98, 0.88, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(420, 0)
	vbox.add_child(_line_label)

	# 互动列表区：内容多时限高滚动
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, clampf(get_viewport_rect().size.y - 300.0, 140.0, 330.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	_close_btn = Button.new()
	_close_btn.text = "今天就到这"
	_close_btn.custom_minimum_size = Vector2(0, 30)
	_close_btn.add_theme_font_override("font", PIXEL_FONT)
	_close_btn.add_theme_font_size_override("font_size", 13)
	_close_btn.pressed.connect(close)
	vbox.add_child(_close_btn)

func _mk_label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# 打开给第 slave_index 位伙伴的恋爱界面（先建列表再显示）
func open_for(slave_index: int) -> void:
	_slave_index = slave_index
	var s: Dictionary = Slaves.slave_at(slave_index)
	if s.is_empty():
		return
	var id := Slaves.roster_id(slave_index)
	if not Marriage.is_bride(id):
		# 非可婚对象：好感线兜底文案（恋爱线只对六位姑娘开放）
		_title.text = "%s" % str(s["name"])
		_love_label.text = "好感线: 并肩伙伴"
		_status_label.text = "(恋爱线只对六位姑娘开放, 想拉近距离就多送点 Ta 喜欢的东西)"
		_line_label.text = "Ta 笑了笑, 拍了拍你的肩膀."
		_close_btn.text = "回去干活"
		_refresh_list_fallback()
		show()
		return
	_close_btn.text = "今天就到这"
	_refresh()
	show()

func close() -> void:
	_slave_index = -1
	hide()
	closed.emit()

# 非 bride 的兜底列表：一句话说明 + 关闭提示
func _refresh_list_fallback() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var tip := _mk_label("好感线: 赠送礼物攒好感, 好感提升战斗加成.\n恋爱线: 等你遇到对的人再开启.",
		12, Color(0.78, 0.74, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	tip.custom_minimum_size = Vector2(420, 60)
	_list_box.add_child(tip)

# 刷新心动条 + 状态行 + 互动列表（bride 路径）
func _refresh() -> void:
	var id := Slaves.roster_id(_slave_index)
	var sname := String(Slaves.slave_at(_slave_index)["name"])
	_title.text = "与 %s 的恋爱时光" % sname
	# 心动条：* 实格 . 空格（IPix 没有爱心字形, 用星号代替）
	var lv := Marriage.love_of(id)
	var bar := ""
	for i in Marriage.LOVE_MAX:
		bar += "* " if i < lv else ". "
	_love_label.text = "心动 %d/%d  %s" % [lv, Marriage.LOVE_MAX, bar.strip_edges()]
	# 状态行：未婚报心里话进度, 已婚报婚姻纪念 + 专属 perk
	if Marriage.is_married_to(id):
		var pk: Dictionary = Marriage.perk()
		_status_label.text = "已婚 第 %d 天  %s" % [Marriage.married_day,
			String(pk.get("desc", "")) if not pk.is_empty() else ""]
	else:
		_status_label.text = "心里话 %d/5 段  (篝火聊天解锁更多互动)" % Marriage.stage(id)
	# 今天互动过没：过了就在台词区提醒
	if Marriage.romance_done_today(id):
		_line_label.text = "今天已经约过会了, 明天再来吧."
	_refresh_list()

# 重列一遍互动（每行一个按钮；不可做的灰显并写明原因）
func _refresh_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var id := Slaves.roster_id(_slave_index)
	var done_today := Marriage.romance_done_today(id)
	for a in Marriage.ROMANCE_ACTIONS:
		var ok := Marriage.romance_action_ok(a, id)
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 32)
		row.add_theme_font_override("font", PIXEL_FONT)
		row.add_theme_font_size_override("font_size", 13)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 行文案：名字 + 心动增量 / 灰显原因
		if bool(a["married"]) and not Marriage.is_married_to(id):
			row.text = "%s  (婚后专属)" % String(a["name"])
			row.disabled = true
		elif Marriage.stage(id) < int(a["need"]) and not Marriage.is_married_to(id):
			row.text = "%s  (需心里话第 %d 段)" % [String(a["name"]), int(a["need"])]
			row.disabled = true
		elif done_today:
			row.text = "%s  +%d 心动" % [String(a["name"]), int(a["love"])]
			row.disabled = true
		else:
			row.text = "%s  +%d 心动" % [String(a["name"]), int(a["love"])]
			row.pressed.connect(_on_action_pressed.bind(String(a["id"])))
		# 能做的行染上暖色, 一眼认得出
		if ok:
			row.add_theme_color_override("font_color", Color(0.99, 0.80, 0.86))
		_list_box.add_child(row)

func _on_action_pressed(action_id: String) -> void:
	Audio.play_sfx("ui_click")
	var id := Slaves.roster_id(_slave_index)
	var r: Dictionary = Marriage.do_romance(id, action_id)
	if bool(r.get("ok", false)):
		_line_label.text = "%s  (+%d 心动)" % [String(r["line"]), int(r["gain"])]
		if bool(r.get("full", false)):
			_line_label.text += "\n心动已满, 你们的感情稳定升温中."
	else:
		match String(r.get("reason", "")):
			"done_today":
				_line_label.text = "今天已经约过会了, 明天再来吧."
			"not_married":
				_line_label.text = "这一件, 要等婚后才合适."
			"locked":
				_line_label.text = "再多聊聊心里话, 才好往前一步."
			_:
				_line_label.text = "现在不太合适."
	_refresh()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
