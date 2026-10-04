# tools/_probe_biome.gd —— 候选格拼图（红色细线分隔, 6x, 10 列一行）
# 跑法: Godot_console.exe --headless --path . --script res://tools/_probe_biome.gd
# 产出: tools/_biome_cells.png —— 候选格按 CANDS 顺序排, 从左到右从上到下
extends SceneTree

const WINTER := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Winter.png"
const ROCK := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Rock Caves.png"
const PROPS := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"

# (源图下标, tx, ty) —— 顺序即拼图位置
# 0-7: WINTER 雪/冰候选; 8-13: ROCK 洞窟地面候选; 14+: PROPS 石头/土/枯枝候选
const CANDS := [
	[0, 9, 2], [0, 21, 2], [0, 9, 14], [0, 21, 14], [0, 9, 18], [0, 21, 18], [0, 9, 30], [0, 21, 30],
	[1, 2, 0], [1, 4, 0], [1, 8, 1], [1, 4, 4], [1, 7, 5], [1, 9, 15],
	[2, 0, 4], [2, 2, 4], [2, 4, 4], [2, 6, 4], [2, 8, 4], [2, 10, 4], [2, 12, 4], [2, 14, 4],
	[2, 16, 4], [2, 18, 4], [2, 20, 4], [2, 21, 4],
	[2, 0, 5], [2, 2, 5], [2, 4, 5], [2, 6, 5], [2, 8, 5], [2, 10, 5], [2, 12, 5], [2, 14, 5],
	[2, 6, 3], [2, 8, 3], [2, 9, 3], [2, 14, 3],
	[2, 12, 2], [2, 13, 2], [2, 9, 2],
]
const ZOOM := 6
const COLS := 10

func _initialize() -> void:
	var imgs: Array = []
	for p in [WINTER, ROCK, PROPS]:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			print("OPEN FAIL " + p)
			quit(1)
			return
		var img := Image.new()
		img.load_png_from_buffer(f.get_buffer(f.get_length()))
		img.convert(Image.FORMAT_RGBA8)
		imgs.append(img)
	var rows := int(ceil(float(CANDS.size()) / COLS))
	var cell := 16 * ZOOM
	var out := Image.create_empty(COLS * (cell + 2), rows * (cell + 2), false, Image.FORMAT_RGBA8)
	out.fill(Color(1, 0, 0))
	for i in CANDS.size():
		var cx := i % COLS
		var cy := i / COLS
		var src: Image = imgs[CANDS[i][0]]
		var c := src.get_region(Rect2i(CANDS[i][1] * 16, CANDS[i][2] * 16, 16, 16))
		c.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		out.blit_rect(c, Rect2i(0, 0, cell, cell), Vector2i(cx * (cell + 2) + 1, cy * (cell + 2) + 1))
	out.save_png("res://tools/_biome_cells.png")
	print("saved %d cands, %dx%d" % [CANDS.size(), out.get_width(), out.get_height()])
	quit(0)
