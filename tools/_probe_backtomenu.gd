# tools/_probe_backtomenu.gd —— 「存档只在早上 6 点」+「读档入口搬到主页面」这两件事，
# 端到端验一遍。
#
# 验的链路：
#   1) 开新档 = 第 1 天早上 6 点 -> 立刻写一份档（不用等睡一觉，主页面马上看得到）
#   2) 白天怎么改都不写档（关窗兜底已删，退回主页面也不写）-> 档还停在早上 6 点那份
#   3) 换日流程走完 -> 档翻到第 2 天早上 6 点（唯一真正的存档时机）
#   4) 设置页：有「返回主页面」按钮，没有任何读档按钮（读档统一在主页面）
#   5) 从游戏内退回主页面再读档：上一把脏数据不许漏进读回来的那档
#
# ❗探针先把三个存档路径指到 user://_probe_btm/... 临时目录。
#   不这么做的话：save_game() 会覆盖玩家真正的 savegame.json 和每日快照，
#   跑一次测试就把人家的档毁了。
extends Node

const BASE := "user://_probe_btm"
const SLOT := "探针回主页面档"

var _ok := 0
var _bad := 0


func _ready() -> void:
	await get_tree().process_frame
	SaveManager.save_path = BASE + "/savegame.json"
	SaveManager.history_dir = BASE + "/history"
	SaveManager.slot_dir = BASE + "/slots"
	SaveManager.enabled = true
	_wipe(BASE)

	# ---------- 1. 开新档：立刻留一份「第 1 天早上 6 点」的档 ----------
	print("\n===== 1. 开新档立刻写档 =====")
	SaveManager.begin_new_game(SLOT)
	var game: Node = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 6:
		await get_tree().process_frame

	_chk(TimeManager.day == 1 and TimeManager.hour == TimeManager.START_HOUR
			and TimeManager.minute == 0,
		"新档 = 第 1 天早上 6 点整 (现在 %d:%02d)" % [TimeManager.hour, TimeManager.minute])
	var slots := SaveManager.list_slots()
	_chk(slots.size() == 1, "刚开的档马上出现在档列表里 (%d 个)" % slots.size())
	if slots.is_empty():
		print("\n========== 结果: %d 通过 / %d 失败 ==========" % [_ok, _bad])
		_wipe(BASE)
		get_tree().quit()
		return
	var path := String(slots[0]["path"])
	_chk(int(slots[0]["hour"]) == 6 and int(slots[0]["minute"]) == 0,
		"档里记的存档时刻 = 06:00 (%02d:%02d)" % [int(slots[0]["hour"]), int(slots[0]["minute"])])
	var stamped := FileAccess.get_file_as_string(path)

	# ---------- 2. 白天怎么折腾都不写档 ----------
	print("\n===== 2. 白天不写档 =====")
	TimeManager.hour = 15                 # 假装玩到了下午
	TimeManager.minute = 40
	Wallet.add_money(7777)
	# 手动敲一次「关窗口」通知：原来这个会兜底存一份，现在应该什么都不做
	if SaveManager.has_method("_notification"):
		SaveManager.call("_notification", Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_chk(not SaveManager.has_method("_notification"),
		"关窗兜底存档已经删掉（存档时机只有换日那一刻）")
	_chk(FileAccess.get_file_as_string(path) == stamped,
		"白天的改动没写进档里（档还停在早上 6 点那份）")

	# ---------- 3. 换日 -> 这才是唯一写档的时机 ----------
	print("\n===== 3. 换日写档 =====")
	TimeManager.advance_day()             # game._on_day_ended 结尾做的事之一
	_chk(TimeManager.day == 2 and TimeManager.hour == 6 and TimeManager.minute == 0,
		"换完日是第 2 天早上 6 点 (现在 第%d天 %d:%02d)" % [
			TimeManager.day, TimeManager.hour, TimeManager.minute])
	SaveManager.save_game(game)           # game.gd 换日流程结尾那一句
	slots = SaveManager.list_slots()
	_chk(slots.size() == 1 and int(slots[0]["day"]) == 2,
		"档翻到第 2 天 (%d 个档, 第 %d 天)" % [slots.size(), int(slots[0]["day"])])
	_chk(int(slots[0]["hour"]) == 6 and int(slots[0]["minute"]) == 0,
		"存档时刻还是 06:00 (%02d:%02d)" % [int(slots[0]["hour"]), int(slots[0]["minute"])])
	var money_saved: int = Wallet.money

	# ---------- 4. 设置页：只有「返回主页面」，没有读档 ----------
	print("\n===== 4. 设置页 =====")
	var bp: Control = load("res://backpack_ui.gd").new()
	add_child(bp)
	await get_tree().process_frame
	bp.open()
	bp.call("_select_module", "set")
	for i in 3:
		await get_tree().process_frame
	_chk(_has_button(bp, "返回主页面"), "设置页有「返回主页面」按钮")
	_chk(not _has_button(bp, "读档") and not _has_button(bp, "再点一次"),
		"设置页没有任何读档按钮了")
	_chk(not bp.has_method("_on_load_save_pressed") and not bp.has_method("_refresh_save_list"),
		"设置页里那套读档逻辑已经删干净")
	_chk(bp.has_method("_on_back_to_menu"), "回主页面的处理函数在")
	bp.close()
	bp.queue_free()
	await get_tree().process_frame

	# ---------- 5. 退回主页面再读档：脏数据不许漏进来 ----------
	print("\n===== 5. 退回主页面 -> 读档 =====")
	Wallet.add_money(5000)                # 退回前又赚了一笔（这份不该进档）
	TimeManager.day = 25
	Slaves.count = 0
	Slaves.slaves = []
	game.queue_free()                     # 相当于 change_scene 把 game 场景清掉
	for i in 3:
		await get_tree().process_frame

	_chk(SaveManager.open_slot(path), "主页面按「读档」: 档进 _pending")
	_chk(SaveManager.slot_name == SLOT, "档名跟着存档走: %s" % SaveManager.slot_name)
	var game2: Node = load("res://scene/game.tscn").instantiate()
	add_child(game2)
	for i in 6:
		await get_tree().process_frame
	_chk(Wallet.money == money_saved, "钱回到存档那份 (%d -> %d, 存的 %d)" % [
		money_saved + 5000, Wallet.money, money_saved])
	_chk(TimeManager.day == 2 and TimeManager.hour == 6,
		"日期回到第 2 天早上 6 点 (现在 第%d天 %d:%02d)" % [
			TimeManager.day, TimeManager.hour, TimeManager.minute])
	_chk(SaveManager.take_reset_request() == false,
		"读档不会被顺手当成开新档重置掉")

	print("\n========== 结果: %d 通过 / %d 失败 ==========" % [_ok, _bad])
	_wipe(BASE)          # 临时目录收干净，别在 user:// 里留垃圾
	await get_tree().process_frame
	get_tree().quit()


# 递归找按钮：文字里含 needle 就算命中
func _has_button(n: Node, needle: String) -> bool:
	if n is Button and String((n as Button).text).contains(needle):
		return true
	for c in n.get_children():
		if _has_button(c, needle):
			return true
	return false


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
