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

const ON_HOUR := 18.5      # 天擦黑就点灯
const OFF_HOUR := 6.5      # 天亮了熄灯

var cell := Vector2i.ZERO     # 所在格子
var kind := "lamp"            # Structures.KIND_LAMP
var is_ghost := false         # 建造模式的半透明预览：不建碰撞、不带光源

var _art: Sprite2D = null
var _light: PointLight2D = null
var _glow: Sprite2D = null
var _lit := false
var _gap := 0.0                 # 素材底部透明留白（贴地修正, 见 SoftRes.bottom_gap）
var _flick_t := 0.0             # 灯焰抖动时钟（点亮那刻随机相位, 多盏灯错开）
const LIGHT_ENERGY := 1.15      # e36e 定的光斑亮度, 抖动围绕这个值呼吸

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

	# 灯下那圈暖光。e36e 定下来的亮度：光斑 128*1.15≈147，只在灯下留一圈亮，
	# 走出去就暗下来 —— 路灯是一片而不是一盏大灯。
	_light = preload("res://scene/light_util.gd").make_light(Color(1.0, 0.72, 0.40), 0.9, 1.15, 2.2)
	_light.position = Vector2(0, -27)      # 光心抬到灯头那两盏上
	_light.enabled = false
	add_child(_light)
	_glow = preload("res://scene/light_util.gd").make_glow(Color(1.0, 0.74, 0.42, 0.16), 1.3, 2.2)
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

# 天黑点灯 / 天亮熄灯（force=true 时立刻切，刚放下那一下用）
func _sync_lamp(force: bool) -> void:
	var h := TimeManager.hour + TimeManager.minute / 60.0
	var want := h >= ON_HOUR or h < OFF_HOUR
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
			_glow.modulate.a = f

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