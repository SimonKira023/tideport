extends Node
# 一次性工具：把候选家具 region 拼成一张 4 倍放大对照图，肉眼确认裁剪效果。
# 输出 res://tools/deco_check.png，跑完即退。

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"

# [标签, 图集文件名, region]
const CROPS := [
	["win1", "Doors, windows and curtains.png", Rect2i(7, 163, 33, 24)],
	["clock", "Others.png", Rect2i(1, 46, 30, 34)],
	["closet", "Closet.png", Rect2i(69, 8, 35, 38)],
	["fire", "Fireplace.png", Rect2i(0, 65, 64, 94)],
	["dress", "Dressers.png", Rect2i(0, 8, 48, 16)],
	["table", "Tables and desks.png", Rect2i(0, 200, 128, 21)],
	["chairA", "Chairs.png", Rect2i(2, 10, 13, 21)],
	["chairB", "Chairs.png", Rect2i(34, 11, 11, 20)],
	["sofa", "Sofa and armchair.png", Rect2i(2, 11, 29, 20)],
	["arm", "Sofa and armchair.png", Rect2i(1, 66, 13, 29)],
	["plant1", "Others.png", Rect2i(1, 7, 14, 25)],
	["plant2", "Others.png", Rect2i(17, 7, 14, 25)],
	["rug1", "Tables and desks.png", Rect2i(0, 353, 31, 30)],
	["rug2", "Tables and desks.png", Rect2i(32, 353, 31, 30)],
	["rug3", "Tables and desks.png", Rect2i(225, 353, 63, 30)],
	["rug4", "Tables and desks.png", Rect2i(160, 353, 31, 30)],
]

func _ready() -> void:
	var cache := {}
	for c in CROPS:
		if not cache.has(c[1]):
			var tex := load(DIR + c[1]) as Texture2D
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			cache[c[1]] = img
	var sc := 4
	var x := 8
	var y := 8
	var rowh := 0
	var sheet := Image.create_empty(1100, 1000, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.16, 0.2))
	for c in CROPS:
		var img: Image = cache[c[1]]
		var crop := img.get_region(c[2])
		crop.resize(crop.get_width() * sc, crop.get_height() * sc, Image.INTERPOLATE_NEAREST)
		if x + crop.get_width() + 8 > sheet.get_width():
			x = 8
			y += rowh + 14
			rowh = 0
		sheet.blend_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()), Vector2i(x, y))
		x += crop.get_width() + 12
		rowh = maxi(rowh, crop.get_height())
	sheet.save_png("res://tools/deco_check.png")
	print("[SAVED] res://tools/deco_check.png")
	get_tree().quit()
