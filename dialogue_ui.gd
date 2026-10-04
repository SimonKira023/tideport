# dialogue_ui.gd —— 跟伙伴对话的弹窗
#
# 由 slave_npc.gd 走近按 F 时打开（对话窗口是「寻路途中伙伴在场」时用）；
# 团队界面里的伙伴详情弹窗是另一个 UI（不跟这个冲突）。
#
# 行为（赠送合并改版）：
#   · 打开：显示伙伴名字 + 好感 + 按钮排（聊天 / 赠送 / 再见了）
#   · 点「聊天」→ 弹视觉小说对话框（dialog_box, 2~3 段台词翻页）——
#     聊天纯陪伴不加好感, 好感全靠赠送（随时都能聊）
#   · 「赠送」→ 打开选物弹窗（gift_picker）, 从背包挑一份作物/食物/材料送出去 ——
#     消耗一份 + 加好感（送中 Ta 的爱好好感 x2, 生日当天增量再 x2）
#   · 「心里话」/「求婚」→ 婚恋入口（marriage.gd）：篝火夜话逐段解锁，
#     五段全看完 + 好感满 + 有银戒 → 求婚 → 婚礼，演出全走 story_dialogue 导演模式
#   · 关掉时 unpause
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const NPC_SCRIPT := preload("res://scene/slave_npc.gd")   # 性别真相源（MODEL_MALE）
const MARRIAGE_SCRIPT := preload("res://scripts_marriage.gd")   # 婚恋剧本工厂（static）
const RING := preload("res://item/ring.tres")                   # 求婚信物
const GIFT_PICKER := preload("res://gift_picker.gd")            # 赠送选物弹窗

# 台词池（e24 起写, e30t 按**性别**拆成两套 —— 男伙伴说话短促、爱逞强爱吹牛,
# 女伙伴话多一点、爱念叨也爱分享小发现; 同一档好感下读起来是两个人）
# ❗性别真相源 = slave_npc.gd 的 MODEL_MALE（idx % 4 == 0 是男, 其余是女）,
#   跟名字池 NAMES_M/NAMES_F、头像分组是同一张表, 三者永远一致。
# 每套按好感分四档（0~2 冷淡 / 3~5 客气 / 6~8 熟络 / 9~10 亲昵）, 每档 3 组, 每组 2~4 段翻页。
# ❗标点只用 ASCII, IPix.ttf 没有全角字形
const LINES_M := [
	# 0~2 冷淡（话少, 埋头干活）
	[
		["......(头也没抬, 手上的活没停)", "锄头比嘴好使.", "要站这儿聊, 就帮我把那排苗扶正."],
		["唔? 哦, 是你啊.", "别踩! 我刚翻的土!", "话说完我就得赶活了."],
		["有事?", "没事就帮我盯会儿那窝鸡.", "上回一转身, 三只全窜树上去了."],
	],
	# 3~5 客气（开始有来有往, 会汇报进度）
	[
		["今天露水可真厚!", "正好, 麦苗最馋这一口.", "你摸摸叶子, 凉得像井水."],
		["报告! 东边三垄全锄完了!", "西边那块......嗯, 明天再收拾它."],
		["跟你讲, 鸡其实认人.", "我蹲了三天, 那只花的才肯从我手里啄食.", "头一个蛋给你留着."],
	],
	# 6~8 熟络（自来熟, 爱开玩笑）
	[
		["嘿! 来得正好!", "我刚跟大伙打了赌, 这茬麦子能长到我腰.", "输了就得替所有人喂一个月鸡......麦子你争点气!"],
		["哎你听我说, 昨晚有条鱼自己蹦上岸了!", "就在码头边, 扑通一声!", "我扑过去--扑了个空, 摔一身泥.", "哈哈别笑! 真有鱼!"],
		["中午炊事棚烙了麦饼.", "我藏了两块, 分你一块.", "藏好点, 别让人闻出来, 那帮家伙鼻子比狗灵."],
	],
	# 9~10 亲昵（掏心窝子 + 约定）
	[
		["你来啦!", "(大步迎上来) 今天先去哪块地?", "你的田我闭着眼都认得, 比自家门口还熟."],
		["跟你说个事.", "夜里睡不着, 我就趴在窗口数你的田.", "数着数着, 想到这里有我一份......就睡着了."],
		["等秋收完, 咱们去海边烤鱼!", "我捡柴, 你生火, 再拉个人负责捕鱼.", "说好了啊, 谁赖谁是狗."],
	],
]
const LINES_F := [
	# 0~2 冷淡（客气但疏远, 手上也忙着）
	[
		["......(低头择菜, 没看你)", "手上还有活呢.", "要聊, 就坐下来帮我择两把."],
		["呀, 是你.", "别踩那儿! 我刚撒的种!", "......好啦好啦, 我还得去浇水."],
		["怎么啦?", "没事的话, 帮我看一眼那窝鸡好不好.", "上回一转身, 三只全跑树上去啦."],
	],
	# 3~5 客气（爱分享小发现）
	[
		["今天露水可真厚!", "正好, 麦苗最馋这一口.", "你摸摸叶子, 凉丝丝的, 像井水一样!"],
		["东边三垄都锄完啦!", "西边那块......嗯, 明天再慢慢弄."],
		["跟你说哦, 鸡其实认人的.", "我蹲了三天, 那只花的终于肯从我手里啄食了.", "头一个蛋肯定留给你."],
	],
	# 6~8 熟络（话密, 爱念叨也爱讲趣事）
	[
		["嘿! 来得正好!", "我刚跟大伙打了赌, 这茬麦子能长到我腰.", "输了要替所有人喂一个月鸡......麦子你可争点气呀!"],
		["哎, 你听我说, 昨晚有条鱼自己蹦上岸了!", "就在码头边, 扑通一声!", "我扑过去--扑了个空, 摔一身泥.", "哈哈哈别笑! 真的有鱼!"],
		["中午炊事棚烙了麦饼.", "我藏了两块, 分你一块.", "藏好哦, 尤其别让布恩闻到, 他鼻子比狗灵."],
	],
	# 9~10 亲昵（掏心窝子 + 拉钩）
	[
		["你来啦!", "(小跑过来) 今天先去哪块地呀?", "你的田我闭着眼都认得, 比自家门口还熟."],
		["跟你说个秘密.", "夜里睡不着, 我就趴在窗口数你的田.", "数着数着, 想到这里有我一份......就睡着了."],
		["等秋收完, 咱们去海边烤鱼吧!", "我捡柴, 你生火, 再拉个伙伴负责捕鱼.", "说好了啊, 拉钩!"],
	],
]

var _slave_index := -1        # 当前对话的伙伴 index（-1 = 未指定）
var _box: PanelContainer
var _name_label: Label
var _aff_label: Label
var _line_label: Label
var _chat_btn: Button
var _give_btn: Button       # 赠送（喂食 + 送礼合并）
var _heart_btn: Button       # 心里话（可结婚对象 + 好感到门槛才显示）
var _propose_btn: Button     # 求婚（五段全看 + 好感满 + 有银戒才显示）
var _close_btn: Button
var _visible := false
var _dialog: Control = null   # e18: 聊天对话框（多段翻页, 关掉才算聊）

func _ready() -> void:
	add_to_group("dialogue")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_dialog = preload("res://dialog_box.gd").new()
	_dialog.name = "ChatDialog"
	add_child(_dialog)
	_dialog.closed.connect(_finish_chat)
	Slaves.changed.connect(func() -> void:
		if _visible:
			_refresh())

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_box = PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.14, 0.11, 0.09, 0.97)
	box_style.border_color = Color(0.62, 0.47, 0.28)
	box_style.set_border_width_all(3)
	box_style.set_corner_radius_all(8)
	box_style.content_margin_left = 22
	box_style.content_margin_right = 22
	box_style.content_margin_top = 14
	box_style.content_margin_bottom = 16
	_box.add_theme_stylebox_override("panel", box_style)
	_box.custom_minimum_size = Vector2(360, 0)
	center.add_child(_box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_box.add_child(vbox)

	_name_label = _label("", 18, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_name_label)
	_aff_label = _label("", 12, Color(0.95, 0.66, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_aff_label)
	vbox.add_child(_label("---", 11, Color(0.72, 0.64, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	_line_label = _label("", 14, Color(0.95, 0.93, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(320, 0)
	vbox.add_child(_line_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)

	_chat_btn = Button.new()
	_chat_btn.text = "聊天"
	_chat_btn.custom_minimum_size = Vector2(100, 30)
	_chat_btn.add_theme_font_override("font", PIXEL_FONT)
	_chat_btn.add_theme_font_size_override("font_size", 13)
	_chat_btn.pressed.connect(_on_chat_pressed)
	row.add_child(_chat_btn)

	_give_btn = Button.new()
	_give_btn.text = "赠送"
	_give_btn.custom_minimum_size = Vector2(100, 30)
	_give_btn.add_theme_font_override("font", PIXEL_FONT)
	_give_btn.add_theme_font_size_override("font_size", 13)
	_give_btn.pressed.connect(_on_give_pressed)
	row.add_child(_give_btn)

	_close_btn = Button.new()
	_close_btn.text = "再见了"
	_close_btn.custom_minimum_size = Vector2(100, 30)
	_close_btn.add_theme_font_override("font", PIXEL_FONT)
	_close_btn.add_theme_font_size_override("font_size", 13)
	_close_btn.pressed.connect(close_panel)
	row.add_child(_close_btn)

	# 第二排：婚恋按钮（只在条件达成时显示）
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	_heart_btn = Button.new()
	_heart_btn.text = "心里话"
	_heart_btn.custom_minimum_size = Vector2(120, 30)
	_heart_btn.add_theme_font_override("font", PIXEL_FONT)
	_heart_btn.add_theme_font_size_override("font_size", 13)
	_heart_btn.pressed.connect(_on_heart_pressed)
	_heart_btn.visible = false
	row2.add_child(_heart_btn)

	_propose_btn = Button.new()
	_propose_btn.text = "求婚"
	_propose_btn.custom_minimum_size = Vector2(120, 30)
	_propose_btn.add_theme_font_override("font", PIXEL_FONT)
	_propose_btn.add_theme_font_size_override("font_size", 13)
	_propose_btn.pressed.connect(_on_propose_pressed)
	_propose_btn.visible = false
	row2.add_child(_propose_btn)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# 按好感切段, 取一组台词（2~4 段; 当天固定: 用 day + index 当种子）
# e30t: 台词池按性别分（MODEL_MALE[idx % 4], 跟名字池/头像同一张表）
func _pick_group() -> Array:
	if _slave_index < 0:
		return ["..."]
	var s: Dictionary = Slaves.slave_at(_slave_index)
	if s.is_empty():
		return ["..."]
	var aff: int = int(s["affection"])
	# 按好感切段
	var tier := 0
	if aff >= 3 and aff <= 5:
		tier = 1
	elif aff >= 6 and aff <= 8:
		tier = 2
	elif aff >= 9:
		tier = 3
	var male: bool = bool(NPC_SCRIPT.MODEL_MALE[_slave_index % NPC_SCRIPT.MODEL_MALE.size()])
	var pool: Array = (LINES_M if male else LINES_F)[tier]
	var seed := TimeManager.day * 13 + _slave_index * 17 + aff
	return pool[seed % pool.size()]

func _refresh() -> void:
	if _slave_index < 0:
		return
	var s: Dictionary = Slaves.slave_at(_slave_index)
	if s.is_empty():
		close_panel()
		return
	_name_label.text = "和 %s 聊聊" % s["name"]
	_aff_label.text = "好感 %s/%d" % [
		_heart_str(int(s["affection"])), Slaves.AFFECTION_MAX]
	# ❗IPix.ttf 没有全角引号「」—— 文案里别用
	_line_label.text = "(点 聊天 跟 %s 说说话; 点 赠送 挑份背包里的东西送 Ta)" % s["name"]
	# 聊天按钮一直能点（不加好感, 纯看台词）
	# 赠送按钮：今天送过就灰掉
	_give_btn.disabled = bool(s.get("gift_today", false))
	_give_btn.modulate = Color(0.7, 0.7, 0.7) if bool(s.get("gift_today", false)) else Color(1, 1, 1)
	# 婚恋按钮：心里话（可结婚对象且好感到下一段门槛）/ 求婚（五段全看 + 好感满 + 有银戒）
	if _slave_index >= 0 and _slave_index < Slaves.ROSTER.size():
		var id := str(Slaves.ROSTER[_slave_index]["id"])
		var aff := int(s["affection"])
		_heart_btn.visible = Marriage.can_heart_talk(id, aff)
		_propose_btn.visible = Marriage.can_propose(id, aff, Inventory.count_item(RING) >= 1)

# 点聊天弹对话框 —— 2~3 段台词翻页（聊天不加好感, 随时都能聊）
func _on_chat_pressed() -> void:
	if _slave_index < 0:
		return
	var s: Dictionary = Slaves.slave_at(_slave_index)
	var portrait: Texture2D = load("res://resources/texture/portraits/slave_%02d.png" % _slave_index)
	if portrait == null:
		portrait = load("res://resources/texture/portraits/player.png")
	_dialog.open_multi(portrait, s["name"], _pick_group())

# 对话框关掉的那一下：聊天不加好感, 只刷新界面
func _finish_chat() -> void:
	_refresh()

func _heart_str(n: int) -> String:
	var s := ""
	for i in n:
		s += "*"      # ❗IPix.ttf 没有 ♥ 的字形（会显示成方块），用 * 代替
	return s

# 赠送：打开选物弹窗（gift_picker）, 挑一份背包里的作物/食物/材料送出去
func _on_give_pressed() -> void:
	if _slave_index < 0:
		return
	var gp: Control = GIFT_PICKER.new()
	add_child(gp)
	gp.picked.connect(_on_gift_picked)
	gp.open_for(_slave_index)

# 选物弹窗点了某件物品 → 落账（give 记好感 + 扣背包一份, 跟弹窗约定配对）
func _on_gift_picked(item: ItemData) -> void:
	if _slave_index < 0 or item == null:
		return
	var sname: String = Slaves.slave_at(_slave_index)["name"]
	var gain: int = Slaves.give(_slave_index, item)
	if gain <= 0:
		_flash_box("今天已经给 %s 送过东西了" % sname)
		return
	Inventory.remove_item(item, 1)
	Audio.play_sfx("buy")
	var bonus := ""
	if item.display_name == Slaves.like_of(_slave_index):
		bonus = "\n(Ta 最喜欢这个!)"
	_flash_box("送给 %s 1 份 %s\n好感 +%d%s" % [sname, item.display_name, gain, bonus])
	_refresh()

# ---------------- 婚恋（marriage.gd） ----------------
# 心里话：播当前段篝火夜话（导演模式），播完推进段数
func _on_heart_pressed() -> void:
	if _slave_index < 0:
		return
	var idx := _slave_index
	var id := str(Slaves.ROSTER[idx]["id"])
	if not Marriage.can_heart_talk(id, int(Slaves.slave_at(idx)["affection"])):
		return
	var dlg: Node = get_tree().get_first_node_in_group("story_dialogue")
	if dlg == null:
		return
	close_panel()
	dlg.play_directed(MARRIAGE_SCRIPT.heart_script(idx, Marriage.stage(id)), func() -> void:
		Marriage.do_heart_talk(id))

# 求婚：五段心里话全看完 + 好感满 + 有银戒 → 求婚演出 → 紧接婚礼演出
func _on_propose_pressed() -> void:
	if _slave_index < 0:
		return
	var idx := _slave_index
	var id := str(Slaves.ROSTER[idx]["id"])
	if not Marriage.can_propose(id, int(Slaves.slave_at(idx)["affection"]),
			Inventory.count_item(RING) >= 1):
		return
	var dlg: Node = get_tree().get_first_node_in_group("story_dialogue")
	if dlg == null:
		return
	close_panel()
	Inventory.remove_item(RING, 1)
	dlg.play_directed(MARRIAGE_SCRIPT.propose_script(idx), func() -> void:
		Marriage.marry(id, TimeManager.day)
		var sd: Node = get_tree().get_first_node_in_group("story_dialogue")
		if sd != null:
			sd.play_directed(MARRIAGE_SCRIPT.wedding_script(idx)))

func _flash_box(text: String) -> void:
	var old := _line_label.text
	_line_label.text = text
	_line_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_line_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		_line_label.text = old
		_line_label.modulate.a = 1.0)

# ---------------- 开合 ----------------
func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close_panel()
		get_viewport().set_input_as_handled()

func open_panel(slave_index: int) -> void:
	if _visible:
		if _slave_index == slave_index:
			return
		close_panel()
	_slave_index = slave_index
	_visible = true
	show()
	_refresh()
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	_slave_index = -1
	hide()
	Audio.play_sfx("ui_close")
	closed.emit()

func is_open() -> bool:
	return _visible