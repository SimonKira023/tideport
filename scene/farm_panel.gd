# scene/farm_panel.gd —— e49 畜棚/马厩的管理面板
# 对畜棚/马厩按 F 打开：买卖牲口 / 一头一头收畜产 / 一键收全部 / 扩建加位。
# 跟鸡舍面板（coop_panel）一个套路，只是牲口分种类 —— 表里的每种牲口占一行，
# 本棚养不了的那几种（比如马厩里的牛）整行藏起来。
#
# ❗行是 _build() 一次性建好的**固定 6 行**，_refresh() 只改字和显隐、绝不 free 重建 ——
#   因为 _buy/_sell/_collect 是从行内的按钮信号里进去的，在那儿把按钮 free 掉
#   （背包面板那种"整列拆了重来"的刷新法）会把正在发信号的对象连根拔掉。
# 由 farm_building_node.activate 按需挂到 HUD 上（game.gd 不许改, 所以没走 _setup_*）。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _visible := false
var _cell := Vector2i.ZERO

var _title: Label = null
var _info: Label = null
var _money: Label = null
var _note: Label = null
var _btn_all: Button = null
var _btn_up: Button = null
var _flash_label: Label = null

var _species: Array = []     # 6 种牲口（畜棚那 5 种 + 马）
var _rows: Array = []        # [{box, name, cnt, buy, sell, prod, collect}] 跟 _species 一一对应

func _ready() -> void:
	# 不能写 const: autoload 的常量不是常量表达式（见 COOP 那套的注释）
	_species = Structures.BARN_ANIMALS.duplicate()
	for sp in Structures.STABLE_ANIMALS:
		if not _species.has(sp):
			_species.append(sp)
	add_to_group("farm_panel")
	# 挂在 HUD(CanvasLayer) 下：不自己声明全屏的话面板会挤在左上角
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

# ---------------- 搭界面 ----------------
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
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.13, 0.11, 0.07, 0.97)      # 暖黑（跟鸡舍面板一个色系）
	st.border_color = Color(0.85, 0.62, 0.25)
	st.set_border_width_all(3)
	st.set_corner_radius_all(8)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 14
	st.content_margin_bottom = 16
	box.add_theme_stylebox_override("panel", st)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	box.add_child(vbox)

	_title = _label("畜棚", 22, Color(1, 0.78, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title)
	_info = _label("", 14, Color(0.95, 0.88, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_info)
	_money = _label("", 13, Color(0.85, 0.78, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_money)

	for sp in _species:
		vbox.add_child(_make_row(String(sp)))

	_note = _label("", 12, Color(0.72, 0.68, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_note)

	_btn_all = _mk_btn("一键收全部畜产", Vector2(0, 32))
	_btn_all.pressed.connect(_collect_all)
	vbox.add_child(_btn_all)

	_btn_up = _mk_btn("", Vector2(0, 32))
	_btn_up.pressed.connect(_upgrade)
	vbox.add_child(_btn_up)

	_flash_label = _label("", 13, Color(1, 0.95, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_flash_label)

	var close := _mk_btn("关上 (F / Esc)", Vector2(0, 32))
	close.pressed.connect(close_panel)
	vbox.add_child(close)

# 一行牲口：名字 / 存栏 / 买 / 卖 / 攒下的畜产 / 收
func _make_row(sp: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var nm := _label(Structures.animal_name(sp), 14, Color(0.95, 0.9, 0.8))
	nm.custom_minimum_size = Vector2(76, 0)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(nm)
	var cnt := _label("", 13, Color(0.85, 0.82, 0.7))
	cnt.custom_minimum_size = Vector2(58, 0)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cnt)
	var buy := _mk_btn("", Vector2(132, 30))
	buy.pressed.connect(_buy.bind(sp))
	row.add_child(buy)
	var sell := _mk_btn("", Vector2(132, 30))
	sell.pressed.connect(_sell.bind(sp))
	row.add_child(sell)
	var prod := _label("", 13, Color(0.98, 0.85, 0.5))
	prod.custom_minimum_size = Vector2(112, 0)
	prod.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(prod)
	var take := _mk_btn("收", Vector2(58, 30))
	take.pressed.connect(_collect.bind(sp))
	row.add_child(take)
	_rows.append({"box": row, "cnt": cnt, "buy": buy, "sell": sell, "prod": prod, "collect": take})
	return row

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _mk_btn(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 13)
	return b

# ---------------- 开合 ----------------
func open(c: Vector2i) -> void:
	if _visible:
		return
	_cell = c
	_visible = true
	_flash_label.text = ""
	_refresh()
	show()
	Audio.play_sfx("ui_open")
	TimeManager.push_ui_pause()      # 管牲口的时候时间先停住
	_close_others()
	_freeze(true)
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	Audio.play_sfx("ui_close")
	TimeManager.pop_ui_pause()
	_freeze(false)
	closed.emit()

func is_open() -> bool:
	return _visible

func cell() -> Vector2i:
	return _cell

func _game() -> Node:
	return get_tree().get_first_node_in_group("game")

# 冻住/放开玩家：借 game 现成的 _set_player_frozen（鸡舍/箱子面板都是这么接的）。
# 不冻的话面板虽然铺满全屏吞鼠标, 方向键照样能把人走开。
func _freeze(on: bool) -> void:
	var g := _game()
	if g != null and g.has_method("_set_player_frozen"):
		g.call("_set_player_frozen", on)

# 开自己之前先把别的面板收掉, 别几个叠在一起（跟 game._setup_coop_panel 一个规矩）
func _close_others() -> void:
	var g := _game()
	if g == null:
		return
	for pname in ["backpack_panel", "shop_panel", "coop_panel", "chest_panel", "bin_panel"]:
		var p: Variant = g.get(pname)
		if p == null or not is_instance_valid(p):
			continue
		var n := p as Node
		if n.has_method("is_open") and bool(n.call("is_open")):
			if n.has_method("close_panel"):
				n.call("close_panel")
			elif n.has_method("close"):
				n.call("close")

# ---------------- 动作 ----------------
func _buy(sp: String) -> void:
	var fee: int = Structures.animal_buy_fee(sp)
	if not Wallet.spend_money(fee):
		_flash("钱不够, 买一头%s要 %d 金" % [Structures.animal_name(sp), fee], true)
		return
	if not Structures.add_animal(_cell, sp):
		Wallet.add_money(fee)        # 住不下了: 钱原样退回去
		_flash("%s住不下了, 先扩建或卖掉几头" % Structures.animal_name(sp), true)
		return
	Audio.play_sfx("ui_open", -8.0)
	_flash("买回一头%s" % Structures.animal_name(sp))

func _sell(sp: String) -> void:
	if not Structures.remove_animal(_cell, sp):
		_flash("棚里没有%s可卖" % Structures.animal_name(sp), true)
		return
	var fee: int = Structures.animal_sell_fee(sp)
	Wallet.add_money(fee)
	Audio.play_sfx("ui_open", -8.0)
	_flash("卖掉一头%s (+%d 金)" % [Structures.animal_name(sp), fee])

func _collect(sp: String) -> void:
	var r: Dictionary = Structures.take_produce_item(_cell, sp)
	var got := int(r.get("count", 0))
	var pn := _produce_name(sp)
	if got <= 0:
		_flash("没有%s可收" % pn, true)
		return
	Audio.play_sfx("harvest", -6.0)
	_flash("收了 %d 份%s" % [got, pn])

func _collect_all() -> void:
	var total := 0
	for sp in _species:
		var r: Dictionary = Structures.take_produce_item(_cell, String(sp))
		total += int(r.get("count", 0))
	if total <= 0:
		_flash("棚里没有攒下的畜产", true)
		return
	Audio.play_sfx("harvest", -6.0)
	_flash("收了 %d 份畜产" % total)

func _upgrade() -> void:
	var lv: int = Structures.level_of(_cell)
	if lv >= 3:
		return
	var fee: int = Structures.ANIMAL_UP_FEE * lv
	if not Wallet.spend_money(fee):
		_flash("钱不够, 扩建要 %d 金" % fee, true)
		return
	Structures.set_level(_cell, lv + 1)
	Audio.play_sfx("ui_open")
	_flash("扩建完成, 能多养一头了")

func _produce_name(sp: String) -> String:
	return String(Structures.ANIMALS.get(sp, {}).get("prod", "畜产"))

# ---------------- 状态刷新 ----------------
func _refresh() -> void:
	if not _visible:
		return
	var k: String = Structures.kind_of(_cell)
	if k != Structures.KIND_BARN and k != Structures.KIND_STABLE:
		close_panel()                # 棚没了（理论上开着面板时不会被拆）—— 关掉自己
		return
	var allow: Array = Structures.animal_kinds_for(k)
	_title.text = String(Structures.building_cost(k).get("name", "农场"))
	var heads: int = Structures.animal_count_of(_cell)
	var cap: int = Structures.animal_cap_of(_cell)
	var lv: int = Structures.level_of(_cell)
	_info.text = "牲口 %d/%d  等级 Lv%d" % [heads, cap, lv]
	_money.text = "钱包 %d 金" % Wallet.money
	_note.text = "同一个种类最多攒 %d 份畜产, 攒满了不再涨 (冬天和风暴天不产)" % Structures.PRODUCE_MAX
	for i in _rows.size():
		var sp := String(_species[i])
		var row: Dictionary = _rows[i]
		var box: Control = row["box"]
		if not allow.has(sp):
			box.visible = false       # 马厩不显示牛 / 畜棚不显示马
			continue
		box.visible = true
		var n: int = Structures.count_of_species(_cell, sp)
		(row["cnt"] as Label).text = "%d 头" % n
		var buy: Button = row["buy"]
		buy.disabled = heads >= cap
		buy.text = "买一头 (%d金)" % Structures.animal_buy_fee(sp)
		var sell: Button = row["sell"]
		sell.disabled = n <= 0
		sell.text = "卖一头 (+%d金)" % Structures.animal_sell_fee(sp)
		var prod: Label = row["prod"]
		var take: Button = row["collect"]
		if Structures.animal_product_path(sp) == "":
			prod.text = "不产畜产"
			take.visible = false
		else:
			var pc: int = Structures.produce_of_species(_cell, sp)
			prod.text = "%s %d 份" % [_produce_name(sp), pc]
			take.visible = true
			take.disabled = pc <= 0
	_btn_all.disabled = Structures.produce_count(_cell) <= 0
	_btn_all.text = "一键收全部畜产 (%d 份)" % Structures.produce_count(_cell)
	if lv >= 3:
		_btn_up.disabled = true
		_btn_up.text = "已经扩建到顶了 (Lv3)"
	else:
		_btn_up.disabled = false
		_btn_up.text = "扩建到 Lv%d (%d 金, 多养一头)" % [lv + 1, Structures.ANIMAL_UP_FEE * lv]

# ---------------- 键盘 ----------------
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()   # ❗先吞掉再关, 否则 F 会传到建筑节点又把它开回来
		close_panel()

func _flash(text: String, bad := false) -> void:
	# 面板内的轻提示就写在按钮下面那一行（不再往玩家头上飘 —— 面板铺满全屏,
	# 从玩家那取飘字会被面板盖住）。
	_flash_label.text = text
	_flash_label.add_theme_color_override("font_color",
		Color(1, 0.58, 0.5) if bad else Color(1, 0.95, 0.75))
	_refresh()