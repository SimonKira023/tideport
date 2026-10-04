extends Node
# marriage.gd —— 婚恋数据层（autoload: Marriage）
#
# 六位可结婚对象（slaves.gd ROSTER 里的女性）：娜雅/珞琳/咪露/海莉/珂丹/雪莱
# 恋爱节奏：篝火「心里话」按好感门槛逐段解锁（每位 5 段），
#          全看完 + 好感满 10 → 可求婚（需一枚戒指）→ 篝火婚礼 → 专属 perk。
# 存档：跟着 save_manager 走（to_dict / from_dict）。

signal changed

const HEART_STEPS := [2, 4, 6, 8, 10]   # 每段心里话需要的好感

# 每位： Hearts 键 = ROSTER id；perk = 结婚后全局生效的加成（c14 接线读）
const BRIDES := {
	"rq_01": {"name": "娜雅", "perk_key": "crop",   "perk_mult": 1.15, "perk_desc": "作物产量 +15%"},
	"rq_02": {"name": "珞琳", "perk_key": "build",  "perk_mult": 0.90, "perk_desc": "建筑花费 -10%"},
	"rq_03": {"name": "咪露", "perk_key": "atk",    "perk_mult": 2.0,  "perk_desc": "伙伴攻击 +2"},
	"rq_05": {"name": "海莉", "perk_key": "voyage", "perk_mult": 1.20, "perk_desc": "航海收益 +20%"},
	"rq_06": {"name": "珂丹", "perk_key": "mine",   "perk_mult": 1.15, "perk_desc": "矿井产出 +15%"},
	"rq_07": {"name": "雪莱", "perk_key": "tech",   "perk_mult": 1.10, "perk_desc": "科技点 +10%"},
}

var wife_id := ""                      # 已婚对象的 ROSTER id（空 = 未婚）
var hearts := {}                       # id -> 已看心里话段数 0..5
var married_day := 0                   # 结婚那天是第几天（婚礼纪要）

func _ready() -> void:
	for id in BRIDES:
		hearts[id] = 0

# ---------------- 查询 ----------------
func is_bride(id: String) -> bool:
	return BRIDES.has(id)

func stage(id: String) -> int:
	return int(hearts.get(id, 0))

# 现在能不能讲下一段心里话（好感由调用方传）
func can_heart_talk(id: String, affection: int) -> bool:
	if not is_bride(id) or is_married_to(id):
		return false
	var st := stage(id)
	if st >= HEART_STEPS.size():
		return false
	return affection >= int(HEART_STEPS[st])

# 讲完一段：推进并广播
func do_heart_talk(id: String) -> void:
	if not is_bride(id):
		return
	hearts[id] = mini(HEART_STEPS.size(), stage(id) + 1)
	changed.emit()

# 求婚条件：五段心里话全看完 + 好感满（10）由调用方校验 + 有戒指由调用方传
func stage_full(id: String) -> bool:
	return is_bride(id) and stage(id) >= HEART_STEPS.size()

func can_propose(id: String, affection: int, has_ring: bool) -> bool:
	if wife_id != "" or not stage_full(id):
		return false
	return affection >= 10 and has_ring

func marry(id: String, day: int) -> void:
	if not is_bride(id):
		return
	wife_id = id
	married_day = day
	changed.emit()

func is_married_to(id: String) -> bool:
	return wife_id == id and wife_id != ""

func wife_name() -> String:
	if wife_id == "" or not BRIDES.has(wife_id):
		return ""
	return String(BRIDES[wife_id]["name"])

# ---------------- 专属 perk ----------------
# 已婚时返回 {key, mult, desc}；未婚返回空字典
func perk() -> Dictionary:
	if wife_id == "" or not BRIDES.has(wife_id):
		return {}
	var b: Dictionary = BRIDES[wife_id]
	return {"key": b["perk_key"], "mult": float(b["perk_mult"]), "desc": b["perk_desc"]}

# 便捷查询：当前 perk 是否某键（c14 各系统用它问）
func perk_key() -> String:
	var p := perk()
	return str(p.get("key", "")) if not p.is_empty() else ""

func perk_mult(key: String) -> float:
	var p := perk()
	if p.is_empty() or str(p["key"]) != key:
		return 1.0
	return float(p["mult"])

# 咪露：攻击是加法体系，专用接口（未婚 0，已婚 +2）
func ally_atk_bonus() -> int:
	return int(perk()["mult"]) if perk_key() == "atk" else 0

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {"wife": wife_id, "day": married_day, "hearts": hearts.duplicate()}

func from_dict(d: Dictionary) -> void:
	wife_id = String(d.get("wife", ""))
	married_day = int(d.get("day", 0))
	var hs: Dictionary = d.get("hearts", {})
	for id in BRIDES:
		hearts[id] = int(hs.get(id, 0))
	changed.emit()

func reset() -> void:
	wife_id = ""
	married_day = 0
	for id in BRIDES:
		hearts[id] = 0
	changed.emit()
