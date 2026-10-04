# tools/_probe_battle_exit.gd —— 查「战斗后不能退出」到底卡在哪
#
# 走真实流程：先摆一张大地图（Voyage.enter_battle 要靠 group="world_map" 找到它），
# 然后进战场，把敌人全打死，看战斗节点会不会自己拆掉、海图会不会露回来。
# 三条收尾路径都跑一遍：打赢 / 撤退 / 打输。
extends Node

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false

	await _run("打赢", "win")
	await _run("撤退", "retreat")
	await _run("打输", "lose")

	get_tree().quit()

func _run(tag: String, how: String) -> void:
	print("\n========== 战斗收尾: %s ==========" % tag)
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await get_tree().process_frame

	var party := {"id": 0, "pos": Vector2(60, 50) * 16.0, "dir": Vector2.ZERO,
		"t": 0.0, "type": "海寇", "size": 3, "node": null}
	# world_map 自己会调 enter_battle，这里直接照它的路子来
	wm.parties = [party]
	wm._active_party = 0
	Voyage.enter_battle(party)
	await get_tree().process_frame
	await get_tree().process_frame

	var bm: Node = get_tree().get_first_node_in_group("battle")
	if bm == null:
		print("  [!!] 进战场失败：没找到 group=battle 的节点")
		return
	print("  进战场 OK: time_scale=%.2f 敌人=%d 主角血=%d" % [
		Engine.time_scale, bm._count_foes(), Legion.player_hp])

	match how:
		"win":
			for u in bm.units.duplicate():
				if is_instance_valid(u) and u.side == "enemy":
					u.call("take_damage", 9999)
		"retreat":
			bm._over = true
			bm._finish("retreat", 0.6)
		"lose":
			bm._over = true
			Legion.player_hp = 0
			bm._finish("defeat", 1.4)

	# 慢放是 0.5 倍，收尾 tween 要跑 delay 秒（真时间），给足 6 秒
	var waited := 0.0
	while waited < 6.0:
		await get_tree().process_frame
		waited += get_process_delta_time() / maxf(Engine.time_scale, 0.01)
		if get_tree().get_first_node_in_group("battle") == null:
			break

	var bm2: Node = get_tree().get_first_node_in_group("battle")
	var wm2: Node = get_tree().get_first_node_in_group("world_map")
	print("  等 %.2f 秒后: 战场还在=%s  海图在=%s  traveling=%s  ashore=%s  time_scale=%.2f" % [
		waited, str(bm2 != null), str(wm2 != null), str(Voyage.traveling),
		str(Voyage.ashore), Engine.time_scale])
	if wm2 != null:
		var vis := "true"
		if wm2 is CanvasItem:
			vis = str((wm2 as CanvasItem).visible)
		print("  海图 visible=%s  队伍数=%d  遭遇冷却=%.1f" % [
			vis, wm2.parties.size(), float(wm2.get("_encounter_cd"))])
	var game := get_tree().get_first_node_in_group("game")
	print("  岛上游戏场景: %s" % ("(探针里没造，正常)" if game == null else "在"))

	if bm2 != null:
		bm2.queue_free()
	if wm2 != null:
		wm2.queue_free()
	await get_tree().process_frame
	Voyage.traveling = false
	Voyage.ashore = false
	Legion.player_hp = Legion.player_max_hp()
	Engine.time_scale = 1.0
