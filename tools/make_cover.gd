extends SceneTree
# 封面生成器（纯 GDScript，系统无 Python 时替代 _make_cover.py）：重生成封面三件套
#   e39: 封面重画 —— **不画任何文字**；允许非方格/有机构图；上方留大片留白
#   构图: 左上淡青晨空(留白) + 一轮淡金晨阳 + 三抹薄云 + 远处岛影
#         右下角一座海港小镇(珊瑚屋顶/白灯塔/木栈桥) + 左下角一艘小帆船
#   笔触: SubViewport 里用多边形/圆/线自由摆放(不是 8px 方格块), 硬边不加抗锯齿
# 产物: outputs/cover_preview.png + 根目录 icon_256.png + icon.ico（多尺寸）
# 运行（SubViewport 取图要真实渲染设备，不能 --headless）:
#   Godot_console.exe --path <项目> -s res://tools/make_cover.gd

const S := 512
const HORIZON := 332

# ---------- 调色（清新向：淡青 / 薄荷 / 米黄 / 珊瑚） ----------
const SKY_TOP := Vector3i(146, 197, 209)
const SKY_MID := Vector3i(196, 226, 224)
const SKY_LOW := Vector3i(238, 240, 226)
const SKY_HOT := Vector3i(250, 231, 202)
const SEA_TOP := Vector3i(180, 220, 214)
const SEA_MID := Vector3i(88, 158, 164)
const SEA_DEEP := Vector3i(38, 96, 112)

const SUN_CORE := Vector3i(255, 240, 188)
const SUN_RIM := Vector3i(255, 222, 166)
const CLOUD := Vector3i(255, 252, 245)
const GULL := Vector3i(88, 122, 132)
const ISLAND := Vector3i(158, 196, 198)
const GLITTER := Vector3i(255, 240, 208)
const FOAM := Vector3i(240, 246, 242)
const DEPTH := Vector3i(22, 62, 78)

const GRASS := Vector3i(132, 176, 128)
const GRASS_DIM := Vector3i(104, 148, 112)
const GRASS_LIT := Vector3i(158, 198, 138)
const SAND := Vector3i(238, 224, 194)
const SAND_WET := Vector3i(212, 194, 164)
const TREE := Vector3i(66, 116, 92)
const TREE_LIT := Vector3i(92, 146, 108)
const TRUNK := Vector3i(112, 84, 60)
const WALL := Vector3i(250, 242, 224)
const WALL_DIM := Vector3i(216, 204, 184)
const ROOF := Vector3i(204, 112, 92)
const ROOF_DIM := Vector3i(168, 84, 68)
const BRICK := Vector3i(178, 118, 96)
const BRICK_DIM := Vector3i(146, 92, 74)
const WINDOW := Vector3i(58, 92, 106)
const WOOD := Vector3i(176, 140, 106)
const WOOD_DIM := Vector3i(138, 104, 76)
const POST := Vector3i(120, 90, 66)
const HULL := Vector3i(216, 124, 96)
const HULL_DIM := Vector3i(170, 92, 72)
const SAIL := Vector3i(252, 248, 238)
const SAIL_DIM := Vector3i(230, 222, 204)
const MAST := Vector3i(150, 112, 78)
const TOWER := Vector3i(250, 244, 230)
const TOWER_BAND := Vector3i(206, 122, 100)
const LAMP := Vector3i(255, 226, 158)
const DARK := Vector3i(58, 84, 96)

# 岬角外轮廓（顺时针）：左上角是尖角，右下贴着海面，底边是岸线
var LAND := PackedVector2Array([
	Vector2(512, 322), Vector2(478, 314), Vector2(444, 308), Vector2(408, 309),
	Vector2(370, 318), Vector2(332, 334), Vector2(298, 356), Vector2(268, 378),
	Vector2(246, 400), Vector2(266, 418), Vector2(300, 430), Vector2(348, 440),
	Vector2(400, 444), Vector2(452, 440), Vector2(498, 432), Vector2(512, 428)])
# 山脊线（上边缘）/ 岸线（下边缘），都从右往左逐点
var RIDGE := PackedVector2Array([
	Vector2(512, 322), Vector2(478, 314), Vector2(444, 308), Vector2(408, 309),
	Vector2(370, 318), Vector2(332, 334), Vector2(298, 356), Vector2(268, 378),
	Vector2(246, 400)])
var SHORE := PackedVector2Array([
	Vector2(246, 400), Vector2(266, 418), Vector2(300, 430), Vector2(348, 440),
	Vector2(400, 444), Vector2(452, 440), Vector2(498, 432), Vector2(512, 428)])

var img: Image


func col(v: Vector3i, a := 255) -> Color:
	return Color8(v.x, v.y, v.z, a)


func lerp3(a: Vector3i, b: Vector3i, t: float) -> Vector3i:
	return Vector3i(
		int(round(a.x + (b.x - a.x) * t)),
		int(round(a.y + (b.y - a.y) * t)),
		int(round(a.z + (b.z - a.z) * t)))


func _initialize() -> void:
	img = Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	_paint_base()
	var base := ImageTexture.create_from_image(img)
	var shot: Image = await _raster(base)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs"))
	shot.save_png(ProjectSettings.globalize_path("res://outputs/cover_preview.png"))
	var i256: Image = shot.duplicate()
	i256.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	i256.save_png(ProjectSettings.globalize_path("res://icon_256.png"))
	_write_ico(shot, [16, 24, 32, 48, 64, 128, 256], ProjectSettings.globalize_path("res://icon.ico"))
	print("[封面] 已重生成 cover_preview.png / icon_256.png / icon.ico （无文字·非方格·上方留白）")
	quit(0)


# ---------------- 底色：天空 / 海面 两条竖向渐变（逐行填，不用方格） ----------------
func _paint_base() -> void:
	for y in range(HORIZON):
		var t: float = y / float(HORIZON - 1)
		var c: Vector3i
		if t < 0.58:
			c = lerp3(SKY_TOP, SKY_MID, t / 0.58)
		elif t < 0.86:
			c = lerp3(SKY_MID, SKY_LOW, (t - 0.58) / 0.28)
		else:
			c = lerp3(SKY_LOW, SKY_HOT, (t - 0.86) / 0.14)
		img.fill_rect(Rect2i(0, y, S, 1), col(c))
	for y in range(HORIZON, S):
		var t2: float = (y - HORIZON) / float(S - HORIZON - 1)
		var c2: Vector3i
		if t2 < 0.42:
			c2 = lerp3(SEA_TOP, SEA_MID, t2 / 0.42)
		else:
			c2 = lerp3(SEA_MID, SEA_DEEP, (t2 - 0.42) / 0.58)
		img.fill_rect(Rect2i(0, y, S, 1), col(c2))


# ---------------- 取图 ----------------
class Painter:
	extends Node2D

	var base_t: ImageTexture
	var host: Object

	func _draw() -> void:
		draw_texture_rect(base_t, Rect2(Vector2.ZERO, Vector2(512, 512)), false)
		host.draw_art(self)


func draw_art(ci: CanvasItem) -> void:
	_sky_accents(ci)
	_islands(ci)
	_waves(ci)
	_land(ci)
	_trees(ci)
	_houses(ci)
	_lighthouse(ci)
	_pier(ci)
	_sailboat(ci)
	_vignette(ci)


# ---------------- 天空：晨阳 / 薄云 / 海鸥 / 水面反光柱 ----------------
func _sky_accents(ci: CanvasItem) -> void:
	var sx := 120.0
	var sy := 108.0
	ci.draw_circle(Vector2(sx, sy), 70.0, col(SUN_RIM, 9), true, -1.0, true)
	ci.draw_circle(Vector2(sx, sy), 56.0, col(SUN_RIM, 18), true, -1.0, true)
	ci.draw_circle(Vector2(sx, sy), 44.0, col(SUN_RIM, 34), true, -1.0, true)
	ci.draw_circle(Vector2(sx, sy), 33.0, col(SUN_RIM, 90), true, -1.0, true)
	ci.draw_circle(Vector2(sx, sy), 30.0, col(SUN_CORE), true, -1.0, true)

	_cloud(ci, 40.0, 196.0, 128.0, 132)
	_cloud(ci, 150.0, 246.0, 102.0, 108)
	_cloud(ci, 244.0, 286.0, 86.0, 84)

	_gull(ci, 170.0, 148.0, 11.0)
	_gull(ci, 214.0, 130.0, 9.0)
	_gull(ci, 256.0, 166.0, 7.0)

	# 晨阳在水面的反光柱（越往下越散）
	var gl := [[340, 18], [348, 15], [358, 13], [370, 11], [384, 9], [400, 8], [420, 7], [442, 6]]
	for g in gl:
		var gy: int = g[0]
		var gw: int = g[1]
		ci.draw_rect(Rect2(sx - gw * 0.5, float(gy), float(gw), 2.0), col(GLITTER, 72))


func _cloud(ci: CanvasItem, x: float, y: float, w: float, a: int) -> void:
	var c := col(CLOUD, a)
	ci.draw_rect(Rect2(x, y, w, 5.0), c)
	for i in 3:
		ci.draw_circle(Vector2(x + w * (0.24 + float(i) * 0.26), y + 1.0), 7.0, c, true, -1.0, true)


func _gull(ci: CanvasItem, x: float, y: float, r: float) -> void:
	var c := col(GULL, 205)
	ci.draw_line(Vector2(x - r, y + r * 0.45), Vector2(x, y - r * 0.30), c, 2.0, true)
	ci.draw_line(Vector2(x, y - r * 0.30), Vector2(x + r, y + r * 0.45), c, 2.0, true)


func _islands(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(0, 334), Vector2(0, 331), Vector2(26, 320), Vector2(54, 326),
		Vector2(82, 317), Vector2(112, 325), Vector2(140, 331), Vector2(140, 334)]),
		col(ISLAND, 150))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(158, 334), Vector2(158, 330), Vector2(176, 323), Vector2(196, 328),
		Vector2(208, 332), Vector2(208, 334)]),
		col(ISLAND, 120))


# ---------------- 海面浪花（避开陆地） ----------------
func _waves(ci: CanvasItem) -> void:
	var rows := [[344, 6, 20, 70], [356, 8, 26, 78], [370, 10, 32, 84],
			[386, 12, 38, 92], [404, 14, 44, 100], [424, 16, 50, 105],
			[448, 18, 58, 108], [476, 20, 66, 108], [502, 24, 74, 108]]
	for r in rows:
		var y: int = r[0]
		var w: int = r[1]
		var step: int = r[2]
		var a: int = r[3]
		var x := float((y * 7) % step)
		while x < float(S):
			if not _in_land(x + w * 0.5, float(y)):
				ci.draw_rect(Rect2(x, float(y), float(w), 2.0), col(FOAM, a))
				if y >= 420:
					ci.draw_rect(Rect2(x + 2.0, float(y + 2), float(maxi(2, w - 4)), 2.0),
							col(DEPTH, 40))
			x += float(step)


# ---------------- 岬角：草地 + 山脊亮边 + 岸线暗边 + 沙岸湿线 ----------------
func _land(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(LAND, col(GRASS))
	ci.draw_polyline(SHORE, col(GRASS_DIM), 6.0, false)
	ci.draw_polyline(RIDGE, col(GRASS_LIT), 4.0, false)
	var sand := PackedVector2Array()
	for p in SHORE:
		sand.append(p)
	for i in range(SHORE.size() - 1, -1, -1):
		sand.append(SHORE[i] + Vector2(0, 8))
	ci.draw_colored_polygon(sand, col(SAND))
	ci.draw_polyline(SHORE, col(SAND_WET), 2.0, false)
	var wet := PackedVector2Array()
	for p in SHORE:
		wet.append(p + Vector2(0, 7))
	ci.draw_polyline(wet, col(SAND_WET), 2.0, false)
	# 草地上零星几笔亮色，破一破大片平色
	for d in [[330, 356], [356, 348], [392, 336], [420, 334], [300, 392],
			[368, 372], [440, 358], [478, 350], [268, 402], [410, 404]]:
		ci.draw_rect(Rect2(float(d[0]), float(d[1]), 6.0, 3.0), col(GRASS_LIT, 90))


# ---------------- 山坡上的柏树 ----------------
func _trees(ci: CanvasItem) -> void:
	_tree(ci, 276.0, 386.0, 28.0)
	_tree(ci, 292.0, 372.0, 24.0)
	_tree(ci, 496.0, 434.0, 20.0)


func _tree(ci: CanvasItem, x: float, ground: float, h: float) -> void:
	ci.draw_rect(Rect2(x - 1.5, ground - 4.0, 3.0, 7.0), col(TRUNK))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x - 6.0, ground), Vector2(x, ground - h),
		Vector2(x + 6.0, ground), Vector2(x + 3.0, ground - h * 0.2)]), col(TREE))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x - 6.0, ground), Vector2(x, ground - h),
		Vector2(x - 1.5, ground - h * 0.3)]), col(TREE_LIT, 170))


# ---------------- 镇上的三间小屋（沿山脊排开） ----------------
func _houses(ci: CanvasItem) -> void:
	_house(ci, 306.0, 346.0, _ridge_y(326.0) + 13.0, 0)
	_house(ci, 356.0, 392.0, _ridge_y(374.0) + 13.0, 1)
	_house(ci, 408.0, 440.0, _ridge_y(424.0) + 12.0, 2)


func _house(ci: CanvasItem, x0: float, x1: float, ground: float, tag: int) -> void:
	var w := x1 - x0
	var wall_h := 21.0 + float(tag % 2) * 2.0
	var wall_top := ground - wall_h
	var apex := Vector2((x0 + x1) * 0.5, wall_top - 13.0 - float(tag % 2) * 3.0)
	ci.draw_rect(Rect2(x0, wall_top, w, wall_h), col(WALL))
	ci.draw_rect(Rect2(x1 - 7.0, wall_top, 7.0, wall_h), col(WALL_DIM))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x0 - 5.0, wall_top), apex, Vector2(x1 + 5.0, wall_top)]), col(ROOF))
	ci.draw_colored_polygon(PackedVector2Array([
		apex, Vector2(x1 + 5.0, wall_top), Vector2(x1 - 8.0, wall_top)]), col(ROOF_DIM))
	ci.draw_rect(Rect2(x0 - 6.0, wall_top - 1.0, w + 12.0, 3.0), col(ROOF_DIM))
	var wx := x0 + 7.0 + float((tag * 5) % 11)
	ci.draw_rect(Rect2(wx, wall_top + 7.0, 7.0, 8.0), col(WINDOW))
	ci.draw_rect(Rect2(wx + 3.0, wall_top + 7.0, 1.0, 8.0), col(WALL_DIM))
	# 烟囱：从屋顶斜面上长出来（不算悬空）
	var cx := x1 - 13.0
	var roof_y := apex.y + (wall_top - apex.y) * (cx - apex.x) / maxf(1.0, x1 + 5.0 - apex.x)
	ci.draw_rect(Rect2(cx, roof_y - 15.0, 6.0, 22.0), col(BRICK))
	ci.draw_rect(Rect2(cx - 1.0, roof_y - 16.0, 8.0, 3.0), col(BRICK_DIM))


# ---------------- 灯塔（右边的地标，白塔 + 两道珊瑚环 + 暗色顶） ----------------
func _lighthouse(ci: CanvasItem) -> void:
	var cx := 477.0
	var base_y := _ridge_y(cx) + 13.0
	var top_y := base_y - 96.0
	ci.draw_circle(Vector2(cx, top_y - 8.0), 34.0, col(LAMP, 22), true, -1.0, true)
	ci.draw_circle(Vector2(cx, top_y - 8.0), 25.0, col(LAMP, 32), true, -1.0, true)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 16.0, base_y), Vector2(cx - 11.0, top_y),
		Vector2(cx + 11.0, top_y), Vector2(cx + 16.0, base_y)]), col(TOWER))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx + 8.0, base_y), Vector2(cx + 6.0, top_y),
		Vector2(cx + 11.0, top_y), Vector2(cx + 16.0, base_y)]), col(WALL_DIM))
	# 两道珊瑚色环（按塔身梯形缩进）
	for band_y in [base_y - 34.0, base_y - 66.0]:
		var t: float = (base_y - band_y) / 96.0
		var hw: float = 16.0 - 5.0 * t
		ci.draw_rect(Rect2(cx - hw, band_y, hw * 2.0, 9.0), col(TOWER_BAND))
	ci.draw_rect(Rect2(cx - 5.0, base_y - 11.0, 10.0, 11.0), col(DARK))
	# 观景台 + 灯室 + 顶盖
	ci.draw_rect(Rect2(cx - 19.0, top_y - 5.0, 38.0, 6.0), col(DARK))
	ci.draw_rect(Rect2(cx - 12.0, top_y - 24.0, 24.0, 19.0), col(DARK))
	ci.draw_rect(Rect2(cx - 8.0, top_y - 21.0, 16.0, 14.0), col(LAMP))
	ci.draw_rect(Rect2(cx - 1.0, top_y - 21.0, 2.0, 14.0), col(DARK))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 15.0, top_y - 24.0), Vector2(cx + 15.0, top_y - 24.0),
		Vector2(cx, top_y - 40.0)]), col(DARK))
	ci.draw_rect(Rect2(cx - 2.0, top_y - 45.0, 4.0, 5.0), col(DARK))


# ---------------- 木栈桥（从岬角尖伸进水里） ----------------
func _pier(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(248, 392), Vector2(172, 406), Vector2(172, 414), Vector2(248, 400)]), col(WOOD))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(172, 410), Vector2(248, 396), Vector2(248, 400), Vector2(172, 414)]), col(WOOD_DIM))
	for i in 6:
		var px := 178.0 + float(i) * 12.0
		var pt := _pier_top_y(px)
		ci.draw_rect(Rect2(px, pt + 1.0, 1.0, 8.0), col(WOOD_DIM))
	# 桥墩（泡在水里）+ 脚边浪花
	for px in [186.0, 212.0, 238.0]:
		var pt2 := _pier_top_y(px)
		ci.draw_rect(Rect2(px, pt2 + 8.0, 4.0, 16.0), col(POST))
		ci.draw_rect(Rect2(px - 3.0, pt2 + 22.0, 10.0, 2.0), col(FOAM, 110))
	ci.draw_rect(Rect2(174.0, _pier_top_y(174.0) - 12.0, 4.0, 24.0), col(POST))


func _pier_top_y(x: float) -> float:
	return 392.0 + (248.0 - x) / 76.0 * 14.0


# ---------------- 小帆船（左下角，主体之外的那点人气） ----------------
func _sailboat(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(78, 398), Vector2(140, 398), Vector2(130, 410), Vector2(90, 410)]), col(HULL))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(90, 410), Vector2(130, 410), Vector2(126, 414), Vector2(96, 414)]), col(HULL_DIM))
	ci.draw_rect(Rect2(78, 395, 62, 3), col(WALL))
	ci.draw_rect(Rect2(107, 342, 3, 56), col(MAST))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(112, 346), Vector2(112, 394), Vector2(152, 394)]), col(SAIL))
	ci.draw_polyline(PackedVector2Array([
		Vector2(112, 394), Vector2(152, 394)]), col(SAIL_DIM), 3.0, false)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(104, 356), Vector2(104, 394), Vector2(76, 394)]), col(SAIL_DIM))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(110, 340), Vector2(128, 345), Vector2(110, 350)]), col(ROOF))
	ci.draw_rect(Rect2(78, 408, 52, 2), col(FOAM, 130))
	for d in [[86, 418, 46, 60], [94, 424, 30, 45], [102, 430, 16, 30]]:
		ci.draw_rect(Rect2(float(d[0]), float(d[1]), float(d[2]), 2.0),
				col(DEPTH, int(d[3])))


func _vignette(ci: CanvasItem) -> void:
	for i in 30:
		ci.draw_rect(Rect2(0, 482 + i, S, 1), col(DEPTH, int(28.0 * float(i) / 29.0)))


# ---------------- 工具 ----------------
func _ridge_y(x: float) -> float:
	return _poly_y(RIDGE, x)


func _poly_y(pts: PackedVector2Array, x: float) -> float:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if x <= maxf(a.x, b.x) and x >= minf(a.x, b.x) and absf(a.x - b.x) > 0.001:
			return a.y + (b.y - a.y) * ((x - a.x) / (b.x - a.x))
	return pts[0].y


func _in_land(x: float, y: float) -> bool:
	var inside := false
	var n := LAND.size()
	var j := n - 1
	for i in range(n):
		var yi := LAND[i].y
		var yj := LAND[j].y
		if (yi > y) != (yj > y):
			var xr: float = LAND[i].x + (y - yi) / (yj - yi) * (LAND[j].x - LAND[i].x)
			if x < xr:
				inside = not inside
		j = i
	return inside


func _raster(base: ImageTexture) -> Image:
	var painter := Painter.new()
	painter.base_t = base
	painter.host = self
	painter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sv := SubViewport.new()
	sv.size = Vector2i(S, S)
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.transparent_bg = false
	root.add_child(sv)
	sv.add_child(painter)
	await process_frame
	await process_frame
	var shot: Image = sv.get_texture().get_image()
	if shot.is_compressed():
		shot.decompress()
	shot.convert(Image.FORMAT_RGBA8)
	sv.queue_free()
	return shot


func _write_ico(cover: Image, sizes: Array, out_path: String) -> void:
	var datas: Array = []
	for s in sizes:
		var im: Image = cover.duplicate()
		im.resize(int(s), int(s), Image.INTERPOLATE_LANCZOS)
		var tmp := ProjectSettings.globalize_path("user://_ico_tmp.png")
		im.save_png(tmp)
		datas.append(FileAccess.get_file_as_bytes(tmp))
	var buf := StreamPeerBuffer.new()
	buf.put_u16(0)
	buf.put_u16(1)
	buf.put_u16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for i in range(sizes.size()):
		var sz: int = sizes[i]
		var bytes: PackedByteArray = datas[i]
		buf.put_u8(0 if sz >= 256 else sz)      # 宽（0 表示 256）
		buf.put_u8(0 if sz >= 256 else sz)      # 高
		buf.put_u8(0)
		buf.put_u8(0)
		buf.put_u16(1)
		buf.put_u16(32)
		buf.put_u32(bytes.size())
		buf.put_u32(offset)
		offset += bytes.size()
	for d: PackedByteArray in datas:
		buf.put_data(d)
	var f2 := FileAccess.open(out_path, FileAccess.WRITE)
	f2.store_buffer(buf.data_array)
	f2.close()