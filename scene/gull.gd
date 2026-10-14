extends Node2D
# e89 叙事粒子（TLN 计划 E）：海鸥。白天绕着锚点（码头）慢慢盘旋的一两只,
#   程序化画的 V 形双翅, 扇翅正弦 —— 夜里（灯亮时分）隐去, 跟路灯同一套色调钟。
#   挂 Game 下（不套容器, 坑 9），z 抬在角色之上、粒子层之下。
#   ❗纯装饰: 无碰撞、不进存档、被拆了就散（is_instance_valid 兜着）。

var _center := Vector2.ZERO   # 盘旋锚点（世界坐标）
var _dir := 1.0               # 绕向（+1 顺 / -1 逆, 两只错开）
var _t := 0.0
var _phase := 0.0             # 出发相位, 两只海鸥别重叠

const RX := 95.0              # 椭圆长轴
const RY := 42.0              # 椭圆短轴
const ALT := -130.0           # 飞行高度（往上悬）
const SCALE := 1.6

static func make(center: Vector2, dir: float, phase: float) -> Node2D:
	var g := new()
	g._center = center
	g._dir = dir
	g._phase = phase
	g._t = phase * 10.0
	g.z_index = 55
	g.scale = Vector2(SCALE, SCALE)
	return g

func _process(delta: float) -> void:
	# 白天飞, 夜里歇（跟灯同一刻切换 —— 天黑点灯时海鸥也归巢）
	var day := not preload("res://scene/light_util.gd").glow_hour_now()
	visible = day
	if not day:
		return
	_t += delta
	var a := _t * 0.55 * _dir + _phase
	var bob := 6.0 * sin(_t * 1.3 + _phase)          # 高低轻起伏
	position = _center + Vector2(cos(a) * RX, sin(a) * RY + bob + ALT)
	queue_redraw()

func _draw() -> void:
	var flap := sin(_t * 9.0 + _phase)               # 扇翅
	var c := Color(0.94, 0.95, 0.98, 0.88)
	var edge := Color(0.72, 0.76, 0.84, 0.7)
	# V 形双翅: 翅尖随扇翅上下摆（俯视角看就是一只掠过的海鸥）
	draw_line(Vector2.ZERO, Vector2(-9.0, -4.5 * flap - 1.5), c, 2.2)
	draw_line(Vector2.ZERO, Vector2(9.0, -4.5 * flap - 1.5), c, 2.2)
	draw_circle(Vector2.ZERO, 1.6, edge)
