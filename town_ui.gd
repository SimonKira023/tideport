# town_ui.gd —— 城镇议事厅（大陆城镇里走到议事厅按 F）
#
# e27h: 五分页面板 —— 一座城的所有事务都收进这一张卡（页签在卡片顶部）：
#   商贸     —— 集市搬了进来：卖作物/食物 + 进货单（价跟 market_ui 同一套 Research 倍率）
#   攻城     —— 对敌城只开这一页：递战书（花外交点）/ 攻城
#   招募     —— 酒馆的招募消息板：看下一位候选人 / 诉求 / 进度（入队只在岛上篝火边）
#   到处逛逛 —— 外交社交：聊天 / 送礼 / 签商盟 / 签盟约 / 领主头像闲话
#   管理     —— 占领城专属：税入 / 繁荣 / 忠诚 / 军力 / 驻军 / 安抚 / 修葺建设
#
# 页签显隐按城的状态定：
#   占领城   → 商贸 / 酒馆 / 管理（领主已逃, 没外交, 更没敌人）
#   交战敌城 → 只剩攻城（敌城只能攻城）
#   其它外邦城 → 商贸 / 攻城 / 酒馆 / 到处逛逛
#
# 好感 / 协议 / 战争 / 治理的数据与每日结算全在 Nations（autoload），这里只管说话和刷新。
# 界面骨架跟 market_ui.gd 同一套：打开时暂停时间，F / Esc 关闭，_flash 提示行。
# ❗selftest 22.5 锁死了结构：CenterContainer 的 child(0) 必须是 PanelContainer 卡片，
#   所以页签行放在卡片内部，不能学 backpack_ui 把页签挂到卡片外面。
# ❗到处逛逛页永远要建（哪怕页签藏着）：selftest 62e 不开面板直接 _rebuild() 后找
#   _portrait 的领主头像 —— 占领城也得有这页在树里。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const PANEL_W := 470

# e27h: 进货单 —— 跟 market_ui.STOCK 同一份（price 是基准价, 实付按买入倍率重算）
const STOCK := [
	{"path": "res://item/seed.tres", "price": 14},           # 土豆种子
	{"path": "res://item/carrot_seed.tres", "price": 10},    # 胡萝卜种子
	{"path": "res://item/cabbage_seed.tres", "price": 22},   # 卷心菜种子
	{"path": "res://item/pumpkin_seed.tres", "price": 40},   # 南瓜种子
	# e49/e52 季节限制作物（跟 market_ui.STOCK 同步）：六包种子都备货, 货架只摆当季的
	#      （甜菜=冬、花椰菜=夏）
	{"path": "res://item/beet_seed.tres", "price": 22},      # 甜菜种子（冬）
	{"path": "res://item/cauliflower_seed.tres", "price": 26},  # 花椰菜种子（夏）
	{"path": "res://item/wood.tres", "price": 9},            # 木头
	{"path": "res://item/wood_floor.tres", "price": 12},     # 木地板（e28b 降价, 跟 market_ui 同步）
	{"path": "res://item/wheat.tres", "price": 8},           # 小麦（厨房做面包/派的原料）
	# —— 整套盔甲（三档全有售, 但贵: 手头紧就走铁匠铺自己打）——
	{"path": "res://item/armor_wood.tres", "price": 120},       # 皮甲
	{"path": "res://item/armor_iron.tres", "price": 300},       # 锁链甲
	{"path": "res://item/armor_gold.tres", "price": 420},       # 铁甲
]

# e27h: 五个页签（key / 名字）
const TABS := [
	{"key": "trade",  "name": "商贸"},
	{"key": "siege",  "name": "攻城"},
	{"key": "tavern", "name": "招募"},
	{"key": "visit",  "name": "到处逛逛"},
	{"key": "admin",  "name": "管理"},
]

var town_id := ""
var _visible := false
var _guard := 0.0
var _chatted_day := {}          # 国家id -> 上次聊天的总天数（聊天一天一次）
var _last_chat := ""
var _root: VBoxContainer = null
var _flash_label: Label = null
var _chat_label: Label = null
var _portrait: TextureRect = null
var _dialog: Control = null     # e16g: 聊天对话框（关掉框才算聊了天）
# e27h: 分页
var _tab_btns := {}             # key -> Button
var _pages := {}                # key -> Control
var _current := "visit"         # 默认停在「到处逛逛」（打不过就想先聊聊天）

# 进城时由 mainland 调用（add_child 之前设置，_ready 里就能用）
func setup(tid: String) -> void:
	town_id = tid

func _nid() -> String:
	return String(Nations.TOWNS.get(town_id, {}).get("nation", ""))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# e16g: 聊天对话框挂在本面板之上 —— 关掉框的那一下才真正落账
	_dialog = preload("res://dialog_box.gd").new()
	_dialog.name = "ChatDialog"
	add_child(_dialog)
	_dialog.closed.connect(_finish_chat)
	hide()
	Wallet.money_changed.connect(func(_m): if _visible: _rebuild())
	Nations.changed.connect(func(): if _visible: _rebuild())
	# e27h: 商贸页吃背包变动, 酒馆页吃雇佣变动
	Inventory.inventory_changed.connect(func(): if _visible: _rebuild())
	Slaves.changed.connect(func(): if _visible: _rebuild())

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

# ---------------- 刷新 ----------------
func _rebuild() -> void:
	if _root == null:
		return
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_tab_btns.clear()
	_pages.clear()

	var nid := _nid()
	var t: Dictionary = Nations.TOWNS.get(town_id, {})
	var n: Dictionary = Nations.nation(nid)
	var occupied: bool = Nations.occupied.has(town_id)
	var at_war: bool = Nations.at_war_with(nid)
	var hall_word := "城主府" if String(t.get("kind", "")) == "capital" else "议事厅"
	var ncolor: Color = n.get("color", Color(0.9, 0.85, 0.7))

	_root.add_child(_label("%s - %s" % [String(t.get("name", "")), hall_word],
		19, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("%s - %s" % [String(n.get("name", "")), String(n.get("desc", ""))],
		12, ncolor.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER))
	var lord := Nations.lord_full(town_id)
	if occupied:
		_root.add_child(_label("军管城池 - 原领主已逃", 13,
			Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	elif lord != "":
		_root.add_child(_label("领主: %s" % lord, 13,
			Color(0.98, 0.88, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
	_flash_label = _label("", 12, Color(0.75, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_flash_label)

	# —— 页签行（卡片内部; 显隐按城的状态定）——
	var keys := _visible_tabs(occupied, at_war)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(tabs)
	for e in TABS:
		var key := str(e["key"])
		if not keys.has(key):
			continue
		var b := _button(str(e["name"]), 0)
		b.pressed.connect(_select_page.bind(key))
		tabs.add_child(b)
		_tab_btns[key] = b

	# —— 内容页：一次全建好、靠 visibility 切换（探针递归找文本才找得着）——
	#   admin 只给占领城建（非占领城不许出现「占领城治理」字样）,
	#   siege 只给非占领城建（自己的城没得攻）, 其余三页永远建。
	var pages_box := VBoxContainer.new()
	pages_box.add_theme_constant_override("separation", 7)
	_root.add_child(pages_box)
	for e in TABS:
		var key := str(e["key"])
		if key == "admin" and not occupied:
			continue
		if key == "siege" and occupied:
			continue
		var page: Control = null
		match key:
			"trade":
				page = _page_trade()
			"siege":
				page = _page_siege(at_war)
			"tavern":
				page = _page_tavern()
			"visit":
				page = _page_visit(occupied, at_war, ncolor)
			"admin":
				page = _page_admin()
		if page == null:
			continue
		page.visible = false
		pages_box.add_child(page)
		_pages[key] = page

	# 当前页不在可见集合里就落到第一枚可见页签
	if not keys.has(_current):
		_current = str(keys[0])
	_select_page(_current)

	_root.add_child(_label("F / Esc 关闭", 11,
		Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))

func _select_page(key: String) -> void:
	_current = key
	for k in _pages:
		_pages[k].visible = (k == key)

# e27h: 哪些页签亮着 —— 占领城没外交没敌人; 敌城只能攻城
func _visible_tabs(occupied: bool, at_war: bool) -> Array:
	if occupied:
		return ["trade", "tavern", "admin"]
	if at_war:
		return ["siege"]
	return ["trade", "siege", "tavern", "visit"]

# ---------------- 商贸页（market_ui 同款） ----------------
func _page_trade() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page.add_child(_label("身上的钱: %d 金" % Wallet.money, 14,
		Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	page.add_child(_label("出手 (作物和食物)", 13, Color(1, 0.93, 0.76)))
	var tot := _sell_total()
	page.add_child(_label("背包里有 %d 份, 能卖 %d 金" % [int(tot["n"]), int(tot["gold"])],
		12, Color(0.86, 0.82, 0.74)))
	var sb := _button("全部卖掉 (%d 金)" % int(tot["gold"]), PANEL_W - 60)
	sb.disabled = int(tot["n"]) <= 0
	sb.pressed.connect(_sell_all)
	page.add_child(_hwrap(sb))
	page.add_child(_label("进货 (岛上没有的货)", 13, Color(1, 0.93, 0.76)))
	# ❗货单限高滚动：10 档货全铺开会把卡片顶出 648 的屏幕底
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W - 40, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	for e in STOCK:
		# e52: 种子只摆当季能种的（跟 market_ui 同一套过滤, Farm.season_ok_for 是季节唯一真相源）
		if not Farm.season_ok_for(load(str(e["path"]))):
			continue
		list.add_child(_stock_row(e))
	list.add_child(_label("买卖价吃行商技能和卡片的加成. 种子只摆当季的.", 11,
		Color(0.62, 0.60, 0.54)))
	return page

func _stock_row(e: Dictionary) -> Control:
	var it: ItemData = load(str(e["path"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	# ❗这几行必须用**不换行**的标签（_plain）并给死宽度：autowrap 的 Label
	#   最小宽度只有 1px, 放进 HBox 会被压扁竖排
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
		var t1 := _plain("-> %s" % it.grow_to.display_name, 11, Color(0.62, 0.60, 0.54))
		t1.custom_minimum_size = Vector2(110, 0)
		row.add_child(t1)
	elif it.type == "装备":
		var t2 := _plain("整套甲 %d 级" % it.armor_tier, 11, Color(0.62, 0.60, 0.54))
		t2.custom_minimum_size = Vector2(110, 0)
		row.add_child(t2)
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

# ---------------- 攻城页（e27h: 宣战入口 + 敌城只能攻城） ----------------
func _page_siege(at_war: bool) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var gar := Nations.garrison_of(town_id)
	page.add_child(_label("城防: 守军 x%d (满编 %d)" % [gar, Nations.garrison_max(town_id)],
		13, Color(0.92, 0.90, 0.84)))
	if at_war:
		var left := int(Nations.at_war.get(_nid(), 0)) - Nations.total_days()
		page.add_child(_label("两国交战中 - 战事还剩 %d 天" % maxi(0, left), 12,
			Color(0.95, 0.70, 0.55)))
	else:
		page.add_child(_label("还没开战: 先递战书才能攻城", 12, Color(0.75, 0.78, 0.86)))
		var db := _button("递战书 (花 %d 外交点, 开战 %d 天)" % [
			Nations.WAR_DECLARE_COST, Nations.WAR_DAYS], PANEL_W - 60)
		db.disabled = Nations.prestige < Nations.WAR_DECLARE_COST
		db.pressed.connect(_on_declare)
		page.add_child(_hwrap(db))
		page.add_child(_label("递了战书两国军队见面就打, 好感 -60, 协议当场撕毁.",
			11, Color(0.62, 0.60, 0.54)))
	var why := Nations.can_siege(town_id)
	var sb := _button("", PANEL_W - 60)
	if why != "":
		sb.text = why
		sb.disabled = true
	else:
		sb.text = "攻城! (守军 x%d, 战利品约 %d 金)" % [gar, Nations.siege_reward(town_id)]
		sb.pressed.connect(_on_siege)
	page.add_child(_hwrap(sb))
	return page

func _on_declare() -> void:
	var why := Nations.declare_war(_nid())
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Audio.play_sfx("buy", -4.0)
	_flash("递了战书! 两国的军队从此见面就打")   # changed 已触发重建, 页签自动收成只剩攻城

func _on_siege() -> void:
	if Nations.can_siege(town_id) != "":
		return
	close_panel()                # 收面板 + 恢复时间（battle_map 会再放慢）
	Voyage.enter_siege(town_id)  # 直接开打

# ---------------- 招募页（酒馆消息板同款, 只看不雇） ----------------
func _page_tavern() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(_label("现在有 %d 个伙伴 (最多 %d 个)" % [Slaves.count, Slaves.CAP],
		13, Color(0.86, 0.82, 0.74), HORIZONTAL_ALIGNMENT_CENTER))
	var c := Recruits.candidate()
	if c.is_empty():
		page.add_child(_label("伙伴都招齐了, 板上没了新消息.", 13,
			Color(0.7, 0.86, 0.95), HORIZONTAL_ALIGNMENT_CENTER))
		return page
	# 板上钉着的消息：下一位是谁、要什么、现在人在不在岛上
	page.add_child(_label("新贴出的一张:", 13, Color(1, 0.93, 0.76)))
	page.add_child(_label("  %s   %s   夜里能派 %d 格活" % [
		str(c.get("name", "?")), str(c.get("troop", "新兵")), Slaves.cells_per_slave()],
		14, Color(0.92, 0.90, 0.84), HORIZONTAL_ALIGNMENT_CENTER))
	page.add_child(_label("诉求: %s" % str(c.get("req", "")), 13,
		Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	page.add_child(_label("进度: %s" % Recruits.progress_text(), 13,
		Color(0.92, 0.90, 0.84), HORIZONTAL_ALIGNMENT_CENTER))
	if Recruits.visitor():
		page.add_child(_label("此刻就坐在岛上篝火边 (停留还剩 %d 天)" % Recruits.window_left(),
			13, Color(0.75, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		page.add_child(_label("眼下不在岛上, 过些日子会再来.", 13,
			Color(1.0, 0.78, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	page.add_child(_label("入队不用钱: 回岛上完成他的诉求,\n傍晚在篝火边跟他搭话就行.",
		11, Color(0.62, 0.60, 0.54)))
	return page

# ---------------- 到处逛逛页（旧外交社交段原样承接） ----------------
func _page_visit(occupied: bool, at_war: bool, ncolor: Color) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var nid := _nid()
	# —— 好感条: 国家一本账, 领主个人一本账（碰面聊天/登门送礼才涨个人账）——
	page.add_child(_fav_row("好感", Nations.favor_of(nid), ncolor))
	page.add_child(_fav_row("领主", Nations.lord_favor_of(town_id), Color(0.98, 0.85, 0.45)))

	# —— 协议状态 ——
	var pact := Nations.pact_of(nid)
	var pact_color := Color(0.62, 0.60, 0.54)
	var pact_text := "协议: 无 (商盟要好感 %d, 盟约要 %d)" % [Nations.TRADE_NEED, Nations.ALLY_NEED]
	if pact != "":
		pact_color = Color(0.75, 0.92, 0.62)
		var income := Nations.TRADE_INCOME if pact == "商盟" else Nations.ALLY_INCOME
		pact_text = "协议: %s - 还剩 %d 天 - 每天进账 %d 金" % [
			pact, Nations.pact_left(nid), income]
	page.add_child(_label(pact_text, 12, pact_color))

	# —— 按钮们（占领城 / 交战中都办不了外交, 只陈列状态）——
	var frozen := occupied or at_war
	var can_chat := int(_chatted_day.get(nid, -1)) != Nations.total_days()
	var cb := _button("聊聊天 (每天一次, +1 好感)" if can_chat else "今天聊过了", PANEL_W - 60)
	cb.disabled = frozen or not can_chat
	cb.pressed.connect(_on_chat)
	page.add_child(_hwrap(cb))

	var gb := _button("送份礼 (%d 金, +5 好感)" % Nations.GIFT_COST, PANEL_W - 60)
	gb.disabled = frozen or Wallet.money < Nations.GIFT_COST
	gb.pressed.connect(_on_gift)
	page.add_child(_hwrap(gb))

	var tb := _button("签商盟 (每天 +%d 金)" % Nations.TRADE_INCOME, PANEL_W - 60)
	if pact == "盟约":
		tb.text = "已有盟约 (含通商)"
		tb.disabled = true
	else:
		tb.disabled = frozen
	tb.pressed.connect(_on_sign.bind("商盟"))
	page.add_child(_hwrap(tb))

	var ab := _button("签盟约 (每天 +%d 金 + 巡逻友善)" % Nations.ALLY_INCOME, PANEL_W - 60)
	if pact == "盟约":
		ab.text = "盟约生效中 (还剩 %d 天)" % Nations.pact_left(nid)
		ab.disabled = true
	else:
		ab.disabled = frozen
	ab.pressed.connect(_on_sign.bind("盟约"))
	page.add_child(_hwrap(ab))

	if frozen:
		page.add_child(_label("军管城池办不了外交" if occupied else "两国交战中, 外交先停一停",
			11, Color(0.62, 0.60, 0.54)))

	# —— 最近的话（领主头像 + 对话气泡）——
	var talk_row := HBoxContainer.new()
	talk_row.add_theme_constant_override("separation", 10)
	var frame := PanelContainer.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0.16, 0.13, 0.10)
	fstyle.border_color = ncolor
	fstyle.set_border_width_all(2)
	fstyle.set_corner_radius_all(6)
	fstyle.content_margin_left = 3
	fstyle.content_margin_right = 3
	fstyle.content_margin_top = 3
	fstyle.content_margin_bottom = 3
	frame.add_theme_stylebox_override("panel", fstyle)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # e30m: 不随行高拉伸, 头像贴住框底
	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.custom_minimum_size = Vector2(72, 72)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture = load("res://resources/texture/portraits/lord_%s.png" % town_id)
	frame.add_child(_portrait)
	talk_row.add_child(frame)
	_chat_label = _label(_last_chat, 12, Color(0.85, 0.88, 0.95))
	_chat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	talk_row.add_child(_chat_label)
	page.add_child(talk_row)

	# —— 国家最近的大事（协议签下 / 到期都会留通告，不取走，海图那边还要用）——
	var news := Nations.notices
	if news.size() > 0:
		page.add_child(_label("最近: %s" % news[news.size() - 1], 11, Color(0.62, 0.60, 0.54)))
	return page

# e16g/e18: 点聊天只弹对话框（台词组预览不落账, 2~3 段翻完关框才 _finish_chat 记账）
func _on_chat() -> void:
	var nid := _nid()
	if int(_chatted_day.get(nid, -1)) == Nations.total_days():
		return
	var lord: Dictionary = Nations.lord_of(town_id)
	var portrait: Texture2D = load("res://resources/texture/portraits/lord_%s.png" % town_id)
	_dialog.open_multi(portrait,
		"%s %s" % [String(lord.get("title", "")), String(lord.get("name", ""))],
		Nations.town_lines(town_id))

# 对话框关掉的那一下才算聊了天: 记今天聊过 + 国家/领主各 +1 好感
func _finish_chat(_line: String = "") -> void:
	var nid := _nid()
	if int(_chatted_day.get(nid, -1)) == Nations.total_days():
		return
	_chatted_day[nid] = Nations.total_days()
	_last_chat = "聊了一阵子"
	Nations.chat_town(town_id)   # 里面: 国家 +1, 领主个人也 +1（触发 changed 重刷）
	_flash("聊了聊, 好感 +1 (领主也是)")

func _on_gift() -> void:
	var who := String(Nations.lord_of(town_id).get("name", ""))
	var reply := Nations.gift(_nid(), who, town_id)  # 扣钱: 国家 +5, 领主个人也 +5
	if reply == "":
		Audio.play_sfx("error", -6.0)
		_flash("钱不够 (要 %d 金)" % Nations.GIFT_COST)
		return
	_last_chat = reply
	Audio.play_sfx("coin", -4.0)
	_flash("好感 +5 (领主也是)")   # 扣钱/好感信号已触发过 rebuild, 别再刷一次把提示清掉

func _on_sign(kind: String) -> void:
	var nid := _nid()
	var why := Nations.can_sign(nid, kind)
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Nations.sign_pact(nid, kind)
	Audio.play_sfx("buy", -4.0)
	_flash("签下了%s" % kind)

# ---------------- 管理页（占领城专属, e26a 承接 + e27h 三栏） ----------------
func _page_admin() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(_label("- 占领城治理 -", 14,
		Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	page.add_child(_label("每天税入 +%d 金" % Nations.occupy_tax(town_id), 12,
		Color(0.98, 0.85, 0.45)))
	# e27h: 繁荣 / 忠诚 / 军力 三栏（忠诚 = 100 - 不满; 军力 = 驻军编成）
	var pro := Nations.prosperity_of(town_id)
	page.add_child(_fav_row("繁荣", pro, _good_color(pro)))
	var loy := Nations.loyalty_of(town_id)
	page.add_child(_fav_row("忠诚", loy, _good_color(loy)))
	var gar := Nations.pgar_of(town_id)
	page.add_child(_fav_row("军力", gar, Color(0.65, 0.80, 0.95), Nations.PGAR_MAX))
	# e52: 忠诚是干什么用的 —— 面板上直接讲清楚（忠诚 = 100 - 不满, 一体两面）
	page.add_child(_label("忠诚低 = 不满高. 不满 %d 当天就爆叛乱:" % Nations.REBEL_UNREST,
		11, Color(0.85, 0.70, 0.55)))
	page.add_child(_label("城头换旗, 这座城和它每天那份税入一起没了.",
		11, Color(0.85, 0.70, 0.55)))
	page.add_child(_label("不满每天自然 +%d, 每支驻军每天 +%d 忠诚; 安抚一次 +%d 忠诚."
		% [Nations.UNREST_BASE, Nations.UNREST_PER_GAR, Nations.CALM_DOWN],
		11, Color(0.62, 0.60, 0.54)))
	var u := Nations.unrest_of(town_id)
	var sb := _button("派驻军 x%d/%d (%d 金, 忠诚 +%d/天)"
		% [gar, Nations.PGAR_MAX, Nations.PGAR_COST, Nations.UNREST_PER_GAR], PANEL_W - 60)
	sb.disabled = gar >= Nations.PGAR_MAX or Wallet.money < Nations.PGAR_COST
	sb.pressed.connect(_on_station)
	page.add_child(_hwrap(sb))
	var cab := _button("安抚民心 (%d 金, 忠诚 +%d)" % [Nations.CALM_COST, Nations.CALM_DOWN], PANEL_W - 60)
	cab.disabled = u <= 0 or Wallet.money < Nations.CALM_COST
	cab.pressed.connect(_on_calm)
	page.add_child(_hwrap(cab))
	var bb := _button("修葺建设 (%d 金, 繁荣 +%d)" % [Nations.BUILD_COST, Nations.BUILD_UP], PANEL_W - 60)
	bb.disabled = pro >= 100 or Wallet.money < Nations.BUILD_COST
	bb.pressed.connect(_on_build)
	page.add_child(_hwrap(bb))
	page.add_child(_label("修葺一次繁荣 +%d, 繁荣 100 时税入 1.5 倍." % Nations.BUILD_UP,
		11, Color(0.62, 0.60, 0.54)))
	if u >= 75:
		page.add_child(_label("民怨沸腾, 随时会爆发叛乱!", 12,
			Color(0.95, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER))
	return page

# 越高越好的条用这个配色（繁荣 / 忠诚）
func _good_color(v: int) -> Color:
	if v >= 75:
		return Color(0.55, 0.78, 0.45)
	if v >= 40:
		return Color(0.95, 0.78, 0.35)
	return Color(0.92, 0.40, 0.32)

func _on_station() -> void:
	var why := Nations.station_garrison(town_id)
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Audio.play_sfx("buy", -4.0)
	_flash("驻军进驻 (%d/%d), 忠诚每天 +%d"
		% [Nations.pgar_of(town_id), Nations.PGAR_MAX, Nations.UNREST_PER_GAR])

func _on_calm() -> void:
	var why := Nations.calm_town(town_id)
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Audio.play_sfx("coin", -4.0)
	_flash("安抚了民心, 忠诚 +%d" % Nations.CALM_DOWN)

func _on_build() -> void:
	var why := Nations.build_town(town_id)
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Audio.play_sfx("buy", -4.0)
	_flash("修葺了城池, 繁荣 +%d" % Nations.BUILD_UP)

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text

# ---------------- 小工具 ----------------
# 一行数值条: 名词 + 进度条 + 数值（好感 / 繁荣 / 忠诚 / 军力共用; maxv < 0 时用 FAVOR_MAX）
func _fav_row(word: String, value: int, fg: Color, maxv := -1) -> HBoxContainer:
	var top := Nations.FAVOR_MAX if maxv < 0 else maxv
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var w := _plain(word, 13, Color(0.92, 0.90, 0.84))
	w.custom_minimum_size = Vector2(44, 0)
	row.add_child(w)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = float(top)
	bar.value = float(value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(230, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.22, 0.18, 0.14)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fg
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var num := _plain("%d / %d" % [value, top], 12, Color(0.98, 0.85, 0.45))
	num.custom_minimum_size = Vector2(64, 0)
	row.add_child(num)
	return row

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

# 不换行的标签（给 HBoxContainer 里的行用）
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
	TimeManager.push_ui_pause()
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
	# 用 _input 抢在 mainland 的 F 处理之前：不然关面板的同一下 F 又被当成"再开一次"。
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
