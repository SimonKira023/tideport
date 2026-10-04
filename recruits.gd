# recruits.gd —— e53 招募任务状态机（纯任务制招募的中枢）
#
# 花名册（Slaves.ROSTER）定人: 顺序 / 名字 / 初始职业固定, Slaves.count 就是候选序号。
# 这里只管「窗口」与「交付」:
#   · 候选人从 ROSTER.day 那天起在篝火边坐 WINDOW_DAYS 天;
#   · 错过就回家, RETURN_GAP 天后回来再坐一轮, 循环到招到为止;
#   · 窗口打开当天把「有客来访」挂上任务栏（Quests）, 关窗撤下, 交付完成收掉;
#   · 交付（deliver）核验 need -> 扣账（作物/金币/材料）-> Slaves.recruit_roster 入队。
# 纯函数化: 窗口相位由绝对天数模运算推出来, 本模块零存档 ——
# 经过天数读 TimeManager 的 year/season/day 现算, 入队进度读 Slaves.count。
# need 类型: crops 作物份数 / coin 金币 / flag 指引链完成记录 /
#            level 主角历练 / item 材料（stone/iron/wood, 走 Slaves.can_afford）/
#            techs 完成科技数 / prestige 声望。
extends Node

signal changed   # 每天翻日时发（面板刷新用）

const WINDOW_DAYS := 7   # 候选人在篝火边坐几天（一轮窗口）
const RETURN_GAP := 14   # 错过窗口后, 隔几天再回来开下一轮

const TASK_TITLE := "有客来访: %s"   # 任务栏标题模板（%s = 名字）

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

func _on_new_day(_d: int) -> void:
	changed.emit()
	sync_quests()

# ---------------- 候选与窗口 ----------------

# 当前候选（第 Slaves.count 位）。8 人全招完返回空。
func candidate() -> Dictionary:
	if Slaves.count >= Slaves.ROSTER.size():
		return {}
	return Slaves.ROSTER[Slaves.count]

# 本局经过的天数（开局第 1 天 = 0）。
func days_elapsed() -> int:
	return (TimeManager.year - 1) * TimeManager.DAYS_PER_SEASON * 4 \
		+ TimeManager.season * TimeManager.DAYS_PER_SEASON + TimeManager.day - 1

# 本轮窗口已开了几天（0 = 今天刚开; -1 = 关窗中）。
# 相位纯函数: 首窗从 day-1 起 [day, day+7), 之后每轮 [上窗末+14, +7) 循环 —— 模运算推, 零状态。
func _phase() -> int:
	var c := candidate()
	if c.is_empty():
		return -1
	var since := days_elapsed() - (int(c["day"]) - 1)
	if since < 0:
		return -1
	if since < WINDOW_DAYS:
		return since
	var t := since - WINDOW_DAYS - RETURN_GAP
	if t >= 0 and t % (WINDOW_DAYS + RETURN_GAP) < WINDOW_DAYS:
		return t % (WINDOW_DAYS + RETURN_GAP)
	return -1

# 今天篝火边有没有候选坐着（game.gd 拿这个决定今晚生不生篝火）。
func visitor() -> bool:
	return _phase() >= 0

# 本轮窗口还剩几天（含今天; 关窗中返回 0）。
func window_left() -> int:
	var p := _phase()
	return 0 if p < 0 else WINDOW_DAYS - p

# ---------------- 任务栏联动 ----------------

# 窗口打开 -> 挂「有客来访」; 关窗 -> 撤下（新档开局 / 每天翻日 / 读档后各调一次）。
func sync_quests() -> void:
	var c := candidate()
	if c.is_empty():
		return
	var id := String(c["id"])
	if visitor():
		if not Quests.has_active(id):
			Quests.add(id, TASK_TITLE % String(c["name"]), String(c["req"]))
	elif Quests.has_active(id):
		Quests.cancel(id)

# ---------------- 条件核验与交付 ----------------

# 条件是否已达成（只查不扣 —— 扣账在 deliver 里一次做完）。
func met(need: Dictionary) -> bool:
	if need.has("crops") and _crops_count() < int(need["crops"]):
		return false
	if need.has("coin") and Wallet.money < int(need["coin"]):
		return false
	if need.has("flag") and not Quests.has_done(String(need["flag"])):
		return false
	if need.has("level") and Legion.level < int(need["level"]):
		return false
	if need.has("item") and not Slaves.can_afford(need["item"]):
		return false
	if need.has("techs") and _techs_count() < int(need["techs"]):
		return false
	if need.has("prestige") and Nations.prestige < int(need["prestige"]):
		return false
	return true

# 交付: 条件全达成时扣账并让候选人入队（返回是否成功）。
# 作物 / 金币在这里扣; 石头 / 铁 / 木头走 Slaves.pay_cost（它自己再兜底核验一次）。
func deliver() -> bool:
	var c := candidate()
	if c.is_empty() or not visitor():
		return false
	var need: Dictionary = c["need"]
	if not met(need):
		return false
	if need.has("crops"):
		_take_crops(int(need["crops"]))
	if need.has("coin"):
		Wallet.spend_money(int(need["coin"]))
	if need.has("item") and not Slaves.pay_cost(need["item"]):
		return false
	Slaves.recruit_roster()
	Quests.complete(String(c["id"]))
	changed.emit()
	return true

# 背包里有多少份「作物」（跟 Quests 里程碑同一口径: item.type == 作物, 跨槽位累计）
func _crops_count() -> int:
	var n := 0
	for s in Inventory.slot_list():
		var it = s["item"]
		if it != null and it is ItemData and String(it.type) == "作物":
			n += int(s["count"])
	return n

# 跨槽位扣 n 份作物（什么作物都行 —— 来客只认吃的）
func _take_crops(n: int) -> void:
	for s in Inventory.slot_list():
		if n <= 0:
			return
		var it = s["item"]
		if it != null and it is ItemData and String(it.type) == "作物":
			var take: int = mini(int(s["count"]), n)
			Inventory.remove_item(it, take)
			n -= take

# 完成的科技数（跟 Quests 里程碑同一口径）
func _techs_count() -> int:
	var finished := 0
	for tid in Research.TECHS.keys():
		if Research.has_tech(String(tid)):
			finished += 1
	return finished

# ---------------- 面板文案 ----------------

# 招募任务的进度一句话（篝火面板 + 酒馆消息板共用）。
func progress_text() -> String:
	var c := candidate()
	if c.is_empty():
		return ""
	var need: Dictionary = c["need"]
	if need.has("crops"):
		return "作物 %d/%d" % [mini(_crops_count(), int(need["crops"])), int(need["crops"])]
	if need.has("coin"):
		return "金币 %d/%d" % [mini(Wallet.money, int(need["coin"])), int(need["coin"])]
	if need.has("flag"):
		return "已达成" if Quests.has_done(String(need["flag"])) else "未达成"
	if need.has("level"):
		return "历练 %d/%d" % [Legion.level, int(need["level"])]
	if need.has("item"):
		return _item_progress(need["item"])
	if need.has("techs"):
		return "科技 %d/%d" % [_techs_count(), int(need["techs"])]
	if need.has("prestige"):
		return "声望 %d/%d" % [Nations.prestige, int(need["prestige"])]
	return "到火边搭话就行"

# item 类条件的进度串（多种料拼一行）
func _item_progress(cost: Dictionary) -> String:
	var parts := []
	for k in ["coin", "wood", "stone", "iron"]:
		if not cost.has(k):
			continue
		var goal := int(cost[k])
		var have := 0
		match String(k):
			"coin":
				have = Wallet.money
			"wood":
				have = Inventory.count_item(Slaves.WOOD_ITEM)
			"stone":
				have = Inventory.count_item(Slaves.STONE_ITEM)
			"iron":
				have = Inventory.count_item(Slaves.IRON_ITEM)
		parts.append("%s %d/%d" % [String(k), mini(have, goal), goal])
	return " ".join(parts)

# ---------------- 剧情对话 ----------------

# 8 人的三段话: intro 首次搭话 / ok 条件达成入队 / wait 条件不够被婉拒。
# ❗文案不用「·」字符（IPix.ttf 缺字形）。
const DIALOGS := {
	"rq_00": {
		"intro": "我看见山下的烟了. 你是这火的主人? 我叫布恩, 没地方去了. 给口饭吃, 我就把力气留给这座岛.",
		"ok": "行, 就这么说定. 你把火分我一半, 我把力气分你一半.",
		"wait": "我就在火边坐坐, 不碍事.",
	},
	"rq_01": {
		"intro": "我叫娜雅, 篮子空了三天. 锅里要是能添上 6 份收成, 我就留下帮你们烧粥.",
		"ok": "香极了. 这一锅粥是我请的, 以后的日子, 我们一起过.",
		"wait": "篮子还空着. 等田里收出 6 份作物, 我再回来.",
	},
	"rq_02": {
		"intro": "珞琳, 木匠家的丫头. 光有火不算家. 哪天你们在这岛上盖起第一座屋子, 我就来投.",
		"ok": "梁正了, 家就成了. 这个家, 我来帮你们撑.",
		"wait": "图纸我都画好了. 可你们连第一座房子都还没盖.",
	},
	"rq_03": {
		"intro": "咪露. 我在坡上看了你半天, 手还是生的. 等历练到 2 级, 再来跟我谈入伙的事.",
		"ok": "现在像样了. 我的刀, 从今天起归你的火.",
		"wait": "手还在抖. 去历练, 练到 2 级再来.",
	},
	"rq_04": {
		"intro": "塔洛, 从前替人管账, 也替自己欠了账. 300 金币, 替我还清, 我的算盘就是你的.",
		"ok": "债一笔勾销. 往后你的账, 我记得比我自己的命还牢.",
		"wait": "300 金币, 一个子儿都不能少. 债主可不看火候.",
	},
	"rq_05": {
		"intro": "海莉. 听说你们的船真出过海了? 带我走海路的人, 我也跟他走.",
		"ok": "海风的味道, 我在岸上闻了一辈子. 总算等到同行的人.",
		"wait": "出了海再来叫我. 没出过海的火堆, 留不住我.",
	},
	"rq_06": {
		"intro": "珂丹. 矿坑口的石缝里能长出好东西. 你们要是真从矿井里挖出过矿, 就让我看看.",
		"ok": "石头底下压着的春天, 让你们挖出来了. 我来给这岛添点绿的.",
		"wait": "矿井还没出过矿吧? 石头不醒, 我不醒.",
	},
	"rq_07": {
		"intro": "雪莱. 别的我不问, 只问一句: 你们可曾把一样东西琢磨明白过? 明明白白的那种.",
		"ok": "问出答案的人, 就该跟做事的人在一起. 收下我吧.",
		"wait": "先去明白一件事. 糊里糊涂的火, 照不亮学问.",
	},
}

# 篝火「上前搭话」拿到的对话行（story_dialogue.play 直接吃的 {name, portrait, text} 数组）。
# stage: "intro" / "ok" / "wait"; portrait 用花名册序号对应的立绘（slave_00..slave_07）。
func talk_lines(stage: String) -> Array:
	var c := candidate()
	if c.is_empty():
		return []
	var dl: Dictionary = DIALOGS.get(String(c["id"]), {})
	var text := String(dl.get(stage, ""))
	if text.is_empty():
		return []
	return [{"name": String(c["name"]), "portrait": "slave_%02d" % Slaves.count, "text": text}]

# ---------------- 入伙长剧本（导演模式, cg_view 场景 + 台词） ----------------
# 每人一段专属入伙演出: 场景/时段贴合人物, 3~4 句台词。
# 行 = ["he"/"me", 文案]; ❗标点只用 ASCII。
const _ME := {"name": "我", "portrait": "player"}
const JOINS := {
	"rq_00": {"scene": "camp", "tod": "night", "weather": "embers", "lines": [
		["he", "行, 就这么说定. 你把火分我一半, 我把力气分你一半."],
		["me", "从今晚起, 火边就有你的位置了."],
		["he", "位置.......好久没人给我留过位置了. 布恩记下了. 明天天一亮, 头一个上工."],
	]},
	"rq_01": {"scene": "field", "tod": "day", "lines": [
		["he", "香极了. 这一锅粥是我请的, 以后的日子, 我们一起过."],
		["me", "田里的活, 往后就多指望娜雅了."],
		["he", "别客气. 一口锅, 一块田, 有来有往, 这就是家了."],
	]},
	"rq_02": {"scene": "camp", "tod": "day", "lines": [
		["he", "梁正了, 家就成了. 这个家, 我来帮你们撑."],
		["me", "有珞琳在, 图纸和锤子都放心交出去."],
		["he", "锤子可以借你. 图纸免谈--那上面还画着没盖的屋子呢."],
	]},
	"rq_03": {"scene": "cliff", "tod": "dusk", "lines": [
		["he", "现在像样了. 我的刀, 从今天起归你的火."],
		["me", "欢迎入伙. 往后守夜的活, 有你在就睡得踏实."],
		["he", "那当然. 从今晚起, 敢靠近这座岛的野东西, 都得先问过我的刀."],
	]},
	"rq_04": {"scene": "camp", "tod": "night", "weather": "embers", "lines": [
		["he", "债一笔勾销. 往后你的账, 我记得比我自己的命还牢."],
		["me", "账交给你, 我放心. 人也留下来吧, 火边缺个管事的."],
		["he", "好. 从今晚起, 我连人带算盘, 都押在这堆火上了."],
	]},
	"rq_05": {"scene": "docks", "tod": "dusk", "lines": [
		["he", "海风的味道, 我在岸上闻了一辈子. 总算等到同行的人."],
		["me", "以后出海, 船头就留给海莉."],
		["he", "说定了. 有风我顶着, 有浪我看着, 你们只管把船开稳."],
	]},
	"rq_06": {"scene": "field", "tod": "dawn", "lines": [
		["he", "石头底下压着的春天, 让你们挖出来了. 我来给这岛添点绿的."],
		["me", "苗圃就交给珂丹了, 我给你打下手."],
		["he", "不急, 慢慢学. 好东西都是等出来的--人也一样."],
	]},
	"rq_07": {"scene": "camp", "tod": "day", "lines": [
		["he", "问出答案的人, 就该跟做事的人在一起. 收下我吧."],
		["me", "求之不得. 往后岛上的账和学问, 都有雪莱一份."],
		["he", "一言为定. 明天开始, 我要把这座岛, 从头到尾算明白一遍."],
	]},
}

# 入伙演出脚本（play_directed 直接吃; 没配剧本的 id 返回空, 走旧 ok 台词）
func join_script() -> Array:
	var c := candidate()
	if c.is_empty():
		return []
	var j: Dictionary = JOINS.get(String(c["id"]), {})
	if j.is_empty():
		return []
	var idx := int(Slaves.count)   # 候选人 = 花名册下一位（与 ROSTER 同序）
	var who: Dictionary = {"name": String(c["name"]), "portrait": "slave_%02d" % idx}
	var lines: Array = []
	lines.append({"fx": "bg", "scene": j["scene"], "tod": j["tod"], "dur": 1.4})
	if j.has("weather"):
		lines.append({"fx": "weather", "mode": j["weather"], "amount": 26})
	lines.append({"fx": "show", "who": "s%02d" % idx, "at": "m"})
	lines.append({"fx": "show", "who": "you", "at": "ml"})
	for row in j["lines"]:
		if row[0] == "me":
			lines.append({"name": _ME["name"], "portrait": _ME["portrait"], "text": row[1]})
		else:
			lines.append({"name": who["name"], "portrait": who["portrait"], "text": row[1]})
	lines.append({"fx": "sfx", "name": "buy"})
	lines.append({"fx": "hide", "who": "all"})
	return lines
