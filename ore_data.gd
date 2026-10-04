# ore_data.gd —— Autoload，名字：OreVein
# 管理全岛的岩石/矿石露头 + 矿井劳动力：
#   · 岩石：镐子敲 3 下碎，掉石头
#   · 铁矿露头：镐子敲 4 下碎，掉铁矿
#   · 矿井：岛上的一处建筑，派劳动力进去每天稳定产出石头/铁矿（不用自己挖）
# 跟 Trees 一个套路：这里只存数据 + 发信号，贴图/动画由 scene/rock_node.gd 画。
extends Node

signal rock_changed(cell: Vector2i)    # 某块岩石被敲了一下（晃动）
signal rock_removed(cell: Vector2i)    # 某块岩石碎了

enum { KIND_ROCK = 0, KIND_IRON = 1 }
enum { RESULT_MISS = 0, RESULT_HIT = 1, RESULT_BROKEN = 2 }

const ROCK_HP := 3             # 普通岩石要几镐子
const IRON_HP := 4             # 铁矿露头要几镐子
# 矿井劳动力：每人每天的产出（石头工/铁矿工）—— e15b: 提产配合矿石涨价, 别让下矿成死路
const MINE_STONE_PER_WORKER := 8
const MINE_IRON_PER_WORKER := 4

# cell -> {kind:int, hp:int, variant:int}
var rocks := {}

func _ready() -> void:
	# 岩石不过夜生长，不用订阅 new_day；矿井产出在 game 的换日流程里结算
	pass

# 重开地图（game._ready）时清空，防止加载两次场景后岩石翻倍
func reset() -> void:
	rocks.clear()

func has_rock(c: Vector2i) -> bool:
	return rocks.has(c)

# 有岩石的格子不能耕地 / 铺地板 / 种树
func is_blocked(c: Vector2i) -> bool:
	return rocks.has(c)

func kind_of(c: Vector2i) -> int:
	if not rocks.has(c):
		return -1
	return int(rocks[c].kind)

# 摆一块岩石。开局由 game 按种子撒；存档恢复也走这里
func place(c: Vector2i, kind: int, variant: int) -> bool:
	if rocks.has(c):
		return false
	rocks[c] = {
		"kind": kind,
		"hp": IRON_HP if kind == KIND_IRON else ROCK_HP,
		"variant": variant,
	}
	rock_changed.emit(c)
	return true

# 建筑动工时把格子上的岩石/铁矿直接推平：不补偿、不掉落，节点走消失动画
func clear_cell(c: Vector2i) -> void:
	if rocks.erase(c):
		rock_removed.emit(c)

# 敲一下。返回 {result, kind, stone, iron}（掉落数量，result == RESULT_BROKEN 时有效）
func hit(c: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	if not rocks.has(c):
		return {"result": RESULT_MISS, "kind": -1, "stone": 0, "iron": 0}
	var r: Dictionary = rocks[c]
	r.hp = int(r.hp) - 1
	if int(r.hp) > 0:
		rock_changed.emit(c)
		return {"result": RESULT_HIT, "kind": int(r.kind), "stone": 0, "iron": 0}
	var kind := int(r.kind)
	rocks.erase(c)
	rock_removed.emit(c)
	match kind:
		KIND_IRON:
			# 铁矿露头：1~2 块铁矿，顺手敲下 1 块石头
			var iron := 1 + (1 if rng.randf() < 0.35 else 0)
			return {"result": RESULT_BROKEN, "kind": kind, "stone": 1, "iron": iron}
		_:
			# 普通岩石：2~3 块石头
			return {"result": RESULT_BROKEN, "kind": kind, "stone": 2 + (1 if rng.randf() < 0.5 else 0), "iron": 0}
	return {"result": RESULT_MISS, "kind": -1, "stone": 0, "iron": 0}

# ---------------- 矿井产出 ----------------
# 每天早上结算矿井产出。crew 是 slaves.mine_crew（[{i:int, job:String}]）。
# 返回 {stone:int, iron:int}
func settle_mine_day(crew: Array, rng: RandomNumberGenerator) -> Dictionary:
	var stone := 0
	var iron := 0
	for w in crew:
		# 劳动树「园丁-农艺师-大地之友」加的是劳动力格子：下矿产出按这人提供的
		# 劳动力等比放大（基础额度 = cells_per_slave，加成翻倍产出也翻倍）。
		var mult := 1.0
		var s: Dictionary = Slaves.slave_at(int(w.get("i", -1)))
		if not s.is_empty():
			mult = float(Slaves.slave_cells(s)) / float(maxi(1, Slaves.cells_per_slave()))
		match String(w.get("job", "stone")):
			"iron":
				iron += int(round(float(MINE_IRON_PER_WORKER) * mult))
				if rng.randf() < 0.3:
					stone += 1            # 铁矿工顺手敲出点石头
			_:
				stone += int(round(float(MINE_STONE_PER_WORKER) * mult))
				if rng.randf() < 0.2:
					iron += 1             # 石头工偶尔筛出一点铁矿
	# e20: 采掘技能已删 —— 矿井产出只看派工人数, 不再吃技能加成
	if stone + iron > 0:
		Quests.complete("mine_first")   # e32: 矿井第一次有产出
	return {"stone": stone, "iron": iron}
