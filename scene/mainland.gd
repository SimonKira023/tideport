# scene/mainland.gd —— 大陆据点（上岸后的小场景）
#
# 海图西北那片大陆的**登陆点**：一条木栈桥 + 海边几间房子。
# 在海图的大陆码头按 F 上岸进这里，走到栈桥头按 F 回海图继续航行。
# 据点里能按 F 的地方：
#   · 集市 —— 把岛上的作物/食物卖掉，买岛上造不出的货（种子 / 木头 / 木地板）
#   · 酒馆 —— 花钱雇人（价目跟岛上傍晚的篝火一样，走 Slaves 那一份）
#   · 栈桥 —— 回海图
#
# ❗这跟 game.tscn 那张岛**没有关系**：自己一套网格、自己的相机、自己的主角，
#   由 Voyage.enter_mainland() 挂在 root 上盖住海图（跟战役地图一个套路）。
#   这样岛上那套 Farm/耕地/伙伴逻辑一行都不用动。
extends Node2D

const CELL := 16
const W := 44                 # 44 x 28 格 = 704 x 448 像素
const H := 28
const SEED := 20260916

# 海岸线：SHORE_Y 是基准行，噪声让它弯一点（y <= 岸线 = 陆地）
const SHORE_Y := 18
# 栈桥：从岸边往海里伸，2 格宽
const PIER_X := 30
const PIER_LEN := 7

const SPEED := 52.0           # 走路速度（比岛上的主角慢一点：据点是逛，不是赶路）
# 一个走路循环迈多远 —— 跟 slave_npc.gd 同一个量法（Walk.png 侧身 6 帧约 10px）
const WALK_STRIDE_PX := 10.0
const WALK_FPS_CAP := 22.0

const FONT_PIX := preload("res://resources/font/IPix.ttf")
# 栈桥边停泊的船：用「只画船身」那张（e40）—— 两排泊位行距 22px,
# 挂帆（32x44）后排的帆会盖住前排的船；停着=收帆。
const BOAT_HULL_TEX := preload("res://resources/texture/boat_hull.png")
const KEY_HINT := preload("res://scene/key_hint.gd")
const MODEL_DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/%s"
const SHEETS := {
	"idle": {"file": "Idle.png", "frames": 4, "fps": 7.0, "loop": true},
	"walk": {"file": "Walk.png", "frames": 6, "fps": 10.0, "loop": true},
}
const DIR_ROW := {"down": 0, "up": 1, "side": 2}

# ---------------- 地形美术素材（跟岛上、战役同一套）----------------
const GRASS_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Spring.png"
const GRASS_TILE := Vector2i(9, 18)
const PROP_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const DECOR_TUFT := [
	Vector2i(1, 0), Vector2i(5, 0), Vector2i(1, 1), Vector2i(5, 1),
	Vector2i(10, 0), Vector2i(10, 1),
]
const DECOR_FLOWER := [
	Vector2i(11, 0), Vector2i(12, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(8, 1), Vector2i(12, 1),
]
const DECOR_MUSHROOM := [Vector2i(13, 0), Vector2i(13, 1), Vector2i(11, 2)]
const DECOR_DENSITY := 0.13
const DECOR_NOISE_FREQ := 0.09

const TREE_SHEETS := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Cherry Tree.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Apricot Tree.png",
]
const TREE_MATURE_FRAME := [6, 3]
const TREE_FRAME_W := 32
const TREE_FRAME_H := 48
const TREE_BASE_Y := 45.0

const WATER_DEPTHS := [
	Color(0.56, 0.87, 0.93), Color(0.43, 0.81, 0.91), Color(0.30, 0.74, 0.89),
	Color(0.18, 0.66, 0.86), Color(0.04, 0.50, 0.77),
]
const WATER_VARIANTS := 3
const WATER_RIPPLE := 0.035
const WATER_EDGE := 2
const WATER_MAX_DIST := 4

const SAND_W := 5
const SAND_BAND := [
	Color(0.86, 0.77, 0.50), Color(0.82, 0.74, 0.52, 0.85),
	Color(0.77, 0.72, 0.54, 0.55), Color(0.71, 0.75, 0.59, 0.24),
]
const SAND_TILE_OF := {"up": Vector2i(0, 0), "right": Vector2i(1, 0),
	"down": Vector2i(2, 0), "left": Vector2i(3, 0)}

# 三间房子（现成素材）。base_row = 图里“房子踩地”的那一行，foot_w = 图宽。
# bbox 是用 PIL 量出来的：贴图四周有透明留白，按图高直接摆会浮在半空。
const HOUSE_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/%s"
const HOUSES := {
	"market": {"file": "5.png", "base_row": 90.0, "w": 80.0},
	"tavern": {"file": "1.png", "base_row": 100.0, "w": 128.0},
	"home": {"file": "8.png", "base_row": 116.0, "w": 128.0},
}

# 摆位（格子号 = 房子**脚下**那一格）
const MARKET_CELL := Vector2i(12, 15)
const TAVERN_CELL := Vector2i(24, 14)
const HOME_CELL := Vector2i(18, 9)

# e11g: 城镇里的装饰建筑（纯摆设, 不可交互）—— 让十五座城镇看起来是「城」。
# 摆位用城镇 id 做种: 每座城长得不一样, 同一座城每次进城一模一样。
# 数量按城镇规格: 首都最密, 贸易镇次之, 军镇疏一点。
# 楼统一缩 0.5（素材都是 72~124 宽的大楼, 缩小才塞得下一座城）。
const DECOR_FILES := ["2.png", "3.png", "4.png", "6.png", "7.png",
	"9.png", "10.png", "11.png", "12.png"]
# e27d: 雪顶「糖果屋」只属于北岭雪国（口径同 world_map.HOUSE_OF_NATION:
# 1/4/5/6/12.png 都是雪顶, 5.png 是集市那张糖果屋）。其它国的城里
# 不该冒出雪屋 —— 晨曦满城雪顶太出戏, 全换普通屋。
const SNOW_HOUSES := ["1.png", "4.png", "5.png", "6.png", "12.png"]
const DECOR_PLAIN_FILES := ["2.png", "3.png", "7.png", "9.png", "10.png", "11.png"]
# 非北岭国的功能房替代图（集市/酒馆原用 5.png/1.png 雪屋; 议事厅 8.png 本就是普通屋）
const HOUSE_PLAIN_OF := {"market": "10.png", "tavern": "11.png", "home": "8.png"}
const DECOR_SCALE := 0.5
const DECOR_TARGET := {"capital": 14, "trade": 10, "military": 8}

var world: Node2D = null            # y_sort 世界层（房子/树/人互相遮挡）
var _land := {}
var _water := {}
var _pier := {}                     # 栈桥占的格子（在水上，但能走）
var _blocked := {}                  # 树占的格子（人不能穿过去）
var _house_rects: Array = []        # 房子的占位矩形（像素，挡人不挡视线）

var player: Node2D = null
var _sprite: AnimatedSprite2D = null
var _facing: StringName = &"down"
var _cam: Camera2D = null

var _hud: CanvasLayer = null
var _hint: Label = null
var _spots: Array = []              # {kind, pos, word}
var _near := -1                     # 站在哪个交互点旁边（-1 = 都不挨着）
var _closed := false                # 已经按了「上船」，正在退回海图
var _hints: Array = []              # 三个交互点头顶的 [F] 徽章
var _market: Control = null
var _tavern: Control = null
var town_id := ""                   # 非空 = 城镇模式（Voyage.enter_town 设置）
var _town: Control = null

func _ready() -> void:
	add_to_group("mainland")
	_build_terrain()
	# ❗顺序有讲究：房子（_house_rects）和树（_blocked）要先摆好，
	#   花草才知道哪些地方该留空（不然花会长到房子墙上、树底下）。
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	_build_houses()
	_spawn_trees()
	_build_pier()
	_paint_grass(_land, {})
	_paint_sand(_land, _water)
	_paint_water(_water)
	_paint_decor()
	_moor_boats()
	_setup_player()
	_setup_hud()
	if town_id == "":
		announce("到了大陆码头. 栈桥头按 F 回海图, 集市和酒馆进去看看")
	else:
		announce("进了%s. 议事厅里能聊天送礼签协议" % _town_name())

# ---------------- 地形 ----------------
func _build_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.14
	for x in W:
		var wob := noise.get_noise_2d(float(x), 0.0) * 1.8
		var shore := clampi(int(round(float(SHORE_Y) + wob)), SHORE_Y - 1, SHORE_Y + 2)
		for y in H:
			var c := Vector2i(x, y)
			if y <= shore:
				_land[c] = true
			else:
				_water[c] = true
	# 栈桥：从岸边一直伸到海里
	for i in range(PIER_LEN + 1):
		for dx in 2:
			var c := Vector2i(PIER_X + dx, SHORE_Y + i)
			if _water.has(c):
				_pier[c] = true

func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)

func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))

# 人能站吗：水面不能（栈桥除外），房子和树占的地方也不能
func walkable(pos: Vector2) -> bool:
	var c := _cell_at(pos)
	if c.x < 1 or c.y < 1 or c.x >= W - 1 or c.y >= H - 1:
		return false
	if _water.has(c) and not _pier.has(c):
		return false
	if _blocked.has(c):
		return false
	for r in _house_rects:
		if (r as Rect2).has_point(pos):
			return false
	return true

# ---------------- 贴图（跟战役地图同一套画法）----------------
func _paint_grass(land: Dictionary, ford: Dictionary) -> void:
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var grass_tex := SoftRes.tex(GRASS_SHEET)
	if grass_tex == null:
		push_warning("[素材] 缺少草地贴图, 跳过铺设草地")
		return
	var layer := _make_tile_layer("Ground", grass_tex, [GRASS_TILE], -20)
	_grass_alts(layer)
	for c in land.keys():
		layer.set_cell(c, 0, GRASS_TILE, _grass_alt_of(c))
	for c in ford.keys():
		layer.set_cell(c, 0, GRASS_TILE, _grass_alt_of(c))

# ---------------- 草地明暗变体 ----------------
# 全岛同一格贴图平铺就是「贴图重复」的根源 —— 同 game.gd 的做法:
# 同一张图调 modulate 当变体, 双频噪声切成大团色块（亮斑/暗斑/深斑）, 草地不再一整张平色。
const GRASS_ALT_LITE := 1
const GRASS_ALT_DARK := 2
const GRASS_ALT_DEEP := 3
var _grass_noise: FastNoiseLite = null
var _grass_noise2: FastNoiseLite = null

func _grass_alts(layer: TileMapLayer) -> void:
	var src := layer.tile_set.get_source(0) as TileSetAtlasSource
	if src == null:
		return
	if not src.has_alternative_tile(GRASS_TILE, GRASS_ALT_LITE):
		src.create_alternative_tile(GRASS_TILE, GRASS_ALT_LITE)
	if not src.has_alternative_tile(GRASS_TILE, GRASS_ALT_DARK):
		src.create_alternative_tile(GRASS_TILE, GRASS_ALT_DARK)
	if not src.has_alternative_tile(GRASS_TILE, GRASS_ALT_DEEP):
		src.create_alternative_tile(GRASS_TILE, GRASS_ALT_DEEP)
	var lite := src.get_tile_data(GRASS_TILE, GRASS_ALT_LITE)
	if lite != null:
		lite.modulate = Color(0.96, 1.0, 0.88)
	var dark := src.get_tile_data(GRASS_TILE, GRASS_ALT_DARK)
	if dark != null:
		dark.modulate = Color(0.90, 0.97, 0.93)
	var deep := src.get_tile_data(GRASS_TILE, GRASS_ALT_DEEP)
	if deep != null:
		deep.modulate = Color(0.79, 0.89, 0.85)
	_grass_noise = FastNoiseLite.new()
	_grass_noise.seed = SEED + 991
	_grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_grass_noise.frequency = 0.03
	_grass_noise2 = FastNoiseLite.new()
	_grass_noise2.seed = SEED + 992
	_grass_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_grass_noise2.frequency = 0.12

# 这一格草用哪个变体（0 底色 / 1 亮斑 / 2 暗斑 / 3 深斑）：大团块定基调 + 细节抖边
func _grass_alt_of(c: Vector2i) -> int:
	if _grass_noise == null:
		return 0
	var v := _grass_noise.get_noise_2d(float(c.x), float(c.y)) * 0.72 \
		+ _grass_noise2.get_noise_2d(float(c.x), float(c.y)) * 0.28
	if v > 0.26:
		return GRASS_ALT_LITE
	if v < -0.52:
		return GRASS_ALT_DEEP
	if v < -0.20:
		return GRASS_ALT_DARK
	return 0

func _paint_sand(land: Dictionary, water: Dictionary) -> void:
	var tiles: Array = []
	for k in SAND_TILE_OF.keys():
		tiles.append(SAND_TILE_OF[k])
	var layer := _make_tile_layer("Sand", _sand_texture(), tiles, -16)
	for c in land.keys():
		for dir in SAND_TILE_OF.keys():
			if water.has(c + _dir_vec(dir)):
				layer.set_cell(c, 0, SAND_TILE_OF[dir])

func _dir_vec(dir: String) -> Vector2i:
	match dir:
		"up": return Vector2i.UP
		"right": return Vector2i.RIGHT
		"down": return Vector2i.DOWN
	return Vector2i.LEFT

func _sand_texture() -> ImageTexture:
	var img := Image.create_empty(4 * CELL, CELL, false, Image.FORMAT_RGBA8)
	for i in 4:
		var dir: String = SAND_TILE_OF.keys()[i]
		for y in CELL:
			for x in CELL:
				var depth := 0
				match dir:
					"up": depth = y
					"down": depth = CELL - 1 - y
					"left": depth = x
					"right": depth = CELL - 1 - x
				var band := clampi(int(float(depth) / float(SAND_W) * float(SAND_BAND.size())),
					0, SAND_BAND.size() - 1)
				var col: Color = SAND_BAND[band]
				var n := float(((x * 7 + y * 13 + i * 5) % 11)) / 11.0
				col.a *= 0.78 + 0.22 * n
				img.set_pixel(i * CELL + x, y, col)
	return ImageTexture.create_from_image(img)

func _paint_water(water: Dictionary) -> void:
	var img := Image.create_empty(WATER_DEPTHS.size() * CELL, WATER_VARIANTS * CELL,
		false, Image.FORMAT_RGBA8)
	for d in WATER_DEPTHS.size():
		for v in WATER_VARIANTS:
			_draw_water_tile(img, d * CELL, v * CELL, d, v)
	var tiles: Array = []
	for d in WATER_DEPTHS.size():
		for v in WATER_VARIANTS:
			tiles.append(Vector2i(d, v))
	var layer := _make_tile_layer("Water", ImageTexture.create_from_image(img), tiles, -18)
	if water.is_empty():
		return
	var depth := _water_depth_map(water)
	# ❗深浅之间别加太猛的噪声：加 0.9 的时候相邻格会在档位之间乱跳，
	#   一大片开阔海面看着像「蓝方块棋盘」。0.32 只够把档位边界揉弯。
	var wob := FastNoiseLite.new()
	wob.seed = SEED + 7
	wob.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wob.frequency = 0.13
	var last: int = WATER_DEPTHS.size() - 1
	for c in water.keys():
		var f: float = float(int(depth.get(c, 1))) - 1.0 \
			+ wob.get_noise_2d(float(c.x), float(c.y)) * 0.32
		var lv := clampi(int(floor(f + 0.5)), 0, last)
		var v := absi(c.x * 374761393 + c.y * 668265263) % WATER_VARIANTS
		layer.set_cell(c, 0, Vector2i(lv, v))

func _water_depth_map(water: Dictionary) -> Dictionary:
	var dist := {}
	var frontier: Array = []
	for c in water.keys():
		dist[c] = WATER_MAX_DIST
		for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
			if not water.has(nb):
				dist[c] = 1
				frontier.append(c)
				break
	var d := 1
	while not frontier.is_empty() and d < WATER_MAX_DIST:
		var nxt: Array = []
		for c in frontier:
			for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
				if water.has(nb) and int(dist[nb]) > d + 1:
					dist[nb] = d + 1
					nxt.append(nb)
		frontier = nxt
		d += 1
	return dist

func _draw_water_tile(img: Image, ox: int, oy: int, depth: int, variant: int) -> void:
	var base: Color = WATER_DEPTHS[depth]
	for y in CELL:
		for x in CELL:
			img.set_pixel(ox + x, oy + y, base)
	var wob := sin(float(variant) * 2.1) * 0.5
	for y in range(WATER_EDGE, CELL - WATER_EDGE):
		for x in range(WATER_EDGE, CELL - WATER_EDGE):
			var w := sin(float(x) * 0.9 + wob + float(y) * 0.35 + float(variant) * 1.7)
			var a := WATER_RIPPLE * w
			img.set_pixel(ox + x, oy + y, Color(clampf(base.r + a, 0.0, 1.0),
				clampf(base.g + a, 0.0, 1.0), clampf(base.b + a, 0.0, 1.0), 1.0))

func _paint_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 31
	var tiles: Array = DECOR_TUFT + DECOR_FLOWER + DECOR_MUSHROOM
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var prop_tex := SoftRes.tex(PROP_SHEET)
	if prop_tex == null:
		push_warning("[素材] 缺少花草点缀贴图, 跳过装饰层")
		return
	var layer := _make_tile_layer("Decor", prop_tex, tiles, -14)
	var noise := FastNoiseLite.new()
	noise.seed = SEED + 31
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = DECOR_NOISE_FREQ
	for c in _land.keys():
		# 沙滩上不长草（贴着水的格子留干净）
		var on_sand := false
		for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
			if _water.has(nb):
				on_sand = true
				break
		if on_sand or _blocked.has(c):
			continue
		# 栈桥口和房子门口留出来，别把路铺满花
		if _near_house(_cell_center(c), 26.0) or _cell_center(c).distance_to(_pier_root()) < 30.0:
			continue
		var dens := (noise.get_noise_2d(float(c.x), float(c.y)) * 0.5 + 0.5) * DECOR_DENSITY
		if rng.randf() > dens:
			continue
		var roll := rng.randf()
		var pick: Vector2i
		if roll < 0.04:
			pick = DECOR_MUSHROOM[rng.randi() % DECOR_MUSHROOM.size()]
		elif roll < 0.30:
			pick = DECOR_FLOWER[rng.randi() % DECOR_FLOWER.size()]
		else:
			pick = DECOR_TUFT[rng.randi() % DECOR_TUFT.size()]
		layer.set_cell(c, 0, pick)

func _spawn_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 99
	var noise := FastNoiseLite.new()
	noise.seed = SEED + 99
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.12
	for c in _land.keys():
		# 只在北边那片（离岸远）长树，码头附近留空
		if c.y > SHORE_Y - 4:
			continue
		if _near_house(_cell_center(c), 34.0):
			continue
		if c.x < 3 or c.x > W - 4:
			continue
		var v := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
		if v < 0.66 or rng.randf() > 0.5:
			continue
		_blocked[c] = true
		var variant := rng.randi() % TREE_SHEETS.size()
		var at := AtlasTexture.new()
		at.atlas = SoftRes.tex(TREE_SHEETS[variant])
		at.region = Rect2(float(TREE_MATURE_FRAME[variant] * TREE_FRAME_W), 0.0,
			float(TREE_FRAME_W), float(TREE_FRAME_H))
		var n := Node2D.new()
		n.position = Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL - 3)
		var s := Sprite2D.new()
		s.centered = false
		s.position = Vector2(-TREE_FRAME_W / 2.0, -TREE_BASE_Y)
		s.texture = at
		# 打破平铺感: 翻面 + 明暗按格子哈希微调（同主岛树的做法）
		var hh := absi(c.x * 92837111 + c.y * 689287499)
		s.flip_h = hh % 2 == 0
		var shade := 0.93 + float(hh % 7) / 7.0 * 0.12
		var warm := float((hh / 7) % 3) - 1.0
		s.modulate = Color(shade + warm * 0.02, shade, shade - warm * 0.02, 1.0)
		n.add_child(s)
		world.add_child(n)

func _make_tile_layer(layer_name: String, tex: Texture2D, tiles: Array, z: int) -> TileMapLayer:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	for t in tiles:
		atlas.create_tile(t)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_source(atlas, 0)
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = ts
	layer.z_index = z
	add_child(layer)
	return layer

# ---------------- 栈桥 ----------------
func _pier_root() -> Vector2:
	return _cell_center(Vector2i(PIER_X, SHORE_Y - 1))

func _pier_tip() -> Vector2:
	return _cell_center(Vector2i(PIER_X + 1, SHORE_Y + PIER_LEN))

# 栈桥：一整张程序化木栈道（不切图块，省得木板缝在每格边界上重复）
func _build_pier() -> void:
	var img_w := 32 + 10                 # 桥面 32px + 两侧各伸 5px 的护桩
	var img_h := PIER_LEN * CELL + 18    # 底下多留一点：木桩插进水里那截
	var img := Image.create_empty(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var plank_a := Color(0.58, 0.43, 0.27)
	var plank_b := Color(0.49, 0.36, 0.23)
	var beam := Color(0.36, 0.26, 0.17)
	var wl := 5                            # 桥面左边界
	var wr := 5 + 32 - 1                   # 桥面右边界
	# 桥面：一条条横板（每 5px 一条，深浅交替）
	for y in range(0, PIER_LEN * CELL):
		var c := plank_a if ((y / 5) % 2 == 0) else plank_b
		for x in range(wl, wr + 1):
			img.set_pixel(x, y, c)
	# 板缝：每 5px 一条暗线
	for k in range(0, int(PIER_LEN * CELL / 5) + 1):
		var y := k * 5
		if y < PIER_LEN * CELL:
			for x in range(wl, wr + 1):
				img.set_pixel(x, y, beam)
	# 两侧边梁
	for y in range(0, PIER_LEN * CELL):
		img.set_pixel(wl, y, beam)
		img.set_pixel(wr, y, beam)
	# 护桩：每 2 格一对，桥面外各伸 5px，往下插进水里
	for k in range(0, PIER_LEN * CELL, CELL * 2):
		for x in range(0, wl):
			for y in range(k, mini(k + 26, img_h)):
				img.set_pixel(x, y, beam.darkened(0.12))
		for x in range(wr + 1, img_w):
			for y in range(k, mini(k + 26, img_h)):
				img.set_pixel(x, y, beam.darkened(0.12))
	var spr := Sprite2D.new()
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.texture = ImageTexture.create_from_image(img)
	var holder := Node2D.new()
	holder.name = "Pier"
	holder.position = Vector2(float(PIER_X * CELL) - 5.0, float(SHORE_Y * CELL))
	holder.add_child(spr)
	world.add_child(holder)

# ---------------- 房子 ----------------
func _build_houses() -> void:
	# 交互点取「门口地面」= 脚下再往南 8 像素 —— 那儿不在房子占位里，人站得住
	# e27h: 集市/酒馆功能已并入议事厅五分页 —— 房子照建当景, 玩家村才留独立入口
	var market := _add_house("market", MARKET_CELL)
	var tavern := _add_house("tavern", TAVERN_CELL)
	if town_id == "":
		_spots.append({"kind": "market", "pos": market + Vector2(0, 8), "word": "交易"})
		_spots.append({"kind": "tavern", "pos": tavern + Vector2(0, 8), "word": "雇人"})
	var home := _add_house("home", HOME_CELL)
	if town_id != "":
		# 城镇模式：大宅当议事厅（外交面板），府前插两面国旗
		_spots.append({"kind": "town", "pos": home + Vector2(0, 8), "word": "议事"})
		_add_banners()
		_add_decor_town()
		_add_streets()
	_spots.append({"kind": "pier", "pos": _pier_root(),
		"word": "回海图" if town_id != "" else "上船"})

# 摆一栋房子，返回它**脚下**的世界坐标（交互点就用这个）
func _add_house(key: String, cell: Vector2i) -> Vector2:
	var info: Dictionary = HOUSES[key]
	var file := String(info["file"])
	# e27d: 雪屋只留给北岭 —— 其它国的功能房换普通屋顶。
	# 替代图的脚底/宽度不再手写 bbox, 走 _measure_decor 自动量。
	if town_id != "" and file in SNOW_HOUSES and _town_nid() != "beiling":
		file = String(HOUSE_PLAIN_OF.get(key, file))
	var path := HOUSE_SHEET % file
	var m := _measure_decor(path)
	var w: float = float(info["w"]) if m.is_empty() else float(m["w"])
	var base_row: float = float(info["base_row"]) if m.is_empty() else float(m["h"])
	var x0: float = 0.0 if m.is_empty() else float(m["x0"])
	var foot := Vector2(float(cell.x * CELL + CELL / 2), float(cell.y * CELL + CELL))
	var n := Node2D.new()
	n.name = "House_%s" % key
	n.position = foot
	var s := Sprite2D.new()
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.texture = SoftRes.tex(path)
	# 内容 bbox 居中: 内容中心对齐脚点 x, 内容底行落在脚点 y
	s.position = Vector2(-(x0 + w * 0.5), -base_row)
	n.add_child(s)
	world.add_child(n)
	# 占位：房子本体那块不能穿。❗下边界**收在脚底下**（不含脚下方），
	#   不然「门口那一格」也被挡掉，人走不到交互点上。
	var bw := w * 0.9
	_house_rects.append(Rect2(foot.x - bw * 0.5, foot.y - 30.0, bw, 30.0))
	return foot

func _near_house(pos: Vector2, r: float) -> bool:
	for rect in _house_rects:
		if (rect as Rect2).grow(r * 0.5).has_point(pos):
			return true
	return false

# ---------------- 装饰建筑（e11g: 城镇像座城） ----------------
# 纯摆设: 不注册交互点, 只挡人。北带散布, 避开功能房的画和所有交互点门口。
func _add_decor_town() -> void:
	var kind := String(Nations.TOWNS.get(town_id, {}).get("kind", "trade"))
	var want := int(DECOR_TARGET.get(kind, 8))
	# e27d: 装饰楼按国家过滤 —— 雪屋顶只留在北岭(全雪屋池), 其它国从普通屋里挑
	var files: Array = SNOW_HOUSES if _town_nid() == "beiling" else DECOR_PLAIN_FILES
	var pool: Array = []
	for f in files:
		var m := _measure_decor(HOUSE_SHEET % str(f))
		if not m.is_empty():
			pool.append(m)
	if pool.is_empty():
		return
	# 按宽从大到小摆: 大楼先进开阔地, 小楼往后见缝插针, 一带能塞下更多。
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["w"]) > float(b["w"]))
	# 功能房的整幅画也占地方: 装饰楼别跟它们叠在一起
	var arts: Array = []
	var cells_of := {"market": MARKET_CELL, "tavern": TAVERN_CELL, "home": HOME_CELL}
	for key in cells_of.keys():
		var i: Dictionary = HOUSES[key]
		var fp := Vector2(float(cells_of[key].x * CELL + CELL / 2),
			float(cells_of[key].y * CELL + CELL))
		arts.append(Rect2(fp.x - float(i["w"]) * 0.5 - 3.0, fp.y - float(i["base_row"]) - 3.0,
			float(i["w"]) + 6.0, float(i["base_row"]) + 6.0))
	# 确定性洗牌（种子带城镇 id）: 各城长得不一样, 同城每次一样
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 77 + hash(town_id)
	# 候选位: 铺满岸上城区（贴到海岸线上一行）。行序用来补位, 洗牌序用来散布
	var rowfirst: Array = []
	for gy in range(2, SHORE_Y - 2):
		for gx in range(3, W - 3):
			rowfirst.append(Vector2i(gx, gy))
	var cands: Array = rowfirst.duplicate()
	for k in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var t: Vector2i = cands[k]
		cands[k] = cands[j]
		cands[j] = t
	# 洗牌撒一遍, 不够数再按行补一遍（补位专挑最窄的楼, 见缝插针）
	var placed := 0
	for list in [cands, rowfirst]:
		for c in list:
			if placed >= want:
				break
			var d: Dictionary = (pool[rng.randi_range(0, pool.size() - 1)] if list == cands
				else pool[pool.size() - 1])
			var foot := Vector2(float(c.x * CELL + CELL / 2), float(c.y * CELL + CELL))
			var w: float = float(d["w"]) * DECOR_SCALE
			var h: float = float(d["h"]) * DECOR_SCALE
			if foot.y - h - 2.0 < 2.0:
				continue   # 屋顶会伸出图外, 换个低处的位
			# 整幅画（含屋顶）不跟任何已摆的画重叠
			var art := Rect2(foot.x - w * 0.5 - 2.0, foot.y - h - 2.0, w + 4.0, h + 4.0)
			var clash := false
			for r in arts:
				if (r as Rect2).intersects(art):
					clash = true
					break
			# 挡人条不能盖住交互点（门口要能站人）
			if not clash:
				var block := Rect2(foot.x - w * 0.45, foot.y - 26.0, w * 0.9, 26.0)
				for s in _spots:
					if block.grow(8.0).has_point(s["pos"]):
						clash = true
						break
			if clash:
				continue
			_add_decor_building(d, foot, placed)
			arts.append(art)
			placed += 1

# 读一张房子贴图的像素：先走文件流（源码 / headless 下最稳, 见项目记忆里的 CompressedTexture2D 坑）,
# 读不到再走导入贴图。
# ❗e52b 导出包修复：res:// 的原始 png 不进 PCK（export_presets 是 all_resources + include_filter 空）,
#   只走文件流的话导出后量不到任何一张, 装饰楼的池子会是空的 -> 整批装饰楼不见。
func _decor_image(path: String) -> Image:
	var buf := FileAccess.get_file_as_bytes(path)
	if not buf.is_empty():
		var im := Image.new()
		if im.load_png_from_buffer(buf) == OK:
			im.convert(Image.FORMAT_RGBA8)
			return im
	var tex := SoftRes.tex(path)
	if tex != null:
		var ti := tex.get_image()
		if ti != null and ti.get_width() > 0 and ti.get_height() > 0:
			var out := Image.new()
			# 副本: 别把共享贴图的 Image 改花
			out.copy_from(ti)
			out.convert(Image.FORMAT_RGBA8)
			return out
	return null

# 量一张房子贴图: 实底宽 w / 实底高 h（到底边为止）/ 实底左右缘 x0 x1
func _measure_decor(path: String) -> Dictionary:
	var img := _decor_image(path)
	if img == null:
		return {}
	var minx := -1
	var maxx := -1
	var bottom := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				if minx < 0 or x < minx:
					minx = x
				if x > maxx:
					maxx = x
				bottom = y
	if minx < 0:
		return {}
	return {"file": path.get_file(), "w": float(maxx - minx + 1),
		"h": float(bottom + 1), "x0": float(minx), "x1": float(maxx)}

# ---------------- 城区街道（e12g: 把码头/功能房/装饰楼串起来的土路） ----------------
# 用 16x16 色块沿格子铺 L 形路: 主干从栈桥头到议事厅门口, 支路连集市/酒馆/每座装饰楼。
# z=-12 垫在房子和人脚下（贴图 -14 之上）; 半透明土色压在草地上不抢戏。
func _add_streets() -> void:
	var holder := Node2D.new()
	holder.name = "Streets"
	holder.z_index = -12
	add_child(holder)
	var img := Image.create_empty(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.60, 0.52, 0.38))
	# 几粒明暗沙点, 路面不那么塑料
	for p in [Vector2i(3, 4), Vector2i(11, 9), Vector2i(7, 13), Vector2i(13, 2)]:
		img.set_pixel(p.x, p.y, Color(0.50, 0.43, 0.31))
	for p in [Vector2i(5, 11), Vector2i(12, 6)]:
		img.set_pixel(p.x, p.y, Color(0.68, 0.60, 0.45))
	var tex := ImageTexture.create_from_image(img)
	var home_foot := Vector2(float(HOME_CELL.x * CELL + CELL / 2),
		float(HOME_CELL.y * CELL + CELL))
	var segs: Array = [
		[_pier_root(), home_foot],                       # 主干: 码头 -> 议事厅
		[Vector2(float(MARKET_CELL.x * CELL + CELL / 2), float(MARKET_CELL.y * CELL + CELL)), home_foot],
		[Vector2(float(TAVERN_CELL.x * CELL + CELL / 2), float(TAVERN_CELL.y * CELL + CELL)), home_foot],
	]
	for n in world.get_children():
		if (n as Node).name.begins_with("DecorHouse"):
			segs.append([(n as Node2D).position, home_foot])   # 支路: 每座楼 -> 主干
	for s in segs:
		_street_path(holder, tex, s[0], s[1])

# 从 a 到 b 铺 L 形路块（先横后竖, 一格一步）
func _street_path(holder: Node2D, tex: Texture2D, a: Vector2, b: Vector2) -> void:
	var cur := Vector2(roundf(a.x / CELL) * CELL, roundf(a.y / CELL) * CELL)
	var goal := Vector2(roundf(b.x / CELL) * CELL, roundf(b.y / CELL) * CELL)
	var guard := 0
	while guard < 200:
		guard += 1
		_street_block(holder, tex, cur)
		if absf(goal.x - cur.x) > 0.5:
			cur.x += signf(goal.x - cur.x) * CELL
		elif absf(goal.y - cur.y) > 0.5:
			cur.y += signf(goal.y - cur.y) * CELL
		else:
			break

func _street_block(holder: Node2D, tex: Texture2D, pos: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = pos - Vector2(CELL * 0.5, CELL * 0.5)
	s.modulate = Color(1, 1, 1, 0.72)
	holder.add_child(s)

func _add_decor_building(d: Dictionary, foot: Vector2, idx: int) -> void:
	var n := Node2D.new()
	n.name = "DecorHouse%d" % idx
	n.position = foot
	n.scale = Vector2(DECOR_SCALE, DECOR_SCALE)   # 缩放整株: sprite 和占位一起变小
	var s := Sprite2D.new()
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.texture = SoftRes.tex(HOUSE_SHEET % str(d["file"]))
	# 画的内容以脚下格为中心: 底边压着脚线
	s.position = Vector2((float(d["x0"]) + float(d["x1"]) + 1.0) * -0.5, -float(d["h"]))
	n.add_child(s)
	world.add_child(n)
	_house_rects.append(Rect2(foot.x - float(d["w"]) * DECOR_SCALE * 0.45, foot.y - 26.0,
		float(d["w"]) * DECOR_SCALE * 0.9, 26.0))

# 城镇模式：议事厅两侧各插一面国旗（程序化小旗，旗面用国家配色），
# 一眼认出这座城是谁家的 —— 盟约生效的国家进城时旗子也照旧，配色即立场。
func _add_banners() -> void:
	var nid := _town_nid()
	var col: Color = Nations.nation(nid).get("color", Color(0.8, 0.72, 0.42))
	var img := Image.create_empty(11, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 20:                            # 旗杆
		img.set_pixel(1, y, Color(0.42, 0.30, 0.18))
		img.set_pixel(2, y, Color(0.34, 0.24, 0.14))
	for y in range(1, 8):                   # 旗面：国色 + 一条暗边
		for x in range(3, 11):
			img.set_pixel(x, y, col if x < 10 else col.darkened(0.25))
	var tex := ImageTexture.create_from_image(img)
	for dx in [-30.0, 30.0]:
		var n := Node2D.new()
		n.name = "Banner"
		n.position = _cell_center(HOME_CELL) + Vector2(dx, -14.0)
		var s := Sprite2D.new()
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = tex
		s.position = Vector2(-5, -20)
		n.add_child(s)
		world.add_child(n)

# 船停在栈桥两侧的水里（一左一右，多了再往南排一条）。
# ❗y 取桥的**中段**：站在岸上就能看见自己的船队，不用走到桥尽头。
func _moor_boats() -> void:
	var cx := float(PIER_X * CELL) + 15.5
	var cy := float((SHORE_Y + 3) * CELL)
	for i in maxi(1, Voyage.boats_needed()):
		var s := Sprite2D.new()
		s.texture = BOAT_HULL_TEX
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var side := 1.0 if i % 2 == 1 else -1.0
		s.position = Vector2(cx + side * 34.0, cy + float(i / 2) * 22.0)
		world.add_child(s)

# ---------------- 主角 ----------------
func _setup_player() -> void:
	player = Node2D.new()
	player.name = "Hero"
	player.position = _cell_center(Vector2i(PIER_X, SHORE_Y - 1))
	_sprite = AnimatedSprite2D.new()
	_sprite.position = Vector2(0, -16)      # 原点在脚下（跟岛上同一约定）
	_sprite.sprite_frames = _build_frames()
	_sprite.play(&"idle_down")
	player.add_child(_sprite)
	world.add_child(player)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(3, 3)
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = W * CELL
	_cam.limit_bottom = H * CELL
	player.add_child(_cam)
	_cam.make_current()
	_sync_walk_speed()

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for key in SHEETS.keys():
		var info: Dictionary = SHEETS[key]
		var tex: Texture2D = SoftRes.tex(MODEL_DIR % str(info["file"]))
		for d in DIR_ROW.keys():
			var an := StringName("%s_%s" % [key, d])
			sf.add_animation(an)
			sf.set_animation_loop(an, bool(info["loop"]))
			sf.set_animation_speed(an, float(info["fps"]))
			var row: int = DIR_ROW[d]
			for i in int(info["frames"]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * 32, row * 32, 32, 32)
				sf.add_frame(an, at)
	return sf

# 走路动画帧率永远跟着速度走（同 slave_npc._sync_walk_speed）
func _sync_walk_speed() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var frames := float(SHEETS["walk"]["frames"])
	var fps := minf(WALK_FPS_CAP, SPEED * frames / WALK_STRIDE_PX)
	for d in DIR_ROW.keys():
		var an := StringName("walk_%s" % d)
		if _sprite.sprite_frames.has_animation(an):
			_sprite.sprite_frames.set_animation_speed(an, fps)

# ---------------- 主循环 ----------------
func _physics_process(delta: float) -> void:
	if player == null or _closed:
		return
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving := mv != Vector2.ZERO
	if moving:
		# 两个轴分开试：撞墙了还能顺着墙滑，不会整个人卡死
		var next: Vector2 = player.position + Vector2(mv.x, 0.0).normalized() * SPEED * delta
		if walkable(next):
			player.position = next
		next = player.position + Vector2(0.0, mv.y).normalized() * SPEED * delta
		if walkable(next):
			player.position = next
		_facing = _dir_name(mv)
	if _sprite.animation != _anim_name(&"walk" if moving else &"idle"):
		_sprite.play(_anim_name(&"walk" if moving else &"idle"))
	_sprite.flip_h = (_facing == &"left")
	_update_near()

func _dir_name(dir: Vector2) -> StringName:
	if absf(dir.x) >= absf(dir.y):
		return &"right" if dir.x > 0 else &"left"
	return &"down" if dir.y > 0 else &"up"

func _anim_name(prefix: StringName) -> StringName:
	if _facing == &"left" or _facing == &"right":
		return StringName("%s_side" % String(prefix))
	return StringName("%s_%s" % [String(prefix), String(_facing)])

# 站在哪个交互点旁边（只认最近的一个，免得两行提示叠在一起）
func _update_near() -> void:
	var best := -1
	var best_d := 46.0 * 46.0
	for i in _spots.size():
		var d: float = player.position.distance_squared_to(_spots[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	if best == _near:
		return
	if _near >= 0 and _near < _hints.size():
		_hints[_near].call("hide_hint")
	_near = best
	if _near >= 0 and _near < _hints.size():
		_hints[_near].call("show_hint")
	if _hint != null:
		_hint.text = _hint_text()

func _hint_text() -> String:
	var head := ""
	if town_id == "":
		head = "大陆码头 - 集市 / 酒馆 / 栈桥\nWASD 走动, 走近按 F"
	else:
		head = "%s (%s) - 议事厅 / 栈桥\nWASD 走动, 走近按 F" % [
			_town_name(), _nation_name()]
	if _near >= 0:
		return "%s\n[F] %s" % [head, _spot_word(_near)]
	return head

func _spot_word(i: int) -> String:
	match str(_spots[i]["kind"]):
		"market": return "集市 (买卖东西)"
		"tavern": return "酒馆 (花钱雇人)"
		"town": return "议事厅 (商贸 / 攻城 / 酒馆 / 逛逛 / 管理)"
		_: return "栈桥 (回海图)"

# ---------------- HUD ----------------
func _setup_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	_hint = Label.new()
	_hint.text = _hint_text()
	_hint.add_theme_font_override("font", FONT_PIX)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_hint.position = Vector2(12, 10)
	_hud.add_child(_hint)
	# 三个交互点头顶常驻的 [F] 徽章。
	# ❗要挂在**世界坐标**里（跟着相机走），不能挂 HUD —— HUD 是屏幕坐标，
	#   相机一移动徽章就飘到别处了。
	for spot in _spots:
		var holder := Node2D.new()
		holder.position = spot["pos"]
		world.add_child(holder)
		var k = KEY_HINT.new()
		k.setup("F", str(spot["word"]), -40.0)
		holder.add_child(k)
		# e36i: 左键点哪个点的框就进哪个点（比按 F 只认最近的那个更准）
		# ❗字符串写法: KEY_HINT.new() 推不出静态类型, 走 connect("clicked", ...) 最稳
		k.connect("clicked", _on_hint_clicked.bind(_hints.size()))
		_hints.append(k)

func announce(text: String, dur := 3.5) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.62))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position.y = 58
	_hud.add_child(l)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

# ---------------- 交互 ----------------
func _unhandled_input(event: InputEvent) -> void:
	if _closed or _near < 0:
		return
	if not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	_open_spot(_near)

# e36i 左键点了某个交互点头上的「F xxx」框 —— 直接开那一个（不用凑 F 那个「最近的点」判定）
func _on_hint_clicked(i: int) -> void:
	if _closed or i < 0 or i >= _spots.size():
		return
	_open_spot(i)

func _open_spot(i: int) -> void:
	match str(_spots[i]["kind"]):
		"market":
			_get_market().call("open_panel")
		"tavern":
			_get_tavern().call("open_panel")
		"town":
			_get_town().call("open_panel")
		_:
			_closed = true
			announce("回海图")
			await get_tree().create_timer(0.5).timeout
			Voyage.leave_mainland()

func _get_market() -> Control:
	if _market == null:
		_market = preload("res://market_ui.gd").new()
		_market.name = "MarketPanel"
		_hud.add_child(_market)
	return _market

func _get_tavern() -> Control:
	if _tavern == null:
		_tavern = preload("res://tavern_ui.gd").new()
		_tavern.name = "TavernPanel"
		_hud.add_child(_tavern)
	return _tavern

func _get_town() -> Control:
	if _town == null:
		_town = preload("res://town_ui.gd").new()
		_town.call("setup", town_id)       # add_child 之前给，_ready 里就要用
		_town.name = "TownPanel"
		_hud.add_child(_town)
	return _town

# ---------------- 城镇信息 ----------------
func _town_nid() -> String:
	return String(Nations.TOWNS.get(town_id, {}).get("nation", ""))

func _town_name() -> String:
	return String(Nations.TOWNS.get(town_id, {}).get("name", "城镇"))

func _nation_name() -> String:
	return String(Nations.nation(_town_nid()).get("name", ""))
