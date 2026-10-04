# scene/hive_node.gd —— e44b 新建的「蜂箱」
#
# 每天早上攒 1 罐蜜（冬天/风暴天不产，见 Structures.make_honey），
# 站旁边按 F（或左键点头上的提示框）把攒的蜜一次收进背包。
# 素材 Beehive.png 是 112x32 = 7 帧 16x32 的同一只蜂箱：帧号越大箱口挂的蜜越厚，
# 所以直接拿「攒了几罐」当帧号 —— 箱里越满，看着越淌蜜，一眼看出该收了。
# 原点在**箱底中间**（父节点开了 y_sort，排序点落在底边）。
extends Node2D

const TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Work Benches/Beehive.png"
const IMG_W := 16.0
const IMG_H := 32.0
const FRAMES := 7           # 素材整张 112 宽 / 16 = 7 帧

# 可交互范围（相对原点）：跟走近浮提示的 reach 区同一个矩形 ——
# 只要「F 蜂箱」提示露出来了，按 F 就一定收得到。
const REACH_SIZE := Vector2(48, 40)
const REACH_CENTER := Vector2(0, -18)

var cell := Vector2i.ZERO   # 所在格子
var kind := "hive"          # Structures.KIND_HIVE
var is_ghost := false       # 建造模式的半透明预览：不建碰撞、不带提示

var _spr: Sprite2D = null
var _hint: Node2D = null
var _gap := 0.0             # 素材底部透明留白（贴地修正, 见 SoftRes.bottom_gap）

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	var at := _frame_tex(0)
	# 素材帧底部可能有透明留白, 按非透明像素底边下移贴地（见 SoftRes.bottom_gap）
	_gap = float(SoftRes.bottom_gap(at.atlas, at.region))
	_spr.position = Vector2(-IMG_W / 2.0, -IMG_H + _gap)
	_spr.texture = at
	add_child(_spr)

	if is_ghost:
		return                 # 预览只是张图，不挡路、不带提示

	add_child(preload("res://scene/shadow_util.gd").make_shadow(20, 9, 0.2))

	# 碰撞：贴底的矮矩形，layer 4 只有玩家的 mask 里有
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(14, 10)
	cs.shape = sh
	cs.position = Vector2(0, -5)
	body.add_child(cs)
	add_child(body)

	# 走近浮出「F 蜂箱」提示（交互在 game._station_interact_cell 里）
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
	_hint.setup("F", "蜂箱", -44.0)
	# ❗用 connect("clicked", ...) 的字符串写法: _hint 声明成 Node2D,
	#   直接写 _hint.clicked 会被静态检查判成「Node2D 没有 clicked 成员」。
	_hint.connect("clicked", _on_hint_clicked)   # 左键点这个框 = 按 F
	add_child(_hint)

	Structures.station_changed.connect(_on_station_changed)
	Structures.station_removed.connect(_on_station_removed)
	_refresh_frame()

func _exit_tree() -> void:
	if Structures.station_changed.is_connected(_on_station_changed):
		Structures.station_changed.disconnect(_on_station_changed)
	if Structures.station_removed.is_connected(_on_station_removed):
		Structures.station_removed.disconnect(_on_station_removed)

func _frame_tex(f: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	# 第三方素材不入库(见 README), 缺失时留空不崩（atlas 为 null 合法, 不崩）
	at.atlas = SoftRes.tex(TEX)
	at.region = Rect2(16 * clampi(f, 0, FRAMES - 1), 0, 16, 32)
	return at

func _on_station_changed(c: Vector2i) -> void:
	if c == cell:
		_refresh_frame()

func _on_station_removed(c: Vector2i) -> void:
	if c == cell:
		_refresh_frame()

# 帧号跟着箱里攒的蜜走：空箱 -> 第 0 帧；攒满 HIVE_MAX -> 最后一帧（蜜往下淌）
func _refresh_frame() -> void:
	if _spr == null:
		return
	var n := Structures.honey_of(cell)
	var f := 0
	if n > 0:
		f = int(round(float(n) / float(Structures.HIVE_MAX) * float(FRAMES - 1)))
	_spr.texture = _frame_tex(f)

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

# 按 F 可交互的矩形（世界坐标）：game._try_station_interact 用它判断玩家贴没贴边
func interact_rect() -> Rect2:
	return Rect2(global_position + REACH_CENTER - REACH_SIZE * 0.5, REACH_SIZE)

# 左键点了头上的「F 蜂箱」框：功能跟按 F 完全一样，走 game 的同一条派发
func _on_hint_clicked() -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g != null and g.has_method("station_hint_clicked"):
		g.call("station_hint_clicked", cell)

# 被镐子拆掉：小跳 + 淡出（材料/攒的蜜返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)