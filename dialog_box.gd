# dialog_box.gd —— e16g/e18: 聊天对话框（视觉小说式, 支持多段台词）
#
# 「点聊天会跳对话框, 对话框出来才算聊了天」: 聊天按钮只负责弹这个框
# （大像素头像 + 名字 + 台词），玩家**把所有段翻完关掉**的那一下, 由调用方在
# closed 信号里真正落账（+好感 / 记今天聊过）。台词由调用方先取好（不落账
# 的预览组, 见 Nations.town_lines / captain_lines）。
#
# e18: 台词升级成 2~3 段 —— open_multi(segs, portrait, who), 点「继续」翻段,
# 最后一段才可关闭; closed 在关框时发出。单段也走这个入口(数组里就一个元素)。
#
# 关闭方式: 最后一段时点任意处 / F(interact) / Esc。guard 0.25s 防点开按钮的
# 同一下鼠标/按键立刻把它关掉。
#
# P0 手感三件套（PLAN_CUTE_STYLE.md）:
#   1. 打字机逐字 —— 台词按 ~30 字/秒逐个显示, 标点后停一小拍; 打字中点一下
#      = 立刻显示全文, 再点才翻段/关框（两段式, 星露谷同款）。
#   2. blip 音 —— 每漏出 2 个字响一声极短 blip, 音高带抖动; 每个角色有
#      自己的基准音高（按名字哈希）, 听起来是"不同的人在说话"。
#   3. 木框弹出 pop —— 对话条从 62% 缩放弹到 100%（TRANS_BACK 回弹）,
#      遮罩同步淡入; 打开不再是"啪一下糊脸上"。
extends Control

signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const FRAME := preload("res://wood_frame.gd")   # e53c: 程序化木框（对话框 + 头像框）

const CHARS_PER_SEC := 30.0   # 打字机速度（中文字/秒）
const PUNCT_PAUSE := 0.09     # 标点后多停一拍（秒）—— 逗号句号处"说话人喘口气"
const PUNCT := ".,!?;:、,。!?;:"

var _segs: Array = []          # 台词段数组（2~3 段）
var _seg_i := 0                # 当前第几段
var _built: Control = null
var _line_label: Label = null
var _hint_label: Label = null
var _bar: Control = null       # P0: 对话条本体（弹出动画用）
var _guard := 0.0
# --- P3 头像差分 ---
const MOOD_PORTRAIT := preload("res://scene/mood_portrait.gd")
var _pic: TextureRect = null   # 头像块（翻段时按差分换贴图）
var _pic_key := ""             # 头像的 key（"player"/"slave_03"…, 空 = 调用方给的裸纹理）
var _moods: Array = []         # 每段的表情（空 = 全普通）; 短于段数时最后一段沿用末项
# --- P0 打字机状态 ---
var _typing := false           # 当前段正在逐字显示?
var _reveal := 0.0             # 已漏出的字符数（浮点累计, 整数部分给 visible_characters）
var _pause := 0.0              # 标点停顿倒计时
var _blip_tick := 0            # 漏字计数（每 2 个字响一声 blip）
var _voice_pitch := 1.0        # 当前说话人的基准音高（按名字哈希）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta
	# P0 打字机: 逐字漏出 + 标点停一拍 + 每 2 字一声 blip
	if _typing and _line_label != null:
		if _pause > 0.0:
			_pause -= delta
			return
		_reveal += delta * CHARS_PER_SEC
		var shown := int(_reveal)
		var txt := _line_label.text
		var previous: int = _line_label.visible_characters
		_line_label.visible_characters = shown
		# 刚漏出的这个字如果是标点, 多停一拍（说话人喘口气）
		if shown > previous and shown > 0 and shown < txt.length():
			if PUNCT.contains(txt[shown - 1]):
				_pause = PUNCT_PAUSE
		# blip: 每 2 个字一声, 音高 = 角色基准 + 随机抖动
		if shown >= _blip_tick + 2:
			_blip_tick = shown
			Audio.play_sfx("blip", -13.0, randf_range(_voice_pitch - 0.05, _voice_pitch + 0.08))
		if shown >= txt.length():
			_finish_typing()

func is_open() -> bool:
	return visible

func is_last_seg() -> bool:
	return _seg_i >= _segs.size() - 1

# portrait: 对面的像素头像; who: 名字行; segs: 台词段数组(每段一句);
# moods: 每段的表情差分（P3）, 如 ["normal","happy","shy"] —— 空 = 全普通;
# pic_key: 头像的差分 key（P3, open_key 用）—— 空 = 裸纹理, 不做逐段换装
func open_multi(portrait: Texture2D, who: String, segs: Array, moods: Array = [], pic_key := "") -> void:
	var sentences: Array = []
	for seg in segs:
		sentences.append({"text": str(seg)})
	_segs = []
	for page: Dictionary in preload("res://story_dialogue.gd")._paragraphs(sentences):
		_segs.append(page["text"])
	if _segs.is_empty():
		_segs = ["......"]
	_seg_i = 0
	_moods = moods
	_pic_key = pic_key
	# P0: 每个角色一个固定基准音高（名字哈希 -> 0.92~1.22）, blip 听起来是同一个人
	_voice_pitch = 0.92 + float(abs(who.hash()) % 1000) / 1000.0 * 0.30
	if _built != null:
		_built.queue_free()
	_built = _build(portrait, who)
	add_child(_built)
	visible = true
	_guard = 0.25
	_show_seg(0)
	Audio.play_sfx("ui_open", -6.0)
	# P0 pop: 对话条从 62% 弹到 100%（回弹曲线）, 遮罩同步淡入 —— 打开有"落桌"感
	if _bar != null:
		_bar.pivot_offset = Vector2(330.0, 196.0)   # 条子尺寸 660x196, 以底边中心为轴
		_bar.scale = Vector2(0.62, 0.62)
		var tw := create_tween()
		tw.tween_property(_bar, "scale", Vector2.ONE, 0.30) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_built.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_property(_built, "modulate:a", 1.0, 0.14)

# P3: 按头像 key 打开（走像素 Q 版 + 表情差分管线）。
# key 形如 "player" / "slave_03"; 立绘文件缺失时退回 player, 再缺退裸 load。
func open_key(key: String, who: String, segs: Array, moods: Array = []) -> void:
	var tex: Texture2D = MOOD_PORTRAIT.tex_of(key)
	if tex == null and key != "player":
		key = "player"
		tex = MOOD_PORTRAIT.tex_of(key)
	if tex == null:
		tex = MOOD_PORTRAIT.portrait_texture("player")
	open_multi(tex, who, segs, moods, key if tex != null else "")

func close() -> void:
	if not visible:
		return
	visible = false
	_typing = false
	if _built != null:
		_built.queue_free()
		_built = null
	_bar = null
	_line_label = null
	_hint_label = null
	Audio.play_sfx("ui_close", -8.0)
	closed.emit()

# 显示第 i 段: 重置打字机, 从第一个字开始漏; 头像按该段表情换差分
func _show_seg(i: int) -> void:
	_line_label.text = String(_segs[i])
	_line_label.visible_characters = 0
	_reveal = 0.0
	_pause = 0.0
	_blip_tick = 0
	_typing = true
	_hint_label.text = "[F / 空格 / 左键] 显示全文"
	# P3: 该段的表情差分（moods 短于段数时沿用末项）
	if _pic != null and _pic_key != "" and not _moods.is_empty():
		var mood: String = _moods[mini(i, _moods.size() - 1)]
		var tex: Texture2D = MOOD_PORTRAIT.tex_of(_pic_key, mood)
		if tex != null:
			_pic.texture = tex

# 打字结束: 全文显示, 提示行浮现（带呼吸闪烁）
func _finish_typing() -> void:
	_typing = false
	_line_label.visible_characters = -1
	_hint_label.text = ("继续 (%d/%d)" % [_seg_i + 1, _segs.size()]) if _segs.size() > 1 else "点击任意处继续"

# 点继续: 打字中 = 先补全; 已是最后一段 = 关框(这才算聊完)
func _advance_or_close() -> void:
	if _typing:
		_finish_typing()
		return
	if not is_last_seg():
		_seg_i += 1
		_show_seg(_seg_i)
		Audio.play_sfx("ui_click", -10.0)
	else:
		close()

func _build(portrait: Texture2D, who: String) -> Control:
	# 半透明遮罩: 点一下就翻段/关框（关的那一下才算聊了天）
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.35)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _guard <= 0.0:
				_advance_or_close())

	# 底部对话框条: 左头像 + 右名字/台词
	# e53c: 改成程序化木框（木板 + 金斜面 + 四角包边）, 条子不上衬纸, 面积留给文字
	var bar: Control = FRAME.new()
	bar.mat_color = Color(0, 0, 0, 0)
	bar.inner_color = Color(0.10, 0.07, 0.05, 0.82)   # 半透明深底（游戏画面透一点, e109 回退 material）
	bar.inner_top_color = Color(0.14, 0.10, 0.07)
	bar.set_frame_size(11, 5, 10, 18, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = bar   # P0: open_multi 的弹出动画要动它

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	# e53c: 头像也套一圈同款木框 + 暖衬纸（参考图里就是这样: 金线 + 衬纸 + 四角包边）
	var frame: Control = FRAME.new()
	frame.mat_color = Color("c9a566")
	frame.inner_color = Color(0.13, 0.10, 0.08, 0.82)   # 半透明深底（头像框, e109 回退 material）
	frame.set_frame_size(6, 3, 7, 12, 4)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # e30m: 不随行高拉伸, 头像贴住框底
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(88, 88)   # 44px Q 版 x2 整数倍, 像素颗粒均匀
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = portrait
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic = pic   # P3: 翻段换差分用
	frame.add_child(pic)
	row.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var name_l := Label.new()
	name_l.text = who
	name_l.add_theme_font_override("font", PIXEL_FONT)
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", Color(1, 0.93, 0.76))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)

	_line_label = Label.new()
	_line_label.text = String(_segs[0])
	_line_label.add_theme_font_override("font", PIXEL_FONT)
	_line_label.add_theme_font_size_override("font_size", 14)
	_line_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95))
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(430, 0)
	_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_line_label)

	_hint_label = Label.new()
	_hint_label.text = "继续 (1/%d)" % _segs.size() if _segs.size() > 1 else "点击任意处继续"
	_hint_label.add_theme_font_override("font", PIXEL_FONT)
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", Color(0.66, 0.62, 0.55))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hint_label)

	# 对话框条贴屏幕底部居中
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.offset_left = -330
	bar.offset_right = 330
	bar.offset_top = -212
	bar.offset_bottom = -16
	veil.add_child(bar)
	return veil

func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _guard <= 0.0:
			_advance_or_close()
