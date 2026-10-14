# parchment.gd —— e98: 羊皮纸材质（参考图头像框内衬同款, 程序化 + 固定种子）
#
# 参考图取色: 纸面 #e1bd81 / 暖影 #d7ae76 / 亮斑 #f0dcae / 深麻点 #8a6838。
# 96x96 无缝平铺（所有斑点坐标取模回绕）, wood_frame.gd 衬纸层 draw_texture_rect 平铺。
# 固定种子 —— 每次起游戏纸纹一模一样（截图对比/自检都吃这个）。
extends RefCounted

const C_BASE := Color("e3c08a")   # 纸底
const C_WARM := Color("d7ae76")   # 暖影（洇开的茶渍团）
const C_HI := Color("f0dcae")     # 亮斑
const C_FLECK := Color("8a6838")  # 深麻点

static var _tex: Texture2D = null

static func tex() -> Texture2D:
	if _tex != null:
		return _tex
	var W := 96
	var H := 96
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xE98E98
	for y in H:
		for x in W:
			# 极轻的斜向冷暖条（纸卷纹）, 幅度压在 4% 内, 不抢内容
			var shade := 1.0 + 0.04 * sin(float(x) * 0.11 + float(y) * 0.03)
			img.set_pixel(x, y, C_BASE * shade)
	# 大块暖斑: 12 团椭圆软边（纸面洇渍）, 坐标取模保证无缝
	for i in 12:
		var cx := rng.randf_range(0.0, float(W))
		var cy := rng.randf_range(0.0, float(H))
		var rx := rng.randf_range(6.0, 16.0)
		var ry := rng.randf_range(4.0, 10.0)
		for dy in range(-int(ry) - 2, int(ry) + 3):
			for dx in range(-int(rx) - 2, int(rx) + 3):
				var fx := absf(float(dx) / rx)
				var fy := absf(float(dy) / ry)
				if fx * fx + fy * fy > 1.0:
					continue
				var a := clampf(1.0 - (fx * fx + fy * fy), 0.0, 1.0) * 0.35
				var x := posmod(int(cx) + dx, W)
				var y := posmod(int(cy) + dy, H)
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(C_WARM, a))
	# 亮斑: 8 小团（纸纤维反光）
	for i in 8:
		var cx := rng.randf_range(0.0, float(W))
		var cy := rng.randf_range(0.0, float(H))
		var rx := rng.randf_range(4.0, 9.0)
		var ry := rng.randf_range(3.0, 6.0)
		for dy in range(-int(ry) - 1, int(ry) + 2):
			for dx in range(-int(rx) - 1, int(rx) + 2):
				var fx := absf(float(dx) / rx)
				var fy := absf(float(dy) / ry)
				if fx * fx + fy * fy > 1.0:
					continue
				var a := clampf(1.0 - (fx * fx + fy * fy), 0.0, 1.0) * 0.3
				var x := posmod(int(cx) + dx, W)
				var y := posmod(int(cy) + dy, H)
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(C_HI, a))
	# 深麻点: 60 颗 1px, 三分之一带一粒淡影
	for i in 60:
		var x := rng.randi() % W
		var y := rng.randi() % H
		img.set_pixel(x, y, C_FLECK)
		if i % 3 == 0:
			img.set_pixel((x + 1) % W, y, C_FLECK.lerp(C_BASE, 0.5))
	_tex = ImageTexture.create_from_image(img)
	return _tex
