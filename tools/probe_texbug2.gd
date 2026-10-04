# texbug 终审：列出存档里已摆放的设施 + 导出嫌犯贴图 region 放大图
extends Node

const BASE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)"

func _ready() -> void:
	for i in 2:
		await get_tree().process_frame
	var game: Node2D = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 4:
		await get_tree().process_frame
	_walk(game)
	_crop(BASE + "/Objects/Work Benches/Workbench.png", Rect2(0, 0, 32, 32), 8, "res://tools/tex_workbench.png")
	_crop(BASE + "/Objects/Work Benches/Furnace.png", Rect2(0, 0, 32, 32), 8, "res://tools/tex_furnace.png")
	_crop(BASE + "/Objects/Exterior/Well .png", Rect2(0, 48, 32, 48), 8, "res://tools/tex_well.png")
	_crop(BASE + "/Objects/Exterior/Houses/NPCS houses/Blacksmith/Blacksmith house.png", Rect2(0, 8, 144, 88), 3, "res://tools/tex_blacksmith.png")
	get_tree().quit(0)

func _walk(n: Node) -> void:
	for c in n.get_children():
		var s: Script = c.get_script()
		if s != null:
			var p: String = s.resource_path
			if p.contains("station_node") or p.contains("well_node") or p.contains("blacksmith_node") \
					or p.contains("coop_node") or p.contains("campfire") or p.contains("site_node"):
				print("STRUCT ", p.get_file(), " kind=", str(c.get("kind")), " cell=", str(c.get("cell")),
					" gpos=", str((c as Node2D).global_position), " ghost=", str(c.get("is_ghost")))
		_walk(c)

func _crop(path: String, region: Rect2, scale: int, out: String) -> void:
	var tex: Texture2D = load(path)
	if tex == null:
		print("MISS ", path)
		return
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var sub: Image = img.get_region(region)
	sub.resize(int(sub.get_width()) * scale, int(sub.get_height()) * scale, Image.INTERPOLATE_NEAREST)
	var err := sub.save_png(out)
	print("SAVED ", out, " ", sub.get_size(), " err=", err)
