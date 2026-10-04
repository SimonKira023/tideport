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
#   · explore_island -> 第一次钓上鱼（e32 毕业条件, 完成即开闸里程碑 + 接上中后期链）
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

# 第一周指引链：id -> [下一步 id, 标题, 描述]（链尾 explore_island 无下一环）
const _CHAIN := {
	"go_house": ["buy_goblin", "照顾哥布林的生意",
		"在哥布林摊位买点东西, 他就好这口"],
	"buy_goblin": ["till_first", "开出第一块田",
		"拿锄头对准草地挥一下, 开出能播种的耕地"],
	"till_first": ["plant_first", "播下第一颗种子",
		"拿一包种子对准耕地点一下, 把它埋进土里"],
	"plant_first": ["water_first", "给苗浇头道水",
		"拿洒水壶对准耕地浇水, 苗每天都要喝水"],
	"water_first": ["harvest_first", "收获第一份作物",
		"照看好田地, 作物熟了收下来"],
	"harvest_first": ["sell_first", "卖出第一份作物",
		"把收成投进屋边的售卖箱, 关箱就换成金币"],
	"sell_first": ["explore_island", "去水边钓条鱼",
		"拿钓竿对着水面点一下, 钓上第一条鱼就算出师了"],
}

# 第二段指引链（e32 中后期指引）：毕业之后接着往下指, 一路串到中后期各大系统。
# 跟 _CHAIN 分开放：_CHAIN 是「第一周」的封闭链, 这里是「出新手村」之后的开放链。
# 每一环都由对应系统的首次达成事件驱动 Quests.complete(id)：
#   · explore_island -> player.gd 第一次钓上鱼（也是毕业条件, 见 note_first_fish）
#   · build_first    -> structures.gd place() 盖起第一座建筑
#   · mine_first     -> ore_data.gd settle_mine_day() 矿井第一次有产出
#   · tech_first     -> research.gd research_tech() 完成第一项科技
#   · sail_first     -> voyage.gd enter_travel() 第一次出海
#   · navy_first     -> scene/battle_map.gd 打赢第一场海战
#   · contract_first -> nations.gd sign_contract() 签下第一份契约
#   · siege_first    -> nations.gd on_siege_victory() 攻下第一座城（链尾）
const _MID_CHAIN := {
	"explore_island": ["build_first", "盖起第一座建筑",
		"打开建造页, 在空地上盖一间鸡舍或者熔炉"],
	"build_first": ["mine_first", "下矿挖第一份矿",
		"在派活页把伙伴派进矿井, 他们每天早上挖矿回来"],
	"mine_first": ["tech_first", "研究出第一项科技",
		"打开科技页, 花科技点点开第一项研究"],
	"tech_first": ["sail_first", "出海跑一趟",
		"修好码头就能出海, 去别的海域看看"],
	"sail_first": ["navy_first", "打赢第一场海战",
		"海上撞见海寇或者巡逻队, 打赢他们"],
	"navy_first": ["contract_first", "签下第一份契约",
		"声望够了就能在外交页签雇佣兵或者封臣契约"],
	"contract_first": ["siege_first", "攻下第一座城",
		"带兵打下一座城, 把它插上你的旗"],
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
		"check": "techs", "goal": 3, "reward": 1200},
	{"id": "ms_navy", "title": "出海首胜", "desc": "在海上打赢一场遭遇战",
		"check": "navy", "goal": 1, "reward": 1500},
	{"id": "ms_friends", "title": "建交五方", "desc": "五国好感都到 20",
		"check": "favor", "goal": 20, "reward": 2000},
	# 终局三连: 达成即庆典, 但游戏永不收官 —— 想怎么玩还怎么玩
	{"id": "ms_lord", "title": "裂土封王", "desc": "签下封臣契约, 拿到一座封地",
		"check": "lord", "reward": 3000, "grand": true},
	{"id": "ms_prestige", "title": "威震四海", "desc": "声望攒到 100",
		"check": "prestige", "goal": 100, "reward": 3000, "grand": true},
	{"id": "ms_unify", "title": "四海归一", "desc": "把五国的王都都插上你的旗",
		"check": "unify", "reward": 5000, "grand": true},
]

const TASK_MILESTONE := "milestone"   # 里程碑在任务栏里的常驻任务位 id

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
	Nations.prestige_changed.connect(check_milestones)   # e26c: 声望走自己的信号, 终局"威震四海"要听

# 新档开局：发起指引任务链
func start_guide() -> void:
	if _guide_started:
		return
	_guide_started = true
	add("go_house", "瞧瞧东边那栋房子",
		"东边有一栋房子, 进去看看是谁的屋子")

func add(id: String, title: String, desc: String) -> void:
	if has_active(id):
		return
	_tasks.append({"id": id, "title": title, "desc": desc})
	changed.emit()

func complete(id: String) -> void:
	_done[id] = true
	var before := _tasks.size()
	_tasks = _tasks.filter(func(t): return t["id"] != id)
	if _tasks.size() != before:
		changed.emit()
	_chain_from(id)
	if id == "explore_island":
		start_milestones()   # 指引链毕业 -> 长线里程碑开闸
	elif _fish_first and has_active("explore_island"):
		# e32: 鱼早就钓过了, 只是链才刚走到这一环 —— 补一次毕业
		complete("explore_island")

# e32 毕业条件: 钓上第一条鱼。player.gd 钓鱼成功时调。
# 指引链还没走到 explore_island 的话只记下 flag, 等链走到那一环时 complete() 里补毕业。
func note_first_fish() -> void:
	if _fish_first:
		return
	_fish_first = true
	if has_active("explore_island"):
		complete("explore_island")

# 链条衔接：id 完成后挂下一步（跳步完成过的不再挂）
func _chain_from(id: String) -> void:
	var nx: Array = []
	if _CHAIN.has(id):
		nx = _CHAIN[id]
	elif _MID_CHAIN.has(id):
		nx = _MID_CHAIN[id]
	if nx.is_empty():
		return
	if not _done.has(String(nx[0])):
		add(String(nx[0]), String(nx[1]), String(nx[2]))

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
	for m in MILESTONES:
		var id := String(m["id"])
		if _milestone_done.has(id) or not _milestone_met(m):
			continue
		_milestone_done[id] = true
		Wallet.add_money(int(m["reward"]))
		if bool(m.get("grand", false)):
			# 终局目标: 大庆祝, 但不锁档 —— 宣词里就说清楚, 海还是你的
			celebrated.emit("%s达成! 奖励 +%d 金" % [String(m["title"]), int(m["reward"])])
		else:
			rewarded.emit("%s达成! 奖励 +%d 金" % [String(m["title"]), int(m["reward"])])
	_sync_milestone_task()

func _milestone_met(m: Dictionary) -> bool:
	match String(m["check"]):
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
	for m in MILESTONES:
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
	changed.emit()

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {
		"done": _done.keys(),
		"guide": _guide_started,
		"ms_on": _milestones_on,
		"ms_done": _milestone_done.keys(),
		"navy": _navy_win,
		"fish": _fish_first,
	}

func from_dict(d: Dictionary) -> void:
	_done.clear()
	for k in d.get("done", []):
		_done[String(k)] = true
	_guide_started = bool(d.get("guide", false))
	_milestones_on = bool(d.get("ms_on", false))
	_milestone_done.clear()
	for k in d.get("ms_done", []):
		_milestone_done[String(k)] = true
	_navy_win = bool(d.get("navy", false))
	_fish_first = bool(d.get("fish", false))
	_sync_milestone_task()
	changed.emit()
