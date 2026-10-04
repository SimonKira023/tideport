# crafting.gd —— Autoload，名字：Crafting
# 管理「物品制作」配方：什么材料 → 什么产物。
# 只管配方数据和「能不能做 / 做出来」的纯逻辑，界面交给 backpack_ui.gd 的 craft 页。
extends Node

signal crafted(item: ItemData)       # 做出来一件东西（面板弹提示用）
signal smith_changed                 # 制造中项目变化（开工 / 每晚推进 / 出货）

# 配方表。每个配方：
#   name   —— 产物显示名（冗余，方便面板直接显示）
#   result —— 产物 ItemData（preload）
#   count  —— 一次做几件
#   costs  —— [{item: ItemData, count: int}] 需要的材料
const RECIPES := [
	{
		"result": preload("res://item/baked_potato.tres"),
		"count": 1,
		"costs": [
			{"item": preload("res://item/potato.tres"), "count": 1},
			{"item": preload("res://item/wood.tres"), "count": 1},
		],
	},
	{
		"result": preload("res://item/carrot_salad.tres"),
		"count": 1,
		"costs": [
			{"item": preload("res://item/carrot.tres"), "count": 2},
		],
	},
	{
		"result": preload("res://item/cabbage_soup.tres"),
		"count": 1,
		"costs": [
			{"item": preload("res://item/cabbage.tres"), "count": 1},
			{"item": preload("res://item/wood.tres"), "count": 1},
		],
	},
	{
		"result": preload("res://item/pumpkin_pie.tres"),
		"count": 1,
		"costs": [
			{"item": preload("res://item/pumpkin.tres"), "count": 1},
			{"item": preload("res://item/wheat.tres"), "count": 1},
		],
	},
	{
		# 木板: 一块木头锯成两块, 铺在屋里/野外当地板（镐子可撬掉回收）
		"result": preload("res://item/wood_floor.tres"),
		"count": 2,
		"costs": [
			{"item": preload("res://item/wood.tres"), "count": 1},
		],
	},
	{
		# 鹅卵石小径: 一块石头凿成两块石板, 铺在野外当路（镐子可挖掉回收）
		"result": preload("res://item/stone_path.tres"),
		"count": 2,
		"costs": [
			{"item": preload("res://item/stone.tres"), "count": 1},
		],
	},
	{
		# ❗工作台必须留在基础配方区：它是解锁工作台配方的前提，放工作台区就死锁了
		"result": preload("res://item/workbench.tres"),
		"count": 1,
		"costs": [
			{"item": preload("res://item/wood.tres"), "count": 4},
		],
	},
	# ❗木船不在这儿做了：船只能在东岸那座废弃码头造（见 voyage.gd / dock_ui.gd），
	#   造好就停在码头，走到码头按 F 出海。
]

# 工作台配方：要站在工作台旁边才能做（ Structures.near_workbench 判定）。
# e28b: 镐子撤了 —— 开局哥布林赠礼直接给一把（game._give_starting_items）,
# 工作台再能做一把纯属多余。这儿只做熔炉这类器械。
const WORKBENCH_RECIPES := [
	{
		"result": preload("res://item/furnace.tres"),
		"count": 1,
		"costs": [
			{"item": preload("res://item/stone.tres"), "count": 6},
			{"item": preload("res://item/iron_ore.tres"), "count": 2},
			{"item": preload("res://item/wood.tres"), "count": 2},
		],
	},
]

# 铁匠铺配方：要站在铁匠铺旁（game.player_blacksmith_level, 附近最高那座的等级达标）。
# ❗盔甲是「整套」卖的装备（type = "装备"）, 不是一个头盔一个护腿的散件。
#   lv = 需要的铁匠铺等级（1-3, 铁匠铺交互按 F 花钱升级）,
#   labor = 建成需要的人工（人·天）：开工付清材料，之后每晚按派去打铁的人数积累，
#   攒够 labor 出货（人数在每晚派活面板「打铁」栏调整）。
#   e41c: 可以一次排好几件 —— 人工先喂队首，多出来的顺延给下一件（见 add_smith_work）。
#   磨坊的 craft_bonus 对盔甲**不生效**——一件是一件, 打铁没有买一送一。
const SMITH_RECIPES := [
	{
		"result": preload("res://item/armor_wood.tres"), "count": 1, "lv": 1, "labor": 2,
		"costs": [{"item": preload("res://item/wood.tres"), "count": 5}],
	},
	{
		"result": preload("res://item/armor_iron.tres"), "count": 1, "lv": 1, "labor": 2,
		"costs": [
			{"item": preload("res://item/iron.tres"), "count": 3},
			{"item": preload("res://item/stone.tres"), "count": 1},
		],
	},
	{
		"result": preload("res://item/armor_gold.tres"), "count": 1, "lv": 2, "labor": 4,
		"costs": [
			{"item": preload("res://item/iron.tres"), "count": 4},
			{"item": preload("res://item/stone.tres"), "count": 2},
		],
	},
	{
		# 婚恋系统（marriage.gd）：向心意相通的伙伴求婚要一枚银戒
		"result": preload("res://item/ring.tres"), "count": 1, "lv": 2, "labor": 3,
		"costs": [
			{"item": preload("res://item/iron.tres"), "count": 2},
			{"item": preload("res://item/stone.tres"), "count": 1},
		],
	},
]

# 背包里某材料有多少（够不够用）
func _have(item: ItemData, need: int) -> bool:
	return Inventory.count_item(item) >= need

# 某个配方当前能不能做（所有材料都够）
func can_craft(idx: int) -> bool:
	if idx < 0 or idx >= RECIPES.size():
		return false
	var recipe: Dictionary = RECIPES[idx]
	for c in recipe["costs"]:
		if not _have(c["item"], int(c["count"])):
			return false
	return true

# 制作：扣材料、产产物。返回 true 表示做出来了。
func craft(idx: int) -> bool:
	if not can_craft(idx):
		return false
	var recipe: Dictionary = RECIPES[idx]
	for c in recipe["costs"]:
		Inventory.remove_item(c["item"], int(c["count"]))
	var result: ItemData = recipe["result"]
	# 科技树「磨坊」：制作时多产 1 份（见 research.gd）
	var n: int = int(recipe["count"]) + Research.craft_bonus()
	for _i in n:
		Inventory.add_item(result, 1)
	crafted.emit(result)
	return true

# 某个配方缺哪些材料（给人看的文字，返回空数组=都不缺）
func missing(idx: int) -> Array:
	var out: Array = []
	if idx < 0 or idx >= RECIPES.size():
		return out
	var recipe: Dictionary = RECIPES[idx]
	for c in recipe["costs"]:
		var have: int = Inventory.count_item(c["item"])
		var need: int = int(c["count"])
		if have < need:
			out.append({"item": c["item"], "have": have, "need": need})
	return out

# ---------------- 工作台配方 ----------------
# 跟上面一套，只是查的是 WORKBENCH_RECIPES，而且要先站在工作台旁。

func can_craft_workbench(idx: int) -> bool:
	if idx < 0 or idx >= WORKBENCH_RECIPES.size():
		return false
	if not near_workbench():
		return false
	var recipe: Dictionary = WORKBENCH_RECIPES[idx]
	for c in recipe["costs"]:
		if not _have(c["item"], int(c["count"])):
			return false
	return true

func craft_workbench(idx: int) -> bool:
	if not can_craft_workbench(idx):
		return false
	var recipe: Dictionary = WORKBENCH_RECIPES[idx]
	for c in recipe["costs"]:
		Inventory.remove_item(c["item"], int(c["count"]))
	var result: ItemData = recipe["result"]
	var n: int = int(recipe["count"]) + Research.craft_bonus()
	for _i in n:
		Inventory.add_item(result, 1)
	crafted.emit(result)
	return true

func missing_workbench(idx: int) -> Array:
	var out: Array = []
	if idx < 0 or idx >= WORKBENCH_RECIPES.size():
		return out
	if not near_workbench():
		out.append({"item": null, "have": 0, "need": -1})   # need = -1 表示「不在工作台旁」
		return out
	var recipe: Dictionary = WORKBENCH_RECIPES[idx]
	for c in recipe["costs"]:
		var have: int = Inventory.count_item(c["item"])
		var need: int = int(c["count"])
		if have < need:
			out.append({"item": c["item"], "have": have, "need": need})
	return out

# 玩家身边有没有工作台（问 game 拿玩家格子；面板里/编辑器里问不到就当没有）
func near_workbench() -> bool:
	var g := Engine.get_main_loop()
	if g == null or not (g is SceneTree):
		return false
	var game: Node = (g as SceneTree).get_first_node_in_group("game")
	if game == null or not game.has_method("player_near_workbench"):
		return false
	return bool(game.call("player_near_workbench"))

# ---------------- 铁匠铺配方 ----------------
# 跟工作台一套，但门槛是「铁匠铺等级」：附近最高那座 Lv 几，就能打几档的甲。
# 打铁是「制造中」的：点配方 = 排进队尾（材料当场付清），每晚按派去打铁的人数积累人工，
# 攒够队首那件就出货；**多出来的人工顺延给下一件**（所以多件可以一次排好，
# 夜里按排队顺序一件件打出来，见 add_smith_work）。
# ❗e41c 起不再是「一次只能打一件」：smith_queue 里可以排任意多件。

# 制造中/待制造的打铁队列：每项 = {"idx": int, "work": int, "need": int}
var smith_queue: Array = []

func reset() -> void:
	smith_queue.clear()

func smith_busy() -> bool:
	return not smith_queue.is_empty()

# 队里排了几件
func smith_queued() -> int:
	return smith_queue.size()

# 队首那件（没排队返回 {}）—— 面板显示进度用
func smith_top() -> Dictionary:
	return smith_queue[0] if not smith_queue.is_empty() else {}

# 某个配方的产物名（越界返回 ""）
func smith_item_name(idx: int) -> String:
	if idx < 0 or idx >= SMITH_RECIPES.size():
		return ""
	return String(SMITH_RECIPES[idx]["result"].display_name)

# 正在打的那件的显示名（"铁甲"）；没在打返回 ""
func smith_name() -> String:
	var job := smith_top()
	if job.is_empty():
		return ""
	return smith_item_name(int(job["idx"]))

# 排队的清单文案："皮甲 0/2, 锁链甲 0/2"（队首在前）
func smith_queue_text() -> String:
	var parts: Array = []
	for job in smith_queue:
		parts.append("%s %d/%d" % [smith_item_name(int(job.get("idx", -1))),
			int(job.get("work", 0)), int(job.get("need", 0))])
	return ", ".join(parts)

# 玩家身边铁匠铺的等级（0 = 不在旁边；编辑器/无场景时也是 0）
func near_blacksmith_lv() -> int:
	var g := Engine.get_main_loop()
	if g == null or not (g is SceneTree):
		return 0
	var game: Node = (g as SceneTree).get_first_node_in_group("game")
	if game == null or not game.has_method("player_blacksmith_level"):
		return 0
	return int(game.call("player_blacksmith_level"))

func can_craft_smith(idx: int) -> bool:
	if idx < 0 or idx >= SMITH_RECIPES.size():
		return false
	var recipe: Dictionary = SMITH_RECIPES[idx]
	if near_blacksmith_lv() < int(recipe["lv"]):
		return false
	for c in recipe["costs"]:
		if not _have(c["item"], int(c["count"])):
			return false
	return true

# 点配方 = 把这一件排进队尾：扣清材料，记进制造中（不出货——出货在夜里人工攒够时）。
func craft_smith(idx: int) -> bool:
	if not can_craft_smith(idx):
		return false
	var recipe: Dictionary = SMITH_RECIPES[idx]
	for c in recipe["costs"]:
		Inventory.remove_item(c["item"], int(c["count"]))
	smith_queue.append({"idx": idx, "work": 0, "need": maxi(1, int(recipe["labor"]))})
	smith_changed.emit()
	return true

# 每晚推进：heads = 今晚派去打铁的有效人手（人数 + 建造加成）。
# 人工先喂队首：攒够出货，**多出来的顺延给下一件**，一直喂下去直到人工用完或队空。
# 返回今晚出件的名字列表（["皮甲", "锁链甲"]；空 = 今晚没出件）。
func add_smith_work(heads: int) -> Array:
	var made: Array = []
	if heads <= 0 or smith_queue.is_empty():
		return made
	var pool := heads
	while pool > 0 and not smith_queue.is_empty():
		var job: Dictionary = smith_queue[0]
		var need := maxi(1, int(job["need"]))
		var got := int(job["work"]) + pool
		if got < need:
			job["work"] = got
			break                       # 人工用完了，明晚接着打
		pool = got - need               # 顺延给下一件的人工
		var idx := int(job["idx"])
		smith_queue.remove_at(0)
		var result: ItemData = SMITH_RECIPES[idx]["result"]
		Inventory.add_item(result, int(SMITH_RECIPES[idx]["count"]))
		made.append(String(result.display_name))
		crafted.emit(result)
	smith_changed.emit()
	return made

# 缺什么：need = -1 不在铁匠铺旁 / -2 铁匠铺等级不够；其余是缺材料
# （e41c: 不再有「已经在打」这种拦法 —— 排在队尾就行）
func missing_smith(idx: int) -> Array:
	var out: Array = []
	if idx < 0 or idx >= SMITH_RECIPES.size():
		return out
	var recipe: Dictionary = SMITH_RECIPES[idx]
	var lv := near_blacksmith_lv()
	if lv == 0:
		out.append({"item": null, "have": 0, "need": -1})
		return out
	if lv < int(recipe["lv"]):
		out.append({"item": null, "have": lv, "need": -2})
		return out
	for c in recipe["costs"]:
		var have: int = Inventory.count_item(c["item"])
		var need: int = int(c["count"])
		if have < need:
			out.append({"item": c["item"], "have": have, "need": need})
	return out
