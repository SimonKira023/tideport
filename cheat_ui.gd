# cheat_ui.gd —— 作弊面板（按 P 键唤醒）
#
# 用途：调试 / 测试，一键加钱、加资源、推进工地、白嫖伙伴。
#   加钱：+100 / +1000 / +10000
#   加资源：木头 / 石头 / 铁矿石 / 铁 / 各类种子 / 作物，每次 +10 或 +99（可切换）
#   工地：+5 人工 / 直接建成（当前工地；没开工就提示）
#   伙伴：免费招 1 人（先补足价钱再走正规招募，预览/信号跟篝火一致）
#
# 规则：
#   · 只给「材料和种子/作物」复制，工具类（锄头/斧头/镐等）不给 —— 怕坏存档平衡
#   · 背包装不下时多余部分丢弃（add_item 返回 false 就提示满了）
#   · 按 P / Esc / 空格 / F 关闭；开着时时间冻结（push_ui_pause），关闭恢复
#
# ❗IPix.ttf 字形硬约束：不用全角标点、不用 | → ■ ·，箭头一律 ASCII ->
extends Control

signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const GUARD := 0.5       # 刚弹出来的这段时间不吃输入

# 可加的资源清单（item/ 下 .tres 文件名，不含扩展名）
const ITEMS := [
	"wood", "stone", "iron_ore", "iron",
	"seed", "carrot_seed", "cabbage_seed", "pumpkin_seed", "tree_seed",
	"wheat", "potato", "carrot", "cabbage", "pumpkin",
]
const ITEM_STEPS := [10, 99]
const MONEY_STEPS := [100, 1000, 10000]

var _open := false
var _guard := 0.0
var _step := 10
var _money_label: Label
var _tip: Label
var _step_btns := {}     # 步长按钮（10/99），选中提亮

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

# ---------------- 搭界面 ----------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.07, 0.96)
	sb.border_color = Color(0.62, 0.5, 0.32)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := _label("作弊面板", 20, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(title)

	_money_label = _label("", 14, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_money_label)

	# 加钱一排
	var money_row := HBoxContainer.new()
	money_row.alignment = BoxContainer.ALIGNMENT_CENTER
	money_row.add_theme_constant_override("separation", 8)
	vbox.add_child(money_row)
	money_row.add_child(_label("加钱", 13, Color(0.85, 0.8, 0.7)))
	for m in MONEY_STEPS:
		var b := _button("+%d" % m, 92)
		b.pressed.connect(_add_money.bind(m))
		money_row.add_child(b)

	# 资源步长切换（每次 +10 / +99）
	var step_row := HBoxContainer.new()
	step_row.alignment = BoxContainer.ALIGNMENT_CENTER
	step_row.add_theme_constant_override("separation", 8)
	vbox.add_child(step_row)
	step_row.add_child(_label("资源步长", 13, Color(0.85, 0.8, 0.7)))
	for s in ITEM_STEPS:
		var b := _button("+%d" % s, 72)
		b.pressed.connect(_set_step.bind(s))
		step_row.add_child(b)
		_step_btns[s] = b

	# 资源按钮网格：4 列
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)
	for path in ITEMS:
		var it: ItemData = load("res://item/%s.tres" % path)
		if it == null:
			continue
		var b := _button("", 150)
		b.set_meta("item", it)
		b.pressed.connect(_add_item.bind(b))
		grid.add_child(b)
		_refresh_item_btn(b)

	# 工地一排：推进 / 直接建成当前工地（铁匠铺/水井/鸡舍都在 Structures.site 里排队）
	var site_row := HBoxContainer.new()
	site_row.alignment = BoxContainer.ALIGNMENT_CENTER
	site_row.add_theme_constant_override("separation", 8)
	vbox.add_child(site_row)
	site_row.add_child(_label("工地", 13, Color(0.85, 0.8, 0.7)))
	var wb := _button("+5 人工", 92)
	wb.pressed.connect(_cheat_site_work)
	site_row.add_child(wb)
	var wd := _button("直接建成", 92)
	wd.pressed.connect(_cheat_site_done)
	site_row.add_child(wd)

	# 伙伴一排：免费招募（直接走 recruit_roster —— 纯任务制下跳过诉求核验, 纯调试用）
	var slave_row := HBoxContainer.new()
	slave_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slave_row.add_theme_constant_override("separation", 8)
	vbox.add_child(slave_row)
	slave_row.add_child(_label("伙伴", 13, Color(0.85, 0.8, 0.7)))
	var rb := _button("免费招 1 人", 192)
	rb.pressed.connect(_cheat_recruit)
	slave_row.add_child(rb)

	_tip = _label("", 12, Color(0.72, 0.66, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(640, 0)
	vbox.add_child(_tip)

	vbox.add_child(_label("按 P / Esc / 空格 / F 关闭", 11, Color(0.6, 0.55, 0.48), HORIZONTAL_ALIGNMENT_CENTER))

# ---------------- 动作 ----------------
func _add_money(n: int) -> void:
	Wallet.add_money(n)
	_refresh()
	_tip.text = "已加 %d 钱" % n

func _set_step(s: int) -> void:
	_step = s
	for k in _step_btns.keys():
		var b: Button = _step_btns[k]
		b.modulate = Color(1, 1, 1) if k == _step else Color(0.72, 0.7, 0.66)
	for b in _find_item_btns():
		_refresh_item_btn(b)

func _add_item(b: Button) -> void:
	var it: ItemData = b.get_meta("item")
	var ok := Inventory.add_item(it, _step)
	if ok:
		_tip.text = "已加 %d %s (背包 %d)" % [_step, it.display_name, Inventory.count_item(it)]
	else:
		_tip.text = "%s 背包满了" % it.display_name
	_refresh()

func _refresh_item_btn(b: Button) -> void:
	var it: ItemData = b.get_meta("item")
	b.text = "+%d %s" % [_step, it.display_name]

func _find_item_btns() -> Array:
	var out: Array = []
	_collect_item_btns(self, out)
	return out

# ---------------- 作弊动作：工地 / 伙伴 ----------------
# 当前工地 +5 人工。add_site_work 返回 true = 这一下直接建成了。
func _cheat_site_work() -> void:
	if not Structures.site_busy():
		_tip.text = "现在没有工地 (背包建造页先开工)"
		return
	var nm := Structures.site_name()
	if Structures.add_site_work(5):
		_tip.text = "%s 建成了!" % nm
	else:
		_tip.text = "%s 进度 %d/%d" % [nm,
			int(Structures.site.get("work", 0)), int(Structures.site.get("need", 0))]
	_refresh()

# 补齐剩余人工，工地当场落成。
func _cheat_site_done() -> void:
	if not Structures.site_busy():
		_tip.text = "现在没有工地 (背包建造页先开工)"
		return
	var nm := Structures.site_name()
	var left := maxi(1, int(Structures.site.get("need", 1)) - int(Structures.site.get("work", 0)))
	if Structures.add_site_work(left):
		_tip.text = "%s 建成了!" % nm
	else:
		_tip.text = "建成失败 (意外)"
	_refresh()

# 免费招 1 人：直接 recruit_roster（跳过窗口与诉求核验, 只给调试用 ——
# 名字/职业仍按花名册推进, changed 信号照发, 面板全走同一套刷新）。
func _cheat_recruit() -> void:
	if Slaves.count >= Slaves.CAP:
		_tip.text = "伙伴已满 (%d/%d)" % [Slaves.count, Slaves.CAP]
		return
	Slaves.recruit_roster()
	var s: Dictionary = Slaves.slave_at(Slaves.count - 1)
	_tip.text = "免费招到 %s (%s)" % [str(s.get("name", "")), str(s.get("troop", ""))]
	_refresh()

func _collect_item_btns(n: Node, out: Array) -> void:
	if n is Button and n.has_meta("item"):
		out.append(n)
	for c in n.get_children():
		_collect_item_btns(c, out)

func _refresh() -> void:
	_money_label.text = "钱 %d" % Wallet.money

# ---------------- 开关 ----------------
func open() -> void:
	_refresh()
	_tip.text = ""
	_guard = GUARD
	_open = true
	TimeManager.push_ui_pause()
	show()

func _input(event: InputEvent) -> void:
	if not _open or _guard > 0.0:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
		or event.is_action_pressed("interact") or event.is_action_pressed("cheat_panel"):
		_dismiss()
		get_viewport().set_input_as_handled()

func _dismiss() -> void:
	if not _open:
		return
	_open = false
	TimeManager.pop_ui_pause()
	hide()
	closed.emit()

func is_open() -> bool:
	return _open

# ---------------- 控件工厂 ----------------
func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 34)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 13)
	return b
