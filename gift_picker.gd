# gift_picker.gd —— e56 赠送选物弹窗
#
# 「赠送」点开后在这里挑一份背包里的东西送出去：
#   · 只列 作物 / 食物 / 材料 三类（Slaves.GIFT_TYPES 白名单）——
#     工具 / 装备 / 种子 / 地板 / 船这些「道具」不收，不进列表
#   · 顶部提示这位伙伴的爱好（送中 x2 好感）和生日提示（今天生日增量再 x2）
#
# 调用方（dialogue_ui 对话窗 / backpack_ui 团队详情页）：
#   var gp := preload("res://gift_picker.gd").new()
#   add_child(gp)
#   gp.picked.connect(_on_gift_picked)   # picked(item: ItemData) -> 调用方落账 give + 扣背包
#   gp.open_for(slave_index)
# ❗物品只在 picked 信号里交出去，这里不动背包 —— 扣账统一由调用方做（跟 give 配对）。
extends Control

signal picked(item: ItemData)
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _slave_index := -1
var _title: Label
var _like_label: Label
var _list_box: VBoxContainer

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

	_title = _mk_label("", 18, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title)
	_like_label = _mk_label("", 13, Color(0.95, 0.7, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	_like_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_like_label)
	vbox.add_child(_mk_label("---", 11, Color(0.72, 0.64, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# 列表区：内容多时限高滚动（跟详情页同一套参数）
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, clampf(get_viewport_rect().size.y - 260.0, 160.0, 380.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	var cancel := Button.new()
	cancel.text = "不送了"
	cancel.custom_minimum_size = Vector2(0, 30)
	cancel.add_theme_font_override("font", PIXEL_FONT)
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.pressed.connect(close)
	vbox.add_child(cancel)

func _mk_label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# 打开给第 slave_index 位伙伴挑礼物（先建列表再显示）
func open_for(slave_index: int) -> void:
	_slave_index = slave_index
	var s: Dictionary = Slaves.slave_at(slave_index)
	if s.is_empty():
		return
	_title.text = "送给 %s 的礼物" % str(s["name"])
	# 爱好 + 生日两行提示（IPix 没有全角标点, 文案全用 ASCII 符号）
	var like := Slaves.like_of(slave_index)
	var tips := "Ta 最喜欢: %s (送中好感 x2)" % like if like != "" else "Ta 没有特别的爱好"
	if Slaves.is_birthday(slave_index):
		tips += "\n今天是 Ta 的生日! 好感增量翻倍"
	_like_label.text = tips
	_refresh_list()
	show()

func close() -> void:
	_slave_index = -1
	hide()
	closed.emit()

# 重新列一遍背包里能送的东西（每份槽位一行按钮）
func _refresh_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	var found := 0
	for sl in Inventory.slot_list():
		var it: ItemData = sl["item"]
		if it == null or int(sl["count"]) <= 0:
			continue
		if not Slaves.GIFT_TYPES.has(it.type):
			continue
		found += 1
		var row := Button.new()
		row.text = "%s x%d  [%s]" % [it.display_name, int(sl["count"]), it.type]
		# 送中爱好的行名前插一颗星, 一眼认得出
		if it.display_name == Slaves.like_of(_slave_index):
			row.text = "* " + row.text
			row.add_theme_color_override("font_color", Color(0.98, 0.75, 0.5))
		row.custom_minimum_size = Vector2(0, 32)
		row.add_theme_font_override("font", PIXEL_FONT)
		row.add_theme_font_size_override("font_size", 13)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.tooltip_text = it.info_text()
		row.pressed.connect(_on_item_pressed.bind(it))
		_list_box.add_child(row)
	if found == 0:
		var empty := _mk_label(
			"背包里没有能送的东西\n(作物 / 食物 / 材料 都行, 道具类人家不收)",
			12, Color(0.78, 0.74, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
		empty.custom_minimum_size = Vector2(420, 60)
		_list_box.add_child(empty)

func _on_item_pressed(item: ItemData) -> void:
	Audio.play_sfx("ui_click")
	picked.emit(item)
	close()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
