# floor.gd —— Autoload，名字：Floor
# 管理「铺装」的铺设状态：哪些格子铺了地板/小径，铺的是哪一种。
# 跟 Farm 一个思路：这里只管数据（Dictionary），显示交给 scene/floor_layer.gd，
# 铺设/收起动作交给 scene/player.gd。
extends Node

signal floor_changed(pos: Vector2i)   # 某格地板状态变了（铺上/拆掉/换类型）

const KIND_WOOD := 0         # 木板（1 木头锯成 2 块）
const KIND_PATH := 1         # 鹅卵石小径（1 石头合成）
# 2026-10-06 城镇铺装扩展：给「城镇建设」凑齐几种铺地（石板路/红砖路/砾石路）。
# ❗加新铺装只动三张表（KIND_ITEM / NAME_KIND / floor_layer 的渲染分流）+ 一件物品 tres
#   + 一条配方 + 一个图标 + 商店售价，别在 player.gd 里再写一串 if 名字 == xxx。
const KIND_SLAB := 2         # 石板路：大块切割石板（城市主干道那种）
const KIND_BRICK := 3        # 红砖路：错缝红砖（广场/码头那种）
const KIND_GRAVEL := 4       # 砾石路：碎石子（最便宜的临时路）
# 拆掉时返还哪种物品，按类型对号入座
const KIND_ITEM := {
	KIND_WOOD: preload("res://item/wood_floor.tres"),
	KIND_PATH: preload("res://item/stone_path.tres"),
	KIND_SLAB: preload("res://item/slab_path.tres"),
	KIND_BRICK: preload("res://item/brick_path.tres"),
	KIND_GRAVEL: preload("res://item/gravel_path.tres"),
}

# 铺装名字 -> 类型（唯一真相源）。player 铺地时按「手持物品的显示名」查这张表，
# 别再写 `if nm == "鹅卵石小径"` 那种散落硬编码 —— 加一种铺装就得改一堆地方。
const NAME_KIND := {
	"木板": KIND_WOOD,
	"鹅卵石小径": KIND_PATH,
	"石板路": KIND_SLAB,
	"红砖路": KIND_BRICK,
	"砾石路": KIND_GRAVEL,
}

# 按名字查类型（查不到返回 -1）
func kind_by_name(nm: String) -> int:
	return int(NAME_KIND.get(nm, -1))

# 这类铺装拆掉返还的物品（没有就 null）
func item_of(kind: int) -> ItemData:
	return KIND_ITEM.get(kind)

# 这类铺装的中文名（撬回提示用；查不到兜「地板」）
func display_of(kind: int) -> String:
	var it: ItemData = KIND_ITEM.get(kind)
	if it == null:
		return "地板"
	return it.display_name

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
