# scene/site_node.gd —— 建筑工地（建造中的脚手架）
# Structures.start_site 动工后由 game 摆出来：**对应建筑**的半透明轮廓 + 进度字。
# 夜里派活面板派几个人施工，人天攒够 Structures.add_site_work 自动落成，
# 这时 site 清空、game._sync_site_node 把脚手架撤掉换上真房子。
# e24a: 贴图跟工地类型走（鸡舍工地画鸡舍轮廓，不再一律画铁匠铺 —— 那是
# 「鸡舍贴图错误」的根源）；.kind 由 game._sync_site_node 在 add_child 前赋值。
extends Node2D

const DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/"
# kind -> [贴图路径, region x, y, w, h]（跟落成节点同一张图同一块区域）
const SKIN := {
	"blacksmith": [DIR + "Houses/NPCS houses/Blacksmith/Blacksmith house.png", 0, 8, 144, 88],
	"well": [DIR + "Well .png", 0, 48, 32, 48],
	# e30d: 跟落成节点(coop_node.gd e29h)对齐 —— 旧 112 会把下栋雪顶建筑的
	# 白屋尖裁进来（玩家说的「工地对、落成错」：其实工地多一块、落成才是干净的）。
	"coop": [DIR + "Houses/Farm Buildings/Chicken Coop/Chicken Coop.png", 12, 0, 56, 80],
}
const PIXEL_FONT := preload("res://resources/font/IPix.ttf")

var cell := Vector2i.ZERO     # 工地锚点格（底边中间那格）
var kind := "blacksmith"      # Structures 的建筑 kind（game 摆出来前赋好值）

var _spr: Sprite2D = null
var _label: Label = null
var _img_w := 144.0
var _img_h := 88.0

func _ready() -> void:
	var skin: Array = SKIN.get(kind, SKIN["blacksmith"])
	_img_w = float(skin[3])
	_img_h = float(skin[4])
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-_img_w / 2.0, -_img_h)
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var site_base := SoftRes.tex(String(skin[0]))
	var at := AtlasTexture.new()
	at.atlas = site_base      # 缺失时为 null, 工地轮廓留空但进度字照常
	at.region = Rect2(float(skin[1]), float(skin[2]), _img_w, _img_h)
	_spr.texture = at
	if site_base == null:
		push_warning("[素材] %s 工地贴图缺失, 已留空" % kind)
	# 脚手架感：褪成棕褐色的半透明轮廓
	_spr.modulate = Color(0.62, 0.5, 0.36, 0.55)
	add_child(_spr)

	# 碰撞：跟落成后的房子一样贴底一条矮矩形（layer 4 = 只拦玩家），
	# 工地期间也不让从地基里穿过去。
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(maxf(_img_w - 4.0, 24.0), 18)
	cs.shape = sh
	cs.position = Vector2(0, -9)
	body.add_child(cs)
	add_child(body)

	_label = Label.new()
	_label.add_theme_font_override("font", PIXEL_FONT)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(1, 0.93, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(-_img_w / 2.0, -_img_h - 22.0)
	_label.size = Vector2(_img_w, 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)

func _process(_delta: float) -> void:
	if _label == null or Structures.site.is_empty():
		return
	# 只在「当前工地确实是我这块」时刷新字（防残留旧工地数据）
	if Vector2i(Structures.site["anchor"]) != cell:
		return
	_label.text = "%s %d/%d 人天" % [
		Structures.site_name(), int(Structures.site["work"]), int(Structures.site["need"])]
