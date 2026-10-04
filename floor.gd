# floor.gd —— Autoload，名字：Floor
# 管理「铺装」的铺设状态：哪些格子铺了地板/小径，铺的是哪一种。
# 跟 Farm 一个思路：这里只管数据（Dictionary），显示交给 scene/floor_layer.gd，
# 铺设/收起动作交给 scene/player.gd。
extends Node

signal floor_changed(pos: Vector2i)   # 某格地板状态变了（铺上/拆掉/换类型）

const KIND_WOOD := 0         # 木地板（2 木头合成）
const KIND_PATH := 1         # 鹅卵石小径（1 石头合成）
# 拆掉时返还哪种物品，按类型对号入座
const KIND_ITEM := {
	KIND_WOOD: preload("res://item/wood_floor.tres"),
	KIND_PATH: preload("res://item/stone_path.tres"),
}

var floors := {}          # {Vector2i: int(KIND_*)} 已铺装的格子；旧档里的 true 会按木地板读回

# ---------------- 查询 ----------------
func is_floored(pos: Vector2i) -> bool:
	return floors.has(pos)

func kind_of(pos: Vector2i) -> int:
	return int(floors.get(pos, KIND_WOOD))

# ---------------- 铺 / 拆 ----------------
# 铺装。kind 缺省按木地板（兼容旧调用）。
func place(pos: Vector2i, kind: int = KIND_WOOD) -> bool:
	if floors.has(pos):
		return false
	floors[pos] = kind
	floor_changed.emit(pos)
	return true

# 拆掉铺装。返回 true 表示真的拆了。
func remove(pos: Vector2i) -> bool:
	if not floors.has(pos):
		return false
	floors.erase(pos)
	floor_changed.emit(pos)
	return true

# 拆掉所有铺装（重开存档用）
func clear_all() -> void:
	if floors.is_empty():
		return
	for pos in floors.keys():
		floor_changed.emit(pos)
	floors.clear()
