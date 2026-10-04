# market_ui.gd —— 大陆集市（大陆据点里走到集市按 F）
#
# 出海一趟总得有点赚头，这个面板就是那条**经济闭环**的出口：
#   卖 —— 把背包里的作物/食物一次性出手（价走 Research.sell_price_of，
#         行商技能/科技树/互市卡都会加价）
#   买 —— 岛上现成造不出来的货：六种种子（含 e49 甜菜/花椰菜）+ 木头 + 木地板
#         （价走 Research.buy_price_of，同样吃技能和卡片的折扣）
#
# 跟其他面板一样：打开时暂停时间（TimeManager.push_ui_pause），
# F / Esc 关闭，按钮全部走同一个 _flash 提示行。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const PANEL_W := 440

# 进货单：price 是**基准**价，实付按当下的买入倍率重算（可能刚升过级）
const STOCK := [
	{"path": "res://item/seed.tres", "price": 14},           # 土豆种子
	{"path": "res://item/carrot_seed.tres", "price": 10},    # 胡萝卜种子
	{"path": "res://item/cabbage_seed.tres", "price": 22},   # 卷心菜种子
	{"path": "res://item/pumpkin_seed.tres", "price": 40},   # 南瓜种子
	# e49/e52 季节限制作物：甜菜只在冬天长、花椰菜只在夏天长 —— 六包种子全都备货,
	#      但 e52 起货架只摆当季那几包（见 _rebuild 里的 Farm.season_ok_for 过滤）,
	#      这样四季都至少有一包种子能买（不然季节线永远开不了张）
	{"path": "res://item/beet_seed.tres", "price": 22},      # 甜菜种子（冬）
	{"path": "res://item/cauliflower_seed.tres", "price": 26},  # 花椰菜种子（夏）
	{"path": "res://item/wood.tres", "price": 9},            # 木头
	{"path": "res://item/wood_floor.tres", "price": 12},     # 木地板（e28b 降价: 20 太贵, 装修铺路买得起了）
	{"path": "res://item/wheat.tres", "price": 8},           # 小麦（厨房做面包/派的原料）
	# —— 整套盔甲（三档全有售, 但贵: 手头紧就走铁匠铺自己打, 见 Crafting.SMITH_RECIPES）——
	{"path": "res://item/armor_wood.tres", "price": 120},       # 皮甲
	{"path": "res://item/armor_iron.tres", "price": 300},       # 锁链甲
	{"path": "res://item/armor_gold.tres", "price": 420},       # 铁甲
]

var _visible := false
var _guard := 0.0
var _root: VBoxContainer = null
var _list: VBoxContainer = null      # 清单区（卖 + 进货），装在滚动框里
var _flash_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()
	Wallet.money_changed.connect(func(_m): if _visible: _rebuild())
	Inventory.inventory_changed.connect(func(): if _visible: _rebuild())

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

# ---------------- 搭界面 ----------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var card := PanelContainer.new()
	# ❗必须用 PanelContainer（或带 StyleBox 的容器）当底板，**不能**拿 ColorRect：
	#   ColorRect 的尺寸只看 custom_minimum_size，里面的子节点撑不大它 ——
	#   高度算出来就是 0，于是「底板不见了，字直接飘在草地上」。
	#   PanelContainer 会跟着内容长，顺便还能给边框和圆角。
	card.custom_minimum_size = Vector2(PANEL_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.14, 0.11, 0.09, 0.97)
	card_style.border_color = Color(0.62, 0.47, 0.28)
	card_style.set_border_width_all(3)
	card_style.set_corner_radius_all(8)
	card_style.content_margin_left = 20
	card_style.content_margin_right = 20
	card_style.content_margin_top = 16
	card_style.content_margin_bottom = 18
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 7)
	card.add_child(_root)

	# ❗清单区必须限高滚动：进货单 16 档货（10 档护甲一摆就是一长列），
	#   全铺开的话整卡 825px 高，直接顶出 648 的屏幕底 —— 头部和钱都看得见，
	#   页脚和后半截货全在屏外。头部/flash/页脚留在滚动框外，永远可见。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W - 40, 396)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)

# ---------------- 刷新 ----------------
func _rebuild() -> void:
	if _root == null or _list == null:
		return
	for c in _root.get_children():
		if c is ScrollContainer:
			continue                    # 滚动框是 _build 一次搭好的，只清里面的清单
		_root.remove_child(c)
		c.queue_free()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	_root.add_child(_label("大陆集市", 19, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("身上的钱: %d 金" % Wallet.money, 14,
		Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	_flash_label = _label("", 12, Color(0.75, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_flash_label)

	# —— 卖（清单区，可滚动） ——
	_list.add_child(_label("出手 (作物和食物)", 13, Color(1, 0.93, 0.76)))
	var tot := _sell_total()
	_list.add_child(_label("背包里有 %d 份, 能卖 %d 金" % [int(tot["n"]), int(tot["gold"])],
		12, Color(0.86, 0.82, 0.74)))
	var sb := _button("全部卖掉 (%d 金)" % int(tot["gold"]), PANEL_W - 60)
	sb.disabled = int(tot["n"]) <= 0
	sb.pressed.connect(_sell_all)
	_list.add_child(_hwrap(sb))

	# —— 买（清单区，可滚动） ——
	_list.add_child(_label("进货 (当季种子 + 常备货)", 13, Color(1, 0.93, 0.76)))
	for e in STOCK:
		# e52: 种子只摆当季能种的（Farm.season_ok_for 是季节的唯一真相源）;
		#      木头/木地板/小麦/盔甲没有 seasons, 照样全年有货。
		if not Farm.season_ok_for(load(str(e["path"]))):
			continue
		_list.add_child(_stock_row(e))
	_list.add_child(_label("买卖价吃行商技能和卡片的加成.", 11, Color(0.62, 0.60, 0.54)))

	_root.add_child(_label("F / Esc 关闭", 11,
		Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))

func _stock_row(e: Dictionary) -> Control:
	var it: ItemData = load(str(e["path"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# ❗这几行必须用**不换行**的标签（_plain）并给死宽度：
	#   _label 带 autowrap，自动换行的 Label 最小宽度只有 1px，
	#   放进 HBox 后会被压成 1px 宽 —— 文字竖着排成一列、整行高 80 多像素。
	var name_l := _plain(it.display_name, 13, Color(0.92, 0.90, 0.84))
	name_l.custom_minimum_size = Vector2(122, 0)
	row.add_child(name_l)
	var price := Research.buy_price_of(int(e["price"]))
	var pl := _plain("%d 金" % price, 12,
		Color(0.98, 0.85, 0.45) if Wallet.money >= price else Color(1, 0.55, 0.5))
	pl.custom_minimum_size = Vector2(70, 0)
	row.add_child(pl)
	var b := _button("买 1", 72)
	b.disabled = Wallet.money < price
	b.pressed.connect(func(): _buy(it, int(e["price"])))
	row.add_child(b)
	if it.type == "种子" and it.grow_to != null:
		var t := _plain("-> %s" % it.grow_to.display_name, 11, Color(0.62, 0.60, 0.54))
		t.custom_minimum_size = Vector2(110, 0)
		row.add_child(t)
	elif it.type == "装备":
		var t := _plain("整套甲 %d 级" % it.armor_tier, 11, Color(0.62, 0.60, 0.54))
		t.custom_minimum_size = Vector2(110, 0)
		row.add_child(t)
	return row

# 背包里所有能卖的东西（作物 / 食物 / 材料）：份数 + 总价
func _sell_total() -> Dictionary:
	var n := 0
	var gold := 0
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		if it == null or int(s["count"]) <= 0:
			continue
		if it.type != "作物" and it.type != "食物" and it.type != "材料":
			continue
		var each := Research.sell_price_of(it)
		if each <= 0:
			continue
		n += int(s["count"])
		gold += each * int(s["count"])
	return {"n": n, "gold": gold}

func _sell_all() -> void:
	var to_sell: Array = []
	var total := 0
	var n := 0
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		if it == null or int(s["count"]) <= 0:
			continue
		if it.type != "作物" and it.type != "食物" and it.type != "材料":
			continue
		var each := Research.sell_price_of(it)
		if each <= 0:
			continue
		to_sell.append({"item": it, "count": int(s["count"])})
		n += int(s["count"])
		total += each * int(s["count"])
	if n <= 0:
		Audio.play_sfx("error", -6.0)
		_flash("没东西可卖")
		return
	for e in to_sell:
		Inventory.remove_item(e["item"], e["count"])
	Wallet.add_money(total)
	Audio.play_sfx("coin", -4.0)
	_flash("卖出 %d 份, 赚了 %d 金" % [n, total])
	_rebuild()

func _buy(it: ItemData, base: int) -> void:
	var price := Research.buy_price_of(base)
	if not Wallet.spend_money(price):
		Audio.play_sfx("error", -6.0)
		_flash("钱不够 (要 %d 金)" % price)
		return
	if not Inventory.add_item(it, 1):
		Wallet.add_money(price)             # 背包塞不下就退钱
		Audio.play_sfx("error", -6.0)
		_flash("背包满了, 放不下")
		return
	Audio.play_sfx("buy", -4.0)
	_flash("买了 1 个%s" % it.display_name)
	_rebuild()

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text

# ---------------- 小工具 ----------------
func _hwrap(c: Control) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(c)
	return h

func _button(text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 30)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 13)
	return b

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# 不换行的标签（给 HBoxContainer 里的行用，见 _stock_row 那段注释）
func _plain(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

# ---------------- 开关 ----------------
func open_panel() -> void:
	if _visible:
		return
	_visible = true
	_rebuild()
	show()
	TimeManager.push_ui_pause()      # 站在摊子前挑货的时候时间停住
	Audio.play_sfx("ui_open", -6.0)
	opened.emit()
	_guard = 0.28

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	TimeManager.pop_ui_pause()
	Audio.play_sfx("ui_close", -8.0)
	closed.emit()

func is_open() -> bool:
	return _visible

func _input(event: InputEvent) -> void:
	if not _visible or _guard > 0.0:
		return
	# ❗用 _input 而不是 _unhandled_input：要抢在 mainland 的 F 处理之前把这一下吃掉，
	#   不然关面板的同一下 F 又会被当成「再开一次」。
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
