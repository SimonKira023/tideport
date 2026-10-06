extends RefCounted
# ==========================================================================
# 岩石 / 铁矿露头模块 —— 阶段 1-1「拆 scene/game.gd」的第二块（2026-10-06）
#
# 原先这整块就长在 scene/game.gd 里（从「# ---------------- 岩石 / 铁矿露头 ----------------」
# 到 _spawn_rock_drops 为止，外加 _respawn_rocks 与 rebuild_rocks_from_save）。
# 现在整体搬到这里，game.gd 只留一层转调门面
# （_build_rocks / _rock_spot_ok / _on_rock_changed / _on_rock_removed /
#   pick_rock_cell / hit_rock / _respawn_rocks / rebuild_rocks_from_save）。
#
# 职责：开局撒岩石 / 显示节点的增删 / 鼠标挑石 / 敲石结算 / 掉落调度 /
#       每夜补石 / 读档后按存档数据重建节点。数据本身存在 OreVein autoload 里。
#
# ❗为什么本模块是 RefCounted（不是挂 Game 下的 Node2D）：
#   岩石显示节点必须**直接挂在 Game 下**参与根节点 y_sort ——
#   中间套容器会把整片石头当成一个排序单位，前后遮挡立刻乱
#   （AGENTS.md 坑 9；跟 tree_layer.gd 同款原因）。所以这里只持数据与逻辑，
#   节点一律用 _game.add_child() 挂到 Game 身上 —— 与拆分前逐字节一致。
#
# ❗与 Game 的耦合：需要 Game 的能力（_world_to_cell / _cell_tree_pos /
#   is_bridge_cell / _hash2 / _spawn_pickup / _land_set / _sand_set /
#   mine_cell / _dock_cell / _nature_anchors / _near_tilled / _near_structures /
#   ROCK_* / RESPAWN_* 常量等）时统一走 _game 回问。_game 故意**不标类型**，
#   走 GDScript 动态派发（这些成员不在 RefCounted 的静态基类里）。
# ==========================================================================

var rock_nodes := {}      # cell -> rock_node 显示节点
var _game = null          # Game 节点（动态派发，故意不标类型）

func setup(game) -> void:
	_game = game

# 开局撒岩石 / 铁矿露头。固定种子 -> 每次开局长在同样的地方，方便对照改动。
func build() -> void:
	# ❗这个函数可能被调多次（开局一次、开新档 reset 后再补一次）—— 必须幂等
	if OreVein.rock_changed.is_connected(on_changed):
		OreVein.rock_changed.disconnect(on_changed)
	if OreVein.rock_removed.is_connected(on_removed):
		OreVein.rock_removed.disconnect(on_removed)
	for n in rock_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	OreVein.reset()
	rock_nodes.clear()
	OreVein.rock_changed.connect(on_changed)
	OreVein.rock_removed.connect(on_removed)

	# 让位锚点：建筑附近 + 矿井 + 码头 + 屋内那块野地，都不摆石头
	var anchors: Array = []
	for n: Node2D in [_game.get_node("House"), _game.get_node("Merchant"),
			_game.get_node("ShippingBin"), _game.get_node("Player")]:
		anchors.append(_game._world_to_cell(n.global_position))
	anchors.append(_game.mine_cell)
	anchors.append(_game._dock_cell())
	var house: Node2D = _game.get_node("House")
	var inner_from: Vector2i = _game._world_to_cell(house.global_position + Vector2(-16, 272))
	var inner_to: Vector2i = _game._world_to_cell(house.global_position + Vector2(304, 496))

	var rng := RandomNumberGenerator.new()
	rng.seed = _game.ROCK_SEED
	var placed := 0
	for c in _game._land_set.keys():
		if OreVein.rocks.size() >= _game.ROCK_MAX:
			break
		if not spot_ok(c, anchors, inner_from, inner_to):
			continue
		if rng.randf() >= _game.ROCK_DENSITY:
			continue
		var kind: int = OreVein.KIND_ROCK
		if rng.randf() < _game.ROCK_IRON_RATIO:
			kind = OreVein.KIND_IRON
		OreVein.place(c, kind, _game._hash2(c + Vector2i(3, 11)) % 4)
		placed += 1
	print("[矿] 全岛撒了 %d 处岩石/铁矿(上限 %d)" % [placed, _game.ROCK_MAX])

# 这格能不能摆石头：非田、没树、离锚点 3 格开外、四邻都是陆地（三石堆 22 宽会悬到邻格）。
func spot_ok(c: Vector2i, anchors: Array, inner_from: Vector2i, inner_to: Vector2i) -> bool:
	if Farm.tilled.has(c) or _game.is_bridge_cell(c) or Trees.is_blocked(c) or OreVein.is_blocked(c):
		return false
	if _game._sand_set.has(c):          # 沙滩上不长石头
		return false
	for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
		if not _game._land_set.has(nb) or _game.is_bridge_cell(nb):
			return false
	for a in anchors:
		var ac: Vector2i = a
		if maxi(absi(c.x - ac.x), absi(c.y - ac.y)) < 3:
			return false
	if c.x >= inner_from.x and c.x <= inner_to.x and c.y >= inner_from.y and c.y <= inner_to.y:
		return false
	return true

# 每夜补石：复用开局让位判定，再避开耕田周边一格、玩家建筑周边一格。
func respawn() -> void:
	if OreVein.rocks.size() >= _game.ROCK_MAX:
		return
	var anchors: Array = _game._nature_anchors()
	var house: Node2D = _game.get_node("House")
	var inner_from: Vector2i = _game._world_to_cell(house.global_position + Vector2(-16, 272))
	var inner_to: Vector2i = _game._world_to_cell(house.global_position + Vector2(304, 496))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var land: Array = _game._land_set.keys()
	if land.is_empty():
		return
	var spawned := 0
	for _try in _game.RESPAWN_TRIES:
		if spawned >= _game.RESPAWN_ROCKS_PER_DAY or OreVein.rocks.size() >= _game.ROCK_MAX:
			break
		var c: Vector2i = land[rng.randi() % land.size()]
		if not spot_ok(c, anchors, inner_from, inner_to):
			continue
		if _game._near_tilled(c, 1) or _game._near_structures(c, 1):
			continue
		var kind: int = OreVein.KIND_ROCK
		if rng.randf() < _game.ROCK_IRON_RATIO:
			kind = OreVein.KIND_IRON
		if OreVein.place(c, kind, _game._hash2(c + Vector2i(3, 11)) % 4):
			spawned += 1
	if spawned > 0:
		print("[矿] 清晨长回了 %d 处岩石(全岛 %d)" % [spawned, OreVein.rocks.size()])

func on_changed(c: Vector2i) -> void:
	if not OreVein.rocks.has(c):
		return
	var r: Dictionary = OreVein.rocks[c]
	var n: Node2D = rock_nodes.get(c)
	if n == null:
		n = preload("res://scene/rock_node.gd").new()
		n.name = "Rock%d_%d" % [c.x, c.y]
		n.cell = c
		n.kind = int(r.kind)
		n.variant = int(r.variant)
		n.position = _game._cell_tree_pos(c)   # 跟树一样：底部踩在格子底边（y_sort 排序点）
		_game.add_child(n)
		rock_nodes[c] = n

func on_removed(c: Vector2i) -> void:
	var n: Node2D = rock_nodes.get(c)
	if n == null:
		return
	rock_nodes.erase(c)
	n.play_broken()      # 原地小跳 + 淡出，掉落由 hit 生成

# 鼠标指的是哪块石头（player 挥镐前先问这句）。跟 pick_tree_cell 同一套退让：
# ① 按贴图矩形命中（1:1 视觉最高 22x16，留点余量好点中）② 鼠标那一格 ③ 玩家身边一圈。
func pick_cell(mouse_world: Vector2, fallback: Vector2i) -> Vector2i:
	var player: Node2D = _game.get_node("Player")
	var on_self: bool = mouse_world.distance_to(player.global_position) < float(Farm.TILE_SIZE)
	var best := fallback
	var best_d := INF
	if not on_self:
		for key in rock_nodes.keys():
			var n: Node2D = rock_nodes[key]
			if n == null or not is_instance_valid(n):
				continue
			var base: Vector2 = n.global_position
			# 石头矩形：原点在石头底部（三石堆 22x16），向上 18、向下 2、左右各 11
			if not Rect2(base + Vector2(-11.0, -18.0), Vector2(22.0, 20.0)).has_point(mouse_world):
				continue
			var d: float = base.distance_squared_to(mouse_world)
			if d < best_d:
				best_d = d
				best = key
		if best_d < INF:
			return best
	if OreVein.has_rock(fallback):
		return fallback
	var pc: Vector2i = _game._world_to_cell(player.global_position)
	var near := fallback
	var nd := INF
	for around in [fallback, pc]:
		var b: Vector2i = around
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c: Vector2i = b + Vector2i(dx, dy)
				if not OreVein.has_rock(c):
					continue
				var d2: float = Vector2(c - pc).length_squared()
				if d2 < nd:
					nd = d2
					near = c
	if nd < INF:
		return near
	return fallback

# 敲一下（player 手持镐子点石头时调）。返回 OreVein.hit 的结算，掉落物在这里生成。
func hit(c: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res: Dictionary = OreVein.hit(c, rng)
	match int(res.result):
		OreVein.RESULT_HIT:
			var n: Node2D = rock_nodes.get(c)
			if n != null:
				n.shake()
				n.chip_burst()   # 石屑带黑描边，受重力掉下来
		OreVein.RESULT_BROKEN:
			_spawn_drops(c, int(res.stone), int(res.iron))
	return res

func _spawn_drops(c: Vector2i, stone: int, iron: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stone_item: ItemData = load("res://item/stone.tres")
	var iron_item: ItemData = load("res://item/iron_ore.tres")
	var base: Vector2 = _game._cell_tree_pos(c)
	for i in stone:
		_game._spawn_pickup(stone_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))
	for i in iron:
		_game._spawn_pickup(iron_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))

# 读档还原：先全拆显示节点，再按存档里的 OreVein.rocks 逐格补。
# ❗save_manager._apply 里已经调过一次；这里做成幂等（重复调用不炸也不翻倍）。
func rebuild_from_save() -> void:
	for c in rock_nodes.keys():
		var n: Node = rock_nodes[c]
		if is_instance_valid(n):
			n.queue_free()
	rock_nodes.clear()
	for c in OreVein.rocks.keys():
		on_changed(c)
