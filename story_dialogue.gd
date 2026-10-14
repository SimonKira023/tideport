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
const FRAME := preload("res://wood_frame.gd")   # e53c: 程序化木框（聊天对话框同款）
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
var _skip_event := false
var _choices: VBoxContainer
var _choice_index := -1
signal _choice_picked

var _mask: ColorRect
var _box: MarginContainer
var _portrait: TextureRect
var _name_label: Label
var _text_label: Label
var _next_hint: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# e53c: 换成程序化木框（跟聊天对话框同款）—— 框厚兼任内容边距
	_box = FRAME.new()
	_box.mat_color = Color(0, 0, 0, 0)
	_box.inner_color = Color(0.09, 0.07, 0.06, 0.82)   # 半透明深底（游戏画面透一点, e109 回退 material）
	_box.inner_top_color = Color(0.13, 0.10, 0.07)
	_box.set_frame_size(11, 5, 10, 18, 12)
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
	portrait_col.custom_minimum_size = Vector2(172, 0)   # e53c: 木框头像(128+框厚40)放得下
	hbox.add_child(portrait_col)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", PIXEL_FONT)
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_col.add_child(_name_label)

	# e53c: 头像框也换同款木框 + 暖衬纸
	var frame: Control = FRAME.new()
	frame.mat_color = Color("c9a566")
	frame.inner_color = Color(0.13, 0.10, 0.08, 0.82)   # 半透明深底（头像框, e109 回退 material）
	frame.set_frame_size(6, 3, 7, 12, 4)
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
	_choices = VBoxContainer.new()
	text_col.add_child(_choices)
	_choices.hide()

# ---------------- 播放 ----------------
func play(lines: Array, on_done: Callable = Callable()) -> void:
	if _active or lines.is_empty():
		return                    # 剧情对话不叠加，空台词直接忽略
	_lines = _paragraphs(lines)
	_on_done = on_done
	_idx = 0
	_active = true
	_directed = false
	_awaiting = false
	_box.show()  # 导演模式收尾会隐藏正文, 普通对话必须重新打开.
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
	_lines = _paragraphs(script)
	_on_done = on_done
	_active = true
	_directed = true
	_skip_event = false
	_box.anchor_top = 0.68
	_set_event_layout(true)
	TimeManager.push_ui_pause()
	show()
	opened.emit()
	# e100: 实机舞台（live_view, 星露谷式就地演出）—— 与 cg_view 同接口,
	# 剧本一行不用改; 旧画布布景 cg_view.gd 留着没删（可回滚）。
	_cg = load("res://live_view.gd").new()
	add_child(_cg)
	move_child(_cg, 0)
	_cg.prepare(_lines)
	_mask.color.a = 0.0
	_box.visible = false
	_run_script()

func _run_script() -> void:
	await _run_entries(_lines)
	# 收尾：BGM 还原 + 淡出 + 场景复位
	if _cg != null:
		var cw: float = _cg.close_stage()
		await get_tree().create_timer(cw).timeout
		if is_instance_valid(_cg):
			_cg.queue_free()
		_cg = null
	_mask.color.a = 0.35
	_box.anchor_top = 1.0 - BOX_H_RATIO
	_set_event_layout(false)
	_choices.hide()
	_directed = false
	_lines = []
	_close()

# 演出正文留出更多世界空间, 头像和边框同时缩小, 防止最小高度把底部提示挤出屏幕.
func _set_event_layout(event_layout: bool) -> void:
	_portrait.custom_minimum_size = Vector2(96, 96) if event_layout else Vector2(128, 128)
	var frame: Control = _portrait.get_parent()
	var column: Control = frame.get_parent()
	column.custom_minimum_size.x = 132 if event_layout else 172
	if event_layout:
		frame.set_frame_size(4, 2, 5, 8, 3)
		_box.set_frame_size(7, 3, 0, 12, 8)
	else:
		frame.set_frame_size(6, 3, 7, 12, 4)
		_box.set_frame_size(11, 5, 10, 18, 12)

func _run_entries(entries: Array, nested := false) -> void:
	for i in entries.size():
		if _skip_event:
			break
		var line: Dictionary = entries[i]
		if line.has("fx") or line.has("cmd"):
			if _cg != null:
				await _cg.execute(line, -1 if nested else i)
		elif line.has("choice"):
			await _ask_choice(line)
		else:
			_box.visible = true
			_display_line(line)
			_awaiting = true
			await _line_advanced
			_awaiting = false
			_box.visible = false

func _ask_choice(line: Dictionary) -> void:
	_box.show()
	_display_line({"name": "我", "portrait": "player", "text": line.get("choice", "")})
	_finish_typing()
	_choice_index = -1
	for child in _choices.get_children():
		child.queue_free()
	var options: Array = line.get("options", [])
	for i in options.size():
		var button := Button.new()
		button.text = str(options[i]["text"])
		button.add_theme_font_override("font", PIXEL_FONT)
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", Color("493a2c"))
		button.add_theme_color_override("font_focus_color", Color("493a2c"))
		button.add_theme_color_override("font_hover_color", Color("493a2c"))
		button.add_theme_color_override("font_pressed_color", Color("493a2c"))
		_choices.add_child(button)
		button.pressed.connect(_pick_choice.bind(i))
	_choices.show()
	_next_hint.text = "[上下 / 回车] 选择   [Esc] 跳过演出"
	if not options.is_empty():
		_choices.get_child(_choices.get_child_count() - options.size()).grab_focus()
	await _choice_picked
	_choices.hide()
	_box.hide()
	if not _skip_event and _choice_index >= 0:
		await _run_entries(options[_choice_index].get("lines", []), true)

func _pick_choice(index: int) -> void:
	_choice_index = index
	_choice_picked.emit()

func _show_line() -> void:
	var line: Dictionary = _lines[_idx]
	_display_line(line)

func _display_line(line: Dictionary) -> void:
	var key: String = str(line.get("portrait", "player"))
	var tex := preload("res://scene/mood_portrait.gd").portrait_texture(key)
	_portrait.texture = tex if tex != null else null
	_name_label.text = str(line.get("name", ""))
	_text_label.text = str(line.get("text", ""))
	_char_shown = 0.0
	_typing = true
	_text_label.visible_characters = 0
	_next_hint.text = "[F / 空格 / 左键] 显示全文" + ("   [Esc] 跳过演出" if _directed else "")
	_next_hint.visible = true

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
	_next_hint.text = "[F / 空格 / 左键] 继续" + ("   [Esc] 跳过演出" if _directed else "")

# ---------------- 输入 ----------------
func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.echo:
		return
	if _directed and event.is_action_pressed("ui_cancel"):
		_skip_event = true
		if _cg != null:
			_cg.request_skip()
		if _awaiting:
			_line_advanced.emit()
		if _choices.visible:
			_choice_picked.emit()
		get_viewport().set_input_as_handled()
		return
	if _directed and _choices.visible:
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
	if not _active:
		return
	_active = false
	_typing = false
	hide()
	TimeManager.pop_ui_pause()
	# 先取走旧回调, 信号或回调开启下一段时不会被旧收尾覆盖.
	var cb := _on_done
	_on_done = Callable()
	closed.emit()
	if cb.is_valid():
		cb.call()

# 同一说话人连续的句子组成一段, 换人或演出指令才分开.
# 每页控制长度, 避免小窗口下长段正文挤出框外.
static func _paragraphs(lines: Array) -> Array:
	var pages: Array = []
	for entry: Dictionary in lines:
		var line: Dictionary = entry.duplicate(true)
		if not pages.is_empty() and line.has("text") and not line.has("fx") and not line.has("cmd"):
			var previous: Dictionary = pages.back()
			var identity: Dictionary = line.duplicate()
			var previous_identity: Dictionary = previous.duplicate()
			identity.erase("text")
			previous_identity.erase("text")
			var joined: String = str(previous.get("text", "")) + " " + str(line["text"])
			if previous.has("text") and identity == previous_identity and joined.length() <= 120:
				previous["text"] = joined
				continue
		pages.append(line)
	return pages

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
