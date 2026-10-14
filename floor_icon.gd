# floor_icon.gd —— 运行时程序化生成「木地板 / 鹅卵石小径」道具的 32x32 图标。
#
# wood_floor.tres / stone_path.tres 没法直接 inline 一张程序化图，所以这里统一在 autoload 启动时
# 各生成一个 ImageTexture，挂到对应 ItemData 的 icon 字段上。
# （Texture 资源在加载时是 null；运行时再改 ItemData.icon 一样能让背包/快捷栏显示。）
extends Node

const FLOOR_ICON_PATH := "res://item/wood_floor.tres"
const PATH_ICON_PATH := "res://item/stone_path.tres"
# 2026-10-06 城镇铺装三件套的图标（同样运行时生成）
const SLAB_ICON_PATH := "res://item/slab_path.tres"
const BRICK_ICON_PATH := "res://item/brick_path.tres"
const GRAVEL_ICON_PATH := "res://item/gravel_path.tres"
# 2026-10-06 面包房/织造坊的产物图标（同样是运行时生成，避免依赖第三方素材）
const BREAD_ICON_PATH := "res://item/bread.tres"
const CLOTH_ICON_PATH := "res://item/cloth.tres"

func _ready() -> void:
	var item: ItemData = load(FLOOR_ICON_PATH)
	if item == null:
		push_warning("找不到 wood_floor.tres, 木地板图标没有生成")
	else:
		item.icon = _make_floor_icon()
	var path_item: ItemData = load(PATH_ICON_PATH)
	if path_item == null:
		push_warning("找不到 stone_path.tres, 小径图标没有生成")
	else:
		path_item.icon = _make_path_icon()
	_icon_to(SLAB_ICON_PATH, _make_slab_icon())
	_icon_to(BRICK_ICON_PATH, _make_brick_icon())
	_icon_to(GRAVEL_ICON_PATH, _make_gravel_icon())
	_icon_to(BREAD_ICON_PATH, _make_bread_icon())
	_icon_to(CLOTH_ICON_PATH, _make_cloth_icon())

# 把生成好的图标挂到某个 ItemData 上（找不到资源只警告，不炸）
func _icon_to(path: String, tex: ImageTexture) -> void:
	var it: ItemData = load(path)
	if it == null:
		push_warning("找不到 %s, 图标没有生成" % path)
		return
	it.icon = tex

# 32x32 木地板小图：e30k 跟地图上的新板条风统一 —— 四条 8px 高的横板，端缝错开
func _make_floor_icon() -> ImageTexture:
	const TS := 32
	var fill := Color8(180, 132, 80)
	var rim := Color8(102, 64, 32)
	var hl := Color8(204, 158, 100)
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	# 四条横板，相邻板色差一点，拼出「一块一块」的板条感
	var joints := [20, 6, 24, 10]
	for r in 4:
		var row := fill.lightened(0.05) if r % 2 == 0 else fill.darkened(0.07)
		img.fill_rect(Rect2i(0, r * 8, TS, 8), row)
	# 板间通缝 + 每板一道竖端缝（四条错开）+ 端缝旁一枚钉头
	for r in range(1, 4):
		img.fill_rect(Rect2i(0, r * 8, TS, 1), rim)
	for r in 4:
		var jx: int = joints[r]
		img.fill_rect(Rect2i(jx, r * 8, 1, 8), rim)
		img.set_pixel(mini(jx + 2, TS - 2), r * 8 + 2, rim)
		# 板内木纹：两段断续亮线
		for seg: Array in [[2, 8], [jx + 2, 8]]:
			var x0: int = seg[0]
			var ly := r * 8 + 4
			for x in range(x0, mini(x0 + int(seg[1]), TS)):
				if not img.get_pixel(x, ly).is_equal_approx(rim):
					img.set_pixel(x, ly, hl)
	# 四条边各画一道暗边（这样跟背包其他图标风格统一）
	for i in TS:
		img.set_pixel(0, i, rim)
		img.set_pixel(TS - 1, i, rim)
		img.set_pixel(i, 0, rim)
		img.set_pixel(i, TS - 1, rim)
	return ImageTexture.create_from_image(img)

# 32x32 鹅卵石小径小图：e30k 跟地图上的新画法统一 —— 三颗又圆又大的鹅卵石
# 嵌在夯土底上, 哑光上浅下暗, 不再是满地小碎点
func _make_path_icon() -> ImageTexture:
	const TS := 32
	var base := Color8(122, 116, 104)      # 夯土底（比石头暗一档的暖土灰）
	var rim := Color8(78, 74, 68)          # 边框
	var stone_a := Color8(196, 192, 182)   # 亮鹅卵石
	var stone_m := Color8(164, 160, 150)   # 中间调
	var stone_b := Color8(132, 128, 120)   # 暗鹅卵石
	var stone_dk := Color8(88, 84, 78)     # 石头下沿暗圈
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for i in TS:
		img.set_pixel(0, i, rim)
		img.set_pixel(TS - 1, i, rim)
		img.set_pixel(i, 0, rim)
		img.set_pixel(i, TS - 1, rim)
	# 三颗大圆石（圆心手工排布, 半径 5-8, 占满画面）
	var stones := [
		[10, 10, 7, 6], [23, 9, 6, 5], [16, 23, 8, 6],
	]
	var cols := [stone_a, stone_m, stone_b]
	for si in stones.size():
		var s: Array = stones[si]
		var cx: int = s[0]
		var cy: int = s[1]
		var rx: int = s[2]
		var ry: int = s[3]
		var col: Color = cols[si]
		# 落影（右下偏移的椭圆暗斑）
		for y in range(cy - ry, cy + ry + 3):
			for x in range(cx - rx, cx + rx + 3):
				if x <= 0 or x >= TS - 1 or y <= 0 or y >= TS - 1:
					continue
				var dxs := float(x - cx - 1) / float(rx + 1)
				var dys := float(y - cy - 2) / float(ry)
				if dxs * dxs + dys * dys <= 1.0:
					img.set_pixel(x, y, Color(30, 34, 22, 110))
		# 石身：哑光上浅下暗 + 底缘压一圈暗边（跟地图上的石头同一套明暗逻辑）
		for y in range(cy - ry, cy + ry + 1):
			for x in range(cx - rx, cx + rx + 1):
				if x <= 0 or x >= TS - 1 or y <= 0 or y >= TS - 1:
					continue
				var dx := float(x - cx) / float(rx)
				var dy := float(y - cy) / float(ry)
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					var c := col
					if dy < -0.35:
						c = col.lerp(Color8(224, 220, 212), 0.4)
					elif dy > 0.45:
						c = col.lerp(stone_dk, 0.5)
					if d2 > 0.86 and dy > 0.0:
						c = c.lerp(stone_dk, 0.4)
					img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# 32x32 石板路小图：一块大石板压在深缝底上，上沿亮、下沿暗，面上开两个小坑
func _make_slab_icon() -> ImageTexture:
	const TS := 32
	var gap := Color8(70, 78, 68)          # 石板之间的缝（图标用不透明版，轮廓才清楚）
	var base := Color8(166, 168, 162)      # 石板中档
	var hi := Color8(206, 208, 202)        # 上沿亮阶
	var dk := Color8(104, 108, 102)        # 下沿暗阶
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(gap)
	# 一块大石板：四周留 3px 缝
	var l := 3
	var t := 3
	var r := TS - 4
	var b := TS - 4
	img.fill_rect(Rect2i(l, t, r - l + 1, b - t + 1), base)
	for x in range(l, r + 1):
		img.set_pixel(x, t, base.lerp(hi, 0.5))
		img.set_pixel(x, b, base.lerp(dk, 0.55))
	for y in range(t, b + 1):
		img.set_pixel(l, y, base.lerp(hi, 0.24))
		img.set_pixel(r, y, base.lerp(dk, 0.34))
	# 石面上两个小坑
	img.set_pixel(11, 12, base.lerp(dk, 0.5))
	img.set_pixel(12, 12, base.lerp(dk, 0.28))
	img.set_pixel(21, 20, base.lerp(dk, 0.45))
	return ImageTexture.create_from_image(img)

# 32x32 红砖路小图：5 行错缝红砖（跟地图上同一套配色）
func _make_brick_icon() -> ImageTexture:
	const TS := 32
	var mortar := Color8(94, 66, 54)
	var bricks := [Color8(178, 88, 62), Color8(158, 74, 52), Color8(198, 108, 76)]
	var hi := Color8(216, 136, 100)
	var dk := Color8(112, 52, 38)
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(mortar)
	var rh := 6                       # 每行 6px（最下一行裁到 2px 收尾）
	var bw := 16
	for r in 5:
		var y0 := r * rh
		var off := 0 if r % 2 == 0 else -bw / 2
		var x := off
		var bi := 0
		while x < TS:
			var bx: int = maxi(0, x)
			var bwv: int = mini(bw, TS - bx)
			if x < 0:
				bwv = bw + x
			if bwv > 0:
				var col: Color = bricks[bi % 3]
				var y_end: int = mini(y0 + rh - 1, TS)
				for y in range(y0 + 1, y_end):
					for px in range(bx, bx + bwv - 1):
						img.set_pixel(px, y, col)
				if y0 + 1 < TS:
					for px in range(bx, bx + bwv - 1):
						img.set_pixel(px, y0 + 1, col.lerp(hi, 0.42))
				if y_end - 1 > y0:
					for px in range(bx, bx + bwv - 1):
						img.set_pixel(px, y_end - 1, col.lerp(dk, 0.45))
			x += bw
			bi += 1
	return ImageTexture.create_from_image(img)

# 32x32 砾石路小图：夯土底 + 满地小石子（跟地图上的砾石同一套配色）
func _make_gravel_icon() -> ImageTexture:
	const TS := 32
	var ground := Color8(122, 116, 104)   # 夯土底（图标用不透明底，看得清）
	var rim := Color8(78, 74, 68)
	var a := Color8(182, 174, 152)
	var b := Color8(152, 146, 128)
	var dk := Color8(110, 106, 94)
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6772
	for i in 64:
		var px := rng.randi_range(2, TS - 3)
		var py := rng.randi_range(2, TS - 3)
		var col := a if rng.randi_range(0, 1) == 0 else b
		img.set_pixel(px, py, col)
		if rng.randi_range(0, 1) == 0:
			img.set_pixel(px + 1, py, col.lerp(dk, 0.3))
		if rng.randi_range(0, 2) == 0:
			img.set_pixel(px, py + 1, col.lerp(dk, 0.55))
	for i in TS:
		img.set_pixel(0, i, rim)
		img.set_pixel(TS - 1, i, rim)
		img.set_pixel(i, 0, rim)
		img.set_pixel(i, TS - 1, rim)
	return ImageTexture.create_from_image(img)

# 32x32 面包图标：一枚椭圆面包，顶面烤色深、划三道刀口，底缘压暗
func _make_bread_icon() -> ImageTexture:
	const TS := 32
	var crust := Color8(196, 138, 74)     # 面包皮（金棕）
	var top := Color8(228, 176, 104)      # 顶面受光
	var dk := Color8(146, 96, 48)         # 底缘暗
	var cut := Color8(240, 208, 150)      # 刀口露出的浅瓤
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := 16
	var cy := 17
	var rx := 12
	var ry := 8
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx := float(x - cx) / float(rx)
			var dy := float(y - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				var col := crust
				if dy < -0.3:
					col = crust.lerp(top, 0.55)
				elif dy > 0.45:
					col = crust.lerp(dk, 0.6)
				img.set_pixel(x, y, col)
	# 三道斜刀口
	for k in 3:
		var x0 := 9 + k * 5
		for t in 6:
			img.set_pixel(clampi(x0 + t, 1, TS - 2), clampi(13 + t, 1, TS - 2), cut)
			img.set_pixel(clampi(x0 + t + 1, 1, TS - 2), clampi(13 + t, 1, TS - 2), cut.lerp(crust, 0.3))
	return ImageTexture.create_from_image(img)

# 32x32 布匹图标：一叠折起来的布，横向折纹 + 四周压边 + 左侧厚度
func _make_cloth_icon() -> ImageTexture:
	const TS := 32
	var face := Color8(126, 158, 190)     # 布面（海蓝）
	var hi := Color8(168, 196, 220)       # 受光折边
	var dk := Color8(84, 112, 144)        # 背光折谷
	var rim := Color8(58, 80, 106)
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(5, 7, 22, 18), face)
	for i in 6:
		var y := 8 + i * 3
		if i % 2 == 0:
			img.fill_rect(Rect2i(5, y, 22, 1), hi)
		else:
			img.fill_rect(Rect2i(5, y, 22, 1), dk)
	img.fill_rect(Rect2i(5, 7, 22, 1), rim)
	img.fill_rect(Rect2i(5, 24, 22, 1), rim)
	img.fill_rect(Rect2i(5, 7, 1, 18), rim)
	img.fill_rect(Rect2i(26, 7, 1, 18), rim)
	img.fill_rect(Rect2i(5, 7, 2, 18), face.lerp(hi, 0.5))
	return ImageTexture.create_from_image(img)