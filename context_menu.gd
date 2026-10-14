# context_menu.gd —— 情境 F 键环: 附近有多件事时弹小菜单, 不删任何交互
extends Control

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _box: PanelContainer
var _list: VBoxContainer
var _open := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close())
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.14, 0.11, 0.09, 0.97)
	st.border_color = Color(0.62, 0.47, 0.28)
	st.set_border_width_all(3)
	st.set_corner_radius_all(8)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	_box.add_theme_stylebox_override("panel", st)
	center.add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_box.add_child(v)
	var title := Label.new()
	title.text = "附近可以:"
	title.add_theme_font_override("font", PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	v.add_child(_list)

func is_open() -> bool:
	return _open

func show_choices(items: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	for it in items:
		var label := String(it.get("label", ""))
		var fn: Callable = it.get("fn", Callable())
		if label == "" or not fn.is_valid():
			continue
		var b := Button.new()
		b.text = label
		b.add_theme_font_override("font", PIXEL_FONT)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			close()
			fn.call())
		_list.add_child(b)
	_open = true
	show()
	TimeManager.push_ui_pause()

func close() -> void:
	if not _open:
		return
	_open = false
	hide()
	TimeManager.pop_ui_pause()

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
