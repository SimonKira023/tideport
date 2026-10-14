# scene/lamp_node.gd —— 建造系统摆出来的「路灯」
#
# e38c/e38d：原来屋门口那盏挂灯撤掉了（它立在门边、正好压在售货箱的落脚点上，
# 俯瞰下去像从箱子里长出一盏灯笼）。路灯改成**可建造的建筑**：材料少、不用人工，
# 钱料付清当场就立起来（见 structures.gd 的 start_site 里 labor<=0 那条即时分支）。
#
# 跟 well_node 一个套路：原点在**灯座底部**（父节点开了 y_sort，排序点落在底部），
# 角色走到灯后面被挡住、走到前面挡住灯。
# 素材 Street Lamp.png 一图两态：左半边 = 灯头没点（灰玻璃），右半边 = 点着（暖黄）。
extends Node2D

const TEX := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Street Lamp.png"
const RECT_OFF := Rect2(4, 1, 25, 37)      # 图集左半边：没点
const RECT_LIT := Rect2(36, 1, 25, 37)     # 图集右半边：点着

const IMG_W := 25.0
const IMG_H := 37.0

# 点灯/熄灯的"时辰"不在这里写死 —— 统一走 light_util.glow_hour_now()（读 time_manager.gd
# 的 TONE_ADVANCE）。路灯/窗火/招牌/栈桥灯/船舷灯必须是同一刻亮，各写各的迟早会错开。

var cell := Vector2i.ZERO     # 所在格子
var kind := "lamp"            # Structures.KIND_LAMP
var is_ghost := false         # 建造模式的半透明预览：不建碰撞、不带光源

var _art: Sprite2D = null
var _light: PointLight2D = null
var _glow: Sprite2D = null
var _lit := false
var _gap := 0.0                 # 素材底部透明留白（贴地修正, 见 SoftRes.bottom_gap）
var _flick_t := 0.0             # 灯焰抖动时钟（点亮那刻随机相位, 多盏灯错开）
# e36e 定的光斑亮度。2026-10-06 从 1.3 收到 1.15：这一轮把后处理泛光推强了，
# 亮点数量也多了几十个 —— 单盏真灯再那么亮，bloom 会把灯芯顶成一片死白（"过曝"），
# 反而看不出是灯。夜里的暖是靠"很多小暖点 + 泛光连成片"，不是靠单盏灯更亮。
const LIGHT_ENERGY := 1.15
# 灯下那圈可见柔光的基准透明度。❗必须留成常量：_process 里的抖动是**围绕**它呼吸，
# 早先写成 `_glow.modulate.a = f`（f ≈ 1.0）等于把 0.22 直接顶成满不透明 ——
# 加法混合下这就是一坨死黄的圆盘，夜景探针一照就现形（2026-10-06 修）。
const GLOW_ALPHA := 0.14   # e90: HDR 2D 后加法柔光被 bloom 放大, 0.22 -> 0.14
# e89 水面拉丝的基准透明度（同 GLOW_ALPHA 的道理: 呼吸围绕它, 不顶满）
const STREAK_ALPHA := 0.26

var _streak: Sprite2D = null   # 灯光在水面上的竖直反光（加法柔光, 灯下 3 格内有水才有）
var _streak_t := 0.0           # 拉丝随波呼吸的时钟

func _ready() -> void:
	_art = Sprite2D.new()
	_art.centered = false
	# 第三方素材不入库(见 README), 缺失时留空不崩
	# （仍要建 AtlasTexture: _sync_lamp 每次取 _art.texture 改 region, 不能是 null）
	var lamp_base := SoftRes.tex(TEX)
	# 素材帧底部有透明留白（实测 Street Lamp.png 灯座偏上），按非透明像素底边下移贴地
	_gap = float(SoftRes.bottom_gap(lamp_base, RECT_OFF))
	_art.position = Vector2(-IMG_W / 2.0, -IMG_H + _gap)
	var at := AtlasTexture.new()
	at.atlas = lamp_base      # 缺失时为 null, 灯留空但昼夜切换照常
	at.region = RECT_OFF
	_art.texture = at
	add_child(_art)
	if lamp_base == null:
		push_warning("[素材] 路灯贴图缺失, 已留空")

	if is_ghost:
		return                 # 预览只是张图，不亮、不挡路

	add_child(preload("res://scene/shadow_util.gd").make_shadow(20, 7, 0.22))

	# q1 光影追踪：灯柱当遮挡体。❗只放光心 (0,-27) 以下（y=-24 起往下）——
	#   遮挡体若包住光心，整盏灯会把自己罩黑全场。
	add_child(preload("res://scene/light_util.gd").occluder_rect(Rect2(-2.5, -24, 5, 24)))

	# 灯下那圈暖光。e36e 定下来的亮度：光斑 128*1.15≈147，只在灯下留一圈亮，
	# 走出去就暗下来 —— 路灯是一片而不是一盏大灯。
	_light = preload("res://scene/light_util.gd").make_light(Color(1.0, 0.72, 0.40), 0.9, LIGHT_ENERGY, 2.2)
	_light.position = Vector2(0, -27)      # 光心抬到灯头那两盏上
	_light.enabled = false
	add_child(_light)
	_glow = preload("res://scene/light_util.gd").make_glow(Color(1.0, 0.74, 0.42, GLOW_ALPHA), 2.0, 1.7)
	_glow.position = _light.position
	_glow.visible = false
	add_child(_glow)

	# 灯柱的碰撞：一条贴底的矮矩形；layer 4 只有玩家的 mask 里有，伙伴穿过去免得被卡住
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(10, 8)
	cs.shape = sh
	cs.position = Vector2(0, -4)
	body.add_child(cs)
	add_child(body)

	_sync_lamp(true)
	_build_streak()

# 天黑点灯 / 天亮熄灯（force=true 时立刻切，刚放下那一下用）
func _sync_lamp(force: bool) -> void:
	# 跟着「色调钟」走: 昼夜色提前两小时, 路灯也提前点/熄, 免得天色已暮灯还黑着
	var want := preload("res://scene/light_util.gd").glow_hour_now()
	if want == _lit and not force:
		return
	_lit = want
	if _art != null:
		var at: AtlasTexture = _art.texture
		at.region = RECT_LIT if want else RECT_OFF
	if _light != null:
		_light.enabled = want
		if want:
			_flick_t = randf() * 10.0   # 点亮那刻随机相位, 一排灯不会齐刷刷同呼吸
	if _glow != null:
		_glow.visible = want

# e89 水面灯光拉丝（TLN 计划 B）：灯在岸边时，灯光往水面拖一道竖直的暖色反光。
#   只用加法柔光（成本≈0），随波微微呼吸 —— 灯下有水才画，不是每盏灯都拖。
func _build_streak() -> void:
	var g := get_parent()
	if g == null or not g.has_method("is_water"):
		return
	for i in range(1, 4):                       # 往下最多扫 3 格, 找最近的水
		var c: Vector2i = cell + Vector2i(0, i)
		if not g.call("is_water", c):
			continue
		var lu := preload("res://scene/light_util.gd")
		_streak = lu.make_glow(Color(1.0, 0.72, 0.40, STREAK_ALPHA), 1.0, 2.4)
		_streak.scale = Vector2(0.9, 4.6)       # 纵向拉长 = 水里的倒影
		_streak.position = Vector2(0, i * 32.0 - 14.0)
		_streak.visible = false
		add_child(_streak)
		_streak_t = randf() * 6.0               # 相位错开, 一排灯不同步呼吸
		return

# 每帧问一次天色（只在跨过 18:30 / 6:30 那一瞬间真的切，平时一句话就返回）
func _process(_delta: float) -> void:
	if is_ghost:
		return
	_sync_lamp(false)
	# 灯焰抖动（参照篝火）: 两个不可通约的正弦叠出无规律的小幅呼吸, 熄灯不抖
	if _lit and _light != null:
		_flick_t += _delta
		var f := 1.0 + 0.05 * sin(_flick_t * 7.3) + 0.035 * sin(_flick_t * 13.1 + 1.7)
		_light.energy = LIGHT_ENERGY * f
		if _glow != null:
			_glow.modulate.a = GLOW_ALPHA * f   # 围绕基准呼吸, 别顶成满不透明（过曝）
	# 拉丝随波呼吸: 只在灯亮着、且真的扫到水面时有
	if _streak != null:
		_streak.visible = _lit
		if _lit:
			_streak_t += _delta
			var w := 0.8 + 0.2 * sin(_streak_t * 2.1) + 0.08 * sin(_streak_t * 5.3 + 0.9)
			_streak.modulate.a = STREAK_ALPHA * w
			_streak.scale.y = 4.6 + 0.5 * sin(_streak_t * 1.7 + 2.0)

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-IMG_W / 2.0, -IMG_H + _gap - 2.0), Vector2(IMG_W, IMG_H + 4.0))

# 被镐子拆掉：小跳 + 淡出（材料返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)