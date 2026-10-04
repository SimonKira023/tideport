# probe_house10 —— texbug 终局：把 House 周边所有 Sprite2D（运行时创建的也算）
# 全部 dump + 通用渲染到一张图里，蓝色物件现形即锁定。
extends Node2D

const PROP := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const HOUSE_PNG := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/10.png"

const ORIG := Vector2(250, -150)
const SZ := Vector2i(420, 420)
const SCALE := 2

var _img: Image

func _ready() -> void:
	var game: Node2D = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 4:
		await get_tree().process_frame

	_img = Image.create_empty(SZ.x, SZ.y, false, Image.FORMAT_RGBA8)
	_img.fill(Color8(106, 170, 90))

	var water: TileMapLayer = game.get_node("WaterTileMapLayer")
	for c in water.get_used_cells():
		var w: Vector2 = water.position + Vector2(c.x * 16, c.y * 16)
		_stamp16(w, Color8(64, 120, 196))
	for pos in Floor.floors.keys():
		var p: Vector2i = pos
		_stamp16(Vector2(29 + p.x * 16, 21 + p.y * 16), Color8(180, 132, 80))

	var decor: TileMapLayer = game.get_node_or_null("DecorTileMapLayer")
	if decor != null:
		var sheet: Image = (load(PROP) as Texture2D).get_image()
		if sheet.is_compressed():
			sheet.decompress()
		for c in decor.get_used_cells():
			var ac: Vector2i = decor.get_cell_atlas_coords(c)
			var w: Vector2 = decor.position + Vector2(c.x * 16, c.y * 16)
			_img.blend_rect(sheet, Rect2i(ac.x * 16, ac.y * 16, 16, 16),
				Vector2i(int(w.x - ORIG.x), int(w.y - ORIG.y)))

	print("=== all Sprite2D in wide region ===")
	_walk(game, Vector2.ZERO, Vector2.ONE, "")

	var house_img: Image = (load(HOUSE_PNG) as Texture2D).get_image()
	if house_img.is_compressed():
		house_img.decompress()
	_img.blend_rect(house_img, Rect2i(0, 0, 80, 112), Vector2i(int(349.0 - ORIG.x), int(-91.0 - ORIG.y)))

	_img.resize(SZ.x * SCALE, SZ.y * SCALE, Image.INTERPOLATE_NEAREST)
	_img.save_png("res://tools/texbug_replica3.png")
	print("saved res://tools/texbug_replica3.png")
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
		print("%s pos=%s centered=%s scale=%s globalTL=%s z=%d vis=%s" %
			[info, s.position, s.centered, s.scale, top_left, s.z_index, s.visible])
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
