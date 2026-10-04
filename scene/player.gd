extends CharacterBody2D

# 角色动画：Idle/Run 用 normal_/run_ + 朝向；工具动作单独一套放在 ToolSprite 上
var NORMAL_ANIMATION_PREFIX := &"normal"

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var tool_sprite: AnimatedSprite2D = $ToolSprite

var facing_suffix: StringName = &"down"

@export var move_speed: float = 70.0

# 当前选中的道具（由 HUD/快捷栏同步过来）
var current_item: ItemData = null

# 正在做动作：期间锁住移动，避免"边跑边锄"
var busy := false

# 在室内时禁用农具（鼠标坐标对应的是野外网格，室内不该能耕地）
var indoors := false

# 打开背包等 UI 时冻结：禁止移动和使用工具
var frozen := false

# 脚步声的间隔（秒）—— 走一步响一下
const STEP_INTERVAL := 0.34
var _step_timer := 0.0

# i3 农作成功时的粒子色（锄地翻土 / 浇水水花 / 播种扬壳）
const COL_SOIL := Color(0.47, 0.34, 0.21)
const COL_WATER := Color(0.55, 0.75, 0.95)
const COL_SEED := Color(0.65, 0.58, 0.38)

# i3 相机平滑跟随: 一帧位移超过这个数就当瞬移, 直接把相机吸过来
const CAM_SNAP_DIST := 64.0
var _last_pos := Vector2.INF

# ---------------- 动作素材 ----------------
# Josh 的每套动作图都是「32px 一帧、一行一个朝向」：
#   行 0 = 朝下, 行 1 = 朝上, 行 2 = 侧面（左/右靠 flip_h 复用）
# 第三方素材不入库(见 README), 缺失时留空不崩
var HOE_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Hoe.png")
var AXE_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Axe.png")
var WATER_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Watering.png")
var SLEEP_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Sleep.png")
var PICK_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Pickaxe.png")
var FISH_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Fishing/Wait Idle.png")
var FISH_HOOKED_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Fishing/Hooked.png")
# e49 钓鱼动画链补齐：甩竿 -> 等咬钩 -> 咬钩挣扎 -> 拉回（有鱼 / 空竿）
var FISH_CAST_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Fishing/Casting.png")
var FISH_CAPTURE_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Fishing/Captured Fish.png")
var FISH_EMPTY_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Fishing/Captured No Fish.png")
# e49 游泳：蹚水（贴岸浅滩）时的移动 / 静止 / 上岸
var SWIM_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Swim/Swim.png")
var SWIM_SUBMERGED_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Swim/submerged.png")
var SWIM_OUT_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Swim/Coming out of the water.png")

# 站立/奔跑的身体动画
var IDLE_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Idle.png")
var RUN_TEX: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Run.png")
const DEATH_TEX := preload("res://resources/texture/W.png")

const HOE_FRAMES := 6        # Hoe.png      192x96 -> 6 帧 x 3 朝向
const AXE_FRAMES := 6        # Axe.png      192x96 -> 6 帧 x 3 朝向（跟锄头同版式）
const WATER_FRAMES := 8      # Watering.png 256x96 -> 8 帧 x 3 朝向
const SLEEP_FRAMES := 2      # Sleep.png     64x32 -> 2 帧 x 1 朝向
const PICK_FRAMES := 6       # Pickaxe.png  192x96 -> 6 帧 x 3 朝向（跟斧头同版式）
const FETCH_FRAMES := 4      # 取水：借浇水动画的前 4 帧（弯腰探身），和「浇水」区分开
const FISH_FRAMES := 4       # 等咬钩：Wait Idle.png 256x192 -> 4 帧 x 3 朝向（64px 一帧）
const FISH_HOOKED_FRAMES := 8  # 咬钩挣扎：Hooked.png 512x192 -> 8 帧 x 3 朝向（64px 一帧）
const FISH_CAST_FRAMES := 15   # 甩竿：Casting.png 960x192 -> 15 帧 x 3 朝向（64px 一帧）
const FISH_CAPTURE_FRAMES := 4 # 拉回：Captured Fish / No Fish.png 256x192 -> 4 帧 x 3 朝向
const SWIM_FRAMES := 4         # 游泳：Swim.png / submerged.png 128x96 -> 4 帧 x 3 朝向（32px 一帧）
const SWIM_OUT_FRAMES := 3     # 上岸：Coming out of the water.png 96x96 -> 3 帧 x 3 朝向
const SWIM_SPEED_MULT := 0.55  # 水里走得慢（蹚水不是散步）
const SWIM_OUT_TIME := 0.45    # 上岸动作保持时长（演完就回到站立/奔跑）
const FISH_CELL := 64        # 钓鱼图是 64px 一帧（鱼竿伸得远，画布比 32px 大）
const TOOL_CELL := 32
const DIR_ROW := {"down": 0, "up": 1, "side": 2}

# ---------------- 钓鱼状态机 ----------------
# "" 空闲 / "cast" 甩竿等待中 / "bite" 咬钩（要在时限内再点一下拉竿）
var _fish_state := ""
var _fish_deadline_ms := 0
const BITE_WINDOW_MS := 1500     # 咬钩后的反应窗口（1.5 秒, 原先 0.9 太手忙脚乱）
# selftest 加速开关: true 时甩竿等待缩到 0.05 秒（真实玩家不受影响）
var fish_fast := false

# ---------------- 游泳状态（e49 / e51）----------------
# 能下水的水格不再有碰撞, 玩家可以蹚进去 —— 范围由 game.is_swim_water() 说了算：
# 整条河都能游, 海里只有最深那一档挡着, 所以照旧游不出海。
# （桥上不算水：判定里排掉了桥面格, 不然站在桥上也会变游泳）
var _in_water := false
var _out_water_t := 0.0          # 上岸动作剩余时长
var _shadow: Node2D = null       # 影子交给成员持有：下水要藏起来

func _ready() -> void:
	# e33 脚下的影子：角色不再「浮」在地上
	# e36d: 影子居中点原来在 y=1，比视觉脚底(约 y=-7)低了 8px，看着像影子掉在脚外面
	#       —— 抬到脚底那一行，影子和角色重新连成一体
	_shadow = preload("res://scene/shadow_util.gd").make_shadow(18, 7, 0.30)
	_shadow.position = Vector2(0, -7)
	add_child(_shadow)
	# g3: 主角提灯已整个删掉 —— 用户不要身边的光圈, 夜里跟着 CanvasModulate 一起暗
	_build_body_frames()
	_build_action_frames()
	tool_sprite.visible = false
	_update_animation()

# ---------------- d2: 影子随昼夜 ----------------
# 太阳低的时候影子拉长、还偏向一边；正午收成一小团；深夜淡得快看不见。
# g3: 提灯光圈整个删掉了（用户要求）—— 昼夜明暗全归 CanvasModulate 管。
func _process(delta: float) -> void:
	var h: float = TimeManager.hour
	var k := minf(2.5 * delta, 1.0)
	if _shadow != null:
		var m := absf(h - 12.5)                                # 离正午多远
		var stretch := clampf(1.0 - absf(m - 6.0) / 3.0, 0.0, 1.0) # 清晨 6 点半 / 傍晚 6 点半达峰
		var night := clampf((m - 9.0) / 2.5, 0.0, 1.0)         # 深夜才淡出
		_shadow.scale.x = lerpf(_shadow.scale.x, 0.65 + 0.9 * stretch, k)
		_shadow.modulate.a = lerpf(_shadow.modulate.a, 0.30 - 0.16 * night, k)
		_shadow.position.x = lerpf(_shadow.position.x,
			clampf((h - 12.5) / 6.0, -1.0, 1.0) * 6.5 * stretch, k)

# ---------------- 身体动画（站立 / 奔跑 / 倒地）----------------
# 原来 Bake 在 player.tscn 里；现在代码里搭。
func _build_body_frames() -> void:
	var idle: Texture2D = IDLE_TEX
	var run: Texture2D = RUN_TEX
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	# 行号：一行一个朝向 = 0 下 / 1 上 / 2 侧（左右靠 flip_h 复用侧行）
	_add_body_row(sf, "normal_down", idle, 0, 4)
	_add_body_row(sf, "normal_up", idle, 1, 4)
	_add_body_row(sf, "normal_left", idle, 2, 4)
	_add_body_row(sf, "normal_right", idle, 2, 4)
	_add_body_row(sf, "run_down", run, 0, 8)
	_add_body_row(sf, "run_up", run, 1, 8)
	_add_body_row(sf, "run_left", run, 2, 8)
	_add_body_row(sf, "run_right", run, 2, 8)
	_add_body_row(sf, "death", DEATH_TEX, 8, 4)
	# e49 游泳三态：蹚水移动 / 水里静止（只露上半身）/ 上岸那一下
	_add_body_row(sf, "swim_down", SWIM_TEX, 0, SWIM_FRAMES, 6.0)
	_add_body_row(sf, "swim_up", SWIM_TEX, 1, SWIM_FRAMES, 6.0)
	_add_body_row(sf, "swim_left", SWIM_TEX, 2, SWIM_FRAMES, 6.0)
	_add_body_row(sf, "swim_right", SWIM_TEX, 2, SWIM_FRAMES, 6.0)
	_add_body_row(sf, "submerged_down", SWIM_SUBMERGED_TEX, 0, SWIM_FRAMES, 4.0)
	_add_body_row(sf, "submerged_up", SWIM_SUBMERGED_TEX, 1, SWIM_FRAMES, 4.0)
	_add_body_row(sf, "submerged_left", SWIM_SUBMERGED_TEX, 2, SWIM_FRAMES, 4.0)
	_add_body_row(sf, "submerged_right", SWIM_SUBMERGED_TEX, 2, SWIM_FRAMES, 4.0)
	_add_body_row(sf, "out_of_water_down", SWIM_OUT_TEX, 0, SWIM_OUT_FRAMES, 8.0, false)
	_add_body_row(sf, "out_of_water_up", SWIM_OUT_TEX, 1, SWIM_OUT_FRAMES, 8.0, false)
	_add_body_row(sf, "out_of_water_left", SWIM_OUT_TEX, 2, SWIM_OUT_FRAMES, 8.0, false)
	_add_body_row(sf, "out_of_water_right", SWIM_OUT_TEX, 2, SWIM_OUT_FRAMES, 8.0, false)
	body_sprite.sprite_frames = sf

func _add_body_row(sf: SpriteFrames, anim_name: String, tex: Texture2D, row: int, count: int,
		speed := 8.0, loop := true) -> void:
	var an := StringName(anim_name)
	sf.add_animation(an)
	sf.set_animation_loop(an, loop)
	sf.set_animation_speed(an, speed)
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * TOOL_CELL, row * TOOL_CELL, TOOL_CELL, TOOL_CELL)
		sf.add_frame(an, at)

# 用素材搭出工具动作：每种工具 3 个朝向（下 / 上 / 侧面）
func _build_action_frames() -> void:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")     # SpriteFrames 自带一个 default，先删掉
	var hoe: Texture2D = HOE_TEX
	var axe: Texture2D = AXE_TEX
	var water: Texture2D = WATER_TEX
	var sleep: Texture2D = SLEEP_TEX
	var pick: Texture2D = PICK_TEX
	_add_directed(sf, "hoe", hoe, HOE_FRAMES, 14.0)           # 锄地
	_add_directed(sf, "axe", axe, AXE_FRAMES, 14.0)           # 砍树
	_add_directed(sf, "water", water, WATER_FRAMES, 14.0)     # 浇水
	_add_directed(sf, "pick", pick, PICK_FRAMES, 14.0)        # 挖矿 / 拆熔炉
	_add_directed(sf, "fetch", water, FETCH_FRAMES, 7.0)      # 水井取水
	_add_plain(sf, "sleep", sleep, SLEEP_FRAMES, 2.0, false)
	_add_directed(sf, "fish", FISH_TEX, FISH_FRAMES, 6.0, FISH_CELL, true)          # 等咬钩（64px 帧 x 3 朝向, 循环）
	_add_directed(sf, "hooked", FISH_HOOKED_TEX, FISH_HOOKED_FRAMES, 10.0, FISH_CELL, true)  # 咬钩挣扎
	# e49 钓鱼链的两头：甩竿（15 帧一次性）+ 拉回（有鱼 / 空竿各 4 帧一次性）
	_add_directed(sf, "cast", FISH_CAST_TEX, FISH_CAST_FRAMES, 14.0, FISH_CELL, false)
	_add_directed(sf, "capture", FISH_CAPTURE_TEX, FISH_CAPTURE_FRAMES, 8.0, FISH_CELL, false)
	_add_directed(sf, "capture_empty", FISH_EMPTY_TEX, FISH_CAPTURE_FRAMES, 8.0, FISH_CELL, false)
	tool_sprite.sprite_frames = sf

func _add_directed(sf: SpriteFrames, base: String, tex: Texture2D, count: int, speed: float, cell: int = TOOL_CELL, loop := false) -> void:
	for d in DIR_ROW.keys():
		var an := StringName("%s_%s" % [base, d])
		sf.add_animation(an)
		sf.set_animation_loop(an, loop)
		sf.set_animation_speed(an, speed)
		var row: int = DIR_ROW[d]
		for i in count:
			sf.add_frame(an, _frame(tex, i, row, cell))

func _add_plain(sf: SpriteFrames, anim_name: String, tex: Texture2D, count: int, speed: float, loop: bool) -> void:
	var an := StringName(anim_name)
	sf.add_animation(an)
	sf.set_animation_loop(an, loop)
	sf.set_animation_speed(an, speed)
	for i in count:
		sf.add_frame(an, _frame(tex, i, 0))

func _frame(tex: Texture2D, col: int, row: int, cell: int = TOOL_CELL) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * cell, row * cell, cell, cell)
	return at

# ---------------- 移动 ----------------
func _physics_process(delta: float) -> void:
	_tick_camera_snap()
	if busy or frozen:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_tick_swim_state(delta)
	velocity = move_input * move_speed
	if _in_water:
		velocity *= SWIM_SPEED_MULT
	move_and_slide()
	# ❗走完这一步脚底下可能已经换成另一格了（刚下水 / 刚上岸）—— 立刻按新位置重算一次。
	#   delta 传 0：只更新「在不在水里」和影子，不推进上岸计时（那一步上面已经扣过了）。
	#   不补这一下的话，判定永远慢一帧：上岸后还会按水里那套算速度、播游泳动画。
	_tick_swim_state(0.0)

	if move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)
		NORMAL_ANIMATION_PREFIX = "swim" if _in_water else "run"
		_update_animation()
		if not _in_water:
			_tick_footstep(delta)
	else:
		NORMAL_ANIMATION_PREFIX = "submerged" if _in_water else "normal"
		_step_timer = 0.0
		_update_animation()

# e49 水里/岸上切换：脚下是能下水的水格就算在水里（减速 + 换动画 + 藏影子）。
# 从水里踩上岸的那一下演「上岸」动作（0.45 秒, 走跑都盖得住），演完自动回站立/奔跑。
func _tick_swim_state(delta: float) -> void:
	var was_in_water := _in_water
	_in_water = _on_swim_water()
	if _in_water:
		_out_water_t = 0.0
	elif was_in_water and _out_water_t <= 0.0 and not indoors:
		_out_water_t = SWIM_OUT_TIME
	_out_water_t = maxf(0.0, _out_water_t - delta)
	if _shadow != null:
		_shadow.visible = not _in_water

func _on_swim_water() -> bool:
	var g := _game()
	if g == null or not g.has_method("is_swim_water"):
		return false
	# 屋里不算水。房间是挂在农舍下面的独立场景（house.tscn 的 Interior 在 House 底下 +288），
	# 它的世界坐标正好压在小岛的河道和 row26 那座桥上 —— 不拦住的话在自家地板上
	# 走两步就踩进「水格」变游泳（人变成一小团水花, 站着还不出水面）。
	if indoors:
		return false
	return g.is_swim_water(_facing_grid_pos(global_position))

# 脚步声：走一段路响一下。音高随机 ±6%，不然同一段采样重复播会很机械。
func _tick_footstep(delta: float) -> void:
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = STEP_INTERVAL
	# D2 脚步分材质: 屋里木地板; 甲板/铺了木地板踩木头, 石路踩石头, 沙滩踩沙
	var sfx := "step"
	if indoors:
		sfx = "step_wood"
	else:
		var g := _game()
		var c := _facing_grid_pos(global_position)
		if g != null and g.is_deck_cell(c):
			sfx = "step_wood"
		elif Floor.is_floored(c):
			sfx = "step_wood" if Floor.kind_of(c) == Floor.KIND_WOOD else "step_stone"
		elif g != null and g.is_sand(c):
			sfx = "step_sand"
	Audio.play_sfx(sfx, -12.0, randf_range(0.94, 1.06))

# ---------------- 使用工具 ----------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use_tool"):
		_use_current_item()

func _use_current_item() -> void:
	# 钓鱼进行中: 这一击先交给钓鱼状态机（收线 / 拉竿），别去挥工具
	if _fish_state != "":
		_fish_click()
		return
	if busy or indoors or frozen:
		return
	# 建造模式（ghost 跟着鼠标摆建筑）/ 建筑模式（搬房子）时，点击都归 game 处理，不挥工具
	var g0 := _game()
	if g0 != null and g0.has_method("is_build_mode") and g0.is_build_mode():
		return
	if g0 != null and g0.has_method("is_move_mode") and g0.is_move_mode():
		return
	var mouse_world := get_global_mouse_position()
	var target := _facing_grid_pos(mouse_world)

	# 指向成熟作物时，无论手里拿什么都优先收获
	if Farm.is_ready(target):
		var crop := Farm.harvest(target)
		if crop != null:
			# 婚恋 perk（娜雅）: 作物产量 +15% —— 按概率多收一份
			var n := 1 + (1 if randf() < Marriage.perk_mult("crop") - 1.0 else 0)
			Inventory.add_item(crop, n)
			Audio.play_sfx("harvest")
			play_tool_animation("hoe")
			Quests.complete("harvest_first")   # 开局指引: 第一份收成
		return
	# 枯掉的作物：收割键 = 清地（不出货），腾出耕地好种新季
	if Farm.is_dead(target):
		Farm.clear_dead(target)
		_flash("枯掉的作物清掉了")
		play_tool_animation("hoe")
		return

	# 熔炉左键: 手持矿物点炉 = 放进去烧; 出炉了 = 左键直接取铁（镐子除外 —— 那是拆炉）
	var gf := _game()
	if gf != null and gf.has_method("furnace_click") \
			and gf.furnace_click(mouse_world, target, current_item):
		return

	# e30q: 水井左键也能打水（跟 F 一样, 点井 = 打水）
	if gf != null and gf.has_method("well_click") \
			and gf.well_click(mouse_world, target):
		return

	if current_item == null:
		return

	match current_item.type:
		"工具":
			match current_item.display_name:
				"锄头":
					# 已耕地再锄一次 = 翻回草地（有作物先拦）
					if Farm.is_tilled(target):
						if Farm.has_crop(target):
							_flash("作物还长着, 先收割")
						elif Farm.untill(target):
							Audio.play_sfx("hoe", -6.0, 0.85)
							play_tool_animation("hoe")
							_flash("翻回了草地")
					# 水面/桥面/有树的地方不能动土（问 game.is_tillable，别让土翻到河里）
					else:
						var tg: Node = _game()
						if tg != null and tg.has_method("is_tillable") and not tg.is_tillable(target):
							if tg.has_method("is_water") and tg.is_water(target):
								_flash("水边不能锄地", "error")
							elif tg.has_method("is_sand") and tg.is_sand(target):
								_flash("沙滩上开不了田", "error")
							else:
								_flash("这里不能锄地", "error")
						elif Farm.till(target):
							Audio.play_sfx("hoe")
							play_tool_animation("hoe")
							_burst_at(target, COL_SOIL)
							Quests.complete("till_first")   # 开局指引: 第一块田
				"斧头":
					_swing_axe(target, mouse_world)
				"镐子":
					_swing_pick(target, mouse_world)
				"洒水壶":
					# 对着水面（海/河/池塘）点 = 打水，否则才是浇地
					if _fetch_water(target):
						return
					_use_watering_can(target)
				"鱼竿":
					_start_fishing(target)
		"种子":
			if current_item.plant_on == "草地":
				_plant_tree(target)
			elif not Farm.season_ok_for(current_item):
				# 不是这包种子能种的季节（Farm.plant 里还有一层兜底）
				_flash("%s要%s季种, 现在是%s季" % [
					current_item.display_name, Farm.seasons_text_for(current_item),
					TimeManager.SEASONS[TimeManager.season]], "error")
			elif Farm.plant(target, current_item):
				Inventory.remove_item(current_item, 1)
				Audio.play_sfx("plant")
				_burst_at(target, COL_SEED)
				Quests.complete("plant_first")   # 开局指引: 第一颗种子
		"地板":
			_place_floor(target)
		"放置":
			_place_station(target)
		"船":
			# 船不再手持下水：只能去东岸的废弃码头造，造好就停在码头
			_flash("船要在废弃码头造, 那边按 F", "error")

func _game() -> Node:
	var g := get_tree().get_first_node_in_group("game")
	return g if g != null else get_parent()

# i3: 相机平滑跟随的瞬移兜底 —— 一帧跳过大距离（进屋/睡觉醒来/出海回岛）时
#     把相机直接吸过来, 不然它会从半张地图外慢慢飘过来。
#     挂在 busy/frozen 早退之前: 睡觉瞬移正好发生在 frozen 路径上。
func _tick_camera_snap() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		_last_pos = global_position
		return
	if _last_pos == Vector2.INF or _last_pos.distance_to(global_position) > CAM_SNAP_DIST:
		cam.reset_smoothing()
	_last_pos = global_position

# i3: 农作成功时在格子上炸一小撮粒子（土屑/水花/种壳）。
#     挂在 game 上而不是 player 上 —— 不然人会带着粒子跑。
func _burst_at(cell: Vector2i, col: Color, n := 10) -> void:
	var g := _game()
	if g == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = n
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.spread = 55.0
	p.direction = Vector2(0, -1)
	p.gravity = Vector2(0, 150)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 42.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.7
	p.color = col
	p.position = Farm.grid_origin + Vector2(cell) * float(Farm.TILE_SIZE) \
			+ Vector2.ONE * (float(Farm.TILE_SIZE) * 0.5) - Vector2(0, 6)
	g.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# 对着水格用洒水壶 —— 直接打满，不用特地跑去水井。
# 返回 true 表示这一下被「打水」吃掉了（就不会再去浇地）。
func _fetch_water(target: Vector2i) -> bool:
	var g := _game()
	if g == null or not g.has_method("is_water") or not g.is_water(target):
		return false
	if Inventory.is_can_full():
		_flash("水壶已经是满的", "error")
		return true
	Inventory.fill_water()
	Audio.play_sfx("fill")
	_flash("打满水了! %d/%d" % [Inventory.water_max(), Inventory.water_max()])
	play_tool_animation("fetch")
	return true

# ---------------- 钓鱼 ----------------
# 甩竿：对着水格点左键。等一会儿鱼咬钩（雨天更快），咬钩后 1.5 秒内再点一下 = 钓上来。
func _start_fishing(target: Vector2i) -> void:
	if _fish_state != "":
		return
	var g := _game()
	if g == null or not g.has_method("is_water") or not g.is_water(target):
		_flash("要对着水才能甩竿")
		return
	_fish_state = "cast"
	_play_cast_pose()                     # 甩竿（Casting.png）演完 -> 停在持竿等咬钩的姿势
	_fish_wait_bite()

# e49 甩竿：Casting.png 15 帧演完，接 Wait Idle 的持竿姿势（busy 全程保持，人物不动）。
# ❗fish_fast（自检模式）直接跳到持竿姿势 —— 甩竿动作有 1 秒多，会拖过自检的 0.3 秒咬钩窗口。
func _play_cast_pose() -> void:
	play_tool_animation("cast", true)
	if not busy:
		return
	if fish_fast:
		_play_hold_pose("fish")
		return
	await tool_sprite.animation_finished
	if _fish_state != "cast":
		return                            # 演到一半玩家收线了
	_play_hold_pose("fish")

# 等鱼咬钩：平时 9~13 秒，雨天 5~7 秒（钓鱼是慢活，别让它变成刷钱机器）；
# 2026-09-19 用户要求把上钩等待与逃离窗口都放宽一点。selftest 开 fish_fast 缩到 0.05 秒
func _fish_wait_bite() -> void:
	var wait: float = randf_range(5.0, 7.0) if Weather.is_rain() else randf_range(9.0, 13.0)
	if fish_fast:
		wait = 0.05
	await get_tree().create_timer(wait).timeout
	if _fish_state != "cast":
		return                # 等待期间玩家收线了
	_fish_state = "bite"
	_fish_deadline_ms = Time.get_ticks_msec() + BITE_WINDOW_MS
	_flash("咬钩了! 快点!")
	_play_hold_pose("hooked")
	Audio.play_sfx("fill", -6.0, 1.5)     # 借打水音当咬钩提示（音效库暂无鱼效）
	_fish_watch_deadline()

# 在「保持中」的持竿状态里换姿势（甩竿演完换持竿 / 咬钩换挣扎）。
# 只换动画不收尾 —— busy 一直挂着，人物保持不动。
func _play_hold_pose(kind: String) -> void:
	if not busy:
		return
	var d := String(facing_suffix)
	if d == "left" or d == "right":
		d = "side"
	var an := StringName("%s_%s" % [kind, d])
	var sf := tool_sprite.sprite_frames
	if sf != null and sf.has_animation(an):
		tool_sprite.play(an)

# 咬钩超时：时限内没拉竿 = 脱钩复位
func _fish_watch_deadline() -> void:
	await get_tree().create_timer(BITE_WINDOW_MS / 1000.0).timeout
	if _fish_state == "bite":
		_pull_and_reset("capture_empty")
		_flash("鱼跑了...")

# 钓鱼中的点击：cast = 收线空手；bite = 拉竿结算（抽鱼 -> 入包 -> 记图鉴）
func _fish_click() -> void:
	if _fish_state == "cast":
		_pull_and_reset("capture_empty")
		_flash("收线了, 什么都没钓着")
		return
	if _fish_state != "bite":
		return
	var fish: ItemData = FishJournal.roll()
	if fish == null:
		_pull_and_reset("capture_empty")
		_flash("这下没拉上来")
		return
	Inventory.add_item(fish, 1)
	Legion.gain_exp(2)          # e13h: 钓鱼也长主角经验
	if FishJournal.record(fish):
		_flash("钓到了 %s! 新收录图鉴" % fish.display_name)
	else:
		_flash("钓到了 %s!" % fish.display_name)
	Audio.play_sfx("harvest")
	Quests.note_first_fish()        # e32: 第一条鱼 = 走出农场, 指引链毕业
	_pull_and_reset("capture")

# e49 收竿收尾：先放下鱼竿姿势，再演「拉回」动作（有鱼 capture / 空竿 capture_empty）。
# ❗fish_fast（自检模式）直接复位 —— 自检断言「点完就 not busy」，不能挂着收竿动作。
func _pull_and_reset(kind: String) -> void:
	if fish_fast:
		_fish_reset()
		return
	_fish_state = ""
	end_tool_animation()
	play_tool_animation(kind)

func _fish_reset() -> void:
	_fish_state = ""
	end_tool_animation()

func _use_watering_can(target: Vector2i) -> void:
	# 浇水的失败提示只飘字不出声（用户要求去掉这类打断感的 error 音）
	if Inventory.is_can_empty():
		_flash("水壶空了 -- 对着水面点一下就能打水")
		return
	if not Farm.is_tilled(target):
		_flash("这里还没耕地")
		return
	if Farm.is_watered(target):
		_flash("今天已经浇过了")
		return
	if Farm.water(target):
		Inventory.use_water()
		Audio.play_sfx("water")
		play_tool_animation("water")
		_burst_at(target, COL_WATER)
		_irrigate_around(target)
		Quests.complete("water_first")   # 开局指引: 头道水

# 科技「引水渠」：浇一格的时候，把前后左右的耕地也顺手浇了。
# 多浇的每格各耗一份水（水不够就停下），所以它省的是**操作**而不是水资源。
func _irrigate_around(center: Vector2i) -> void:
	if not Research.irrigate():
		return
	var extra := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Inventory.is_can_empty():
			break
		var c: Vector2i = center + d
		if not Farm.is_tilled(c) or Farm.is_watered(c):
			continue
		if Farm.water(c):
			Inventory.use_water()
			extra += 1
	if extra > 0:
		_flash("引水渠: 顺带浇了 %d 格" % extra)

# 铺设地板/小径：能动土的地方（草地/耕地）都行，水/桥/有树的地方不行；铺一格扣一件道具
func _place_floor(target: Vector2i) -> void:
	var g: Node = _game()
	if g != null and g.has_method("is_tillable") and not g.is_tillable(target):
		_flash("这里不能铺地板", "error")
		return
	if Floor.is_floored(target):
		_flash("这里已经铺过了", "error")
		return
	# 手持哪种铺装就铺哪种（鹅卵石小径 / 木地板）。
	# ❗名字要先抓 —— remove_item 把最后一块耗掉时 current_item 会被清成空,
	#   再读它就崩溃(铺完最后一块地板必崩, 就是这个原因)。
	var nm := String(current_item.display_name)
	var kind := Floor.KIND_PATH if nm == "鹅卵石小径" else Floor.KIND_WOOD
	if Floor.place(target, kind):
		Inventory.remove_item(current_item, 1)
		Audio.play_sfx("plant", -10.0)        # 借用 plant 的锤子音
		_flash("铺了一块%s" % nm)
		# 不用动画，地板只是贴个纹理

# 挥斧头：砍中树就播砍树结算（摇晃/倒树/掉落在 game.hit_tree 里办），
# 没砍中也照常挥空 —— 斧头是工具，不是激光笔。
func _swing_axe(target: Vector2i, mouse_world: Vector2) -> void:
	play_tool_animation("axe")
	var g: Node = _game()
	if g == null or not g.has_method("hit_tree"):
		return
	# ❗别拿「鼠标 -> 格子」的格子直接查树：树的贴图比它注册的那格高出近 3 格，
	#   对着树冠点会算出树顶上方的空格，判定成"这里没有能砍的树"。
	#   由 game 按贴图矩形挑出真正指着的那棵（顺便接住"站在树前直接按使用键"）。
	if g.has_method("pick_tree_cell"):
		target = g.pick_tree_cell(mouse_world, target)
	var res: Dictionary = g.hit_tree(target)
	match int(res.get("result", 0)):
		0:
			_flash("这里没有能砍的树")   # 空挥不出声（用户要求）
		1:
			Audio.play_sfx("chop", -4.0)
		2:
			Audio.play_sfx("chop", -2.0, 0.9)   # 倒了的那一下更低沉

# 放置工作台/熔炉：能动土的地方（草地/耕地）都行；一格只能摆一座，扣一件道具
func _place_station(target: Vector2i) -> void:
	var g: Node = _game()
	if g != null and g.has_method("is_tillable") and not g.is_tillable(target):
		_flash("这里不能放置", "error")
		return
	if Structures.is_blocked(target):
		_flash("这里已经有设施了", "error")
		return
	# e30o: 大建筑只记锚点格 —— 身体格上摆设施会跟房子叠成一团
	if g != null and g.has_method("station_footprint_blocked") \
			and g.station_footprint_blocked(target):
		_flash("跟建筑叠在一起了", "error")
		return
	# e30o: 脚底下不能摆 —— 工作台自带碰撞会把人卡在原地
	if g != null and g.get("player") != null and g.has_method("_world_to_cell") \
			and target == g._world_to_cell(g.player.global_position):
		_flash("不能摆在脚底下", "error")
		return
	# 工作台/熔炉画的是 32x32、格子只有 16px：贴着摆两座大件会叠成一团
	# （门口蓝影 bug 的根源）, 所以大件之间要求隔开一格。
	# 灯/井/蜂箱/储物箱这类小件画幅窄, 贴着大件放不会叠 —— 不算障碍
	# （用户实测: 路灯两侧贴熔炉是正常摆法, 之前被一刀切挡住了）。
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nk := Structures.kind_of(target + Vector2i(dx, dy))
			if nk == Structures.KIND_WORKBENCH or nk == Structures.KIND_FURNACE:
				_flash("离其他设施太近了", "error")
				return
	var kind := Structures.KIND_WORKBENCH
	if current_item.display_name == "熔炉":
		kind = Structures.KIND_FURNACE
	if Structures.place(target, kind):
		var shown := current_item.display_name
		Inventory.remove_item(current_item, 1)
		Audio.play_sfx("plant", -10.0)        # 借用 plant 的锤子音
		_flash("摆好了 %s" % shown)
		if kind == Structures.KIND_FURNACE:
			_flash("按 F 点火: 1 木头 + 1 铁矿 -> 1 铁锭")

# 挥镐子：挖岩石/矿石露头，也能把放置的熔炉挖回物品栏。
# 判定思路跟斧头一致：贴图比格子大，由 game 按贴图矩形挑出真正指着的那块。
func _swing_pick(target: Vector2i, mouse_world: Vector2) -> void:
	play_tool_animation("pick")
	var g: Node = _game()
	if g == null:
		return
	# 先看指没指着玩家摆的设施（工作台/熔炉）—— e30e: 要敲满 10 下才真拆
	if g.has_method("pick_station_cell"):
		var sc: Vector2i = g.pick_station_cell(mouse_world, target)
		if Structures.has_station(sc):
			var sres: Dictionary = g.hit_station_once(sc)
			match int(sres.get("result", 0)):
				1:
					Audio.play_sfx("chop", -8.0, 1.15)   # 还在拆：轻敲一下
				2:
					Audio.play_sfx("chop", -4.0, 1.1)    # 拆掉了：那声更沉
			return
	# 再看铺装（木地板/鹅卵石小径）—— 一镐子撬起来收回归还
	if Floor.is_floored(target):
		var kind := Floor.kind_of(target)
		Floor.remove(target)
		var back: ItemData = Floor.KIND_ITEM.get(kind)
		if back != null:
			Inventory.add_item(back, 1)
		Audio.play_sfx("chop", -8.0, 1.15)
		_flash("撬回了%s" % ("鹅卵石小径" if kind == Floor.KIND_PATH else "木地板"))
		return
	if g.has_method("pick_rock_cell"):
		target = g.pick_rock_cell(mouse_world, target)
	var res: Dictionary = g.hit_rock(target) if g.has_method("hit_rock") else {"result": 0}
	match int(res.get("result", 0)):
		0:
			_flash("这里没有能挖的石头")   # 空挥不出声（用户要求）
		1:
			Audio.play_sfx("chop", -8.0, 1.15)  # 敲石头: 借砍树音调高一点
		2:
			Audio.play_sfx("chop", -2.0, 0.8)   # 碎掉的那一下更沉

# 种树种子：只能种在草地上（水里、桥上、田里、已有树的地方都不行）
func _plant_tree(target: Vector2i) -> void:
	var g: Node = _game()
	if g != null and g.has_method("is_water") and g.is_water(target):
		_flash("水边种不成树", "error")
		return
	if Farm.is_tilled(target):
		_flash("田里种不了树 -- 找块草地", "error")
		return
	if g != null and g.has_method("is_bridge_cell") and g.is_bridge_cell(target):
		_flash("桥上种不了树", "error")
		return
	if Trees.is_blocked(target):
		_flash("这里已经有树了", "error")
		return
	if Structures.is_blocked(target):
		_flash("设施上种不了树", "error")
		return
	var variant := absi(target.x * 7 + target.y * 13) % 2
	if Trees.plant(target, variant):
		Inventory.remove_item(current_item, 1)
		Audio.play_sfx("plant")
		play_tool_animation("hoe")      # 弯腰埋种：借锄地动作
		_flash("种下了树苗,几天后长大")

# 播一次动作；播放期间锁住移动。
# kind 里如果直接有同名动画（比如 sleep），就用它；否则按当前朝向取 kind_方向。
# hold = true 时播完不收尾，姿势一直保持（睡觉用），由 end_tool_animation() 起身。
func play_tool_animation(kind: String, hold := false) -> void:
	if busy:
		return
	var sf := tool_sprite.sprite_frames
	if sf == null:
		return
	var an := StringName(kind)
	if not sf.has_animation(an):
		var d := String(facing_suffix)
		if d == "left" or d == "right":
			d = "side"
		an = StringName("%s_%s" % [kind, d])
	if not sf.has_animation(an):
		return
	busy = true
	body_sprite.visible = false
	tool_sprite.visible = true
	tool_sprite.flip_h = (facing_suffix == &"left")
	tool_sprite.play(an)
	if hold:
		return
	await tool_sprite.animation_finished
	tool_sprite.visible = false
	body_sprite.visible = true
	busy = false
	_update_animation()

# 收掉「保持中」的工具姿势（天亮起床时把睡姿换回站立）
func end_tool_animation() -> void:
	if not busy:
		return
	tool_sprite.stop()
	tool_sprite.visible = false
	body_sprite.visible = true
	busy = false
	_update_animation()

# 头顶飘字提示。sfx 传 "error" 之类会顺便响一下音效（可选）。
func _flash(text: String, sfx := "") -> void:
	if sfx != "":
		Audio.play_sfx(sfx, -6.0)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.position = Vector2(-60, -34)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", -54.0, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

# ---------------- 坐标 / 动画 ----------------
# mouse_world 留空 = 用真实鼠标位置；探针可以塞一个具体点进来量换算对不对。
func _facing_grid_pos(mouse_world := Vector2.INF) -> Vector2i:
	var m: Vector2 = get_global_mouse_position() if mouse_world == Vector2.INF else mouse_world
	var local := m - Farm.grid_origin
	return Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE))

func _update_animation() -> void:
	# 刚上岸那一小段优先演「上岸」；上岸动作就 3 帧，演完自然回到站立/奔跑。
	# ❗但只在**站着**时演：那 3 帧画的还是「人泡在水里」，一直压着就成了「上了岸还在游一段」。
	#   一旦迈步（prefix 变 run）立刻回到走/跑 —— 上岸就该是上岸的样子。
	var prefix: String = NORMAL_ANIMATION_PREFIX
	if not _in_water and _out_water_t > 0.0 and prefix != "run":
		prefix = "out_of_water"
	var animation_name := StringName("%s_%s" % [prefix, facing_suffix])
	if body_sprite.animation != animation_name and body_sprite.sprite_frames.has_animation(animation_name):
		body_sprite.play(animation_name)
	body_sprite.flip_h = (facing_suffix == &"left")

func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0 else &"left"
	return &"down" if direction.y > 0 else &"up"
