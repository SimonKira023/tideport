# tools/_probe_newgame.gd —— 开始界面的三条路，端到端验一遍
#
# 验的是一整条链：开始新档 -> 真是第 1 年第 1 天 -> 改点东西存上 -> 再开一次新档要干净
# -> 加载刚才那档要能读回来。
#
# ❗探针先把三个存档路径指到 user://_probe_save/... 临时目录。
#   不这么做的话：save_game() 会覆盖玩家真正的 savegame.json 和每日快照，
#   跑一次测试就把人家的档毁了。
extends Node

const BASE := "user://_probe_save"
const SLOT := "探针测试档"

var _ok := 0
var _bad := 0


func _ready() -> void:
	await get_tree().process_frame
	SaveManager.save_path = BASE + "/savegame.json"
	SaveManager.history_dir = BASE + "/history"
	SaveManager.slot_dir = BASE + "/slots"
	SaveManager.enabled = true
	_wipe(BASE)

	# ---------- 1. 像开始界面按「开始」那样开新档 ----------
	SaveManager.begin_new_game(SLOT)
	var game: Node = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 6:
		await get_tree().process_frame

	print("\n===== 1. 新档开局状态 =====")
	_chk(TimeManager.year == 1 and TimeManager.season == 0 and TimeManager.day == 1,
		"从第 1 年第 1 天开始 (现在是 第%d年 季%d 第%d天)" % [
			TimeManager.year, TimeManager.season, TimeManager.day])
	_chk(TimeManager.hour == TimeManager.START_HOUR and TimeManager.time_running,
		"时间从早上 %d 点开始走" % TimeManager.START_HOUR)
	_chk(Wallet.money == Wallet.START_MONEY, "钱包 = 开局资金 %d (现在 %d)" % [
		Wallet.START_MONEY, Wallet.money])
	_chk(Slaves.count == 0, "一个伙伴都没有 (现在 %d)" % Slaves.count)
	_chk(Legion.level == 1 and Legion.exp == 0, "等级 1 / 经验 0 (现在 %d/%d)" % [
		Legion.level, Legion.exp])
	_chk(Voyage.dock_state == Voyage.DOCK_RUIN and Voyage.boat_count == 0,
		"码头是废墟、没有船 (状态 %d, 船 %d)" % [Voyage.dock_state, Voyage.boat_count])
	_chk(SaveManager.slot_name == SLOT, "当前档名 = %s" % SaveManager.slot_name)
	var given := 0
	for s in Inventory.hotbar:
		if s["item"] != null:
			given += 1
	_chk(given > 0, "发了新手物资 (%d 格有东西)" % given)

	# ---------- 2. 改点东西再存档 ----------
	print("\n===== 2. 改状态 -> 存档 =====")
	Wallet.add_money(999)
	Slaves.recruit_roster()
	TimeManager.day = 7
	TimeManager.season = 2
	var money_now: int = Wallet.money
	var saved := SaveManager.save_game(game)
	_chk(saved, "存盘成功")

	var slots := SaveManager.list_slots()
	_chk(slots.size() == 1, "档列表里有 1 个档 (现在 %d)" % slots.size())
	if slots.size() == 1:
		var e: Dictionary = slots[0]
		_chk(String(e["name"]) == SLOT, "档名对得上: %s" % e["name"])
		_chk(int(e["day"]) == 7 and int(e["season"]) == 2,
			"档里记着第 2 季第 7 天 (现在 季%d 第%d天)" % [e["season"], e["day"]])

	# ---------- 3. 回开始界面再开一次新档：必须干干净净 ----------
	print("\n===== 3. 再开一次新档 (上一把的数据不许漏进来) =====")
	SaveManager.begin_new_game("第二个档")
	SaveManager.reset_all()                      # game._ready 里这时候会做的事
	_chk(TimeManager.day == 1 and TimeManager.season == 0, "时间回到第 1 季第 1 天 (现在 季%d 第%d天)" % [
		TimeManager.season, TimeManager.day])
	_chk(Wallet.money == Wallet.START_MONEY, "钱包回到 %d (现在 %d)" % [
		Wallet.START_MONEY, Wallet.money])
	_chk(Slaves.count == 0, "伙伴清空 (现在 %d)" % Slaves.count)
	_chk(TimeManager.time_running, "时间在走 (不会被上一把的面板暂停栈卡住)")

	# ---------- 4. 加载刚才那一档 ----------
	print("\n===== 4. 加载旧档 =====")
	var path := String(slots[0]["path"]) if slots.size() == 1 else ""
	_chk(SaveManager.open_slot(path), "读档进 _pending")
	_chk(SaveManager.slot_name == SLOT, "档名跟着存档走: %s" % SaveManager.slot_name)
	SaveManager.apply_pending(game)
	_chk(Wallet.money == money_now, "钱读回来了 (存的 %d, 读的 %d)" % [money_now, Wallet.money])
	_chk(TimeManager.day == 7 and TimeManager.season == 2, "日期读回来了 (现在 季%d 第%d天)" % [
		TimeManager.season, TimeManager.day])
	_chk(Slaves.count == 1, "伙伴读回来了 (现在 %d)" % Slaves.count)

	# ---------- 5. 没有档的时候，列表是空的、不会崩 ----------
	print("\n===== 5. 空档列表 =====")
	SaveManager.delete_slot(path)
	_chk(SaveManager.list_slots().is_empty(), "删掉之后列表为空")

	print("\n========== 结果: %d 通过 / %d 失败 ==========" % [_ok, _bad])
	_wipe(BASE)          # 临时目录收干净，别在 user:// 里留垃圾
	await get_tree().process_frame
	get_tree().quit()


func _chk(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  [ok] %s" % msg)
	else:
		_bad += 1
		print("  [!!] %s" % msg)


func _wipe(dir: String) -> void:
	var abs_path := OS.get_user_data_dir() + "/" + dir.substr(7)
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path + "/" + String(f))
	for sub in d.get_directories():
		_wipe(dir + "/" + String(sub))
		DirAccess.remove_absolute(abs_path + "/" + String(sub))
