extends Node
# 探针: 1) 打印 Fireplace/Chairs/candle 连通域  2) 按规划摆一张 mock 房间渲染成 png 预览
const BASE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/"

func _ready() -> void:
	var fire_regions := _components(BASE + "Fireplace.png", 40)
	var chair_regions := _components(BASE + "Chairs.png", 30)
	var candle_regions := _components(BASE + "candle.png", 8)
	_print_regions("Fireplace", fire_regions)
	_print_regions("Chairs", chair_regions)
	_print_regions("candle", candle_regions)
	_mock(fire_regions, chair_regions, candle_regions)
	get_tree().quit()

func _components(path: String, min_area: int) -> Array[Rect2i]:
	var tex: Texture2D = load(path)
	if tex == null:
		push_error("加载失败 " + path)
		return []
	var img := tex.get_image()
	img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var visited := {}
	var out: Array[Rect2i] = []
	for y in h:
		for x in w:
			var key := Vector2i(x, y)
			if visited.has(key):
				continue
			visited[key] = true
			if img.get_pixel(x, y).a <= 0.05:
				continue
			var queue: Array[Vector2i] = [key]
			var minx := x
			var maxx := x
			var miny := y
			var maxy := y
			var area := 0
			while queue.size() > 0:
				var p: Vector2i = queue.pop_back()
				area += 1
				minx = mini(minx, p.x)
				maxx = maxi(maxx, p.x)
				miny = mini(miny, p.y)
				maxy = maxi(maxy, p.y)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
						continue
					if visited.has(q):
						continue
					visited[q] = true
					if img.get_pixel(q.x, q.y).a > 0.05:
						queue.append(q)
			if area >= min_area:
				out.append(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))
	return out

func _print_regions(name_: String, regions: Array[Rect2i]) -> void:
	for i in regions.size():
		var r := regions[i]
		print("%s #%d (%d,%d,%d,%d)" % [name_, i, r.position.x, r.position.y, r.size.x, r.size.y])

func _pick_largest(regions: Array[Rect2i]) -> Rect2i:
	var best := Rect2i()
	for r in regions:
		if r.get_area() > best.get_area():
			best = r
	return best

func _pick_chair(regions: Array[Rect2i]) -> Rect2i:
	var best := Rect2i()
	for r in regions:
		if r.size.x <= 22 and r.size.y <= 26 and r.get_area() > best.get_area():
			best = r
	return best

func _pick_candle(regions: Array[Rect2i]) -> Rect2i:
	var best := Rect2i()
	for r in regions:
		if r.size.x <= 12 and r.size.y <= 20 and r.get_area() > best.get_area():
			best = r
	return best

func _put(dst: Image, path: String, region: Rect2i, pos: Vector2i) -> void:
	var tex: Texture2D = load(path)
	if tex == null:
		push_error("加载失败 " + path)
		return
	var src := tex.get_image()
	src.decompress()
	dst.blend_rect(src, region, pos)

func _mock(fire_regions: Array[Rect2i], chair_regions: Array[Rect2i], candle_regions: Array[Rect2i]) -> void:
	var fire := _pick_largest(fire_regions)
	var chair := _pick_chair(chair_regions)
	var candle := _pick_candle(candle_regions)
	var img := Image.create_empty(288, 192, false, Image.FORMAT_RGBA8)
	img.fill(Color8(138, 54, 37))
	img.fill_rect(Rect2i(16, 32, 256, 144), Color8(217, 168, 138))
	# 地毯(最底层)
	_put(img, BASE + "Part 11 copiar.png", Rect2i(4, 165, 70, 40), Vector2i(104, 100))
	# 底墙一排: 沙发 / 钢琴 / 书柜
	_put(img, BASE + "Sofa and armchair.png", Rect2i(2, 11, 29, 20), Vector2i(36, 140))
	_put(img, BASE + "Others.png", Rect2i(66, 91, 29, 20), Vector2i(196, 146))
	_put(img, BASE + "Others.png", Rect2i(81, 48, 30, 32), Vector2i(238, 138))
	# 左墙: 抽屉桌 + 椅子
	_put(img, BASE + "Tables and desks.png", Rect2i(225, 225, 63, 30), Vector2i(20, 84))
	if chair.size.x > 0:
		_put(img, BASE + "Chairs.png", chair, Vector2i(46, 114))
	# 顶墙一排: 床头柜 / 衣柜 / 窗 / 立镜 / 壁炉 / 床
	_put(img, BASE + "Dressers.png", Rect2i(2, 130, 27, 14), Vector2i(54, 44))
	_put(img, BASE + "Closet.png", Rect2i(69, 8, 35, 38), Vector2i(86, 2))
	_put(img, BASE + "Doors, windows and curtains.png", Rect2i(7, 163, 33, 24), Vector2i(128, 6))
	_put(img, BASE + "Others.png", Rect2i(1, 7, 14, 25), Vector2i(166, 8))
	if fire.size.x > 0:
		_put(img, BASE + "Fireplace.png", fire, Vector2i(206, 0))
	_put(img, BASE + "Beds.png", Rect2i(7, 269, 33, 34), Vector2i(16, 32))
	# 扶手椅在地毯右侧
	_put(img, BASE + "Sofa and armchair.png", Rect2i(1, 66, 13, 29), Vector2i(216, 112))
	if candle.size.x > 0:
		_put(img, BASE + "candle.png", candle, Vector2i(62, 30))
	img.resize(576, 384, Image.INTERPOLATE_NEAREST)
	img.save_png("res://tools/mock_room.png")
	print("saved mock_room.png fire=%s chair=%s candle=%s" % [fire, chair, candle])
