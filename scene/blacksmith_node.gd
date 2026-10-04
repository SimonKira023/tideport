# scene/blacksmith_node.gd —— 建造系统摆出来的「铁匠铺」
#
# 跟 station_node 一个套路：原点在**建筑底部**（父节点开了 y_sort，排序点落在底部），
# 角色走到房子后面被挡住、走到前面挡住房子。
# 素材 Blacksmith house.png 是 144x96，顶部约 8px 是空白 —— 裁掉后内容 144x88。
# 等级越高外观越亮一点（Lv1 白 -> Lv2 淡金 -> Lv3 红铜），凑合当「升级了看得出来」。
extends Node2D

const TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/NPCS houses/Blacksmith/Blacksmith house.png"

const IMG_W := 144.0
const IMG_H := 88.0           # 裁掉顶部空白后的内容高
const CROP_TOP := 8           # 素材顶部空白像素数

# 等级外观：乘到精灵 modulate 上的色（Lv1 原色）
const LEVEL_TINTS := [
	Color(1, 1, 1),
	Color(1.06, 1.0, 0.82),
	Color(1.12, 0.9, 0.72),
]

var cell := Vector2i.ZERO     # 所在格子（锚点 = 底边中间那格）
var kind := "blacksmith"      # Structures.KIND_BLACKSMITH
var is_ghost := false         # 建造模式的半透明预览：不建碰撞、不查等级色

var _spr: Sprite2D = null
var _last_level := -1

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-IMG_W / 2.0, -IMG_H)
	add_child(_spr)
	apply_look()

	if is_ghost:
		return                 # 预览只是张图，不挡路

	# e33 房子脚下的影子：一大片很淡的椭圆, 把建筑「压」到地面上
	add_child(preload("res://scene/shadow_util.gd").make_shadow(120, 26, 0.16))

	# 碰撞：跟树干/石头一样 layer 4（值 4）—— 只有玩家的 mask 里有这一层，
	# 伙伴穿过去免得被房子卡住。房子地基很宽，用一条贴底的矮矩形。
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(140, 18)
	cs.shape = sh
	cs.position = Vector2(0, -9)
	body.add_child(cs)
	add_child(body)

func apply_look() -> void:
	if _spr == null:
		return
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var bs_base := SoftRes.tex(TEX)
	var at := AtlasTexture.new()
	at.atlas = bs_base      # 缺失时为 null, 铁匠铺留空但等级色照常
	at.region = Rect2(0, CROP_TOP, IMG_W, IMG_H)
	_spr.texture = at
	if bs_base == null:
		push_warning("[素材] 铁匠铺贴图缺失, 已留空")
	_sync_level()

func _process(_delta: float) -> void:
	if is_ghost or _spr == null:
		return
	# 等级变了（升级）就换一下外观色
	if Structures.level_of(cell) != _last_level:
		_sync_level()

func _sync_level() -> void:
	_last_level = Structures.level_of(cell)
	if _spr == null:
		return
	var lv := maxi(1, _last_level)
	var tints: int = LEVEL_TINTS.size()
	_spr.modulate = LEVEL_TINTS[mini(lv, tints) - 1]

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-IMG_W / 2.0, -IMG_H - 2.0), Vector2(IMG_W, IMG_H + 4.0))

# 被镐子拆掉：小跳 + 淡出（材料返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
