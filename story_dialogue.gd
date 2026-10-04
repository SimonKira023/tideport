# story_dialogue.gd —— 剧情对话框（铺满下小半屏 / 暂停时间 / 像素头像+名字）
#
# 用法（任意脚本里）：
#   var dlg := get_tree().get_first_node_in_group("story_dialogue")
#   dlg.play([
#       {"name": "哥布林", "portrait": "goblin", "text": "句子..."},
#       {"name": "主角", "portrait": "player", "text": "回复..."},
#   ], func(): print("说完了"))
#
# 行为：
#   · 对话框占据屏幕下方约 42%（铺满宽度），全屏半透明遮罩挡输入
#   · play() 时 TimeManager.push_ui_pause() 暂停时间，结束 pop
#   · 头像 64x64 像素图放大到 128x128 显示（nearest 保留像素感），旁边标注名字
#   · 打字机逐字显示；按 F/空格/鼠标左键/Esc：没显示完→立刻显示完，显示完→下一句
#   · 最后一句后回调 on_done 并关闭
extends Control

signal opened
signal closed
signal _line_advanced

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const PORTRAIT_DIR := "res://resources/texture/portraits/"
const TYPE_INTERVAL := 0.028        # 打字机每个字的间隔（秒）
const BOX_H_RATIO := 0.42          # 对话框占屏幕高度比例（下小半屏）

var _lines: Array = []
var _idx := 0
var _char_shown := 0.0             # 已显示的字符数（浮点累加）
var _typing := false
var _active := false
var _on_done := Callable()

# 导演模式状态
var _directed := false             # 演出脚本驱动中
var _awaiting := false             # 等玩家按键推进台词
var _cg: Control = null            # CGView 场景层实例

var _mask: ColorRect
var _box: PanelContainer
var _portrait: TextureRect
var _name_label: Label
var _text_label: Label
var _next_hint: Label

func _ready() -> void:
	add_to_group("story_dialogue")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func _build() -> void:
	# 全屏遮罩（挡住下层点击，顺便压暗背景）
	_mask = ColorRect.new()
	_mask.color = Color(0, 0, 0, 0.35)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_mask)

	# 底部对话框：铺满宽度、高约 42%
	_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.06, 0.96)
	style.border_color = Color(0.62, 0.47, 0.28)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_box.add_theme_stylebox_override("panel", style)
	# 用比例锚点铺满宽度、占下方 42%（任意分辨率下都成立）
	_box.anchor_left = 0.0
	_box.anchor_right = 1.0
	_box.anchor_top = 1.0 - BOX_H_RATIO
	_box.anchor_bottom = 1.0
	_box.offset_left = 0
	_box.offset_right = 0
	_box.offset_top = 0
	_box.offset_bottom = 0
	add_child(_box)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	_box.add_child(hbox)

	# 左侧：头像 + 名字
	var portrait_col := VBoxContainer.new()
	portrait_col.add_theme_constant_override("separation", 4)
	portrait_col.custom_minimum_size = Vector2(136, 0)
	hbox.add_child(portrait_col)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", PIXEL_FONT)
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_col.add_child(_name_label)

	var frame := PanelContainer.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0.18, 0.14, 0.10)
	fstyle.border_color = Color(0.72, 0.55, 0.34)
	fstyle.set_border_width_all(2)
	fstyle.set_corner_radius_all(4)
	fstyle.content_margin_left = 3
	fstyle.content_margin_right = 3
	fstyle.content_margin_top = 3
	fstyle.content_margin_bottom = 3
	frame.add_theme_stylebox_override("panel", fstyle)
	portrait_col.add_child(frame)

	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.custom_minimum_size = Vector2(128, 128)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_portrait)

	# 右侧：正文 + 继续提示
	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 6)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_col)

	_text_label = Label.new()
	_text_label.add_theme_font_override("font", PIXEL_FONT)
	_text_label.add_theme_font_size_override("font_size", 17)
	_text_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_col.add_child(_text_label)

	_next_hint = Label.new()
	_next_hint.add_theme_font_override("font", PIXEL_FONT)
	_next_hint.add_theme_font_size_override("font_size", 13)
	_next_hint.add_theme_color_override("font_color", Color(0.8, 0.68, 0.45))
	_next_hint.text = "[F] "
	_next_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text_col.add_child(_next_hint)

# ---------------- 播放 ----------------
func play(lines: Array, on_done: Callable = Callable()) -> void:
	if _active or lines.is_empty():
		return                    # 剧情对话不叠加，空台词直接忽略
	_lines = lines
	_on_done = on_done
	_idx = 0
	_active = true
	TimeManager.push_ui_pause()
	show()
	opened.emit()
	_show_line()

# ---------------- 导演模式 ----------------
# script 行两种：
#   {"fx": "bg", "scene": "beach", "tod": "dawn"}      纯指令，交给 CGView 执行
#   {"name": "娜雅", "portrait": "s1", "text": "..."}   台词（打字机 + 按键推进）
func play_directed(script: Array, on_done: Callable = Callable()) -> void:
	if _active or script.is_empty():
		return
	_lines = script
	_on_done = on_done
	_active = true
	_directed = true
	TimeManager.push_ui_pause()
	show()
	opened.emit()
	# CGView 插到最底层（mask 之前），mask 减淡让场景透出来
	_cg = load("res://cg_view.gd").new()
	add_child(_cg)
	move_child(_cg, 0)
	_mask.color.a = 0.12
	_box.visible = false
	_run_script()

func _run_script() -> void:
	for i in _lines.size():
		var line: Dictionary = _lines[i]
		if line.has("fx") or line.has("cmd"):
			if _cg == null:
				continue
			var w: float = _cg.fx(line)
			if w > 0.0:
				await get_tree().create_timer(w).timeout
		else:
			_idx = i
			_box.visible = true
			_show_line()
			_awaiting = true
			await _line_advanced
			_awaiting = false
			_box.visible = false
	# 收尾：BGM 还原 + 淡出 + 场景复位
	if _cg != null:
		var cw: float = _cg.close_stage()
		await get_tree().create_timer(cw).timeout
		if is_instance_valid(_cg):
			_cg.queue_free()
		_cg = null
	_mask.color.a = 0.35
	_directed = false
	_lines = []
	_close()

func _show_line() -> void:
	var line: Dictionary = _lines[_idx]
	var key: String = str(line.get("portrait", "player"))
	var tex := load(PORTRAIT_DIR + key + ".png")
	_portrait.texture = tex if tex != null else null
	_name_label.text = str(line.get("name", ""))
	_text_label.text = str(line.get("text", ""))
	_char_shown = 0.0
	_typing = true
	_text_label.visible_characters = 0
	_next_hint.visible = false

func _process(delta: float) -> void:
	if not _active or not _typing:
		return
	_char_shown += delta / TYPE_INTERVAL
	var total := _text_label.text.length()
	_text_label.visible_characters = mini(int(_char_shown), total)
	if int(_char_shown) >= total:
		_finish_typing()

func _finish_typing() -> void:
	_typing = false
	_text_label.visible_characters = -1
	_next_hint.visible = true

# ---------------- 输入 ----------------
func _input(event: InputEvent) -> void:
	if not _active:
		return
	var advance: bool = event.is_action_pressed("interact") \
		or event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("ui_cancel") \
		or (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT)
	if not advance:
		return
	get_viewport().set_input_as_handled()
	if _directed:
		if not _awaiting:
			return
		if _typing:
			_char_shown = 999999.0
			_finish_typing()
			return
		_line_advanced.emit()
		return
	if _typing:
		_char_shown = 999999.0     # 直接显示完整句
		_finish_typing()
		return
	_idx += 1
	if _idx < _lines.size():
		Audio.play_sfx("ui_click")
		_show_line()
	else:
		_close()

func _close() -> void:
	_active = false
	hide()
	TimeManager.pop_ui_pause()
	closed.emit()
	if _on_done.is_valid():
		var cb := _on_done
		_on_done = Callable()
		cb.call()

func is_open() -> bool:
	return _active

# ---------------- 剧情 flag（跨存档的一次性剧情标记） ----------------
# 存在 user://story_flags.cfg，用于「哥布林开场白已看过」这类一次性剧情。
const FLAGS_PATH := "user://story_flags.cfg"

static func flag_get(key: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(FLAGS_PATH) != OK:
		return false
	return bool(cf.get_value("flags", key, false))

static func flag_set(key: String) -> void:
	var cf := ConfigFile.new()
	cf.load(FLAGS_PATH)
	cf.set_value("flags", key, true)
	cf.save(FLAGS_PATH)

static func flags_reset() -> void:
	DirAccess.remove_absolute(FLAGS_PATH)   # 新档：一次性剧情（哥布林开场白）重播
