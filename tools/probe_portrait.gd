# tools/probe_portrait.gd —— 临时探针: 量头像 PNG 底部空带高度(诊断"没贴到底")
# e30m: 改用左右边缘像素当该行纯背景基准, 数"非背景像素", 深色护甲不再误报
# 跑法: Godot_console.exe --headless --path . --script res://tools/probe_portrait.gd
extends SceneTree

const DIR := "res://resources/texture/portraits"
const NAMES := ["lord_chenxi_cap", "lord_xichuan_cap", "lord_tieyan_cap",
	"lord_beiling_cap", "lord_canglang_cap", "player", "slave_00"]
const TH := 0.10   # 与边缘背景的色差阈值

func _initialize() -> void:
	for nm in NAMES:
		var img := Image.new()
		var err := img.load("%s/%s.png" % [DIR, nm])
		if err != OK:
			print("[probe] %s 读不了 err=%d" % [nm, err])
			continue
		var w := img.get_width()
		var h := img.get_height()
		var amin := 1.0
		for y in h:
			for x in w:
				amin = minf(amin, img.get_pixel(x, y).a)
		# 底部空带: 自底向上第一行有"非背景像素"的行; 背景取该行左右各 4 像素均值
		var content_bottom := -1
		for y in range(h - 1, -1, -1):
			if _row_content(img, w, y) > 0:
				content_bottom = y
				break
		var content_top := -1
		for y in range(0, h):
			if _row_content(img, w, y) > 0:
				content_top = y
				break
		print("[probe] %s  %dx%d  alpha_min=%.2f  底部空带=%dpx  顶部空带=%dpx"
			% [nm, w, h, amin, h - 1 - content_bottom, content_top])
	quit(0)

# 该行非背景像素个数: 背景 = 行两端(各 4px)平均色
func _row_content(img: Image, w: int, y: int) -> int:
	var bg := Color(0, 0, 0)
	for x in 4:
		bg += img.get_pixel(x, y)
		bg += img.get_pixel(w - 1 - x, y)
	bg = bg / 8.0
	var n := 0
	for x in w:
		var c := img.get_pixel(x, y)
		var d := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
		if d > TH:
			n += 1
	return n
