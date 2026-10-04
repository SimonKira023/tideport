# tools/_probe_atlas_preview.gd —— 复用 world_map.gd 的取样函数渲染预览图（人工目检用）
# 跑法: Godot_console.exe --headless --path . --script res://tools/_probe_atlas_preview.gd
# 产出: tools/_atlas_strip.png（整条图集 4x） + tools/_atlas_shore.png（草沙海过渡样张 2x）
extends SceneTree

const WM := "res://scene/world_map.gd"

func _initialize() -> void:
	var wm: Node = load(WM).new()
	var CELL: int = wm.CELL
	var grass: Image = wm._load_png(wm.ART_GRASS)
	var beach: Image = wm._load_png(wm.ART_BEACH)
	var T_COUNT: int = wm.T_COUNT

	# ---- 1) 整条图集，和 _paint_tiles 一字不差 ----
	var img := Image.create_empty(T_COUNT * CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(wm.SEA[wm.SEA_LEVELS - 1])
	for k in wm.ART_GRASS_CELLS.size():
		wm._blit_cell(img, (wm.T_GRASS_A + k) * CELL, grass, wm.ART_GRASS_CELLS[k])
	wm._blend_cells(img, wm.T_GRASS_SAND * CELL, grass, wm.ART_GRASS_CELLS[0], beach, wm.ART_SAND_CELL, 0.45)
	wm._blit_cell(img, wm.T_SAND * CELL, beach, wm.ART_SAND_CELL)
	wm._wet_sand(img, wm.T_SAND_WET * CELL, beach)
	for lv in wm.SEA_LEVELS:
		for v in wm.SEA_VARIANTS:
			wm._sea_tile(img, (wm.T_SEA + lv * wm.SEA_VARIANTS + v) * CELL, beach, wm.ART_SEA_CELLS[v], lv)
	var strip := img.duplicate()
	strip.resize(T_COUNT * CELL * 4, CELL * 4, Image.INTERPOLATE_NEAREST)
	strip.save_png("res://tools/_atlas_strip.png")

	# ---- 2) 草沙海过渡样张：中间 11x11 陆地 + 海水按离岸深度上色 ----
	var W := 24
	var H := 24
	var mp := Image.create_empty(W * CELL, H * CELL, false, Image.FORMAT_RGBA8)
	for cy in H:
		for cx in W:
			var ox := cx * CELL
			var oy := cy * CELL
			var in_land := cx >= 7 and cx <= 17 and cy >= 7 and cy <= 17
			if in_land:
				var s: int = mini(mini(cx - 7, 17 - cx), mini(cy - 7, 17 - cy))
				var idx: int
				match s:
					0: idx = wm.T_SAND_WET
					1: idx = wm.T_SAND
					2: idx = wm.T_SAND if (cx + cy) % 2 == 0 else wm.T_GRASS_SAND
					_: idx = wm.T_GRASS_A + (cx * 31 + cy * 17) % 3
				mp.blit_rect(img, Rect2i(idx * CELL, 0, CELL, CELL), Vector2i(ox, oy))
			else:
				var d := maxi(maxi(7 - cx, cx - 17), maxi(7 - cy, cy - 17)) - 1
				var lv: int = clampi(d, 0, wm.SEA_LEVELS - 1)
				var v: int = (cx * 7 + cy * 13 + lv) % wm.SEA_VARIANTS
				var idx2: int = wm.T_SEA + lv * wm.SEA_VARIANTS + v
				mp.blit_rect(img, Rect2i(idx2 * CELL, 0, CELL, CELL), Vector2i(ox, oy))
	mp.resize(W * CELL * 2, H * CELL * 2, Image.INTERPOLATE_NEAREST)
	mp.save_png("res://tools/_atlas_shore.png")

	print("OK strip=%dx%d shore=%dx%d" % [strip.get_width(), strip.get_height(), mp.get_width(), mp.get_height()])
	wm.free()
	quit(0)
