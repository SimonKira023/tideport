extends CanvasLayer
# P4 转场全家桶（前身: C1/d9 圆幕黑场, e89/e90 手绘 iris）。
# 挂 get_tree().root, 比 battle 节点活得久, 演完自毁。
#
# 黑窗契约照旧: 收幕到全遮 -> force_black 补刀全黑 -> 放主 mid + 排队攒下的 mid
#   （画面零突变）-> 黑透一拍 -> 开幕 -> 自毁。转场重入: play 再进来时不叠第二块,
#   mid 入队; 演完发现排队就重演一轮收黑。
#
# P4 新增（作者点单「转场效果多一点、创新一点」）:
#   play(mode, mid, style)  style 七式, 可用 "a->b" 组合（收用 a 开用 b）:
#     circle     圆幕（默认, 兼容老调用）: 手抖圆洞, 圆心钉玩家
#     brush      撕纸: 噪声阈值撕纸边, 从四周向内撕（切大陆/战斗）
#     watercolor 水彩晕染: fbm 软边墨晕（通用兜底/结算）
#     sail       起帆: 帆布鼓风扭曲(径向 fbm 波浪扭屏幕) + 边缘撕黑（出海/回岛）
#     page       翻页: 对角翻页 + 纸背棱高光 + 页前落影（回城镇/回主菜单）
#     fade       纯黑
#     frost      冬霜: fbm 白霜从四角生长（入冬专用, 睡觉黑幕用）
#   micro(kind)  微转场池: 开箱这类小场合用 0.2s 级轻反馈, 不必全屏 0.6s:
#     "gold" 金光带扫过 / "wipe" 冷光带 / "flash" 闪白
#   ❗修复一个 e89 起就埋着的 bug: 老 _unveil 只补 radius, force_black 已被补刀
#     tween 到 1 且从不复位 —— 展开那段其实一直全黑, 观众看到的是黑幕自毁瞬间的
#     硬切。现在开幕时 force_black 并行退场, 圆洞/各式真的会"展开"。
#   ❗圆心若拿不到玩家屏幕位置（自检/无相机）, 退回屏幕中心 —— 效果照旧成立。

const T_CLOSE := 0.52     # 收幕
const T_BACKUP := 0.10    # 黑幕补刀
const T_HOLD := 0.08      # 全黑窗口的黑透一拍
const T_OPEN := 0.55      # 开幕

const COL_IRIS := Color(0.055, 0.045, 0.038)  # 兼容旧引用: circle 的暖墨色

# 转场七式: 名字 -> shader style 编号（_FRAG / _FRAG_PLAIN 里的分支号要对应）
const STYLES := {
	"circle": 0, "brush": 1, "watercolor": 2, "sail": 3,
	"page": 4, "fade": 5, "frost": 6,
}
# 各式自带墨色（水彩/撕纸偏暖墨, 起帆深海蓝, 翻页纸背暖褐, 冬霜近白）
const STYLE_TINTS := {
	"circle": Color(0.055, 0.045, 0.038, 1.0),
	"brush": Color(0.07, 0.055, 0.04, 1.0),
	"watercolor": Color(0.05, 0.05, 0.06, 1.0),
	"sail": Color(0.03, 0.06, 0.09, 1.0),
	"page": Color(0.09, 0.08, 0.07, 1.0),
	"fade": Color(0.02, 0.02, 0.03, 1.0),
	"frost": Color(0.92, 0.95, 1.0, 1.0),
}

var _mat: ShaderMaterial
var _rect: ColorRect
var _pend_mode := "out"
var _pend_style := "circle"     # 收幕用
var _open_style := "circle"     # 开幕用（组合语法 "a->b" 时与收幕不同）
var _micro_kind := ""           # 非空 = 微转场（不走黑窗契约, 不进 iris_wipe 组）
var _mid: Callable = Callable()
var _queue: Array[Callable] = []   # 重入排队的 mid: 只在全黑窗口里放
var _busy := false

# mode: "out"=先收幕后放 mid 再展开; "in"=已在全黑状态直接展开（兼容保留）
# style: 七式之一, 或 "a->b" 组合（收用 a 开用 b, 如 "sail->brush"）
static func play(mode: String, mid: Callable = Callable(), style := "circle") -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# 防重入: 已有一块黑幕在演（比如战败回岛时, 结算的 out 还没演完又触发回岛）
	# 就不叠第二块 —— 新 mid 进它的队, 等全黑窗口再放, 画面不跳。
	for n in tree.root.get_children():
		if n.is_in_group("iris_wipe"):
			n.request(mode, mid, style)
			return
	var w := new()
	w._prepare(style, mode, mid)
	# deferred: 调用方可能正处于 root.add_child 的调用栈里 (busy parent)
	tree.root.add_child.call_deferred(w)

# 微转场池: 0.2s 级轻反馈, 小场合专用（开箱/捡东西）, 与黑幕互不干扰
static func micro(kind := "gold") -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var w := new()
	w._micro_kind = kind
	tree.root.add_child.call_deferred(w)

# 新块: 只记参数, 进树后 _ready 开演（create_tween 得在树里）
func _prepare(style: String, mode: String, mid: Callable) -> void:
	var parts := style.split("->")
	var s1 := parts[0].strip_edges()
	_pend_style = s1 if STYLES.has(s1) else "circle"
	_open_style = _pend_style
	if parts.size() > 1:
		var p2 := parts[1].strip_edges()
		_open_style = p2 if STYLES.has(p2) else _pend_style
	_mid = mid
	_pend_mode = mode

# 老块被二次 play 命中: 在演就排队（等全黑补放）, 没在演直接开新一轮
func request(mode: String, mid: Callable, style := "circle") -> void:
	if _busy:
		if mid.is_valid():
			_queue.append(mid)
		return
	_prepare(style, mode, mid)
	_start(mode)

func _ready() -> void:
	_rect = ColorRect.new()
	_rect.color = Color.WHITE          # 颜色交给 shader, rect 只当画布
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	if _micro_kind != "":
		add_to_group("iris_micro")
		layer = 98                     # 微转场比黑幕矮一层, 别盖结算/黑窗
		# ❗shader code 必须先赋、材质后挂（跟主路径同序）: 反过来试过,
		#   空码 shader 先进树会吃不到重编译, ColorRect 的白底直接糊一整屏。
		_rect.color = Color(1, 1, 1, 0)   # 兜底透明: shader 万一失手也别白屏闪眼
		_mat.shader.code = _FRAG
		_rect.material = _mat
		add_child(_rect)
		_play_micro()
		return
	add_to_group("iris_wipe")
	layer = 100
	_mat.shader.code = _FRAG
	add_child(_rect)
	_rect.material = _mat
	_center_on_player()
	_start(_pend_mode)

# 圆心钉在玩家的屏幕位置（转场从主角身上收拢/展开, 才有"跟着人走"的感觉）
func _center_on_player() -> void:
	var c := Vector2(0.5, 0.5)
	var tree := Engine.get_main_loop() as SceneTree
	var pl: Node2D = null
	if tree != null:
		var grp := tree.get_nodes_in_group("player")
		if not grp.is_empty() and grp[0] is Node2D:
			pl = grp[0]
	if pl != null:
		var cam := pl.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			var vp := _rect.get_viewport_rect().size
			c = ((pl.global_position - cam.get_screen_center_position())
				* cam.zoom + vp * 0.5) / vp
			c = c.clamp(Vector2.ZERO, Vector2.ONE)
	_mat.set_shader_parameter("center", c)

func _set_style(name: String) -> void:
	_mat.set_shader_parameter("style", int(STYLES.get(name, 0)))
	_mat.set_shader_parameter("tint", STYLE_TINTS.get(name, COL_IRIS))
	_mat.set_shader_parameter("seed", randf() * 20.0)

func _start(mode: String) -> void:
	_busy = true
	if mode == "in":
		_open_style = _pend_style
		_set_style(_open_style)
		_mat.set_shader_parameter("progress", 1.0)
		_mat.set_shader_parameter("force_black", 1.0)
		_unveil()
		return
	_close()

# 收幕: progress 0 -> 1（EXPO 加速冲进来）-> force_black 补刀全黑 -> 放 mid
func _close() -> void:
	_set_style(_pend_style)
	_mat.set_shader_parameter("force_black", 0.0)
	_mat.set_shader_parameter("progress", 0.0)
	var tw := create_tween()
	tw.tween_property(_mat, "shader_parameter/progress", 1.0, T_CLOSE) \
		.set_trans(Tween.TRANS_EXPO if _pend_style == "circle" else Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN)
	tw.tween_property(_mat, "shader_parameter/force_black", 1.0, T_BACKUP) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_fire_all)        # 纯黑窗口: 切场景 + 排队的 mid 全在这放
	tw.tween_interval(T_HOLD)           # 黑透一拍, 给 mid 里的拆/建留帧余量
	tw.tween_callback(_unveil)

# 展开: progress 1 -> 0, force_black 并行退场（修复 e89 的"展开其实全黑"bug）。
#       有新攒的 mid 就重演一轮收黑, 不闪亮。
func _unveil() -> void:
	_set_style(_open_style)
	_mat.set_shader_parameter("progress", 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_mat, "shader_parameter/progress", 0.0, T_OPEN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mat, "shader_parameter/force_black", 0.0, 0.12) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_callback(_done)

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
		_close()   # 重演一轮收黑, mid 依然只在全黑窗口放
		return
	remove_from_group("iris_wipe")
	queue_free()

# ---------------- 微转场池 ----------------
func _play_micro() -> void:
	match _micro_kind:
		"flash":
			_rect.color = Color(1.0, 0.99, 0.92, 0.45)
			var tw := create_tween()
			tw.tween_property(_rect, "color:a", 0.0, 0.18) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_callback(queue_free)
		"gold", "wipe":
			_mat.shader.code = _FRAG
			_mat.set_shader_parameter("style", 7)   # band: 斜向光带扫过
			_mat.set_shader_parameter("progress", 0.0)
			_mat.set_shader_parameter("seed", randf() * 20.0)
			_mat.set_shader_parameter("tint",
				Color(1.0, 0.84, 0.42, 0.5) if _micro_kind == "gold"
				else Color(0.9, 0.94, 1.0, 0.4))
			var tw := create_tween()
			tw.tween_property(_mat, "shader_parameter/progress", 1.0, 0.22) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_callback(queue_free)
		_:
			queue_free()

# ---------------- shader: 全屏遮罩, style 决定"怎么遮" ----------------
# progress: 0 = 未遮, 1 = 全遮。guard 让噪声随 progress 渐入, 保证 p=0 时整屏干净。
# force_black: 补刀全黑（收拢完强制全遮, 展开时并行退场）。
# 撕纸/晕染/冬霜共用 fbm 噪声; 起帆/翻页采样屏幕做扭曲与光影。
const _FRAG := "
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int style = 0;
uniform float progress = 0.0;
uniform vec2 center = vec2(0.5);
uniform vec4 tint : source_color = vec4(0.055, 0.045, 0.038, 1.0);
uniform float seed = 0.0;
uniform float force_black = 0.0;
float vhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.7) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), f.x),
		mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return s;
}
void fragment() {
	vec2 pc = (UV - center) * vec2(1.777, 1.0);
	float r = length(pc);
	float n = fbm(UV * 5.0);
	float guard = clamp(progress * 4.0, 0.0, 1.0);
	float cov = 0.0;
	float dim = 1.0;
	float a = 0.0;
	vec3 col = tint.rgb;
	if (style == 0) {
		// circle: 手抖圆洞（圆周两层正弦慢漂, 毛笔手描感）
		float rad = (1.0 - progress) * 1.5;
		float ang = atan(pc.y, pc.x);
		float wob = sin(ang * 7.0 + TIME * 1.3) * 0.6 + sin(ang * 13.0 - TIME * 0.9) * 0.4;
		float d = r / (1.0 + wob * 0.045);
		cov = smoothstep(rad - 0.05, rad + 0.03, d);
	} else if (style == 1) {
		// brush: 撕纸 —— front 从屏外(1.30)收到屏内(-0.65), 噪声撕边, 四周先黑
		float front = 1.30 - progress * 1.95;
		cov = smoothstep(-0.10, 0.10, r + (n - 0.5) * 0.9 * guard - front);
	} else if (style == 2) {
		// watercolor: 墨晕从四周向内心洇开, 宽窗慢晕
		float front = 1.30 - progress * 1.95;
		cov = smoothstep(-0.16, 0.16, r * 0.85 + (n - 0.5) * 0.85 * guard - front);
	} else if (style == 3) {
		// sail: 帆布鼓风（径向 fbm 波浪扭屏幕, 中段最鼓）+ 四周撕黑向心收
		float front = 1.30 - progress * 1.80;
		float edge = smoothstep(-0.08, 0.12, r + (n - 0.5) * 0.6 * guard - front);
		vec2 dir = pc / max(r, 0.0001);
		float bulge = progress * (1.0 - progress) * 4.0;
		float wave = fbm(vec2(r * 4.0 - TIME * 1.6, seed * 3.1)) - 0.5;
		vec3 sc = texture(screen_tex, UV + dir * wave * bulge * 0.11).rgb;
		col = mix(sc, tint.rgb, clamp(edge, 0.0, 1.0));
		cov = 1.0;
	} else if (style == 4) {
		// page: 对角翻页, 纸背棱高光 + 页前落影（2D 假 3D）
		float d = (UV.x * 0.85 + UV.y * 0.55) / 1.4;
		float e = progress * 1.3 - 0.15;
		float back = clamp(smoothstep(0.04, -0.02, d - e), 0.0, 1.0);
		float shadow = exp(-max(d - e, 0.0) * 26.0) * 0.30;
		float lit = exp(-abs(d - e) * 26.0) * step(d, e) * 0.35;
		vec3 sc = texture(screen_tex, UV).rgb * (1.0 - shadow * (1.0 - back));
		col = mix(sc, tint.rgb * (1.0 + lit), back);
		cov = back;
		a = clamp(max(back, force_black) + shadow * (1.0 - back) * 0.8, 0.0, 1.0);
	} else if (style == 5) {
		cov = progress;
	} else if (style == 6) {
		// frost: 白霜从四角生长（软边 fbm, 四周先白）
		float front = 1.30 - progress * 1.95;
		cov = smoothstep(-0.18, 0.14, r * 0.9 + (n - 0.5) * 0.7 * guard - front);
	} else {
		// band: 斜向光带扫过（微转场专用, 不遮画面只提一条亮带）
		float d = (UV.x * 0.85 + UV.y * 0.55) / 1.4;
		float e = progress * 1.5 - 0.25;
		cov = smoothstep(0.30, 0.0, abs(d - e));
		dim = 0.5;
	}
	cov = clamp(cov, 0.0, 1.0);
	if (style != 4) {
		a = max(cov, force_black) * tint.a * dim;
	}
	COLOR = vec4(col, a);
}
"

# 睡觉黑幕用的精简版: 不要屏幕采样（省一整帧 backbuffer copy, 夜里常驻不拖帧）,
# 砍掉 sail/page 两个要采屏的式子, 其余照旧。
const _FRAG_PLAIN := "
shader_type canvas_item;
uniform int style = 0;
uniform float progress = 0.0;
uniform vec2 center = vec2(0.5);
uniform vec4 tint : source_color = vec4(0.055, 0.045, 0.038, 1.0);
uniform float seed = 0.0;
uniform float force_black = 0.0;
float vhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.7) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), f.x),
		mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return s;
}
void fragment() {
	vec2 pc = (UV - center) * vec2(1.777, 1.0);
	float r = length(pc);
	float n = fbm(UV * 5.0);
	float guard = clamp(progress * 4.0, 0.0, 1.0);
	float cov = 0.0;
	float dim = 1.0;
	vec3 col = tint.rgb;
	if (style == 0) {
		float rad = (1.0 - progress) * 1.5;
		float ang = atan(pc.y, pc.x);
		float wob = sin(ang * 7.0 + TIME * 1.3) * 0.6 + sin(ang * 13.0 - TIME * 0.9) * 0.4;
		float d = r / (1.0 + wob * 0.045);
		cov = smoothstep(rad - 0.05, rad + 0.03, d);
	} else if (style == 1) {
		float f = progress * 1.9 - 0.16;
		cov = smoothstep(0.14, -0.06, r + (n - 0.5) * 0.9 * guard - f);
	} else if (style == 2) {
		float f = progress * 2.0 - 0.16;
		cov = smoothstep(0.16, -0.16, r * 0.85 + (n - 0.5) * 0.85 * guard - f);
	} else if (style == 5) {
		cov = progress;
	} else if (style == 6) {
		float f = progress * 2.0 - 0.16;
		cov = smoothstep(0.20, -0.10, r * 0.9 + (n - 0.5) * 0.7 * guard - f);
	} else {
		float d = (UV.x * 0.85 + UV.y * 0.55) / 1.4;
		float e = progress * 1.5 - 0.25;
		cov = smoothstep(0.30, 0.0, abs(d - e));
		dim = 0.5;
	}
	cov = clamp(cov, 0.0, 1.0);
	COLOR = vec4(col, max(cov, force_black) * tint.a * dim);
}
"
