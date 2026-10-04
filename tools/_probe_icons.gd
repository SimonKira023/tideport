# _probe_icons.gd —— 列出所有道具图标的类型/尺寸，抓「一张图里好几帧」的双图标
extends Node

func _ready() -> void:
	var dir := DirAccess.open("res://item")
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var it: ItemData = load("res://item/" + f)
		if it == null or it.icon == null:
			print("%s: 无图标" % f)
			continue
		var size := it.icon.get_size()
		var kind := it.icon.get_class()
		var whole := ""
		if it.icon is AtlasTexture:
			whole = " 整图=%s" % str(it.icon.atlas.get_size())
		var flag := ""
		if size.x > size.y:
			flag = "  <<<< 宽大于高, 多帧图!"
		print("%s [%s] 显示=%s%s%s" % [f, kind, str(size), whole, flag])
	get_tree().quit()
