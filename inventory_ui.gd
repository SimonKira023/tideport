# inventory_ui.gd —— 快捷栏（hotbar）：主界面底部的一行 6 格
# 只显示 Inventory.hotbar（6 格），背包里的东西在这里看不到，要按 B 打开背包面板。
extends GridContainer

signal selection_changed   # 选中格或格子内容变了（右上角时钟靠它决定水壶状态显不显示）

var selected_index := 0
var player = null   # 由 game.gd 设置，或运行时找

func _ready() -> void:
	add_to_group("hotbar")   # clock.gd 等外部模块靠这个组找到快捷栏
	columns = Inventory.HOTBAR_SIZE
	Inventory.inventory_changed.connect(_refresh)
	for i in Inventory.HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(40, 40)
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 接下点击，别漏给「使用工具」
		panel.gui_input.connect(_on_slot_input.bind(i))
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon)
		vbox.add_child(label)
		panel.add_child(vbox)
		panel.set_meta("icon", icon)
		panel.set_meta("label", label)
		add_child(panel)
	_refresh()
	_update_selection()

# 数字键 1~6 直接选格；滚轮前后滚也能换格（Ctrl/⌘ + 滚轮是镜头缩放，别抢）
func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_6:
			var idx: int = key_event.keycode - KEY_1
			select(idx)
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.ctrl_pressed or mb.meta_pressed:
		return                       # 留给镜头缩放（见 game.gd _unhandled_input）
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_DOWN:
			_step(1)
		MOUSE_BUTTON_WHEEL_UP:
			_step(-1)
		_:
			return
	accept_event()

# 往下滚 = 往右挪一格；到头了绕回另一头
func _step(d: int) -> void:
	select(wrapi(selected_index + d, 0, Inventory.HOTBAR_SIZE))
	Audio.play_sfx("ui_click", -18.0)

# 用鼠标点快捷栏某一格 = 选中它（跟按数字键一样）
func _on_slot_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	select(index)
	Audio.play_sfx("ui_click")
	accept_event()

# 选中第 idx 格：更新高亮、把道具同步给玩家
func select(index: int) -> void:
	if index < 0 or index >= Inventory.HOTBAR_SIZE:
		return
	selected_index = index
	_update_selection()
	_sync_player_item()
	selection_changed.emit()

func _refresh() -> void:
	for i in get_child_count():
		var panel := get_child(i)
		var icon: TextureRect = panel.get_meta("icon")
		var label: Label = panel.get_meta("label")
		var s: Dictionary = Inventory.hotbar[i]
		if s["item"] != null:
			icon.texture = s["item"].icon
			label.text = str(s["count"]) if s["count"] > 1 else ""
			panel.tooltip_text = s["item"].info_text()   # 悬浮看详情（种子显示长成什么+收成价）
		else:
			icon.texture = null
			label.text = ""
			panel.tooltip_text = ""
	# ❗耗尽/换货后手持引用必须跟着格子刷新：
	#   种子用完时格子被清空，之后捡到的熔炉会落进这格 —— 但手持还攥着旧种子的话，
	#   左键就还在种树（残留 bug）。每次格子变化都重新同步选中格给玩家。
	_sync_player_item()
	selection_changed.emit()   # 选中格内容变了（如换上/撤下洒水壶）也要通知时钟

func _update_selection() -> void:
	for i in get_child_count():
		var panel := get_child(i)
		if i == selected_index:
			panel.add_theme_stylebox_override("panel", _selected_style())
		else:
			panel.add_theme_stylebox_override("panel", _normal_style())

func _sync_player_item() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var item: ItemData = Inventory.hotbar_item(selected_index)
	player.current_item = item

func _selected_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.21, 0.15, 0.9)
	sb.border_color = Color(1, 0.85, 0.4)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	return sb

func _normal_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.09, 0.72)
	sb.border_color = Color(0.45, 0.38, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb
