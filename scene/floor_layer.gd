# floor_layer.gd —— 铺装显示层（木地板 + 鹅卵石小径）
#
# 跟 soil_layer 一个套路：
#   · 数据（哪些格子铺了什么）存 Floor autoload，这里只负责显示
#   · 木地板 16 格自动拼接：4 方向哪几边「挨着另一块地板」决定要不要画横向/纵向缝
#     —— 这样做相邻两块板子在「接壤的那条边」上是同色纯填，拼起来完全无缝
#   · 鹅卵石小径不拼接：每格独立一张图，草地当基底（图本身透明，透出底下的草），
#     e30k 起每格一颗「又圆又大块」的大圆石（+ 五成概率角落一颗小的作伴）+ 落影，
#     铺一排像草地上踩出来的大石板路
#
# 跟 soil_layer 不同的点：木地板还要兼容两种底层（草地/耕地），
# 所以底层色按 Farm.tilled 决定 —— 浅板色画在草地上要更鲜明一点，
# 画在耕地上就偏白（因为耕地是棕色，再叠棕色看不出）。
extends Node2D

const TS := 16

# —— 木色 ——（e30p: 调清新 —— 浅原木奶油色，缝线提亮不再压重棕）
const FILL := Color8(216, 182, 130)       # 板子底色（浅原木奶油）
const RIM := Color8(162, 122, 76)         # 缝线（暖沙木色）
const HIGHLIGHT := Color8(238, 212, 166)  # 板子内部的木纹亮线（很淡）

# —— 小径石色（小径图本身透明，草从底下透出来，所以没有「底色」这一项）——
# e30k: 小径重画成「又圆又大块」—— 每格一颗半径 5-6 的大圆石 + 五成概率角落一颗小的作伴,
# 亮/中/暗三档石色随机挑, 哑光上浅下暗, 不再是满地小碎点
# e30p: 石色调清新 —— 偏暖白米色, 融进草地不再发灰
const P_STONE_A := Color8(216, 214, 202)  # 亮鹅卵石
const P_STONE_M := Color8(188, 186, 172)  # 中间调鹅卵石
const P_STONE_B := Color8(156, 154, 140)  # 暗鹅卵石
const P_STONE_HI := Color8(236, 234, 224) # 石头上沿的哑光亮阶（只比石身浅一档，不反光）
const P_STONE_DK := Color8(118, 116, 106) # 石头背光那一圈的暗沿
const P_SHADOW := Color8(52, 66, 40, 110) # 石头落在草上的小片落影
const P_DUST := Color8(208, 200, 164, 42) # 踩出来的浅土痕（低透明度沙色）

# 草地上：直接是上面这套木色
# 耕地上：调亮一点 + 偏冷白，让它在棕色耕地上更跳
const TINT_GRASS := Color(1, 1, 1)
const TINT_TILLED := Color(1.18, 1.10, 0.92)

# 随机种子（每次开局位置不一样，但单次跑里固定）
const FLOOR_SEED := 0x8F37C2

var _rng := RandomNumberGenerator.new()
var _tiles: Dictionary = {}        # {mask(String): ImageTexture}
var _path_tiles: Dictionary = {}   # {seed(int): ImageTexture} 小径每格独立图
var _sprites: Dictionary = {}      # {Vector2i: Sprite2D}
var _tile_seeds: Dictionary = {}   # {Vector2i: int} 每格用自己独立的随机种子，保证相邻不会「撞」

func _ready() -> void:
	_rng.seed = FLOOR_SEED
	Floor.floor_changed.connect(_on_changed)
	for pos in Floor.floors.keys():
		_on_changed(pos)

# ---------------- 增删 ----------------
func _on_changed(pos: Vector2i) -> void:
	if Floor.is_floored(pos):
		_add(pos)
	else:
		_remove(pos)
	for n in _neighbors(pos):
		if Floor.is_floored(n):
			_refresh(n)             # 邻居的边缘变了

func _add(pos: Vector2i) -> void:
	if _sprites.has(pos):
		_refresh(pos)
		return
	var spr := Sprite2D.new()
	spr.centered = false
	add_child(spr)
	_sprites[pos] = spr
	_tile_seeds[pos] = _rng.randi()
	_refresh(pos)

func _remove(pos: Vector2i) -> void:
	if not _sprites.has(pos):
		return
	_sprites[pos].queue_free()
	_sprites.erase(pos)
	_tile_seeds.erase(pos)

func _neighbors(pos: Vector2i) -> Array:
	return [
		pos + Vector2i.UP, pos + Vector2i.DOWN,
		pos + Vector2i.LEFT, pos + Vector2i.RIGHT,
	]

# ---------------- 重画单格 ----------------
func _refresh(pos: Vector2i) -> void:
	if not _sprites.has(pos):
		return
	var spr: Sprite2D = _sprites[pos]
	var seed: int = int(_tile_seeds.get(pos, 0))
	if Floor.kind_of(pos) == Floor.KIND_PATH:
		spr.texture = _path_tile(seed)
	else:
		spr.texture = tile_for(_mask(pos), seed)
	spr.position = _grid_to_local(pos)
	# 耕地上要调亮偏冷，区别于草地
	spr.modulate = TINT_TILLED if Farm.is_tilled(pos) else TINT_GRASS

# 四方向是否「有相邻地板」（=这一边是接缝还是敞开边）
func _mask(pos: Vector2i) -> String:
	var m := ""
	m += "N" if not Floor.is_floored(pos + Vector2i.UP) else "-"
	m += "S" if not Floor.is_floored(pos + Vector2i.DOWN) else "-"
	m += "W" if not Floor.is_floored(pos + Vector2i.LEFT) else "-"
	m += "E" if not Floor.is_floored(pos + Vector2i.RIGHT) else "-"
	return m

# 格子号 -> 本节点局部坐标
func _grid_to_local(pos: Vector2i) -> Vector2:
	var origin_local := Farm.grid_origin - global_position
	return origin_local + Vector2(pos.x * TS, pos.y * TS)

# ---------------- 生成拼接图块 ----------------
# mask = N/S/W/E（哪个方向敞开）。
# e30k: 木地板重画成横向板条 —— 整格上下两条 8px 高的木板行（每行色差一点），
# 行与行之间一道通长深缝（y=7），每行各一道竖向「端缝」且上下错开（像真实木地板的错缝拼接），
# 行内再点缀断续的木纹亮线；敞开的四边照旧描缝。
func tile_for(mask: String, seed: int) -> ImageTexture:
	var key := "%s_%d" % [mask, seed]
	if _tiles.has(key):
		return _tiles[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	# 两条板行：各自在 FILL 上下浮动一点色差，拼出「一块一块的板」
	var row_a := FILL.lerp(HIGHLIGHT, rng.randf_range(0.0, 0.2))
	var row_b := FILL.lerp(RIM, rng.randf_range(0.0, 0.16))
	img.fill_rect(Rect2i(0, 0, TS, 7), row_a)
	img.fill_rect(Rect2i(0, 8, TS, TS - 8), row_b)
	# 行间通长缝（y=7）+ 敞开边描缝
	_hline(img, 7)
	if mask[0] == "N":
		_hline(img, 0)
	if mask[1] == "S":
		_hline(img, TS - 1)
	if mask[2] == "W":
		_vline(img, 0)
	if mask[3] == "E":
		_vline(img, TS - 1)
	# 每行一道竖向端缝，上下错开（|xa-xb|>=4），像真实地板的错缝
	var xa := rng.randi_range(2, TS - 3)
	var xb := xa
	while absi(xa - xb) < 4:
		xb = rng.randi_range(2, TS - 3)
	for y in range(0, 7):
		img.set_pixel(xa, y, RIM)
	for y in range(8, TS):
		img.set_pixel(xb, y, RIM)
	# 端缝旁偶尔一枚钉头
	if rng.randi_range(0, 2) == 0:
		img.set_pixel(clampi(xa + 1, 0, TS - 1), 1, RIM)
	if rng.randi_range(0, 2) == 0:
		img.set_pixel(clampi(xb - 1, 0, TS - 1), TS - 2, RIM)
	# 木纹：每行 1-2 段断续亮线（有起有收更像木板, 不是通长的死线）
	for row_top: int in [1, 8]:
		for i in rng.randi_range(1, 2):
			var ly := row_top + rng.randi_range(1, 4)
			var lx := rng.randi_range(0, TS - 5)
			var ln := rng.randi_range(4, 9)
			for x in range(lx, mini(lx + ln, TS)):
				var cur := img.get_pixel(x, ly)
				if not cur.is_equal_approx(RIM):
					img.set_pixel(x, ly, cur.lerp(HIGHLIGHT, 0.5))
	var tex := ImageTexture.create_from_image(img)
	_tiles[key] = tex
	return tex

# 鹅卵石小径单格：整格透明（底下是什么草就露什么草）。
# e30k 重画: 每格一颗大圆石（半径 5-6, 占满大半格）+ 五成概率角落一颗小的作伴,
# 石头是正圆略压扁, 哑光上浅下暗、底缘压一圈暗边 —— 「又圆又大块」, 不再是满地小碎点
# （seed 定形状, 相邻不重样）
func _path_tile(seed: int) -> ImageTexture:
	if _path_tiles.has(seed):
		return _path_tiles[seed]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))          # 透明基底：草地从底下透出来
	# 踩出来的浅土痕：两三撮低透明度沙色小点, 暗示「这里有条路」
	for i in rng.randi_range(2, 3):
		var dx0 := rng.randi_range(2, TS - 3)
		var dy0 := rng.randi_range(2, TS - 3)
		for j in 3:
			img.set_pixel(clampi(dx0 + rng.randi_range(-1, 1), 1, TS - 2),
				clampi(dy0 + rng.randi_range(-1, 1), 1, TS - 2), P_DUST)
	# 大石头：圆心在格中心附近抖动, 半径 5-6 —— 又圆又大块
	var stones: Array = []
	stones.append(Vector4(8 + rng.randi_range(-2, 2), 8 + rng.randi_range(-2, 2),
		rng.randi_range(5, 6), rng.randi_range(4, 6)))
	# 一半概率在四角之一补一颗小的（r 2-3）作伴
	if rng.randi_range(0, 1) == 0:
		var corners := [Vector2(3, 3), Vector2(TS - 4, 3),
			Vector2(3, TS - 4), Vector2(TS - 4, TS - 4)]
		var c: Vector2 = corners[rng.randi_range(0, 3)]
		stones.append(Vector4(c.x + rng.randi_range(-1, 1), c.y + rng.randi_range(-1, 1),
			rng.randi_range(2, 3), rng.randi_range(2, 3)))
	# 先把所有落影画完（右下偏移的椭圆暗斑），再叠石头本体
	for pb: Vector4 in stones:
		for y in range(int(pb.y) - int(pb.w), int(pb.y) + int(pb.w) + 3):
			for x in range(int(pb.x) - int(pb.z), int(pb.x) + int(pb.z) + 3):
				if x < 0 or x > TS - 1 or y < 0 or y > TS - 1:
					continue
				var dxs := float(x - int(pb.x) - 1) / float(int(pb.z) + 1)
				var dys := float(y - int(pb.y) - 2) / float(int(pb.w))
				if dxs * dxs + dys * dys <= 1.0:
					img.set_pixel(x, y, P_SHADOW)
	# 石头本体：哑光纵向渐变 —— 上沿浅一档 / 石身基色 / 下沿暗一圈,
	# 底缘再压一圈暗边让石头「落地」；圆感全靠明暗差, 不加近白高光
	for pb: Vector4 in stones:
		var cx := int(pb.x)
		var cy := int(pb.y)
		var rx := int(pb.z)
		var ry := int(pb.w)
		var pick := rng.randi_range(0, 2)
		var base := P_STONE_A
		if pick == 1:
			base = P_STONE_M
		elif pick == 2:
			base = P_STONE_B
		for y in range(cy - ry, cy + ry + 1):
			for x in range(cx - rx, cx + rx + 1):
				if x < 0 or x > TS - 1 or y < 0 or y > TS - 1:
					continue
				var dx := float(x - cx) / float(rx)
				var dy := float(y - cy) / float(ry)
				var d2 := dx * dx + dy * dy
				if d2 <= 1.0:
					var col := base
					if dy < -0.35:
						col = base.lerp(P_STONE_HI, 0.35)
					elif dy > 0.45:
						col = base.lerp(P_STONE_DK, 0.55)
					if d2 > 0.86 and dy > 0.0:
						col = col.lerp(P_STONE_DK, 0.4)
					img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_path_tiles[seed] = tex
	return tex

func _hline(img: Image, y: int) -> void:
	for x in TS:
		img.set_pixel(x, y, RIM)

func _vline(img: Image, x: int) -> void:
	for y in TS:
		img.set_pixel(x, y, RIM)
