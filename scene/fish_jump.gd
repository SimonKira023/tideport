extends Node2D
# q4 灵动：深水区偶尔有鱼跃出水面 —— 一条小鱼剪影沿抛物线一跃，
# 起跳/落水各荡开一圈涟漪。克制频率：平均十几秒一条，下雨/风暴鱼不露头。
# 挑点规则：只挑「四周不贴陆」的深水格（_edge_mask==0，鱼不在岸边蹦），
# 且在相机视野附近 —— 视野外跳了也看不见，纯浪费。

const CD_MIN := 7.0        # 两条鱼之间的间隔（秒，区间内随机）
const CD_MAX := 18.0
const RIPPLE_T := 0.7      # 一圈涟漪荡完的秒数

var _game: Node2D = null
var _cd := 0.0
var _ripples: Array = []   # [{p: Vector2, t: float}] 活动中的涟漪，t 0→1

static var _fish_tex: ImageTexture = null

func setup(g: Node2D) -> void:
	_game = g
	z_index = g.Z_SHORE       # 与浪线/波光同层；节点排在 WaterGlint 之后 -> 盖在水面上
	_cd = randf_range(CD_MIN, CD_MAX)

func _process(delta: float) -> void:
	if _game == null:
		return
	# 涟漪推进；同时最多两三条，每帧重绘开销可忽略
	for r in _ripples:
		r["t"] += delta / RIPPLE_T
	var n0 := _ripples.size()
	_ripples = _ripples.filter(func(r): return float(r["t"]) < 1.0)
	if not _ripples.is_empty() or _ripples.size() != n0:
		queue_redraw()
	# 下雨/风暴：鱼不露头
	if Weather.is_rain() or Weather.is_storm():
		return
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = randf_range(CD_MIN, CD_MAX)
	_try_jump()

func _draw() -> void:
	for r in _ripples:
		var t: float = r["t"]
		draw_arc(r["p"], 1.0 + t * 5.0, 0.0, TAU, 20,
			Color(0.93, 0.98, 1.0, 0.42 * (1.0 - t)), 0.9)

# 随机抽样挑一个合适的深水格；挑不到就等下一轮（不硬凑）
func _try_jump() -> void:
	var wset: Dictionary = _game._water_set if "_water_set" in _game else _game._water
	if wset.is_empty():
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var ks: Array = wset.keys()
	var half: Vector2 = get_viewport_rect().size * 0.5 / cam.zoom + Vector2(64, 64)
	var vis := Rect2(cam.get_screen_center_position() - half, half * 2.0)
	var origin: Vector2 = _game.grid_layer.position
	for i in 32:
		var c: Vector2i = ks[randi() % ks.size()]
		if _game._edge_mask(c, true) != 0:
			continue                     # 贴岸的格子不要
		var p := origin + Vector2(c.x * 16 + 8, c.y * 16 + 8)
		if not vis.has_point(p):
			continue
		_jump(p)
		return

func _jump(p: Vector2) -> void:
	_ripples.append({"p": p, "t": 0.0})      # 起跳先荡一圈
	var fish := Sprite2D.new()
	fish.texture = _fish_texture()
	fish.modulate = Color(0.22, 0.28, 0.38, 0.95)   # 白色小贴图在这里染成鱼灰蓝
	fish.position = p
	fish.flip_h = randf() < 0.5
	add_child(fish)
	var dir := -1.0 if fish.flip_h else 1.0
	var span := randf_range(9.0, 14.0)       # 跃出的水平距离
	var arc := randf_range(7.0, 10.0)        # 跃起的高度
	var tw := fish.create_tween()
	tw.tween_method(func(t: float):
		# 抛物线：x 匀速、y 按 sin 拱起；鱼头始终沿速度方向（导数）
		var vy := -arc * PI * cos(t * PI)
		fish.position = p + Vector2(dir * t * span, -sin(t * PI) * arc)
		fish.rotation = Vector2(dir * span, vy).angle()
	, 0.0, 1.0, 0.55)
	tw.tween_callback(func():
		_ripples.append({"p": fish.position, "t": 0.0})   # 落水再荡一圈
		fish.queue_free())

# 小鱼剪影 7x3：纺锤身 + 尾叉（白色，_jump 里 modulate 染色；static 缓存共用）
func _fish_texture() -> ImageTexture:
	if _fish_tex != null:
		return _fish_tex
	var img := Image.create_empty(7, 3, false, Image.FORMAT_RGBA8)
	var body := Color(1, 1, 1, 1)
	img.set_pixel(0, 1, body)                # 尾尖
	img.set_pixel(1, 1, body)                # 尾根
	for y in 3:
		for x in range(2, 6):
			if y == 1 or (x >= 3 and x <= 4):
				img.set_pixel(x, y, body)
	img.set_pixel(6, 1, body)                # 头尖
	_fish_tex = ImageTexture.create_from_image(img)
	return _fish_tex
