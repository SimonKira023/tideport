extends Node

signal inventory_changed
signal water_changed          # 水壶水量变化

const WATER_MAX := 10         # 一壶水能浇几次

# —— 背包结构 ——
# 快捷栏（hotbar）永远只有 6 格，摆在主界面底部一行，按 1~6 直接切换。
# 背包（backpack）是额外的储物格，只有打开背包面板时才看得到。
const HOTBAR_SIZE := 6
const BACKPACK_SIZE := 24      # 背包格数（4 行 x 6 列，跟快捷栏同宽好看）
const BACKPACK_COLS := 6

var hotbar: Array = []         # 6 格，每格 {item, count}
var backpack: Array = []       # 24 格，每格 {item, count}

# 洒水壶的水量（开局是满的）
var watering_can_water: int = WATER_MAX

# 穿戴中的盔甲（e8）：背包里某件「装备」被右键穿上后记在这里 ——
# 出战/battle 里的伙伴只披这一件甲；null = 都穿布衣（默认）。
# 道具本体还躺在背包格子里，这里只是个「指到哪件」的标记。
var worn_armor: ItemData = null

func _ready() -> void:
	reset_for_new_game()

# 开新档（也用于 _ready）：背包全空、水壶打满。
# 由 save_manager.reset_all 统一调用 —— 不退到开始界面开新档的话，
# 上一把的种子会原样留在新档的背包里。
func reset_for_new_game() -> void:
	hotbar.clear()
	backpack.clear()
	for i in HOTBAR_SIZE:
		hotbar.append(_empty_slot())
	for i in BACKPACK_SIZE:
		backpack.append(_empty_slot())
	watering_can_water = WATER_MAX
	worn_armor = null
	inventory_changed.emit()
	water_changed.emit()

func _empty_slot() -> Dictionary:
	return {"item": null, "count": 0}

# 水壶的**实际上限**：基础 10 次 + 科技「水轮」的加成。
# ❗所有判断「满没满」的地方都走这里，别直接读 WATER_MAX，
#   否则研究出水轮之后打水会被当成「已经满了」。
func water_max() -> int:
	# e14 农艺: 主干封顶 5 级每级 +2, 园丁分支每级再 +4 (e28f 比主干强)
	var farm := 2 * mini(Legion.skill_lv("farm"), Legion.SKILL_SPLIT)
	if Legion.branch_of("farm") == "a":
		farm += 4 * Legion.branch_lv("farm")
	return WATER_MAX + Research.water_bonus() + farm

func is_can_full() -> bool:
	return watering_can_water >= water_max()

func is_can_empty() -> bool:
	return watering_can_water <= 0

# 用掉一次水；没水返回 false
func use_water() -> bool:
	if watering_can_water <= 0:
		return false
	watering_can_water -= 1
	water_changed.emit()
	return true

# 在水井边打满
func fill_water() -> bool:
	if watering_can_water >= water_max():
		return false
	watering_can_water = water_max()
	water_changed.emit()
	return true

# ---------------- 取格 / 计数 ----------------
# 所有「可见格子」的线性索引：0~5 = 快捷栏，6~29 = 背包。
func slot_list() -> Array:
	return hotbar + backpack

func get_slot(linear_index: int) -> Dictionary:
	if linear_index < HOTBAR_SIZE:
		return hotbar[linear_index]
	return backpack[linear_index - HOTBAR_SIZE]

# 快捷栏第 i 格当前选中的道具（可能为 null）
func hotbar_item(i: int) -> ItemData:
	if i < 0 or i >= HOTBAR_SIZE:
		return null
	return hotbar[i]["item"]

func count_item(item: ItemData) -> int:
	var total := 0
	for s in hotbar + backpack:
		if s["item"] == item:
			total += s["count"]
	return total

# ---------------- 加入 ----------------
# 优先塞进已有的同类堆（先快捷栏、后背包），再找空格（同样先快捷栏、后背包）。
func add_item(item: ItemData, amount := 1) -> bool:
	if item == null:
		push_warning("add_item 收到 null 道具,已忽略")
		return false
	var order := hotbar + backpack
	for s in order:
		if s["item"] == item and s["count"] < item.max_stack:
			var add := mini(item.max_stack - s["count"], amount)
			s["count"] += add
			amount -= add
			if amount <= 0:
				inventory_changed.emit()
				return true
	for s in order:
		if s["item"] == null:
			var add := mini(item.max_stack, amount)
			s["item"] = item
			s["count"] = add
			amount -= add
			if amount <= 0:
				inventory_changed.emit()
				return true
	inventory_changed.emit()
	return amount <= 0

func remove_item(item: ItemData, amount := 1) -> void:
	# 从后往前删（背包优先），避免优先动快捷栏里的常用道具
	var order := backpack + hotbar
	for s in order:
		if s["item"] == item:
			var sub := mini(s["count"], amount)
			s["count"] -= sub
			amount -= sub
			if s["count"] <= 0:
				s["item"] = null
				s["count"] = 0
			if amount <= 0:
				break
	# 穿着的那件被卖掉 / 当晋升材料吃掉后就别再披着了
	if worn_armor != null:
		_validate_worn()
	inventory_changed.emit()

# 穿的那件已经不在背包/快捷栏里了 -> 自动脱下
func _validate_worn() -> void:
	for s in hotbar + backpack:
		if s["item"] == worn_armor:
			return
	worn_armor = null

# ---------------- 一键整理（e46） ----------------
# 背包的 hotbar/backpack 和储物箱的 items 长得一样（每格 {item, count}），
# 所以整理逻辑写成一份共用的：把一排格子重新堆一遍 ——
#   1) 同种道具先并叠（wood x50 + x30 合成 x80），每堆仍不超 max_stack
#   2) 工具排最前，后面按类型分组、同组按名字（见 ItemData.sort_rank）
#   3) 空格全部沉到最后
# ❗返回**新**的一排, 且是紧凑的（不留空格）：箱子那份本来就是紧凑的,
#   背包那边由 sort_all 自己按格数补空。
static func arrange(slots: Array) -> Array:
	var piles: Array = []
	for s in slots:
		var it: ItemData = (s as Dictionary).get("item", null)
		if it == null:
			continue
		var left := int((s as Dictionary).get("count", 0))
		for p in piles:                       # 先补进已有的同类堆
			if left <= 0:
				break
			if p["item"] == it and int(p["count"]) < it.max_stack:
				var add: int = mini(it.max_stack - int(p["count"]), left)
				p["count"] = int(p["count"]) + add
				left -= add
		while left > 0:                       # 还剩就另开堆（一件叠满可能开出好几堆）
			var add2: int = mini(it.max_stack, left)
			piles.append({"item": it, "count": add2})
			left -= add2
	piles.sort_custom(_pile_before)
	return piles

static func _pile_before(a: Dictionary, b: Dictionary) -> bool:
	var ia: ItemData = a["item"]
	var ib: ItemData = b["item"]
	var ra: int = ia.sort_rank()
	var rb: int = ib.sort_rank()
	if ra != rb:
		return ra < rb
	if ia.display_name != ib.display_name:
		return ia.display_name < ib.display_name
	return ia.resource_path < ib.resource_path   # 名字都一样时给个固定次序

# 背包一键整理：快捷栏 + 背包当一排 30 格整体排 ——
# 工具会落到最前面的快捷栏里，按 1~6 就能直接拿。
func sort_all() -> void:
	var merged := arrange(hotbar + backpack)
	while merged.size() < HOTBAR_SIZE + BACKPACK_SIZE:
		merged.append(_empty_slot())
	for i in HOTBAR_SIZE:
		hotbar[i] = merged[i]
	for i in BACKPACK_SIZE:
		backpack[i] = merged[HOTBAR_SIZE + i]
	inventory_changed.emit()

# ---------------- 移动 / 交换（背包面板里拖拽用）----------------
# 把 from 格的整堆移到 to 格；同种道具且可堆叠就合并，否则交换。
func move_slot(from: int, to: int) -> void:
	if from == to:
		return
	var a := get_slot(from)
	var b := get_slot(to)
	if a["item"] == null:
		return
	if b["item"] != null and a["item"] == b["item"]:
		# 合并：能塞多少塞多少
		var it: ItemData = a["item"]
		var can_hold: int = it.max_stack - b["count"]
		var move: int = mini(can_hold, a["count"])
		b["count"] += move
		a["count"] -= move
		if a["count"] <= 0:
			a["item"] = null
			a["count"] = 0
	else:
		# 交换
		var tmp_item = a["item"]
		var tmp_count = a["count"]
		a["item"] = b["item"]
		a["count"] = b["count"]
		b["item"] = tmp_item
		b["count"] = tmp_count
	inventory_changed.emit()
