# key_hint.gd —— 走近时浮在半空中的「按键提示」
#
# 以前每个交互点（商人 / 水井 / 售卖箱 / 门 / 床）都是「飘一行字，1.2 秒后消失」，
# 走近了还得等它飘出来，走开之前字就没了。现在换成常驻悬浮：
#   · 走近 -> 从下往上「飞入」（带一点回弹），停在半空
#   · 停着的时候轻轻上下浮动，不消失
#   · 走远 -> 往上「飞出」并淡掉
#
# 外观是**画**出来的（不用 Container 排 Label）：
#   [ F ] 交易        <- 左边一个按键徽章，右边一个两三个字的动作词
# 像素游戏里 Container 的对齐经常差半个像素，自己画才对得齐。
#
# ❗节点原点在提示框的**正中心**（画的时候四边往外扩），所以 base_y 就是「悬浮高度」。
# ❗每帧把 y 取整再赋值：像素字体落在非整数像素上会糊成一团。
#
# e36i: 鼠标左键点这个框 = 按 F。多个「F xxx」框挨在一起时（比如门口又是售货箱又是门），
#   点哪个框就是哪个功能，不用再猜 F 会喂给谁。框自己发 clicked 信号，谁建的框谁接。
extends Node2D

signal clicked

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

const KEY_SIZE := 9          # 按键字母
const WORD_SIZE := 10        # 动作词（比按键稍大一点，一眼先看到动作）
const PAD := Vector2(5, 3)   # 框内边距
const GAP := 5               # 徽章和动作词之间的空隙
const BADGE_PAD := 4

const ENTER_TIME := 0.20
const LEAVE_TIME := 0.16
const FROM_Y := 10.0         # 飞入：从下方 10 像素处冒出来
const OUT_Y := -8.0          # 飞出：往上飘 8 像素同时淡掉
const FLOAT_AMP := 1.6       # 悬浮摆幅（像素）
const FLOAT_SPEED := 2.4

const BG := Color(0.10, 0.07, 0.06, 0.82)
const BORDER := Color(0.72, 0.58, 0.34)
const BADGE_BG := Color(0.95, 0.90, 0.76)
const BADGE_BORDER := Color(0.42, 0.30, 0.18)
const KEY_COLOR := Color(0.20, 0.14, 0.08)
const WORD_COLOR := Color(1, 1, 1)
const OUTLINE := Color(0, 0, 0, 0.85)

var _key := ""
var _word := ""

# e44 建筑模式（搬房子）时 game 会把这个闸门打开：整屏的「F xxx」框都不吃鼠标。
# 不然想搬一座鸡舍/水井、玩家恰好站在它旁边时，点在提示框上反而开出了它的面板，
# 而不是把手底下的房子拾起来。
static var click_locked := false

var _base_y := 0.0
var _shown := false
var _t := 0.0
var _anim_offset := FROM_Y
var _tw: Tween = null

var _badge_w := 16.0
var _word_w := 20.0
var _line_h := 14.0
var _box := Vector2.ZERO

# key = 按键字母（"F"）；word = 动作词（"交易"）；height = 悬浮高度（负数 = 在原点上方）
func setup(key: String, word: String, height: float) -> void:
	name = "KeyHint"
	_key = key
	_word = word
	_base_y = height
	z_index = 3                 # 压在角色和地形之上
	_measure()
	_anim_offset = FROM_Y
	modulate.a = 0.0
	scale = Vector2(0.72, 0.72)
	visible = false
	queue_redraw()

func _measure() -> void:
	var f: Font = PIXEL_FONT
	_badge_w = f.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE).x + BADGE_PAD * 2
	_word_w = f.get_string_size(_word, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_SIZE).x
	_line_h = maxf(f.get_height(KEY_SIZE), f.get_height(WORD_SIZE))
	_box = Vector2(PAD.x * 2 + _badge_w + GAP + _word_w, PAD.y * 2 + _line_h)

func get_text() -> String:
	return "%s %s" % [_key, _word]

# ---------------- 鼠标左键点框 = 按 F ----------------
# 命中判定：鼠标事件是**视口坐标**，框是**节点局部坐标** —— 用
# get_global_transform_with_canvas() 把视口坐标反变换回局部空间再去比 _box，
# 相机的平移和缩放（Ctrl+滚轮）就自动算进去了，不用手写换算。
# ❗只在框真的露着的时候吃这次点击（_shown + 在可见树里都要满足）：看不见的框不该抢鼠标。
# 吃掉的写法跟别处一致（set_input_as_handled），这样同一次左键不会再去挥锄头/摆建筑。
func _unhandled_input(event: InputEvent) -> void:
	if not _shown or not is_visible_in_tree():
		return
	if click_locked:      # e44 建筑模式：别抢鼠标（见 click_locked 的注释）
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not hit_point(mb.position):
		return
	get_viewport().set_input_as_handled()
	clicked.emit()

# 视口坐标的一个点是否落在框里（外扩 2 像素，小框好点一点）。selftest 直接调这个。
func hit_point(view_pos: Vector2) -> bool:
	if _box == Vector2.ZERO:
		return false
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * view_pos
	return Rect2(-_box * 0.5, _box).grow(2.0).has_point(local)

# ---------------- 飞入 / 飞出 ----------------
func show_hint() -> void:
	if _shown:
		return
	_shown = true
	visible = true
	_t = 0.0
	_kill_tween()
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(self, "_anim_offset", 0.0, ENTER_TIME).from(FROM_Y) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "scale", Vector2.ONE, ENTER_TIME).from(Vector2(0.72, 0.72)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "modulate:a", 1.0, ENTER_TIME)

func hide_hint() -> void:
	if not _shown:
		return
	_shown = false
	_kill_tween()
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(self, "_anim_offset", OUT_Y, LEAVE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tw.tween_property(self, "scale", Vector2(0.72, 0.72), LEAVE_TIME)
	_tw.tween_property(self, "modulate:a", 0.0, LEAVE_TIME)
	_tw.chain().tween_callback(func() -> void:
		visible = false)

func _kill_tween() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var bob := 0.0
	if _shown:
		bob = sin(_t * FLOAT_SPEED) * FLOAT_AMP
	position.y = roundf(_base_y + _anim_offset + bob)

# ---------------- 画 ----------------
func _draw() -> void:
	var f: Font = PIXEL_FONT
	var box := Rect2(-_box.x * 0.5, -_box.y * 0.5, _box.x, _box.y)
	draw_rect(box, BG)
	draw_rect(box, BORDER, false, 1.0)

	var badge := Rect2(box.position.x + PAD.x, box.position.y + PAD.y, _badge_w, _line_h)
	draw_rect(badge, BADGE_BG)
	draw_rect(badge, BADGE_BORDER, false, 1.0)

	# 字的基线：框顶 + (框高 - 字高) / 2 + 字体的 ascent
	var key_w := f.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE).x
	var key_pos := Vector2(badge.position.x + (_badge_w - key_w) * 0.5,
		badge.position.y + (_line_h - f.get_height(KEY_SIZE)) * 0.5 + f.get_ascent(KEY_SIZE))
	draw_string(f, key_pos, _key, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_SIZE, KEY_COLOR)

	var word_pos := Vector2(badge.position.x + _badge_w + GAP,
		box.position.y + (box.size.y - f.get_height(WORD_SIZE)) * 0.5 + f.get_ascent(WORD_SIZE))
	draw_string_outline(f, word_pos, _word, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_SIZE, 2, OUTLINE)
	draw_string(f, word_pos, _word, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_SIZE, WORD_COLOR)
