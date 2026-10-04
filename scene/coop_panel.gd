# coop_panel.gd —— 鸡舍管理面板（e30p）
# 对鸡舍按 F 打开：一键收蛋 / 买鸡入住 / 卖鸡换钱 / 扩建加位。
# 鸡不再走道具链路（商人不卖小鸡），买卖都在这里办。
# 容量等级制：Lv1 住 3 只，每升一级多 1 只（扩建 80*现级 金，顶格 Lv3）。
# 风格对齐 sleep_menu_ui（暖黑 + 火光橙）。由 game.gd 的 _try_station_interact 打开。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _visible := false
var _cell := Vector2i.ZERO       # 当前管理的鸡舍格

var _info: Label                 # 鸡 n/上限 · 蛋 m 枚 · 等级 Lv
var _money: Label                # 钱包余额
var _btn_eggs: Button
var _btn_buy: Button
var _btn_sell: Button
var _btn_up: Button

func _ready() -> void:
	add_to_group("coop_panel")
	# 父节点是 HUD/CanvasLayer, Control 默认 0 尺寸会挤到左上角, 必须自己铺满全屏
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

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
	st.bg_color = Color(0.14, 0.11, 0.07, 0.97)       # 暖黑
	st.border_color = Color(0.85, 0.62, 0.25)         # 谷仓橙
	st.set_border_width_all(3)
	st.set_corner_radius_all(8)
	st.content_margin_left = 24
	st.content_margin_right = 24
	st.content_margin_top = 16
	st.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", st)
	center.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	vbox.add_child(_label("鸡舍", 22, Color(1, 0.78, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	_info = _label("", 14, Color(0.95, 0.88, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_info)
	_money = _label("", 13, Color(0.85, 0.78, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_money)

	# ---- 四个动作按钮 ----
	_btn_eggs = _mk_btn("收蛋 (一键)")
	_btn_eggs.pressed.connect(_take_eggs)
	vbox.add_child(_btn_eggs)

	_btn_buy = _mk_btn("买一只小鸡 (120 金)")
	_btn_buy.pressed.connect(_buy_chicken)
	vbox.add_child(_btn_buy)

	_btn_sell = _mk_btn("卖一只鸡 (90 金)")
	_btn_sell.pressed.connect(_sell_chicken)
	vbox.add_child(_btn_sell)

	_btn_up = _mk_btn("扩建鸡舍")
	_btn_up.pressed.connect(_upgrade)
	vbox.add_child(_btn_up)

	var btn_close := _mk_btn("关上 (Esc)", 32)
	btn_close.pressed.connect(close_panel)
	vbox.add_child(btn_close)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _mk_btn(text: String, h := 36) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, h)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 14)
	return b

# ---------------- 开合 ----------------
func open(c: Vector2i) -> void:
	if _visible:
		return
	_cell = c
	_visible = true
	_refresh()
	show()
	Audio.play_sfx("ui_open")
	TimeManager.push_ui_pause()      # 管鸡舍的时候时间先停住
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	Audio.play_sfx("ui_close")
	TimeManager.pop_ui_pause()
	closed.emit()

func is_open() -> bool:
	return _visible

# ---------------- 动作 ----------------
func _game() -> Node:
	return get_tree().get_first_node_in_group("game")

func _take_eggs() -> void:
	var g := _game()
	if g == null or not g.has_method("coop_take_eggs"):
		return
	var got: int = g.call("coop_take_eggs", _cell)
	if got > 0:
		_flash("收了 %d 个鸡蛋" % got)
	_refresh()

func _buy_chicken() -> void:
	var g := _game()
	if g == null or not g.has_method("coop_buy_chicken"):
		return
	if g.call("coop_buy_chicken", _cell):
		_flash("小鸡搬进来啦")
	else:
		_flash("买不了 (钱不够 / 住满了)", true)
	_refresh()

func _sell_chicken() -> void:
	var g := _game()
	if g == null or not g.has_method("coop_sell_chicken"):
		return
	if g.call("coop_sell_chicken", _cell):
		_flash("卖掉一只鸡")
	else:
		_flash("舍里没有鸡可卖", true)
	_refresh()

func _upgrade() -> void:
	var g := _game()
	if g == null or not g.has_method("coop_upgrade"):
		return
	if g.call("coop_upgrade", _cell):
		_flash("扩建完成, 能住更多鸡了")
	_refresh()

func _flash(text: String, bad := false) -> void:
	# 面板内的轻提示: 借游戏里的飘字（面板开着飘字照样出）
	var g := _game()
	if g == null or g.get("player") == null:
		return
	var p: Node = g.get("player")
	if bad:
		p._flash(text, "error")
	else:
		p._flash(text)

# ---------------- 状态刷新 ----------------
func _refresh() -> void:
	if not Structures.has_station(_cell) or String(Structures.kind_of(_cell)) != Structures.KIND_COOP:
		# 鸡舍没了（理论上开着面板时不会被拆）—— 关掉自己
		close_panel()
		return
	var chick := Structures.chickens_of(_cell)
	var cap := Structures.coop_cap_of(_cell)
	var lv := Structures.level_of(_cell)
	var eggs := Structures.eggs_of(_cell)
	_info.text = "鸡 %d/%d  蛋 %d 枚  等级 Lv%d" % [chick, cap, eggs, lv]
	_money.text = "钱包 %d 金" % Wallet.money
	_btn_eggs.disabled = (eggs <= 0)
	_btn_eggs.text = ("收蛋 (一键, %d 枚)" % eggs) if eggs > 0 else "没有蛋可收"
	_btn_buy.disabled = (chick >= cap)
	_btn_buy.text = "买一只小鸡 (%d 金)" % Structures.COOP_BUY_FEE
	_btn_sell.disabled = (chick <= 0)
	_btn_sell.text = "卖一只鸡 (+%d 金)" % Structures.COOP_SELL_FEE
	if lv >= 3:
		_btn_up.disabled = true
		_btn_up.text = "已经扩建到顶了 (Lv3)"
	else:
		_btn_up.disabled = false
		_btn_up.text = "扩建到 Lv%d (%d 金, 多住 1 只)" % [lv + 1, Structures.COOP_UP_FEE * lv]

# ---------------- 键盘 ----------------
# F/Esc 关闭
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close_panel()
