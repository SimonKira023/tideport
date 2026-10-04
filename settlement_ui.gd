# settlement_ui.gd —— 夜晚结算画面（星露谷「睡觉 → 今日发货明细」同款）
#
# 睡觉后黑幕拉起来，这张面板盖在黑幕之上：
#   · 背景 = 一整幅程序化夜空（星空 + 月亮 + 远山 + 萤火），盖住身后的农场
#   · 明细面板从下方滑进来，售卖明细一行一行浮现
#   · 收入数字从 0 滚到实际金额，滚完「叮」一声
#   · 若有备注（比如「伙伴们把没干完的 X 格活补完了」）会显示在最下面
#   · 最下面还有一块「夜间研究」：今晚科技/行政各涨了多少点（内容由 game.gd 传进来）
# 按 F / 空格 / Esc / 点一下鼠标 继续 → 换日、天亮。
#
# 它挂在 game.gd 那张「睡觉黑幕」CanvasLayer 上，且加在黑幕之后 → 天然画在黑幕之上。
extends Control

signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const GUARD := 0.45      # 刚弹出来的这段时间内不吃输入（免得收尾的那次点击把它关掉）

# 背景内部分辨率（1 像素 = 1 像素的艺术，整幅拉伸铺满屏幕，配合 NEAREST 滤镜正好是像素风）
const BG_W := 320
const BG_H := 180
const BG_SEED := 20260914   # 固定种子：每晚的星空长一样，改背景时好对比

var _open := false
var _guard := 0.0
var _bg: TextureRect           # 夜空底图
var _stars: TextureRect        # 星星单独一层，做闪烁
var _holder: Control           # 全屏容器，手动把面板居中（方便做滑入动画）
var _box: PanelContainer
var _title: Label
var _date: Label
var _list: VBoxContainer
var _list_scroll: ScrollContainer   # 明细列表限高滚动框（行一多也不撑爆面板）
var _empty: Label
var _income: Label
var _money: Label
var _note: Label
var _research_title: Label
var _research_box: VBoxContainer
var _tw_main: Tween            # 入场动画
var _tw_sky: Tween             # 星星闪烁（循环）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

# ---------------- 搭界面 ----------------
func _build() -> void:
	_bg = TextureRect.new()
	_bg.texture = _make_night_texture(false)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 星星单独一层：只画星星、底透明，靠透明度呼吸做「闪烁」
	_stars = TextureRect.new()
	_stars.texture = _make_night_texture(true)
	_stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stars.stretch_mode = TextureRect.STRETCH_SCALE
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stars)

	_holder = Control.new()
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)

	_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(26, 18, 12, 242)
	style.border_color = Color8(200, 155, 90)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_box.add_theme_stylebox_override("panel", style)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_holder.add_child(_box)

	var vbox := VBoxContainer.new()
	# ❗间隔 6：这页内容多（明细/收入/研究播报），间隔大了整包会被 648 的屏高顶破
	vbox.add_theme_constant_override("separation", 6)
	vbox.custom_minimum_size = Vector2(340, 0)
	_box.add_child(vbox)

	_title = _label("收工", 22, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title)
	_date = _label("", 13, Color(0.85, 0.78, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_date)

	vbox.add_child(_label("--- 今日发货 ---", 13, Color(0.72, 0.64, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	# ❗明细行数不固定（今晚卖出多少种就说多少种）—— 不限高的话行一多,
	#   整个面板会被顶出屏幕底。所以列表放进限高的小滚动框里。
	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(340, 0)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.add_child(_list)
	vbox.add_child(_list_scroll)

	_empty = _label("售卖箱是空的,今天没东西要卖", 13, Color(0.7, 0.66, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_empty)

	_income = _label("", 16, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_income)
	_money = _label("", 14, Color(0.92, 0.9, 0.84), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_money)
	_note = _label("", 12, Color(0.62, 0.86, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_note)

	# 夜间研究播报：科技/行政两条树今晚涨了多少点。没有内容时整块隐藏。
	_research_title = _label("--- 夜间研究 ---", 13, Color(0.72, 0.64, 0.52),
		HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_research_title)
	_research_box = VBoxContainer.new()
	_research_box.add_theme_constant_override("separation", 3)
	vbox.add_child(_research_box)

	var btn := Button.new()
	btn.text = "继续 (F / 空格 / 点击)"
	btn.custom_minimum_size = Vector2(0, 34)
	btn.add_theme_font_override("font", PIXEL_FONT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(_dismiss)
	vbox.add_child(btn)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# ---------------- 程序化夜空 ----------------
# 半透明色“叠”到不透明底色上。set_pixel 是替换而不是混合，
# 直接写半透明色会把天幕戳出一个半透明的洞（下层内容透上来）。
func _blend_px(img: Image, x: int, y: int, c: Color) -> void:
	var b := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(
		b.r * (1.0 - c.a) + c.r * c.a,
		b.g * (1.0 - c.a) + c.g * c.a,
		b.b * (1.0 - c.a) + c.b * c.a, 1.0))

# stars_only = false：整幅夜空（渐变天幕 + 星 + 月 + 远山 + 萤火）
# stars_only = true ：只画星星（底透明），叠在底图上做闪烁层
func _make_night_texture(stars_only: bool) -> ImageTexture:
	var img := Image.create_empty(BG_W, BG_H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = BG_SEED
	var sky_top := Color8(7, 10, 32)
	var sky_mid := Color8(26, 26, 66)
	var sky_low := Color8(48, 36, 74)

	# 星星的位置先抽出来（两层共用同一批位置，闪烁层才会跟底图对齐）
	var star_pts: Array = []
	for i in 110:
		var sx := rng.randi_range(2, BG_W - 3)
		var sy := rng.randi_range(2, 118)
		var big := rng.randf() < 0.12          # 少数亮星是 2x2 的
		var warm := rng.randf() < 0.25         # 少数偏暖色
		star_pts.append({
			"x": sx, "y": sy, "big": big, "warm": warm,
			"b": rng.randf_range(0.45, 1.0),       # 底图亮度
		})

	if not stars_only:
		# 1) 天幕：上深下暖的竖向渐变
		for y in BG_H:
			var t := float(y) / float(BG_H - 1)
			var c := sky_top.lerp(sky_mid, clampf(t / 0.62, 0.0, 1.0))
			if t > 0.62:
				c = sky_mid.lerp(sky_low, (t - 0.62) / 0.38)
			img.fill_rect(Rect2i(0, y, BG_W, 1), c)

		# 2) 星星：小白点，亮度随机；贴着地平线的不画（留给山）
		for s in star_pts:
			var a: float = s["b"]
			var col := Color(1, 0.95, 0.82) if s["warm"] else Color(0.88, 0.93, 1.0)
			col.a = a * 0.85
			var sz := 2 if s["big"] else 1
			for yy in sz:
				for xx in sz:
					_blend_px(img, s["x"] + xx, s["y"] + yy, col)

		# 3) 月亮：右上角，淡黄圆 + 两个环形光晕 + 几个陨石坑
		var mc := Vector2i(252, 40)
		var r := 13
		for gy in range(mc.y - r - 5, mc.y + r + 6):
			for gx in range(mc.x - r - 5, mc.x + r + 6):
				var d := Vector2(gx - mc.x, gy - mc.y).length()
				if d <= float(r):
					var shade := 1.0
					if Vector2(gx - mc.x + 4, gy - mc.y - 3).length() < 3.2:
						shade = 0.88          # 陨石坑
					elif Vector2(gx - mc.x - 3, gy - mc.y + 4).length() < 2.2:
						shade = 0.9
					elif Vector2(gx - mc.x + 1, gy - mc.y + 6).length() < 1.8:
						shade = 0.9
					img.set_pixel(gx, gy, Color8(int(244 * shade), int(236 * shade), int(208 * shade)))
				elif d <= float(r + 2):
					_blend_px(img, gx, gy, Color(1.0, 0.97, 0.86, 0.16))   # 内晕
				elif d <= float(r + 5):
					_blend_px(img, gx, gy, Color(1.0, 0.97, 0.86, 0.07))   # 外晕

		# 4) 远山两层：正弦叠出来的轮廓，深蓝绿剪影
		for x in BG_W:
			var far_h := 132 + int(5.0 * sin(x * 0.055) + 3.0 * sin(x * 0.021 + 1.7))
			var near_h := 150 + int(4.0 * sin(x * 0.04 + 0.6) + 3.0 * sin(x * 0.013 + 3.1))
			img.fill_rect(Rect2i(x, far_h, 1, BG_H - far_h), Color8(28, 32, 62))
			img.fill_rect(Rect2i(x, near_h, 1, BG_H - near_h), Color8(16, 18, 38))

		# 5) 萤火：山脚下几点暖黄的小灯
		for i in 9:
			var fx := rng.randi_range(8, BG_W - 8)
			var fy := rng.randi_range(138, 160)
			var fire := Color(1.0, 0.84, 0.45, 0.9)
			_blend_px(img, fx, fy, fire)
			if rng.randf() < 0.5:
				_blend_px(img, fx + 1, fy, Color(fire.r, fire.g, fire.b, 0.35))
	else:
		img.fill(Color(0, 0, 0, 0))
		for s in star_pts:
			var col2 := Color(1, 0.95, 0.82) if s["warm"] else Color(0.9, 0.95, 1.0)
			col2.a = 0.95
			var sz2 := 2 if s["big"] else 1
			img.fill_rect(Rect2i(s["x"], s["y"], sz2, sz2), col2)

	return ImageTexture.create_from_image(img)

# ---------------- 显示 ----------------
# entries: [{item: ItemData, count: int, price: int}]
# note: 额外备注（可空），比如「伙伴们把没干完的 X 格活补完了」
# research: 夜间研究播报的每一行（可空数组）。空数组 = 整块不显示。
func show_summary(date_text: String, day: int, entries: Array, income: int, money: int,
		note := "", research: Array = []) -> void:
	_title.text = "第 %d 天 - 收工" % day
	_date.text = date_text

	# 先 remove_child 再 queue_free —— queue_free 是延迟的，
	# 同一帧里连开两次结算的话旧行会赖着不走，跟新行叠在一起。
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var kinds := 0
	for e in entries:
		_list.add_child(_row(e))
		kinds += 1
	_empty.visible = kinds == 0
	_list_scroll.visible = kinds > 0
	# ❗滚动框的 min 高度跟行数走：行少时不占多余空间（否则反而把面板撑高），
	#   行多时封顶 110 —— 再多就把整个面板顶出 648 的屏高了，超出的滚动看。
	_list_scroll.custom_minimum_size = Vector2(340, minf(110.0, 28.0 * float(kinds)))

	# 研究播报：一行一句；没有内容就把标题和方框一起收起来
	for c in _research_box.get_children():
		_research_box.remove_child(c)
		c.queue_free()
	for line in research:
		var rl := _label(String(line), 12, Color(0.68, 0.86, 1.0),
			HORIZONTAL_ALIGNMENT_LEFT)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_research_box.add_child(rl)
	var show_res := not research.is_empty()
	_research_title.visible = show_res
	_research_box.visible = show_res

	# ❗文字先一次性写成最终值（自检/逻辑都按最终值读），
	#   入场动画再从 0 开始滚数字 —— 视觉滚动，数据不骗人。
	_income.text = "售卖箱收入 +%d 金" % income
	_money.text = "口袋里的金币: %d" % money
	_note.text = note
	_note.visible = note != ""

	_guard = GUARD
	_open = true
	show()
	_do_entrance.call_deferred(kinds, income)

func _row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.modulate.a = 0.0                 # 入场动画再亮起来

	var it: ItemData = entry["item"]
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if it != null:
		icon.texture = it.icon
	row.add_child(icon)

	var name_text := "%s x%d" % [it.display_name if it != null else "???", int(entry["count"])]
	var nm := _label(name_text, 13, Color(0.95, 0.93, 0.88))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size = Vector2(180, 0)
	row.add_child(nm)

	row.add_child(_label("%d 金" % int(entry["price"]), 13, Color(0.98, 0.85, 0.45),
		HORIZONTAL_ALIGNMENT_RIGHT))
	return row

# ---------------- 入场动画 ----------------
func _recentre() -> void:
	_box.reset_size()
	_box.position = ((_holder.size - _box.size) * 0.5).floor()

func _do_entrance(rows: int, income: int) -> void:
	if not _open:
		return
	_recentre()
	var target_y := _box.position.y

	# 星星闪烁：一条循环缓动，收面板时掐掉
	if _tw_sky != null:
		_tw_sky.kill()
	_stars.modulate.a = 1.0
	_tw_sky = create_tween()
	_tw_sky.set_loops()
	_tw_sky.tween_property(_stars, "modulate:a", 0.35, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw_sky.tween_property(_stars, "modulate:a", 1.0, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _tw_main != null:
		_tw_main.kill()
	_tw_main = create_tween()
	# 1) 夜空先亮起来
	_bg.modulate.a = 0.0
	_tw_main.tween_property(_bg, "modulate:a", 1.0, 0.35)
	# 2) 面板从下方 26px 滑进来 + 淡入
	_box.modulate.a = 0.0
	_box.position.y = target_y + 26.0
	_tw_main.tween_interval(0.05)
	_tw_main.tween_callback(func(): Audio.play_sfx("ui_open", -8.0))
	_tw_main.tween_property(_box, "modulate:a", 1.0, 0.3)
	_tw_main.parallel().tween_property(_box, "position:y", target_y, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 3) 明细一行一行浮现
	for i in _list.get_child_count():
		var row: Control = _list.get_child(i)
		_tw_main.tween_interval(0.13)
		_tw_main.tween_property(row, "modulate:a", 1.0, 0.22)
	# 4) 收入数字从 0 滚到实际金额，滚完「叮」一声
	_tw_main.tween_interval(0.15)
	_tw_main.tween_method(_set_income_text, 0.0, float(income), 0.55)
	if income > 0:
		_tw_main.tween_callback(func(): Audio.play_sfx("coin"))

func _set_income_text(v: float) -> void:
	_income.text = "售卖箱收入 +%d 金" % int(roundf(v))

# ---------------- 关闭 ----------------
func _input(event: InputEvent) -> void:
	if not _open or _guard > 0.0:
		return
	var dismiss := false
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		dismiss = true
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("ui_cancel"):
		dismiss = true
	if not dismiss:
		return
	_dismiss()
	get_viewport().set_input_as_handled()

func _dismiss() -> void:
	if not _open:
		return
	_open = false
	if _tw_main != null:
		_tw_main.kill()
	if _tw_sky != null:
		_tw_sky.kill()
	hide()
	closed.emit()

func is_open() -> bool:
	return _open
