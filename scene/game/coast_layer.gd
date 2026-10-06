extends RefCounted
# ==========================================================================
# 岸线模块 —— 阶段 1-1「拆 scene/game.gd」的第四块（2026-10-06）
#
# 原先这整块长在 scene/game.gd 的
# 「# ---------------- 岸：草地 <-> 水 的过渡 ----------------」一节里。
# 现在整体搬到这里，game.gd 只留一层转调门面
# （_build_beach / _build_shore / _edge_mask / _sand_grass_mask / _grass_sand_mask）。
#
# 职责：把「草地 <-> 水」的硬边用两层渐变藏掉
#   beach（陆地侧）：贴水的草地格上，朝水那侧铺一条沙色渐变
#   shore（水面侧）：贴岸的水格上，朝岸那侧铺一条由浅到深的浅滩
# 两层拼起来就是「草地 -> 沙 -> 浅水 -> 深水」，硬边藏在渐变了。
#
# ❗为什么图层节点仍挂在 Game 下、字段也仍留在 Game 上：
#   _apply_layer_z() 要按 z_index 统一收口（Z_BEACH / Z_SHORE），
#   _build_bridges() 要按**节点顺序**把桥插在 shore_layer 之后
#   （AGENTS.md 坑 9：z/顺序错了整片会沉下去）。
#   所以这里只负责「建节点 + 铺格」，节点一律 _game.add_child()，
#   并把结果写回 _game.beach_layer / _game.shore_layer。
#
# ❗与 Game 的耦合：需要 Game 的能力（grid_layer / water_layer / _water_set /
#   _land_set / _sand_set / _hash2 / _in_yard / BEACH_* / SHORE_* / SAND_*
#   常量）时统一走 _game 回问。_game 故意**不标类型**，走 GDScript 动态派发。
# ==========================================================================

var _game = null          # Game 节点（动态派发，故意不标类型）

func setup(game) -> void:
	_game = game

# ---------------- 陆地侧沙滩 ----------------
func build_beach() -> void:
	var g = _game
	if g.grid_layer.tile_set == null:
		return
	var tsz: Vector2i = g.grid_layer.tile_set.tile_size
	# 生成陆地侧沙滩：
	#   (i, 0) i=0..15  透明底渐变带（草地格朝水侧的湿沙）
	#   (i, 1) i=0..15  实心沙底 + 朝水湿沙带（沙滩格贴水的一侧）
	#   (16,1)/(17,1)   纯沙两种变体（沙滩内格：一种带杂点）
	#   (i, 2) i=0..15  实心沙底 + 朝草地淡出带（沙滩和草地的交界）
	#   (i, 3) i=0..15  透明底 + 朝沙侧的沙色淡入带（贴沙的草地格, 草地↔沙地的第二级过渡）
	var sheet := Image.create_empty(18 * tsz.x, 4 * tsz.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in 16:
		draw_band_tile(sheet, i * tsz.x, 0, i, tsz, g.BEACH_BAND)
	for i in 16:
		fill_sand_tile(sheet, i * tsz.x, tsz.y, tsz, i)   # 先铺沙底
		draw_band_tile(sheet, i * tsz.x, tsz.y, i, tsz, g.BEACH_BAND)
	for v in 2:
		fill_sand_tile(sheet, (16 + v) * tsz.x, tsz.y, tsz, -1, v)
	for i in 16:
		fill_sand_tile(sheet, i * tsz.x, 2 * tsz.y, tsz, i)
		draw_band_tile(sheet, i * tsz.x, 2 * tsz.y, i, tsz, g.SAND_FADE)
	for i in 16:
		draw_band_tile(sheet, i * tsz.x, 3 * tsz.y, i, tsz, g.SAND_FADE)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(sheet)
	for y in 4:
		for i in 18:
			if y == 0 and i >= 16:
				continue
			if y == 3 and i >= 16:
				continue
			atlas.create_tile(Vector2i(i, y))
	var ts := TileSet.new()
	ts.tile_size = tsz
	ts.add_source(atlas, g.BEACH_SRC)

	var layer := TileMapLayer.new()
	layer.name = "BeachTileMapLayer"
	layer.tile_set = ts
	layer.position = g.grid_layer.position
	g.add_child(layer)
	g.move_child(layer, g.water_layer.get_index())   # 插到水面之前
	g.beach_layer = layer

	var painted := 0
	for c in g._land_set.keys():
		if g._sand_set.has(c):
			var wmask: int = edge_mask(c, false)          # 哪几边挨着水
			if wmask != 0:
				layer.set_cell(c, g.BEACH_SRC, Vector2i(wmask, 1))
			elif sand_grass_mask(c) != 0:
				layer.set_cell(c, g.BEACH_SRC, Vector2i(sand_grass_mask(c), 2))
			else:
				layer.set_cell(c, g.BEACH_SRC, Vector2i(16 + g._hash2(c) % 2, 1))
			painted += 1
			continue
		var idx: int = edge_mask(c, false)          # 哪几边挨着水
		if idx != 0:
			layer.set_cell(c, g.BEACH_SRC, Vector2i(idx, 0))
			painted += 1
			continue
		var gmask: int = grass_sand_mask(c)         # 哪几边挨着沙地
		if gmask != 0:
			layer.set_cell(c, g.BEACH_SRC, Vector2i(gmask, 3))
			painted += 1
	print("[岸] 陆地侧沙滩 %d 格(其中沙地 %d 格)" % [painted, g._sand_set.size()])

# 铺一块实心沙底：variant=-1 无杂点；variant>=0 撒几个杂点/亮点
# idx>=0 时朝掩码方向先空出湿沙带再铺沙（给 band 让位，免得盖住渐变）——简化：直接整格铺，
# band 会用 alpha 混合叠上去（blend_px），湿沙色不透明度高，盖得住。
func fill_sand_tile(sheet: Image, ox: int, oy: int, tsz: Vector2i, idx: int, variant: int = -1) -> void:
	var g = _game
	for y in tsz.y:
		for x in tsz.x:
			sheet.set_pixel(ox + x, oy + y, g.SAND_BASE)
	if variant < 0:
		return
	# 杂点：固定 pattern（不随格子变，同一变体看起来一致）
	var dots := [Vector2i(3, 4), Vector2i(11, 2), Vector2i(6, 12), Vector2i(13, 9), Vector2i(2, 9)]
	var lites := [Vector2i(9, 6), Vector2i(4, 14), Vector2i(14, 13)]
	for d in dots:
		sheet.set_pixel(ox + d.x, oy + d.y, g.SAND_DOT)
	for l in lites:
		sheet.set_pixel(ox + l.x, oy + l.y, g.SAND_LITE)

# 沙滩格四周哪些方向挨着「非沙滩的陆地」（要画朝草地的淡出带）
func sand_grass_mask(c: Vector2i) -> int:
	var g = _game
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		var nb: Vector2i = c + dirs[i]
		if not g._in_yard(nb):
			continue
		if g._land_set.has(nb) and not g._sand_set.has(nb):
			idx |= bits[i]
	return idx

# 草地格四周哪些方向挨着沙地（要画朝沙侧的淡入带, 与 sand_grass_mask 互为镜像）
func grass_sand_mask(c: Vector2i) -> int:
	var g = _game
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		if g._sand_set.has(c + dirs[i]):
			idx |= bits[i]
	return idx

# ---------------- 水面侧浅滩 ----------------
func build_shore() -> void:
	var g = _game
	if g.grid_layer.tile_set == null:
		return
	var tsz: Vector2i = g.grid_layer.tile_set.tile_size
	if g._water_set.is_empty():
		return

	# 16 格岸线并排拼成一张 16x1 的小图集，图块号 = 那一边挨着陆地（1上 2下 4左 8右）
	var sheet := Image.create_empty(16 * tsz.x, tsz.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in 16:
		draw_band_tile(sheet, i * tsz.x, 0, i, tsz, g.SHORE_BANDS)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(sheet)
	for i in 16:
		atlas.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = tsz
	ts.add_source(atlas, g.SHORE_SRC)

	var layer := TileMapLayer.new()
	layer.name = "ShoreTileMapLayer"
	layer.tile_set = ts
	layer.position = g.grid_layer.position
	g.add_child(layer)
	g.move_child(layer, g.water_layer.get_index() + 1)   # 水面之上
	g.shore_layer = layer

	var painted := 0
	for c in g._water_set.keys():
		var idx: int = edge_mask(c, true)           # 哪几边挨着陆地
		if idx == 0:
			continue                             # 四面都是水：纯深水，不用画
		layer.set_cell(c, g.SHORE_SRC, Vector2i(idx, 0))
		painted += 1
	print("[岸] 水面 %d 格,其中 %d 格贴到岸边(浅滩)" % [g._water_set.size(), painted])

# 某格四周的方位掩码。want_land=true 时统计「邻居是陆地」的方向，false 统计「邻居是水」。
# 地图外不算陆地（否则地图边界会被当成岸、描一圈假的浅滩）。
func edge_mask(c: Vector2i, want_land: bool) -> int:
	var g = _game
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		var nb: Vector2i = c + dirs[i]
		if not g._in_yard(nb):
			continue                 # 地图外：既不算陆地也不算水，不要在那边描过渡
		var nb_land: bool = not g._water_set.has(nb)
		if nb_land == want_land:
			idx |= bits[i]
	return idx

# 画第 idx 号渐变图块（左上角在 ox,oy）：朝掩码指定的那几条边铺 bands 色带
func draw_band_tile(sheet: Image, ox: int, oy: int, idx: int, tsz: Vector2i, bands: Array) -> void:
	var w := tsz.x
	var h := tsz.y
	if idx & 1:                                # 上边 -> 从第 0 行往下
		for d in bands.size():
			for x in w:
				blend_px(sheet, ox + x, oy + d, bands[d])
	if idx & 2:                                # 下边
		for d in bands.size():
			for x in w:
				blend_px(sheet, ox + x, oy + h - 1 - d, bands[d])
	if idx & 4:                                # 左边
		for d in bands.size():
			for y in h:
				blend_px(sheet, ox + d, oy + y, bands[d])
	if idx & 8:                                # 右边
		for d in bands.size():
			for y in h:
				blend_px(sheet, ox + w - 1 - d, oy + y, bands[d])

# 把 col 叠到 (x,y) 上（正常的 alpha 混合，因为同一条边可能被两边各画一次）
func blend_px(img: Image, x: int, y: int, col: Color) -> void:
	var old := img.get_pixel(x, y)
	var a := col.a + old.a * (1.0 - col.a)
	if a <= 0.0:
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	var rgb := (Vector3(col.r, col.g, col.b) * col.a
		+ Vector3(old.r, old.g, old.b) * old.a * (1.0 - col.a)) / a
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, a))
