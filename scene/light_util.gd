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
static func make_light(color: Color, energy: float, scale: float, falloff: float = 1.9) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = radial_mask(128, falloff)
	l.color = color
	l.energy = energy
	l.texture_scale = scale
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
