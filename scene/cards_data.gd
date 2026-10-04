# scene/cards_data.gd —— KARDS 式卡牌战斗的数据层（纯静态, 无场景依赖）
#
# 战斗改成卡牌后的「牌从哪来、长什么样」全在这：
#   · 主角卡 —— 主角亲征的一张金卡（2 费守护, 攻血随历练微涨）: 队伍里永远有他
#   · 伙伴卡 —— 出征名单里每个伙伴一张, 职业即兵种:
#       费用 = 1 + 职业档位(新兵0/一线1/二线2/三线3)
#       攻   = 2 + 职业攻击(同 Slaves.class_atk) + 好感满 80 额外 +1
#       血   = 3 + 档位（甲胄折算）; 满阶职业出金卡
#       同伴比敌军同级兵硬一截 —— 他们是花钱花料养出来的, 该有排面
#       关键词: 骑兵系=低油(高级行动免费) / 弓手系=后排可射(支援线也参战)
#               步兵系=守护(左右相邻友军免受攻击伤害)
#   · 法术卡 —— 每研究一个科技/行政解锁一张（键 = m_<id>, 越后期越强力）
#       卡池在 ESC 战斗页编组, 编入卡组才随军出征
#   · 敌方令牌 —— 敌方「增援」法术召出的 1/1 民夫（非卡组牌, 只进战场）
#   · 行动费 act —— 部队「前进 / 进攻」要付的点数: 卡费 1-2 的兵 1 点, 3 费往上 2 点
#       (骑兵低油: 普通骑兵 1 点, 高级骑兵行动免费)
#   · 敌方卡组 —— 按 party/nations 分四流: 骑兵国快攻 / 山贼哥布林人海 /
#       海寇魔物直伤 / 国家正规军混编; 大营血随敌军规模和主角等级水涨船高
#
# 数值表尽量平（费用 1..5, 攻血 1..5）, 谁强谁弱先跑起来再调。
extends RefCounted

const CAMP_HP := 15            # 双方大营血
const HAND_CAP := 8            # 手牌上限（多了烧掉）
const COST_CAP := 10           # 费用上限

# ---------------- 兵种档位（同 slaves.gd CLASSES 的转职深度） ----------------
const TIER := {
	"新兵": 0,
	"刀客": 1, "弓手": 1, "骑兵": 1,
	"剑士": 2, "神射手": 2, "枪骑兵": 2,
	"咏剑士": 3, "狙击手": 3, "重骑兵": 3,
}
const CAVALRY_CLS := ["骑兵", "枪骑兵", "重骑兵"]     # 低油: 普通骑兵行动 1 点, 高级(费>=3)免费
const RANGED_CLS := ["弓手", "神射手", "狙击手"]      # 后排可射: 支援线也能进攻
const GUARD_CLS := ["新兵", "刀客", "剑士", "咏剑士"]  # 守护: 左右相邻友军免受攻击伤害

# 行动费: 部队前进 / 进攻各要付的点数（便宜兵轻便, 精兵每次挪动都贵）
# 骑兵低油: 普通骑兵 1 点, 高级骑兵（卡费 >= 3）行动免费
static func act_cost(card_cost: int, kw := "") -> int:
	if kw == "cav":
		return 0 if card_cost >= 3 else 1
	return 1 if card_cost <= 2 else 2

# ---------------- 法术卡（每研究一个科技/行政解锁一张, 越后期越强力） ----------------
# 键 = "m_" + 科技/行政 id（Research.TECHS / Research.ADMINS）, 研究完成即进卡池
#   n   = 数值参数: buff/hp_all/atk_all 的加成, coin2 的费用, draw2 的抽牌数, heal 的回血
#   dmg = 直伤数值: unit_dmg / camp_dmg（同敌方法术的 dmg 约定）
const SPELLS := {
	# —— 科技线（12 张, tier1 单点小利 → tier3 战略级） ——
	"m_fert":      {"name": "沃土",     "cost": 1, "spell": "buff",     "target": "ally", "n": 1, "desc": "一个友军 +1攻 +1血"},
	"m_axe":       {"name": "飞斧",     "cost": 1, "spell": "unit_dmg", "target": "foe", "dmg": 2, "desc": "一个敌军 -2"},
	"m_mill":      {"name": "磨坊号子", "cost": 1, "spell": "coin2",    "n": 1, "desc": "本回合费用 +1"},
	"m_well":      {"name": "甘泉",     "cost": 1, "spell": "heal",     "n": 3, "desc": "大营回 3 血"},
	"m_plow":      {"name": "深耕",     "cost": 2, "spell": "buff",     "target": "ally", "n": 2, "desc": "一个友军 +2攻 +2血"},
	"m_cellar":    {"name": "屯粮",     "cost": 2, "spell": "hp_all",   "n": 1, "desc": "全体友军 +1血"},
	"m_sawmill":   {"name": "征召木匠", "cost": 2, "spell": "summon2",  "desc": "召出两个 1/1 民夫"},
	"m_ditch":     {"name": "引水",     "cost": 2, "spell": "heal",     "n": 5, "desc": "大营回 5 血"},
	"m_steel":     {"name": "淬火",     "cost": 2, "spell": "unit_dmg", "target": "foe", "dmg": 4, "desc": "一个敌军 -4"},
	"m_steam":     {"name": "蒸汽重锤", "cost": 4, "spell": "camp_dmg", "dmg": 6, "desc": "敌方大营 -6"},
	"m_ledger":    {"name": "钱庄票号", "cost": 2, "spell": "coin2",    "n": 3, "desc": "本回合费用 +3"},
	"m_telegraph": {"name": "飞鸽传书", "cost": 3, "spell": "draw2",    "n": 3, "desc": "抽 3 张牌"},
	# —— 行政线（7 张, 从保甲征召到枢密院的战时动员） ——
	"m_admin_hu":      {"name": "编户齐民", "cost": 1, "spell": "summon2", "desc": "召出两个 1/1 民夫"},
	"m_admin_trade":   {"name": "互市获利", "cost": 1, "spell": "coin2",   "n": 2, "desc": "本回合费用 +2"},
	"m_admin_militia": {"name": "乡勇出击", "cost": 2, "spell": "atk_all", "n": 1, "desc": "全体友军 +1攻"},
	"m_admin_road":    {"name": "驿马传令", "cost": 2, "spell": "draw2",   "n": 2, "desc": "抽 2 张牌"},
	"m_admin_navy":    {"name": "火攻",     "cost": 3, "spell": "camp_dmg", "dmg": 4, "desc": "敌方大营 -4"},
	"m_admin_drill":   {"name": "严明操练", "cost": 3, "spell": "buff",    "target": "ally", "n": 3, "desc": "一个友军 +3攻 +3血"},
	"m_admin_cabinet": {"name": "枢密令",   "cost": 5, "spell": "atk_all", "n": 2, "desc": "全体友军 +2攻"},
}

# 出征卡组上限: 主角卡 + 基础牌固定在场之外, 玩家最多再编入多少张
# （同伴卡 / 法术卡各算 1 张, 解锁部队牌按 DECK_MAX 的同名上限算张数）
const DECK_CAP := 12

# ---------------- 出征卡组：基础牌（人人在手, 不靠解锁） ----------------
# 全 1 费 —— 首回合 2 费时手里保证有牌可打（原来开局摸一手 2 费民兵,
# 点出去全是「费用不足」, 玩家像被锁了手）。cls 对齐职业立绘, 卡面直接复用美术。
const BASICS := {
	"spike":  {"name": "长枪农兵", "cost": 1, "atk": 2, "hp": 1, "kw": "",      "cls": "民兵"},
	"wicker": {"name": "藤牌手",   "cost": 1, "atk": 0, "hp": 3, "kw": "guard", "cls": "刀客"},
	"runner": {"name": "快腿斥候", "cost": 1, "atk": 1, "hp": 1, "kw": "cav",   "cls": "骑兵"},
}
const BASIC_COPIES := 3        # 每张基础牌固定带 3 张（开局 9 张 + 主角, 没伙伴也有十来张）

# ---------------- 出征卡组：解锁牌（研究行政/科技后在「出征编组」里编入） ----------------
#   req    = 解锁条件（行政树 ADMINS 或科技树 TECHS 的 id）
#   rarity = strong 强力卡（同名牌最多 4 张）/ elite 精英卡（最多 2 张）
#   cls    = 卡面立绘走的职业名（复用现有 u_my_<职业> 美术, 不新画图）
const DECK_MAX := {"strong": 4, "elite": 2}
const UNLOCK := {
	"u_axeman":   {"name": "持斧客",   "cost": 2, "atk": 3, "hp": 1, "kw": "",       "cls": "刀客",  "rarity": "strong", "req": "axe"},
	"u_levy":     {"name": "持械民壮", "cost": 2, "atk": 2, "hp": 2, "kw": "",       "cls": "民兵",  "rarity": "strong", "req": "admin_hu"},
	"u_spear":    {"name": "长矛手",   "cost": 2, "atk": 2, "hp": 3, "kw": "guard",  "cls": "刀客",  "rarity": "strong", "req": "admin_militia"},
	"u_merc":     {"name": "佣剑客",   "cost": 3, "atk": 3, "hp": 3, "kw": "",       "cls": "剑士",  "rarity": "strong", "req": "admin_trade"},
	"u_archer":   {"name": "游哨弓手", "cost": 2, "atk": 2, "hp": 2, "kw": "ranged", "cls": "弓手",  "rarity": "strong", "req": "admin_drill"},
	"u_outrider": {"name": "驿骑",     "cost": 3, "atk": 3, "hp": 2, "kw": "cav",    "cls": "骑兵",  "rarity": "strong", "req": "admin_road"},
	"u_marine":   {"name": "艨艟水手", "cost": 3, "atk": 2, "hp": 4, "kw": "guard",  "cls": "刀客",  "rarity": "strong", "req": "admin_navy"},
	"u_ballista": {"name": "床弩车",   "cost": 4, "atk": 3, "hp": 4, "kw": "ranged", "cls": "神射手", "rarity": "elite",  "req": "steam"},
	"u_marksman": {"name": "神机弩手", "cost": 4, "atk": 4, "hp": 3, "kw": "ranged", "cls": "神射手", "rarity": "elite",  "req": "admin_cabinet"},
	"u_knight":   {"name": "甲骑",     "cost": 4, "atk": 4, "hp": 4, "kw": "cav",    "cls": "重骑兵", "rarity": "elite",  "req": "admin_cabinet"},
}

# ---------------- 敌方卡组素材 ----------------
# 单位模板: [名字, 费用, 攻, 血, 关键词]; 法术见 FOE_SPELLS
# 数值红线: 属性点(atk+hp) ≈ 2×费 - 1, 关键词(cav低油/guard守护/ranged射程)再值 +0.5~1;
# 全池卡面落在 [2×费-2, 2×费+2] 区间内 —— 爆点卡按此修正 (e2 数值平衡)
const FOE_UNITS := {
	"rush":  [["铁骑", 1, 2, 1, "cav"], ["轻骑", 2, 3, 1, "cav"], ["重骑", 3, 3, 3, "cav"]],
	"swarm": [["民夫", 1, 1, 2, ""], ["山贼", 1, 1, 3, ""], ["悍匪", 2, 2, 2, ""], ["匪首", 3, 3, 3, ""]],
	"burn":  [["海寇", 2, 2, 2, ""], ["浪人", 3, 3, 2, ""], ["刀魁", 4, 4, 3, ""]],
	"army":  [["刀客", 2, 2, 2, "guard"], ["弓手", 2, 2, 2, "ranged"], ["枪骑兵", 3, 2, 3, "cav"], ["重装", 4, 4, 4, ""]],
}
const FOE_SPELLS := {
	# dmg = 直伤数值单一事实来源 (执行端读它; 每费伤害红线 ≤ 2)
	"fire":      {"name": "火油罐", "cost": 2, "spell": "camp_dmg", "desc": "敌方大营 -3", "dmg": 3},
	"axe":       {"name": "飞斧", "cost": 1, "spell": "unit_dmg", "desc": "一个敌军 -2", "target": "foe", "dmg": 2},
	"reinforce": {"name": "增援", "cost": 2, "spell": "summon2", "desc": "召出两个 1/1 民夫"},
	"horns":     {"name": "战号", "cost": 2, "spell": "atk_all", "desc": "全体友军 +1攻"},
	"rocks":     {"name": "滚木礌石", "cost": 1, "spell": "camp_dmg", "desc": "敌方大营 -2", "dmg": 2},
}
# 各流派的编队: [模板名, 张数]（单位来自 FOE_UNITS[流派], 法术来自 FOE_SPELLS）
const FOE_LISTS := {
	"rush":  [["铁骑", 8], ["轻骑", 6], ["重骑", 6]],
	"swarm": [["民夫", 8], ["山贼", 4], ["悍匪", 4], ["匪首", 2], ["reinforce", 2]],
	# burn 法术占比压到 40% (fire 5->4), 海寇 4->5 补足 20 张 (护住开局 3 抽后 17 的牌库断言)
	"burn":  [["海寇", 5], ["浪人", 4], ["刀魁", 3], ["fire", 4], ["axe", 4]],
	"army":  [["刀客", 6], ["弓手", 4], ["枪骑兵", 4], ["重装", 4], ["horns", 2]],
}

# ---------------- 玩家卡组 ----------------
# 编成: 主角一张 + 基础牌各 3 固定在场; 其余按 ESC 战斗页编组的卡组（Research.deck）来:
#   p_<序号> 同伴卡 / m_<科技或行政id> 法术卡 / u_<模板id> 解锁部队牌
# 上限 DECK_CAP（编组时把关）, 不再拿民兵补位 —— 牌库就是这支队伍。
# 固定种子洗牌（selftest 可复现）
static func player_deck(seed_val: int) -> Array:
	var deck: Array = []
	deck.append(hero_card())              # 主角亲征: 永远在卡组里
	for id_v in Research.deck:            # 编组卡组: 同伴 / 法术 / 解锁牌
		var id := String(id_v)
		if id.begins_with("p_"):
			var idx := int(id.substr(2))
			if Slaves.slave_at(idx).is_empty():
				continue
			deck.append(partner_card(idx))
		elif id.begins_with("m_"):
			if SPELLS.has(id):
				deck.append(spell_card_of(id))
		elif UNLOCK.has(id):
			if deck_unlocked(id):
				deck.append(unlock_card(id))
	for key in BASICS.keys():
		for i in BASIC_COPIES:
			deck.append(basic_card(String(key)))
	return shuffled(deck, seed_val)

# 解锁牌是否已可编入（req 先查行政树, 不在行政树就去科技树找）
static func deck_unlocked(id: String) -> bool:
	if not UNLOCK.has(id):
		return false
	var req := String(UNLOCK[id]["req"])
	if Research.ADMINS.has(req):
		return Research.has_admin(req)
	return Research.has_tech(req)

# 同名牌携带上限: 强力卡 4 张 / 精英卡 2 张
static func deck_max_of(id: String) -> int:
	return int(DECK_MAX.get(String(UNLOCK.get(id, {}).get("rarity", "strong")), 1))

# 编组条目是否可用: p_ 伙伴还在队里 / m_ 对应科技或行政已研究 / u_ 解锁牌查 req
static func deck_entry_unlocked(id: String) -> bool:
	var s := String(id)
	if s.begins_with("p_"):
		return not Slaves.slave_at(int(s.substr(2))).is_empty()
	if s.begins_with("m_"):
		var rid := s.substr(2)
		return Research.has_tech(rid) or Research.has_admin(rid)
	return deck_unlocked(s)

# 编组条目的同名牌上限: p_/m_ 各 1 张, u_ 按稀有度（强力 4 / 精英 2）
static func deck_entry_max(id: String) -> int:
	if String(id).begins_with("u_"):
		return deck_max_of(String(id))
	return 1

# 伙伴卡：职业即兵种, 数值由档位/职业/好感推导
static func partner_card(idx: int) -> Dictionary:
	var s: Dictionary = Slaves.slave_at(idx)
	var cls := String(s.get("troop", "新兵"))
	var tier := int(TIER.get(cls, 0))
	var kw := ""
	if cls in CAVALRY_CLS:
		kw = "cav"
	elif cls in RANGED_CLS:
		kw = "ranged"
	elif cls in GUARD_CLS:
		kw = "guard"
	var aff := int(s.get("affection", 0))
	return {
		"key": "p_%d" % idx, "name": String(s.get("name", "伙伴")),
		"type": "unit", "cls": cls,
		"cost": 1 + tier,
		"act": act_cost(1 + tier, kw),
		"atk": 2 + Slaves.class_atk(cls) + (1 if aff >= 80 else 0),
		"hp": 3 + tier,
		"kw": kw, "gold": tier >= 3, "src": idx,
	}

# 主角卡：金卡 2 费守护, 攻血随历练（Legion.level）微涨 —— 统帅亲征, 坐镇一线
static func hero_card() -> Dictionary:
	var lv := Legion.level
	var c := unit_card("主角", 2, 2 + clampi((lv - 1) / 6, 0, 2),
		4 + clampi((lv - 1) / 8, 0, 2), "guard", "hero")
	c["gold"] = true
	return c

# 敌方「增援」法术召出的令牌：1/1 民夫（跟法术描述一致, 复用民兵立绘）
static func summon_card() -> Dictionary:
	var c := unit_card("民夫", 1, 1, 1, "", "token")
	c["cls"] = "民兵"
	return c

# 基础牌 / 解锁牌: cls 用职业名对齐立绘（unit_card 默认 cls=名字, 这里手动覆盖）
static func basic_card(key: String) -> Dictionary:
	var t: Dictionary = BASICS[key]
	var c := unit_card(String(t["name"]), int(t["cost"]), int(t["atk"]), int(t["hp"]), String(t["kw"]), key)
	c["cls"] = String(t["cls"])
	return c

static func unlock_card(id: String) -> Dictionary:
	var t: Dictionary = UNLOCK[id]
	var c := unit_card(String(t["name"]), int(t["cost"]), int(t["atk"]), int(t["hp"]), String(t["kw"]), id)
	c["cls"] = String(t["cls"])
	return c

# 法术卡: 从 SPELLS 表造牌, n / dmg 数值一并带进卡字典（执行端按它结算）
static func spell_card_of(id: String) -> Dictionary:
	var t: Dictionary = SPELLS[id]
	var c := spell_card(String(t["name"]), int(t["cost"]), String(t["spell"]),
		String(t.get("target", "")), String(t["desc"]), id)
	if t.has("n"):
		c["n"] = int(t["n"])
	if t.has("dmg"):
		c["dmg"] = int(t["dmg"])
	return c

# 敌方法术牌（键 = FOE_SPELLS 的 id）
static func foe_spell_card(id: String) -> Dictionary:
	var t: Dictionary = FOE_SPELLS[id]
	var c := spell_card(String(t["name"]), int(t["cost"]), String(t["spell"]),
		String(t.get("target", "")), String(t["desc"]), id)
	if t.has("dmg"):
		c["dmg"] = int(t["dmg"])
	return c

# 法术牌公共骨架（玩家支援卡 / 敌方法术共用）
static func spell_card(cname: String, cost: int, sp: String, target: String, desc: String, key: String) -> Dictionary:
	return {
		"key": key, "name": cname, "type": "spell", "cls": key,
		"cost": cost, "atk": 0, "hp": 0, "kw": "", "gold": false,
		"src": -1, "spell": sp, "target": target, "desc": desc,
	}

# 通用单位卡模板（民兵/敌方单位都用）
static func unit_card(cname: String, cost: int, atk: int, hp: int, kw: String, key := "") -> Dictionary:
	return {
		"key": key if key != "" else cname, "name": cname,
		"type": "unit", "cls": cname,
		"cost": cost, "act": act_cost(cost, kw), "atk": atk, "hp": hp,
		"kw": kw, "gold": false, "src": -1,
	}

# ---------------- 敌方卡组 ----------------
# 流派判定: 骑兵国=快攻; 山贼/哥布林=人海; 海寇/魔物=直伤; 其余(国家正规军/巡逻/攻城)=混编
static func foe_archetype(party: Dictionary) -> String:
	var nid := String(party.get("nation", ""))
	var tid := String(party.get("siege", ""))
	if tid != "" and Nations.TOWNS.has(tid):
		nid = String((Nations.TOWNS[tid] as Dictionary).get("nation", ""))
	if Nations.is_mounted(nid):
		return "rush"
	var ptype := String(party.get("type", ""))
	if ptype == "山贼" or ptype == "哥布林":
		return "swarm"
	if ptype == "海寇" or ptype == "魔物":
		return "burn"
	return "army"

# ---------------- 流派（编成学说） ----------------
# 键是内部代号（判定/存档用, 不要改）, 值是给玩家看的「势力编成」正式名。
# 敌情条与开战横幅都念这个名字, 别在别处另拼一套。
const ARCH_NAME := {
	"rush":  "苍狼铁骑",
	"swarm": "绿林蜂起",
	"burn":  "海寇船团",
	"army":  "王国边军",
}

static func arch_name(party: Dictionary) -> String:
	return String(ARCH_NAME.get(foe_archetype(party), ARCH_NAME["army"]))

static func arch_name_of(arch: String) -> String:
	return String(ARCH_NAME.get(arch, ARCH_NAME["army"]))

# ---------------- 战场词条（特殊场景） ----------------
# 每场战斗按 party 挑一套规则, HUD 上显示成小标签; 规则是真的生效, 不是换皮。
#   front     前线槽数（接舷战甲板狭窄, 只放得下 3 个）
#   camp      敌方大营加成
#   hp        敌方单位登场加血（城墙掩护/守军披甲）
#   lim       回合上限（0 = 不限）; 超了判守方胜
#   no_atk1   第 1 回合双方都不能攻击（夜里看不清）
const SCENARIOS := {
	"field": {"name": "野战", "desc": "平原遭遇, 堂堂之阵",
		"front": 7, "camp": 0, "hp": 0, "lim": 0, "no_atk1": false},
	"siege": {"name": "坚城", "desc": "城墙掩护: 守方大营 +5, 守军 +1 血; 12 回合攻不下就粮尽撤兵",
		"front": 7, "camp": 5, "hp": 1, "lim": 12, "no_atk1": false},
	"boarding": {"name": "接舷", "desc": "甲板狭窄: 双方前线只有 3 个位置",
		"front": 3, "camp": 0, "hp": 0, "lim": 0, "no_atk1": false},
	"night": {"name": "夜袭", "desc": "夜色难辨: 第 1 回合双方都不能攻击, 各自摸黑铺场",
		"front": 7, "camp": 0, "hp": 0, "lim": 0, "no_atk1": true},
}

# 攻城 > 魔物夜袭 > 海寇接舷 > 野战（不看时间, 只看 party, 保证可复现）
static func scenario_of(party: Dictionary) -> String:
	if String(party.get("siege", "")) != "":
		return "siege"
	var ptype := String(party.get("type", ""))
	if ptype == "魔物":
		return "night"
	if ptype == "海寇":
		return "boarding"
	return "field"

static func scenario(id: String) -> Dictionary:
	return SCENARIOS.get(id, SCENARIOS["field"])

static func foe_deck(party: Dictionary, seed_val: int) -> Array:
	var arch := foe_archetype(party)
	var deck: Array = []
	for row in FOE_LISTS[arch]:
		var tpl := String(row[0])
		var n := int(row[1])
		for i in n:
			if FOE_UNITS[arch].any(func(u): return u[0] == tpl):
				for u in FOE_UNITS[arch]:
					if String(u[0]) == tpl:
						deck.append(unit_card(String(u[0]), int(u[1]), int(u[2]), int(u[3]), String(u[4])))
						break
			elif FOE_SPELLS.has(tpl):
				deck.append(foe_spell_card(tpl))
	# 攻城: 守军把滚木礌石搬上城头 —— 换掉最后 3 张
	# (先全部 pop 再 append: 同循环里 pop+append 会把自己刚塞的那张又 pop 掉, 只换 1 张)
	if scenario_of(party) == "siege" and deck.size() >= 3:
		for i in 3:
			deck.pop_back()
		for i in 3:
			deck.append(foe_spell_card("rocks"))
	return shuffled(deck, seed_val)

# 敌方大营血：基础 15 + 兵多加血 + 主角等级水涨船高（同岛上刷怪同一套思路）
# 再加战场词条的加血（坚城 +5）
static func foe_camp_hp(party: Dictionary) -> int:
	var size := int(party.get("size", 3))
	return CAMP_HP + clampi(size - 3, 0, 6) + clampi(Legion.level / 4, 0, 4) \
		+ int(scenario(scenario_of(party)).get("camp", 0))

# ---------------- 小工具 ----------------
static func shuffled(arr: Array, seed_val: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var out: Array = arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out

# ---------------- 卡面立绘 ----------------
# 素材与生成脚本: resources/cards_src（CC0/Public Domain, 见 SOURCES.txt）
#                tools/make_card_art.gd -> resources/cards_art/<key>_card.png(76x84) / _icon.png(40x44)
# 键规则: 法术 = s_<key>(drill/fire/...); 部队 = u_<阵营>_<兵种>(u_my_刀客 / u_foe_山贼)
const ART_DIR := "res://resources/cards_art/"

static func art_key(card: Dictionary, side: String) -> String:
	if String(card.get("type", "unit")) == "spell":
		return "s_" + String(card.get("key", ""))
	return "u_%s_%s" % [side if side != "" else "my", String(card.get("cls", ""))]

# 手牌立绘（大图）
static func art_of(card: Dictionary, side: String) -> Texture2D:
	return _art_load(art_key(card, side) + "_card.png")

# 战场槽位小图
static func art_icon_of(card: Dictionary, side: String) -> Texture2D:
	return _art_load(art_key(card, side) + "_icon.png")

static func _art_load(file: String) -> Texture2D:
	var p := ART_DIR + file
	return load(p) as Texture2D if ResourceLoader.exists(p) else null

# 卡面图标：优先新立绘, 没有再退回旧的行政卡/职业图标
static func icon_of(card: Dictionary, side := "") -> Texture2D:
	var a := art_icon_of(card, side)
	if a != null:
		return a
	if String(card.get("type", "unit")) == "spell":
		var id := String(card.get("key", ""))
		if id.begins_with("m_"):        # 法术卡键 = m_<科技/行政id>, 图标复用它的
			id = id.substr(2)
		if Research.ICONS.has(id):
			return Research.icon_for(id)
		return null
	var cls := String(card.get("cls", ""))
	if cls == "民兵":
		var p := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/1. Wood/Sword.png"
		return load(p) as Texture2D if ResourceLoader.exists(p) else null
	return Slaves.class_icon_for(cls)
