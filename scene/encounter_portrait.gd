# 领主与巡逻队长共用的人物信息卡, 头像和文字使用固定列宽。
extends PanelContainer

const Style := preload("res://scene/ui_style.gd")
const Portraits := preload("res://scene/mood_portrait.gd")

var portrait: TextureRect
var message: Label

func configure(key: String, title: String, text: String, accent: Color, width: float) -> void:
	custom_minimum_size.x = width
	add_theme_stylebox_override("panel", Style.panel(Style.SURFACE, accent.darkened(0.25), 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(128, 128)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = Portraits.portrait_texture(key)
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = maxf(120.0, width - 162.0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 10)
	row.add_child(info)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_override("font", Style.FONT)
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", Style.PAPER)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(heading)
	message = Label.new()
	message.text = text
	message.add_theme_font_override("font", Style.FONT)
	message.add_theme_font_size_override("font_size", 12)
	message.add_theme_color_override("font_color", Style.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(message)
