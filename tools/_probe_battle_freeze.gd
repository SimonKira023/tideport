# tools/_probe_battle_freeze.gd —— 回归验证：AI 撞到树/河岸后还能不能绕过去
#
# 背景（真凶，已修）：troop._try_move 的贴墙滑行阈值写成绝对像素 0.1，
# 而一步才 0.47 像素、垂直分量只有 0.01 —— 滑行分支被整条跳过，
# 正面顶住树的单位从此一动不动，敌人清不完 -> 胜负判定不触发 -> 玩家出不去战场。
#
# 这个探针盯住「当初会卡死的那个敌人」（树林模板里第一个敌人刀客，原来停在 x≈384），
# 看它 30 秒里最长静止多久。修好之后它应该一直在动（最大静止 < 1 秒）。
extends Node

var _u: Node = null

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

	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await get_tree().process_frame
	# ❗走真实路径生成敌人（早期版本直接塞了个 node=null 的假队伍，
	#   害得 world_map._physics_process 每帧刷 "position on Nil"，噪声盖住了真问题）。
	#   注意 id：_ready 里 _spawn_parties() 已经刷了 6 支敌人，_next_id 早就不是 0 了，
	#   所以 id 要从刚建好的那支队伍身上读，写死 0 会找不到队伍、压根进不了战场。
	wm._make_party(Vector2(60, 50) * 16.0, "山贼", 3)
	var pid: int = int(wm.parties[wm.parties.size() - 1]["id"])   # 刚建的那支在最后
	wm._start_battle(pid)
	await get_tree().process_frame
	await get_tree().process_frame

	var bm: Node = get_tree().get_first_node_in_group("battle")
	if bm == null:
		print("[!!] 没进战场，探针没意义")
		get_tree().quit()
		return
	print("地形 = %s" % bm.template)
	for u in bm.units:
		if is_instance_valid(u) and u.side == "enemy" and u.kind == "刀客":
			_u = u
			break
	if _u == null:
		print("[!!] 没找到敌人刀客")
		get_tree().quit()
		return
	print("盯住的敌人初始位置 = %s  speed=%.1f" % [str(_u.global_position), _u.speed])

	# ❗进战场先布阵，Engine.time_scale 会被冻成 0（selftest 证实是设计行为）。
	#   必须走玩家同款路径「点开始战斗」(_begin_battle) 恢复时间——
	#   以前探针没走这条路，下面盯梢循环的计时器被 time_scale 缩放、永不触发，探针自己先假死。
	bm._begin_battle()
	Engine.time_scale = 1.0        # 观察加速：不进慢动作

	var last: Vector2 = _u.global_position
	var still := 0.0
	var max_still := 0.0
	# ❗_u 声明成 Node，取属性回来是 Variant，`:=` 推断不出类型会直接 Parse Error
	var min_x: float = _u.global_position.x
	var t := 0.0
	var left_of_tree := false
	while t < 30.0 and is_instance_valid(_u):
		# ❗ignore_time_scale=true：布阵/结算等阶段 time_scale 可能被冻或缩放，
		#   默认计时器跟着缩放、冻住时永不触发（e27j 假死教训）。
		#   用真实秒表盯梢：若游戏真把时间冻住了，静止时长会如实涨到 FAIL。
		await get_tree().create_timer(0.2, true, false, true).timeout
		t += 0.2
		if get_tree().get_first_node_in_group("battle") == null:
			print("  %.1fs：战斗自己结束了" % t)
			break
		if not is_instance_valid(_u):
			print("  %.1fs：盯住的敌人没了（打死了 / 逃走了）" % t)
			break
		var d: float = _u.global_position.distance_to(last)
		if d < 0.3:
			still += 0.2
			max_still = maxf(max_still, still)
		else:
			still = 0.0
		last = _u.global_position
		min_x = minf(min_x, _u.global_position.x)
		# 原来它顶死在格 (24,12) = x384 过不去；能跑到 x<368 说明绕过那棵树了
		if _u.global_position.x < 368.0:
			left_of_tree = true

	print("\n结果：")
	print("  最长静止 %.1f 秒   （>=5 秒就是又卡住了）" % max_still)
	print("  最远走到 x=%.0f   （原来顶在 384 过不去）" % min_x)
	print("  绕过了那棵树：%s" % ("是" if left_of_tree else "否"))
	print("  判定：%s" % ("PASS" if max_still < 5.0 else "FAIL"))
	get_tree().quit()
