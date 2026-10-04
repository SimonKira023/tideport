# weather_icon.gd —— 手绘 16x16 天气小图标（晴/阴/雨/风暴），运行时自画，不依赖图集。
# kind 直接对照 weather.gd 的常量：0 晴 1 阴 2 雨 3 风暴。
# 跟 clock.gd 的表盘一样走 _draw 自绘像素风。
extends Control

const GOLD := Color(1.0, 0.84, 0.35)
const BOLT := Color(1.0, 0.9, 0.3)
const DROP := Color(0.45, 0.62, 0.95)

var kind := 0

func _ready() -> void:
	custom_minimum_size = Vector2(16, 16)

func set_kind(k: int) -> void:
	if k == kind:
		return
	kind = k
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	match kind:
		0:      # 晴：黄太阳 + 8 道短光芒
			draw_circle(c, 3.6, GOLD)
			for i in 8:
				var ang := i / 8.0 * TAU
				var dir := Vector2(cos(ang), sin(ang))
				draw_line(c + dir * 5.2, c + dir * 7.4, GOLD, 1.2)
		1:      # 阴：两朵灰云
			_cloud(Color(0.72, 0.72, 0.76))
		2:      # 雨：云 + 三道斜雨
			_cloud(Color(0.60, 0.63, 0.70))
			for i in 3:
				var x := size.x * (0.28 + 0.22 * i)
				var y := size.y * 0.62
				draw_line(Vector2(x + 1.0, y), Vector2(x - 1.0, y + 4.0), DROP, 1.2)
		3:      # 风暴：乌云 + 闪电
			_cloud(Color(0.38, 0.38, 0.46))
			var bx := size.x * 0.5
			var by := size.y * 0.56
			draw_polyline(PackedVector2Array([
				Vector2(bx + 2.0, by), Vector2(bx - 1.5, by + 3.2),
				Vector2(bx + 0.8, by + 3.6), Vector2(bx - 2.2, by + 7.5),
			]), BOLT, 1.5)

func _cloud(col: Color) -> void:
	var top := size.y * 0.40
	draw_circle(Vector2(size.x * 0.34, top + 0.6), 3.2, col)
	draw_circle(Vector2(size.x * 0.54, top - 1.4), 3.9, col)
	draw_circle(Vector2(size.x * 0.72, top + 0.8), 3.0, col)
	draw_rect(Rect2(size.x * 0.30, top + 1.2, size.x * 0.46, 3.2), col)
