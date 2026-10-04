# scene/well_node.gd —— 建造系统摆出来的「水井」
#
# 开局没有现成水井了（原来那口拆掉，改成可建造建筑）：摆好后站旁边按 F 打满洒水壶。
# 跟 blacksmith_node 一个套路：原点在**井底**（父节点开了 y_sort，排序点落在底部），
# 角色走到井后面被挡住、走到前面挡住井。
# 素材 Well .png 是 128x192（4x4 共 16 个配色变体，每格 32x48），
# 取 (0,1) 那块「灰色顶棚 + 木质井身」的经典水井。
extends Node2D

const TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Well .png"

const IMG_W := 32.0
const IMG_H := 48.0

# e36h 可交互范围（相对原点）：跟走近浮提示的 reach 区同一个矩形，提示看得见就按得开
const REACH_SIZE := Vector2(48, 40)
const REACH_CENTER := Vector2(0, -16)

var cell := Vector2i.ZERO     # 所在格子
var kind := "well"            # Structures.KIND_WELL
var is_ghost := false         # 建造模式的半透明预览：不建碰撞、不带提示

var _spr: Sprite2D = null
var _hint: Node2D = null      # 走近时浮出的「F 打水」提示
var _gap := 0.0               # 素材底部透明留白（贴地修正, 见 SoftRes.bottom_gap）

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	var at := AtlasTexture.new()
	at.atlas = load(TEX)
	at.region = Rect2(0, 48, 32, 48)
	# 素材帧底部可能有透明留白, 按非透明像素底边下移贴地（见 SoftRes.bottom_gap）
	_gap = float(SoftRes.bottom_gap(at.atlas, at.region))
	_spr.position = Vector2(-IMG_W / 2.0, -IMG_H + _gap)
	_spr.texture = at
	add_child(_spr)

	if is_ghost:
		return                 # 预览只是张图，不挡路、不带提示

	# e33 井脚下的影子
	add_child(preload("res://scene/shadow_util.gd").make_shadow(26, 10, 0.25))

	# 碰撞：跟老水井一样一条贴底的矮矩形；layer 4 只有玩家的 mask 里有，
	# 伙伴穿过去免得被卡住。
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(26, 12)
	cs.shape = sh
	cs.position = Vector2(0, -6)
	body.add_child(cs)
	add_child(body)

	# 走近浮出「F 打水」提示（打水交互在 game._try_station_interact 里）
	var reach := Area2D.new()
	reach.collision_layer = 0
	reach.collision_mask = 1   # 只探玩家（玩家在 layer 1）
	var rcs := CollisionShape2D.new()
	var rsh := RectangleShape2D.new()
	rsh.size = REACH_SIZE
	rcs.shape = rsh
	rcs.position = REACH_CENTER
	reach.add_child(rcs)
	reach.body_entered.connect(_on_reach.bind(true))
	reach.body_exited.connect(_on_reach.bind(false))
	add_child(reach)

	_hint = preload("res://scene/key_hint.gd").new()
	_hint.setup("F", "打水", -64.0)
	# ❗用 connect("clicked", ...) 的字符串写法: _hint 声明成 Node2D, 直接写 _hint.clicked 过不了静态检查
	_hint.connect("clicked", _on_hint_clicked)   # e36i: 左键点这个框 = 按 F
	add_child(_hint)

func _on_reach(b: Node2D, on: bool) -> void:
	if not b.is_in_group("player") or _hint == null:
		return
	if on:
		_hint.show_hint()
	else:
		_hint.hide_hint()

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-IMG_W / 2.0, -IMG_H + _gap - 2.0), Vector2(IMG_W, IMG_H + 4.0))

# e36h 按 F 可交互的矩形（世界坐标）：game._try_station_interact 用它兜底判贴边
func interact_rect() -> Rect2:
	return Rect2(global_position + REACH_CENTER - REACH_SIZE * 0.5, REACH_SIZE)

# e36i 左键点了头上的「F 打水」框：功能跟按 F 完全一样，走 game 的同一条派发
func _on_hint_clicked() -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g != null and g.has_method("station_hint_clicked"):
		g.call("station_hint_clicked", cell)

# 被镐子拆掉：小跳 + 淡出（材料返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
