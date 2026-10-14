# emote_bubble.gd —— P1 情绪气泡（星露谷式）
#
# 一句话：`EMOTE.pop_over(npc, "heart")` —— 小人头顶弹出一个
# 黑边白底小气泡，里面住着一个像素表情，停一拍后 pop 掉。
#
# ⭐和星露谷同款的「融合贴图」设计（用户点名）：
#   白色气泡底 + 黑描边 + 下垂小尾巴 + 表情，**全部画进同一张 ImageTexture**，
#   气泡即表情、表情即气泡 —— 不是「框 + 字」两层皮，凸出心情本身。
#   ⚠️IPix.ttf 没有 ♥/怒筋 等字形（红线 1），所以表情也是**逐像素画**的，
#   不走字体。
#
# 结构（像素级）：
#   · 画布 13x14，1 画布像素 = 1 世界像素（岛上相机 zoom 4 下小人约 16px 高,
#     气泡跟人一个颗粒度才不穿帮；NEAREST 过滤保证 4x 放大后棱角分明）
#   · 气泡圆角矩形 13x11 + 3 行小尾巴，尾巴尖 = 节点原点（挂谁头顶就对准谁）
#   · 表情 7x7 居中，每种一套字符画（ICON_MAP），调色板逐个配
#   · 静态缓存：每种 kind 只画一次，全局共用同一张贴图
#
# 动画：pop 弹入（0.4 -> 1.0 回弹）-> 轻轻晃 -> 到点缩小淡出 -> 自毁。
# process_mode = ALWAYS：送礼面板暂停世界时气泡照常蹦（纯装饰不参与逻辑）。
#
# API：
#   EMOTE.pop_over(host: Node2D, kind: String, dur := 1.4, height := 30.0)
#     —— 挂 host 头顶 height 像素处（host 原点必须在**脚下**，红线 5）。
#     小人头顶约在 -26, 默认 30 = 尾巴尖刚好悬在头顶上一格。
#   kind 一览：!  ?  ...  heart  anger  sweat  note  zzz
extends Node2D

# ---------------- 表情字符画（7x7，字符 -> 颜色查各自的 PALETTE） ----------------
# '.' = 透明。每张都要是 7 行 x 7 列，画歪一格都会在截图里很明显。
const ICON_MAP := {
	"!": [
		"...KK...",
		"...KK...",
		"...KK...",
		"...KK...",
		"...KK...",
		"........",
		"...KK...",
	],
	"?": [
		"..KKKK..",
		".KK..KK.",
		".KK..KK.",
		"....KK..",
		"...KK...",
		"........",
		"...KK...",
	],
	"...": [
		"........",
		"........",
		"........",
		"........",
		".K.K.K..",
		".K.K.K..",
		"........",
	],
	"heart": [
		".KK.KK..",
		"KRRKRRK.",
		"KRRRRRK.",
		"KRRRRRK.",
		".KRRRK..",
		"..KRK...",
		"...K....",
	],
	"anger": [
		"KK...KK.",
		".KK.KK..",
		"..KKK...",
		"...K....",
		"..KKK...",
		".KK.KK..",
		"KK...KK.",
	],
	"sweat": [
		"...KK...",
		"..KKKK..",
		"..KBBK..",
		".KBBBBK.",
		".KBBBBK.",
		".KBBBBK.",
		"..KKKK..",
	],
	"note": [
		"...KKKK.",
		"...K..K.",
		"...K..K.",
		"...K....",
		"...K....",
		".KKKK...",
		".KKKK...",
	],
	"zzz": [
		".KKKKK..",
		"....KK..",
		"...KK...",
		"..KK....",
		".KK.....",
		".KKKKKK.",
		"........",
	],
}

# 每种表情的字符调色板（K 一律当描边/主体深色用）
const PALETTES := {
	"!": {"K": Color("3a3a46")},
	"?": {"K": Color("3a3a46")},
	"...": {"K": Color("3a3a46")},
	"heart": {"K": Color("8c2f3f"), "R": Color("e0455a")},
	"anger": {"K": Color("c23434")},
	"sweat": {"K": Color("2b4a66"), "B": Color("5aa7e8")},
	"note": {"K": Color("4a55c0")},
	"zzz": {"K": Color("5a6b85")},
}

# 气泡本体的颜色（白底黑框, 微暖白不刺眼）
const BUBBLE_FILL := Color("faf7f0")
const BUBBLE_LINE := Color("241f1a")

const PIX := 1              # 1 张画布像素 = 1 世界像素（相机 zoom 4 下正好是小人同款颗粒度）
const CANVAS_W := 13
const CANVAS_H := 14
const ICON_SIZE := 7        # 表情字符画边长（调 ICON_MAP 要连着改）
const ICON_POS := Vector2i(3, 2)

static var _cache: Dictionary = {}   # kind -> Texture2D（全项目共用一套贴图）

# ---------------- 生成一张「气泡 + 表情」融合贴图 ----------------
static func tex_of(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var icon: Array = ICON_MAP.get(kind, ICON_MAP["!"])
	var pal: Dictionary = PALETTES.get(kind, PALETTES["!"])
	var img := Image.create_empty(CANVAS_W, CANVAS_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 1) 气泡圆角矩形：行 0..10 全宽 13，四角各削 1px（像素画的"圆角"）
	for y in range(0, 11):
		for x in range(0, CANVAS_W):
			var corner := (x == 0 or x == CANVAS_W - 1) and (y == 0 or y == 10)
			if corner:
				continue
			var edge := x == 0 or x == CANVAS_W - 1 or y == 0 or y == 10
			img.set_pixel(x, y, BUBBLE_LINE if edge else BUBBLE_FILL)
	# 2) 尾巴：底边 x=5..7 开口向下收成尖（尖在 x=6, 行 13 = 节点原点）
	var tail := {
		Vector2i(5, 11): BUBBLE_FILL, Vector2i(6, 11): BUBBLE_FILL,
		Vector2i(7, 11): BUBBLE_FILL,
		Vector2i(4, 11): BUBBLE_LINE, Vector2i(8, 11): BUBBLE_LINE,
		Vector2i(6, 12): BUBBLE_FILL,
		Vector2i(5, 12): BUBBLE_LINE, Vector2i(7, 12): BUBBLE_LINE,
		Vector2i(6, 13): BUBBLE_LINE,
	}
	for p: Vector2i in tail:
		img.set_pixel(p.x, p.y, tail[p])
	# 3) 表情 7x7 盖进气泡正中
	for iy in range(ICON_SIZE):
		var row: String = icon[iy]
		for ix in range(ICON_SIZE):
			var ch := row[ix]
			if ch == ".":
				continue
			# 字符画 7 列画在 7 宽的区域里, 右侧留 1px 余量（图标统一偏左半格更居中）
			img.set_pixel(ICON_POS.x + ix, ICON_POS.y + iy, pal.get(ch, Color.BLACK))
	var t := ImageTexture.create_from_image(img)
	_cache[kind] = t
	return t

# ---------------- 气泡节点 ----------------
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 5               # 压过 key_hint(3) 和角色

# 挂 host 头顶弹出（host 原点在脚下）。fire-and-forget，到点自毁。
# （静态函数里直接 new() 出自己的实例 —— 同脚本作用域内可用）
static func pop_over(host: Node2D, kind: String, dur := 1.4, height := 30.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var e := new()
	e._fire(host, kind, dur, height)

# ---------------- 内部 ----------------
var _spr: Sprite2D

func _fire(host: Node2D, kind: String, dur: float, height: float) -> void:
	host.add_child(self)
	position = Vector2(0, -height)
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_spr.texture = tex_of(kind)
	# 尾巴尖(画布 6,13) 对准节点原点: offset = -(6,13)，整体 x2 放大
	_spr.offset = Vector2(-6, -13)
	_spr.scale = Vector2(PIX, PIX)
	add_child(_spr)
	# pop 弹入 -> 摇一摇 -> 到点淡出
	scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(dur, 0.3))
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.14)
	tw.tween_callback(queue_free)
	# 待机期间轻轻左右晃（幅度 1 像素, 像被风吹）
	var sway := create_tween().set_loops()
	sway.tween_property(_spr, "position:x", 1.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(_spr, "position:x", -1.0, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
