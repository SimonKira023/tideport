# campfire_ui.gd —— 篝火「有客来访」面板（e53 招募改纯任务制）
# 走近篝火按 F 打开：火边坐着的来客按花名册固定（顺序/名字/初始职业），
# 「上前搭话」播剧情对话（recruits.gd 的 DIALOGS）—— 条件达成当场入队，不够就被婉拒。
# 招募不花钱：完成来客的诉求（作物/金币/材料/指引链任务/历练/科技/声望）才是入队条件。
# 伙伴上限 8 人 —— 满员的日子里根本不会出现篝火（见 game.gd _on_campfire_tick）。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const NPC_SCRIPT := preload("res://scene/slave_npc.gd")

var _visible := false
var _money: Label
var _info: Label
var _info2: Label
var _btn: Button
var _flash_label: Label
var _delivered := false   # 这堆火已经谈成一位（卡片切到刚入队那位、按钮停用）
var _talk_hid := false    # 搭话播剧情时面板暂时藏了（播完要亮回来）

# —— 「今晚火边的这个人」信息卡 ——
var _card_title: Label
var _p_name: Label
var _p_troop: Label
var _p_stat: Label
var _p_life: Label
var _p_note: Label
var _portrait: TextureRect
var _portrait_key := ""
var _portrait_tex: Texture2D = null

func _ready() -> void:
	add_to_group("campfire_panel")
	# 必须自己声明占满全屏（父节点是 HUD/CanvasLayer，Control 默认 0 尺寸会挤到左上角）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Wallet.money_changed.connect(func(_m): _refresh())
	Slaves.changed.connect(_refresh)
	Recruits.changed.connect(_refresh)
	_refresh()

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
	st.bg_color = Color(0.16, 0.10, 0.06, 1.0)         # b4: 全不透明, 防背后 UI 文字透出成暗字
	st.border_color = Color(0.85, 0.52, 0.2)          # 火光橙
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

	vbox.add_child(_label("篝火 - 有客来访", 22, Color(1, 0.78, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	vbox.add_child(_label("火光引来了愿意入伙的人", 13, Color(0.85, 0.75, 0.62), HORIZONTAL_ALIGNMENT_CENTER))

	var money := _label("", 14, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(money)
	_money = money

	_build_card(vbox)          # 「这个人是谁」——先看清来客和她的诉求

	# 两行拆成两个 Label（不是一个多行 Label）：UI 预览工具对 Label 内部的换行处理不好，
	# 拆开之后预览跟游戏里长得一样。
	# ❗文案只用 ASCII 标点 —— IPix.ttf 没有全角括号的字形，渲出来是方块（以前这行就是）
	_info = _label("", 14, Color(0.92, 0.88, 0.8))
	vbox.add_child(_info)
	_info2 = _label("", 14, Color(0.92, 0.88, 0.8))
	vbox.add_child(_info2)

	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(0, 36)
	_btn.add_theme_font_override("font", PIXEL_FONT)
	_btn.add_theme_font_size_override("font_size", 14)
	_btn.pressed.connect(_talk)
	vbox.add_child(_btn)

	_flash_label = _label("", 14, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_flash_label)

	var close := Button.new()
	close.text = "关闭 (F / Esc)"
	close.custom_minimum_size = Vector2(0, 32)
	close.add_theme_font_override("font", PIXEL_FONT)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(close_panel)
	vbox.add_child(close)

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# ---------------- 「今晚火边的这个人」信息卡 ----------------
# 招募**之前**就能把他看清楚：小像 + 名字 + 初始职业 + 血量/攻击 + 诉求 + 进哪一队。
# ❗卡片数据来自 Slaves.preview_next()，跟真招进来那份是**同一次读表**
#   （都在 slaves.gd 的 _roll_slave 读 ROSTER），所以不会「看着是弓手，招进来变刀客」。
#   谈成之后（_delivered）卡片改写刚入队那位（slave_at(count-1)，正坐在火边）。
func _build_card(vbox: VBoxContainer) -> void:
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.07, 0.04, 1.0)   # b4: 全不透明
	st.border_color = Color(0.66, 0.38, 0.15)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(card)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 7)
	card.add_child(cv)

	_card_title = _label("今晚火边的这个人", 13, Color(0.95, 0.72, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(_card_title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	cv.add_child(row)

	# 小像：贴图本来就是 32x32 的像素画，放大到 48 必须用最近邻，不然糊成一团
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.06, 0.04, 0.03, 1.0)   # b4: 全不透明
	fs.border_color = Color(0.45, 0.28, 0.13)
	fs.set_border_width_all(2)
	fs.set_corner_radius_all(4)
	fs.content_margin_left = 4
	fs.content_margin_right = 4
	fs.content_margin_top = 4
	fs.content_margin_bottom = 4
	frame.add_theme_stylebox_override("panel", fs)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(frame)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(48, 48)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.add_child(_portrait)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	_p_name = _label("", 18, Color(1, 0.95, 0.85))
	_p_troop = _label("", 13, Color(0.72, 0.88, 1.0))
	_p_stat = _label("", 13, Color(0.92, 0.88, 0.82))
	_p_life = _label("", 13, Color(0.92, 0.88, 0.82))
	for l in [_p_name, _p_troop, _p_stat, _p_life]:
		col.add_child(l)

	_p_note = _label("", 11, Color(0.74, 0.68, 0.60), HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(_p_note)

# 刷新卡片文字。_delivered = 这堆火已经谈成一位（那卡片写火边坐着的那位，不写下一位）
func _refresh_card() -> void:
	if _card_title == null:
		return
	var idx: int = Slaves.count
	var person: Dictionary = Slaves.preview_next()
	if _delivered and Slaves.count > 0:
		idx = Slaves.count - 1                  # 刚谈成那位（正坐在火边）
		person = Slaves.slave_at(idx)
	if person.is_empty():
		_portrait.visible = false
		_p_name.text = ""
		_p_troop.text = ""
		_p_stat.text = ""
		_p_life.text = ""
		_p_note.text = ""
		return
	_portrait.visible = true
	_refresh_portrait(idx)

	var nm := String(person.get("name", "?"))
	var troop := String(person.get("troop", "新兵"))
	var hp := int(person.get("max_hp", Legion.ally_max_hp()))
	var squad := clampi(int(person.get("squad", 1)), 1, 3)

	if _delivered:
		_card_title.text = "火边这位已经是你的人了"
	else:
		_card_title.text = "今晚火边的这个人"
	_p_name.text = nm
	if troop == "新兵":
		_p_troop.text = "新兵 - 先当近战, 背包详情页里选近战/远程/骑兵一条线升级"
	elif troop == "弓手":
		_p_troop.text = "弓手 - 远程, 隔着一段距离放箭 (脆一点, 别让他贴脸)"
	elif troop == "骑兵":
		_p_troop.text = "骑兵 - 骑马冲锋, 撞进人堆里最快"
	elif troop == "剑士":
		_p_troop.text = "剑士 - 老练的近战, 新兵熬了半辈子熬出来的"
	else:
		_p_troop.text = "刀客 - 近战, 冲到敌人面前砍"
	_p_stat.text = "血量 %d    攻击 %d" % [hp, Legion.ally_atk() + Slaves.class_atk(troop)]
	_p_life.text = "编队 第 %d 队    夜里能派 %d 格活" % [squad, Slaves.cells_per_slave()]
	if _delivered:
		_p_note.text = "天亮他就来农场干活"
	else:
		# 候选人的诉求就是入队条件（任务栏同步挂着「有客来访」）
		var c := Recruits.candidate()
		_p_note.text = "" if c.is_empty() else "他的诉求: %s" % String(c["req"])

# 小像：走 slave_npc 的 model_for / build_frames —— 跟白天在农场跑的那个伙伴同脸同色
# e29c: 个人配色（发色/服装）已烘进贴图层，不再需要 tint modulate
func _refresh_portrait(idx: int) -> void:
	if _portrait == null:
		return
	var model := NPC_SCRIPT.model_for(idx)
	var key := "%s|%d" % [model, idx]
	if key != _portrait_key:
		_portrait_key = key
		_portrait_tex = _load_idle_texture(model, idx)
	_portrait.texture = _portrait_tex

# 借伙伴的贴图拼法取「正面站立第一帧」。造不出来就返回 null（面板少张小像而已，不崩）
func _load_idle_texture(model: String, idx: int) -> Texture2D:
	var frames: SpriteFrames = NPC_SCRIPT.build_frames(model, idx)
	if frames == null:
		return null
	return frames.get_frame_texture(&"idle_down", 0)

# 当前这堆火（篝火在 "campfire" 组里，一次只会有一堆；找不到就按「没火」处理）
func _current_fire() -> Node:
	return get_tree().get_first_node_in_group("campfire")

func _refresh() -> void:
	var c := Recruits.candidate()
	if _money != null:
		_money.text = "口袋里的金币: %d" % Wallet.money
	if _info != null:
		_info.text = "已有 %d / %d 名伙伴 - 每晚可派 %d 格活" % [
			Slaves.count, Slaves.CAP, Slaves.budget()]
	if _info2 != null:
		if c.is_empty():
			_info2.text = "8 位伙伴都已入伙, 火堆只为取暖了"
		elif _delivered:
			_info2.text = "诉求已完成, 天亮他就上工"
		else:
			_info2.text = "诉求: %s (进度 %s) - 这轮停留还剩 %d 天" % [
				String(c["req"]), Recruits.progress_text(), Recruits.window_left()]
	if _btn != null:
		if _delivered:
			_btn.text = "已入伙, 明早一起来干活"
			_btn.disabled = true
			_btn.modulate = Color(0.75, 0.72, 0.7)
		elif c.is_empty():
			_btn.text = "火边没有人"
			_btn.disabled = true
			_btn.modulate = Color(0.75, 0.72, 0.7)
		else:
			_btn.text = "上前搭话"
			_btn.disabled = false
			_btn.modulate = Color(1, 1, 1)
	_refresh_card()

# ---------------- 上前搭话（剧情对话 -> 判定 -> 入队/婉拒） ----------------
# intro 播完看条件: 达成 -> ok 段播完当场 deliver; 不够 -> wait 段婉拒。
# story_dialogue 是全局单例（play 不叠加），所以全程串联回调、一环扣一环。
func _talk() -> void:
	var c := Recruits.candidate()
	if c.is_empty() or _delivered:
		return
	var sd: Node = get_tree().get_first_node_in_group("story_dialogue")
	var intro := Recruits.talk_lines("intro")
	if sd == null or intro.is_empty():
		_after_intro(c)               # 没有对话框时直接判定（保险路径）
		return
	sd.play(intro, func(): _after_intro(c))

# 剧情要上场了, 面板先让路 —— 大面板杵在屏幕正中会把台词挡得严严实实。
# 只 hide() 视觉, _visible 不动（逻辑上还开着, closed 信号不发）。
func _panel_hide_for_talk() -> void:
	if _visible and is_visible():
		_talk_hid = true
		hide()

# 剧情链走到头, 把面板亮回来（可选补一条提示）
func _panel_show_after_talk(msg := "") -> void:
	if _talk_hid:
		_talk_hid = false
		if _visible:
			show()
	if msg != "":
		_flash(msg)

func _after_intro(c: Dictionary) -> void:
	if not Recruits.visitor():    # 对话期间窗口关了（过夜才可能，兜底）
		_talk_hid = false
		return
	var sd: Node = get_tree().get_first_node_in_group("story_dialogue")
	if not Recruits.met(c["need"]):
		var wait := Recruits.talk_lines("wait")
		if sd != null and not wait.is_empty():
			sd.play(wait, func(): _panel_show_after_talk("条件还没够 (%s)" % Recruits.progress_text()))
		else:
			_panel_show_after_talk("条件还没够 (%s)" % Recruits.progress_text())
		return
	var ok := Recruits.talk_lines("ok")
	# 有专属入伙长剧本就播导演模式演出（cg_view 场景 + 台词）; 没配则走旧单行台词
	var join := Recruits.join_script()
	if sd != null and not join.is_empty():
		sd.play_directed(join, func(): _finish_talk(c))
	elif sd != null and not ok.is_empty():
		sd.play(ok, func(): _finish_talk(c))
	else:
		_finish_talk(c)

func _finish_talk(c: Dictionary) -> void:
	_panel_show_after_talk()                 # 剧情（含入伙演出）播完, 面板亮回来
	if not Recruits.deliver():
		_flash("条件还没够 (%s)" % Recruits.progress_text())
		return
	Audio.play_sfx("buy")
	var fire := _current_fire()
	if fire != null and fire.has_method("seat_someone"):
		fire.seat_someone()
	_delivered = true
	_flash("聊定了! %s 入伙" % String(c["name"]))
	_refresh()

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text
	_flash_label.modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_flash_label, "modulate:a", 0.0, 0.6)

# ---------------- 开合 ----------------
func _input(event: InputEvent) -> void:
	if not _visible or not is_visible():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close_panel()
		get_viewport().set_input_as_handled()

func open_panel() -> void:
	if _visible:
		return
	_visible = true
	show()
	Audio.play_sfx("ui_open")
	_flash_label.text = ""
	# 「这堆火谈成没有」以当前这堆火为准重新判定 ——
	# 新火（新客）来了必须把上一位的「已入伙」状态清掉, 不然卡片永远显示旧人、按钮点不动
	var fire := _current_fire()
	_delivered = fire != null and bool(fire.get("recruited"))
	_refresh()
	opened.emit()

func close_panel() -> void:
	if not _visible:
		return
	_visible = false
	hide()
	Audio.play_sfx("ui_close")
	closed.emit()

func is_open() -> bool:
	return _visible
