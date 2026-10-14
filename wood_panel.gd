# wood_panel.gd —— e90 UI 全面手绘化：程序生成的"手绘木板"面板底（StyleBoxTexture 版）
#
# 对话框那套 wood_frame.gd 是"画框"（九层套框, 一块一块 draw_rect）；
# 这里补的是"面板"版：一整张横板拼的木板贴图, 包成 StyleBoxTexture 给
# PanelContainer / 底板用 —— 背包、商店、作弊面板的主底板统一换成木板材质。
#
# 生成纪律：
#   · 固定种子 —— 每次起游戏木理一模一样（截图对比/自检都吃这个）。
#   · e98 色板照抄参考图（暖橙木 #d29151/#a1572a/#461f18）: 中段做板底、亮面只留
#     板顶 1px 受光、深影只留板缝 —— 大面积仍是中暗木色, 白字照样读得出。
#   · 16px 一块横板：板顶受光 1px、板底落缝 1px、板中木理 + 结疤 + 板头钉。
#   · 外圈 2px 深边 = 老版 StyleBoxFlat 的 border 的手绘替身。
# 用法: panel.add_theme_stylebox_override("panel", preload("res://wood_panel.gd").style())
extends RefCounted

const C_PLANK_A := Color("8f4d24")   # e98 照抄参考图框木色: 板与板之间换色（暖橙木）
const C_PLANK_B := Color("a1572a")   # （参考图亮面 #d29151 / 中段 #a1572a / 深影 #461f18）
const C_PLANK_C := Color("7f441f")
const C_HI := Color("d29151")        # 板顶受光（参考图亮木面原色）
const C_GRAIN := Color("5a2b10")     # 木理
const C_KNOT := Color("472211")      # 结疤芯
const C_GAP := Color("401c15")       # 板缝 / 外圈深边（参考图深影压深一档, 保白字对比）

static var _tex: Texture2D = null

static func tex() -> Texture2D:
	if _tex != null:
		return _tex
	var W := 96
	var H := 96
	var plank := 16
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xE90E90
	var bases := [C_PLANK_A, C_PLANK_B, C_PLANK_C]
	for py in range(0, H, plank):
		var base: Color = bases[(py / plank) % bases.size()]
		# 板底色 + 极轻的斜向明暗（固定频率, 不是噪点）
		for y in range(py, py + plank):
			for x in W:
				var shade := 1.0 + 0.07 * sin(float(x) * 0.13 + float(py) * 0.9)
				img.set_pixel(x, y, base * shade)
		for x in W:
			img.set_pixel(x, py, C_HI)                       # 板顶受光
			img.set_pixel(x, py + plank - 1, C_GAP)          # 板底落缝
		# 木理：每板 2~3 道短横纹, 带 1px 阶梯抖动（手绘的"抖"）
		var grains := 2 + rng.randi() % 2
		for g in grains:
			var gy := py + 3 + rng.randi() % (plank - 6)
			var gx := rng.randi() % W
			var gl := 12 + rng.randi() % 26
			for i in gl:
				var x := (gx + i) % W
				var yy := gy + ((i / 7) % 2)                 # 每隔几步上下错 1px
				img.set_pixel(x, yy, C_GRAIN)
				if i % 5 == 0:
					img.set_pixel(x, yy + 1, C_GRAIN * 0.8)  # 纹下淡影
		# 结疤：一半的板有一个, 深芯 + 受光圈
		if rng.randf() < 0.5:
			var kx := 8 + rng.randi() % (W - 16)
			var ky := py + 5 + rng.randi() % (plank - 9)
			for dy in range(-2, 3):
				for dx in range(-3, 4):
					if absf(float(dx) / 3.2) * absf(float(dx) / 3.2) \
							+ float(dy * dy) / 5.0 <= 1.0:
						var c := C_KNOT
						if dx < 0 and dy < 0:
							c = C_HI.darkened(0.2)           # 左上受光
						img.set_pixel(clampi(kx + dx, 0, W - 1), clampi(ky + dy, 0, H - 1), c)
		# 板头钉：缝上两颗深点
		img.set_pixel(3, py + plank / 2, C_GAP)
		img.set_pixel(W - 4, py + plank / 2, C_GAP)
	# 外圈 2px 深边（九宫格拉伸后, 四边都是这道手描边）
	for i in W:
		for e in 2:
			img.set_pixel(i, e, C_GAP)
			img.set_pixel(i, H - 1 - e, C_GAP)
	for i in H:
		for e in 2:
			img.set_pixel(e, i, C_GAP)
			img.set_pixel(W - 1 - e, i, C_GAP)
	_tex = ImageTexture.create_from_image(img)
	return _tex

# 面板样式。九宫格边距取板高一半（96px 程序图 -> 16）。
# 平铺模式（TILE）保证大面板上木板不拉伸糊掉。
static func style(cml := 22, cmt := 14, cmr := 22, cmb := 18) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex()
	var m := minf(16.0, tex().get_height() / 2.0)
	for k in ["texture_margin_left", "texture_margin_right", "texture_margin_top", "texture_margin_bottom"]:
		sb.set(k, m)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.content_margin_left = cml
	sb.content_margin_top = cmt
	sb.content_margin_right = cmr
	sb.content_margin_bottom = cmb
	return sb
