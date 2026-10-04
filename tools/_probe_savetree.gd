# tools/_probe_savetree.gd —— 探针：存档 -> 模拟重启 -> 读档 -> 真实左键砍树
#
# 背景：干净场景下鼠标左键能砍树（_probe_click 全过）、自检全过，
#       但真实游戏"树木无法被砍伐"。最大未验证路径 = 读档后。
# 跑法：EXE --headless --path . res://tools/_probe_savetree.tscn
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
	print("===== 存读档链路砍树 探针 =====")
	SaveManager.enabled = true
	SaveManager.save_path = "user://_probe_savetree/save.json"
	SaveManager.history_dir = "user://_probe_savetree/hist"
	SaveManager.slot_dir = "user://_probe_savetree/slots"
	DirAccess.remove_absolute(SaveManager._abs("user://_probe_savetree"))

	# ---------- 第一局：新档 ----------
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node2D = g.get_node("Player")

	# 种一棵成树当靶子
	var tc := Vector2i(-999, -999)
	for k in g._land_set.keys():
		var kk: Vector2i = k
		if g.is_water(kk) or g.is_bridge_cell(kk) or Farm.tilled.has(kk):
			continue
		var clean := true
		for dy in range(-2, 2):
			for dx in range(-2, 3):
				var n: Vector2i = kk + Vector2i(dx, dy)
				if Trees.is_blocked(n) or g.is_water(n):
					clean = false
		if clean and Trees.plant(kk, 0, Trees.ST_MATURE):
			tc = kk
			break
	chk(tc.x != -999, "第一局: 靶子树种在 %s" % tc)
	if tc.x == -999:
		_finish()
		return
	await get_tree().process_frame
	await get_tree().process_frame

	player.current_item = load("res://item/axe.tres")
	place_player(g, tc + Vector2i(0, 1))
	var node: Node2D = g.tree_nodes[tc]
	var crown: Vector2 = node.global_position + Vector2(0, -30)
	var vp: Vector2 = g.get_viewport().get_canvas_transform() * crown
	var hp0 := int(Trees.trees[tc].hp)
	_click(g, vp)
	await get_tree().process_frame
	await get_tree().process_frame
	chk(int(Trees.trees[tc].hp) == hp0 - 1, "第一局: 真实点击砍一斧 %d -> %d" % [hp0, int(Trees.trees[tc].hp)])

	var key_type := typeof(Trees.trees.keys()[0])
	print("  第一局: 树键类型 = %s (Vector2i=%d)" % [key_type, TYPE_VECTOR2I])

	# ---------- 存档 ----------
	var saved := SaveManager.save_game(g)
	chk(saved, "存档成功 (%s)" % SaveManager.save_path)
	print("  存档里树的记录: %s" % str(JSON.stringify(_read_json(SaveManager._abs(SaveManager.save_path)).get("trees", []))))

	# ---------- 模拟重启：拆场景、清 autoload ----------
	g.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	Trees.reset()
	Farm.clear_all()
	Floor.clear_all()
	chk(Trees.trees.is_empty(), "重启后: 树数据已清")

	# ---------- 第二局：_ready 自动读档 ----------
	var g2: Node = load("res://scene/game.tscn").instantiate()
	add_child(g2)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var player2: Node2D = g2.get_node("Player")

	chk(Trees.trees.size() > 0, "第二局: 树数据恢复 (%d 棵)" % Trees.trees.size())
	var kt2 := TYPE_NIL
	for k in Trees.trees.keys():
		kt2 = typeof(k)
		break
	chk(kt2 == TYPE_VECTOR2I, "第二局: 树键类型 = %s (应 Vector2i=%d)" % [kt2, TYPE_VECTOR2I])
	chk(Trees.has_tree(tc), "第二局: 靶子树 %s 还在" % tc)
	if not Trees.has_tree(tc):
		_finish()
		return
	chk(int(Trees.trees[tc].hp) == hp0 - 1, "第二局: 耐久保持 %d (存档时砍过)" % int(Trees.trees[tc].hp))
	chk(g2.tree_nodes.has(tc), "第二局: 靶子树有显示节点")
	chk(Trees.stage_of(tc) == Trees.ST_MATURE, "第二局: 阶段 = 成树 (%d)" % Trees.stage_of(tc))

	# ---------- 第二局真实点击 ----------
	if not g2.tree_nodes.has(tc):
		_finish()
		return
	var node2: Node2D = g2.tree_nodes[tc]
	var crown2: Vector2 = node2.global_position + Vector2(0, -30)
	var vp2: Vector2 = g2.get_viewport().get_canvas_transform() * crown2
	var blockers := _find_blockers(g2, vp2)
	if blockers.is_empty():
		print("  [ok] 第二局: 树冠点无 Control 拦截")
	else:
		print("  [!!] 第二局: 拦截 %s 的 Control:" % vp2)
		for b in blockers:
			print("      - %s in_tree=%s mf=%d rect=%s" % [b, b.is_visible_in_tree(), b.mouse_filter, b.get_global_rect()])
	player2.current_item = load("res://item/axe.tres")
	place_player(g2, tc + Vector2i(0, 1))
	var hp2 := int(Trees.trees[tc].hp)
	_click(g2, vp2)
	await get_tree().process_frame
	await get_tree().process_frame
	chk(int(Trees.trees[tc].hp) == hp2 - 1, "第二局: 真实点击砍一斧 %d -> %d" % [hp2, int(Trees.trees[tc].hp)])
	_finish()

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _click(g: Node, vp_pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = vp_pos
	down.global_position = vp_pos
	g.get_viewport().push_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = vp_pos
	up.global_position = vp_pos
	g.get_viewport().push_input(up)

func _find_blockers(g: Node, vp_pos: Vector2) -> Array:
	var out: Array = []
	var stack: Array = [g.get_viewport()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			if c.mouse_filter == Control.MOUSE_FILTER_STOP \
					and c.get_global_rect().has_point(vp_pos):
				out.append(c)
	return out

func place_player(g: Node, cell: Vector2i) -> void:
	var player: Node2D = g.get_node("Player")
	var cs: CollisionShape2D = player.get_node("CollisionShape2D")
	player.global_position = Farm.grid_origin \
		+ Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5) - cs.position

func _finish() -> void:
	print("----- 通过 %d / 失败 %d -----" % [_pass, _fail])
	get_tree().quit()
