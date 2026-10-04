extends SceneTree
# tools/make_boat.gd —— 木船贴图生成器（纯 GDScript；系统没装 PIL，替代 _make_boat.py）
#   e40: 加帆 + 美化船体 —— 配色照封面上的小帆船（珊瑚船体 / 米白船缘与帆 / 木桅杆 / 珊瑚小旗）
# 产物（resources/texture/）:
#   boat.png       32x44  带帆帆船 —— 大地图船队用（上半 26 行 = 桅杆+主帆+前帆+小旗，
#                         下半 = 船身）。越靠上的行画在越后面，船头尖朝右。
#   boat_hull.png  32x20  只画船身（不挂帆）—— 码头停泊 / 大陆栈桥 / 出海动画 / 海上队伍用：
#                         这些地方船挨得近（行距 15~22px）或船上有真人，挂帆会互相压、挡脑袋，
#                         停泊时「收帆」在设定上也自洽。
#   boat_icon.png  16x16  道具 / 科技树图标（小帆船）
#   boat_preview.png      预览板（放大看细节，不参与游戏）
# 运行: Godot_console.exe --headless --path . -s res://tools/make_boat.gd

const OUT_DIR := "res://resources/texture"

# ---------- 调色（与 tools/make_cover.gd 封面小帆船同一份色号） ----------
const HULL := Color8(216, 124, 96)        # 珊瑚船帮
const HULL_DIM := Color8(170, 92, 72)     # 船帮背光面（光源左上）
const WALL := Color8(250, 242, 224)       # 米白船缘（吃水线那道白条）
const MAST := Color8(150, 112, 78)        # 木桅杆
const MAST_DIM := Color8(122, 90, 62)
const SAIL := Color8(252, 248, 238)       # 主帆
const SAIL_DIM := Color8(230, 222, 204)   # 前帆（背光）
const FLAG := Color8(204, 112, 92)        # 珊瑚小旗
const FLAG_DIM := Color8(168, 84, 68)
const DECK := Color8(196, 156, 112)       # 木甲板
const DECK_SH := Color8(166, 126, 86)     # 甲板板缝 / 内侧阴影

# 船身轮廓表（顶视角 32x20：**船尾平、船头尖**朝右）—— 按**列**写。
# ❗按列写才画得出真船形：按行写的表两头一起收, 从上往下看就是一枚眼睛/面包,
#   看不出船头在哪（早期版本就是那样, 停泊时一排「面包」）。现在:
#   船尾 x=0 是一道竖直的平艉（transom）x=1..3 迅速鼓到满宽,
#   船头 x=16 起一路收到 x=31 只剩两格 —— 细长的尖船首。
#   值 = 那一列船的上下边界 [y0, y1]。
const HULL_COLS := {
	0: [5, 14], 1: [3, 16], 2: [2, 17], 3: [2, 17],
	4: [1, 18], 5: [1, 18], 6: [1, 18], 7: [1, 18], 8: [1, 18],
	9: [1, 18], 10: [1, 18], 11: [1, 18], 12: [1, 18], 13: [1, 18],
	14: [1, 18], 15: [1, 18], 16: [2, 17], 17: [2, 17],
	18: [3, 16], 19: [3, 16], 20: [4, 15], 21: [4, 15],
	22: [5, 14], 23: [5, 14], 24: [6, 13], 25: [6, 13],
	26: [7, 12], 27: [7, 12], 28: [8, 11], 29: [8, 11],
	30: [9, 10], 31: [9, 10],
}
# 三道色带全部由轮廓「腐蚀」推出来（见 _erode）：珊瑚船帮 + 米白船缘 + 木甲板。
# 手写一张甲板表会跟船帮对不齐 —— 旧图就是这么来的：左边船帮 5px、右边 1px，一边厚一边薄。
# ❗船帮只留 1px：2px 的时候 32x20 的船看着像「桃子/面包」，船缘和甲板都被挤没了。
const CORAL_RING := 1
const CREAM_RING := 1
# ❗带帆那张的下移量：船身画在 25~42 行。配 Sprite2D offset(0,-14)（图高 44）后
#   绘制矩形 = position + offset - size/2 = position - (16,36)，
#   船身落在与旧 32x20 贴图**几乎逐像素一样**的位置上（差 1px）——
#   换图不会让船/船员相对位置漂移。
const HULL_Y := 24
const W := 32
const H_W := 44
const HULL_H := 20

# ---------------- 工具 ----------------
func P(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


# 把一坨 cells 往里收 rounds 圈（8 邻域：斜角也算，收出来的边才跟着船形走不会起毛刺）
func _erode(m: Dictionary, rounds: int) -> Dictionary:
	var cur := m
	for _i in rounds:
		var out := {}
		for k in cur.keys():
			var c: Vector2i = k
			var ok := true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if not cur.has(c + Vector2i(dx, dy)):
						ok = false
						break
				if not ok:
					break
			if ok:
				out[c] = true
		cur = out
	return cur


func _masks() -> Dictionary:
	var hull := {}
	for x in HULL_COLS.keys():
		var v: Array = HULL_COLS[x]
		for y in range(int(v[0]), int(v[1]) + 1):
			hull[Vector2i(int(x), y)] = true
	return hull


# ---------------- 船身：珊瑚船帮 + 米白船缘 + 木甲板 ----------------
func _paint_hull(img: Image, y_off: int) -> void:
	var hull := _masks()
	var cream_in := _erode(hull, CORAL_RING)          # 船帮内沿
	var deck := _erode(hull, CORAL_RING + CREAM_RING)  # 甲板（船缘以内）
	for c in hull.keys():
		var v: Vector2i = c
		if cream_in.has(v):
			continue
		P(img, v.x, y_off + v.y, HULL_DIM if v.y >= 10 else HULL)
	for c in cream_in.keys():
		var v: Vector2i = c
		if not deck.has(v):
			P(img, v.x, y_off + v.y, WALL)
	for c in deck.keys():
		var v: Vector2i = c
		P(img, v.x, y_off + v.y, DECK)
	# 甲板板缝（跟旧图同一组位置）+ 右舷内侧阴影（光源左上）
	var right := {}
	for c in deck.keys():
		var v: Vector2i = c
		if x_seam(v.x):
			P(img, v.x, y_off + v.y, DECK_SH)
		var cur: int = right.get(v.y, -1)
		if v.x > cur:
			right[v.y] = v.x
	for r in right.keys():
		P(img, int(right[r]), y_off + int(r), DECK_SH)


func x_seam(x: int) -> bool:
	return x in [11, 20]


# ---------------- 桅杆 + 帆：主帆在右、前帆在左、旗在桅顶（同封面构图） ----------------
func _paint_rig(img: Image, shift: int, top: int, bottom: int) -> void:
	var mast_x := 13 + shift
	for y in range(top, bottom + 1):
		P(img, mast_x, y, MAST)
		P(img, mast_x + 1, y, MAST_DIM)
	# 主帆：竖边贴桅杆右侧，斜边从桅顶拉到帆脚右端
	var sail_top := top
	var sail_bot := top + 20
	for y in range(sail_top, sail_bot + 1):
		var w := int(round(float(y - sail_top) / float(sail_bot - sail_top) * 14.0))
		for x in range(mast_x + 2, mast_x + 3 + w):
			P(img, x, y, SAIL)
		P(img, mast_x + 3 + w, y, SAIL_DIM)      # 斜边描一档，帆形才清楚
	for x in range(mast_x + 2, mast_x + 17):
		P(img, x, sail_bot, SAIL_DIM)            # 帆脚
	# 前帆：桅杆左侧的小三角（背光, 用暗一档的米白）
	var jib_top := top + 6
	for y in range(jib_top, sail_bot + 1):
		var w := int(round(float(y - jib_top) / float(sail_bot - jib_top) * 10.0))
		for x in range(mast_x - 1 - w, mast_x):
			P(img, x, y, SAIL_DIM)
	# 珊瑚小旗（桅顶往右飘）
	for x in range(mast_x, mast_x + 8):
		P(img, x, top - 2, FLAG)
	for x in range(mast_x, mast_x + 6):
		P(img, x, top - 1, FLAG)
	for x in range(mast_x, mast_x + 3):
		P(img, x, top, FLAG_DIM)


func _boat_full() -> Image:
	var img := Image.create_empty(W, H_W, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_paint_rig(img, 0, 4, 26)          # 桅杆从第 4 行立到第 26 行（脚下扎进甲板）
	_paint_hull(img, HULL_Y)
	return img


func _boat_hull() -> Image:
	var img := Image.create_empty(W, HULL_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_paint_hull(img, 0)
	return img


# ---------------- 图标 16x16：小帆船 ----------------
# ❗图标不铺米白船缘、帆的斜边和帆脚一律描深色（MAST_DIM）—— 米白帆碰到
#   技能树的金卡 / 背包的浅底就糊成一团白，16px 的图标必须自己带边。
#   （大地图那张反而不能描边：背景是海，描了会显脏。）
func _icon() -> Image:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mast_x := 7
	for y in range(1, 12):
		P(img, mast_x, y, MAST)
		if y >= 3:
			P(img, mast_x + 1, y, MAST_DIM)
	# 珊瑚小旗（桅顶往右飘）
	for x in range(mast_x, mast_x + 4):
		P(img, x, 0, FLAG)
	for x in range(mast_x, mast_x + 3):
		P(img, x, 1, FLAG_DIM)
	# 主帆：竖边贴桅杆，斜边拉到帆脚右端
	for y in range(3, 10):
		var w := int(round(float(y - 3) / 6.0 * 5.0))
		for x in range(mast_x + 1, mast_x + 2 + w):
			P(img, x, y, SAIL)
		P(img, mast_x + 2 + w, y, MAST_DIM)
	for x in range(mast_x + 1, mast_x + 8):
		P(img, x, 10, MAST_DIM)
	# 前帆：桅杆左侧的背光小三角
	for y in range(4, 10):
		var w := int(round(float(y - 4) / 5.0 * 3.0))
		for x in range(mast_x - 1 - w, mast_x):
			P(img, x, y, SAIL_DIM)
		P(img, mast_x - 2 - w, y, MAST_DIM)
	for x in range(mast_x - 5, mast_x):
		P(img, x, 10, MAST_DIM)
	P(img, mast_x, 10, MAST)
	# 船身：珊瑚船帮 + 木甲板 + 深色船底
	for x in range(2, 14):
		P(img, x, 11, HULL)
	for x in range(3, 13):
		P(img, x, 12, DECK)
		P(img, x, 13, HULL_DIM)
	P(img, 2, 12, HULL)
	P(img, 13, 12, HULL)
	return img


# ---------------- 预览板 ----------------
func _preview(full: Image, hull: Image, icon: Image) -> Image:
	var img := Image.create_empty(320, 210, false, Image.FORMAT_RGBA8)
	for y in 210:
		var t := float(y) / 209.0
		img.fill_rect(Rect2i(0, y, 320, 1),
			Color(0.55, 0.80, 0.82).lerp(Color(0.10, 0.34, 0.44), t))
	_paste(img, full, 12, 16, 4)
	_paste(img, hull, 155, 16, 4)
	# 图标垫一块金色底板 —— 技能树的金卡就是这颜色, 顺带验一下描边够不够
	img.fill_rect(Rect2i(158, 112, 84, 84), Color8(190, 158, 74))
	_paste(img, icon, 160, 114, 5)
	return img


func _paste(dst: Image, src: Image, dx: int, dy: int, k: int) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			for oy in k:
				for ox in k:
					P(dst, dx + x * k + ox, dy + y * k + oy, c)


func _save(img: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err := img.save_png(path)
	print("[船] ", name, " ", img.get_width(), "x", img.get_height(),
		" -> ", path, " err=", err)


func _initialize() -> void:
	var full := _boat_full()
	var hull := _boat_hull()
	var icon := _icon()
	_save(full, "boat.png")
	_save(hull, "boat_hull.png")
	_save(icon, "boat_icon.png")
	_save(_preview(full, hull, icon), "boat_preview.png")
	print("[船] 好了（珊瑚船帮 + 米白船缘 / 主帆前帆 + 木桅杆 + 珊瑚小旗，同封面风格）")
	quit(0)