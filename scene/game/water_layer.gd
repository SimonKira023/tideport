extends RefCounted
# ==========================================================================
# 水面模块 —— 阶段 1-1「拆 scene/game.gd」的第五块（2026-10-06）
#
# 原先这整块长在 scene/game.gd 的
# 「# ---------------- 水面绘制 ----------------」与「# ---------------- 水碰撞 ----------------」两节里。
# 现在整体搬到这里，game.gd 只留两层转调门面（_paint_water / _build_water_collision）。
#
# 职责：
#   1. 水面绘制：程序化生成水图集（横轴 = 深浅档，纵轴 = 波纹变体），按
#      「离岸多远」的 BFS 分档铺到 water_layer 上，最外圈一律最深色。
#   2. 水碰撞：把水格用贪心矩形合并成一组 16px 整倍数矩形，挂到
#      StaticBody2D 上；再给每座桥砌两条 4px 薄墙（桥带三行是豁口，
#      但桥本身得是实心的，不能从桥带直接踏进河里）。
#
# ❗为什么 water_layer 节点与微澜动画状态仍留 Game：
#   _apply_layer_z() 要按 z_index 统一收口（Z_WATER）；
#   _tick_water_ripple() 每帧要轮换波纹变体（_water_anim_cells / _water_anim_lv）。
#   所以这里只负责「建图集 + 铺格 + 建碰撞」，节点一律 _game.add_child()。
#
# ❗与 Game 的耦合：需要 Game 的能力（water_layer / grid_layer / _water_set /
#   _hash2 / _cross / _is_water_like / _at_map_edge / _bridge_x0 / _bridge_x1 /
#   is_swim_water / _water_anim_cells / _water_anim_lv / WATER_* / COAST_SEED /
#   Z_WATER / BRIDGE_* 常量）时统一走 _game 回问。
#   _game 故意**不标类型**，走 GDScript 动态派发 —— 所以凡是从 `g.` 取回来的值，
#   要用 `:=` 时必须先想清楚是不是 Variant（AGENTS.md 坑 1：会撞 Parse Error），
#   本文件一律写显式类型。
# ==========================================================================

var _game = null          # Game 节点（动态派发，故意不标类型）

func setup(game) -> void:
	_game = game

# ---------------- 水面绘制 ----------------
func paint_water() -> void:
	var g = _game
	var tsz: Vector2i = g.grid_layer.tile_set.tile_size
	g.water_layer.clear()
	g.water_layer.tile_set = make_water_tileset(tsz)
	g.water_layer.z_index = g.Z_WATER   # 地形层一律负 z_index，见 _apply_layer_z()
	g._water_anim_cells.clear()       # e33b 微澜轮换的花名册跟着重铺
	g._water_anim_lv.clear()

	if g._water_set.is_empty():
		return
	var depth := water_depth_map()
	# 深浅分档不能按整数一刀切 —— 那样窄河里会出现一条条笔直的色带；
	# 早先用的「随机把某一格升一档」又会变成一个个方块。
	# 正解是叠一层平滑噪声，让分档边界变成波浪线（水看起来才像在流动）。
	var wob := FastNoiseLite.new()
	wob.seed = g.COAST_SEED + 4242
	wob.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wob.frequency = 0.13
	var last: int = g.WATER_DEPTHS.size() - 1
	for c in g._water_set.keys():
		var d: int = depth.get(c, 1)
		var f: float = float(d) - 1.0 + wob.get_noise_2d(float(c.x), float(c.y)) * 0.9
		var lv: int = clampi(int(floor(f + 0.5)), 0, last)
		# e51: 地图最外圈一律画成最深色 —— 那一圈不放人下水（见 is_swim_water）
		if g._at_map_edge(c):
			lv = last
		var v: int = g._hash2(c + Vector2i(31, 17)) % g.WATER_VARIANTS
		g.water_layer.set_cell(c, g.WATER_SRC, Vector2i(lv, v))
		g._water_anim_cells.append(c)     # e33b 记下这格的深浅档, 轮换时只换变体
		g._water_anim_lv[c] = lv

# 每格水离岸多远（多源 BFS，4 邻域）。
# 只有「地图内的陆地」才算岸 —— 地图外当作海继续延伸（见 _is_water_like）。
func water_depth_map() -> Dictionary:
	var g = _game
	var dist := {}
	var frontier := []
	for c in g._water_set.keys():
		dist[c] = g.WATER_MAX_DIST
		for nb in g._cross(c):
			if not g._is_water_like(nb):
				dist[c] = 1
				frontier.append(c)
				break
	var d := 1
	while not frontier.is_empty() and d < g.WATER_MAX_DIST:
		var nxt := []
		for c in frontier:
			for nb in g._cross(c):
				if g._water_set.has(nb) and int(dist[nb]) > d + 1:
					dist[nb] = d + 1
					nxt.append(nb)
		frontier = nxt
		d += 1
	return dist

# 生成水面图集：横轴 = 深浅档，纵轴 = 波纹变体
func make_water_tileset(tsz: Vector2i) -> TileSet:
	var g = _game
	var img := Image.create_empty(
		g.WATER_DEPTHS.size() * tsz.x, g.WATER_VARIANTS * tsz.y, false, Image.FORMAT_RGBA8)
	for d in g.WATER_DEPTHS.size():
		for v in g.WATER_VARIANTS:
			draw_water_tile(img, d * tsz.x, v * tsz.y, d, v, tsz)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(img)
	for d in g.WATER_DEPTHS.size():
		for v in g.WATER_VARIANTS:
			atlas.create_tile(Vector2i(d, v))
	var ts := TileSet.new()
	ts.tile_size = tsz
	ts.add_source(atlas, g.WATER_SRC)
	return ts

# 一格水：底色是该深浅档的基色，内部画几道轻微的波纹；
# 四周 WATER_EDGE 像素保持纯基色 —— 这是「拼起来看不出接缝」的关键。
func draw_water_tile(img: Image, ox: int, oy: int, depth: int, variant: int, tsz: Vector2i) -> void:
	var g = _game
	var base: Color = g.WATER_DEPTHS[depth]
	for y in tsz.y:
		for x in tsz.x:
			img.set_pixel(ox + x, oy + y, base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717 + depth * 31 + variant * 101
	var inner_x: int = tsz.x - g.WATER_EDGE * 2
	var inner_y: int = tsz.y - g.WATER_EDGE * 2
	if inner_x <= 2 or inner_y <= 2:
		return
	for _i in 3:
		var x0: int = g.WATER_EDGE + rng.randi() % maxi(inner_x - 3, 1)
		var y0: int = g.WATER_EDGE + rng.randi() % inner_y
		var ln: int = 3 + rng.randi() % 4
		var up: bool = rng.randf() < 0.5
		for k in ln:
			var px: int = x0 + k
			if px >= tsz.x - g.WATER_EDGE:
				break
			var col: Color = base.lightened(g.WATER_RIPPLE) if up else base.darkened(g.WATER_RIPPLE)
			img.set_pixel(ox + px, oy + y0, col)

# ---------------- 水碰撞 ----------------
# 把 _water_set 的水格用「贪心矩形合并」打包成一组 16px 整倍数矩形，
# 然后挂到一个 StaticBody2D + N 个 RectangleShape2D 上。
#   矩形合并：扫到水格，先往右扩到不能再扩，再往下扩到不能再扩，标记已访问。
#   不是最小矩形数（那是 NP-hard），但够紧凑（一个小岛地图能合并到几十个矩形）。
#
#   桥面 + 桥头引道那几格不算水碰撞 —— 否则玩家从桥上走会被水碰撞顶死。
#   f3: 桥带三行 (y-1/y/y+1) + 引道全豁口, 三行桥带全可走; 上一版的 BridgeWalls
#     隐形墙已拆 (桥不再只许走一行, 游泳也能正常横穿桥带)。
func build_water_collision() -> void:
	var g = _game
	if g._water_set.is_empty():
		return
	var bridge_cells := {}
	for y in g.BRIDGE_ROWS:
		var x0: int = g._bridge_x0(y)
		var x1: int = g._bridge_x1(y)
		for x in range(x0 - g.BRIDGE_APPROACH, x1 + g.BRIDGE_APPROACH + 1):
			for dy in [-1, 0, 1]:                        # 桥段三行全放行（河面豁口）
				bridge_cells[Vector2i(x, y + dy)] = true
	var water_for_collide := {}
	for c in g._water_set.keys():
		# e51: 桥带豁口 + 「能下水」的格子都放行 —— 桥面照旧能走, 水面能蹚能游
		#      （游泳动作见 player.gd）。只有最深那一档海格留着挡人 -> 游不出海。
		if not bridge_cells.has(c) and not g.is_swim_water(c):
			water_for_collide[c] = true

	var rects := merge_water_rects(water_for_collide)
	var container := Node2D.new()
	container.name = "WaterCollision"
	container.position = g.grid_layer.position
	g.add_child(container)
	var sb := StaticBody2D.new()
	sb.name = "WaterBodies"           # 起个名字，自检查「撞到的是不是水」时好认
	container.add_child(sb)
	for r in rects:
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(r.size.x * 16, r.size.y * 16)
		cs.shape = sh
		cs.position = Vector2(r.position.x * 16 + sh.size.x * 0.5, r.position.y * 16 + sh.size.y * 0.5)
		sb.add_child(cs)

	# g5: 桥沿薄墙 —— 桥带三行是豁口, 但桥得是实心的: 不能从桥带直接踏进河里,
	#     也不能从河里游进桥底下。给每座桥的视觉跨度 (x0..x1) 砌两条 4px 薄横墙:
	#       北墙贴上桥带行 (y-1) 顶部 4px
	#       南墙贴下桥带行 (y+1) 底部 4px
	#     b6 修: 原先「墙外侧那格是水才砌」把落在岸上的桥头两格漏成了能穿行的
	#     豁口 —— 陆上桥头的栏杆也得拦人, 现在全跨度无条件砌, 想绕就沿引道外
	#     侧 (x0-1/x1+1 列) 走。东西向过桥 (沿 y 行) 不受影响; 站在桥带边上的
	#     碰撞圆跟墙只叠 ~2px, 顶多被微推。
	var rails := StaticBody2D.new()
	rails.name = "BridgeRails"
	container.add_child(rails)
	var rail_count := 0
	for y in g.BRIDGE_ROWS:
		var bx0: int = g._bridge_x0(y)
		var bx1: int = g._bridge_x1(y)
		for x in range(bx0, bx1 + 1):
			var rcn := CollisionShape2D.new()
			var shn := RectangleShape2D.new()
			shn.size = Vector2(16, 4)
			rcn.shape = shn
			rcn.position = Vector2(x * 16 + 8, (y - 1) * 16 + 2)
			rails.add_child(rcn)
			rail_count += 1
			var rcs := CollisionShape2D.new()
			var shs := RectangleShape2D.new()
			shs.size = Vector2(16, 4)
			rcs.shape = shs
			rcs.position = Vector2(x * 16 + 8, (y + 2) * 16 - 2)
			rails.add_child(rcs)
			rail_count += 1
	print("[水碰撞] %d 块矩形(共 %d 格), 桥带豁口 + 桥沿薄墙 %d 条" % [rects.size(), water_for_collide.size(), rail_count])

# 贪心矩形合并：扫到一个水格 → 横扩到最长 → 竖扩到最长 → 标记访问
func merge_water_rects(lookup: Dictionary) -> Array:
	var visited := {}
	var rects: Array = []
	for c in lookup.keys():
		if visited.has(c):
			continue
		var cv: Vector2i = c
		var x0: int = cv.x
		var x1: int = cv.x
		while lookup.has(Vector2i(x1 + 1, cv.y)) and not visited.has(Vector2i(x1 + 1, cv.y)):
			x1 += 1
		var y1: int = cv.y
		while true:
			var all := true
			for x in range(x0, x1 + 1):
				if not lookup.has(Vector2i(x, y1 + 1)) or visited.has(Vector2i(x, y1 + 1)):
					all = false
					break
			if not all:
				break
			y1 += 1
		for x in range(x0, x1 + 1):
			for y in range(cv.y, y1 + 1):
				visited[Vector2i(x, y)] = true
		rects.append(Rect2i(x0, cv.y, x1 - x0 + 1, y1 - cv.y + 1))
	return rects
