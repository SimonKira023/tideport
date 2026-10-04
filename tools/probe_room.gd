extends Node
# 一次性工具：把 house.tscn 的室内（地板 + 家具 + 床 + 出口门）合成一张放大 PNG，
# 用来肉眼验收内饰排版（位置有没有撞、有没有压到走道）。跑完即退。
# 输出 res://tools/room_preview.png

const SCALE := 3

func _ready() -> void:
	var house: Node2D = (load("res://scene/house.tscn") as PackedScene).instantiate()
	add_child(house)
	await get_tree().process_frame
	var interior: Node2D = house.get_node("Interior")
	interior.visible = true
	var w := 288
	var h := 192
	var canvas := Image.create_empty(w * SCALE, h * SCALE, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.06, 0.05, 0.08))
	for n in _sprites(interior):
		var spr := n as Sprite2D
		if spr.texture == null:
			continue
		var img := spr.texture.get_image()
		if img.is_compressed():
			img.decompress()
		var rect := Rect2i(0, 0, img.get_width(), img.get_height())
		if spr.region_enabled:
			rect = Rect2i(spr.region_rect)
		rect = rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if rect.size.x <= 0 or rect.size.y <= 0:
			print("[跳过] %s region 越界 %s" % [spr.name, str(spr.region_rect)])
			continue
		var part := img.get_region(rect)
		part.resize(part.get_width() * SCALE, part.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
		var local := spr.global_position - interior.global_position
		var at := Vector2i(roundi(local.x) * SCALE, roundi(local.y) * SCALE)
		_blit(canvas, part, at)
		print("[摆] %-12s %s  尺寸 %dx%d" % [spr.name, str(local), rect.size.x, rect.size.y])
	# 走道检查点：出生点 / 出口门 / 床脚
	for pt in [["SpawnPoint", Vector2(136, 120)], ["ExitDoor", Vector2(128, 158)],
			["BedFoot", Vector2(32, 89)]]:
		var p: Vector2 = pt[1]
		canvas.fill_rect(Rect2i(int(p.x) * SCALE, int(p.y) * SCALE, 2, 2), Color(1, 0, 0))
		print("[走道] %s %s" % [pt[0], str(p)])
	canvas.save_png("res://tools/room_preview.png")
	print("[SAVED] res://tools/room_preview.png")
	get_tree().quit()

# 带 alpha 的 src-over 贴合（Image.blend_rect 在 FORMAT_RGBA8 上够用）
func _blit(dst: Image, src: Image, at: Vector2i) -> void:
	var r := Rect2i(at, Vector2i(src.get_width(), src.get_height()))
	var clipped := r.intersection(Rect2i(0, 0, dst.get_width(), dst.get_height()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	dst.blend_rect(src, Rect2i(clipped.position - at, clipped.size), clipped.position)

func _sprites(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Sprite2D:
			out.append(c)
		elif c is Node2D or c is Control:
			out.append_array(_sprites(c))
	return out
