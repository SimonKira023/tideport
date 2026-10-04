# tools/_probe_tiles.gd —— 打印瓦片图集每 16x16 格的色彩分类（选格用）
# 跑法: Godot_console.exe --headless --path . --script res://tools/_probe_tiles.gd
extends SceneTree

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset"
const FILES := [
	"Tileset Grass Spring.png",
	"Tileset Grass Water Spring.png",
	"Water tile.png",
	"Beach animations tiles.png",
	"Tileset Grass Cliff Tileset Spring.png",
	"Path tiles.png",
]

func _initialize() -> void:
	for fn in FILES:
		var img := _load_png("%s/%s" % [DIR, fn])
		if img == null:
			print("== %s : 打不开" % fn)
			continue
		var cw := img.get_width() / 16
		var ch := img.get_height() / 16
		print("== %s (%dx%d, %dx%d 格) ==" % [fn, img.get_width(), img.get_height(), cw, ch])
		for ty in ch:
			var row := ""
			for tx in cw:
				row += _classify(img, tx, ty)
			print("%2d %s" % [ty, row])
	quit(0)

func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK:
		return null
	return img

func _classify(img: Image, tx: int, ty: int) -> String:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var a := 0
	for y in 16:
		for x in 16:
			var c := img.get_pixel(tx * 16 + x, ty * 16 + y)
			if c.a < 0.4:
				continue
			a += 1
			r += c.r
			g += c.g
			b += c.b
	if a == 0:
		return "."
	var n := float(a)
	r /= n
	g /= n
	b /= n
	if a < 200:
		return "-"                      # 半透明/稀疏
	if g > 0.45 and g > r + 0.08 and g > b + 0.08:
		return "G"                      # 草绿
	if b > 0.45 and b > r + 0.08 and b > g - 0.05:
		return "W"                      # 水
	if r > 0.55 and g > 0.42 and b < 0.45 and r - b > 0.15:
		return "S"                      # 沙/土黄
	if r > 0.3 and g < 0.3 and b < 0.3:
		return "D"                      # 深棕/地
	return "?"
