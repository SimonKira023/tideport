extends RefCounted
# scene/world_map/decor_layer.gd —— 海图「装饰层」实现模块。
#
# 原先长在 scene/world_map.gd 的 `# ---------------- 树 / 礁石 / 码头标记 ----------------` 一节，
# 整块搬到这里：陆地果树林、远洋礁石、两头码头标记、三条河的桥面贴图。
#
# 【为什么是 RefCounted 而不是 Node2D 子节点】
#   这些 Sprite2D 必须**直接挂在海图根节点下**（与地形/城镇同层参与 z 排序，Trees 容器还要
#   被 _physics_process 整体显隐救帧率）。套一层容器会多出一级父节点、打乱子节点顺序与 z。
#   所以模块只负责「建 + add_child」，节点一律 g.add_child() 挂回海图。
#
# 【字段为什么留宿主】
#   `_trees_root` 被 _physics_process 直接读写（观景档拉远时整片藏掉）→ 必须是宿主真字段，
#   模块写 g._trees_root。dock_island / dock_continent / _land / _water / _sea_d / _town_marks
#   都是宿主生成的地形与标记数据，模块只读。
#
# 【耦合面（模块回问宿主的接口）】
#   g.SEED
#   g._land g._water g._sea_d g.dock_island g.dock_continent g._town_marks g._trees_root
#   g._cell_center() g.R() g.add_child()
#   g.ISLAND_CENTER g.ISLAND_BRIDGE_ROWS g.ISLAND_RIVER_FREQ g.ISLAND_RIVER_PHASE g.ISLAND_RIVER_WOBBLE
#   g.RIVER_EW_BRIDGE_COLS g.RIVER_EW_Y g.RIVER_EW_FREQ g.RIVER_EW_PHASE g.RIVER_EW_HALF
#   g.RIVER_W_BRIDGE_ROWS g.RIVER_W_X g.RIVER_W_FREQ g.RIVER_W_PHASE g.RIVER_W_HALF
#   注意：`_game` 故意不标类型（动态派发），所以从 `g.` 取回来的一切都是 Variant，
#   凡是出现在 `:=` 右边的都要显式标类型，否则会撞 Parse Error（项目已知坑）。

var _game = null          # world_map 节点（动态派发，故意不标类型）

# 幂等。宿主门面每次都先调一次（自检会裸 load().new() 建海图、不进树, _ready 不跑）。
func setup(game) -> void:
	_game = game

# 树换成素材果树成树帧(战场同款 Cherry/Apricot 32x48, 帧号 6/3) ——
# 旧的 14x18 程序三角树太简陋(用户点名)。缩 0.9 贴 16px 格, NEAREST 干净像素。
const MAP_TREES := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Cherry Tree.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Apricot Tree.png",
]
const MAP_TREE_FRAME := [6, 3]        # 两种果树的「成树」帧号（同 scene/tree_node.gd）
const MAP_TREE_W := 32
const MAP_TREE_H := 48

func scatter_trees() -> void:
	var g = _game
	var noise := FastNoiseLite.new()
	noise.seed = int(g.SEED) + 999
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.11
	var texs: Array = []
	for k in MAP_TREES.size():
		var at := AtlasTexture.new()
		# 第三方素材不入库(见 README), 缺失时留空不崩
		at.atlas = SoftRes.tex(MAP_TREES[k])
		at.region = Rect2(float(MAP_TREE_FRAME[k] * MAP_TREE_W), 0.0,
			float(MAP_TREE_W), float(MAP_TREE_H))
		texs.append(at)
	var bridge_set := {}
	for bc in bridge_cells():
		bridge_set[bc] = true
	var holder := Node2D.new()
	holder.name = "Trees"
	g.add_child(holder)
	g._trees_root = holder
	for c in g._land.keys():
		var v := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
		if v < 0.72:
			continue
		# 码头附近留空，别把路挡了
		if g._cell_center(c).distance_to(g.dock_island) < 40.0 \
				or g._cell_center(c).distance_to(g.dock_continent) < 40.0:
			continue
		# 岛上两座木桥的桥面留空：树长在桥上像话吗
		if bridge_set.has(c):
			continue
		# 城镇周围也留空：旗子和小房不跟树挤在一块
		var near_town := false
		for m in g._town_marks:
			if g._cell_center(c).distance_to(m["pos"]) < 30.0:
				near_town = true
				break
		if near_town:
			continue
		var s := Sprite2D.new()
		s.texture = texs[absi(c.x * 13 + c.y * 7) % 2]   # 樱桃 / 杏树 交替，陆地不至一片同款
		s.position = g._cell_center(c) + Vector2(0, -6)
		holder.add_child(s)

# 礁石：远洋里稀疏撒几块，给空旷的海面一点地标（不影响航行）
func scatter_rocks() -> void:
	var g = _game
	var noise := FastNoiseLite.new()
	noise.seed = int(g.SEED) + 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.3
	var tex: ImageTexture = rock_tex()
	var holder := Node2D.new()
	holder.name = "Rocks"
	g.add_child(holder)
	for c in g._water.keys():
		if int(g._sea_d.get(c, 0)) < 3:       # 只挑够深的水，别糊在岸边
			continue
		if (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5 < 0.92:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.position = g._cell_center(c) + Vector2(0, -2)
		holder.add_child(s)

func rock_tex() -> ImageTexture:
	var g = _game
	var img := Image.create_empty(14, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	g.R(img, 1, 8, 12, 9, Color(0.86, 0.94, 0.96, 0.85))      # 脚下一圈白浪
	var stone := Color(0.44, 0.46, 0.50)
	var stone_l := Color(0.58, 0.60, 0.64)
	for p in [Vector2i(3, 7), Vector2i(4, 6), Vector2i(5, 7), Vector2i(5, 5),
			Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7),
			Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(8, 6),
			Vector2i(8, 7), Vector2i(9, 7)]:
		img.set_pixel(p.x, p.y, stone)
	for p in [Vector2i(5, 5), Vector2i(6, 4), Vector2i(7, 5)]:
		img.set_pixel(p.x, p.y, stone_l)
	return ImageTexture.create_from_image(img)

# 两头码头在海图上的标记：走到这儿按 F 返航 / 上岸，一眼看得见该去哪儿
func build_dock_marks() -> void:
	var g = _game
	var tex: ImageTexture = dock_tex()
	var holder := Node2D.new()
	holder.name = "DockMarks"
	g.add_child(holder)
	for p in [g.dock_island, g.dock_continent]:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = p + Vector2(0, -6)
		holder.add_child(s)

func dock_tex() -> ImageTexture:
	var img := Image.create_empty(16, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.58, 0.40, 0.23)
	var wood_d := Color(0.43, 0.29, 0.16)
	for x in 14:                            # 桥面横板（每 4 像素一条板缝）
		img.set_pixel(x + 1, 4, wood if x % 4 != 3 else wood_d)
		img.set_pixel(x + 1, 5, wood_d)
	for y in range(6, 12):                  # 两根桩
		img.set_pixel(3, y, wood_d)
		img.set_pixel(12, y, wood_d)
	return ImageTexture.create_from_image(img)

# 河上的木桥：三条河（出发岛小河 + 中部东西长河 + 西部南北河）的桥线豁出的格子
# 盖一层木板桥面，跟岛上（game.gd）两座桥的规矩对上。
func bridge_cells() -> Array:
	var g = _game
	var out: Array = []
	# 出发岛小河：南北河道, 桥是东西走向的整行
	for y in g.ISLAND_BRIDGE_ROWS:
		var rc: float = float(g.ISLAND_CENTER.x) \
			+ sin(float(y) * float(g.ISLAND_RIVER_FREQ) + float(g.ISLAND_RIVER_PHASE)) * float(g.ISLAND_RIVER_WOBBLE)
		for x in range(int(floor(rc - 1.6)), int(ceil(rc + 1.6))):
			var c := Vector2i(x, y)
			if g._land.has(c):
				out.append(c)
	# 中部东西长河：东西河道, 桥是南北走向的整列
	for x in g.RIVER_EW_BRIDGE_COLS:
		var ry: float = float(g.RIVER_EW_Y) \
			+ sin(float(x) * float(g.RIVER_EW_FREQ) + float(g.RIVER_EW_PHASE)) * float(g.RIVER_EW_WOBBLE)
		for y in range(int(floor(ry - float(g.RIVER_EW_HALF))), int(ceil(ry + float(g.RIVER_EW_HALF)))):
			var c := Vector2i(x, y)
			if g._land.has(c):
				out.append(c)
	# 西部南北河：南北河道, 桥是东西走向的整行
	for y in g.RIVER_W_BRIDGE_ROWS:
		var cx: float = float(g.RIVER_W_X) \
			+ sin(float(y) * float(g.RIVER_W_FREQ) + float(g.RIVER_W_PHASE)) * float(g.RIVER_W_WOBBLE)
		for x in range(int(floor(cx - float(g.RIVER_W_HALF))), int(ceil(cx + float(g.RIVER_W_HALF)))):
			var c := Vector2i(x, y)
			if g._land.has(c):
				out.append(c)
	return out

func build_bridges() -> void:
	var g = _game
	var tex: ImageTexture = bridge_tex()
	var holder := Node2D.new()
	holder.name = "Bridges"
	g.add_child(holder)
	for c in bridge_cells():
		var s := Sprite2D.new()
		s.texture = tex
		s.position = g._cell_center(c)
		holder.add_child(s)

func bridge_tex() -> ImageTexture:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color(0.58, 0.40, 0.23)
	var wood_d := Color(0.43, 0.29, 0.16)
	for y in 16:
		for x in 16:
			var c := wood if y % 4 != 3 else wood_d    # 横板缝（板东西向铺）
			if x <= 1 or x >= 14:
				c = wood_d                              # 东西两侧栏杆
			img.set_pixel(x, y, c)
	for y in range(2, 16, 5):               # 几颗铆钉点缀
		img.set_pixel(0, y, wood)
		img.set_pixel(15, y, wood)
	return ImageTexture.create_from_image(img)
