# fish_journal.gd —— 钓鱼图鉴 + 鱼种表（autoload）
#
# 记录「钓到过哪些鱼、各多少条」，存档走 SaveManager._collect/_apply，
# 新档归零走 reset_for_new_game。鱼种表带权重：越往后越稀有。
extends Node

# 鱼种表：path -> item tres，w = 抽中权重。
# ❗用 load 懒加载，不用 preload —— 避免 autoload 加载期和 item.tres 的加载时序打架。
const FISH_TABLE := [
	{"path": "res://item/perch.tres", "w": 40},
	{"path": "res://item/crayfish.tres", "w": 30},
	{"path": "res://item/pufferfish.tres", "w": 20},
	{"path": "res://item/starfish.tres", "w": 10},
]

var caught := {}   # display_name -> 累计钓到条数（图鉴）

# 按权重随机抽一条鱼（钓上来哪条由它决定）
func roll() -> ItemData:
	var total := 0
	for e in FISH_TABLE:
		total += int(e["w"])
	var r := randi() % total
	for e in FISH_TABLE:
		r -= int(e["w"])
		if r < 0:
			return load(String(e["path"])) as ItemData
	return null

# 记图鉴。返回 true = 新收录的鱼种（用来触发「入册」提示）
func record(it: ItemData) -> bool:
	if it == null:
		return false
	var first: bool = not caught.has(it.display_name)
	caught[it.display_name] = int(caught.get(it.display_name, 0)) + 1
	return first

func count_of(fish_name: String) -> int:
	return int(caught.get(fish_name, 0))

func kinds_caught() -> int:
	return caught.size()

func reset_for_new_game() -> void:
	caught.clear()

# ---------------- 存档接口（SaveManager 调） ----------------
func collect_data() -> Dictionary:
	var out := {}
	for k in caught.keys():
		out[String(k)] = int(caught[k])
	return out

func apply_data(d: Dictionary) -> void:
	caught.clear()
	for k in d.keys():
		caught[String(k)] = int(d[k])
