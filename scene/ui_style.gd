# 温馨农场主题统一默认控件和旧面板, 品质边框与战斗徽章保留语义颜色。
extends Node

const FONT := preload("res://resources/font/IPix.ttf")
const INK := Color("efdfb9")       # 兼容旧调用名, 现在表示暖纸底。
const SURFACE := Color("f8edce")
const RAISED := Color("e8ca92")
const EDGE := Color("95633f")
const PAPER := Color("503827")     # 兼容旧调用名, 现在表示深棕文字。
const MUTED := Color("846b50")
const GOLD := Color("a47432")
const TEAL := Color("6e9774")
var shared_theme: Theme

func _ready() -> void:
	shared_theme = make_theme()
	get_tree().node_added.connect(_on_node_added)
	_install_tree(get_tree().root)

func _on_node_added(node: Node) -> void:
	if node is Control:
		_install_id.call_deferred(node.get_instance_id())

# 自检和动态列表可能在本帧销毁节点, 延迟队列只保存实例 ID。
func _install_id(instance_id: int) -> void:
	var node: Object = instance_from_id(instance_id)
	if is_instance_valid(node) and node is Node:
		_install(node as Node)

func _install_tree(node: Node) -> void:
	_install(node)
	for child in node.get_children():
		_install_tree(child)

func _install(node: Node) -> void:
	if not is_instance_valid(node) or not node is Control:
		return
	var control := node as Control
	if not control.get_parent() is Control and control.theme == null:
		control.theme = shared_theme
	# 布局重算不随缩放动画抖动, 像素字和图标保持最近邻采样。
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _preserve_palette(control):
		return
	_warm_control(control)
	if (control is Label or control is RichTextLabel or control is Button) and not control.has_meta("cozy_text_watch"):
		control.set_meta("cozy_text_watch", true)
		control.theme_changed.connect(_queue_text_refresh.bind(control.get_instance_id()))

func _queue_text_refresh(instance_id: int) -> void:
	_refresh_text_id.call_deferred(instance_id)

func _refresh_text_id(instance_id: int) -> void:
	var object: Object = instance_from_id(instance_id)
	if not is_instance_valid(object) or not object is Control:
		return
	var control := object as Control
	if _preserve_palette(control) or (not control is Button and not _on_paper(control)):
		return
	var keys: Array[String] = []
	keys.append("default_color" if control is RichTextLabel else "font_color")
	if control is Button:
		keys.append("font_hover_color")
		keys.append("font_pressed_color")
		keys.append("font_disabled_color")
	for key: String in keys:
		var old_color: Color = control.get_theme_color(key)
		if old_color.v > 0.55:
			var color: Color = PAPER if old_color.s < 0.3 else Color.from_hsv(old_color.h, minf(old_color.s, 0.65), 0.48, old_color.a)
			control.add_theme_color_override(key, color)

func _preserve_palette(control: Control) -> bool:
	var ancestor: Node = control
	while ancestor != null:
		if bool(ancestor.get_meta("keep_ui_palette", false)):
			return true
		ancestor = ancestor.get_parent()
	return false

func _warm_control(control: Control) -> void:
	# 木框是程序化绘制的, 只改配色而不改变布局厚度。
	var script: Script = control.get_script() as Script
	if script != null and script.resource_path == "res://wood_frame.gd":
		control.set("inner_color", INK)
		control.set("inner_top_color", SURFACE)
		control.set_meta("cozy_surface", true)
		control.queue_redraw()
	if control is Button:
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var old: StyleBox = control.get_theme_stylebox(state)
			var replacement: StyleBox = shared_theme.get_stylebox(state, "Button").duplicate()
			_copy_margins(old, replacement)
			control.add_theme_stylebox_override(state, replacement)
		control.add_theme_color_override("font_color", PAPER)
		control.add_theme_color_override("font_hover_color", PAPER)
		control.add_theme_color_override("font_pressed_color", PAPER)
		control.add_theme_color_override("font_disabled_color", MUTED)
		control.set_meta("cozy_surface", true)
	elif control is PanelContainer or control is Panel:
		var extent: Vector2 = control.size.max(control.get_combined_minimum_size())
		# 小型血量/费用/阵营徽章需要维持自己的高对比底色。
		if control is Panel and extent.x <= 64 and extent.y <= 40:
			control.set_meta("cozy_surface", false)
		else:
			var old: StyleBox = control.get_theme_stylebox("panel")
			var edge: Color = EDGE
			if old is StyleBoxFlat and (old as StyleBoxFlat).border_color.s > 0.3:
				edge = (old as StyleBoxFlat).border_color.darkened(0.1)
			var replacement: StyleBoxFlat = panel(INK, edge)
			_copy_margins(old, replacement)
			control.add_theme_stylebox_override("panel", replacement)
			control.set_meta("cozy_surface", true)
			if extent.x >= 240 and extent.y >= 120 and not control.has_meta("cozy_trim"):
				control.set_meta("cozy_trim", true)
				control.draw.connect(_draw_cozy_frame.bind(control))
				control.queue_redraw()
	elif control is ProgressBar:
		control.add_theme_stylebox_override("background", panel(Color("d6bf96"), EDGE, 0))
		control.add_theme_color_override("font_color", PAPER)
	elif control is ColorRect and _on_paper(control):
		var rect := control as ColorRect
		if rect.size.x >= 120 and rect.size.y >= 80 and rect.color.v > 0.06 and rect.color.v < 0.5 and rect.color.a > 0.5:
			rect.color = INK
	if (control is Label or control is RichTextLabel) and _on_paper(control):
		var key: String = "font_color" if control is Label else "default_color"
		var old_color: Color = control.get_theme_color(key)
		if old_color.v > 0.55:
			var color: Color = PAPER if old_color.s < 0.3 else Color.from_hsv(old_color.h, minf(old_color.s, 0.65), 0.48, old_color.a)
			control.add_theme_color_override(key, color)
		control.add_theme_constant_override("outline_size", 0)

func _on_paper(control: Control) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor.has_meta("cozy_surface"):
			return bool(ancestor.get_meta("cozy_surface"))
		ancestor = ancestor.get_parent()
	return false

func _copy_margins(source: StyleBox, target: StyleBox) -> void:
	if source == null:
		return
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		target.set_content_margin(side, source.get_content_margin(side))

# 细木框直接绘制在面板上, 不增加节点或改变容器最小尺寸。
func _draw_cozy_frame(control: Control) -> void:
	var w: float = floorf(control.size.x)
	var h: float = floorf(control.size.y)
	if w < 16 or h < 16:
		return
	var wood := Color("b8804a")
	var shade := Color("80502f")
	var light := Color("edbd75")
	control.draw_rect(Rect2(0, 0, w, 4), wood)
	control.draw_rect(Rect2(0, 0, 4, h), wood)
	control.draw_rect(Rect2(0, h - 4, w, 4), shade)
	control.draw_rect(Rect2(w - 4, 0, 4, h), shade)
	control.draw_rect(Rect2(4, 4, w - 8, 1), light)
	control.draw_rect(Rect2(4, 4, 1, h - 8), light)
	control.draw_rect(Rect2(4, h - 5, w - 8, 1), wood)
	control.draw_rect(Rect2(w - 5, 4, 1, h - 8), wood)
	for x in range(12, int(w) - 16, 48):
		control.draw_rect(Rect2(x, 1, 12, 1), light)
		control.draw_rect(Rect2(x + 8, h - 3, 10, 1), wood)
	for corner: Vector2 in [Vector2(1, 1), Vector2(w - 3, 1), Vector2(1, h - 3), Vector2(w - 3, h - 3)]:
		control.draw_rect(Rect2(corner, Vector2(2, 2)), shade)

static func panel(bg: Color = INK, edge: Color = EDGE, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(2)
	style.border_width_bottom = 3
	style.set_corner_radius_all(0)
	style.set_content_margin_all(margin)
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 13
	for type_name in ["Label", "Button", "CheckButton", "CheckBox", "LineEdit", "OptionButton", "RichTextLabel"]:
		result.set_color("font_color", type_name, PAPER)
		result.set_color("font_hover_color", type_name, PAPER)
		result.set_color("font_pressed_color", type_name, PAPER)
		result.set_color("font_disabled_color", type_name, MUTED)
	for type_name in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type_name, panel(SURFACE, EDGE, 8))
		result.set_stylebox("hover", type_name, panel(RAISED, TEAL, 8))
		result.set_stylebox("pressed", type_name, panel(Color("d4dda8"), EDGE, 8))
		result.set_stylebox("disabled", type_name, panel(Color("dfd3b4"), Color("b09a78"), 8))
		var focus := panel(Color(0, 0, 0, 0), GOLD, 0)
		focus.set_border_width_all(2)
		result.set_stylebox("focus", type_name, focus)
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_stylebox("panel", "Panel", panel())
	result.set_stylebox("normal", "LineEdit", panel(SURFACE, EDGE, 8))
	result.set_stylebox("focus", "LineEdit", panel(SURFACE, GOLD, 8))
	result.set_stylebox("panel", "TooltipPanel", panel(INK, GOLD, 10))
	result.set_color("font_color", "TooltipLabel", PAPER)
	result.set_color("default_color", "RichTextLabel", PAPER)
	result.set_stylebox("panel", "PopupMenu", panel(SURFACE, EDGE, 8))
	result.set_color("font_color", "PopupMenu", PAPER)
	result.set_color("font_hover_color", "PopupMenu", PAPER)
	result.set_stylebox("hover", "PopupMenu", panel(Color("d4dda8"), TEAL, 4))
	result.set_stylebox("background", "ProgressBar", panel(Color("d3bd93"), EDGE, 0))
	result.set_stylebox("fill", "ProgressBar", panel(TEAL, TEAL, 0))
	for type_name: String in ["Tree", "ItemList"]:
		result.set_stylebox("panel", type_name, panel(SURFACE, EDGE, 6))
		result.set_stylebox("selected", type_name, panel(Color("d4dda8"), TEAL, 2))
		result.set_color("font_color", type_name, PAPER)
		result.set_color("font_selected_color", type_name, PAPER)
	result.set_stylebox("panel", "TabContainer", panel())
	result.set_stylebox("tab_selected", "TabContainer", panel(SURFACE, EDGE, 8))
	result.set_stylebox("tab_unselected", "TabContainer", panel(RAISED, EDGE, 8))
	result.set_color("font_selected_color", "TabContainer", PAPER)
	result.set_color("font_unselected_color", "TabContainer", MUTED)
	for type_name: String in ["HScrollBar", "VScrollBar"]:
		result.set_stylebox("scroll", type_name, panel(Color("d3bd93"), EDGE, 0))
		result.set_stylebox("grabber", type_name, panel(RAISED, EDGE, 0))
		result.set_stylebox("grabber_highlight", type_name, panel(SURFACE, GOLD, 0))
	result.set_constant("outline_size", "TooltipLabel", 0)
	result.set_constant("separation", "VBoxContainer", 8)
	result.set_constant("separation", "HBoxContainer", 8)
	return result
