extends Node
# 探针: 导出城镇摆设 png (雕像/灯柱/木桶/喷泉) + 晨曦国其余房子, 对照商店门口的蓝色物件
func _ready() -> void:
	var base := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/"
	var files := [
		base + "Stone Statue.png",
		base + "Street Lamp.png",
		base + "Stacked Barrels.png",
		base + "Water fountain.png",
		base + "Houses/3.png",
		base + "Houses/8.png",
		base + "Houses/11.png",
	]
	var cols := 4
	var cell := 300
	var rows := int(ceil(files.size() / float(cols)))
	var out := Image.create_empty(cols * cell, rows * (cell + 20), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.15, 0.15, 0.18))
	var font := ThemeDB.fallback_font
	for i in files.size():
		var tex: Texture2D = load(files[i])
		if tex == null:
			push_error("加载失败 " + files[i])
			continue
		var img := tex.get_image()
		img.decompress()
		var sc := float(cell - 40) / maxf(img.get_width(), img.get_height())
		sc = minf(sc, 5.0)
		img.resize(int(img.get_width() * sc), int(img.get_height() * sc), Image.INTERPOLATE_NEAREST)
		var cx := (i % cols) * cell
		var cy := int(i / float(cols)) * (cell + 20)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(cx + 10, cy + 20))
		var short: String = files[i].replace(base, "")
		var txt := "%s  %dx%d  x%.2f" % [short, tex.get_width(), tex.get_height(), sc]
		var tw := int(minf(280.0, font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)) + 4
		out.blend_rect(_label(txt, Rect2i(0, 0, tw, 16)), Rect2i(0, 0, tw, 16), Vector2i(cx + 10, cy + 2))
	out.save_png("res://tools/deco_check8.png")
	print("saved deco_check8.png")
	get_tree().quit()

func _label(s: String, r: Rect2i) -> Image:
	var f := ThemeDB.fallback_font
	var img := Image.create_empty(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.9))
	f.draw_string(img, Vector2(2, 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.4))
	return img
