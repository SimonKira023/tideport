extends Node
# 探针: 导出 Houses 1-12.png 放大拼贴, 查商店门口蓝色物件是不是贴图自带杂物
func _ready() -> void:
	var dir := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/"
	var ids := ["1", "2", "3", "8", "10", "11"]
	var cols := 3
	var cell := 260   # 每格: 图放大到最大 240 宽
	var rows := int(ceil(ids.size() / float(cols)))
	var out := Image.create_empty(cols * cell, rows * (cell + 20), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.15, 0.15, 0.18))
	var font := ThemeDB.fallback_font
	for i in ids.size():
		var tex: Texture2D = load(dir + ids[i] + ".png")
		if tex == null:
			push_error("加载失败 " + ids[i])
			continue
		var img := tex.get_image()
		img.decompress()
		var sc := float(cell - 20) / maxf(img.get_width(), img.get_height())
		sc = minf(sc, 6.0)
		img.resize(int(img.get_width() * sc), int(img.get_height() * sc), Image.INTERPOLATE_NEAREST)
		var cx := (i % cols) * cell
		var cy := int(i / float(cols)) * (cell + 20)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(cx + 10, cy + 20))
		var txt := "%s.png  %dx%d  scale %.2f" % [ids[i], tex.get_width(), tex.get_height(), sc]
		var tw := int(minf(240.0, font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)) + 4
		out.blend_rect(_label(txt, Rect2i(0, 0, tw, 16)), Rect2i(0, 0, tw, 16), Vector2i(cx + 10, cy + 2))
	# 顺带把 10.png 原尺寸 4x 放大也导一份 (查杂物像素坐标)
	var tex10: Texture2D = load(dir + "10.png")
	if tex10 != null:
		var im10 := tex10.get_image()
		im10.decompress()
		var big := im10.duplicate()
		big.resize(im10.get_width() * 4, im10.get_height() * 4, Image.INTERPOLATE_NEAREST)
		var out2 := Image.create_empty(big.get_width() + 20, big.get_height() + 20, false, Image.FORMAT_RGBA8)
		out2.fill(Color(0.2, 0.2, 0.25))
		out2.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(10, 10))
		out2.save_png("res://tools/out_house10_zoom.png")
		print("house10 size=", im10.get_width(), "x", im10.get_height())
	var odir := "res://tools/deco_check7.png"
	out.save_png(odir)
	print("saved ", odir)
	get_tree().quit()

func _label(s: String, r: Rect2i) -> Image:
	var f := ThemeDB.fallback_font
	var img := Image.create_empty(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.9))
	f.draw_string(img, Vector2(2, 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.4))
	return img
