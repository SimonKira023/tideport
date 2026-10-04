extends Node
# 探针: 渲染 Fireplace.png 各候选区域, 挑一个独立的砖炉(带火)做屋内壁炉
const PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Interior/Fireplace.png"
# 按行排列, 顺序打印在日志里, 图上从左到右从上到下对应
const REGIONS := [
	Rect2i(34, 6, 28, 42), Rect2i(67, 8, 26, 40), Rect2i(162, 18, 28, 30), Rect2i(2, 20, 28, 28),
	Rect2i(0, 65, 64, 94), Rect2i(68, 83, 24, 29), Rect2i(0, 161, 32, 47), Rect2i(64, 161, 32, 47),
	Rect2i(128, 161, 32, 47), Rect2i(192, 161, 32, 47), Rect2i(0, 209, 32, 47), Rect2i(64, 209, 41, 47),
]

func _ready() -> void:
	var tex: Texture2D = load(PATH)
	var src := tex.get_image()
	src.decompress()
	var cell := 110
	var cols := 4
	var rows := int(ceil(REGIONS.size() / float(cols)))
	var out := Image.create_empty(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in REGIONS.size():
		var r: Rect2i = REGIONS[i]
		print("cell %d -> (%d,%d,%d,%d)" % [i, r.position.x, r.position.y, r.size.x, r.size.y])
		var cx := (i % cols) * cell
		var cy := int(i / float(cols)) * cell
		out.blend_rect(src, r, Vector2i(cx + 5, cy + 5))
	out.resize(cols * cell * 2, rows * cell * 2, Image.INTERPOLATE_NEAREST)
	out.save_png("res://tools/fire_check.png")
	print("saved fire_check.png")
	get_tree().quit()
