extends RefCounted
# 面板打开时只淡入, 保持像素字和图标的原始缩放, 避免非整数缩放闪烁.
# 关闭立即生效, 不拖延输入和可见性状态.

static func pop_in(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
