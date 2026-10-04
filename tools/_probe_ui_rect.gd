# 探针：把 game.tscn 跑起来，量一下挂在 HUD(CanvasLayer) 上的各个 UI 面板
# 到底占了屏幕多大 —— 用来判断「面板是不是全屏布局」。
extends Node

func _ready() -> void:
	var game: Node = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 8:
		await get_tree().process_frame

	print("--- 视口: ", get_viewport().get_visible_rect().size, " ---")
	for n in [game.get("shop_panel"), game.get("backpack_panel"), game.get("settlement_panel")]:
		var c := n as Control
		if c == null:
			continue
		print("%-18s size=%-16s global=%s  在HUD下=%s" % [
			c.name, str(c.size), str(c.get_global_rect()), str(c.get_parent() is CanvasLayer)])
		if c.name == "Shop":
			print("  ---- Shop 子树 ----")
			_walk(c, 1)
	get_tree().quit()

func _walk(n: Node, depth: int) -> void:
	for child in n.get_children():
		var c := child as Control
		if c != null:
			print("%s%-14s %-18s anchors=%s offsets=%s rect=%s" % [
				"  ".repeat(depth), c.name, c.get_class(),
				str(Vector4(c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom)),
				str(Vector4(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom)),
				str(c.get_global_rect())])
		_walk(child, depth + 1)
