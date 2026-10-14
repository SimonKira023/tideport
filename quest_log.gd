# 任务页: 玩家选择一条追踪, 生活经营和可选远征分开呈现。
extends Control

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
var embedded := false
var _visible := false
var _list_label: Label
var _goto_btn: Button
var _rows: VBoxContainer
var _war_btn: Button
var _others_expanded := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(680, 330)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_list_label = Label.new()
	_list_label.add_theme_font_override("font", PIXEL_FONT)
	_list_label.add_theme_font_size_override("font_size", 13)
	_list_label.text = "经营自己的港口. 钓鱼和远征都可以慢慢来."
	column.add_child(_list_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 230)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	_goto_btn = _button("查看当前指引")
	_goto_btn.pressed.connect(_on_goto_pressed)
	column.add_child(_goto_btn)
	_war_btn = _button("")
	_war_btn.pressed.connect(func(): Quests.choose_war_route(not Quests.war_route))
	column.add_child(_war_btn)
	Quests.changed.connect(_refresh)
	_visible = embedded
	visible = embedded
	_refresh()

func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_override("font", PIXEL_FONT)
	btn.add_theme_font_size_override("font_size", 13)
	return btn

func setup_embedded() -> void:
	embedded = true
	_visible = true
	show()
	_refresh()

func _refresh() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var tracked: Dictionary = Quests.tracked_task()
	var guide: Dictionary = Quests.guidance()
	_list_label.text = String(guide["caption"]) + ": " + String(guide["title"])
	_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list_label.custom_minimum_size.x = 640
	if not tracked.is_empty():
		var action := _description(String(guide["action"]), 14)
		action.visible = not action.text.is_empty()
		_rows.add_child(action)
		_rows.add_child(_description(String(guide["detail"]), 12))
	var other_tasks: Array = Quests.active().filter(func(task: Dictionary) -> bool: return String(task["id"]) != String(tracked.get("id", "")))
	if not other_tasks.is_empty():
		var toggle := _button(("收起其他事情" if _others_expanded else "其他事情, 有空再做") + " (%d)" % other_tasks.size())
		toggle.pressed.connect(func():
			_others_expanded = not _others_expanded
			_refresh())
		_rows.add_child(toggle)
	for task in other_tasks:
		if not _others_expanded:
			break
		var id: String = String(task["id"])
		var title := _button("追踪: " + String(task["title"]))
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.pressed.connect(Quests.track.bind(id))
		_rows.add_child(title)
		_rows.add_child(_description(String(task["desc"]), 12))
	_goto_btn.disabled = tracked.is_empty()
	_goto_btn.text = "打开相关面板" if Quests.page_for_task(String(tracked.get("id", ""))) != "" else "回到地图看指引"
	_war_btn.visible = Quests.has_done("sail_first") or Quests.war_route
	_war_btn.text = "暂停远征指引 (经营不受影响)" if Quests.war_route else "主动开启远征指引 (可选挑战)"

func _description(text: String, font_size: int) -> Label:
	var desc := Label.new()
	desc.text = text
	desc.add_theme_font_override("font", PIXEL_FONT)
	desc.add_theme_font_size_override("font_size", font_size)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 640
	return desc

func _on_goto_pressed() -> void:
	if not Quests.goto_active_page():
		var bp: Node = get_tree().get_first_node_in_group("backpack_panel")
		if bp != null and bp.has_method("close"):
			bp.call("close")

func open_panel() -> void:
	_visible = true
	show()
	_refresh()

func close_panel() -> void:
	_visible = false
	hide()

func on_backpack_page(_key: String) -> void:
	pass
