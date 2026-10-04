# patrol_ui.gd —— 大陆巡逻军队的「军中交谈」面板（海图上走近巡逻队按 F）
#
# 外交玩法的第二入口（w3）：大陆上四处巡逻的是各国的首领亲军 / 封臣军，
# 一开始中立，不会主动动武；走近按 F 可以跟他们搭话：
#   聊天 —— 每天一次，+1 好感，听一句该国的闲话
#   送礼 —— 200 金一次，+5 好感（给当兵的塞好处，不限次数）
#   签约 —— 好感到 40 签商盟（每天 +40 金）、到 70 签盟约（每天 +60 金 +
#           巡逻军队对你友善 + 攻城可请援军）。协议 28 天到期作废。
#
# 数据与每日结算全在 Nations（autoload），这里只管说话和刷新。
# 界面骨架跟 town_ui.gd 同一套：打开暂停时间，F / Esc 关闭，_flash 提示行。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const PANEL_W := 470

var army_name := ""
var nation_id := ""
var _visible := false
var _guard := 0.0
var _chatted_day := {}          # 国家id -> 上次聊天的总天数（聊天一天一次）
var _last_chat := ""
var _root: VBoxContainer = null
var _flash_label: Label = null
var _chat_label: Label = null
var _portrait: TextureRect = null
var _dialog: Control = null     # e16g: 聊天对话框（关掉框才算聊了天）

# 海图开面板前由 world_map 调用（add_child 之前设置，_ready 里就能用）
func setup(army: String, nid: String) -> void:
	army_name = army
	nation_id = nid

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

	var nid := nation_id
	var n: Dictionary = Nations.nation(nid)
	var ncolor: Color = n.get("color", Color(0.9, 0.85, 0.7))

	_root.add_child(_label(army_name, 19, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("%s - %s" % [String(n.get("name", "")), String(n.get("desc", ""))],
		12, ncolor.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER))
	var cap := Nations.captain_name(nid)
	if cap != "":
		# e36n: 称号按国别特色走（港口护卫长 / 雪境巡逻长 ...）, 不再一律「百夫长」
		_root.add_child(_label("%s: %s" % [Nations.captain_title(nid), cap], 13,
			Color(0.98, 0.88, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("巡逻队中立通行. 打好关系, 盟约之下还能请他们助阵",
		11, Color(0.62, 0.60, 0.54), HORIZONTAL_ALIGNMENT_CENTER))
	_flash_label = _label("", 12, Color(0.75, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_flash_label)

	# —— 好感条: 国家一本账, 队长个人一本账（碰面聊天/送礼才涨个人账）——
	# e36n: 第二行的名字用该国称号（5 个字, 见 _fav_row 的名词列宽）
	_root.add_child(_fav_row("好感", Nations.favor_of(nid), ncolor))
	_root.add_child(_fav_row(Nations.captain_title(nid), Nations.captain_favor_of(nid),
		Color(0.98, 0.85, 0.45)))

	# —— 协议状态 ——
	var pact := Nations.pact_of(nid)
	var pact_color := Color(0.62, 0.60, 0.54)
	var pact_text := "协议: 无 (商盟要好感 %d, 盟约要 %d)" % [Nations.TRADE_NEED, Nations.ALLY_NEED]
	if pact != "":
		pact_color = Color(0.75, 0.92, 0.62)
		var income := Nations.TRADE_INCOME if pact == "商盟" else Nations.ALLY_INCOME
		pact_text = "协议: %s - 还剩 %d 天 - 每天进账 %d 金" % [
			pact, Nations.pact_left(nid), income]
	_root.add_child(_label(pact_text, 12, pact_color))

	# —— 按钮们 ——
	var can_chat := int(_chatted_day.get(nid, -1)) != Nations.total_days()
	var cb := _button("聊聊天 (每天一次, +1 好感)" if can_chat else "今天聊过了", PANEL_W - 60)
	cb.disabled = not can_chat
	cb.pressed.connect(_on_chat)
	_root.add_child(_hwrap(cb))

	var gb := _button("送份礼 (%d 金, +5 好感)" % Nations.GIFT_COST, PANEL_W - 60)
	gb.disabled = Wallet.money < Nations.GIFT_COST
	gb.pressed.connect(_on_gift)
	_root.add_child(_hwrap(gb))

	var tb := _button("签商盟 (每天 +%d 金)" % Nations.TRADE_INCOME, PANEL_W - 60)
	if pact == "盟约":
		tb.text = "已有盟约 (含通商)"
		tb.disabled = true
	tb.pressed.connect(_on_sign.bind("商盟"))
	_root.add_child(_hwrap(tb))

	var ab := _button("签盟约 (每天 +%d 金 + 巡逻友善)" % Nations.ALLY_INCOME, PANEL_W - 60)
	if pact == "盟约":
		ab.text = "盟约生效中 (还剩 %d 天)" % Nations.pact_left(nid)
		ab.disabled = true
	ab.pressed.connect(_on_sign.bind("盟约"))
	_root.add_child(_hwrap(ab))

	# —— 最近的话（百夫长头像 + 对话气泡）——
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
	_portrait.texture = load("res://resources/texture/portraits/captain_%s.png" % nid)
	frame.add_child(_portrait)
	talk_row.add_child(frame)
	_chat_label = _label(_last_chat, 12, Color(0.85, 0.88, 0.95))
	_chat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	talk_row.add_child(_chat_label)
	_root.add_child(talk_row)

	# —— 国家最近的大事（协议签下 / 到期都会留通告，不取走，海图那边还要用）——
	var news := Nations.notices
	if news.size() > 0:
		_root.add_child(_label("最近: %s" % news[news.size() - 1], 11, Color(0.62, 0.60, 0.54)))

	_root.add_child(_label("F / Esc 关闭", 11,
		Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))

# e16g/e18: 点聊天只弹对话框（台词组预览不落账, 2~3 段翻完关框才 _finish_chat 记账）
func _on_chat() -> void:
	var nid := nation_id
	if int(_chatted_day.get(nid, -1)) == Nations.total_days():
		return
	var portrait: Texture2D = load("res://resources/texture/portraits/captain_%s.png" % nid)
	_dialog.open_multi(portrait, "%s %s" % [Nations.captain_title(nid), Nations.captain_name(nid)],
		Nations.captain_lines(nid))

# 对话框关掉的那一下才算聊了天: 记今天聊过 + 国家/队长各 +1 好感
func _finish_chat(_line: String = "") -> void:
	var nid := nation_id
	if int(_chatted_day.get(nid, -1)) == Nations.total_days():
		return
	_chatted_day[nid] = Nations.total_days()
	_last_chat = "聊了一阵子"
	Nations.chat_captain(nid)   # 里面: 国家 +1, 队长个人也 +1（触发 changed 重刷）
	_flash("聊了聊, 好感 +1 (%s也是)" % Nations.captain_title(nid))

func _on_gift() -> void:
	var who := Nations.captain_name(nation_id)
	var reply := Nations.gift(nation_id, who, "cap_" + nation_id)  # 扣钱: 国家 +5, 队长个人也 +5
	if reply == "":
		Audio.play_sfx("error", -6.0)
		_flash("钱不够 (要 %d 金)" % Nations.GIFT_COST)
		return
	_last_chat = reply
	Audio.play_sfx("coin", -4.0)
	_flash("好感 +5 (%s也是)" % Nations.captain_title(nation_id))   # 扣钱/好感信号已触发过 rebuild, 别再刷一次把提示清掉

func _on_sign(kind: String) -> void:
	var nid := nation_id
	var why := Nations.can_sign(nid, kind)
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Nations.sign_pact(nid, kind)
	Audio.play_sfx("buy", -4.0)
	_flash("签下了%s" % kind)

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text

# ---------------- 小工具 ----------------
# 一行好感条: 名词 + 进度条 + 数值（国家好感 / 队长个人好感共用）
# e36n: 名词列从 44 放宽到 72 —— 国别称号有 5 个字（港口护卫长）, 44 装不下会压到进度条上
func _fav_row(word: String, value: int, fg: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var w := _plain(word, 13, Color(0.92, 0.90, 0.84))
	w.custom_minimum_size = Vector2(72, 0)
	row.add_child(w)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = float(Nations.FAVOR_MAX)
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
	var num := _plain("%d / %d" % [value, Nations.FAVOR_MAX], 12, Color(0.98, 0.85, 0.45))
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
	# 用 _input 抢在海图的 F 处理之前：不然关面板的同一下 F 又被当成"再开一次"。
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
