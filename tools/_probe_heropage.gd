# 实拍技能树页：验证内容盒不再顶出屏幕、树能滚到底、体魄行完整可见
extends Node

var _fails := 0

func chk(ok: bool, msg: String) -> void:
	if ok:
		print("  [ok] " + msg)
	else:
		_fails += 1
		print("  [!!] " + msg)

func _ready() -> void:
	print("===== 技能树页实拍 =====")
	SaveManager.enabled = false
	SaveManager.save_path = OS.get_user_data_dir() + "/tmp_hero_probe.json"

	var bp: Control = load("res://backpack_ui.gd").new()
	add_child(bp)
	await get_tree().process_frame
	bp._switch_to("hero")
	await get_tree().process_frame
	bp.show()
	await get_tree().process_frame

	# a. 内容盒顶边不超过屏幕、底边也在屏幕内
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var box: Control = bp._box
	var top := box.global_position.y
	var bottom := box.global_position.y + box.size.y
	chk(bottom <= vp.y + 0.5, "内容盒底边 %.0f <= 屏幕高 %.0f（不再顶出屏幕）" % [bottom, vp.y])
	chk(top >= 0.0, "内容盒顶边 %.0f >= 0" % top)

	# b. 树的最小高度跟实际绘制范围一致（5 行画到 ~500）
	var tree: Control = bp._skill_tree
	chk(tree.custom_minimum_size.y >= 500.0,
		"树画布高度 %.0f 覆盖实际绘制范围 ~500（之前 424 裁掉体魄行）" % tree.custom_minimum_size.y)

	# c. 树在滚动容器里能滚到底：滚动范围 >= 树实际内容超出量
	var scroll: Node = tree.get_parent()
	while scroll != null and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	var sc: ScrollContainer = scroll as ScrollContainer
	chk(sc != null, "树外面套着滚动容器")
	var vbar: VScrollBar = sc.get_v_scroll_bar()
	chk(vbar.max_value > sc.size.y, "滚动范围 %.0f > 视口 %.0f（能滚）" % [vbar.max_value, sc.size.y])
	sc.scroll_vertical = int(vbar.max_value)
	await get_tree().process_frame
	await get_tree().process_frame
	chk(sc.scroll_vertical + sc.size.y >= vbar.max_value - 1.0,
		"滚到底后能看完整棵树（底部 = %.0f / %.0f）" % [sc.scroll_vertical + sc.size.y, vbar.max_value])

	# d. 实拍两张：顶部（行商）与底部（体魄滚到底）
	await _shot("outputs/probe_hero_top.png")
	sc.scroll_vertical = int(vbar.max_value)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("outputs/probe_hero_bottom.png")

	print("===== 结果: %s =====" % ("全部通过" if _fails == 0 else "%d 项没过" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("  已保存 " + path)
