extends Node
# 一次性工具 5（修正版）：补确认——
# - "Tables and desks.png" 找桌子（连通域 + 整图缩略）
# - Fireplace / Closet / Sofa and armchair 连通域 + 缩略（场景已预声明这三张图集）
# - Others 三个 29×20 小件定内容、(81,48,30,32) 定书柜还是钢琴
# - candle.png 单帧、Part 9 (480,84)、Chairs y=141 行备选
# 输出 res://tools/deco_check5.png

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"

# [标签, 文件, region, 放大倍数]
const PICKS := [
	["oth_2_93", "Others.png", Rect2i(2, 93, 29, 18), 8.0],
	["oth_34_91", "Others.png", Rect2i(34, 91, 29, 20), 8.0],
	["oth_66_91", "Others.png", Rect2i(66, 91, 29, 20), 8.0],
	["oth_81_48", "Others.png", Rect2i(81, 48, 30, 32), 6.0],
	["candle_a", "candle.png", Rect2i(0, 0, 16, 16), 8.0],
	["candle_b", "candle.png", Rect2i(16, 0, 16, 16), 8.0],
	["p9_480", "Part 9 copiar.png", Rect2i(480, 84, 48, 28), 5.0],
	["chair_2_141", "Chairs.png", Rect2i(2, 141, 11, 18), 8.0],
	["chair_66_141", "Chairs.png", Rect2i(66, 141, 11, 18), 8.0],
	["chair_130_141", "Chairs.png", Rect2i(130, 141, 11, 18), 8.0],
	["chair_194_141", "Chairs.png", Rect2i(194, 141, 11, 18), 8.0],
]

# 要整体缩略 + 连通域扫描的图集
const ATLASES := [
	"Tables and desks.png",
	"Fireplace.png",
	"Closet.png",
	"Sofa and armchair.png",
]

var _x := 8
var _y := 8
var _rowh := 0

func _ready() -> void:
	var sheet := Image.create_empty(1200, 1600, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.16, 0.2))
	for p in PICKS:
		_put(sheet, p[0], _img(DIR + p[1]), p[2], p[3])
	for a in ATLASES:
		var img := _img(DIR + a)
		print("[%s] 原始尺寸 %s" % [a, img.get_size()])
		var show := img
		if img.get_width() > 560:
			show = img.duplicate()
			show.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_NEAREST)
		_put(sheet, a.get_basename() + "_x0.5", show, Rect2i(Vector2i.ZERO, show.get_size()), 1.0)
		_dump(img, a)
	sheet.save_png("res://tools/deco_check5.png")
	print("[SAVED] res://tools/deco_check5.png")
	get_tree().quit()

func _put(sheet: Image, tag: String, src: Image, region: Rect2i, sc: float) -> void:
	var c := src.get_region(region)
	if sc != 1.0:
		c.resize(int(c.get_width() * sc), int(c.get_height() * sc), Image.INTERPOLATE_NEAREST)
	if _x + c.get_width() + 8 > sheet.get_width():
		_x = 8
		_y += _rowh + 12
		_rowh = 0
	if _y + c.get_height() + 8 > sheet.get_height():
		print("[警告] 画布不够，跳过 ", tag)
		return
	sheet.blend_rect(c, Rect2i(0, 0, c.get_width(), c.get_height()), Vector2i(_x, _y))
	print("[放] %-22s @(%d,%d) %dx%d" % [tag, _x, _y, c.get_width(), c.get_height()])
	_x += c.get_width() + 12
	_rowh = maxi(_rowh, c.get_height())

func _dump(img: Image, tag: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var rects: Array[Rect2i] = []
	for y in h:
		for x in w:
			var i := y * w + x
			if seen[i] == 1:
				continue
			if img.get_pixel(x, y).a <= 0.05:
				seen[i] = 1
				continue
			var minx := x
			var maxx := x
			var miny := y
			var maxy := y
			var q: Array[Vector2i] = [Vector2i(x, y)]
			seen[i] = 1
			while q.size() > 0:
				var c: Vector2i = q.pop_back()
				minx = mini(minx, c.x)
				maxx = maxi(maxx, c.x)
				miny = mini(miny, c.y)
				maxy = maxi(maxy, c.y)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
						continue
					var ni := n.y * w + n.x
					if seen[ni] == 1:
						continue
					seen[ni] = 1
					if img.get_pixel(n.x, n.y).a > 0.05:
						q.push_back(n)
			if (maxx - minx + 1) * (maxy - miny + 1) >= 80:
				rects.append(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))
	rects.sort_custom(func(a, b): return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	print("== %s 连通域 %d 个（面积>=80）==" % [tag, rects.size()])
	for r in rects:
		print("  ", r)

func _img(path: String) -> Image:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("加载失败: " + path)
		var empty := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		return empty
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img
