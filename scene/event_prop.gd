extends Node2D
# 演出道具只绘制, 无碰撞/存档/物品收益. 原点仍在脚下.
var kind := "letter"
func _draw() -> void:
	var ink := Color("493e35")
	var paper := Color("e8d5a2")
	match kind:
		"fire":
			draw_line(Vector2(-7, -2), Vector2(7, -6), Color("8c633c"), 3)
			draw_line(Vector2(-7, -6), Vector2(7, -2), Color("8c633c"), 3)
			draw_colored_polygon(PackedVector2Array([Vector2(-5, -6), Vector2(-3, -14), Vector2(0, -11), Vector2(2, -19), Vector2(6, -6)]), Color("df7a34"))
			draw_colored_polygon(PackedVector2Array([Vector2(-2, -6), Vector2(1, -13), Vector2(3, -6)]), Color("f4d578"))
		"bench":
			draw_rect(Rect2(-20, -12, 40, 7), Color("ae804e"))
			draw_rect(Rect2(-17, -5, 3, 5), ink)
			draw_rect(Rect2(14, -5, 3, 5), ink)
			draw_line(Vector2(-17, -10), Vector2(17, -10), Color("d7ad73"), 1)
		"garden":
			draw_rect(Rect2(-20, -4, 40, 6), Color("90734a"))
			for x in [-14, 0, 14]:
				draw_line(Vector2(x, -3), Vector2(x, -10), Color("487344"), 1)
				draw_line(Vector2(x, -6), Vector2(x - 3, -9), Color("6f944f"), 2)
		"ring":
			draw_arc(Vector2(0, -10), 3, 0, TAU, 12, Color("edc76d"), 1)
			draw_rect(Rect2(-1, -15, 2, 2), Color("f5eccc"))
		"seeds", "grain":
			draw_rect(Rect2(-5, -10, 10, 10), Color("a08c5c"))
			draw_line(Vector2(-5, -8), Vector2(5, -8), ink)
			for x in [-2, 1, 3]:
				draw_rect(Rect2(x, -6, 1, 2), Color("e3bc6c"))
		"bowl", "spoon":
			draw_rect(Rect2(-5, -6, 10, 3), Color("b27853"))
			draw_rect(Rect2(-3, -3, 6, 3), ink)
			draw_line(Vector2(1, -4), Vector2(5, -12), Color("ceaa68"), 2)
		"wood", "hairpin":
			draw_rect(Rect2(-8, -5, 16, 4), Color("be9660"))
			draw_line(Vector2(-6, -3), Vector2(6, -3), ink)
		"sword", "cloth":
			draw_line(Vector2(-7, -3), Vector2(6, -14), Color("ccd2c8"), 2)
			draw_line(Vector2(-7, -8), Vector2(-2, -3), ink, 2)
			draw_rect(Rect2(-8, -3, 3, 4), Color("9b5262"))
		"compass":
			draw_circle(Vector2(0, -6), 5, Color("c8a35c"))
			draw_line(Vector2(-2, -3), Vector2(2, -9), Color("933c3c"), 1)
		"rod":
			draw_line(Vector2(-8, 0), Vector2(5, -19), Color("be9660"), 1)
			draw_line(Vector2(5, -19), Vector2(11, -3), paper, 1)
			draw_rect(Rect2(10, -4, 2, 3), Color("c75744"))
		"fish":
			draw_rect(Rect2(-5, -6, 9, 4), Color("8bb6b9"))
			draw_line(Vector2(4, -4), Vector2(7, -7), Color("8bb6b9"), 2)
			draw_rect(Rect2(-4, -5, 1, 1), ink)
		"flag":
			draw_line(Vector2(0, 0), Vector2(0, -28), ink, 2)
			draw_rect(Rect2(1, -27, 14, 9), Color("8b4960"))
		_:
			draw_rect(Rect2(-8, -10, 16, 10), paper)
			for y in [-7, -4]:
				draw_line(Vector2(-5, y), Vector2(4, y), ink, 1)
			if kind == "letter":
				draw_circle(Vector2(5, -3), 2, Color("ab534a"))
