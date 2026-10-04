# cutscene_base.gd —— 过场动画基类: 布景工具箱 + 幕驱动 (e42)
#
# 为什么要有这个基类:
#   · 序章 (scene/opening.gd) 原来自己搭了一整套「黑幕 + 字幕 + 点击推进 + 跳过」的壳,
#     e42 又要加好几段剧情过场 —— 复制五遍那套壳显然不行, 于是抽到这里。
#   · 壳 (幕驱动 / 字幕 / 跳过 / finished) 加工具箱 (天空 / 星野 / 云 / 海面 / 光晕 /
#     粒子 / 剪影 / 暗角 / 闪白 / 震屏) 全在这个文件里;
#     每段过场只写自己的 STEPS 和 _scene_* 布景方法。
#
# 画面一律代码绘制, 不新增贴图资源 (跟序章原来的口径一致)。
# ❗文案约束: IPix.ttf 没有全角标点 / 竖线 / 箭头字形 —— 标点只用 ASCII。
#
# 两种用法:
#   1) 一次性过场 (scene/opening.gd): extends 本类, 覆写 steps(), auto_run 保持 true,
#      播完自动 queue_free。
#   2) 常驻过场机 (cutscenes.gd, 是 autoload): auto_run = false, free_on_finish = false,
#      随时调 start_steps(list) 反复放不同的幕。
#
# ❗层级口径 (selftest 50 节盯着): 布景节点一律走 _add_prop(), 它们被插在字幕衬条
#   _cap_bg 之前 —— 于是「字幕永远画在布景之上」, 收尾淡出也一起淡。
extends CanvasLayer

signal finished
signal started

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const CAPTION_DUR := 3.4        # 每幕文字停留秒数
const FADE_DUR := 0.8
const TITLE_DUR := 2.2          # 章节标题卡停留秒数
const INK := Color(0.035, 0.040, 0.055)

var auto_run := true            # false = 先把景搭好藏着, 等 start_steps()
var free_on_finish := true      # false = 播完只隐藏 (autoload 用, 不能自杀)

var _root: ColorRect            # 整块黑幕 (所有东西的爹)
var _sky: TextureRect           # 天幕底层
var _sky2: TextureRect          # 天幕交叉淡入层
var _stars: Control
var _clouds: Control
var _sea: Control
var _cap_bg: TextureRect        # 字幕底衬 (底部渐隐的黑条)
var _caption: Label
var _hint: Label
var _skip_btn: Button
var _title_box: VBoxContainer
var _title_lbl: Label
var _sub_lbl: Label
var _title_line: ColorRect
var _vignette: Control          # 暗角
var _fx: Control                # 粒子 (雨 / 火星 / 雪 / 萤火)
var _glow: Control              # 径向光晕
var _flash_rect: ColorRect
var _wipe_rect: ColorRect

var _props: Array = []          # 本幕的布景节点 (重放前统一清掉)
var _cur_steps: Array = []
var _a_tw: Dictionary = {}      # 每个节点的透明度 tween (重设时先 kill 掉旧的)
var _sky_tw: Tween = null

var _jump := false              # 点击 / 按键: 快进到下一幕
var _skip_all := false          # 跳过按钮: 直接放完
var _done := false

# 震屏 (整块黑幕轻微位移; 字幕跟着抖一下, 正好像镜头被晃了)
var _shake_amp := 0.0
var _shake_dur := 0.0
var _shake_left := 0.0

func _ready() -> void:
	layer = 80
	_build()
	if auto_run:
		_run()
	else:
		visible = false
		set_process(false)

# ---------------- 幕驱动 ----------------
# 子类覆写这个返回自己的幕表 (每项 = [文案, 布景方法名])
func steps() -> Array:
	return _cur_steps

# 反复放片的入口 (cutscenes.gd 用)
func start_steps(list: Array) -> void:
	_cur_steps = list
	_jump = false
	_skip_all = false
	_done = false
	_reset_stage()
	visible = true
	set_process(true)
	started.emit()
	_run()

func _run() -> void:
	for st in steps():
		if _skip_all:
			break
		_jump = false
		call(String(st[1]))
		await _show_caption(String(st[0]))
	_finish()

func _show_caption(text: String) -> void:
	_caption.text = text
	_caption.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, FADE_DUR)
	# 分片等待: 随时可被「下一幕」打断
	var t := 0.0
	while t < CAPTION_DUR and not _jump and not _skip_all:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	if not _skip_all and not _jump:
		var out := create_tween()
		out.tween_property(_caption, "modulate:a", 0.0, 0.45)
		await out.finished
	_caption.text = ""

func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec and not _jump and not _skip_all:
		await get_tree().create_timer(0.05).timeout
		t += 0.05

func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	await tw.finished
	finished.emit()
	if free_on_finish:
		queue_free()
	else:
		visible = false
		set_process(false)

# ---------------- 搭景 ----------------
func _build() -> void:
	# 震屏衬底: _root 是 FULL_RECT, 被 shake 偏移时四周会露出下面的空屏 ——
	# 先垫一圈同色外扩底, 震幅（最大 9px）永远出不了这 48px 的边
	var pad := ColorRect.new()
	pad.color = INK
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.offset_left = -48.0
	pad.offset_top = -48.0
	pad.offset_right = 48.0
	pad.offset_bottom = 48.0
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
	_root = ColorRect.new()
	_root.color = INK
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	var base_sky := _grad_tex(Color(0.05, 0.06, 0.10), Color(0.10, 0.12, 0.18))
	_sky = _mk_sky(base_sky)
	_sky.modulate.a = 0.0
	_sky2 = _mk_sky(base_sky)
	_sky2.modulate.a = 0.0

	_stars = _fill(StarField.new())
	_stars.modulate.a = 0.0
	_clouds = _fill(CloudLayer.new())
	_clouds.modulate.a = 0.0
	_sea = _fill(SeaField.new())
	_sea.modulate.a = 0.0

	# 字幕底衬: 底部渐隐的黑条 (不衬一下, 亮天幕上的字幕会飘)
	_cap_bg = TextureRect.new()
	_cap_bg.texture = _grad_tex(Color(0, 0, 0, 0), Color(0, 0, 0, 0.66))
	_cap_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cap_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_cap_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cap_bg.offset_top = -240.0
	_cap_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cap_bg)

	_caption = _mk_label("", 20, Color(0.95, 0.92, 0.84))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.anchor_left = 0.5
	_caption.anchor_right = 0.5
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = -380.0
	_caption.offset_right = 380.0
	_caption.offset_top = -280.0
	_caption.offset_bottom = -160.0
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_caption.add_theme_constant_override("outline_size", 6)
	_root.add_child(_caption)

	_hint = _mk_label("点击或按任意键继续", 11, Color(0.52, 0.50, 0.46))
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -100.0
	_hint.offset_right = 100.0
	_hint.offset_top = -70.0
	_hint.offset_bottom = -50.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)

	# 章节标题卡: 大字 + 金线 + 小字 (居中偏上)
	_title_box = VBoxContainer.new()
	_title_box.anchor_left = 0.0
	_title_box.anchor_right = 1.0
	_title_box.anchor_top = 0.30
	_title_box.anchor_bottom = 0.30
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_theme_constant_override("separation", 6)
	_title_box.modulate.a = 0.0
	_root.add_child(_title_box)

	_title_lbl = _mk_label("", 34, Color(1.0, 0.92, 0.70))
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_color_override("font_outline_color", Color(0.03, 0.02, 0.02, 0.9))
	_title_lbl.add_theme_constant_override("outline_size", 8)
	_title_box.add_child(_title_lbl)

	_title_line = ColorRect.new()
	_title_line.color = Color(0.88, 0.72, 0.36, 0.9)
	_title_line.custom_minimum_size = Vector2(150, 2)
	_title_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.add_child(_title_line)

	_sub_lbl = _mk_label("", 13, Color(0.74, 0.72, 0.66))
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_box.add_child(_sub_lbl)

	_vignette = _fill(Vignette.new())
	_vignette.modulate.a = 0.0
	_fx = _fill(ParticleField.new())
	_fx.modulate.a = 0.0
	_glow = _fill(GlowOrb.new())
	_glow.modulate.a = 0.0

	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash_rect)

	_wipe_rect = ColorRect.new()
	_wipe_rect.color = Color(0, 0, 0, 0)
	_wipe_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_wipe_rect)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.add_theme_font_override("font", PIXEL_FONT)
	_skip_btn.add_theme_font_size_override("font_size", 12)
	_skip_btn.anchor_left = 1.0
	_skip_btn.anchor_right = 1.0
	_skip_btn.anchor_top = 0.0
	_skip_btn.anchor_bottom = 0.0
	_skip_btn.offset_left = -92.0
	_skip_btn.offset_right = -28.0
	_skip_btn.offset_top = 22.0
	_skip_btn.offset_bottom = 50.0
	_skip_btn.pressed.connect(func() -> void: _skip_all = true)
	_root.add_child(_skip_btn)

func _mk_sky(tex: Texture2D) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tr)
	return tr

func _fill(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c

func _mk_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# 1 像素宽的竖向渐变贴图 (拉伸成整块天幕)
func _grad_tex(top: Color, bot: Color, steps := 96) -> ImageTexture:
	var img := Image.create_empty(1, steps, false, Image.FORMAT_RGBA8)
	for y in steps:
		img.set_pixel(0, y, top.lerp(bot, float(y) / float(maxi(1, steps - 1))))
	return ImageTexture.create_from_image(img)

func _vw() -> Vector2:
	var r := get_viewport().get_visible_rect().size
	return r if r.x > 4.0 else Vector2(1152.0, 648.0)

# ---------------- 布景小工具 ----------------
# 布景节点统一走这里: 插在字幕衬条之前 -> 永远被字幕盖住, 收尾也跟着一起淡
func _add_prop(n: Node) -> Node:
	_root.add_child(n)
	_root.move_child(n, _cap_bg.get_index())
	_props.append(n)
	return n

# 一条横向色带 (比例定位): y/h 都是 0..1
func _band(y_frac: float, h_frac: float, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = y_frac
	c.anchor_bottom = y_frac + h_frac
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _add_prop(c) as ColorRect

# 山脊 / 城墙剪影: keys 是一串 [x 比例, 高度比例], 底边封到画面底
func _ridge(keys: Array, base_frac: float, color: Color) -> Polygon2D:
	var v := _vw()
	var pts := PackedVector2Array()
	for k in keys:
		pts.append(Vector2(float(k[0]) * v.x, base_frac * v.y - float(k[1]) * v.y))
	pts.append(Vector2(v.x, v.y))
	pts.append(Vector2(0.0, v.y))
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = color
	_add_prop(poly)
	return poly

# 城墙: 底带 + 一排城垛子
func _wall_tower(x_frac: float, w_frac: float, y_frac: float, color: Color) -> Node2D:
	var v := _vw()
	var box := Node2D.new()
	var body := Polygon2D.new()
	var x0 := x_frac * v.x
	var x1 := (x_frac + w_frac) * v.x
	var y0 := y_frac * v.y
	body.polygon = PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, v.y), Vector2(x0, v.y)])
	body.color = color
	box.add_child(body)
	var n := maxi(3, int((x1 - x0) / 26.0))
	for i in n:
		var mx := x0 + (x1 - x0) * (float(i) + 0.5) / float(n)
		var merlon := Polygon2D.new()
		merlon.polygon = PackedVector2Array([
			Vector2(mx - 8.0, y0), Vector2(mx + 8.0, y0),
			Vector2(mx + 8.0, y0 - 12.0), Vector2(mx - 8.0, y0 - 12.0)])
		merlon.color = color
		box.add_child(merlon)
	_add_prop(box)
	return box

# 一面小旗 (旗杆 + 旗面), 返回 [杆顶坐标所在 Node2D, 旗面 Polygon2D]
func _flag_prop(x_frac: float, y_frac: float, h: float, cloth: Color) -> Array:
	var v := _vw()
	var box := Node2D.new()
	box.position = Vector2(x_frac * v.x, y_frac * v.y)
	var pole := Polygon2D.new()
	pole.polygon = PackedVector2Array([
		Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(1.5, -h), Vector2(-1.5, -h)])
	pole.color = Color(0.26, 0.21, 0.16)
	box.add_child(pole)
	var face := Polygon2D.new()
	face.polygon = PackedVector2Array([
		Vector2(1.5, -h), Vector2(h * 0.62, -h + 5.0),
		Vector2(h * 0.58, -h + h * 0.44), Vector2(1.5, -h + h * 0.52)])
	face.color = cloth
	box.add_child(face)
	_add_prop(box)
	return [box, face]

# ---------------- 工具箱: 天幕 / 星 / 云 / 海 / 光 / 粒子 ----------------
# 天幕换色: 每次调用都把上一张定格成底, 新的一张交叉淡入 (绝不会有闪变)
func sky_to(top: Color, bot: Color, dur := 1.2) -> void:
	if _sky_tw != null and _sky_tw.is_valid():
		_sky_tw.kill()
		if _sky2.texture != null and _sky2.modulate.a > 0.5:
			_sky.texture = _sky2.texture
	var tex := _grad_tex(top, bot)
	if _sky.modulate.a < 1.0:
		# 第一张天幕: 直接铺上, 从黑里浮出来
		_sky.texture = tex
		_sky_tw = create_tween()
		_sky_tw.tween_property(_sky, "modulate:a", 1.0, maxf(0.02, dur))
		return
	_sky2.texture = tex
	_sky2.modulate.a = 0.0
	_sky_tw = create_tween()
	_sky_tw.tween_property(_sky2, "modulate:a", 1.0, maxf(0.02, dur))
	_sky_tw.tween_callback(func() -> void: _sky.texture = tex)

func stars_on(a := 0.85, dur := 1.2) -> void:
	_tween_a(_stars, a, dur)

func clouds_on(a := 0.55, dur := 1.4) -> void:
	_tween_a(_clouds, a, dur)

# 海面: horizon 是海平线的高度比例 (0.62 = 偏上)
func sea_on(horizon := 0.66, a := 1.0, dur := 1.4) -> void:
	_sea.set("horizon", horizon)
	_sea.queue_redraw()
	_tween_a(_sea, a, dur)

func sea_off(dur := 0.8) -> void:
	_tween_a(_sea, 0.0, dur)

# 光晕: pos 是比例坐标, color 是光色, radius 是像素半径
func glow_at(pos: Vector2, color: Color, radius := 340.0, a := 0.85, dur := 1.4) -> void:
	_glow.set("gpos", pos)
	_glow.set("gcolor", color)
	_glow.set("gradius", radius)
	_glow.queue_redraw()
	_tween_a(_glow, a, dur)

func glow_off(dur := 1.0) -> void:
	_tween_a(_glow, 0.0, dur)

# 粒子: mode = "embers" 火星上飘 / "rain" 斜雨 / "snow" 落雪 / "fireflies" 萤火
func fx_on(mode: String, amount := 90, a := 1.0) -> void:
	_fx.call("setup", mode, amount)
	_tween_a(_fx, a, 0.7)

func fx_off(dur := 1.0) -> void:
	_tween_a(_fx, 0.0, dur)

func vignette_on(a := 0.5, dur := 1.2) -> void:
	_tween_a(_vignette, a, dur)

# 闪白 / 闪红: 走 _flash_rect
func flash(color := Color(1, 1, 1), a := 0.75, sec := 0.4) -> void:
	_flash_rect.color = Color(color.r, color.g, color.b, a)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, maxf(0.05, sec))

# 震屏
func shake(amount := 6.0, sec := 0.6) -> void:
	_shake_amp = amount
	_shake_dur = sec
	_shake_left = sec

# 章节标题卡: 大字 + 金线 + 小字, 淡入停留后淡出
func title_card(main: String, sub := "", dur := TITLE_DUR) -> void:
	_title_lbl.text = main
	_sub_lbl.text = sub
	_title_box.modulate.a = 0.0
	_title_line.scale = Vector2(0.2, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_title_box, "modulate:a", 1.0, 0.7)
	tw.tween_property(_title_line, "scale:x", 1.0, 0.9)
	tw.chain().tween_property(_title_box, "modulate:a", 0.0, 0.6).set_delay(maxf(0.0, dur - 1.3))

func _tween_a(n: Node, a: float, dur: float) -> void:
	var key := n.get_instance_id()
	if _a_tw.has(key) and is_instance_valid(_a_tw[key]):
		(_a_tw[key] as Tween).kill()
	var tw := create_tween()
	tw.tween_property(n, "modulate:a", a, maxf(0.02, dur))
	_a_tw[key] = tw

# ---------------- 每幕收场复位 ----------------
func _reset_stage() -> void:
	for p in _props:
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	for k in _a_tw.keys():
		if is_instance_valid(_a_tw[k]):
			(_a_tw[k] as Tween).kill()
	_a_tw.clear()
	if _sky_tw != null and _sky_tw.is_valid():
		_sky_tw.kill()
	_root.modulate = Color(1, 1, 1, 1)
	_root.position = Vector2.ZERO
	_sky.modulate.a = 0.0
	_sky2.modulate.a = 0.0
	_stars.modulate.a = 0.0
	_clouds.modulate.a = 0.0
	_sea.modulate.a = 0.0
	_fx.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_vignette.modulate.a = 0.0
	_caption.text = ""
	_caption.modulate.a = 0.0
	_cap_bg.modulate.a = 0.0
	_title_box.modulate.a = 0.0
	_hint.modulate.a = 1.0
	_skip_btn.visible = true
	_flash_rect.color = Color(1, 1, 1, 0)
	_wipe_rect.color = Color(0, 0, 0, 0)
	_shake_left = 0.0

func _process(delta: float) -> void:
	if _cap_bg != null:
		_cap_bg.modulate.a = _caption.modulate.a
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k := _shake_left / maxf(0.001, _shake_dur)
		var amp := _shake_amp * k * k
		_root.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	elif _root != null and _root.position != Vector2.ZERO:
		_root.position = Vector2.ZERO

# ---------------- 输入 ----------------
func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		_jump = true

# 任意按键推进一幕。走 _input 而不是 _unhandled_input ——
# autoload 是常驻节点, 排在主场景之前, 主场景的 _unhandled_input 会先跑
# (B/T/F/Esc 都能漏进去); _input 在 GUI 之前, 键盘一把按死。
# ❗鼠标不在这里按死: 按死了「跳过」按钮就永远点不着 —— 鼠标交给 GUI,
#   _root 是 MOUSE_FILTER_STOP, 点空处由 _on_gui_input 收, 点按钮由按钮收。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed:
		_jump = true
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		_jump = true

# ================= 绘制内件 (全部自绘, 不占贴图) =================

# 星野: 一堆小方点 + 各自闪烁相位, 整片缓慢横移
class StarField:
	extends Control

	var t := 0.0
	var stars: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260925
		for i in 110:
			stars.append({
				"x": rng.randf(), "y": rng.randf() * 0.62,
				"s": rng.randf_range(1.0, 2.6),
				"p": rng.randf() * TAU, "sp": rng.randf_range(0.5, 1.9),
			})
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		for st in stars:
			var a: float = 0.30 + 0.70 * (0.5 + 0.5 * sin(t * float(st["sp"]) + float(st["p"])))
			var s: float = float(st["s"])
			var x: float = fposmod(float(st["x"]) * w - t * 3.0, w)
			draw_rect(Rect2(x, float(st["y"]) * h, s, s), Color(1.0, 0.98, 0.90, a))


# 云: 每朵由几个半透明圆叠出来, 整片缓慢右移
class CloudLayer:
	extends Control

	var t := 0.0
	var puffs: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 9911
		for i in 14:
			puffs.append({
				"x": rng.randf(), "y": rng.randf_range(0.08, 0.72),
				"r": rng.randf_range(44.0, 96.0),
				"sp": rng.randf_range(3.0, 9.0),
				"a": rng.randf_range(0.30, 0.60),
			})
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		for p in puffs:
			var x: float = fposmod(float(p["x"]) * w + t * float(p["sp"]), w + 360.0) - 180.0
			var y: float = float(p["y"]) * h
			var r: float = float(p["r"])
			var a: float = float(p["a"])
			for k in 5:
				var off := Vector2(float(k - 2) * r * 0.55, absf(float(k - 2)) * r * 0.16)
				draw_circle(Vector2(x, y) + off, r * (1.0 - absf(float(k - 2)) * 0.16),
					Color(1.0, 0.97, 0.94, a * 0.10))


# 海面: 海平线以下垫底色 + 3 层正弦浪 + 一条反光
class SeaField:
	extends Control

	var t := 0.0
	var horizon := 0.66
	var deep := Color(0.10, 0.20, 0.32)
	var layers: Array = [
		{"dy": 0.010, "amp": 0.016, "len": 0.30, "sp": 0.9,
			"col": Color(0.15, 0.27, 0.40)},
		{"dy": 0.075, "amp": 0.022, "len": 0.24, "sp": 1.5,
			"col": Color(0.10, 0.20, 0.33)},
		{"dy": 0.170, "amp": 0.028, "len": 0.20, "sp": 2.2,
			"col": Color(0.06, 0.14, 0.26)},
	]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		var hz := horizon * h
		draw_rect(Rect2(0.0, hz, w, h - hz), deep)
		for L in layers:
			var pts := PackedVector2Array()
			pts.append(Vector2(0.0, h))
			var steps := 44
			for i in steps + 1:
				var x := w * float(i) / float(steps)
				var y: float = hz + float(L["dy"]) * h \
					+ sin(x / (float(L["len"]) * w) * TAU + t * float(L["sp"])) * float(L["amp"]) * h \
					+ sin(x / (float(L["len"]) * w * 0.37) + t * float(L["sp"]) * 1.7) \
						* float(L["amp"]) * h * 0.3
				pts.append(Vector2(x, y))
			pts.append(Vector2(w, h))
			draw_colored_polygon(pts, L["col"])
		# 月/日在水面上的那一道反光
		var gx := w * 0.5
		for i in 10:
			var u := float(i) / 9.0
			var y := hz + 6.0 + u * (h - hz) * 0.55
			var wdt := w * (0.03 + u * 0.10) * (0.8 + 0.2 * sin(t * 1.7 + u * 6.0))
			draw_rect(Rect2(gx - wdt * 0.5, y, wdt, 2.0),
				Color(1.0, 0.95, 0.82, 0.055 * (1.0 - u)))


# 径向光晕: 一圈圈同心半透明圆叠出柔光 (内亮外淡)
class GlowOrb:
	extends Control

	var t := 0.0
	var gpos := Vector2(0.5, 0.5)
	var gcolor := Color(1.0, 0.85, 0.55)
	var gradius := 340.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(gpos.x * size.x, gpos.y * size.y)
		var r: float = gradius * (1.0 + 0.035 * sin(t * 1.3))
		for i in 18:
			var u := float(i) / 17.0
			draw_circle(c, r * (1.0 - u * 0.92),
				Color(gcolor.r, gcolor.g, gcolor.b, 0.030))


# 暗角: 四条边由外向内一层层压黑
class Vignette:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		var depth: float = minf(w, h) * 0.24
		var steps := 26
		for i in steps:
			var u := float(i) / float(steps)
			var a := 0.020 * (1.0 - u * 0.7)
			var d := u * depth
			draw_rect(Rect2(0.0, d, w, depth / float(steps) + 1.0), Color(0, 0, 0, a))
			draw_rect(Rect2(0.0, h - d - 2.0, w, 2.0), Color(0, 0, 0, a))
			draw_rect(Rect2(d, 0.0, depth / float(steps) + 1.0, h), Color(0, 0, 0, a))
			draw_rect(Rect2(w - d - 2.0, 0.0, 2.0, h), Color(0, 0, 0, a))


# 粒子: 火星上飘 / 斜雨 / 落雪 / 萤火, 四种模式共用一套积分
class ParticleField:
	extends Control

	var t := 0.0
	var mode := "embers"
	var ps: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		setup("embers", 0)
		set_process(true)

	func setup(m: String, amount: int) -> void:
		mode = m
		ps.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711 + amount
		for i in amount:
			ps.append({
				"x": rng.randf(), "y": rng.randf(),
				"s": rng.randf_range(1.0, 2.6),
				"v": rng.randf_range(0.05, 0.22),
				"p": rng.randf() * TAU,
			})

	func _process(delta: float) -> void:
		t += delta
		if not ps.is_empty():
			_step(delta)
			queue_redraw()

	func _step(delta: float) -> void:
		var d := minf(delta, 0.05)
		for p in ps:
			match mode:
				"embers":
					p["y"] = fposmod(float(p["y"]) - float(p["v"]) * d, 1.05) - 0.025
					p["x"] = fposmod(float(p["x"]) + sin(t * 1.8 + float(p["p"])) * 0.03 * d, 1.0)
				"rain":
					p["y"] = fposmod(float(p["y"]) + float(p["v"]) * 3.4 * d, 1.05) - 0.025
					p["x"] = fposmod(float(p["x"]) - float(p["v"]) * 0.9 * d, 1.0)
				"snow":
					p["y"] = fposmod(float(p["y"]) + float(p["v"]) * 0.6 * d, 1.05) - 0.025
					p["x"] = fposmod(float(p["x"]) + sin(t * 1.1 + float(p["p"])) * 0.05 * d, 1.0)
				"fireflies":
					p["y"] = fposmod(float(p["y"]) + sin(t * 0.9 + float(p["p"])) * 0.05 * d, 1.0)
					p["x"] = fposmod(float(p["x"]) + cos(t * 0.7 + float(p["p"])) * 0.06 * d, 1.0)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		for p in ps:
			var x := float(p["x"]) * w
			var y := float(p["y"]) * h
			var s: float = float(p["s"])
			var flick: float = 0.5 + 0.5 * sin(t * 3.1 + float(p["p"]))
			match mode:
				"embers":
					draw_rect(Rect2(x, y, s, s), Color(1.0, 0.62, 0.26, 0.35 + 0.5 * flick))
				"rain":
					draw_line(Vector2(x, y), Vector2(x - 2.0, y + 9.0),
						Color(0.72, 0.82, 0.95, 0.35 + 0.3 * flick), 1.0)
				"snow":
					draw_rect(Rect2(x, y, s, s), Color(0.94, 0.96, 1.0, 0.45 + 0.35 * flick))
				"fireflies":
					draw_circle(Vector2(x, y), s, Color(1.0, 0.92, 0.55, 0.25 + 0.6 * flick))