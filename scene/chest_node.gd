# scene/chest_node.gd —— e45 新建的「储物箱」
#
# 站旁边按 F（或左键点头上的提示框）开箱, 把暂时用不上的东西存进去 / 取出来。
# 素材 chest.png 是 256x32 = 8 列 x 2 行 的单只木头箱子（每格 32x16, 里面一只 16x16 的箱子;
# 8 列 = 8 种配色, 2 行 = 盖着的 / 敞着的）。这里取上排第 0 列那只盖着的棕木箱。
# ❗e47 之前取的是 Rect2(0,0,32,32) —— 那根本不是「一只箱子」, 而是**上下两只**,
#   画出来像个双屉柜（跟 scene/shipping_bin.gd 里踩过的坑一模一样, 见那边的注释）。
#   箱子是 16x16 一格, 原点在箱底中间, 不缩放。
# 原点在**箱底中间**（父节点开了 y_sort，排序点落在底边）。
extends Node2D

const TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/chest.png"
const IMG_W := 16.0
const IMG_H := 16.0
# 单只箱子的裁剪区: 第 0 列、上排（盖着的那只棕木箱）
const REGION := Rect2(8, 0, 16, 16)

# 可交互范围（相对原点）：跟走近浮提示的 reach 区同一个矩形 ——
# 只要「F 储物箱」提示露出来了，按 F 就一定开得开。
const REACH_SIZE := Vector2(56, 44)
const REACH_CENTER := Vector2(0, -18)

var cell := Vector2i.ZERO   # 所在格子
var kind := "chest"         # Structures.KIND_CHEST
var is_ghost := false       # 建造模式的半透明预览：不建碰撞、不带提示

var _spr: Sprite2D = null
var _hint: Node2D = null
var _full_mark: Label = null

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-IMG_W / 2.0, -IMG_H)
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var chest_base := SoftRes.tex(TEX)
	var at := AtlasTexture.new()
	at.atlas = chest_base      # 缺失时为 null, 箱子留空但碰撞照常
	at.region = REGION
	_spr.texture = at
	add_child(_spr)
	if chest_base == null:
		push_warning("[素材] 储物箱贴图缺失, 已留空")

	if is_ghost:
		return                 # 预览只是张图，不挡路、不带提示

	add_child(preload("res://scene/shadow_util.gd").make_shadow(16, 8, 0.22))

	# 箱满了在头上挂个小字（一眼看出没地方了, 不用开箱才知道）
	_full_mark = Label.new()
	_full_mark.text = "满"
	_full_mark.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	_full_mark.add_theme_font_size_override("font_size", 11)
	_full_mark.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	_full_mark.position = Vector2(-5, -IMG_H - 14)
	_full_mark.visible = false
	add_child(_full_mark)

	# 碰撞：贴底的矮矩形，layer 4 只有玩家的 mask 里有
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(14, 8)
	cs.shape = sh
	cs.position = Vector2(0, -4)
	body.add_child(cs)
	add_child(body)

	# 走近浮出「F 储物箱」提示（交互在 game._station_interact_cell 里）
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
	_hint.setup("F", "储物箱", -48.0)
	# ❗用 connect("clicked", ...) 的字符串写法: _hint 声明成 Node2D,
	#   直接写 _hint.clicked 会被静态检查判成「Node2D 没有 clicked 成员」。
	_hint.connect("clicked", _on_hint_clicked)   # 左键点这个框 = 按 F
	add_child(_hint)

	Structures.station_changed.connect(_on_station_changed)
	Structures.station_removed.connect(_on_station_removed)
	_refresh_mark()

func _exit_tree() -> void:
	if Structures.station_changed.is_connected(_on_station_changed):
		Structures.station_changed.disconnect(_on_station_changed)
	if Structures.station_removed.is_connected(_on_station_removed):
		Structures.station_removed.disconnect(_on_station_removed)

func _on_station_changed(c: Vector2i) -> void:
	if c == cell:
		_refresh_mark()

func _on_station_removed(c: Vector2i) -> void:
	if c == cell:
		_refresh_mark()

func _refresh_mark() -> void:
	if _full_mark == null:
		return
	_full_mark.visible = Structures.chest_full(cell)

func _on_reach(b: Node2D, on: bool) -> void:
	if not b.is_in_group("player") or _hint == null:
		return
	if on:
		_hint.show_hint()
	else:
		_hint.hide_hint()

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-IMG_W / 2.0, -IMG_H - 2.0),
		Vector2(IMG_W, IMG_H + 4.0))

# 按 F 可交互的矩形（世界坐标）：game._try_station_interact 用它判断玩家贴没贴边
func interact_rect() -> Rect2:
	return Rect2(global_position + REACH_CENTER - REACH_SIZE * 0.5, REACH_SIZE)

# 左键点了头上的「F 储物箱」框：功能跟按 F 完全一样，走 game 的同一条派发
func _on_hint_clicked() -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g != null and g.has_method("station_hint_clicked"):
		g.call("station_hint_clicked", cell)

# 被镐子拆掉：小跳 + 淡出（材料/箱里的东西返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)