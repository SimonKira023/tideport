# 一次性探针：验「砍树检测不到树」的修复。
#
# 复现的现场（用户那张截图）：人贴着树站，对着树冠挥斧头，提示"这里没有能砍的树"。
# 病根：树的贴图 32x48、底边对齐节点原点 —— 视觉上比注册的那一格**高出近 3 格**，
#       树冠悬在格子上方。而斧头判定拿的是「鼠标位置 -> 格子」，点在树冠上算出来的是
#       树顶上方的空格，查表自然查不到树。
#
# 跑法：
#   EXE --headless --path . res://tools/_probe_choptree.tscn
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
	print("===== 砍树检测 探针 =====")
	SaveManager.enabled = false          # 别碰玩家真档
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = g.get_node("Player")
	player.current_item = load("res://item/axe.tres")

	print("  格子原点: Farm.grid_origin=%s(=grid_layer 的全局位置)  grid_layer.position=%s(局部)"
		% [Farm.grid_origin, g.grid_layer.position])

	# ---------- 挑一棵成树：贴图最大，最容易被"树冠错位"坑到 ----------
	var tc := Vector2i(-999, -999)
	for k in Trees.trees.keys():
		var kk: Vector2i = k
		if int(Trees.trees[kk].stage) != Trees.ST_MATURE:
			continue
		if not g.tree_nodes.has(kk):
			continue
		# 下方一格得能站人，不然摆不了现场
		if g.is_water(kk + Vector2i(0, 1)) or Trees.has_tree(kk + Vector2i(0, 1)):
			continue
		tc = kk
		break
	chk(tc.x != -999, "找到一棵成树 %s" % tc)
	if tc.x == -999:
		_finish()
		return

	var node: Node2D = g.tree_nodes[tc]
	var base: Vector2 = node.global_position
	print("  树格=%s  节点原点(树干底)=%s  贴图范围=%s"
		% [tc, base, Rect2(base + Vector2(-16, -45), Vector2(32, 48))])
	# 树的节点位置按 grid_layer 的（局部）原点算、格子索引按 Farm.grid_origin（全局）算，
	# 两个数值不一样但必须指向同一套格子 —— 不然树画在一处、判定在另一处。
	chk(g._world_to_cell(base - Vector2(0.0, 8.0)) == tc,
		"节点位置换算回格子 = 它注册的那格（两套原点是等效的）")

	# ---------- ① 复现错位：鼠标搁在树冠上 ----------
	var crown := base + Vector2(0, -34)          # 树冠中部（贴图里偏上那一段）
	var wrong: Vector2i = player._facing_grid_pos(crown)  # 旧路子：鼠标 -> 格子
	print("  鼠标搁在树冠 %s -> 换算成格子 %s（树其实在 %s）" % [crown, wrong, tc])
	chk(wrong != tc, "确实复现了错位：树冠上的鼠标算出的是 %s" % wrong)

	# ---------- ② 修复：按贴图矩形命中 ----------
	chk(g.pick_tree_cell(crown, wrong) == tc, "修复后：指着树冠 = 指着树 %s" % tc)
	chk(g.pick_tree_cell(base + Vector2(0, -44), Vector2i(0, 0)) == tc,
		"点在树冠最顶端也认得出这棵树")
	chk(g.pick_tree_cell(base + Vector2(-14, -20), wrong) == tc, "点在树冠左缘也认得出")
	chk(g.pick_tree_cell(base + Vector2(14, -20), wrong) == tc, "点在树冠右缘也认得出")

	# ---------- ③ 全链路：挥斧头真的削到树 ----------
	var hp0 := int(Trees.trees[tc].hp)
	player._swing_axe(wrong, crown)
	chk(int(Trees.trees[tc].hp) == hp0 - 1,
		"对着树冠挥一斧：耐久 %d -> %d" % [hp0, int(Trees.trees[tc].hp)])

	# ---------- ④ 站在树前面直接按使用键（鼠标没挪到树上）----------
	place_player(tc + Vector2i(0, 1))
	var pc: Vector2i = g._world_to_cell(player.global_position)
	var pw: Vector2 = player.global_position
	chk(pc == tc + Vector2i(0, 1), "人站在树下方一格 %s" % pc)
	chk(g.pick_tree_cell(pw, pc) == tc, "鼠标停在自己脚下按键：也能砍到身边那棵 %s" % tc)
	var hp1 := int(Trees.trees[tc].hp)
	player._swing_axe(pc, pw)
	chk(int(Trees.trees[tc].hp) == hp1 - 1, "这条路也真的削到了耐久")

	# ---------- ⑤ 对着远处空地挥斧：不该乱吸旁边的树 ----------
	var empty := Vector2i(-999, -999)
	for k in g._land_set.keys():
		var kk: Vector2i = k
		var clean := not Farm.tilled.has(kk)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if Trees.has_tree(kk + Vector2i(dx, dy)):
					clean = false
		if clean:
			empty = kk
			break
	chk(empty.x != -999, "找到一块周围一圈都没树的空地 %s" % empty)
	place_player(empty)
	var ew: Vector2 = player.global_position
	var got: Vector2i = g.pick_tree_cell(ew, empty)
	chk(got == empty, "对着空地挥斧：还是那格（没被旁边的树吸走，返回 %s）" % got)
	var res_far: Dictionary = g.hit_tree(got)
	chk(int(res_far.result) == Trees.RESULT_MISS, "空地挥斧 = MISS（会提示'这里没有能砍的树'）")

	# ---------- ⑥ 真砍倒一棵，确认整条链没坏 ----------
	# 只砍到「变树桩」就收手：再敲两下会把树桩也敲碎（那棵树就整个没了）
	place_player(tc + Vector2i(0, 1))
	for i in 6:
		if Trees.stage_of(tc) == Trees.ST_STUMP:
			break
		player._swing_axe(pc, crown)
		await get_tree().process_frame
	chk(Trees.stage_of(tc) == Trees.ST_STUMP, "连砍几斧：树倒了，原地留树桩（现在是 %d）" % Trees.stage_of(tc))
	chk(g._falling_cells.has(tc), "倒下动画在播（贴图更新挂起）")

	_finish()

func place_player(cell: Vector2i) -> void:
	var player: Node2D = _player()
	var cs: CollisionShape2D = player.get_node("CollisionShape2D")
	player.global_position = Farm.grid_origin \
		+ Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5) - cs.position

func _player() -> Node2D:
	return get_child(0).get_node("Player")

func _finish() -> void:
	print("----- 通过 %d / 失败 %d -----" % [_pass, _fail])
	get_tree().quit()
