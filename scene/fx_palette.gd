extends Object
# scene/fx_palette.gd —— P5 特效包: 飘字色板 + 打击三连工具箱
#
# 飘字色板（唯一真相源）: 以前各处 _float_text 各配各的色, 现在统一从这拿 ——
#   GAIN 金(收获/+钱/击倒) / FAVOR 粉(好感) / EXP 蓝(经验)
#   HURT 红(受伤/扣钱) / GUARD 绿(守护/回复) / TEXT 暖白(中性提示)
# 用法: const FxPalette := preload("res://scene/fx_palette.gd")
#       FxPalette.GAIN / FxPalette.hit_stop() / FxPalette.speed_lines(_fx, tp)
#
# 打击三连（击杀/重击瞬间叠一起, 观感立涨）:
#   hit_stop()         时间 0.05 倍僵直 0.06s（打击感之王; 已在慢放时不抢）
#   flash(tree,...)    全屏短闪（从 cutscene_base 的闪白思路抽出, 不依赖过场层）
#   speed_lines(p, at) 辐射速度线 0.15s（程序化画, 画完自毁）

# ---------------- 色板 ----------------
const GAIN := Color(1.0, 0.85, 0.35)      # 金: 收获 / +钱 / 击倒
const FAVOR := Color(1.0, 0.62, 0.78)     # 粉: 好感
const EXP := Color(0.55, 0.78, 1.0)       # 蓝: 经验
const HURT := Color(1.0, 0.58, 0.46)      # 红: 受伤 / 扣钱
const GUARD := Color(0.55, 0.90, 0.75)    # 绿: 守护 / 回复
const TEXT := Color(1.0, 0.95, 0.85)      # 暖白: 中性提示

# ---------------- hit-stop ----------------
static func hit_stop(scale := 0.05, sec := 0.06) -> void:
	if Engine.time_scale < 1.0:
		return   # 已在慢放（战役指挥 0.1 倍等）, 别把别人的慢放抢成 1.0
	Engine.time_scale = scale
	var t := Engine.get_main_loop() as SceneTree
	if t == null:
		return
	# ignore_time_scale 的计时器负责恢复: 慢放不影响恢复时机, 打击节奏稳定
	t.create_timer(sec, false, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)

# ---------------- 全屏短闪 ----------------
static func flash(tree: SceneTree, col := Color(1, 1, 1), a := 0.28, sec := 0.14) -> void:
	if tree == null:
		return
	var w := ColorRect.new()
	w.color = Color(col.r, col.g, col.b, a)
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := CanvasLayer.new()
	cl.layer = 97                      # 黑幕(100)/微转场(98)之下, 画面之上
	cl.add_child(w)
	tree.root.add_child.call_deferred(cl)
	var tw := tree.create_tween()
	tw.tween_property(w, "color:a", 0.0, maxf(0.05, sec))
	tw.tween_callback(cl.queue_free)

# ---------------- 辐射速度线 ----------------
static func speed_lines(parent: CanvasItem, at: Vector2,
		col := Color(1.0, 0.98, 0.9, 0.85)) -> void:
	if parent == null:
		return
	var lines := SpeedLines.new(at, col)
	parent.add_child(lines)

class SpeedLines extends Control:
	var at := Vector2.ZERO
	var line_col := Color(1.0, 0.98, 0.9, 0.85)

	func _init(c: Vector2, col: Color) -> void:
		at = c
		line_col = col

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		pivot_offset = at
		scale = Vector2(0.55, 0.55)    # 从中心炸开的一瞬: 先小后大
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "scale", Vector2(1.18, 1.18), 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 0.0, 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(queue_free)

	func _draw() -> void:
		# 14 条辐射细线, 长短交错（三档节奏）, 中段留空不糊住受击点
		for i in 14:
			var ang := TAU * float(i) / 14.0 + 0.19
			var dir := Vector2(cos(ang), sin(ang))
			var r0 := 30.0 + 8.0 * (i % 3)
			var r1 := r0 + 34.0 + 26.0 * (i % 4)
			draw_line(at + dir * r0, at + dir * r1, line_col, 2.0)
