# scene/troop.gd —— 战役地图里的通用兵种单位
#
# 三种身份（side）：
#   hero  = 主角本人（WASD 直接操纵；e15h 后不再自动攻击 —— 左键点哪儿挥哪儿）
#   ally  = 出海伙伴（听指挥：F1 点地图开过去 / F2 跟随我 / F3 冲锋 / F4 驻守，
#           且只跟数字键 1/2 选中的兵种有关，没被选中的保持原来的口令）
#   enemy = 敌人（海寇/山贼，自动索敌；弓手会放风筝射箭）
#
# 两种兵种（kind）：刀客 = 近战扑脸砍；弓手 = 保持距离放箭（箭矢见 arrow.gd）。
#
# 骑砍味的两条（e48）：
#   · 兵种相克 —— 步兵拒马克骑兵 / 骑兵冲阵克弓手 / 弓手攒射克步兵（counter_mult）
#   · 士气与溃逃 —— 同伴阵亡、自己挨刀、血太薄都会掉士气, 士气见底当场溃逃退场
#
# 伤害直通数据层：主角扣 Legion.player_hp（下场战斗还接着疼），
# 伙伴扣 Slaves 字典里的 hp（引用直写，倒下了要睡一觉才爬起来）。
# ❗节点原点在脚下，跟岛上角色同一个约定。
extends Node2D

signal died(unit)

const CELL := 32
const MODEL_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/%s"
const MODELS := ["Alex", "Lyria", "Manu", "Tori"]
const JOSH_IDLE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Idle.png"
const JOSH_WALK := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Walk.png"
# ❗e41e: Josh/Walk.png 是 192x96 = **6 帧** x 3 行（Idle.png 才是 128x96 = 4 帧）。
#   以前按 8 帧切 -> 第 7/8 帧的取样区跑出图外 -> 主角走路时「走两步闪一下」。
const JOSH_WALK_FRAMES := 6
# e17: 真攻击帧 —— 每个角色目录都有 Sword.png(320x96 = 10 帧 x 3 行 32x32, 行序同
# Idle/Walk 是 下/上/侧) 和 Bow and Arrow.png(224x96 = 7 帧 x 3 行)。侧向帧默认朝右。
# 骑兵的马素材没有攻击帧, 攻击时兜底回手绘光效(见 _play_attack)。
const DIR_ROW := {"down": 0, "up": 1, "side": 2}
# 岛上伙伴外观的唯一真相源（slave_npc.gd 无 class_name, 只能 preload 调它的静态方法）：
# 战场上的伙伴按同一条「第 i 个伙伴」规则取配色，跟岛上那个人对得上。
const SNPC := preload("res://scene/slave_npc.gd")

# 走路动画的「一个循环迈多远」：跟岛上伙伴同一份素材、同一个量法（见 slave_npc.gd）。
# 帧率由 speed 反推（速度是唯一真相源），就不会出现「腿在蹬、人在滑」。
const WALK_STRIDE_PX := 10.0
const WALK_FPS_CAP := 22.0    # 安全上限：只防呆，正常速度碰不到（见 _sync_walk_speed）

const MELEE_RANGE := 22.0
const ARCHER_RANGE := 100.0
const ARCHER_KEEP := 55.0          # 弓手跟敌人保持的最小距离
const ATTACK_CD := 1.1
const ARRIVE_DIST := 3.0
# e27k: 跟随途中近身有敌就顺手接敌的小半径（近战专用，打完自己回位）
const ENGAGE_LEASH := 26.0
const FORMATION := [Vector2(-24, -10), Vector2(24, -10), Vector2(0, 20),
	Vector2(-24, 20), Vector2(24, 20)]

# 撞墙后「绕开」的方向锁定多久（0.7 秒 x 速度 28 = 横挪约 20 像素，够走过一格障碍）
const DETOUR_TIME := 0.7
# 敌人一动不动超过这么久，就当它过不来（见 _tick_stuck）
const STUCK_LIMIT := 6.0

# 涉水减速（h-m）：站进浅水格（贴岸的水）迈不开腿，速度打这个折扣。
# 深水照样挡路（is_blocked_at）；水里照样能砍 —— 攻击判定不查水。
const WATER_MULT := 0.55

# ---------------- 哥布林蛮族（e49）----------------
# 素材: Enemy/Goblins/<兵种>/*.png。一格 32x32, 整张图纵向 4 行（下/上/侧/侧镜像),
# 帧数与行数都由 _make_strip_frames 按图尺寸自动数。三种兵各一路:
# 矛手(近战) / 弓手(远程) / 炸弹手(远程投掷)。
const GOBLIN_DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Enemy/Goblins/%s/%s"
const GOBLIN_KINDS := ["哥布林矛手", "哥布林弓手", "哥布林炸弹手"]
const GOBLIN_ARCHER_KINDS := ["哥布林弓手", "哥布林炸弹手"]   # 会站远处放风筝的两路
# 兵种 -> 素材目录 + 帧表 [名字, 文件名, fps, 是否循环]（帧数按图宽自动数）
const GOBLIN_SHEETS := {
	"哥布林矛手": {"dir": "Spear Goblin", "sheets": [
		["idle", "Idle.png", 6.0, true], ["walk", "Walk.png", 10.0, true],
		["swing", "Spear.png", 16.0, false], ["hurt", "Damage.png", 14.0, false],
		["dead", "Dead.png", 9.0, false]]},
	"哥布林弓手": {"dir": "Archer Goblin", "sheets": [
		["idle", "Idle.png", 6.0, true], ["walk", "Walk.png", 10.0, true],
		["shoot", "Bow.png", 14.0, false], ["hurt", "Damage.png", 14.0, false],
		["dead", "Dead.png", 9.0, false]]},
	"哥布林炸弹手": {"dir": "Bomb Goblin", "sheets": [
		["idle", "Idle.png", 6.0, true], ["walk", "Walk.png", 10.0, true],
		["shoot", "Throw a bomb.png", 12.0, false], ["hurt", "Damage.png", 14.0, false],
		["dead", "Dead.png", 9.0, false]]},
}

# ---------------- 岛上魔物（e49）----------------
# 素材: Enemy/ 下的史莱姆/毒菇人/芽苗史莱姆/毒花/尖刺怪。多数是格 32x32、竖 3 行带白边;
# 毒花是 48x48 单行（三向共用第 0 行）。它们都没「挥砍」帧, 攻击时借用走/攻击帧充数。
# 「魔物」是巨岛野外游荡的第三种敌人（跟海寇/山贼并列）, 打散了算土匪声望。
const MONSTER_DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Enemy/%s/%s"
const MONSTER_KINDS := ["史莱姆", "毒菇人", "芽苗史莱姆", "毒花", "尖刺怪"]
# 兵种 -> {path 子目录, cell 格宽, sheets 帧表}
const MONSTER_SHEETS := {
	"史莱姆": {"path": "Slimes/Green/Big Slime", "cell": 32, "sheets": [
		["idle", "Idle.png", 6.0, true], ["walk", "Walk.png", 8.0, true],
		["swing", "Walk.png", 9.0, false], ["hurt", "Damage.png", 12.0, false],
		["dead", "Dead.png", 8.0, false]]},
	"毒菇人": {"path": "Myconid/Green", "cell": 32, "sheets": [
		["idle", "Idle.png", 6.0, true], ["walk", "Walk.png", 9.0, true],
		["swing", "Attack.png", 12.0, false], ["hurt", "Damage.png", 12.0, false],
		["dead", "Dead.png", 8.0, false]]},
	"芽苗史莱姆": {"path": "Sprout Slime/Blue", "cell": 32, "sheets": [
		["idle", "Idle.png", 5.0, true], ["walk", "Walk.png", 7.0, true],
		["swing", "Walk.png", 9.0, false], ["hurt", "Damage.png", 12.0, false],
		["dead", "Dead.png", 8.0, false]]},
	"毒花": {"path": "Venom Bloom/Purple", "cell": 48, "sheets": [
		["idle", "Idle.png", 5.0, true], ["walk", "Idle.png", 5.0, true],
		["swing", "Attack.png", 8.0, false], ["hurt", "Damage.png", 10.0, false],
		["dead", "Dead.png", 7.0, false]]},
	"尖刺怪": {"path": "Spike", "cell": 32, "sheets": [
		["idle", "idle.png", 5.0, true], ["walk", "idle.png", 6.0, true],
		["swing", "spitting.png", 10.0, false], ["hurt", "damage.png", 12.0, false],
		["dead", "dead.png", 8.0, false]]},
}

var side := "enemy"                # hero / ally / enemy
var kind := "刀客"                  # 刀客 / 弓手 / 晋升职业（神射手 狙击手...）
# 远程系都会放风筝：人的弓手系 + 哥布林的弓手/炸弹手
const ARCHER_KINDS := ["弓手", "神射手", "狙击手"] + GOBLIN_ARCHER_KINDS
func is_archer() -> bool:
	return kind in ARCHER_KINDS

# 哥布林 / 魔物判定（贴图、站位、配色都按这两条分叉）
func is_goblin() -> bool:
	return kind in GOBLIN_KINDS

func is_monster() -> bool:
	return kind in MONSTER_KINDS

# 这一路用的格子边长：毒花是 48x48, 其余 32x32
func _cell_size() -> int:
	if is_monster():
		return int(MONSTER_SHEETS.get(kind, {}).get("cell", 32))
	return CELL
# —— 骑兵 ——（晋升树转职而来, 见 Slaves.CLASSES; 骑枪冲锋 = 马上近战, 跑得快）
const MOUNTED_KINDS := ["骑兵", "枪骑兵", "重骑兵"]   # e41i: 补上满阶重骑兵（以前漏了, 满阶反而不骑马）
func is_mounted() -> bool:
	return kind in MOUNTED_KINDS
# 骑枪比刀长：骑马单位的贴身判定大一圈, 冲锋接敌更容易
func reach() -> float:
	return MELEE_RANGE + (14.0 if is_mounted() else 0.0)

# ---------------- 兵种相克（骑砍式三角）----------------
# 三类归一：近战步兵 foot / 弓手 archer / 骑兵 mounted。
#   步兵结阵拒马克骑兵  ->  骑兵冲阵克弓手  ->  弓手攒射克步兵
# 克制方打 COUNTER_WIN 倍, 被克方打 COUNTER_LOSE 倍, 同系 1.0。
# ❗倍率在「挥刀/中箭」那一刻按**双方兵种**算（见 _melee_attack 与 battle_map 的箭矢判定）。
const COUNTER_WIN := 1.35
const COUNTER_LOSE := 0.85
const CLASS_FOOT := "foot"
const CLASS_ARCHER := "archer"
const CLASS_MOUNTED := "mounted"

static func kind_class(k: String) -> String:
	if k in MOUNTED_KINDS:
		return CLASS_MOUNTED
	if k in ARCHER_KINDS:
		return CLASS_ARCHER
	return CLASS_FOOT

static func counter_mult(a_kind: String, d_kind: String) -> float:
	var a := kind_class(a_kind)
	var d := kind_class(d_kind)
	if a == d:
		return 1.0
	if (a == CLASS_FOOT and d == CLASS_MOUNTED) \
			or (a == CLASS_MOUNTED and d == CLASS_ARCHER) \
			or (a == CLASS_ARCHER and d == CLASS_FOOT):
		return COUNTER_WIN
	return COUNTER_LOSE

var max_hp := 20
var hp := 20
var atk := 4
# 速度一变，走路动画的帧率自动跟着重算（见 _sync_walk_speed）
var speed: float = 30.0:
	set(v):
		speed = v
		_sync_walk_speed()
var index := 0                     # 阵型槽位
var slave_data := {}               # ally 专用：直写的 Slaves 字典引用
var order := 1                     # ally 专用：0 移动到点 / 1 跟随 / 2 冲锋 / 3 驻守
var move_dest := Vector2.ZERO      # order 0 时的目的地
var face_when_arrived := Vector2.ZERO  # 走到目的地后朝哪儿（拖拽画阵型线时用，0 = 不管）
var squad := 1                     # ally 专用：第几编队（1/2/3，决定选中圈颜色）
var _arrived := false              # 已经走到集结点了（之后原地待命）

var _sprite: AnimatedSprite2D
var _facing: StringName = &"down"
var _cd := 0.0
var _dying := false
var _hp_root: Node2D
var _hp_fg: ColorRect
var _sel_ring: Sprite2D
var _detour := Vector2.ZERO     # 正在绕行时的固定方向（ZERO = 没在绕，见 _try_move）
var _detour_t := 0.0
var _stuck_t := 0.0             # 一动不动累计了多久（只对敌人用，见 _tick_stuck）
var _engage := false            # 本帧接战中（贴脸砍/站桩射，_tick_enemy 点亮）——stuck 别把输出当卡死
var _in_water := false          # 正在浅水里蹚（h-m：减速 + 半身入水贴片）
var _water_fx: Sprite2D         # 水位贴片：半透明水色横在腰上，进浅水才显示
var _stuck_from := Vector2.ZERO
var _atk_lock := false          # e17: 攻击动画播放中 —— 期间 _play 不许切回走/站

# ---------------- 士气（骑砍式：打崩了就溃逃） ----------------
# 每个人有一点士气(0~100)。两件事会耗它：同伴在身边战死（battle_map 喊 shock_morale）、
# 自己挨刀 / 血太薄。士气见底当场扔掉武器往自家来路跑 —— 溃逃 = 退出这场仗
# （胜负不再算他, 也不给经验金币）。所以这仗不一定打到最后一个人才分胜负:
# 一边崩了就是一边输, 跟骑砍一个样。
# ❗主角不吃这套 —— 玩家想走自己按 O 撤退, 不该被系统赶下场。
const MORALE_MAX := 100.0
const MORALE_SHOCK_RADIUS := 96.0   # 同伴倒在这个圈里才折损士气（离远了听不见）
const MORALE_HURT := 1.5            # 每挨 1 点伤害掉的士气
const MORALE_LOW_HP := 0.35         # 血线掉到这条线以下就开始持续泄气
const MORALE_DRAIN := 6.0           # 血薄时每秒泄多少士气

var morale := MORALE_MAX
var routing := false                # 已经溃逃（正在往自家来路退场）

func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	# 骑兵的帧是 48x48（马+人整幅画), 居中摆放时脚底在 +24 —— 原点约定是脚下,
	# 所以把精灵往上抬一帧半, 不然马会陷进地里半个身子。毒花(48x48)同理。
	_sprite.position = Vector2(0, _sprite_lift())
	_sprite.sprite_frames = _build_frames()
	_sprite.modulate = _base_tint()
	_sprite.play(&"idle_down")
	_sprite.animation_finished.connect(_on_attack_anim_done)
	add_child(_sprite)
	_sync_walk_speed()          # 按默认速度先把步伐帧率对一遍（battle_map 随后会改速度）
	_build_water_fx()
	_build_hp_bar()
	_build_sel_ring()
	_stuck_from = global_position

# 水位贴片（h-m 半身入水）：一条半透明水色横在腰上，两端渐隐，进浅水才显示。
# z 压在身体贴图之上 —— 下半身被水色盖住，就是「蹚水蹚到腰」的意思。
func _build_water_fx() -> void:
	_water_fx = Sprite2D.new()
	_water_fx.texture = _water_fx_tex()
	_water_fx.position = Vector2(0, -7)
	_water_fx.z_index = 1
	_water_fx.visible = false
	add_child(_water_fx)

func _water_fx_tex() -> ImageTexture:
	var img := Image.create_empty(28, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 28:
			var dx := (float(x) - 13.5) / 14.0
			var dy := (float(y) - 4.5) / 5.0
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			img.set_pixel(x, y, Color(0.43, 0.81, 0.91, 0.62 * (1.0 - d * 0.55)))
	return ImageTexture.create_from_image(img)

# 涉水状态：站进浅水格 -> 减速 + 显示水位贴片；上岸恢复（h-m 河谷涉水）
func _update_water() -> void:
	var b := _battle()
	var wet := false
	if b != null and b.has_method("is_shallow_at"):
		wet = bool(b.call("is_shallow_at", global_position))
	if wet == _in_water:
		return
	_in_water = wet
	if _water_fx != null:
		_water_fx.visible = wet
	_sync_walk_speed()          # 步频跟着实际移速重算：水里小碎步

# 当前实际移速：骑兵提速 1.25x（e27k 冲阵更快）；浅水里打折扣（三个 _tick 都走这里）
func _move_speed() -> float:
	var v := speed * (1.25 if is_mounted() else 1.0)
	return v * (WATER_MULT if _in_water else 1.0)

# 本方阵营的基础色调（被打闪红之后也要回到这个色, 见 take_damage）:
#   hero  = 淡钢色 —— 披甲上阵的中世纪主角（平时种田穿布衣, 打仗才着甲）
#   ally  = 冷青打底 * 装甲档位色 —— 职业越高披挂越亮（布衣 -> 银甲 -> 金铜甲）
#   enemy = 红皮（野寇海寇）
func _base_tint() -> Color:
	match side:
		"enemy":
			# e49: 三种敌人各一档色 —— 人形野寇偏红 / 哥布林偏绿 / 魔物偏紫
			if is_goblin():
				return Color(0.9, 1.0, 0.85)
			if is_monster():
				return Color(1.0, 0.85, 1.0)
			return Color(1.0, 0.55, 0.5)
		"ally":
			# 冷青打底 * 装甲档位色 —— e29c: 个人配色(发色/服装)烘在贴图层
			# (slave_npc 的 RECIPES 色带改色), modulate 这层只剩阵营和装甲
			return Color(0.85, 0.95, 1.0) * Slaves.armor_tint(kind)
	return Color(0.9, 0.94, 1.03)

# 下标圈：被选中的部队脚下一圈亮环（"这轮听我指挥的是谁"一眼看清）
# ❗不能用 z_index = -1 压到贴图底下 —— 那是相对父节点累加的，会连地块一起压过去，
#   圈就被地图盖掉了。老老实实插到树序最前面（同 z 时先画的在下边）。
func _build_sel_ring() -> void:
	if side != "ally":
		return
	_sel_ring = Sprite2D.new()
	_sel_ring.texture = _ring_tex()
	_sel_ring.modulate = Voyage.squad_color(squad)
	_sel_ring.position = Vector2(0, 2)
	_sel_ring.visible = false
	add_child(_sel_ring)
	move_child(_sel_ring, 0)

# 白色椭圆环，颜色靠 modulate 上（好按编队换色）
func _ring_tex() -> ImageTexture:
	var w := 26
	var h := 12
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var nx := (float(x) + 0.5 - float(w) / 2.0) / (float(w) / 2.0)
			var ny := (float(y) + 0.5 - float(h) / 2.0) / (float(h) / 2.0)
			var r := sqrt(nx * nx + ny * ny)
			# 只在椭圆环带里上色（0.72~1.0 之间），其余透明
			img.set_pixel(x, y, Color(1, 1, 1, 0.9) if r > 0.72 and r <= 1.02
				else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

# 精灵往上抬多少：素材是「整幅画居中」摆的, 而节点原点约定在脚下 —— 把画面的
# 底边(脚/马蹄/花根)提到跟 32x32 步兵同一条线上。实测各素材「底边落在格子里的行号」
# 不同, 所以按帧高分档抬（32x32 步兵底边在 25/32, 32x48 马在 46/48, 48x48 毒花在 47/48）。
func _sprite_lift() -> float:
	if is_mounted():
		return -29.0                       # 马: 32x48
	if _cell_size() == 48:
		return -30.0                       # 毒花: 48x48
	return -16.0

func _build_frames() -> SpriteFrames:
	if is_mounted():
		return _build_mount_frames()
	if is_goblin():
		return _build_goblin_frames()
	if is_monster():
		return _build_monster_frames()
	var specs: Array
	if side == "hero":
		# e49: 补上「受击」(Damage.png) 与「倒地」(Dead.png) —— 每个预制角色目录都自带这两张,
		# 都是 128x96 = 4 帧 x 3 行, 跟 Idle 同一套网格。
		specs = [["idle", JOSH_IDLE, 4, 7.0, true], ["walk", JOSH_WALK, JOSH_WALK_FRAMES, 10.0, true],
			["swing", MODEL_PATH % ["Josh", "Sword.png"], 10, 26.0, false],
			["shoot", MODEL_PATH % ["Josh", "Bow and Arrow.png"], 7, 15.0, false],
			["hurt", MODEL_PATH % ["Josh", "Damage.png"], 4, 14.0, false],
			["dead", MODEL_PATH % ["Josh", "Dead.png"], 4, 9.0, false]]
	else:
		var model: String = MODELS[index % MODELS.size()]
		if side == "ally":
			# e29c: 本方伙伴的贴图走局部改色管线 —— 战场上的小兵跟岛上同脸同色
			specs = [["idle", SNPC.sheet_texture(model, "Idle.png", index), 4, 7.0, true],
				["walk", SNPC.sheet_texture(model, "Walk.png", index), 6, 10.0, true],
				["swing", SNPC.sheet_texture(model, "Sword.png", index), 10, 26.0, false],
				["shoot", SNPC.sheet_texture(model, "Bow and Arrow.png", index), 7, 15.0, false],
				["hurt", SNPC.sheet_texture(model, "Damage.png", index), 4, 14.0, false],
				["dead", SNPC.sheet_texture(model, "Dead.png", index), 4, 9.0, false]]
		else:
			# 敌人保持原图: 红皮 modulate 一罩, 个人配色没有意义
			specs = [["idle", MODEL_PATH % [model, "Idle.png"], 4, 7.0, true],
				["walk", MODEL_PATH % [model, "Walk.png"], 6, 10.0, true],
				["swing", MODEL_PATH % [model, "Sword.png"], 10, 26.0, false],
				["shoot", MODEL_PATH % [model, "Bow and Arrow.png"], 7, 15.0, false],
				["hurt", MODEL_PATH % [model, "Damage.png"], 4, 14.0, false],
				["dead", MODEL_PATH % [model, "Dead.png"], 4, 9.0, false]]
	return _make_frames(specs)

# 哥布林的帧：素材在 Enemy/Goblins/<兵种>/ 下, 格 32x32 且上下带 16px 白边。
func _build_goblin_frames() -> SpriteFrames:
	var d: Dictionary = GOBLIN_SHEETS.get(kind, {})
	if d.is_empty():
		return _build_foot_frames()      # 表里没这一路: 退回步兵, 别让战斗崩掉
	var dir := String(d.get("dir", ""))
	var specs: Array = []
	for s in d.get("sheets", []):
		specs.append([s[0], GOBLIN_DIR % [dir, String(s[1])], s[2], s[3]])
	return _make_strip_frames(specs, CELL)

# 魔物的帧：素材散在 Enemy/ 各子目录下, 多半格 32x32（毒花 48x48）。
func _build_monster_frames() -> SpriteFrames:
	var d: Dictionary = MONSTER_SHEETS.get(kind, {})
	if d.is_empty():
		return _build_foot_frames()
	var sub := String(d.get("path", ""))
	var cell := int(d.get("cell", 32))
	var specs: Array = []
	for s in d.get("sheets", []):
		specs.append([s[0], MONSTER_DIR % [sub, String(s[1])], s[2], s[3]])
	return _make_strip_frames(specs, cell)

# 刷子：一张图里横向 N 帧、纵向若干行（下/上/侧）。帧数、行数都按图尺寸自动数。
# ❗e49 实测(逐像素量过): Enemy/Goblins 与 Enemy/ 下这些素材是 **纵向 4 行 x 32px
#   一格、四周不留白边**（早先误判成「3 行 + 上下各 16px 白边」—— 图高同样是 128,
#   但 128/32 = 4 行, 不是 16+96+16, 按 16 偏移切会横着切到两只怪身上）。
#   行序: 0 朝下 / 1 朝上 / 2 侧面(默认朝右, 跟预制「人」同一约定) / 3 是 2 的镜像(不用)。
#   只有一行的素材（毒花 48x48、小史莱姆）三向共用第 0 行。
func _make_strip_frames(specs: Array, cell: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for key in specs:
		var tex: Texture2D = load(String(key[1]))
		if tex == null:
			continue
		var n := maxi(1, int(tex.get_width() / cell))
		var rows := maxi(1, int(tex.get_height() / cell))
		for d in DIR_ROW.keys():
			var an := StringName("%s_%s" % [key[0], d])
			sf.add_animation(an)
			sf.set_animation_loop(an, bool(key[3]))
			sf.set_animation_speed(an, float(key[2]))
			var row: int = mini(DIR_ROW[d], rows - 1)
			for i in n:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * cell, row * cell, cell, cell)
				sf.add_frame(an, at)
	return sf

# ---------------- 骑兵的帧（马匹模型） ----------------
# 素材: Pre-made/<人>/Horse/Horse run.png —— 192x144 = **6 帧 x 3 行的 32x48 网格**
# (e16c: 早期误当 4 帧 x 48x48 切 —— 素材帧宽其实只有 32, 48px 步进把人马劈成
#  两半, 拼出「上半个人 + 半匹马」的怪图, 用户截图实锤)。三行顺序 下/上/侧
# (DIR_ROW 直接复用); e27b: 侧向帧实测默认朝**右**（e16c 记反了）, 翻转逻辑见 _play。
# idle = 每行第 0 帧（勒马站立, 单帧动画）; walk = 整行 6 帧（策马跑动）。
# ❗cavalry 没有专门的下/上 idle 图（Horse idle.png 只有侧面一行 6 帧）,
#   就统一用 run 图的首帧 —— 像素小画上勒马跟跑马是同一个姿势, 没人看得出破绽。
const HORSE_RUN := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Alex/Horse/Horse run.png"
const MOUNT_FRAME_W := 32
const MOUNT_FRAME_H := 48
func _build_mount_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var tex: Texture2D = load(HORSE_RUN)
	if tex == null:
		return _build_foot_frames()       # 贴图丢失: 退回步兵, 别让战斗崩掉
	for d in DIR_ROW.keys():
		var row: int = DIR_ROW[d]
		for spec in [["idle", 1, 4.0], ["walk", 6, 8.0]]:
			var an := StringName("%s_%s" % [spec[0], d])
			sf.add_animation(an)
			sf.set_animation_loop(an, true)
			sf.set_animation_speed(an, float(spec[2]))
			for i in int(spec[1]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * MOUNT_FRAME_W, row * MOUNT_FRAME_H,
					MOUNT_FRAME_W, MOUNT_FRAME_H)
				sf.add_frame(an, at)
	return sf

# 步兵抽帧共用器: specs = [名字, 贴图路径, 帧数, fps, 是否循环] —— 32x32 x 3 行。
func _make_frames(specs: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for key in specs:
		# e29c: key[1] 可能是路径字符串, 也可能是改色管线烘出来的 Texture2D
		var tex: Texture2D = key[1] if key[1] is Texture2D else load(key[1])
		if tex == null:
			continue
		for d in DIR_ROW.keys():
			var an := StringName("%s_%s" % [key[0], d])
			sf.add_animation(an)
			sf.set_animation_loop(an, bool(key[4]))
			sf.set_animation_speed(an, float(key[3]))
			var row: int = DIR_ROW[d]
			for i in int(key[2]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * CELL, row * CELL, CELL, CELL)
				sf.add_frame(an, at)
	return sf

# 原来的步兵抽帧（骑兵贴图丢失时兜底用），现在只是 _make_frames 的另一份 specs。
func _build_foot_frames() -> SpriteFrames:
	var specs: Array
	if side == "hero":
		specs = [["idle", JOSH_IDLE, 4, 7.0, true], ["walk", JOSH_WALK, JOSH_WALK_FRAMES, 10.0, true],
			["swing", MODEL_PATH % ["Josh", "Sword.png"], 10, 26.0, false],
			["shoot", MODEL_PATH % ["Josh", "Bow and Arrow.png"], 7, 15.0, false]]
	else:
		var model: String = MODELS[index % MODELS.size()]
		specs = [["idle", MODEL_PATH % [model, "Idle.png"], 4, 7.0, true],
			["walk", MODEL_PATH % [model, "Walk.png"], 6, 10.0, true],
			["swing", MODEL_PATH % [model, "Sword.png"], 10, 26.0, false],
			["shoot", MODEL_PATH % [model, "Bow and Arrow.png"], 7, 15.0, false]]
	return _make_frames(specs)

# 速度是唯一真相源：帧率 = 速度 * 帧数 / 步幅（原理同 slave_npc.gd）。
# ❗主角不动 —— 他的手感是玩家已经习惯了的，别顺手改掉。
func _sync_walk_speed() -> void:
	if side == "hero" or _sprite == null or _sprite.sprite_frames == null:
		return
	var frames := 6.0
	# 马步比人步长一截（步幅 x1.5）—— 不然骑兵 48 速套人腿步频, 四条腿蹬得像抽风
	var stride := WALK_STRIDE_PX * (1.5 if is_mounted() else 1.0)
	# 用实际移速（涉水打折）反推步频，水里就不会「腿在蹬、人滑不动」
	var base_fps := minf(WALK_FPS_CAP, _move_speed() * frames / stride)
	for d in DIR_ROW.keys():
		var an := StringName("walk_%s" % d)
		if _sprite.sprite_frames.has_animation(an):
			# e49: 哥布林/魔物的走图帧数跟「人」不一样（4~8 帧都有）—— 按每条动画
			# 实际的帧数折算, 免得素材帧数一多/一少就走成滑步或抽腿。
			var n := maxi(1, _sprite.sprite_frames.get_frame_count(an))
			var fps := base_fps * float(n) / frames
			_sprite.sprite_frames.set_animation_speed(an, minf(WALK_FPS_CAP, fps))

# 血条：24x3 的细条，原点居中（节点原点是脚底，血条挂在头顶 -40 处）。
# ❗坑：底板 bg 缩到 (-12, 0) 让整条居中，但红绿那根 fg 忘了跟着挪，留在 (0, 0) ——
#   于是左半边露出的是黑底板（看着就是"左边有一块黑的"），右半边还捅出底板外一截。
#   两根条必须用同一个 x 偏移，宽度变化也从同一个左边算起。
const HP_BAR_W := 24.0
const HP_BAR_X := -12.0

func _build_hp_bar() -> void:
	_hp_root = Node2D.new()
	_hp_root.position = Vector2(0, -40)
	_hp_root.z_index = 20
	var bg := ColorRect.new()
	bg.size = Vector2(HP_BAR_W, 3)
	bg.position = Vector2(HP_BAR_X, 0)
	bg.color = Color(0.1, 0.1, 0.1, 0.9)
	_hp_root.add_child(bg)
	_hp_fg = ColorRect.new()
	_hp_fg.size = Vector2(HP_BAR_W, 3)
	_hp_fg.position = Vector2(HP_BAR_X, 0)      # ← 跟底板同一个偏移，别再漏了
	_hp_fg.color = Color(0.3, 0.85, 0.35) if side != "enemy" else Color(0.9, 0.25, 0.2)
	_hp_root.add_child(_hp_fg)
	_hp_root.visible = false
	add_child(_hp_root)

func _process(delta: float) -> void:
	if _dying:
		return
	_cd = maxf(0.0, _cd - delta)
	_tick_morale(delta)             # 血薄的会持续泄气（士气见底就地溃逃）
	match side:
		"hero":
			_tick_hero(delta)
		"ally":
			_tick_ally(delta)
		"enemy":
			_tick_enemy(delta)
	_tick_stuck(delta)
	_update_water()

# ---------------- 「卡住」自检（只对敌人）----------------
# AI 只会朝目标直线走 + 贴墙滑行，没有真正的寻路。所以「目标在河对岸、而附近
# 没有浅滩」这种局，它能顶在岸边顶到天荒地老。
# ❗这不是小事：胜负判定是「场上敌人一个不剩」，只要有一个敌人永远过不来，
#   玩家打死所有够得着的敌人之后，战斗**永远结束不了** —— 被困在战场里，
#   这就是「战斗后不能退出」的另一半原因。
# 所以卡够久就判它**逃了**（山贼海寇看打不赢自己散伙），从场上撤掉。
func _tick_stuck(delta: float) -> void:
	if side != "enemy":
		return
	# e27j: 接战中（贴脸互砍 / 站桩放风筝射箭）原地不动是正常输出不是卡住 ——
	#   旧版会把站定射箭的敌弓手射着射着判成「逃走了」。
	if _engage:
		_stuck_t = 0.0
		_stuck_from = global_position
		return
	_stuck_t += delta
	if _stuck_t < STUCK_LIMIT:
		return
	_stuck_t = 0.0
	# e27j: 旧判定「挪过 2px 就重置」挡不住贴墙来回蹭——滑行每次都成功，
	#   净位移≈0 却总能重置计时，敌人能顶到天荒地老。改成 6 秒窗口结净位移：
	#   没接战、6 秒净挪不到 5px，就是真的过不去，判逃。
	if global_position.distance_squared_to(_stuck_from) > 25.0:
		_stuck_from = global_position
		return
	_flee()

# 逃走 = 跟倒下一样退出战场（_count_foes 会把它算掉），只是不给经验金币
func _flee() -> void:
	if _dying:
		return
	_dying = true
	_float_text("逃走了", Color(0.82, 0.82, 0.78))
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		died.emit(self)
		queue_free())

# ---------------- 士气 / 溃逃 ----------------
# 外场折损士气：battle_map 在有人阵亡时, 朝倒地处周围的同营人喊一声（见 _morale_shock）
func shock_morale(amount: float) -> void:
	if side == "hero" or _dying or routing:
		return
	morale = maxf(0.0, morale - amount)
	if morale <= 0.0:
		_rout()

# 血太薄的会持续泄气 —— 这一条保证拉锯久了总有一边先崩,
# 不会场场都打成「全员战至最后一人」。
func _tick_morale(delta: float) -> void:
	if side == "hero" or _dying or routing:
		return
	if float(hp) / float(maxi(1, max_hp)) >= MORALE_LOW_HP:
		return
	morale = maxf(0.0, morale - MORALE_DRAIN * delta)
	if morale <= 0.0:
		_rout()

# 溃逃：扔下武器往自家来路跑, 跑出画面就算退场（战况里跟倒下一样被划掉）。
# ❗立刻置 _dying, 跟 _die/_flee 同一套 —— 置了就再没人索敌到它、也挨不着刀,
#   只剩 tween 还在把它往外挪。别改成「靠 _process 慢慢跑」: _dying 会把 _process 掐掉。
func _rout() -> void:
	if _dying or routing:
		return
	routing = true
	_dying = true
	_float_text("溃逃!", Color(0.95, 0.82, 0.5))
	# 逃跑方向 = 自家来路（我方朝左, 敌方朝右）, 顺手撒开一点别挤成一串
	var away := Vector2(-1.0, randf_range(-0.35, 0.35))
	if side == "enemy":
		away = Vector2(1.0, randf_range(-0.35, 0.35))
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + away.normalized() * 40.0, 0.5)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		died.emit(self)
		queue_free())

# ---------------- 主角：WASD 移动 + 左键挥剑（e15h: 不再自动攻击） ----------------
func _tick_hero(delta: float) -> void:
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if mv != Vector2.ZERO:
		_try_move(delta, mv * _move_speed() * delta)
		_facing = _dir_name(mv)
		_play(&"walk")
	else:
		_play(&"idle")
	_update_tree_fade()

# e16f: 走到树后被树冠整个盖住 = 玩家视角「主角贴图凭空消失几秒」(用户实测)。
# 星露谷式解法: 挡住主角的那棵树临时降到半透明, 走出树冠立刻恢复。
# e27b: 判定按树的真身矩形算 —— 帧是 32x48, sprite 从节点往上铺 45px（-45..+3）、
# 横向 ±16; 主角自身高约 24px 宽约 20px。旧阈值(dy<44 / dx<18)漏了 44~53 段和
# 树冠边缘一圈, 主角斜着穿树梢还是会隐身几秒, 现在放宽到完整覆盖。
func _update_tree_fade() -> void:
	for t in get_tree().get_nodes_in_group("battle_tree"):
		var tr := t as Node2D
		if tr == null:
			continue
		var dy := tr.global_position.y - global_position.y
		var behind := dy > 4.0 and dy < 54.0 \
			and absf(tr.global_position.x - global_position.x) < 24.0
		var target := 0.4 if behind else 1.0
		if absf(tr.modulate.a - target) > 0.01:
			tr.modulate.a = target

# 左键挥剑：朝鼠标方向挥一刀，够得着的敌人吃伤害（挥空也出弧光，0.4s 冷却防连点狂砍）。
# battle_map._unhandled_input 里左键按下时调 —— 指挥伙伴的同一击顺手也挥。
func swing_sword(at: Vector2) -> void:
	if _dying or _cd > 0.0:
		return
	_cd = 0.4
	_facing = _dir_name(at - global_position)
	var foe := _nearest_foe(reach() + 6.0)
	if foe != null:
		_melee_attack(foe)
	else:
		_play_attack(at, false)     # e17: 挥空也出真挥剑帧（骑兵回光效）

# ---------------- 伙伴：听指挥 ----------------
# 口令存在自己身上（order），这样按 1/2 换兵种时，没被选中的那批人
# 还按上一道口令继续干自己的活，跟骑砍一个意思。
func _tick_ally(delta: float) -> void:
	var foe := _nearest_foe(9999.0)
	# e41i: 骑兵优先切后排 —— 身边(reach 内)没敌人挡路时, 改扑敌方最近的弓手。
	# （正面已经贴脸了就先解决贴脸的, 不兴骑着马从人堆里穿过去）
	if is_mounted() and foe != null:
		var arm := _foe_archer()
		if arm != null and _nearest_foe(reach() + 8.0) == null:
			foe = arm
	var dest := global_position
	var move := false
	match order:
		0:      # F1 点地图 / 拖阵型线：开到自己的位置，到了就原地待命
			if not _arrived:
				dest = move_dest
				if global_position.distance_to(dest) > ARRIVE_DIST:
					move = true
				else:
					_arrived = true
					# 站定后转向前方（拖线展开时线的前方就是部队正面）
					if face_when_arrived != Vector2.ZERO:
						_facing = _dir_name(face_when_arrived)
		1:      # F2 跟随我：围着主角站，手边有敌人就打
			var hero := _hero()
			if hero != null:
				dest = hero.global_position + FORMATION[index % FORMATION.size()]
				move = global_position.distance_to(dest) > ARRIVE_DIST
				# e27k: 敌人贴到身边一小圈就迎上去（近战），打完自动回编队位
				if not is_archer() and foe != null:
					var fd := global_position.distance_to(foe.global_position)
					if fd > reach() and fd <= reach() + ENGAGE_LEASH:
						dest = foe.global_position
						move = true
				# e27j: 弓手跟随但敌人在射程外时别干瞪眼 —— 推进到射程边缘再放风筝
				#   （差 5px 够不着、主角又不自动攻击，全场会冻在对峙距离上）
				elif is_archer() and foe != null \
						and global_position.distance_to(foe.global_position) > ARCHER_RANGE:
					dest = foe.global_position \
						+ (global_position - foe.global_position).normalized() * (ARCHER_RANGE - 10.0)
					move = true
		2:      # F3 冲锋：扑向最近的敌人（骑兵绕侧后包抄）
			if foe != null:
				dest = foe.global_position
				move = global_position.distance_to(dest) > reach()
				if is_mounted() and move \
						and global_position.distance_to(dest) > reach() + 24.0:
					dest = _flank_dest(foe)
		3:      # F4 驻守：不动窝，来了敌人才砍
			pass
	# 弓手系不贴脸：够近就站定射箭（晋升后的 神射手/狙击手 同样放风筝）
	if foe != null:
		var d := global_position.distance_to(foe.global_position)
		if is_archer():
			if d <= ARCHER_RANGE:
				move = d < ARCHER_KEEP          # 太近了往后撤
				_shoot_if_ready(foe)
				_face_to(foe.global_position)
				_play(&"idle")
				return
		elif d <= reach():
			move = false
			_face_to(foe.global_position)
			_play(&"idle")
			if _cd <= 0.0:
				_cd = ATTACK_CD
				_melee_attack(foe)
			return
	if move:
		if _try_move(delta, (dest - global_position).normalized() * _move_speed() * delta):
			_facing = _dir_name(dest - global_position)
			_play(&"walk")
		else:
			_play(&"idle")
	else:
		_play(&"idle")

# ---------------- 敌人：索敌 + 弓手放风筝 ----------------
func _tick_enemy(delta: float) -> void:
	_engage = false                 # 每帧重置，攻击分支里再点亮（_tick_stuck 要看）
	var target := _nearest_target()
	if target == null:
		_play(&"idle")
		return
	var d := global_position.distance_to(target.global_position)
	if is_archer():
		if d <= ARCHER_RANGE:
			if d < ARCHER_KEEP:
				_try_move(delta, (global_position - target.global_position).normalized() * _move_speed() * delta)
				_play(&"walk")
			else:
				_play(&"idle")
			_face_to(target.global_position)
			_shoot_if_ready(target)
			_engage = true          # 站定放风筝输出中：不是卡住
			return
	if d <= reach():
		_face_to(target.global_position)
		_play(&"idle")
		_engage = true              # 贴脸互砍中：不是卡住
		if _cd <= 0.0:
			_cd = ATTACK_CD
			_melee_attack(target)
		return
	if _try_move(delta, (_chase_dest(target, d) - global_position).normalized()
			* _move_speed() * delta):
		_facing = _dir_name(target.global_position - global_position)
		_play(&"walk")
	else:
		_play(&"idle")          # 被挡住（水/树）：原地跺步

# e27k 骑兵 AI：离目标远时不走直线 —— 朝侧后方弧线包抄（绕后），两人一左一右
# （index 奇偶分边）包过去；进入两步内改直取本体，不会绕着目标原地打转。
func _chase_dest(target: Node2D, d: float) -> Vector2:
	if is_mounted() and d > reach() + 24.0:
		return _flank_dest(target)
	return target.global_position

func _flank_dest(foe: Node2D) -> Vector2:
	var to_foe := foe.global_position - global_position
	var dir := to_foe.normalized() if to_foe.length_squared() > 0.001 else Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x) * (14.0 if index % 2 == 0 else -14.0)
	# e41i: 目标是弓手 -> 落点定在他**身后**一点（骑马从旁边兜过去, 逼他回头）
	var back := 12.0 if (foe.has_method("is_archer") and bool(foe.call("is_archer"))) else -10.0
	return foe.global_position + dir * back + perp

# e41i: 敌方最近的弓手（骑兵切后排的优先目标）；场上一张弓都没有就返回 null
func _foe_archer() -> Node2D:
	var b := _battle()
	if b == null or not b.has_method("nearest_archer_of"):
		return null
	var a = b.call("nearest_archer_of", self, 9999.0)
	return a if is_instance_valid(a) else null

# ---------------- 接受指挥（battle_map 发下来） ----------------
func set_order(cmd: int, dest := Vector2.ZERO, face_dir := Vector2.ZERO) -> void:
	order = cmd
	if cmd == 0:
		move_dest = dest
		face_when_arrived = face_dir
		_arrived = false

func set_selected(v: bool) -> void:
	if _sel_ring == null:
		return
	if v:
		_sel_ring.modulate = Voyage.squad_color(squad)   # 编队颜色可能刚改过
	_sel_ring.visible = v

# ---------------- 移动（被水/树挡住就贴着绕过去） ----------------
# ❗这里有个把整场战斗锁死的坑，改之前一定要看清：
#   贴墙滑行原来写的是 `if absf(step.x) > 0.1 and ...` —— 阈值 0.1 是**绝对像素**，
#   可速度 28、60 帧的时候一步才 0.47 像素：正面朝着目标走时，垂直于墙的那个分量
#   只有 0.01（目标几乎和它同一水平线），连 0.1 都够不上，于是滑行那两条分支
#   **整条被跳过**，直接 return false。结果：任何「正面顶上树 / 河岸」的单位
#   从此一动不动 —— 敌人的刀客会、被你下令冲锋的伙伴也会。敌人永远清不完
#   -> 胜负判定不触发 -> 玩家出不去战场（这就是「战斗后不能退出」的真凶）。
#   现在两步走：
#     1) 滑行位移按**整步长**算（不是按被挡那一轴的分量，见下面的坑 2）；
#     2) 正面顶死时退一步找**侧向绕行**，方向锁定 DETOUR_TIME 秒，免得两帧一抖
#        在原地抽搐；同一格上挤着两个人时 index 奇偶不同，各走各的一边。
func _try_move(delta: float, step: Vector2) -> bool:
	var b := _battle()
	if step.length_squared() < 0.0000001:
		return false
	var next := global_position + step
	if b == null or not b.call("is_blocked_at", next):
		global_position = next
		_detour = Vector2.ZERO
		return true
	# 贴墙滑行：主方向被挡，就把整步让给另一轴（横着蹭过去）。
	# ❗这里是两个坑叠在一起，别改回去：
	#   1) 判定阈值原来是绝对像素 0.1，而一步才 0.47、垂直分量只有 0.01，
	#      滑行那两条分支整条被跳过 -> 顶住树的单位一动不动；
	#   2) 就算阈值改成相对值，位移写 `step.y`（0.01 像素）照样等于原地不动：
	#      它小到连自己所在格的边界都跨不过去，is_blocked_at 永远放行，
	#      于是每帧"成功"滑 0.01 像素 + return true，绕行分支一辈子进不去。
	#   所以位移必须用 sl（整步长），方向只取正负号；
	#   某一轴恰好为 0（纯水平朝树走）时 signf 给 0，自动落到下面的绕行逻辑。
	var sl := step.length()
	var slide := Vector2.ZERO
	if absf(step.x) >= absf(step.y):
		slide = Vector2(0.0, signf(step.y) * sl)      # 主要在横着走 -> 竖着蹭
	else:
		slide = Vector2(signf(step.x) * sl, 0.0)      # 主要在竖着走 -> 横着蹭
	if slide != Vector2.ZERO and _move_if_free(b, slide):
		return true
	# 正面顶死：按上一次选定的绕行方向横着挪；方向过期了再重新挑
	if _detour_t > 0.0:
		_detour_t -= delta
		if _move_if_free(b, _detour * step.length()):
			return true
	for d in _detour_tries(step):
		if _move_if_free(b, d * step.length()):
			_detour = d
			_detour_t = DETOUR_TIME
			return true
	return false

func _move_if_free(b: Node, step: Vector2) -> bool:
	var p := global_position + step
	if b.call("is_blocked_at", p):
		return false
	global_position = p
	return true

# 绕行的候选方向 = 垂直于前进方向的两个侧向。
# 谁先试按 index 的奇偶分：一堆人堵在同一棵树上时不会全往同一边挤。
func _detour_tries(step: Vector2) -> Array:
	var n := Vector2(-step.y, step.x)
	if n.length_squared() < 0.0000001:
		n = Vector2(0.0, 1.0)
	n = n.normalized()
	return [n, -n] if index % 2 == 0 else [-n, n]

# ---------------- 攻击 ----------------
func _melee_attack(target: Node2D) -> void:
	_stuck_t = 0.0            # 能在原地砍人也算"有事干"，别被当成卡住（见 _tick_stuck）
	_play_attack(target.global_position, false)   # e17: 真挥剑帧(骑兵没攻击帧回光效)
	var dir := (target.global_position - global_position).normalized()
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position + dir * 6.0, 0.08)
	tw.tween_property(self, "global_position", global_position, 0.1)
	# 兵种相克：这把刀砍下去先按双方兵种过一遍倍率（长枪拒马 / 马踏弓阵 / 箭雨压步兵）
	var dmg := int(round(float(atk) * counter_mult(kind, String(target.get("kind")))))
	target.call("take_damage", dmg, side == "hero")
	if side == "hero":        # e27k: 主角砍中 = 轻震一下（力度收敛，别晃眼）
		var b := _battle()
		if b != null and b.has_method("shake"):
			b.call("shake", 0.7)
	Audio.play_sfx("chop", -14.0, randf_range(0.9, 1.1))

func _shoot_if_ready(target: Node2D) -> void:
	if _cd > 0.0:
		return
	_cd = 1.6
	_stuck_t = 0.0            # 站着放箭也算"有事干"（见 _tick_stuck）
	_play_attack(target.global_position, true)    # e17: 真拉弓帧(骑兵回光效)
	var b := _battle()
	if b != null:
		# e27j 修复: 方向向量必须与箭起点(胸口)同参考点, 否则残局站定后弹道
		# 恒定平行偏移(~14px)擦肩而过 —— 方向算的是"脚底->目标胸口", 箭却从胸口出发
		var from := global_position + Vector2(0, -14)
		# 箭矢带上射手的兵种 —— battle_map 命中时按「谁放的箭 x 谁挨的箭」算相克
		b.call("spawn_arrow", from,
			(target.global_position + Vector2(0, -10) - from).normalized(), atk, side, kind)
	Audio.play_sfx("chop", -18.0, 1.4)

# e17: 真攻击动画 —— 朝向目标播 Sword.png(10 帧挥砍)/Bow and Arrow.png(7 帧拉弓)。
# 非循环, 播完 animation_finished 里解锁 _atk_lock 回 idle。骑兵马素材没有攻击帧,
# 兜底回 e15h 的手绘光效。
func _play_attack(at: Vector2, is_bow: bool) -> void:
	var an := _anim_name(&"shoot" if is_bow else &"swing")
	if is_mounted() or not _sprite.sprite_frames.has_animation(an):
		_attack_fx(at, is_bow)
		return
	_facing = _dir_name(at - global_position)
	_atk_lock = true
	_sprite.play(an)
	_sprite.flip_h = _facing == &"left"

# 攻击动画播完(非循环动画的 animation_finished): 解锁, 先站一拍, tick 再接手
# ❗倒地中不许被这条拽回站姿 —— dead 也是非循环动画, 播完会误触发这里。
func _on_attack_anim_done() -> void:
	if _dying:
		return
	_atk_lock = false
	_play(&"idle")

# 受击动画（e49）：挨了一下就闪「挨打」动作 —— 非循环, 播完 animation_finished
# 里自动解锁回站（复用 _on_attack_anim_done）。没这路素材的单位直接跳过。
func _play_hurt() -> void:
	var an := _anim_name(&"hurt")
	if not _sprite.sprite_frames.has_animation(an):
		return
	_atk_lock = true
	_sprite.play(an)
	_sprite.flip_h = _facing == &"left"

# 攻击光效（e15h，骑兵专用兜底）：马素材没有攻击帧，用一道手绘光效当攻击动作
# —— 挥剑 = 白亮弧光；拉弓 = 一弯弓 + 搭着的箭。0.16 秒淡出。
func _attack_fx(at: Vector2, is_bow: bool) -> void:
	var fx := AtkFx.new()
	fx.bow = is_bow
	var dir := at - global_position
	dir = Vector2.DOWN if dir.length_squared() < 0.001 else dir.normalized()
	fx.position = dir * 9.0 + Vector2(0, -12)     # 挂在胸口高度，朝目标前方探出去
	fx.rotation = dir.angle()
	add_child(fx)
	var tw := create_tween()
	tw.tween_property(fx, "modulate:a", 0.0, 0.16)
	tw.tween_callback(fx.queue_free)

class AtkFx extends Node2D:
	var bow := false
	func _draw() -> void:
		if bow:
			draw_arc(Vector2.ZERO, 6.5, -1.15, 1.15, 10, Color(0.5, 0.36, 0.2, 0.95), 1.6)
			draw_line(Vector2(-1.5, 0), Vector2(6.0, 0), Color(0.82, 0.84, 0.88, 0.9), 1.2)
		else:
			draw_arc(Vector2.ZERO, 12.5, -0.95, 0.95, 12, Color(1.0, 0.97, 0.86, 0.95), 2.4)
			draw_arc(Vector2.ZERO, 9.5, -0.7, 0.7, 10, Color(1.0, 1.0, 1.0, 0.55), 1.5)

func take_damage(n: int, from_hero := false) -> void:
	if _dying:
		return
	hp = maxi(0, hp - n)
	# 挨刀也折损士气（主角除外: 主角的士气就是玩家自己）
	if side != "hero":
		morale = maxf(0.0, morale - float(n) * MORALE_HURT)
	_hp_root.visible = hp < max_hp
	_hp_fg.size.x = HP_BAR_W * float(hp) / float(max_hp)     # 左端固定，从右边往里缩
	if side == "hero":        # e15h: 主角挨打 = 屏幕震一下（e27k 力度减半）
		var b := _battle()
		if b != null and b.has_method("shake"):
			b.call("shake", 1.5)
	if from_hero:             # e27k: 主角打出的伤害 = 大号金白飘字（打击感）
		_float_text("-%d" % n, Color(1.0, 0.97, 0.75), 17)
	else:
		_float_text("-%d" % n, Color(1, 0.85, 0.4))
	_sprite.modulate = Color(1.0, 0.35, 0.3) if side == "enemy" else Color(1.0, 0.5, 0.45)
	var base := _base_tint()
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", base, 0.18)
	match side:
		"hero":
			Legion.damage_player(n)       # 数据层同步扣（下场仗还接着疼）
		"ally":
			if not slave_data.is_empty():
				slave_data["hp"] = maxi(0, int(slave_data.get("hp", 30)) - n)
	if hp <= 0:
		_die()
	elif morale <= 0.0:
		_rout()          # 没被打死, 但心气没了 —— 当场溃逃（骑砍式的「打崩」）
	else:
		_play_hurt()     # e49: 挨了一下, 闪一下受击动作

func _die() -> void:
	_dying = true
	Audio.play_sfx("chop", -8.0, 0.7)
	_float_text("倒下了", Color(1, 0.5, 0.4))
	# e49: 有倒地素材就先摆倒地姿势（非循环, 停在最后一帧）, 停一拍再淡出,
	#   不再是一被砍就整块淡掉 —— 「倒下」这个动作看得见。
	var an := _anim_name(&"dead")
	var has_dead := _sprite.sprite_frames.has_animation(an)
	if has_dead:
		_sprite.play(an)
		_sprite.flip_h = _facing == &"left"
	var tw := create_tween()
	if has_dead:
		tw.tween_interval(0.3)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		died.emit(self)
		queue_free())

# ---------------- 查找 ----------------
func _hero() -> Node2D:
	var b := _battle()
	if b == null:
		return null
	var h = b.call("get_hero")            # e27j: 不做 cast —— 主角刚死那 0.5 秒
	return h if is_instance_valid(h) else null   # 引用已释放，cast 会每帧炸

func _nearest_foe(max_d: float) -> Node2D:
	var b := _battle()
	if b == null:
		return null
	return b.call("nearest_foe_of", self, max_d) as Node2D

func _nearest_target() -> Node2D:
	return _nearest_foe(9999.0)

# ---------------- 杂项 ----------------
func _face_to(pos: Vector2) -> void:
	_facing = _dir_name(pos - global_position)

func _play(prefix: StringName) -> void:
	if _atk_lock:
		return        # e17: 攻击动画播完前不许切回走/站（否则 10 帧挥砍只露一帧）
	var an := _anim_name(prefix)
	if _sprite.sprite_frames.has_animation(an) and _sprite.animation != an:
		_sprite.play(an)
	# e27b: 马/人素材侧向帧其实都默认朝右（e16c 当年把马记反了, 实测向右走马头朝左）,
	# 统一「朝左才翻」, 不再按骑兵异或。
	_sprite.flip_h = _facing == &"left"

func _anim_name(prefix: StringName) -> StringName:
	if _facing == &"left" or _facing == &"right":
		return StringName("%s_side" % String(prefix))
	return StringName("%s_%s" % [String(prefix), String(_facing)])

func _dir_name(dir: Vector2) -> StringName:
	if absf(dir.x) >= absf(dir.y):
		return &"right" if dir.x > 0 else &"left"
	return &"down" if dir.y > 0 else &"up"

func _float_text(text: String, col: Color, size := 10) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# 字号越大落点越靠上/越居中：默认小字 (-20,-46)，大号伤客单独算
	l.position = Vector2(-float(size) - 3.0, -46.0 - float(size - 10))
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", -62.0 - float(size - 10), 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.tween_callback(l.queue_free)

func _battle() -> Node:
	return get_tree().get_first_node_in_group("battle")
