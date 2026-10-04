extends Node2D
# 水面波光 v2（water_glint）：洒在深水上的横向长条碎光，代替上一版被撤掉的粼光。
# 每条碎光是一根 1px 高、5~9px 宽的横向光条，两端透明、中心亮 —— 像日/月光
# 在水面上拉出的细碎反光条。昼间镀暖金，夜里换成冷月光白、更多更亮（Eastward 夜水感）。
# 只挑「四面全水」的深水格：岸边那条呼吸白浪归 waves_layer 管，两者地盘互斥。
# 加法混合（CanvasItemMaterial ADD）+ 顶点色渐变 polygon，纯 _draw 不依赖任何素材。

var _game: Node2D = null
var _glints: Array = []      # [{p, w, ph, sp, dr, sub}]，setup 一次造齐
var _t := 0.0
var _acc := 0.0              # 重绘限帧累加器

const MAX_GLINTS := 110      # 全图碎光条数上限（全部深水格按 hash 排序挑出）
const REDRAW_DT := 0.05      # 20fps：慢呼吸动画足够顺，省下全量重画

const DAY_COL := Color(1.0, 0.90, 0.58)    # 白天：太阳碎金
const NIGHT_COL := Color(0.72, 0.85, 1.0)  # 夜里：冷月光白

func setup(g: Node2D) -> void:
	_game = g
	z_index = g.Z_SHORE      # 与白浪同层；本节点排在 waves 之后 add_child，同层后画
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD   # 加法混合：光条只加亮、不吃底
	material = mat
	_build()

# ❗候选表要在 setup 里建：_build_waves 先 add_child 再 setup，
#   _ready 执行时 _game 还是 null（跟 waves_layer 同一个坑）。
func _build() -> void:
	_glints.clear()
	# 主岛叫 _water_set, 海图(world_map)叫 _water —— 哪个在用取哪个
	var wset: Dictionary = _game._water_set if "_water_set" in _game else _game._water
	var pool: Array = []     # [{k:排序键, ...参数}]，超出上限时按 k 挑前 MAX_GLINTS 条
	for c in wset.keys():
		if _game._edge_mask(c, true) != 0:
			continue         # 贴岸的格子交给白浪层，这里只要深水
		var h1: int = _game._hash2(c * 91 + Vector2i(7, 3))
		var h2: int = _game._hash2(c * 53 + Vector2i(11, 29))
		var h3: int = _game._hash2(c * 17 + Vector2i(43, 5))
		pool.append({
			"k": h1 ^ (h2 << 7),
			"p": Vector2(c.x * 16 + 2.0 + float(h1 % 9),       # 格内偏移 x 2..10，不贴格边
					c.y * 16 + 3.0 + float(h2 % 11)),          # 格内偏移 y 3..13
			"w": float(5 + 2 * (h3 % 3)),                      # 条宽 5/7/9px
			"ph": float(h2 % 628) / 100.0,                     # 呼吸相位
			"sp": 0.9 + float(h3 % 100) / 100.0,               # 呼吸速度 0.9..1.9
			"dr": float(h1 % 628) / 100.0,                     # 慢漂相位
			"sub": -2.0 if (h3 % 2 == 0) else 3.0,             # 副条在主条上/下方
		})
	if pool.size() > MAX_GLINTS:
		pool.sort_custom(func(a, b): return a["k"] < b["k"])
		pool.resize(MAX_GLINTS)
	_glints = pool
	set_process(not _glints.is_empty())

func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc < REDRAW_DT:
		return
	_acc = 0.0
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	if _game == null:
		return
	var night: float = _game._post_night
	var col: Color = DAY_COL.lerp(NIGHT_COL, night)
	var amp: float = 0.30 + 0.42 * night          # 亮度幅：夜里更亮更抓眼
	var cam := get_viewport().get_camera_2d()
	var vis := Rect2()
	if cam != null:
		var half: Vector2 = get_viewport_rect().size * 0.5 / cam.zoom + Vector2(24, 24)
		vis = Rect2(cam.get_screen_center_position() - half, half * 2.0)
	for g in _glints:
		var p: Vector2 = g["p"]
		if cam != null and not vis.has_point(p):
			continue
		var b: float = maxf(0.0, sin(_t * float(g["sp"]) + float(g["ph"])))
		if b <= 0.02:
			continue                              # 熄着的不画
		var a: float = amp * b
		var dx: float = sin(_t * 0.22 + float(g["dr"])) * 2.6   # 慢漂：随水纹左右轻晃
		var w: float = float(g["w"])
		var c: Color = col
		c.a = a
		_bar(p + Vector2(dx, 0.0), w, c)          # 主条
		var c2: Color = col
		c2.a = a * 0.45                           # 副条：更淡的"回声"
		_bar(p + Vector2(dx * 0.7 + 1.0, float(g["sub"])), w * 0.6, c2)

# 一根 6 点渐变光条：中心在 at、宽 w、高 1px，两端 alpha=0、中心满强度。
# 点序沿凸六边形周边排（左上->中上->右上->右下->中下->左下），draw_polygon 自动剖分。
func _bar(at: Vector2, w: float, c: Color) -> void:
	var e := c
	e.a = 0.0
	var hw := w * 0.5
	var pts := PackedVector2Array([
		at + Vector2(-hw, -0.5), at + Vector2(0.0, -0.5), at + Vector2(hw, -0.5),
		at + Vector2(hw, 0.5), at + Vector2(0.0, 0.5), at + Vector2(-hw, 0.5)])
	draw_polygon(pts, PackedColorArray([e, c, e, e, c, e]))
