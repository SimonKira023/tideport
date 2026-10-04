# floor_icon.gd —— 运行时程序化生成「木地板 / 鹅卵石小径」道具的 32x32 图标。
#
# wood_floor.tres / stone_path.tres 没法直接 inline 一张程序化图，所以这里统一在 autoload 启动时
# 各生成一个 ImageTexture，挂到对应 ItemData 的 icon 字段上。
# （Texture 资源在加载时是 null；运行时再改 ItemData.icon 一样能让背包/快捷栏显示。）
extends Node

const FLOOR_ICON_PATH := "res://item/wood_floor.tres"
const PATH_ICON_PATH := "res://item/stone_path.tres"

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