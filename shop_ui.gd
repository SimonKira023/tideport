# shop_ui.gd —— 商人的交易面板
#   只做一件事：买种子/材料（花金币进货）
#   e30w：卖货整块砍掉 —— 出货统一走「售卖箱」（scene/shipping_bin.gd + bin_ui.gd），
#         商人这边不再收货（两处卖货等于两个价，玩家也记不住该去哪儿）。
# 由 merchant.gd 在玩家走近按 F 时打开；打开时锁定角色。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const STORY := preload("res://story_dialogue.gd")     # e43: 剧情旗 (鱼竿上不上架)

# 商人卖的货。price 是**基准**进货价；实付价走 Research.buy_price_of()（行商技能/驼队卡打折），
# 种子长大后卖多少走 Research.sell_price_of()（行商技能/科技树/互市卡加价）。
# locked_by: 有这把剧情旗没立起来之前, 这行挂「未上架」且按钮点不动 (e43 鱼竿)。
const STOCK := [
	{"seed": "res://item/carrot_seed.tres", "price": 10},
	{"seed": "res://item/seed.tres", "price": 14},          # 土豆种子
	{"seed": "res://item/cabbage_seed.tres", "price": 22},
	{"seed": "res://item/pumpkin_seed.tres", "price": 40},
	# e52: 甜菜/花椰菜也备货（价跟 market_ui.STOCK 一致）—— 货架只摆当季的,
	#      六包都在才不会出现「冬天岛上买不到任何种子」
	{"seed": "res://item/beet_seed.tres", "price": 22},          # 甜菜种子（冬）
	{"seed": "res://item/cauliflower_seed.tres", "price": 26},   # 花椰菜种子（夏）
	# e43: 开局哥布林不卖鱼竿 —— 第二天撞见他在河边钓鱼、聊完才进货
	{"seed": "res://item/fishing_rod.tres", "price": 50, "locked_by": "goblin_rod"},
	# e30p: 小鸡不再走道具链路 —— 买鸡/卖鸡都在鸡舍管理界面里办（对鸡舍按 F）
	{"seed": "res://item/wheat.tres", "price": 8},          # 小麦（材料, 厨房做面包/派的原料）
]

var _visible := false
var _money_label: Label
var _flash_label: Label
var _grid: GridContainer = null     # e52: 种子货架（换季要重铺, 见 _fill_stock）
var _seed_head: Label = null        # e52: 「买种子」那行标题（顺手写上现在是哪一季）
var _stock_season := -1             # e52: 货架是按哪一季铺的
# [{"seed": ItemData, "base": int, "price_label": Label, "earn_label": Label, "button": Button}]
var _rows: Array = []
var _tips: Array = []       # 每行图标，刷新时要重写 tooltip（里面也有价格）
var _rate_label: Label      # 顶部一行：现在的买卖加成是多少

func _ready() -> void:
	add_to_group("shop")
	# 自己必须是全屏尺寸！父节点是 HUD(CanvasLayer) 而不是 Control，
	# Control 的默认锚点是「左上角 + 0 尺寸」→ 遮罩 ColorRect 会退化成 0x0，
	# 面板就会被顶到屏幕左上角。必须自己声明占满全屏。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Wallet.money_changed.connect(func(_m): _refresh())
	Inventory.inventory_changed.connect(_refresh)
	_refresh()

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

	vbox.add_child(_label("商人 - 进货", 22, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	money_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(money_row)
	var coin := TextureRect.new()
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var coin_base := SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/UI/Money.png")
	if coin_base == null:
		push_warning("[素材] 金币图标缺失, 已留空")
		coin.visible = false
	var coin_at := AtlasTexture.new()
	coin_at.atlas = coin_base      # 缺失时为 null, 图标留空
	coin_at.region = Rect2(0, 0, 16, 16)      # 96x16 图集取第 1 枚金币
	coin.texture = coin_at
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money_row.add_child(coin)
	_money_label = _label("", 14, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	money_row.add_child(_money_label)
	_rate_label = _label("", 12, Color(0.7, 0.86, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_rate_label)

	# ❗中段（买种子清单）限高滚动：货架以后再加料也不至于顶出 648 的屏幕底、
	#   把页脚按钮挤到屏外。标题/钱包/加成/提示/关闭留在滚动框外，永远看得见
	#   —— 跟 market_ui 同一套路。
	var body := ScrollContainer.new()
	body.custom_minimum_size = Vector2(0, 260)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(body)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	body.add_child(col)

	_seed_head = _separator("买种子") as Label
	col.add_child(_seed_head)

	# 每一行：作物图标 | 名字 | 进价 | 收成卖价 | 「买」按钮
	# ❗「收成卖价」直接摆在这（不是藏进悬浮提示）：进货价和收成价放一起，利润一眼看清
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(_grid)
	_fill_stock()

	_flash_label = _label("", 14, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_flash_label)

	# ❗招募伙伴从商店挪去了「篝火」（campfire_ui.gd）：某些天傍晚野外会出现篝火，
	#   走近按 F 才能招人 —— 商店现在只管进货（卖货在售卖箱）。

	var close := Button.new()
	close.text = "关闭 (F / Esc)"
	close.custom_minimum_size = Vector2(0, 32)
	close.add_theme_font_override("font", PIXEL_FONT)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(close_panel)
	vbox.add_child(close)

# e52: 铺种子货架 —— 只摆当季能种的（Farm.season_ok_for 是季节的唯一真相源;
#   小麦/鱼竿这些没有 seasons, 一律照摆）。换季要重铺, 见 _refresh。
func _fill_stock() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_rows.clear()
	_tips.clear()
	var season: int = clampi(TimeManager.season, 0, TimeManager.SEASONS.size() - 1)
	_stock_season = season
	if _seed_head != null:
		_seed_head.text = "--- 买种子 (当季: %s季) ---" % TimeManager.SEASONS[season]

	for entry in STOCK:
		var seed: ItemData = load(entry["seed"])
		if seed == null:
			continue
		# ★ 只卖当季种子：过季的种子不上架（甜菜=冬、花椰菜=夏…）;
		#   小麦/鱼竿没有 seasons, Farm.season_ok_for 一律放行。
		if not Farm.season_ok_for(seed):
			continue
		var base: int = int(entry["price"])

		# 长成什么（用作物图标，一眼看出这包种子种出来是啥）
		var crop_icon := TextureRect.new()
		crop_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		crop_icon.custom_minimum_size = Vector2(32, 32)
		crop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 种子行长成物图标; 工具行（鱼竿）没有 grow_to, 显示自己的图标
		crop_icon.texture = seed.grow_to.icon if seed.grow_to != null else seed.icon
		_grid.add_child(crop_icon)

		var name_label := _label(seed.display_name, 14, Color(0.95, 0.93, 0.88))
		name_label.custom_minimum_size = Vector2(140, 0)
		name_label.tooltip_text = seed.info_text()
		_grid.add_child(name_label)

		var price_label := _label("", 14, Color(0.98, 0.85, 0.45))
		price_label.custom_minimum_size = Vector2(60, 0)
		_grid.add_child(price_label)

		# 收成卖价 + 净赚（正数绿色 / 负数灰色）—— 具体数字在 _refresh 里按加成算
		var earn_label := _label("", 13, Color(0.55, 0.9, 0.5))
		earn_label.custom_minimum_size = Vector2(180, 0)
		_grid.add_child(earn_label)

		var buy := Button.new()
		buy.text = "买"
		buy.custom_minimum_size = Vector2(58, 30)
		buy.add_theme_font_override("font", PIXEL_FONT)
		buy.add_theme_font_size_override("font_size", 14)
		buy.pressed.connect(_buy.bind(seed, base))
		_grid.add_child(buy)

		_rows.append({"seed": seed, "base": base, "price_label": price_label,
			"earn_label": earn_label, "button": buy, "name_label": name_label,
			"lock": String(entry.get("locked_by", "")), "base_name": seed.display_name})
		_tips.append(crop_icon)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _separator(text: String) -> Control:
	var l := _label("--- %s ---" % text, 13, Color(0.72, 0.64, 0.52), HORIZONTAL_ALIGNMENT_CENTER)
	return l

# ---------------- 刷新 ----------------
func _refresh() -> void:
	# e52: 换季了就把种子货架重铺一遍（当季的才上架）——
	#   这个面板只在 _ready 里搭一次, 不重铺的话过季了还摆着上季的种子。
	if _stock_season != TimeManager.season:
		_fill_stock()
	if _money_label != null:
		_money_label.text = "口袋里的金币: %d" % Wallet.money
	# 买：价格吃「行商技能 / 驼队卡」的折扣，买不起就把按钮灰掉
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var seed: ItemData = r["seed"]
		var base: int = int(r["base"])
		var btn: Button = r["button"]
		var get_earn: Label = r["earn_label"]
		var get_name: Label = r["name_label"]
		# e43: 剧情没解锁的行挂「未上架」——按钮锁死, 价格和收成都不报
		var lock := String(r.get("lock", ""))
		if lock != "" and not STORY.flag_get(lock):
			get_name.text = "%s (未上架)" % String(r.get("base_name", seed.display_name))
			get_name.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
			r["price_label"].text = "--"
			r["price_label"].add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
			get_earn.text = "哥布林还没进这批货"
			get_earn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
			get_earn.tooltip_text = "还没上架: 哥布林那边有点缘由"
			_tips[i].tooltip_text = get_earn.tooltip_text
			btn.disabled = true
			btn.modulate = Color(0.75, 0.72, 0.7)
			continue
		get_name.text = String(r.get("base_name", seed.display_name))
		get_name.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
		var price := Research.buy_price_of(base)
		var get_price: Label = r["price_label"]
		if price != base:
			get_price.text = "%d金" % price
			get_price.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
		else:
			get_price.text = "%d金" % price
			get_price.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
		# 收成卖价 + 净赚（也带上科技/卖价加成）；工具行（鱼竿）没有收成, 标一下类别
		var tip: TextureRect = _tips[i]
		if seed.grow_to == null:
			get_earn.text = seed.type             # 非种子行直接标类别（工具/材料）
			get_earn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.68))
			get_earn.tooltip_text = seed.info_text()
		else:
			var sell_one: int = Research.sell_price_of(seed.grow_to)
			var earn: int = sell_one - price
			var days: int = seed.grow_days
			get_earn.text = "%d天成熟 - 卖%d金 (+%d)" % [days, sell_one, earn]
			get_earn.add_theme_color_override("font_color",
				Color(0.55, 0.9, 0.5) if earn >= 0 else Color(0.7, 0.7, 0.68))
			get_earn.tooltip_text = "%s\n生长周期: %d天成熟\n收成卖价: %d金/个\n买一包 %d金, 卖一个收成净赚 %d金" \
				% [seed.grow_to.display_name, days, sell_one, price, earn]
		if tip != null:
			tip.tooltip_text = get_earn.tooltip_text
		var ok: bool = Wallet.money >= price
		btn.disabled = not ok
		btn.modulate = Color(1, 1, 1) if ok else Color(0.75, 0.72, 0.7)
	# 顶部那行：现在的买卖倍率（一眼看出技能/科技/卡片到底值多少）
	if _rate_label != null:
		var sm := Research.sell_mult("作物")
		var bm := Research.buy_mult()
		var extra: Array = []
		var trade := int(Legion.skills.get("trade", 0))
		if trade > 0:
			extra.append("行商 Lv%d" % trade)
		if Research.is_active("market"):
			extra.append("互市卡")
		if Research.is_active("caravan"):
			extra.append("驼队卡")
		var suffix := "" if extra.is_empty() else "  (%s)" % " ".join(extra)
		_rate_label.text = "作物卖出 x%.2f    买入 x%.2f%s" % [sm, bm, suffix]

# ---------------- 买 ----------------
func _buy(seed: ItemData, base: int) -> void:
	if seed == null:
		return
	# e43: 剧情没解锁的行不许买（按钮本来就灰着, 这里再兜一道）
	for r in _rows:
		if r["seed"] == seed:
			var lk := String(r.get("lock", ""))
			if lk != "" and not STORY.flag_get(lk):
				Audio.play_sfx("error", -4.0)
				_flash("哥布林还没进这批货")
				return
			break
	# ❗传进来的是基准价，实付按当下加成重算（技能可能刚升过级）
	var price := Research.buy_price_of(base)
	if not Wallet.spend_money(price):
		Audio.play_sfx("error", -4.0)
		_flash("金币不够 (要 %d 金)" % price)
		return
	if not Inventory.add_item(seed, 1):
		Wallet.add_money(price)          # 背包塞不下：退钱
		Audio.play_sfx("error", -4.0)
		_flash("背包满了,放不下")
		return
	Audio.play_sfx("buy")
	_flash("买了 1 包%s" % seed.display_name)
	Quests.complete("buy_goblin")     # 开局指引：第一次照顾哥布林生意
	_refresh()

# ---------------- 卖 ----------------
# e30w: 商人不再收卖货 —— 卖货整块搬去了「售卖箱」（scene/shipping_bin.gd + bin_ui.gd）。
# 想改成「商人收货」的话别在这儿加回来：两处卖货等于两个价，出货口只能有一个。

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
# 会被 merchant 的 _unhandled_input 也收到，关了又立刻开。
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close_panel()
		get_viewport().set_input_as_handled()

func open_panel() -> void:
	if _visible:
		return
	_visible = true
	show()
	TimeManager.push_ui_pause()      # 逛商店的时候时间停住
	Audio.play_sfx("ui_open")
	_flash_label.text = ""
	_refresh()
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	TimeManager.pop_ui_pause()
	Audio.play_sfx("ui_close")
	closed.emit()

func is_open() -> bool:
	return _visible
