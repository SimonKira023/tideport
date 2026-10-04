# legion_manager.gd —— Autoload，名字：Legion
# 军团系统的「数据层」：主角/伙伴的战斗属性 + 技能树。
#
# 设计（按项目原则砍到能玩的最小集）：
#   · 岛上不再打仗 —— 旧「G 键指挥」整套已删。战斗只发生在出海战役
#     （voyage 出海 -> battle_map），那边用 1/2/3 选编队、F1 点地图指挥。
#     这里只管属性/技能/经验这些数据，谁动手怎么走位看 scene/battle_map.gd + troop.gd。
#   · 属性：主角 攻击力/血量/等级/经验；伙伴的 hp/atk 塞在 Slaves.slaves 的
#     个体字典里（存档跟着整本字典走，不用单独伺候）。主角的血会跟着
#     带进出海战役（下场战斗接着算），战败被抬回家回满血。
#   · 技能树：杀敌得经验，升级得技能点，角色页技能树状图点节点升级
#     （e14 起多条主干; e20 删掉采掘, 现在五条）：
#       行商 = 卖出/买入价；管理 = 劳动力/预算/研究；统帅 = 伙伴攻/血
#       农艺 = 水壶/作物价；体魄 = 主角血/攻
#     分支名统一用职业名/称号（掌柜/豪商/账房/师爷/将军/统领/园丁/粮长/武人/壮士）
#     ❗旧档的「武艺/强健」(id: martial/vigor) 在 from_dict 里映射成 行商/管理
#     ❗e20 删掉的 mine 字段: 旧档里有也直接忽略（from_dict 只认现存键）
extends Node

signal stats_changed        # 等级/经验/技能点/属性变了（角色页刷新）

# —— 技能 ——
# e13i: 主干各 10 级; 5 级后出现两条分支, 选一条走到底（选了就锁另一条）。e14 起六条。
const SKILL_MAX := 10
const SKILL_SPLIT := 5              # 分叉等级：到 5 级必须二选一才能继续升
# e14: 六条主干; 分支名统一用职业名/称号（用户要求）
# e28f: 分支技能一律比主干强 —— 同一项数值分支每级 > 主干每级（掌柜 6%>4% 等）,
#       数值差异较大的（血换攻这类）也把每级收益翻倍往上提，选支才真有「质变感」。
const SKILLS := {
	"trade":  {"name": "行商", "desc": "卖出价 +4%/级, 买入价 -3%/级",
		"a": {"name": "掌柜", "desc": "卖出价再 +6%/级"},
		"b": {"name": "豪商", "desc": "买入价再 -5%/级"}},
	"manage": {"name": "管理", "desc": "每个同伴劳动力 +1/级",
		"a": {"name": "账房", "desc": "每日派活预算 +4 格/级"},
		"b": {"name": "师爷", "desc": "研究点数 +8%/级"}},
	"leader": {"name": "统帅", "desc": "伙伴攻击 +1/级",
		"a": {"name": "将军", "desc": "伙伴攻击再 +2/级"},
		"b": {"name": "统领", "desc": "伙伴血上限 +5/级"}},
	"farm":   {"name": "农艺", "desc": "水壶容量 +2/级",
		"a": {"name": "园丁", "desc": "水壶容量再 +4/级"},
		"b": {"name": "粮长", "desc": "作物卖出价 +5%/级"}},
	"body":   {"name": "体魄", "desc": "主角血上限 +6/级",
		"a": {"name": "武人", "desc": "主角攻击 +2/级"},
		"b": {"name": "壮士", "desc": "主角血上限再 +8/级"}},
}
# 旧档技能名的映射（武艺->行商，强健->管理）
const LEGACY_SKILLS := {"martial": "trade", "vigor": "manage"}

# —— 基础属性（1 级白板）——
const BASE_ATK := 5
const BASE_HP := 50
const ATK_PER_LEVEL := 1          # 每级自带 +1 攻
const HP_PER_LEVEL := 5           # 每级自带 +5 血
const ATK_PER_LEADER := 1
const ALLY_BASE_ATK := 3

const EXP_PER_KILL := 10          # 一个敌人给的经验
const EXP_BASE := 20              # 升级所需经验 = EXP_BASE + (level-1)*EXP_STEP
const EXP_STEP := 15

# —— 状态 ——
var level := 1
var exp := 0
var skill_points := 0
var skills := {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}
var branches := {"trade": "", "manage": "", "leader": "", "farm": "", "body": ""}   # "" / "a" / "b"（5 级后选定）
var player_hp := BASE_HP

# ---------------- 技能树（e13i） ----------------
func skill_lv(id: String) -> int:
	return int(skills.get(id, 0))

# 选的哪条分支（"" = 还没选, 5 级前不用选）
func branch_of(id: String) -> String:
	return String(branches.get(id, ""))

# 分支已生效的级数（0..5）: 没选支/没到 6 级都是 0
func branch_lv(id: String) -> int:
	if branch_of(id) == "":
		return 0
	return maxi(0, skill_lv(id) - SKILL_SPLIT)

# 升一级：5 级是关口 —— 没选分支就升不动（角色页会出现两条分支按钮二选一）
func upgrade_skill(id: String) -> bool:
	if not SKILLS.has(id) or skill_points <= 0:
		return false
	var lv := skill_lv(id)
	if lv >= SKILL_MAX:
		return false
	if lv >= SKILL_SPLIT and branch_of(id) == "":
		return false             # 5 级后必须先选分支
	skills[id] = lv + 1
	skill_points -= 1
	player_hp = mini(player_hp, player_max_hp())     # 血上限变了别溢出
	stats_changed.emit()
	return true

# 选分支（5 级时二选一, 选了就锁死另一条）—— 只能选一次, 不能反悔
func choose_branch(id: String, which: String) -> bool:
	if not SKILLS.has(id) or not SKILLS[id].has(which):
		return false
	if skill_lv(id) < SKILL_SPLIT or branch_of(id) != "":
		return false
	branches[id] = which
	stats_changed.emit()
	return true

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

# 开新档：等级/经验/技能全归零、血回满（由 save_manager.reset_all 调用）
func reset_for_new_game() -> void:
	level = 1
	exp = 0
	skill_points = 0
	skills = {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}
	branches = {"trade": "", "manage": "", "leader": "", "farm": "", "body": ""}
	player_hp = BASE_HP
	stats_changed.emit()

func _on_new_day(_day: int) -> void:
	# 睡一觉满血复活；伙伴的血也回满（Slaves 那边只重置喂食标记）
	player_hp = player_max_hp()
	stats_changed.emit()

# ---------------- 属性计算 ----------------
# 主角血上限 = 基础 + 等级成长 + 穿的盔甲（盔甲只加生命上限, 不存在防御减伤）
func player_max_hp() -> int:
	var hp := BASE_HP + HP_PER_LEVEL * (level - 1)
	hp += 6 * mini(skill_lv("body"), SKILL_SPLIT)    # e14 体魄主干: 血上限 +6/级 (到 5)
	if branch_of("body") == "b":
		hp += 8 * branch_lv("body")                  # e28f 壮士: 分支每级再 +8 (比主干 6 强)
	var worn: ItemData = Inventory.worn_armor
	if worn != null:
		hp += maxi(0, int(worn.armor_hp))
	return hp

func player_atk() -> int:
	var atk := BASE_ATK + ATK_PER_LEVEL * (level - 1)
	if branch_of("body") == "a":
		atk += 2 * branch_lv("body")                 # e28f 武人: 分支每级 +2
	return atk

# 伙伴攻击 = 基础 + 统帅技能（主干封顶 5 级, 5 级后走分支）+ 将军分支 + 行政政策卡
func ally_atk() -> int:
	var atk := ALLY_BASE_ATK + ATK_PER_LEADER * mini(skill_lv("leader"), SKILL_SPLIT) \
		+ Research.ally_atk_bonus() + Marriage.ally_atk_bonus()   # 婚恋: 咪露之婚 +2
	if branch_of("leader") == "a":
		atk += 2 * branch_lv("leader")       # e28f 将军: 分支每级再 +2 (比主干 1 强)
	return atk

# 伙伴血上限 = 基础 30 + 统领分支 + 行政政策卡
func ally_max_hp() -> int:
	var hp := 30 + Research.ally_hp_bonus()
	if branch_of("leader") == "b":
		hp += 5 * branch_lv("leader")        # e28f 统领: 分支每级 +5 (质变感)
	return hp

func exp_next() -> int:
	return EXP_BASE + EXP_STEP * (level - 1)

# ---------------- 经验 / 升级 ----------------
func gain_exp(n: int) -> void:
	exp += n
	while exp >= exp_next():
		exp -= exp_next()
		level += 1
		skill_points += 1
	stats_changed.emit()

# ---------------- 血量 ----------------
# 血上限变了（穿脱盔甲/升技能）后把当前血钳回范围内
func clamp_player_hp() -> void:
	player_hp = clampi(player_hp, 0, player_max_hp())
	stats_changed.emit()

func damage_player(n: int) -> void:
	player_hp = maxi(0, player_hp - n)
	stats_changed.emit()

func heal_player(n: int) -> void:
	player_hp = mini(player_max_hp(), player_hp + n)
	stats_changed.emit()

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {
		"level": level,
		"exp": exp,
		"skill_points": skill_points,
		"skills": skills.duplicate(),
		"branches": branches.duplicate(),
		"player_hp": player_hp,
	}

func from_dict(d: Dictionary) -> void:
	level = maxi(1, int(d.get("level", 1)))
	exp = maxi(0, int(d.get("exp", 0)))
	skill_points = maxi(0, int(d.get("skill_points", 0)))
	var sk: Dictionary = d.get("skills", {})
	for id in skills.keys():
		skills[id] = clampi(int(sk.get(id, 0)), 0, SKILL_MAX)
	# 旧档兼容：武艺 -> 行商 / 强健 -> 管理（只有新名还没数据时才搬）
	for old_id in LEGACY_SKILLS.keys():
		var new_id: String = String(LEGACY_SKILLS[old_id])
		if sk.has(old_id) and not sk.has(new_id):
			skills[new_id] = clampi(int(sk[old_id]), 0, SKILL_MAX)
	# e13i: 分支选择也存档（脏数据一律清成没选）
	var br: Dictionary = d.get("branches", {})
	for id in branches.keys():
		var b := String(br.get(id, ""))
		branches[id] = b if b == "a" or b == "b" else ""
	player_hp = clampi(int(d.get("player_hp", player_max_hp())), 0, player_max_hp())
	stats_changed.emit()
