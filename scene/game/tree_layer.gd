extends RefCounted
# ==========================================================================
# 树木模块 —— 阶段 1-1「拆 scene/game.gd」的第一块试点（2026-10-06）
#
# 原先这整块就长在 scene/game.gd 里（从「# ---------------- 树木 ----------------」
# 到 _spawn_tree_drops 为止）。现在整体搬到这里，game.gd 只留一层转调门面
# （_build_trees / _tree_spot_ok / _on_tree_changed / _on_tree_removed /
#   pick_tree_cell / hit_tree / rebuild_trees_from_save）。
#
# 职责：开局撒树 / 树显示节点的增删 / 鼠标挑树 / 砍树结算 / 木屑与掉落调度 /
#       读档后按存档数据重建节点。数据本身仍然存在 Trees autoload 里。
#
# ❗为什么本模块是 RefCounted 而不是挂在 Game 下的 Node2D：
#   树的显示节点必须**直接挂在 Game 下**参与 Game 根节点的 y_sort
#   （AGENTS.md 坑 9：中间套一层容器会把整片树林当成一个排序单位，
#    前后遮挡立刻错乱）。所以这里只持数据与逻辑，节点一律用
#   _game.add_child() 挂到 Game 身上 —— 与拆分前逐字节一致，y_sort 不受影响。
#
# ❗与 Game 的耦合：需要 Game 的能力（_world_to_cell / _cell_tree_pos /
#   is_bridge_cell / _hash2 / _spawn_pickup / shake_screen / _land_set /
#   _sand_set / TREE_* 常量 / $Player / $House 等）时统一走 _game 回问。
#   _game 故意**不标类型**，走 GDScript 动态派发（这些成员不在 RefCounted
#   的静态基类里）。这是拆分的临时代价：等 _world_to_cell / _cell_tree_pos
#   这类通用工具搬进独立工具模块后，耦合面可以收窄。
# ==========================================================================

var tree_nodes := {}      # cell -> tree_node 显示节点
var _falling_cells := {}  # 正在播「倒下动画」的格子：cell -> 待换的 stage
var _game = null          # Game 节点（动态派发，故意不标类型）

func setup(game) -> void:
	_game = game

# 开局撒树。固定种子 -> 每次开局树长在同样的地方，方便对照改动。
func build() -> void:
	# ❗这个函数可能被调多次（开局一次、开新档 reset 后再补一次）—— 必须幂等：
	#   旧信号连接要断掉（不然 tree_changed 发两次），旧节点要真拆掉
	#   （tree_nodes.clear() 只清字典，屏幕上的树会变成"看得见砍不着"的幽灵）。
	if Trees.tree_changed.is_connected(on_changed):
		Trees.tree_changed.disconnect(on_changed)
	if Trees.tree_removed.is_connected(on_removed):
		Trees.tree_removed.disconnect(on_removed)
	for n in tree_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	Trees.reset()
	tree_nodes.clear()
	_falling_cells.clear()
	Trees.tree_changed.connect(on_changed)
	Trees.tree_removed.connect(on_removed)

	# 建筑锚点：附近 4 格不种树。屋身有 5x7 格那么大，给它两个锚点（屋根 + 门口）。
	var house: Node2D = _game.get_node("House")
	var anchors: Array = []
	for key in ["House", "Merchant", "ShippingBin", "Player"]:
		var nd: Node2D = _game.get_node(key)
		anchors.append(_game._world_to_cell(nd.global_position))
	anchors.append(_game._world_to_cell(house.to_global(Vector2(40, -100))))
	anchors.append(_game._world_to_cell(house.to_global(Vector2(50, 28))))
	# ❗室内那块「屋子」在**世界坐标里是真实存在的野地**（屋下 288px 起），
	#   树要是长在那儿，进屋后会有一棵树穿墙画在房间里。整块都避开。
	var inner_from: Vector2i = _game._world_to_cell(house.global_position + Vector2(-16, 272))
	var inner_to: Vector2i = _game._world_to_cell(house.global_position + Vector2(304, 496))

	var noise := FastNoiseLite.new()
	noise.seed = _game.TREE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = _game.TREE_NOISE_FREQ
	var rng := RandomNumberGenerator.new()
	rng.seed = _game.TREE_SEED
	var placed := 0
	for c in _game._land_set.keys():
		if Trees.trees.size() >= _game.TREE_MAX:
			break
		if not spot_ok(c, anchors, inner_from, inner_to):
			continue
		var nv := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
		var density: float = smoothstep(0.35, 0.9, nv) * _game.TREE_DENSITY
		if rng.randf() >= density:
			continue
		var r := rng.randf()
		var stage: int = Trees.ST_MATURE
		if r < 0.12:
			stage = Trees.ST_SAPLING
		elif r < 0.32:
			stage = Trees.ST_YOUNG
		Trees.plant(c, _game._hash2(c + Vector2i(7, 13)) % 2, stage)
		placed += 1
	print("[树] 全岛种了 %d 棵(上限 %d)" % [placed, _game.TREE_MAX])

# 这格能不能长树：非田、离桥远、四邻都是陆地（树冠 32 宽，悬到水里很怪）、
# 离建筑锚点 4 格开外、不压室内。
func spot_ok(c: Vector2i, anchors: Array, inner_from: Vector2i, inner_to: Vector2i) -> bool:
	if Farm.tilled.has(c) or _game.is_bridge_cell(c):
		return false
	if _game._sand_set.has(c):          # 沙滩上不长树
		return false
	for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
		if not _game._land_set.has(nb) or _game.is_bridge_cell(nb):
			return false
	for a in anchors:
		var ac: Vector2i = a
		if maxi(absi(c.x - ac.x), absi(c.y - ac.y)) < 4:
			return false
	if c.x >= inner_from.x and c.x <= inner_to.x and c.y >= inner_from.y and c.y <= inner_to.y:
		return false
	return true

func on_changed(c: Vector2i) -> void:
	if not Trees.trees.has(c):
		return
	var t: Dictionary = Trees.trees[c]
	if _falling_cells.has(c):
		_falling_cells[c] = int(t.stage)     # 倒下动画播完再换贴图（见 hit）
		return
	var n: Node2D = tree_nodes.get(c)
	if n == null:
		n = preload("res://scene/tree_node.gd").new()
		n.name = "Tree%d_%d" % [c.x, c.y]
		n.cell = c
		n.variant = int(t.variant)
		n.position = _game._cell_tree_pos(c)
		_game.add_child(n)
		tree_nodes[c] = n
	n.apply_stage(int(t.stage))

func on_removed(c: Vector2i) -> void:
	var n: Node2D = tree_nodes.get(c)
	if n == null:
		return
	tree_nodes.erase(c)
	n.play_pop()      # 幼苗被刨走 / 树桩被敲碎：小跳一下消失

# 鼠标指着的是哪棵树（player 挥斧头前先问这一句）。
#
# ❗树的贴图是 32x48、底边对齐节点原点，也就是**视觉上比它注册的那一格高出近 3 格**
#   （树冠悬在格子上方）。玩家对着树冠点下去，坐标换算出来的是树顶上方的空格，
#   于是"这里没有能砍的树" —— 树明明就在眼前。
#   所以判定不能拿「鼠标 -> 格子」的格子去查表，得按贴图矩形命中，所见即所砍。
#
# 依次退让：① 鼠标压在哪棵树上 ② 鼠标那一格有树（幼苗/树桩贴图贴地，这步接得住）
#          ③ 鼠标格和玩家格周围一圈里最近的树（接住"站在树前面直接按使用键"）
# 都没找到就原样返回 fallback，让 hit 老实报 MISS。
func pick_cell(mouse_world: Vector2, fallback: Vector2i) -> Vector2i:
	# 鼠标就搁在自己身上时，"指哪砍哪"没有指向性 —— 玩家按使用键常常压根没挪鼠标。
	# 这时跳过①直接看身边那棵，免得被"头顶上悬着的那棵（别人）的树冠"截胡。
	var player: Node2D = _game.get_node("Player")
	var on_self: bool = mouse_world.distance_to(player.global_position) < float(Farm.TILE_SIZE)

	var best := fallback
	var best_d := INF
	if not on_self:
		for key in tree_nodes.keys():
			var n: Node2D = tree_nodes[key]
			if n == null or not is_instance_valid(n):
				continue
			var base: Vector2 = n.global_position
			# 贴图范围：节点原点在树干底部（TRUNK_BASE_Y=45 那行），
			# 于是向上 45、向下 3、左右各 16（见 tree_node.FRAME_W/H、TRUNK_BASE_Y）
			if not Rect2(base + Vector2(-16.0, -45.0), Vector2(32.0, 48.0)).has_point(mouse_world):
				continue
			var d: float = base.distance_squared_to(mouse_world)
			if d < best_d:
				best_d = d
				best = key
		if best_d < INF:
			return best

	if Trees.has_tree(fallback):
		return fallback

	var pc: Vector2i = _game._world_to_cell(player.global_position)
	var near := Vector2i.ZERO
	var nd := INF
	for around in [fallback, pc]:
		var b: Vector2i = around
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = b + Vector2i(dx, dy)
				if not Trees.has_tree(c):
					continue
				var d2: float = Vector2(c - pc).length_squared()
				if d2 < nd:
					nd = d2
					near = c
	if nd < INF:
		return near
	return fallback

# 砍一下（player 手持斧头点树时调）。返回 Trees.hit 的结算，掉落物在这里生成。
func hit(c: Vector2i) -> Dictionary:
	var was_mature: bool = Trees.has_tree(c) and int(Trees.trees[c].stage) == Trees.ST_MATURE
	if was_mature:
		# ❗先挂起再砍：Trees.hit 里会发 tree_changed（换成树桩贴图），
		#   挂起让那条更新先记着，等倒下动画播完再补树桩节点。
		_falling_cells[c] = Trees.ST_STUMP
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res: Dictionary = Trees.hit(c, rng, Research.chop_power())
	if int(res.result) != Trees.RESULT_FELLED:
		_falling_cells.erase(c)              # 没砍倒（RESULT_HIT / MISS），挂起作废
	match int(res.result):
		Trees.RESULT_HIT:
			var n: Node2D = tree_nodes.get(c)
			if n != null:
				n.shake()
				n.chip_burst()       # 木屑带黑描边，受重力掉下来
		Trees.RESULT_FELLED:
			var n2: Node2D = tree_nodes.get(c)
			if was_mature and n2 != null:
				tree_nodes.erase(c)
				n2.fell_done.connect(_on_fell_done)
				n2.play_fell()
				_game.shake_screen(2.0, 0.25)   # e33d 树倒震屏
	# 科技树加成：锻铁斧 +1 / 木匠行会 +2（见 research.gd）—— 必须放在 match 之外
	var wood: int = int(res.wood)
	if wood > 0:
		wood += Research.wood_bonus()
	var seeds: int = int(res.seeds)
	if wood > 0 or seeds > 0:
		_spawn_drops(c, wood, seeds)
	return res

func _on_fell_done(c: Vector2i) -> void:
	_falling_cells.erase(c)
	on_changed(c)      # 补上树桩节点

func _spawn_drops(c: Vector2i, wood: int, seeds: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var wood_item: ItemData = load("res://item/wood.tres")
	var seed_item: ItemData = load("res://item/tree_seed.tres")
	var base: Vector2 = _game._cell_tree_pos(c)
	for i in wood:
		_game._spawn_pickup(wood_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))
	for i in seeds:
		_game._spawn_pickup(seed_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))

# 读档还原：先全拆显示节点，再按存档里的 Trees.trees 逐格补。
# ❗save_manager._apply 里已经调过一次；这里做成幂等（重复调用不炸也不翻倍）。
func rebuild_from_save() -> void:
	for c in tree_nodes.keys():
		var n: Node = tree_nodes[c]
		if is_instance_valid(n):
			n.queue_free()
	tree_nodes.clear()
	_falling_cells.clear()
	for c in Trees.trees.keys():
		on_changed(c)      # 走正常信号路径建节点，跟开局撒树同一套代码
