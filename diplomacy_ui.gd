# diplomacy_ui.gd —— 背包面板里的「外交」页
#
# 城镇议事厅是「上门拜访」（一次只能谈一国），这页是「运筹帷幄」：
#   一屏摆开五国，每国一张卡片 —— 国王头像 / 好感条 / 协议状态 / 军事力量，
#   送礼、签商盟、签盟约当场就能办。聊天不在这页 —— 得去地图上碰见领主当面谈。
#
# 军事力量 = 该国各镇守军之和（army_power）：攻城打赢会打掉，重整期结束回升，
# 所以这页数字是活的 —— 想动手前先翻翻谁的「不堪一击」。
#
# 数据全在 Nations（autoload），这里只管说话和刷新；由 backpack_ui 当子页挂着，
# 开关和锁时间都归背包面板管，这里不再自己弹全屏。
extends VBoxContainer

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var _last_chat := {}      # 国家id -> 最近一句回应（送礼回话记在这儿）
var _root: VBoxContainer = null
var _flash_label: Label = null

func _ready() -> void:
	_build()
	Wallet.money_changed.connect(func(_m): if visible: _rebuild())
	Nations.changed.connect(func(): if visible: _rebuild())
	_rebuild()

# ---------------- 搭界面 ----------------
func _build() -> void:
	# 内容可能超过一屏高（五国卡片），套一层滚动
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 6)
	scroll.add_child(_root)

# ---------------- 刷新 ----------------
func _rebuild() -> void:
	if _root == null:
		return
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

	_flash_label = _label("", 12, Color(0.75, 0.9, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_flash_label)

	# 自己的势力也占一张卡（排最上, 只报家底, 不用跟自己外交）
	_root.add_child(_player_block())
	if Nations.NATIONS.size() > 0:
		_root.add_child(HSeparator.new())
	for i in Nations.NATIONS.size():
		_root.add_child(_nation_block(Nations.NATIONS[i]))
		if i < Nations.NATIONS.size() - 1:
			_root.add_child(HSeparator.new())

	# —— 国家最近的大事（协议签下 / 到期都会留通告，不取走，海图那边还要用）——
	var news := Nations.notices
	if news.size() > 0:
		_root.add_child(_label("最近: %s" % news[news.size() - 1], 11,
			Color(0.62, 0.60, 0.54)))

# 自己的势力卡（排最上）: 主角头像 + 人丁 + 占领的领地, 只报家底没有外交按钮
func _player_block() -> Control:
	var lands := Nations.occupied.size()
	var pcolor := Color(0.28, 0.90, 0.82)    # 潮汐港的旗色（青碧, e13c 跟国界占领色同款）
	var block := PanelContainer.new()
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.16, 0.13, 0.10, 0.9)
	bstyle.border_color = pcolor
	bstyle.set_border_width_all(1)
	bstyle.set_border_width(SIDE_LEFT, 6)
	bstyle.set_corner_radius_all(6)
	bstyle.content_margin_left = 12
	bstyle.content_margin_right = 10
	bstyle.content_margin_top = 8
	bstyle.content_margin_bottom = 8
	block.add_theme_stylebox_override("panel", bstyle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	block.add_child(row)

	var frame := PanelContainer.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0.16, 0.13, 0.10)
	fstyle.border_color = pcolor
	fstyle.set_border_width_all(2)
	fstyle.set_corner_radius_all(6)
	fstyle.content_margin_left = 3
	fstyle.content_margin_right = 3
	fstyle.content_margin_top = 3
	fstyle.content_margin_bottom = 3
	frame.add_theme_stylebox_override("panel", fstyle)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # e30m: 不随行高拉伸, 头像贴住框底
	var portrait := TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = load("res://resources/texture/portraits/player.png")
	frame.add_child(portrait)
	row.add_child(frame)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_plain("%s - 主角自己的势力" % Nations.player_nation_name, 13,
		Color(1.0, 0.93, 0.65)))
	head.add_child(_plain("人丁: %d (自己 + %d 伙伴)" % [1 + Slaves.count, Slaves.count],
		12, Color(0.85, 0.86, 0.90)))
	col.add_child(head)
	var land_text := "领地: 潮汐港 (出海攻城能插旗扩土)"
	if lands > 0:
		land_text = "领地: 潮汐港 + 打下的 %d 座城" % lands
	col.add_child(_label(land_text, 11, Color(0.62, 0.60, 0.54)))
	# —— 声望与主从契约（e13g）——
	col.add_child(_label("声望: %d (打仗/海外贸易攒, 够数才能签雇佣兵 20 / 封臣 50)"
		% Nations.prestige, 11, Color(0.98, 0.85, 0.45)))
	var ctext := "契约: 无 (签一国后打它的敌人有赏金加成)"
	if Nations.contract != "":
		var lname := String(Nations.nation(Nations.liege).get("name", Nations.liege))
		ctext = "契约: %s - 宗主 %s" % [Nations.contract, lname]
		if Nations.contract == "封臣" and Nations.fief != "":
			ctext += " - 封地 %s" % String(Nations.TOWNS.get(Nations.fief, {}).get("name", Nations.fief))
	col.add_child(_label(ctext, 11, Color(0.75, 0.92, 0.62) if Nations.contract != ""
		else Color(0.55, 0.52, 0.46)))
	if Nations.contract == "雇佣兵":
		var sev := _button("解约雇佣兵", 110)
		sev.pressed.connect(func() -> void:
			var why := Nations.sever_contract()
			_flash(why if why != "" else "契约已解除")
			_rebuild())
		col.add_child(sev)
	elif Nations.contract == "封臣":
		var bet := _button("叛变! 带封地脱离并宣战", 190)
		bet.tooltip_text = "封地真变成你的, 与宗主国开战 (国界涂色跟着变)"
		bet.pressed.connect(func() -> void:
			var why := Nations.betray_liege()
			_flash(why if why != "" else "叛变成功! 领地到手, 与宗主开战")
			Audio.play_sfx("error", -2.0)
			_rebuild())
		col.add_child(bet)
	col.add_child(_label("自己的家底不用跟自己外交 - 想扩地就出海攻城", 11,
		Color(0.55, 0.52, 0.46)))
	return block

# 一国一张卡片：左侧国王头像，右侧关系与武备 + 外交按钮
func _nation_block(n: Dictionary) -> Control:
	var nid := String(n.get("id", ""))
	var ncolor: Color = n.get("color", Color(0.9, 0.85, 0.7))
	var power := Nations.army_power(nid)

	var block := PanelContainer.new()
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.16, 0.13, 0.10, 0.9)
	bstyle.border_color = ncolor
	bstyle.set_border_width_all(1)
	bstyle.set_border_width(SIDE_LEFT, 6)   # 左边框加粗当国旗色条
	bstyle.set_corner_radius_all(6)
	bstyle.content_margin_left = 12
	bstyle.content_margin_right = 10
	bstyle.content_margin_top = 8
	bstyle.content_margin_bottom = 8
	block.add_theme_stylebox_override("panel", bstyle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	block.add_child(row)

	# —— 国王头像（主城领主 = 国王, 头像 lord_<主城id>.png）——
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
	var portrait := TextureRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = load("res://resources/texture/portraits/lord_%s.png" % _capital_of(nid))
	frame.add_child(portrait)
	row.add_child(frame)

	# —— 右侧：名头 / 好感条 / 协议与军力 / 按钮 / 最近的话 ——
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var aw := Nations.army_word(nid)
	var name_lab := _plain("%s - %s" % [String(n.get("name", "")), String(n.get("desc", ""))],
		13, ncolor.lightened(0.25))
	head.add_child(name_lab)
	head.add_child(_plain("武备: %s (守军 x%d)" % [aw, power], 12, _army_color(aw)))
	col.add_child(head)

	# 好感条（复用 town_ui 的画法, 缩窄一点）
	var fav_row := HBoxContainer.new()
	fav_row.add_theme_constant_override("separation", 8)
	fav_row.add_child(_plain("好感", 12, Color(0.92, 0.90, 0.84)))
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = float(Nations.FAVOR_MAX)
	bar.value = float(Nations.favor_of(nid))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 13)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.22, 0.18, 0.14)
	bar_bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = ncolor
	bar_fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", bar_fg)
	fav_row.add_child(bar)
	fav_row.add_child(_plain("%d/%d" % [Nations.favor_of(nid), Nations.FAVOR_MAX],
		11, Color(0.98, 0.85, 0.45)))
	col.add_child(fav_row)

	var pact := Nations.pact_of(nid)
	var pact_color := Color(0.62, 0.60, 0.54)
	var pact_text := "协议: 无 (商盟要好感 %d, 盟约要 %d)" % [
		Nations.TRADE_NEED, Nations.ALLY_NEED]
	if pact != "":
		pact_color = Color(0.75, 0.92, 0.62)
		var income := Nations.TRADE_INCOME if pact == "商盟" else Nations.ALLY_INCOME
		pact_text = "协议: %s - 剩 %d 天 - 每天 +%d 金" % [
			pact, Nations.pact_left(nid), income]
	col.add_child(_label(pact_text, 11, pact_color))

	# e52d: 关系行 —— 跟玩家、跟列国的战争状态（开战/停战剩多少天一眼看清）
	var parts: Array[String] = []
	var rel_col := Color(0.62, 0.60, 0.54)
	if Nations.at_war_with(nid):
		var wleft := maxi(0, int(Nations.at_war.get(nid, 0)) - Nations.total_days())
		parts.append("与你交战中 (休战还剩 %d 天)" % wleft)
	var wars: Array = Nations.ai_wars_of(nid)
	if not wars.is_empty():
		var wnames: Array[String] = []
		var wshort := 9999
		for wid in wars:
			wnames.append(String(Nations.nation(String(wid)).get("name", String(wid))))
			wshort = mini(wshort, Nations.ai_war_left(nid, String(wid)))
		parts.append("与%s交战中 (休战还剩 %d 天)" % ["/".join(wnames), wshort])
	var rel := "相安无事"
	if not parts.is_empty():
		rel = " / ".join(parts)
		rel_col = Color(0.95, 0.55, 0.45)
	col.add_child(_label("关系: %s" % rel, 11, rel_col))

	# —— 三样外交活动（聊天要去地图上碰领主），一行摆开 ——
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var gb := _button("送礼+5", 92)
	gb.disabled = Wallet.money < Nations.GIFT_COST
	gb.tooltip_text = "花 %d 金买交情" % Nations.GIFT_COST
	gb.pressed.connect(_on_gift.bind(nid))
	btn_row.add_child(gb)

	var tb := _button("签商盟", 92)
	if pact == "盟约":
		tb.text = "含通商"
		tb.disabled = true
	elif pact == "商盟":
		tb.text = "已签"
		tb.disabled = true
	tb.pressed.connect(_on_sign.bind(nid, "商盟"))
	btn_row.add_child(tb)

	var ab := _button("签盟约", 92)
	if pact == "盟约":
		ab.text = "剩%d天" % Nations.pact_left(nid)
		ab.disabled = true
	ab.pressed.connect(_on_sign.bind(nid, "盟约"))
	btn_row.add_child(ab)

	# —— 主从契约（e13g）: 只能签一国; 雇佣兵可原地升级封臣 ——
	var mwhy := Nations.can_sign_contract(nid, "雇佣兵")
	var mb := _button("签佣", 70)
	mb.disabled = mwhy != ""
	mb.tooltip_text = "雇佣兵协议 (声望 20): 打土匪金+50%声望+1, 打宗主国的敌人金翻倍声望+2" \
		if mwhy == "" else mwhy
	mb.pressed.connect(func() -> void:
		if Nations.sign_contract(nid, "雇佣兵"):
			_flash("签下了%s的雇佣兵契约" % String(n.get("name", nid)))
			Audio.play_sfx("buy", -4.0)
		_rebuild())
	btn_row.add_child(mb)

	var cwhy := Nations.can_sign_contract(nid, "封臣")
	var cb := _button("签封臣", 82)
	cb.disabled = cwhy != ""
	cb.tooltip_text = "封臣协议 (声望 50): 雇佣兵权益 + 挑一座城当封地, 每天有岁入 (首都更高)" \
		if cwhy == "" else cwhy
	cb.pressed.connect(func() -> void:
		_pick_fief(nid))
	btn_row.add_child(cb)

	var btn_wrap := HBoxContainer.new()
	btn_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_wrap.add_child(btn_row)
	col.add_child(btn_wrap)

	# 最近一句话（该国领主说过什么 / 收礼回应）
	var said := String(_last_chat.get(nid, ""))
	if said != "":
		col.add_child(_label("\"%s\"" % said, 11, Color(0.85, 0.88, 0.95)))
	return block

# ---------------- 外交活动 ----------------
# 封臣要挑封地（e13g）: 弹一层该国的城列表, 点哪座哪座就是自己的封地（每天有岁入）
func _pick_fief(nid: String) -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(wrap)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.06, 0.98)
	sb.border_color = Color(0.62, 0.47, 0.28)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	wrap.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := _label("向 %s 称臣 - 挑一座城做封地" % String(Nations.nation(nid).get("name", nid)),
		16, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(title)
	box.add_child(_label("首都岁入 %d 金/天, 普通城 %d 金/天; 封地就是你的城, 叛变时能带走" \
		% [Nations.FIEF_CAP_INCOME, Nations.FIEF_INCOME],
		11, Color(0.72, 0.68, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	for tid in Nations.TOWNS.keys():
		var t: Dictionary = Nations.TOWNS[tid]
		if String(t.get("nation", "")) != nid:
			continue
		var b := _button("%s%s (%d金/天)" % [String(t.get("name", tid)),
			" [首都]" if String(t.get("kind", "")) == "capital" else "",
			Nations.FIEF_CAP_INCOME if String(t.get("kind", "")) == "capital"
			else Nations.FIEF_INCOME], 320)
		b.pressed.connect(func() -> void:
			if Nations.sign_contract(nid, "封臣", String(tid)):
				_flash("称臣成功! 封地: %s" % String(t.get("name", tid)))
				Audio.play_sfx("buy", -4.0)
			wrap.queue_free()
			_rebuild())
		box.add_child(b)
	var cancel := _button("再想想", 320)
	cancel.pressed.connect(wrap.queue_free)
	box.add_child(cancel)

func _on_gift(nid: String) -> void:
	var reply := Nations.gift(nid)  # 里面扣钱 +5 好感（who 省略 -> 用国名）
	if reply == "":
		Audio.play_sfx("error", -6.0)
		_flash("钱不够 (要 %d 金)" % Nations.GIFT_COST)
		return
	_last_chat[nid] = reply
	Audio.play_sfx("coin", -4.0)
	_flash("%s收礼甚悦, 好感 +5" % _king_word(nid))

func _on_sign(nid: String, kind: String) -> void:
	var why := Nations.can_sign(nid, kind)
	if why != "":
		Audio.play_sfx("error", -6.0)
		_flash(why)
		return
	Nations.sign_pact(nid, kind)     # push_notice + changed 都在里面
	Audio.play_sfx("buy", -4.0)
	_flash("与%s签下了%s" % [String(Nations.nation(nid).get("name", nid)), kind])

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text

# 该国的国王头像 id：主城（kind == capital）的镇 id
func _capital_of(nid: String) -> String:
	for tid in Nations.TOWNS.keys():
		var t: Dictionary = Nations.TOWNS[tid]
		if String(t.get("nation", "")) == nid and String(t.get("kind", "")) == "capital":
			return tid
	return nid

# 送礼提示里点出名号（主城领主 title+name，没配到就笼统说「该国国王」）
func _king_word(nid: String) -> String:
	var full := Nations.lord_full(_capital_of(nid))
	return full if full != "" else "该国国王"

func _army_color(word: String) -> Color:
	match word:
		"兵强马壮":
			return Color(0.90, 0.45, 0.40)
		"武备整肃":
			return Color(0.98, 0.85, 0.45)
		"守备平平":
			return Color(0.85, 0.86, 0.90)
		_:
			return Color(0.70, 0.92, 0.60)   # 不堪一击 -> 绿（可乘之机）

# ---------------- 小工具 ----------------
func _button(text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 26)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 12)
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
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
