# sleep_menu_ui.gd —— 上床后的睡觉选择菜单
# 床边按 F 不再直接睡: 先问一句「今晚怎么睡」。
#   1. 睡到明天 —— 时针转到次日清晨, go_to_bed 换日（老流程）
#   2. 睡到今天的某个时刻 —— 小睡: 挑一个时刻, 时针转到那儿,
#      不换日, 醒来站在床脚边。挑 18 点且今晚有篝火时会提示「可能有篝火」。
# 风格对齐 campfire_ui（暖黑 + 火光橙）。由 house.gd 打开, game.gd 负责挂到 HUD。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const CLOCK := preload("res://clock_ui.gd")

const NAP_LAST_HOUR := 25   # 凌晨 1 点(25 点)是「今天」的最后一格, 26 点会强制昏迷
const CAMP_HOUR := 18       # 篝火时刻, 跟 game.gd 的 CAMP_HOUR 保持一致

var _visible := false
var _player: Node2D = null
var _house: Node = null
var _hour_view := false     # false = 主菜单(两种睡法)  true = 挑时刻
var _hours: Array = []      # 可以挑的时刻(整数), 开面板时按当前时间算好
var _sel := 0               # 当前选中 _hours 的下标

var _main_view: VBoxContainer
var _hour_box: VBoxContainer
var _btn_nap: Button
var _dial                   # clock_ui.Dial（内部类, 不标类型方便改 hour 属性）
var _time_label: Label
var _event_label: Label
var _weather_label: Label   # 主菜单的「明晨天气」预报

func _ready() -> void:
	add_to_group("sleep_menu")
	# 父节点是 HUD/CanvasLayer, Control 默认 0 尺寸会挤到左上角, 必须自己铺满全屏
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.10, 0.06, 0.97)       # 暖黑
	st.border_color = Color(0.85, 0.52, 0.2)          # 火光橙
	st.set_border_width_all(3)
	st.set_corner_radius_all(8)
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 16
	st.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", st)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	# ---- 主菜单: 两种睡法 ----
	_main_view = VBoxContainer.new()
	_main_view.add_theme_constant_override("separation", 10)
	vbox.add_child(_main_view)

	_main_view.add_child(_label("睡觉", 22, Color(1, 0.78, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	_main_view.add_child(_label("今晚怎么睡?", 13, Color(0.85, 0.75, 0.62), HORIZONTAL_ALIGNMENT_CENTER))
	# 明晨天气预报（open_panel 时按当天日期刷新）
	_weather_label = _label("", 13, Color(0.62, 0.80, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	_main_view.add_child(_weather_label)

	var btn1 := Button.new()
	btn1.text = "1. 睡到明天 (醒来是清晨)"
	btn1.custom_minimum_size = Vector2(300, 36)
	btn1.add_theme_font_override("font", PIXEL_FONT)
	btn1.add_theme_font_size_override("font_size", 14)
	btn1.pressed.connect(choose_next_day)
	_main_view.add_child(btn1)

	_btn_nap = Button.new()
	_btn_nap.text = "2. 睡到今天的某个时刻"
	_btn_nap.custom_minimum_size = Vector2(300, 36)
	_btn_nap.add_theme_font_override("font", PIXEL_FONT)
	_btn_nap.add_theme_font_size_override("font_size", 14)
	_btn_nap.pressed.connect(choose_nap)
	_main_view.add_child(_btn_nap)

	var btn_close := Button.new()
	btn_close.text = "取消 (Esc)"
	btn_close.custom_minimum_size = Vector2(0, 32)
	btn_close.add_theme_font_override("font", PIXEL_FONT)
	btn_close.add_theme_font_size_override("font_size", 13)
	btn_close.pressed.connect(close_panel)
	_main_view.add_child(btn_close)

	# ---- 挑时刻: 表盘 + 左右调 + 确认 ----
	_hour_box = VBoxContainer.new()
	_hour_box.add_theme_constant_override("separation", 8)
	_hour_box.visible = false
	vbox.add_child(_hour_box)

	_hour_box.add_child(_label("睡到几点?", 18, Color(1, 0.78, 0.45), HORIZONTAL_ALIGNMENT_CENTER))

	_dial = CLOCK.Dial.new()
	_dial.custom_minimum_size = Vector2(160, 160)
	_dial.R = 65.0
	var dial_wrap := CenterContainer.new()
	dial_wrap.add_child(_dial)
	_hour_box.add_child(dial_wrap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hour_box.add_child(row)

	var btn_left := Button.new()
	btn_left.text = "<"
	btn_left.custom_minimum_size = Vector2(40, 32)
	btn_left.add_theme_font_override("font", PIXEL_FONT)
	btn_left.add_theme_font_size_override("font_size", 16)
	btn_left.pressed.connect(func() -> void: _shift_hour(-1))
	row.add_child(btn_left)

	_time_label = _label("18:00", 18, Color(0.98, 0.90, 0.70), HORIZONTAL_ALIGNMENT_CENTER)
	_time_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(_time_label)

	var btn_right := Button.new()
	btn_right.text = ">"
	btn_right.custom_minimum_size = Vector2(40, 32)
	btn_right.add_theme_font_override("font", PIXEL_FONT)
	btn_right.add_theme_font_size_override("font_size", 16)
	btn_right.pressed.connect(func() -> void: _shift_hour(1))
	row.add_child(btn_right)

	_event_label = _label("", 13, Color(1, 0.60, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
	_hour_box.add_child(_event_label)

	var btn_ok := Button.new()
	btn_ok.text = "就这样睡 (F)"
	btn_ok.custom_minimum_size = Vector2(0, 36)
	btn_ok.add_theme_font_override("font", PIXEL_FONT)
	btn_ok.add_theme_font_size_override("font_size", 14)
	btn_ok.pressed.connect(confirm_nap)
	_hour_box.add_child(btn_ok)

	var btn_back := Button.new()
	btn_back.text = "返回 (Esc)"
	btn_back.custom_minimum_size = Vector2(0, 32)
	btn_back.add_theme_font_override("font", PIXEL_FONT)
	btn_back.add_theme_font_size_override("font_size", 13)
	btn_back.pressed.connect(back)
	_hour_box.add_child(btn_back)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# ---------------- 开合 ----------------
func open_panel(p: Node2D, house: Node) -> void:
	if _visible:
		return
	_player = p
	_house = house
	_visible = true
	# 能挑的时刻: 从下一个整点到今天最后一格(25 点 = 凌晨 1 点)
	_hours.clear()
	for h in range(TimeManager.hour + 1, NAP_LAST_HOUR + 1):
		_hours.append(h)
	_sel = 0
	_show_main()
	show()
	Audio.play_sfx("ui_open")
	TimeManager.push_ui_pause()      # 挑怎么睡的时候时间先停住
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	Audio.play_sfx("ui_close")
	TimeManager.pop_ui_pause()
	closed.emit()

func is_open() -> bool:
	return _visible

# ---------------- 两个选项 ----------------
# 选 1: 关菜单直接走「睡到明天」的老流程（house.gd _sleep_next_day）
func choose_next_day() -> void:
	if not _visible or _hour_view:
		return
	close_panel()
	_house_do("_sleep_next_day")

# 选 2: 切到「挑时刻」视图
func choose_nap() -> void:
	if not _visible or _hour_view or _hours.is_empty():
		return
	_hour_view = true
	_main_view.visible = false
	_hour_box.visible = true
	_sel = 0
	_refresh_hour()

# 自检用 / 也可以做成点时刻直接跳: 把选中时刻定位到 h
func set_hour(h: int) -> void:
	var idx: int = _hours.find(h)
	if idx >= 0:
		_sel = idx
		_refresh_hour()

func confirm_nap() -> void:
	if not _visible or not _hour_view or _hours.is_empty():
		return
	var target: int = int(_hours[_sel])
	close_panel()
	_house_do("_sleep_until", target)

func back() -> void:
	if not _visible or not _hour_view:
		return
	_show_main()

func _house_do(method: String, arg := -1) -> void:
	if _house == null or not is_instance_valid(_house):
		return
	if not _house.has_method(method):
		return
	if arg < 0:
		_house.call(method, _player)
	else:
		_house.call(method, _player, arg)

func _show_main() -> void:
	_hour_view = false
	_main_view.visible = true
	_hour_box.visible = false
	# 明晨天气预报: 有雨/雪/风暴就提醒一句（天气按日期播种, 现在就能报准明天）
	if Weather.is_tomorrow_rain():
		_weather_label.text = "明晨有%s, 田里的水天亮就浇好" % Weather.tomorrow_name_text()
	else:
		_weather_label.text = "明晨天气: %s" % Weather.tomorrow_name_text()
	# 太晚(过了凌晨 1 点)就没有「小睡」可选 —— 只能睡到明天等天亮
	if _hours.is_empty():
		_btn_nap.text = "太晚了, 只能睡到明天了"
		_btn_nap.disabled = true
	else:
		_btn_nap.text = "2. 睡到今天的某个时刻"
		_btn_nap.disabled = false

func _shift_hour(dir: int) -> void:
	if not _visible or not _hour_view or _hours.is_empty():
		return
	_sel = clampi(_sel + dir, 0, _hours.size() - 1)
	_refresh_hour()

func _refresh_hour() -> void:
	if _hours.is_empty():
		return
	var h: int = int(_hours[_sel])
	_dial.hour = float(h)
	_dial.queue_redraw()
	_time_label.text = _hour_text(h)
	# 事件提示: 睡到 18 点正好赶上傍晚的篝火（今晚真有火才提示, 播种法跟 game.gd 一致）
	if h == CAMP_HOUR and _campfire_tonight():
		_event_label.text = "今晚 18 点可能有篝火"
	else:
		_event_label.text = "醒来还是今天, 不换日"

func _hour_text(h: int) -> String:
	if h >= 24:
		return "凌晨 %d:00" % (h - 24)
	return "%d:00" % h

func _campfire_tonight() -> bool:
	var game: Node = get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("_campfire_today"):
		return bool(game.call("_campfire_today"))
	return false

# ---------------- 键盘 ----------------
# 主菜单: 1/2 直接选, F/Esc 取消; 挑时刻: 左右调, F 确认, Esc 返回
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if _hour_view:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			confirm_nap()
		elif event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			back()
		elif event.is_action_pressed("ui_left"):
			get_viewport().set_input_as_handled()
			_shift_hour(-1)
		elif event.is_action_pressed("ui_right"):
			get_viewport().set_input_as_handled()
			_shift_hour(1)
	else:
		if event is InputEventKey and event.pressed and not event.is_echo():
			if event.keycode == KEY_1:
				get_viewport().set_input_as_handled()
				choose_next_day()
				return
			if event.keycode == KEY_2:
				get_viewport().set_input_as_handled()
				choose_nap()
				return
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
			close_panel()
