# slave_npc.gd —— 白天的「伙伴（奴隶）」
#
# 他们白天真的在农场里干活，不是站着摆样子：
#   夜里派了活（涂色的那些格子）→ 白天走过去 → 挥锄头/浇水/播种 → 那一格真的变了
#   （耕地会长出耕地贴图、浇过水的变湿土、播下去的会冒苗 —— 全是 Farm 那套信号在管）
#
# 一个伙伴的行动循环：
#   LOITER(闲逛) ──有活──> GO_WORK(走过去) ──> WORK(干活动画) ──> REST(喘口气) ──> 再挑活
#   没活了就回到 LOITER，从「涂过色的格子」里随机挑落点 —— 挑的是格子而不是随机坐标，
#   所以涂得密的地方被挑中的概率天然就高，人群自动聚过去。
#
# e30s 岗位（派活页六大板块的另外五块）：
#   被派去矿井/工地/铁匠铺/研究的人白天**不下地浇水**，各自走到岗位上干自己的活
#   （抡镐 / 铲土 / 抡锤 / 站门口钻研），见 POST 状态与 _post_of。
#   ❗「远航出征」不算岗位：那份名单是「下次出海带谁」，人平时还在岛上过日子，
#     真出海那天由 game.gd 的 board_to 接手（走上船 -> 藏起来）。
#
# ❗活儿干完会在 Slaves.done_today 上打个勾（今天不再碰这一格）。
#   assignments（计划）不删 —— 夜里那张涂色地图还要原样显示，方便复看和复涂。
#
# 模型：四个「不是主角」的预制角色轮流当班（主角是 Josh，伙伴换人演，一眼能分清）。
# ❗节点原点在**脚下**（精灵画在原点上方 16 像素）—— 跟主角、水井、房子一个约定，
#   这样挂在 Game 下才能跟它们一起做 y_sort 前后遮挡。
extends Node2D

enum State { LOITER, GO_WORK, WORK, REST, BOARD, POST }

const STEP_MOVING := 0
const STEP_ARRIVED := 1
const STEP_BLOCKED := 2       # 前头是水，这一趟走不通

const CELL := 32              # 一帧 32x32
const ARRIVE_DIST := 2.5
const BLOCK_TIME := 8.0       # 这格暂时干不了（比如还没耕地/没种子），隔这么久再回来试
const HIT_RATIO := 0.55       # 动画播到 55% 时「落下去」—— 视觉上正在使劲那一下

# 四个「不是主角」的预制角色
const MODELS := ["Alex", "Lyria", "Manu", "Tori"]
# 每个模型的性别（跟 MODELS 一一对应, 素材包里的真实长相）:
#   Alex=男(橙金短发) / Lyria=女(棕红卷发) / Manu=女(深肤黑发白帽) / Tori=女(橙红长发)。
# 招募名字池（slaves.gd）和头像分组（tools/make_portraits.gd）都按这张表对齐。
const MODEL_MALE := [true, false, false, false]
const MODEL_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/%s"

# 每种动作一张图：32px 一帧、一行一个朝向（行 0 朝下 / 1 朝上 / 2 侧面，左右靠 flip_h）
const SHEETS := {
	"idle":   {"file": "Idle.png",     "frames": 4, "fps": 7.0,  "loop": true},
	# walk 的 fps 只是个初值：真正跑起来由 _sync_walk_speed 按 speed 反推
	"walk":   {"file": "Walk.png",     "frames": 6, "fps": 10.0, "loop": true},
	"hoe":    {"file": "Hoe.png",      "frames": 6, "fps": 13.0, "loop": false},
	"water":  {"file": "Watering.png", "frames": 8, "fps": 13.0, "loop": false},
	"sickle": {"file": "Sickle.png",   "frames": 6, "fps": 13.0, "loop": false},
	# e30s 岗位动作：循环播（人整天待在岗位上，动作不能播一遍就僵住）
	"pickaxe": {"file": "Pickaxe.png", "frames": 6, "fps": 10.0, "loop": true},
	"shovel":  {"file": "Shovel.png",  "frames": 5, "fps": 9.0,  "loop": true},
	"axe":     {"file": "Axe.png",     "frames": 6, "fps": 10.0, "loop": true},
}
const DIR_ROW := {"down": 0, "up": 1, "side": 2}

# 工种 -> 干活用哪套动作。数字跟 slaves.gd 的 TASK_* 一一对应：
# 那边是 autoload 里的常量，const 表达式取不到，所以在这儿写死，由自检对账。
const T_TILL := 1
const T_WATER := 2
const T_PLANT := 3
const TASK_ANIM := {T_TILL: &"hoe", T_WATER: &"water", T_PLANT: &"sickle"}
# （播种扣种子 / 睡前补完的真正逻辑在 slaves.gd apply_task，这里只管演。）

# e30s 岗位 -> 干活动作 / 站定朝向。
# 「科研」没有书桌类素材，用待机代替（人站在家门口钻研，重点是「不去地里浇水」）。
const POST_ANIM := {
	"mine": &"pickaxe",
	"dock": &"shovel",
	"smith": &"axe",
	"research": &"idle",
}
const POST_FACING := {
	"mine": &"up",        # 面朝矿门
	"dock": &"down",
	"smith": &"down",
	"research": &"down",
}
# 岗位干活的音效间隔与音量（比下地干活轻一点：好几个人一起抡会吵）
const POST_SFX_DB := -18.0
const POST_SFX_GAP := Vector2(0.9, 1.6)

# —— e29c: 伙伴局部改色配方（RECIPES[i] = 第 i 个伙伴的色带清单）——
# 用户要求: 伙伴长相各不一样, 但**只改局部**(发色/服装的色相带), 不做整体染色 ——
# 整体 modulate 连皮肤眼睛一起染, 很怪。改色发生在贴图 Image 层:
# 色带内像素的色相平移到目标色, 高光/阴影的明度按倍率缩放(层次保留),
# 色带外的皮肤/眼睛/轮廓线一概不碰。
# ❗「第 i 个伙伴长什么样」唯一真相源的一部分: 白天实体、篝火边的人、背包卡片墙、
#   战场小兵、船员 —— 全部贴图都走 sheet_texture()/recipe_for() 同一套。
# 色带依据 4 个模型图集的实采样色相分布(probe_model_colors 探针):
#   Alex: 橙金发 hue[0.00,0.15] 饱和≥0.40 / 蓝背带裤 hue[0.56,0.68] 饱和≥0.35
#         (浅青内衬、皮肤饱和度低被 smin 挡住; 蓝眼睛 hue 0.526 被 0.56 下限挡住)
#   Lyria: 棕红发 hue[0.02,0.10] 饱和≥0.45 / 红裙 hue[0.88,1.00]
#   Manu: 黑发+白帽+粉衣 —— 粉衣跟皮肤同色相改不了; 白帽/眼白/刀光都是无色相的
#         亮像素, 逐行探针实锤挥剑图里帽子和剑刃根本分不开 —— 所以白帽不动,
#         只给黑发「挑染」: 暗带(v0.06~0.28 低饱和, 轮廓线 v<0.06 挡住)在所有
#         动作图里只落在头发区, 整条染成彩色并抬明度 = 黑发染出颜色
#   Tori: 橙红长发 hue[0.00,0.17] 饱和≥0.40 / 紫裙 hue[0.78,0.92] 饱和≥0.35
# 带参数: band=[hue 起,hue 止](可跨 0/1) / to=目标色相(缺省不动) / vmul=明度倍率
#         smul=饱和倍率 / sset=饱和度直接定值 / smin/smax=饱和门槛 / vmin/vmax=明度门槛
#         ytop/ybot=帧内 y 范围
# 超出 20 人(行政研究加员额外)按 i%20 回绕 —— 跟 model_for 的轮换同一套防御。
const RECIPES := [
	# ---- Alex 组(男·橙金短发+蓝背带裤): slave_00/04/08/12/16 ----
	[{"band": [0.56, 0.68], "smin": 0.35, "to": 0.97, "vmul": 0.90}],   # 00 本色橙发, 裤染酒红
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.07, "vmul": 0.55},    # 04 栗棕发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.30, "vmul": 0.80}], #    苔绿裤
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.22, "vmul": 0.75},    # 08 橄榄发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.75, "vmul": 0.80}], #    暗紫裤
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.55, "vmul": 0.85},    # 12 青蓝发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.07, "vmul": 0.85}], #    赭棕裤
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.80, "vmul": 0.90},    # 16 粉紫发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.60, "smul": 0.12}], #    炭灰裤
	# ---- Lyria 组(女·棕红卷发+红裙): slave_01/05/09/13/17 ----
	[{"band": [0.88, 1.00], "smin": 0.30, "to": 0.61, "vmul": 0.85}],   # 01 本色棕红发, 裙染靛蓝
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.11, "vmul": 1.05},    # 05 金发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.30, "vmul": 0.80}], #    苔绿裙
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.52, "vmul": 0.80},    # 09 青发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.13, "vmul": 1.00}], #    金黄裙
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.72, "vmul": 0.80},    # 13 紫发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.85, "vmul": 0.90}], #    玫紫裙
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.00, "vmul": 0.60},    # 17 暗红褐发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.00, "smul": 0.15}], #    炭灰裙
	# ---- Manu 组(女·黑发白帽粉衣): slave_02/06/10/14/18 ----
	# 发带: v0.06~0.28 的暗低饱和像素(黑发), 轮廓线 v<0.06、眼白 v≥0.5 都被挡住
	[],                                                                 # 02 本色黑发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.93, "sset": 0.55, "vmul": 1.9}],                        # 06 玫红发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.55, "sset": 0.50, "vmul": 1.9}],                        # 10 青蓝发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.30, "sset": 0.50, "vmul": 1.9}],                        # 14 草绿发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.09, "sset": 0.60, "vmul": 1.9}],                        # 18 金橙发
	# ---- Tori 组(女·橙红长发+紫裙): slave_03/07/11/15/19 ----
	[{"band": [0.78, 0.92], "smin": 0.35, "to": 0.60, "vmul": 0.85}],   # 03 本色橙红发, 裙染靛蓝
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.11, "vmul": 1.00},    # 07 金发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.97, "vmul": 0.85}], #    酒红裙
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.45, "vmul": 0.80},    # 11 青绿发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.32, "vmul": 0.80}], #    苔绿裙
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.66, "vmul": 0.85},    # 15 蓝紫发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.07, "vmul": 0.85}], #    赭棕裙
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.90, "vmul": 0.90},    # 19 玫红发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.00, "smul": 0.15}], #    炭灰裙
]

# 走路的「一个循环迈多远」：从 Walk.png 里量出来的 ——
# 侧身那 6 帧里两只脚分得最开时中心差约 5 像素，一个循环两步 -> 约 10 像素。
# 速度按它反推动画帧率，脚就踩得住地（不会像溜冰）。
const WALK_STRIDE_PX := 10.0
const WALK_FPS_CAP := 22.0    # 安全上限：只防呆，正常速度碰不到（见 _sync_walk_speed）

# 由 game.gd 在 add_child **之前**赋值（_ready 里要靠它选脸）
var index := 0

# ❗setter 里改动画速度：速度是**唯一真相源**，帧率永远跟着它算，
#   所以以后无论把速度调快调慢，动画都自动配得上（这是用户提的「速度配得上动画」）。
var speed: float = 30.0:
	set(v):
		speed = v
		_sync_walk_speed()
var _sprite: AnimatedSprite2D
var _state := State.LOITER
var _target := Vector2.ZERO           # 闲逛落点
var _work_cell := Vector2i(-999, -999)
var _rest := 0.0
var _gaze_t := 0.0                    # e54: 歇着时下一次张望（换朝向）还有多久
var _work_t := 0.0                    # 当前动作还剩多久
var _work_hit := 0.0                  # 播到这个时刻「落下去」
var _work_applied := false
var _facing: StringName = &"down"
var _rng := RandomNumberGenerator.new()
var _blocked := {}                    # Vector2i -> 剩余冷却秒数

# —— e30s 岗位 ——
var _post := ""                       # 当前岗位键（"" = 照料作物, 下地干活）
var _post_spot := Vector2.ZERO        # 岗位站位（换岗时重算, 免得每帧抖）
var _post_t := 0.0                    # 距离下一次「岗位上出声」还有多久

# —— 出海登船 ——
# 出海那天，被勾了「明天出行」的伙伴先被叫到码头边（game.gd 负责摆位置），
# 再走上最后几步 -> _aboard = true 就藏起来，白天那套「挑活/干活」循环整个不参与。
# 船上的人数就是 Slaves.expedition，海图的船队照着它画船员。
var _aboard := false
var _board_dest := Vector2.ZERO

# 玩家走近交互的检测
const TALK_RANGE := 22.0              # 半径（玩家中心到伙伴中心的距离 < 这个才提示对话）
var _area: Area2D = null              # 玩家的 CharacterBody2D 走进时会触发
var _shape: CollisionShape2D = null
var _key_hint: Node2D = null          # 头顶的「F 对话」常驻提示
var _player_in_range := false         # 玩家走进了这个伙伴的对话半径

func _ready() -> void:
	# e33 脚下的影子（跟主角同款）
	# e36d 之后主角把影子的居中点抬到了 y=-7（贴图 32x32 里视觉脚底就在那一行，
	# 留在 y=0 会比脚底低 7px，看着像影子跟人分了家）—— 伙伴这边也要跟上，别一边改一边没改。
	var _sh := preload("res://scene/shadow_util.gd").make_shadow(18, 7, 0.28)
	_sh.position = Vector2(0, -7)
	add_child(_sh)
	_sprite = AnimatedSprite2D.new()
	_sprite.position = Vector2(0, -16)          # 原点在脚下，精灵画在上面
	_sprite.sprite_frames = build_frames(MODELS[index % MODELS.size()], index)
	_sprite.play(&"idle_down")
	add_child(_sprite)
	_sync_walk_speed()                  # 步伐帧率由速度反推（setup 里定了速度还会再算一次）
	# e28e: 物理碰撞体积 —— 玩家走近会被挡住，不再穿过伙伴身体。
	# ❗伙伴自己的走位是直写 global_position（不查物理），这层只拦玩家、不拖累自己：
	#   layer 跟建筑一样在位值 4（玩家的 mask 7 覆盖得到），mask 0 = 谁也不挡。
	var _blk := StaticBody2D.new()
	_blk.name = "BodyBlock"
	_blk.collision_layer = 4
	_blk.collision_mask = 0
	var _blk_shape := CollisionShape2D.new()
	var _blk_circle := CircleShape2D.new()
	_blk_circle.radius = 5.5
	_blk_shape.shape = _blk_circle
	_blk_shape.position = Vector2(0, -6)     # 跟玩家的碰撞圆同高（圆心都悬在脚踝上方）
	_blk.add_child(_blk_shape)
	add_child(_blk)
	# 交互检测 Area
	_area = Area2D.new()
	_area.name = "TalkArea"
	_area.collision_layer = 0
	_area.collision_mask = 1                # 玩家 CharacterBody2D 在 layer 1
	add_child(_area)
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TALK_RANGE
	_shape.shape = circle
	_shape.position = Vector2(0, -8)
	_area.add_child(_shape)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	# 头顶对话提示
	_key_hint = preload("res://scene/key_hint.gd").new()
	_key_hint.setup("F", "对话", -62.0)
	_key_hint.connect("clicked", _try_talk)   # e36i: 左键点这个框 = 按 F（字符串写法, _key_hint 是 Node2D）
	add_child(_key_hint)
	# 晋升换甲：职业一变（Slaves.changed）就把身上的装甲色重刷一遍
	Slaves.changed.connect(_refresh_outfit)

# 由 game.gd 在入树后调用：给号、定速度、撒在集合点附近
func setup(i: int, near: Vector2) -> void:
	index = i
	_rng.seed = 9871 + i * 7717
	speed = _rng.randf_range(24.0, 36.0)
	global_position = _dry_spot(near)          # ❗撒点要挑陆地：撒进水里人就泡在那儿了
	_refresh_outfit()
	_decide_next()

# 一身行头的装甲档位色（e29c: 发色/服装的「个人配色」已烘进贴图层, 见 RECIPES;
# modulate 这层只剩装甲 —— 职业晋升（Slaves.changed）时当场重刷: 布衣->银甲->金铜甲。
# 两层天然可乘, 贴图层的个人色不会被装甲色盖掉。
func _refresh_outfit() -> void:
	var troop := String(Slaves.slave_at(index).get("troop", "新兵"))
	modulate = Slaves.armor_tint(troop)

# 集合点附近找个不落水的落脚处（试不出来就退到最近的一片岸上，绝不站水里）
func _dry_spot(near: Vector2, radius := 44.0) -> Vector2:
	for _try in 24:
		var p := near + Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
		if not _is_water_at(p):
			return p
	return _cell_center(_nearest_land(near))

# ---------------- 动画表 ----------------
# 拼一套动画。idx 是伙伴序号 —— 贴图按 RECIPES[idx] 局部改色（e29c）,
# 所以「第 i 个伙伴」不管出现在农场/战场/篝火/船上都长同一张脸。
# 静态：篝火、面板、背包都直接调, 不用为抽一张小像实例化整个伙伴。
static func build_frames(model: String, idx: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for key in SHEETS.keys():
		var info: Dictionary = SHEETS[key]
		var tex := sheet_texture(model, info["file"], idx)
		if tex == null:
			push_error("伙伴素材加载失败:%s / %s" % [model, info["file"]])
			continue
		for d in DIR_ROW.keys():
			var an := StringName("%s_%s" % [key, d])
			sf.add_animation(an)
			sf.set_animation_loop(an, bool(info["loop"]))
			sf.set_animation_speed(an, float(info["fps"]))
			var row: int = DIR_ROW[d]
			for i in int(info["frames"]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * CELL, row * CELL, CELL, CELL)
				sf.add_frame(an, at)
	return sf

# 让走路动画的帧率跟着 speed 走：速度 = 步幅 / 循环时长，所以
#   循环时长 = 步幅 / 速度，帧率 = 帧数 / 循环时长 = 速度 * 帧数 / 步幅。
# 这样「脚踩住地」和「速度」永远同时成立，改速度不用再回头调帧率。
func _sync_walk_speed() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var frames := float(SHEETS["walk"]["frames"])
	var fps := minf(WALK_FPS_CAP, speed * frames / WALK_STRIDE_PX)
	for d in DIR_ROW.keys():
		var an := StringName("walk_%s" % d)
		if _sprite.sprite_frames.has_animation(an):
			_sprite.sprite_frames.set_animation_speed(an, fps)

# 当前用的是哪个模型（自检用来确认「伙伴不是主角那张脸」）
func model_name() -> String:
	return MODELS[index % MODELS.size()]

# ---------------- 「第 i 个伙伴长什么样」的唯一真相源 ----------------
# 白天在农场跑的伙伴、篝火边站着等你的人、篝火面板里的小像 —— 三处都走这里，
# 于是「招募前在火边看到的那张脸」跟「招进来之后的脸」必然是同一张。
static func model_for(i: int) -> String:
	return MODELS[maxi(0, i) % MODELS.size()]

# 配方在 RECIPES 里的下标。RECIPES 是按模型分组的布局:
#   [0..4]=Alex(00/04/08/12/16) [5..9]=Lyria(01/05/09/13/17)
#   [10..14]=Manu(02/06/10/14/18) [15..19]=Tori(03/07/11/15/19)
# 伙伴 i 的模型组 = i % 4（跟 model_for 同一规则）, 组内轮次 = (i / 4) % 5,
# 超出 20 人自动回绕。
static func _recipe_index(i: int) -> int:
	var m := maxi(0, i)
	return (m % MODELS.size()) * 5 + (m / MODELS.size()) % 5

# 第 i 个伙伴的改色配方
static func recipe_for(i: int) -> Array:
	return RECIPES[_recipe_index(i)]

# —— e29c: 改色贴图缓存 ——
# key = "模型|文件|配方序号"。五个消费方（农场实体/战场小兵/篝火人/两处面板小像/
# 船员）共用同一张贴图, 不重算也不重开显存。
static var _tex_cache := {}

# 模型图集的改色版。file 是模型目录里的文件名（Idle.png / Sword.png ...）。
# RECIPES[i] 为空（本色伙伴）直接回原图, 一个字节都不重排。
static func sheet_texture(model: String, file: String, i: int) -> Texture2D:
	var ri := _recipe_index(i)
	var key := "%s|%s|%d" % [model, file, ri]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = load(MODEL_PATH % [model, file])
	if tex == null:
		return null
	var bands: Array = RECIPES[ri]
	if bands.is_empty():
		_tex_cache[key] = tex
		return tex
	var img: Image = tex.get_image().duplicate()  # get_image 是共享引用, 直接改会把原图弄脏
	img.convert(Image.FORMAT_RGBA8)      # 压缩贴图读出来不一定可直接写, 先转标准格式
	_apply_bands(img, bands)
	var out := ImageTexture.create_from_image(img)
	_tex_cache[key] = out
	return out

# 把一套色带刷到整张图集上。图集是 32px 帧的横排竖排, ytop/ybot 按「帧内行号」算。
# 命中第一条色带就停（后面的带不再叠加）—— 配方之间互不侵犯。
static func _apply_bands(img: Image, bands: Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		var ry := y % CELL
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			for b in bands:
				if _band_hit(c, b, ry):
					img.set_pixel(x, y, _band_paint(c, b))
					break

# 一个像素落在不在色带里。色相带支持跨 0/1（比如红 0.88~1.00）。
static func _band_hit(c: Color, b: Dictionary, ry: int) -> bool:
	var band: Array = b.get("band", [0.0, 1.0])
	var h0 := float(band[0])
	var h1 := float(band[1])
	var h := c.h
	var in_hue: bool
	if h0 <= h1:
		in_hue = h >= h0 and h <= h1
	else:
		in_hue = h >= h0 or h <= h1
	if not in_hue:
		return false
	if c.s < float(b.get("smin", 0.0)) or c.s > float(b.get("smax", 1.0)):
		return false
	if c.v < float(b.get("vmin", 0.0)) or c.v > float(b.get("vmax", 1.0)):
		return false
	return ry >= int(b.get("ytop", 0)) and ry <= int(b.get("ybot", CELL - 1))

# 色带内的上色：hue 平移到目标色, 明度/饱和度按倍率缩放（sset 直接定值）,
# 保留原像素的明暗层次 —— 高光还是高光, 阴影还是阴影。
static func _band_paint(c: Color, b: Dictionary) -> Color:
	var h := c.h
	if b.has("to"):
		h = float(b["to"])
	var s := c.s * float(b.get("smul", 1.0))
	if b.has("sset"):
		s = float(b["sset"])
	var v := clampf(c.v * float(b.get("vmul", 1.0)), 0.0, 1.0)
	return Color.from_hsv(h, clampf(s, 0.0, 1.0), v, c.a)

# ---------------- 主循环 ----------------
func _process(delta: float) -> void:
	# 已经跟着船出海了：人在船上，岛上这套循环整个不参与
	if _aboard:
		return
	var night := TimeManager.hour >= 19 or TimeManager.hour < 6
	if night and _state != State.BOARD:
		visible = false
		_state = State.LOITER                 # 天亮重新决定要干嘛
		_post = ""                            # 夜里重新看名单（白天可能又被改派过）
		return
	visible = true
	# 正在登船：只管走向船，别的活一概不接
	if _state == State.BOARD:
		_tick_board(delta)
		return
	# 玩家开着涂色面板（在绘制派活地图）时全部停下歇着：
	# 不挑新活、不挪步、手上那一下也不落 —— 松开面板（或睡醒）再继续。
	if Slaves.paused:
		if _state == State.WORK:
			_state = State.REST               # 动画作废，这格明天按「没干」重排
		_rest = maxf(_rest, 0.6)
		_play_loop(&"idle")
		return
	_tick_blocked(delta)

	# e30s 岗位：被派去矿井/工地/铁匠铺/研究的人不去地里浇水, 各自去岗位上干活。
	# 名单白天随时能改（派活面板 T），所以每帧对一次 —— 换岗了当场掉头。
	var post := _post_of()
	if post != _post:
		_post = post
		_post_spot = Vector2.ZERO             # 落点重算
		_post_t = 0.0
		if post == "":
			_decide_next()                    # 被撤回来 -> 回地里那套循环
		else:
			_state = State.POST
	if _post != "":
		_tick_post(delta)
		return

	match _state:
		State.REST:
			_rest -= delta
			_tick_gaze(delta)
			_play_loop(&"idle")
			if _rest <= 0.0:
				_decide_next()
		State.LOITER:
			_tick_loiter(delta)
		State.GO_WORK:
			_tick_go_work(delta)
		State.WORK:
			_tick_work(delta)

# 闲逛：走到落点 -> 歇一会儿 -> 再挑一个
func _tick_loiter(delta: float) -> void:
	var r := _step_toward(delta, _target)
	if r == STEP_MOVING:
		return
	_rest = _rng.randf_range(1.0, 3.0)
	_state = State.REST

# e54 歇着时的随机张望：隔一会儿换个朝向，像在打量四周
# （_play_loop/_anim_name 按 _facing 切朝向动画，改 _facing 即生效）
func _tick_gaze(delta: float) -> void:
	_gaze_t -= delta
	if _gaze_t > 0.0:
		return
	_gaze_t = _rng.randf_range(0.9, 2.2)
	var faces: Array[StringName] = [&"down", &"up", &"left", &"right"]
	_facing = faces[_rng.randi() % faces.size()]

# 赶去干活：走到岗位 -> 开工。路上撞见水就放弃这一趟（这格先冻一会儿）
func _tick_go_work(delta: float) -> void:
	if not Slaves.assignments.has(_work_cell) or Slaves.is_done(_work_cell):
		_decide_next()
		return
	var r := _step_toward(delta, _stand_pos(_work_cell))
	if r == STEP_ARRIVED:
		_begin_work()
	elif r == STEP_BLOCKED:
		_block(_work_cell)
		_decide_next()

# 干活：播动作，放到 HIT_RATIO 时真正改变农场数据，播完歇口气
func _tick_work(delta: float) -> void:
	_work_t -= delta
	if not _work_applied and _work_t <= _work_hit:
		_work_applied = true
		_apply_work()
	if _work_t <= 0.0:
		_state = State.REST
		_rest = _rng.randf_range(0.5, 1.3)

# ---------------- 出海登船 / 返航下船 ----------------
# game.gd 在出海前把人摆到码头边，再调这个：走向船 -> 到了就藏起来。
# ❗目的地是码头/栈桥上的点，不是水里的船 —— _step_toward 撞到水会 STEP_BLOCKED，
#   所以人自然停在岸线上，看起来就是「走到码头边上船」。
func board_to(dest: Vector2) -> void:
	_aboard = false
	_board_dest = dest
	_state = State.BOARD
	visible = true
	set_process(true)

func _tick_board(delta: float) -> void:
	if _step_toward(delta, _board_dest) != STEP_MOVING:
		_aboard = true
		visible = false
		set_process(false)

# 返航：在码头边重新出现，接着挑活干
func unboard(pos: Vector2) -> void:
	_aboard = false
	visible = true
	set_process(true)
	global_position = _dry_spot(pos, 30.0)
	_decide_next()

func is_aboard() -> bool:
	return _aboard

# 兜底：到点了还没走到船边（被地形挤住 / 绕远路）就直接算上船 ——
# 不能因为一个人走不到位就把整趟出海卡在那儿。
func board_now() -> void:
	_aboard = true
	visible = false
	set_process(false)

# ---------------- 走位 ----------------
# 返回 STEP_MOVING / STEP_ARRIVED / STEP_BLOCKED
func _step_toward(delta: float, dest: Vector2) -> int:
	# 兜底：万一人已经站在水里了（旧存档 / 撒点撒歪），先把他挪到最近的岸上，
	# 绝不让他「在水里走」。
	if _is_water_at(global_position):
		global_position = _cell_center(_nearest_land(global_position))
		return STEP_BLOCKED
	var to := dest - global_position
	if to.length() < ARRIVE_DIST:
		return STEP_ARRIVED
	var dir := to.normalized()
	_facing = _dir_name(dir)
	# ❗先看水再迈步：判定放在 _play_loop 前面，撞水的那一帧就不该摆出走路姿势
	var next := global_position + dir * speed * delta
	if _is_water_at(next):
		_play_loop(&"idle")
		return STEP_BLOCKED
	_play_loop(&"walk")
	global_position = next
	return STEP_MOVING

# 离这个点最近的一格陆地（螺旋往外找，找到就停）
func _nearest_land(pos: Vector2) -> Vector2i:
	var g := _game()
	if g == null:
		return Vector2i.ZERO
	var local := pos - Farm.grid_origin
	var c := Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE))
	for r in 12:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t := c + Vector2i(dx, dy)
				if not _is_cell_water(t):
					return t
	return c

func _is_water_at(pos: Vector2) -> bool:
	var g := _game()
	if g == null or not g.has_method("is_water"):
		return false
	var local := pos - Farm.grid_origin
	return g.is_water(Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE)))

# 一格的格子中心（世界坐标）
func _cell_center(cell: Vector2i) -> Vector2:
	return Farm.grid_origin + Vector2(cell.x * Farm.TILE_SIZE + 8, cell.y * Farm.TILE_SIZE + 8)

func _is_cell_water(cell: Vector2i) -> bool:
	var g := _game()
	if g == null or not g.has_method("is_water"):
		return false
	return g.is_water(cell)

# 干活的站位：就站在那一格上（略微偏一点，几个人一起干不会完全重叠）
func _stand_pos(cell: Vector2i) -> Vector2:
	return _cell_center(cell) + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))

# ---------------- 干活 ----------------
func _begin_work() -> void:
	var task := Slaves.task_at(_work_cell)
	var anim: StringName = TASK_ANIM.get(task, &"hoe")
	_work_t = _play_once(anim)
	if _work_t <= 0.0:                 # 动画缺帧就直接生效，别卡住
		_apply_work()
		_state = State.REST
		_rest = 0.5
		return
	_work_hit = _work_t * HIT_RATIO
	_work_applied = false
	_state = State.WORK

# 真正把活干出来。写进 Farm 的逻辑在 Slaves.apply_task（跟睡前「强行补完」共用一份），
# 这里只负责：水里勾掉、干不了的进冷却、按工种配音效。
func _apply_work() -> void:
	var c := _work_cell
	if not Slaves.assignments.has(c) or Slaves.is_done(c):
		return
	if _is_cell_water(c):
		Slaves.mark_done(c)            # 水里没法干活，别再排它了
		return
	var task := Slaves.task_at(c)
	if Slaves.apply_task(c) != Slaves.APPLY_OK:
		_block(c)                      # 还没耕地 / 背包没种子 —— 过会儿再来看看
		return
	match task:
		Slaves.TASK_TILL:
			Audio.play_sfx("hoe", -15.0, _rng.randf_range(0.92, 1.08))
		Slaves.TASK_WATER:
			Audio.play_sfx("water", -15.0, _rng.randf_range(0.92, 1.08))
		Slaves.TASK_PLANT:
			Audio.play_sfx("plant", -15.0, _rng.randf_range(0.92, 1.08))

# ---------------- 岗位干活（e30s） ----------------
# 这个人在派活页上归哪个板块（空 = 照料作物, 也就是没被别的岗位占住, 下地浇水）。
# 数据层保证一个人只占一个岗位（slaves.gd 的 toggle 之间互斥），所以判断顺序无所谓。
# ❗「远航出征」不算岗位：那份名单是「下次出海带谁」, 人平时还在岛上过日子;
#   真出海那天由 game.gd 的 _board_expedition -> board_to 接手（见 _process 的 BOARD 分支）。
func _post_of() -> String:
	if Slaves.is_research(index, "tech") or Slaves.is_research(index, "admin"):
		return "research"
	if Slaves.is_dock(index):
		return "dock"
	if Slaves.is_craft(index):
		return "smith"
	if Slaves.is_mine(index):
		return "mine"
	return ""

# 岗位站位（世界坐标）。找不到对应设施就退回农田中心 —— 宁可站着也别站着不动就消失。
func _post_pos() -> Vector2:
	match _post:
		"mine":
			var g := _game()
			if g != null:
				var raw: Variant = g.get("mine_cell")
				if raw is Vector2i and (raw as Vector2i).x != 9999:
					return _cell_center((raw as Vector2i) + Vector2i(0, 1))   # 站矿门外一格
		"dock":
			var site: Dictionary = Structures.site
			if not site.is_empty():
				return _cell_center(Vector2i(site.get("anchor", Vector2i.ZERO)))
			var g2 := _game()
			if g2 != null:
				var dk: Variant = g2.get("dock")
				if dk is Node2D:
					return (dk as Node2D).global_position + Vector2(-8, 20)
		"smith":
			var bc := _blacksmith_cell()
			if bc.x != 9999:
				return _cell_center(bc + Vector2i(0, 1))                 # 站砧子外面一格
		"research":
			var g3 := _game()
			if g3 != null:
				var h: Node2D = g3.get_node_or_null("House")
				if h != null:
					return h.global_position + Vector2(0, 46)
	return _field_center()

# 场上第一座铁匠铺所在格（没盖就 9999）
func _blacksmith_cell() -> Vector2i:
	for c in Structures.stations.keys():
		if String((Structures.stations[c] as Dictionary).get("kind", "")) == Structures.KIND_BLACKSMITH:
			return c
	return Vector2i(9999, 9999)

# 岗位上的循环：走到位 -> 面朝岗位站定 -> 循环播干活动作 -> 隔一会儿出一声
func _tick_post(delta: float) -> void:
	if _post_spot == Vector2.ZERO:
		_post_spot = _dry_spot(_post_pos(), 16.0)     # 落点也要挑陆地
	var r := _step_toward(delta, _post_spot)
	if r == STEP_MOVING:
		return
	_facing = POST_FACING.get(_post, &"down")
	var anim: StringName = POST_ANIM.get(_post, &"idle")
	_play_loop(anim)
	_post_t -= delta
	if _post_t <= 0.0:
		_post_t = _rng.randf_range(POST_SFX_GAP.x, POST_SFX_GAP.y)
		_post_sfx()

# 岗位上那一下的响动：矿/工地/打铁各用一种音高，听得出是三种活
func _post_sfx() -> void:
	match _post:
		"mine":
			Audio.play_sfx("hoe", POST_SFX_DB, _rng.randf_range(0.90, 1.04))
		"dock":
			Audio.play_sfx("hoe", POST_SFX_DB, _rng.randf_range(0.80, 0.92))
		"smith":
			Audio.play_sfx("hoe", POST_SFX_DB, _rng.randf_range(1.06, 1.20))

# ---------------- 冷却 ----------------
func _block(cell: Vector2i) -> void:
	_blocked[cell] = BLOCK_TIME

func _tick_blocked(delta: float) -> void:
	if _blocked.is_empty():
		return
	for c in _blocked.keys():
		var t: float = float(_blocked[c]) - delta
		if t <= 0.0:
			_blocked.erase(c)
		else:
			_blocked[c] = t

# ---------------- 挑活 / 挑落点 ----------------
# 下一步干嘛：有没干完的活就去干活，没有就闲逛
func _decide_next() -> void:
	if _acquire_job():
		_state = State.GO_WORK
	else:
		_pick_target()
		_state = State.LOITER

# 挑一格还没干的活。从最近的几格里随机挑一个 —— 不总盯着同一格，
# 人也不会都挤在同一个点上，但又不会大老远绕到岛另一头。
func _acquire_job() -> bool:
	var pool: Array = []
	for c in Slaves.undone_cells():
		if _blocked.has(c):
			continue
		if _is_cell_water(c):
			continue
		pool.append(c)
	if pool.is_empty():
		return false
	pool.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a) < _dist2(b))
	var n: int = mini(3, pool.size())
	_work_cell = pool[_rng.randi_range(0, n - 1)]
	return true

func _dist2(c: Vector2i) -> float:
	return global_position.distance_squared_to(_cell_center(c))

# 闲逛落点：优先挑「已派活的格子」（涂得密的区域被挑中的概率高）
func _pick_target() -> void:
	# ❗落点要过滤掉水格：涂色面板允许涂到水面上，但人不能站水里
	var cells: Array = []
	for c in Slaves.assigned_cells():
		if not _is_cell_water(c):
			cells.append(c)
	if cells.is_empty():
		# 还没派过活（或派的活全在水里）：就在耕地一带随便晃
		_target = _dry_spot(_field_center(), 150.0)
		return
	var c: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
	# ❗落点必须还在这一格里面（_stand_pos 的 ±3 已经够错开了，再加抖动就会跑到隔壁格）
	_target = _stand_pos(c)

# 耕地的中心（世界坐标）—— 一格都没派活时的兜底集合点
func _field_center() -> Vector2:
	var cells: Array = Farm.tilled.keys()
	if cells.is_empty():
		return Farm.grid_origin
	var sum := Vector2i.ZERO
	for c in cells:
		sum += c
	var avg := Vector2(sum.x, sum.y) / float(cells.size())
	return Farm.grid_origin + avg * Farm.TILE_SIZE

# ---------------- 播动画 ----------------
func _play_loop(prefix: StringName) -> void:
	var an := _anim_name(prefix)
	if _sprite.animation != an and _sprite.sprite_frames.has_animation(an):
		_sprite.play(an)
	_sprite.flip_h = (_facing == &"left")

# 播一次不循环的动作，返回它的时长（秒）
func _play_once(prefix: StringName) -> float:
	var an := _anim_name(prefix)
	if not _sprite.sprite_frames.has_animation(an):
		return 0.0
	_sprite.speed_scale = 1.0
	_sprite.play(an)
	_sprite.flip_h = (_facing == &"left")
	var fps := _sprite.sprite_frames.get_animation_speed(an)
	if fps <= 0.0:
		return 0.0
	return float(_sprite.sprite_frames.get_frame_count(an)) / fps

func _dir_name(dir: Vector2) -> StringName:
	if absf(dir.x) >= absf(dir.y):
		return &"right" if dir.x > 0 else &"left"
	return &"down" if dir.y > 0 else &"up"

# 素材只有三行（下 / 上 / 侧），左右是同一张「侧身图」水平翻过来的。
# ❗以前是直接拿朝向去拼动画名（walk_left / walk_right），这两个动画根本不存在 ——
#   结果伙伴往左右走的时候动画压根不播，一直僵在上一张「朝下」的姿势上。
#   现在统一走这里：左右都翻成 side，真正的左右靠 flip_h 区分。
func _anim_name(prefix: StringName) -> StringName:
	if _facing == &"left" or _facing == &"right":
		return StringName("%s_side" % String(prefix))
	return StringName("%s_%s" % [String(prefix), String(_facing)])

func _game() -> Node:
	return get_tree().get_first_node_in_group("game")

# ---------------- 走近对话 ----------------
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _key_hint != null:
			_key_hint.show_hint()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _key_hint != null:
			_key_hint.hide_hint()

# 在主场景里挂的伙伴处理 F 键：打开 dialogue_ui
# （夜晚时伙伴不可见，自然不会触发）
func _try_talk() -> bool:
	if not _player_in_range:
		return false
	var night := TimeManager.hour >= 19 or TimeManager.hour < 6
	if night:
		return false
	if Slaves.paused:
		return false
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	if dialogue != null and dialogue.has_method("open_panel"):
		dialogue.open_panel(index)
		return true
	return false
