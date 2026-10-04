# save_manager.gd —— Autoload，名字：SaveManager
# 存档系统：只在每天早上 6 点自动存档（换日流程走完那一刻）+ 主页面读档。
#
# 设计（跟用户对过的方案）：
#   · 存档时间**有且只有每天早上 6 点**，只有两个调用点，都在 game.gd：
#       - 换日流程全部走完（advance_day 之后，此刻正好是新一天 6:00）
#       - 新档开出来（第 1 天 6:00，正好也是 6 点，顺手记一份让主页面立刻看得到）
#     ❗没有关窗兜底、也没有退回主页面时存 —— 白天中断 = 回到最近那个早上 6 点。
#   · 存档文件 user://savegame.json —— 纯文本，出问题能直接打开看。
#   · 这里只管「数据」的收集/写盘/读盘/应用；树和玩家的显示还原需要碰场景，
#     通过 game 节点的 rebuild_trees_from_save() / apply_player_state() 回调。
#
# 开始界面（scene/main_menu.gd）用得着的三个入口：
#   · begin_new_game("档名")  -> 开新档：清掉待读档、挂一个「重置请求」，
#                                 game._ready 看到就把所有系统打回第 1 年第 1 天
#   · open_slot(path)        -> 读某个具名档（挂进 _pending）
#   · list_slots()           -> 列出所有具名档给界面显示
#
# ❗两个坑（都在自检里验证过）：
#   1) crops 里存的是 ItemData 资源 -> 序列化时存 resource_path，读档时 load() 回来；
#   2) 字典的 key 是 Vector2i，JSON 只认字符串 key -> 存成 "x,y" 字符串，
#      读回来再解析；JSON 里所有数字都会变 float，应用时必须 int() 兜底。
extends Node

# —— 三个路径刻意写成 var 而不是 const ——
# 探针 / 自检可以临时把它们指到 user://_probe/... 之类的临时目录去跑，
# 这样测试怎么读写都不会碰到玩家真正的存档（真档案被测试覆盖过一次就找不回来了）。
var save_path := "user://savegame.json"

# —— 每日存档列表（设置页里能看到「第几天」的档）——
# 每次存档除 savegame.json（最新档，启动自动读）外，
# 再写一份按「年/季/天」命名的快照到 user://saves/；同一天重复存会覆盖。
var history_dir := "user://saves"
const HISTORY_KEEP := 10          # 最多留几天的快照，多了删最旧的

# —— 具名存档（开始界面里的「档」）——
# 一个档 = user://slots/<档名>.json，内容是完整存档 + 档名 + 存档时刻。
# ❗特意跟 user://saves/ 里那份「每日快照」**分开放**：快照是系统自动滚动的历史，
#   档是玩家自己起名、自己挑的东西，混在一个目录里列表界面就分不清谁是谁了。
var slot_dir := "user://slots"

# 自检脚本会把它关掉：自检会真的跑一遍睡觉换日流程，
# 不关的话测试过程会把真实存档覆盖掉、下次启动又把测试现场读回来 —— 全乱了。
var enabled := true

# 已从磁盘读出、等 game 场景就绪后再应用的存档
var _pending: Dictionary = {}

# 当前在玩哪一档（空 = 还没起名：睡觉只会更新 savegame.json 和每日快照）
var slot_name := ""
# 开始界面按了「开始」-> 挂着这个请求，等 game 场景就绪时把系统打回初始值
var _reset_request := false

# ❗这台机器上 user:// 被解析成相对路径（./Godot/app_userdata/<游戏名>），
#   FileAccess 能用，但 DirAccess.open("user://...") 会直接返回 null（Godot 对
#   相对 user 目录的坑）。列表/删除必须走 DirAccess，所以统一换成绝对路径。
var _user_base: String = OS.get_user_data_dir()

func _abs(path: String) -> String:
	if path.begins_with("user://"):
		return _user_base + "/" + path.substr(7)
	return path

# ❗这里原本挂着一个「关窗口兜底存档」（收到 NOTIFICATION_WM_CLOSE_REQUEST 就 save_game），
#   已经去掉 —— 存档时机有且只有**每天早上 6 点**那一次（game.gd 换日流程走完时写）。
#   所以白天直接叉掉游戏/退回主页面 = 回到最近那个早上 6 点，这是明确的设计决定，
#   别好心加回来；真要改，背包「设置」页那两行说明也得跟着改。

func _game_node() -> Node:
	return get_tree().get_first_node_in_group("game")

func has_save() -> bool:
	return FileAccess.file_exists(_abs(save_path))

func has_pending() -> bool:
	return not _pending.is_empty()

# ---------------- 具名存档（开始界面）----------------
# 档名要当文件名用，必须先洗一遍（问号、斜杠、冒号都是 Windows 的非法字符，
# 直接拿去开文件会静默失败）；validate_filename() 会把它们换成下划线。
func slot_path(n: String) -> String:
	var clean := n.strip_edges().validate_filename()
	if clean.is_empty():
		clean = "未命名"
	return "%s/%s.json" % [slot_dir, clean]

# 开始界面按「开始」：开出这一档，等 game 场景就绪时把所有系统重置成第 1 年第 1 天
func begin_new_game(n: String) -> void:
	slot_name = n.strip_edges()
	if slot_name.is_empty():
		slot_name = "未命名"
	_pending.clear()
	_reset_request = true

# 取一次「要重置」的请求（取完就清掉，免得读档又被重置一遍）
func take_reset_request() -> bool:
	var r := _reset_request
	_reset_request = false
	return r

# 开始界面按「加载」：把某个档读进 _pending，档名跟着存档里记的那份走
func open_slot(path: String) -> bool:
	if not load_from_file(path):
		return false
	slot_name = String(_pending.get("name", ""))
	_reset_request = false          # 读档是整份覆盖，不需要先重置
	return true

# 列出所有具名档，新的在前。每项: {path, name, year, season, day, hour, minute, stamp}
func list_slots() -> Array:
	var out: Array = []
	var dir := DirAccess.open(_abs(slot_dir))
	if dir == null:
		return out
	for fname in dir.get_files():
		if not String(fname).ends_with(".json"):
			continue
		var path := _abs(slot_dir) + "/" + String(fname)
		var pf := FileAccess.open(path, FileAccess.READ)
		if pf == null:
			continue
		var parsed = JSON.parse_string(pf.get_as_text())
		pf.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = parsed.get("time", {})
		out.append({
			"path": path,
			"name": String(parsed.get("name", String(fname).get_basename())),
			"year": int(t.get("year", 1)),
			"season": int(t.get("season", 0)),
			"day": int(t.get("day", 1)),
			"hour": int(t.get("hour", 6)),
			"minute": int(t.get("minute", 0)),
			"stamp": float(parsed.get("saved_at", 0.0)),
		})
	# 按存档时刻排（老档没记时刻就往后放，别让它插在最前面）
	out.sort_custom(func(a, b): return float(a["stamp"]) > float(b["stamp"]))
	return out

# 开始界面「删掉这一档」用
func delete_slot(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

# ---------------- 存 ----------------
func save_game(game: Node) -> bool:
	if not enabled or game == null:
		return false
	# 睡觉流程进行中（黑幕/结算面板开着）不做关窗兜底存档：
	# 那一刻的时间/位置是半成品，覆盖掉正常的睡前存档反而丢进度。
	var sleeping = game.get("_sleeping")
	if sleeping != null and bool(sleeping):
		return false
	var data := _collect(game)
	# ❗目录得自己保证存在：FileAccess.open(WRITE) 不会帮你建目录，路径只要缺一级
	#   就直接返回 null（写盘静默失败）。以前存档就在 user:// 根下、目录必然在，
	#   所以没暴露；路径一旦挪到子目录（探针/自检会挪）就必须补这一步。
	DirAccess.make_dir_recursive_absolute(_abs(save_path).get_base_dir())
	var f := FileAccess.open(_abs(save_path), FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败: %s" % save_path)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	_write_history(data)             # 同一份快照进每日列表（当自动备份，留最近几份）
	_write_slot(data)                # 有档名的话顺手更新那个具名档
	return true

# 把同一份存档写回「当前这一档」（开始界面里能按名字找到它）。
# 没档名就跳过 —— 直接从编辑器跑游戏时没有档名，只留 savegame.json 那份。
func _write_slot(data: Dictionary) -> void:
	if not enabled:                     # ❗自检/探针直接调这里也不能碰真档（35 节教训）
		return
	if slot_name.strip_edges().is_empty():
		return
	var err := DirAccess.make_dir_recursive_absolute(_abs(slot_dir))
	if err != OK:
		push_warning("档目录创建失败: %s" % slot_dir)
		return
	var f := FileAccess.open(_abs(slot_path(slot_name)), FileAccess.WRITE)
	if f == null:
		push_warning("档写入失败: %s" % slot_path(slot_name))
		return
	f.store_string(JSON.stringify(data))
	f.close()

# ---------------- 每日存档列表 ----------------
func _history_path() -> String:
	return "%s/y%d_s%d_d%02d.json" % [history_dir, TimeManager.year, TimeManager.season, TimeManager.day]

func _write_history(data: Dictionary) -> void:
	if not enabled:                     # ❗selftest 35 节会直接调这里 —— 没这道闸它就写进真档了
		return
	var err := DirAccess.make_dir_recursive_absolute(_abs(history_dir))
	if err != OK:
		push_warning("存档目录创建失败: %s" % history_dir)
		return
	var f := FileAccess.open(_abs(_history_path()), FileAccess.WRITE)
	if f == null:
		push_warning("每日存档写入失败: %s" % _history_path())
		return
	f.store_string(JSON.stringify(data))
	f.close()
	_prune_history()

# 快照超过 HISTORY_KEEP 份时删最旧的。
# ❗enabled = false（自检）时直接跳过：测试写的假快照绝不能碰真实旧档。
func _prune_history() -> void:
	if not enabled:
		return
	var entries := list_saves()
	for i in range(HISTORY_KEEP, entries.size()):
		DirAccess.remove_absolute(String(entries[i]["path"]))

# 列出每日快照（新 -> 旧）。每项: {path, year, season, day, hour, minute}
func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(_abs(history_dir))
	if dir == null:
		return out
	for fname in dir.get_files():
		if not String(fname).ends_with(".json"):
			continue
		var path := _abs(history_dir) + "/" + String(fname)
		var pf := FileAccess.open(path, FileAccess.READ)
		if pf == null:
			continue
		var parsed = JSON.parse_string(pf.get_as_text())
		pf.close()
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("time"):
			continue
		var t: Dictionary = parsed["time"]
		var year := int(t.get("year", 1))
		var season := int(t.get("season", 0))
		var day := int(t.get("day", 1))
		var hour := int(t.get("hour", 6))
		out.append({
			"path": path,
			"year": year, "season": season, "day": day,
			"hour": hour, "minute": int(t.get("minute", 0)),
			# 排序键：年 > 季 > 天 > 时（同一份快照分钟无所谓）
			"key": year * 1000000 + season * 10000 + day * 100 + hour,
		})
	out.sort_custom(func(a, b): return int(a["key"]) > int(b["key"]))
	return out

# 从指定快照文件读进 _pending（随后 apply_pending 应用）
func load_from_file(path: String) -> bool:
	var f := FileAccess.open(_abs(path), FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("快照文件坏了: %s" % path)
		return false
	_pending = parsed
	return true

# ---------------- 读 ----------------
func load_into_pending() -> bool:
	var f := FileAccess.open(_abs(save_path), FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档文件坏了,按新档处理")
		return false
	_pending = parsed
	return true

func apply_pending(game: Node) -> bool:
	if _pending.is_empty():
		return false
	_apply(_pending)
	_pending.clear()
	# e52: 读档时 TimeManager.season 是 _apply 里改的, 换季信号不会响 —— 四季地表得手动重刷一次,
	# 否则读一份秋天的存档, 岛上还铺着春草（game._ready 早于 _apply 跑, 那会儿读到的还是旧季节）。
	if game != null and game.has_method("_apply_season_terrain"):
		game._apply_season_terrain()
	# e21v2: 读档后 BGM 归位 —— 主菜单那首 fixed menu.ogg 让位给岛上池。
	# _apply 已把 TimeManager 恢复成存档时刻, 夜/昼/季节池由 _resolve_key 按时刻解析。
	# (原先只有 reset_all —— 开新档路径 —— 有这行, 从主页加载存档就会一直播主菜单曲。)
	Audio.set_scene_bgm("island")
	return true

# ---------------- 收集当前状态 ----------------
func _collect(game: Node) -> Dictionary:
	var slots: Array = []
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		slots.append({
			"path": it.resource_path if it != null else "",
			"count": int(s["count"]),
		})
	var crops: Array = []
	for c in Farm.crops.keys():
		var cv: Vector2i = c
		var cr: Dictionary = Farm.crops[cv]
		var seed: ItemData = cr["seed"]
		crops.append({
			"cell": _enc_cell(cv),
			"seed": seed.resource_path if seed != null else "",
			"stage": int(cr["stage"]),
			"days": int(cr["days"]),
			"dead": bool(cr.get("dead", false)),
		})
	var trees: Array = []
	for c in Trees.trees.keys():
		var tv: Vector2i = c
		var t: Dictionary = Trees.trees[tv]
		trees.append({
			"cell": _enc_cell(tv),
			"stage": int(t["stage"]),
			"days": int(t["days"]),
			"hp": int(t["hp"]),
			"variant": int(t["variant"]),
		})
	var rocks: Array = []
	for c in OreVein.rocks.keys():
		var rv: Vector2i = c
		var r: Dictionary = OreVein.rocks[rv]
		rocks.append({
			"cell": _enc_cell(rv),
			"kind": int(r["kind"]),
			"hp": int(r["hp"]),
			"variant": int(r["variant"]),
		})
	var stations: Array = []
	for c in Structures.stations.keys():
		var sv: Vector2i = c
		var s: Dictionary = Structures.stations[sv]
		stations.append({
			"cell": _enc_cell(sv),
			"kind": String(s["kind"]),
			"state": String(s["state"]),
			"level": int(s.get("level", 1)),
			"chickens": int(s.get("chickens", 0)),
			"eggs": int(s.get("eggs", 0)),
			"honey": int(s.get("honey", 0)),        # e44b 蜂箱里攒的蜜
			"variant": int(s.get("variant", 0)),    # e44 同伴小屋用的第几款外形
			# e45 储物箱里存的东西：跟背包格一个规矩, ItemData 存 resource_path
			"items": _enc_chest_items(s.get("items", [])),
			# e49 畜棚/马厩里的牲口 {种类: 头数} 和攒下的畜产 {种类: 份数}
			# （纯字符串键的小字典, 不牵扯 ItemData, 直接原样写出去）
			"animals": (s.get("animals", {}) as Dictionary).duplicate(true),
			"produce": (s.get("produce", {}) as Dictionary).duplicate(true),
		})
	var ppos := Vector2.ZERO
	var indoors := false
	var player := _player_node(game)
	if player != null:
		ppos = player.global_position
		indoors = bool(player.get("indoors"))
	return {
		"version": 1,
		"name": slot_name,                                   # 档名（开始界面的列表靠它显示）
		"saved_at": Time.get_unix_time_from_system(),        # 存档时刻（列表按它排序）
		"time": {
			"year": TimeManager.year,
			"season": TimeManager.season,
			"day": TimeManager.day,
			"hour": TimeManager.hour,
			"minute": TimeManager.minute,
			"running": TimeManager.time_running,
		},
		"money": Wallet.money,
		"water": Inventory.watering_can_water,
		# e8: 穿戴中的盔甲按 resource_path 存（跟 slots 一个规矩）
		"worn_armor": Inventory.worn_armor.resource_path if Inventory.worn_armor != null else "",
		"slots": slots,
		"tilled": _enc_cell_list(Farm.tilled),
		"watered": _enc_cell_list(Farm.watered),
		"crops": crops,
		"trees": trees,
		"rocks": rocks,
		"stations": stations,
		"floors": _enc_cell_map(Floor.floors),   # 格子 -> 铺装类型（0 木地板 / 1 小径）
		"slaves": {
			"count": Slaves.count,
			"list": Slaves.slaves.duplicate(true),
			"assignments": _enc_cell_map(Slaves.assignments),
			"done_today": _enc_cell_list(Slaves.done_today),
			"research_tech": Slaves.research_tech.duplicate(),
			"research_admin": Slaves.research_admin.duplicate(),
			"dock_crew": Slaves.dock_crew.duplicate(),
		"mine_crew": Slaves.mine_crew.duplicate(true),
		"craft_crew": Slaves.craft_crew.duplicate(),
		},
		"site": {} if Structures.site.is_empty() else {
			# 工地（盖到一半的建筑）：anchor 是 Vector2i -> 存成字符串
			"kind": String(Structures.site["kind"]),
			"anchor": _enc_cell(Vector2i(Structures.site["anchor"])),
			"work": int(Structures.site.get("work", 0)),
			"need": int(Structures.site.get("need", 0)),
		},
		# 打铁队列（铁匠铺排着队的东西，队首在前）
		"smith_queue": [] if Crafting.smith_queue.is_empty() else _enc_smith_queue(),
		"research": Research.to_dict(),
		"voyage": Voyage.to_dict(),
		"nations": Nations.to_dict(),
		"player": {"x": ppos.x, "y": ppos.y, "indoors": indoors},
		"fish_journal": FishJournal.collect_data(),   # 钓鱼图鉴（名字 -> 累计条数）
		"quests": Quests.to_dict(),                   # 任务栏状态（指引 + 里程碑）
		"marriage": Marriage.to_dict(),               # 婚恋进度（心里话段数 / 妻子）
		"cutscene_seen": Cutscenes.seen_list(),       # e42: 放过的剧情过场（不重播）
	}

# ---------------- 应用存档 ----------------
# 前提：game._ready 已把地形/图层/树都按「新档」摆好，这里把数据整个换成存档里的，
# 再靠各系统已有的信号把显示层重画一遍（soil/floor/crop 都只听信号，不用单独伺候）。
func _apply(data: Dictionary) -> void:
	# 各系统逐字段还原时会发信号（钱包/好感等），Quests 的里程碑检查要先挂起，
	# 不然半新半旧的混装状态会被误判成「达成」白给一份奖。
	Quests.suspend_checks()
	# —— 时间 ——
	var t: Dictionary = data.get("time", {})
	TimeManager.year = int(t.get("year", 1))
	TimeManager.season = int(t.get("season", 0))
	TimeManager.day = int(t.get("day", 1))
	TimeManager.hour = int(t.get("hour", TimeManager.START_HOUR))
	TimeManager.minute = int(t.get("minute", 0))
	TimeManager.time_running = bool(t.get("running", true))
	TimeManager._acc = 0.0

	# —— 钱 / 水 ——
	Wallet.money = int(data.get("money", Wallet.money))
	Wallet.money_changed.emit(Wallet.money)
	Inventory.watering_can_water = int(data.get("water", Inventory.watering_can_water))
	Inventory.water_changed.emit()

	# —— 背包（快捷栏 6 + 背包 24，缺的格子补空）——
	var saved_slots: Array = data.get("slots", [])
	Inventory.hotbar.clear()
	Inventory.backpack.clear()
	for i in Inventory.HOTBAR_SIZE + Inventory.BACKPACK_SIZE:
		var sd: Dictionary = saved_slots[i] if i < saved_slots.size() else {}
		var it: ItemData = null
		var p := String(sd.get("path", ""))
		if p != "":
			it = load(p) as ItemData
		var slot := {"item": it, "count": int(sd.get("count", 0))}
		if i < Inventory.HOTBAR_SIZE:
			Inventory.hotbar.append(slot)
		else:
			Inventory.backpack.append(slot)
	# e8: 恢复穿戴中的盔甲（背包格都就位后再指过去）
	var worn_path := String(data.get("worn_armor", ""))
	if worn_path != "":
		Inventory.worn_armor = load(worn_path) as ItemData
	else:
		Inventory.worn_armor = null
	Inventory.inventory_changed.emit()

	# —— 农田：先 clear_all（发 tilled_removed 清掉旧贴图），再灌数据、逐格发信号重画 ——
	Farm.clear_all()
	for c in _dec_cell_list(data.get("tilled", [])):
		Farm.tilled[c] = true
	for c in _dec_cell_list(data.get("watered", [])):
		Farm.watered[c] = true
	for cr in data.get("crops", []):
		var cell := _dec_cell(String(cr.get("cell", "")))
		var seed: ItemData = null
		var sp := String(cr.get("seed", ""))
		if sp != "":
			seed = load(sp) as ItemData
		if seed != null:
			Farm.crops[cell] = {"seed": seed, "stage": int(cr.get("stage", 0)), "days": int(cr.get("days", 0)), "dead": bool(cr.get("dead", false))}
	for c in Farm.tilled.keys():
		Farm.tilled_added.emit(c)
	for c in Farm.watered.keys():
		Farm.soil_changed.emit(c)
	for c in Farm.crops.keys():
		Farm.crop_changed.emit(c)

	# —— 树：数据在这换，显示节点让 game 重建（程序化撒的树要先拆掉）——
	Trees.trees.clear()
	for tr in data.get("trees", []):
		Trees.trees[_dec_cell(String(tr.get("cell", "")))] = {
			"stage": int(tr.get("stage", 0)),
			"days": int(tr.get("days", 0)),
			"hp": int(tr.get("hp", Trees.CHOPS_TO_FELL)),
			"variant": int(tr.get("variant", 0)),
		}
	var game := _game_node()
	if game != null and game.has_method("rebuild_trees_from_save"):
		game.rebuild_trees_from_save()

	# —— 岩石/矿石露头：同树的套路，显示节点让 game 重建 ——
	OreVein.rocks.clear()
	for rr in data.get("rocks", []):
		OreVein.rocks[_dec_cell(String(rr.get("cell", "")))] = {
			"kind": int(rr.get("kind", 0)),
			"hp": int(rr.get("hp", OreVein.ROCK_HP)),
			"variant": int(rr.get("variant", 0)),
		}
	if game != null and game.has_method("rebuild_rocks_from_save"):
		game.rebuild_rocks_from_save()

	# —— 工作台/熔炉/铁匠铺/水井/鸡舍/路灯/同伴小屋/蜂箱：同上，显示节点让 game 重建 ——
	# 熔炼中的恢复成 smelting（t 归零重烧，材料不白扣）；ready 的直接可取
	Structures.reset()
	for ss in data.get("stations", []):
		var scell := _dec_cell(String(ss.get("cell", "")))
		var skind := String(ss.get("kind", ""))
		if skind != Structures.KIND_WORKBENCH and skind != Structures.KIND_FURNACE \
				and skind != Structures.KIND_BLACKSMITH and skind != Structures.KIND_WELL \
				and skind != Structures.KIND_COOP and skind != Structures.KIND_LAMP \
				and skind != Structures.KIND_HUT and skind != Structures.KIND_HIVE \
				and skind != Structures.KIND_CHEST and not Structures.is_farm_kind(skind):
			continue
		Structures.place(scell, skind, true)   # e32: 读档重建, 不触发 build_first
		var slv := int(ss.get("level", 1))
		if slv > 1:
			Structures.stations[scell]["level"] = slv
		var sst := String(ss.get("state", Structures.ST_IDLE))
		if sst == Structures.ST_READY or sst == Structures.ST_SMELTING:
			Structures.stations[scell]["state"] = sst
		if skind == Structures.KIND_COOP:
			Structures.stations[scell]["chickens"] = int(ss.get("chickens", 0))
			Structures.stations[scell]["eggs"] = int(ss.get("eggs", 0))
		elif skind == Structures.KIND_HIVE:
			Structures.stations[scell]["honey"] = int(ss.get("honey", 0))
		elif skind == Structures.KIND_HUT:
			# ❗外形要按存档里的来: place 已经按「当前有几座」给了默认款, 这里覆盖回去 ——
			#   否则拆掉中间一座再读档, 后面的小屋会集体改脸。
			Structures.stations[scell]["variant"] = int(ss.get("variant", 0))
		elif skind == Structures.KIND_CHEST or skind == Structures.KIND_SILO:
			# e45 储物箱里存的东西（每项 {path, count} -> 还原成 ItemData 格）
			# e49: 筒仓走同一套（structures.gd 里两者都算容器）
			Structures.stations[scell]["items"] = _dec_chest_items(ss.get("items", []))
		elif skind == Structures.KIND_BARN or skind == Structures.KIND_STABLE:
			# e49 畜棚/马厩：牲口和没来得及收的畜产（JSON 读回来是浮点数,
			#   取用那侧一律 int(...), 所以原样存回去就行）
			var an: Dictionary = ss.get("animals", {})
			var pd: Dictionary = ss.get("produce", {})
			Structures.stations[scell]["animals"] = an.duplicate(true)
			Structures.stations[scell]["produce"] = pd.duplicate(true)
	if game != null and game.has_method("rebuild_stations_from_save"):
		game.rebuild_stations_from_save()

	# —— 工地（盖到一半的建筑）：锚点是 Vector2i，读回来再解析 ——
	# ❗放在 stations 之后：rebuild_stations 不碰 site，互不干扰。
	#   恢复完发 site_changed，game 的脚手架节点跟着摆出来。
	Structures.site = {}
	var sd: Dictionary = data.get("site", {})
	if not sd.is_empty():
		Structures.site = {
			"kind": String(sd.get("kind", "")),
			"anchor": _dec_cell(String(sd.get("anchor", "-99999,-99999"))),
			"work": int(sd.get("work", 0)),
			"need": maxi(1, int(sd.get("need", 1))),
		}
	Structures.site_changed.emit()

	# —— 打铁队列（铁匠铺排着队的东西）——
	Crafting.smith_queue = []
	for e in data.get("smith_queue", []):
		var job: Dictionary = e
		Crafting.smith_queue.append({
			"idx": int(job.get("idx", -1)),
			"work": int(job.get("work", 0)),
			"need": maxi(1, int(job.get("need", 1))),
		})
	# 旧档（e41c 之前）只有单件 "smith_job"：换算成只有一件的队列
	var sj_old: Dictionary = data.get("smith_job", {})
	if Crafting.smith_queue.is_empty() and not sj_old.is_empty():
		Crafting.smith_queue.append({
			"idx": int(sj_old.get("idx", -1)),
			"work": int(sj_old.get("work", 0)),
			"need": maxi(1, int(sj_old.get("need", 1))),
		})
	Crafting.smith_changed.emit()

	# —— 铺装（地板/小径）——
	# 新档: [{cell, v: 类型}]；旧档: 纯格子字符串数组（按木地板读回）
	Floor.clear_all()
	for e in data.get("floors", []):
		if e is Dictionary:
			Floor.place(_dec_cell(String(e.get("cell", ""))), int(e.get("v", Floor.KIND_WOOD)))
		else:
			Floor.place(_dec_cell(String(e)))

	# —— 伙伴 ——
	var sl: Dictionary = data.get("slaves", {})
	var list: Array = sl.get("list", [])
	Slaves.slaves = list
	Slaves.count = list.size()
	Slaves.backfill_combat()               # 旧档没有战斗字段 -> 补默认值
	Slaves.assignments.clear()
	Slaves.done_today.clear()
	for am in sl.get("assignments", []):
		Slaves.assignments[_dec_cell(String(am.get("cell", "")))] = int(am.get("v", 0))
	for dm in sl.get("done_today", []):
		Slaves.done_today[_dec_cell(String(dm))] = true   # done_today 是格子数组，不是映射
	# expedition 已取消存档：全员自动出海，backfill_combat 里会 _sync_expedition 同步
	Slaves.research_tech.clear()
	for i in sl.get("research_tech", []):
		Slaves.research_tech.append(int(i))
	Slaves.research_admin.clear()
	for i in sl.get("research_admin", []):
		Slaves.research_admin.append(int(i))
	Slaves.dock_crew.clear()
	for i in sl.get("dock_crew", []):
		Slaves.dock_crew.append(int(i))
	Slaves.mine_crew.clear()
	for w in sl.get("mine_crew", []):
		Slaves.mine_crew.append({
			"i": int(w.get("i", -1)),
			"job": String(w.get("job", "stone")),
		})
	Slaves.craft_crew.clear()
	for i in sl.get("craft_crew", []):
		Slaves.craft_crew.append(int(i))
	Slaves.changed.emit()          # game._sync_slaves 会照着人数建/删伙伴节点

	# —— 科技树 / 行政树 / 政策卡 ——（必须在伙伴之后：点数按派去研究的人数算）
	Research.from_dict(data.get("research", {}))

	# —— 船 / 大地图旅行状态 ——
	Voyage.from_dict(data.get("voyage", {}))

	# —— 国家好感 / 协议 ——
	Nations.from_dict(data.get("nations", {}))

	# —— 玩家位置 + 室内外 ——
	var pd: Dictionary = data.get("player", {})
	if game != null and pd.has("x") and game.has_method("apply_player_state"):
		game.apply_player_state(
			Vector2(float(pd.get("x", 0.0)), float(pd.get("y", 0.0))),
			bool(pd.get("indoors", false)))

	# —— 钓鱼图鉴 ——
	FishJournal.apply_data(data.get("fish_journal", {}))

	# —— 任务栏（指引进度 + 里程碑）——
	Quests.from_dict(data.get("quests", {}))
	Quests.resume_checks()
	# —— 婚恋进度 ——
	Marriage.from_dict(data.get("marriage", {}))

	# —— 剧情过场（放过的不再重播）——
	Cutscenes.apply_seen(data.get("cutscene_seen", []))

# ---------------- 开新档：把所有系统打回初始值 ----------------
# ❗必须**逐个显式**重置：autoload 是跨场景常驻的，从玩过的档退回开始界面再开新档时，
#   上一把的数据会原样漏进新档（钱包还是上把的钱、背包里还躺着上把的种子）。
#   重置动作放在各个系统自己的文件里（reset_for_new_game），不是在这儿硬改它们的字段 ——
#   谁加字段谁顺手改自己那个函数，比在一个"什么都懂"的大函数里漏一行靠谱得多。
func reset_all() -> void:
	# 重置途中各系统会发信号（钱包/好感等），里程碑检查先挂起防误发奖；
	# game.gd 随后会调 Quests.reset_all() 把任务栏整个清零。
	Quests.suspend_checks()
	TimeManager.reset_for_new_game()     # 第 1 年第 1 天早上 6 点，时间开始流动
	Wallet.reset_for_new_game()
	Inventory.reset_for_new_game()
	Farm.clear_all()
	Trees.reset()
	OreVein.reset()
	Structures.reset()
	Floor.clear_all()
	Crafting.reset()          # 打铁中的项目一并清掉（铁匠铺材料都发了 reset，进度没意义）
	Slaves.reset_for_new_game()
	Legion.reset_for_new_game()
	Research.reset()
	Voyage.reset_for_new_game()
	Nations.reset_for_new_game()
	FishJournal.reset_for_new_game()     # 钓鱼图鉴清零（进度不跨新档）
	Marriage.reset()                     # 婚恋进度清零（新档重新恋爱）
	Cutscenes.reset_for_new_game()       # e42: 剧情过场记录清零（新档从序章重看一遍）
	Audio.set_scene_bgm("island")              # 万一上一把停在海图/战场，BGM 也归位

func _player_node(game: Node) -> Node2D:
	if game == null:
		return null
	return game.get_tree().get_first_node_in_group("player") as Node2D

# ---------------- Vector2i <-> JSON ----------------
func _enc_cell(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

# e45 储物箱里存的东西：每格 {item: ItemData, count: int} -> {path, count}
# （ItemData 存 resource_path, 跟背包格/crops 一个规矩；读回来 load() 吃掉坏路径）
func _enc_chest_items(arr: Array) -> Array:
	var out: Array = []
	for e in arr:
		var d: Dictionary = e
		var it: ItemData = d.get("item", null)
		if it == null:
			continue
		out.append({"path": it.resource_path, "count": int(d.get("count", 0))})
	return out

func _dec_chest_items(arr: Array) -> Array:
	var out: Array = []
	for e in arr:
		var d: Dictionary = e
		var p := String(d.get("path", ""))
		if p == "" or not ResourceLoader.exists(p):
			continue
		var it := load(p) as ItemData
		if it == null:
			continue
		out.append({"item": it, "count": int(d.get("count", 0))})
	return out

# 打铁队列：队首在前，逐件存配方号 + 已投入人工 + 需要人工
func _enc_smith_queue() -> Array:
	var out: Array = []
	for job in Crafting.smith_queue:
		out.append({
			"idx": int(job.get("idx", -1)),
			"work": int(job.get("work", 0)),
			"need": int(job.get("need", 1)),
		})
	return out

func _dec_cell(s: String) -> Vector2i:
	var parts := s.split(",")
	if parts.size() != 2:
		return Vector2i(-99999, -99999)
	return Vector2i(int(parts[0]), int(parts[1]))

# 值全是 true 的集合（tilled/watered/floors/done_today）：存成格子字符串数组
func _enc_cell_list(d: Dictionary) -> Array:
	var out: Array = []
	for c in d.keys():
		out.append(_enc_cell(c))
	return out

func _dec_cell_list(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append(_dec_cell(String(s)))
	return out

# 有值的映射（assignments：格子 -> 工种号）：存成 {cell, v} 数组
func _enc_cell_map(d: Dictionary) -> Array:
	var out: Array = []
	for c in d.keys():
		out.append({"cell": _enc_cell(c), "v": int(d[c])})
	return out
