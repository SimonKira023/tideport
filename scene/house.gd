# house.gd —— 农舍：外观 + 门 + 室内（地板 / 墙 / 床）
#
# 室内不是另一个场景，而是挂在同一个 House 节点下面、往下方挪了一段距离的一块独立区域。
# 好处：不用切场景，HUD / 时间 / 相机全都照常工作，进门出门只是把玩家瞬移过去。
extends Node2D

# 室内不去切 Tileset House.png —— 那一整张是所有能平铺的「花砖」，
# 每一格都带竖向条纹或角上的小点，铺满一屋子就是「条形和点」。
# 改成**整间屋子一次性画成一张图**（RoomArt）：
#   · 木地板：一行一块长板，板缝是铺满整行的横线（连贯，不会断成一格一格）；
#     板与板之间的端头缝间隔 70~150 像素随机错开 —— 看上去是拼起来的长条地板，不是砖
#   · 每块板深浅略有随机，板上再拉几条顺着纹理的细线 —— 这是「木质感」的来源
#   · 木墙：一块块竖着钉的木板，宽窄/深浅也都有微差
#   · 地板四周压 2px 深色 —— 墙脚阴影，房间轮廓清楚
const TS := 16
const FLOOR_COLOR := Color8(217, 168, 138)     # 地板底色（浅暖木）
const FLOOR_SEAM := Color8(171, 102, 89)       # 板缝
const FLOOR_HI := Color8(233, 189, 161)        # 缝下高光
const WALL_COLOR := Color8(138, 54, 37)        # 墙底色（暖红棕）
const WALL_SEAM := Color8(104, 40, 27)         # 板缝
const WALL_HI := Color8(160, 70, 50)           # 缝侧高光
const SHADOW_COLOR := Color8(74, 33, 35)       # 墙脚阴影

const ROOM_W := 18
const ROOM_H := 12
const PLANK_H := 16      # 每块地板的横向高度
const PLANK_W := 48      # 端头缝的最小间隔基准（真正用的是 70~150 的随机值）
const BOARD_W := 32      # 墙板基准宽度（实际会上下浮动）
const ROOM_SEED := 20260913   # 固定种子：木纹每次开局都一样，方便对比改动

# ---------------- e31 光影 ----------------
const LIGHT_UTIL := preload("res://scene/light_util.gd")
# e38c 屋前挂灯整盏撤掉：它立在门边、正好卡在售货箱的落脚点上，
#   俯瞰下去像从箱子里长出来一盏灯笼。路灯改走「可建造建筑」（见 structures.gd 的 KIND_LAMP）。

# 地板区域（相对 Interior 节点）
const FLOOR_RECT := Rect2i(TS, 2 * TS, (ROOM_W - 2) * TS, (ROOM_H - 3) * TS)

# 床（素材 Beds.png 里那张「床头两张枕头 + 被子」的双人床）
const BED_REGION := Rect2(7, 269, 33, 34)
const BED_LOCAL := Vector2(16, 32)      # 床贴在图里的左上角（紧挨左墙和上墙）
const BED_SIZE := Vector2(BED_REGION.size)

# 睡觉落点：Bed 节点原点（= 床贴图左上角）+ 这个偏移 = 玩家脚下位置。
# ❗睡觉动作那帧 32x32 里，脑袋只占中间一小块（大约 x 10..23 / y 6..18），
#   而精灵整体画在玩家原点上方 16px 处 —— 以前直接把玩家放到床中心，
#   脑袋整个飘到床沿上方的墙上了。往下挪 16px 让脑袋正好躺在两个枕头中间。
const SLEEP_LAND := Vector2(16, 33)

# 室内活动范围（相对 Interior 节点），用夹位置的方式代替给房间加一圈碰撞体
#
# ❗e36c 夹的是玩家**节点原点**，而角色的可见像素并不长在原点周围：
#   BodySprite 画在 (0,-16)、帧 32x32，Idle 第 0 帧的不透明区是 x 10..21 / y 6..25，
#   换算到节点坐标 = x -6..+5、y -26..-7（脚底在原点上方 7px）。
#   以前直接夹地板矩形 (16,32)..(272,164)，于是角色左半边压进左墙 6px、
#   脚底踩到上墙 7px —— 看上去就是「能走到墙上」。现在按上面这个可见像素框内缩：
#     左 16+6=22 / 右 272-5=267 / 上 32+7=39（脚底正好贴地板沿）。
#   下边照旧 164 不动（离底墙还有 19px，本来就够）。
const ROOM_MIN := Vector2(22, 39)
const ROOM_MAX := Vector2(267, 164)

@onready var interior: Node2D = $Interior
@onready var room_art: Sprite2D = $Interior/RoomArt
@onready var door: Area2D = $Door
@onready var door_front: Marker2D = $DoorFront
@onready var exit_door: Area2D = $Interior/ExitDoor
@onready var bed: Area2D = $Interior/Bed
@onready var bed_body: StaticBody2D = $Interior/BedBody
@onready var furniture_body: StaticBody2D = $Interior/FurnitureBody
@onready var spawn_point: Marker2D = $Interior/SpawnPoint

var _player: Node2D = null
var _at_front_door := false
var _at_bed := false
var _at_exit := false
# 三处「走近了浮在半空的按键提示」。床和出口挂在 Interior 下 ——
# 室内默认整块隐藏，所以这两个提示天然只会在进屋之后才可能出现。
var _hint_front: Node2D = null
var _hint_bed: Node2D = null
var _hint_exit: Node2D = null

# 星露谷式「进屋后外界全黑」的黑幕：一块 2048² 深色多边形盖住整个世界视图，
# 屋内（Interior z=95）与玩家（进屋时临时提 z=97）画在幕布之上。
var _veil: Node2D = null
var _prev_player_z := 0
var _intro_done := false
var _rod_done := false            # e43: 第二天出门那段钓鱼剧情只走一次

# e31 光影：壁炉火光（e38c 屋前挂灯撤掉，只剩壁炉这一处动态光源）
var _fire_light: PointLight2D = null
var _fire_glow: Sprite2D = null
var _fire_audio: AudioStreamPlayer = null   # e54 炭火噼啪（进屋才响）

func _add_hint(parent: Node, key: String, word: String, height: float) -> Node2D:
	var n: Node2D = preload("res://scene/key_hint.gd").new()
	parent.add_child(n)
	n.setup(key, word, height)
	return n

func _ready() -> void:
	_build_room()

	# Interior 是和 Exterior 同一个 House 节点下的两个区域（Exterior 在上、Interior 往下
	# 挪了 400 像素）。如果默认就把 Interior 显示出来，地图下方会透出整间屋子的地板。
	# 所以一开始藏起来，等玩家进门再显。
	interior.visible = false

	interior.z_index = 95
	_build_veil()
	_build_fire_light()
	_build_fire_body()

	door.body_entered.connect(func(b): _set_flag(b, "front", true))
	door.body_exited.connect(func(b): _set_flag(b, "front", false))
	bed.body_entered.connect(func(b): _set_flag(b, "bed", true))
	bed.body_exited.connect(func(b): _set_flag(b, "bed", false))
	exit_door.body_entered.connect(func(b): _set_flag(b, "exit", true))
	exit_door.body_exited.connect(func(b): _set_flag(b, "exit", false))

	# 睡醒（换日）后把角色从床上挪回门口，免得卡在床里
	TimeManager.new_day.connect(_on_new_day)

	# e36e 门口提示抬到 -70：售货箱上移之后它的「F 售卖箱」提示飘在 y≈120，
	#   门提示原来也在 -46(≈122)，两个框会叠在一起，所以门这个往上让开一截。
	_hint_front = _add_hint(door, "F", "进屋", -70.0)
	_hint_bed = _add_hint(bed, "F", "睡觉", -26.0)
	_hint_exit = _add_hint(exit_door, "F", "出门", -34.0)
	# e36i: 左键点这三个框 = 按 F（走到哪一侧就只有哪一侧的框露着，点哪个进哪个）
	# ❗字符串写法: 三个 _hint_* 都声明成 Node2D, 写 .clicked 过不了静态检查
	_hint_front.connect("clicked", _do_interact)
	_hint_bed.connect("clicked", _do_interact)
	_hint_exit.connect("clicked", _do_interact)

func _set_flag(body: Node2D, which: String, on: bool) -> void:
	if not body.is_in_group("player"):
		return
	match which:
		"front":
			_at_front_door = on
			_toggle_hint(_hint_front, on)
		"bed":
			_at_bed = on
			_toggle_hint(_hint_bed, on)
		"exit":
			_at_exit = on
			_toggle_hint(_hint_exit, on)

func _toggle_hint(h: Node2D, on: bool) -> void:
	if h == null:
		return
	if on:
		h.show_hint()
	else:
		h.hide_hint()

# 室内时把玩家夹在房间里（地板范围内），不用给房间单独做一圈碰撞
func _physics_process(_delta: float) -> void:
	var p := _player_node()
	if p == null or not p.indoors:
		return
	var base := interior.global_position
	p.global_position = Vector2(
		clampf(p.global_position.x, base.x + ROOM_MIN.x, base.x + ROOM_MAX.x),
		clampf(p.global_position.y, base.y + ROOM_MIN.y, base.y + ROOM_MAX.y))

# ---------------- 室内：一次性画好整间屋子的木头材质 ----------------
# 黑幕中心钉在屋内房间中心，2048² 远超相机可视范围（1152x648）——
# 相机无论在门口还是床边都看不到幕布外的世界。
func _build_veil() -> void:
	_veil = Node2D.new()
	_veil.z_index = 90
	var poly := Polygon2D.new()
	var s := 2048.0
	poly.polygon = PackedVector2Array([
		Vector2(-s * 0.5, -s * 0.5), Vector2(s * 0.5, -s * 0.5),
		Vector2(s * 0.5, s * 0.5), Vector2(-s * 0.5, s * 0.5)])
	poly.color = Color8(12, 10, 14)
	# ❗黑幕不吃任何光源：不然屋里壁炉的火光会在幕布上糊出一圈暖边，
	#   看起来像"墙外还亮着"，屋外全黑这件事就破了。light_mask=0 = 不受任何 Light2D 影响。
	poly.light_mask = 0
	_veil.add_child(poly)
	_veil.position = interior.position + Vector2(ROOM_W, ROOM_H) * TS * 0.5
	add_child(_veil)
	_veil.visible = false

func _build_room() -> void:
	room_art.texture = _make_room_texture()
	room_art.centered = false
	room_art.position = Vector2.ZERO

# ---------------- e31 光影：室内壁炉火光 ----------------
# 室内唯一的动态光源。黑幕(z=90)在 _build_veil 里设了 light_mask=0，不吃这盏灯，
# 所以光池只落在屋里（地板/家具/玩家上），不会在黑幕上糊出一圈暖边。
# 亮度慢慢抖 = 火在烧，不是一盏死灯（比篝火慢、幅度也小，壁炉里是炭不是柴）。
func _build_fire_light() -> void:
	var fp: Sprite2D = interior.get_node_or_null("Decor/Fireplace") as Sprite2D
	# 炉口位置：壁炉贴图横向正中、纵向偏下（火是从炉膛里烧出来的）
	var at := Vector2(190, 26)
	if fp != null:
		at = fp.position + Vector2(fp.region_rect.size.x * 0.5, fp.region_rect.size.y * 0.62)
	_fire_light = LIGHT_UTIL.make_light(Color(1.0, 0.58, 0.26), 1.15, 1.7, 2.2)
	_fire_light.position = at
	interior.add_child(_fire_light)
	_fire_glow = LIGHT_UTIL.make_glow(Color(1.0, 0.55, 0.24, 0.20), 1.5, 2.2)
	_fire_glow.position = at
	interior.add_child(_fire_glow)
	var tw := create_tween().set_loops()
	tw.tween_property(_fire_light, "energy", 0.95, 0.55).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_fire_glow, "modulate:a", 0.15, 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_fire_light, "energy", 1.28, 0.7).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_fire_glow, "modulate:a", 0.26, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_fire_light, "energy", 1.05, 0.45).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_fire_glow, "modulate:a", 0.18, 0.45).set_trans(Tween.TRANS_SINE)

# e54 壁炉火本体：粒子火苗 + 淡烟 + 炭火噼啪声（光源还是上面那盏，别动）。
# 火苗/烟全程序化生成（跟 campfire.gd 同一套语言：屋里是炭火，比篝火小一号）。
func _build_fire_body() -> void:
	var fp: Sprite2D = interior.get_node_or_null("Decor/Fireplace") as Sprite2D
	var at := Vector2(190, 26)
	if fp != null:
		at = fp.position + Vector2(fp.region_rect.size.x * 0.5, fp.region_rect.size.y * 0.62)
	# 火苗：橙黄小点往上窜（比篝火少一点、矮一点）
	var flame := CPUParticles2D.new()
	flame.name = "FireFlame"
	flame.amount = 9
	flame.lifetime = 0.6
	flame.spread = 14.0
	flame.direction = Vector2(0, -1)
	flame.gravity = Vector2(0, -34)
	flame.initial_velocity_min = 6.0
	flame.initial_velocity_max = 16.0
	flame.scale_amount_min = 0.8
	flame.scale_amount_max = 1.8
	flame.color_ramp = _flame_ramp()
	flame.position = at + Vector2(0, -2)
	interior.add_child(flame)
	# 烟：灰白半透明慢飘，往炉膛上方走
	var smoke := CPUParticles2D.new()
	smoke.name = "FireSmoke"
	smoke.texture = _make_fire_dot()
	smoke.amount = 4
	smoke.lifetime = 2.0
	smoke.spread = 16.0
	smoke.direction = Vector2(0, -1)
	smoke.gravity = Vector2(0, -10)
	smoke.initial_velocity_min = 4.0
	smoke.initial_velocity_max = 8.0
	smoke.scale_amount_min = 1.2
	smoke.scale_amount_max = 2.4
	smoke.color = Color(0.82, 0.8, 0.78, 0.22)
	smoke.position = at + Vector2(0, -18)
	interior.add_child(smoke)
	# 炭火噼啪：低音量循环（播完接播），进屋才响 —— 播放与否由 _enter/_leave 控制
	_fire_audio = AudioStreamPlayer.new()
	_fire_audio.name = "FireAudio"
	_fire_audio.stream = preload("res://resources/audio/sfx/campfire.wav")
	_fire_audio.volume_db = -16.0
	_fire_audio.finished.connect(_fire_audio.play)
	interior.add_child(_fire_audio)

# 火苗颜色渐变：白黄 -> 橙 -> 红 -> 透明（campfire.gd 同款）
func _flame_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.set_color(1, Color(0.9, 0.25, 0.1, 0.0))
	g.add_point(0.35, Color(1.0, 0.62, 0.16, 0.95))
	g.add_point(0.7, Color(0.85, 0.3, 0.08, 0.5))
	return g

# 径向渐变小圆点（烟用；纯运行时生成不依赖图集）
func _make_fire_dot() -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			var d := Vector2(x - 5.5, y - 5.5).length() / 5.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

func _make_room_texture() -> ImageTexture:
	var w := ROOM_W * TS
	var h := ROOM_H * TS
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = ROOM_SEED

	# 1) 木墙：一块块竖着钉的木板（宽窄、深浅都有微差 + 顺纹细线）
	img.fill(WALL_COLOR)
	var x := 0
	while x < w:
		var bw: int = maxi(14, BOARD_W + rng.randi_range(-7, 9))
		bw = mini(bw, w - x)
		var tone := _tint(WALL_COLOR, rng.randf_range(-0.055, 0.065))
		img.fill_rect(Rect2i(x, 0, bw, h), tone)
		img.fill_rect(Rect2i(x, 0, 1, h), WALL_SEAM)              # 板缝
		img.fill_rect(Rect2i(x + 1, 0, 1, h), WALL_HI)            # 缝边高光
		for g in rng.randi_range(1, 2):                           # 顺纹的暗线
			var gx: int = x + rng.randi_range(4, maxi(4, bw - 4))
			var gy: int = rng.randi_range(0, h / 3)
			var gl: int = rng.randi_range(h / 3, h * 2 / 3)
			if gx < w - 1:
				img.fill_rect(Rect2i(gx, gy, 1, mini(gl, h - gy)), _tint(tone, -0.07))
		x += bw

	# 2) 木地板：横向铺长条木板。关键在于**每一块板的深浅都不一样**（同一行里相邻两块也不同），
	#    所以不会连成一条条横带；板上再拉几条顺纹的暗线。这是它像木头而不像砖的原因。
	img.fill_rect(FLOOR_RECT, FLOOR_COLOR)
	var y := FLOOR_RECT.position.y
	while y < FLOOR_RECT.end.y:
		var rh: int = mini(PLANK_H, FLOOR_RECT.end.y - y)
		var px := FLOOR_RECT.position.x
		while px < FLOOR_RECT.end.x:
			var pw: int = mini(rng.randi_range(92, 186), FLOOR_RECT.end.x - px)
			var tone := _tint(FLOOR_COLOR, rng.randf_range(-0.055, 0.065))
			img.fill_rect(Rect2i(px, y + 1, pw, maxi(1, rh - 1)), tone)
			for g in rng.randi_range(2, 3):                       # 顺纹暗线：长短位置都随机
				var gy: int = y + rng.randi_range(3, maxi(3, rh - 2))
				var gx: int = px + rng.randi_range(1, maxi(1, pw - 6))
				var gl: int = rng.randi_range(12, maxi(12, pw / 2))
				gl = mini(gl, px + pw - gx)
				if gl > 4:
					img.fill_rect(Rect2i(gx, gy, gl, 1), _tint(tone, -0.075))
			if px > FLOOR_RECT.position.x:                        # 端头缝
				img.fill_rect(Rect2i(px, y + 1, 1, maxi(1, rh - 1)), FLOOR_SEAM)
			px += pw
		# 横向板缝：只压一条 1px 暗线。
		# 这里**不要**再加一条亮高光 —— 每 16px 一道亮线会把地板切成一格一格，看着就是砖。
		img.fill_rect(Rect2i(FLOOR_RECT.position.x, y, FLOOR_RECT.size.x, 1), FLOOR_SEAM)
		y += PLANK_H

	# 3) 墙脚阴影：地板四周压深，房间轮廓清楚
	img.fill_rect(Rect2i(FLOOR_RECT.position.x, FLOOR_RECT.position.y - 2, FLOOR_RECT.size.x, 2), SHADOW_COLOR)
	img.fill_rect(Rect2i(FLOOR_RECT.position.x, FLOOR_RECT.end.y, FLOOR_RECT.size.x, 2), SHADOW_COLOR)
	img.fill_rect(Rect2i(FLOOR_RECT.position.x - 2, FLOOR_RECT.position.y - 2, 2, FLOOR_RECT.size.y + 4), SHADOW_COLOR)
	img.fill_rect(Rect2i(FLOOR_RECT.end.x, FLOOR_RECT.position.y - 2, 2, FLOOR_RECT.size.y + 4), SHADOW_COLOR)

	return ImageTexture.create_from_image(img)

# 只改明度、不动色相，用来给每块板一点随机深浅
func _tint(c: Color, amount: float) -> Color:
	return Color(clampf(c.r + amount, 0.0, 1.0), clampf(c.g + amount, 0.0, 1.0),
		clampf(c.b + amount, 0.0, 1.0), c.a)

# ---------------- 交互 ----------------
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	_do_interact()

# 进门 / 上床 / 出门 —— 按 F 和「左键点提示框」共用这一段（e36i）
func _do_interact() -> void:
	var p := _player_node()
	if p == null:
		return

	if _at_exit and p.indoors:
		_leave_house_fx(p)
		return
	if _at_front_door and not p.indoors:
		_enter_house_fx(p)
		return
	if _at_bed and p.indoors:
		if p.busy:
			return
		_open_sleep_menu(p)

# ---------------- d9: 进出屋衔接 ----------------
# 进门/出门是「瞬移 + 内饰显隐」, 裸眼看就是一帧跳变 —— 这里垫一个快速暗闪:
# 画面先压暗 (0.12s), 全黑那一瞬才真的挪人, 再亮回来 (0.2s)。
# 玩家按 F / 点门都走这; 自检直调 _enter_house/_leave_house 同步版, 不受影响。
func _enter_house_fx(p: Node2D) -> void:
	_door_wipe(func() -> void: _enter_house(p))

func _leave_house_fx(p: Node2D) -> void:
	_door_wipe(func() -> void: _leave_house(p))

func _door_wipe(do: Callable) -> void:
	var tree := get_tree()
	if tree == null or SaveManager.enabled == false:
		do.call()              # 自检/探针环境: 直接走同步路径
		return
	var cl := CanvasLayer.new()
	cl.layer = 120
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.02, 0.03, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	cl.add_child(rect)
	add_child(cl)
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, 0.12)
	tw.tween_callback(do)
	tw.tween_interval(0.06)
	tw.tween_property(rect, "modulate:a", 0.0, 0.2)
	tw.tween_callback(cl.queue_free)

func _enter_house(p: Node2D) -> void:
	p.global_position = spawn_point.global_position
	p.indoors = true
	interior.visible = true
	if _veil != null:
		_veil.visible = true
	_prev_player_z = p.z_index
	p.z_index = 97          # 提到黑幕(90)和屋内(95)之上
	_set_world_collision(p, false)
	# 床的实体碰撞只在屋里开（layer 2，玩家的 mask 常开这一层）。
	# ❗屋外必须关掉：室内那块地在世界坐标里是真实野地，开着会在野外留一堵隐形床墙。
	bed_body.collision_layer = 2
	furniture_body.collision_layer = 2   # e30u 家具同理
	if _fire_audio != null and not _fire_audio.playing:
		_fire_audio.play()               # e54 进屋才听得见炭火
	Audio.set_indoor(true)               # D3 屋里声音变闷
	_try_intro()

func _leave_house(p: Node2D) -> void:
	p.global_position = door_front.global_position
	p.indoors = false
	interior.visible = false
	if _veil != null:
		_veil.visible = false
	p.z_index = _prev_player_z
	_set_world_collision(p, true)
	bed_body.collision_layer = 0
	furniture_body.collision_layer = 0   # e30u
	if _fire_audio != null:
		_fire_audio.stop()
	Audio.set_indoor(false)              # D3 出屋恢复通透
	_try_rod_story()                     # e43: 第二天出门撞见哥布林钓鱼

# ---------------- e43: 第二天出门, 撞见哥布林在河边钓鱼 ----------------
# 开局他摊子上没有鱼竿 (shop_ui 那一行挂「未上架」)。第二天一出门: 先放一段
# 过场 (cutscenes.gd 的 goblin_rod), 再进对话, 聊完才立旗 goblin_rod —— 商店
# 那行鱼竿这时候才上架。flag 进 user://story_flags.cfg, 新档会被 flags_reset() 清掉。
const ROD_LINES := [
	{"name": "哥布林", "portrait": "goblin",
		"text": "哎哎哎, 别声张! 我就钓两条, 解解馋..."},
	{"name": "哥布林", "portrait": "goblin",
		"text": "想学也行. 摊子上那批竿子明天就给你摆上, 五十金一根, 够便宜了吧?"},
	{"name": "主角", "portrait": "player",
		"text": "成交. 以后钓上来的鱼, 也照顾你生意."},
]

func _try_rod_story() -> void:
	if _rod_done:
		return
	if TimeManager.day < 2:
		return                            # 头一天他还没露馅, 撞不上
	# ❗自检/探针 (SaveManager.enabled == false) 一律不触发: 这段是「过场 + 对话框」,
	#   塞进测试流程会把剧情对话框一直摊开着, 后面测对话的段落全被顶掉。
	if not SaveManager.enabled:
		return
	if preload("res://story_dialogue.gd").flag_get("goblin_rod"):
		_rod_done = true
		return
	_rod_done = true
	_play_rod_story()

func _play_rod_story() -> void:
	Cutscenes.play("goblin_rod")
	# ❗等过场收片再进对话: 不然字幕条和对话框叠在一起, 两边的暂停开关也会互相踩
	while Cutscenes.playing():
		await Cutscenes.finished
	var dlg := get_tree().get_first_node_in_group("story_dialogue")
	if dlg == null:
		_finish_rod_story()
		return
	dlg.play(ROD_LINES, _finish_rod_story)

func _finish_rod_story() -> void:
	preload("res://story_dialogue.gd").flag_set("goblin_rod")

# ---------------- 开局指引：第一次进屋，哥布林的「赠礼」 ----------------
# 开局身上一无所有：第一次进屋时哥布林隔空喊话（他人在岛东北角的摊位上），
# 说屋子借你住 + 送你一包家当。播完才记 flag / 发物资 / 销案 go_house ——
# 中途闪退的话 flag 没记上，下次进屋会重播一遍，物资不会丢。
const INTRO_LINES := [
	{"name": "哥布林", "portrait": "goblin",
		"text": "哦嚯嚯! 这屋子现在归你了, 别拘束, 就当自己家."},
	{"name": "哥布林", "portrait": "goblin",
		"text": "瞧你两手空空的样子... 床边那包家当拿去吧: 农具, 种子, 还有几颗土豆."},
	{"name": "哥布林", "portrait": "goblin",
		"text": "不过嘛... 天下没有白住的房子. 条件只有一个: 多在我这儿买东西, 照顾照顾我的生意!"},
	{"name": "主角", "portrait": "player",
		"text": "...成交."},
]

func _try_intro() -> void:
	if _intro_done:
		return
	if preload("res://story_dialogue.gd").flag_get("goblin_intro"):
		_intro_done = true
		return
	_intro_done = true
	var dlg := get_tree().get_first_node_in_group("story_dialogue")
	if dlg == null:
		_grant_and_finish()
		return
	dlg.play(INTRO_LINES, _grant_and_finish)

func _grant_and_finish() -> void:
	preload("res://story_dialogue.gd").flag_set("goblin_intro")
	_grant_intro_gifts()
	# 后续任务由 quests.gd 的链条自动挂: complete(go_house) -> buy_goblin
	Quests.complete("go_house")

# 开局物资改成哥布林对话后赠与：发件清单在 game.gd 的 _give_starting_items()，
# 这里只负责敲门，别另抄一份。
func _grant_intro_gifts() -> void:
	var game: Node = get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("_give_starting_items"):
		game._give_starting_items()

# ❗室内那间屋子挂在「房子下方 288 像素」处，那块地方在世界地图上是**真实存在的野地**
#   （可能压着水面/水井之类的碰撞体）。如果不把碰撞关掉，CharacterBody2D 的
#   move_and_slide 会把玩家从这些碰撞体里顶出去 —— 表现就是「睡醒后位置会莫名漂几像素」。
#   Area2D（门/床/出口）靠的是玩家的 collision_layer 而不是 mask，所以关 mask 不影响交互。
func _set_world_collision(p: Node2D, outside: bool) -> void:
	var body := p as CollisionObject2D
	if body != null:
		body.set_collision_mask_value(1, outside)

# 床边按 F: 弹「今晚怎么睡」的选择菜单（见 sleep_menu_ui.gd）;
# 万一菜单没挂上（异常情况）就直接睡到明天, 别卡死睡觉功能
func _open_sleep_menu(p: Node2D) -> void:
	var menu: Node = get_tree().get_first_node_in_group("sleep_menu")
	if menu == null:
		_sleep_next_day(p)
		return
	if menu.is_open():
		return
	menu.open_panel(p, self)

# 选项 1: 睡到明天。躺下 → 时针转到次日清晨 → go_to_bed 换日（game.gd 结算）
func _sleep_next_day(p: Node2D) -> void:
	_lie_down(p)
	var clock := get_tree().get_first_node_in_group("clock_anim")
	if clock != null:
		clock.play(TimeManager.hour + TimeManager.minute / 60.0,
			func() -> void: TimeManager.go_to_bed())
	else:
		TimeManager.go_to_bed()

# 选项 2: 小睡到今天的某个时刻（不换日）。躺下 → 时针转到目标点 →
# 把时间直接拨过去, 然后醒来站在床脚边 —— 想赶傍晚的篝火就睡到 18 点。
func _sleep_until(p: Node2D, hour: int) -> void:
	_lie_down(p)
	var wake := func() -> void:
		TimeManager.hour = hour
		TimeManager.minute = 0
		TimeManager.snap()   # e30h: 立刻广播一次 tick，时钟文字/昼夜色马上跟上 —— 不然醒来头几秒还显示早上
		p.end_tool_animation()
		p.global_position = bed.global_position + SLEEP_LAND + Vector2(0, 24)
	var clock := get_tree().get_first_node_in_group("clock_anim")
	if clock != null:
		clock.play(TimeManager.hour + TimeManager.minute / 60.0, wake, float(hour))
	else:
		wake.call()

# 躺上床: 落点对准枕头, 睡姿一直保持（不会播完 1 秒自己站起来）
func _lie_down(p: Node2D) -> void:
	# 先躺到床上（脑袋对准枕头），再播睡觉动作
	p.global_position = bed.global_position + SLEEP_LAND
	p.play_tool_animation("sleep", true)

func _on_new_day(_day: int) -> void:
	var p := _player_node()
	if p == null:
		return
	if p.indoors:
		# 起床：收掉睡姿，人就站在床脚边（不再挪回门口）
		p.end_tool_animation()
		p.global_position = bed.global_position + SLEEP_LAND + Vector2(0, 24)

# 读档还原用：只把「在不在屋里」的显示与碰撞状态摆好，不挪玩家位置。
# （_enter_house/_leave_house 是给玩家主动进出用的，会顺手改位置，读档不能用那两个。）
func set_indoors_visual(on: bool) -> void:
	interior.visible = on
	if _veil != null:
		_veil.visible = on
	bed_body.collision_layer = 2 if on else 0
	furniture_body.collision_layer = 2 if on else 0   # e30u
	var p := _player_node()
	if p != null:
		p.indoors = on
		p.z_index = 97 if on else _prev_player_z
		_set_world_collision(p, not on)
	Audio.set_indoor(on)                 # D3 读档还原屋里屋外的声音状态

func _player_node() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player
