extends Node
# 探针: 1:1 复刻晨曦都城集群(10.png 主屋 + 8/11 厢房 + 喷泉/灯柱/雕像/木桶),
# 下排把四件摆设的第一帧单独放大 —— 对照商店门口截图里的蓝色物件到底是哪件。
const BASE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/"
const CHENXI := Color(0.86, 0.38, 0.33)

func _ready() -> void:
	var tint: Color = CHENXI.lerp(Color(1, 1, 1), 0.75)
	var img := Image.create_empty(400, 420, false, Image.FORMAT_RGBA8)
	img.fill(Color8(96, 160, 70))   # 草地
	var ox := 130
	var oy := 140
	_deco_img(img, BASE + "Houses/10.png", 0.50, Vector2(-32, -56), tint, ox, oy, Vector2i.ZERO)
	_deco_img(img, BASE + "Houses/8.png", 0.35, Vector2(-56, -39), tint, ox, oy, Vector2i.ZERO)
	_deco_img(img, BASE + "Houses/11.png", 0.38, Vector2(16, -49), tint, ox, oy, Vector2i.ZERO)
	_deco_img(img, BASE + "Water fountain.png", 0.30, Vector2(26, -19), Color(1, 1, 1), ox, oy, Vector2i(48, 64))
	_deco_img(img, BASE + "Street Lamp.png", 0.28, Vector2(-42, -14), Color(1, 1, 1), ox, oy, Vector2i(32, 48))
	_deco_img(img, BASE + "Stone Statue.png", 0.35, Vector2(-10, -17), Color(1, 1, 1), ox, oy, Vector2i.ZERO)
	_deco_img(img, BASE + "Stacked Barrels.png", 0.28, Vector2(44, -13), Color(1, 1, 1), ox, oy, Vector2i.ZERO)
	# 下排: 四摆设第一帧单独 2 倍图
	_raw(img, BASE + "Water fountain.png", Vector2i(48, 64), Vector2i(10, 260))
	_raw(img, BASE + "Street Lamp.png", Vector2i(32, 48), Vector2i(130, 260))
	_raw(img, BASE + "Stone Statue.png", Vector2i.ZERO, Vector2i(220, 260))
	_raw(img, BASE + "Stacked Barrels.png", Vector2i.ZERO, Vector2i(320, 260))
	img.resize(800, 840, Image.INTERPOLATE_NEAREST)
	img.save_png("res://tools/town_check.png")
	print("saved town_check.png")
	get_tree().quit()

# 按 world_map._deco 的方式贴一件摆设/房子: pos 是节点空间左上角, 整体 ×2 保比例
func _deco_img(img: Image, path: String, sc: float, pos: Vector2, tint: Color,
		ox: int, oy: int, frame: Vector2i) -> void:
	var tex: Texture2D = load(path)
	var src := tex.get_image()
	src.decompress()
	print(path.get_file(), " tex=", tex.get_width(), "x", tex.get_height())
	if frame != Vector2i.ZERO:
		src = src.get_region(Rect2i(Vector2i.ZERO, frame))
	var scaled: Image = src.duplicate()
	scaled.resize(int(src.get_width() * sc * 2.0), int(src.get_height() * sc * 2.0), Image.INTERPOLATE_NEAREST)
	if tint != Color(1, 1, 1):
		for y in scaled.get_height():
			for x in scaled.get_width():
				var c: Color = scaled.get_pixel(x, y)
				if c.a > 0.0:
					c.r *= tint.r
					c.g *= tint.g
					c.b *= tint.b
					scaled.set_pixel(x, y, c)
	img.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()),
		Vector2i(ox + int(pos.x * 2.0), oy + int(pos.y * 2.0)))

# 摆设原图 ×2 单独贴
func _raw(img: Image, path: String, frame: Vector2i, dst: Vector2i) -> void:
	var tex: Texture2D = load(path)
	var src := tex.get_image()
	src.decompress()
	if frame != Vector2i.ZERO:
		src = src.get_region(Rect2i(Vector2i.ZERO, frame))
	var scaled: Image = src.duplicate()
	scaled.resize(src.get_width() * 2, src.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), dst)
