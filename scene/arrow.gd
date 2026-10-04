# scene/arrow.gd —— 弓手射出的箭（直线飞行，撞人/超时消失）
# 碰撞判定由 battle_map 统一做（遍历箭 x 单位），这里只管飞和画。
extends Node2D

var dir := Vector2.RIGHT
var speed := 800.0             # e15h: 几乎离弦即中（原 175 慢得能看清箭飞全程）
var dmg := 4
var from_side := "enemy"       # 打哪边的（反向判定）
var from_kind := ""            # 射手的兵种（命中时算兵种相克, 见 troop.counter_mult）
var _life := 0.4               # 提速后半秒就飞出 320px，早超射程了，别让箭飞出图
var prev := Vector2.ZERO       # 上一帧的位置（battle_map 扫掠碰撞用，防高速穿人）

func _process(delta: float) -> void:
	prev = position
	position += dir * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()

func _draw() -> void:
	rotation = dir.angle()
	draw_line(Vector2(-5, 0), Vector2(3, 0), Color(0.55, 0.40, 0.22), 1.5)
	draw_circle(Vector2(4, 0), 1.2, Color(0.75, 0.78, 0.85))
