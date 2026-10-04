extends Node
# 探针: 渲染 Crow.png / Common Butterfly.png 原始精灵表 + 网格, 核对
# critters.gd 里 hframes/vframes 的假设(乌鸦 5x3@32, 蝴蝶 4x2@16)是否成立
const CROW := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Animals/Forest/Crow/Crow.png"
const FLY := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/Bugs/Butterflies/Common Butterfly.png"

func _ready() -> void:
	var img := Image.create_empty(860, 900, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.16, 0.2))
	_sheet(img, CROW, 5, Vector2i(10, 30))      # 乌鸦 x5
	_sheet(img, FLY, 8, Vector2i(10, 560))      # 蝴蝶 x8
	img.save_png("res://tools/critter_check.png")
	print("saved critter_check.png")
	get_tree().quit()

func _sheet(img: Image, path: String, zoom: int, dst: Vector2i) -> void:
	var tex: Texture2D = load(path)
	var src := tex.get_image()
	src.decompress()
	var w := src.get_width()
	var h := src.get_height()
	print(path.get_file(), " size=", w, "x", h)
	var scaled: Image = src.duplicate()
	scaled.resize(w * zoom, h * zoom, Image.INTERPOLATE_NEAREST)
	img.blend_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), dst)
	# 网格: 乌鸦按 32 源像素一格, 蝴蝶按 16
	var cell := 32 if w >= 100 else 16
	var gx := 0
	while gx <= w:
		img.fill_rect(Rect2i(dst.x + gx * zoom, dst.y, 1, h * zoom), Color(1, 1, 0, 0.55))
		gx += cell
	var gy := 0
	while gy <= h:
		img.fill_rect(Rect2i(dst.x, dst.y + gy * zoom, w * zoom, 1), Color(1, 1, 0, 0.55))
		gy += cell
