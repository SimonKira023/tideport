# quest_log.gd —— 任务栏（挂在 HUD 上）
#
# 用户要求「esc 增加任务栏」：ESC/B 打开背包时任务栏一并显示，关背包一起收。
# 数据来自 Quests（autoload），changed 时若正显示就刷新。
# IPix.ttf 字形有限：文案用半角标点，爱心/箭头等符号用 ASCII 代替。
extends Control

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _box: PanelContainer
var _list_label: Label
var _visible := false
var embedded := false            # e13j: 嵌进背包「任务」页签（铺满页内容, 不再是左侧竖栏）

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE    # 任务栏不挡操作，只展示
	_build()
	if embedded:
		_refresh()     # 嵌进背包页签: 开页就有内容（不再靠 open_panel 触发）
	else:
		hide()
	Quests.changed.connect(_refresh_if_visible)

# 背包「任务」页签里用（e13j）: 内容铺满整个页, 生命周期归背包页管
func setup_embedded() -> void:
	embedded = true
	_visible = true
	_refresh()

func _build() -> void:
	_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.92)
	style.border_color = Color(0.62, 0.47, 0.28)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_box.add_theme_stylebox_override("panel", style)
	# 任务栏只活在背包「任务」页签里（e13j）: 铺满整页; 独立竖栏模式已废
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(vbox)

	var title := Label.new()
	title.text = "- 任务 -"
	title.add_theme_font_override("font", PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	_list_label = Label.new()
	_list_label.add_theme_font_override("font", PIXEL_FONT)
	_list_label.add_theme_font_size_override("font_size", 13)
	_list_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_list_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_list_label)

func _refresh() -> void:
	var tasks: Array = Quests.active()
	if tasks.is_empty():
		_list_label.text = "暂无任务\n\n努力经营这片田地吧!"
		return
	var lines: Array[String] = []
	for i in tasks.size():
		var t: Dictionary = tasks[i]
		lines.append("%d. %s" % [i + 1, str(t["title"])])
		lines.append("   %s" % str(t["desc"]))
		if i < tasks.size() - 1:
			lines.append(" ")
	_list_label.text = "\n".join(lines)

func _refresh_if_visible() -> void:
	if _visible:
		_refresh()

# 由 game.gd 在背包开/合时调（任务栏生命周期跟着背包走）
func open_panel() -> void:
	_visible = true
	show()
	_refresh()

func close_panel() -> void:
	_visible = false
	hide()

# 科技/行政/建造/团队页都压住左侧任务栏：这些页开着时收起任务栏，
# 切回别的页再亮回来（_visible 不动，生命周期仍跟着背包走）。
func on_backpack_page(key: String) -> void:
	if key == "tech" or key == "admin" or key == "build" or key == "team":
		hide()
	elif _visible:
		show()
