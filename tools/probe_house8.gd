extends Node
# 探针: 渲染 Tileset/ALL props seasons.png 整表 + 16px 网格,
# 核对 DECOR_* 瓦片取样 —— 找商店门口截图里的蓝色物件出处
const PROPS := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"

func _ready() -> void:
	var tex: Texture2D = load(PROPS)
	var src := tex.get_image()
	src.decompress()
	var w := src.get_width()
	var h := src.get_height()
	print("props size=", w, "x", h)
	var zoom := 4
	var img := Image.create_empty(w * zoom + 20, h * zoom + 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.16, 0.2))
	var scaled: Image = src.duplicate()
	scaled.resize(w * zoom, h * zoom, Image.INTERPOLATE_NEAREST)
	img.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), Vector2i(10, 10))
	var gx := 0
	while gx <= w:
		img.fill_rect(Rect2i(10 + gx * zoom, 10, 1, h * zoom), Color(1, 1, 0, 0.5))
		gx += 16
	var gy := 0
	while gy <= h:
		img.fill_rect(Rect2i(10, 10 + gy * zoom, w * zoom, 1), Color(1, 1, 0, 0.5))
		gy += 16
	img.save_png("res://tools/props_check.png")
	print("saved props_check.png")
	get_tree().quit()
