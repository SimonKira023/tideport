# probe_house9 —— texbug 收口：实例化真 game.tscn，dump House 门口附近
# decor / Floor / 实体，并渲染「草+点缀+房子+出货箱」复刻图，和用户截图对比。
extends Node2D

const PROP := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const HOUSE_PNG := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/10.png"
const BIN_SCENE := "res://scene/shipping_bin.tscn"

const ORIG := Vector2(320, -95)   # 复刻图左上角的世界坐标
const SZ_X := 160
const SZ_Y := 180
const SCALE := 6

func _ready() -> void:
	var game: Node2D = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 4:
		await get_tree().process_frame

	var decor: TileMapLayer = game.get_node_or_null("DecorTileMapLayer")
	var water: TileMapLayer = game.get_node("WaterTileMapLayer")

	# 1) 门口附近的 decor 格
	print("=== decor near house (world 300..500, -60..120) ===")
	if decor != null:
		for c in decor.get_used_cells():
			var w: Vector2 = decor.position + Vector2(c.x * 16, c.y * 16)
			if w.x >= 300.0 and w.x <= 500.0 and w.y >= -60.0 and w.y <= 120.0:
				print("decor cell %s atlas %s world %s" % [c, decor.get_cell_atlas_coords(c), w])
	else:
		print("decor layer missing!")

	# 2) 门口附近的木地板格（新开局应为空）
	print("=== floor near house ===")
	for pos in Floor.floors.keys():
		var p: Vector2i = pos
		var wx := 29 + p.x * 16
		var wy := 21 + p.y * 16
		if wx >= 300 and wx <= 500 and wy >= -60 and wy <= 120:
			print("floor cell %s kind %s" % [p, Floor.kind_of(p)])

	# 3) 附近实体节点
	print("=== Node2D near house ===")
	_list(game, 0)

	# 4) 复刻图
	var img := Image.create_empty(SZ_X, SZ_Y, false, Image.FORMAT_RGBA8)
	img.fill(Color8(106, 170, 90))
	for c in water.get_used_cells():
		var w: Vector2 = water.position + Vector2(c.x * 16, c.y * 16)
		_stamp16(img, w, Color8(64, 120, 196))
	for pos in Floor.floors.keys():
		var p: Vector2i = pos
		_stamp16(img, Vector2(29 + p.x * 16, 21 + p.y * 16), Color8(180, 132, 80))
	if decor != null:
		var sheet: Image = (load(PROP) as Texture2D).get_image()
		if sheet.is_compressed():
			sheet.decompress()
		for c in decor.get_used_cells():
			var ac: Vector2i = decor.get_cell_atlas_coords(c)
			var w: Vector2 = decor.position + Vector2(c.x * 16, c.y * 16)
			_stamp_region(img, sheet, Rect2i(ac.x * 16, ac.y * 16, 16, 16), w)
	var house_img: Image = (load(HOUSE_PNG) as Texture2D).get_image()
	if house_img.is_compressed():
		house_img.decompress()
	print("house png size %s" % [house_img.get_size()])
	img.blend_rect(house_img, Rect2i(0, 0, house_img.get_width(), house_img.get_height()),
		Vector2i(int(ORIG.x) * -1 + 349, int(ORIG.y) * -1 + -91))
	var bin: Node2D = (load(BIN_SCENE) as PackedScene).instantiate()
	add_child(bin)
	await get_tree().process_frame
	_draw_bin(img, bin)

	img.resize(SZ_X * SCALE, SZ_Y * SCALE, Image.INTERPOLATE_NEAREST)
	img.save_png("res://tools/texbug_replica.png")
	print("saved res://tools/texbug_replica.png")
	get_tree().quit(0)

func _list(n: Node, depth: int) -> void:
	if n is Node2D:
		var n2 := n as Node2D
		var p: Vector2 = n2.global_position
		if p.x >= 300.0 and p.x <= 520.0 and p.y >= -130.0 and p.y <= 130.0:
			print("%s%s '%s' local %s global %s z %d" %
				["  ".repeat(depth), n.get_class(), n.name, n2.position, p, n2.z_index])
	for c in n.get_children():
		_list(c, depth + 1)

func _stamp16(img: Image, w: Vector2, col: Color) -> void:
	var x0 := int(w.x - ORIG.x)
	var y0 := int(w.y - ORIG.y)
	for y in range(maxi(y0, 0), mini(y0 + 16, SZ_Y)):
		for x in range(maxi(x0, 0), mini(x0 + 16, SZ_X)):
			img.set_pixel(x, y, col)

func _stamp_region(img: Image, sheet: Image, r: Rect2i, w: Vector2) -> void:
	img.blend_rect(sheet, r, Vector2i(int(w.x - ORIG.x), int(w.y - ORIG.y)))

func _draw_bin(img: Image, bin: Node2D) -> void:
	_walk_sprites(img, bin, bin.position)

func _walk_sprites(img: Image, n: Node, base: Vector2) -> void:
	if n is Sprite2D:
		var s := n as Sprite2D
		var tex := s.texture
		if tex != null:
			var simg := tex.get_image()
			if simg.is_compressed():
				simg.decompress()
			var size: Vector2 = simg.get_size()
			var top_left: Vector2 = base + s.position
			if s.centered:
				top_left -= size * 0.5
			top_left += s.offset
			var rr := Rect2i(0, 0, int(size.x), int(size.y))
			if s.region_enabled:
				rr = s.region_rect
			print("bin sprite '%s' tex %s size %s topleft %s region %s" %
				[s.name, tex.resource_path.get_file(), size, top_left, rr])
			img.blend_rect(simg, rr, Vector2i(int(top_left.x - ORIG.x), int(top_left.y - ORIG.y)))
	for c in n.get_children():
		_walk_sprites(img, c, base)
