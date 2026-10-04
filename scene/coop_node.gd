# scene/coop_node.gd —— 建造系统摆出来的「鸡舍」
#
# e30p: 对鸡舍按 F 开管理界面（收蛋/买鸡/卖鸡/扩建），鸡不再走道具链路；
# 每只鸡每天早上下一个蛋（交互逻辑在 game._try_station_interact）。
# 跟 well_node 一个套路：原点在**屋底**（父节点开了 y_sort，排序点落在底部）。
# 素材 Chicken Coop.png 480x224，取 (0,0) 红墙蓝顶那栋。e28a: 房屋真实内容只有
# x 13..67 宽 55px（探针量过），旧按 96 宽取格会把右边相邻 A 字架的左边缘裁进来
# —— 游戏里鸡舍右侧挂着一条棕色断架。改取 (12,0,56,112)，内容恰好居中且无脏边。
# e29h: 纵向也重裁 —— 上栋红墙实际只到 y=79（y=80..81 是空隙，y=82 起是下栋雪顶
# 建筑的尖端），旧取 112 把下栋的白色屋尖裁进来了（玩家说的「多了一块」）。
# 鸡群：门口空地最多显示 4 只 16x16 的小鸡，四帧交替做啄食动画（e38a 取第 6 行那组真啄食帧）；
# 显示只数跟着 Structures.chickens_of 走（e30p 起上限随等级涨 Lv1=3/Lv2=4/Lv3=5，
# 门口画 4 只挤挤也够了）。
extends Node2D

const TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/Farm Buildings/Chicken Coop/Chicken Coop.png"
const CHICK_TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Animals/Farm/Chicken/Chicken White.png"

const IMG_W := 56.0
const IMG_H := 80.0
const SHOW_CAP := 4         # 门口最多画几只鸡

# e38a 啄食取帧：Chicken White.png 是 4 列 x 7 行、每格 16x16。
#   探针逐格对账过：第 0~5 行都是「两帧一小动」的重复布局（c0 与 c2 逐像素相同、
#   c1 与 c3 相同），其中第 0 行那两帧只差 1 个像素 —— 鸡站在那儿等于不动。
#   真正低头啄食的那一组在第 6 行：四帧像素数 148 / 117 / 111 / 121，
#   不透明框顶从 y96 掉到 y99（脑袋埋下去，跟身子并成一块，所以像素反而变少）。
const CHICK_PECK_ROW := 6
const CHICK_FRAMES := 4
const CHICK_STEP := 0.18    # 一帧 0.18 秒，一轮啄食 ≈ 0.7 秒

# e36h 可交互范围（相对原点）：跟走近浮提示的 reach 区**同一个矩形**。
#   —— 只要「F 鸡舍」提示露出来了，按 F 就一定能开面板，四周任意一边都行。
#   以前 F 走 game._try_station_interact 的 3x3 格扫描，而 Structures 只记锚点那一格，
#   锚点又在鸡舍最下面一行的底边：站在门前（下方）/两侧时，自己那 3x3 够不到锚点格，
#   非得绕到屋后去按 F —— 玩家报的「要在后面按 F 才能点开面板」就是这里。
const REACH_SIZE := Vector2(120, 52)
const REACH_CENTER := Vector2(0, -18)

var cell := Vector2i.ZERO   # 所在格子
var kind := "coop"          # Structures.KIND_COOP
var is_ghost := false       # 建造模式的半透明预览：不建碰撞、不带提示

var _spr: Sprite2D = null
var _hint: Node2D = null    # 走近时浮出的「F 鸡舍」提示
var _chicks: Array = []     # 门口的小鸡 Sprite2D（按需显示）
var _frame := 0

# 门口空地的站位（相对原点）：鸡在门前一小片来回啄
const PERCH := [Vector2(-30, 10), Vector2(-8, 14), Vector2(14, 10), Vector2(32, 14)]

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-IMG_W / 2.0, -IMG_H)
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var coop_base := SoftRes.tex(TEX)
	var at := AtlasTexture.new()
	at.atlas = coop_base      # 缺失时为 null, 鸡舍留空但碰撞照常
	at.region = Rect2(12, 0, 56, 80)
	_spr.texture = at
	add_child(_spr)
	if coop_base == null:
		push_warning("[素材] 鸡舍贴图缺失, 已留空")

	if is_ghost:
		return                 # 预览只是张图，不挡路、不带提示、不带鸡

	# e33 鸡舍脚下的影子
	add_child(preload("res://scene/shadow_util.gd").make_shadow(50, 14, 0.18))

	# 碰撞：贴底的矮矩形（门那一行），layer 4 只有玩家的 mask 里有
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(52, 16)
	cs.shape = sh
	cs.position = Vector2(0, -8)
	body.add_child(cs)
	add_child(body)

	# 走近浮出「F 鸡舍」提示（交互在 game._try_station_interact 里）
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
	_hint.setup("F", "鸡舍", -92.0)   # e29h: 屋高从 112 降到 80, 提示浮点跟着降
	# ❗用 connect("clicked", ...) 的字符串写法: _hint 声明成 Node2D,
	#   直接写 _hint.clicked 会被静态检查判成「Node2D 没有 clicked 成员」。
	_hint.connect("clicked", _on_hint_clicked)   # e36i: 左键点这个框 = 按 F
	add_child(_hint)

	# 门口的鸡：先建好藏着，鸡数变了再露头（第三方素材缺失时留空不崩）
	var ctex: Texture2D = SoftRes.tex(CHICK_TEX)
	if ctex == null:
		push_warning("[素材] 小鸡贴图缺失, 已留空")
	for i in SHOW_CAP:
		var chick := Sprite2D.new()
		var cat := AtlasTexture.new()
		cat.atlas = ctex
		cat.region = Rect2(0, 16 * CHICK_PECK_ROW, 16, 16)
		chick.texture = cat
		chick.position = PERCH[i]
		chick.flip_h = i % 2 == 0      # 相邻的鸡脸朝反方向
		chick.visible = false
		add_child(chick)
		_chicks.append(chick)
	Structures.station_changed.connect(_on_station_changed)
	Structures.station_removed.connect(_on_station_removed)
	_refresh_chicks()

	# 啄食动画：第 6 行那四帧循环，每只鸡按编号错开相位（不会同起同落）
	var tw := create_tween().set_loops()
	tw.tween_interval(CHICK_STEP)
	tw.tween_callback(_flip_frames)

func _exit_tree() -> void:
	if Structures.station_changed.is_connected(_on_station_changed):
		Structures.station_changed.disconnect(_on_station_changed)
	if Structures.station_removed.is_connected(_on_station_removed):
		Structures.station_removed.disconnect(_on_station_removed)

func _on_station_changed(c: Vector2i) -> void:
	if c == cell:
		_refresh_chicks()

func _on_station_removed(c: Vector2i) -> void:
	if c == cell:
		_refresh_chicks()

func _flip_frames() -> void:
	_frame = (_frame + 1) % CHICK_FRAMES
	for i in _chicks.size():
		var chick: Sprite2D = _chicks[i]
		if chick.visible:
			var f: int = (_frame + i) % CHICK_FRAMES
			(chick.texture as AtlasTexture).region = Rect2(16 * f, 16 * CHICK_PECK_ROW, 16, 16)

func _refresh_chicks() -> void:
	var n: int = mini(Structures.chickens_of(cell), SHOW_CAP)
	for i in _chicks.size():
		_chicks[i].visible = i < n

func _on_reach(b: Node2D, on: bool) -> void:
	if not b.is_in_group("player") or _hint == null:
		return
	if on:
		_hint.show_hint()
	else:
		_hint.hide_hint()

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-IMG_W / 2.0, -IMG_H - 2.0), Vector2(IMG_W, IMG_H + 4.0))

# e36h 按 F 可交互的矩形（世界坐标）：game._try_station_interact 用它判断玩家贴没贴边。
#   跟「走近浮提示」的 reach 区重合，所以「提示看得见 = F 按得开」。
func interact_rect() -> Rect2:
	return Rect2(global_position + REACH_CENTER - REACH_SIZE * 0.5, REACH_SIZE)

# e36i 左键点了头上的「F 鸡舍」框：功能跟按 F 完全一样，走 game 的同一条派发
func _on_hint_clicked() -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g != null and g.has_method("station_hint_clicked"):
		g.call("station_hint_clicked", cell)

# 被镐子拆掉：小跳 + 淡出（材料/鸡/蛋返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
