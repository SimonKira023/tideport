extends Node
# 一次性工具 2：整图集缩略 + 16px 网格（粗选坐标用），同时打印候选图集的
# 全部连通域精确 Rect（与缩略图交叉对照）。输出 res://tools/deco_check2.png。

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"

# [文件名, 缩放]；打印区域清单的图集放 PRINT 里
const SHEETS := [
	["Doors, windows and curtains.png", 2.5],
	["Others.png", 3.0],
	["Chairs.png", 2.0],
	["Dressers.png", 3.0],
	["cats furniture.png", 0.0],   # 0 = 自动缩到宽<=560
	["Part 1 copiar.png", 0.0],
	["Part 2 copiar.png", 0.0],
	["Part 9 copiar.png", 0.0],
	["Part 10 copiar.png", 0.0],
	["Part 11 copiar.png", 0.0],
	["candle.png", 3.0],
	["Candle 1.png", 3.0],
	["Candle 2.png", 3.0],
	["Candle 3.png", 3.0],
	["Candle 4.png", 3.0],
	["Candle 5.png", 3.0],
	["Candle 6.png", 3.0],
]
const PRINT := [
	"Doors, windows and curtains.png",
	"Others.png",
	"Chairs.png",
	"Dressers.png",
	"cats furniture.png",
]

func _ready() -> void:
	var x := 8
	var y := 8
	var rowh := 0
	var sheet := Image.create_empty(1200, 4200, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.16, 0.16, 0.2))
	for s in SHEETS:
		var tex := load(DIR + s[0]) as Texture2D
		if tex == null:
			print("[缺图] ", s[0])
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		if PRINT.has(s[0]):
			print("\n=== %s ===" % s[0])
			_dump(img)
		var sc: float = s[1]
		if sc <= 0.0:
			sc = minf(560.0 / img.get_width(), 560.0 / img.get_height())
			sc = clampf(sc, 0.5, 4.0)
		var thumb := img.duplicate() as Image
		thumb.resize(int(img.get_width() * sc), int(img.get_height() * sc), Image.INTERPOLATE_NEAREST)
		_grid(thumb, sc)
		if x + thumb.get_width() + 8 > sheet.get_width():
			x = 8
			y += rowh + 16
			rowh = 0
		if y + thumb.get_height() + 8 > sheet.get_height():
			print("[警告] 画布不够高，跳过 ", s[0])
			continue
		sheet.blend_rect(thumb, Rect2i(0, 0, thumb.get_width(), thumb.get_height()), Vector2i(x, y))
		print("[放] %s @(%d,%d) 缩放x%.2f" % [s[0], x, y, sc])
		x += thumb.get_width() + 14
		rowh = maxi(rowh, thumb.get_height())
	sheet.save_png("res://tools/deco_check2.png")
	print("[SAVED] res://tools/deco_check2.png")
	get_tree().quit()

# 在缩略图上叠 16px 网格（原图坐标）：普通格淡白、64px 大格淡黄
func _grid(img: Image, sc: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var step := int(16 * sc)
	for gx in range(0, w, step):
		var big := int(gx / sc) % 64 == 0
		for gy in h:
			img.set_pixel(gx, gy, Color(1, 1, 0.4, 0.35) if big else Color(1, 1, 1, 0.12))
	for gy in range(0, h, step):
		var big := int(gy / sc) % 64 == 0
		for gx in w:
			img.set_pixel(gx, gy, Color(1, 1, 0.4, 0.35) if big else Color(1, 1, 1, 0.12))

func _dump(img: Image) -> void:
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
			if mx.x - mn.x >= 2 and mx.y - mn.y >= 2 and n >= 4:
				out.append(Rect2i(mn, mx - mn + Vector2i(1, 1)))
	out.sort_custom(func(a, b):
		return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	for r in out:
		print("  Rect2i(%d, %d, %d, %d)" % [r.position.x, r.position.y, r.size.x, r.size.y])
	print("  (共 %d 个区域)" % out.size())
