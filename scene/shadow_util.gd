extends RefCounted
# e33 画面美化：脚底影子公用件 —— 半透明扁椭圆，垫在角色/树/建筑的脚下。
# 之前所有实体都是「贴图直接浮在地上」，没有投影，看着像贴纸；
# 垫一层椭圆影子之后才「站」在地面上（树/建筑尤其明显）。
#
# ❗为什么自己逐像素画、不走「光晕贴图拉扁」那条路：
#   全局纹理过滤是 nearest（像素风），一张方贴图拉扁会把像素拉成一棱一棱的横条。
#   按 (宽,高) 逐像素生成一次就缓存 —— 全项目就这么几种尺寸，不亏。

static var _cache := {}

# 一片影子：w x h 的扁椭圆，中心最实、边上 2px 渐隐，黑褐色。
# 精灵自带 z_index = -1（垫在实体贴图下面、地形上面），调用方只管摆位置。
static func make_shadow(w: float, h: float, alpha: float = 0.28) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _mask(int(ceil(w)), int(ceil(h)), alpha)
	s.z_index = -1
	return s

# 逐像素椭圆：到椭圆心的归一化距离 > 1 全透明，0.85~1.0 之间渐隐。
static func _mask(w: int, h: int, alpha: float) -> ImageTexture:
	var key := "%d_%d_%d" % [w, h, int(round(alpha * 100.0))]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var cx: float = (w - 1) * 0.5
	var cy: float = (h - 1) * 0.5
	var rx: float = w * 0.5
	var ry: float = h * 0.5
	for y in h:
		for x in w:
			var dx: float = (float(x) - cx) / rx
			var dy: float = (float(y) - cy) / ry
			var d: float = sqrt(dx * dx + dy * dy)
			var v: float = clampf((1.0 - d) / 0.15, 0.0, 1.0)
			if v > 0.0:
				img.set_pixel(x, y, Color(0.05, 0.03, 0.02, v * alpha))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
