# scene/battle_map.gd —— 战役地图（遭遇战）
#
# 遭遇敌人后从海图切进来。四张预定地形（按模板名固定种子生成，每次一样）：
#   甲板 —— 海寇专属（h-m）：一大块船板四周全是海，接舷战
#   草原 —— 开阔，零星几棵树（山贼也可能撞上）
#   树林 —— 树多，近战绕来绕去（山贼的主场）
#   河谷 —— 一条河把战场劈成两半：两处浅滩 + 贴岸浅水都能趟过去，
#           河心深水照样挡（h-m 河谷涉水：水里迈不开腿、半身入水、照样能砍）
#
# 指挥（简化版骑砍，不用 G 循环）：
#   1/2/3 选第几编队（编队归属在派活面板里自己定；再按一次同一个键回全体，开局默认全体）
#   F1 → 鼠标左键：点一下 = 全员开过去（地上插旗，到了原地待命）；
#                 按住拖一条线再松手 = 沿这条线列阵，正面朝线的法线方向
#   F2 跟随我 / F3 冲锋 / F4 驻守 —— 只管伙伴，主角永远自己手走
#   O = 撤退（正在选落点/画线时，Esc 或右键先取消）：回海图，敌人还在原地
#   进战役就是慢动作（倍率在设置页调，Engine.time_scale）
#
# 骑砍味的四块（e48）：
#   · 阵型 —— 拖线展开还能选队形（横列/楔形/圆阵/散兵，指挥栏一颗按钮循环切）
#   · 兵种相克 —— 步兵拒马克骑兵 / 骑兵冲阵克弓手 / 弓手攒射克步兵（troop.counter_mult）
#   · 士气与溃逃 —— 阵亡、挨刀、血薄都掉士气, 士气见底当场溃逃退场; 一边崩了就是输
#   · 兵力对比条 —— 屏幕顶上一条, 左蓝右红, 还剩几成一眼看得见
#
# 出战名单 = 全体伙伴（全员自动出海，不占当天劳动；弓手会放箭，见 troop.gd）。
# 打赢：敌人给经验/金币（跟岛上同一套 Legion/Wallet）；打输：回家躺门口。
# e25: 胜负分出先弹**结算页**（主角/伙伴血量条 + 百分比 + 金币/声望/经验收获，
#      配 settle 曲池的 BGM），点了「继续」才回海图/回岛；撤退不走结算页。
extends Node2D

const CELL := 16
const W := 44
const H := 26
const FONT_PIX := preload("res://resources/font/IPix.ttf")
const TroopScript := preload("res://scene/troop.gd")
const ArrowScript := preload("res://scene/arrow.gd")

# ---------------- 地形美术素材（跟岛上同一套，不再是纯色方块）----------------
# 草地格 (9,18) 是从岛屿地形层统计出来的（岛上 8611 格草地全用这一格），
# 用它铺战场就与岛上的草地完全一致；花草点缀沿用岛上那几张「透明底单格」。
const GRASS_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Spring.png"
const GRASS_TILE := Vector2i(9, 18)
const PROP_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const DECOR_TUFT := [
	Vector2i(1, 0), Vector2i(5, 0), Vector2i(1, 1), Vector2i(5, 1),
	Vector2i(10, 0), Vector2i(10, 1),
]
const DECOR_FLOWER := [
	Vector2i(11, 0), Vector2i(12, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(8, 1), Vector2i(12, 1), Vector2i(11, 3), Vector2i(12, 3),
]
const DECOR_MUSHROOM := [Vector2i(13, 0), Vector2i(13, 1), Vector2i(11, 2)]
const DECOR_DENSITY := 0.16          # 战场比岛上稀一点：打仗时别让花草抢视线
const DECOR_NOISE_FREQ := 0.085

# 树：直接借岛上那套「果树生长图」的成树帧（32x48，原点在树干底部）
const TREE_SHEETS := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Cherry Tree.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Apricot Tree.png",
]
const TREE_MATURE_FRAME := [6, 3]     # 两种树的「成树」帧号（同 scene/tree_node.gd）
const TREE_FRAME_W := 32
const TREE_FRAME_H := 48
const TREE_BASE_Y := 45.0             # 帧里树干底部的行 —— 对齐到节点原点

# 水：沿用岛上的程序化水色（5 档深浅 × 3 种波纹），河看起来才像岛上的池塘
const WATER_DEPTHS := [
	Color(0.56, 0.87, 0.93), Color(0.43, 0.81, 0.91), Color(0.30, 0.74, 0.89),
	Color(0.18, 0.66, 0.86), Color(0.04, 0.50, 0.77),
]
const WATER_VARIANTS := 3
const WATER_RIPPLE := 0.035
const WATER_EDGE := 2
const WATER_MAX_DIST := 4

# 沙滩：陆地格朝水那一侧画一条沙色渐变（同岛上的岸线做法）
const SAND_W := 5
const SAND_BAND := [
	Color(0.86, 0.77, 0.50), Color(0.82, 0.74, 0.52, 0.85),
	Color(0.77, 0.72, 0.54, 0.55), Color(0.71, 0.75, 0.59, 0.24),
]
const SAND_TILE_OF := {"up": Vector2i(0, 0), "right": Vector2i(1, 0),
	"down": Vector2i(2, 0), "left": Vector2i(3, 0)}
# F1 集结点的人位偏移：一堆人别全叠在一个点上
const MOVE_SPREAD := [Vector2(0, 0), Vector2(-20, -12), Vector2(20, -12),
	Vector2(0, 18), Vector2(-20, 18), Vector2(20, 18)]

# 阵型（骑砍式）：拖一条线展开时按哪种队形站 —— 换个阵型就换接敌面。
# 只改「站位怎么摊开」（见 _formation_slots），不改口令/兵种，指挥栏一颗按钮循环切。
const FORMATIONS := ["横列", "楔形", "圆阵", "散兵"]
var formation := 0

# 士气折损：有人阵亡时, 倒地处周围的同营人一律掉这么多, 再按「这边已经折了几个人」加码。
# 顺风仗越打越稳, 逆风仗一崩就崩一片 —— 溃逃会连锁, 一场仗常常不是打到最后一人。
const MORALE_SHOCK := 18.0
const MORALE_SHOCK_STEP := 12.0

# 甲板（h-m 海寇接舷战）：战场中央一大块船板，四周全是海。配色仿 dock.gd 的木栈桥。
const DECK_X0 := 6
const DECK_X1 := 37          # 含两端：甲板 32 格宽，罩住两边出生列（11 / 33）
const DECK_Y0 := 3
const DECK_Y1 := 22          # 含两端：甲板 20 格高
const DECK_PLANK := 4        # 每块木板 4 像素宽（16px 一格里 4 条板）
const DECK_A := Color(0.58, 0.43, 0.27)      # 亮木板
const DECK_B := Color(0.48, 0.35, 0.22)      # 暗木板（相邻板深浅交替）
const DECK_SEAM := Color(0.28, 0.20, 0.13)   # 板缝
const DECK_RIM := Color(0.34, 0.24, 0.15)    # 船舷横梁（甲板最外一圈）

# 遭遇的敌人队伍（Voyage.enter_battle / enter_siege 里 set 进来，add_child 之前就位）
var party: Dictionary = {}
var is_siege := false         # 攻城战：打的是国家正规军守军，赢了解锁战利品
var _aid_name := ""           # 盟约援军的国家名（攻城时盟约国会派人助阵）
var world: Node2D = null      # 地形之上的世界层（y_sort：树/人互相遮挡）

# 出生列：两边都从「地图中间偏左右」开局，别贴着边缘 —— 一进场就能同时看到敌我，
# 指挥（F1 点地图）也不用先把镜头拖到对面去。
const SPAWN_HERO_X := 11
const SPAWN_FOE_X := 33

var template := "草原"
var blocked := {}            # Vector2i -> true（水 + 树；浅滩不挡）
var shallow := {}            # Vector2i -> true（贴岸浅水：能趟，减速不挡；h-m 河谷涉水）
var units: Array = []        # 全部 troop
var hero: Node2D = null
var arrows: Array = []
var _night_rect: Sprite2D       # e15h: 昼夜天色罩（深夜进战场就黑着打; 首条窄条引用）
var _night_a := 0.0             # 夜色 alpha（烘进 PNG 像素 + 取档, 不走 modulate）
var _night_parts: Array = []    # e15h: 夜罩全部窄条（movie 模式延帧重建时拆旧用）
var _cam: Camera2D              # e15h: 屏幕震动用（shake 往 offset 上抖，衰减后归零）
var _shake_t := 0.0
var _shake_amp := 0.0
var move_target := Vector2.ZERO   # F1 指定的集结点
var _dragging := false            # 左键按住正在拖阵型线
var _drag_from := Vector2.ZERO    # 拖拽起点（世界坐标）
var _drag_to := Vector2.ZERO      # 拖拽终点
var _preview: Node2D = null       # 阵型线预览（线 + 队位小方块）
var _mark: Sprite2D = null        # 集结点的旗子
var _over := false
var _exp_gain := 0
var _coin_gain := 0
var _foe_count := -1
var _last_coin := 0             # e25: 结算页要展示的战果（victory 分支里算好存下）
var _last_prest := 0
var _deployed_ids: Array = []   # 这场真正上阵的伙伴全局序号（结算页按它列血条）
var _settle_hud: CanvasLayer = null  # e25 结算页浮层（victory/defeat 弹出，点继续才收尾）
var _settle_result := ""
var _settle_armed := false      # 弹出 0.9 秒后才收「继续」输入：免得胜利那一刀的余点击把结算页瞬间关掉
var _ally_lost := 0             # 这场我方折了几个人（士气折损按它加码, 见 _morale_shock）
var _foe_lost := 0
var _rout_warned := {"ally": false, "enemy": false}   # 「崩溃」播报每边只喊一次

func _ready() -> void:
	add_to_group("battle")
	# e17: 进战场不再自动慢 —— 减速只在「选中编队」的指挥时刻生效(Voyage._apply_selection_slow)
	Voyage.set_squad_selection(0)    # 每场开局都是「全体」（用户要的默认）
	Voyage.set_command(1)            # 默认跟随我
	var ptype := String(party.get("type", "海寇"))
	var rng := RandomNumberGenerator.new()
	is_siege = String(party.get("siege", "")) != ""
	if is_siege:
		# 攻城战：城外平地开阔打，地形按城名定种子（同一座城每次进城一个样）
		template = "草原"
		rng.seed = hash("siege_" + String(party["siege"]))
	else:
		rng.seed = hash(ptype)      # 同类敌人总撞同款地形：地图「预定好」
		if ptype == "海寇":
			template = "甲板"       # h-m：海寇只会在船板上接舷，不再上草原/河谷
		else:
			template = ["树林", "草原"][rng.randi() % 2]
	# 地形之上先铺一层 World：开了 y_sort，人走到树后面会被树冠挡住
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	_build_terrain(rng)
	# 盟约援军：攻城时，凡与你有盟约的国家都会派两位义士助阵（nations.gd 承诺过的）
	if is_siege:
		for nid in Nations.nation_ids():
			if Nations.is_allied(nid):
				_aid_name = String(Nations.nation(nid).get("name", nid))
				break
	_spawn_units()
	_build_hud()
	_build_night()      # e15h: 按进场的时刻压夜色（深夜遭遇战画面要黑）
	_start_deploy()     # 布阵阶段：时间停住，摆好阵点「开始战斗」才开打（e11f）
	# 点地图也会改口令（=0 移动），所以按钮高亮跟着信号走，不是每帧刷
	Voyage.command_changed.connect(_sync_cmd_bar)
	Voyage.selection_changed.connect(_refresh_selection)
	_refresh_selection()
	if is_siege:
		var tname := String(Nations.TOWNS.get(String(party["siege"]), {}).get("name", ""))
		if _aid_name != "":
			_announce("攻城战 - %s!  %s派来援军!" % [tname, _aid_name])
		else:
			_announce("攻城战 - %s!" % tname)
	else:
		_announce("%s - 遭遇%s!" % [template, ptype])

# ---------------- 昼夜天色罩（e15h） ----------------
# 战场也认时刻: 19 点起渐入夜, 20 点后全黑, 清晨 7 点渐亮。
# ❗Movie Writer 渲染坑(15 轮对照实验定稿, e15h): --write-movie 模式下, 战场进场帧
#   「最先创建的那批含纹理节点」整批静默不渲染 —— 节点树完好、零报错、画面上就是
#   没有; 换颜色/拆窄条/独立父层/内容扰动/延帧重建/res 纹理全救不活, 而紧跟在一张
#   「注定不渲染的牺牲品 veil」之后建的条带三次复现全部实拍可见。普通窗口模式一切
#   正常。对策见 _build_night: 先建牺牲品罩挡住死亡批次, 再建主夜罩(预生成 PNG,
#   夜色 alpha 直接烘进 PNG 像素 —— 不依赖 modulate, 最稳)。
#   (2026-09-20 复核: modulate 在 Movie 下其实能用, 海图天色就是这么做的;
#   战场这套牺牲品+烘像素配方已实拍验证有效, 不再动它。)
func _build_night() -> void:
	var h := float(TimeManager.hour) + TimeManager.minute / 60.0
	var a := 0.0
	if h >= 20.0 or h < 5.0:
		a = 0.5
	elif h >= 19.0:
		a = (h - 19.0) * 0.5
	elif h < 7.0:
		a = (7.0 - h) / 2.0 * 0.5
	if a <= 0.01:
		return
	_night_a = a
	# [牺牲品 veil] Movie Writer 渲染坑的解法(15 轮对照实验定稿, 详见下注释):
	#   进场帧「最先建的那批含纹理节点」整批静默不渲染 —— 每轮实验里紧跟在
	#   一张注定不渲染的 veil 之后建的条带全部实拍可见(qb 六带/绿带/双面对照
	#   三次复现), 所以先建这张牺牲品罩挡住死亡批次, 再建真正的主夜罩。
	var imgv := Image.create_empty(W * CELL, H * CELL, false, Image.FORMAT_RGBA8)
	imgv.fill(Color(0.05, 0.07, 0.20, _night_a))
	var veil := Sprite2D.new()
	veil.texture = ImageTexture.create_from_image(imgv)
	veil.centered = false
	veil.z_index = 60
	add_child(veil)
	_spawn_night_stripes()

# 4 条 176px PNG 窄条并排(4x176=704), 夜色连 alpha 烘进 PNG(10 档, 5% 步进取最近);
# 必须在 _build_night 的牺牲品 veil 之后调用才会被 Movie Writer 渲染(见上注释)。
const NIGHT_VEIL_W := 176

func _spawn_night_stripes() -> void:
	for old in _night_parts:
		old.free()
	_night_parts.clear()
	var al := clampi(int(roundf(_night_a * 20.0)) * 5, 5, 50)   # 0.5->50 档
	var tex: Texture2D = load("res://resources/fx/night_veil_a%02d.png" % al)
	if tex == null:
		return
	for k in 4:
		var sk := Node2D.new()
		sk.z_index = 60     # 压过单位/树冠；HUD 是 CanvasLayer, 永远在罩上
		add_child(sk)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.position = Vector2(float(NIGHT_VEIL_W * k), 0.0)
		sk.add_child(spr)
		_night_parts.append(sk)
		if k == 0:
			_night_rect = spr   # selftest 断言用(首条, 仍是 Sprite2D)

# ---------------- 地形 ----------------
func _build_terrain(rng: RandomNumberGenerator) -> void:
	var land := {}
	var water := {}
	var ford := {}                 # 浅滩：画成沙色，可以走
	shallow = {}                   # 每场重建（battle_map 只活一场，保险起见）
	for x in W:
		for y in H:
			land[Vector2i(x, y)] = true
	if template == "甲板":
		# 接舷战（h-m）：中央一大块船板，四周全是海
		for y in H:
			for x in W:
				if x < DECK_X0 or x > DECK_X1 or y < DECK_Y0 or y > DECK_Y1:
					var c := Vector2i(x, y)
					land.erase(c)
					water[c] = true
	elif template == "河谷":
		for y in H:
			var cx := float(W) / 2.0 + sin(float(y) * 0.45) * 2.5
			for x in W:
				var c := Vector2i(x, y)
				if absf(float(x) - cx) <= 1.6:
					land.erase(c)
					water[c] = true
		# 两处浅滩（能趟过去的河段）
		for fy in [6, 7, 18, 19]:
			for x in W:
				var c := Vector2i(x, fy)
				if water.has(c):
					water.erase(c)
					ford[c] = true
					land[c] = true
		# 贴岸浅水（h-m 河谷涉水）：离岸 1 格的水能趟过去 —— 水下铺草、
		# 半透明水盖上去看着就浅；河心深水照样挡。
		var depth := _water_depth_map(water)
		for c in water.keys():
			if int(depth.get(c, 9)) <= 1:
				water.erase(c)
				shallow[c] = true
				land[c] = true
	# 树：挡路的障碍
	var tree_count: int = {"草原": 10, "树林": 32, "河谷": 14, "甲板": 0}.get(template, 10)
	var trees := {}
	var guard := 0
	while trees.size() < tree_count and guard < 500:
		guard += 1
		var c := Vector2i(rng.randi_range(6, W - 7), rng.randi_range(2, H - 3))
		if not land.has(c) or water.has(c) or ford.has(c) or shallow.has(c):
			continue
		# 出生列留空，别把人卡在树里
		if c.x < 8 or c.x > W - 9:
			continue
		trees[c] = true
	for c in trees.keys():
		blocked[c] = true
	for c in water.keys():
		blocked[c] = true

	# —— 画：甲板 / 草地(真素材) -> 沙滩 -> 水面(岛上同款水色) -> 浅水 -> 花草点缀 -> 树 ——
	if template == "甲板":
		_paint_deck()
	else:
		_paint_grass(land, ford)
		_paint_sand(land, water)
	_paint_water(water)
	_paint_shallow(shallow)
	if template != "甲板":
		_paint_decor(rng, land, water, ford)
	_spawn_trees(rng, trees)

# 甲板：船板纹理（深浅交替木板 + 板缝 + 船舷横梁），两个变体错开板缝别像贴图
func _paint_deck() -> void:
	var img := Image.create_empty(3 * CELL, CELL, false, Image.FORMAT_RGBA8)
	for v in 2:
		for y in CELL:
			for x in CELL:
				var band := (y + v * 2) / DECK_PLANK
				var col: Color = DECK_A if band % 2 == 0 else DECK_B
				if (y + v * 2) % DECK_PLANK == DECK_PLANK - 1:
					col = DECK_SEAM
				# 每条板里一点固定轻噪，木头才有纹理
				var n := float(((x * 7 + band * 13) % 11)) / 11.0
				img.set_pixel(v * CELL + x, y, Color(
					col.r * (0.92 + 0.10 * n), col.g * (0.92 + 0.10 * n),
					col.b * (0.92 + 0.10 * n)))
	for y in CELL:
		for x in CELL:
			var n := float(((x * 7 + y * 13) % 11)) / 11.0
			var col := DECK_RIM
			if y % DECK_PLANK == DECK_PLANK - 1:
				col = DECK_SEAM.darkened(0.3)
			img.set_pixel(2 * CELL + x, y, Color(
				col.r * (0.92 + 0.10 * n), col.g * (0.92 + 0.10 * n),
				col.b * (0.92 + 0.10 * n)))
	var layer := _make_tile_layer("Deck", ImageTexture.create_from_image(img),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], -20)
	for x in range(DECK_X0, DECK_X1 + 1):
		for y in range(DECK_Y0, DECK_Y1 + 1):
			var rim := x == DECK_X0 or x == DECK_X1 or y == DECK_Y0 or y == DECK_Y1
			layer.set_cell(Vector2i(x, y), 0, Vector2i(2 if rim else (x + y) % 2, 0))

# 浅水：半透明水色盖在草上（水下草/沙透出来 = 看着就浅），带一点波纹
func _paint_shallow(sh: Dictionary) -> void:
	if sh.is_empty():
		return
	var img := Image.create_empty(CELL, 2 * CELL, false, Image.FORMAT_RGBA8)
	for v in 2:
		for y in CELL:
			for x in CELL:
				var a := 0.52 + 0.07 * sin(float(x) * 0.9 + float(v) * 2.1 + float(y) * 0.35)
				img.set_pixel(x, v * CELL + y, Color(WATER_DEPTHS[0], a))
	var layer := _make_tile_layer("Shallow", ImageTexture.create_from_image(img),
		[Vector2i(0, 0), Vector2i(0, 1)], -13)
	for c in sh.keys():
		layer.set_cell(c, 0, Vector2i(0, absi(c.x * 374761393 + c.y * 668265263) % 2))

# 草地：真·美术图块（岛上同款）。浅滩格也铺草，沙色交给沙滩层压上去。
func _paint_grass(land: Dictionary, ford: Dictionary) -> void:
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var grass_tex := SoftRes.tex(GRASS_SHEET)
	if grass_tex == null:
		push_warning("[素材] 缺少草地贴图, 跳过铺设草地")
		return
	var layer := _make_tile_layer("Ground", grass_tex, [GRASS_TILE], -20)
	for c in land.keys():
		layer.set_cell(c, 0, GRASS_TILE)
	for c in ford.keys():
		layer.set_cell(c, 0, GRASS_TILE)

# 沙滩：紧挨水的陆地格，朝水那一侧画一条沙色渐变（跟岛上岸线一个做法）
func _paint_sand(land: Dictionary, water: Dictionary) -> void:
	var tiles: Array = []
	for k in SAND_TILE_OF.keys():
		tiles.append(SAND_TILE_OF[k])
	var tex := _sand_texture()
	var layer := _make_tile_layer("Sand", tex, tiles, -16)
	for c in land.keys():
		for dir in SAND_TILE_OF.keys():
			var nb: Vector2i = c + _dir_vec(dir)
			if water.has(nb):
				layer.set_cell(c, 0, SAND_TILE_OF[dir])

func _dir_vec(dir: String) -> Vector2i:
	match dir:
		"up": return Vector2i.UP
		"right": return Vector2i.RIGHT
		"down": return Vector2i.DOWN
	return Vector2i.LEFT

# 沙滩图集：四张 16x16，分别从四个方向由沙色渐隐到透明。
#   · 每张都从边缘往内 SAND_BAND.size() 像素渐变，越往里越淡 —— 跟草地融在一起
#   · 横向再撒一点固定噪点，别让渐变看着像塑料膜
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
				var band := int(float(depth) / float(SAND_W) * float(SAND_BAND.size()))
				band = clampi(band, 0, SAND_BAND.size() - 1)
				var col: Color = SAND_BAND[band]
				# 固定花纹（不随每局变），看着像沙粒
				var n := float(((x * 7 + y * 13 + i * 5) % 11)) / 11.0
				col.a *= 0.78 + 0.22 * n
				img.set_pixel(i * CELL + x, y, col)
	return ImageTexture.create_from_image(img)

# 水面：5 档深浅 × 3 种波纹的程序化水（同岛上），深浅按「离岸多远」分档
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
	# 分档边界加一点噪声，免得深浅之间出现一条条笔直的色带
	var wob := FastNoiseLite.new()
	wob.seed = 20260916
	wob.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wob.frequency = 0.13
	var last: int = WATER_DEPTHS.size() - 1
	for c in water.keys():
		var f: float = float(int(depth.get(c, 1))) - 1.0 \
			+ wob.get_noise_2d(float(c.x), float(c.y)) * 0.9
		var lv := clampi(int(floor(f + 0.5)), 0, last)
		var v := absi(c.x * 374761393 + c.y * 668265263) % WATER_VARIANTS
		layer.set_cell(c, 0, Vector2i(lv, v))

# 每格水离岸多远（4 邻域 BFS；地图外的水当作继续延伸的海）
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

# 一格水：底色是该档基色，内部几道轻波纹；四周 WATER_EDGE 像素保持纯基色（拼起来无缝）
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
			var col: Color = Color(clampf(base.r + a, 0.0, 1.0), clampf(base.g + a, 0.0, 1.0),
				clampf(base.b + a, 0.0, 1.0), 1.0)
			img.set_pixel(ox + x, oy + y, col)

# 花草点缀：按低频噪声定疏密，撒草丛 / 小花 / 蘑菇（同岛上的用法）
func _paint_decor(rng: RandomNumberGenerator, land: Dictionary, water: Dictionary,
		ford: Dictionary) -> void:
	var tiles: Array = DECOR_TUFT + DECOR_FLOWER + DECOR_MUSHROOM
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var prop_tex := SoftRes.tex(PROP_SHEET)
	if prop_tex == null:
		push_warning("[素材] 缺少花草点缀贴图, 跳过装饰层")
		return
	var layer := _make_tile_layer("Decor", prop_tex, tiles, -14)
	var noise := FastNoiseLite.new()
	noise.seed = 20260916
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = DECOR_NOISE_FREQ
	for c in land.keys():
		if ford.has(c) or shallow.has(c):
			continue                  # 浅滩不长草；浅水底下也不长（h-m）
		# 沙滩上不长草（贴着水的格子留干净）
		var on_sand := false
		for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
			if water.has(nb):
				on_sand = true
				break
		if on_sand:
			continue
		if blocked.has(c):
			continue                          # 树底下不撒
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

# 树：岛上那套果树成树帧，原点在树干底部（跟 scene/tree_node.gd 一个约定），
# 放进开了 y_sort 的 World 里，人走到树后面就被树冠挡住。
func _spawn_trees(rng: RandomNumberGenerator, trees: Dictionary) -> void:
	for c in trees.keys():
		var variant := rng.randi() % TREE_SHEETS.size()
		var at := AtlasTexture.new()
		at.atlas = SoftRes.tex(TREE_SHEETS[variant])
		at.region = Rect2(float(TREE_MATURE_FRAME[variant] * TREE_FRAME_W), 0.0,
			float(TREE_FRAME_W), float(TREE_FRAME_H))
		var n := Node2D.new()
		n.position = Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL - 3)
		n.add_to_group("battle_tree")   # e16f: 主角走到树后时这棵树要降半透明
		var s := Sprite2D.new()
		s.centered = false
		s.position = Vector2(-TREE_FRAME_W / 2.0, -TREE_BASE_Y)
		s.texture = at
		n.add_child(s)
		world.add_child(n)

# 建一个只有一种图块的 TileMapLayer（z_index 统一为负：地形永远在人脚下）
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

# ---------------- 出战名单 ----------------
func _spawn_units() -> void:
	# 主角：地图中间偏左
	var hero_c := _free_cell(Vector2i(SPAWN_HERO_X, H / 2))
	hero = _make_troop("hero", "刀客", _cell_pos(hero_c))
	hero.max_hp = Legion.player_max_hp()
	hero.hp = maxi(1, Legion.player_hp)          # 血是接着岛的伤继续算的
	hero.atk = Legion.player_atk()
	hero.speed = 62.0
	# 伙伴（出海名单里还活着的）：跟在主角身后一小簇。
	# 遍历 expedition 拿全局序号 i 传进 _make_troop —— 战场上的脸/配色都按它推导，
	# 才跟岛上「第 i 个伙伴长什么样」对得上。
	var row := 0
	for i in Slaves.expedition:
		var s: Dictionary = Slaves.slave_at(i)
		if s.is_empty() or int(s.get("hp", 30)) <= 0:
			continue                             # 倒下的伙伴上不了阵
		var ac := _free_cell(Vector2i(SPAWN_HERO_X - 1, H / 2 - 1 + row))
		var u := _make_troop("ally", String(s.get("troop", "刀客")), _cell_pos(ac), "", i)
		u.slave_data = s
		u.squad = 3 if u.is_mounted() else (2 if u.is_archer() else 1)   # 编队按兵种: 1近战/2射手/3骑兵
		u.max_hp = int(s.get("max_hp", 30))
		u.hp = int(s.get("hp", 30))
		u.atk = Legion.ally_atk() + Slaves.class_atk(String(s.get("troop", "刀客"))) \
			+ Slaves.affection_atk(int(s.get("affection", 0)))   # 军团 + 职业 + 好感加成
		# 骑兵策马: 比步兵快一截（政策卡「游哨」照样往上乘）
		u.speed = (48.0 if u.is_mounted() else 34.0) * Research.ally_speed_mult()
		u.call("set_order", 1)          # 开局都是跟着我
		u.died.connect(_on_ally_died)
		_deployed_ids.append(i)     # 结算页按这份名单列血条
		row += 1
	# 盟约援军：没有 companion 存档，打完这场就各自回乡（不会写回 Slaves）
	if _aid_name != "":
		for k in 2:
			var ac := _free_cell(Vector2i(SPAWN_HERO_X - 2, H / 2 - 2 + k * 2))
			var au := _make_troop("ally", "刀客", _cell_pos(ac), "", 90 + k)
			au.max_hp = 26 + Legion.level * 2
			au.hp = au.max_hp
			au.atk = 3 + int(Legion.level * 0.7)
			au.speed = 34.0
			au.call("set_order", 1)
	# 敌人：地图中间偏右，竖直方向围着中线排开（主角等级水涨船高，跟岛上刷怪同一套数值）
	var size := int(party.get("size", 3))
	# 国家正规军才有国籍可披（h-n 国甲）: 攻城查 siege 城镇所属国, 巡逻队 party 自带 nation;
	# 山贼/海寇的 nation 是空串 —— 赤膊红皮不变
	var foe_nation := ""
	if is_siege:
		var tid := String(party.get("siege", ""))
		if Nations.TOWNS.has(tid):
			foe_nation = String((Nations.TOWNS[tid] as Dictionary).get("nation", ""))
	else:
		foe_nation = String(party.get("nation", ""))
	if is_siege:
		# 国家正规军守军：混编刀客与弓手，比野寇难缠；战利品在结算时按 Nations 算
		# 骑兵国（Nations.is_mounted）守军以骑兵为主：弓手压阵, 其余全员策马
		var mnt_siege := Nations.is_mounted(foe_nation)
		for i in size:
			var guard_archer := i % 3 == 2      # 每三人一个弓手压阵
			var guard_kind := "弓手" if guard_archer \
				else ("骑兵" if mnt_siege else "刀客")
			var fc := _free_cell(Vector2i(SPAWN_FOE_X, H / 2 + i - int(size / 2)))
			var u2 := _make_troop("enemy", guard_kind, _cell_pos(fc), foe_nation, i)
			u2.max_hp = 20 + Legion.level * 5
			u2.atk = 3 + int(Legion.level * 0.9)
			u2.speed = 44.0 if guard_kind == "骑兵" else 30.0
			u2.hp = u2.max_hp
			u2.died.connect(_on_enemy_died)
			_exp_gain += 14 + Legion.level * 2
	else:
		# e49: 巨岛野外多出两路非人敌人 —— 哥布林蛮族 / 岛上魔物, 各有自己的阵容
		var ptype_field := String(party.get("type", ""))
		if ptype_field == "哥布林":
			_spawn_goblin_foes(size)
		elif ptype_field == "魔物":
			_spawn_monster_foes(size)
		else:
			var mnt_field := Nations.is_mounted(foe_nation)
			for i in size:
				var is_archer := (i == size - 1 and size >= 3)   # 3 人队带一个弓手压阵
				var fc := _free_cell(Vector2i(SPAWN_FOE_X, H / 2 + i - int(size / 2)))
				var foe_kind := "弓手" if is_archer \
					else ("骑兵" if mnt_field else "刀客")
				var u2 := _make_troop("enemy", foe_kind, _cell_pos(fc), foe_nation, i)
				if is_archer:
					u2.max_hp = 12 + Legion.level * 3
					u2.atk = 2 + int(Legion.level * 0.6)
					u2.speed = 26.0
				else:
					u2.max_hp = 18 + Legion.level * 4
					u2.atk = 3 + int(Legion.level * 0.8)
					# 骑兵策马：跑得比步兵快一截, 冲锋接敌更凶
					u2.speed = 44.0 if foe_kind == "骑兵" else 28.0
				u2.hp = u2.max_hp
				u2.died.connect(_on_enemy_died)
				# e16e: 战斗奖励大幅上调(原 10+lv*2 / 8+lv*3) —— 出生入死一场才换
				# 十几金, 种一天田就盖过去了, 打仗不值得。现在一场稳稳 100+ 金。
				_exp_gain += 30 + Legion.level * 6
				_coin_gain += 30 + Legion.level * 10

# 哥布林蛮族的阵容（e49）：三种兵混编 —— 矛手顶在前排, 弓手/炸弹手在后排放风筝。
# 数值比野寇薄一点, 但腿快、人多; 队里按 i%3 轮着出兵种。
func _spawn_goblin_foes(size: int) -> void:
	var pool: Array = TroopScript.GOBLIN_KINDS
	for i in size:
		var kind := String(pool[0]) if size <= 1 else String(pool[i % pool.size()])
		var fc := _free_cell(Vector2i(SPAWN_FOE_X, H / 2 + i - int(size / 2)))
		var u := _make_troop("enemy", kind, _cell_pos(fc), "", i)
		if u.is_archer():
			u.max_hp = 10 + Legion.level * 2
			u.atk = 2 + int(Legion.level * 0.5)
			u.speed = 30.0
		else:
			u.max_hp = 16 + Legion.level * 4
			u.atk = 3 + int(Legion.level * 0.7)
			u.speed = 34.0
		u.hp = u.max_hp
		u.died.connect(_on_enemy_died)
		_exp_gain += 22 + Legion.level * 4
		_coin_gain += 18 + Legion.level * 6

# 魔物的阵容（e49）：史莱姆/毒菇人/芽苗史莱姆/毒花/尖刺怪 五类轮着来。
# 一律近战(贴上去撞/咬), 走得慢但皮厚 —— 手感跟人形敌人故意拉开差异。
func _spawn_monster_foes(size: int) -> void:
	var pool: Array = TroopScript.MONSTER_KINDS
	for i in size:
		var kind := String(pool[i % pool.size()])
		var fc := _free_cell(Vector2i(SPAWN_FOE_X, H / 2 + i - int(size / 2)))
		var u := _make_troop("enemy", kind, _cell_pos(fc), "", i)
		u.max_hp = 22 + Legion.level * 5
		u.atk = 3 + int(Legion.level * 0.7)
		u.speed = 20.0
		u.hp = u.max_hp
		u.died.connect(_on_enemy_died)
		_exp_gain += 26 + Legion.level * 5
		_coin_gain += 22 + Legion.level * 7

func _make_troop(side: String, kind: String, pos: Vector2, nation := "", idx := 0) -> Node2D:
	var u: Node2D = TroopScript.new()
	u.side = side
	u.kind = kind
	u.position = pos
	u.index = idx                 # ❗add_child 前给号 —— _ready 里靠它挑脸/配色
	world.add_child(u)
	units.append(u)
	return u

# 格子中心的世界坐标
func _cell_pos(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5) * CELL

# 想要的那格被水/树占着就往旁边找一格空地（不穿墙、不站水里）。
# 螺旋式往外找，优先保持同一侧 —— 免得伙伴被挤到河对岸去。
func _free_cell(prefer: Vector2i) -> Vector2i:
	var want := Vector2i(clampi(prefer.x, 1, W - 2), clampi(prefer.y, 1, H - 2))
	if not blocked.has(want):
		return want
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := want + Vector2i(dx, dy)
				if c.x < 1 or c.x >= W - 1 or c.y < 1 or c.y >= H - 1:
					continue
				if not blocked.has(c):
					return c
	return want

# ---------------- HUD ----------------
var _cmd_label: Label
var _count_label: Label
var _tally_on := false         # e27k: Tab 切换 —— 战况行（双方剩余人数）默认藏起来
var _slow_label: Label        # e17: 「指挥中 0.1x」指示 —— 只在选中编队时亮
var _squad_label: Label

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	_cmd_label = Label.new()
	_cmd_label.text = "左键点地面 = 走过去    左键点敌人 = 冲上去    左键拖一条线 = 沿线列阵\n" \
		+ "右键 = 取消    O = 撤退    Tab = 战况    左下角按钮 = 选编队 / 令 / 阵型\n" \
		+ "兵种相克: 步兵克骑兵 / 骑兵克弓手 / 弓手克步兵"
	_cmd_label.add_theme_font_override("font", FONT_PIX)
	_cmd_label.add_theme_font_size_override("font_size", 13)
	_cmd_label.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_cmd_label.add_theme_constant_override("outline_size", 4)
	_cmd_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_cmd_label.position = Vector2(12, 10)
	hud.add_child(_cmd_label)
	# 当前在指挥谁（颜色 = 该编队的选中圈颜色，一眼对得上）
	_squad_label = Label.new()
	_squad_label.add_theme_font_override("font", FONT_PIX)
	_squad_label.add_theme_font_size_override("font_size", 14)
	_squad_label.add_theme_constant_override("outline_size", 4)
	_squad_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_squad_label.position = Vector2(12, 48)
	hud.add_child(_squad_label)
	_count_label = Label.new()
	_count_label.add_theme_font_override("font", FONT_PIX)
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.78))
	_count_label.add_theme_constant_override("outline_size", 4)
	_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_count_label.position = Vector2(12, 68)
	_count_label.visible = false     # e27k: 按 Tab 才显示
	hud.add_child(_count_label)
	# 右上角提示（e17）: 选中编队指挥时才亮 —— 「指挥中 0.1x」, 下令后自动隐掉
	_slow_label = Label.new()
	_slow_label.text = "指挥中 - 时间 0.1x"
	_slow_label.add_theme_font_override("font", FONT_PIX)
	_slow_label.add_theme_font_size_override("font_size", 11)
	_slow_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_slow_label.add_theme_constant_override("outline_size", 4)
	_slow_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_slow_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_slow_label.position = Vector2(-104, 10)
	_slow_label.visible = false
	hud.add_child(_slow_label)
	Voyage.selection_changed.connect(_refresh_slow_label)
	# 出海已全自动：全员跟主角出海，不再需要「勾选 明天出行」的提示
	_build_cmd_bar(hud)
	_build_tally(hud)
	# 相机跟主角
	var cam := Camera2D.new()
	cam.zoom = Vector2(4, 4)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = W * CELL
	cam.limit_bottom = H * CELL
	hero.add_child(cam)
	_cam = cam                    # e15h: 记下来，shake() 往它 offset 上抖
	cam.make_current()

# ---------------- 屏幕震动（e15h） ----------------
# 主角砍中轻震(0.7) / 主角挨打震(1.5)，触发在 troop 里（e27k 力度收敛防晃眼）。
# 相机 offset 随机抖，0.22 秒线性衰减归零（衰减写在 _physics_process 开头）。
func shake(amp: float) -> void:
	_shake_amp = maxf(_shake_amp, amp)
	_shake_t = maxf(_shake_t, 0.22)

# ---------------- 兵力对比条（骑砍式）----------------
# 屏幕正上方一条, 左边蓝条 = 我方、右边红条 = 敌方, 条长 = 各自还剩几成。
# 一眼看出「这仗还值不值得打」, 不用去数人头（Tab 那行细账照旧留着）。
# ❗分母用开战那一刻的人数（_tally_base_*）, 不是「当前最大」—— 不然一边死光时
#   另一边的条会被拉满, 看着像全员健在。
const TALLY_W := 240.0
const TALLY_HALF := 110.0
const TALLY_BAR_Y := 13.0
const TALLY_BAR_H := 8.0

var _tally_a_fill: ColorRect
var _tally_f_fill: ColorRect
var _tally_a_lbl: Label
var _tally_f_lbl: Label
var _tally_base_a := 0
var _tally_base_f := 0

func _build_tally(hud: CanvasLayer) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE    # 别把地图点击吃掉
	root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	root.position = Vector2(-TALLY_W * 0.5, 8.0)
	root.size = Vector2(TALLY_W, 30.0)
	hud.add_child(root)
	_tally_base_a = _count_side("ally")
	_tally_base_f = _count_side("enemy")
	# 底槽（左右各半）+ 两端的数字
	var bg_l := _tally_rect(Color(0, 0, 0, 0.55), Vector2(0.0, TALLY_BAR_Y), TALLY_HALF)
	var bg_r := _tally_rect(Color(0, 0, 0, 0.55),
		Vector2(TALLY_W - TALLY_HALF, TALLY_BAR_Y), TALLY_HALF)
	root.add_child(bg_l)
	root.add_child(bg_r)
	_tally_a_fill = _tally_rect(Color(0.42, 0.72, 1.0), Vector2(0.0, TALLY_BAR_Y), TALLY_HALF)
	_tally_f_fill = _tally_rect(Color(0.95, 0.42, 0.35),
		Vector2(TALLY_W - TALLY_HALF, TALLY_BAR_Y), TALLY_HALF)
	root.add_child(_tally_a_fill)
	root.add_child(_tally_f_fill)
	_tally_a_lbl = _tally_label(Vector2(0.0, -4.0), TALLY_HALF,
		HORIZONTAL_ALIGNMENT_LEFT, Color(0.72, 0.88, 1.0))
	_tally_f_lbl = _tally_label(Vector2(TALLY_W - TALLY_HALF, -4.0), TALLY_HALF,
		HORIZONTAL_ALIGNMENT_RIGHT, Color(1.0, 0.72, 0.66))
	root.add_child(_tally_a_lbl)
	root.add_child(_tally_f_lbl)

func _tally_rect(c: Color, pos: Vector2, w: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = Vector2(w, TALLY_BAR_H)
	return r

func _tally_label(pos: Vector2, w: float, align: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.position = pos
	l.size = Vector2(w, 16)
	l.horizontal_alignment = align
	return l

# 一边场上还剩几个（溃逃的跟倒下的一样不算, 见 troop.routing）
func _count_side(s: String) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.side == s and not bool(u.get("_dying")):
			n += 1
	return n

# 条长 = 剩下的成数；敌方的条从右边往里缩, 两条在中间对头
func _update_tally(ally_n: int, foe_n: int) -> void:
	if _tally_a_fill == null:
		return
	var fa := clampf(float(ally_n) / float(maxi(1, _tally_base_a)), 0.0, 1.0)
	var ff := clampf(float(foe_n) / float(maxi(1, _tally_base_f)), 0.0, 1.0)
	_tally_a_fill.size.x = TALLY_HALF * fa
	_tally_f_fill.size.x = TALLY_HALF * ff
	_tally_f_fill.position.x = TALLY_W - TALLY_HALF * ff
	_tally_a_lbl.text = "我方 %d" % ally_n
	_tally_f_lbl.text = "敌方 %d" % foe_n

# ---------------- 左下角指挥按钮条 ----------------
# 键盘指令全删了，编队和号令都改成鼠标点（点按钮不会误判成点地图：
# Button 自己会吃掉那次点击，_unhandled_input 收不到）。
var _squad_btns: Array = []   # [全体, 剑士, 弓手, 骑兵]（下标 = Voyage.selection）
var _cmd_btns: Array = []     # [跟随我, 冲锋, 驻守, 撤退]
var _deselect_btn: Button = null   # e41f: 取消选中（回到全体）
var _form_btn: Button = null       # e48: 阵型（横列/楔形/圆阵/散兵，点一下换一种）
const CMD_IDS := [1, 2, 3, -1]  # 最后一个是撤退，不是 Voyage.command

const BAR_ROW_A_Y := -70.0   # 编队那一排
const BAR_ROW_B_Y := -40.0   # 号令那一排
const BAR_TIP_Y := -98.0
const BAR_BTN_DX := 62.0     # 按钮横向间距
const BAR_BTN_W := 56.0
const BAR_BTN_N := 5         # 上排 4 个编队 + 1 个取消选中
const BAR_FORM_W := 76.0     # 「阵型」按钮宽一点（要装下「阵型:楔形」）
const BAR_W := 406.0         # 底衬宽度：罩住上排最后一颗按钮（阵型）

func _build_cmd_bar(hud: CanvasLayer) -> void:
	# 底衬：草地太亮，按钮直接浮在上面看不清
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.4)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 别把地图的点击吃掉
	_place_bottom(back, 8, BAR_TIP_Y, BAR_W, -BAR_TIP_Y - 8)
	hud.add_child(back)
	var tip := Label.new()
	tip.text = "指挥"
	tip.add_theme_font_override("font", FONT_PIX)
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(0.8, 0.8, 0.72))
	tip.add_theme_constant_override("outline_size", 4)
	tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_place_bottom(tip, 12, BAR_TIP_Y + 2, 120, 20)
	hud.add_child(tip)
	# 上排：这轮指挥谁（e41h: 编队按兵种叫 剑士/弓手/骑兵）
	_squad_btns = []
	for i in 4:
		var n := i          # 0 = 全体
		var b := _mk_btn("全体" if n == 0 else Voyage.squad_name(n),
			12 + i * BAR_BTN_DX, BAR_ROW_A_Y)
		b.pressed.connect(func():
			Voyage.set_squad_selection(n)
			_refresh_selection()
			_hold_deploy_freeze())
		_squad_btns.append(b)
		hud.add_child(b)
	# e41f/e41j: 取消选中 —— 一键「不指挥」（谁都不听令）。
	# ❗别再退回 0（那是全体）：取消完再下口令就变成全军一起动, 跟按钮字面意思正好拧着。
	_deselect_btn = _mk_btn("取消选中", 12 + 4 * BAR_BTN_DX, BAR_ROW_A_Y)
	_deselect_btn.pressed.connect(func():
		Voyage.set_squad_selection(Voyage.SELECT_NONE)
		_refresh_selection()
		_hold_deploy_freeze())
	hud.add_child(_deselect_btn)
	# 阵型：拖线展开时按哪种队形站（横列/楔形/圆阵/散兵），点一下换一种
	_form_btn = _mk_btn(_form_label(), 12 + 5 * BAR_BTN_DX, BAR_ROW_A_Y, BAR_FORM_W)
	_form_btn.pressed.connect(func():
		_cycle_formation()
		_sync_cmd_bar())
	hud.add_child(_form_btn)
	# 下排：下什么口令
	_cmd_btns = []
	var names := ["跟随我", "冲锋", "驻守", "撤退"]
	for i in 4:
		var cmd: int = CMD_IDS[i]
		var b := _mk_btn(names[i], 12 + i * BAR_BTN_DX, BAR_ROW_B_Y)
		b.pressed.connect(func():
			if cmd < 0:
				if not _over:
					_over = true
					_announce("撤退!")
					_finish("retreat", 0.6)
			else:
				_issue_order(cmd)
				_announce(Voyage.COMMAND_NAMES[cmd] + "!")
			_sync_cmd_bar())
		_cmd_btns.append(b)
		hud.add_child(b)

# e41g: 布阵期间时间是停的（Engine.time_scale = 0）。可是 Voyage.set_squad_selection
# 会顺手把 time_scale 改成 0.1/1.0（那是开打后的指挥慢放）—— 于是布阵时一按编队
# 或「冲锋」，士兵立刻就动起来了。所有指挥动作收尾都要把时间按回 0。
func _hold_deploy_freeze() -> void:
	if _deploying:
		Engine.time_scale = 0.0

# ---------------- 阵型（骑砍式）----------------
# 「拖一条线 = 沿线列阵」这条线上怎么摆人：横列最宽 / 楔形像把尖刀 / 圆阵四面御 /
# 散兵两排拉开。换阵型不改口令也不改兵种, 只改站位 —— 接敌面宽窄、谁先被撞上,
# 全靠这个（骑砍里阵型就是这么用的）。
func _form_label() -> String:
	return "阵型:" + FORMATIONS[formation]

func _cycle_formation() -> void:
	formation = (formation + 1) % FORMATIONS.size()
	if _form_btn != null:
		_form_btn.text = _form_label()
	_clear_preview()                 # 线上的人位跟着阵型变, 旧预览作废
	_announce("阵型 - %s" % FORMATIONS[formation], 1.4)
	_hold_deploy_freeze()            # e41g: 布阵时换阵型也不许解冻

# 拖线展开的落点表：同一条线, 换个阵型站出来的队形不一样。
#   from->to = 玩家画的那条线; face = 部队正面（_face_dir_for 算出来的法线）,
#   back = 正面反过来（往后站的方向）。落点顺序就是 picked 的顺序, 一一对应。
func _formation_slots(from: Vector2, to: Vector2, n: int, face: Vector2) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var back: Vector2 = -face.normalized() if face.length_squared() > 0.0001 else Vector2(0, -1)
	var span := from.distance_to(to)
	var axis: Vector2 = (to - from) / span if span > 0.001 else Vector2.RIGHT
	var mid := (from + to) * 0.5
	match formation:
		1:      # 楔形：中间的杵在最前, 两翼依次往后收 —— 撞进去像把尖刀
			for k in n:
				var t := 0.0 if n == 1 else float(k) / float(n - 1) * 2.0 - 1.0   # -1 .. 1
				out.append(mid + axis * (t * span * 0.5) + back * (absf(t) * span * 0.45 + 6.0))
		2:      # 圆阵：围着线心站一圈, 四面都能接敌（守御、护住弓手）
			var r := maxf(span * 0.5, 22.0)
			for k in n:
				var a := TAU * float(k) / float(n) - PI * 0.5
				out.append(mid + Vector2(cos(a), sin(a)) * r)
		3:      # 散兵：两排交错站开, 挤成一团的时候不至于被一箭一串
			var per := int(ceil(float(n) / 2.0))
			for k in n:
				var ri := k / per
				var ci := k % per
				var t := 0.5 if per <= 1 else float(ci) / float(per - 1)
				var stagger := Vector2.ZERO
				if ri % 2 == 1:
					stagger = axis * (span * 0.5 / float(per))
				out.append(from + (to - from) * t + back * (float(ri) * 18.0) + stagger)
		_:      # 横列（默认）：沿玩家画的那条线均分, 排成一条正面
			for k in n:
				var t := 0.5 if n == 1 else float(k) / float(n - 1)
				out.append(from + (to - from) * t)
	return out

# 一个 24 像素高的小按钮，钉在左下角（跟着窗口大小走，不会被顶掉）
func _mk_btn(t: String, x: float, y: float, w := BAR_BTN_W) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", FONT_PIX)
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE          # 别抢焦点，免得出现焦点框
	_place_bottom(b, x, y, w, 24)
	return b

# 锚点挂到左下角，再给相对偏移 —— 这样窗口拉大缩小都贴在角上
func _place_bottom(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)

# 当前选中哪一项，就把那颗按钮的字点亮（跟脚下选中圈的颜色对得上）
func _sync_cmd_bar() -> void:
	# e41j: 编队按钮「不指挥」时一颗都不亮（Voyage.selection = -1 谁都对不上）
	for i in _squad_btns.size():
		var b: Button = _squad_btns[i]
		var on := (i == Voyage.selection)
		b.add_theme_color_override("font_color",
			(Voyage.squad_color(i) if i > 0 else Color(1, 0.95, 0.85)) if on
			else Color(0.62, 0.62, 0.62))
	# 口令按钮：不指挥的时候整排灰掉（按了也没人接, 别让人以为下了令）
	var no_one: bool = Voyage.selection < 0
	for i in _cmd_btns.size():
		var cb: Button = _cmd_btns[i]
		var hit: bool = (not no_one and CMD_IDS[i] >= 0 and CMD_IDS[i] == Voyage.command)
		cb.add_theme_color_override("font_color",
			Color(0.5, 0.48, 0.45) if no_one else
				(Color(1, 0.85, 0.35) if hit else Color(0.82, 0.78, 0.72)))
	# e41f: 「取消选中」已经在不指挥状态时才灰着
	if _deselect_btn != null:
		_deselect_btn.add_theme_color_override("font_color",
			Color(1, 0.95, 0.85) if Voyage.selection >= 0 else Color(0.55, 0.53, 0.5))

# ---------------- 布阵阶段（开战前） ----------------
# 进战场先「布阵」：时间停住（Engine.time_scale = 0，敌人/伙伴/主角全体冻结），
# 玩家只能用指挥系统摆阵 —— 点地/拖线不再是「走过去」而是**瞬移**（时间都停了
# 还走什么走），编队/号令按钮照常能按（口令先存着，开战后才执行）。
# 屏幕下方一颗「开始战斗」按钮，点了才恢复时间开打。
var _deploying := false
var _deploy_hud: CanvasLayer = null

func _start_deploy() -> void:
	_deploying = true
	Engine.time_scale = 0.0            # 时间停：谁都不许动
	_build_deploy_hud()

func _build_deploy_hud() -> void:
	_deploy_hud = CanvasLayer.new()
	_deploy_hud.name = "DeployHUD"
	add_child(_deploy_hud)
	var title := Label.new()
	title.text = "阵型布置"
	title.add_theme_font_override("font", FONT_PIX)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.62))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position.y = 40
	_deploy_hud.add_child(title)
	var hint := Label.new()
	hint.text = "时间停止  左键点地 = 瞬移过去  左键拖线 = 瞬移列阵  编队/号令按钮照用"
	hint.add_theme_font_override("font", FONT_PIX)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position.y = 66
	_deploy_hud.add_child(hint)
	var go := Button.new()
	go.text = "开始战斗"
	go.add_theme_font_override("font", FONT_PIX)
	go.add_theme_font_size_override("font_size", 14)
	go.focus_mode = Control.FOCUS_NONE
	go.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	go.position = Vector2(-66, -50)
	go.size = Vector2(132, 32)
	go.pressed.connect(_begin_battle)
	_deploy_hud.add_child(go)

func _begin_battle() -> void:
	if not _deploying:
		return
	_deploying = false
	if _deploy_hud != null:
		_deploy_hud.queue_free()
		_deploy_hud = null
	# 从布阵的时间静止(time_scale=0)恢复流动; 若此时已选中编队, 下一句会压回 0.1x
	Voyage.set_battle_slow(false)
	Voyage.apply_selection_slow()
	_announce("开 战!", 1.6)

# 布阵瞬移：把人直接放到落点。落点在水里/树上就就近挪到能站的格子。
# set_order(0, p, face) 把「站住 + 朝向」存好、_arrived 保持 false —— 开战第一拍
# 距离已是 0，自动转「到位」并把脸转向正面（不用直接掏 troop 的内部状态）。
func _deploy_place(u: Node2D, p: Vector2, face := Vector2.ZERO) -> void:
	p.x = clampf(p.x, float(CELL), float((W - 1) * CELL))
	p.y = clampf(p.y, float(CELL), float((H - 1) * CELL))
	if is_blocked_at(p):
		p = _nearest_free(p)
	u.global_position = p
	u.call("set_order", 0, p, face)

# 落点被挡时向外一圈圈找最近的空位（每圈 12 个方向，最多 8 圈）
func _nearest_free(p: Vector2) -> Vector2:
	for r in range(1, 9):
		var step := float(r * CELL)
		for i in 12:
			var q := p + Vector2.from_angle(TAU * float(i) / 12.0) * step
			if not is_blocked_at(q):
				return q
	return p

# 公告字幕（顶部居中那一条）。
# ❗以前每条都钉在同一个 y 上，连着按 F1/F2/F3 会抛出好几条、互相盖成一团 ——
#   现在新的一条排在旧的**下方**，最多同时留 2 条，多出来的立刻淡掉。
var _announces: Array = []            # 活着的公告 Label（按出现顺序）
var _announce_alive: Dictionary = {}  # Label -> Tween（要手动 kill，不然淡出回调会打到已释放的节点）

func _announce(text: String, dur := 2.2) -> void:
	var hud: CanvasLayer = get_node_or_null("HUD")
	if hud == null:
		return
	while _announces.size() >= 2:
		_drop_announce(_announces[0])
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.62))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position.y = 108 + 28 * _announces.size()      # 往下顺延一行，别叠在一起
	hud.add_child(l)
	_announces.append(l)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		_announce_alive.erase(l)
		_announces.erase(l)
		if is_instance_valid(l):
			l.queue_free())
	_announce_alive[l] = tw

# 立刻收掉一条公告（连抛太多时挤掉最旧的那条）
func _drop_announce(l: Label) -> void:
	var tw = _announce_alive.get(l)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	_announce_alive.erase(l)
	_announces.erase(l)
	if is_instance_valid(l):
		l.queue_free()

# ---------------- 指挥（全鼠标：不用记键盘）----------------
# 左键点地面 = 选中的伙伴开过去；按住左键拖一条线 = 沿线列阵；
# 左键点敌人 = 冲向那个敌人。右键 = 取消/收起集结旗。O = 撤退，Tab = 战况。
# 编队与号令都做成左上角**可点的按钮**（见 _build_hud），不占键盘。
func _unhandled_input(event: InputEvent) -> void:
	# e25: 结算页开着 —— 指挥键全部休眠，任何按键（揭幕后）都当「继续」
	if _settle_hud != null:
		var sk := event as InputEventKey
		if sk != null and sk.pressed and not sk.echo and _settle_armed:
			_close_settlement()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE and _dragging:
			_cancel_drag()               # e27k: Esc 只管取消拖线（撤退键挪到 O，防误触）
			get_viewport().set_input_as_handled()
			return
		# e27k: 撤退键从 Esc 改成 O —— Esc 挨得太近容易把整场仗误退了
		if key.keycode == KEY_O and not _over:
			_over = true
			_announce("撤退!")
			_finish("retreat", 0.6)
			get_viewport().set_input_as_handled()
			return
		# e27k: Tab = 显示/收起双方剩余人数
		if key.keycode == KEY_TAB and _count_label != null:
			_tally_on = not _tally_on
			_count_label.visible = _tally_on
			get_viewport().set_input_as_handled()
			return
		# 数字键 1/2/3 选中编队：1剑士(近战) / 2弓手(远程) / 3骑兵（再按同一个键回全体）
		if key.keycode in [KEY_1, KEY_2, KEY_3]:
			Voyage.toggle_squad(key.keycode - KEY_1 + 1)
			_refresh_selection()
			_hold_deploy_freeze()     # e41g: 布阵时按键选编队也不许解冻
			get_viewport().set_input_as_handled()
			return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# e15h: 左键挥剑 —— 主角朝鼠标方向挥一刀（不再自动攻击）。
				# 点地图 / 拖阵型的指挥照旧，同一次点击两用：指挥伙伴顺手也挥一刀。
				if not _deploying:
					var hero: Node2D = get_hero()
					if hero != null:
						hero.call("swing_sword", get_global_mouse_position())
				# 按下 = 起笔：记住起点，之后拖多远就是阵型线多长
				_drag_from = get_global_mouse_position()
				_drag_to = _drag_from
				_dragging = true
				_update_formation_preview()
			else:
				_commit_formation()      # 松手 = 下令（没拖动就是「走过去」）
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_drag()
			get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		_drag_to = get_global_mouse_position()
		_update_formation_preview()
		get_viewport().set_input_as_handled()

func _cancel_drag() -> void:
	_dragging = false
	_clear_preview()

# ---- 松手：拖得够远就列阵，只点了一下就当普通移动 ----
const DRAG_MIN := 14.0           # 小于这个距离算"点一下"

func _commit_formation() -> void:
	var from := _drag_from
	var to := _drag_to
	var span := from.distance_to(to)
	_dragging = false
	_clear_preview()
	if span >= DRAG_MIN:
		_cast_line(from, to)
	else:
		_cast_move(to, true)     # e27f: 单击也走这里, 但点地不再下令（见下）

# 单击：选中的伙伴聚到这个点（各占一个人位，别叠一起）；点到的若是敌人，就冲他
# e27f: 单击点地不再下令 —— 玩家挥刀顺手点一下地, 全军就开跑, 是误触指挥的源头。
# 移动/列阵一律拖线（>=14px）；单击只保留「点敌人=冲锋」这种有明确意图的指令。
func _cast_move(pos: Vector2, tap := false) -> void:
	_clear_preview()          # 点了就别留着上一条阵型线
	# e41j: 不指挥的时候点地不该动队伍 —— 跟拖线那边同一句提示, 免得静悄悄没反应
	if Voyage.selection < 0:
		_announce("不指挥中 -- 点上面的编队按钮选一队")
		return
	if _deploying:
		# 布阵阶段：瞬移落位（时间停着，也不兴冲锋）
		move_target = pos
		_show_mark(pos)
		var here := _picked_units()
		for u in here:
			_deploy_place(u, pos + MOVE_SPREAD[u.index % MOVE_SPREAD.size()])
		Voyage.set_command(0)
		_announce("%s: 落位 %d 人!" % [Voyage.selection_name(), here.size()])
		return
	var foe := _foe_under_point(pos)
	if foe != null:
		move_target = foe.global_position
		_show_mark(move_target)
		Voyage.set_command(2)          # 冲锋：过去之后还会追着打
		for u in _picked_units():
			u.call("set_order", 2)
		_announce("%s: 冲锋!" % Voyage.selection_name())
		Voyage.set_squad_selection(0)  # e17: 下令完选中失效, 时间恢复常速
		return
	if tap:                            # e27f: 单击点地 = 只是挥了一刀, 不动队伍
		return
	move_target = pos
	_show_mark(pos)
	for u in _picked_units():
		u.call("set_order", 0, pos + MOVE_SPREAD[u.index % MOVE_SPREAD.size()], Vector2.ZERO)
	Voyage.set_command(0)
	_announce("%s: 前进!" % Voyage.selection_name())
	Voyage.set_squad_selection(0)      # e17: 下令完选中失效, 时间恢复常速

# 鼠标点到的敌人（判定用单位脚下的小身子范围，别整棵树那么大）
func _foe_under_point(pos: Vector2) -> Node2D:
	for u in units:
		if not is_instance_valid(u) or u.side != "enemy" or bool(u.get("_dying")):
			continue
		if absf(u.global_position.x - pos.x) <= 10.0 \
				and pos.y >= u.global_position.y - 22.0 and pos.y <= u.global_position.y + 6.0:
			return u
	return null

# 拖拽：沿画的这条线按当前阵型铺开，正面朝线的法线（有敌人就朝敌人那侧）
func _cast_line(from: Vector2, to: Vector2) -> void:
	_clear_preview()
	var picked := _picked_units()
	if picked.is_empty():
		_announce("没人听令 -- 点上面的编队按钮换一个")
		return
	var face := _face_dir_for((to - from).normalized(), picked[0])
	var slots := _formation_slots(from, to, picked.size(), face)
	for k in picked.size():
		if _deploying:
			_deploy_place(picked[k], slots[k], face)   # 布阵：沿线瞬移展开
		else:
			picked[k].call("set_order", 0, slots[k], face)
	move_target = (from + to) * 0.5
	_show_mark(move_target)
	Voyage.set_command(0)
	_announce("%s: %s %d 人!" % [Voyage.selection_name(), FORMATIONS[formation], picked.size()])
	if not _deploying:
		Voyage.set_squad_selection(0)  # e17: 下令完选中失效, 时间恢复常速

# 阵型线垂直于队列方向，正面朝敌人（没敌人就朝下）
func _face_dir_for(line_dir: Vector2, sample: Node2D) -> Vector2:
	var n := line_dir.orthogonal().normalized()
	if n == Vector2.ZERO:
		return Vector2(0, 1)
	var foe := nearest_foe_of(sample, 99999.0)
	if foe == null or not is_instance_valid(foe):
		return Vector2(0, 1)
	var to_foe: Vector2 = foe.global_position - sample.global_position
	return n if n.dot(to_foe) >= 0.0 else -n

# 阵型线预览：一条半透明的线 + 沿线每个队位一个小方块
func _update_formation_preview() -> void:
	_clear_preview()
	_preview = Node2D.new()
	_preview.z_index = 7
	add_child(_preview)
	var col := Voyage.squad_color(Voyage.selection) if Voyage.selection > 0 \
		else Color(0.95, 0.95, 0.9)
	var ln := Line2D.new()
	ln.add_point(_drag_from)
	ln.add_point(_drag_to)
	ln.width = 2.0
	ln.default_color = Color(col.r, col.g, col.b, 0.85)
	_preview.add_child(ln)
	var picked := _picked_units()
	var n := picked.size()
	# 小方块按当前阵型摆（不是死板地均分）—— 松手前就能看出会站成什么样
	var face := Vector2(0, 1)
	if n > 0:
		face = _face_dir_for((_drag_to - _drag_from).normalized(), picked[0])
	var slots := _formation_slots(_drag_from, _drag_to, n, face)
	for k in n:
		var s := Sprite2D.new()
		s.texture = _dot_tex()
		s.modulate = col
		s.position = slots[k]
		_preview.add_child(s)

func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null

func _dot_tex() -> ImageTexture:
	var img := Image.create_empty(5, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.55))
	for y in range(1, 4):
		for x in range(1, 4):
			img.set_pixel(x, y, Color(1, 1, 1, 0.95))
	return ImageTexture.create_from_image(img)

# ---- 把口令发给「这轮被选中」的编队；没选中的保持原口令不动（骑砍同理） ----
func _issue_order(cmd: int) -> void:
	_dragging = false         # 下了口令就收起集结旗预览
	_clear_preview()
	# e41j: 不指挥的时候下口令 = 没人接 —— 连 command 都别改（改了那是「默认口令」，
	# 一选回全体就全体冲锋, 等于偷偷替玩家做了决定）
	if Voyage.selection < 0:
		return
	Voyage.set_command(cmd)
	for u in _picked_units():
		u.call("set_order", cmd)
	# e17: 口令也是令 —— 下完选中失效, 时间恢复常速（口令存在各人身上继续生效）
	Voyage.set_squad_selection(0)
	_hold_deploy_freeze()     # e41g: 布阵阶段照旧冻结, 别被上面那行的常速顶开

# 这一轮听指挥的伙伴（selection = 0 时是全部）
func _picked_units() -> Array:
	var out: Array = []
	for u in units:
		if not is_instance_valid(u) or u.side != "ally" or bool(u.get("_dying")):
			continue
		if Voyage.commands_squad(int(u.squad)):
			out.append(u)
	return out

# 选中的伙伴脚下亮圈（颜色 = 他的编队色）+ 刷新 HUD
func _refresh_selection() -> void:
	for u in units:
		if is_instance_valid(u) and u.side == "ally":
			u.call("set_selected", Voyage.commands_squad(int(u.squad)))
	_foe_count = -1
	_refresh_hud()

# e17: 「指挥中 0.1x」指示跟选中走 —— 下令后 selection 清 0 自动隐掉
func _refresh_slow_label() -> void:
	_slow_label.visible = Voyage.selection > 0

func _count_foes() -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.side == "enemy" and not bool(u.get("_dying")):
			n += 1
	return n

func _refresh_hud() -> void:
	if _count_label == null:
		return
	if _foe_count < 0:
		_foe_count = _count_foes()
	# 三个编队各有几个人（算的是场上还站着的）
	var per := [0, 0, 0]
	var total := 0
	for u in units:
		if not is_instance_valid(u) or u.side != "ally" or bool(u.get("_dying")):
			continue
		total += 1
		per[clampi(int(u.squad), 1, 3) - 1] += 1
	# e41j: selection = -1 是「不指挥」——人数报 0, 别去 per[-2] 取下标（越界会报错）
	var picked: int = total if Voyage.selection == 0 \
		else (0 if Voyage.selection < 0 else per[Voyage.selection - 1])
	if _squad_label != null:
		_squad_label.text = "当前指挥: %s   (%d 人)" % [Voyage.selection_name(), picked]
		_squad_label.add_theme_color_override("font_color",
			Voyage.squad_color(Voyage.selection) if Voyage.selection > 0
			else Color(1, 0.95, 0.85))
	_count_label.text = "我方 %d人 (%s %d / %s %d / %s %d)   敌方 %d人" % [
		total, Voyage.squad_name(1), per[0], Voyage.squad_name(2), per[1],
		Voyage.squad_name(3), per[2], _foe_count]
	_update_tally(total, _foe_count)     # 顶部兵力对比条跟着人走
	_sync_cmd_bar()

# 集结点插面小红旗，到位没有一眼看得见
func _show_mark(pos: Vector2) -> void:
	if _mark == null:
		_mark = Sprite2D.new()
		_mark.texture = _mark_tex()
		_mark.z_index = 6
		add_child(_mark)
	_mark.position = pos
	_mark.visible = true
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_mark, "scale", Vector2(1.0, 1.18), 0.5)
	tw.tween_property(_mark, "scale", Vector2(1.0, 1.0), 0.5)

func _mark_tex() -> ImageTexture:
	var w := 14
	var h := 22
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		img.set_pixel(3, y, Color(0.35, 0.24, 0.14))          # 旗杆
	for y in range(2, 10):
		var ww := int(9.0 - float(y - 2) * 0.55)              # 三角红旗
		for x in range(4, 4 + ww):
			img.set_pixel(x, y, Color(0.86, 0.24, 0.20))
		img.set_pixel(4 + ww - 1, y, Color(0.60, 0.13, 0.11))
	return ImageTexture.create_from_image(img)

# ---------------- 主循环 ----------------
func _physics_process(delta: float) -> void:
	if _cam != null:              # e15h: 屏幕震动衰减（0.22 秒线性归零）
		if _shake_t > 0.0:
			_shake_t -= delta
			_cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
				* _shake_amp * maxf(_shake_t, 0.0) / 0.22
		elif _cam.offset != Vector2.ZERO:
			_cam.offset = Vector2.ZERO
	_tick_arrows(delta)
	# 敌人计数 + 胜负判定（结算中只走一次）
	if not _over:
		var foes := _count_foes()
		if foes != _foe_count:
			_foe_count = foes
			_refresh_hud()
		if foes == 0:
			_over = true
			# 政策卡「艨艟」：出海打赢多拿五成金币（经验不吃这张卡）
			# 婚恋 perk（海莉）: 航海收益 +20%
			var coin := int(round(float(_coin_gain) * Research.battle_coin_mult() * Marriage.perk_mult("voyage")))
			if is_siege:
				# 攻城打赢：守军清零 + 好感重创 + 协议撕毁，战利品按城里的库房算
				coin += Nations.on_siege_victory(String(party["siege"]))
			# 声望与雇佣兵/封臣加成（e13g）: 土匪 2 / 国家队 3 / 攻城 5;
			# 签着契约时打土匪金+50%声望+1, 打宗主国的敌人金翻倍声望+2。
			var ptype13 := String(party.get("type", ""))
			var prest := Nations.PRESTIGE_SIEGE if is_siege \
				else (Nations.PRESTIGE_PATROL if ptype13 == "巡逻" else Nations.PRESTIGE_BANDIT)
			if Nations.contract != "":
				var foe_nid := String(party.get("nation", ""))
				var is_bandit := ptype13 == "山贼" or ptype13 == "海寇" \
					or ptype13 == "哥布林" or ptype13 == "魔物"   # e49: 蛮族/魔物也算土匪
				var is_foe_of_liege := foe_nid != "" and foe_nid != Nations.liege \
					and (Nations.at_war_with(foe_nid) or Nations.favor_of(foe_nid) < 20)
				if is_bandit:
					coin = int(round(float(coin) * 1.5))
					prest += 1
				elif is_foe_of_liege:
					coin *= 2
					prest += 2
			Legion.gain_exp(_exp_gain)
			Nations.add_prestige(prest)
			Wallet.add_money(coin)
			# 里程碑「出海首胜」：海寇/巡逻的海上遭遇战打赢算数
			if ptype13 == "海寇" or ptype13 == "巡逻":
				Quests.note_navy_win()
				Quests.complete("navy_first")   # e32: 第一场海战胜利
			_last_coin = coin             # e25: 战果存给结算页展示
			_last_prest = prest
			if is_siege:
				_announce("城破!  战利品 +%d 金  声望 +%d" % [coin, prest], 2.6)
			else:
				_announce("胜 利!  +%d 经验  +%d 金币  声望 +%d" % [_exp_gain, coin, prest], 2.6)
			_show_settlement("victory")
		elif Legion.player_hp <= 0:
			_over = true
			_announce("你倒下了...")
			_show_settlement("defeat")

func _tick_arrows(delta: float) -> void:
	var dead: Array = []
	for a in arrows:
		if not is_instance_valid(a):
			dead.append(a)
			continue
		# 箭撞人：跟「被打的一方」逐个比距离。
		# e15h: 箭速 800 后一帧能蹿 13~26px（30fps 录制更是 26），只查圆心点会穿人
		# —— 改成沿 prev->position 这一小段扫掠判定，帧率再低也漏不掉。
		for u in units:
			if not is_instance_valid(u) or bool(u.get("_dying")):
				continue
			if u.side == a.from_side:
				continue
			var upos: Vector2 = u.global_position + Vector2(0, -10)
			if _seg_dist(a.get("prev"), a.position, upos) < 8.0:
				# 兵种相克：箭的伤害按「射手的兵种 x 挨箭人的兵种」折算
				var dmg := int(round(float(a.dmg) * TroopScript.counter_mult(
					String(a.get("from_kind")), String(u.kind))))
				u.call("take_damage", dmg)
				dead.append(a)
				break
	for a in dead:
		if is_instance_valid(a):
			a.queue_free()
		arrows.erase(a)

# 点到线段的最短距离（箭的扫掠碰撞用）
func _seg_dist(from: Vector2, to: Vector2, p: Vector2) -> float:
	var ab := to - from
	var t := 0.0
	if ab.length_squared() > 0.0001:
		t = clampf((p - from).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (from + ab * t).distance_to(p)

# 箭从 troop._shoot_if_ready 里请求（from_kind = 射手兵种, 命中时算相克）
func spawn_arrow(pos: Vector2, dir: Vector2, dmg: int, from_side: String,
		from_kind := "") -> void:
	var a: Node2D = ArrowScript.new()
	a.position = pos
	a.set("prev", pos)            # e15h: 首帧别拿 (0,0) 当线段起点，会误伤出生点附近的人
	a.dir = dir
	a.dmg = dmg
	a.from_side = from_side
	a.set("from_kind", from_kind)
	a.rotation = dir.angle()
	add_child(a)
	arrows.append(a)

func _on_enemy_died(u: Node2D) -> void:
	# 经验/金币已在开局按人数算好，胜利时一次性发；这里只算士气与战况
	_foe_lost += 1
	if is_instance_valid(u):
		_morale_shock(u.global_position, "enemy")
	_refresh_hud()
	_check_rout_announce()

func _on_ally_died(u: Node2D) -> void:
	_ally_lost += 1
	if is_instance_valid(u):
		_morale_shock(u.global_position, "ally")
	_refresh_hud()      # 少了一个能指挥的人，人数标签跟着变
	_check_rout_announce()

# ---------------- 士气折损 / 溃逃播报（骑砍式）----------------
# 有人倒下 -> 倒地处周围的同营人掉士气。折损量随「这边已经折了几个人」加码：
# 顺风仗越打越稳, 逆风仗一崩就崩一片（士气压到 0 的人当场溃逃, 见 troop._rout）。
# 一场仗于是常常不是「打到最后一个」, 而是打崩一边 —— 这是骑砍最像的一块。
func _morale_shock(at: Vector2, dead_side: String) -> void:
	var lost: int = _ally_lost if dead_side == "ally" else _foe_lost
	var amount := MORALE_SHOCK + MORALE_SHOCK_STEP * float(lost)
	for u in units:
		if not is_instance_valid(u) or bool(u.get("_dying")) or u.side != dead_side:
			continue
		if u.global_position.distance_to(at) > TroopScript.MORALE_SHOCK_RADIUS:
			continue
		u.call("shock_morale", amount)

# 一边过半的人跑了 = 那一边崩了（每边只喊一次, 免得刷屏）
func _check_rout_announce() -> void:
	for s in ["ally", "enemy"]:
		if bool(_rout_warned[s]):
			continue
		var ran := 0
		var live := 0
		for u in units:
			if not is_instance_valid(u) or u.side != s:
				continue
			if bool(u.get("routing")):
				ran += 1
			elif not bool(u.get("_dying")):
				live += 1
		if ran > 0 and ran * 2 >= live + ran:
			_rout_warned[s] = true
			if s == "enemy":
				_announce("敌军崩溃! 开始溃逃", 2.6)
			else:
				_announce("我军溃散! 各自逃命", 2.6)

# ---------------- 给 troop 的查询 ----------------
func is_blocked_at(pos: Vector2) -> bool:
	var c := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
	if c.x < 1 or c.y < 1 or c.x >= W - 1 or c.y >= H - 1:
		return true
	return blocked.has(c)

# 站进浅水格了吗（troop 据此减速 + 半身入水贴片；h-m 河谷涉水）
func is_shallow_at(pos: Vector2) -> bool:
	return shallow.has(Vector2i(floori(pos.x / CELL), floori(pos.y / CELL)))

func get_hero() -> Node2D:
	# e27j: 主角阵亡淡出 0.5 秒后 queue_free，引用还挂在 hero 上——
	#   直接返回会让 troop._hero() 的 cast 每帧炸「Trying to cast a freed object」
	return hero if is_instance_valid(hero) else null

func nearest_foe_of(unit: Node2D, max_d: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_d * max_d
	for u in units:
		if not is_instance_valid(u) or u == unit or bool(u.get("_dying")):
			continue
		var unit_is_enemy: bool = (unit.side == "enemy")
		var u_is_enemy: bool = (u.side == "enemy")
		var hostile: bool = unit_is_enemy != u_is_enemy
		if not hostile:
			continue
		var d: float = unit.global_position.distance_squared_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# e41i: 离 unit 最近的「敌弓手」（骑兵绕后切后排用）。场上没有弓手就返回 null。
func nearest_archer_of(unit: Node2D, max_d: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_d * max_d
	for u in units:
		if not is_instance_valid(u) or u == unit or bool(u.get("_dying")):
			continue
		if (unit.side == "enemy") == (u.side == "enemy"):
			continue
		if not (u.has_method("is_archer") and bool(u.call("is_archer"))):
			continue
		var d: float = unit.global_position.distance_squared_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	return best

# ---------------- 结算页（e25）----------------
# 胜负分出不再直接 _finish 自动流转：先弹一张结算页 —— 主角与上阵伙伴的剩余血量
# （条 + 数字 + 百分比）、这场收获的金币/声望/经验，BGM 切到 settle 曲池。
# 点「继续」（按钮 / 面板任意处 / 任意按键）才走 _finish -> Voyage.end_battle
# 回海图或回岛（那两处已经把 BGM 交还给 ocean/island，无需额外收尾）。
func _show_settlement(result: String) -> void:
	_settle_result = result
	_settle_armed = false
	_settle_hud = null
	Voyage.set_battle_slow(false)     # 揭幕计时走真实秒，别被 0.1x 拖成九秒
	Audio.set_scene_bgm("settle")
	var hud := CanvasLayer.new()
	hud.name = "SettleHUD"
	_settle_hud = hud
	add_child(hud)
	hud.visible = false               # 先藏住：公告（胜利!/你倒下了）先亮相 0.9 秒
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 挡住地图点击，别让挥剑/拖线穿过去
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(dim)
	# 面板高度随上阵人数长（标题 + 每人一行 + 收获 + 继续）
	var rows := 1 + _deployed_ids.size()
	var pw := 372.0
	var ph := 96.0 + float(rows) * 24.0
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.94)
	sb.border_color = Color(0.85, 0.72, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-pw / 2.0, -ph / 2.0)
	panel.size = Vector2(pw, ph)
	hud.add_child(panel)
	var win := result == "victory"
	var title := Label.new()
	title.text = "胜 利!" if win else "败 北"
	title.add_theme_font_override("font", FONT_PIX)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color",
		Color(1, 0.85, 0.35) if win else Color(0.8, 0.45, 0.4))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 14)
	title.size = Vector2(pw, 24)
	panel.add_child(title)
	var y := 46.0
	_settle_row(panel, "主角", Legion.player_hp, Legion.player_max_hp(), y)
	y += 24.0
	for idx in _deployed_ids:
		var s: Dictionary = Slaves.slave_at(int(idx))
		if s.is_empty():
			continue
		_settle_row(panel, "%s(%s)" % [String(s.get("name", "?")), String(s.get("troop", "刀客"))],
			int(s.get("hp", 0)), int(s.get("max_hp", 30)), y)
		y += 24.0
	var gains := Label.new()
	gains.text = "金币 +%d   声望 +%d   经验 +%d" % (
		[_last_coin, _last_prest, _exp_gain] if win else [0, 0, 0])
	gains.add_theme_font_override("font", FONT_PIX)
	gains.add_theme_font_size_override("font_size", 14)
	gains.add_theme_color_override("font_color",
		Color(1, 0.88, 0.5) if win else Color(0.75, 0.72, 0.66))
	gains.add_theme_constant_override("outline_size", 4)
	gains.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	gains.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gains.position = Vector2(0, y)
	gains.size = Vector2(pw, 20)
	panel.add_child(gains)
	var cont := Button.new()
	cont.text = "继续"
	cont.add_theme_font_override("font", FONT_PIX)
	cont.add_theme_font_size_override("font_size", 13)
	cont.focus_mode = Control.FOCUS_NONE
	cont.position = Vector2(pw / 2.0 - 60, ph - 32)
	cont.size = Vector2(120, 26)
	cont.pressed.connect(_close_settlement)
	panel.add_child(cont)
	# 面板/暗幕上任意一点 = 继续（揭幕后才生效；按钮自己也会走同一个入口）
	for eater: Control in [panel, dim]:
		eater.gui_input.connect(func(ev: InputEvent) -> void:
			var me := ev as InputEventMouseButton
			if me != null and me.pressed and _settle_armed:
				_close_settlement())
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func() -> void:
		if _settle_hud != null:
			_settle_hud.visible = true
			_settle_armed = true)

# 结算页一行：名字 + 血条（按比例变色）+ 数字与百分比
func _settle_row(parent: Control, disp: String, hp: int, mhp: int, y: float) -> void:
	var nm := Label.new()
	nm.text = disp
	nm.add_theme_font_override("font", FONT_PIX)
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color(0.92, 0.88, 0.8))
	nm.position = Vector2(20, y)
	nm.size = Vector2(118, 16)
	nm.clip_text = true
	parent.add_child(nm)
	var mhp1 := maxi(1, mhp)
	var ratio := clampf(float(maxi(hp, 0)) / float(mhp1), 0.0, 1.0)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.position = Vector2(142, y + 3)
	bar.size = Vector2(120, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	var fill := ColorRect.new()
	fill.color = Color(0.36, 0.78, 0.31) if ratio >= 0.5 \
		else (Color(0.9, 0.75, 0.2) if ratio >= 0.25 else Color(0.82, 0.25, 0.2))
	fill.size = Vector2(120.0 * ratio, 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var txt := Label.new()
	txt.text = "%d/%d  %d%%" % [maxi(hp, 0), mhp1, int(round(ratio * 100.0))]
	txt.add_theme_font_override("font", FONT_PIX)
	txt.add_theme_font_size_override("font_size", 12)
	txt.add_theme_color_override("font_color", Color(0.85, 0.85, 0.75))
	txt.position = Vector2(268, y)
	txt.size = Vector2(92, 16)
	parent.add_child(txt)

func _close_settlement() -> void:
	if _settle_hud == null:
		return
	_settle_hud.queue_free()
	_settle_hud = null
	_finish(_settle_result, 0.1)

# ---------------- 收尾 ----------------
# 结算动画走正常速度（先把慢放关掉，不然 2 秒要等 4 秒）
func _finish(result: String, delay: float) -> void:
	_dragging = false
	_clear_preview()
	_deploying = false                 # 布阵中撤退/收尾：布阵层收掉，下一行恢复时间
	if _deploy_hud != null:
		_deploy_hud.queue_free()
		_deploy_hud = null
	Voyage.set_battle_slow(false)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): Voyage.end_battle(result))

# 兜底：不管怎么离开战场，时间都不能留在一半速度
func _exit_tree() -> void:
	Voyage.set_battle_slow(false)
