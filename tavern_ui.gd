# tavern_ui.gd —— 大陆酒馆「招募消息板」（e53 招募改纯任务制）
#
# 酒馆墙上钉着一块消息板：贴着下一位候选人的消息 —— 名字 / 初始职业 / 诉求 / 进度。
# 只看不用钱：入队的唯一路子是回岛上完成他的诉求（篝火边搭话，见 recruits.gd），
# 这块板子给出门在外的玩家一个盼头 —— 知道下一位是谁、差什么、什么时候在岛上。
# ❗花名册（Slaves.ROSTER）定人定序：板上的「下一位」跟岛上篝火边坐的必然是同一个人。
extends Control

signal opened
signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const PANEL_W := 400

var _visible := false
var _guard := 0.0
var _root: VBoxContainer = null
var _flash_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()
	Wallet.money_changed.connect(func(_m): if _visible: _rebuild())
	Slaves.changed.connect(func(): if _visible: _rebuild())

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

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
	# ❗底版必须用 PanelContainer：ColorRect 的尺寸只看 custom_minimum_size，
	#   里面的子节点撑不大它，高度会算成 0 —— 底版直接消失、字飘在草地上。
	card.custom_minimum_size = Vector2(PANEL_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.13, 0.10, 0.09, 0.97)
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

func _rebuild() -> void:
	if _root == null:
		return
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()

	_root.add_child(_label("酒馆 - 招募消息板", 19, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER))
	_flash_label = _label("", 12, Color(0.75, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_root.add_child(_flash_label)

	_root.add_child(_label("现在有 %d 个伙伴 (最多 %d 个)" % [Slaves.count, Slaves.CAP],
		13, Color(0.86, 0.82, 0.74), HORIZONTAL_ALIGNMENT_CENTER))

	var c := Recruits.candidate()
	if c.is_empty():
		_root.add_child(_label("伙伴都招齐了, 板上没了新消息.", 13,
			Color(0.7, 0.86, 0.95), HORIZONTAL_ALIGNMENT_CENTER))
		_root.add_child(_label("F / Esc 关闭", 11,
			Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
		return

	# 板上钉着的消息：下一位是谁、要什么、现在人在不在岛上
	_root.add_child(_label("新贴出的一张:", 13, Color(1, 0.93, 0.76)))
	_root.add_child(_label("  %s   %s   夜里能派 %d 格活" % [
		str(c.get("name", "?")), str(c.get("troop", "新兵")), Slaves.cells_per_slave()],
		14, Color(0.92, 0.90, 0.84), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("诉求: %s" % str(c.get("req", "")), 13,
		Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("进度: %s" % Recruits.progress_text(), 13,
		Color(0.92, 0.90, 0.84), HORIZONTAL_ALIGNMENT_CENTER))
	if Recruits.visitor():
		_root.add_child(_label("此刻就坐在岛上篝火边 (停留还剩 %d 天)" % Recruits.window_left(),
			13, Color(0.75, 0.9, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		_root.add_child(_label("眼下不在岛上, 过些日子会再来.", 13,
			Color(1.0, 0.78, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(_label("入队不用钱: 回岛上完成他的诉求,\n傍晚在篝火边跟他搭话就行.", 11,
		Color(0.62, 0.60, 0.54)))
	_root.add_child(_label("F / Esc 关闭", 11,
		Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

func _flash(text: String) -> void:
	if _flash_label == null:
		return
	_flash_label.text = text

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
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
