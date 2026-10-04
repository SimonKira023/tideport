# tools/_probe_battle_loop.gd —— 让 AI 自己打完一整场，看战斗会不会卡死
#
# 前面的 _probe_battle_exit 是「手动把敌人打死」，验证的是收尾逻辑；
# 这个探针换成**不插手**：主角站在原地不动，只让伙伴按默认口令（跟随我）打，
# 每 5 秒打一次快照，看 60 秒内战斗能不能自己分出胜负 / 会不会有人卡在打不到的地方。
extends Node

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false

	Slaves.slaves = [
		{"name": "甲", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1},
		{"name": "乙", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1},
		{"name": "丙", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "弓手", "squad": 1},
	]
	Slaves.count = Slaves.slaves.size()
	Slaves.expedition = [0, 1, 2]

	for tpl in ["海寇", "山贼"]:
		await _one(tpl)

	get_tree().quit()

func _one(ptype: String) -> void:
	# e27j: 每场开打前把随从血回满 —— 上一场的残血会经 slave_data["hp"] 带进下一场，
	#   hp=0 的随从上不了场（山贼场「我方 0」就是这么来的，不是游戏 bug 是探针没回血）
	for s in Slaves.slaves:
		s["hp"] = s.get("max_hp", 30)
	print("\n========== AI 自动交战: %s ==========" % ptype)
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await get_tree().process_frame

	var party := {"id": 0, "pos": Vector2(60, 50) * 16.0, "dir": Vector2.ZERO,
		"t": 0.0, "type": ptype, "size": 3, "node": null}
	# ❗一定要走 _make_party 让 world_map 自己建敌人节点：早先直接塞了个 node=null
	#   的假队伍，_physics_process 每帧刷 "position on Nil"，噪声盖住了真问题。
	#   id 也不能写死 0 —— _ready 里已经刷过 6 支敌人了，id 要从新建的那支身上读。
	wm.parties.clear()
	for c in wm.get_children():
		if String(c.name).begins_with("Party"):
			c.queue_free()
	wm._make_party(party["pos"], ptype, 3)
	wm.parties[0]["pos"] = party["pos"]
	wm._start_battle(int(wm.parties[0]["id"]))
	await get_tree().process_frame
	await get_tree().process_frame
	var bm0: Node = get_tree().get_first_node_in_group("battle")
	if bm0 == null:
		print("  [!!] 没进战场")
		get_tree().quit()
		return
	# ❗进战场先布阵，Engine.time_scale 会被冻成 0（selftest 证实是设计行为）。
	#   必须走玩家同款路径「点开始战斗」(_begin_battle) 恢复时间——
	#   以前裸设 time_scale 跟异步进场赛跑，输一次整个探针就 await 假死（e27j 教训）。
	bm0._begin_battle()
	Engine.time_scale = 1.0        # 不等慢动作，加速观察
	print("  地形=%s  敌人=%d  我方=%d" % [bm0.template, bm0._count_foes(), _allies(bm0)])

	var t := 0.0            # 战斗秒（按 time_scale 折算）
	var real_t := 0.0       # 真实秒表：时间被冻住时守卫照样走，兜底报警
	var frozen := 0.0
	var next_log := 5.0
	var last_ms := Time.get_ticks_msec()
	# e27j: 互射零命中排查 —— 箭寿命只有 0.4s，5 秒快照必漏；每帧轮询 arrows
	#   数组累加「在飞箭帧数」（1 支箭≈24 帧），0 = 压根没射，>0 而血不掉 = 射了没中
	var arrow_frames := 0
	var last_hero_hp := -1
	# e27j: 箭到 hero 胸口的最小距离 —— min<8 却不掉血 = 判定 bug；远大于 8 = 箭没朝 hero 飞
	var arrow_round_min := -1.0   # 本 5 秒轮最小，快照后清零
	var arrow_min_d := -1.0       # 全场最小
	while t < 60.0 and real_t < 120.0:
		# ❗用 process_frame + 真实秒表，不用 physics_frame：
		#   time_scale=0 时 physics 帧停发，await physics_frame 会永远挂起（e27j 假死教训）；
		#   process 帧照常触发，守卫才有机会报告「时间被冻住」。
		await get_tree().process_frame
		var now_ms := Time.get_ticks_msec()
		var real_dt := float(now_ms - last_ms) / 1000.0
		last_ms = now_ms
		real_t += real_dt
		t += real_dt * Engine.time_scale
		var bm: Node = get_tree().get_first_node_in_group("battle")
		if bm == null:
			print("  >>> 第 %.1f 战斗秒（真实 %.1f 秒）：战斗自己结束了（节点已拆）" % [t, real_t])
			_print_scene_state()
			return
		if Engine.time_scale <= 0.0:
			frozen += real_dt
			if frozen >= 2.0:
				print("  [!!] 战斗没结束但 time_scale=0 已持续 %.1f 秒 —— 时间被冻住，physics 已停" % frozen)
				await _dump_stuck(bm)
				return
		else:
			frozen = 0.0
		# e27j: 每帧箭计数 + hero 掉血即时打印 + 箭-胸口距离观测
		var hero_u = bm.get("hero")
		var arr_v = bm.get("arrows")
		if arr_v is Array:
			arrow_frames += (arr_v as Array).size()
			for a in arr_v:
				if a == null or not is_instance_valid(a):
					continue
				if hero_u != null and is_instance_valid(hero_u):
					var d: float = (a.position - (hero_u.global_position + Vector2(0, -10))).length()
					if arrow_round_min < 0.0 or d < arrow_round_min:
						arrow_round_min = d
					if arrow_min_d < 0.0 or d < arrow_min_d:
						arrow_min_d = d
		if hero_u != null and is_instance_valid(hero_u):
			var hp_now: int = int(hero_u.hp)
			if last_hero_hp >= 0 and hp_now != last_hero_hp:
				print("    [箭测] hero 血 %d→%d（累计在飞箭帧 %d）" % [last_hero_hp, hp_now, arrow_frames])
			last_hero_hp = hp_now
		# e27j: 胜负分出后弹结算页、等玩家点「继续」才拆战斗节点 —— 探针替玩家点
		#   （等 0.9 秒揭幕 armed 后）。不点的话节点一直挂着，60 秒守卫会误报卡住
		#   （「山贼场全员死光战斗不结束」其实是结算页没人点）。
		if bool(bm.get("_over")) and bool(bm.get("_settle_armed")):
			print("  >>> 第 %.1f 战斗秒：结算页已揭幕（%s），替玩家点「继续」" % [t, str(bm.get("_settle_result"))])
			bm.call("_close_settlement")
		if t >= next_log:
			next_log += 5.0
			var hu2 = bm.get("hero")
			var hpos := "无"
			if hu2 != null and is_instance_valid(hu2):
				hpos = "(%d,%d)" % [int(hu2.global_position.x / 16.0), int(hu2.global_position.y / 16.0)]
			print("  %2ds: 敌人 %d  我方 %d  主角血 %d  敌人血 %s  我方血 %s  距离 %.0f  在飞箭帧 %d" % [
				int(t), bm._count_foes(), _allies(bm), Legion.player_hp,
				_hps(bm, "enemy"), _hps(bm, "ally"), _gap(bm), arrow_frames])
			print("      hero格%s  ally位 %s  本轮箭距胸口min %.1f (全程 %.1f)" % [
				hpos, _ally_pos(bm), arrow_round_min, arrow_min_d])
			arrow_round_min = -1.0

	if real_t >= 120.0:
		print("  [!!] 真实 120 秒只推进了 %.1f 战斗秒 —— time_scale=%.2f，疑似时间被冻/慢放异常" % [t, Engine.time_scale])
		await _dump_stuck(get_tree().get_first_node_in_group("battle"))
		return
	print("  [!!] 60 秒还没分出胜负 —— 卡住了")
	await _dump_stuck(get_tree().get_first_node_in_group("battle"))

func _dump_stuck(bm: Node) -> void:
	if bm != null:
		for u in bm.units:
			if not is_instance_valid(u):
				continue
			var c: Vector2i = Vector2i(floori(u.global_position.x / 16.0), floori(u.global_position.y / 16.0))
			# e27j: 原来转储的「目标=_target_cache」是幽灵字段（troop 里根本没这个属性，
			#   恒 <null> 误导排查）——换成接战状态和到最近敌人的距离，对峙一眼能看懂。
			var near = bm.nearest_foe_of(u, 9999.0)
			var nd: float = -1.0
			if near != null:
				nd = near.global_position.distance_to(u.global_position)
			print("     %s %s 格%s hp=%d 被挡=%s 接战=%s 最近敌距=%.0f" % [
				u.side, u.kind, str(c), u.hp, str(bm.is_blocked_at(u.global_position)),
				str(bool(u.get("_engage"))), nd])
		bm.queue_free()
	var wm: Node = get_tree().get_first_node_in_group("world_map")
	if wm != null:
		wm.queue_free()
	await get_tree().process_frame
	Voyage.traveling = false
	Legion.player_hp = Legion.player_max_hp()
	Engine.time_scale = 1.0

func _print_scene_state() -> void:
	await get_tree().process_frame
	var wm: Node = get_tree().get_first_node_in_group("world_map")
	var vis := "?"
	if wm != null and wm is CanvasItem:
		vis = str((wm as CanvasItem).visible)
	print("     海图在=%s visible=%s traveling=%s time_scale=%.2f" % [
		str(wm != null), vis, str(Voyage.traveling), Engine.time_scale])
	if wm != null:
		wm.queue_free()
	await get_tree().process_frame
	Voyage.traveling = false
	Legion.player_hp = Legion.player_max_hp()
	Engine.time_scale = 1.0

func _allies(bm: Node) -> int:
	var n := 0
	for u in bm.units:
		if is_instance_valid(u) and u.side == "ally" and not u.get("_dying"):
			n += 1
	return n

func _hps(bm: Node, side: String) -> String:
	var out: Array = []
	for u in bm.units:
		if is_instance_valid(u) and u.side == side and not u.get("_dying"):
			out.append(str(u.hp))
	return "[" + ",".join(out) + "]"

# e27j: ally 坐标快照 —— 验证「残局弓手 122px 不推进」到底动没动
func _ally_pos(bm: Node) -> String:
	var out: Array = []
	for u in bm.units:
		if is_instance_valid(u) and u.side == "ally" and not u.get("_dying"):
			out.append("%s(%d,%d)" % [u.kind,
				int(u.global_position.x / 16.0), int(u.global_position.y / 16.0)])
	return "[" + ",".join(out) + "]"

func _gap(bm: Node) -> float:
	var best := 9999.0
	for a in bm.units:
		if not is_instance_valid(a) or a.side != "ally" or a.get("_dying"):
			continue
		for e in bm.units:
			if not is_instance_valid(e) or e.side != "enemy" or e.get("_dying"):
				continue
			best = minf(best, a.global_position.distance_to(e.global_position))
	return best
