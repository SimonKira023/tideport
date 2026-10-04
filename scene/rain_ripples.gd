# scene/rain_ripples.gd —— e33 画面美化：雨天地面涟漪。
# 雨点砸在地上「啵」地扩散一圈小环，风暴时更密。挂在 game 根下，
# _draw 画环、_process 推进寿命 + 在视野内随机补新环。
# ❗z_index 由 game 那边设成 -1：垫在角色/建筑（0 层）下面、地形（-2 以下）上面，
#   雨环永远贴着地面，不会被 y_sort 卷进遮挡。
extends Node2D

const MAX_RIPPLES := 40      # 同屏最多多少个环（风暴也就这个量，多了糊）
const RING_TIME := 0.55      # 一个环从出现到消失的秒数
const RING_R0 := 1.5         # 起始半径
const RING_R1 := 7.0         # 消失前扩到多大

var _ripples: Array = []     # [{p: Vector2, t: float}]
var _acc := 0.0              # 生成速率的累积器（按秒攒出小数个环）

func _process(delta: float) -> void:
	var raining := Weather.is_rain() or Weather.is_storm()
	# 1) 推进现有环的寿命
	var keep: Array = []
	for r in _ripples:
		var t: float = float(r["t"]) + delta
		if t < RING_TIME:
			keep.append({"p": r["p"], "t": t})
	_ripples = keep
	# 2) 雨中按密度补新环（风暴点密一倍），雨停了就不再补
	if raining:
		var rate := 7.0
		if Weather.is_storm():
			rate = 14.0
		_acc += delta * rate
		while _acc >= 1.0 and _ripples.size() < MAX_RIPPLES:
			_acc -= 1.0
			_ripples.append({"p": _rand_point(), "t": 0.0})
	else:
		_acc = 0.0
	queue_redraw()

# 在相机视野内随机取一点（按 zoom 反推世界坐标范围）
func _rand_point() -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Vector2.ZERO
	var half := get_viewport_rect().size / cam.zoom * 0.5
	var c := cam.get_screen_center_position()
	return c + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))

func _draw() -> void:
	for r in _ripples:
		var t: float = float(r["t"]) / RING_TIME
		var rad: float = RING_R0 + (RING_R1 - RING_R0) * t
		var a: float = 0.45 * (1.0 - t)
		draw_arc(r["p"], rad, 0.0, TAU, 12, Color(1, 1, 1, a), 1.0)
