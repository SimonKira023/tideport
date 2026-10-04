# terrain_map.gd —— 一张「会动的地形图」
#
# 它按真实地形（game._land_set / _water_set / Farm.tilled / Farm.crops）实时画出来：
#   深蓝 = 水、橄榄绿 = 草地、棕 = 耕地、黄绿 = 已播种、深灰 = 地图外。
# 玩家和伙伴的位置会画成小点，所以白天开 Esc 看地图能看见人在哪儿。
#
# 交互：
#   · 滚轮 = 放缩（以视野中心为锚点，不会跳来跳去）
#   · 左键 / 中键拖拽 = 平移视角
#
# ❗底图是「1 格 = 1 像素」的图 + NEAREST 放大画出来的，不是逐格 draw_rect ——
#   整座岛有好几千格，每帧画几千个矩形没必要。
# ❗这个控件本身**不带滚动条**：靠 view_center（视野中心，格子坐标）+ 拖拽来移动视角，
#   超出自己矩形范围的部分靠 clip_contents 裁掉。
extends Control

const TILE_DEFAULT := 6
const TILE_MIN := 2
const TILE_MAX := 40
const ZOOM_MIN := 0.5          # 相对「刚好铺满」的倍率
const ZOOM_MAX := 8.0
const ZOOM_STEP := 1.25        # 滚一格放大/缩小多少
const DRAG_DEAD := 3.0         # 拖动超过这么多像素才算「在拖」，不然算点击

# 地形配色：四种地彼此要分得开，也要跟任务色（浇水是亮青蓝）分得开
const COL_OUTSIDE := Color(0.11, 0.11, 0.14)
const COL_WATER := Color(0.13, 0.28, 0.42)
const COL_SOIL := Color(0.55, 0.34, 0.24)
const COL_SEEDED := Color(0.66, 0.82, 0.24)
const COL_GRASS := Color(0.34, 0.52, 0.28)
const COL_PLAYER := Color(1.00, 0.86, 0.32)
const COL_SLAVE := Color(0.40, 0.92, 1.00)

var game: Node = null
var map_from := Vector2i.ZERO
var map_to := Vector2i.ZERO

var tile := TILE_DEFAULT       # 当前一格多少像素
var zoom := 1.0                # 1.0 = 刚好铺满
var view_center := Vector2.ZERO   # 视野中心（格子坐标，可以是小数）
var show_actors := false          # 画不画玩家 / 伙伴的小点
var pan_enabled := true           # 能不能拖着移动视角
var auto_fit := false             # true = 格子边长跟着自己的实际尺寸走（铺满可用区域）

var _base: ImageTexture = null
var _fit_box := Vector2.ZERO
var _base_tile := float(TILE_DEFAULT)
var _drag_btn := -1
var _drag_last := Vector2.ZERO
var _dragged := false

# ---------------- 初始化 ----------------
func setup(g: Node, from: Vector2i, to: Vector2i, fit_box := Vector2.ZERO) -> void:
	game = g
	map_from = from
	map_to = to
	_fit_box = fit_box
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 放大了也要是硬边像素
	if _fit_box != Vector2.ZERO:
		custom_minimum_size = _fit_box
	_fit_tile()
	view_center = Vector2(float(map_from.x + map_to.x) * 0.5,
		float(map_from.y + map_to.y) * 0.5)
	_build_base()
	set_process(true)

func _resized() -> void:
	# 尺寸变了（面板被撑大 / 窗口改大小）就按新尺寸重算「铺满」的格子边长
	if auto_fit and size.x > 8.0 and size.y > 8.0:
		_fit_box = size
		_fit_tile()

func _map_cells() -> Vector2:
	return Vector2(map_to.x - map_from.x + 1, map_to.y - map_from.y + 1)

func map_size_px() -> Vector2:
	return _map_cells() * float(tile)

# ---------------- 缩放 / 平移 ----------------
# 「刚好铺满」的格子边长：按可用区域算。算不出来（还没布局 / headless）就退回 6 像素。
func _fit_tile() -> void:
	var c := _map_cells()
	_base_tile = float(TILE_DEFAULT)
	if _fit_box.x > 8.0 and _fit_box.y > 8.0 and c.x > 0.0 and c.y > 0.0:
		_base_tile = clampf(minf(_fit_box.x / c.x, _fit_box.y / c.y),
			float(TILE_MIN), float(TILE_MAX))
	_apply_zoom()

func _apply_zoom() -> void:
	tile = clampi(int(round(_base_tile * zoom)), TILE_MIN, TILE_MAX)
	_clamp_view()
	queue_redraw()

# 滚轮：以视野中心为锚点放缩（view_center 不动，所以画面不会跳）
func zoom_by(steps: int) -> void:
	var z: float = zoom
	if steps > 0:
		z *= ZOOM_STEP
	else:
		z /= ZOOM_STEP
	zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_apply_zoom()

# 回到「整张图铺满 + 居中」的初始视角（面板上的「重新绘制」）
func reset_view() -> void:
	zoom = 1.0
	view_center = Vector2(float(map_from.x + map_to.x) * 0.5,
		float(map_from.y + map_to.y) * 0.5)
	_apply_zoom()

# 拖了多少像素 -> 视野中心跟着挪多少格
func pan_by(delta_px: Vector2) -> void:
	view_center -= delta_px / float(tile)
	_clamp_view()
	queue_redraw()

# 别让视角飘到地图外面找不着北
func _clamp_view() -> void:
	view_center.x = clampf(view_center.x, float(map_from.x) - 2.0, float(map_to.x) + 2.0)
	view_center.y = clampf(view_center.y, float(map_from.y) - 2.0, float(map_to.y) + 2.0)

# 底图左上角画在控件的哪个位置（像素）
func _draw_origin() -> Vector2:
	return Vector2(size.x * 0.5 - (view_center.x - float(map_from.x)) * float(tile),
		size.y * 0.5 - (view_center.y - float(map_from.y)) * float(tile))

# ---------------- 底图 ----------------
func _build_base() -> void:
	var w: int = map_to.x - map_from.x + 1
	var h: int = map_to.y - map_from.y + 1
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := Vector2i(map_from.x + x, map_from.y + y)
			var col: Color = COL_OUTSIDE
			if game != null and game.has_method("is_water") and game.is_water(c):
				col = COL_WATER
			elif Farm.crops.has(c):
				col = COL_SEEDED          # 地里已经有苗了
			elif Farm.tilled.has(c):
				col = COL_SOIL            # 耕过但还空着
			elif game != null and game._land_set.has(c):
				col = COL_GRASS
			img.set_pixel(x, y, col)
	_base = ImageTexture.create_from_image(img)
	queue_redraw()

# 面板每次打开都调一次：地形（新锄的地 / 刚播的种）会变，底图得跟着重画
func refresh(fit_box := Vector2.ZERO) -> void:
	if auto_fit and size.x > 8.0 and size.y > 8.0:
		_fit_box = size
	elif fit_box != Vector2.ZERO:
		_fit_box = fit_box
		custom_minimum_size = fit_box
	_fit_tile()
	_build_base()

# ---------------- 格子换算 ----------------
func cell_at(local_pos: Vector2) -> Vector2i:
	var p := local_pos - _draw_origin()
	return Vector2i(map_from.x + int(floor(p.x / float(tile))),
		map_from.y + int(floor(p.y / float(tile))))

func _in_rect(c: Vector2i) -> bool:
	return c.x >= map_from.x and c.x <= map_to.x and c.y >= map_from.y and c.y <= map_to.y

# ---------------- 画 ----------------
func _draw() -> void:
	var o := _draw_origin()
	if _base != null:
		draw_texture_rect(_base, Rect2(o, map_size_px()), false)
		draw_rect(Rect2(o, map_size_px()), Color(0, 0, 0, 0.55), false, 1.0)
	if show_actors:
		_draw_actors(o)

# 玩家 / 伙伴的小点。格子坐标 -> 控件内的像素。
func _draw_actors(o: Vector2) -> void:
	if game == null:
		return
	var p := _actor_cell("player")
	if p != null:
		_dot(o, p, COL_PLAYER, 3.0)
	var slaves: Array = game.get("slave_nodes")
	if slaves != null:
		for n in slaves:
			if n == null or not is_instance_valid(n):
				continue
			_dot(o, world_to_cell(n.global_position), COL_SLAVE, 2.0)

func _actor_cell(group: String) -> Vector2i:
	var n: Node2D = get_tree().get_first_node_in_group(group) as Node2D
	if n == null:
		return Vector2i(0x7fffffff, 0x7fffffff)
	return world_to_cell(n.global_position)

# ❗世界坐标 -> 格子：必须走 Farm.grid_origin，别硬编码偏移
func world_to_cell(pos: Vector2) -> Vector2i:
	var local := pos - Farm.grid_origin
	return Vector2i(int(floor(local.x / float(Farm.TILE_SIZE))),
		int(floor(local.y / float(Farm.TILE_SIZE))))

func _dot(o: Vector2, c: Vector2i, col: Color, r: float) -> void:
	if not _in_rect(c):
		return
	var p := o + (Vector2(c) - Vector2(map_from)) * float(tile) + Vector2(tile, tile) * 0.5
	draw_circle(p, maxf(r, tile * 0.35), col)
	draw_arc(p, maxf(r, tile * 0.35) + 1.0, 0.0, TAU, 12, Color(0, 0, 0, 0.8), 1.0, true)

func _process(_delta: float) -> void:
	# 开了「显示人物」就要每帧重画，小点才会跟着人走
	if show_actors and is_visible_in_tree():
		queue_redraw()

# ---------------- 输入：滚轮放缩 + 拖拽平移 ----------------
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				zoom_by(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			accept_event()
			return
		if mb.pressed and pan_enabled \
				and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE):
			_drag_btn = mb.button_index
			_drag_last = mb.position
			_dragged = false
			accept_event()
			return
		if not mb.pressed and mb.button_index == _drag_btn:
			_drag_btn = -1
			accept_event()
			return
	var mm := event as InputEventMouseMotion
	if mm != null and _drag_btn >= 0:
		var d := mm.position - _drag_last
		_drag_last = mm.position
		if d.length() > DRAG_DEAD:
			_dragged = true
		pan_by(d)
		accept_event()
