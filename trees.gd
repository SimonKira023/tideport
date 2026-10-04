# trees.gd —— Autoload，名字：Trees
# 管理全岛的树：种树（树种子）、生长（幼苗 -> 小树 -> 成树）、砍树（掉木头 + 树种子）、
# 树桩（砍掉成树后留下，再敲几下才能清掉）。
# 跟 Farm 一个套路：这里只存数据 + 发信号，贴图/动画由 scene/tree_node.gd 画。
extends Node

signal tree_changed(cell: Vector2i)    # 某棵树变了（长了一阶 / 被砍了一斧 / 变成树桩）
signal tree_removed(cell: Vector2i)    # 某棵树彻底没了（树桩敲碎 / 幼苗被刨走）

# 树的四个阶段（tree_node 里按这个查图集帧号，别改数值）
enum { ST_SAPLING = 0, ST_YOUNG = 1, ST_MATURE = 2, ST_STUMP = 3 }

# 砍一下的结算结果
enum { RESULT_MISS = 0, RESULT_HIT = 1, RESULT_FELLED = 2 }

const GROW_SAPLING_DAYS := 2    # 幼苗 -> 小树
const GROW_YOUNG_DAYS := 3      # 小树 -> 成树
const CHOPS_TO_FELL := 4        # 砍倒一棵成树要几斧子
const STUMP_CHOPS := 2          # 树桩要再敲几下才清掉
const STUMP_WOOD := 1           # 敲碎树桩掉几根木头

# cell -> {stage:int, days:int, hp:int, variant:int}
var trees := {}

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

# 重开地图（game._ready）时清空，防止加载两次场景后树翻倍
func reset() -> void:
	trees.clear()

func has_tree(c: Vector2i) -> bool:
	return trees.has(c)

# 有树（含树桩）的格子不能耕地 / 铺地板 / 再种一棵
func is_blocked(c: Vector2i) -> bool:
	return trees.has(c)

func stage_of(c: Vector2i) -> int:
	if not trees.has(c):
		return -1
	return int(trees[c].stage)

# 种下一棵树苗。variant 是树的样子（0 樱桃 / 1 杏树），stage 一般用默认的幼苗，
# 开局撒树时会直接种出小树 / 成树。
func plant(c: Vector2i, variant: int, stage: int = ST_SAPLING) -> bool:
	if trees.has(c):
		return false
	trees[c] = {"stage": stage, "days": 0, "hp": CHOPS_TO_FELL, "variant": variant}
	tree_changed.emit(c)
	return true

# 建筑动工时把格子上的树（含树桩）直接推平：不补偿、不掉落，节点走 play_pop 消失
func clear_cell(c: Vector2i) -> void:
	if trees.erase(c):
		tree_removed.emit(c)

# 砍一下。返回 {result: 结果, wood: 掉几根木头, seeds: 掉几颗树种子}
#   · 幼苗/小树：一斧子刨掉，把树种还给你（等于移栽）
#   · 成树：CHOPS_TO_FELL 斧子砍倒 -> 掉木头 + 树种子，原地留个树桩
#   · 树桩：STUMP_CHOPS 下敲碎 -> 掉 1 根木头
# power = 一斧头削掉几点耐久。默认 1（没研究「精钢斧」时的基线），
# game.hit_tree 会传 Research.chop_power() 进来。
func hit(c: Vector2i, rng: RandomNumberGenerator, power := 1) -> Dictionary:
	if not trees.has(c):
		return {"result": RESULT_MISS, "wood": 0, "seeds": 0}
	var t: Dictionary = trees[c]
	var dmg := maxi(1, power)
	match int(t.stage):
		ST_SAPLING, ST_YOUNG:
			trees.erase(c)
			tree_removed.emit(c)
			return {"result": RESULT_FELLED, "wood": 0, "seeds": 1}
		ST_MATURE:
			t.hp = int(t.hp) - dmg
			if int(t.hp) > 0:
				tree_changed.emit(c)              # 树晃了一下，没倒
				return {"result": RESULT_HIT, "wood": 0, "seeds": 0}
			t.stage = ST_STUMP
			t.hp = STUMP_CHOPS
			t.days = 0
			tree_changed.emit(c)                  # game 那边先播倒树动画，再换树桩贴图
			var wood: int = 3 + rng.randi() % 3            # 3~5 根
			var seeds: int = 1 + (1 if rng.randf() < 0.25 else 0)
			return {"result": RESULT_FELLED, "wood": wood, "seeds": seeds}
		ST_STUMP:
			t.hp = int(t.hp) - dmg
			if int(t.hp) > 0:
				tree_changed.emit(c)
				return {"result": RESULT_HIT, "wood": 0, "seeds": 0}
			trees.erase(c)
			tree_removed.emit(c)
			return {"result": RESULT_FELLED, "wood": STUMP_WOOD, "seeds": 0}
	return {"result": RESULT_MISS, "wood": 0, "seeds": 0}

# 过夜生长：幼苗和小树每天长一点；成树不再长，树桩也不会自己发芽（要砍掉才清）
func _on_new_day(_day: int) -> void:
	var changed: Array = []
	for c in trees.keys():
		var t: Dictionary = trees[c]
		t.days = int(t.days) + 1
		match int(t.stage):
			ST_SAPLING:
				if int(t.days) >= GROW_SAPLING_DAYS:
					t.stage = ST_YOUNG
					t.days = 0
					changed.append(c)
			ST_YOUNG:
				if int(t.days) >= GROW_YOUNG_DAYS:
					t.stage = ST_MATURE
					t.days = 0
					t.hp = CHOPS_TO_FELL
					changed.append(c)
	for c in changed:
		tree_changed.emit(c)
