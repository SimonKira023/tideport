extends Node
# 一次性工具: Dressers / Others / Doors, windows and curtains 三图集连通域编号拼贴
# 输出 res://tools/deco_check9.png; 编号→Rect 对应关系打印在日志
const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"
const ATLASES := [
	"Dressers.png",
	"Others.png",
	"Doors, windows and curtains.png",
]
const SHEET_W := 1600
const SHEET_H := 3600
var _x := 8
var _y := 8
var _rowh := 0
var _sheet: Image
var _font := ThemeDB.fallback_font

func _ready() -> void:
	_sheet = Image.create_empty(SHEET_W, SHEET_H, false, Image.FORMAT_RGBA8)
	_sheet.fill(Color(0.16, 0.16, 0.2))
	for a in ATLASES:
		var img := _img(DIR + a)
		var rects := _big_rects(img)
		print("==== %s  大件 %d 个 ====" % [a, rects.size()])
		for i in rects.size():
			var r: Rect2i = rects[i]
			var sc := 3.0
			if r.size.x >= 40 or r.size.y >= 40:
				sc = 2.0
			var c := img.get_region(r)
			c.resize(int(c.get_width() * sc), int(c.get_height() * sc), Image.INTERPOLATE_NEAREST)
			_flow(c, str(i))
			print("  #%-3d %s" % [i, r])
	_sheet.save_png("res://tools/deco_check9.png")
	print("[SAVED] res://tools/deco_check9.png")
	get_tree().quit()

func _flow(c: Image, tag: String) -> void:
	if _x + c.get_width() + 8 > _sheet.get_width():
		_x = 8
		_y += _rowh + 14
		_rowh = 0
	if _y + c.get_height() + 22 > _sheet.get_height():
		print("  [警告] 画布满，剩余跳过")
		_y = _sheet.get_height()
		return
	_sheet.blend_rect(c, Rect2i(0, 0, c.get_width(), c.get_height()), Vector2i(_x, _y))
	_font.draw_string(_sheet, Vector2(_x, _y + c.get_height() + 12), tag,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.4))
	_x += c.get_width() + 10
	_rowh = maxi(_rowh, c.get_height())

# 连通域（4 邻接 alpha>0.05），面积>=80
func _big_rects(img: Image) -> Array[Rect2i]:
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
			var rw := maxx - minx + 1
			var rh := maxy - miny + 1
			if rw * rh >= 80:
				rects.append(Rect2i(minx, miny, rw, rh))
	rects.sort_custom(func(a, b): return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	return rects

func _img(path: String) -> Image:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("加载失败: " + path)
		return Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img
