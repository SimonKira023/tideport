extends Node
# 一次性工具：扫描内饰图集，用连通域分析输出每个不透明精灵的包围盒，
# 供家具 region 裁剪选区用（只读图 + 打印，跑完即退）。

const ATLASES := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Fireplace.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Tables and desks.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Chairs.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Closet.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Dressers.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Others.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Sofa and armchair.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/cats furniture.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Doors, windows and curtains.png",
]

func _ready() -> void:
	for path in ATLASES:
		var tex := load(path) as Texture2D
		if tex == null:
			print("[缺图] ", path)
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		print("\n=== %s  尺寸=%dx%d ===" % [path.get_file(), img.get_width(), img.get_height()])
		_regions(img)
	get_tree().quit()

func _regions(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var out := []
	for y in h:
		for x in w:
			if seen.has(Vector2i(x, y)) or img.get_pixel(x, y).a <= 0.05:
				continue
			# BFS 收集这个连通域
			var mn := Vector2i(x, y)
			var mx := Vector2i(x, y)
			var n := 0
			var stack := [Vector2i(x, y)]
			seen[Vector2i(x, y)] = true
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
			# 过滤碎点：至少 4x4 且 8 个像素以上
			if mx.x - mn.x >= 3 and mx.y - mn.y >= 3 and n >= 8:
				out.append(Rect2i(mn, mx - mn + Vector2i(1, 1)))
	out.sort_custom(func(a, b):
		return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	for r in out:
		print("  Rect2i(%d, %d, %d, %d)" % [r.position.x, r.position.y, r.size.x, r.size.y])
	print("  (共 %d 个区域)" % out.size())
