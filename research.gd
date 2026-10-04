# research.gd —— Autoload，名字：Research
# 「科技树 + 行政树 + 政策卡」的数据层（Esc 面板里的两页）。
#
# 设计要点（对齐《文明6》的观感，但砍到跟本作节奏匹配的最小集）：
#   · 两条树各自攒点数：**玩家分配劳动力**（自己 + 伙伴）去研究，
#     每人每天产 POINTS_PER_HEAD 点，换日结算（跟农田的「每天派活」同一套节奏）。
#   · 科技树 —— 效果是**给物品加增益**：
#       作物/食物/全部卖出价加成、砍树多掉木头、制作多产一份、研究速度加成。
#   · 行政树 —— 解锁**政策卡**，还额外给**卡槽**；
#       卡槽是独立的（基础 1 个 + 行政树里赚）。挂卡不是立刻生效：
#       先进**准备槽**「为下一周的政策作准备」，到下周初（第 1/8/15/22 天早上）
#       才按顺序挪进生效槽开始起作用（用户要求：隔周生效）。
#   · 一切增益都从这里取，别的地方（商店卖价/买价、砍树、制作、伙伴属性）
#     只调用本文件的 getter，保证「一个地方改，全局一致」。
#
# 存档：整个 to_dict() 塞进 savegame 的 "research" 节。
extends Node

signal changed            # 点数/已研究/卡片/劳动力分配 变了（两页 UI 刷新）

const CardsData := preload("res://scene/cards_data.gd")   # 出征编组: 解锁牌表/携带上限在这

# —— 每份劳动力每天产多少研究点 ——（跟 Slaves.CELLS_PER_SLAVE 同量级，
#    这样「派人去研究」和「派人去种地」是两个等价的取舍）
const POINTS_PER_HEAD := 8
const CARDS_BASE_SLOTS := 1          # 不点任何行政就有 1 个卡槽
const WEEK_DAYS := 7                 # 一周 7 天：政策在每周第 1 天早上换班

# ---------------- 科技树 ----------------
# tier 只影响 UI 分组；req 是前置科技（都研究完才能点）。
# eff 里的键：
#   crop / food / all —— 对应类别物品的卖出价加成（同类别相加、再加到 1.0 上）
#   wood   —— 砍树额外掉几根木头
#   craft  —— 制作时额外多产几份
#   research —— 研究速度加成（乘区）
#   water  —— 水壶容量 +N（Inventory.water_max()）
#   irrigate —— 浇水时顺带浇相邻耕地
#   chop   —— 一斧头削掉几点树的耐久
const TECHS := {
	"fert": {
		"name": "轮作法", "tier": 1, "cost": 30, "req": [],
		"desc": "作物卖出价 +15%", "eff": {"crop": 0.15},
	},
	"axe": {
		"name": "锻铁斧", "tier": 1, "cost": 30, "req": [],
		"desc": "砍树多掉 1 根木头", "eff": {"wood": 1},
	},
	"mill": {
		"name": "磨坊", "tier": 1, "cost": 30, "req": [],
		"desc": "制作食物多产 1 份", "eff": {"craft": 1},
	},
	"well": {
		"name": "水轮", "tier": 1, "cost": 30, "req": [],
		"desc": "水壶容量 +5", "eff": {"water": 5},
	},
	"plow": {
		"name": "犁耕法", "tier": 2, "cost": 70, "req": ["fert"],
		"desc": "作物卖出价再 +20%", "eff": {"crop": 0.20},
	},
	"cellar": {
		"name": "谷仓", "tier": 2, "cost": 70, "req": ["mill"],
		"desc": "食物卖出价 +25%", "eff": {"food": 0.25},
	},
	"sawmill": {
		"name": "木匠行会", "tier": 2, "cost": 70, "req": ["axe"],
		"desc": "砍树再多掉 2 根木头", "eff": {"wood": 2},
	},
	"ditch": {
		"name": "引水渠", "tier": 2, "cost": 70, "req": ["well"],
		"desc": "浇一格时顺带浇相邻耕地", "eff": {"irrigate": 1},
	},
	"steel": {
		"name": "精钢斧", "tier": 2, "cost": 70, "req": ["axe"],
		"desc": "砍树一斧顶两斧", "eff": {"chop": 1},
	},
	"steam": {
		"name": "齿轮机关", "tier": 3, "cost": 140, "req": ["plow", "sawmill"],
		"desc": "所有物品卖出价 +25%", "eff": {"all": 0.25},
	},
	"ledger": {
		"name": "钱庄", "tier": 3, "cost": 140, "req": ["cellar"],
		"desc": "所有物品卖出价 +15%", "eff": {"all": 0.15},
	},
	"telegraph": {
		"name": "飞鸽传书", "tier": 3, "cost": 140, "req": ["ledger"],
		"desc": "研究速度 +50%", "eff": {"research": 0.5},
	},
}

# ---------------- 行政树 ----------------
# cards = 研究完解锁哪些政策卡（卡 id 见 CARDS）；slots = 额外赚到的卡槽数。
const ADMINS := {
	"admin_hu": {
		"name": "编户", "tier": 1, "cost": 40, "req": [], "slots": 1,
		"cards": ["corvee"], "desc": "解锁 劳役卡 + 卡槽 1",
	},
	"admin_trade": {
		"name": "榷场", "tier": 2, "cost": 80, "req": ["admin_hu"], "slots": 0,
		"cards": ["market"], "desc": "解锁 互市卡",
	},
	"admin_militia": {
		"name": "乡勇", "tier": 2, "cost": 80, "req": ["admin_hu"], "slots": 1,
		"cards": ["armory", "baojia"], "desc": "解锁 甲胄/同袍卡 + 卡槽 1",
	},
	"admin_road": {
		"name": "驿道", "tier": 3, "cost": 150, "req": ["admin_trade"], "slots": 1,
		"cards": ["caravan"], "desc": "解锁 驼队卡 + 卡槽 1",
	},
	"admin_navy": {
		"name": "楼船", "tier": 3, "cost": 150, "req": ["admin_militia"], "slots": 1,
		"cards": ["ironboat"], "desc": "解锁 艨艟卡 + 卡槽 1",
	},
	"admin_drill": {
		"name": "演武场", "tier": 3, "cost": 150, "req": ["admin_militia"], "slots": 0,
		"cards": ["drill", "scout"], "desc": "解锁 校场/游哨卡",
	},
	"admin_cabinet": {
		"name": "枢密院", "tier": 4, "cost": 260, "req": ["admin_militia", "admin_road"],
		"slots": 1, "cards": ["mobilize"], "desc": "解锁 征发卡 + 卡槽 1",
	},
}

# ---------------- 政策卡 ----------------
# by = 哪条行政科技解锁它（UI 里显示来源）。
const CARDS := {
	"corvee":   {"name": "劳役",   "desc": "每个同伴劳动力 +2",      "by": "admin_hu"},
	"market":   {"name": "互市",   "desc": "卖出价 +12%",            "by": "admin_trade"},
	"armory":   {"name": "甲胄",   "desc": "伙伴攻击 +2",            "by": "admin_militia"},
	"baojia":   {"name": "同袍",   "desc": "伙伴血上限 +10",         "by": "admin_militia"},
	"caravan":  {"name": "驼队",   "desc": "买入价 -15%",            "by": "admin_road"},
	"ironboat": {"name": "艨艟",   "desc": "出海打赢金币 +50%",      "by": "admin_navy"},
	"drill":    {"name": "校场",   "desc": "伙伴攻击 +1",            "by": "admin_drill"},
	"scout":    {"name": "游哨",   "desc": "伙伴战场移动 +25%",      "by": "admin_drill"},
	"mobilize": {"name": "征发",   "desc": "劳动力 +2 且伙伴攻击 +1", "by": "admin_cabinet"},
}

# ---------------- 卡面图标 ----------------
# id -> 贴图。值两种写法：
#   "res://..."                       整图直接用
#   ["res://...", x, y, w, h]         从图集切一格（AtlasTexture）
# 没配图标的 id icon_for() 返回 null，
# UI 侧退回无图标排版 —— 面板不能因为少张图就崩。
# ❗像素画放大必须 TEXTURE_FILTER_NEAREST（UI 侧统一处理）。
const ICONS := {
	# —— 科技树 ——
	"fert":     "res://resources/Sunnyside_World_Assets/UI/plant.png",
	"axe":      ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Axe.png", 0, 0, 16, 16],
	"mill":     "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/Food Icons/Flour.png",
	"well":     "res://resources/Sunnyside_World_Assets/UI/water.png",
	"plow":     ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Hoe.png", 0, 0, 16, 16],
	"cellar":   "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/Food Icons/Cheese.png",
	"sawmill":  ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Wood.png", 0, 0, 16, 16],
	"ditch":    "res://resources/Sunnyside_World_Assets/UI/shovel.png",
	"steel":    ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/3. Iron/Axe.png", 0, 0, 16, 16],
	"steam":    "res://resources/Sunnyside_World_Assets/UI/hammer.png",
	"ledger":   ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Books.png", 0, 0, 16, 16],
	"telegraph": "res://resources/Sunnyside_World_Assets/UI/expression_chat.png",
	# —— 行政树 ——
	"admin_hu":     ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Books.png", 16, 0, 16, 16],
	"admin_trade":  "res://resources/Sunnyside_World_Assets/UI/basket.png",
	"admin_militia": ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Sword.png", 0, 0, 16, 16],
	"admin_road":   "res://resources/Sunnyside_World_Assets/UI/itemdisc_01.png",
	"admin_navy":   "res://resources/texture/boat_icon.png",
	"admin_drill":  ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Bow.png", 0, 0, 16, 16],
	"admin_cabinet": ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Books.png", 64, 0, 16, 16],
	# —— 政策卡 ——
	"corvee":   ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Pickaxe.png", 0, 0, 16, 16],
	"market":   "res://resources/Sunnyside_World_Assets/UI/basket.png",
	"armory":   ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Sword.png", 0, 0, 16, 16],
	"baojia":   ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Helmet.png", 0, 0, 16, 16],
	"caravan":  "res://resources/Sunnyside_World_Assets/UI/itemdisc_01.png",
	"ironboat": "res://resources/texture/boat_icon.png",
	"drill":    ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Bow.png", 0, 0, 16, 16],
	"scout":    "res://resources/Sunnyside_World_Assets/UI/search.png",
	"mobilize": ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Arrow.png", 0, 0, 16, 16],
}

# 取某条科技/行政/政策卡的卡面图标；没配或文件缺失返回 null。
func icon_for(id: String) -> Texture2D:
	if not ICONS.has(id):
		return null
	var v: Variant = ICONS[id]
	var path := ""
	var region := Rect2()
	if v is String:
		path = String(v)
	elif v is Array and (v as Array).size() >= 5:
		var arr: Array = v
		path = String(arr[0])
		region = Rect2(int(arr[1]), int(arr[2]), int(arr[3]), int(arr[4]))
	if path == "" or not ResourceLoader.exists(path):
		return null
	if region.size == Vector2.ZERO:
		return load(path) as Texture2D
	var at := AtlasTexture.new()
	at.atlas = load(path) as Texture2D
	at.region = region
	return at

# ---------------- 状态 ----------------
var tech_points := 0
var admin_points := 0
var techs := {}                  # 科技id -> true（已研究）
var admins := {}                 # 行政id -> true（已研究）
var slots := []                  # 生效卡槽：每个槽存卡 id 或 ""（空槽），长度 = 卡槽数
var pending := []                # 准备槽：挂上还没生效的卡 id（为下一周的政策作准备）
var deck: Array = []             # 出征编组：编进战斗卡组的解锁牌 id（同名牌可重复, 受携带上限管）
var last_promoted: Array = []    # 今早刚生效的卡名（给晨间播报用，一天内有效）
# 伙伴那边派了谁去研究，唯一真相源在 Slaves（research_tech / research_admin），
# 这里不再存一份 —— 少一份状态就少一类「两边不一致」的 bug。
# e30i: 主角自己不再下场研究 —— player_tech / player_admin 字段随之废弃。

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)
	_normalize_slots()
	_normalize_deck()

# ---------------- 劳动力 ----------------
# 一份劳动力 = 一个被派来研究的伙伴（e30i: 主角自己不再下场）。
# 伙伴的序号列表由 Slaves 那边勾选，这里只负责计数和产点数。
# 人手按劳动树「学徒-书生-学士」加权：学者级的伙伴一人顶好几个人手。
func tech_heads() -> float:
	var heads := 0.0
	for i in Slaves.research_tech:
		heads += 1.0 + float(Slaves.study_bonus(Slaves.slave_at(i)))
	return heads

func admin_heads() -> float:
	var heads := 0.0
	for i in Slaves.research_admin:
		heads += 1.0 + float(Slaves.study_bonus(Slaves.slave_at(i)))
	return heads

# 每人每天产的点数（科技树点出「飞鸽传书」后科技侧加速 50%）
func points_per_head(tree: String) -> float:
	var p := float(POINTS_PER_HEAD)
	if tree == "tech" and _has(techs, "telegraph"):
		p *= 1.0 + float(TECHS["telegraph"]["eff"]["research"])
	return p

# 这条树每天会涨多少点（UI 显示「每天 +N」）
func day_gain(tree: String) -> int:
	var heads := tech_heads() if tree == "tech" else admin_heads()
	var pts := float(heads) * points_per_head(tree)
	# e13i 师爷分支: 主角管理技能 5 级选「师爷」后, 每级研究点 +8% (e28f 比主干质变)
	if Legion.branch_of("manage") == "b":
		pts *= 1.0 + 0.08 * Legion.branch_lv("manage")
	# 婚恋 perk（雪莱）: 科技点 +10%
	pts *= Marriage.perk_mult("tech")
	return int(round(pts))

# ---------------- 夜间结算 / 播报 ----------------
# ❗一晚只结算一次：睡觉时 game.gd 先调一次 settle_night()（好在结算面板上播报「今晚进展」），
#   紧接着 TimeManager.advance_day 发出的 new_day 就不该再加一遍。
var _night_settled := false

# 把今晚该涨的点数入账，并返回一份给结算面板播报用的说明。
# 返回 {} = 今晚已经结算过了（重复调用不会重复加）。
func settle_night() -> Dictionary:
	if _night_settled:
		return {}
	var gt := day_gain("tech")
	var ga := day_gain("admin")
	tech_points += gt
	admin_points += ga
	_night_settled = true
	changed.emit()
	return {
		"tech_gain": gt,
		"admin_gain": ga,
		"tech_heads": tech_heads(),
		"admin_heads": admin_heads(),
		"tech_total": tech_points,
		"admin_total": admin_points,
	}

func _on_new_day(day: int) -> void:
	# 周初（第 1/8/15/22 天）：准备槽里的卡正式上任 —— 这步不管账结没结都要做
	if _is_week_start(day):
		_promote_pending()
	if _night_settled:
		_night_settled = false      # 睡觉流程已经结过账，换日不再重复加
		return
	settle_night()

# 今天是不是一周的第一天（day 从 1 起算：1/8/15/22/...）
func _is_week_start(day: int) -> bool:
	return (day - 1) % WEEK_DAYS == 0

# ---------------- 隔周生效 ----------------
# 周初换班：把准备槽里的卡按挂上顺序挪进生效槽。
# 生效槽空位不够的卡继续留在准备槽，下周接着上。返回今天生效了几张。
func _promote_pending() -> int:
	last_promoted = []
	var still: Array = []
	for id in pending:
		var cid := String(id)
		if cid == "" or not card_unlocked(cid):
			continue                # 来源行政没了/存档带了脏数据：直接丢弃
		if free_slots() > 0:
			_slot_into_free(cid)
			last_promoted.append(String(CARDS[cid]["name"]))
		else:
			still.append(cid)
	pending = still
	if not last_promoted.is_empty():
		changed.emit()
	return last_promoted.size()

# 今晚结算后马上能研究的项目名（播报用），最多 limit 个。
func ready_list(tree: String, limit := 3) -> Array:
	var out: Array = []
	if tree == "tech":
		for id in TECHS.keys():
			if out.size() >= limit:
				break
			var ti := String(id)
			if not has_tech(ti) and tech_ready(ti) and tech_points >= int(TECHS[ti]["cost"]):
				out.append(String(TECHS[ti]["name"]))
	else:
		for id in ADMINS.keys():
			if out.size() >= limit:
				break
			var ai := String(id)
			if not has_admin(ai) and admin_ready(ai) and admin_points >= int(ADMINS[ai]["cost"]):
				out.append(String(ADMINS[ai]["name"]))
	return out

# e30i: 主角不再下场钻研 —— 派活面板里也没有「自己」这一行了，这里恒拒绝。
func toggle_self(_tree: String) -> bool:
	return false

func self_labor(_tree: String) -> bool:
	return false

# ---------------- 研究 ----------------
func _has(d: Dictionary, id: String) -> bool:
	return bool(d.get(id, false))

func has_tech(id: String) -> bool:
	return _has(techs, id)

func has_admin(id: String) -> bool:
	return _has(admins, id)

func tech_ready(id: String) -> bool:
	if not TECHS.has(id) or has_tech(id):
		return false
	for r in TECHS[id]["req"]:
		if not has_tech(String(r)):
			return false
	return true

func admin_ready(id: String) -> bool:
	if not ADMINS.has(id) or has_admin(id):
		return false
	for r in ADMINS[id]["req"]:
		if not has_admin(String(r)):
			return false
	return true

func can_research_tech(id: String) -> bool:
	return tech_ready(id) and tech_points >= int(TECHS[id]["cost"])

func can_research_admin(id: String) -> bool:
	return admin_ready(id) and admin_points >= int(ADMINS[id]["cost"])

func research_tech(id: String) -> bool:
	if not can_research_tech(id):
		return false
	tech_points -= int(TECHS[id]["cost"])
	techs[id] = true
	Legion.gain_exp(3)          # e13h: 完成一项研究也长主角经验
	changed.emit()
	Quests.complete("tech_first")   # e32: 第一项科技
	return true

func research_admin(id: String) -> bool:
	if not can_research_admin(id):
		return false
	admin_points -= int(ADMINS[id]["cost"])
	admins[id] = true
	_normalize_slots()          # 新赚的卡槽要补进 slots 数组
	# e44: 行政研究不再加伙伴上限（上限改由「同伴小屋」决定, 见 Structures.place）
	Legion.gain_exp(3)          # e13h: 完成一项研究也长主角经验
	changed.emit()
	return true

# ---------------- 政策卡槽 ----------------
func slot_count() -> int:
	var n := CARDS_BASE_SLOTS
	for id in ADMINS.keys():
		if has_admin(String(id)):
			n += int(ADMINS[id]["slots"])
	return n

# 把 slots 数组长度对齐到 slot_count()（多了裁掉、少了补空槽）
func _normalize_slots() -> void:
	var want := slot_count()
	while slots.size() < want:
		slots.append("")
	while slots.size() > want:
		slots.pop_back()         # 卡槽变少就裁掉末尾（卡本身还在，随时可重挂）
	# 清掉「来源行政树被拿掉的」和重复的卡
	var seen := {}
	for i in slots.size():
		var c := String(slots[i])
		if c == "" or not CARDS.has(c) or not card_unlocked(c) or seen.has(c):
			slots[i] = ""
		else:
			seen[c] = true
	# 准备槽同样清一遍：来源丢了/重复的/脏数据踢掉，容量别超过槽数
	var pseen := {}
	var keep: Array = []
	for id in pending:
		var cid := String(id)
		if cid == "" or not CARDS.has(cid) or not card_unlocked(cid) or pseen.has(cid):
			continue
		pseen[cid] = true
		keep.append(cid)
	pending = keep.slice(0, slot_count())

func card_unlocked(id: String) -> bool:
	if not CARDS.has(id):
		return false
	return has_admin(String(CARDS[id]["by"]))

func card_slotted(id: String) -> bool:
	return slots.has(id)

func free_slots() -> int:
	var n := 0
	for c in slots:
		if String(c) == "":
			n += 1
	return n

# 准备槽是否已满（容量跟生效槽数一致）
func pending_full() -> bool:
	return pending.size() >= slot_count()

# 挂卡（用户要求：隔周生效）—— 不再直接进生效槽，先进**准备槽**「为下一周的政策作准备」，
# 下周初（第 1/8/15/22 天早上）才挪进生效槽起作用（见 _promote_pending）。
# 准备槽容量跟槽数一致：凑不齐一套的政策没必要准备。
func slot_card(id: String) -> bool:
	if not card_unlocked(id) or card_slotted(id) or is_pending(id):
		return false
	if pending.size() >= slot_count():
		return false
	pending.append(id)
	changed.emit()
	return true

# 直接填进第一个空生效槽（只给每周换班 _promote_pending 用，别处别调）
func _slot_into_free(id: String) -> bool:
	if not card_unlocked(id) or card_slotted(id) or free_slots() <= 0:
		return false
	for i in slots.size():
		if String(slots[i]) == "":
			slots[i] = id
			return true
	return false

# 这张卡是否在准备槽里（挂上了但还没生效）
func is_pending(id: String) -> bool:
	return pending.has(id)

# 摘卡：生效槽和准备槽都清
func unslot_card(id: String) -> bool:
	var dirty := false
	for i in slots.size():
		if String(slots[i]) == id:
			slots[i] = ""
			dirty = true
	if pending.has(id):
		pending.erase(id)
		dirty = true
	if dirty:
		changed.emit()
	return dirty

func is_active(id: String) -> bool:
	return card_slotted(id)

# ---------------- 出征编组（解锁牌编进战斗卡组） ----------------
# 编组即时生效（战斗开打时 player_deck 现拉这份名单），不走「隔周生效」——
# 政策卡隔周是仪式感, 自己带什么牌上场是纯粹的个人偏好, 没必要等。
func deck_count(id: String) -> int:
	return deck.count(id)

func deck_add(id: String) -> bool:
	if not CardsData.deck_unlocked(id):
		return false
	if deck_count(id) >= CardsData.deck_max_of(id):
		return false
	deck.append(id)
	changed.emit()
	return true

func deck_del(id: String) -> bool:
	if not deck.has(id):
		return false
	deck.erase(id)               # 只撤第一张: 同名多张一次撤一张
	changed.emit()
	return true

# 脏编组清理：表里没有的 id / 条件已不满足的 / 超上限的, 全部踢掉
func _normalize_deck() -> void:
	var keep: Array = []
	var seen := {}
	for id in deck:
		var cid := String(id)
		if not CardsData.UNLOCK.has(cid) or not CardsData.deck_unlocked(cid):
			continue
		seen[cid] = int(seen.get(cid, 0)) + 1
		if int(seen[cid]) > CardsData.deck_max_of(cid):
			continue
		keep.append(cid)
	deck = keep

# 已解锁的卡 id 列表（按 CARDS 声明顺序，UI 直接遍历用）
func unlocked_cards() -> Array:
	var out: Array = []
	for id in CARDS.keys():
		if card_unlocked(String(id)):
			out.append(String(id))
	return out

# ---------------- 效果：卖出 / 买入 ----------------
# 卖出倍率：行商技能（主干封顶 5 级, 5 级后走分支）+ 掌柜分支 + 互市卡 + 科技
func sell_mult(item_type: String) -> float:
	var m := 1.0
	m += 0.08 * mini(Legion.skill_lv("trade"), Legion.SKILL_SPLIT)   # 行商主干: 卖价 +8%/级 (到 5)
	if Legion.branch_of("trade") == "a":
		m += 0.06 * Legion.branch_lv("trade")               # e13i 掌柜: 分支每级再 +6% (e28f 强化)
	if is_active("market"):
		m += 0.12
	if item_type == "作物":
		if has_tech("fert"):
			m += float(TECHS["fert"]["eff"]["crop"])
		if has_tech("plow"):
			m += float(TECHS["plow"]["eff"]["crop"])
		if Legion.branch_of("farm") == "b":
			m += 0.05 * Legion.branch_lv("farm")            # e14 粮长: 作物卖价再 +5%/级 (e28f)
	if item_type == "食物" and has_tech("cellar"):
		m += float(TECHS["cellar"]["eff"]["food"])
	if has_tech("steam"):
		m += float(TECHS["steam"]["eff"]["all"])
	if has_tech("ledger"):
		m += float(TECHS["ledger"]["eff"]["all"])
	return m

# 某件物品实际卖多少（商店/出货箱都用这个，别直接读 it.sell_price）
func sell_price_of(it: ItemData) -> int:
	if it == null:
		return 0
	if it.sell_price <= 0:
		return 0
	return int(round(float(it.sell_price) * sell_mult(it.type)))

# 买入倍率：行商技能 -5%/级（主干封顶 5）、豪商分支 -3%/级、驼队卡 -15%（有下限，别变成白送）
func buy_mult() -> float:
	var m := 1.0
	m -= 0.05 * mini(Legion.skill_lv("trade"), Legion.SKILL_SPLIT)
	if Legion.branch_of("trade") == "b":
		m -= 0.05 * Legion.branch_lv("trade")               # e13i 豪商: 分支每级再 -5% (e28f)
	if is_active("caravan"):
		m -= 0.15
	return maxf(0.40, m)

func buy_price_of(base: int) -> int:
	return maxi(1, int(round(float(base) * buy_mult())))

# ---------------- 效果：产出 / 属性 ----------------
# 砍树额外掉几根木头
func wood_bonus() -> int:
	var b := 0
	if has_tech("axe"):
		b += int(TECHS["axe"]["eff"]["wood"])
	if has_tech("sawmill"):
		b += int(TECHS["sawmill"]["eff"]["wood"])
	return b

# 制作额外多产几份
func craft_bonus() -> int:
	return int(TECHS["mill"]["eff"]["craft"]) if has_tech("mill") else 0

# 水壶容量加成（水轮）。Inventory.water_max() 会加到 WATER_MAX 上。
func water_bonus() -> int:
	return int(TECHS["well"]["eff"]["water"]) if has_tech("well") else 0

# 浇水时是否顺带浇相邻的耕地（引水渠）
func irrigate() -> bool:
	return has_tech("ditch")

# 一斧头削掉几点树的耐久（精钢斧 = 2，没研究 = 1）。
# 默认值就写 1，是「没研究科技时的基线」，Trees.hit 的 power 参数直接用这个。
func chop_power() -> int:
	return 1 + (int(TECHS["steel"]["eff"]["chop"]) if has_tech("steel") else 0)

# 每个同伴的劳动力加成（管理技能主干封顶 5 级 + 劳役/征发卡）
# Slaves.cells_per_slave() 会把它加到 CELLS_PER_SLAVE 上
func labor_bonus_per_head() -> int:
	var b := mini(int(Legion.skills.get("manage", 0)), Legion.SKILL_SPLIT)
	if is_active("corvee"):
		b += 2
	if is_active("mobilize"):
		b += 2
	return b

# 伙伴战斗加成（甲胄 / 校场 / 征发卡）
func ally_atk_bonus() -> int:
	var b := 0
	if is_active("armory"):
		b += 2
	if is_active("drill"):
		b += 1
	if is_active("mobilize"):
		b += 1
	return b

func ally_hp_bonus() -> int:
	return 10 if is_active("baojia") else 0

# 出海打仗的金币倍率（艨艟卡）：打赢一次多拿五成
func battle_coin_mult() -> float:
	return 1.0 + (0.5 if is_active("ironboat") else 0.0)

# 伙伴在战场上的移动倍率（游哨卡）—— 只在战役地图里用，岛上不受影响
func ally_speed_mult() -> float:
	return 1.0 + (0.25 if is_active("scout") else 0.0)

# ---------------- UI 用的一行摘要 ----------------
func tech_summary(id: String) -> String:
	if not TECHS.has(id):
		return ""
	var t: Dictionary = TECHS[id]
	if has_tech(id):
		return "已研究"
	for r in t["req"]:
		if not has_tech(String(r)):
			return "需要 %s" % String(TECHS[r]["name"])
	if tech_points < int(t["cost"]):
		return "点数 %d/%d" % [tech_points, int(t["cost"])]
	return "可研究"

func admin_summary(id: String) -> String:
	if not ADMINS.has(id):
		return ""
	var a: Dictionary = ADMINS[id]
	if has_admin(id):
		return "已研究"
	for r in a["req"]:
		if not has_admin(String(r)):
			return "需要 %s" % String(ADMINS[r]["name"])
	if admin_points < int(a["cost"]):
		return "点数 %d/%d" % [admin_points, int(a["cost"])]
	return "可研究"

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	# 只存 true 的键（省体积），读档时按表补 false
	var t: Array = []
	for id in TECHS.keys():
		if has_tech(String(id)):
			t.append(String(id))
	var a: Array = []
	for id in ADMINS.keys():
		if has_admin(String(id)):
			a.append(String(id))
	return {
		"tech_points": tech_points,
		"admin_points": admin_points,
		"techs": t,
		"admins": a,
		"slots": slots.duplicate(),
		"pending": pending.duplicate(),
		"deck": deck.duplicate(),
	}

func from_dict(d: Dictionary) -> void:
	tech_points = maxi(0, int(d.get("tech_points", 0)))
	admin_points = maxi(0, int(d.get("admin_points", 0)))
	techs = {}
	for id in d.get("techs", []):
		if TECHS.has(String(id)):
			techs[String(id)] = true
	admins = {}
	for id in d.get("admins", []):
		if ADMINS.has(String(id)):
			admins[String(id)] = true
	slots = []
	for c in d.get("slots", []):
		slots.append(String(c))
	pending = []
	for c in d.get("pending", []):
		pending.append(String(c))
	deck = []
	for c in d.get("deck", []):
		deck.append(String(c))
	_night_settled = false           # 刚读档，今晚还没结过账
	_normalize_slots()
	_normalize_deck()
	Slaves.refresh_cap()             # e44: 读档后按岛上小屋数同步伙伴上限
	changed.emit()

func reset() -> void:
	tech_points = 0
	admin_points = 0
	techs = {}
	admins = {}
	slots = []
	pending = []
	deck = []
	last_promoted = []
	_night_settled = false
	_normalize_slots()
	Slaves.refresh_cap()             # e44: 新档 -> 伙伴上限回基础值 (岛上还没小屋)
	changed.emit()
