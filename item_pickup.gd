extends Area2D

@export var item: ItemData
@export var amount := 1

const FONT_PIX := preload("res://resources/font/IPix.ttf")

func _ready() -> void:
	if item == null:
		push_warning("ItemPickup 忘了指定 item,节点名: " + name)
		queue_free()
		return
	$Sprite2D.texture = item.icon
	# e26e: 掉落物轻轻浮动（小循环 tween, 捡走时跟着节点一起没）
	var spr := $Sprite2D as Sprite2D
	var base_y := spr.position.y
	var tw := spr.create_tween().set_loops()
	tw.tween_property(spr, "position:y", base_y - 3.0, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(spr, "position:y", base_y, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if Inventory.add_item(item, amount):
			Audio.play_sfx("pickup", -4.0, randf_range(0.94, 1.08))
			_float_text("%s x%d" % [item.display_name, amount])
			queue_free()


# e26e: 捡到东西在原地飘一行字（挂在父节点上, 自己 freed 也不影响它飘完）
func _float_text(txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.9, 0.95, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.size = Vector2(200, 20)
	l.position = global_position + Vector2(-100, -34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 60
	get_parent().add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 26.0, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)
