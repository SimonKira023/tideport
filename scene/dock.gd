# scene/dock.gd —— 东岸外海那座**废弃码头**
#
# 出海的唯一入口（ESC 制作台不再造船）：
#   废墟 --(付钱+材料动工)--> 待施工 --(派活面板派人, 攒够人天)--> 建成
#   建成后在这儿造船（一船两人），船造好就固定停在码头；走到码头按 F 开面板出海。
#
# 位置：由 game.gd 在地形生成后挑好（东岸最靠东、东边就是水的那格陆地），
#   码头本体（这个节点）站在那格上，栈桥往东伸进水里。
#
# 美术是**程序化画的像素图**（跟 world_map 的树、battle_map 的水一样），
#   不依赖外部素材，放大后也不会糊。
extends Node2D

const FONT_PIX := preload("res://resources/font/IPix.ttf")
# ❗停泊的船用「只画船身」那张（e40：带帆那张 32x44 是大地图船队专用的）。
#   泊位行距只有 15px，挂帆的话后排的帆会盖住前排的船；而且停着=收帆，设定上也自洽。
const BOAT_HULL_TEX := preload("res://resources/texture/boat_hull.png")

const IMG_W := 64          # 码头贴图：4 格宽 x 3 格高（16px 一格）
const IMG_H := 48
const REACH := 60.0        # 站多近才能按 F 交互（像素）

# ---------------- 2026-10-06 夜里栈桥灯（视觉提升 B：发光体铺量） ----------------
# 基线探针拍出来的现状是「岛上夜里一片死蓝, 一点暖光都没有」。栈桥上这盏灯是最便宜、
# 最不违和的一个锚点：港口本来就该有灯。海灯的色温是约定俗成的暖琥珀 —— 不管后面
# 主色调走「暖橘渔村」还是「冷青 + 暖点撞色」, 这盏都成立, 所以先做它、不赌风格。
const LAMP_POS := Vector2(36.0, 2.0)   # 灯座落在栈桥桥面西段（相对本节点坐标）
const LAMP_W := 9
const LAMP_H := 24
const LAMP_ENERGY := 0.85      # 2026-10-06 从 0.95 收到 0.85：泛光推强后 0.95 会把灯芯顶到近白
# 灯头那圈可见柔光的基准透明度。❗跟 lamp_node 同一约定：_process 的抖动要**围绕**它呼吸，
# 不能写成 `_lamp_glow.modulate.a = f`（f≈1.0 会把基准顶成满不透明 → 加法混合下一坨死黄）。
const LAMP_GLOW_ALPHA := 0.19   # e90: HDR 2D 后 0.30 会被 bloom 放大成黄团, 收一档
# 点灯/熄灯的时刻不在这里写死 —— 统一走 light_util.glow_hour_now() 一个总闸
# （读 time_manager.gd 的 TONE_ADVANCE, 全岛所有夜灯共用一个时辰）。

var _lamp: Sprite2D = null          # 栈桥灯（只在码头建成后出现）
var _lamp_light: PointLight2D = null
var _lamp_glow: Sprite2D = null
var _boat_glows: Array = []         # 2026-10-06 船舷灯：每艘泊船船头一点暖光（只加法柔光）
var _lamp_lit := false
var _flick_t := 0.0                 # 灯焰抖动时钟（点亮那刻随机相位）

var anchor := Vector2i.ZERO    # 码头根部所在的陆地格

var _spr: Sprite2D = null
var _hint: Label = null
var _boats: Node2D = null
var _trade_ship: Sprite2D = null
var _ruin_tex: ImageTexture = null
var _built_tex: ImageTexture = null

# game.gd 在 _build_terrain() 之后调用（那时候才知道哪格是陆地）
# ❗必须写 global_position，不能写 position：
#   `Farm.grid_origin` 取的是 GrassTileMapLayer 的**全局**位置（已经含了 Game 自己的偏移），
#   而本节点是 Game 的子节点。写 position 会把 Game 的偏移叠第二次 —— 码头就会
#   被推到东边十几格外的海面上（这个坑踩过一次）。
func setup(cell: Vector2i) -> void:
	anchor = cell
	global_position = Farm.grid_origin + Vector2(
		float(cell.x) * Farm.TILE_SIZE + 8.0,
		float(cell.y) * Farm.TILE_SIZE + 8.0)
	y_sort_enabled = true      # 船在栈桥南边时盖住栈桥，看着像停在水上
	z_index = -3               # 水面(-6)/浅滩(-5)/桥(-4) 之上，角色(0) 之下

	_spr = Sprite2D.new()
	_spr.position = Vector2(24, 4)     # 栈桥从脚下往东伸，图心得往东挪
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_spr)

	_boats = Node2D.new()
	_boats.name = "Boats"
	_boats.y_sort_enabled = true
	add_child(_boats)
	_trade_ship = Sprite2D.new()
	_trade_ship.name = "TradeVisitor"
	_trade_ship.texture = BOAT_HULL_TEX
	_trade_ship.modulate = Color(0.75, 0.85, 1.0)
	_trade_ship.position = Vector2(Farm.TILE_SIZE * 4, Farm.TILE_SIZE * 3)
	add_child(_trade_ship)
	Structures.station_changed.connect(func(_c: Vector2i): _refresh_trade_visitor())
	Structures.station_removed.connect(func(_c: Vector2i): _refresh_trade_visitor())

	_hint = Label.new()
	_hint.add_theme_font_override("font", FONT_PIX)
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_hint.add_theme_constant_override("outline_size", 3)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.position = Vector2(-30, -34)
	# ❗z_index 是**相对父节点**累加的：本节点是 -3，这行提示要盖过岸上的树和人，
	#   所以给 +6（净层级 3 > 实体的 0）。不写就会「码头提示被树挡住」。
	_hint.z_index = 6
	add_child(_hint)

	# 栈桥灯：建成后才亮（_refresh / _sync_lamp 按状态切）。天黑点、天亮灭。
	# ❗用 offset 把「节点原点」留在灯座底、而不是图的左上角 —— 本节点开了 y_sort,
	#   排序用的是节点原点；原点在头顶的话这盏灯会被整个排到栈桥后面去。
	_lamp = Sprite2D.new()
	_lamp.centered = false
	_lamp.offset = Vector2(-LAMP_W / 2.0, -LAMP_H)   # 原点 = 灯座底中点
	_lamp.position = LAMP_POS
	_lamp.texture = _make_lamp()
	_lamp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lamp.visible = false
	add_child(_lamp)

	_lamp_light = preload("res://scene/light_util.gd").make_light(
		Color(1.0, 0.78, 0.46), LAMP_ENERGY, 1.3, 2.0)
	_lamp_light.position = LAMP_POS + Vector2(0, -19)   # 光心抬到灯头
	_lamp_light.enabled = false
	add_child(_lamp_light)

	_lamp_glow = preload("res://scene/light_util.gd").make_glow(
		Color(1.0, 0.80, 0.50, LAMP_GLOW_ALPHA), 1.3, 1.9)
	_lamp_glow.position = _lamp_light.position
	_lamp_glow.visible = false
	add_child(_lamp_glow)

	Voyage.dock_changed.connect(_refresh)
	_refresh()

# ---------------- 状态刷新 ----------------
func _refresh() -> void:
	if _spr == null:
		return
	_spr.texture = _tex_for(Voyage.dock_state)
	for c in _boats.get_children():
		c.queue_free()
	_boat_glows.clear()
	var lu := preload("res://scene/light_util.gd")
	for i in Voyage.boat_count:
		var s := Sprite2D.new()
		s.texture = BOAT_HULL_TEX
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = _boat_slot(i)
		_boats.add_child(s)
		# 2026-10-06 船舷灯：船头挑一盏小灯。❗只给加法柔光、不给 PointLight2D ——
		#   泊位一多就是十几艘, 每艘架真灯会把「同屏 8~12 盏」的灯池直接撑爆;
		#   而夜里远看这一排小暖点, 靠后处理 bloom 晕开就已经很像渔港了。
		var g := lu.make_glow(Color(1.0, 0.72, 0.38), 0.52, 2.1)
		g.position = s.position + Vector2(5.0, -8.0)    # 船头（东侧）桅下
		g.visible = false
		_boats.add_child(g)
		_boat_glows.append(g)
	if _hint != null:
		_hint.text = hint_text()
	_sync_lamp(true)          # 建成/拆掉之后重新对一次灯（废墟状态不点灯）
	_refresh_trade_visitor()

func _refresh_trade_visitor() -> void:
	if _trade_ship != null:
		_trade_ship.visible = Voyage.dock_state == Voyage.DOCK_BUILT and Structures.can_sea_trade()

# 天黑点灯 / 天亮熄灯，并且只在码头建成后才亮（废墟/施工中栈桥还没木面）。
# force=true 时立刻切（刚建成/刚刷新那一下用）。
func _sync_lamp(force: bool) -> void:
	if _lamp == null:
		return
	var built := Voyage.dock_state >= Voyage.DOCK_BUILT
	_lamp.visible = built
	# 天黑该点灯了问 light_util 一个总闸（读 TONE_ADVANCE, 别在这写死提前量）
	var want: bool = built and preload("res://scene/light_util.gd").glow_hour_now()
	if want == _lamp_lit and not force:
		return
	_lamp_lit = want
	if _lamp_light != null:
		_lamp_light.enabled = want
		if want:
			_flick_t = randf() * 10.0
	if _lamp_glow != null:
		_lamp_glow.visible = want
	# 船舷灯跟栈桥灯同一刻亮/灭（一道亮着、一道黑着会很怪）
	for g in _boat_glows:
		if is_instance_valid(g):
			(g as Sprite2D).visible = want

# 每帧问一次天色（只在跨过 18:30 / 6:30 那一瞬间真的切，平时一句话就返回）
func _process(delta: float) -> void:
	if _lamp == null:
		return
	_sync_lamp(false)
	# 灯焰抖动（照搬 lamp_node 的做法）：两个不可通约的正弦叠出无规律的小幅呼吸
	if _lamp_lit and _lamp_light != null:
		_flick_t += delta
		var f := 1.0 + 0.05 * sin(_flick_t * 6.7) + 0.03 * sin(_flick_t * 11.9 + 2.3)
		_lamp_light.energy = LAMP_ENERGY * f
		if _lamp_glow != null:
			_lamp_glow.modulate.a = LAMP_GLOW_ALPHA * f   # 围绕基准呼吸, 别顶满（过曝）

# 栈桥灯：程序化画的像素小灯（不依赖素材，跟码头本体同一套画法）
func _make_lamp() -> ImageTexture:
	var img := Image.create_empty(LAMP_W, LAMP_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.32, 0.23, 0.15)
	var wood_l := Color(0.46, 0.35, 0.23)
	var iron := Color(0.26, 0.24, 0.24)
	var glass := Color(1.0, 0.80, 0.46)
	var core := Color(1.0, 0.96, 0.80)
	# 灯柱（中偏左）+ 迎光面
	for y in range(9, LAMP_H):
		img.set_pixel(4, y, wood)
		img.set_pixel(5, y, wood_l)
	# 底座
	for x in range(3, 7):
		img.set_pixel(x, LAMP_H - 1, wood)
	# 灯头：铁框 + 暖玻璃
	for y in range(1, 9):
		for x in range(1, 8):
			img.set_pixel(x, y, iron)
	for y in range(3, 8):
		for x in range(2, 7):
			img.set_pixel(x, y, glass)
	# 亮芯
	img.set_pixel(4, 5, core)
	img.set_pixel(4, 6, core)
	img.set_pixel(5, 5, core)
	# 顶盖
	for x in range(0, 9):
		img.set_pixel(x, 0, wood_l)
	img.set_pixel(4, 0, wood)
	return ImageTexture.create_from_image(img)

# 船停哪儿：栈桥南侧的水面，一排 3 条，多了往南再排一排
func _boat_slot(i: int) -> Vector2:
	return Vector2(14.0 + float(i % 3) * 26.0, 28.0 + float(i / 3) * 15.0)

# 出发船队的泊位（跟停泊船同款点位，全局坐标）—— game.gd 出海动画用
func boat_slot_global(i: int) -> Vector2:
	return global_position + _boat_slot(i)

# 出发动画期间把停着的船藏起来 / 结束后放回来：
# 出海的正是这些船，动画里由 game.gd 另画一份会动的
func set_parked_boats_visible(v: bool) -> void:
	if _boats != null:
		_boats.visible = v

# 码头头顶那行提示（也用在交互距离外的说明里）
func hint_text() -> String:
	match Voyage.dock_state:
		Voyage.DOCK_FUNDED:
			return "修码头 %d/%d (F)" % [Voyage.dock_work, Voyage.DOCK_WORK]
		Voyage.DOCK_BUILT:
			if Voyage.boat_count <= 0:
				return "码头 - 还没船 (F)"
			return "码头 - 船 %d 艘 (F)" % Voyage.boat_count
		_:
			return "废弃码头 (F)"

# 玩家站得够不够近（game.gd 按 F 时先问这个）
func in_reach(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= REACH

func _tex_for(state: int) -> ImageTexture:
	if state >= Voyage.DOCK_BUILT:
		if _built_tex == null:
			_built_tex = _make_built()
		return _built_tex
	if _ruin_tex == null:
		_ruin_tex = _make_ruin()
	return _ruin_tex

# ---------------- 程序化像素图 ----------------
func _new_img() -> Image:
	var img := Image.create_empty(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _p(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < IMG_W and y >= 0 and y < IMG_H:
		img.set_pixel(x, y, c)

func _r(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_p(img, x, y, c)

# —— 废墟：几根烂木桩 + 一条断掉的横梁，桩上挂着海草 ——
func _make_ruin() -> ImageTexture:
	var img := _new_img()
	var wood := Color(0.34, 0.26, 0.19)
	var wood_d := Color(0.23, 0.18, 0.14)
	var moss := Color(0.28, 0.40, 0.30)
	# 四根高低不齐的桩（top = 桩顶 y，从画布顶往下量）
	var piles := [[8, 24], [20, 15], [34, 27], [48, 19]]
	for p in piles:
		var px: int = int(p[0])
		var top: int = int(p[1])
		_r(img, px, top, px + 3, 41, wood)
		# 迎光面亮一点，另一侧压暗 —— 柱子才有体积
		_r(img, px, top, px, 41, Color(0.42, 0.33, 0.24))
		_r(img, px + 3, top, px + 3, 41, wood_d)
		# 桩顶削个斜角，看着像断的
		_p(img, px + 2, top - 1, wood)
		_p(img, px + 3, top - 1, wood_d)
		# 桩上挂几撮海草
		if px % 2 == 0:
			_p(img, px + 1, top + 5, moss)
			_p(img, px, top + 6, moss)
		_p(img, px + 2, top + 12, moss)
	# 一条断掉的横梁：搭在 1、2 号桩之间，中间缺一段
	_r(img, 10, 20, 26, 24, wood)
	_r(img, 10, 20, 26, 20, Color(0.42, 0.33, 0.24))
	_r(img, 30, 22, 38, 26, wood)
	_r(img, 30, 22, 38, 22, Color(0.42, 0.33, 0.24))
	# 水面压几星白沫就收手 —— 别再垫整宽的半透明深色带，
	# 那条带远看就是「贴图底下多了一根灰条」（用户点名删掉的东西）
	for k in 3:
		var yy := 41 + k
		for x in range(0, IMG_W, 6):
			_p(img, x + k * 2, yy, Color(0.55, 0.78, 0.92, 0.45))
	return ImageTexture.create_from_image(img)

# —— 建成：整齐的木栈桥 + 立柱 + 系缆桩和缆绳 ——
func _make_built() -> ImageTexture:
	var img := _new_img()
	var plank_a := Color(0.58, 0.43, 0.27)
	var plank_b := Color(0.48, 0.35, 0.22)
	var beam := Color(0.38, 0.27, 0.17)
	var beam_d := Color(0.28, 0.20, 0.13)
	# 桥面：横向木板（每 5px 一条，深浅交替）
	for y in range(18, 32):
		var c := plank_a if ((y - 18) / 5) % 2 == 0 else plank_b
		_r(img, 0, y, 57, y, c)
	# 木板缝：一道暗线
	for k in range(1, 3):
		var y := 18 + k * 5 - 1
		_r(img, 0, y, 57, y, beam_d)
	# 钉子：每条板两端一个小暗点
	for y in range(18, 32, 5):
		_p(img, 3, y + 1, Color(0.30, 0.24, 0.18))
		_p(img, 54, y + 1, Color(0.30, 0.24, 0.18))
	# 桥沿：上下各一条横梁，码头才有边
	_r(img, 0, 16, 58, 17, beam)
	_r(img, 0, 32, 58, 33, beam)
	# 立柱：三根，从桥面直插水里
	for px in [5, 26, 47]:
		_r(img, px, 33, px + 4, 45, beam)
		_r(img, px, 33, px, 45, Color(0.46, 0.33, 0.21))
		_r(img, px + 4, 33, px + 4, 45, beam_d)
	# 系缆桩：东端一根粗的，顶上磨得发亮
	_r(img, 51, 10, 56, 22, beam)
	_r(img, 51, 10, 51, 22, Color(0.50, 0.36, 0.23))
	_r(img, 56, 10, 56, 22, beam_d)
	_r(img, 51, 9, 56, 9, Color(0.62, 0.46, 0.30))
	# 缆绳：从桩顶斜拉到桥面
	var rope := Color(0.70, 0.62, 0.44)
	for k in 12:
		_p(img, 50 - k, 12 + int(float(k) * 0.35), rope)
	# 水面点几星波光就收手 —— 之前这里还压了一条整宽的半透明深色带，
	# 远看就是码头贴图底下垫了根灰条（用户点名删掉的东西）
	for k in 2:
		for x in range(k * 3, IMG_W, 7):
			_p(img, x, 45, Color(0.55, 0.78, 0.92, 0.40))
	return ImageTexture.create_from_image(img)
