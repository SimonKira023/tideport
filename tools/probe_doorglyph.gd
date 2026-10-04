# probe_doorglyph —— texbug 定谳：商店门口蓝色物件高倍复刻
# 1) 导出 10.png 底部放大图（判定蓝色是否烙在房贴图里）
# 2) 导出床贴图放大图（对照截图排除「蓝色床单」嫌疑）
# 3) 门口区域 4x 复刻（有根坐标系：全局 = game 根(170,149) + 节点位置）
# 4) 打印 Floor.floors 全部数据
extends Node2D

const PROP := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const HOUSE_PNG := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/10.png"
const BEDS_PNG := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Beds.png"

const ORIG := Vector2(480, 90)
const SZ := Vector2i(200, 140)
const SCALE := 4
const GAME_ROOT := Vector2(170, 149)   # game.tscn 根 position（实测真实生效）

var _img: Image

func _ready() -> void:
	# 1) 10.png 底部三条带放大 8x（行 84..112：门台阶 + 左下角 + 透明底）
	var himg: Image = (load(HOUSE_PNG) as Texture2D).get_image()
	if himg.is_compressed():
		himg.decompress()
	var bottom := himg.get_region(Rect2i(0, 84, 80, 28))
	bottom.resize(80 * 8, 28 * 8, Image.INTERPOLATE_NEAREST)
	bottom.save_png("res://tools/doorglyph_house10_bottom.png")
	print("house10 size=", himg.get_width(), "x", himg.get_height(), " bottom saved")

	# 2) 床贴图（Beds.png region 7,269,33,34）放大 8x 对照
	var bimg: Image = (load(BEDS_PNG) as Texture2D).get_image()
	if bimg.is_compressed():
		bimg.decompress()
	var bed := bimg.get_region(Rect2i(7, 269, 33, 34))
	bed.resize(33 * 8, 34 * 8, Image.INTERPOLATE_NEAREST)
	bed.save_png("res://tools/doorglyph_bed.png")

	# 3) 高倍复刻门口区域
	var game: Node2D = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 4:
		await get_tree().process_frame

	_img = Image.create_empty(SZ.x, SZ.y, false, Image.FORMAT_RGBA8)
	_img.fill(Color8(106, 170, 90))

	# 水章（有根坐标系）
	var water: TileMapLayer = game.get_node("WaterTileMapLayer")
	for c in water.get_used_cells():
		_stamp16(GAME_ROOT + water.position + Vector2(c.x * 16, c.y * 16),
			Color8(64, 120, 196))

	# decor 章（有根坐标系）
	var decor: TileMapLayer = game.get_node_or_null("DecorTileMapLayer")
	if decor != null:
		var sheet: Image = (load(PROP) as Texture2D).get_image()
		if sheet.is_compressed():
			sheet.decompress()
		for c in decor.get_used_cells():
			var ac: Vector2i = decor.get_cell_atlas_coords(c)
			var w: Vector2 = GAME_ROOT + decor.position + Vector2(c.x * 16, c.y * 16)
			_img.blend_rect(sheet, Rect2i(ac.x * 16, ac.y * 16, 16, 16),
				Vector2i(int(w.x - ORIG.x), int(w.y - ORIG.y)))

	# 全部 Sprite2D（含 FloorLayer/SoilLayer 程序化贴图、摆设、房子、玩家）按树序渲染
	_walk(game, Vector2.ZERO, Vector2.ONE, "")

	_img.resize(SZ.x * SCALE, SZ.y * SCALE, Image.INTERPOLATE_NEAREST)
	_img.save_png("res://tools/doorglyph_replica.png")
	print("saved res://tools/doorglyph_replica.png")

	# 4) Floor 数据
	print("=== Floor.floors ===")
	for pos in Floor.floors.keys():
		print("floor ", pos, " kind=", Floor.floors[pos])
	get_tree().quit(0)

func _walk(n: Node, parent_g: Vector2, parent_s: Vector2, path: String) -> void:
	if n is Node2D:
		var n2 := n as Node2D
		parent_g = parent_g + n2.position * parent_s
		parent_s = parent_s * n2.scale
	if n is Sprite2D:
		var s := n as Sprite2D
		var tex := s.texture
		var info := "%s tex=%s" % [path + "/" + String(s.name),
			tex.resource_path.get_file() if tex != null else "null"]
		var simg: Image
		var rr := Rect2i()
		if tex is AtlasTexture:
			var at := tex as AtlasTexture
			rr = Rect2i(at.region)
			simg = (at.atlas as Texture2D).get_image()
			info += " atlas_region=%s" % [at.region]
		elif tex != null:
			simg = tex.get_image()
			rr = Rect2i(0, 0, simg.get_width(), simg.get_height())
		if simg != null and simg.is_compressed():
			simg.decompress()
		var size: Vector2 = Vector2(rr.size)
		var half := size * 0.5 if s.centered else Vector2.ZERO
		var top_left := parent_g + s.offset * parent_s - half * parent_s
		var gscale := parent_s
		print("%s pos=%s centered=%s globalTL=%s z=%d vis=%s" %
			[info, s.position, s.centered, top_left, s.z_index, s.visible])
		if simg != null:
			_draw_scaled(simg, rr, top_left, gscale)
	for c in n.get_children():
		_walk(c, parent_g, parent_s, path + "/" + String(n.name))

func _draw_scaled(simg: Image, rr: Rect2i, top_left: Vector2, sc: Vector2) -> void:
	var piece: Image
	if rr.size == Vector2i(simg.get_width(), simg.get_height()):
		piece = simg
	else:
		piece = simg.get_region(rr)
	var w := int(round(rr.size.x * sc.x))
	var h := int(round(rr.size.y * sc.y))
	if w <= 0 or h <= 0:
		return
	if w != piece.get_width() or h != piece.get_height():
		piece.resize(w, h, Image.INTERPOLATE_NEAREST)
	_img.blend_rect(piece, Rect2i(0, 0, w, h),
		Vector2i(int(top_left.x - ORIG.x), int(top_left.y - ORIG.y)))

func _stamp16(w: Vector2, col: Color) -> void:
	var x0 := int(w.x - ORIG.x)
	var y0 := int(w.y - ORIG.y)
	for y in range(maxi(y0, 0), mini(y0 + 16, SZ.y)):
		for x in range(maxi(x0, 0), mini(x0 + 16, SZ.x)):
			_img.set_pixel(x, y, col)
