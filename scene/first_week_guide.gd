# 第一份收成的实时操作指引。只读现有农田、背包和来访状态, 不推进任务或改动存档。
extends RefCounted

const FIRST_STEPS := ["go_house", "buy_goblin", "till_first", "plant_first", "water_first", "harvest_first", "sell_first"]

static func describe(task: Dictionary, page: String = "") -> Dictionary:
	var id: String = String(task.get("id", ""))
	var result: Dictionary = {
		"title": String(task.get("title", "自由经营")),
		"caption": "当前目标", "action": "", "detail": String(task.get("desc", "今天也可以种田, 钓鱼, 或和伙伴聊聊天.")),
		"target": "", "cells": [], "page": page,
	}
	var index: int = FIRST_STEPS.find(id)
	if index >= 0:
		result["caption"] = "第一份收成 %d/%d" % [index + 1, FIRST_STEPS.size()]
	match id:
		"go_house":
			_instruction(result, "先去小屋领取工具", "靠近屋门按 F. 哥布林只赠送农具, 种子要到摊位购买.", "house")
		"buy_goblin":
			_instruction(result, "去桥头买当季种子", "靠近哥布林按 F, 先买 3 包当季作物种子就好. 买材料或食物不会完成购种指引.", "merchant")
		"explore_island":
			result["target"] = "merchant"
		"till_first":
			_instruction(result, "开出一小块田", _tool_hint("锄头") + "对身边空草地左键. 先开 3 块就好.")
		"plant_first":
			_instruction(result, "把种子播进耕地", _seed_hint() + "对空耕地左键.")
			result["cells"] = _empty_soil()
			if _seed_hint().begins_with("去哥布林"):
				result["target"] = "merchant"
				result["cells"] = []
		"water_first":
			_watering(result, _dry_crops())
		"harvest_first":
			_harvest(result)
		"sell_first", "sea_trade_first":
			result["target"] = "shipping"
			if id == "sell_first":
				_instruction(result, "把第一份收成卖出去", "售卖箱在小屋旁. 按 F 放入作物, 关箱后本地货款立即到账.", "shipping")
		"meet_partner":
			_partner(result)
		"sail_first":
			result["target"] = "dock"
		"mine_first":
			if Slaves.count == 0:
				_partner(result)
	if id.begins_with("rq_"):
		result["target"] = "campfire"
	return result

static func _instruction(result: Dictionary, action: String, detail: String, target: String = "") -> void:
	result["action"] = action
	result["detail"] = detail
	result["target"] = target

static func _tool_hint(name: String) -> String:
	for i in Inventory.HOTBAR_SIZE:
		var item: ItemData = Inventory.hotbar_item(i)
		if item != null and item.display_name == name:
			return "按 %d 选%s, " % [i + 1, name]
	return "按 B 把%s移到快捷栏, " % name

static func _seed_hint() -> String:
	for i in Inventory.HOTBAR_SIZE:
		var item: ItemData = Inventory.hotbar_item(i)
		if _usable_seed(item):
			return "按 %d 选%s, " % [i + 1, item.display_name]
	for slot: Dictionary in Inventory.slot_list():
		var item: ItemData = slot.get("item")
		if _usable_seed(item):
			return "按 B 把当季种子移到快捷栏, "
	return "去哥布林摊位买当季种子, 再选种子, "

static func _usable_seed(item: ItemData) -> bool:
	return item != null and item.type == "种子" and item.plant_on != "草地" \
		and (item.seasons.is_empty() or TimeManager.season in item.seasons)

static func _empty_soil() -> Array:
	var cells: Array = []
	for cell: Vector2i in Farm.tilled:
		if not Farm.has_crop(cell):
			cells.append(cell)
	return cells

static func _dry_crops() -> Array:
	var cells: Array = []
	for cell: Vector2i in Farm.crops:
		if not Farm.is_dead(cell) and not Farm.is_ready(cell) and not Farm.is_watered(cell):
			cells.append(cell)
	return cells

static func _watering(result: Dictionary, cells: Array) -> void:
	_instruction(result, "先照料今天的幼苗", _tool_hint("洒水壶") + "对幼苗左键. 漏浇只会暂停生长.")
	result["cells"] = cells
	if Inventory.is_can_empty():
		_instruction(result, "水壶空了, 先去补水", _tool_hint("洒水壶") + "对水面左键补满, 然后回来浇田.")
		result["cells"] = []

static func _harvest(result: Dictionary) -> void:
	var mature: Array = []
	var living: int = 0
	var remaining: int = 999
	for cell: Vector2i in Farm.crops:
		if Farm.is_dead(cell):
			continue
		living += 1
		if Farm.is_ready(cell):
			mature.append(cell)
		var crop: Dictionary = Farm.crops[cell]
		var seed: ItemData = crop["seed"]
		remaining = mini(remaining, seed.grow_days - int(crop["stage"]))
	if not mature.is_empty():
		_instruction(result, "收成成熟了, 去田里看看", "靠近成熟作物左键就能收获, 手里拿着工具也可以.")
		result["cells"] = mature
		return
	if living == 0:
		_instruction(result, "重新播下一颗种子", "枯苗可左键清掉. " + _seed_hint() + "对耕地左键, 再浇水.")
		if _seed_hint().begins_with("去哥布林"):
			result["target"] = "merchant"
		return
	var dry: Array = _dry_crops()
	if not dry.is_empty():
		_watering(result, dry)
		result["detail"] += " 今天还有 %d 块没浇." % dry.size()
		return
	if Slaves.count == 0 and Recruits.visitor():
		_partner(result)
		result["detail"] = "今天的田已浇好. " + String(result["detail"])
		return
	_instruction(result, "今天的田已照料好, 可以休息了", "还需 %d 次生长结算. 小屋床边按 F, 选择睡到明早. 也可以自由逛逛." % remaining, "house")

static func _partner(result: Dictionary) -> void:
	if Recruits.visitor():
		var candidate: Dictionary = Recruits.candidate()
		_instruction(result, "去篝火见见%s" % String(candidate.get("name", "来客")), "走近篝火按 F, 聊聊后邀请她加入. 相认不收金币.", "campfire")
	else:
		_instruction(result, "来客暂时离开了, 可以先休息", "来客会再次回到篝火, 不会永久错过. 先照料田地, 或回家睡到明早.", "house")
