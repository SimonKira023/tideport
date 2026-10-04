# scene/main_menu.gd —— 开始界面（主场景）
#
# 两个入口，跟用户说好的一致：
#   · 开始 —— 给这一档起个名字，然后**从第 1 年第 1 天**开一档全新的
#   · 加载 —— 列出所有具名档（名字 + 第几天 + 存档时刻），挑一个继续
#
# 数据侧的活都在 SaveManager：begin_new_game() 挂"重置请求"，open_slot() 挂"待读档"，
# 这里只负责问、显示、然后把场景换成 game.tscn（game._ready 会看那两个标记决定怎么开局）。
#
# 画面：程序化的一片海（天空渐变 + 三层正弦波 + 一轮月亮），会缓慢流动。
# ❗UI 文案只用 ASCII 标点 —— IPix.ttf 没有全角标点字形，会渲成方块。
extends Control

const FONT_PIX := preload("res://resources/font/IPix.ttf")
const IRIS := preload("res://scene/iris_wipe.gd")   # d9: 场景切换的 iris 黑幕转场
const CARD_BG := Color(0.10, 0.09, 0.14, 0.94)
const CARD_EDGE := Color(0.72, 0.58, 0.32)
const GOLD := Color(1.0, 0.90, 0.62)
const DIM := Color(0.72, 0.74, 0.80)

var _view_new: VBoxContainer
var _view_load: VBoxContainer
var _name_edit: LineEdit
var _slot_rows: VBoxContainer
var _hint: Label
var _phase := 0.0

# e21: 开场动画 —— 黑幕揭开 → 帆船驶入海面 → 标题金字浮现 → 菜单滑入。
# 时间轴帧驱动(秒), 任意点击跳过; 船在动画结束后常驻海面轻轻摇曳。
# e21b: 动画最前面加「工作室符号」段 —— 开场先是**白屏**, 用户的头像 logo 弹性
# 缩放浮现(旁边跳出绿色小叉), 停留一拍后白屏淡出转场进主菜单海面。
# logo 图放 res://resources/texture/studio.png; 没有这张图就用程序画的风格化兽耳娘剪影兜底。
const STUDIO_END := 2.6
const STUDIO_IMG := "res://resources/texture/studio.png"
const INTRO_END := 3.2
var _intro_t := 0.0            # 开场时间轴; INTRO_END 后停止(=已跳过/播完)
var _studio_t := 0.0           # 工作室段时间轴(0..STUDIO_END, 先于 intro 播)
var _boat_x := -1.0            # 帆船 x(动画驱动; -1 = 未入场)
var _black: ColorRect = null   # 开场罩: 工作室段是白屏, 段末转黑幕淡出进海面
var _logo: Control = null      # 工作室 logo(贴图或程序画)
var _logo_glow: Control = null # e42: logo 背后那团柔光
var _logo_check: Control = null # e42: logo 旁的绿勾(用贴图时才有 —— 程序画的那版勾在画里)
var _title_box: VBoxContainer = null
var _menu_card: PanelContainer = null
var _card_glow: Control = null  # d7: 菜单卡片背后那团呼吸柔光（海面开场后常驻）
var _stars: Array = []         # e42: 夜空星点(比例坐标 + 闪烁相位/速度)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_stars()
	_build()
	_show_new()
	Audio.set_scene_bgm("menu")      # e21: 主菜单固定一首
	_start_intro()


# 夜空星点: 固定种子生成一次, 之后每帧只按相位闪
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925
	for i in 96:
		_stars.append({
			"x": rng.randf(), "y": rng.randf() * 0.40,
			"s": rng.randf_range(1.0, 2.3),
			"p": rng.randf() * TAU,
			"sp": rng.randf_range(0.6, 2.0),
		})


# ---------------- 开场动画 ----------------
func _start_intro() -> void:
	# 工作室段: 白屏罩 + logo
	_black = ColorRect.new()
	_black.color = Color(1, 1, 1, 1)          # 一开始是**白屏**
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_black.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_skip_intro())
	add_child(_black)
	# logo: 有贴图用贴图, 没有就用程序画的兽耳娘符号
	var tex: Texture2D = load(STUDIO_IMG) if ResourceLoader.exists(STUDIO_IMG) else null
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(320, 320)
		tr.position = Vector2(-1000, -1000)     # _layout_logo 里摆正
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_logo = tr
	else:
		_logo = StudioLogoDraw.new()
		_logo.size = Vector2(360, 360)
		_logo.position = Vector2(-1000, -1000)
	_logo.modulate.a = 0.0
	add_child(_logo)
	# e42: logo 背后垫一团柔光, 旁边跳一枚绿勾 —— 白屏上看着就不秃了
	_logo_glow = SoftGlow.new()
	_logo_glow.size = Vector2(540, 540)
	_logo_glow.position = Vector2(-1000, -1000)
	_logo_glow.modulate.a = 0.0
	_logo_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo_glow)
	move_child(_logo_glow, _logo.get_index())      # 插到 logo 之前 = 画在它下面
	if tex_logo():
		_logo_check = CheckMark.new()
		_logo_check.size = Vector2(54, 54)
		_logo_check.position = Vector2(-1000, -1000)
		_logo_check.pivot_offset = _logo_check.size * 0.5
		_logo_check.modulate.a = 0.0
		_logo_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_logo_check)
	if _title_box != null:
		_title_box.modulate.a = 0.0
	if _menu_card != null:
		_menu_card.modulate.a = 0.0
		_menu_card.pivot_offset = Vector2(200.0, 150.0)
		_menu_card.scale = Vector2(0.94, 0.94)
	if _hint != null:
		_hint.modulate.a = 0.0
	_studio_t = 0.0
	_intro_t = 0.0

# logo 居中(窗口尺寸就绪后调)
func _layout_logo() -> void:
	if _logo == null:
		return
	var c := size * 0.5
	_logo.position = c - _logo.size * 0.5
	if _logo_glow != null:
		_logo_glow.position = c - _logo_glow.size * 0.5
	if _logo_check != null:
		_logo_check.position = c + Vector2(_logo.size.x * 0.31, -_logo.size.y * 0.35)

func _skip_intro() -> void:
	if _studio_t >= STUDIO_END and _intro_t >= INTRO_END:
		return
	_studio_t = STUDIO_END
	_intro_t = INTRO_END
	_finish_intro()

func _finish_intro() -> void:
	if _black != null:
		_black.queue_free()
		_black = null
	if _logo != null:
		_logo.queue_free()
		_logo = null
	if _logo_glow != null:
		_logo_glow.queue_free()
		_logo_glow = null
	if _logo_check != null:
		_logo_check.queue_free()
		_logo_check = null
	if _title_box != null:
		_title_box.modulate.a = 1.0
	if _menu_card != null:
		_menu_card.modulate.a = 1.0
		_menu_card.scale = Vector2.ONE
	if _hint != null:
		_hint.modulate.a = 1.0
	_boat_x = size.x * 0.30            # 船停在左侧海面常驻摇曳

# 时间轴: 先工作室段(白屏/logo), 播完才进海面开场(intro)
func _tick_intro(delta: float) -> void:
	if _studio_t < STUDIO_END:
		_studio_t = minf(_studio_t + delta, STUDIO_END)
		_tick_studio()
		return
	if _intro_t >= INTRO_END:
		return
	_intro_t = minf(_intro_t + delta, INTRO_END)
	var t := _intro_t
	if _black != null:
		# 工作室段结束: 白屏换黑幕淡出。e42 别用纯黑 —— 掺一点夜蓝,
		# 幕布散开时像海面透上来的暮色, 接海面那一下更顺
		_black.color = Color(0.05, 0.06, 0.11, clampf(1.0 - t / 0.8, 0.0, 1.0))
	# 帆船: 0.5s 后从画外驶入, 2.2s 到位
	if t >= 0.5:
		var u := clampf((t - 0.5) / 1.7, 0.0, 1.0)
		var ease_u := 1.0 - pow(1.0 - u, 2.2)              # ease-out
		_boat_x = lerp(-70.0, size.x * 0.30, ease_u)
	if _title_box != null:
		var u2 := clampf((t - 1.3) / 0.9, 0.0, 1.0)
		_title_box.modulate.a = u2
	if _menu_card != null:
		var u3 := clampf((t - 2.1) / 0.7, 0.0, 1.0)
		_menu_card.modulate.a = u3
		_menu_card.scale = Vector2(0.94, 0.94).lerp(Vector2.ONE, u3)   # ❗别碰 position —— CenterContainer 每帧重排会盖掉
	if _hint != null:
		_hint.modulate.a = clampf((t - 2.6) / 0.6, 0.0, 1.0)
	if t >= INTRO_END:
		_finish_intro()

# 工作室段: 0~0.4 纯白 → 0.4~1.4 logo 弹性浮现 → 1.4~2.1 定格(绿叉跳出来) → 2.1~2.6 整体淡出转场
func _tick_studio() -> void:
	if _logo == null:
		return
	if size.x > 4.0 and _logo.position.x < 0.0:
		_layout_logo()
	var t := _studio_t
	if t < 0.4:
		return
	# 弹性浮现: ease-out-back 的近似(过冲一点点再收回)
	var u := clampf((t - 0.4) / 1.0, 0.0, 1.0)
	var back := 1.0 + 2.4 * pow(u - 1.0, 3.0) + 1.4 * pow(u - 1.0, 2.0)   # easeOutBack 近似
	var sc := 0.55 + 0.45 * back
	if tex_logo():
		var tr := _logo as TextureRect
		tr.modulate.a = clampf(u * 1.6, 0.0, 1.0)
		tr.scale = Vector2(sc, sc)
		tr.pivot_offset = tr.size * 0.5
	else:
		_logo.modulate.a = clampf(u * 1.6, 0.0, 1.0)
		_logo.scale = Vector2(sc, sc)
		_logo.pivot_offset = _logo.size * 0.5
	# e42: 背后的柔光跟着一起亮; 1.4 秒后旁边那枚绿勾弹出来(过冲一下)
	if _logo_glow != null:
		_logo_glow.modulate.a = clampf(u * 1.1, 0.0, 0.80)
	if _logo_check != null and t >= 1.4:
		var uc := clampf((t - 1.4) / 0.45, 0.0, 1.0)
		var cb := 1.0 + 1.9 * pow(uc - 1.0, 3.0) + 1.1 * pow(uc - 1.0, 2.0)
		_logo_check.modulate.a = uc
		_logo_check.scale = Vector2(0.4 + 0.6 * cb, 0.4 + 0.6 * cb)
	# 2.1 后整体淡出(白屏也一起) —— 转场进海面
	if t >= 2.1:
		var u2 := clampf((t - 2.1) / 0.5, 0.0, 1.0)
		_logo.modulate.a = 1.0 - u2
		if _logo_glow != null:
			_logo_glow.modulate.a = 0.80 * (1.0 - u2)
		if _logo_check != null:
			_logo_check.modulate.a = 1.0 - u2      # 走到这儿绿勾早已弹满
		if _black != null:
			_black.color = Color(1, 1, 1, 1 - u2)   # 白屏淡出露海面
	if _black != null and t < 2.1 and _black.color != Color(1, 1, 1, 1):
		_black.color = Color(1, 1, 1, 1)

# logo 用的是贴图还是程序画
func tex_logo() -> bool:
	return _logo is TextureRect


# e42: 一团柔光(同心圆叠出来的), 摆在 logo 背后, 白屏上就有一层光
class SoftGlow:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		for i in 20:
			var u := float(i) / 19.0
			draw_circle(c, r * (1.0 - u * 0.88), Color(1.0, 0.99, 0.94, 0.020))


# e42: 一枚绿勾(两笔画), 贴图 logo 的签名符 —— 贴着 logo 右下角跳出来
class CheckMark:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		var g := Color(0.52, 0.80, 0.34)
		var pen: float = maxf(3.0, w * 0.13)
		draw_line(Vector2(w * 0.08, h * 0.52), Vector2(w * 0.38, h * 0.84), g, pen)
		draw_line(Vector2(w * 0.38, h * 0.84), Vector2(w * 0.94, h * 0.12), g, pen)

# 程序画的兽耳娘符号(兜底): 平色块风格 —— 兽耳剪影 + 眯眼笑 + 西瓜一角 + 绿叉
class StudioLogoDraw:
	extends Control

	func _draw() -> void:
		var cx := 180.0
		var cy := 190.0
		var ink := Color(0.16, 0.17, 0.24)          # 藏蓝黑(发色)
		var ink2 := Color(0.27, 0.30, 0.40)
		var skin := Color(0.96, 0.90, 0.84)
		var melon_r := Color(0.94, 0.36, 0.42)
		var melon_g := Color(0.45, 0.75, 0.30)
		var leaf := Color(0.62, 0.80, 0.30)
		# 两条兽耳(尖角, 内耳浅灰)
		for side: int in [-1, 1]:
			var bx: float = cx + side * 62.0
			var ear := PackedVector2Array([
				Vector2(bx - 34 * side, cy - 40), Vector2(bx + 10 * side, cy - 128),
				Vector2(bx + 42 * side, cy - 30), Vector2(bx + 12 * side, cy - 52)])
			draw_colored_polygon(ear, ink)
			var inner := PackedVector2Array([
				Vector2(bx - 12 * side, cy - 52), Vector2(bx + 8 * side, cy - 104),
				Vector2(bx + 26 * side, cy - 44), Vector2(bx + 6 * side, cy - 58)])
			draw_colored_polygon(inner, ink2)
		# 圆脸 + 刘海
		draw_circle(Vector2(cx, cy), 96.0, ink)
		draw_circle(Vector2(cx + 6, cy + 16), 74.0, skin)
		# 刘海一撇
		draw_circle(Vector2(cx - 30, cy - 42), 40.0, ink)
		# 眯眼笑(两条弧) + 小嘴
		for side in [-1, 1]:
			draw_arc(Vector2(cx + side * 34, cy - 8), 15.0, PI + 0.5, TAU - 0.3, 10,
				Color(0.1, 0.1, 0.12), 4.0)
		draw_arc(Vector2(cx, cy + 30), 10.0, 0.4, PI - 0.4, 8, Color(0.5, 0.2, 0.2), 3.0)
		# 西瓜一角(捧在嘴边)
		var m := PackedVector2Array([
			Vector2(cx - 40, cy + 62), Vector2(cx + 40, cy + 62), Vector2(cx, cy + 14)])
		draw_colored_polygon(m, melon_r)
		draw_arc(Vector2(cx, cy + 62), 40.0, PI, TAU, 12, melon_g, 7.0)
		# 两颗西瓜籽
		draw_circle(Vector2(cx - 10, cy + 46), 2.5, Color(0.2, 0.15, 0.15))
		draw_circle(Vector2(cx + 12, cy + 50), 2.5, Color(0.2, 0.15, 0.15))
		# 右上两撇绿叉(原 image 的signature十字)
		for i in 2:
			var gx := 300.0 + i * 26.0
			var gy := 60.0 + i * 44.0
			draw_line(Vector2(gx, gy), Vector2(gx + 30, gy + 26), leaf, 10.0)
			draw_line(Vector2(gx + 30, gy), Vector2(gx, gy + 26), leaf, 10.0)


# ---------------- 搭界面 ----------------
func _build() -> void:
	_title_box = _build_title()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 26.0          # 稍微往下挪一点，给上面的标题让位置
	# d7: 卡片背后一团呼吸柔光 —— 必须先于 center 添加才画在卡片下层
	_card_glow = SoftGlow.new()
	_card_glow.size = Vector2(560, 480)
	_card_glow.modulate.a = 0.0
	add_child(_card_glow)
	add_child(center)

	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = CARD_BG
	st.border_color = CARD_EDGE
	st.set_border_width_all(3)
	st.set_corner_radius_all(8)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 20
	st.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", st)
	center.add_child(card)

	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(360, 0)
	card.add_child(stack)
	_view_new = _build_new_view()
	stack.add_child(_view_new)
	_view_load = _build_load_view()
	stack.add_child(_view_load)
	_menu_card = card

	_hint = _label("", 12, Color(0.95, 0.72, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -46.0
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_hint)


func _build_title() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 54.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var t := _label("潮汐港", 40, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12, 0.9))
	box.add_child(t)
	# e42: 标题下压一条金线, 光一个金字太干
	var rule := ColorRect.new()
	rule.color = Color(0.88, 0.72, 0.36, 0.50)
	rule.custom_minimum_size = Vector2(104, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	return box


func _build_new_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)

	box.add_child(_label("开始新档", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("给这一档起个名字, 以后就靠它认档", 12, DIM,
		HORIZONTAL_ALIGNMENT_CENTER))

	_name_edit = LineEdit.new()
	_name_edit.text = _default_slot_name()
	_name_edit.placeholder_text = "比如: 娜雅的第一次出海"
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_override("font", FONT_PIX)
	_name_edit.add_theme_font_size_override("font_size", 16)
	_name_edit.custom_minimum_size = Vector2(0, 30)
	_name_edit.text_submitted.connect(func(_t): _on_start())
	box.add_child(_name_edit)

	var b_start := _button("开始新的一天")
	b_start.pressed.connect(_on_start)
	box.add_child(b_start)

	var b_load := _button("加载存档")
	b_load.pressed.connect(_show_load)
	box.add_child(b_load)

	var b_quit := _button("退出游戏")
	b_quit.pressed.connect(func(): get_tree().quit())
	box.add_child(b_quit)
	return box


func _build_load_view() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.add_child(_label("选择存档", 22, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("存档时间: 每天早上 6 点(睡完觉换日那一刻自动存)",
		11, DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_slot_rows = VBoxContainer.new()
	_slot_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_slot_rows)

	var b_back := _button("返回")
	b_back.pressed.connect(_show_new)
	box.add_child(b_back)
	return box


# ---------------- 视图切换 ----------------
func _show_new() -> void:
	_view_new.visible = true
	_view_load.visible = false
	_hint.text = ""
	_name_edit.grab_focus()
	# ❗别 select_all：默认档名会整段套上灰底高亮，看着像渲染坏了
	_name_edit.caret_column = _name_edit.text.length()


func _show_load() -> void:
	_view_new.visible = false
	_view_load.visible = true
	_hint.text = ""
	_refresh_slots()


func _refresh_slots() -> void:
	for c in _slot_rows.get_children():
		c.queue_free()
	var slots: Array = SaveManager.list_slots()
	if slots.is_empty():
		_slot_rows.add_child(_label("还没有任何存档", 13, DIM, HORIZONTAL_ALIGNMENT_CENTER))
		return
	for e in slots:
		_slot_rows.add_child(_slot_row(e))


# 一行 = 「档名」+ 「第 x 年 季 第 x 天 时:分」+「读」+「删」
func _slot_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	# ❗HBox 里的 Label 必须 autowrap OFF 并给死最小宽度，
	#   否则最小宽度会被压成 1px、文字竖排成一列（这个坑踩过好几次了）
	var name_l := _plain(e["name"], 15, Color(0.98, 0.93, 0.80), 190)
	info.add_child(name_l)
	# 存档时刻其实恒为早上 6 点（唯一的存档时机就是换日那一刻），
	# 按实际值显示是给早先留下的老档兜底
	var h := int(e["hour"]) % 24
	var ampm := "上午" if h < 12 else "下午"
	var when := "第 %d 年 %s 第 %d 天  %s %d:%02d" % [
		int(e["year"]), TimeManager.SEASONS[int(e["season"]) % 4],
		int(e["day"]), ampm, h, int(e["minute"])]
	info.add_child(_plain(when, 11, DIM, 190))
	row.add_child(info)

	var b_open := _button("读档", 58)
	b_open.pressed.connect(func():
		if SaveManager.open_slot(String(e["path"])):
			# d9: iris 收黑后再切进游戏, 黑幕中展开岛上清晨
			IRIS.play("out", func() -> void:
				get_tree().change_scene_to_file("res://scene/game.tscn"))
		else:
			_hint.text = "这份存档读不出来, 可能文件坏了")
	row.add_child(b_open)

	var b_del := _button("删", 44)
	b_del.pressed.connect(func():
		SaveManager.delete_slot(String(e["path"]))
		_refresh_slots())
	row.add_child(b_del)
	return row


# ---------------- 动作 ----------------
func _on_start() -> void:
	var n := _name_edit.text.strip_edges()
	if n.is_empty():
		_hint.text = "先给这一档起个名字"
		_name_edit.grab_focus()
		return
	SaveManager.begin_new_game(n)
	# d9: 新游戏也走 iris 收黑 -> 黑幕中换场景
	IRIS.play("out", func() -> void:
		get_tree().change_scene_to_file("res://scene/game.tscn"))


# 默认档名：按已有档数往下排，省得每次都手打
func _default_slot_name() -> String:
	return "第 %d 档" % (SaveManager.list_slots().size() + 1)


# ---------------- 控件小工具 ----------------
func _label(t: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = align
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# 给死宽度的 Label：放进 HBox 时用它，免得被压成竖排
func _plain(t: String, size: int, col: Color, w: float) -> Label:
	var l := _label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.custom_minimum_size = Vector2(w, 0)
	return l


func _button(t: String, w := 0.0) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", FONT_PIX)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.78))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.84, 0.42))
	# ❗不套样式的话按钮就是一块跟卡片底色差不多的深灰，看不出能点。
	#   给个亮边框 + 比卡片亮一档的底，鼠标一上去再亮一格。
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.20, 0.19, 0.25), Color(0.46, 0.40, 0.30)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.27, 0.25, 0.31), Color(0.86, 0.72, 0.40)))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.14, 0.13, 0.18), Color(0.95, 0.80, 0.45)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())   # 别留一圈焦点虚线
	b.custom_minimum_size = Vector2(w, 32)
	if w == 0.0:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: Audio.play_sfx("ui_click", -4.0))
	return b


func _btn_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = edge
	st.set_border_width_all(2)
	st.set_corner_radius_all(5)
	st.content_margin_left = 10
	st.content_margin_right = 10
	return st


# ---------------- 程序化海面（自己画，不占资源文件）----------------
func _process(delta: float) -> void:
	_phase += delta * 0.45
	_tick_intro(delta)
	# d7: 柔光跟着卡片走, 随相位呼吸; 乘卡片透明度跟开场淡入同步
	if _card_glow != null and _menu_card != null:
		_card_glow.position = _menu_card.global_position \
			+ _menu_card.size * 0.5 - _card_glow.size * 0.5
		_card_glow.modulate.a = (0.16 + 0.10 * sin(_phase * 1.4)) * _menu_card.modulate.a
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	var horizon := h * 0.46
	# 天空：从上到下由深靛蓝过渡到海平线的暖青，越靠近海平线越掺一点落日余光
	var sky_top := Color(0.07, 0.09, 0.21)
	var sky_bot := Color(0.26, 0.38, 0.49)
	var glow := Color(0.94, 0.62, 0.40)
	var bands := 26
	var band_h := horizon / float(bands)
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := sky_top.lerp(sky_bot, t).lerp(glow, pow(t, 3.0) * 0.50)
		draw_rect(Rect2(0.0, band_h * float(i), w, band_h + 1.0), col)
	# e42: 星野 —— 96 颗小方点各自闪烁, 只在海平线以上
	for st in _stars:
		var a: float = 0.18 + 0.62 * (0.5 + 0.5 * sin(_phase * float(st["sp"]) * 1.7 + float(st["p"])))
		draw_rect(Rect2(float(st["x"]) * w, float(st["y"]) * h,
			float(st["s"]), float(st["s"])), Color(1.0, 0.98, 0.90, a))
	# e42: 几缕薄云横着飘, 边缘被月光染亮一点
	for i in 4:
		var cy: float = horizon * (0.16 + 0.15 * float(i))
		var cx: float = fposmod(w * (0.10 + 0.29 * float(i)) + _phase * (5.0 + 4.0 * float(i)),
			w + 560.0) - 280.0
		for k in 6:
			var off := Vector2(float(k - 2) * 46.0, absf(float(k - 2)) * 8.0)
			draw_circle(Vector2(cx, cy) + off, 40.0 - absf(float(k - 2)) * 5.0,
				Color(0.84, 0.89, 0.98, 0.040))
	# 月亮: 一圈柔光 + 月盘 + 一点外晕
	var moon := Vector2(w * 0.78, horizon * 0.34)
	var mr: float = minf(w, h) * 0.038
	for i in 12:
		draw_circle(moon, mr * (1.7 + float(i) * 0.34), Color(0.94, 0.95, 1.0, 0.020))
	draw_circle(moon, mr, Color(0.96, 0.95, 0.86, 0.92))
	draw_circle(moon, minf(w, h) * 0.055, Color(0.96, 0.95, 0.86, 0.10))
	# 海：先把海平线以下整片垫个底色，再往上一层层叠浪。
	# ❗不垫这一层的话：第一层浪的波谷比海平线低，中间会漏出视口的默认清屏色 ——
	#   画面上就是海平线下挂着一条 20 像素高的灰带（不是天空也不是海）。
	draw_rect(Rect2(0.0, horizon, w, h - horizon), Color(0.17, 0.30, 0.43))
	# 三层正弦浪，越靠下越深（层次感）
	var layers := [
		{"amp": h * 0.020, "y": horizon + h * 0.015, "len": w * 0.30, "sp": 0.9,
			"col": Color(0.19, 0.34, 0.48)},
		{"amp": h * 0.026, "y": horizon + h * 0.095, "len": w * 0.24, "sp": 1.4,
			"col": Color(0.13, 0.26, 0.41)},
		{"amp": h * 0.032, "y": horizon + h * 0.195, "len": w * 0.20, "sp": 2.1,
			"col": Color(0.08, 0.19, 0.34)},
	]
	for k in layers.size():
		var L: Dictionary = layers[k]
		var pts := PackedVector2Array()
		pts.append(Vector2(0.0, h))
		var steps := 48
		for i in steps + 1:
			var x := w * float(i) / float(steps)
			var y: float = float(L["y"]) \
				+ sin(x / float(L["len"]) * TAU + _phase * float(L["sp"])) * float(L["amp"]) \
				+ sin(x / (float(L["len"]) * 0.37) + _phase * float(L["sp"]) * 1.7) * float(L["amp"]) * 0.3
			pts.append(Vector2(x, y))
		pts.append(Vector2(w, h))
		draw_colored_polygon(pts, L["col"])
	# e42: 月光在水面上那道抖动的反光 —— 有了它海才不像一块布
	for i in 12:
		var u := float(i) / 11.0
		var ry := horizon + 5.0 + u * (h - horizon) * 0.60
		var rw: float = w * (0.020 + u * 0.080) * (0.84 + 0.16 * sin(_phase * 2.1 + u * 5.0))
		draw_rect(Rect2(w * 0.78 - rw * 0.5, ry, rw, 2.0),
			Color(1.0, 0.96, 0.84, 0.070 * (1.0 - u)))
	# e42: 浪尖上的一线碎光
	for i in 24:
		var x := fposmod(float(i) * w * 0.061 + _phase * 13.0, w)
		var u2 := float(i) / 23.0
		var y: float = horizon + h * 0.035 + u2 * h * 0.28 \
			+ sin(x / (w * 0.26) * TAU + _phase * 1.1) * h * 0.013
		draw_rect(Rect2(x, y, 14.0 + u2 * 24.0, 1.0), Color(0.86, 0.93, 1.0, 0.085))
	# e42: 暗角 —— 四边向内压一层黑, 视线自然收到中间的菜单上
	var depth: float = minf(w, h) * 0.20
	var vsteps := 18
	for i in vsteps:
		var u := float(i) / float(vsteps)
		var va := 0.050 * (1.0 - u)
		var d := u * depth
		draw_rect(Rect2(0.0, d, w, 1.6), Color(0, 0, 0, va))
		draw_rect(Rect2(0.0, h - d - 1.6, w, 1.6), Color(0, 0, 0, va))
		draw_rect(Rect2(d, 0.0, 1.6, h), Color(0, 0, 0, va))
		draw_rect(Rect2(w - d - 1.6, 0.0, 1.6, h), Color(0, 0, 0, va))
	# e21: 帆船剪影（开场动画驶入, 之后常驻海面随浪摇曳）
	if _boat_x >= 0.0:
		_draw_boat(w, h)


func _draw_boat(w: float, h: float) -> void:
	var horizon := h * 0.46
	var bob := sin(_phase * 2.2) * 3.0                     # 随浪起伏
	var base := Vector2(_boat_x, horizon + h * 0.055 + bob)
	var tilt := sin(_phase * 1.6) * 0.045                  # 轻微摇摆
	var s := clampf(minf(w, h) / 640.0, 0.7, 1.4)          # 整体缩放
	var hull_c := Color(0.30, 0.19, 0.12)
	var hull_dk := Color(0.22, 0.13, 0.08)
	var sail_c := Color(0.93, 0.90, 0.82)
	var sail_dk := Color(0.80, 0.76, 0.68)
	# 船体: 上宽下窄的梯形, 底部深色一条
	var hull := PackedVector2Array([
		base + Vector2(-34, -6) * s, base + Vector2(34, -6) * s,
		base + Vector2(22, 8) * s, base + Vector2(-22, 8) * s])
	draw_colored_polygon(hull, hull_c)
	draw_line(base + Vector2(-22, 8) * s, base + Vector2(22, 8) * s, hull_dk, 3.0 * s)
	# 桅杆
	draw_line(base + Vector2(0, -6) * s, base + Vector2(2, -46) * s, hull_dk, 2.5 * s)
	# 主帆(白色大三角, 随风微鼓) + 前帆(小三角)
	var sway := sin(_phase * 0.9) * 3.0 * s
	var mainsail := PackedVector2Array([
		base + Vector2(2, -44) * s,
		base + Vector2(24 + sway, -12) * s,
		base + Vector2(4, -8) * s])
	draw_colored_polygon(mainsail, sail_c)
	var foresail := PackedVector2Array([
		base + Vector2(0, -38) * s,
		base + Vector2(-26 + sway * 0.6, -10) * s,
		base + Vector2(-2, -8) * s])
	draw_colored_polygon(foresail, sail_dk)
	# e42: 桅顶三角旗(跟着风摆)
	var pennant := PackedVector2Array([
		base + Vector2(2, -46) * s,
		base + Vector2(17 + sway * 0.5, -42) * s,
		base + Vector2(2, -37) * s])
	draw_colored_polygon(pennant, Color(0.80, 0.30, 0.24))
	# e42: 船尾挂一盏灯 —— 暖光晕 + 一点灯芯, 夜海就活了一个人
	draw_circle(base + Vector2(-27, -11) * s, 10.0 * s, Color(1.0, 0.80, 0.45, 0.14))
	draw_circle(base + Vector2(-27, -11) * s, 2.3 * s, Color(1.0, 0.88, 0.60, 0.85))
	# 船底倒影(半透明模糊椭圆)
	draw_circle(base + Vector2(0, 16) * s, 26.0 * s, Color(0.05, 0.10, 0.16, 0.35))
