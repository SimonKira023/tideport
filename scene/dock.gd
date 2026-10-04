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

var anchor := Vector2i.ZERO    # 码头根部所在的陆地格

var _spr: Sprite2D = null
var _hint: Label = null
var _boats: Node2D = null
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

	Voyage.dock_changed.connect(_refresh)
	_refresh()

# ---------------- 状态刷新 ----------------
func _refresh() -> void:
	if _spr == null:
		return
	_spr.texture = _tex_for(Voyage.dock_state)
	for c in _boats.get_children():
		c.queue_free()
	for i in Voyage.boat_count:
		var s := Sprite2D.new()
		s.texture = BOAT_HULL_TEX
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = _boat_slot(i)
		_boats.add_child(s)
	if _hint != null:
		_hint.text = hint_text()

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
