extends Node
# tools/_probe_e26a.gd —— e26a 占城治理实机探针: 数据层 / 叛军上地图 / 治理面板
# 跑法（带窗口跑, 要截图）:
#   & $exe --path . --log-file w32_e26a.log res://tools/_probe_e26a.tscn
#
# 站点:
#   [1] 治理数据层 —— 攻城占领 -> 每日税入 -> 驻军压不满 -> 安抚 -> 满 100 爆叛乱
#   [2] 叛军上地图 —— Nations 叛乱队列 -> world_map 每日钩子刷叛军队伍
#   [3] 治理面板 —— town_ui 占领城分支（军管/税入/不满条/驻军/安抚按钮）

const OUT := "res://outputs"
var fails := 0

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_data_layer()
	await _world_rebels()
	await _ui_panel()
	print("\n[e26a] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

# 手动走一天（TimeManager.new_day 的全部订阅者都会响: Nations 结算 + world_map 刷叛军）
func _fire_day() -> void:
	TimeManager.day += 1
	TimeManager.new_day.emit(TimeManager.day)

# ---------------- 1. 治理数据层 ----------------
func _data_layer() -> void:
	print("\n========== [1] 治理数据层 ==========")
	Nations.reset_for_new_game()
	Wallet.add_money(10000)
	var tid := "chenxi_cap"
	var loot := Nations.on_siege_victory(tid)
	_ck(Nations.occupied.has(tid), "攻城后 %s 已占领" % tid)
	_ck(loot > 0, "战利品 %d 金" % loot)
	_ck(Nations.pgar_of(tid) == 0, "初始驻军 0")
	_ck(Nations.unrest_of(tid) == 45, "初始不满 45 (实际 %d)" % Nations.unrest_of(tid))

	# 次日: 首都税（占领初繁荣 30 -> 55x1.15=63, e27h 繁荣加成）, 无驻军不满 +8
	var m0 := Wallet.money
	var tax0 := Nations.occupy_tax(tid)   # e27j: 税入动态取值, 不再硬编码 55
	_fire_day()
	_ck(Wallet.money == m0 + tax0,
		"次日税入 +%d (%d -> %d)" % [tax0, m0, Wallet.money])
	_ck(Nations.unrest_of(tid) == 53, "无驻军不满 45+8=53 (实际 %d)" % Nations.unrest_of(tid))

	# 派驻军: 1 支后日涨幅 8-2=6
	var why := Nations.station_garrison(tid)
	_ck(why == "" and Nations.pgar_of(tid) == 1 and Wallet.money == m0 + tax0 - Nations.PGAR_COST,
		"派驻军成功 x1 (花了 %d 金)" % Nations.PGAR_COST)
	_fire_day()
	_ck(Nations.unrest_of(tid) == 59, "1 支驻军不满 53+6=59 (实际 %d)" % Nations.unrest_of(tid))

	# 安抚: -45
	why = Nations.calm_town(tid)
	_ck(why == "" and Nations.unrest_of(tid) == 14,
		"安抚 -45: 59-45=14 (实际 %d)" % Nations.unrest_of(tid))

	# 满编 3 支
	for i in 5:
		Nations.station_garrison(tid)
	_ck(Nations.pgar_of(tid) == Nations.PGAR_MAX, "驻军封顶 %d (实际 %d)" % [Nations.PGAR_MAX, Nations.pgar_of(tid)])

	# 叛乱: 不满拉满, 过一天城池易主 + 队列入账
	Nations.unrest[tid] = 99
	_fire_day()
	_ck(not Nations.occupied.has(tid), "不满满 100 -> 叛乱, 城池易主")
	_ck(Nations.pending_rebels.has(tid), "叛乱城进了队列 (等海图取走)")

	# 存档往返
	Nations.reset_for_new_game()
	Nations.on_siege_victory(tid)
	Nations.p_gar[tid] = 2
	Nations.unrest[tid] = 66
	var d := Nations.to_dict()
	Nations.reset_for_new_game()
	Nations.from_dict(d)
	_ck(Nations.occupied.has(tid), "存档往返: occupied 还在")
	_ck(Nations.pgar_of(tid) == 2 and Nations.unrest_of(tid) == 66,
		"存档往返: p_gar=2 unrest=66 还原")

# ---------------- 2. 叛军上地图 ----------------
func _world_rebels() -> void:
	print("\n========== [2] 叛军上地图 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var n0: int = wm.parties.size()
	Nations._fire_rebellion("tieyan_cap")   # 造一桩叛乱, 次日海图钩子取走
	_fire_day()
	await get_tree().process_frame
	var rebels := 0
	for p in wm.parties:
		if String(p.get("type", "")) == "叛军":
			rebels += 1
	_ck(rebels >= 1, "叛乱城刷出 %d 队叛军 (总队伍 %d -> %d)" % [rebels, n0, wm.parties.size()])
	_ck(Nations.pending_rebels.is_empty(), "叛乱队列已被取走")
	await _shot("govern_map")
	wm.free()
	await get_tree().process_frame

# ---------------- 3. 治理面板 ----------------
func _ui_panel() -> void:
	print("\n========== [3] 治理面板 ==========")
	Nations.reset_for_new_game()
	Wallet.add_money(10000)
	Nations.on_siege_victory("chenxi_cap")
	var ui: Control = load("res://town_ui.gd").new()
	ui.setup("chenxi_cap")
	add_child(ui)
	await get_tree().process_frame
	ui.call("open_panel")
	await _wait(0.4)
	var texts := _texts(ui)
	_ck(_has(texts, "占领城治理"), "面板出现占领城治理区")
	_ck(_has(texts, "军管城池"), "领主行换成军管城池")
	_ck(_has(texts, "派驻军"), "有派驻军按钮")
	_ck(_has(texts, "安抚民心"), "有安抚民心按钮")
	_ck(_has(texts, "不满"), "有不满度条")
	_ck(_has(texts, "每天税入 +%d" % Nations.occupy_tax("chenxi_cap")),
		"显示首都日税 %d" % Nations.occupy_tax("chenxi_cap"))
	await _shot("govern_panel")

	# 点「派驻军」: 钱 -120, 驻军 x1
	var m0 := Wallet.money
	_click_btn(ui, "派驻军")
	await get_tree().process_frame
	_ck(Nations.pgar_of("chenxi_cap") == 1 and Wallet.money == m0 - Nations.PGAR_COST,
		"点派驻军: 驻军 x1, 钱包 %d -> %d" % [m0, Wallet.money])
	await _shot("govern_station")

	# 点「安抚民心」: 钱 -80, 不满 -45
	var u0 := Nations.unrest_of("chenxi_cap")
	_click_btn(ui, "安抚民心")
	await get_tree().process_frame
	_ck(Nations.unrest_of("chenxi_cap") == maxi(0, u0 - Nations.CALM_DOWN),
		"点安抚: 不满 %d -> %d" % [u0, Nations.unrest_of("chenxi_cap")])
	await _shot("govern_calm")
	ui.call("close_panel")
	await _wait(0.2)

	# 普通城不受影响: 还是外交面板
	ui.setup("chenxi_bridge")
	ui.call("open_panel")
	await _wait(0.3)
	var texts2 := _texts(ui)
	_ck(_has(texts2, "聊聊天") and not _has(texts2, "占领城治理"),
		"普通贸易镇仍是外交面板")
	ui.call("close_panel")
	ui.free()
	await get_tree().process_frame

# ---------------- 工具 ----------------
func _texts(root: Node) -> Array:
	var out: Array = []
	if root is Label:
		out.append(String(root.text))
	if root is Button:
		out.append(String(root.text))
	for c in root.get_children():
		out.append_array(_texts(c))
	return out

func _has(arr: Array, sub: String) -> bool:
	for t in arr:
		if String(t).contains(sub):
			return true
	return false

func _click_btn(root: Node, sub: String) -> bool:
	if root is Button and String(root.text).contains(sub) and not root.disabled:
		root.pressed.emit()
		return true
	for c in root.get_children():
		if _click_btn(c, sub):
			return true
	return false

func _shot(nm: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		img.save_png(ProjectSettings.globalize_path("%s/e26_%s.png" % [OUT, nm]))
		print("  [shot] e26_%s.png" % nm)
	else:
		print("  [!!] 截图失败: viewport 纹理为空")

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame
