# scene/station_node.gd —— 玩家摆放的设施（工作台 / 熔炉）：贴图 + 碰撞 + 熔炼动画
#
# ❗原点在**设施底部**（不是格子中心）：父节点开了 y_sort，排序点落在底部，
#   角色走到设施后面就被挡住、走到前面就挡住设施 —— 跟树/石头一个道理。
extends Node2D

# 工作台：32x32 单帧；熔炉：160x32 = 5 帧 32x32（第 0 帧 idle，1~4 帧熔炼循环）
const WORKBENCH_TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Work Benches/Workbench.png"
const FURNACE_TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Work Benches/Furnace.png"

const FRAME_W := 32
const FRAME_H := 32
const BASE_Y := 32.0            # 素材内容贴到帧底，底部对齐节点原点

var cell := Vector2i.ZERO       # 所在格子
var kind := "workbench"         # Structures.KIND_*

var _spr: Sprite2D = null
var _anim_t := 0.0
var _gap := 0.0                 # 素材帧底部透明留白（贴地修正, 见 SoftRes.bottom_gap）

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-FRAME_W / 2.0, -BASE_Y)
	add_child(_spr)
	apply_look()
	# e33 设施脚下的影子
	add_child(preload("res://scene/shadow_util.gd").make_shadow(24, 9, 0.25))

	# 碰撞：跟树干/石头一样 layer 4（值 4）—— 只有玩家的 mask 里有这一层，
	# 伙伴会直接穿过去，免得它们干活时被设施卡住。
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(28, 12)
	cs.shape = sh
	cs.position = Vector2(0, -6)
	body.add_child(cs)
	add_child(body)

# 摆好贴图（kind 决定用哪张图）
func apply_look() -> void:
	if _spr == null:
		return
	var at := AtlasTexture.new()
	if kind == "furnace":
		at.atlas = load(FURNACE_TEX)
	else:
		at.atlas = load(WORKBENCH_TEX)
	at.region = Rect2(0, 0, FRAME_W, FRAME_H)
	_spr.texture = at
	_spr.modulate = Color.WHITE
	# 素材帧底部常有透明留白（实测 Workbench.png 内容偏上），按非透明像素
	# 的底边把贴图往下挪, 内容才踩在原点上不悬空。熔炉 5 帧同图集对齐, 取第 0 帧即可。
	_gap = float(SoftRes.bottom_gap(at.atlas, at.region))
	_spr.position = Vector2(-FRAME_W / 2.0, -BASE_Y + _gap)

func _process(delta: float) -> void:
	if _spr == null:
		return
	if kind != "furnace":
		return
	var st := Structures.state_of(cell)
	match st:
		"smelting":
			# 熔炼中：1~4 帧火焰循环
			_anim_t += delta * 6.0
			_set_frame(1 + (int(_anim_t) % 4))
			_spr.modulate = Color.WHITE
		"ready":
			# 出铁待取：回到静止帧 + 发亮提醒玩家来拿
			_set_frame(0)
			_spr.modulate = Color(1.3, 1.2, 0.75)
		_:
			_set_frame(0)
			_spr.modulate = Color.WHITE

func _set_frame(f: int) -> void:
	var at: AtlasTexture = _spr.texture
	if at != null:
		at.region = Rect2(f * FRAME_W, 0, FRAME_W, FRAME_H)

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-FRAME_W / 2.0, -BASE_Y + _gap - 2.0),
		Vector2(FRAME_W, BASE_Y + 4.0))

# 被镐子拆掉：小跳 + 淡出（物品返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
