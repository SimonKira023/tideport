# quests.gd —— 任务栏数据（开局指引 + 毕业后的里程碑长线目标）
#
# 状态整体进存档（to_dict/from_dict）：读档后任务栏不再空白，
# 里程碑的奖励也不会因为读档把进度洗掉而重复发。
# 新档开局 game.gd 调 start_guide()；完成由事件侧触发：
#   · go_house      -> house.gd 玩家第一次进屋
#   · buy_goblin    -> shop_ui.gd 第一次成功购买
#   · till_first    -> player.gd 第一次锄出耕地
#   · plant_first   -> player.gd 第一次播种成功
#   · water_first   -> player.gd 第一次浇水成功
#   · harvest_first -> player.gd 第一次收下作物
#   · sell_first    -> scene/shipping_bin.gd 第一次从售卖箱卖出货
#   · explore_island -> 第一次钓上鱼, 独立可选目标
# complete(id) 按 _CHAIN / _MID_CHAIN 自动挂上下一步；跳步完成过的环节不再回挂。
#
# 毕业后任务栏常驻一个里程碑任务（永远显示最靠前的未达成项），
# 达成条件由各系统已有的信号驱动 check_milestones() 自动结算：
# 奖励直接进钱包 + rewarded 信号（game.gd 弹屏幕公告）。
# ❗读档/开新档期间 SaveManager 会 suspend_checks()：半新半旧的混装状态
#   不许结算里程碑，否则会把上一把的进度错算成新档达成、白给一份奖。
extends Node

signal changed
signal rewarded(text: String)   # 里程碑达成（game.gd 听了弹公告）
signal celebrated(text: String) # 终局里程碑达成（game.gd 弹大庆祝横幅, 不锁档继续玩）

# 第一周指引链：开局只赠工具, 第一次购买当季作物种子后开始种田。
const _CHAIN := {
	"go_house": ["buy_goblin", "买第一包种子",
		"工具已经领好. 出门去东边桥头找哥布林, 按 F 买当季作物种子, 先买 3 包就好."],
	"buy_goblin": ["till_first", "开出第一块田",
		"在家附近选一块空草地, 用数字键选锄头, 左键开田."],
	"till_first": ["plant_first", "播下第一颗种子",
		"选中当季种子, 对耕地左键播种. 先种几块就好, 留点时间逛岛."],
	"plant_first": ["water_first", "给苗浇头道水",
		"选洒水壶, 对苗左键浇水. 壶空了去水边补水, 下雨会自动浇田."],
	"water_first": ["harvest_first", "等待第一份收成",
		"每天浇水, 成熟后左键收获. 漏浇只会停长. 等待时去坡上篝火找咪露, 或按 B 查看制作."],
	"harvest_first": ["sell_first", "卖出第一份作物",
		"走到屋边售卖箱按 F, 放入收成再关箱, 金币马上到账. 之后可以建造家园."],
	"sell_first": ["build_first", "添一件家园设施",
		"按 B 打开建造, 先放一个储物箱或一盏路灯. 小件当场建好, 房屋要按 T 派伙伴施工."],
}

# 经营与出海是主线, 钓鱼和复国各自独立, 不互相充当门槛。
const _MID_CHAIN := {
	"build_first": ["mine_first", "安排第一份采矿工作",
		"按 T 打开派活, 把一位伙伴放入采集矿石, 选采石或采铁. 次日早上收到矿物, 计划会保留."],
	"mine_first": ["tech_first", "让日常工作更省力",
		"按 T 派伙伴研究科技, 晚上得到研究点. 按 B 到发展-科技, 优先研究水轮或引水渠."],
	"tech_first": ["sail_first", "准备第一次航行",
		"去东岸废弃码头按 F, 付材料并按 T 派人修建, 造好足够的船后出海. 可以先做贸易, 不必打仗."],
}
const WAR_CHAIN := {
	"navy_first": ["contract_first", "选择一份外交契约",
		"按 B 到外交查看声望和关系要求. 先做贸易与赠礼也能积累声望, 不用连续打仗."],
	"contract_first": ["siege_first", "准备自己的远征",
		"在发展-战斗整理卡组, 准备好后到大陆议事厅选择攻城. 可随时暂停这条路线."],
}
const OPTIONAL_TASKS := {
	"explore_island": ["去水边钓条鱼", "找哥布林了解鱼竿, 买到后选中钓竿对水面左键. 有咬钩提示时再收竿, 钓鱼不影响建造解锁."],
	"meet_partner": ["和咪露一起安顿下来", "坡上的篝火有来客时走近按 F, 和咪露相认并邀请她加入. 她能帮忙照料田地."],
	"sea_trade_first": ["收到第一笔海外货款", "建成市集, 去售卖箱选择海外渠道放货. 次日到账, 比本地售卖多赚 40%."],
}

# 毕业后的里程碑长线目标（按数组顺序检查；达成发奖励，任务栏常驻最靠前的未达成项）
# check 类型：money 钱包金额 / crops 背包作物份数 / tilled 耕地块数 / crew 伙伴人数 /
#             techs 完成的科技数 / navy 打赢过海战 / favor 五国好感全达标 /
#             prestige 声望 / lord 封臣契约+封地 / unify 占领全部王都
# grand: true = 终局目标, 达成走 celebrated 弹大横幅 —— 只庆祝, 不锁档, 沙盒继续玩
const MILESTONES := [
	{"id": "ms_gold", "title": "首桶金", "desc": "攒下 2000 金",
		"check": "money", "goal": 2000, "reward": 500},
	{"id": "ms_harvest", "title": "满仓丰收", "desc": "背包里攒够 30 份作物",
		"check": "crops", "goal": 30, "reward": 800},
	{"id": "ms_farm", "title": "大农场", "desc": "开垦 30 块耕地",
		"check": "tilled", "goal": 30, "reward": 1000},
	{"id": "ms_crew", "title": "招贤纳士", "desc": "招齐 6 名同伴",
		"check": "crew", "goal": 6, "reward": 1500},
	{"id": "ms_tech", "title": "科技崛起", "desc": "完成 3 项科技研究",
		"check": "techs", "goal": 3, "reward": 1200, "perk": "tech_point", "perk_val": 2},
	{"id": "ms_navy", "title": "出海首胜", "desc": "在海上打赢一场遭遇战",
		"check": "navy", "goal": 1, "reward": 1500, "route": "war", "perk": "prestige", "perk_val": 5},
	{"id": "ms_friends", "title": "建交五方", "desc": "五国好感都到 20",
		"check": "favor", "goal": 20, "reward": 2000, "perk": "prestige", "perk_val": 8},
	# 终局三连: 达成即庆典, 但游戏永不收官 —— 想怎么玩还怎么玩
	{"id": "ms_lord", "title": "裂土封王", "desc": "签下封臣契约, 拿到一座封地",
		"check": "lord", "reward": 3000, "route": "war", "grand": true},
	{"id": "ms_prestige", "title": "威震四海", "desc": "声望攒到 100",
		"check": "prestige", "goal": 100, "reward": 3000, "route": "war", "grand": true},
	{"id": "ms_unify", "title": "四海归一", "desc": "把五国的王都都插上你的旗",
		"check": "unify", "reward": 5000, "route": "war", "grand": true},
]

const HOME_MILESTONE := {
	"id": "ms_home", "title": "潮汐港是我们的家", "desc": "招募 3 位伙伴, 建好小屋和市集, 完成 3 项科技并收到海外货款",
	"check": "home", "reward": 2000, "grand": true,
}

const TASK_MILESTONE := "milestone"   # 里程碑在任务栏里的常驻任务位 id

# Esc 模块渐进解锁: 完成对应任务 id 后开放 (bag/team/map/quests/set 无门槛)
const MODULE_UNLOCK := {
	"hero": "harvest_first", "calendar": "go_house", "craft": "water_first",
	"build": "sell_first", "grow": "build_first", "diplomacy": "sail_first",
}
const TASK_PAGE := {
	"build_first": "build", "mine_first": "team", "tech_first": "grow",
	"navy_first": "grow", "contract_first": "diplomacy", "siege_first": "diplomacy",
}
const TASK_GROW_SUB := {"tech_first": "tech", "navy_first": "battle"}
var war_route := false
var tracked_id := ""
var _module_access := {}   # 旧档已开放入口不回锁, 新档按相关经历开放。
var quiet_nights := true
var peaceful_voyage := true

var _tasks: Array = []        # [{id, title, desc}]
var _done := {}               # 完成过的任务 id（防跳步回挂）
var _guide_started := false   # 本局是否已发起开局指引

var _milestones_on := false   # 指引链毕业（explore_island 完成）后才开闸
var _milestone_done := {}     # 已领奖的里程碑 id -> true（进存档，防重复发）
var _navy_win := false        # 打赢过海战（出海首胜用，进存档）
var _fish_first := false      # 钓上过第一条鱼（e32: 毕业条件, 进存档）
var _suspended := false       # 存档读档/开新档期间挂起检查

func _ready() -> void:
	# 里程碑条件全靠各系统已有的信号驱动，这里集中接线。
	# Quests 在 autoload 末段，这些单例此刻都已就绪。
	Wallet.money_changed.connect(func(_a: int): check_milestones())
	Inventory.inventory_changed.connect(check_milestones)
	Farm.tilled_added.connect(func(_p: Vector2i): check_milestones())
	Slaves.changed.connect(check_milestones)
	Research.changed.connect(check_milestones)
	Nations.changed.connect(check_milestones)
	Slaves.changed.connect(_on_partner_changed)
	Structures.station_changed.connect(func(_c: Vector2i): check_milestones())
	Voyage.dock_changed.connect(func(): changed.emit())
	Nations.prestige_changed.connect(check_milestones)   # e26c: 声望走自己的信号, 终局"威震四海"要听

# 新档开局：发起指引任务链
func start_guide() -> void:
	if _guide_started:
		return
	_guide_started = true
	add("go_house", "瞧瞧东边那栋房子",
		"向东找到小屋, 靠近门按 F. 哥布林准备了四件农具, 种子需要到桥头摊位购买.")

func add(id: String, title: String, desc: String) -> void:
	if has_active(id):
		return
	_tasks.append({"id": id, "title": title, "desc": desc})
	changed.emit()

func complete(id: String) -> void:
	_done[id] = true
	# 旧档已有种子时允许直接种下, 不把已经会种田的玩家拉回购物教程。
	if id == "plant_first":
		cancel("buy_goblin")
	var before := _tasks.size()
	_tasks = _tasks.filter(func(t): return t["id"] != id)
	if _tasks.size() != before:
		changed.emit()
	_chain_from(id)
	if id == "water_first" and Slaves.count == 0:
		_add_optional("meet_partner")
	if id == "sell_first" and _guide_started:
		start_milestones()
		_add_optional("explore_island")
	if id == "sail_first":
		_add_optional("sea_trade_first")
	if id == "explore_island" and has_done("sell_first") and _guide_started:
		start_milestones()   # 指引链毕业 -> 长线里程碑开闸
	elif _fish_first and has_active("explore_island"):
		# e32: 鱼早就钓过了, 只是链才刚走到这一环 —— 补一次毕业
		complete("explore_island")
	changed.emit()

# e32 毕业条件: 钓上第一条鱼。player.gd 钓鱼成功时调。
# 指引链还没走到 explore_island 的话只记下 flag, 等链走到那一环时 complete() 里补毕业。
func note_first_fish() -> void:
	if _fish_first:
		return
	_fish_first = true
	if has_active("explore_island"):
		complete("explore_island")

func caught_first_fish() -> bool:
	return _fish_first

# 播种在已湿润的土里也算完成照料, 不要求玩家再次对湿田无效点击。
func note_planted(cell: Vector2i) -> void:
	complete("plant_first")
	if Farm.has_crop(cell) and Farm.is_watered(cell):
		complete("water_first")

# 链条衔接：id 完成后挂下一步（跳步完成过的不再挂）
func _chain_from(id: String) -> void:
	var nx: Array = _CHAIN.get(id, _MID_CHAIN.get(id, []))
	if war_route and WAR_CHAIN.has(id):
		nx = WAR_CHAIN[id]
	if nx.is_empty():
		return
	var next_id: String = String(nx[0])
	if next_id == "buy_goblin" and has_done("plant_first"):
		_chain_from(next_id)
		return
	if has_done(next_id):
		_chain_from(next_id)
	else:
		add(next_id, String(nx[1]), String(nx[2]))

func _add_optional(id: String) -> void:
	if has_done(id):
		return
	if id == "meet_partner":
		cancel(String(Slaves.ROSTER[0]["id"]))
	var entry: Array = OPTIONAL_TASKS[id]
	add(id, String(entry[0]), String(entry[1]))

func _on_partner_changed() -> void:
	if Slaves.count > 0 and has_active("meet_partner"):
		complete("meet_partner")
	changed.emit()

func choose_war_route(enabled_route: bool) -> void:
	war_route = enabled_route
	peaceful_voyage = not enabled_route
	for id in ["navy_first", "contract_first", "siege_first"]:
		cancel(id)
	if war_route:
		if not has_done("navy_first"):
			add("navy_first", "尝试第一场海战", "先去发展-战斗查看卡组, 出海寻找小股海寇. 这是可选挑战, 可撤退或暂停路线.")
		else:
			_chain_from("navy_first")
	_sync_milestone_task()
	changed.emit()

func track(id: String) -> void:
	if has_active(id):
		tracked_id = id
		changed.emit()

func tracked_task() -> Dictionary:
	for t in _tasks:
		if String(t["id"]) == tracked_id:
			return t.duplicate(true)
	# 优先经营指引, 然后来客, 最后长期目标。
	for t in _tasks:
		if String(t["id"]) in _CHAIN or String(t["id"]) in _MID_CHAIN or String(t["id"]) == "sail_first":
			return t.duplicate(true)
	return _tasks[0].duplicate(true) if not _tasks.is_empty() else {}

# HUD 和任务页共用只读指引, 不在界面里另外推断任务进度。
func guidance() -> Dictionary:
	var task: Dictionary = tracked_task()
	return preload("res://scene/first_week_guide.gd").describe(task, page_for_task(String(task.get("id", ""))))

func grow_sub_unlocked(sub: String) -> bool:
	if _module_access.has("grow"):
		return true
	match sub:
		"battle": return Voyage.dock_state == Voyage.DOCK_BUILT or has_done("sail_first")
		"admin": return has_done("tech_first") and Slaves.count >= 2
	return module_unlocked("grow")

func building_lock_hint(kind: String) -> String:
	if Structures.has_built_kind(kind) or _module_access.has("build"):
		return ""
	if kind in ["barn", "silo", "mill", "hive", "blacksmith"] and not has_done("build_first"):
		return "先建好一件家园设施"
	if kind == "bakery" and not Structures.has_built_kind("mill"):
		return "先建好磨坊, 才有面粉可加工"
	if kind == "weaver" and not Structures.has_built_kind("barn"):
		return "先建好畜棚, 才有羊毛来源"
	if kind == "greenhouse" and not has_done("tech_first"):
		return "先完成第一项科技"
	if kind in ["market", "lighthouse"] and not has_done("tech_first"):
		return "先完成第一项科技, 再发展港口"
	if kind in ["barracks", "academy", "stable"] and not grow_sub_unlocked("battle"):
		return "先修好码头, 再准备航行装备"
	return ""

func has_active(id: String) -> bool:
	for t in _tasks:
		if t["id"] == id:
			return true
	return false

# e53: 这个 id 完成过没（指引链 / 中期链的 flag 都算）。
# 招募任务（recruits.gd）拿链 flag 当招募条件用。
func has_done(id: String) -> bool:
	return _done.has(id)

# e53: 撤下一个还在栏里的任务（招募窗口关闭时用; _done 完成记录不动）。
func cancel(id: String) -> void:
	var before := _tasks.size()
	_tasks = _tasks.filter(func(t): return t["id"] != id)
	if _tasks.size() != before:
		changed.emit()

func active() -> Array:
	return _tasks.duplicate(true)

# ---------------- 里程碑 ----------------

# 指引链毕业调用：开闸里程碑（幂等）
func start_milestones() -> void:
	if _milestones_on:
		return
	_milestones_on = true
	check_milestones()

# 打赢海战（battle_map.gd 胜利时调：海寇/巡逻遭遇战算数）
func note_navy_win() -> void:
	_navy_win = true
	check_milestones()

# e42: 过场钩子用 —— 打赢过海战没 (world_map 那边判断该不该放「出海首胜」)
func has_navy_win() -> bool:
	return _navy_win

# e42: 过场钩子用 —— 这个里程碑达成过没 (grand 里程碑是剧情节点)
func has_milestone(id: String) -> bool:
	return _milestone_done.has(id)

func check_milestones() -> void:
	if _suspended or not _milestones_on:
		return
	for m in MILESTONES + [HOME_MILESTONE]:
		var id := String(m["id"])
		if _milestone_done.has(id) or not _milestone_met(m):
			continue
		_milestone_done[id] = true
		Wallet.add_money(int(m["reward"]))
		_apply_milestone_perk(m)
		if bool(m.get("grand", false)):
			# 终局目标: 大庆祝, 但不锁档 —— 宣词里就说清楚, 海还是你的
			celebrated.emit("%s达成! 奖励 +%d 金" % [String(m["title"]), int(m["reward"])])
		else:
			rewarded.emit("%s达成! 奖励 +%d 金" % [String(m["title"]), int(m["reward"])])
	_sync_milestone_task()

func _milestone_met(m: Dictionary) -> bool:
	match String(m["check"]):
		"home":
			return has_done("sea_trade_first") and Slaves.count >= 3 and Structures.has_built_kind("hut") \
				and Structures.has_built_kind("market") and _milestone_met({"check": "techs", "goal": 3})
		"money":
			return Wallet.money >= int(m["goal"])
		"crops":
			var n := 0
			for s in Inventory.slot_list():
				var it = s["item"]
				if it != null and it is ItemData and String(it.type) == "作物":
					n += int(s["count"])
			return n >= int(m["goal"])
		"tilled":
			return Farm.tilled.size() >= int(m["goal"])
		"crew":
			return Slaves.count >= int(m["goal"])
		"techs":
			var finished := 0
			for tid in Research.TECHS.keys():
				if Research.has_tech(String(tid)):
					finished += 1
			return finished >= int(m["goal"])
		"navy":
			return _navy_win
		"favor":
			for nid in Nations.nation_ids():
				if Nations.favor_of(String(nid)) < int(m["goal"]):
					return false
			return true
		"prestige":                       # e26c 终局: 威震四海
			return Nations.prestige >= int(m["goal"])
		"lord":                           # e26c 终局: 裂土封王
			return Nations.contract == "封臣" and Nations.fief != ""
		"unify":                          # e26c 终局: 四海归一（所有王都插旗）
			for tid in Nations.TOWNS.keys():
				var t: Dictionary = Nations.TOWNS[tid]
				if String(t.get("kind", "")) == "capital" \
						and not Nations.occupied.has(String(tid)):
					return false
			return true
	return false

# 任务栏常驻位：永远显示最靠前的未达成里程碑（全部达成后撤下）
func _next_milestone() -> Dictionary:
	for m in MILESTONES + [HOME_MILESTONE]:
		if String(m.get("route", "")) == "war" and not war_route:
			continue
		if not _milestone_done.has(String(m["id"])):
			return m
	return {}

func _sync_milestone_task() -> void:
	# 没毕业(没开闸)时常驻位不该存在: 新档/老档读进来都不显示
	if not _milestones_on:
		for i in _tasks.size():
			if String(_tasks[i]["id"]) == TASK_MILESTONE:
				_tasks.remove_at(i)
				changed.emit()
				break
		return
	var idx := -1
	for i in _tasks.size():
		if String(_tasks[i]["id"]) == TASK_MILESTONE:
			idx = i
			break
	var m := _next_milestone()
	if m.is_empty():
		if idx >= 0:
			_tasks.remove_at(idx)
			changed.emit()
		return
	var task := {
		"id": TASK_MILESTONE,
		"title": "里程碑: %s" % String(m["title"]),
		"desc": "%s (奖励 %d 金)" % [String(m["desc"]), int(m["reward"])],
	}
	if idx < 0:
		_tasks.append(task)
		changed.emit()
	elif _tasks[idx] != task:
		_tasks[idx] = task
		changed.emit()

# selftest / SaveManager 用
func milestones_enabled() -> bool:
	return _milestones_on

func milestone_done(id: String) -> bool:
	return _milestone_done.has(id)

# 存档读档/开新档期间挂起里程碑检查（SaveManager._apply / reset_all 调）
func suspend_checks() -> void:
	_suspended = true

func resume_checks() -> void:
	_suspended = false

# 新档重置（SaveManager.reset_all 之后由 game.gd 调）
func reset_all() -> void:
	_tasks.clear()
	_done.clear()
	_guide_started = false
	_milestones_on = false
	_milestone_done.clear()
	_navy_win = false
	_fish_first = false
	war_route = false
	tracked_id = ""
	quiet_nights = true
	peaceful_voyage = true
	_module_access.clear()
	changed.emit()

func module_unlocked(key: String) -> bool:
	if _module_access.has(key):
		return true
	if not MODULE_UNLOCK.has(key):
		return true
	return _done.has(String(MODULE_UNLOCK[key]))

func module_lock_hint(key: String) -> String:
	if module_unlocked(key):
		return ""
	var need := String(MODULE_UNLOCK.get(key, ""))
	return "完成 %s 后开放" % _task_title_for_id(need)

func _task_title_for_id(id: String) -> String:
	for chain in [_CHAIN, _MID_CHAIN, WAR_CHAIN]:
		for nx in chain.values():
			if String(nx[0]) == id:
				return String(nx[1])
	if id == "go_house":
		return "安顿住处"
	return id

func page_for_task(id: String) -> String:
	return String(TASK_PAGE.get(id, ""))

func grow_sub_for_task(id: String) -> String:
	return String(TASK_GROW_SUB.get(id, "tech"))

func goto_active_page() -> bool:
	var task: Dictionary = tracked_task()
	if task.is_empty():
		return false
	var id := String(task["id"])
	if id == TASK_MILESTONE:
		return false
	var page := page_for_task(id)
	if page == "":
		return false
	var bp: Node = get_tree().get_first_node_in_group("backpack_panel")
	if bp == null or not bp.has_method("open_to"):
		return false
	var sub := grow_sub_for_task(id) if page == "grow" else ""
	bp.call("open_to", page, sub)
	return true

func _apply_milestone_perk(m: Dictionary) -> void:
	if not m.has("perk"):
		return
	match String(m["perk"]):
		"tech_point":
			Research.tech_points += int(m.get("perk_val", 1))
			Research.changed.emit()
		"prestige":
			Nations.add_prestige(int(m.get("perk_val", 3)))

func unlock_all_modules_for_ui() -> void:
	for key in MODULE_UNLOCK:
		_module_access[String(key)] = true
	changed.emit()

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {
		"version": 3, "tracked": tracked_id, "war_route": war_route,
		"module_access": _module_access.keys(), "quiet_nights": quiet_nights,
		"peaceful_voyage": peaceful_voyage,
		"done": _done.keys(),
		"guide": _guide_started,
		"ms_on": _milestones_on,
		"ms_done": _milestone_done.keys(),
		"navy": _navy_win,
		"fish": _fish_first,
	}

func from_dict(d: Dictionary) -> void:
	_tasks.clear()
	_module_access.clear()
	_done.clear()
	for k in d.get("done", []):
		_done[String(k)] = true
	_guide_started = bool(d.get("guide", false))
	# 已经开始种田的旧档不回挂购种教程, 也不扣除以前领到的物品。
	if int(d.get("version", 0)) < 3:
		for flag: String in ["till_first", "plant_first", "water_first", "harvest_first", "sell_first"]:
			if has_done(flag):
				_done["buy_goblin"] = true
				break
	_milestones_on = bool(d.get("ms_on", false))
	_milestone_done.clear()
	for k in d.get("ms_done", []):
		_milestone_done[String(k)] = true
	_navy_win = bool(d.get("navy", false))
	_fish_first = bool(d.get("fish", false))
	tracked_id = String(d.get("tracked", ""))
	war_route = bool(d.get("war_route", false))
	quiet_nights = bool(d.get("quiet_nights", true))
	peaceful_voyage = bool(d.get("peaceful_voyage", not war_route))
	for key in d.get("module_access", []):
		_module_access[String(key)] = true
	if int(d.get("version", 0)) < 2:
		var legacy := {"hero": "till_first", "calendar": "plant_first", "craft": "harvest_first", "build": "explore_island", "grow": "mine_first", "diplomacy": "sail_first"}
		for key in legacy:
			if has_done(String(legacy[key])):
				_module_access[key] = true
	if _guide_started:
		if not has_done("go_house"):
			add("go_house", "安顿住处", "向东找到小屋, 靠近门按 F. 先领取工具, 再到哥布林摊位购买种子.")
		else:
			_chain_from("go_house")
		if has_done("sell_first"):
			_milestones_on = true
			_add_optional("explore_island")
		if has_done("water_first") and Slaves.count == 0:
			_add_optional("meet_partner")
		if has_done("sail_first"):
			_add_optional("sea_trade_first")
		if war_route:
			choose_war_route(true)
	# 恢复战争指引时不覆盖玩家单独选择的安心贸易偏好。
	peaceful_voyage = bool(d.get("peaceful_voyage", not war_route))
	_sync_milestone_task()
	changed.emit()
