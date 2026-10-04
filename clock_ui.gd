# clock_ui.gd —— 上床跳时间的时钟动画
#
# 上床后不再直接换日，而是先播一段「时钟转动」动画：表盘中央，
# 时针从当前时间转到次日清晨 6 点（hour 制 30.0），分针一路飞转，
# 下方文字跟着跳到目标时间。动画放完才回调（真正换日由 house.gd/game.gd 接管）。
# 按 F 可以直接跳过动画。
#
# 用法：
#   var clock := get_tree().get_first_node_in_group("clock_anim")
#   clock.play(TimeManager.hour + TimeManager.minute / 60.0, func(): TimeManager.go_to_bed())
extends Control

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const DIAL_SIZE := 210.0
const SPIN_SECONDS := 2.6        # 转针总时长（秒）
const TARGET_HOUR := 30.0        # 次日清晨 6 点（6 + 24）

# 表盘：父控件 _process 里同步 hour，然后 queue_redraw
class Dial extends Control:
	var hour := 6.0
	var R := 90.0

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, R, Color(0.16, 0.13, 0.10))
		draw_arc(c, R, 0, TAU, 64, Color(0.72, 0.55, 0.34), 4.0)
		draw_arc(c, R - 8.0, 0, TAU, 64, Color(0.42, 0.32, 0.22), 2.0)
		# 12 刻度（主刻度长一点）
		for i in 12:
			var ang := i / 12.0 * TAU - PI / 2
			var dir := Vector2(cos(ang), sin(ang))
			var long_tick := i % 3 == 0
			draw_line(c + dir * (R - 16.0), c + dir * (R - (30.0 if long_tick else 22.0)),
				Color(0.85, 0.75, 0.55), 2.0 if long_tick else 1.0)
		# 时针：12 小时表盘
		var ha := fposmod(hour, 12.0) / 12.0 * TAU - PI / 2
		draw_line(c, c + Vector2(cos(ha), sin(ha)) * (R * 0.48), Color(0.95, 0.93, 0.88), 5.0)
		# 分针：分钟位（hour 的小数部分）随动画飞转
		var ma := fposmod(hour, 1.0) * TAU - PI / 2
		draw_line(c, c + Vector2(cos(ma), sin(ma)) * (R * 0.76), Color(0.85, 0.60, 0.45), 3.0)
		draw_circle(c, 6.0, Color(0.85, 0.60, 0.45))

var _dial: Dial
var _label: Label
var _hour := 6.0
var _target := TARGET_HOUR
var _active := false
var _on_done := Callable()
var _tw: Tween

func _ready() -> void:
	add_to_group("clock_anim")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func _build() -> void:
	var mask := ColorRect.new()
	mask.color = Color(0, 0, 0, 0.62)
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(mask)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.06, 0.96)
	style.border_color = Color(0.62, 0.47, 0.28)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	frame.add_theme_stylebox_override("panel", style)
	vbox.add_child(frame)

	_dial = Dial.new()
	_dial.custom_minimum_size = Vector2(DIAL_SIZE, DIAL_SIZE)
	_dial.R = DIAL_SIZE * 0.5 - 15.0
	frame.add_child(_dial)

	_label = Label.new()
	_label.add_theme_font_override("font", PIXEL_FONT)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_label)

	var hint := Label.new()
	hint.text = "[F] "
	hint.add_theme_font_override("font", PIXEL_FONT)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.64, 0.52))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

# target 默认次日清晨 6 点（hour 制 30.0）；小睡到今天的某个时刻时由
# house.gd 传一个当天的小时数进来，指针转到那儿就停。
func play(from_hour: float, on_done: Callable = Callable(),
		target := TARGET_HOUR) -> void:
	if _active:
		return
	_active = true
	_hour = from_hour
	_target = target
	_on_done = on_done
	show()
	_tw = create_tween()
	_tw.tween_property(self, "_hour", _target, SPIN_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(_finish)

func _process(_delta: float) -> void:
	if not _active:
		return
	_dial.hour = _hour
	_dial.queue_redraw()
	var h := int(fmod(floorf(_hour), 24.0))
	var m := int(fposmod(_hour, 1.0) * 60.0)
	_label.text = "%d:%02d" % [h, m]

func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _tw != null and _tw.is_valid():
			_tw.kill()
		_hour = _target
		_finish()

func _finish() -> void:
	_active = false
	hide()
	if _on_done.is_valid():
		var cb := _on_done
		_on_done = Callable()
		cb.call()
