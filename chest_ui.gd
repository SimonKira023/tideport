# chest_ui.gd —— e45 储物箱面板（走近箱子按 F 打开, game._station_interact_cell 负责开）
#   左栏：箱里的东西（左键取 1 个到背包, 右键整格取走）
#   右栏：背包 30 格（左键存 1 个, 右键整格存进去）
# 跟售卖箱(bin_ui.gd)长得像, 但这里**不卖东西** —— 只是腾背包的一个仓库, 关箱也不结算。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _visible := false
var _cell := Vector2i(9999, 9999)     # 开着的那座储物箱
var _list_box: VBoxContainer = null   # 左栏箱里的东西
var _title_label: Label = null        # 标题：储物箱 / 筒仓（两座共用这只面板）
var _bag_panels: Array = []           # 右栏 30 格（meta: icon/label）
var _info_label: Label = null
var _flash_label: Label = null

func _ready() -> void:
	add_to_group("chest_panel")
	# 见 shop_ui.gd 的注释：挂在 HUD(CanvasLayer) 下的 Control 默认 0 尺寸，
	# 不自己声明全屏的话遮罩和居中都会失效（面板挤在左上角）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Inventory.inventory_changed.connect(_refresh)

# ---------------- 搭面板 ----------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.14, 0.11, 0.09, 0.97)
	box_style.border_color = Color(0.62, 0.47, 0.28)
	box_style.set_border_width_all(3)
	box_style.set_corner_radius_all(8)
	box_style.content_margin_left = 22
	box_style.content_margin_right = 22
	box_style.content_margin_top = 16
	box_style.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", box_style)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	_title_label = _label("储物箱", 20, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title_label)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	vbox.add_child(cols)

	# ---------- 左：箱里的东西 ----------
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(_label("箱里 (左键取1个, 右键整格)", 13, Color(0.85, 0.8, 0.7)))
	var lscroll := ScrollContainer.new()
	lscroll.custom_minimum_size = Vector2(300, 250)
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lscroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	lscroll.add_child(_list_box)
	_info_label = _label("", 13, Color(0.98, 0.85, 0.45))
	left.add_child(_info_label)
	var take_all := Button.new()
	take_all.text = "全部取出"
	take_all.custom_minimum_size = Vector2(0, 30)
	take_all.add_theme_font_override("font", PIXEL_FONT)
	take_all.add_theme_font_size_override("font_size", 13)
	take_all.pressed.connect(_take_all)
	# e46: 两个按钮并排, 省一行高度（面板本来就撑得挺满）
	var left_row := HBoxContainer.new()
	left_row.add_theme_constant_override("separation", 6)
	take_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_row.add_child(take_all)
	left_row.add_child(_small_btn("整理箱子", _sort_chest))
	left.add_child(left_row)

	# ---------- 中：箭头 ----------
	var mid := _label("<-  ->", 18, Color(1, 0.85, 0.4))
	mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cols.add_child(mid)

	# ---------- 右：背包 30 格 ----------
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(_label("背包 (左键存1个, 右键整格)", 13, Color(0.85, 0.8, 0.7)))
	var grid := GridContainer.new()
	grid.columns = Inventory.BACKPACK_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	right.add_child(grid)
	var total: int = Inventory.HOTBAR_SIZE + Inventory.BACKPACK_SIZE
	for i in total:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(44, 44)
		panel.add_theme_stylebox_override("panel", _slot_style(i < Inventory.HOTBAR_SIZE))
		panel.gui_input.connect(_on_bag_slot.bind(i))

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var count := Label.new()
		count.add_theme_font_override("font", PIXEL_FONT)
		count.add_theme_font_size_override("font_size", 12)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var vb := VBoxContainer.new()
		vb.add_child(icon)
		vb.add_child(count)
		panel.add_child(vb)
		panel.set_meta("icon", icon)
		panel.set_meta("label", count)
		grid.add_child(panel)
		_bag_panels.append(panel)

	var store_all := Button.new()
	store_all.text = "全部存入"
	store_all.custom_minimum_size = Vector2(0, 30)
	store_all.add_theme_font_override("font", PIXEL_FONT)
	store_all.add_theme_font_size_override("font_size", 13)
	store_all.pressed.connect(_store_all)
	store_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 6)
	right_row.add_child(store_all)
	right_row.add_child(_small_btn("整理背包", _sort_bag))
	right.add_child(right_row)

	_flash_label = _label("", 13, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_flash_label)

	var close := Button.new()
	close.text = "关上 (F / Esc)"
	close.custom_minimum_size = Vector2(0, 32)
	close.add_theme_font_override("font", PIXEL_FONT)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(close_panel)
	vbox.add_child(close)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# 小按钮（e46「整理箱子/整理背包」用）——跟「全部取出/存入」一样高，宽度按文字自适应
func _small_btn(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(handler)
	return b

func _slot_style(is_hotbar: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if is_hotbar:
		sb.bg_color = Color(0.22, 0.18, 0.14, 0.9)
		sb.border_color = Color(0.6, 0.48, 0.34)
	else:
		sb.bg_color = Color(0.16, 0.14, 0.12, 0.9)
		sb.border_color = Color(0.4, 0.35, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb

# ---------------- 刷新 ----------------
func _refresh() -> void:
	if not _visible:
		return
	# 右：背包格
	var list := Inventory.slot_list()
	for i in _bag_panels.size():
		var panel: PanelContainer = _bag_panels[i]
		var icon: TextureRect = panel.get_meta("icon")
		var count: Label = panel.get_meta("label")
		if i < list.size() and list[i]["item"] != null:
			var it: ItemData = list[i]["item"]
			icon.texture = it.icon
			count.text = str(list[i]["count"]) if int(list[i]["count"]) > 1 else ""
			panel.tooltip_text = it.info_text()
		else:
			icon.texture = null
			count.text = ""
			panel.tooltip_text = ""
	# 左：箱里的东西
	# ❗必须 queue_free: 点箱子行取东西时, gui_input 信号链里就会走到这
	#   （_take -> Inventory.add_item -> inventory_changed -> 本函数）,
	#   正在发信号的那一行还在栈上 —— 立即 free 等于把发射者拆了, 信号返回
	#   就是 use-after-free 真机闪退（「箱子取东西崩」的根源）。
	#   queue_free 拖到帧末, 信号链安全走完（bin_ui 的行是纯展示没挂信号,
	#   那边 free 没事, 这边的行是可以点的, 不一样）。
	for c in _list_box.get_children():
		c.queue_free()
	var items := Structures.chest_items(_cell)
	for idx in items.size():
		var e: Dictionary = items[idx]
		var it: ItemData = e.get("item", null)
		if it == null:
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _row_style())
		row.gui_input.connect(_on_chest_row.bind(idx))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		row.add_child(hb)
		var icon2 := TextureRect.new()
		icon2.texture = it.icon
		icon2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon2.custom_minimum_size = Vector2(22, 22)
		icon2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(icon2)
		var name_lb := _label("%s x%d" % [it.display_name, int(e["count"])], 13,
			Color(0.95, 0.93, 0.88))
		name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(name_lb)
		_list_box.add_child(row)
	if items.is_empty():
		_list_box.add_child(_label("(空箱)", 13, Color(0.6, 0.56, 0.5)))
	_info_label.text = "共 %d 件, 占 %d/%d 格" % [Structures.chest_count(_cell),
		Structures.chest_used_slots(_cell), Structures.CHEST_SLOTS]

func _row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.17, 0.14, 0.85)
	sb.border_color = Color(0.42, 0.36, 0.29)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

# ---------------- 从箱里取 ----------------
# e45: 左键拿 1 个, 右键整格拿走；背包放不下的部分原样退回箱里。
func _on_chest_row(event: InputEvent, idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var all := mb.button_index == MOUSE_BUTTON_RIGHT
	if mb.button_index != MOUSE_BUTTON_LEFT and not all:
		return
	_take(idx, all)

func _take(idx: int, all: bool) -> void:
	var got := Structures.chest_take(_cell, idx, all)
	if got.is_empty():
		return
	var it: ItemData = got["item"]
	var n := int(got["count"])
	var before := Inventory.count_item(it)
	Inventory.add_item(it, n)
	var moved := Inventory.count_item(it) - before
	if moved < n:
		Structures.chest_deposit(_cell, it, n - moved)   # 装不下的退回去
	if moved > 0:
		Audio.play_sfx("ui_click", -10.0)
		_flash("取出 %s x%d" % [it.display_name, moved])
	else:
		Audio.play_sfx("error", -4.0)
		_flash("背包满了, 拿不动")
	_refresh()

func _take_all() -> void:
	var total := 0
	var left := 0
	var drained := Structures.chest_drain(_cell)
	for e in drained:
		var it: ItemData = e["item"]
		var n := int(e["count"])
		var before := Inventory.count_item(it)
		Inventory.add_item(it, n)
		var moved := Inventory.count_item(it) - before
		total += moved
		if moved < n:
			Structures.chest_deposit(_cell, it, n - moved)
			left += n - moved
	if total > 0:
		_flash("取回 %d 件" % total)
	else:
		_flash("箱子里是空的" if left == 0 else "背包满了, 一件也没拿动")
	_refresh()

# ---------------- 往箱里存 ----------------
func _on_bag_slot(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var all := mb.button_index == MOUSE_BUTTON_RIGHT
	if mb.button_index != MOUSE_BUTTON_LEFT and not all:
		return
	var s: Dictionary = Inventory.get_slot(index)
	var it: ItemData = s["item"]
	if it == null:
		return
	var n: int = int(s["count"])
	var put: int = n if all else 1
	var got := Structures.chest_deposit(_cell, it, put)
	if got > 0:
		Inventory.remove_item(it, got)
		Audio.play_sfx("ui_click", -10.0)
		_flash("存入 %s x%d" % [it.display_name, got])
	else:
		Audio.play_sfx("error", -4.0)
		_flash("箱子满了 (%d 格都占着)" % Structures.CHEST_SLOTS)
	_refresh()

func _store_all() -> void:
	var slots := Inventory.slot_list()
	var kinds := 0
	var stuffed := 0
	for i in slots.size():
		var s: Dictionary = slots[i]
		var it: ItemData = s["item"]
		if it == null:
			continue
		var got := Structures.chest_deposit(_cell, it, int(s["count"]))
		if got > 0:
			Inventory.remove_item(it, got)
			kinds += 1
		if got < int(s["count"]):
			stuffed += 1
	if kinds > 0:
		_flash("存了 %d 种东西" % kinds)
	elif stuffed > 0:
		_flash("箱子满了 (%d 格都占着)" % Structures.CHEST_SLOTS)
	else:
		_flash("背包是空的")
	_refresh()

# ---------------- 一键整理（e46） ----------------
# 箱子这边只动箱里那几格（并叠 + 工具排最前），不碰背包
func _sort_chest() -> void:
	if Structures.sort_chest(_cell):
		Audio.play_sfx("ui_click", -10.0)
		_flash("箱子整理好了")
	else:
		Audio.play_sfx("error", -4.0)
		_flash("箱子里是空的")
	_refresh()

# 背包这边是快捷栏 + 背包一起排 —— 工具会落到最前面的快捷栏, 按 1~6 直接拿
func _sort_bag() -> void:
	Inventory.sort_all()
	Audio.play_sfx("ui_click", -10.0)
	_flash("背包整理好了 (工具排最前)")
	_refresh()

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text
	_flash_label.modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_flash_label, "modulate:a", 0.0, 0.6)

# ---------------- 开合 ----------------
# 用 _input（早于 _unhandled_input）来关，标记已处理 —— 不然同一按 F
# 会被 game 的设施交互也收到，关了又立刻开。
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close_panel()
		get_viewport().set_input_as_handled()

func open(cell: Vector2i) -> void:
	if _visible:
		return
	_cell = cell
	# e49: 筒仓跟储物箱共用这只面板, 标题得跟着是哪一座走（不然筒仓点开来写着「储物箱」）
	if _title_label != null:
		_title_label.text = String(Structures.building_cost(Structures.kind_of(cell)).get("name", "储物箱"))
	_visible = true
	show()
	TimeManager.push_ui_pause()      # 翻箱子的时候时间停住
	Audio.play_sfx("ui_open")
	_flash_label.text = ""
	_refresh()
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	_cell = Vector2i(9999, 9999)
	TimeManager.pop_ui_pause()
	Audio.play_sfx("ui_close")
	closed.emit()

func is_open() -> bool:
	return _visible

# 面板上正开着的是哪座箱子（自检/外面查询用）
func cell() -> Vector2i:
	return _cell