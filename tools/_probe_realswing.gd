# tools/_probe_realswing.gd —— 复刻玩家真实挥斧路径：读真档 -> 站树边 -> 扫描树冠
#
# 背景：探针(直接调函数)全过、自检全过，但玩家实测"这里没有能砍的树"。
#       本探针不自己复刻判定，全部调真实函数：
#       player._facing_grid_pos(M) 拿 target -> game.pick_tree_cell(M, target)
#       -> game.hit_tree(result)，统计树冠矩形内每个鼠标点的结算。
# 跑法：EXE --headless --path . res://tools/_probe_realswing.tscn
extends Node

const TS := 16

var _pass := 0
var _fail := 0

func chk(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  [ok] ", msg)
	else:
		_fail += 1
		print("  [!!] ", msg)

func _ready() -> void:
	print("===== 真实挥斧路径 扫描探针 =====")
	SaveManager.enabled = false
	var ok := SaveManager.load_into_pending()      # 读玩家的真档（只读，不写）
	chk(ok, "玩家真档 load_into_pending 成功")
	if not ok:
		_finish()
		return
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# _ready 里 has_save() && load_into_pending() && apply_pending() —— pending 已灌好，
	# apply_pending 会再读一遍 pending（幂等），等价于真实启动读档。
	SaveManager.apply_pending(g)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Node2D = g.get_node("Player")
	player.current_item = load("res://item/axe.tres")

	# 挑一棵成树（带节点）
	var tc := Vector2i(-999, -999)
	for k in Trees.trees.keys():
		var kk: Vector2i = k
		if int(Trees.trees[kk].stage) != Trees.ST_MATURE:
			continue
		if g.tree_nodes.has(kk):
			tc = kk
			break
	chk(tc.x != -999, "找到成树 %s (共 %d 棵树 / %d 个节点)" % [tc, Trees.trees.size(), g.tree_nodes.size()])
	if tc.x == -999:
		_finish()
		return

	var node: Node2D = g.tree_nodes[tc]
	var base: Vector2 = node.global_position
	print("  节点位置=%s  数据键=%s  _cell_tree_pos=%s" % [base, tc, g._cell_tree_pos(tc)])
	print("  位置偏差=%s（诊断信息，pick 通了就行）" % (base - g._cell_tree_pos(tc)))

	# 复刻截图站位：树右邻格（玩家脚下 = 格子底中）
	var stand := tc + Vector2i.RIGHT
	var cs: CollisionShape2D = player.get_node("CollisionShape2D")
	player.global_position = Farm.grid_origin \
		+ Vector2(stand.x * TS + TS * 0.5, stand.y * TS + TS) - cs.position
	await get_tree().process_frame

	# 扫描树冠矩形（真实判定矩形 base+(-16,-45)..base+(16,3)），2px 步进
	# 口径：只要 pick 结果是「有树的格子」就算能砍（矩形重叠区按距离选最近的树，无害）
	var hit_cnt := 0
	var miss_cnt := 0
	var miss_samples: Array = []
	var pick0: Vector2i = g.pick_tree_cell(base + Vector2(0, -30), player._facing_grid_pos(base + Vector2(0, -30)))
	chk(Trees.has_tree(pick0), "树冠中心: pick_tree_cell -> %s (有树)" % pick0)

	for oy in range(-44, 3, 2):
		for ox in range(-15, 16, 2):
			var m: Vector2 = base + Vector2(ox, oy)
			var target: Vector2i = player._facing_grid_pos(m)
			var picked: Vector2i = g.pick_tree_cell(m, target)
			if Trees.has_tree(picked):
				hit_cnt += 1
			else:
				miss_cnt += 1
				if miss_samples.size() < 8:
					miss_samples.append("M=%s ox=%d oy=%d target=%s picked=%s" % [m, ox, oy, target, picked])
	print("  扫描结果: 能砍 %d / 真MISS %d (共 %d 点)" % [hit_cnt, miss_cnt, hit_cnt + miss_cnt])
	for s in miss_samples:
		print("    MISS: ", s)
	chk(miss_cnt == 0, "树冠矩形内所有点都能砍到树")

	# 完整走一次 _swing_axe（真实入口）
	var hp0 := int(Trees.trees[tc].hp)
	player._swing_axe(player._facing_grid_pos(base + Vector2(0, -30)), base + Vector2(0, -30))
	await get_tree().process_frame
	await get_tree().process_frame
	chk(int(Trees.trees[tc].hp) == hp0 - 1, "真实 _swing_axe: 耐久 %d -> %d" % [hp0, int(Trees.trees[tc].hp)])

	# ❗关键排查：读档后玩家 current_item 会不会被 _sync_current_item 改掉？
	print("  current_item = %s (玩家砍树时手里必须是斧头)" % player.current_item)

	# ---------- 开新档路径：begin_new_game -> game._ready 的 reset 分支 ----------
	# 之前的大 bug：reset_all 清了树数据但屏幕节点还在（看得见砍不着）。
	SaveManager.begin_new_game("自检新档验证")
	SaveManager.enabled = false          # 新档首存别碰真档
	var g2: Node = load("res://scene/game.tscn").instantiate()
	add_child(g2)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	chk(Trees.trees.size() >= 60, "开新档: 树数据 %d 棵 (满岛重撒 >=60)" % Trees.trees.size())
	chk(g2.tree_nodes.size() == Trees.trees.size(), "开新档: 树节点 %d 个 == 数据 %d (无幽灵树)" % [g2.tree_nodes.size(), Trees.trees.size()])
	var all_valid := true
	for k in Trees.trees.keys():
		var kk: Vector2i = k
		if not g2.tree_nodes.has(kk) or not Trees.has_tree(kk):
			all_valid = false
	chk(all_valid, "开新档: 每棵树数据都有对应节点（无幽灵树）")
	chk(int(Trees.trees.keys().size()) > 0 and int(Wallet.money) > 0, "开新档: 钱包/背包已按新档初始化")
	g2.queue_free()
	_finish()

func _finish() -> void:
	print("----- 通过 %d / 失败 %d -----" % [_pass, _fail])
	get_tree().quit()
