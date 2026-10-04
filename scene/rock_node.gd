# scene/rock_node.gd —— 一块岩石 / 铁矿露头：贴图 + 碰撞 + 敲击晃动 / 碎裂动画
#
# ❗原点在**石头底部**（不是格子中心）：父节点开了 y_sort，排序点落在底部，
#   角色走到石头后面就被挡住、走到前面就挡住石头 —— 跟树/房子一个道理。
extends Node2D

# 素材：Ground stones.png 128x48 —— 每 32 宽一列、每列纵摆 5 种石头；
# 横向 4 列 = 藤叶变体(x0-32) / 素面变体(x32-64) / 白影版(x64-128)。
const ROCK_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Props/Spring/Ground stones.png"
# 铁矿露头：Bars and ores.png 256x64 = 16x16 小格铺成的图标表，矿石那一行 16x16
const ORE_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Bars and ores.png"
const ORE_FRAME := 3            # 图标表第 3 格（48,0 起 16x16）

# 变体表：r = 源图裁剪窗（连通域精确包围盒，1:1 不缩放）；cw/ch = 碰撞宽高（盖住石头底部）
const VARIANTS := [
	{"r": Rect2i(37, 32, 22, 16), "cw": 18.0, "ch": 9.0},   # 素面三石堆（主打）
	{"r": Rect2i(5, 32, 22, 16), "cw": 18.0, "ch": 9.0},    # 藤叶三石堆
	{"r": Rect2i(1, 4, 15, 12), "cw": 13.0, "ch": 7.0},     # 独圆石
	{"r": Rect2i(18, 2, 14, 14), "cw": 12.0, "ch": 8.0},    # 双石柱
]

# 石屑：灰色芯 + 一圈黑描边（5x5）
const CHIP_CORE := Color8(150, 148, 142)
const CHIP_EDGE := Color8(24, 20, 18)
const CHIP_AMOUNT := 10
const CHIP_LIFETIME := 1.0

# 所有岩石共用同一张石屑贴图（静态缓存，别每块都画一张）
static var _chip_tex: ImageTexture = null

var cell := Vector2i.ZERO        # 所在格子
var kind := 0                    # 0 普通岩石 / 1 铁矿露头（OreVein.KIND_*）
var variant := 0                 # 岩石样子（VARIANTS 表下标）

var _spr: Sprite2D = null
var _ore_spr: Sprite2D = null
var _tw: Tween = null

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	add_child(_spr)
	apply_look()
	# e33 石头脚下的影子（宽度跟变体的碰撞宽走）
	var rvsh: Dictionary = VARIANTS[variant % VARIANTS.size()]
	add_child(preload("res://scene/shadow_util.gd").make_shadow(float(rvsh["cw"]) + 6.0, 7.0, 0.26))

	# 石头碰撞：跟树干一样用 layer 3（值 4）—— 只有玩家的 mask 里有这一层，
	# 伙伴（奴隶）会直接穿过去，免得它们去地里干活时被石头卡住。
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	# 碰撞按变体尺寸：盖住石头底部，顶上留给 y_sort 藏身
	var rv: Dictionary = VARIANTS[variant % VARIANTS.size()]
	var chw: float = rv["cw"]
	var chh: float = rv["ch"]
	sh.size = Vector2(chw, chh)
	cs.shape = sh
	cs.position = Vector2(0, -chh / 2.0)
	body.add_child(cs)
	add_child(body)

# 摆好贴图。铁矿露头 = 岩石 + 表面叠 2 块矿石
func apply_look() -> void:
	if _spr == null:
		return
	var vv: Dictionary = VARIANTS[variant % VARIANTS.size()]
	var r: Rect2i = vv["r"]
	var vw := float(r.size.x)
	var vh := float(r.size.y)
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var rock_base := SoftRes.tex(ROCK_SHEET)
	var at := AtlasTexture.new()
	at.atlas = rock_base      # 缺失时为 null, 石头留空但碰撞照常
	# 按变体裁剪窗 1:1 取图（不缩放），底边对齐原点、水平居中
	at.region = r
	_spr.texture = at
	_spr.position = Vector2(-vw / 2.0, -vh)
	if rock_base == null:
		push_warning("[素材] 岩石贴图缺失, 已留空")
	if kind == 1 and _ore_spr == null:
		_ore_spr = Sprite2D.new()
		_ore_spr.centered = false
		_ore_spr.scale = Vector2(0.5, 0.5)   # 矿石图标缩半，别比小石头还大
		# 第三方素材不入库(见 README), 缺失时留空不崩
		var ore_base := SoftRes.tex(ORE_SHEET)
		var ot := AtlasTexture.new()
		ot.atlas = ore_base      # 缺失时为 null, 矿石标记留空
		ot.region = Rect2(ORE_FRAME * 16, 0, 16, 16)
		_ore_spr.texture = ot
		if ore_base == null:
			push_warning("[素材] 矿石贴图缺失, 已留空")
		# 两块矿石错开摆在石头面上（视觉上能一眼看出这石头有矿）
		_ore_spr.position = Vector2(-4.0, -vh + 4.0)
		add_child(_ore_spr)

# 敲中了但没碎：石头晃两下 + 崩几点石屑
func shake() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	var rr: Rect2i = VARIANTS[variant % VARIANTS.size()]["r"]
	var spr_x := -float(rr.size.x) / 2.0
	var ore_x := -4.0
	_spr.position.x = spr_x
	if _ore_spr != null:
		_ore_spr.position.x = ore_x
	_tw = create_tween()
	for i in 3:
		var dx := 1.5 if i % 2 == 0 else -1.5
		_tw.tween_property(_spr, "position:x", spr_x + dx, 0.045)
		if _ore_spr != null:
			_tw.parallel().tween_property(_ore_spr, "position:x", ore_x + dx, 0.045)
	_tw.tween_property(_spr, "position:x", spr_x, 0.045)
	if _ore_spr != null:
		_tw.parallel().tween_property(_ore_spr, "position:x", ore_x, 0.045)

# 石屑贴图：5x5，一圈黑描边包着灰色的芯
func _chip_texture() -> Texture2D:
	if _chip_tex == null:
		var img := Image.create_empty(5, 5, false, Image.FORMAT_RGBA8)
		for y in 5:
			for x in 5:
				var edge := x == 0 or y == 0 or x == 4 or y == 4
				img.set_pixel(x, y, CHIP_EDGE if edge else CHIP_CORE)
		_chip_tex = ImageTexture.create_from_image(img)
	return _chip_tex

# 敲中了：石头上方崩出一把石屑，带重力掉下来
func chip_burst() -> void:
	var p := CPUParticles2D.new()
	p.amount = CHIP_AMOUNT
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = CHIP_LIFETIME
	p.spread = 55.0
	p.direction = Vector2(0, -1)
	p.gravity = Vector2(0, 260)          # 石屑比木屑沉，掉得快一点
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 85.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.8
	p.texture = _chip_texture()
	p.position = Vector2(0, -8)          # 石头中部（三石堆高 16）
	add_child(p)
	p.emitting = true
	get_tree().create_timer(CHIP_LIFETIME + 0.6).timeout.connect(p.queue_free)

# 碎掉了：原地小跳 + 淡出（掉落由 game 那边办）
func play_broken() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	chip_burst()
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 4.0, 0.09)
	tw.tween_property(self, "position:y", y0, 0.11)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)
	_tw = tw
