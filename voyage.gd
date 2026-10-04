# voyage.gd —— Autoload，名字：Voyage
# 「船 + 大地图旅行」的数据层：船摆在哪儿、现在是不是在旅行/打仗、
# 战斗里的指挥口令，以及这些状态的存档读写。
#
# 玩法骨架（跟用户对过的设计）：
#   · 东岸外海有座**废弃码头**：先付钱+材料动工，再派伙伴去修，修好才算数
#   · 码头修好后才能在那儿**造船**（一船两人）；船造好就固定停在码头
#   · 走到码头按 F 出海 → 进入大地图旅行模式（骑砍式：只显示主角头像在海图上移动，
#     在水上时头像下面垫一条船）
#   · 带谁出海：夜里/白天按 T 的派活面板里勾「明天出行」——
#     勾中的人明天不干活（劳动力按人数扣），出海时跟着上船
#   · 大地图：主角岛在东南，大陆在西北；图上逛着海寇/山贼小股敌人，
#     撞上就进预设战役地图开打
#   · 战斗指挥（简化版骑砍，**全鼠标**，没有键盘指令）：
#       左下角一排按钮选这轮指挥谁（全体/剑士/弓手/骑兵）
#       左键点地面 = 开过去；按住拖一条线 = 沿线展开阵型；点敌人 = 冲锋
#       号令按钮：跟随我 / 冲锋 / 驻守 / 撤退（右键取消拖拽，O 撤退）
#     编队归属在派活面板里自己定
#     进战役就是慢动作（倍率在设置页里调，Engine.time_scale）
#   · 打赢回海图继续走，走到大陆码头算抵达；F 回到自家码头就返航
extends Node

signal dock_changed            # 码头状态 / 施工进度 / 船数变了（画面上的码头跟着重画）
signal command_changed         # 战斗指挥口令变了
signal selection_changed       # 这轮指挥哪个编队变了

# 修码头 / 造船要用的材料（preload 一次，账单和扣料都用它）
const WOOD_ITEM := preload("res://item/wood.tres")
const PLANK_ITEM := preload("res://item/wood_floor.tres")
# d10: 进战斗的衔接 —— 收黑->切场景->展开 的 iris 转场层（结算退场已在用）
const IRIS := preload("res://scene/iris_wipe.gd")

# ---------------- 状态 ----------------
var traveling := false         # 正在大地图 / 战役地图 / 大陆据点里（游戏岛场景被冻结隐藏）
var ashore := false            # 具体在「大陆据点」小场景里（traveling 的子状态）
var last_sail_day := -1        # 上次出海的全局日序号（一天只能出一次海, e13a）
var world_pos := Vector2.ZERO  # 大地图上主角头像的位置（跨战斗保留）
var command := 1               # 指挥口令：0 移动到指定点（要点地图）/ 1 跟随我 / 2 冲锋 / 3 驻守
const COMMAND_NAMES := ["移动", "跟随我", "冲锋", "驻守"]

# 这轮指挥谁：0 = 全体（默认），1/2/3 = 第几编队
var selection := 0
const SQUAD_MAX := 3
# 编队代表的颜色（选中圈用它，跟面板上的按钮对得上）
const SQUAD_COLORS := {
	1: Color(1.0, 0.92, 0.45),
	2: Color(0.45, 0.85, 1.0),
	3: Color(1.0, 0.62, 0.9),
}

# ---------------- 废弃码头 / 船队 ----------------
# 东岸外海那座**废弃码头**是出海的唯一入口（ESC 制作台不再造船）：
#   废墟 --(付钱+材料动工)--> 待施工 --(派活面板派人, 攒够人天)--> 建成
#   建成后才能在码头造船；船造好就固定停在码头，走到码头按 F 出海。
# 一船两人：出海的人越多要的船越多，船不够就在派活面板上拦下来。
const DOCK_RUIN := 0            # 废墟（开局）
const DOCK_FUNDED := 1          # 钱和材料给了，等人来修
const DOCK_BUILT := 2           # 建成，能造船能出海
const DOCK_STATE_NAME := ["废墟", "待施工", "已建成"]

const DOCK_MONEY := 600         # 修码头：钱
const DOCK_WOOD := 30           # 修码头：木材
const DOCK_PLANK := 6           # 修码头：木板
const DOCK_WORK := 10           # 修码头要的人·天（1 人干 10 天，或 10 人干 1 天）

const BOAT_SEATS := 2           # 一船两人
const BOAT_MONEY := 300         # 造一条船：钱
const BOAT_WOOD := 12           # 造一条船：木材
const BOAT_MAX := 6             # 码头最多停几条船

var dock_state := DOCK_RUIN
var dock_work := 0              # 已经投入的人·天
var boat_count := 0             # 码头停了几条船

func dock_ready() -> bool:
	return dock_state == DOCK_BUILT

# 开新档：码头回到废墟、船全没、人回岛上（由 save_manager.reset_all 调用）。
# ❗traveling / ashore 也要清 —— 开新档时万一还停在海图/据点里，
#   不清的话新档一进去就"人在海上"，而且岛上场景还是藏着的。
func reset_for_new_game() -> void:
	dock_state = DOCK_RUIN
	dock_work = 0
	boat_count = 0
	world_pos = Vector2.ZERO
	traveling = false
	ashore = false
	last_sail_day = -1
	command = 1
	selection = 0
	set_battle_slow(false)
	dock_changed.emit()

# 出海总人数：主角自己 + 派活面板里勾了「明天出行」的伙伴
func party_size() -> int:
	return 1 + Slaves.expedition.size()

# 这么多人出海要几条船（一船两人，多出一个人也要再占一条）
func boats_needed() -> int:
	return ceili(float(party_size()) / float(BOAT_SEATS))

# 现有船队一共能载几个人
func seats() -> int:
	return boat_count * BOAT_SEATS

func boats_enough() -> bool:
	return boat_count >= boats_needed()

# 给面板列账单用：[{name, have, need}]，UI 只管照着显示
func dock_bill() -> Array:
	return [
		{"name": "钱", "have": Wallet.money, "need": DOCK_MONEY},
		{"name": "木材", "have": Inventory.count_item(WOOD_ITEM), "need": DOCK_WOOD},
		{"name": "木板", "have": Inventory.count_item(PLANK_ITEM), "need": DOCK_PLANK},
	]

func boat_bill(boat_only := false) -> Array:
	var b := [
		{"name": "钱", "have": Wallet.money, "need": BOAT_MONEY},
		{"name": "木材", "have": Inventory.count_item(WOOD_ITEM), "need": BOAT_WOOD},
	]
	if not boat_only:
		b.append_array(dock_bill())
	return b

# 账单里有没有付不起的（返回第一项缺啥的提示，够付返回 ""）
func bill_short(bill: Array) -> String:
	for e in bill:
		if int(e["have"]) < int(e["need"]):
			return "%s不够 (要%d, 只有%d)" % [str(e["name"]), int(e["need"]), int(e["have"])]
	return ""

# —— 动工修码头：扣钱扣材料，码头变成「待施工」——
func can_fund_dock() -> bool:
	return dock_state == DOCK_RUIN and bill_short(dock_bill()) == ""

func fund_dock() -> bool:
	if not can_fund_dock():
		return false
	Wallet.spend_money(DOCK_MONEY)
	Inventory.remove_item(WOOD_ITEM, DOCK_WOOD)
	Inventory.remove_item(PLANK_ITEM, DOCK_PLANK)
	dock_state = DOCK_FUNDED
	dock_work = 0
	dock_changed.emit()
	return true

# —— 施工：每天把派去修码头的人数加进进度。返回 true = 今天就建成了 ——
func add_dock_work(heads: int) -> bool:
	if dock_state != DOCK_FUNDED or heads <= 0:
		return false
	dock_work = mini(dock_work + heads, DOCK_WORK)
	var done := dock_work >= DOCK_WORK
	if done:
		dock_state = DOCK_BUILT
		Slaves.clear_dock_crew()      # 建成了，人回地里干活
	dock_changed.emit()
	return done

# —— 造船：只能在建成的码头造，船固定停在码头 ——
func can_build_boat() -> bool:
	return dock_ready() and boat_count < BOAT_MAX and bill_short(boat_bill(true)) == ""

func build_boat() -> bool:
	if not can_build_boat():
		return false
	Wallet.spend_money(BOAT_MONEY)
	Inventory.remove_item(WOOD_ITEM, BOAT_WOOD)
	boat_count += 1
	dock_changed.emit()
	# e42: 第一条船下水 = 潮风号, 放一段过场推剧情 (放过一次就不再放)
	Cutscenes.play_once("harbor")
	return true

# 出海条件检查：返回空串 = 能走，否则返回给玩家看的提示文字
func depart_block_reason(_game: Node) -> String:
	if not dock_ready():
		return "码头还没修好, 先去修它"
	if boat_count <= 0:
		return "还没有船 (在码头造)"
	if not boats_enough():
		return "船不够: %d 人出海要 %d 艘, 只有 %d 艘" % [
			party_size(), boats_needed(), boat_count]
	if traveling:
		return "已经在路上"
	if last_sail_day == _day_stamp():
		return "今天已经出过海了, 明天再来 (回来时天已擦黑)"
	var night: bool = TimeManager.hour >= 19 or TimeManager.hour < 6
	if night:
		return "天黑了不能出海"
	return ""

# 今天的全局日序号（年/季/日压成一个整数, 判断「今天出过海没有」用）
func _day_stamp() -> int:
	return TimeManager.year * 10000 + TimeManager.season * 100 + TimeManager.day

# ---------------- 战斗指挥 ----------------
func set_command(c: int) -> void:
	command = clampi(c, 0, COMMAND_NAMES.size() - 1)
	command_changed.emit()

# 选编队：按 1/2/3 选第几队，再按一次同一个键回到全体
func toggle_squad(n: int) -> void:
	if n < 1 or n > SQUAD_MAX:
		return
	selection = 0 if selection == n else n
	selection_changed.emit()
	apply_selection_slow()

# e41h: 三个编队的名字 —— 1队=剑士(近战) / 2队=弓手(远程) / 3队=骑兵。
# 战斗指挥条、公告、派活面板的瓦片全从这儿取名字, 别在各自那儿另写一套「N队」。
const SQUAD_NAMES := {1: "剑士", 2: "弓手", 3: "骑兵"}

# e41j: 「不指挥」—— 0 是全体（三队都听令）, -1 是谁也不听令。
# 指挥栏那颗「取消选中」按的是这个：取消就是不指挥了, 别再退成全体（那反而把刚取消的
# 选择又变成了「全都听」，一下口令全军就动 —— 跟按钮字面意思正好相反）。
const SELECT_NONE := -1

func squad_name(sq: int) -> String:
	return String(SQUAD_NAMES.get(sq, "全体"))

func set_squad_selection(n: int) -> void:
	selection = clampi(n, SELECT_NONE, SQUAD_MAX)
	selection_changed.emit()
	apply_selection_slow()

# e17: 减速只在「选中了具体编队」的指挥时刻生效(0.1 倍)，全体/不指挥/下令后正常流速。
# ❗只在战场里动手 —— 岛上/海图上选编队不影响时间（那里本来也没有编队概念，兜个底）。
func apply_selection_slow() -> void:
	var bm := get_tree().get_first_node_in_group("battle")
	set_battle_slow(bm != null and selection > 0)

func selection_name() -> String:
	if selection < 0:
		return "不指挥"
	return "全体" if selection == 0 else squad_name(selection)

func squad_color(sq: int) -> Color:
	return SQUAD_COLORS.get(clampi(sq, 1, SQUAD_MAX), Color(1, 1, 1))

# 这个编队的伙伴听不听这轮指挥（selection = 0 时全体都听, -1 时谁都不听）
func commands_squad(sq: int) -> bool:
	return selection == 0 or clampi(sq, 1, SQUAD_MAX) == selection

# 战场慢放开关（e17: 只在选中编队指挥时开 0.1 倍 —— 下令后 selection 清 0 自动恢复）。
# 进战场不再自动慢；出战役/串场时兜底恢复（battle_map._finish 也调）。
const BATTLE_SLOW_SCALE := 0.1

func set_battle_slow(on: bool) -> void:
	Engine.time_scale = BATTLE_SLOW_SCALE if on else 1.0

# ---------------- 整场景藏 / 露（连 HUD 一起） ----------------
# ❗踩过的坑：CanvasLayer **不是** CanvasItem，把场景节点的 visible 设成 false
#   只能藏住它的 2D 内容 —— 挂在场景下面的 HUD（时间栏 / 快捷栏 / 提示字 / 公告）
#   照样画在屏幕上。于是上海图、进战场、上岸的时候，岛上的顶栏一直飘着，
#   海图上还叠着两张左上角提示。
#   所以藏场景必须走这里：可见性 + 子树里所有 CanvasLayer 一起藏。
func set_scene_visible(n: Node, on: bool) -> void:
	if n == null:
		return
	if n is CanvasItem:
		(n as CanvasItem).visible = on
	_toggle_layers(n, on)

func _toggle_layers(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = on
		_toggle_layers(c, on)

# ---------------- 场景切换 ----------------
# 岛 → 大地图：把游戏岛整个冻结藏起来（数据原样保留，回来不用恢复），
# 大地图作为覆盖节点挂在 root 上。出海时间照走但放慢（现实约 20 秒 = 游戏 10 分钟），
# 凌晨 2 点由 TimeManager 静默翻日，不弹睡觉结算。
func enter_travel(game: Node) -> void:
	if traveling:
		return
	traveling = true
	last_sail_day = _day_stamp()          # 一天只能出一次海（e13a）
	# 出海时间完全停止（e13a）: 海图上不流逝、时钟显示「航行中」;
	# 回岛时由 return_to_island 固定拨到晚上十点。
	TimeManager.time_running = false
	# d9: iris 收黑 -> 黑幕后切场景 -> 展开亮出海图（不再「啪」地硬切）
	var switch := func() -> void:
		Audio.set_scene_bgm("ocean")     # 海图：悠远的行船调（岛上那套昼夜 BGM 先让位）
		if game != null:
			game.process_mode = Node.PROCESS_MODE_DISABLED
			set_scene_visible(game, false)
		var wm: Node = preload("res://scene/world_map.gd").new()
		wm.name = "WorldMap"
		get_tree().root.add_child(wm)
		Quests.complete("sail_first")    # e32: 第一次出海
	IRIS.play("out", switch)

# 大地图 → 岛：iris 收黑后拆掉覆盖节点，把主角放回船边（d9: 不再硬切）
func return_to_island() -> void:
	traveling = false
	ashore = false
	# ❗出海起点归位：world_pos 不清的话，战败复活后再出海会从上次死亡的地方出现。
	#   置回 ZERO，下次进海图 _build_terrain 就会把人放回岛上码头（出海永远从家出发）。
	world_pos = Vector2.ZERO
	set_battle_slow(false)         # 兜底：不在战场上了就把时间恢复正常
	# 回岛固定晚上十点（e13a）: 海上一趟不论多久, 回家都是 22:00, 还能活动到凌晨两点。
	TimeManager.hour = 22
	TimeManager.minute = 0
	TimeManager.speed_scale = 1.0
	TimeManager.time_running = true
	TimeManager.snap()               # e27a: 拨完表立刻广播 tick, 昼夜色/时钟跟上, 不闪白天
	var switch := func() -> void:
		Audio.set_scene_bgm("island")        # 回岛上：交还给"白天/夜里自动换曲"
		var wm := get_tree().get_first_node_in_group("world_map")
		if wm != null:
			wm.queue_free()
		var bm := get_tree().get_first_node_in_group("battle")
		if bm != null:
			bm.queue_free()
		var ml := get_tree().get_first_node_in_group("mainland")
		if ml != null:
			ml.queue_free()
		var game := get_tree().get_first_node_in_group("game")
		if game != null:
			set_scene_visible(game, true)
			game.process_mode = Node.PROCESS_MODE_INHERIT
			if game.has_method("on_voyage_return"):
				game.on_voyage_return()
	IRIS.play("out", switch)

# 大地图 → 大陆据点（scene/mainland.gd）：iris 收黑后海图藏起来，据点亮出。
# 出海期间时间一直慢速走着，上了岸也一样 —— 据点里没有「睡觉换日」这回事。
func enter_mainland() -> void:
	if not traveling or ashore:
		return
	var wm := get_tree().get_first_node_in_group("world_map")
	if wm == null:
		return
	var ml: Node = preload("res://scene/mainland.gd").new()
	ml.name = "Mainland"
	var switch := func() -> void:
		get_tree().root.add_child(ml)
		set_scene_visible(wm, false)
		ashore = true
		Audio.set_scene_bgm("town")      # e21: 进据点换城镇小调
	IRIS.play("out", switch)

# 大地图 -> 城镇（scene/mainland.gd 的城镇模式）：iris 收黑后海图藏起来，城镇亮出。
# tid 是 Nations.TOWNS 的键；mainland 在 _ready 前拿到 town_id，按城摆房、报城名。
func enter_town(tid: String) -> void:
	if not traveling or ashore:
		return
	var wm := get_tree().get_first_node_in_group("world_map")
	if wm == null:
		return
	var ml: Node = preload("res://scene/mainland.gd").new()
	ml.name = "Mainland"
	ml.set("town_id", tid)
	var switch := func() -> void:
		get_tree().root.add_child(ml)
		set_scene_visible(wm, false)
		ashore = true
		Audio.set_scene_bgm("town")      # e21: 进城换城镇小调
	IRIS.play("out", switch)

# 据点 → 大地图（从栈桥返航）：iris 收黑后拆掉据点，海图重新亮出
func leave_mainland() -> void:
	if not ashore:
		return
	var ml := get_tree().get_first_node_in_group("mainland")
	var wm := get_tree().get_first_node_in_group("world_map")
	var switch := func() -> void:
		if ml != null:
			ml.queue_free()
		if wm != null:
			set_scene_visible(wm, true)
			# 拆据点时它把自己的相机也带走了：回来第一件事把海图相机扶正，
			# 不然画面定格在别的地图角落，人也点不动（看着像卡死）。
			if wm.has_method("resume_camera"):
				wm.call("resume_camera")
		ashore = false
		Audio.set_scene_bgm("ocean")     # e21: 回海图换回宏伟的航路曲
	IRIS.play("out", switch)

# 大地图 → 战役地图（遭遇敌人）。d10: 不再「啪」地硬切 ——
# iris 在旧海图上先收拢成黑幕，黑幕后才真正切场景，再展开亮出战场。
func enter_battle(party: Dictionary) -> void:
	var wm := get_tree().get_first_node_in_group("world_map")
	if wm == null:
		return
	# 遭遇战的打法已经换成 KARDS 式卡牌（见 scene/battle_cards.gd）；
	# 旧的骑砍式战役地图 scene/battle_map.gd 保留在库里, 只是不再从这里进。
	var switch := func() -> void:
		var bm: Node = preload("res://scene/battle_cards.gd").new()
		bm.name = "CardBattle"
		bm.set("party", party)
		Audio.set_scene_bgm("battle")    # 开打：军鼓上来
		get_tree().root.add_child(bm)
		set_scene_visible(wm, false)
	IRIS.play("out", switch)

# 城镇议事厅 → 攻城战：iris 收黑后城镇场景藏起来，战斗盖在上面。
# tid 是 Nations.TOWNS 的键；守军规模由 Nations.garrison_of 决定（破过城会变少）。
func enter_siege(tid: String) -> void:
	var ml := get_tree().get_first_node_in_group("mainland")
	if ml == null:
		return
	var switch := func() -> void:
		var bm: Node = preload("res://scene/battle_cards.gd").new()
		bm.name = "CardBattle"
		bm.set("party", {"type": "攻城", "size": maxi(1, Nations.garrison_of(tid)), "siege": tid})
		Audio.set_scene_bgm("battle")    # 开打：军鼓上来
		get_tree().root.add_child(bm)
		set_scene_visible(ml, false)
	IRIS.play("out", switch)

# 战役 → 结果分流：victory/retreat 回大地图，defeat 直接回家躺门口
func end_battle(result: String) -> void:
	var bm := get_tree().get_first_node_in_group("battle")
	if bm != null:
		bm.queue_free()
	if result == "defeat":
		return_to_island()
		var game := get_tree().get_first_node_in_group("game")
		if game != null and game.has_method("on_voyage_defeat"):
			game.on_voyage_defeat()
		return
	Audio.set_scene_bgm("ocean")    # 军鼓退场：回海图就换回海的曲子（此前只有 defeat 路径会重设）
	# 城镇里发起的攻城战：打完不回城里，直接回海图（城头刚打过一仗）
	var ml := get_tree().get_first_node_in_group("mainland")
	if ml != null:
		ml.queue_free()
		ashore = false
	var wm := get_tree().get_first_node_in_group("world_map")
	if wm != null:
		set_scene_visible(wm, true)
		if wm.has_method("resume_camera"):
			wm.call("resume_camera")   # 战场拆掉时相机也没了，海图相机扶正
		wm.call("on_battle_done", result)

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {
		"dock": dock_state,
		"dock_work": dock_work,
		"boats": boat_count,
		"world_x": world_pos.x,
		"world_y": world_pos.y,
		"last_sail_day": last_sail_day,
	}

func from_dict(d: Dictionary) -> void:
	dock_state = clampi(int(d.get("dock", DOCK_RUIN)), DOCK_RUIN, DOCK_BUILT)
	dock_work = clampi(int(d.get("dock_work", 0)), 0, DOCK_WORK)
	boat_count = clampi(int(d.get("boats", 0)), 0, BOAT_MAX)
	# 老存档只记了「船下水的格子」——那会儿全岛就一艘，直接当成码头已修好 + 1 条船
	var legacy := String(d.get("boat", ""))
	if legacy.contains(",") and boat_count == 0:
		boat_count = 1
		dock_state = DOCK_BUILT
		dock_work = DOCK_WORK
	world_pos = Vector2(float(d.get("world_x", 0.0)), float(d.get("world_y", 0.0)))
	last_sail_day = int(d.get("last_sail_day", -1))
	dock_changed.emit()
