# 临时探针2: 把 4 个伙伴模型的 Idle.png 放大 8x 导出到项目外临时目录, 供人工确认色块归属
extends SceneTree

const MODEL_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/%s"
const MODELS := ["Alex", "Lyria", "Manu", "Tori"]
const OUT := "res://tools/_probe_out"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for m in MODELS:
		var tex: Texture2D = load(MODEL_PATH % [m, "Idle.png"])
		if tex == null:
			continue
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		var big := img.duplicate()
		big.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
		var path := "%s/%s_idle_x8.png" % [OUT, m]
		big.save_png(ProjectSettings.globalize_path(path))
		print("saved %s %dx%d" % [path, big.get_width(), big.get_height()])
	quit(0)
