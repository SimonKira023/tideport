# shipping_bin.gd —— 物品售卖箱（星露谷同款「睡觉时自动卖货」的箱子）
#
# 玩法：
#   · 走近箱子按 F → 打开售卖箱面板（左边背包 / 右边箱里的货, 点背包格放货进去）
#   · 投进去的东西在关箱时统一卖掉（e29b）：哥布林渠道立刻入账, 海外渠道次日到账
#   · 箱子上会飘一行「待售 N 件 · 预计 X 金」，一眼看到里面有多少货
#
# 素材：`Objects/Exterior/shipping box.png`（48x64）。
# ❗这张图里**并排着好几个单箱变体**，不是「上下两半拼一个大箱子」。
#    实测（按 alpha 逐列扫）：每个箱子只有 ~13 像素宽，一行里并排放了 3 个。
#    当初误把「上面的箱子」和「下面的箱子」上下叠成 15x35，看着就是个双屉柜 —— 这就是「显示不全」的原因。
#    现在老老实实取**一个箱子**，而且正好素材给了两种状态：
#      · (16,16,13,16) 闭合的箱子（带一道搭扣）
#      · (16,48,13,16) 敞口的箱子（盖子开着，里面是暗的）
#    空箱显示闭合、有货显示敞口 —— 一眼就知道里面有没有东西。
#    ❗e38a 敞口以前取 (16,45,13,19)：那 19 行里**最上面 3 行是脏的** ——
#      y45~47 落在 x16..28 这一格里的只有 x17 / x16..18 几个像素，那是左边那个箱子
#      **掀起的盖子伸过来的碎片**，于是敞口状态头顶总挂着一小块莫名其妙的木片。
#      箱体真正的第一行是 y48（从这一行起相邻两箱并成一片，分不出缝），
#      所以改成 (16,48,13,16)：跳过脏行，高度 16 跟闭合箱一致，也不必再垫高底对齐。
# ❗原生像素直接用，**千万别放大**，否则它的像素会比全世界大一倍。
extends Area2D

signal changed

const SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/shipping box.png"
const BOX_CLOSED := Rect2i(16, 16, 13, 16)   # 空箱：闭合
const BOX_OPEN := Rect2i(16, 48, 13, 16)     # 有货：敞口（跳过 y45~47 的邻箱盖碎片）
const ART_W := 13
const ART_H := 16                             # 两种状态同高 16，不用再垫高底对齐

# 箱子的原点在「底部中心」：贴图往上画，方便直接按地面格子摆位置
const ART_ORIGIN := Vector2(-ART_W * 0.5, -float(ART_H))

var pending: Array = []          # [{item: ItemData, count: int, price: int, mode: String}]
var mode := "哥布林"              # 当前投放渠道（e29a）: 哥布林=关箱即售 / 海外=+40%金 次日到账+按流水折算声望
var sea_hold: Array = []         # 海外在途: [{gold: int, due: int}]（due = 全局日序号）
const SEA_MARKUP := 1.4          # 海外贸易卖价加成（+40%）
var _in_range := false
var _label: Label
var _art: Sprite2D
var _tex_closed: ImageTexture = null
var _tex_open: ImageTexture = null
var _key_hint: Node2D = null         # 走近时浮在半空的「F 存入作物」提示

func _ready() -> void:
	add_to_group("shipping_bin")
	# e33 箱子脚下的影子
	add_child(preload("res://scene/shadow_util.gd").make_shadow(16, 6, 0.26))
	_build_art()
	_build_label()
	_build_key_hint()
	body_entered.connect(func(b): _set_range(b, true))
	body_exited.connect(func(b): _set_range(b, false))
	_refresh_label()
	TimeManager.new_day.connect(_on_new_day)

# 今天的全局日序号（海外贸易的到账期限用）
func _day_stamp() -> int:
	return TimeManager.year * 10000 + TimeManager.season * 100 + TimeManager.day

# 海外在途的货今天到没到期（e29a）: 到期 = 货款入账, 每累积卖出 1000 金 +1 声望
func _on_new_day(_d: int) -> void:
	if sea_hold.is_empty():
		return
	var gold := 0
	var keep: Array = []
	for e in sea_hold:
		if int(e["due"]) <= _day_stamp():
			gold += int(e["gold"])
		else:
			keep.append(e)
	sea_hold = keep
	if gold > 0:
		Wallet.add_money(gold)
		var pr := Nations.add_sea_gold(gold)
		if pr > 0:
			_hint("海外商船回航! 货款 %d 金到账, 声望 +%d" % [gold, pr])
		else:
			_hint("海外商船回航! 货款 %d 金到账" % gold)

# 从上往下排：常驻的「F 售卖箱」提示在 -52，「待售 N 件」标签在 -34
func _build_key_hint() -> void:
	_key_hint = preload("res://scene/key_hint.gd").new()
	_key_hint.setup("F", "售卖箱", -52.0)
	# e38b 箱子整体上移之后，它的 y-sort（箱底 162）落到农舍（房基 170）后面，
	#   整个箱子连同这两行浮字都会画在房子之下；浮字单独抬 z 才不会被房顶贴图盖掉。
	_key_hint.z_index = 2
	_key_hint.connect("clicked", _do_interact)   # e36i: 左键点这个框 = 按 F（字符串写法, _key_hint 是 Node2D）
	add_child(_key_hint)

func _set_range(body: Node2D, on: bool) -> void:
	if body.is_in_group("player"):
		_in_range = on
		if on:
			_key_hint.show_hint()
		else:
			_key_hint.hide_hint()

# ---------------- 外观 ----------------
func _build_art() -> void:
	_art = Sprite2D.new()
	_art.name = "Art"
	_art.centered = false
	_art.position = ART_ORIGIN
	_tex_closed = _make_texture(BOX_CLOSED)
	_tex_open = _make_texture(BOX_OPEN)
	_art.texture = _tex_closed
	add_child(_art)

# 从素材里裁出一个箱子，垫到 13x16、**底对齐**
func _make_texture(trim: Rect2i) -> ImageTexture:
	var tex: Texture2D = load(SHEET)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var piece := img.get_region(trim)
	if piece == null:
		return null
	var out := Image.create_empty(ART_W, ART_H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()),
		Vector2i(0, ART_H - piece.get_height()))     # 底对齐
	return ImageTexture.create_from_image(out)

# 空箱 = 闭合，有货 = 敞口
func _refresh_art() -> void:
	if _art == null:
		return
	_art.texture = _tex_open if pending_count() > 0 else _tex_closed

func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(1, 0.95, 0.72))
	_label.add_theme_constant_override("outline_size", 5)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(-52, -34)
	_label.z_index = 2      # 跟 _build_key_hint 同一个原因：抬到房顶之上
	_label.custom_minimum_size = Vector2(104, 0)
	_label.size = Vector2(104, 14)
	_label.visible = false
	add_child(_label)

func _refresh_label() -> void:
	_refresh_art()
	if _label == null:
		return
	var n := pending_count()
	if n <= 0:
		_label.visible = false
		return
	_label.visible = true
	_label.text = "待售 %d 件 - %d 金" % [n, pending_total()]

# ---------------- 交互 ----------------
func _unhandled_input(event: InputEvent) -> void:
	if not _in_range or not event.is_action_pressed("interact"):
		return
	_do_interact()

# 按 F / 左键点「F 售卖箱」框共用这一段（e36i）
func _do_interact() -> void:
	if not _in_range:
		return
	# 打开售卖箱面板（左背包 / 右箱子, 点选放货）；面板没挂上时退回一键全存
	var ui: Node = get_tree().get_first_node_in_group("bin_panel")
	if ui != null:
		ui.open_panel(self)
	else:
		deposit_all_crops()

# 能进箱子的货：除了工具, 只要有价就收（作物/鱼/材料/种子/地板/装备...）
func _sellable(it: ItemData) -> bool:
	return it != null and it.type != "工具" and it.sell_price > 0

# 把背包里所有能出货的东西一次性投进箱子。返回投进去的件数（0 = 没东西可投）。
func deposit_all_crops() -> int:
	var moved := 0
	var worth := 0
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		if not _sellable(it):
			continue
		var n: int = int(s["count"])
		if n <= 0:
			continue
		# 售价吃「行商技能 / 科技树 / 互市卡」的加成（跟商人那边同一套算法）
		var unit := Research.sell_price_of(it)
		var entry := unit * n
		if mode == "海外":
			entry = int(round(float(entry) * SEA_MARKUP))
		moved += n
		worth += entry
		pending.append({"item": it, "count": n, "price": entry, "mode": mode})
		Inventory.remove_item(it, n)
	if moved <= 0:
		Audio.play_sfx("error", -6.0)
		_hint("背包里没有可以卖的东西(工具不收)")
		return 0
	Audio.play_sfx("bin")
	var eta := "关箱即售" if mode == "哥布林" else "次日到账"
	_hint("放进 %d 件货 (%s), %s %d 金" % [moved, mode, eta, worth])
	_refresh_label()
	changed.emit()
	return moved

# 面板点选：把背包某一格的物品放进箱子（bin_ui 调用：左键 1 个 / 右键整格）。
# 返回放进去的件数（0 = 工具/无价物, 不收）。
# e43: 同一件货 + 同一渠道就并进原来那行 —— 左键一个一个点, 箱单不会排成一长串。
func deposit_one(it: ItemData, n: int) -> int:
	if not _sellable(it) or n <= 0:
		return 0
	var unit := Research.sell_price_of(it)
	var worth := unit * n
	if mode == "海外":
		worth = int(round(float(worth) * SEA_MARKUP))
	var merged := false
	for e in pending:
		if e["item"] == it and String(e.get("mode", "哥布林")) == mode:
			e["count"] = int(e["count"]) + n
			e["price"] = int(e["price"]) + worth
			merged = true
			break
	if not merged:
		pending.append({"item": it, "count": n, "price": worth, "mode": mode})
	Inventory.remove_item(it, n)
	Audio.play_sfx("bin")
	_refresh_label()
	changed.emit()
	return n

# 玩家反悔：把箱子里所有货取回背包。返回取回的件数（背包塞不下的留在箱里）。
func take_back_all() -> int:
	var back := 0
	var keep: Array = []
	for e in pending:
		if Inventory.add_item(e["item"], int(e["count"])):
			back += int(e["count"])
		else:
			keep.append(e)
	pending = keep
	if back > 0:
		Audio.play_sfx("ui_click")
		_refresh_label()
		changed.emit()
	return back

func pending_count() -> int:
	var n := 0
	for e in pending:
		n += int(e["count"])
	return n

func pending_total() -> int:
	var t := 0
	for e in pending:
		t += int(e["price"])
	return t

# e29b: 关箱即售 —— 所有关箱路径（售出按钮 / F / Esc / 程序化关面板）都经 bin_ui.close_panel 到这里。
# 哥布林渠道的货立刻原价入账（跟商人直接卖一致, 做买卖也涨一点主角经验）;
# 海外渠道的货上船, 次日清晨 _on_new_day 回款。
func sell_now() -> void:
	if pending.is_empty():
		return
	var gold := 0
	var n := 0
	var sea := 0
	for e in pending:
		if String(e.get("mode", "哥布林")) == "海外":
			sea_hold.append({"gold": int(e["price"]), "due": _day_stamp() + 1})
			sea += int(e["price"])
		else:
			gold += int(e["price"])
			n += int(e["count"])
	pending.clear()
	_refresh_label()
	changed.emit()
	var bits: PackedStringArray = []
	if gold > 0:
		Wallet.add_money(gold)
		Legion.gain_exp(1)
		Quests.complete("sell_first")    # e30w: 卖货整块搬来售卖箱, 开局指引的「第一笔卖货」跟着改这儿触发
		bits.append("售出 %d 件, %d 金到账" % [n, gold])
	if sea > 0:
		bits.append("海外 %d 金次日到账" % sea)
	if not bits.is_empty():
		_hint(" / ".join(bits))

# 结算：把箱子里攒的东西一次性取走（返回明细 + 总价），箱子清空。
# e29b: 正常流程关箱即售（bin_ui.close_panel → sell_now）, 这里只兜底未关箱的残留;
# 「海外贸易」条目上船 —— 次日到账（价已上浮四成）。
# 调用方负责把钱加进 Wallet —— 箱子自己不管钱，免得「加钱」这件事散落两处。
func collect() -> Dictionary:
	var items := []
	var total := 0
	for e in pending:
		if String(e.get("mode", "哥布林")) == "海外":
			sea_hold.append({"gold": int(e["price"]), "due": _day_stamp() + 1})
		else:
			items.append(e)
			total += int(e["price"])
	pending.clear()
	_refresh_label()
	return {"items": items, "total": total}

func sea_pending_total() -> int:
	var t := 0
	for e in sea_hold:
		t += int(e["gold"])
	return t

# ---------------- 头顶提示 ----------------
# 一次性飘字（只在刚投完料/投不进去时冒一下）。
# 起点压低到箱子口上方，往上飘 —— 别跟上面那两层常驻文字打架。
func _hint(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(-58, -22)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", -46.0, 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2)
	tw.tween_callback(l.queue_free)
