# tools/_probe_biome_map.gd —— e11e 风貌落图目检（临用临删）
# 跑法: Godot_console.exe --headless --path . res://tools/_probe_biome_map.tscn
# 产出: tools/_biome_map.png（4x 着色全图: 雪=白 岩=棕 沙=黄 草=绿 水=蓝）+ 各风貌格数
extends Node2D

func _ready() -> void:
	var wm: Node2D = load("res://scene/world_map.gd").new()
	add_child(wm)
	await get_tree().process_frame
	var tiles: TileMapLayer = wm.get_node("Tiles")
	var img := Image.create_empty(wm.MAP_W, wm.MAP_H, false, Image.FORMAT_RGBA8)
	var cnt := {"snow": 0, "rock": 0, "sand": 0, "gsand": 0, "grass": 0, "wet": 0, "water": 0}
	for y in wm.MAP_H:
		for x in wm.MAP_W:
			var c := Vector2i(x, y)
			var co: Color
			if not wm._land.has(c):
				co = Color(0.20, 0.42, 0.72)
				cnt["water"] += 1
			else:
				var t := tiles.get_cell_atlas_coords(c)
				if t.x == wm.T_SNOW_A or t.x == wm.T_SNOW_B:
					co = Color(0.97, 0.97, 1.0)
					cnt["snow"] += 1
				elif t.x == wm.T_ROCK_A or t.x == wm.T_ROCK_B:
					co = Color(0.48, 0.36, 0.28)
					cnt["rock"] += 1
				elif t.x == wm.T_SAND:
					co = Color(0.93, 0.83, 0.55)
					cnt["sand"] += 1
				elif t.x == wm.T_GRASS_SAND:
					co = Color(0.72, 0.76, 0.42)
					cnt["gsand"] += 1
				elif t.x == wm.T_SAND_WET:
					co = Color(0.78, 0.66, 0.44)
					cnt["wet"] += 1
				else:
					co = Color(0.42, 0.68, 0.30)
					cnt["grass"] += 1
			img.set_pixel(x, y, co)
	# 城镇点红叉标位（看风貌和城对不对得上）
	for tid in Nations.TOWNS.keys():
		var tc: Vector2i = Nations.TOWNS[tid]["cell"]
		for k in 3:
			img.set_pixel(clampi(tc.x - 1 + k, 0, wm.MAP_W - 1), tc.y, Color(1, 0.1, 0.1))
			img.set_pixel(tc.x, clampi(tc.y - 1 + k, 0, wm.MAP_H - 1), Color(1, 0.1, 0.1))
	img.resize(wm.MAP_W * 4, wm.MAP_H * 4, Image.INTERPOLATE_NEAREST)
	img.save_png("res://tools/_biome_map.png")
	print("counts ", cnt)
	print("biome beiling_cap=", wm._biome_of(Vector2i(132, 24)),
		" tieyan_cap=", wm._biome_of(Vector2i(104, 46)),
		" canglang_cap=", wm._biome_of(Vector2i(32, 30)),
		" chenxi_cap=", wm._biome_of(Vector2i(148, 94)),
		" isle=", wm._biome_of(Vector2i(160, 116)))
	get_tree().quit(0)
