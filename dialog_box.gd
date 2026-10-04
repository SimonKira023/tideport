# dialog_box.gd —— e16g/e18: 聊天对话框（视觉小说式, 支持多段台词）
#
# 「点聊天会跳对话框, 对话框出来才算聊了天」: 聊天按钮只负责弹这个框
# （大像素头像 + 名字 + 台词），玩家**把所有段翻完关掉**的那一下, 由调用方在
# closed 信号里真正落账（+好感 / 记今天聊过）。台词由调用方先取好（不落账
# 的预览组, 见 Nations.town_lines / captain_lines）。
#
# e18: 台词升级成 2~3 段 —— open_multi(segs, portrait, who), 点「继续」翻段,
# 最后一段才可关闭; closed 在关框时发出。单段也走这个入口(数组里就一个元素)。
#
# 关闭方式: 最后一段时点任意处 / F(interact) / Esc。guard 0.25s 防点开按钮的
# 同一下鼠标/按键立刻把它关掉。
extends Control

signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _segs: Array = []          # 台词段数组（2~3 段）
var _seg_i := 0                # 当前第几段
var _built: Control = null
var _line_label: Label = null
var _hint_label: Label = null
var _guard := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

func is_open() -> bool:
	return visible

func is_last_seg() -> bool:
	return _seg_i >= _segs.size() - 1

# portrait: 对面的像素头像; who: 名字行; segs: 台词段数组(每段一句)
func open_multi(portrait: Texture2D, who: String, segs: Array) -> void:
	_segs = segs if not segs.is_empty() else ["..."]
	_seg_i = 0
	if _built != null:
		_built.queue_free()
	_built = _build(portrait, who)
	add_child(_built)
	visible = true
	_guard = 0.25
	Audio.play_sfx("ui_open", -6.0)

func close() -> void:
	if not visible:
		return
	visible = false
	if _built != null:
		_built.queue_free()
		_built = null
	Audio.play_sfx("ui_close", -8.0)
	closed.emit()

# 点继续: 翻下一段; 已是最后一段 = 关框(这才算聊完)
func _advance_or_close() -> void:
	if not is_last_seg():
		_seg_i += 1
		_line_label.text = String(_segs[_seg_i])
		_hint_label.text = "继续 (%d/%d)" % [_seg_i + 1, _segs.size()]
		Audio.play_sfx("ui_click", -10.0)
	else:
		close()

func _build(portrait: Texture2D, who: String) -> Control:
	# 半透明遮罩: 点一下就翻段/关框（关的那一下才算聊了天）
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.35)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			get_viewport().set_input_as_handled()
			_advance_or_close())

	# 底部对话框条: 左头像 + 右名字/台词
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.07, 0.97)
	style.border_color = Color(0.62, 0.47, 0.28)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	bar.add_theme_stylebox_override("panel", style)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	var frame := PanelContainer.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0.16, 0.13, 0.10)
	fstyle.set_corner_radius_all(6)
	fstyle.content_margin_left = 3
	fstyle.content_margin_right = 3
	fstyle.content_margin_top = 3
	fstyle.content_margin_bottom = 3
	frame.add_theme_stylebox_override("panel", fstyle)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # e30m: 不随行高拉伸, 头像贴住框底
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(104, 104)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = portrait
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(pic)
	row.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_l := Label.new()
	name_l.text = who
	name_l.add_theme_font_override("font", PIXEL_FONT)
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", Color(1, 0.93, 0.76))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)

	_line_label = Label.new()
	_line_label.text = String(_segs[0])
	_line_label.add_theme_font_override("font", PIXEL_FONT)
	_line_label.add_theme_font_size_override("font_size", 14)
	_line_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(430, 0)
	_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_line_label)

	_hint_label = Label.new()
	_hint_label.text = "继续 (1/%d)" % _segs.size() if _segs.size() > 1 else "点击任意处继续"
	_hint_label.add_theme_font_override("font", PIXEL_FONT)
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", Color(0.66, 0.62, 0.55))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hint_label)

	# 对话框条贴屏幕底部居中
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -330
	bar.offset_right = 330
	bar.offset_top = -158
	bar.offset_bottom = -18
	veil.add_child(bar)
	return veil

func _input(event: InputEvent) -> void:
	if not visible or _guard > 0.0:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_advance_or_close()
