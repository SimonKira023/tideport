extends Node
# tools/_probe_e26b.gd —— e26b 国家AI活跃化实机探针: 国战 / 远征换旗 / 海寇补员
# 跑法（带窗口跑, 要截图）:
#   & $exe --path . --log-file w32_e26b.log res://tools/_probe_e26b.tscn
#
# 站点:
#   [1] 国战数据层 —— _maybe_launch_war 立案 -> pop_wars 取走 -> ai_conquer_town 换旗半编
#       -> 玩家夺回（好感记现主 / town_owner 清账）-> 存档往返
#   [2] 远征上地图 —— spawn_expedition 刷队 -> 挪到城边 -> 到达换旗 + 国界重画 + 队伍消失
#   [3] 玩家拦截 —— 撞上远征队开战 -> 打赢远征队消失（不设防）
#   [4] 海寇补员 —— 清剿到剩 2 -> 过一天补回 4
#   [5] 每日国战链 —— Nations 立案 -> TimeManager.new_day -> 海图自动刷远征队

const OUT := "res://outputs"
var fails := 0

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_data_layer()
	await _expedition_map()
	await _player_intercept()
	await _pirate_respawn()
	await _daily_war_chain()
	print("\n[e26b] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

# 手动走一天（TimeManager.new_day 的全部订阅者都会响）
func _fire_day() -> void:
	TimeManager.day += 1
	TimeManager.new_day.emit(TimeManager.day)

# 挑一个家底 >= 2 城的攻方国
func _pick_attacker() -> String:
	for nid in Nations.nation_ids():
		if Nations.ai_towns_of(nid).size() >= 2:
			return nid
	return ""

# 挑一座别国城（非攻方自有、非玩家占领）
func _pick_target(atk: String) -> String:
	for tid in Nations.TOWNS.keys():
		var cur := Nations.owner_nation_of(String(tid))
		if cur != "" and cur != atk and not Nations.occupied.has(tid):
			return String(tid)
	return ""

# ---------------- 1. 国战数据层 ----------------
func _data_layer() -> void:
	print("\n========== [1] 国战数据层 ==========")
	Nations.reset_for_new_game()
	var atk := _pick_attacker()
	_ck(atk != "", "找到攻方国 %s (家底 %d 城)" % [atk, Nations.ai_towns_of(atk).size()])
	Nations.pending_wars.clear()
	Nations._maybe_launch_war()
	_ck(Nations.pending_wars.size() >= 1, "立案: pending_wars %d 桩" % Nations.pending_wars.size())
	var wars: Array = Nations.pop_wars()
	_ck(wars.size() >= 1 and Nations.pending_wars.is_empty(),
		"pop_wars 取走 %d 桩, 队列清空" % wars.size())

	var w: Dictionary = wars[0]
	var a2 := String(w["from"])
	var tid := String(w["tid"])
	var def := Nations.owner_nation_of(tid)
	_ck(a2 != "" and def != "" and def != a2, "攻方 %s 打 %s 的 %s" % [a2, def, tid])

	# AI 攻陷: 换旗 + 守军半编
	var gmax := Nations.garrison_max(tid)
	Nations.ai_conquer_town(tid, a2)
	_ck(Nations.owner_nation_of(tid) == a2, "换旗: %s 现主是 %s" % [tid, a2])
	_ck(Nations.garrison_of(tid) == maxi(1, gmax / 2),
		"守军半编: max %d -> %d" % [gmax, Nations.garrison_of(tid)])

	# AI 不啃自己家
	var own: String = String(Nations.ai_towns_of(a2)[0])
	Nations.ai_conquer_town(own, a2)
	_ck(Nations.owner_nation_of(own) == a2, "自家城打不动 (现主不变)")

	# 玩家夺回: 好感记现主头上, town_owner 清账
	var fav0 := Nations.favor_of(a2)
	var loot := Nations.on_siege_victory(tid)
	_ck(loot > 0, "玩家夺回 %s, 战利品 %d 金" % [tid, loot])
	_ck(Nations.occupied.has(tid), "城归玩家 (occupied)")
	_ck(not Nations.town_owner.has(tid), "town_owner 旧主记账已清")
	_ck(Nations.favor_of(a2) == maxi(Nations.FAVOR_MIN, fav0 - 60),
		"好感记在现主 %s 头上 (-60, 下限 %d): %d -> %d" % [a2, Nations.FAVOR_MIN, fav0, Nations.favor_of(a2)])

	# AI 啃不动玩家的占领城（occupied 保险）
	Nations.ai_conquer_town(tid, a2)
	_ck(Nations.occupied.has(tid), "玩家占领城 AI 啃不动, 旗帜还在")

	# 存档往返: town_owner / pending_wars
	Nations.reset_for_new_game()
	var t2 := _pick_target(atk)
	Nations.ai_conquer_town(t2, atk)
	Nations._maybe_launch_war()
	var wars_n: int = Nations.pending_wars.size()
	var d := Nations.to_dict()
	var owner_snapshot := Nations.owner_nation_of(t2)
	Nations.reset_for_new_game()
	Nations.from_dict(d)
	_ck(Nations.owner_nation_of(t2) == owner_snapshot, "存档往返: town_owner 还原 (%s)" % owner_snapshot)
	_ck(Nations.pending_wars.size() == wars_n, "存档往返: pending_wars 还原 (%d 桩)" % wars_n)

# ---------------- 2. 远征上地图 ----------------
func _expedition_map() -> void:
	print("\n========== [2] 远征上地图 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var n0: int = wm.parties.size()
	var atk := _pick_attacker()
	var tid := _pick_target(atk)
	var tcell: Vector2i = Nations.TOWNS[tid]["cell"]
	var cap_pos: Vector2 = wm._cell_center(tcell)
	var owner0 := Nations.owner_nation_of(tid)
	wm.spawn_expedition(atk, tid)
	await get_tree().process_frame
	_ck(wm.parties.size() == n0 + 1, "远征队上地图 (队伍 %d -> %d)" % [n0, wm.parties.size()])
	var pd: Dictionary = {}
	for p in wm.parties:
		if String(p.get("type", "")) == "远征":
			pd = p
	_ck(not pd.is_empty() and String(pd.get("target", "")) == tid,
		"远征队 target = %s" % String(pd.get("target", "")))
	_ck(not pd.is_empty() and String((pd["lbl"] as Label).text).contains("远征军"),
		"队名带国名: %s" % String((pd["lbl"] as Label).text))
	await _shot("expedition_spawn")

	# 挪到城边 10 像素, 等到达换旗
	pd["pos"] = cap_pos + Vector2(10, 0)
	(pd["node"] as Node2D).position = pd["pos"]
	await _wait(0.3)
	_ck(Nations.owner_nation_of(tid) == atk, "远征到达: %s 由 %s 换旗给 %s" % [tid, owner0, atk])
	print("    [info] kind=%s garrison_max=%d garrison_of=%d" % [
			String(Nations.TOWNS[tid].get("kind", "")), Nations.garrison_max(tid),
			Nations.garrison_of(tid)])
	var expect_g: int = maxi(1, Nations.garrison_max(tid) / 2) if Nations.garrison_max(tid) > 0 else 0
	_ck(Nations.garrison_of(tid) == expect_g,
		"新守军半编 (贸易镇不设防则为 0): %d" % Nations.garrison_of(tid))
	var gone := true
	for p in wm.parties:
		if p == pd:
			gone = false
	_ck(gone, "远征队进城自毁, 队伍散了")
	await _shot("expedition_conquer")
	wm.free()
	await get_tree().process_frame

# ---------------- 3. 玩家拦截远征队 ----------------
func _player_intercept() -> void:
	print("\n========== [3] 玩家拦截远征队 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var atk := _pick_attacker()
	var tid := _pick_target(atk)
	wm.spawn_expedition(atk, tid)
	await get_tree().process_frame
	var pd: Dictionary = {}
	for p in wm.parties:
		if String(p.get("type", "")) == "远征":
			pd = p
	# 头像贴脸: 遭遇距离 15, 放 10 像素外
	wm.avatar.position = (pd["pos"] as Vector2) + Vector2(10, 0)
	await _wait(0.6)
	var bm: Node = get_tree().get_first_node_in_group("battle")
	_ck(bm != null, "撞上远征队, 战斗开打 (远征队不设防)")
	if bm == null:
		wm.free()
		return
	await _shot("intercept_battle")
	Voyage.end_battle("victory")
	await _wait(0.4)
	var bm2: Node = get_tree().get_first_node_in_group("battle")
	_ck(bm2 == null, "打赢了, 战斗场散了")
	var alive := false
	for p in wm.parties:
		if p == pd:
			alive = true
	_ck(not alive, "远征队被歼灭, 队伍从海图消失")
	wm.free()
	await get_tree().process_frame

# ---------------- 4. 海寇补员 ----------------
func _pirate_respawn() -> void:
	print("\n========== [4] 海寇补员 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var kill := 2
	var kept: Array = []
	var removed: Array = []
	for p in wm.parties:
		if String(p.get("type", "")) == "海寇" and kill > 0:
			(p["node"] as Node2D).queue_free()
			removed.append(p)
			kill -= 1
		else:
			kept.append(p)
	wm.parties = kept
	var before := _count(wm, "海寇")
	_ck(before == 2, "清剿两支海寇, 湾里剩 %d" % before)
	_fire_day()
	await get_tree().process_frame
	var after := _count(wm, "海寇")
	_ck(after == 4, "次日早上窝点补员回 %d 支" % after)
	wm.free()
	await get_tree().process_frame

# ---------------- 5. 每日国战链 ----------------
func _daily_war_chain() -> void:
	print("\n========== [5] 每日国战链 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var n0: int = wm.parties.size()
	Nations.pending_wars.clear()
	Nations._maybe_launch_war()
	_ck(Nations.pending_wars.size() >= 1, "Nations 立案 %d 桩远征" % Nations.pending_wars.size())
	_fire_day()
	await get_tree().process_frame
	var n_exp := _count(wm, "远征")
	_ck(n_exp >= 1, "海图每日钩子自动刷出 %d 支远征队 (队伍 %d -> %d)" % [n_exp, n0, wm.parties.size()])
	_ck(Nations.pending_wars.is_empty(), "国战队列已被取走")
	await _shot("daily_war")
	wm.free()
	await get_tree().process_frame

# ---------------- 工具 ----------------
func _count(wm: Node, type: String) -> int:
	var n := 0
	for p in wm.parties:
		if String(p.get("type", "")) == type and not bool(p.get("gone", false)):
			n += 1
	return n

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
