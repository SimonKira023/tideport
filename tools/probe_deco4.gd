extends Node
# 一次性工具 4：最终选料定稿图。按固定顺序放大候选 region，
# 每项位置打印在日志里，逐项确认颜色形态。
# 输出 res://tools/deco_check4.png

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"

# [标签, 文件, region 或 null(整图), 放大倍数]
const PICKS := [
	["winA_y163_x7", "Doors, windows and curtains.png", Rect2i(7, 163, 33, 24), 4.0],
	["winB_y163_x55", "Doors, windows and curtains.png", Rect2i(55, 163, 33, 24), 4.0],
	["winC_y163_x103", "Doors, windows and curtains.png", Rect2i(103, 163, 33, 24), 4.0],
	["winD_y163_x151", "Doors, windows and curtains.png", Rect2i(151, 163, 33, 24), 4.0],
	["winE_y163_x199", "Doors, windows and curtains.png", Rect2i(199, 163, 33, 24), 4.0],
	["winF_y227_x7", "Doors, windows and curtains.png", Rect2i(7, 227, 33, 24), 4.0],
	["winG_y227_x55", "Doors, windows and curtains.png", Rect2i(55, 227, 33, 24), 4.0],
	["winH_y227_x103", "Doors, windows and curtains.png", Rect2i(103, 227, 33, 24), 4.0],
	["winI_y227_x151", "Doors, windows and curtains.png", Rect2i(151, 227, 33, 24), 4.0],
	["winJ_y227_x199", "Doors, windows and curtains.png", Rect2i(199, 227, 33, 24), 4.0],
	["narrow_y131_x7", "Doors, windows and curtains.png", Rect2i(7, 131, 10, 24), 6.0],
	["narrow_y131_x55", "Doors, windows and curtains.png", Rect2i(55, 131, 10, 24), 6.0],
	["narrow_y131_x103", "Doors, windows and curtains.png", Rect2i(103, 131, 10, 24), 6.0],
	["narrow_y195_x7", "Doors, windows and curtains.png", Rect2i(7, 195, 10, 24), 6.0],
	["narrow_y195_x103", "Doors, windows and curtains.png", Rect2i(103, 195, 10, 24), 6.0],
	["band_y75", "Doors, windows and curtains.png", Rect2i(0, 75, 120, 21), 4.0],
	["band_y107", "Doors, windows and curtains.png", Rect2i(0, 107, 120, 21), 4.0],
	["others_full", "Others.png", null, 6.0],
	["cabinet_0_40", "Dressers.png", Rect2i(0, 40, 48, 18), 4.0],
	["night_2_130", "Dressers.png", Rect2i(2, 130, 27, 14), 5.0],
	["night_34_130", "Dressers.png", Rect2i(34, 130, 27, 14), 5.0],
	["chair_66_205", "Chairs.png", Rect2i(66, 205, 11, 18), 6.0],
	["chair_163_205", "Chairs.png", Rect2i(163, 205, 11, 18), 6.0],
	["chair_130_173", "Chairs.png", Rect2i(130, 173, 11, 18), 6.0],
	["chair_194_173", "Chairs.png", Rect2i(194, 173, 11, 18), 6.0],
	["rug_big_4_165", "Part 11 copiar.png", Rect2i(4, 165, 70, 40), 3.0],
	["rug_big_84_117", "Part 11 copiar.png", Rect2i(84, 117, 70, 40), 3.0],
	["rug_big_4_117", "Part 11 copiar.png", Rect2i(4, 117, 70, 40), 3.0],
	["rug_ov_167_136", "Part 11 copiar.png", Rect2i(167, 136, 33, 18), 4.0],
	["rug_ov_194_74", "Part 11 copiar.png", Rect2i(194, 74, 27, 21), 4.0],
	["rug_ov_226_74", "Part 11 copiar.png", Rect2i(226, 74, 27, 21), 4.0],
	["rug_p9_480_84", "Part 9 copiar.png", Rect2i(480, 84, 48, 28), 3.0],
	["rug_p9_0_72", "Part 9 copiar.png", Rect2i(0, 72, 96, 40), 2.0],
	["rug_p9_352_72", "Part 9 copiar.png", Rect2i(352, 72, 96, 40), 2.0],
	["candle_png", "candle.png", null, 6.0],
	["candle1", "Candle 1.png", null, 6.0],
	["candle3", "Candle 3.png", null, 6.0],
]

var _x := 8
var _y := 8
var _rowh := 0

func _ready() -> void:
	var sheet := Image.create_empty(1150, 2400, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.16, 0.2))
	for p in PICKS:
		var img := _img(DIR + p[1])
		var region: Rect2i = p[2] if p[2] != null else Rect2i(Vector2i.ZERO, img.get_size())
		var c := img.get_region(region)
		var sc: float = p[3]
		c.resize(int(c.get_width() * sc), int(c.get_height() * sc), Image.INTERPOLATE_NEAREST)
		if _x + c.get_width() + 8 > sheet.get_width():
			_x = 8
			_y += _rowh + 12
			_rowh = 0
		if _y + c.get_height() + 8 > sheet.get_height():
			print("[警告] 画布不够，跳过 ", p[0])
			continue
		sheet.blend_rect(c, Rect2i(0, 0, c.get_width(), c.get_height()), Vector2i(_x, _y))
		print("[放] %-16s @(%d,%d) %dx%d" % [p[0], _x, _y, c.get_width(), c.get_height()])
		_x += c.get_width() + 12
		_rowh = maxi(_rowh, c.get_height())
	sheet.save_png("res://tools/deco_check4.png")
	print("[SAVED] res://tools/deco_check4.png")
	get_tree().quit()

func _img(path: String) -> Image:
	var tex := load(path) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img
