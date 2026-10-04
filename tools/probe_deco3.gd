extends Node
# 一次性工具 3：按行放大候选图集 + Part 系大块区域（地毯候选）。
# 输出 res://tools/deco_check3.png，并打印 Part 系大块 Rect。

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"

var _x := 8
var _y := 8
var _rowh := 0

func _ready() -> void:
	var sheet := Image.create_empty(1150, 3000, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.16, 0.2))

	# 门窗图集按行切
	for row in [Rect2i(0, 75, 256, 21), Rect2i(0, 107, 256, 21),
			Rect2i(0, 131, 256, 24), Rect2i(0, 163, 256, 24),
			Rect2i(0, 195, 256, 24), Rect2i(0, 227, 256, 24)]:
		_put(sheet, _crop(DIR + "Doors, windows and curtains.png", row, 3.0))
	# Others 5 倍
	_put(sheet, _zoom(DIR + "Others.png", 5.0))
	# Chairs 每行
	for row in [Rect2i(0, 10, 304, 24), Rect2i(0, 42, 304, 24), Rect2i(0, 74, 304, 24),
			Rect2i(0, 107, 304, 24), Rect2i(0, 141, 304, 20), Rect2i(0, 173, 304, 20),
			Rect2i(0, 205, 304, 20)]:
		_put(sheet, _crop(DIR + "Chairs.png", row, 3.0))
	# Dressers 每行
	for row in [Rect2i(0, 8, 256, 17), Rect2i(0, 40, 256, 18), Rect2i(0, 72, 256, 16),
			Rect2i(0, 130, 256, 14)]:
		_put(sheet, _crop(DIR + "Dressers.png", row, 3.0))
	# Part 系大块（地毯候选）
	for name in ["Part 1 copiar.png", "Part 9 copiar.png", "Part 11 copiar.png"]:
		var img := _img(DIR + name)
		print("\n=== %s 大块 ===" % name)
		for r in _big(img).slice(0, 24):
			print("  Rect2i(%d, %d, %d, %d)" % [r.position.x, r.position.y, r.size.x, r.size.y])
			_put(sheet, _zoom_region(img, r, 2.0))
	sheet.save_png("res://tools/deco_check3.png")
	print("[SAVED] res://tools/deco_check3.png")
	get_tree().quit()

func _put(sheet: Image, thumb: Image) -> void:
	if _x + thumb.get_width() + 8 > sheet.get_width():
		_x = 8
		_y += _rowh + 12
		_rowh = 0
	if _y + thumb.get_height() + 8 > sheet.get_height():
		print("[警告] 画布不够，跳过 (%dx%d)" % [thumb.get_width(), thumb.get_height()])
		return
	sheet.blend_rect(thumb, Rect2i(0, 0, thumb.get_width(), thumb.get_height()), Vector2i(_x, _y))
	_x += thumb.get_width() + 12
	_rowh = maxi(_rowh, thumb.get_height())

func _img(path: String) -> Image:
	var tex := load(path) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img

func _crop(path: String, region: Rect2i, sc: float) -> Image:
	var c := _img(path).get_region(region)
	c.resize(int(c.get_width() * sc), int(c.get_height() * sc), Image.INTERPOLATE_NEAREST)
	return c

func _zoom(path: String, sc: float) -> Image:
	var img := _img(path)
	return _zoom_region(img, Rect2i(Vector2i.ZERO, img.get_size()), sc)

func _zoom_region(img: Image, region: Rect2i, sc: float) -> Image:
	var c := img.get_region(region)
	c.resize(int(c.get_width() * sc), int(c.get_height() * sc), Image.INTERPOLATE_NEAREST)
	return c

func _big(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var out := []
	for yy in h:
		for xx in w:
			if seen.has(Vector2i(xx, yy)) or img.get_pixel(xx, yy).a <= 0.05:
				continue
			var mn := Vector2i(xx, yy)
			var mx := Vector2i(xx, yy)
			var n := 0
			var stack := [Vector2i(xx, yy)]
			seen[Vector2i(xx, yy)] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				n += 1
				mn = Vector2i(mini(mn.x, p.x), mini(mn.y, p.y))
				mx = Vector2i(maxi(mx.x, p.x), maxi(mx.y, p.y))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen.has(q):
						continue
					if img.get_pixel(q.x, q.y).a > 0.05:
						seen[q] = true
						stack.push_back(q)
			if mx.x - mn.x >= 23 and mx.y - mn.y >= 15:
				out.append(Rect2i(mn, mx - mn + Vector2i(1, 1)))
	out.sort_custom(func(a, b):
		return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	return out
