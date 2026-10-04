extends Node
# 临时探针：验证结算面板的居中排版（跑完即还原）
func _ready() -> void:
	var sp: Control = preload("res://settlement_ui.gd").new()
	add_child(sp)
	var carrot: ItemData = load("res://item/carrot.tres")
	sp.show_summary("春季 第 3 天", 3,
		[{"item": carrot, "count": 3, "price": carrot.sell_price * 3}],
		carrot.sell_price * 3, 1234, "伙伴们把没干完的 2 格活补完了")
	for i in 5:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout     # 等入场动画把面板滑到位
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var box: Control = sp._box
	var r := box.get_global_rect()
	print("[settle] vp=%s box=%s center=%s vp_center=%s" % [str(vp), str(r.size),
		str(r.get_center()), str(vp * 0.5)])
	print("[settle] rows=%d income_text='%s' note_visible=%s stars_a=%.2f bg_a=%.2f" % [
		sp._list.get_child_count(), sp._income.text, str(sp._note.visible),
		sp._stars.modulate.a, sp._bg.modulate.a])
	print("[settle] box_in_view=%s" % str(vp.x > 0 and r.position.x >= -1.0
		and r.position.y >= -1.0 and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0))
	sp.queue_free()
	get_tree().quit()
