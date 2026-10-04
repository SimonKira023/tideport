extends CanvasLayer
# C1 转场黑幕层: 挂 get_tree().root, 比 battle 节点活得久, 演完自毁
# g4 重做: 旧版 iris shader 圆幕羽化边遮不死画面; 换纯黑 ColorRect 只动 alpha,
#          并把「放 mid」焊死在全黑窗口里。
# i5 重做: 华丽化 —— 起手暖光闪 + 墨褐/黄铜斜切条带 stagger 冲屏盖满,
#          黑幕只做兜底补刀; 展开时条带反向抽走 + 收尾暖光闪。黑窗契约照旧:
#   光闪 -> 条带唰唰唰盖满 -> 黑幕补刀到 a=1.0 -> 放主 mid + 排队攒下的 mid
#          （画面零突变）-> 黑透一拍 -> 黑幕退到条带底下（不可见）
#          -> 条带反向抽走露新场景 -> 收尾光闪 -> 自毁
#   转场重入: play 再进来时不叠第二块, mid 入队; 演完才发现有排队的
#             就重演一轮收黑（i5 前: 裸放 mid, 半透下切场景, 突变隐患）。
#   mode "in": 已在全黑状态展开（调用方目前只用 "out", 保留兼容）

const T_FLASH := 0.05     # 起手/收尾红闪停驻
const T_BANDS := 0.34     # 条带冲屏总时长（含 stagger）
const T_BACKUP := 0.12    # 黑幕兜底补刀
const T_UNCOVER := 0.15   # 黑幕退场（条带盖满着, 用户看不见）
const T_OUT := 0.42       # 条带抽走总时长（含 stagger）
const T_HOLD := 0.08      # 全黑窗口的黑透一拍

const STAGGER_IN := 0.04
const STAGGER_OUT := 0.035
const BANDS := 7
const COL_BAND_A := Color(0.13, 0.09, 0.055)    # 深墨褐: 夜色里的木纹/牛皮
const COL_BAND_B := Color(0.62, 0.47, 0.24)     # 黄铜金: 火把掠过的暖光
const COL_FLASH := Color(1.0, 0.86, 0.55)       # 暖光闪: 烛火/烽燧一瞬

var _rect: ColorRect
var _flash: ColorRect
var _bands: Array[Polygon2D] = []
var _span := 1000.0        # 单条条带横跨长度（含斜切余量）, 冲屏起点/抽走终点
var _pend_mode := "out"
var _mid: Callable = Callable()
var _queue: Array[Callable] = []   # 重入排队的 mid: 只在全黑窗口里放
var _busy := false

static func play(mode: String, mid: Callable = Callable()) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# 防重入: 已有一块黑幕在演（比如战败回岛时, 结算的 out 还没演完又触发回岛）
	# 就不叠第二块 —— 新 mid 进它的队, 等全黑窗口再放, 画面不跳。
	for n in tree.root.get_children():
		if n.is_in_group("iris_wipe"):
			n.request(mode, mid)
			return
	var w := new()
	w._prepare(mode, mid)
	# deferred: 调用方可能正处于 root.add_child 的调用栈里 (busy parent)
	tree.root.add_child.call_deferred(w)

# 新块: 只记参数, 进树后 _ready 开演（create_tween 得在树里）
func _prepare(mode: String, mid: Callable) -> void:
	_mid = mid
	_pend_mode = mode

# 老块被二次 play 命中: 在演就排队（等全黑补放）, 没在演直接开新一轮
func request(mode: String, mid: Callable) -> void:
	if _busy:
		if mid.is_valid():
			_queue.append(mid)
		return
	_mid = mid
	_start(mode)

func _ready() -> void:
	add_to_group("iris_wipe")
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_make_bands()
	_flash = ColorRect.new()
	_flash.color = COL_FLASH
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)
	_start(_pend_mode)

# i5: 墨褐/黄铜交替的斜切条带（平行四边形）—— 斜边扫过屏幕才有掠光那一下。
#     树序: 黑幕 < 条带 < 光闪, 光闪负责起手/收尾那一下冲击帧。
func _make_bands() -> void:
	var vs := _rect.get_viewport_rect().size
	var bh := vs.y / float(BANDS)
	var skew := bh * 0.55
	_span = vs.x + skew + 40.0
	for i in BANDS:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(_span, 0),
			Vector2(_span - skew, bh + skew), Vector2(-skew, bh + skew),
		])
		poly.color = COL_BAND_B if i % 2 == 0 else COL_BAND_A
		poly.position = Vector2(0, i * bh)
		add_child(poly)
		_bands.append(poly)

func _start(mode: String) -> void:
	_busy = true
	if mode == "in":
		_rect.modulate.a = 1.0          # "in" 本义是从黑幕展开亮出
		for b in _bands:
			b.position.x = 0.0          # 条带已盖满, 黑幕退下去用户看不见
		_unveil()
		return
	_cover()

# 收场: 暖光闪一拍 -> 条带 stagger 急冲盖满（EXPO 冲进去急停）-> 黑幕补刀全黑
func _cover() -> void:
	_rect.modulate.a = 0.0              # 新块从全透明起, 挂上去的瞬间画面不变
	for b in _bands:
		b.position.x = _span            # 条带先停屏幕右外
	var tw := create_tween()
	tw.tween_callback(_flash_on)        # 起手暖光闪直接盖场（火把掠过的快闪帧）
	tw.tween_interval(T_FLASH)
	tw.tween_callback(_bands_in)
	tw.tween_interval(T_BANDS)
	tw.tween_property(_rect, "modulate:a", 1.0, T_BACKUP) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_fire_all)        # 纯黑窗口: 切场景 + 排队的 mid 全在这放
	tw.tween_interval(T_HOLD)           # 黑透一拍, 给 mid 里的拆/建留帧余量
	tw.tween_callback(_unveil)          # h4: 渐亮接在收黑链尾, 不与收黑并行抢 alpha

# 展开: 黑幕先退到条带底下（条带盖满着, 不可见）-> 条带倒序急抽走露新场景
#       -> 收尾暖光闪 -> 自毁。有新攒的 mid 就重演一轮收黑, 不闪亮。
func _unveil() -> void:
	var tw := create_tween()
	tw.tween_property(_rect, "modulate:a", 0.0, T_UNCOVER)
	tw.tween_callback(_bands_out)
	tw.tween_interval(T_OUT)
	tw.tween_callback(_flash_on)
	tw.tween_interval(T_FLASH + 0.08)
	tw.tween_callback(_done)

func _flash_on() -> void:
	_flash.modulate.a = 0.8
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "modulate:a", 0.0, T_FLASH + 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _bands_in() -> void:
	var step := T_BANDS - (BANDS - 1) * STAGGER_IN
	for i in _bands.size():
		var b := _bands[i]
		b.position.x = _span
		var tw := b.create_tween()
		tw.tween_interval(i * STAGGER_IN)
		tw.tween_property(b, "position:x", 0.0, step) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _bands_out() -> void:
	var n := _bands.size()
	var step := T_OUT - (n - 1) * STAGGER_OUT
	for i in n:
		var b := _bands[i]
		var tw := b.create_tween()
		tw.tween_interval((n - 1 - i) * STAGGER_OUT)   # 倒序抽走: 下条先溜
		tw.tween_property(b, "position:x", -_span, step) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# 纯黑窗口放 mid: 一个个同步放光, 期间画面保持全黑, 零突变
func _fire_all() -> void:
	if _mid.is_valid():
		_mid.call()
	while not _queue.is_empty():
		var cb: Callable = _queue.pop_front()
		if cb.is_valid():
			cb.call()

func _done() -> void:
	if not _queue.is_empty():
		_cover()   # i5: 带条带重演一轮收黑, mid 依然只在全黑窗口放（不再裸放）
		return
	remove_from_group("iris_wipe")
	queue_free()
