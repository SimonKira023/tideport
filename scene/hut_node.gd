# scene/hut_node.gd —— e44 新建的「同伴小屋」
#
# 每盖一座伙伴上限 +1（数据在 Structures.hut_count -> Slaves.refresh_cap）。
# 每座外形按建造顺序取 Structures.HUT_LOOKS 里的下一款 —— 后盖的跟先盖的长得不一样；
# 用哪一款记在 station 字典的 variant 字段里，读档/搬移都不会变脸。
# 跟 coop_node 一个套路：原点在**屋底中间**（父节点开了 y_sort，排序点落在底边）。
# 小屋本身不可交互（不挂 F 提示）—— 它只是个住处，摆哪儿都行。
extends Node2D

var cell := Vector2i.ZERO   # 所在格子
var kind := "hut"           # Structures.KIND_HUT
var is_ghost := false       # 建造模式的半透明预览：不建碰撞
var variant := -1           # 用第几款外形；-1 = 自己按所在格子问 Structures

# 建筑模式搬房子时, game 在建节点(还没 add_child)前先喂进来 —— 预览/新家的外形跟原来一致
func set_variant(v: int) -> void:
	variant = v

var _w := 0.0
var _h := 0.0

func _ready() -> void:
	var v := variant
	if v < 0:
		v = Structures.variant_of(cell)
	var look: Dictionary = Structures.hut_look(v)
	if look.is_empty():
		return
	var rect: Rect2 = look["rect"]
	_w = rect.size.x
	_h = rect.size.y
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var hut_base := SoftRes.tex(String(look["tex"]))
	var at := AtlasTexture.new()
	at.atlas = hut_base      # 缺失时为 null, 屋子留空但碰撞照常
	at.region = rect
	var spr := Sprite2D.new()
	spr.centered = false
	spr.position = Vector2(-_w / 2.0, -_h)   # 原点 = 屋底中间
	spr.texture = at
	add_child(spr)
	if hut_base == null:
		push_warning("[素材] 同伴小屋贴图缺失, 已留空")

	if is_ghost:
		return                 # 预览只是张图，不挡路

	# 屋脚下的影子
	add_child(preload("res://scene/shadow_util.gd").make_shadow(_w * 0.82, 14, 0.18))

	# 碰撞：贴底的矮矩形（门那一行），layer 4 只有玩家的 mask 里有
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(maxf(24.0, _w - 16.0), 16.0)
	cs.shape = sh
	cs.position = Vector2(0, -8)
	body.add_child(cs)
	add_child(body)

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-_w / 2.0, -_h - 2.0), Vector2(_w, _h + 4.0))

# 被镐子拆掉：小跳 + 淡出（材料返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)