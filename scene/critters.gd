extends Node2D
# critters.gd —— 草地小动物氛围层（e29e 素材包盘点的产出）
#
# 草地上常驻两种小动物：
#   · 海鸥  Farm RPG - Tiny Asset Pack/Animals/Forest/Beach/seagull.png
#     草地上啄食、小步溜达，玩家走近就「啪」地惊飞（星露谷式）——贴着地皮蹿上天溜走。
#   · 蝴蝶  Icons/Bugs/Butterflies/Common Butterfly.png   绕着花丛上下飘，
#     玩家凑太近会往旁边闪一下。
#
# 鸽子地面时是 z=0 的普通 Node2D，参与根节点 y_sort、跟树/玩家互相遮挡；
# 惊飞瞬间临时抬 z_index，保证从一切东西头顶飞过去。
# 蝴蝶 e30l: z_index=2 恒在主角上层，贴图不再被主角/树丛盖住。
#
# e35: 原先用的是素材包的乌鸦(Crow.png)，用户要求换成鸽子。素材包里没有以
#      pigeon/dove 命名的图：Sunnyside 那张 deco 鸟条只有 4 帧待机、没有走/飞，
#      所以改用这张海边海鸥(白身灰翅/橙喙橙脚，鸽相而且三段动画齐全)。

const PIGEON_TEX_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Animals/Forest/Beach/seagull.png"
const BUTTERFLY_TEX_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/Bugs/Butterflies/Common Butterfly.png"

# e35: seagull.png 是 16x16 一帧、4 列 x 8 行。陆地动作占行 0~4:
#      行 0 原地踱步(脚交替轻抬) / 行 2 站定单帧 / 行 3 迈步走;
#      行 5~7 是行 0/3/4 的水上版(脚下多一圈水花)，鸽子不下水，用不上。
# e36j: 飞行原来是行 4 —— 逐帧数过才看清行 4 只有 3 帧(第 4 帧整格透明，
#       `% 4` 会让鸟有 1/4 时间凭空消失)，而且姿态是压着地皮前倾低掠，
#       看着像趴着啄食。**行 1 才是双翼大幅上下的扑翼循环(满 4 帧)**，
#       天上飞要用它。
const PIGEON_FRAME := 16
const PIGEON_ROW_PECK := 2
const PIGEON_ROW_WALK := 0
const PIGEON_ROW_FLY := 1

const PIGEON_MAX := 3           # 场上同时存在的鸽子数（e34d 调稀, 满天鸟太吵）
const BUTTERFLY_MAX := 10       # 蝴蝶数
const RESPAWN_WAIT := 25.0      # 有鸽子惊飞离场后，隔这么久在远处补一只（e34d 降频）
const SCARE_DIST := 34.0        # 玩家贴近到这个距离鸽子就惊飞
const BUTTERFLY_SHY_DIST := 22.0 # 蝴蝶怕生的距离

var player: Node2D
var _pigeon_spots: Array = []    # 鸽子候选落点（game 根局部坐标）
var _butterfly_spots: Array = [] # 蝴蝶锚点（花格中心优先）
var _is_water_fn := Callable()   # e34c: 坐标(Vector2) -> 是否水面, 供鸽子避水; 空则跳过检测
var _bf_pool: Array = []         # e30l: 蝴蝶落点洗牌池（抽签不重复, 抽干一池再重洗）
var _rng := RandomNumberGenerator.new()
var _respawn_t := 0.0

func setup(p_player: Node2D, pigeon_spots: Array, butterfly_spots: Array,
		is_water_fn: Callable = Callable()) -> void:
	player = p_player
	_pigeon_spots = pigeon_spots
	_butterfly_spots = butterfly_spots
	_is_water_fn = is_water_fn
	# 摆动/配色细节每局一样 —— 和花草一个思路，固定种子方便对比改动
	_rng.seed = hash("critters-e29e")
	y_sort_enabled = true   # 让每只小动物单独进根节点的 y_sort 池

	# 第三方素材不入库(见 README), 缺失时留空不崩
	var pigeon_tex: Texture2D = SoftRes.tex(PIGEON_TEX_PATH)
	if pigeon_tex == null:
		push_warning("[素材] 海鸥贴图缺失, 已留空")
	for i in PIGEON_MAX:
		var pg := Pigeon.new()
		pg.position = _pick_pigeon_spot()
		pg.player = player
		pg.rng = _rng
		pg.is_water_fn = is_water_fn
		add_child(pg)
		pg.init(pigeon_tex)

	var fly_tex: Texture2D = SoftRes.tex(BUTTERFLY_TEX_PATH)   # 缺失时留空不崩
	if fly_tex == null:
		push_warning("[素材] 蝴蝶贴图缺失, 已留空")
	for i in BUTTERFLY_MAX:
		var b := Butterfly.new()
		b.home = _pick_butterfly_spot()
		b.player = player
		b.rng = _rng
		add_child(b)
		b.init(fly_tex, i)

func _process(delta: float) -> void:
	# 惊飞走的鸽子定期补种（挑离玩家远的落点），不然开局吓一次全场就空了
	_respawn_t += delta
	if _respawn_t < RESPAWN_WAIT:
		return
	_respawn_t = 0.0
	var alive := 0
	for ch in get_children():
		if ch is Pigeon and not ch.gone:
			alive += 1
	if alive >= PIGEON_MAX:
		return
	var pg := Pigeon.new()
	pg.position = _pick_pigeon_spot()
	pg.player = player
	pg.rng = _rng
	pg.is_water_fn = _is_water_fn
	add_child(pg)
	pg.init(SoftRes.tex(PIGEON_TEX_PATH))   # 缺失时留空不崩, setup 里已警告过

# 落点抽签：优先离玩家远的，免得开局落地就吓飞
func _pick_pigeon_spot() -> Vector2:
	if _pigeon_spots.is_empty():
		return Vector2.ZERO
	var best: Vector2 = _pigeon_spots[0]
	var best_d := -1.0
	for i in 6:
		var s: Vector2 = _pigeon_spots[_rng.randi() % _pigeon_spots.size()]
		var d := INF if player == null else player.global_position.distance_to(_to_global_of(s))
		if d > best_d:
			best_d = d
			best = s
	return best

func _pick_butterfly_spot() -> Vector2:
	if _butterfly_spots.is_empty():
		return Vector2.ZERO
	# e30l: 洗牌抽签 —— 同一池里每个锚点只出一次, 十只蝴蝶摊到十丛花上,
	# 不再纯随机好几只挤在同一丛花堆里; 抽干一池才重洗。
	if _bf_pool.is_empty():
		_bf_pool = _butterfly_spots.duplicate()
		for i in range(_bf_pool.size() - 1, 0, -1):
			var j := _rng.randi() % (i + 1)
			var tmp: Vector2 = _bf_pool[i]
			_bf_pool[i] = _bf_pool[j]
			_bf_pool[j] = tmp
	return _bf_pool.pop_back()

# 容器挂在 game 根 (0,0)，局部坐标即 game 根局部；换算成全局只为量距离
func _to_global_of(s: Vector2) -> Vector2:
	return global_position + s

# ============================ 鸽子 ============================
# seagull.png 是 16x16 一帧、4 列 x 8 行：行 0 原地踱步、行 2 站定、行 4 飞行
#（行 5~7 是水上版，不用）。三态各占一行，比原乌鸦的多帧切换更分明。
class Pigeon extends Node2D:
	enum S { PECK, WALK, FLY }
	var state: int = S.PECK
	var spr: Sprite2D
	var player: Node2D
	var rng: RandomNumberGenerator
	var gone := false          # 惊飞离场后置位（critters 数活鸟用）
	var t := 0.0               # 当前状态已持续秒数
	var state_dur := 1.0
	var dir := Vector2.RIGHT
	var speed := 16.0
	var frame_t := 0.0
	var fly_t := 0.0
	# e34c: 坐标(Vector2) -> 是否水面。素材默认头朝左, flip_h 只在朝右时置位。
	var is_water_fn: Callable = Callable()

	func init(tex: Texture2D) -> void:
		spr = Sprite2D.new()
		spr.texture = tex
		spr.hframes = 4
		spr.vframes = 8
		# 脚底落在帧内 y=15(帧底)，上提 7 像素让脚底贴着排序原点
		spr.offset = Vector2(0, -7)
		add_child(spr)
		_next_ground_state()

	func _next_ground_state() -> void:
		t = 0.0
		if rng.randf() < 0.55:
			state = S.PECK
			state_dur = rng.randf_range(0.8, 2.2)
		else:
			state = S.WALK
			state_dur = rng.randf_range(0.6, 1.4)
			dir = Vector2.from_angle(rng.randf() * TAU)
			spr.flip_h = dir.x > 0.0   # 素材默认头朝左, 朝右才要翻
			speed = rng.randf_range(12.0, 20.0)

	func _physics_process(delta: float) -> void:
		if gone:
			return
		# 惊飞判定：玩家一贴近立刻起身
		if player != null and state != S.FLY \
				and global_position.distance_to(player.global_position) < SCARE_DIST:
			_take_off()
		match state:
			S.PECK:
				# 行 2 是站定单帧，靠轻微点头拟「啄」
				spr.frame = PIGEON_ROW_PECK * 4
				spr.offset.y = -7.0 + (1.5 if fmod(t, 0.5) < 0.2 else 0.0)
			S.WALK:
				var step := dir * speed * delta
				# e34c: 已踩到水, 或 12 帧前方是水(防贴水边半格过冲)都要换向
				var wet: bool = is_water_fn.is_valid() \
						and (is_water_fn.call(position) or is_water_fn.call(position + step * 12.0))
				if wet:
					# 换 6 个随机方向, 挑一个 12 帧外仍是陆地的; 都不行就原地站着, 别下水
					var ok := false
					for i in 6:
						dir = Vector2.from_angle(rng.randf() * TAU)
						spr.flip_h = dir.x > 0.0
						step = dir * speed * delta
						if not is_water_fn.call(position + step * 12.0):
							ok = true
							break
					if ok:
						position += step
				else:
					position += step
				spr.offset.y = -7.0
				frame_t += delta * 8.0
				spr.frame = PIGEON_ROW_WALK * 4 + int(frame_t) % 4   # 行 0 踱步 4 帧
			S.FLY:
				fly_t += delta
				speed = minf(speed + 160.0 * delta, 150.0)
				position += dir * speed * delta
				spr.offset.y = -7.0
				frame_t += delta * 12.0
				spr.frame = PIGEON_ROW_FLY * 4 + int(frame_t) % 4    # 行 1 扑翼 4 帧
				if fly_t > 2.0:                     # 飞远后淡出离场
					modulate.a = maxf(1.0 - (fly_t - 2.0) / 0.6, 0.0)
					if fly_t > 2.6:
						gone = true
						queue_free()
		t += delta
		if state != S.FLY and t > state_dur:
			_next_ground_state()

	func _take_off() -> void:
		state = S.FLY
		t = 0.0
		fly_t = 0.0
		frame_t = 0.0
		speed = 50.0
		z_index = 30    # 起飞瞬间越过头顶一切遮挡
		var away := Vector2.RIGHT
		if player != null:
			away = (global_position - player.global_position).normalized()
		dir = (away + Vector2(0, -1.2)).normalized()   # 朝远离玩家、偏上的方向蹿
		spr.flip_h = dir.x > 0.0   # 素材默认头朝左, 朝右才要翻

# ============================ 蝴蝶 ============================
# Common Butterfly.png 是 16x16 一帧的 4x2 排布：4 种配色（列）x 拍翅 2 帧（行）
class Butterfly extends Node2D:
	var spr: Sprite2D
	var player: Node2D
	var rng: RandomNumberGenerator
	var home := Vector2.ZERO   # 锚点（花格中心），飘飞不出它附近太远
	var target := Vector2.ZERO
	var col := 0
	var t := 0.0
	var retarget_t := 0.0
	var frame_t := 0.0

	func init(tex: Texture2D, idx: int) -> void:
		z_index = 2   # e30l: 恒在主角上层, 不参与 y_sort 互相遮挡
		col = rng.randi() % 4
		spr = Sprite2D.new()
		spr.texture = tex
		spr.hframes = 4
		spr.vframes = 2
		spr.frame = col
		add_child(spr)
		target = home
		# 开局相位错开，别一排蝴蝶同步拍翅
		t = float(idx) * 0.37
		frame_t = float(idx) * 0.5

	func _physics_process(delta: float) -> void:
		t += delta
		frame_t += delta * 7.0
		spr.frame = col + (int(frame_t) % 2) * 4   # 同列的行 0/1 交替 = 拍翅
		retarget_t += delta
		var shy := false
		if player != null:
			var dp := global_position - player.global_position
			if dp.length() < BUTTERFLY_SHY_DIST:   # 玩家凑太近：往远处闪
				shy = true
				target = home + dp.normalized() * 20.0
				retarget_t = 0.0
		# e34a: 原先这里用 elif, 玩家在视野内时绕花重瞄准永不执行, 蝴蝶飘一段就钉死不动;
		# 现在怕生闪避优先, 平时照常定时绕花换目标。
		if not shy and (retarget_t > 2.5 or position.distance_to(target) < 2.0):
			# 绕着花丛小范围飘
			target = home + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 22.0)
			retarget_t = 0.0
		var d := target - position
		position += d.limit_length(14.0) * delta * 1.6
		spr.position.y = sin(t * 3.1) * 2.5        # 正弦上下浮动
		if d.length() > 4.0:
			spr.flip_h = d.x < 0.0
