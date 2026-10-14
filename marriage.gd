extends Node
# marriage.gd —— 婚恋数据层（autoload: Marriage）
#
# 六位可结婚对象（slaves.gd ROSTER 里的女性）：娜雅/珞琳/咪露/汐月/珂丹/雪莱
# 两条线并行：
#   好感线 —— 所有人都能走：赠送攒好感 → 战斗加成（slaves.gd 管），心里话也吃好感门槛。
#   恋爱线 —— 只对六位姑娘开放：心里话开线后可做「恋爱互动」攒心动值，纯甜蜜向。
# 节奏：篝火「心里话」按好感门槛逐段解锁（每位 5 段），
#      全看完 + 好感满 10 → 可求婚（需一枚戒指）→ 篝火婚礼 → 专属 perk。
# 存档：跟着 save_manager 走（to_dict / from_dict）。

signal changed

const HEART_STEPS := [2, 4, 6, 8, 10]   # 每段心里话需要的好感
const LOVE_MAX := 10                     # 心动值上限（十格，跟好感同一口径）

# 每位： Hearts 键 = ROSTER id；perk = 结婚后全局生效的加成（c14 接线读）
const BRIDES := {
	"rq_00": {"name": "咪露", "perk_key": "atk",    "perk_mult": 2.0,  "perk_desc": "伙伴攻击 +2"},
	"rq_02": {"name": "珞琳", "perk_key": "build",  "perk_mult": 0.90, "perk_desc": "建筑花费 -10%"},
	"rq_03": {"name": "娜雅", "perk_key": "crop",   "perk_mult": 1.15, "perk_desc": "作物产量 +15%"},
	"rq_05": {"name": "汐月", "perk_key": "voyage", "perk_mult": 1.20, "perk_desc": "航海收益 +20%"},
	"rq_06": {"name": "珂丹", "perk_key": "mine",   "perk_mult": 1.15, "perk_desc": "矿井产出 +15%"},
	"rq_07": {"name": "雪莱", "perk_key": "tech",   "perk_mult": 1.10, "perk_desc": "科技点 +10%"},
}

# 恋爱互动表：need = 开放所需心里话段数（1..5，形成「心里话开线 → 每日互动攒心动」循环）；
# love = 一次加多少心动；married = true 的婚后专属（不看 need）。
const ROMANCE_ACTIONS := [
	{"id": "walk",  "name": "牵手散步", "need": 1, "love": 1, "married": false,
		"line": "(十指相扣, 沿着田埂慢慢走) 走慢点也没关系, 反正今天不赶活."},
	{"id": "cloud", "name": "并肩看云", "need": 2, "love": 1, "married": false,
		"line": "(并排躺在草垛上) 你看那朵云, 胖乎乎的, 像不像咱家的谷仓?"},
	{"id": "snack", "name": "分吃点心", "need": 3, "love": 1, "married": false,
		"line": "(把麦饼掰成两半, 大的那半递过去) 趁热吃, 别嫌我手上有灰."},
	{"id": "hug",   "name": "月下相拥", "need": 4, "love": 2, "married": false,
		"line": "(月亮升起来的时候轻轻抱住) 再站一会儿, 就一会儿."},
	{"id": "kiss",  "name": "额头轻吻", "need": 5, "love": 2, "married": false,
		"line": "(趁 Ta 不注意, 在额头落下轻轻一吻) 脸红什么, 又不是没见过你."},
	{"id": "night", "name": "灯下夜话", "need": 0, "love": 2, "married": true,
		"line": "(一盏油灯, 两杯热茶, 说些不着急的话) 以后每年都这么过, 说好了."},
]

var wife_id := ""                      # 已婚对象的 ROSTER id（空 = 未婚）
var hearts := {}                       # id -> 已看心里话段数 0..5
var love := {}                         # id -> 心动值 0..LOVE_MAX（恋爱线数值，恋爱互动攒）
var romance_today := {}                # id -> 今天恋爱互动过没（每天一次，跟赠送互不占）
var married_day := 0                   # 结婚那天是第几天（婚礼纪要）

func _ready() -> void:
	for id in BRIDES:
		hearts[id] = 0
		love[id] = 0
		romance_today[id] = false
	# 新的一天：恋爱互动次数重置（autoload 顺序 TimeManager 在前，连接安全）
	TimeManager.new_day.connect(_on_new_day)

func _on_new_day(_day: int) -> void:
	for id in BRIDES:
		romance_today[id] = false

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

# ---------------- 恋爱线（心动值 + 恋爱互动） ----------------
func love_of(id: String) -> int:
	return int(love.get(id, 0))

func romance_done_today(id: String) -> bool:
	return bool(romance_today.get(id, false))

# 恋爱线对谁开放：已婚的六位姑娘，或已开出至少一段心里话的
func romance_open(id: String) -> bool:
	if not is_bride(id):
		return false
	return is_married_to(id) or stage(id) >= 1

# 某个互动现在能不能做（内部判定，UI 灰显也用它）
func romance_action_ok(a: Dictionary, id: String) -> bool:
	if not romance_open(id) or romance_done_today(id):
		return false
	if bool(a["married"]):
		return is_married_to(id)
	return stage(id) >= int(a["need"])

# 做一次恋爱互动：成功返回 {ok, gain, line, full}；失败返回 {ok=false, reason}
func do_romance(id: String, action_id: String) -> Dictionary:
	if not is_bride(id):
		return {"ok": false, "reason": "not_bride"}
	for a in ROMANCE_ACTIONS:
		if String(a["id"]) != action_id:
			continue
		if not romance_action_ok(a, id):
			if romance_done_today(id):
				return {"ok": false, "reason": "done_today"}
			if bool(a["married"]) and not is_married_to(id):
				return {"ok": false, "reason": "not_married"}
			return {"ok": false, "reason": "locked"}
		var before := love_of(id)
		var gain := int(a["love"])
		var after := mini(LOVE_MAX, before + gain)
		love[id] = after
		romance_today[id] = true
		changed.emit()
		return {"ok": true, "gain": after - before, "line": String(a["line"]),
			"full": after >= LOVE_MAX}
	return {"ok": false, "reason": "no_action"}

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {"wife": wife_id, "day": married_day, "hearts": hearts.duplicate(),
		"love": love.duplicate(), "romance_today": romance_today.duplicate()}

func from_dict(d: Dictionary) -> void:
	wife_id = String(d.get("wife", ""))
	married_day = int(d.get("day", 0))
	var hs: Dictionary = d.get("hearts", {})
	var lv: Dictionary = d.get("love", {})
	var rt: Dictionary = d.get("romance_today", {})
	for id in BRIDES:
		hearts[id] = int(hs.get(id, 0))
		love[id] = int(lv.get(id, 0))
		romance_today[id] = bool(rt.get(id, false))
	changed.emit()

func reset() -> void:
	wife_id = ""
	married_day = 0
	for id in BRIDES:
		hearts[id] = 0
		love[id] = 0
		romance_today[id] = false
	changed.emit()
