# 战斗手牌和敌方出牌共用纸质卡面, 插画与规则文字分区。
extends RefCounted

const Data := preload("res://scene/cards_data.gd")
const FONT := preload("res://resources/font/IPix.ttf")
const PAPER := Color("e8dfc5")
const INK := Color("303b3e")
const BLUE := Color("416777")
const RED := Color("a45f50")

static func build(card: Dictionary, side: String, dimensions: Vector2) -> Control:
	# 放大预览按整数倍绘制, 像素和文字一起放大。
	if dimensions.x >= 176:
		var enlarged: Control = build(card, side, dimensions * 0.5)
		enlarged.scale = Vector2(2, 2)
		return enlarged
	var root := Panel.new()
	root.name = "CardFace"
	root.set_meta("keep_ui_palette", true)
	root.size = dimensions
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color("655f50")
	style.set_border_width_all(1)
	root.add_theme_stylebox_override("panel", style)
	var w: float = dimensions.x
	var h: float = dimensions.y
	var accent: Color = RED if side == "foe" else BLUE
	var art_h: float = floorf(h * 0.44)
	var art := Data.art_of(card, side)
	if art != null:
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.texture = art
		image.position = Vector2(3, 3)
		image.size = Vector2(w - 6, art_h)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(image)
	var spell: bool = String(card.get("type", "unit")) == "spell"
	_badge(root, str(int(card.get("cost", 0))), Rect2(4, 4, 24, 26), accent, 16)
	_badge(root, "战术" if spell else "部队", Rect2(w - 32, 5, 28, 14), accent, 9)
	var title := _label(String(card.get("name", "")), 11, INK, Rect2(3, art_h + 2, w - 6, 23))
	title.name = "CardName"
	root.add_child(title)
	var rule: String = String(card.get("desc", ""))
	if not spell:
		var kw: String = String(card.get("kw", ""))
		rule = "守护邻军" if kw == "guard" else ("支援线射击" if kw == "ranged" else ("快速骑兵" if kw == "cav" else "前线部队"))
	var description := _label(rule, 8, INK.lightened(0.15), Rect2(5, art_h + 26, w - 10, h - art_h - 52), true)
	description.name = "CardRules"
	root.add_child(description)
	if spell:
		root.add_child(_label("作战命令", 9, accent, Rect2(5, h - 19, w - 10, 15)))
	else:
		_badge(root, str(int(card.get("atk", 0))), Rect2(4, h - 24, 23, 20), RED, 14)
		_badge(root, str(int(card.get("hp", 0))), Rect2(w - 27, h - 24, 23, 20), Color("53765f"), 14)
		root.add_child(_label("行 %d" % int(card.get("act", 1)), 10, INK, Rect2(28, h - 23, w - 56, 19)))
	return root

static func _label(text: String, font_size: int, color: Color, rect: Rect2, wrap: bool = false) -> Label:
	var label := Label.new()
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.add_theme_constant_override("line_spacing", -4)
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.clip_text = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

static func _badge(parent: Control, text: String, rect: Rect2, color: Color, font_size: int) -> void:
	var box := Panel.new()
	box.position = rect.position
	box.size = rect.size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = PAPER.darkened(0.12)
	style.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", style)
	box.add_child(_label(text, font_size, PAPER.lightened(0.1), Rect2(Vector2.ZERO, rect.size)))
	parent.add_child(box)
