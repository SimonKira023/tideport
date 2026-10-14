# cutscene_base.gd —— 过场动画基类: 影视级布景工具箱 + 幕驱动 (e42 / e53 重制)
#
# 为什么要有这个基类:
#   · 序章 (scene/opening.gd) 原来自己搭了一整套「黑幕 + 字幕 + 点击推进 + 跳过」的壳,
#     e42 又要加好几段剧情过场 —— 复制五遍那套壳显然不行, 于是抽到这里。
#   · 壳 (幕驱动 / 字幕 / 跳过 / finished) 加工具箱 (天幕 / 星野 / 云 / 海面 / 光晕 /
#     粒子 / 剪影 / 暗角 / 闪白 / 震屏) 全在这个文件里;
#     每段过场只写自己的 STEPS 和 _scene_* 布景方法。
#
# e53 重制 —— 目标: 工作室级 CG, 而不是「几个贴图在那里移动」:
#   · 天幕不再是一块渐变, 而是 多层天空 + 星野(含银河带与流星) + 体积云(受光面/背光面) +
#     镜面海(渐变水体 + 天空倒影 + 七层浪 + 碎光路径) + 体积光(丁达尔) + 日月(月牙几何) +
#     飞鸟 + 分层雾。
#   · 收尾加 电影遮幅(letterbox) + 手持呼吸漂移 + dolly 推轨 + 胶片颗粒 shader。
#   · 旗帜改成布料模拟 (WavingCloth, 顶点每帧重算), 不再是一块硬多边形。
#   · 所有光晕走 CanvasItemMaterial.BLEND_MODE_ADD + 运行时径向渐变贴图, 不再是叠圆。
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
# ❗层级口径 (selftest 46/50 节盯着): 布景节点一律走 _add_prop(), 它们被插在雾层 _fog
#   之前, 而 _fog 又紧贴字幕衬条 _cap_bg 之前 —— 于是「字幕永远画在布景之上」,
#   收尾淡出也一起淡。
#
# CanvasLayer 直属子节点 (从下到上):
#   pad(震屏外扩底) -> _root(所有布景) -> _bar_top -> _bar_bot -> _grain(胶片颗粒)
# 遮幅条与颗粒刻意放在 _root 外面: 镜头 shake / dolly 时遮幅纹丝不动, 这才是电影感。
extends CanvasLayer

signal finished
signal started

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const CAPTION_DUR := 3.4        # 每幕文字停留秒数
const FADE_DUR := 0.8
const TITLE_DUR := 2.2          # 章节标题卡停留秒数
const INK := Color(0.035, 0.040, 0.055)
const BAR_H := 72.0             # 电影遮幅条高度
const GRAIN_A := 0.055          # 胶片颗粒强度 (shader uniform)

# 胶片颗粒: 24fps 步进的 hash 噪声, 明暗双色斑点。
# ❗刻意不用 hint_screen_texture —— D3D12 后端抓屏偶发黑屏, 这里只需一层噪声。
const GRAIN_CODE := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 0.2) = 0.055;
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	vec2 np = UV * vec2(640.0, 360.0);
	float f = floor(TIME * 24.0);
	float n = hash12(np + vec2(f * 37.0, f * 17.0));
	float d = n - 0.5;
	vec3 col = d > 0.0 ? vec3(1.0) : vec3(0.0);
	COLOR = vec4(col, abs(d) * 2.0 * intensity);
}
"""

var auto_run := true            # false = 先把景搭好藏着, 等 start_steps()
var free_on_finish := true      # false = 播完只隐藏 (autoload 用, 不能自杀)

var _root: ColorRect            # 整块黑幕 (所有布景的爹)
var _sky: TextureRect           # 天幕底层
var _sky2: TextureRect          # 天幕交叉淡入层
var _stars: Control
var _clouds: Control
var _sea: Control
var _fog: Control               # 分层雾 (布景之上, 字幕之下)
var _rays: Control              # 体积光
var _lum: Control               # 日 / 月
var _birds: Control             # 飞鸟
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

var _bar_top: ColorRect         # 电影遮幅 (上)
var _bar_bot: ColorRect         # 电影遮幅 (下)
var _grain: ColorRect           # 胶片颗粒

var _props: Array = []          # 本幕的布景节点 (重放前统一清掉)
var _cur_steps: Array = []
var _a_tw: Dictionary = {}      # 每个节点的透明度 tween (重设时先 kill 掉旧的)
var _sky_tw: Tween = null
var _dolly_tw: Tween = null

var _jump := false              # 点击 / 按键: 快进到下一幕
var _skip_all := false          # 跳过按钮: 直接放完
var _done := false
var _cinema_on := false

# 震屏 (整块黑幕轻微位移; 字幕跟着抖一下, 正好像镜头被晃了)
var _shake_amp := 0.0
var _shake_dur := 0.0
var _shake_left := 0.0

# 手持呼吸 (永远在跑的极小漂移, 让静态画面也「活着」)
var _drift_t := 0.0

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
	# 遮幅 / 颗粒 / 字幕 / 布景 一起淡 —— 颗粒也淡掉, 不然黑屏上还在闪噪点
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_property(_bar_top, "modulate:a", 0.0, 0.6)
	tw.tween_property(_bar_bot, "modulate:a", 0.0, 0.6)
	tw.tween_property(_grain, "modulate:a", 0.0, 0.6)
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
	_root.pivot_offset = _vw() * 0.5
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
	# 雾层: 建在字幕衬条之前, _add_prop 也插在它之前 -> 布景被雾罩着, 字幕盖在雾上
	_fog = _fill(FogLayer.new())
	_fog.modulate.a = 0.0

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

	# 光效层: 全在字幕之上 —— 体积光打在字幕上也对, 但为了字清楚, 强度压低
	_rays = _fill(GodRays.new())
	_rays.modulate.a = 0.0
	_lum = _fill(Luminary.new())
	_lum.modulate.a = 0.0
	_birds = _fill(BirdFlock.new())
	_birds.modulate.a = 0.0
	_glow = _fill(GlowOrb.new())
	_glow.modulate.a = 0.0

	_vignette = _fill(Vignette.new())
	_vignette.modulate.a = 0.0
	_fx = _fill(ParticleField.new())
	_fx.modulate.a = 0.0

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

	# ---- 遮幅 + 颗粒 (挂在 CanvasLayer 上, 不受 dolly / shake 影响) ----
	_bar_top = ColorRect.new()
	_bar_top.color = Color(0, 0, 0)
	_bar_top.anchor_left = 0.0
	_bar_top.anchor_right = 1.0
	_bar_top.anchor_top = 0.0
	_bar_top.anchor_bottom = 0.0
	_bar_top.offset_left = 0.0
	_bar_top.offset_right = 0.0
	_bar_top.offset_top = 0.0
	_bar_top.offset_bottom = 0.0
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_top)

	_bar_bot = ColorRect.new()
	_bar_bot.color = Color(0, 0, 0)
	_bar_bot.anchor_left = 0.0
	_bar_bot.anchor_right = 1.0
	_bar_bot.anchor_top = 1.0
	_bar_bot.anchor_bottom = 1.0
	_bar_bot.offset_left = 0.0
	_bar_bot.offset_right = 0.0
	_bar_bot.offset_top = 0.0
	_bar_bot.offset_bottom = 0.0
	_bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bot)

	# 操作提示与跳过按钮塞进遮幅条里: 条拉开时它们正好落在黑条上, 条收起来也不挡画面
	_hint = _mk_label("点击或按任意键继续", 11, Color(0.52, 0.50, 0.46))
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -110.0
	_hint.offset_right = 110.0
	_hint.offset_top = -50.0
	_hint.offset_bottom = -26.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_bot.add_child(_hint)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.add_theme_font_override("font", PIXEL_FONT)
	_skip_btn.add_theme_font_size_override("font_size", 12)
	_skip_btn.anchor_left = 1.0
	_skip_btn.anchor_right = 1.0
	_skip_btn.anchor_top = 0.0
	_skip_btn.anchor_bottom = 0.0
	_skip_btn.offset_left = -88.0
	_skip_btn.offset_right = -24.0
	_skip_btn.offset_top = 18.0
	_skip_btn.offset_bottom = 46.0
	_skip_btn.pressed.connect(func() -> void: _skip_all = true)
	_bar_top.add_child(_skip_btn)

	_grain = ColorRect.new()
	_grain.color = Color(1, 1, 1, 1)
	_grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = GRAIN_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("intensity", GRAIN_A)
	_grain.material = mat
	add_child(_grain)

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
# 布景节点统一走这里: 插在雾层之前 -> 永远被雾和字幕盖住, 收尾也跟着一起淡
func _add_prop(n: Node) -> Node:
	_root.add_child(n)
	_root.move_child(n, _fog.get_index())
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

# 一面小旗 (旗杆 + 布料模拟旗面), 返回 [杆顶坐标所在 Node2D, 旗面 Polygon2D]
# ❗旗面是 WavingCloth (Polygon2D 子类), 但 cutscenes.gd 只当它是 Polygon2D 用 ——
#   改多边形顶点是每帧内部干的, 外部 tween 的 rotation_degrees / modulate 照旧生效。
func _flag_prop(x_frac: float, y_frac: float, h: float, cloth: Color) -> Array:
	var v := _vw()
	var box := Node2D.new()
	box.position = Vector2(x_frac * v.x, y_frac * v.y)
	var pole := Polygon2D.new()
	pole.polygon = PackedVector2Array([
		Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(1.5, -h), Vector2(-1.5, -h)])
	pole.color = Color(0.26, 0.21, 0.16)
	box.add_child(pole)
	var face := WavingCloth.new(h * 0.62, h * 0.46, cloth)
	face.position = Vector2(1.5, -h + 2.0)
	box.add_child(face)
	_add_prop(box)
	return [box, face]

# 一簇火 (篝火 / 火盆): 加色辉光 + 火舌 + 烟 + 火星, 返回节点自己 (可拿去 tween)
func fire_prop(x_frac: float, y_frac: float, s := 1.0) -> Node2D:
	var v := _vw()
	var f := FireFx.new(s)
	f.position = Vector2(x_frac * v.x, y_frac * v.y)
	_add_prop(f)
	return f

# ---------------- 工具箱: 天幕 / 星 / 云 / 海 / 光 / 粒子 ----------------
# 天幕换色: 每次调用都把上一张定格成底, 新的一张交叉淡入 (绝不会有闪变)
# 顺带按亮度联动云与海面 —— 天暗了云也得暗, 不然「夜里的白云」一眼假。
func sky_to(top: Color, bot: Color, dur := 1.2) -> void:
	if _sky_tw != null and _sky_tw.is_valid():
		_sky_tw.kill()
		if _sky2.texture != null and _sky2.modulate.a > 0.5:
			_sky.texture = _sky2.texture
	var tex := _grad_tex(top, bot)
	var lum := bot.get_luminance()
	if _sky.modulate.a < 1.0:
		# 第一张天幕: 直接铺上, 从黑里浮出来
		_sky.texture = tex
		_sky_tw = create_tween()
		_sky_tw.tween_property(_sky, "modulate:a", 1.0, maxf(0.02, dur))
	else:
		_sky2.texture = tex
		_sky2.modulate.a = 0.0
		_sky_tw = create_tween()
		_sky_tw.tween_property(_sky2, "modulate:a", 1.0, maxf(0.02, dur))
		_sky_tw.tween_callback(func() -> void: _sky.texture = tex)
	_sync_ambient(lum, dur)

# 按天幕亮度把云和海面倒影一起调过去 (昼 / 黄昏 / 夜 三档)
func _sync_ambient(lum: float, dur: float) -> void:
	var lit: Color
	var shade: Color
	if lum > 0.45:
		lit = Color(1.0, 0.99, 0.96)
		shade = Color(0.72, 0.76, 0.84)
	elif lum > 0.18:
		lit = Color(1.0, 0.80, 0.60)
		shade = Color(0.42, 0.30, 0.38)
	else:
		lit = Color(0.52, 0.58, 0.72)
		shade = Color(0.16, 0.18, 0.28)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_clouds, "lit_col", lit, maxf(0.05, dur))
	tw.tween_property(_clouds, "shade_col", shade, maxf(0.05, dur))
	tw.tween_property(_sea, "sky_ref", lit, maxf(0.05, dur))

func stars_on(a := 0.85, dur := 1.2) -> void:
	_tween_a(_stars, a, dur)

func stars_off(dur := 1.0) -> void:
	_tween_a(_stars, 0.0, dur)

func clouds_on(a := 0.55, dur := 1.4) -> void:
	_tween_a(_clouds, a, dur)

func clouds_off(dur := 1.2) -> void:
	_tween_a(_clouds, 0.0, dur)

# 海面: horizon 是海平线的高度比例 (0.62 = 偏上)
# light_x >= 0 时, 在那一列铺一道碎光路径 (日月倒影)
func sea_on(horizon := 0.66, a := 1.0, dur := 1.4, light_x := -1.0) -> void:
	_sea.set("horizon", horizon)
	_sea.set("spark_x", light_x)
	_sea.queue_redraw()
	_tween_a(_sea, a, dur)

func sea_off(dur := 0.8) -> void:
	_tween_a(_sea, 0.0, dur)

# 体积光 (丁达尔): 从画面外上方斜射进来的一束束楔形光
func rays_at(x_frac := 0.5, color := Color(1.0, 0.90, 0.65), a := 0.5, dur := 1.5) -> void:
	_rays.set("ox", x_frac)
	_rays.set("rcol", color)
	_rays.queue_redraw()
	_tween_a(_rays, a, dur)

func rays_off(dur := 1.0) -> void:
	_tween_a(_rays, 0.0, dur)

# 分层雾: 贴地几条横向雾带 (战场 / 清晨海面都要它)
func fog_on(a := 0.45, dur := 1.5) -> void:
	_tween_a(_fog, a, dur)

func fog_off(dur := 1.2) -> void:
	_tween_a(_fog, 0.0, dur)

# 飞鸟: count 只大小不一的剪影, 从左往右掠过头顶
func birds_on(count := 7, dur := 1.0) -> void:
	_birds.call("setup", count)
	_tween_a(_birds, 1.0, dur)

func birds_off(dur := 0.8) -> void:
	_tween_a(_birds, 0.0, dur)

# 日 / 月: moon=false 是太阳, true 是月牙 (几何法裁出来的真月牙)
func luminary(pos: Vector2, col: Color, r := 90.0, moon := false, dur := 1.2) -> void:
	_lum.set("lpos", pos)
	_lum.set("lcol", col)
	_lum.set("lr", r)
	_lum.set("is_moon", moon)
	_lum.queue_redraw()
	_tween_a(_lum, 1.0, dur)

func lum_off(dur := 1.2) -> void:
	_tween_a(_lum, 0.0, dur)

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

# 电影遮幅: 上下拉出黑条
func cinema(on: bool, dur := 0.9) -> void:
	_cinema_on = on
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_bar_top, "offset_bottom", BAR_H if on else 0.0, maxf(0.05, dur)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bar_bot, "offset_top", -BAR_H if on else 0.0, maxf(0.05, dur)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# dolly 推轨: 以 focus 为轴心把整块布景推近一点点 (超过 1.12 会糊)
func dolly(zoom := 1.06, focus := Vector2(0.5, 0.45), dur := 3.0) -> void:
	if _dolly_tw != null and _dolly_tw.is_valid():
		_dolly_tw.kill()
	var v := _vw()
	_root.pivot_offset = Vector2(focus.x * v.x, focus.y * v.y)
	_dolly_tw = create_tween()
	_dolly_tw.tween_property(_root, "scale", Vector2.ONE * minf(zoom, 1.12), maxf(0.05, dur)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

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
	if _dolly_tw != null and _dolly_tw.is_valid():
		_dolly_tw.kill()
	_root.modulate = Color(1, 1, 1, 1)
	_root.scale = Vector2.ONE
	_root.pivot_offset = _vw() * 0.5
	_root.position = Vector2.ZERO
	_sky.modulate.a = 0.0
	_sky2.modulate.a = 0.0
	_stars.modulate.a = 0.0
	_clouds.modulate.a = 0.0
	_sea.modulate.a = 0.0
	_sea.set("spark_x", -1.0)
	_fog.modulate.a = 0.0
	_rays.modulate.a = 0.0
	_lum.modulate.a = 0.0
	_birds.modulate.a = 0.0
	_fx.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_vignette.modulate.a = 0.0
	_caption.text = ""
	_caption.modulate.a = 0.0
	_cap_bg.modulate.a = 0.0
	_title_box.modulate.a = 0.0
	_hint.modulate.a = 1.0
	_skip_btn.visible = true
	_bar_top.modulate.a = 1.0
	_bar_bot.modulate.a = 1.0
	_grain.modulate.a = 1.0
	# 遮幅一律先收回, 由放片方自己 cinema(true) 拉出来 —— 这样每一段过场都能从
	# 「无遮幅」平滑拉开, 而不是上一段开着、这一段一上来就是开着的
	_cinema_on = false
	_bar_top.offset_bottom = 0.0
	_bar_bot.offset_top = 0.0
	_flash_rect.color = Color(1, 1, 1, 0)
	_wipe_rect.color = Color(0, 0, 0, 0)
	_shake_left = 0.0
	_drift_t = 0.0

func _process(delta: float) -> void:
	if _cap_bg != null and _caption != null:
		_cap_bg.modulate.a = _caption.modulate.a
	if _root == null:
		return
	# 手持呼吸: 两个不同周期的正弦叠出「不可能被听出节拍」的微小漂移
	_drift_t += delta
	var off := Vector2(
		sin(_drift_t * 0.6) * 2.4 + sin(_drift_t * 1.7) * 0.8,
		cos(_drift_t * 0.47) * 1.9 + cos(_drift_t * 1.3) * 0.6)
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k := _shake_left / maxf(0.001, _shake_dur)
		var amp := _shake_amp * k * k
		off += Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	_root.position = off

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

# 星野: 主星 (冷暖四色 + 亮星十字光芒) + 银河带 (斜线高斯散布) + 银河雾 + 流星
class StarField:
	extends Control

	var t := 0.0
	var stars: Array = []      # 主星
	var band: Array = []       # 银河带星
	var mist: Array = []       # 银河雾
	var shots: Array = []      # 流星
	var _next_shot := 3.0
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rng.randomize()
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260925
		var tints := [
			Color(1.0, 1.0, 1.0), Color(1.0, 0.96, 0.88),
			Color(0.82, 0.88, 1.0), Color(1.0, 0.94, 0.74)]
		for i in 90:
			stars.append({
				"x": rng.randf(), "y": rng.randf() * 0.62,
				"s": rng.randf_range(1.0, 2.8),
				"p": rng.randf() * TAU, "sp": rng.randf_range(0.5, 1.9),
				"c": tints[rng.randi_range(0, tints.size() - 1)],
			})
		# 银河带: 沿一条从左上到右下的斜线做高斯散布 —— 带心的星多且亮
		for i in 160:
			var u := rng.randf()
			var gy: float = 0.30 - u * 0.16 + (rng.randf() + rng.randf() + rng.randf() - 1.5) * 0.066
			band.append({
				"x": u, "y": clampf(gy, 0.0, 0.72),
				"s": rng.randf_range(0.8, 1.7),
				"p": rng.randf() * TAU, "sp": rng.randf_range(0.3, 1.1),
			})
		for i in 40:
			var u2 := rng.randf()
			var my: float = 0.30 - u2 * 0.16 + (rng.randf() + rng.randf() + rng.randf() - 1.5) * 0.084
			mist.append({
				"x": u2, "y": clampf(my, 0.0, 0.74),
				"r": rng.randf_range(40.0, 120.0),
				"a": rng.randf_range(0.010, 0.026),
			})
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		# 流星: 随机间隔冒一颗, 0.7 秒走完全程
		_next_shot -= delta
		if _next_shot <= 0.0:
			_next_shot = _rng.randf_range(4.0, 9.0)
			shots.append({
				"x0": _rng.randf_range(0.05, 0.75), "y0": _rng.randf_range(0.02, 0.26),
				"dx": _rng.randf_range(0.18, 0.34), "dy": _rng.randf_range(0.10, 0.20),
				"u": 0.0,
			})
		if not shots.is_empty():
			var alive: Array = []
			for sh in shots:
				sh["u"] = float(sh["u"]) + delta / 0.7
				if float(sh["u"]) < 1.0:
					alive.append(sh)
			shots = alive
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		var drift := fposmod(t * 3.0, w)
		# 银河雾: 一片极淡的蓝白雾, 让银河带不是「凭空多出一串星」
		for m in mist:
			var mx: float = fposmod(float(m["x"]) * w - drift * 0.4, w)
			draw_circle(Vector2(mx, float(m["y"]) * h), float(m["r"]),
				Color(0.72, 0.78, 0.95, float(m["a"])))
		for b in band:
			var a: float = 0.20 + 0.45 * (0.5 + 0.5 * sin(t * float(b["sp"]) + float(b["p"])))
			var s: float = float(b["s"])
			var x: float = fposmod(float(b["x"]) * w - drift, w)
			draw_rect(Rect2(x, float(b["y"]) * h, s, s), Color(0.88, 0.92, 1.0, a))
		for st in stars:
			var a2: float = 0.30 + 0.70 * (0.5 + 0.5 * sin(t * float(st["sp"]) + float(st["p"])))
			var s2: float = float(st["s"])
			var x2: float = fposmod(float(st["x"]) * w - drift, w)
			var y2: float = float(st["y"]) * h
			var c: Color = st["c"]
			draw_rect(Rect2(x2, y2, s2, s2), Color(c.r, c.g, c.b, a2))
			# 亮星补一道十字光芒 —— 星「在闪」而不是「在闪的小方块」
			if s2 > 2.2:
				var tw: float = (s2 - 2.2) * 2.6 * a2
				draw_line(Vector2(x2 - 5.0, y2 + s2 * 0.5), Vector2(x2 + s2 + 5.0, y2 + s2 * 0.5),
					Color(c.r, c.g, c.b, tw * 0.45), 1.0)
				draw_line(Vector2(x2 + s2 * 0.5, y2 - 5.0), Vector2(x2 + s2 * 0.5, y2 + s2 + 5.0),
					Color(c.r, c.g, c.b, tw * 0.45), 1.0)
		for sh in shots:
			var u: float = float(sh["u"])
			var hx: float = float(sh["x0"]) * w + u * float(sh["dx"]) * w
			var hy: float = float(sh["y0"]) * h + u * float(sh["dy"]) * h
			var tail := Vector2(float(sh["dx"]), float(sh["dy"])).normalized() * -w * 0.10
			for k in 8:
				var kk := float(k) / 7.0
				var p := Vector2(hx, hy) + tail * kk
				draw_rect(Rect2(p.x, p.y, 2.0, 2.0),
					Color(1.0, 0.98, 0.92, (1.0 - u) * (1.0 - kk) * 0.9))


# 体积云: 每朵 = 一团「半径/位置都随机」的球 (背光底 + 受光顶); 远层小而慢, 近层大而快
# ❗球不能等大、更不能排成一行 —— 规整的球列剪影一定会被读成「棉花球」;
#   每朵预生成一组不规则 lobes (顶点在椭圆里随机散布), 剪影才有云该有的碎边。
# lit_col / shade_col 可被 sky_to 的亮度联动 tween (所以是属性不是常量)
class CloudLayer:
	extends Control

	var t := 0.0
	var puffs: Array = []
	var lit_col := Color(1.0, 0.97, 0.94)
	var shade_col := Color(0.62, 0.66, 0.76)

	# 一朵云 = 一组不规则球; 返回的是归一化坐标 (乘云半径即得像素偏移)
	static func _mk_lobes(rng: RandomNumberGenerator, n: int, flat: float) -> Array:
		var out: Array = []
		for i in n:
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * 0.92
			out.append({
				"x": cos(ang) * rad, "y": sin(ang) * rad * flat,
				"r": 0.30 + rng.randf() * 0.58})
		return out

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 9911
		for i in 8:
			puffs.append({
				"x": rng.randf(), "y": rng.randf_range(0.05, 0.45),
				"r": rng.randf_range(30.0, 60.0),
				"sp": rng.randf_range(2.0, 5.0),
				"a": rng.randf_range(0.26, 0.46),
				"sq": rng.randf_range(0.55, 0.85),
				"lobes": _mk_lobes(rng, 11, 0.40),
			})
		for i in 6:
			puffs.append({
				"x": rng.randf(), "y": rng.randf_range(0.12, 0.62),
				"r": rng.randf_range(60.0, 110.0),
				"sp": rng.randf_range(5.0, 11.0),
				"a": rng.randf_range(0.14, 0.28),
				"sq": rng.randf_range(0.45, 0.70),
				"lobes": _mk_lobes(rng, 15, 0.32),
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
			var x: float = fposmod(float(p["x"]) * w + t * float(p["sp"]), w + 520.0) - 260.0
			var y: float = float(p["y"]) * h
			var r: float = float(p["r"])
			var a: float = float(p["a"])
			var sq: float = float(p["sq"])
			var lobes: Array = p["lobes"]
			# 背光底: 整朵压低、略往下铺
			for L in lobes:
				var ox: float = float(L["x"]) * r * 1.45
				var oy: float = float(L["y"]) * r + r * 0.10
				draw_circle(Vector2(x + ox, y + oy), float(L["r"]) * r * sq,
					Color(shade_col.r, shade_col.g, shade_col.b, a * 0.16))
			# 受光顶: 同一组球整体上移 + 左偏 (光从左上打), 半径收一点
			for L in lobes:
				var ox2: float = float(L["x"]) * r * 1.30 - r * 0.10
				var oy2: float = float(L["y"]) * r - r * 0.20
				draw_circle(Vector2(x + ox2, y + oy2), float(L["r"]) * r * sq * 0.72,
					Color(lit_col.r, lit_col.g, lit_col.b, a * 0.13))


# 镜面海: 渐变水体 (36 条横带) + 海平线亮线 + 碎光路径 + 七层浪 (近两层带泡沫线)
# sky_ref 跟着天幕亮度走; spark_x >= 0 时在那一列铺日月倒影
class SeaField:
	extends Control

	var t := 0.0
	var horizon := 0.66
	var deep := Color(0.06, 0.13, 0.24)
	var sky_ref := Color(0.42, 0.48, 0.62)
	var spark_x := -1.0
	var layers: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dy := [0.008, 0.030, 0.060, 0.105, 0.165, 0.245, 0.345]
		var amp := [0.006, 0.009, 0.013, 0.018, 0.022, 0.026, 0.030]
		var ln := [0.34, 0.30, 0.26, 0.23, 0.20, 0.18, 0.16]
		var sp := [0.7, 0.9, 1.2, 1.5, 1.9, 2.2, 2.6]
		var rng := RandomNumberGenerator.new()
		rng.seed = 0x5EA51DE
		for i in 7:
			# 每层一个固定相位 + 频率漂移 + 分段种子 ——
			# ❗七层同频正弦横铺整幅, 叠出来就是一张规则菱形网, 一眼假
			layers.append({
				"dy": dy[i], "amp": amp[i], "len": ln[i], "sp": sp[i], "foam": i >= 5,
				"ph": rng.randf() * TAU,
				"chirp": rng.randf_range(0.30, 0.80),
				"seed": rng.randf() * 91.0})
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
		var bands := 36
		for i in bands:
			var u := float(i) / float(bands - 1)
			var y0 := hz + (h - hz) * float(i) / float(bands)
			var y1 := hz + (h - hz) * float(i + 1) / float(bands) + 1.0
			var col := sky_ref.lerp(deep, pow(u, 0.55))
			draw_rect(Rect2(0.0, y0, w, y1 - y0), col)
		draw_rect(Rect2(0.0, hz - 1.0, w, 1.6),
			Color(sky_ref.r, sky_ref.g, sky_ref.b, 0.55))
		# 碎光路径: 一堆宽窄不一、左右抖动的亮横条, 越远越稀越淡
		if spark_x >= 0.0:
			var sx := spark_x * w
			for i in 18:
				var u2 := float(i) / 17.0
				var y2 := hz + 4.0 + u2 * (h - hz) * 0.75
				var wd := w * (0.014 + u2 * 0.055) * (0.7 + 0.3 * sin(t * 2.1 + u2 * 9.0))
				var jit := sin(t * 1.3 + u2 * 17.0) * w * 0.030 * u2
				draw_rect(Rect2(sx + jit - wd * 0.5, y2, wd, 1.6 + u2 * 1.4),
					Color(1.0, 0.95, 0.80, 0.16 * (1.0 - u2 * 0.75)))
		# 浪脊: 只画细高光线, ❗绝不能「填色到画面底」—— 那样每层都成了一道剪影,
		# 七层叠起来就是一排假山, 而不是海
		# ❗再切成小段、每段一个明暗门 —— 一整根连续的高光线横贯全幅,
		#   七层交叉出来就是一张编织网; 真实的浪脊是一节一节断断续续亮着的
		for L in layers:
			var u3: float = clampf(float(L["dy"]) / 0.345, 0.0, 1.0)
			var lc := deep.lightened(0.14 + u3 * 0.36)
			var base_a := 0.08 + u3 * 0.24
			var seg := 24
			for i in seg:
				var gate: float = 0.20 + 0.80 * absf(sin(float(i) * 1.137 + float(L["seed"])))
				if gate < 0.30:
					continue
				var x0 := w * float(i) / float(seg)
				var x1 := w * float(i + 1) / float(seg)
				var pts := PackedVector2Array()
				for j in 5 + 1:
					var xx: float = lerp(x0, x1, float(j) / 5.0)
					pts.append(Vector2(xx, _wy(xx, hz, h, w, L)))
				draw_polyline(pts, Color(lc.r, lc.g, lc.b, base_a * gate), 1.0 + u3 * 1.5)
				if bool(L["foam"]):
					var fp := PackedVector2Array()
					for j in 5 + 1:
						var xx2: float = lerp(x0, x1, float(j) / 5.0)
						fp.append(Vector2(xx2, _wy(xx2, hz, h, w, L) - 1.2))
					draw_polyline(fp, Color(1.0, 1.0, 1.0,
						(0.05 + 0.035 * sin(t * 1.7 + float(L["dy"]) * 40.0)) * gate), 1.0)

	# 一层浪在 x 处的高度 (两条正弦叠加 + 频率漂移 + 波包调制)
	# ❗单频正弦 = 规则波纹; chirp 让波长沿 x 变化, env 让振幅一段起一段落
	func _wy(x: float, hz: float, h: float, w: float, L: Dictionary) -> float:
		var ph: float = float(L["ph"])
		var k := TAU / (float(L["len"]) * w)
		var kk: float = k * (1.0 + float(L["chirp"]) * 0.45 * sin(x / w * 2.1 + ph * 1.7))
		var env: float = 0.40 + 0.60 * absf(sin(x / w * 3.3 + ph * 2.6))
		return hz + float(L["dy"]) * (h - hz) \
			+ sin(x * kk + t * float(L["sp"]) + ph) * float(L["amp"]) * h * env \
			+ sin(x * kk * 2.7 + t * float(L["sp"]) * 1.7 + ph * 3.1) \
				* float(L["amp"]) * h * 0.30 * env


# 体积光 (丁达尔): 9 条共享顶点的楔形光束, 加色混合; 每条各自摆动 / 呼吸
class GodRays:
	extends Control

	var t := 0.0
	var ox := 0.5
	var rcol := Color(1.0, 0.90, 0.65)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		# 光源在画面外上方: 整个光扇会随 sin 缓慢平移, 像云在飘
		var src := Vector2(ox * w + sin(t * 0.21) * w * 0.03, -h * 0.12)
		var len_ := h * 1.6
		for i in 9:
			var u := float(i) / 8.0
			var ang := deg_to_rad(-90.0 + (u - 0.5) * 46.0)
			var dir := Vector2(cos(ang), sin(ang))
			var nrm := Vector2(-dir.y, dir.x)
			var bw := w * 0.020 * (0.7 + 0.6 * sin(u * 9.1 + 1.7))
			var al := 0.16 + 0.10 * sin(t * 0.6 + u * 7.3)
			draw_colored_polygon(PackedVector2Array([
				src, src + dir * len_ - nrm * bw, src + dir * len_ + nrm * bw]),
				Color(rcol.r, rcol.g, rcol.b, al))


# 日 / 月: 加色冕 + 两层大气圈 + 本体; is_moon 时用「外圆减内圆」的圆弧交点法裁真月牙
# ❗内圆盘不能用布尔运算, 只能算两圆交点再把两段弧拼成一个简单多边形
class Luminary:
	extends Control

	var t := 0.0
	var lpos := Vector2(0.5, 0.2)
	var lcol := Color(1.0, 0.94, 0.78)
	var lr := 90.0
	var is_moon := false
	var _halo: Sprite2D = null
	var _atm: Sprite2D = null
	var _core: Sprite2D = null

	static func _mk_radial(px := 64) -> ImageTexture:
		var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
		var c := float(px) * 0.5
		for y in px:
			for x in px:
				var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		return ImageTexture.create_from_image(img)

	static func _mk_glow(col: Color, a: float) -> Sprite2D:
		var s := Sprite2D.new()
		# ❗大气圈 / 内核一律用「径向贴图 + 加色」画, 绝不能用 draw_circle ——
		#   draw_circle 是硬边, 在夜空上会露出一整圈清晰的圆边, 像贴了个盘子
		s.texture = _mk_radial(96)
		s.modulate = Color(col.r, col.g, col.b, a)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		s.material = m
		return s

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_atm = _mk_glow(lcol, 0.10)
		_halo = _mk_glow(lcol, 0.26)
		_core = _mk_glow(lcol, 0.22)
		for n in [_atm, _halo, _core]:
			add_child(n)
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		if _halo == null:
			return
		var c := Vector2(lpos.x * size.x, lpos.y * size.y)
		var kb := 96.0
		# 月亮要的是「牙亮、暗面干净」, 加色光一重就把月牙的空心洗成一团灰;
		# 太阳反过来, 就是要那圈溢出来的辉光
		var ha := 0.14 if is_moon else 0.34
		var aa := 0.06 if is_moon else 0.11
		_atm.modulate = Color(lcol.r, lcol.g, lcol.b, aa)
		_halo.modulate = Color(lcol.r, lcol.g, lcol.b, ha)
		_atm.position = c
		_atm.scale = Vector2.ONE * (lr * 7.0 / kb) * (1.0 + 0.02 * sin(t * 0.9))
		_halo.position = c
		_halo.scale = Vector2.ONE * (lr * 4.2 / kb) * (1.0 + 0.03 * sin(t * 1.1))
		_core.position = c + Vector2(-lr * 0.20, -lr * 0.20)
		_core.scale = Vector2.ONE * (lr * 1.9 / kb) * (1.0 + 0.03 * sin(t * 1.4))
		_core.visible = not is_moon
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0:
			return
		var c := Vector2(lpos.x * w, lpos.y * h)
		var body := Color(lcol.r, lcol.g, lcol.b, 0.95)
		if not is_moon:
			# 日面: 外两层递减的薄圈 = 临边昏暗, 日轮边缘才是软的 ——
			# 直接 draw_circle 一个实心圆, 看上去就是个贴上去的黄圆盘
			draw_circle(c, lr * 1.10, Color(lcol.r, lcol.g, lcol.b, 0.13))
			draw_circle(c, lr * 1.05, Color(lcol.r, lcol.g, lcol.b, 0.26))
			draw_circle(c, lr, body)
			return
		# 月牙: 外圆 (c, r) 减内圆 (c + (d,0), r1)
		var r := lr
		var d := r * 0.42
		var r1 := r * 0.88
		if d <= absf(r - r1) or d >= r + r1:
			draw_circle(c, r, body)
			return
		var cx := (d * d + r * r - r1 * r1) / (2.0 * d)
		var cy := sqrt(maxf(0.0, r * r - cx * cx))
		var a0 := atan2(cy, cx)
		# 外弧: 沿左侧绕远路 (a0 -> TAU - a0)
		var pts := PackedVector2Array()
		var n := 40
		for i in n + 1:
			var th: float = lerp(a0, TAU - a0, float(i) / float(n))
			pts.append(c + Vector2(cos(th), sin(th)) * r)
		# 内弧: 由下交点回上交点, 必须走「穿过 180 度」那一段 (那段才落在外圆里)
		# ❗两端点跟外弧的首尾是同一个点 —— 不能重复塞进去, 否则多边形有零长边,
		#   Godot 三角化会直接报 Invalid polygon data 然后整块不画
		var pa := atan2(cy, cx - d)
		var pb := atan2(-cy, cx - d)
		if pb < pa:
			pb += TAU
		for i in range(1, n):
			var ph: float = lerp(pb, pa, float(i) / float(n))
			pts.append(c + Vector2(d, 0.0) + Vector2(cos(ph), sin(ph)) * r1)
		draw_colored_polygon(pts, body)


# 径向光晕: 加色混合 + 运行时径向渐变贴图 (两层: 全径 + 内核实)
class GlowOrb:
	extends Control

	var t := 0.0
	var gpos := Vector2(0.5, 0.5)
	var gcolor := Color(1.0, 0.85, 0.55)
	var gradius := 340.0
	var _tex: ImageTexture = null

	static func _mk_radial(px := 64) -> ImageTexture:
		var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
		var c := float(px) * 0.5
		for y in px:
			for x in px:
				var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		return ImageTexture.create_from_image(img)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tex = _mk_radial(64)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0 or _tex == null:
			return
		var c := Vector2(gpos.x * w, gpos.y * h)
		var r: float = gradius * (1.0 + 0.035 * sin(t * 1.3))
		# ❗加色混合下 0.8 会把光心直接怼成纯白一片 (日月叠上来更是炸成一坨),
		#   压到 0.42 / 0.34 才是「光在雾里散开」而不是「贴了个白圆盘」
		draw_texture_rect(_tex, Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false,
			Color(gcolor.r, gcolor.g, gcolor.b, 0.42))
		var r2 := r * 0.45
		draw_texture_rect(_tex, Rect2(c - Vector2(r2, r2), Vector2(r2 * 2.0, r2 * 2.0)), false,
			Color(gcolor.r, gcolor.g, gcolor.b, 0.34))


# 飞鸟: 每只一段三点折线 (两翼 + 身体), 翅膀按 sin 扇动, 出画后从对面回来
class BirdFlock:
	extends Control

	var t := 0.0
	var bs: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		setup(7)
		set_process(true)

	func setup(count: int) -> void:
		bs.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7731
		for i in count:
			bs.append({
				"u0": rng.randf(), "y": rng.randf_range(0.10, 0.34),
				"s": rng.randf_range(3.0, 6.0),
				"v": rng.randf_range(0.030, 0.062),
				"ph": rng.randf() * TAU,
			})

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0 or bs.is_empty():
			return
		var col := Color(0.08, 0.07, 0.10, 0.80)
		for b in bs:
			var x: float = fposmod(float(b["u0"]) + t * float(b["v"]), 1.24) * w - 0.12 * w
			var y: float = float(b["y"]) * h + sin(t * 0.7 + float(b["ph"])) * h * 0.012
			var s: float = float(b["s"])
			var wing: float = sin(t * 7.5 + float(b["ph"]))
			draw_polyline(PackedVector2Array([
				Vector2(x - s, y - wing * s * 0.65), Vector2(x, y),
				Vector2(x + s, y - wing * s * 0.65)]), col, 1.6)


# 一簇火 (篝火 / 火盆 / 烧掉的船): 加色辉光脉冲 + 八条上升火舌 + 四点烟 + 火星
class FireFx:
	extends Node2D

	var t := 0.0
	var sz := 1.0
	var _glow: Sprite2D = null
	var _sp: Array = []

	static func _mk_radial(px := 48) -> ImageTexture:
		var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
		var c := float(px) * 0.5
		for y in px:
			for x in px:
				var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a))
		return ImageTexture.create_from_image(img)

	func _init(s: float = 1.0) -> void:
		sz = s

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3311
		for i in 8:
			_sp.append({
				"p": rng.randf(), "u": rng.randf_range(-0.5, 0.5),
				"s": rng.randf_range(0.6, 1.4),
			})
		_glow = Sprite2D.new()
		_glow.texture = _mk_radial(48)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = m
		_glow.position = Vector2(0.0, -8.0 * sz)
		_glow.modulate = Color(1.0, 0.62, 0.24, 0.50)
		add_child(_glow)
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		if _glow != null:
			_glow.scale = Vector2.ONE * (26.0 * sz / 48.0) * (1.0 + 0.12 * sin(t * 9.0))
		queue_redraw()

	func _draw() -> void:
		# 烟: 先画, 让火舌盖在它上面
		for i in 4:
			var u2: float = fposmod(t * 0.22 + float(i) * 0.25, 1.0)
			draw_circle(Vector2(sin(t * 0.9 + float(i)) * 6.0 * sz, -30.0 * sz - u2 * 40.0 * sz),
				(5.0 + u2 * 9.0) * sz, Color(0.22, 0.20, 0.20, (1.0 - u2) * 0.16))
		for p in _sp:
			var u: float = fposmod(float(p["p"]) + t * 0.55 * float(p["s"]), 1.0)
			var fx: float = float(p["u"]) * 14.0 * sz * (1.0 - u * 0.6)
			var fy: float = -u * 34.0 * sz
			var col := Color(1.0, 0.72, 0.22).lerp(Color(1.0, 0.25, 0.06), u)
			draw_circle(Vector2(fx, fy), (4.0 - u * 2.6) * sz, Color(col.r, col.g, col.b, (1.0 - u) * 0.85))


# 分层雾: 6 条高度不同的横向雾带, 每条由 5 个压扁 (y 轴 0.32) 的圆慢慢横移
class FogLayer:
	extends Control

	var t := 0.0
	var bands: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 5511
		for i in 6:
			bands.append({
				"y": 0.45 + 0.10 * float(i) + rng.randf_range(-0.02, 0.02),
				"sp": rng.randf_range(6.0, 18.0),
				"a": rng.randf_range(0.030, 0.060),
				"p": rng.randf() * TAU,
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
		for b in bands:
			var y: float = float(b["y"]) * h
			for k in 5:
				var u := float(k) / 4.0
				var x := fposmod(u * w + t * float(b["sp"]) + float(b["p"]) * 60.0, w + 520.0) - 260.0
				draw_set_transform(Vector2(x, y), 0.0, Vector2(1.0, 0.32))
				draw_circle(Vector2.ZERO, w * 0.16 * (0.7 + 0.3 * sin(t * 0.4 + u * 3.0)),
					Color(0.82, 0.85, 0.90, float(b["a"])))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 布料模拟旗面: 每帧重算顶点。振幅随离杆距离 u 增长 —— 杆边钉死, 旗尾甩得最欢。
# ❗用轮廓法 (上缘左->右 + 下缘右->左) 而不是网格顶点: 网格索引成蛇形序会让多边形自交,
#   Godot 三角化直接失败 (整面旗消失)。轮廓法永远是个简单多边形。
class WavingCloth:
	extends Polygon2D

	var cw := 40.0
	var ch := 24.0
	var t := 0.0
	var sway := 1.0

	func _init(w: float = 40.0, h: float = 24.0, col: Color = Color(0.80, 0.30, 0.25)) -> void:
		cw = w
		ch = h
		color = col

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		var pts := PackedVector2Array()
		var n := 9
		for i in n + 1:
			pts.append(_pt(float(i) / float(n), 0.0))
		for i in n + 1:
			pts.append(_pt(1.0 - float(i) / float(n), 1.0))
		polygon = pts

	func _pt(u: float, v: float) -> Vector2:
		var amp := u * ch * 0.30 * sway
		var ph := t * 2.6 - u * 4.2
		var bend := sin(ph) * amp + sin(t * 1.1 - u * 2.3) * amp * 0.35
		var wobble := sin(t * 1.7 - u * 3.1) * amp * 0.25
		# 旗面前缘会因为受风而轻微内收 —— 加这一项, 摆动才不像一块布帘子在平移
		var x := u * cw * (1.0 - 0.05 * u * absf(sin(ph)))
		return Vector2(x, v * ch + bend + wobble)


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
