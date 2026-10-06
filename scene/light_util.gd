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
	l.shadow_filter_smooth = 2.5
	l.shadow_color = Color(0.02, 0.02, 0.06, 0.55)
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
