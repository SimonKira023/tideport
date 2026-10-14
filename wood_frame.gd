# wood_frame.gd —— e53c: 木质画框（对话框 / 头像框通用, 全程序化像素风）
#
# 照参考图临摹的层次（由外向内）:
#   木板底 + 木理(竖板缝 / 横板缝 / 外缘明暗 / 四角接头)
#   -> 金色斜面(上左提亮 / 下右压暗)
#   -> 内衬纸(可选, 暖羊皮纸色 + 斑点)
#   -> 深色内容底(上浅下深, 保证白字读得出)
#   -> 四角金包边(L 形角撑)
#
# 用法: 直接 new() 往里塞子节点 —— 它是个 MarginContainer, 内容会自动落在框内
# （margin 已按框厚让好位）, 不用手动算内边距。
# ❗别给它加 StyleBoxFlat —— 这道框是 draw 出来的, 不是贴图。
extends MarginContainer

# —— 厚度（像素, 整数, 保证边缘不糊）——
var wood_t := 11        # 外层木框
var gold_t := 5         # 金色斜面
var mat_t := 10         # 内衬纸（mat_color 透明时不画）
var bracket := 16       # 四角包边边长
var pad := 10           # 内容离框的呼吸位
var seam_step := 42     # 木板缝间距

# —— 配色（参考图取色）——
const C_WOOD_D := Color("33200f")
const C_WOOD := Color("5a3617")
const C_WOOD_L := Color("774922")
const C_WOOD_HI := Color("8f5c2b")
const C_GOLD_D := Color("7d591c")
const C_GOLD := Color("bf8f38")
const C_GOLD_HI := Color("f2d98a")
const C_GOLD_LO := Color("6b4a16")
const C_MAT_HI := Color("e0c288")
const C_MAT_LO := Color("a9854a")
const C_INNER := Color("241811")
const C_INNER_HI := Color("2f2117")

var mat_color := Color("c9a566")          # 衬纸色; alpha = 0 则不画衬纸
var inner_color := C_INNER
var inner_top_color := C_INNER_HI

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_margins()
	resized.connect(queue_redraw)

# 一次性改厚度（头像框比对话框条细一档时用）
func set_frame_size(w: int, g: int, m: int, br: int, p: int) -> void:
	wood_t = w
	gold_t = g
	mat_t = m
	bracket = br
	pad = p
	_apply_margins()
	queue_redraw()

func has_mat() -> bool:
	return mat_color.a > 0.01

func _apply_margins() -> void:
	var m := wood_t + gold_t + (mat_t if has_mat() else 0) + pad
	add_theme_constant_override("margin_left", m)
	add_theme_constant_override("margin_right", m)
	add_theme_constant_override("margin_top", m)
	add_theme_constant_override("margin_bottom", m)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < float(wood_t + gold_t) * 2.0 + 10.0 or h < float(wood_t + gold_t) * 2.0 + 10.0:
		return

	# 1) 木框
	draw_rect(Rect2(0, 0, w, h), C_WOOD)
	_draw_wood(w, h)

	# 2) 金色斜面
	var gt := float(gold_t)
	draw_rect(Rect2(wood_t, wood_t, w - wood_t * 2.0, h - wood_t * 2.0), C_GOLD)
	draw_rect(Rect2(wood_t, wood_t, w - wood_t * 2.0, gt), C_GOLD_HI)
	draw_rect(Rect2(wood_t, wood_t, gt, h - wood_t * 2.0), C_GOLD_HI)
	draw_rect(Rect2(wood_t, h - wood_t - gt, w - wood_t * 2.0, gt), C_GOLD_LO)
	draw_rect(Rect2(w - wood_t - gt, wood_t, gt, h - wood_t * 2.0), C_GOLD_LO)

	var inset := float(wood_t + gold_t)

	# 3) 内衬纸（e98: 羊皮纸材质平铺, 参考图头像框内衬同款 —— 米黄纸底 + 洇渍 + 麻点）
	if has_mat():
		var mr := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0)
		draw_rect(mr, mat_color)
		draw_texture_rect(PARCH.tex(), mr, true)
		draw_rect(Rect2(mr.position.x, mr.position.y, mr.size.x, 1), C_MAT_HI)
		draw_rect(Rect2(mr.position.x, mr.end.y - 1, mr.size.x, 1), C_MAT_LO)
		inset += float(mat_t)

	# 4) 内容底
	var ir := Rect2(inset, inset, w - inset * 2.0, h - inset * 2.0)
	if ir.size.x <= 4.0 or ir.size.y <= 4.0:
		return
	draw_rect(ir, inner_color)
	draw_rect(Rect2(ir.position.x, ir.position.y, ir.size.x, ir.size.y * 0.45), inner_top_color)
	draw_rect(Rect2(ir.position.x, ir.position.y, ir.size.x, 1), C_GOLD_LO)
	draw_rect(Rect2(ir.position.x, ir.position.y, 1, ir.size.y), C_GOLD_LO)
	draw_rect(Rect2(ir.position.x, ir.end.y - 1, ir.size.x, 1), C_INNER.darkened(0.25))
	draw_rect(Rect2(ir.end.x - 1, ir.position.y, 1, ir.size.y), C_INNER.darkened(0.25))

	# 5) 四角金包边
	_draw_brackets(ir)

# 木框: 外缘明暗 + 四角接头 + 竖/横板缝 + 稀疏木理
func _draw_wood(w: float, h: float) -> void:
	var wt := float(wood_t)
	draw_rect(Rect2(0, 0, w, 2), C_WOOD_HI)
	draw_rect(Rect2(0, 0, 2, h), C_WOOD_HI)
	draw_rect(Rect2(0, h - 2, w, 2), C_WOOD_D)
	draw_rect(Rect2(w - 2, 0, 2, h), C_WOOD_D)
	# 木框内侧收边(贴金色斜面外沿)
	draw_rect(Rect2(wt - 2, wt - 2, w - (wt - 2) * 2.0, 2), C_WOOD_D)
	draw_rect(Rect2(wt - 2, h - wt, w - (wt - 2) * 2.0, 2), C_WOOD_L)
	draw_rect(Rect2(wt - 2, wt - 2, 2, h - (wt - 2) * 2.0), C_WOOD_D)
	draw_rect(Rect2(w - wt, wt - 2, 2, h - (wt - 2) * 2.0), C_WOOD_L)
	# 四角木接头
	draw_rect(Rect2(0, 0, 4, 4), C_WOOD_D)
	draw_rect(Rect2(w - 4, 0, 4, 4), C_WOOD_D)
	draw_rect(Rect2(0, h - 4, 4, 4), C_WOOD_D)
	draw_rect(Rect2(w - 4, h - 4, 4, 4), C_WOOD_D)
	# 板缝
	var step := float(seam_step)
	var x := step
	while x < w - 8.0:
		_seam_v(x, 0.0, wt - 4.0)
		_seam_v(x, h - wt + 2.0, wt - 4.0)
		x += step
	var y := step
	while y < h - 8.0:
		_seam_h(y, 0.0, wt - 4.0)
		_seam_h(y, w - wt + 2.0, wt - 4.0)
		y += step
	# 稀疏木理(固定步进, 不用随机, 保证每次一样)
	var gx := 9.0
	var gi := 0
	while gx < w - 12.0:
		if gi % 3 == 0:
			draw_rect(Rect2(gx, 3.0, 6.0, 1.0), C_WOOD_L)
			draw_rect(Rect2(gx + 4.0, h - 4.0, 5.0, 1.0), C_WOOD_L)
		gx += 17.0
		gi += 1

func _seam_v(x: float, y: float, len: float) -> void:
	if len <= 2.0:
		return
	draw_rect(Rect2(x, y, 2, len), C_WOOD_D)
	draw_rect(Rect2(x + 2, y, 1, len), C_WOOD_HI)

func _seam_h(y: float, x: float, len: float) -> void:
	if len <= 2.0:
		return
	draw_rect(Rect2(x, y, len, 2), C_WOOD_D)
	draw_rect(Rect2(x, y + 2, len, 1), C_WOOD_HI)

const PARCH := preload("res://parchment.gd")   # e98: 羊皮纸内衬材质

# 四角包边: 在内容区四角画 L 形角撑, 压在衬纸/金线上
func _draw_brackets(ir: Rect2) -> void:
	var L := float(bracket)
	var t := maxf(3.0, float(gold_t) - 1.0)
	var x0 := ir.position.x
	var y0 := ir.position.y
	var x1 := ir.end.x
	var y1 := ir.end.y
	# 左上
	_arm(Rect2(x0, y0, L, t))
	_arm(Rect2(x0, y0, t, L))
	# 右上
	_arm(Rect2(x1 - L, y0, L, t))
	_arm(Rect2(x1 - t, y0, t, L))
	# 左下
	_arm(Rect2(x0, y1 - t, L, t))
	_arm(Rect2(x0, y1 - L, t, L))
	# 右下
	_arm(Rect2(x1 - L, y1 - t, L, t))
	_arm(Rect2(x1 - t, y1 - L, t, L))

func _arm(r: Rect2) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	draw_rect(r, C_GOLD)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), C_GOLD_HI)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), C_GOLD_HI)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), C_GOLD_LO)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), C_GOLD_LO)