# bin_ui.gd —— 售卖箱面板（走近箱子按 F 打开, shipping_bin.gd 负责开）
#   左栏：背包 30 格（点一格 -> 整格放进右边的箱子, 工具不收）
#   右栏：箱子里已有的货 + 合计金额（反悔可一键全部取回）
# 投进去的货在关箱时统一卖掉（e29b）: 哥布林渠道立刻入账, 海外渠道次日到账。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _visible := false
var _bin: Node = null                # scene/shipping_bin.gd 实例（open_panel 传入）
var _bag_panels: Array = []          # 左栏 30 格 PanelContainer（meta: icon/label）
var _bin_list: VBoxContainer = null  # 右栏货单容器
var _total_label: Label = null
var _flash_label: Label = null
var _goblin_btn: Button = null       # 贸易渠道切换（e13f）
var _sea_btn: Button = null

# 渠道切换（e29a）: 投放时按当前渠道打标 —— 哥布林关箱即售, 海外 +40% 次日到账
func _set_mode(m: String) -> void:
	if _bin != null:
		_bin.mode = m
	Audio.play_sfx("ui_click", -10.0)
	_flash("渠道: %s" % ("哥布林贸易 (关箱即售)" if m == "哥布林" else "海外贸易 (+40%金, 次日到账, 每累积卖出1000金+1声望)"))
	_refresh()

func _ready() -> void:
	add_to_group("bin_panel")        # shipping_bin 靠组找到这个面板
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

	vbox.add_child(_label("售卖箱 - 关箱即售, 海外次日回款", 20,
		Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	vbox.add_child(cols)

	# ---------- 左：背包 30 格（6 快捷栏 + 24 背包）----------
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	left.add_child(_label("背包 (左键放1个, 右键整格)", 13, Color(0.85, 0.8, 0.7)))
	var grid := GridContainer.new()
	grid.columns = Inventory.BACKPACK_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
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

	# ---------- 中：箭头 ----------
	var mid := _label("->", 24, Color(1, 0.85, 0.4))
	mid.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cols.add_child(mid)

	# ---------- 右：箱里的货 ----------
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(_label("箱里的货 (关箱即售出)", 13, Color(0.85, 0.8, 0.7)))
	# —— 贸易渠道（e29a）: 哥布林=关箱即售原价到账 / 海外=+40%金 次日到账 + 每累积1000金+1声望 ——
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 6)
	right.add_child(modes)
	_goblin_btn = Button.new()
	_goblin_btn.text = "哥布林贸易"
	_goblin_btn.custom_minimum_size = Vector2(150, 28)
	_goblin_btn.add_theme_font_override("font", PIXEL_FONT)
	_goblin_btn.add_theme_font_size_override("font_size", 12)
	_goblin_btn.tooltip_text = "原价卖给哥布林商队, 关箱立即到账"
	_goblin_btn.pressed.connect(func() -> void: _set_mode("哥布林"))
	modes.add_child(_goblin_btn)
	_sea_btn = Button.new()
	_sea_btn.text = "海外贸易 +40%"
	_sea_btn.custom_minimum_size = Vector2(150, 28)
	_sea_btn.add_theme_font_override("font", PIXEL_FONT)
	_sea_btn.add_theme_font_size_override("font_size", 12)
	_sea_btn.tooltip_text = "卖价上浮四成, 次日到账, 每累积卖出 1000 金 +1 声望"
	_sea_btn.pressed.connect(func() -> void: _set_mode("海外"))
	modes.add_child(_sea_btn)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(310, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_bin_list = VBoxContainer.new()
	_bin_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bin_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_bin_list)
	_total_label = _label("", 14, Color(0.98, 0.85, 0.45))
	right.add_child(_total_label)
	var take := Button.new()
	take.text = "全部取回"
	take.custom_minimum_size = Vector2(0, 30)
	take.add_theme_font_override("font", PIXEL_FONT)
	take.add_theme_font_size_override("font_size", 13)
	take.pressed.connect(_take_back)
	right.add_child(take)

	_flash_label = _label("", 13, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_flash_label)

	var close := Button.new()
	close.text = "售出 (F / Esc)"
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
	# 左：背包格
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
	# 右：箱里的货（bin 没绑上就只刷背包）
	if _bin == null or _bin_list == null:
		return
	for c in _bin_list.get_children():
		c.free()     # 不在货单子节点的信号里, 直接 free 干净
	for e in _bin.pending:
		var it: ItemData = e["item"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = it.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var mtag: String = "[海]" if String(e.get("mode", "哥布林")) == "海外" else ""
		var name_lb := _label("%s %s x%d" % [mtag, it.display_name, int(e["count"])], 13,
			Color(0.95, 0.93, 0.88))
		name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lb)
		row.add_child(_label("%d金" % int(e["price"]), 13, Color(0.98, 0.85, 0.45)))
		_bin_list.add_child(row)
	# 海外在途（e13f）: 货已在船上, 显示到账金额
	if _bin.sea_pending_total() > 0:
		_bin_list.add_child(_label("在途: 海外商船载着 %d 金 (次日到账)"
			% _bin.sea_pending_total(), 12, Color(0.55, 0.9, 0.85)))
	var mode_now: String = String(_bin.mode)
	_goblin_btn.modulate = Color(1.2, 1.15, 1.0) if mode_now == "哥布林" else Color(0.62, 0.6, 0.56)
	_sea_btn.modulate = Color(1.2, 1.15, 1.0) if mode_now == "海外" else Color(0.62, 0.6, 0.56)
	_total_label.text = "共 %d 件, 关箱售得 %d 金" % [_bin.pending_count(), _bin.pending_total()]

# ---------------- 点背包格放货 ----------------
# e43: 左键一次只放 1 个 (攒货细水长流), 右键才把整格全倒进箱子。
func _on_bag_slot(event: InputEvent, index: int) -> void:
	if _bin == null:
		return
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
	if _bin.deposit_one(it, put) > 0:
		if all:
			_flash("放进 %s x%d" % [it.display_name, n])
		else:
			_flash("放进 %s x1 (右键可整格)" % it.display_name)
	else:
		Audio.play_sfx("error", -4.0)
		_flash("工具不收, 其他东西都能卖")

# 全部取回（放不下的会留在箱里）
func _take_back() -> void:
	if _bin == null:
		return
	var n: int = _bin.take_back_all()
	if n > 0:
		_flash("取回了 %d 件货" % n)
	else:
		_flash("箱子里是空的")

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
# 会被 shipping_bin 的 _unhandled_input 也收到，关了又立刻开。
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close_panel()
		get_viewport().set_input_as_handled()

func open_panel(bin: Node) -> void:
	if _visible:
		return
	_bin = bin
	_visible = true
	show()
	TimeManager.push_ui_pause()      # 摆货的时候时间停住
	Audio.play_sfx("ui_open")
	_flash_label.text = ""
	_refresh()
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	if _bin != null:
		_bin.sell_now()      # e29b: 关箱即售 —— 哥布林货立刻入账, 海外货上船次日到
	_bin = null
	TimeManager.pop_ui_pause()
	Audio.play_sfx("ui_close")
	closed.emit()

func is_open() -> bool:
	return _visible
