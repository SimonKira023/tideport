extends RefCounted
# e31 光影：光源公用件 —— 圆形光晕贴图 + 挂灯/火光的构造函数。
# 各光源（篝火 / 壁炉 / 门口挂灯）都用这一份，别再各自抄一遍逐像素循环。
#
# ❗为什么不用 GradientTexture2D 的 FILL_RADIAL：渲出来边界是方的（光晕像块方砖）。
#   自己按「到圆心的距离」逐像素算才是正圆，衰减曲线还能随便调。

# 贴图只做一次就缓存：128² 的逐像素循环 × 每盏灯都跑一遍太浪费。
# key = "尺寸_衰减指数"，同一组参数只生成一张。
static var _mask_cache := {}

# falloff 指数越大，中间那团亮芯越小、边缘收得越快（1.9 ≈ 篝火那盏）
static func radial_mask(size: int = 128, falloff: float = 1.9) -> ImageTexture:
	var key := "%d_%.2f" % [size, falloff]
	if _mask_cache.has(key):
		return _mask_cache[key]
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c: float = (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var d: float = sqrt(dx * dx + dy * dy)
			var v: float = pow(clampf(1.0 - d, 0.0, 1.0), falloff)
			img.set_pixel(x, y, Color8(255, 255, 255, int(v * 255.0)))
	var tex := ImageTexture.create_from_image(img)
	_mask_cache[key] = tex
	return tex

# 一盏灯：PointLight2D（真的照亮周围）—— 只给 texture/颜色/大小，位置由调用方摆
# q1 光影追踪：默认开实时阴影 + PCF13 软化影缘 —— 灯光会被遮挡体真实挡住，
#   人从灯下走过影子会绕脚扫动。shadow_color 半透明偏蓝：影子不是死黑，留一点透亮。
static func make_light(color: Color, energy: float, scale: float, falloff: float = 1.9) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = radial_mask(128, falloff)
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	l.shadow_enabled = true
	l.shadow_filter = PointLight2D.SHADOW_FILTER_PCF13
	# e89 手感调校：2.5 的影缘在玩家眼里还是"纸片剪切"。smooth 拉到 6（PCF13 上限收益区）
	#   + 影色透明度 0.55 -> 0.38：影子更透、边缘糊开, 光照才像空气里的雾而不是贴纸。
	l.shadow_filter_smooth = 6.0
	l.shadow_color = Color(0.02, 0.02, 0.06, 0.38)
	return l

# 光源本体的可见柔光：加法混合的圆片。
# ❗PointLight2D 只把周围的东西"染色"，自己是不发光的 —— 夜里远看一盏灯，
#   光靠染色根本看不见光源在哪。叠这层加法柔光才像"在发光"（配合后处理泛光更明显）。
static func make_glow(color: Color, scale: float, falloff: float = 1.9) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = radial_mask(128, falloff)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.scale = Vector2(scale, scale)
	s.modulate = color
	return s

# ---------------- 2026-10-06 建筑窗火 ----------------
# 方形的柔光贴图：窗户是一小块方的，用圆光会像"飘着一团球"。
# 与 radial_mask 共用一个缓存字典（键带 sq_ 前缀，不会撞）。
static func square_mask(size: int = 16, softness: float = 3.0) -> ImageTexture:
	var key := "sq_%d_%.1f" % [size, softness]
	if _mask_cache.has(key):
		return _mask_cache[key]
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c: float = (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx: float = absf(float(x) - c) / c
			var dy: float = absf(float(y) - c) / c
			var d: float = maxf(dx, dy)                  # 棋盘距离 = 方角
			var v: float = clampf((1.0 - d) * float(size) / softness, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v * v))
	var tex := ImageTexture.create_from_image(img)
	_mask_cache[key] = tex
	return tex

# 一扇"亮着的窗"：暖色柔光方块（不建 PointLight2D —— 建筑多, 真灯会爆灯池）。
# 夜里由调用方按 TONE_ADVANCE 决定显隐；色温按用途给，所以夜里一眼认得出是哪栋。
#
# ❗2026-10-06 定调「暖橘渔村」时踩的坑：这里一开始是**加法混合**（跟路灯的 make_glow 一样）。
#   但建筑贴图里的窗格本身是**蓝玻璃**，加法的"暖 + 蓝" = 白 —— 探针拍出来一排窗全是
#   灰白，一点橘都没有（实测 building 区 r-b 只剩 37）。改成**混色**（默认 blend）：
#   暖色直接盖在窗玻璃上，窗格本身变暖，才是「亮着的窗」而不是「糊了一层光」。
#   alpha（= window_tint 的亮度）留在 0.65~1.0，既盖得住蓝玻璃、又留得住逐扇的变化。
static func make_window_glow(color: Color, scale: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = square_mask(16, 3.0)
	s.scale = Vector2(scale, scale)
	s.modulate = color
	return s

# ---------------- 2026-10-06 夜里亮窗：一个总闸 + 一种"生活感" ----------------
# 主色调定为「暖橘渔村」之后, 窗火/招牌/船舷灯统一走这两件 ——
# 亮灭只在 glow_hour_now() 一处判定（读 TONE_ADVANCE, 谁也别再写死提前量）,
# 每扇窗的亮度/色温由 window_tint 抖开（不然一排同款亮窗 = 贴了一排发光贴纸）。
const GLOW_ON_HOUR := 18.5      # 跟路灯/栈桥灯同一个色调钟门槛（见 lamp_node.gd）
const GLOW_OFF_HOUR := 6.5

# 此刻算不算「该点灯的时辰」。窗火/招牌/船舷灯全问这一句。
static func glow_hour_now() -> bool:
	var h: float = TimeManager.hour + TimeManager.minute / 60.0 + TimeManager.TONE_ADVANCE
	return h >= GLOW_ON_HOUR or h < GLOW_OFF_HOUR

# 一扇窗的"生活感"：同一栋楼的每扇窗亮度/色温都不同, 还有约 1/5 是全黑的。
# ❗The Last Night 的窗户没有一扇是均匀亮的 —— 全点成一样的暖黄会变成"贴了一排
#   发光贴纸", 反而廉价。黑着那几扇是"屋里没人", 亮着的那几扇才像有人在过日子。
# 返回色带 alpha：加法混合下 alpha 就是这扇窗的亮度（0 = 完全不出光）。
static func window_tint(base: Color, rng: RandomNumberGenerator) -> Color:
	if rng.randf() < 0.2:
		return Color(0.0, 0.0, 0.0, 0.0)      # 黑着 = 这扇窗后没人
	var warm := rng.randf_range(-0.06, 0.06)   # 色温抖动：有的偏白, 有的偏橘
	# ❗亮度要**偏亮**（0.65~1.0）—— 后处理 fx_post 的色温分离对"中间调"会把蓝拉上来（中和掉暖），
	#   只有落进高光档的亮点才会被镀金。窗火调暗 = 反而变灰白（2026-10-06 探针实测走了一趟弯路）。
	var bright := rng.randf_range(0.65, 1.0)   # 亮度抖动
	var c := Color(
		clampf(base.r + warm, 0.0, 1.0),
		clampf(base.g + warm * 0.55, 0.0, 1.0),
		clampf(base.b - warm * 0.45, 0.0, 1.0))
	c.a = bright
	return c

# 一扇窗"真的照亮墙面"的小灯。
# ❗2026-10-06 探针实测的血泪结论：夜色 CanvasModulate 是**蓝主导**的 (0.2,0.22,0.42) ——
#   红被压到 1/5、蓝保留 42%，纯画布元素（加法或混色的 sprite）在夜里**怎么调都读不出暖**
#   （窗火 sprite 只能拍到"灰白方块"）。只有 Light2D 的光是在 modulate **之后**叠加的，
#   才保得住暖橘。所以窗火 = "窗格亮着"的 sprite + 这盏真灯给墙面铺暖。
#   ❗一律关阴影：PointLight2D 的大头开销是投影；窗灯数量多，关掉才敢多摆。
static func make_window_light(color: Color, energy: float, scale: float) -> PointLight2D:
	var l := make_light(color, energy, scale, 2.0)
	l.shadow_enabled = false
	return l

# ---------------- q1/q2 光影追踪：遮挡体公用件 ----------------
# LightOccluder2D = 挡光的实体剪影：所有开了阴影的光（灯/篝火/太阳）都会被它
#   真实截断，物后拖出影子。 ❗铁律：遮挡体多边形绝不能包住光心，否则整盏灯
#   把自己罩黑（全场景只剩影子）—— 篝火/壁炉不加遮挡体就是这个原因。

# 闭合多边形遮挡体（pts 是相对父节点的局部坐标）
# ❗退化保护：多边形少于 3 个点时 Godot 会往控制台刷
#   `canvas_occluder_polygon_set_shape: pc < 2` 报错（一次几百行，把真错误埋掉）。
#   有调用方需要「先建空壳、之后再按尺寸填 polygon」（见 tree_node.gd 随生长阶段
#   换树冠半径），所以这里对不够点数的数组直接跳过赋值 —— occluder.polygon 保持
#   默认空数组，等于这个遮挡体暂时不产生阴影，不会炸也不会刷屏。
static func make_occluder(pts: PackedVector2Array) -> LightOccluder2D:
	var o := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	if pts.size() >= 3:
		poly.polygon = pts
	o.occluder = poly
	return o

# 矩形的四个角（顺时针）
static func rect_pts(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		r.position,
		r.position + Vector2(r.size.x, 0),
		r.position + r.size,
		r.position + Vector2(0, r.size.y),
	])

# 圆的八边形近似（树冠用方方正正的矩形太生硬）
static func circle_pts(center: Vector2, radius: float, sides: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

# 最常用的「矩形遮挡体」一步到位
static func occluder_rect(r: Rect2) -> LightOccluder2D:
	return make_occluder(rect_pts(r))
