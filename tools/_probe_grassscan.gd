# tools/_probe_grassscan.gd —— 扫描 Tileset Grass Spring.png，找「纯色无缝」草格
# 跑法: Godot_console.exe --headless --path . --script res://tools/_probe_grassscan.gd
extends SceneTree

const SRC := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Spring.png"

func _initialize() -> void:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		print("OPEN FAIL")
		quit(1)
		return
	var img := Image.new()
	img.load_png_from_buffer(f.get_buffer(f.get_length()))
	img.convert(Image.FORMAT_RGBA8)
	var cw := img.get_width() / 16
	var ch := img.get_height() / 16
	print("size %dx%d (%dx%d cells)" % [img.get_width(), img.get_height(), cw, ch])
	for ty in ch:
		for tx in cw:
			var mn := Vector3(1, 1, 1)
			var mx := Vector3(0, 0, 0)
			var solid := true
			for y in 16:
				for x in 16:
					var c := img.get_pixel(tx * 16 + x, ty * 16 + y)
					if c.a < 0.95:
						solid = false
						break
					mn = Vector3(minf(mn.x, c.r), minf(mn.y, c.g), minf(mn.z, c.b))
					mx = Vector3(maxf(mx.x, c.r), maxf(mx.y, c.g), maxf(mx.z, c.b))
				if not solid:
					break
			if not solid:
				continue
			var dev := maxf(mx.x - mn.x, maxf(mx.y - mn.y, mx.z - mn.z))
			if dev < 0.02:
				var mid := (mn + mx) * 0.5
				print("SOLID (%d,%d) dev=%.3f rgb=(%.2f,%.2f,%.2f)" % [tx, ty, dev, mid.x, mid.y, mid.z])
	quit(0)
