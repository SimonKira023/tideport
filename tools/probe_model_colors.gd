# 临时探针: 采样 4 个伙伴模型图集的色相/明度分布, 用于定发色带与服装带
# 跑法: Godot_console.exe --headless --path . --script res://tools/probe_model_colors.gd
extends SceneTree

const MODEL_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/%s"
const MODELS := ["Alex", "Lyria", "Manu", "Tori"]

func _init() -> void:
	for m in MODELS:
		var tex: Texture2D = load(MODEL_PATH % [m, "Idle.png"])
		if tex == null:
			print("MISS %s" % m)
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		_dump(m, img)
	quit(0)

func _dump(m: String, img: Image) -> void:
	# hue 12 桶 × 饱和高/低档; 暗像素(v<0.45)单列按 v 细分
	var cnt := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.2:
				continue
			var k: String
			if c.v < 0.45:
				k = "dark%d" % int(c.v * 6.999)          # 0..6: 越大越亮
			elif c.s < 0.14:
				k = "gray%d" % int(c.v * 3.999)
			else:
				k = "h%02d%s" % [int(c.h * 11.999), "S" if c.s >= 0.4 else "L"]
			var e: Array = cnt.get(k, [0, Color(0, 0, 0, 0)])
			e[0] += 1
			e[1] += c
			cnt[k] = e
	var parts: PackedStringArray = []
	var keys := cnt.keys()
	keys.sort()
	for k in keys:
		var e2: Array = cnt[k]
		var n: int = e2[0]
		var avg: Color = e2[1] / float(n)
		parts.append("%s=%d(%s)" % [k, n, avg.to_html(false)])
	print("%s: %s" % [m, " ".join(parts)])
