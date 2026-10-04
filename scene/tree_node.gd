# scene/tree_node.gd —— 一棵树：阶段贴图 + 树干碰撞 + 摇晃 / 倒下动画
#
# ❗原点在**树干底部**（不是格子中心）：父节点开了 y_sort，排序点落在脚下，
#   角色走到树后面就被树冠挡住、走到前面就挡住树 —— 跟房子/水井一个道理。
#   倒下动画也是绕这个点转 90 度，树才是「从根部倒」而不是「凭空飘着转」。
extends Node2D

signal fell_done(cell: Vector2i)      # 倒下动画播完了（game 那边补树桩节点）

# 素材：果树生长图，一帧 32x48，横着排了「种子 / 幼苗 / 小树 / 成树 / 开花 / 结果 / … / 树桩」
const SHEETS := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Cherry Tree.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Apricot Tree.png",
]
# 每种树在图集里的帧号（键 = Trees 的阶段常量值）
#   樱桃：幼苗 1 / 小树 2 / 成树 6（绿的那棵）/ 树桩 10
#   杏树：幼苗 1 / 小树 2 / 成树 3 / 树桩 9
const STAGE_FRAMES := [
	{0: 1, 1: 2, 2: 6, 3: 10},
	{0: 1, 1: 2, 2: 3, 3: 9},
]
# 砍树时崩出来的叶子颜色（跟树种对应）
const LEAF_COLORS := [Color(0.42, 0.68, 0.34), Color(0.38, 0.62, 0.30)]
# 木屑：木头色 + 一圈黑描边（5x5，最外一圈是黑的）
const CHIP_CORE := Color8(214, 168, 120)
const CHIP_EDGE := Color8(24, 16, 14)
const CHIP_AMOUNT := 12
const CHIP_LIFETIME := 1.1

# 所有树共用同一张木屑贴图（静态缓存，别每棵树都画一张）
static var _chip_tex: ImageTexture = null

const FRAME_W := 32
const FRAME_H := 48
const TRUNK_BASE_Y := 45.0      # 素材帧里树干底部所在的行 —— 对齐到节点原点上

var cell := Vector2i.ZERO        # 所在格子
var variant := 0                 # 树种（0 樱桃 / 1 杏树）
var stage := -1                  # 当前阶段（Trees.ST_*）

var _spr: Sprite2D = null
var _cs: CollisionShape2D = null
var _tw: Tween = null
var _shadow: Sprite2D = null   # e33 树脚下的影子（随阶段缩放）
var _anim_lock := false        # 摇晃/倒下动画接管期间, 风摆让位
var _wind_t := -1.0            # 风摆相位（<0 = 还没初始化, _process 里按格子错开）
var _sheet_warned := false     # 第三方树贴图缺失只警告一次, 不重复刷

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-FRAME_W / 2.0, -TRUNK_BASE_Y)
	add_child(_spr)
	# e33 树脚下的影子：树不再像贴纸
	_shadow = preload("res://scene/shadow_util.gd").make_shadow(20, 8, 0.30)
	add_child(_shadow)

	# 树干碰撞：只有薄薄一条。
	# ❗用的是 layer 3（值 4）—— 只有玩家的 mask 里有这一层，伙伴（奴隶）会直接穿过去，
	#   免得它们去地里干活时被一棵树卡住一整天。
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	_cs = CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(8, 6)
	_cs.shape = sh
	_cs.position = Vector2(0, -3)
	body.add_child(_cs)
	add_child(body)

	if stage < 0:
		stage = Trees.ST_MATURE
	apply_stage(stage)

# 换阶段：改图集里的帧号，顺带收一收碰撞（幼苗/树桩小一点）
func apply_stage(s: int) -> void:
	stage = s
	if _spr == null:
		return
	var frames: Dictionary = STAGE_FRAMES[clampi(variant, 0, STAGE_FRAMES.size() - 1)]
	var f: int = int(frames.get(s, frames.get(2, 3)))
	var at := AtlasTexture.new()
	# 第三方素材不入库(见 README), 缺失时留空不崩
	at.atlas = SoftRes.tex(SHEETS[clampi(variant, 0, SHEETS.size() - 1)])
	if at.atlas == null and not _sheet_warned:
		_sheet_warned = true
		push_warning("[素材] 果树贴图缺失, 已留空")
	at.region = Rect2(f * FRAME_W, 0, FRAME_W, FRAME_H)
	_spr.texture = at
	# 外观微调: 同种树也各有各的样子 —— 翻面 + 明暗色温按格子哈希微调,
	# 打破「整片树林一棵脸」的平铺感（不改贴图, 只动绘制参数; 影子/叶子粒子不受影响）。
	var h := absi(cell.x * 92837111 + cell.y * 689287499)
	_spr.flip_h = h % 2 == 0
	var shade := 0.93 + float(h % 7) / 7.0 * 0.12      # 0.93 ~ 1.05
	var warm := float((h / 7) % 3) - 1.0               # -1 / 0 / 1 轻微色温偏移
	_spr.modulate = Color(shade + warm * 0.02, shade, shade - warm * 0.02, 1.0)
	if _cs != null:
		_cs.shape.size = Vector2(8, 6) if s >= Trees.ST_YOUNG else Vector2(6, 4)
	# e33 影子跟阶段走：幼苗/树桩一小团, 长大了才撑得起一大片
	if _shadow != null:
		var k := 0.55 if (s == Trees.ST_SAPLING or s == Trees.ST_STUMP) else 1.0
		_shadow.scale = Vector2(k, k)

# e33 树梢风摆：树冠随时间轻轻左右晃（正弦拨 _spr.position.x 一两个像素）,
# 每棵树相位错开、风雨天摆得更凶。摇晃/倒下动画接管期间（_anim_lock）让位。
func _process(delta: float) -> void:
	if _spr == null or _anim_lock:
		return
	if stage != Trees.ST_YOUNG and stage != Trees.ST_MATURE:
		return
	if _wind_t < 0.0:
		_wind_t = float(absi(cell.x * 73 + cell.y * 151) % 628) * 0.01
	_wind_t += delta
	var amp := 1.2
	if Weather.is_storm() or Weather.is_rain():
		amp = 2.4
	_spr.position.x = -FRAME_W / 2.0 + sin(_wind_t * 1.3) * amp

# 砍中了但没倒：树晃两下 + 崩几片叶子
func shake() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_anim_lock = true
	_spr.position.x = -FRAME_W / 2.0
	_tw = create_tween()
	for i in 3:
		_tw.tween_property(_spr, "position:x",
			-FRAME_W / 2.0 + (2.0 if i % 2 == 0 else -2.0), 0.045)
	_tw.tween_property(_spr, "position:x", -FRAME_W / 2.0, 0.045)
	_tw.tween_callback(func(): _anim_lock = false)

# 木屑贴图：5x5，一圈黑描边包着木头色的芯（粒子每个都是一小块带描边的木屑）
func _chip_texture() -> Texture2D:
	if _chip_tex == null:
		var img := Image.create_empty(5, 5, false, Image.FORMAT_RGBA8)
		for y in 5:
			for x in 5:
				var edge := x == 0 or y == 0 or x == 4 or y == 4
				img.set_pixel(x, y, CHIP_EDGE if edge else CHIP_CORE)
		_chip_tex = ImageTexture.create_from_image(img)
	return _chip_tex

# 砍中了：树冠上方崩出一把木屑，带重力掉下来（每粒都带黑描边）
func chip_burst(big := false) -> void:
	var p := CPUParticles2D.new()
	p.amount = CHIP_AMOUNT * (2 if big else 1)
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = CHIP_LIFETIME
	p.spread = 55.0
	p.direction = Vector2(0, -1)
	p.gravity = Vector2(0, 230)          # ❗重力向下：木屑先窜上去再掉下来
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.texture = _chip_texture()
	p.position = Vector2(0, -36)         # 树冠上方
	add_child(p)
	p.emitting = true
	get_tree().create_timer(CHIP_LIFETIME + 0.6).timeout.connect(p.queue_free)

func leaf_burst() -> void:
	var p := CPUParticles2D.new()
	p.amount = 10
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.55
	p.spread = 70.0
	p.gravity = Vector2(0, 90)
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = LEAF_COLORS[clampi(variant, 0, LEAF_COLORS.size() - 1)]
	p.position = Vector2(0, -30)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

# 倒下：先抖几下 -> 绕树干底（节点原点）转 90° 砸地 -> 弹一下 -> 淡出 -> 通知 game 补树桩
func play_fell() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	chip_burst(true)          # 倒下的那一下木屑翻倍
	leaf_burst()              # 再飘几片叶子
	var dir := 1.0 if randf() < 0.5 else -1.0
	var x0 := position.x
	var tw := create_tween()
	tw.tween_property(self, "position:x", x0 + dir * 2.0, 0.06)
	tw.tween_property(self, "position:x", x0 - dir * 2.0, 0.06)
	tw.tween_property(self, "position:x", x0, 0.05)
	tw.tween_property(self, "rotation", dir * PI * 0.5, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation", dir * (PI * 0.5 - 0.1), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		fell_done.emit(cell)
		queue_free())
	_tw = tw

# 幼苗被刨走 / 树桩被敲碎：原地小跳一下淡出（不是倒下）
func play_pop() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 5.0, 0.1)
	tw.tween_property(self, "position:y", y0, 0.12)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.22)
	tw.tween_callback(queue_free)
	_tw = tw
