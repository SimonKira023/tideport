extends Node2D

# —— 地块素材 ——
# Tileset Grass Spring.png 里那块纯色草地（整格同色，可以无缝平铺）
const YARD_GRASS_SRC := 0
const YARD_GRASS_TILE := Vector2i(9, 18)

# 地图范围，单位 = 格子，坐标以农田网格原点为基准。
# 要比一屏（1152x648，zoom 4 → 只看得见约 18x10 格）大很多 ——
# 不然走到边上就会看见草地/海水外面是空的。
# 外圈留得宽，岛外那圈「汪洋」才看得出是海，而不是贴边的一条蓝边。
const YARD_FROM := Vector2i(-46, -22)
const YARD_TO := Vector2i(62, 56)

# —— 主地图布局：海中的岛 + 岛中一条河 ——
# 设计思路：整块地图就是一座孤岛，岛外**全是汪洋**（不再留对岸草地）；
# 岛中间再纵切一条南北走向的浅河，把岛分成东西两块，靠两座木桥连通。
# ISLAND_* 是「核心陆地」（一定是草地，农舍/农田/池塘/商人都在这）；
# 核心往外是海岸带 —— 双层噪声决定这里是草地还是水，所以岛缘弯弯曲曲；
# 再往外没有任何强制，一律是海。
const ISLAND_FROM := Vector2i(-26, -4)
const ISLAND_TO := Vector2i(42, 38)
const COAST_MID := 4.0        # 海岸线平均离核心多远（格）—— 比 4.5 小一点，岛略瘦、海略大
const COAST_AMP := 2.7        # 噪声振幅：越大海岸线越曲折（湾/岬角越大）
const COAST_FREQ := 0.050     # 低频：决定大的凹凸（每隔 ~20 格一个湾）
const COAST_DETAIL_FREQ := 0.20   # 高频：再叠一层小锯齿，免得弧线太圆滑
const COAST_DETAIL_AMP := 0.55
const COAST_SEED := 20260914

# —— 岛中的浅河 ——
# 南北走向，从岛的北岸一直流到南岸（两头都接海），把岛切成东西两块。
# 河心用正弦缓慢左右摆，不是一根直棍，看起来才像天然河道。
# 河不宽（半宽 2 → 约 5 格）+ 离岸近 → 在「按到岸距离分深浅」的水面图集里
# 天然落在最浅的两档，正好就是「浅河」的样子。
const RIVER_CX := 31.0            # 河心基准 x（格）
const RIVER_WOBBLE := 1.8         # 河心左右摆动幅度（格）
const RIVER_WOBBLE_FREQ := 0.115  # 摆动频率：每 ~55 格一个来回
const RIVER_WOBBLE_PHASE := 1.7   # 相位，让河不至于正好从某处笔直穿过
const RIVER_HALF := 2             # 河半宽（格）→ 河宽约 2*2+1 = 5 格

# —— 木桥 ——
# 桥横跨河面。桥的行号固定，左右范围跟着「那一行的河心」自动算，
# 所以河摆动也不影响桥能对上河（见 _bridge_x0 / _bridge_x1）。
const BRIDGE_ROWS := [2, 26]      # 两座桥所在的格子行
const BRIDGE_HALF := 3            # 从河心向两侧各跨几格：河半宽 2 + 两侧各留 1 格桥头
const BRIDGE_APPROACH := 2        # 桥头引道再往外强制这么宽是陆地（兜底，保证上得了桥）

# e52: 码头栈桥贴图盖住的水格范围（从码头根格往东 4 格、往南 2 格）。
# ❗跟 scene/dock.gd 里 _spr.position = (24,4) + 64x48 的贴图对齐：
#   桥面那排木板正好落在 根格 + (0..3, 0..1)。站上去算走路（见 is_deck_cell）。
const DOCK_DECK_W := 4
const DOCK_DECK_H := 2

# —— e52: 四季地表 ——
# 资源包里春夏秋冬四张草地/水边图集**布局完全一致**（草地都是 384x640，
# 水边春夏秋都是 768x256），所以换季只要把 TileSetAtlasSource 的 texture 换一张，
# 所有格子坐标 / 色斑变体 / 动画全都不用动。
# ❗冬季那张水边图集（Tileset Grass Water Winter.png）是 400x384 的另一套布局，
#   换来会错位，所以冬季的水边沿用春版 —— 水边只在下水/上岸那条窄岸线上，看不出差别。
const SEASON_GRASS_TEX := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Spring.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Summer.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Fall.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Winter.png",
]
const SEASON_GRASS_WATER_TEX := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Water Spring.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Water Summer.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Water Fall.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Water Spring.png",
]
# TilledGroundTileMapLayer 的图集里, 草地/水边各占一个 source（跟场景里手放的格子对齐）
const GROUND_GRASS_SRC := 3
const GROUND_WATER_SRC := 6

# —— 草地上的花草点缀 ——
# 全部取自 ALL props seasons.png（22x12 格），都是「透明底、压上去看不出接缝」的单格贴图。
# 注意：Tileset Grass Spring.png 的第 4~5 行**不是**草丛，那是草↔土/小路的拼接边缘块，别拿来当点缀。
const PROP_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const DECOR_SRC := 0
# 草丛 / 高草（row 0~1 = 春 + 夏两套）
const DECOR_TUFT := [
	Vector2i(1, 0), Vector2i(5, 0), Vector2i(1, 1), Vector2i(5, 1),
	Vector2i(10, 0), Vector2i(10, 1),
]
# 小花：白雏菊 / 粉花 / 混合小花 / 白红小花 / 黄心花 / 红玫瑰 / 橙花 / 白花 / 蓝花
const DECOR_FLOWER := [
	Vector2i(11, 0), Vector2i(12, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(8, 1), Vector2i(12, 1),
	Vector2i(11, 3), Vector2i(12, 3),
]
# 蘑菇（红 / 绿 / 棕），点缀得比花更稀疏
const DECOR_MUSHROOM := [
	Vector2i(13, 0), Vector2i(13, 1), Vector2i(11, 2),
]
# 撒出来的东西里各种类的占比（相对值）
const DECOR_MUSHROOM_SHARE := 0.04
const DECOR_FLOWER_SHARE := 0.30      # 累计：0~0.04 蘑菇，0.04~0.30 花，其余都是草丛
# 疏密：用一层低频噪声决定「这片密、那片空」，再乘上这个上限。
# 均匀按概率撒会撒成一张「花毯」，有噪声才有成片的花丛和留白。
const DECOR_MAX_DENSITY := 0.42
const DECOR_NOISE_FREQ := 0.085       # 0.085 ≈ 每 12 格一个起伏
const DECOR_FIELD_FREQ := 0.045       # 花圃：约每 22 格一片花海
const DECOR_FIELD_DENSITY := 0.58     # 花圃核心的密度上限（比野地 0.42 更密）
const DECOR_SEED := 20260913    # 固定种子：花草每次开局都长在同一个地方，方便对比改动
const CRITTER_SEED := 20260922  # 小动物撒点抽签种子（乌鸦落点），同样固定

# —— 水面 ——
# 原来直接拿素材里的纯色水块铺，一整片死蓝，看着像塑料；而且岸线判定写错了
# （拿「草地层」判断哪边是岸，可草地铺满了整张图、水下也有），
# 结果每一格水都被当成四面环岸、描了一圈白边 —— 就是那股「一格一格不连贯」的味儿。
#
# 现在水面是程序化生成的：5 档深浅 × 3 种波纹。
#   · 深浅按「这格水离岸多远」分档：贴岸浅、远处深，水面就有了层次
#   · 每格边框 2px 固定为该档基色，波纹只画在内部 —— 相邻格拼接不会有缝
#   · 分档边界加一点抖动，避免深浅之间出现笔直的色块线
const WATER_SRC := 0
const WATER_DEPTHS := [
	Color(0.56, 0.87, 0.93),   # 离岸 1 格：最浅
	Color(0.43, 0.81, 0.91),
	Color(0.30, 0.74, 0.89),
	Color(0.18, 0.66, 0.86),
	Color(0.04, 0.50, 0.77),   # 离岸 5 格以上：最深
]
const WATER_VARIANTS := 3     # 每档几种波纹（随机挑一种，水面才不呆板）
const WATER_RIPPLE := 0.035   # 波纹明暗幅度（很轻微，不要抢戏）
const WATER_EDGE := 2         # 边框保持纯基色的像素数，保证无缝
const WATER_MAX_DIST := 5     # 离岸这么远就算最深
const WATER_ANIM_PERIOD := 0.55   # e33b 波纹轮换间隔：每 0.55 秒换一桶（3 桶轮一圈）

# —— 岸：水陆之间的过渡 ——
# 一层不够。真正的岸是「草地 -> 沙滩 -> 浅水 -> 深水」这么一段渐变，
# 所以分两层画：
#   BEACH_BAND  = 画在**陆地**格上、朝水那侧的沙色（草地↔水的过渡地带）
#   SHORE_BANDS = 画在**水面**格上、朝岸那侧的浅滩（由浅到深）
# 两层贴在一起，接缝就藏进渐变了。
# 注意浅滩别用纯白 —— 纯白描出来像「发光描边」，要用偏水色的浅蓝。
const SHORE_SRC := 0
const SHORE_BANDS := [
	Color(0.80, 0.94, 0.97, 0.70),    # 贴岸：很浅的水
	Color(0.55, 0.86, 0.94, 0.50),
	Color(0.32, 0.77, 0.91, 0.32),
	Color(0.14, 0.64, 0.86, 0.16),    # 最外侧：接回深水
]
const BEACH_SRC := 0
const BEACH_W := 4
const BEACH_BAND := [
	Color(0.86, 0.77, 0.50, 1.00),    # 贴水：湿沙（最实的一条）
	Color(0.82, 0.74, 0.52, 0.85),
	Color(0.77, 0.72, 0.54, 0.55),
	Color(0.71, 0.75, 0.59, 0.22),    # 最里：淡回草地
]
# 沙滩底色与杂点（左岛西北岸那片沙滩用，比湿沙带干一点、浅一点）
const SAND_BASE := Color(0.85, 0.77, 0.56, 1.0)
const SAND_DOT := Color(0.72, 0.66, 0.47, 1.0)
const SAND_LITE := Color(0.91, 0.85, 0.65, 1.0)
# 朝草地那侧的淡出带（沙色 -> 透明，让沙滩和草地的交界不像刀切的）
const SAND_FADE := [
	Color(0.85, 0.77, 0.56, 1.00),
	Color(0.82, 0.75, 0.55, 0.55),
	Color(0.79, 0.74, 0.55, 0.22),
]

# —— 左岛西北岸的沙滩 ——
# 河西半块的西北角划一片沙滩：主角开局从这儿「复苏」（海难上岸）。
# 沙滩不可耕田（is_tillable 排除），也不长树/石（_tree/_rock_spot_ok 排除）。
# 区域里的水格不受影响 —— 只圈陆地格。
# 右下（东南）边界不做矩形直角：贴东/南内边的格用海岸同款噪声往里啃
# 0..SAND_BITE 格，右下角再叠一段四分之一圆弧（半径 SAND_CORNER_R），
# 让沙地边缘像海岸一样弯着收进草地。出生格离东边 3 格/南边 2 格，
# 啃咬最深 SAND_BITE=2 格，天然不会被啃掉。
const SAND_FROM := Vector2i(-32, -10)
const SAND_TO := Vector2i(-21, 2)
const SAND_BITE := 2          # 东/南内边最多往里啃几格（噪声决定 0..SAND_BITE）
const SAND_CORNER_R := 5.5    # 右下角圆弧半径（格）：弧外的角格剔除
const SPAWN_CELL := Vector2i(-24, 0)   # 开局出生格（核心陆地，保证是沙地）

# —— 耕地四周的过渡地形（田埂）——
# 跟岸线一个思路：在紧挨耕地的草地格上，朝耕地那一侧画一条「土色渐变」。
# 颜色贴近 soil_layer 的土色（FILL=190,109,71），从土色淡出到透明，看起来像踩出来的土路。
const BORDER_W := 3
const BORDER_BAND := [
	Color(0.62, 0.36, 0.27, 0.95),   # 贴耕地：最实的土色
	Color(0.70, 0.45, 0.34, 0.60),
	Color(0.76, 0.53, 0.40, 0.28),   # 最外：几乎融进草里
]

const FONT_PIX := preload("res://resources/font/IPix.ttf")

# —— 图层层级（z_index）——
# 根节点开了 y_sort_enabled 之后，**同一层**（z_index 相同）的节点会按「节点原点的 y」
# 重新排序 —— 这就是「角色站在物体前面就盖住它、站在后面就被它盖住」。
# 但地形必须永远压在角色/房子/箱子下面，所以给地形一个明确的负 z_index：
# z_index 不一样就不会被 y_sort 打乱，永远是 z 小的先画。
# ❗顺序必须跟原来的绘制顺序一致：草 → 花草 → 田埂 → 沙滩 → 水面 → 浅滩 → 桥 → 耕地 → 作物
# ❗并且实体的原点必须落在「脚下」（视觉底边中点），否则排序点会偏一截 ——
#   水井/哥布林/房屋的贴图都往上挪了，让节点原点落在底部中心。
const Z_GRASS := -10
const Z_DECOR := -9
const Z_BORDER := -8
const Z_BEACH := -7
const Z_WATER := -6
const Z_SHORE := -5
const Z_BRIDGE := -4
const Z_SOIL := -3
const Z_FLOOR := -2.5        # 介于 soil 和 crop 之间：地板盖住耕地，但在作物下方
const Z_CROP := -2
# e29j: Z_RAIL 已废 —— 上下护栏改 z=0 参与嵌套 y_sort（见 _build_bridges），
# 「玩家在前盖住栏杆 / 在后从栏杆孔里透出」交给 y_sort，防穿过交给细线碰撞。

# —— 树木 ——
# 树用「果树生长图」的 32x48 帧：幼苗 -> 小树 -> 成树 -> 树桩（见 scene/tree_node.gd）。
# 撒树避开建筑/门口/出生点/室内那块地，也不贴着水岸（树冠 32 宽，会悬到水里）。
const TREE_NOISE_FREQ := 0.09     # 低频噪声决定树林成片/留空
const TREE_DENSITY := 0.10        # 成片区的撒树概率
const TREE_MAX := 120             # 全岛上限，防止噪声年把整座岛种满
const TREE_SEED := 20260915       # 固定种子：树每次开局长在同一个地方

# 岩石/铁矿露头（镐子可敲碎；矿井是另一处固定建筑，派劳动力每天产出）
const ROCK_MAX := 46              # 全岛岩石上限
const ROCK_DENSITY := 0.05        # 陆地格撒石概率
const ROCK_IRON_RATIO := 0.3      # 撒出的石头里铁矿露头占三成
const ROCK_SEED := 20260916       # 固定种子：岩石每次开局长在同一个地方

# 每夜自然补植（用户要求树和石头"更新较快"）：清晨随机挑空地长回一点，但避开耕田与建筑附近
const RESPAWN_TREES_PER_DAY := 2  # 每夜补种的树苗/小树数
const RESPAWN_ROCKS_PER_DAY := 2  # 每夜长回的岩石数
const RESPAWN_TRIES := 400        # 每夜随机找空位的尝试上限
# 矿井素材：Door Mine.png 是两帧 32x32 的矿门（取左帧放大）；点缀用矿石地砖 16x16 网格
const MINE_DOOR_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Mine and Dungeon/Mine/Door Mine.png"
const MINE_ORE_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Mine and Dungeon/stone with minerals.png"
var mine_cell := Vector2i(9999, 9999)   # 矿井所在格（_ready 里最先定，树/岩石都给它让位）
var rock_nodes := {}              # cell -> rock_node（跟 tree_nodes 一个套路）
var station_nodes := {}           # cell -> station_node（玩家摆的工作台/熔炉，跟 rock_nodes 一个套路）
var _site_node: Node2D = null     # 建筑工地脚手架（Structures.site 有内容时挂着）
# 建造模式（背包「建造」页选好建筑进入）：半透明 ghost 跟着鼠标走，左键放下 / 右键或 Esc 取消
var build_kind := ""              # 正在摆放的建筑种类（"" = 没在建造）
var _ghost: Node2D = null         # ghost 预览节点
var _ghost_ok := false            # 鼠标当前位置能不能放
# e44 建筑模式（搬已建好的建筑，不花钱不扣料）：先左键拾起一座，再左键放到新位置
var _move_mode := false           # 在建筑模式里
var _move_hover := Vector2i(9999, 9999)   # 鼠标底下高亮着的那座建筑
var _move_from := Vector2i(9999, 9999)    # 拾起前的位置（右键放回原处）
var _move_payload := {}           # 拾起后暂存的设施数据（整份搬走，含等级/鸡/蜜/外形）
var _move_ghost: Node2D = null    # 拾起后跟着鼠标走的预览
var _move_ok := false             # 鼠标当前位置能不能落下

@onready var player = $Player
@onready var grid_layer: TileMapLayer = $GrassTileMapLayer
@onready var water_layer: TileMapLayer = $WaterTileMapLayer
@onready var authored_field: TileMapLayer = $TilledGroundTileMapLayer
@onready var hud: CanvasLayer = $HUD

var _sleeping := false
var _fade_rect: ColorRect
var _fade_label: Label
var _post_mat: ShaderMaterial = null   # e31 全屏后处理材质（每帧喂 night = 昼夜光感）
var _post_night := 0.0                 # 平滑过的夜度: 0=白天 1=深夜
var _post_wet := 0.0                   # 平滑过的湿地反光度（雨天渐入/雨停慢慢干）
var shore_layer: TileMapLayer      # 池塘浅滩色带（水面之上、草地之下）
var decor_layer: TileMapLayer      # 草地上的花草点缀（草地之上、耕地之下）
var border_layer: TileMapLayer     # 耕地四周的过渡地形（田埂/土路，草地之上、耕地之下）
var backpack_panel: Control = null # 背包面板（按 B 开关）
var shop_panel: Control = null     # 商人交易面板（走近商人按 F 打开）
var coop_panel: Control = null     # 鸡舍管理面板（对鸡舍按 F 打开, e30p）
var chest_panel: Control = null    # e45 储物箱面板（对储物箱按 F 打开）
var bin_panel: Control = null      # 售卖箱面板（走近箱子按 F 打开, 左背包/右箱子）
var dialogue_panel: Control = null # 伙伴对话弹窗（走近伙伴按 F 打开）
var story_dialogue_panel: Control = null # 剧情对话框（下小半屏+头像，剧情/进店前置用）
var quest_log_panel: Control = null   # 任务栏（开背包时一并显示）
var settlement_panel: Control = null  # 夜晚结算画面（睡觉时弹出来）
var assign_panel: Control = null      # 夜晚给伙伴派活的面板（结算之后）
var cheat_panel: Control = null       # 作弊面板（按 P 唤醒，加钱/加资源）
var campfire: Node2D = null           # 傍晚出现的篝火（招伙伴用）
var campfire_panel: Control = null    # 篝火招募面板（走近篝火按 F 打开）
var dock: Node2D = null               # 东岸外海的废弃码头（scene/dock.gd）
var dock_panel: Control = null        # 码头面板：修码头 / 造船 / 出海
var _sailing := false                 # 出海离开动画进行中（挡住 F 再开面板 / 二次出海）
var _dock_deck := {}                  # e52: 码头栈桥盖住的格子（见 _cache_dock_deck）

# 出海离开动画：镜头钉在港口，全员搭船往东驶出画面（码头东边是海）
# e37c: 不再写死「开 640px」—— 改成按玩家当前 zoom 现算（见 _sail_away）。
const SAIL_TIME := 3.2                # 船队驶出画面的秒数（留够看人看船的时间）
const SLAVE_SCRIPT := preload("res://scene/slave_npc.gd")   # 伙伴模型/染色真相源
var shipping_bin: Node = null         # 物品售卖箱（scene/shipping_bin.tscn）
var slave_nodes: Array = []           # 白天的伙伴（scene/slave_npc.gd 动态生成）

func _ready() -> void:
	# 0) 让别的脚本（玩家/商店等）能通过 group 找到这张地图
	add_to_group("game")
	# 0.5) 建筑模式是「static 闸门 + 场景状态」两半，重进场景时把闸门复位 ——
	#      万一上一局是开着建筑模式直接退出去的，提示框不该一直点不动。
	preload("res://scene/key_hint.gd").click_locked = false

	# 1) 确定农田网格的原点（用地面瓦片图层的实际位置，避免硬编码偏移）
	Farm.grid_origin = grid_layer.global_position

	# 2) 先把池塘对齐到草地网格（不然田中间会露黑点）
	_align_pond()

	# 3) 铺主地图：不规则岛屿（核心陆地 + 噪声海岸）+ 环岛溪流 + 池塘，并重画水面
	_build_terrain()

	# 3.1) e52: 码头栈桥盖住的水格先记下来 —— 水碰撞（下一步）和游泳判定都要放行那几格
	_cache_dock_deck()

	# 3.2) e52: 四季地表 —— 资源包里春夏秋冬四张草地/水边图集布局一致, 换季只换贴图。
	#      换季时靠 TimeManager.season_changed -> _on_season_changed() 再调一次（那个槽在 _build_fx 里挂的）。
	_apply_season_terrain()

	# 4) 岸 = 陆地侧沙滩 + 水面侧浅滩，两层一起把草地↔水的硬边渐变掉
	_build_beach()
	_build_shore()

	# 4.5) 在溪流上架桥（需要排在岸线层之上）
	_build_bridges()

	# 4.6) 水的碰撞（不能走进水里，但桥面/引道格不算，留出走桥的通道）
	_build_water_collision()

	# 4.65) 岸边白浪（贴陆水格上一条会呼吸、往复推进的浪线 + 泡沫点）
	_build_waves()

	# 4.655) 唯美氛围：全屏后处理滤镜（色彩分级+晕影+天光）+ 漂浮光尘
	_build_fx()

	# 4.66) 开局复苏点：主角从左岛西北岸的沙滩上醒来（存档读回时会被 apply_player_state 覆盖）
	# ❗global_position 是世界坐标，必须配 global_position（= Farm.grid_origin）；
	#   以前错配了局部的 grid_layer.position，少加 game 根节点偏移 (170,149)，
	#   开局直接落在沙滩西北的海里。
	player.global_position = Farm.grid_origin \
		+ Vector2(SPAWN_CELL.x * 16 + 8, SPAWN_CELL.y * 16 + 8)

	# 4.7) 桥两端的护栏格是陆地，水碰撞管不到 —— 单独补一堵墙，
	#      不然玩家能踩着桥头的栏杆走（看着像站在栏杆上）
	# ❗桥头护栏碰撞已移除：以前给「桥身两端的陆地护栏格」补了一堵墙，
	#   结果玩家在桥头明明踩着草地却被挡住（尤其桥被水盖住时更莫名其妙）。
	#   现在水里那两行护栏本来就有水碰撞（踩栏杆过河照样挡），岸上则完全放行 ——
	#   栏杆的遮挡交给前段 sprite 的 y_sort 做，不再靠碰撞体。

	# 5) 接管场景里手画的耕地（已经在 ISLAND 范围内，跳过水面和桥面）
	_restore_field()

	# 5.5) 全岛撒树（要在耕地接管之后：田里不长树）
	#      矿井格要先定下来：树/岩石都拿它当锚点让位（见 _build_trees/_build_rocks）
	mine_cell = _pick_mine_cell()
	_build_trees()

	# 5.6) 全岛撒岩石/铁矿露头（镐子可敲）+ 矿井建筑（派活面板安排伙伴下井）
	_build_rocks()
	_setup_mine()

	# 5.7) 工作台/熔炉显示层（玩家制作后摆放；监听 Structures 信号自动更新）
	_build_stations()

	# 6) 草地上撒花草点缀（必须在 _restore_field 之后：田里不长草）
	_build_decor()

	# 6.1) 草地小动物：乌鸦啄食惊飞、蝴蝶绕花飘（e29e 素材包盘点产出）
	#      必须排在 _build_decor 之后 —— 蝴蝶要拿 decor 层里的花格当锚点
	_build_critters()

	# 7) 耕地四周的过渡地形（田埂/土路，监听 tilled_added/removed 自动更新）
	_build_field_border()

	# 7.4) 木地板显示层（监听 Floor.floor_changed 自动更新）
	_build_floor_layer()

	# 7.5) 把所有图层的 z_index 摆好 —— 配合根节点的 y_sort 做前后遮挡
	_apply_layer_z()

	# 7.6) 外海底垫 + 相机围栏（e16b）: 主岛是「地图矩形内的岛」, 矩形之外
	#      什么都没画, 相机拉远/靠岸时屏幕边缘就是引擎默认的黑底(用户实测)。
	#      垫一整块远洋深蓝色 + 给玩家相机设 limits, 视野出界也是海。
	_build_outer_sea()

	# 8) 背包面板（挂在 HUD 上，按 B 开关）+ 商人交易面板（按 F 打开）
	_setup_backpack()
	_setup_shop()
	_setup_coop_panel()
	_setup_chest_panel()
	_setup_dialogue()
	_setup_story_dialogue()
	_setup_quest_log()
	# 里程碑达成公告：Quests 结算发奖后这里弹屏幕顶部横幅
	Quests.rewarded.connect(func(text: String): _announce(text, 3.0))
	Quests.celebrated.connect(_celebrate)   # e26c 终局目标: 大庆祝横幅, 不锁档
	# e42: 剧情过场期间把玩家钉住 —— 过场是 layer 80 的全屏浮层, 底下不该还能跑
	Cutscenes.started.connect(func() -> void: _set_player_frozen(true))
	Cutscenes.finished.connect(func() -> void: _set_player_frozen(false))
	_setup_clock_ui()
	_setup_sleep_menu()
	_setup_campfire()
	_setup_wedding_badge()

	# 8.5) 物品售卖箱（场景里已经有实例；这里只是拿个引用，方便结算时取货）
	shipping_bin = get_tree().get_first_node_in_group("shipping_bin")
	# 售卖箱的面板得等箱子实例找到再挂（面板点货要用箱子的引用）
	_setup_bin_panel()

	# 8.6) 伙伴（奴隶）：可涂色的派活地图范围 = 核心陆地
	_setup_slaves()

	# 8.7) 废弃码头（出海的唯一入口）+ 它的面板
	#      ❗要在 _build_terrain() 之后：码头得等地形定下来才知道盖在哪格
	_setup_dock()
	_setup_dock_panel()

	# 9) 睡觉用的黑幕 + 夜晚结算画面
	_build_sleep_overlay()
	TimeManager.day_ended.connect(_on_day_ended)

	# 10) 时间开始流动
	TimeManager.start_new_day()
	# 每夜补植挂在开局这声 new_day 之后：开局撒点已经管过一次，别第一天就重复补
	TimeManager.new_day.connect(_respawn_nature)

	# 11) 读档 / 开新档。三种来路，优先级从高到低：
	#     a) 开始界面按了「开始」 -> 把所有系统打回初始值（第 1 年第 1 天）
	#     b) 开始界面按了「加载」 -> _pending 里挂着一份存档，整个世界还原成存档时的样子
	#     c) 直接从编辑器/探针跑 game.tscn（开始界面没参与）-> 老规矩：有存档就续上
	#     读档要在 _build_trees（步骤 5.5）之后：树的数据换成存档的，显示节点重建。
	#     ❗开局物资不在这里发 —— 一无所有开局，改由第一次进屋时哥布林的对话赠与
	#     （house.gd _try_intro -> game._give_starting_items）。
	if SaveManager.take_reset_request():
		SaveManager.reset_all()
		# 任务栏也是新的一局：清掉上局残留，发起开局指引
		Quests.reset_all()
		Quests.start_guide()
		preload("res://story_dialogue.gd").flags_reset()   # 哥布林开场白新档重播
		# ❗reset_all 把树数据清了，但步骤 5.5 撒的树节点还挂在屏幕上 ——
		#   结果就是「看得见砍不着」+ 新档首存把 trees=[] 写进档。
		#   这里把树连数据带节点整个重建一遍（新档开局就该是满岛 60 棵）。
		#   岩石同理：reset_all 把 OreVein 清了，屏幕上的石头节点也得跟着重建。
		_build_trees()
		_build_rocks()
		_build_stations()
		_sync_current_item()
		# 新档开出来就是「第 1 天早上 6 点」—— 正好是存档时刻，所以立刻记一份：
		# 刚开的档马上出现在主页面的读档列表里，不用先睡一觉才看得见。
		SaveManager.save_game(self)
		# w5 开局动画: 五国瓜分, 国破, 流落荒岛。只有真·新档播一次——
		# 读档/续档走 elif 分支不会进这里; 自检/探针把 SaveManager.enabled
		# 关掉了, 双保险不播（动画是 await 的, 别让测试干等 20 秒）。
		if SaveManager.enabled:
			await _play_opening()
	elif SaveManager.has_pending():
		SaveManager.apply_pending(self)
		_sync_current_item()
	elif SaveManager.enabled and SaveManager.has_save() and SaveManager.load_into_pending():
		SaveManager.apply_pending(self)
		_sync_current_item()
	else:
		_sync_current_item()
	# e53: 招募窗口的任务栏挂载（新档开局 / 读档 / 裸跑三条来路统一补挂一次）
	Recruits.sync_quests()

# 开局动画的壳: 冻时间冻人, 播完再放行。中途径景切换时协程自然断掉,
# 时间状态由下一次 begin_new_game / 读档的 reset 流程兜回来。
func _play_opening() -> void:
	var was_running := TimeManager.time_running
	TimeManager.time_running = false
	_set_player_frozen(true)
	# e28d: 开局动画固定中世纪包第 2 首（新档专属曲），播完交还昼夜/四季自动选曲
	Audio.set_scene_bgm("opening")
	var op: Node = preload("res://scene/opening.gd").new()
	add_child(op)
	await op.finished
	Audio.set_scene_bgm("")          # 回岛: BGM 归位到岛上曲池
	TimeManager.time_running = was_running
	_set_player_frozen(false)
	if player != null and player.has_method("_flash"):
		player._flash("身上一无所有 -- 先去东边的屋子瞧瞧")

# ---------------- e33 画面美化：水澜 / 震屏 ----------------
# e33b 水面微澜：波纹按格子哈希分 3 桶，每 0.55 秒轮换一桶的变体
# （每格约 1.65 秒动一次）—— 海面就活了。只换「变体列」，深浅档不动
# （深浅跟离岸 BFS 对应，重算太贵）。
var _water_anim_cells: Array = []
var _water_anim_lv := {}
var _water_bucket := 0
var _water_anim_t := 0.0

# e33d 相机震屏：雷击/树倒给一记短抖（往 Camera2D.offset 上抖，随剩余时间衰减归零）
var _shake_amp := 0.0
var _shake_dur := 0.0
var _shake_left := 0.0

func _tick_water_ripple(delta: float) -> void:
	if _water_anim_cells.is_empty():
		return
	_water_anim_t += delta
	if _water_anim_t < WATER_ANIM_PERIOD:
		return
	_water_anim_t = 0.0
	_water_bucket = (_water_bucket + 1) % 3
	for c in _water_anim_cells:
		if _hash2(c) % 3 != _water_bucket:
			continue
		var lv: int = int(_water_anim_lv.get(c, 1))
		var v: int = (_hash2(c + Vector2i(31, 17)) + _water_bucket) % WATER_VARIANTS
		water_layer.set_cell(c, WATER_SRC, Vector2i(lv, v))

# 震一下：amp 是最大像素幅度, dur 是时长。连续触发取更强的一档。
func shake_screen(amp: float, dur: float) -> void:
	_shake_amp = maxf(_shake_amp, amp)
	_shake_dur = maxf(_shake_dur, dur)
	_shake_left = _shake_dur

func _tick_camera_shake(delta: float) -> void:
	if _shake_left <= 0.0 or player == null:
		return
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	_shake_left -= delta
	if _shake_left <= 0.0:
		cam.offset = Vector2.ZERO
		return
	var k: float = _shake_left / maxf(_shake_dur, 0.01)
	cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amp * k

func _process(delta: float) -> void:
	_sync_post(delta)
	_tick_water_ripple(delta)      # e33b 水面微澜：波纹分桶轮换
	_tick_camera_shake(delta)      # e33d 相机震屏：衰减抖动
	# 建造模式的 ghost：贴着鼠标格走，绿 = 能放 / 红 = 不能放
	if _move_mode:
		_tick_move_mode()      # e44 建筑模式：悬停高亮 / 拾起后 ghost 跟鼠标
	if build_kind == "" or _ghost == null or not is_instance_valid(_ghost):
		return
	var anchor := _world_to_cell(get_global_mouse_position())
	_ghost.position = _cell_tree_pos(anchor)
	_ghost_ok = _building_site_ok(anchor)
	_ghost.modulate = Color(0.55, 1.0, 0.55, 0.6) if _ghost_ok else Color(1.0, 0.4, 0.35, 0.55)

# e31 光影：后处理跟着昼夜走 —— 夜里泛光更浓（灯火在暗底上最抢眼）、
#   顶部天光从暖金斜阳换成冷月光、晕影压深一点。慢慢过渡，别在日落那一刻"啪"地跳。
func _sync_post(delta: float) -> void:
	if _post_mat == null:
		return
	var want := _night_at(TimeManager.hour + TimeManager.minute / 60.0)
	_post_night = move_toward(_post_night, want, delta * 0.5)
	_post_mat.set_shader_parameter("night", _post_night)
	# 雨夜湿地反光：亮源往下淌光晕（风暴更湿），雨停后地面慢慢"晾干"
	var want_wet := 0.0
	if Weather.is_rain():
		want_wet = 0.9 if Weather.is_storm() else 0.6
	_post_wet = move_toward(_post_wet, want_wet, delta * 0.25)
	_post_mat.set_shader_parameter("wet", _post_wet)
	# 胶片颗粒：基础一点 + 夜里加重（暗部颗粒最出质感）+ 湿地再加一点
	_post_mat.set_shader_parameter("grain", 0.026 + _post_night * 0.02 + _post_wet * 0.012)

# 夜度曲线：8~17 点纯白天；17~21 点天在暗；21~5 点最暗；5~8 点天在亮
func _night_at(h: float) -> float:
	if h >= 8.0 and h < 17.0:
		return 0.0
	if h >= 17.0 and h < 21.0:
		return (h - 17.0) / 4.0
	if h >= 21.0 or h < 5.0:
		return 1.0
	return 1.0 - (h - 5.0) / 3.0

# 背包（Esc / B）和派活面板（T）走 _unhandled_input，不走 _process 轮询。
# ❗这是个真踩过的坑：在 _process 里用 Input.is_action_just_pressed 会绕开
#   「这个按键有没有被面板吃掉」这件事。比如商人面板开着时按 Esc，面板自己会先关掉，
#   等 _process 再看「面板还开着吗」已经晚了 —— 结果 Esc 顺手把背包也翻开了。
#   放在 _unhandled_input 里，被面板 set_input_as_handled() 吃掉的按键传不到这里，
#   天然就没有这个问题。
func _unhandled_input(event: InputEvent) -> void:
	# 建造模式优先：Esc/B 取消摆放，左键放置，右键取消（面板都别想在这时候弹出来）
	if build_kind != "":
		if event.is_action_pressed("toggle_inventory") \
				or event.is_action_pressed("toggle_tasks") \
				or event.is_action_pressed("cheat_panel"):
			_cancel_build()
			get_viewport().set_input_as_handled()
			return
		var bb := event as InputEventMouseButton
		if bb != null and bb.pressed:
			if bb.button_index == MOUSE_BUTTON_LEFT:
				_confirm_build()
				get_viewport().set_input_as_handled()
				return
			if bb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_build()
				player._flash("打消了建造的念头")
				get_viewport().set_input_as_handled()
				return
	# e44 建筑模式优先（跟建造模式一样，面板在这时候都别弹出来）：
	#   左键 = 拾起鼠标底下那座 / 放下手里的那座；右键 = 放回原处 / 退出；Esc/B/T = 退出
	if _move_mode:
		if event.is_action_pressed("toggle_inventory") \
				or event.is_action_pressed("toggle_tasks") \
				or event.is_action_pressed("cheat_panel"):
			_cancel_move()
			get_viewport().set_input_as_handled()
			return
		var mb2 := event as InputEventMouseButton
		if mb2 != null and mb2.pressed:
			if mb2.button_index == MOUSE_BUTTON_LEFT:
				_move_click()
				get_viewport().set_input_as_handled()
				return
			if mb2.button_index == MOUSE_BUTTON_RIGHT:
				_move_right_click()
				get_viewport().set_input_as_handled()
				return
	# e18f: 背包(Esc 界面)开着时 A/D(或方向键) 左右切页签 —— 玩家已冻结, 移动键正好挪用
	if backpack_panel != null and backpack_panel.is_open():
		if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
			backpack_panel.cycle_tab(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
			backpack_panel.cycle_tab(1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_inventory"):
		_toggle_backpack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_tasks"):
		_toggle_tasks()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cheat_panel"):
		_toggle_cheat()
		get_viewport().set_input_as_handled()
		return
	# 按 F：先看码头（修码头/造船/出海），再看矿井（提示去派活面板），
	#       再试伙伴对话，最后才轮到商人/水井等
	if event.is_action_pressed("interact"):
		if _try_dock():
			get_viewport().set_input_as_handled()
			return
		if _try_mine_hint():
			get_viewport().set_input_as_handled()
			return
		if _try_station_interact():
			get_viewport().set_input_as_handled()
			return
		if dialogue_panel != null and _try_talk_nearest():
			get_viewport().set_input_as_handled()
			return
	# Ctrl + 滚轮 = 缩放视角（e18f: 背包等面板开着时外界缩放停止响应 —— 玩家已冻结,
	# frozen 就是「有面板盖着世界」的总开关）
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and (mb.ctrl_pressed or mb.meta_pressed) \
			and (mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if player != null and not player.frozen:
			_zoom_camera(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()

# 找离玩家最近的「在对话范围内」的伙伴，让它开对话。
# 没找到就返回 false，让 merchant 之类的继续接 F。
func _try_talk_nearest() -> bool:
	if player == null:
		return false
	var ppos: Vector2 = player.global_position
	var best: Node = null
	var best_d: float = INF
	for n in slave_nodes:
		if n == null or not n.visible:
			continue
		if not n.has_method("_try_talk"):
			continue
		var npos: Vector2 = (n as Node2D).global_position
		var d: float = ppos.distance_squared_to(npos)
		if d < best_d and d <= 32.0 * 32.0:
			best_d = d
			best = n
	if best == null:
		return false
	return best.call("_try_talk")

# ---------------- 废弃码头 / 大地图旅行 ----------------
# 码头是旅行的唯一入口：废墟 -> 付钱备料 -> 派人修 -> 建成后造船 -> 按 F 出海。
# 出海后整个游戏岛被 Voyage 冻结隐藏（数据原样保留），回来时继续。

# 东岸（河右边那块地）最靠东、东边就是水的那格陆地 —— 码头盖在那儿。
# ❗只能等 _build_terrain() 跑完再问：那时候 _land_set 才填好。
func _dock_cell() -> Vector2i:
	var mid_y := int(round(float(ISLAND_FROM.y + ISLAND_TO.y) * 0.5))
	var best := Vector2i(int(ISLAND_TO.x), mid_y)
	var best_score := -1e9
	for c in _land_set.keys():
		var cx: int = int(c.x)
		var cy: int = int(c.y)
		if cx < RIVER_CX + 6:                       # 只认河东侧那块地
			continue
		if not is_water(Vector2i(cx + 1, cy)):      # 东边得是水，栈桥才伸得出去
			continue
		# 越靠东越好；同时别跑到岛的尖角上，越靠中腰越加分
		var score := float(cx) - absf(float(cy - mid_y)) * 1.6
		if score > best_score:
			best_score = score
			best = Vector2i(cx, cy)
	return best

func _setup_dock() -> void:
	var d = preload("res://scene/dock.gd").new()
	d.name = "Dock"
	add_child(d)
	d.setup(_dock_cell())
	dock = d

func _setup_dock_panel() -> void:
	var p = preload("res://dock_ui.gd").new()
	p.name = "DockPanel"
	hud.add_child(p)
	dock_panel = p
	p.opened.connect(func():
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		_set_player_frozen(true))
	p.closed.connect(func(): _set_player_frozen(false))
	p.depart_requested.connect(_depart)

# F 在码头边：开码头面板（造船 / 出海）。返回 true 表示这下 F 被吃掉了。
func _try_dock() -> bool:
	if dock == null or player == null or dock_panel == null:
		return false
	if Voyage.traveling or _sailing or dock_panel.is_open():
		return false
	if not dock.in_reach(player.global_position):
		return false
	dock_panel.open_panel()
	return true

# 面板上点「出海」：先问 Voyage 同不同意，同意了就让伙伴上船，然后才出海。
func _depart() -> void:
	if player == null or _sailing:
		return
	var why: String = Voyage.depart_block_reason(self)
	if why != "":
		player._flash(why, "error")
		return
	if dock_panel != null:
		dock_panel.close_panel()
	_set_player_frozen(true)
	await _board_expedition()
	await _sail_away()          # 镜头钉在港口，全员搭船驶出画面
	Voyage.enter_travel(self)

# ---------------- 出海离开动画 ----------------
# 需求：出海时摄像机固定在港口，所有人搭船从港口离开画面。
# 走法：镜头钉到码头 -> 泊位上停着的船先藏起来（出海的就是它们）->
#   在泊位另画一支载着全员小人的船队 -> 往东匀速驶出画面 -> 清场，交给 enter_travel。
# ❗全程人已经「在船上」（玩家和小人都藏掉），画面上只有船在动 —— 跟海图上的
#   船队一个规矩：0 号座船是主角，一船两人，人越多船越多。
# ❗e37c: 动画期间**不动 zoom**（用户: 出海动画不要改变镜头缩放）——
#   老版这里把 zoom 强拉到 2 倍再还给玩家, 画面会「啪」地缩一下。
#   改为: 照玩家当前 zoom 算「驶出画面」要开多远, 镜头钉在泊位上不动。
func _sail_away() -> void:
	if dock == null or player == null:
		return
	_sailing = true
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	# 泊位在栈桥南侧水面（dock + (14~66, 28~43)）—— 镜头钉在整排泊位的中心,
	# 玩家在任何缩放档下都刚好把船队圈进来。
	var slot0: Vector2 = dock.boat_slot_global(0)
	var slot1: Vector2 = dock.boat_slot_global(mini(2, maxi(0, Voyage.boat_count - 1)))
	var berth: Vector2 = (slot0 + slot1) * 0.5
	if cam != null:
		cam.global_position = berth
	player.visible = false                 # 主角上船（人藏进船里, 船上另画真身）
	dock.set_parked_boats_visible(false)
	var fleet := Node2D.new()
	fleet.name = "SailFleet"
	fleet.z_index = Z_SHORE                # 船浮在水上：跟码头同层，桥(-4)/水(-6) 之上
	add_child(fleet)
	var n_boats: int = maxi(1, Voyage.boats_needed())
	var crew_total: int = 1 + Slaves.expedition.size()
	var boats: Array = []
	for i in n_boats:
		var s := Sprite2D.new()
		# d12: 出海是「扬帆起航」的正戏 —— 挂帆（boat.png 32x44, 船身上半是桅杆+主帆+前帆+小旗）。
		#   停泊时收帆用 boat_hull, 动画里帆张开, 跟海图船队同一张图同一挂法。
		s.texture = load("res://resources/texture/boat.png")
		# 带帆图高 44（船身在 25~42 行）, offset (0,-14) 让船身落回与旧 32x20 逐像素一致的位置
		s.offset = Vector2(0, -14)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fleet.add_child(s)
		# ❗boat_slot_global 返回的是全局坐标 —— 场景根本身有偏移, 塞给相对 position
		#   会双重偏移, 船就从半海里外冒出来了（用户实测「出发点不在码头」）。
		#   进树之后设 global_position, 引擎自己换算局部坐标。
		s.global_position = dock.boat_slot_global(i)
		# 头一条是主角座船（原尺寸），后面的护卫船略小一点，跟海图上的船队一个规矩
		if i > 0:
			s.scale = Vector2(0.88, 0.88)
			s.modulate = Color(0.92, 0.94, 1.0)
		boats.append(s)
		# 这条船上的座位：一船两人，全队坐满为止
		for seat in Voyage.BOAT_SEATS:
			var k := i * Voyage.BOAT_SEATS + seat
			if k >= crew_total:
				break
			var c: Sprite2D = _crew_sprite(k)   # 主角和同伴的真身，侧身坐船面朝船头
			c.position = Vector2(-6.0 + float(seat) * 12.0, -9.0)
			c.z_index = 1                  # 坐在船面上
			s.add_child(c)
		# 浪里颠簸：船带着人轻轻起伏，才有「航行中」的样子（tween 挂 fleet 上，拆场即停）
		var base_y: float = s.position.y
		var bob: Tween = fleet.create_tween().set_loops()
		bob.tween_property(s, "position:y", base_y - 1.5, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(s, "position:y", base_y, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 出画距离按当前缩放算：观景视野半宽 + 一点余量 —— 不管玩家在 2 倍还是 6 倍,
	# 船队都正好驶出画面, 不会「开一半就没了」或者「开出半天还在屏幕上」。
	var zoom := 1.0
	if cam != null:
		zoom = maxf(0.01, cam.zoom.x)
	var out_dist: float = get_viewport_rect().size.x * 0.5 / zoom + 48.0
	# 船队往东匀速驶出画面 —— d12: 每条船平移**同一距离**, 出发时泊位排成什么样,
	# 出画时就是什么队形（旧版后面船目标多让 14px 会越开越近, 26px 泊位间距
	# 被追成 12px, 48px 宽的船直接叠在一起 = 「船撞在一起」）。
	# 出画余量按队尾算：最左的船也要完全出画, 平移距离 = 视半宽 + 队宽 + 余量。
	# （全程用 global_position:x —— 与出发点同一坐标系, 别再掉进局部/全局的坑）
	var shift: float = out_dist + 26.0 * float(n_boats)
	for b in boats:
		var tw := create_tween()
		tw.tween_property(b, "global_position:x",
			(b as Sprite2D).global_position.x + shift,
			SAIL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(SAIL_TIME).timeout
	# 清场：临时船队拆掉，泊位的船放回来，镜头交还给玩家 —— 接着 enter_travel
	# 会把整座岛藏起来切海图，回岛时一切照旧。
	fleet.queue_free()
	dock.set_parked_boats_visible(true)
	player.visible = true
	if cam != null:
		cam.global_position = player.global_position       # 镜头还给主角（zoom 没动过）
	_sailing = false

# 船上的主角和同伴：用各自模型的**真实侧身帧**（行 2 = 侧面，面朝右 = 船头方向），
# 谁在船上一眼认得出 —— 主角是 Josh，同伴按模型表对号入座。
# e29c: 同伴的发色/服装配色烘在贴图层（sheet_texture 改色管线），跟白天同脸同色；
# modulate 只剩装甲档位色。
# （替代旧版 7x10 抽象小人：模型图 32px 一帧缩 0.75，nearest 过滤不糊。）
func _crew_sprite(k: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var at := AtlasTexture.new()
	if k > 0:
		var idx: int = int(Slaves.expedition[k - 1]) if k - 1 < Slaves.expedition.size() else k - 1
		at.atlas = SLAVE_SCRIPT.sheet_texture(SLAVE_SCRIPT.model_for(idx), "Idle.png", idx)
		var troop := String(Slaves.slave_at(idx).get("troop", "新兵"))
		s.modulate = Slaves.armor_tint(troop)
	else:
		# 第三方素材不入库(见 README), 缺失时留空不崩
		at.atlas = SoftRes.tex(_crew_sheet(k))
	at.region = Rect2(0, 64, 32, 32)       # Idle.png 行 2 第 0 帧（侧面朝右）
	s.texture = at
	s.scale = Vector2(0.75, 0.75)
	return s

# 第 k 位船员的模型图路径：0 = 主角(Josh)，其余按出海名单的序号取各自模型
# （k>0 的改色版贴图在 _crew_sprite 里走 sheet_texture，这里留作模型名真相源）
func _crew_sheet(k: int) -> String:
	if k <= 0:
		return "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Idle.png"
	var idx: int = int(Slaves.expedition[k - 1]) if k - 1 < Slaves.expedition.size() else k - 1
	return "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/Idle.png" \
		% SLAVE_SCRIPT.model_for(idx)

# 出海前那一小段：把勾了「明天出行」的伙伴叫到码头边，看他们走上船。
# ❗不能一按出海就直接切场景 —— 那时候整个岛立刻被藏起来，上船这一幕就看不见了。
func _board_expedition() -> void:
	var party: Array = Slaves.expedition
	if party.is_empty():
		return
	for k in range(party.size()):
		var n: Node2D = _slave_node(int(party[k]))
		if n == null:
			continue
		n.global_position = _board_slot(k)
		n.call("board_to", dock.global_position + Vector2(14, 2))
	if player != null:
		player._flash("伙伴们上船了 (%d 人)" % party.size())
	# ❗等他们**真的**走到船上再切场景（最多 3 秒）：固定等 1.2 秒不够 ——
	#   站得最远那个人还在半路，场景一切 game 就被冻住，人会僵在码头上。
	#   到点还没上船的直接算上船（见 board_now），绝不把整趟出海卡在这儿。
	var t := 0.0
	while t < 3.0 and not _all_aboard():
		await get_tree().process_frame
		t += get_process_delta_time()
	for k in range(party.size()):
		var n2: Node2D = _slave_node(int(party[k]))
		if n2 != null and not bool(n2.call("is_aboard")):
			n2.call("board_now")

func _all_aboard() -> bool:
	for k in range(Slaves.expedition.size()):
		var n: Node2D = _slave_node(int(Slaves.expedition[k]))
		if n != null and not bool(n.call("is_aboard")):
			return false
	return true

# 第 i 个上船伙伴的站位：码头西侧（陆地那边）两列排开。
# ❗码头西边就是海，摆歪了人会泡在水里 —— 真撞上水就继续往西让。
func _board_slot(i: int) -> Vector2:
	var p: Vector2 = dock.global_position \
		+ Vector2(-14.0 - float(i % 2) * 13.0, 8.0 + float(i / 2) * 13.0)
	var guard := 0
	while is_water(_world_to_cell(p)) and guard < 14:
		p += Vector2(-16, 0)
		guard += 1
	return p

# 按序号取伙伴节点（越界/还没生成返回 null）
func _slave_node(i: int) -> Node2D:
	if i < 0 or i >= slave_nodes.size():
		return null
	return slave_nodes[i]

# 从大地图返航：把主角放回码头边，伙伴们下船
func on_voyage_return() -> void:
	if player == null:
		return
	if dock != null:
		player.global_position = dock.global_position + Vector2(-10, 22)
	_disembark_expedition()
	player.frozen = false
	player._flash("回到了岛上")

# 下船：出海的伙伴在码头边重新出现，接着过白天的日子
func _disembark_expedition() -> void:
	if dock == null:
		return
	for k in range(Slaves.expedition.size()):
		var n: Node2D = _slave_node(int(Slaves.expedition[k]))
		if n != null and n.has_method("unboard"):
			n.call("unboard", _board_slot(k) + Vector2(-24, 0))

# 大地图战败：抬回家门口回满血（跟岛上倒下同一套待遇，v0.1 不罚钱）
func on_voyage_defeat() -> void:
	if player == null:
		return
	var house := get_node_or_null("House")
	var pos: Vector2 = player.global_position
	if house != null:
		pos = (house as Node2D).global_position + Vector2(0, 40)
	player.global_position = pos
	Legion.player_hp = Legion.player_max_hp()
	Legion.stats_changed.emit()
	player._flash("战败被抬了回来 -- 休息一下再战")
	Audio.play_sfx("error", -4.0)

# ---------------- 相机缩放 ----------------
# 只走整数倍：像素画在非整数缩放下，同一张图里的像素会被拉成 3px / 4px 混着，
# 移动时地面会「抖」。2~8 倍之间一档一档跳，画面永远是干净的。
const ZOOM_MIN := 2
const ZOOM_MAX := 8

func _zoom_camera(step: int) -> void:
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	if cam == null:
		return
	var now := int(round(cam.zoom.x))
	var z := clampi(now + step, ZOOM_MIN, ZOOM_MAX)
	if z == now:
		return                                  # 已经到头了，不用白响一声
	cam.zoom = Vector2(float(z), float(z))
	Audio.play_sfx("ui_click", -14.0)

# ---------------- 伙伴（奴隶）----------------
# 派活地图的范围跟核心陆地一致（ISLAND_FROM/TO），两边永远同步。
# 伙伴节点**直接挂在 Game 下**（不套容器）—— 套了容器 y_sort 就散了：
# 容器自己只有一个 y，底下的孩子没法跟主角互相遮挡。
func _setup_slaves() -> void:
	# 派活地图 = **整座岛**（核心陆地 + 噪声切出来的海岸带）的外接矩形，
	# 不再只是 ISLAND_FROM/TO 那块核心 —— 岛边上那些零碎的草地也要能划到。
	var b := _island_bounds()
	Slaves.map_from = b[0]
	Slaves.map_to = b[1]
	Slaves.changed.connect(_sync_slaves)
	_sync_slaves()

# 整座岛的外接矩形（格子号）：把 _land_set 里所有陆地取 min/max。
# ❗地形是噪声切的，岛缘凹凸不平，所以只能这么算，不能照抄 ISLAND_FROM/TO。
func _island_bounds() -> Array:
	var have := false
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	for c in _land_set.keys():
		var v: Vector2i = c
		if not have:
			lo = v
			hi = v
			have = true
			continue
		lo.x = mini(lo.x, v.x)
		lo.y = mini(lo.y, v.y)
		hi.x = maxi(hi.x, v.x)
		hi.y = maxi(hi.y, v.y)
	if not have:
		return [ISLAND_FROM, ISLAND_TO]
	return [lo, hi]

func _sync_slaves() -> void:
	while slave_nodes.size() < Slaves.count:
		var n: Node2D = preload("res://scene/slave_npc.gd").new()
		var idx := slave_nodes.size()
		n.name = "Slave%d" % idx
		n.index = idx          # ❗要在 add_child **之前**给号：_ready 里靠它选「这张脸」加载素材
		add_child(n)
		slave_nodes.append(n)
		n.setup(idx, _field_center())
	while slave_nodes.size() > Slaves.count:
		var last: Node = slave_nodes.pop_back()
		last.queue_free()

# 农田的中心（世界坐标）：伙伴的集合点
func _field_center() -> Vector2:
	var cells: Array = Farm.tilled.keys()
	if cells.is_empty():
		return Farm.grid_origin
	var sum := Vector2i.ZERO
	for c in cells:
		sum += c
	var avg := Vector2(float(sum.x), float(sum.y)) / float(cells.size())
	return Farm.grid_origin + avg * float(Farm.TILE_SIZE)

# 白天按 T 随时能改分配（夜里那张面板是同一张，只是自动弹）
func _toggle_tasks() -> void:
	if assign_panel == null or _sleeping:
		return
	if assign_panel.is_open():
		assign_panel._dismiss()
		return
	if shop_panel != null and shop_panel.is_open():
		return
	if bin_panel != null and bin_panel.is_open():
		return
	_set_player_frozen(true)
	assign_panel.open()

# 作弊面板（P）：加钱 / 加资源，测试用。其他面板开着时不叠加
func _toggle_cheat() -> void:
	if cheat_panel == null or _sleeping:
		return
	if cheat_panel.is_open():
		cheat_panel._dismiss()
		return
	if shop_panel != null and shop_panel.is_open():
		return
	if bin_panel != null and bin_panel.is_open():
		return
	if backpack_panel != null and backpack_panel.is_open():
		return
	_set_player_frozen(true)
	cheat_panel.open()

# ---------------- 图层层级（配合 y_sort 做前后遮挡）----------------
# 地形全部给负 z_index（永远在最下面），实体留在 0 层由 y_sort 按脚下的 y 排序。
# ❗水的 z_index 以前在 _paint_water 里被强制成 0，这里统一收口到 Z_WATER。
func _apply_layer_z() -> void:
	grid_layer.z_index = Z_GRASS
	water_layer.z_index = Z_WATER
	authored_field.z_index = Z_SOIL
	if decor_layer != null:
		decor_layer.z_index = Z_DECOR
	if border_layer != null:
		border_layer.z_index = Z_BORDER
	if beach_layer != null:
		beach_layer.z_index = Z_BEACH
	if shore_layer != null:
		shore_layer.z_index = Z_SHORE
	var soil := get_node_or_null("SoilLayer")
	if soil != null:
		soil.z_index = Z_SOIL
	var floor_layer := get_node_or_null("FloorLayer")
	if floor_layer != null:
		floor_layer.z_index = Z_FLOOR
	var crops := get_node_or_null("CropLayer")
	if crops != null:
		crops.z_index = Z_CROP
	var bridges := get_node_or_null("Bridges")
	if bridges != null:
		# ❗容器自己必须是 0：桥后段 sprite 自带 Z_BRIDGE，而 z_index 是**相对父节点累加**的
		#   （z_as_relative 默认开）。以前这里也写了 Z_BRIDGE，结果 -4 + -4 = -8，
		#   比水面(-6)还低 —— 整座桥被水盖住，看着像没架桥。
		bridges.z_index = 0
	# 实体：原点已经在脚下，留在 0 层让 y_sort 排
	for path in ["Merchant", "House", "ShippingBin"]:
		var n := get_node_or_null(path)
		if n != null:
			(n as Node2D).z_index = 0

# ---------------- 外海（e16b） ----------------
# 地图矩形之外原本什么都不画 —— 相机拉到最小档(2x)再靠岸, 视野出界就是
# 引擎默认的黑底(用户实测截图)。对策两条:
#   1. 地形最底下垫一块巨大的远洋深蓝 Polygon2D —— 视野再怎么出界,
#      看到的也是「岛外的远海」, 不是黑幕;
#   2. 玩家相机设 limits(地图矩形外扩 8 格) —— 拉远时画面贴着围栏停,
#      不会把垫子边界也挪进画面。
# ❗坐标: 垫子挂在 game 根下走局部坐标(grid_layer.position); limits 是世界
#   坐标, 用 Farm.grid_origin(= grid_layer.global_position)换算。
const OUTER_SEA := Color(0.05, 0.42, 0.66)   # 远洋深蓝(比 WATER_DEPTHS 末档更深)
const OUTER_PAD_PX := 2048.0                  # 垫子往四周多铺的距离(拉多远都铺满)

func _build_outer_sea() -> void:
	var sea := Polygon2D.new()
	sea.name = "OuterSea"
	var o := grid_layer.position
	var x0 := o.x + float(YARD_FROM.x) * 16.0 - OUTER_PAD_PX
	var y0 := o.y + float(YARD_FROM.y) * 16.0 - OUTER_PAD_PX
	var x1 := o.x + (float(YARD_TO.x) + 1.0) * 16.0 + OUTER_PAD_PX
	var y1 := o.y + (float(YARD_TO.y) + 1.0) * 16.0 + OUTER_PAD_PX
	sea.polygon = PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0),
		Vector2(x1, y1), Vector2(x0, y1)])
	sea.color = OUTER_SEA
	sea.z_index = -20          # 压过一切地形层(水面 Z_WATER=-6)
	add_child(sea)
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	if cam != null:
		var gp := Farm.grid_origin
		var pad := 8.0 * 16.0
		cam.limit_left = int(gp.x + float(YARD_FROM.x) * 16.0 - pad)
		cam.limit_top = int(gp.y + float(YARD_FROM.y) * 16.0 - pad)
		cam.limit_right = int(gp.x + (float(YARD_TO.x) + 1.0) * 16.0 + pad)
		cam.limit_bottom = int(gp.y + (float(YARD_TO.y) + 1.0) * 16.0 + pad)

# ---------------- 池塘 ----------------
# 草地图层在池塘那几格是留空的，水面由 WaterTileMapLayer 负责。
# 问题是水面图层的节点位置跟草地网格差了 (3,-5) 像素 —— 于是「拿草地的格子号
# 去问水面图层这格有没有水」会整体错位，池塘边缘就漏出几个没铺东西的黑洞。
# 这里做两件事：把水面吸附到草地网格上；再把草地上所有没被水盖住的洞补全。
func _align_pond() -> void:
	if water_layer.tile_set == null or grid_layer.tile_set == null:
		return
	var tsz := grid_layer.tile_set.tile_size
	var old_cells := water_layer.get_used_cells()
	var src := -1
	var atlas := Vector2i.ZERO
	for c in old_cells:
		src = water_layer.get_cell_source_id(c)
		atlas = water_layer.get_cell_atlas_coords(c)
		break
	if src == -1:
		return
	var old_origin := water_layer.global_position

	# 1) 吸附网格：每片水面的世界坐标不动，只是换成草地网格里的格子号
	water_layer.global_position = grid_layer.global_position
	water_layer.clear()
	for c in old_cells:
		var world := old_origin + Vector2(c * tsz)
		var local: Vector2 = world - water_layer.global_position
		water_layer.set_cell(
			Vector2i(roundi(local.x / tsz.x), roundi(local.y / tsz.y)), src, atlas)

	# 2) 草地矩形里的每个洞都必须有水
	var cells := grid_layer.get_used_cells()
	if cells.is_empty():
		return
	var has := {}
	var minx: int = cells[0].x
	var maxx: int = minx
	var miny: int = cells[0].y
	var maxy: int = miny
	for c in cells:
		has[c] = true
		minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
		miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
	var filled := 0
	for x in range(minx, maxx + 1):
		for y in range(miny, maxy + 1):
			var c := Vector2i(x, y)
			if has.has(c) or water_layer.get_cell_source_id(c) != -1:
				continue
			water_layer.set_cell(c, src, atlas)
			filled += 1
	print("[池塘] 水面已对齐草地网格,补了 %d 格" % filled)

# ---------------- 地形：岛 / 岛中河 / 桥 ----------------
# 现在的布局：
#   · ISLAND_* 内            = 核心陆地（玩家主要活动区，塘/农舍/商人都在这）
#   · 核心外                = 海岸带，噪声决定草/水 —— 岛的边缘因此凹凸不平
#   · 再往外                = 汪洋（没有任何强制，一律是水）
#   · 岛中间                = 一条南北向的浅河，把这个岛切成东西两块
#   · 桥 = 横跨河面的素材精灵，两端是陆地当桥头
var _pond_cells: Array = []    # _align_pond 后保留下来作为池塘原状的格子
var _water_set := {}           # 所有水格（海洋 + 河 + 池塘），Vector2i -> true
var _land_set := {}            # 所有陆地格
var _forced := {}              # 被强制指定水/陆的格子（平滑时不去动它）
var _sand_set := {}            # 沙滩格（左岛西北岸那片）：不可耕、不长树/石

# 生成整张地图的地形：先铺草，再挖水（海洋 + 河 + 保留池塘），最后重新画水面
func _build_terrain() -> void:
	_pond_cells = water_layer.get_used_cells()

	# 1) 全 YARD 铺草地打底（之后大部分会被水盖住 —— 水面图层排在草地之上）
	#    e33c: 草 tile 按低频噪声混入两张 modulate 变体 —— 草地不再是纯色一片
	_grass_alts()
	for x in range(YARD_FROM.x, YARD_TO.x + 1):
		for y in range(YARD_FROM.y, YARD_TO.y + 1):
			var c := Vector2i(x, y)
			if grid_layer.get_cell_source_id(c) == -1:
				var ga := _grass_alt_of(c)
				if ga == 0:
					grid_layer.set_cell(c, YARD_GRASS_SRC, YARD_GRASS_TILE)
				else:
					grid_layer.set_cell(c, YARD_GRASS_SRC, YARD_GRASS_TILE, ga)

	# 2) 决定每格是陆地还是水
	_compute_terrain()

	# 3) 换成程序化生成的水面（统一材质 + 深浅层次），重画所有水格
	_paint_water()

# 逐格判定水/陆。规则按优先级：
#   池塘格强制水 -> 河强制水 -> 桥头引道强制陆 -> 核心强制陆 -> 其余交给噪声
func _compute_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = COAST_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = COAST_FREQ
	var detail := FastNoiseLite.new()
	detail.seed = COAST_SEED + 777
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = COAST_DETAIL_FREQ

	var pond := {}
	for c in _pond_cells:
		pond[c] = true

	_land_set = {}
	_forced = {}
	for x in range(YARD_FROM.x, YARD_TO.x + 1):
		for y in range(YARD_FROM.y, YARD_TO.y + 1):
			var c := Vector2i(x, y)
			var is_land := true
			var fixed := false
			var f := _bridge_force(c)
			if pond.has(c):
				is_land = false
				fixed = true
			elif _is_river(c):
				is_land = false          # 河：一路从北岸切到南岸，把岛分成两半
				fixed = true
			elif f != 0:
				is_land = (f > 0)
				fixed = true
			else:
				var d := _core_dist(c)
				if d == 0:
					is_land = true
					fixed = true
				else:
					# 海岸线位置 = COAST_MID + 噪声；d 比它小就是陆地
					var n: float = noise.get_noise_2d(float(c.x), float(c.y)) \
						+ detail.get_noise_2d(float(c.x), float(c.y)) * COAST_DETAIL_AMP
					is_land = float(d) < COAST_MID + n * COAST_AMP
			if is_land:
				_land_set[c] = true
			if fixed:
				_forced[c] = true

	_smooth_coast()

	_water_set = {}
	for x in range(YARD_FROM.x, YARD_TO.x + 1):
		for y in range(YARD_FROM.y, YARD_TO.y + 1):
			var c := Vector2i(x, y)
			if not _land_set.has(c):
				_water_set[c] = true

	# 左岛西北岸：划定区域里的陆地格一律算沙滩（水格不圈，只圈沙子踩得到的地方）。
	# 右下（东南）边界不直角：贴东/南内边用海岸同款噪声啃出弯曲，
	# 角上再按 SAND_CORNER_R 走圆弧 —— 到 (R, R) 距离超过 R 的角格剔除，
	# 角尖削圆，边界沿四分之一圆弧弯进草地
	_sand_set = {}
	for x in range(SAND_FROM.x, SAND_TO.x + 1):
		for y in range(SAND_FROM.y, SAND_TO.y + 1):
			var sc := Vector2i(x, y)
			if not _land_set.has(sc):
				continue
			var mx: int = SAND_TO.x - sc.x    # 离东内边几格（0 = 贴边）
			var my: int = SAND_TO.y - sc.y    # 离南内边几格
			var sn: float = noise.get_noise_2d(float(sc.x), float(sc.y)) \
				+ detail.get_noise_2d(float(sc.x), float(sc.y)) * COAST_DETAIL_AMP
			var bite := int(round((sn * 0.5 + 0.5) * float(SAND_BITE)))   # 0..SAND_BITE
			if mx < bite or my < bite:
				continue
			if float(mx) < SAND_CORNER_R and float(my) < SAND_CORNER_R:
				var dx: float = SAND_CORNER_R - float(mx)
				var dy: float = SAND_CORNER_R - float(my)
				if dx * dx + dy * dy > SAND_CORNER_R * SAND_CORNER_R:
					continue
			_sand_set[sc] = true

# 到核心陆地矩形的距离（切比雪夫，0 = 就在核心里）
func _core_dist(c: Vector2i) -> int:
	var dx: int = max(ISLAND_FROM.x - c.x, max(c.x - ISLAND_TO.x, 0))
	var dy: int = max(ISLAND_FROM.y - c.y, max(c.y - ISLAND_TO.y, 0))
	return max(dx, dy)

# ---------------- 岛中的河 ----------------
# 河心随 y 缓慢摆动（正弦），所以河道是弯的；再按「x 离河心多远」判定是不是水。
# 半宽 2 + 河心带小数 → 河宽在 4~5 格之间自然变化，不是一条等宽的色带。
func _river_center(y: int) -> float:
	return RIVER_CX + sin(float(y) * RIVER_WOBBLE_FREQ + RIVER_WOBBLE_PHASE) * RIVER_WOBBLE

func _is_river(c: Vector2i) -> bool:
	return absf(float(c.x) - _river_center(c.y)) <= float(RIVER_HALF) + 0.001

# 给外部用（洒水壶对着水面打水）：这一格是不是水（海 / 河 / 池塘都算）
func is_water(c: Vector2i) -> bool:
	return _water_set.has(c)

# 这一格是不是沙滩（左岛西北岸那片）。沙滩上不能开田。
func is_sand(c: Vector2i) -> bool:
	return _sand_set.has(c)

# e52: 「能下水」的水格 —— 河整条都能蹚, 海里只有最深那一档挡人（离岸 >= 5 格）。
# 三个坑:
#   · 桥面格本身就是水格（桥只是画在河面上的贴图, 底下的河没被填成陆地）——
#     不排掉的话站在桥上就会被判成「在水里」, 就是「在桥上也会游」的来源。
#   · 码头栈桥/木桥这类架在水上的木板同理（见 is_deck_cell）——
#     走到码头上还在游泳, 现在一律算走路。
#   · 档位用「水面实际画出来的那一档」(_water_anim_lv, 见 _draw_water_tiles）,
#     不另算一套 —— 玩家眼里的「最深色」跟挡住他的格子必须是同一格。
func is_swim_water(c: Vector2i) -> bool:
	if not _water_set.has(c) or is_bridge_cell(c) or is_deck_cell(c):
		return false
	# 地图最外圈不放行：出地图既没画水面也没有水碰撞（见 _is_water_like），
	# 放过去就真的游出世界了 —— 河一直延伸到地图边，不拦会从河口游出去。
	if _at_map_edge(c):
		return false
	if _is_river(c):
		return true     # 河宽 4~5 格, 离岸最多 3 格 -> 最深只到第 3 档, 整条都能游
	# 缺档位时按最深档算（保守：不放行）
	return int(_water_anim_lv.get(c, WATER_DEPTHS.size() - 1)) < WATER_DEPTHS.size() - 1

# e52: 架在水面上的木板 —— 码头栈桥 + 农场木桥（1x1 便桥）。
# 站上去是走路, 不是游泳（跟桥面同一个道理: 脚下是板子, 不是水）。
func is_deck_cell(c: Vector2i) -> bool:
	if _dock_deck.has(c):
		return true
	if Structures.stations.has(c):
		var s: Dictionary = Structures.stations[c]
		return String(s.get("kind", "")) == Structures.KIND_BRIDGE
	return false

# 码头栈桥盖住的水格, 在地形生成后一次性算好存起来。
# ❗不能在 is_deck_cell() 里现算：那要遍历整个 _land_set, 而游泳判定每物理帧都要问一次。
# 水碰撞构建也排在 _build_terrain() 之后, 所以那时候 _dock_deck 已经就绪。
func _cache_dock_deck() -> void:
	_dock_deck = {}
	var a := _dock_cell()
	for dx in DOCK_DECK_W:
		for dy in DOCK_DECK_H:
			_dock_deck[Vector2i(a.x + dx, a.y + dy)] = true

# 这一格是不是桥占的地方：桥面 + 上下护栏三行，横跨 x0..x1。
# 桥上不能耕地/铺地板 —— 土翻在木板上、地板盖住栏杆都很怪。
func is_bridge_cell(c: Vector2i) -> bool:
	for y in BRIDGE_ROWS:
		if c.y < y - 1 or c.y > y + 1:
			continue
		if c.x >= _bridge_x0(y) and c.x <= _bridge_x1(y):
			return true
	return false

# 这一格能不能动土（锄地 / 铺地板 / 种树种子都问它）：
#   水面不行（土会泡进海里）、桥上不行、有树的地方不行（树根还在）、
#   有岩石的地方不行（石头底下没法种）、已铺装（地板/小径）要先撬掉。
func is_tillable(c: Vector2i) -> bool:
	if is_water(c) or is_bridge_cell(c):
		return false
	if is_sand(c):
		return false
	if Trees.is_blocked(c):
		return false
	if OreVein.is_blocked(c):
		return false
	if Structures.is_blocked(c):
		return false
	if Floor.is_floored(c):
		return false
	return true

# 世界坐标 -> 格子号（撒树避开建筑时用）
func _world_to_cell(w: Vector2) -> Vector2i:
	var local := w - Farm.grid_origin
	return Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE))

# 树的落点（Game 本地坐标）：格子中心、树干踩在格子底边上（y_sort 的排序点）
func _cell_tree_pos(c: Vector2i) -> Vector2:
	return grid_layer.position + Vector2(c.x * 16 + 8, (c.y + 1) * 16)

# 桥左右两端：以那一行的河心为中心，各跨 BRIDGE_HALF 格。
# 河半宽 2 + BRIDGE_HALF 3 → 最外侧那格一定落在岸上，桥下 5 格正好是河。
func _bridge_x0(y: int) -> int:
	return int(round(_river_center(y))) - BRIDGE_HALF

func _bridge_x1(y: int) -> int:
	return int(round(_river_center(y))) + BRIDGE_HALF

# 桥周围的强制规则：1 = 必须是陆地，-1 = 必须是水，0 = 随噪声。
# 这里只强制「桥头引道」是陆地 —— 河面本身已经由 _is_river 强制成水了，
# 所以不需要（也不该）再把桥下那截强制成水。
func _bridge_force(c: Vector2i) -> int:
	for y in BRIDGE_ROWS:
		if c.y < y - 1 or c.y > y + 1:
			continue
		var x0 := _bridge_x0(y)
		var x1 := _bridge_x1(y)
		if (c.x >= x0 - BRIDGE_APPROACH and c.x < x0) \
			or (c.x > x1 and c.x <= x1 + BRIDGE_APPROACH):
			return 1                     # 桥头引道：陆地
	return 0

# 平滑两遍：噪声直接切出来的岸线会有 1 格的碎渣和孤岛，看着毛躁。
#   · 陆地格四周几乎没邻居 -> 淹掉（去掉伸进水里的细丝）
#   · 水格四面都是陆地     -> 填平（去掉水洼里的小坑）
func _smooth_coast() -> void:
	for _pass in 2:
		var flip_land := []
		var flip_water := []
		for x in range(YARD_FROM.x, YARD_TO.x + 1):
			for y in range(YARD_FROM.y, YARD_TO.y + 1):
				var c := Vector2i(x, y)
				if _forced.has(c):
					continue
				var nb_land := 0
				for nb in _cross(c):
					if _land_set.has(nb):
						nb_land += 1
				if _land_set.has(c):
					if nb_land <= 1:
						flip_land.append(c)
				else:
					if nb_land >= 4:
						flip_water.append(c)
		for c in flip_land:
			_land_set.erase(c)
		for c in flip_water:
			_land_set[c] = true

func _cross(c: Vector2i) -> Array:
	return [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]

# ---------------- 水面绘制 ----------------
func _paint_water() -> void:
	var tsz := grid_layer.tile_set.tile_size
	water_layer.clear()
	water_layer.tile_set = _make_water_tileset(tsz)
	water_layer.z_index = Z_WATER   # 地形层一律负 z_index，见 _apply_layer_z()
	_water_anim_cells.clear()       # e33b 微澜轮换的花名册跟着重铺
	_water_anim_lv.clear()

	if _water_set.is_empty():
		return
	var depth := _water_depth_map()
	# 深浅分档不能按整数一刀切 —— 那样窄河里会出现一条条笔直的色带；
	# 早先用的「随机把某一格升一档」又会变成一个个方块。
	# 正解是叠一层平滑噪声，让分档边界变成波浪线（水看起来才像在流动）。
	var wob := FastNoiseLite.new()
	wob.seed = COAST_SEED + 4242
	wob.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wob.frequency = 0.13
	var last: int = WATER_DEPTHS.size() - 1
	for c in _water_set.keys():
		var d: int = depth.get(c, 1)
		var f: float = float(d) - 1.0 + wob.get_noise_2d(float(c.x), float(c.y)) * 0.9
		var lv: int = clampi(int(floor(f + 0.5)), 0, last)
		# e51: 地图最外圈一律画成最深色 —— 那一圈不放人下水（见 is_swim_water）
		if _at_map_edge(c):
			lv = last
		var v: int = _hash2(c + Vector2i(31, 17)) % WATER_VARIANTS
		water_layer.set_cell(c, WATER_SRC, Vector2i(lv, v))
		_water_anim_cells.append(c)     # e33b 记下这格的深浅档, 轮换时只换变体
		_water_anim_lv[c] = lv

# 每格水离岸多远（多源 BFS，4 邻域）。
# 只有「地图内的陆地」才算岸 —— 地图外当作海继续延伸（见 _is_water_like）。
func _water_depth_map() -> Dictionary:
	var dist := {}
	var frontier := []
	for c in _water_set.keys():
		dist[c] = WATER_MAX_DIST
		for nb in _cross(c):
			if not _is_water_like(nb):
				dist[c] = 1
				frontier.append(c)
				break
	var d := 1
	while not frontier.is_empty() and d < WATER_MAX_DIST:
		var nxt := []
		for c in frontier:
			for nb in _cross(c):
				if _water_set.has(nb) and int(dist[nb]) > d + 1:
					dist[nb] = d + 1
					nxt.append(nb)
		frontier = nxt
		d += 1
	return dist

func _hash2(c: Vector2i) -> int:
	var h: int = c.x * 374761393 + c.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

# ---------------- e33c 草地杂色 ----------------
# 给草 tile 挂三张运行时 alternative（只改 modulate, 不占素材）：
#   亮斑偏黄 / 暗斑偏青 / 深斑深青 —— 双频噪声切成大团色块（约 33 格一片）,
#   边缘用细噪声碎一下；靠海和林缘成片偏深, 草地不再是一整张平色。
const GRASS_ALT_LITE := 1
const GRASS_ALT_DARK := 2
const GRASS_ALT_DEEP := 3
var _grass_noise: FastNoiseLite = null
var _grass_noise2: FastNoiseLite = null

func _grass_alts() -> void:
	var src := grid_layer.tile_set.get_source(YARD_GRASS_SRC) as TileSetAtlasSource
	if src == null:
		return
	if not src.has_alternative_tile(YARD_GRASS_TILE, GRASS_ALT_LITE):
		src.create_alternative_tile(YARD_GRASS_TILE, GRASS_ALT_LITE)
	if not src.has_alternative_tile(YARD_GRASS_TILE, GRASS_ALT_DARK):
		src.create_alternative_tile(YARD_GRASS_TILE, GRASS_ALT_DARK)
	if not src.has_alternative_tile(YARD_GRASS_TILE, GRASS_ALT_DEEP):
		src.create_alternative_tile(YARD_GRASS_TILE, GRASS_ALT_DEEP)
	var lite := src.get_tile_data(YARD_GRASS_TILE, GRASS_ALT_LITE)
	if lite != null:
		lite.modulate = Color(0.96, 1.0, 0.88)
	var dark := src.get_tile_data(YARD_GRASS_TILE, GRASS_ALT_DARK)
	if dark != null:
		dark.modulate = Color(0.90, 0.97, 0.93)
	var deep := src.get_tile_data(YARD_GRASS_TILE, GRASS_ALT_DEEP)
	if deep != null:
		deep.modulate = Color(0.79, 0.89, 0.85)
	# 主噪声 = 大团块基调；细节噪声只在边上碎一下, 避免色块边缘太「圆」
	_grass_noise = FastNoiseLite.new()
	_grass_noise.seed = COAST_SEED + 991
	_grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_grass_noise.frequency = 0.03
	_grass_noise2 = FastNoiseLite.new()
	_grass_noise2.seed = COAST_SEED + 992
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

# ---------------- e52: 四季地表 ----------------
# 把草地/水边那两张图集换成当季的。开局(_ready)和每次换季(TimeManager.season_changed)各调一次。
# 只动 texture, 不动任何格子数据 —— 四张图集同布局, 所以坐标/变体天然对得上。
func _apply_season_terrain() -> void:
	var s: int = clampi(TimeManager.season, 0, SEASON_GRASS_TEX.size() - 1)
	var grass: Texture2D = SoftRes.tex(SEASON_GRASS_TEX[s])
	var water: Texture2D = SoftRes.tex(SEASON_GRASS_WATER_TEX[s])
	if grass != null:
		_swap_atlas_texture(grid_layer.tile_set, YARD_GRASS_SRC, grass)
		_swap_atlas_texture(authored_field.tile_set, GROUND_GRASS_SRC, grass)
	else:
		# 第三方素材不入库(见 README), 缺失时保留当前地表, 不能把 null 塞进 TileSet
		push_warning("[素材] 缺少四季草地贴图, 跳过换季")
	if water != null:
		_swap_atlas_texture(authored_field.tile_set, GROUND_WATER_SRC, water)
	else:
		push_warning("[素材] 缺少四季水边贴图, 跳过换季")
	# d6: 换季贴图是瞬切的，垫一个 0.5s 的明暗呼吸弱化跳变
	# （开局那一次就是淡入，也不难看）
	for lay in [grid_layer, authored_field]:
		if lay == null:
			continue
		var tw := create_tween()
		tw.tween_property(lay, "modulate", Color(0.82, 0.84, 0.9), 0.2)
		tw.tween_property(lay, "modulate", Color.WHITE, 0.3)

# 换某一个 atlas source 的贴图, 并让图层重画
# （TileSet 的 changed 信号会通知图层, queue_redraw 是兜底: 免得贴图换了画面还停在旧的那张）
func _swap_atlas_texture(ts: TileSet, src_id: int, tex: Texture2D) -> void:
	if ts == null:
		return
	var src := ts.get_source(src_id) as TileSetAtlasSource
	if src == null or src.texture == tex:
		return
	src.texture = tex

# 这一格在不在我们生成的地图范围内。
# ❗重要：判断「邻居是不是陆地」时必须先问这个 ——
# 地图外的格子既不在 _land_set 也不在 _water_set，
# 如果不排除，地图边界会被当成一条「海岸线」，
# 于是整圈边缘会被描上浅滩 + 算成最浅水深（就是图上那圈假的亮边）。
func _in_yard(c: Vector2i) -> bool:
	return c.x >= YARD_FROM.x and c.x <= YARD_TO.x \
		and c.y >= YARD_FROM.y and c.y <= YARD_TO.y

# 把地图外一律当成「还是水」（海一直延伸出去，只是不画了）
func _is_water_like(c: Vector2i) -> bool:
	if not _in_yard(c):
		return true
	return _water_set.has(c)

# e51: 地图最外圈（四邻里有落在地图外的格）。地图外不出水面、也没有水碰撞，
# 所以这一圈永远不放人下水（见 is_swim_water）—— 拼起来正好是封闭的一圈。
func _at_map_edge(c: Vector2i) -> bool:
	return not (_in_yard(c + Vector2i(1, 0)) and _in_yard(c + Vector2i(-1, 0)) \
		and _in_yard(c + Vector2i(0, 1)) and _in_yard(c + Vector2i(0, -1)))

# 生成水面图集：横轴 = 深浅档，纵轴 = 波纹变体
func _make_water_tileset(tsz: Vector2i) -> TileSet:
	var img := Image.create_empty(
		WATER_DEPTHS.size() * tsz.x, WATER_VARIANTS * tsz.y, false, Image.FORMAT_RGBA8)
	for d in WATER_DEPTHS.size():
		for v in WATER_VARIANTS:
			_draw_water_tile(img, d * tsz.x, v * tsz.y, d, v, tsz)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(img)
	for d in WATER_DEPTHS.size():
		for v in WATER_VARIANTS:
			atlas.create_tile(Vector2i(d, v))
	var ts := TileSet.new()
	ts.tile_size = tsz
	ts.add_source(atlas, WATER_SRC)
	return ts

# 一格水：底色是该深浅档的基色，内部画几道轻微的波纹；
# 四周 WATER_EDGE 像素保持纯基色 —— 这是「拼起来看不出接缝」的关键。
func _draw_water_tile(img: Image, ox: int, oy: int, depth: int, variant: int, tsz: Vector2i) -> void:
	var base: Color = WATER_DEPTHS[depth]
	for y in tsz.y:
		for x in tsz.x:
			img.set_pixel(ox + x, oy + y, base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717 + depth * 31 + variant * 101
	var inner_x: int = tsz.x - WATER_EDGE * 2
	var inner_y: int = tsz.y - WATER_EDGE * 2
	if inner_x <= 2 or inner_y <= 2:
		return
	for _i in 3:
		var x0: int = WATER_EDGE + rng.randi() % maxi(inner_x - 3, 1)
		var y0: int = WATER_EDGE + rng.randi() % inner_y
		var ln: int = 3 + rng.randi() % 4
		var up: bool = rng.randf() < 0.5
		for k in ln:
			var px: int = x0 + k
			if px >= tsz.x - WATER_EDGE:
				break
			var col: Color = base.lightened(WATER_RIPPLE) if up else base.darkened(WATER_RIPPLE)
			img.set_pixel(ox + px, oy + y0, col)

# ---------------- 桥（用美术素材，不再程序化画木板）----------------
# 素材：`Objects/Exterior/Deep Forest/Bridge.png`，80x256，竖着排了 4 种配色，
#       每种 80x64。桥是「横向」的：上下各一条护栏（带立柱），中间是红木桥面。
#
# 实测这个素材的像素结构（别再猜）：
#   · 真正有内容的是每种配色里的 x=9..69 / y=4..54（61x51），四周是透明留白
#   · 护栏立柱在 x = 9-13 / 29-33 / 45-49 / 65-69（间距 16~20 不等，**不是等距的**）
#     → 所以它**不能当 tileset 平铺**。做法改成：取左收口 + 中间一跨重复 + 右收口
#       拼到目标宽度，最后整体 resize 到精确像素（差异 <8%，像素风看不出来）
const BRIDGE_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Deep Forest/Bridge.png"
const BRIDGE_VARIANT := 0                                  # 第 0 种配色：棕木 + 米色护栏，最搭
const BRIDGE_TRIM := Rect2i(9, 4, 61, 51)                  # 那块贴图在 80x64 里的实际范围
const BRIDGE_CAP_W := 21                                   # 左右收口宽度
const BRIDGE_BAY_W := 21                                   # 中间可重复的一跨宽度
const BRIDGE_H_TILES := 3      # 桥贴图在竖直方向铺 3 格 (侧视整贴, 三行桥带全可走)

var _bridge_piece_img: Image = null    # 缓存：裁好的那一块桥贴图

func _build_bridges() -> void:
	var node := Node2D.new()
	node.name = "Bridges"
	node.position = grid_layer.position
	add_child(node)
	move_child(node, shore_layer.get_index() + 1)   # 桥在水面/岸线之上、角色之下

	for y in BRIDGE_ROWS:
		var x0 := _bridge_x0(y)
		var x1 := _bridge_x1(y)
		var w: int = x1 - x0 + 1
		var tex := _make_bridge_texture(w * 16, BRIDGE_H_TILES * 16)
		if tex == null:
			continue
		# f3 修: 素材是纯侧视图, 上一版按俯视拆成「护栏/桥面」四层还砌了隐形墙,
		#      结果桥只许走一行 + 侧视板壁被切成两条假护栏 (贴图错误)。
		#      改回扁平单层: 每桥一张整贴, 永远压在角色下面 (z=Z_BRIDGE, 不 y-sort),
		#      三行桥带全可走 (水碰撞豁口见 _build_water_collision, 桥墙已拆)。
		var sp := Sprite2D.new()
		sp.name = "Bridge%d" % y
		sp.texture = tex
		sp.centered = false
		sp.position = Vector2(x0 * 16, (y - 1) * 16)   # 盖住 y-1..y+1 三行
		sp.z_index = Z_BRIDGE
		node.add_child(sp)
		# h2: 前层护栏 —— 桥贴图最下 16px (南护栏带) 再叠一张同纹理的 region sprite,
		#     z 抬到 +1 (压过角色 y_sort 池的 0 层): 走在下桥带 (y+1) 的角色就在
		#     护栏后面, 被 h3 挖出栏杆孔的前层护栏半遮半露。上/中桥带的角色不与
		#     这条带重叠, 不受影响。
		var rf := Sprite2D.new()
		rf.name = "BridgeFront%d" % y
		rf.texture = tex
		rf.centered = false
		rf.region_enabled = true
		rf.region_rect = Rect2(0, (BRIDGE_H_TILES - 1) * 16, w * 16, 16)
		rf.position = Vector2(x0 * 16, (y + 1) * 16)
		rf.z_index = 1
		node.add_child(rf)

	print("[桥] 架了 %d 座(行 %s),每座跨 %d 格,扁平单层贴桥面(z=%d),三行桥带全可走" % [BRIDGE_ROWS.size(), str(BRIDGE_ROWS), 2 * BRIDGE_HALF + 1, Z_BRIDGE])

# 裁出素材里的那一块桥（去掉四周透明留白），缓存起来
func _bridge_piece() -> Image:
	if _bridge_piece_img != null:
		return _bridge_piece_img
	var tex: Texture2D = SoftRes.tex(BRIDGE_SHEET)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var cell := Rect2i(0, BRIDGE_VARIANT * 64, 80, 64)
	_bridge_piece_img = img.get_region(Rect2i(cell.position + BRIDGE_TRIM.position, BRIDGE_TRIM.size))
	# h3: 下护栏带 (y=41..50) 素材是一整块实心护板, 玩家被它挡住就彻底看不见了。
	#     按上护栏的镜像结构挖出柱间竖缝 (保留 y=42..46 横梁和四根立柱, 清掉
	#     y=41 与 y=47..50 的柱间区), 变成一样的镂空栏杆 —— 走在下桥带的角色
	#     透过栏杆孔看得见 (上护栏素材自带镂空, 不用动)。挖在 piece 上, 拼装
	#     和缩放自动带着孔走。
	for gap in [Vector2i(5, 19), Vector2i(25, 35), Vector2i(41, 55)]:
		for gy in [41, 47, 48, 49, 50]:
			for gx in range(gap.x, gap.y + 1):
				_bridge_piece_img.set_pixel(gx, gy, Color(0, 0, 0, 0))
	# j7: 素材是纯侧视图, 底部 y=47..50 是支撑柱脚 —— 扁平铺在俯视地图上,
	#     柱脚悬空看着像桥下面的多余贴图。清掉全宽柱脚, 桥体止于下护栏
	#     横梁 (y=46), 再把 piece 裁到 47 高, 拼装时 47->48 正好填满。
	for gy in range(47, 51):
		for gx in range(0, _bridge_piece_img.get_width()):
			_bridge_piece_img.set_pixel(gx, gy, Color(0, 0, 0, 0))
	_bridge_piece_img = _bridge_piece_img.get_region(Rect2i(0, 0, _bridge_piece_img.get_width(), 47))
	return _bridge_piece_img

# 拼一张桥：左收口 + 中间若干跨 + 右收口，最后缩放到目标尺寸
func _make_bridge_texture(target_w: int, target_h: int) -> ImageTexture:
	var piece := _bridge_piece()
	if piece == null:
		return null
	var src_h := piece.get_height()
	var full_w := piece.get_width()
	var cap: int = mini(BRIDGE_CAP_W, full_w / 2)
	var bay: int = mini(BRIDGE_BAY_W, full_w - cap * 2)

	var out := Image.create_empty(target_w, src_h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))

	# j7: piece 素材 x=20 / x=40 两列是整高的分段描边线, 收口各裁掉一列
	#     (cw = cap - 1), 中段只取 src 21..39 无描边区, 桥面就不会再出现黑竖缝。
	var cw: int = cap - 1
	# 左收口 (src 0..19)
	out.blit_rect(piece, Rect2i(0, 0, cw, src_h), Vector2i.ZERO)
	# 中间：一跨一跨重复铺满 (每跨最多 19 宽, 避开描边线)
	var x := cw
	while x < target_w - cw and bay > 0:
		var w: int = mini(bay, target_w - cw - x)
		out.blit_rect(piece, Rect2i(cap, 0, w, src_h), Vector2i(x, 0))
		x += w
	# 右收口 (src 41..60, 落在 target_w - cw 起)
	out.blit_rect(piece, Rect2i(full_w - cap + 1, 0, cw, src_h), Vector2i(target_w - cw, 0))

	# 缩放到精确尺寸（宽度本来就是准的，主要压一下高度 47 -> 48）
	if out.get_width() != target_w or out.get_height() != target_h:
		out.resize(target_w, target_h, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(out)

# ---------------- 水碰撞 ----------------
# 把 _water_set 的水格用「贪心矩形合并」打包成一组 16px 整倍数矩形，
# 然后挂到一个 StaticBody2D + N 个 RectangleShape2D 上。
#   矩形合并：扫到水格，先往右扩到不能再扩，再往下扩到不能再扩，标记已访问。
#   不是最小矩形数（那是 NP-hard），但够紧凑（一个小岛地图能合并到几十个矩形）。
#
#   桥面 + 桥头引道那几格不算水碰撞 —— 否则玩家从桥上走会被水碰撞顶死。
#   f3: 桥带三行 (y-1/y/y+1) + 引道全豁口, 三行桥带全可走; 上一版的 BridgeWalls
#     隐形墙已拆 (桥不再只许走一行, 游泳也能正常横穿桥带)。
func _build_water_collision() -> void:
	if _water_set.is_empty():
		return
	var bridge_cells := {}
	for y in BRIDGE_ROWS:
		var x0 := _bridge_x0(y)
		var x1 := _bridge_x1(y)
		for x in range(x0 - BRIDGE_APPROACH, x1 + BRIDGE_APPROACH + 1):
			for dy in [-1, 0, 1]:                        # 桥段三行全放行（河面豁口）
				bridge_cells[Vector2i(x, y + dy)] = true
	var water_for_collide := {}
	for c in _water_set.keys():
		# e51: 桥带豁口 + 「能下水」的格子都放行 —— 桥面照旧能走, 水面能蹚能游
		#      （游泳动作见 player.gd）。只有最深那一档海格留着挡人 -> 游不出海。
		if not bridge_cells.has(c) and not is_swim_water(c):
			water_for_collide[c] = true

	var rects := _merge_water_rects(water_for_collide)
	var container := Node2D.new()
	container.name = "WaterCollision"
	container.position = grid_layer.position
	add_child(container)
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
	#     也不能从河里游进桥底下。给每座桥的视觉跨度 (x0..x1) 砌两条 4px 薄横墙,
	#     只砌在「墙外侧那一格是河面」的桥跨上 (河道会摆, 用外侧行判水比用桥行准):
	#       北墙贴上桥带行 (y-1) 顶部 4px —— 外侧格 (x, y-2) 是水才砌
	#       南墙贴下桥带行 (y+1) 底部 4px —— 外侧格 (x, y+2) 是水才砌
	#     外侧是岸的桥头不砌 (本就从岸上上下桥); 东西向过桥、沿河在 y-2/y+2 行
	#     平行游泳都不受影响; 站在桥带边上的碰撞圆跟墙只叠 ~2px, 顶多被微推。
	var rails := StaticBody2D.new()
	rails.name = "BridgeRails"
	container.add_child(rails)
	var rail_count := 0
	for y in BRIDGE_ROWS:
		var bx0: int = _bridge_x0(y)
		var bx1: int = _bridge_x1(y)
		for x in range(bx0, bx1 + 1):
			if _water_set.has(Vector2i(x, y - 2)):
				var rcn := CollisionShape2D.new()
				var shn := RectangleShape2D.new()
				shn.size = Vector2(16, 4)
				rcn.shape = shn
				rcn.position = Vector2(x * 16 + 8, (y - 1) * 16 + 2)
				rails.add_child(rcn)
				rail_count += 1
			if _water_set.has(Vector2i(x, y + 2)):
				var rcs := CollisionShape2D.new()
				var shs := RectangleShape2D.new()
				shs.size = Vector2(16, 4)
				rcs.shape = shs
				rcs.position = Vector2(x * 16 + 8, (y + 2) * 16 - 2)
				rails.add_child(rcs)
				rail_count += 1
	print("[水碰撞] %d 块矩形(共 %d 格), 桥带豁口 + 桥沿薄墙 %d 条" % [rects.size(), water_for_collide.size(), rail_count])

# 贪心矩形合并：扫到一个水格 → 横扩到最长 → 竖扩到最长 → 标记访问
func _merge_water_rects(lookup: Dictionary) -> Array:
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

# 给一个水格集合，生成顺时针外边界多边形（pixel，相对 grid_layer）。
# 经典右手法则：站在水格外边沿、沿水格边界顺时针走一圈。
# 站在角点 pos（pixel 整数格点）上，facing 是下一步要走的边方向。
# 在角点先判定能否左转：
#   左手边格子还是水 → 左转（facing = 左转后的方向），再走 16 像素
#   不是水           → 直走 16 像素后右转
# ---------------- 岸：草地 <-> 水 的过渡 ----------------
# 只在水里画浅滩是不够的 —— 草地上还是一条硬边。真正的岸得两边都收：
#   beach（陆地侧）：贴水的草地格上，朝水那侧铺一条沙色渐变
#   shore（水面侧）：贴岸的水格上，朝岸那侧铺一条由浅到深的浅滩
# 两层拼起来就是「草地 -> 沙 -> 浅水 -> 深水」，硬边藏在渐变了。
#
# 另外之前的写法有个致命 bug：它拿「草地层」判断哪边是岸，可草地铺满了整张图
# （水下也有），于是每格水都被当成四面环岸、描了一圈白边 —— 看着就是材质不连贯。
# 现在统一用 _water_set 判断。
var beach_layer: TileMapLayer    # 陆地侧沙滩（草地之上、水面之下）

func _build_beach() -> void:
	if grid_layer.tile_set == null:
		return
	var tsz := grid_layer.tile_set.tile_size
	# 生成陆地侧沙滩：
	#   (i, 0) i=0..15  透明底渐变带（草地格朝水侧的湿沙）
	#   (i, 1) i=0..15  实心沙底 + 朝水湿沙带（沙滩格贴水的一侧）
	#   (16,1)/(17,1)   纯沙两种变体（沙滩内格：一种带杂点）
	#   (i, 2) i=0..15  实心沙底 + 朝草地淡出带（沙滩和草地的交界）
	#   (i, 3) i=0..15  透明底 + 朝沙侧的沙色淡入带（贴沙的草地格, 草地↔沙地的第二级过渡）
	var sheet := Image.create_empty(18 * tsz.x, 4 * tsz.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in 16:
		_draw_band_tile(sheet, i * tsz.x, 0, i, tsz, BEACH_BAND)
	for i in 16:
		_fill_sand_tile(sheet, i * tsz.x, tsz.y, tsz, i)   # 先铺沙底
		_draw_band_tile(sheet, i * tsz.x, tsz.y, i, tsz, BEACH_BAND)
	for v in 2:
		_fill_sand_tile(sheet, (16 + v) * tsz.x, tsz.y, tsz, -1, v)
	for i in 16:
		_fill_sand_tile(sheet, i * tsz.x, 2 * tsz.y, tsz, i)
		_draw_band_tile(sheet, i * tsz.x, 2 * tsz.y, i, tsz, SAND_FADE)
	for i in 16:
		_draw_band_tile(sheet, i * tsz.x, 3 * tsz.y, i, tsz, SAND_FADE)

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
	ts.add_source(atlas, BEACH_SRC)

	beach_layer = TileMapLayer.new()
	beach_layer.name = "BeachTileMapLayer"
	beach_layer.tile_set = ts
	beach_layer.position = grid_layer.position
	add_child(beach_layer)
	move_child(beach_layer, water_layer.get_index())   # 插到水面之前

	var painted := 0
	for c in _land_set.keys():
		if _sand_set.has(c):
			var wmask := _edge_mask(c, false)          # 哪几边挨着水
			if wmask != 0:
				beach_layer.set_cell(c, BEACH_SRC, Vector2i(wmask, 1))
			elif _sand_grass_mask(c) != 0:
				beach_layer.set_cell(c, BEACH_SRC, Vector2i(_sand_grass_mask(c), 2))
			else:
				beach_layer.set_cell(c, BEACH_SRC, Vector2i(16 + _hash2(c) % 2, 1))
			painted += 1
			continue
		var idx := _edge_mask(c, false)          # 哪几边挨着水
		if idx != 0:
			beach_layer.set_cell(c, BEACH_SRC, Vector2i(idx, 0))
			painted += 1
			continue
		var gmask := _grass_sand_mask(c)         # 哪几边挨着沙地
		if gmask != 0:
			beach_layer.set_cell(c, BEACH_SRC, Vector2i(gmask, 3))
			painted += 1
	print("[岸] 陆地侧沙滩 %d 格(其中沙地 %d 格)" % [painted, _sand_set.size()])

# 铺一块实心沙底：variant=-1 无杂点；variant>=0 撒几个杂点/亮点
# idx>=0 时朝掩码方向先空出湿沙带再铺沙（给 band 让位，免得盖住渐变）——简化：直接整格铺，
# band 会用 alpha 混合叠上去（_blend_px），湿沙色不透明度高，盖得住。
func _fill_sand_tile(sheet: Image, ox: int, oy: int, tsz: Vector2i, idx: int, variant: int = -1) -> void:
	for y in tsz.y:
		for x in tsz.x:
			sheet.set_pixel(ox + x, oy + y, SAND_BASE)
	if variant < 0:
		return
	# 杂点：固定 pattern（不随格子变，同一变体看起来一致）
	var dots := [Vector2i(3, 4), Vector2i(11, 2), Vector2i(6, 12), Vector2i(13, 9), Vector2i(2, 9)]
	var lites := [Vector2i(9, 6), Vector2i(4, 14), Vector2i(14, 13)]
	for d in dots:
		sheet.set_pixel(ox + d.x, oy + d.y, SAND_DOT)
	for l in lites:
		sheet.set_pixel(ox + l.x, oy + l.y, SAND_LITE)

# 沙滩格四周哪些方向挨着「非沙滩的陆地」（要画朝草地的淡出带）
func _sand_grass_mask(c: Vector2i) -> int:
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		var nb: Vector2i = c + dirs[i]
		if not _in_yard(nb):
			continue
		if _land_set.has(nb) and not _sand_set.has(nb):
			idx |= bits[i]
	return idx

# 草地格四周哪些方向挨着沙地（要画朝沙侧的淡入带, 与 _sand_grass_mask 互为镜像）
func _grass_sand_mask(c: Vector2i) -> int:
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		if _sand_set.has(c + dirs[i]):
			idx |= bits[i]
	return idx

func _build_shore() -> void:
	if grid_layer.tile_set == null:
		return
	var tsz := grid_layer.tile_set.tile_size
	if _water_set.is_empty():
		return

	# 16 格岸线并排拼成一张 16x1 的小图集，图块号 = 那一边挨着陆地（1上 2下 4左 8右）
	var sheet := Image.create_empty(16 * tsz.x, tsz.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in 16:
		_draw_band_tile(sheet, i * tsz.x, 0, i, tsz, SHORE_BANDS)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(sheet)
	for i in 16:
		atlas.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = tsz
	ts.add_source(atlas, SHORE_SRC)

	shore_layer = TileMapLayer.new()
	shore_layer.name = "ShoreTileMapLayer"
	shore_layer.tile_set = ts
	shore_layer.position = grid_layer.position
	add_child(shore_layer)
	move_child(shore_layer, water_layer.get_index() + 1)   # 水面之上

	var painted := 0
	for c in _water_set.keys():
		var idx := _edge_mask(c, true)           # 哪几边挨着陆地
		if idx == 0:
			continue                             # 四面都是水：纯深水，不用画
		shore_layer.set_cell(c, SHORE_SRC, Vector2i(idx, 0))
		painted += 1
	print("[岸] 水面 %d 格,其中 %d 格贴到岸边(浅滩)" % [_water_set.size(), painted])

# 岸边白浪：独立一层（scene/waves_layer.gd），要排在浅滩层之后 add_child 才盖得住浅滩
func _build_waves() -> void:
	var waves: Node2D = preload("res://scene/waves_layer.gd").new()
	waves.name = "WavesLayer"
	add_child(waves)
	waves.setup(self)

# 唯美氛围（王国新大陆观感）：全屏后处理滤镜。萤火虫/光尘粒子层已整体删除
# （多次调渐隐玩家仍见白点，直接消去）。滤镜垫在 HUD 第 0 位 —— 只调世界画面，
# 背包/商店等面板和文字画在它上面保持干净。
func _build_fx() -> void:
	var rect := ColorRect.new()
	rect.name = "PostFX"
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scene/fx_post.gdshader")
	rect.material = mat
	_post_mat = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(rect)
	hud.move_child(rect, 0)
	# ❗preset 必须进树后再铺: add_child 前铺会把尺寸按当时视口(设计高 648)定死,
	#   窗口比 16:9 高 (expand 拉高视口) 时 Rect 不跟着长 → 底部露一条没滤镜的亮带
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(func() -> void:
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT))
	# 天气粒子（雨/雪/风暴）+ 雷电白闪：垫在 PostFX 之上、面板之下，只闪世界画面
	var rain := preload("res://scene/rain_fx.gd").new()
	rain.name = "RainFX"
	add_child(rain)
	rain.thunder.connect(_on_thunder)
	# 季节氛围粒子（秋落叶；冬晴轻雪已删——晴天白点看不懂）
	var season := preload("res://scene/season_fx.gd").new()
	season.name = "SeasonFX"
	add_child(season)
	# D1 环境音层: 海浪/风/鸟鸣(夜里·冬天·风暴出风, 晴朗白天有鸟)
	var amb := preload("res://scene/ambience_fx.gd").new()
	amb.name = "AmbienceFX"
	add_child(amb)
	# 天上的半透明白云：几块长方形拼一朵，整层慢飘、跟着缩放走（云是氛围不糊地图）
	var clouds := preload("res://scene/cloud_layer.gd").new()
	clouds.name = "CloudLayer"
	add_child(clouds)
	# e33e 雨天地面涟漪：雨点砸地的一圈圈小扩散（风暴更密）, 垫在实体下面
	var ripples := preload("res://scene/rain_ripples.gd").new()
	ripples.name = "RainRipples"
	ripples.z_index = -1
	add_child(ripples)
	# 雨雾层：流动的半透明雾，雨天蒙上来压出空气感（云 20 与雨丝 60 之间）
	var fog := preload("res://scene/fog_layer.gd").new()
	fog.name = "FogLayer"
	add_child(fog)
	# 换季飘提示（advance_day 进位时发，此时新季第一天的结算还没跑）
	TimeManager.season_changed.connect(_on_season_changed)

# 换季：飘一句进入新季的提示 + 把地表换成当季那套贴图（e52）
func _on_season_changed(s: int) -> void:
	_apply_season_terrain()
	if player == null:
		return
	player._flash("新的一季来了 -- 进入%s季" % TimeManager.SEASONS[s])
	# 入冬：这时节地里只剩耐寒的甜菜，提醒一句（e52: 冬季作物只有甜菜, 文案跟着改）
	if s == 3:
		player._flash("冬天只有甜菜能种 -- 秋天的作物快收吧")

# 风暴滚雷：HUD 白闪一瞬 + 雷声（跟 PostFX 一个层级，面板不被闪到）
func _on_thunder() -> void:
	Audio.play_sfx("thunder")
	shake_screen(2.5, 0.4)   # e33d 雷击震屏
	var flash: ColorRect = hud.get_node_or_null("ThunderFlash")
	if flash == null:
		flash = ColorRect.new()
		flash.name = "ThunderFlash"
		flash.color = Color(1, 1, 1, 0)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(flash)
		hud.move_child(flash, 1)
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.28, 0.06)
	tw.tween_property(flash, "color:a", 0.0, 0.35)

# 某格四周的方位掩码。want_land=true 时统计「邻居是陆地」的方向，false 统计「邻居是水」。
# 地图外不算陆地（否则地图边界会被当成岸、描一圈假的浅滩）。
func _edge_mask(c: Vector2i, want_land: bool) -> int:
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		var nb: Vector2i = c + dirs[i]
		if not _in_yard(nb):
			continue                 # 地图外：既不算陆地也不算水，不要在那边描过渡
		var nb_land: bool = not _water_set.has(nb)
		if nb_land == want_land:
			idx |= bits[i]
	return idx

# 画第 idx 号渐变图块（左上角在 ox,oy）：朝掩码指定的那几条边铺 bands 色带
func _draw_band_tile(sheet: Image, ox: int, oy: int, idx: int, tsz: Vector2i, bands: Array) -> void:
	var w := tsz.x
	var h := tsz.y
	if idx & 1:                                # 上边 -> 从第 0 行往下
		for d in bands.size():
			for x in w:
				_blend_px(sheet, ox + x, oy + d, bands[d])
	if idx & 2:                                # 下边
		for d in bands.size():
			for x in w:
				_blend_px(sheet, ox + x, oy + h - 1 - d, bands[d])
	if idx & 4:                                # 左边
		for d in bands.size():
			for y in h:
				_blend_px(sheet, ox + d, oy + y, bands[d])
	if idx & 8:                                # 右边
		for d in bands.size():
			for y in h:
				_blend_px(sheet, ox + w - 1 - d, oy + y, bands[d])

# 把 col 叠到 (x,y) 上（正常的 alpha 混合，因为同一条边可能被两边各画一次）
func _blend_px(img: Image, x: int, y: int, col: Color) -> void:
	var old := img.get_pixel(x, y)
	var a := col.a + old.a * (1.0 - col.a)
	if a <= 0.0:
		img.set_pixel(x, y, Color(0, 0, 0, 0))
		return
	var rgb := (Vector3(col.r, col.g, col.b) * col.a
		+ Vector3(old.r, old.g, old.b) * old.a * (1.0 - col.a)) / a
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, a))

# ---------------- 草地上的花草点缀 ----------------
# 遍历每一格草地，按概率撒草丛 / 小花 / 蘑菇。
# 跳过水面（池塘）和耕地 —— 田里长草会很怪。
func _build_decor() -> void:
	var tex: Texture2D = SoftRes.tex(PROP_SHEET)
	if tex == null or grid_layer.tile_set == null:
		return
	var grass_cells := grid_layer.get_used_cells()
	if grass_cells.is_empty():
		return

	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	var palette: Array = []
	palette.append_array(DECOR_MUSHROOM)
	palette.append_array(DECOR_FLOWER)
	palette.append_array(DECOR_TUFT)
	for t in palette:
		if not atlas.has_tile(t):
			atlas.create_tile(t)
	var ts := TileSet.new()
	ts.tile_size = grid_layer.tile_set.tile_size
	ts.add_source(atlas, DECOR_SRC)

	decor_layer = TileMapLayer.new()
	decor_layer.name = "DecorTileMapLayer"
	decor_layer.tile_set = ts
	decor_layer.position = grid_layer.position
	add_child(decor_layer)
	move_child(decor_layer, grid_layer.get_index() + 1)     # 草地之上、耕地之下

	var rng := RandomNumberGenerator.new()
	rng.seed = DECOR_SEED
	# 低频噪声：这一步是「好看」的关键 —— 均匀撒出来像花毯，有了疏密才像野地
	var noise := FastNoiseLite.new()
	noise.seed = DECOR_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = DECOR_NOISE_FREQ
	# 花圃噪声：更低频的一层, 高值区整片是花（花海）, 低值区几乎只有草丛
	var field_noise := FastNoiseLite.new()
	field_noise.seed = DECOR_SEED + 7
	field_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	field_noise.frequency = DECOR_FIELD_FREQ
	var placed := 0
	var n_mushroom := 0
	var n_flower := 0
	var n_tuft := 0
	for c in grass_cells:
		if water_layer.get_cell_source_id(c) != -1:
			continue
		if beach_layer != null and beach_layer.get_cell_source_id(c) != -1:
			continue       # 沙滩是过渡带，上面不长花
		if Farm.tilled.has(c):
			continue
		var n := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5      # 0~1
		# 基础密度收紧（留白更多）; 花圃区里用花圃强度兜底, 疏密对比更强
		var density := smoothstep(0.34, 0.92, n) * DECOR_MAX_DENSITY
		var field := smoothstep(0.66, 0.90,
			(field_noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5)
		if field > 0.0:
			density = maxf(density, field * DECOR_FIELD_DENSITY)
		if rng.randf() >= density:
			continue
		# 花圃里花的占比被拉高、蘑菇近乎绝迹; 区外回归「草丛为主, 花是点缀」
		var flower_share := lerpf(DECOR_FLOWER_SHARE, 0.72, field)
		var mush_share := lerpf(DECOR_MUSHROOM_SHARE, 0.015, field)
		var tuft_band := 1.0 - (mush_share + flower_share)
		var r := rng.randf()
		var pick := Vector2i(-1, -1)
		var kind := ""
		if r < tuft_band:
			pick = DECOR_TUFT[rng.randi() % DECOR_TUFT.size()]
			kind = "草丛"
		elif r < tuft_band + flower_share:
			pick = DECOR_FLOWER[rng.randi() % DECOR_FLOWER.size()]
			kind = "花"
		else:
			pick = DECOR_MUSHROOM[rng.randi() % DECOR_MUSHROOM.size()]
			kind = "蘑菇"
		decor_layer.set_cell(c, DECOR_SRC, pick)
		placed += 1
		match kind:
			"蘑菇": n_mushroom += 1
			"花": n_flower += 1
			"草丛": n_tuft += 1
	print("[点缀] 草地 %d 格里撒了 %d 处(约 %.0f%%):草丛 %d / 花 %d / 蘑菇 %d"
		% [grass_cells.size(), placed, 100.0 * placed / grass_cells.size(), n_tuft, n_flower, n_mushroom])

# ---------------- 草地小动物（鸽子 / 蝴蝶，e29e） ----------------
# 素材包盘点的产出：鸽子在草地上啄食溜达、玩家靠近惊飞；蝴蝶绕着花丛飘。
# 撒点沿用花草的固定种子 —— 每次开局小动物待在同一片草地。
func _build_critters() -> void:
	var critters: Node2D = preload("res://scene/critters.gd").new()
	critters.name = "Critters"
	add_child(critters)

	var rng := RandomNumberGenerator.new()
	rng.seed = CRITTER_SEED
	var grass_cells := grid_layer.get_used_cells()

	# 鸽子落点：开阔草地（避开水 / 沙 / 田 / 桥 / 树 / 出生点附近）
	var pigeon_cells: Array = []
	for c in grass_cells:
		if water_layer.get_cell_source_id(c) != -1:
			continue
		if beach_layer != null and beach_layer.get_cell_source_id(c) != -1:
			continue
		if Farm.tilled.has(c) or is_bridge_cell(c):
			continue
		if Trees.trees.has(c) or not _land_set.has(c):
			continue
		if maxi(absi(c.x - SPAWN_CELL.x), absi(c.y - SPAWN_CELL.y)) < 6:
			continue      # 别把鸽子撒在出生点旁边，开局落地就吓飞太滑稽
		pigeon_cells.append(c)

	# 蝴蝶锚点：优先 decor 层里真撒了花的格子；不够就补随机开阔草地
	var flower_set := {}
	for f in DECOR_FLOWER:
		flower_set[f] = true
	var flower_cells: Array = []
	if decor_layer != null:
		for c in decor_layer.get_used_cells():
			if flower_set.has(decor_layer.get_cell_atlas_coords(c)):
				flower_cells.append(c)
	var n_real_flower := flower_cells.size()
	while flower_cells.size() < 10 and not pigeon_cells.is_empty():
		flower_cells.append(pigeon_cells[rng.randi() % pigeon_cells.size()])

	# 格子 -> game 根局部坐标（与树同一套换算，见 _cell_tree_pos）
	var pigeon_spots: Array = []
	for c in pigeon_cells:
		pigeon_spots.append(grid_layer.position + Vector2(c.x * 16 + 8, c.y * 16 + 8))
	var fly_spots: Array = []
	for c in flower_cells:
		fly_spots.append(grid_layer.position + Vector2(c.x * 16 + 8, c.y * 16 + 8))
	# e34c: 给鸽子避水用 —— 输入 game 根局部坐标, 查那一格是不是水（海/河/池塘）
	critters.setup(player, pigeon_spots, fly_spots,
		func(w: Vector2) -> bool: return is_water(_world_to_cell(w)))
	print("[小动物] 鸽子落点 %d 处 / 蝴蝶锚点 %d 处（花 %d + 草补 %d）"
		% [pigeon_spots.size(), fly_spots.size(), n_real_flower, fly_spots.size() - n_real_flower])

# ---------------- 背包 / 交易面板 ----------------
func _setup_backpack() -> void:
	var bp := preload("res://backpack_ui.gd").new()
	bp.name = "Backpack"
	hud.add_child(bp)
	backpack_panel = bp
	bp.opened.connect(func():
		_set_player_frozen(true))
	bp.closed.connect(func():
		_set_player_frozen(false))
	# e13j: 任务栏搬进背包「任务」页签, 不再随背包开合在屏幕左侧亮起/收起

# 任务栏：e13j 起作为背包「任务」页签存在（屏幕左侧竖栏退役, 实例不再挂 HUD）
func _setup_quest_log() -> void:
	pass

# 时钟动画（上床跳时间时播）：挂在 HUD 上，house.gd 通过 group 找到它
func _setup_clock_ui() -> void:
	var clock := preload("res://clock_ui.gd").new()
	clock.name = "ClockAnim"
	hud.add_child(clock)

# ---------------- d4: 婚后 HUD 反馈 ----------------
# 结婚后 ClockPanel 下面亮一枚「婚戒徽章」：金框头像 + 妻子名 + 呼吸闪光的戒指。
# 未婚隐藏；婚礼那天 Marriage.changed 一响自动亮出来。悬停能看婚后加成。
var _wedding_badge: Control = null

func _setup_wedding_badge() -> void:
	var badge := PanelContainer.new()
	badge.name = "WeddingBadge"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.88)
	sb.border_color = Color(0.85, 0.66, 0.28)      # 金框
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	badge.add_theme_stylebox_override("panel", sb)
	# 跟 ClockPanel 同一列（顶右），垫在它正下方
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -198.0
	badge.offset_right = -16.0
	badge.offset_top = 166.0
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 7)
	badge.add_child(row)
	var pv := TextureRect.new()
	pv.name = "WifePortrait"
	pv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv.custom_minimum_size = Vector2(40, 40)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pv)
	var lb := Label.new()
	lb.name = "WifeName"
	lb.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	lb.add_theme_font_size_override("font_size", 14)
	lb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lb)
	var ring := TextureRect.new()
	ring.name = "RingIcon"
	ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ring.custom_minimum_size = Vector2(20, 20)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring_item: Resource = load("res://item/ring.tres")
	if ring_item != null:
		ring.texture = ring_item.get("icon")
	row.add_child(ring)
	# 戒指呼吸闪光：暖金一亮一收，循环
	var tw := badge.create_tween().set_loops()
	tw.tween_property(ring, "modulate", Color(1.5, 1.28, 0.7), 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	badge.visible = false
	hud.add_child(badge)
	_wedding_badge = badge
	_refresh_wedding_badge()
	Marriage.changed.connect(_refresh_wedding_badge)

func _refresh_wedding_badge() -> void:
	if _wedding_badge == null:
		return
	if Marriage.wife_id == "" or not Marriage.BRIDES.has(Marriage.wife_id):
		_wedding_badge.visible = false
		return
	_wedding_badge.visible = true
	var idx := int(String(Marriage.wife_id).trim_prefix("rq_"))
	var pv: TextureRect = _wedding_badge.get_node("Row/WifePortrait")
	pv.texture = load("res://resources/texture/portraits/slave_%02d.png" % idx)
	var lb: Label = _wedding_badge.get_node("Row/WifeName")
	lb.text = Marriage.wife_name()
	var perk: Dictionary = Marriage.perk()
	_wedding_badge.tooltip_text = "婚后加成: " + String(perk.get("desc", ""))

# 睡觉选择菜单（床边按 F 弹出）：挂在 HUD 上，由 house.gd 打开，
# 开/关时锁住角色 + 暂停时间（暂停栈在菜单自己那里推/弹）
func _setup_sleep_menu() -> void:
	var sm := preload("res://sleep_menu_ui.gd").new()
	sm.name = "SleepMenu"
	hud.add_child(sm)
	sm.opened.connect(func(): _set_player_frozen(true))
	sm.closed.connect(func(): _set_player_frozen(false))

# 商人的交易面板（跟背包一样挂在 HUD 上，由 merchant.gd 按 F 打开）
func _setup_shop() -> void:
	var sp := preload("res://shop_ui.gd").new()
	sp.name = "Shop"
	hud.add_child(sp)
	shop_panel = sp
	sp.opened.connect(func():
		# 开交易面板时先把背包/售卖箱收起来，别几个面板叠在一起
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		if bin_panel != null and bin_panel.is_open():
			bin_panel.close_panel()
		_set_player_frozen(true))
	sp.closed.connect(func(): _set_player_frozen(false))

# 鸡舍管理面板（e30p）：挂在 HUD 上，对鸡舍按 F 打开 —— 收蛋/买鸡/卖鸡/扩建都在里面办。
func _setup_coop_panel() -> void:
	var cp := preload("res://scene/coop_panel.gd").new()
	cp.name = "CoopPanel"
	hud.add_child(cp)
	coop_panel = cp
	cp.opened.connect(func():
		# 开鸡舍面板时先把别的面板收起来，别几个叠在一起
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		if shop_panel != null and shop_panel.is_open():
			shop_panel.close_panel()
		_set_player_frozen(true))
	cp.closed.connect(func(): _set_player_frozen(false))

# e45 储物箱面板：挂在 HUD 上，对储物箱按 F 打开 —— 左右两栏存取, 不结算只腾背包。
func _setup_chest_panel() -> void:
	var cp := preload("res://chest_ui.gd").new()
	cp.name = "ChestPanel"
	hud.add_child(cp)
	chest_panel = cp
	cp.opened.connect(func():
		# 开箱子时先把别的面板收起来，别几个叠在一起
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		if coop_panel != null and coop_panel.is_open():
			coop_panel.close_panel()
		_set_player_frozen(true))
	cp.closed.connect(func(): _set_player_frozen(false))

# 售卖箱面板：挂在 HUD 上，由 shipping_bin.gd 按 F 打开（点背包格放货，隔天卖）。
func _setup_bin_panel() -> void:
	var bp := preload("res://bin_ui.gd").new()
	bp.name = "BinPanel"
	hud.add_child(bp)
	bin_panel = bp
	bp.opened.connect(func():
		# 开售卖箱时先把背包收起来，别两个面板叠在一起
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		_set_player_frozen(true))
	bp.closed.connect(func(): _set_player_frozen(false))

# 对话面板：挂在 HUD 上，由 slave_npc 按 F 触发。
# 开/关都锁住角色；开的时候会把背包和交易面板顺手收掉。
func _setup_dialogue() -> void:
	var dp := preload("res://dialogue_ui.gd").new()
	dp.name = "Dialogue"
	hud.add_child(dp)
	dialogue_panel = dp
	dp.opened.connect(func():
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		if shop_panel != null and shop_panel.is_open():
			shop_panel.close_panel()
		if bin_panel != null and bin_panel.is_open():
			bin_panel.close_panel()
		_set_player_frozen(true))
	dp.closed.connect(func(): _set_player_frozen(false))

# 剧情对话框：铺满下小半屏、暂停时间、像素头像+名字。
# 由 merchant（进店前置）和开局指引等剧情脚本调用 play()。
func _setup_story_dialogue() -> void:
	var sd := preload("res://story_dialogue.gd").new()
	sd.name = "StoryDialogue"
	hud.add_child(sd)
	story_dialogue_panel = sd
	sd.opened.connect(func():
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		if shop_panel != null and shop_panel.is_open():
			shop_panel.close_panel()
		if bin_panel != null and bin_panel.is_open():
			bin_panel.close_panel()
		_set_player_frozen(true))
	sd.closed.connect(func(): _set_player_frozen(false))

# ---------------- 篝火（招伙伴） ----------------
# e53 招募改纯任务制: 有候选人坐镇的日子（Recruits.visitor, 花名册窗口期）,
# 傍晚 18 点起远离建筑的草地上燃起一堆篝火, 走近按 F 搭话谈入伙。过夜就熄。
const CAMP_HOUR := 18
const CAMP_ANCHOR_DIST := 7        # 离建筑/出生点至少这么远（格）

func _setup_campfire() -> void:
	var cp := preload("res://campfire_ui.gd").new()
	cp.name = "CampfirePanel"
	hud.add_child(cp)
	campfire_panel = cp
	cp.opened.connect(func():
		if backpack_panel != null and backpack_panel.is_open():
			backpack_panel.close()
		if shop_panel != null and shop_panel.is_open():
			shop_panel.close_panel()
		_set_player_frozen(true))
	cp.closed.connect(func(): _set_player_frozen(false))
	TimeManager.time_tick.connect(_on_campfire_tick)
	TimeManager.new_day.connect(func(_d): _clear_campfire())   # 过夜就熄

func _on_campfire_tick() -> void:
	if campfire != null or _sleeping:
		return
	if TimeManager.hour < CAMP_HOUR:
		return
	if Slaves.count >= Slaves.CAP:       # 满员：今晚没有篝火
		return
	if not Recruits.visitor():           # e53: 花名册窗口开着才生火（错过等 14 天再开）
		return
	_spawn_campfire()

# 在远离建筑的草地上挑一格，把篝火摆出来
func _spawn_campfire() -> void:
	if campfire != null:      # 保险: 已经有一堆火了, 别再点第二堆
		return
	var anchors: Array = []
	for n: Node2D in [$House, $Merchant, $ShippingBin, $Player]:
		anchors.append(_world_to_cell(n.global_position))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("campfire_pos") + TimeManager.year * 100000 \
		+ TimeManager.season * 1000 + TimeManager.day * 13
	var cands: Array = []
	for c in _land_set.keys():
		if Farm.tilled.has(c) or is_bridge_cell(c) or Trees.is_blocked(c):
			continue
		var ok := true
		for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
			if not _land_set.has(nb) or is_bridge_cell(nb) or Farm.tilled.has(nb):
				ok = false
				break
		if not ok:
			continue
		for a in anchors:
			var ac: Vector2i = a
			if maxi(absi(c.x - ac.x), absi(c.y - ac.y)) < CAMP_ANCHOR_DIST:
				ok = false
				break
		if not ok:
			continue
		cands.append(c)
	if cands.is_empty():
		return
	var cell: Vector2i = cands[rng.randi() % cands.size()]
	campfire = preload("res://scene/campfire.gd").new()
	campfire.name = "Campfire"
	campfire.position = _cell_tree_pos(cell)    # 格子中心、踩在格子底边（y_sort 排序点）
	add_child(campfire)
	Audio.play_sfx("campfire", -8.0)
	# 带上方向，不然玩家只知道"远处有火"却不知道往哪走
	var dir := _dir_name(campfire.position - $Player.position)
	_announce("%s方向亮起了篝火, 走近按 F 招募伙伴" % dir, 5.0)

func _clear_campfire() -> void:
	if campfire != null:
		campfire.queue_free()
		campfire = null

# 屏幕上方居中的一条公告（篝火出现之类的事件播报），几秒后自己淡掉
func _announce(text: String, dur := 3.0) -> void:
	# 半透明黑底条 + 居中大字：光有描边的文字在草地/水面上容易糊，垫一层底才看得清
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.42)
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 104.0

	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.62))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	hud.add_child(box)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(box.queue_free)

# 终局里程碑的大庆祝（e26c）: 金边大横幅滑入 + 副标题点明沙盒不收官, 8 秒后淡出
# 只庆祝, 不做任何锁档/收官逻辑 —— 用户要求"不限制结局, 可以继续玩"
func _celebrate(text: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.05, 0.0, 0.62)
	sb.border_color = Color(1.0, 0.84, 0.35, 0.95)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 92.0

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)

	var l := Label.new()
	l.text = "* %s *" % text
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)

	var sub := Label.new()
	sub.text = "结局没有终点, 这片海随你继续闯"
	sub.add_theme_font_override("font", FONT_PIX)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 0.92))
	sub.add_theme_constant_override("outline_size", 4)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	hud.add_child(box)
	var tw := create_tween()
	box.modulate = Color(1, 1, 1, 0.0)
	box.offset_top = 68.0
	tw.tween_property(box, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(box, "offset_top", 92.0, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(8.0)
	tw.tween_property(box, "modulate:a", 0.0, 1.2)
	tw.tween_callback(box.queue_free)

# 把「篝火在玩家的哪个方向」说成人话：东南西北 / 东北、西南 这种八向说法
func _dir_name(d: Vector2) -> String:
	var ns: String = "南" if d.y > 0 else "北"      # 屏幕下方 = 南
	var ew: String = "东" if d.x > 0 else "西"
	if absf(d.x) > absf(d.y) * 2.0:
		return ew
	if absf(d.y) > absf(d.x) * 2.0:
		return ns
	return ns + ew

func _toggle_backpack() -> void:
	if backpack_panel == null:
		return
	# 交易面板/售卖箱开着的时候按 B/Esc：先关它们（不然两个面板打架）
	if shop_panel != null and shop_panel.is_open():
		shop_panel.close_panel()
		return
	if bin_panel != null and bin_panel.is_open():
		bin_panel.close_panel()
		return
	# 夜里那两张面板（结算 / 派活）正开着时，Esc 是它们的事，不该顺手把背包翻开。
	# ❗它们刚弹出来的头 0.5 秒**故意不吃输入**（防误触），所以这里必须自己再挡一道 ——
	#   不然那半秒里按 Esc 会绕过去，把背包盖在夜晚面板上面。
	if settlement_panel != null and settlement_panel.is_open():
		return
	if assign_panel != null and assign_panel.is_open():
		return
	backpack_panel.toggle()

# 打开背包时锁住角色移动和工具操作；关掉就恢复
func _set_player_frozen(frozen: bool) -> void:
	if player == null:
		return
	player.frozen = frozen

# ---------------- 木地板显示层 ----------------
# 跟 soil_layer 一个套路：Floor autoload 存数据，这里只挂个监听器把贴图画出来。
# 排在草地/田埂之上、耕地之下 —— 这样地板会盖住田埂（贴得紧），
# 但被耕地盖住（在耕地上铺地板是允许的）会被 soil_layer 盖在上面。
# ❗实际效果：**地板始终可见**，因为 Floor.place 不会被 Farm.till 触发反向刷新。
#   但玩家的「覆盖耕地」交互流程是：先铺地板（再刨地？）—— 现状是允许的但视觉上
#   地板被耕地纹理盖住。要解这个问题，最简单的是把 floor_layer 排在 soil_layer 之后。
func _build_floor_layer() -> void:
	var layer := preload("res://scene/floor_layer.gd").new()
	layer.name = "FloorLayer"
	add_child(layer)

# ---------------- 树木 ----------------
# Trees autoload 存数据，这里负责摆节点 + 砍树结算 + 掉落。
# 节点直接挂在 Game 下参与 y_sort（跟伙伴一个套路，不套容器）。
var tree_nodes := {}        # cell -> tree_node
var _falling_cells := {}    # 正在播「倒下动画」的格子：这期间的贴图更新先挂起（cell -> 待换的 stage）

# 开局撒树。固定种子 -> 每次开局树长在同样的地方，方便对照改动。
func _build_trees() -> void:
	# ❗这个函数可能被调多次（开局一次、开新档 reset 后再补一次）—— 必须幂等：
	#   旧信号连接要断掉（不然 tree_changed 发两次），旧节点要真拆掉
	#   （tree_nodes.clear() 只清字典，屏幕上的树会变成"看得见砍不着"的幽灵）。
	if Trees.tree_changed.is_connected(_on_tree_changed):
		Trees.tree_changed.disconnect(_on_tree_changed)
	if Trees.tree_removed.is_connected(_on_tree_removed):
		Trees.tree_removed.disconnect(_on_tree_removed)
	for n in tree_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	Trees.reset()
	tree_nodes.clear()
	_falling_cells.clear()
	Trees.tree_changed.connect(_on_tree_changed)
	Trees.tree_removed.connect(_on_tree_removed)

	# 建筑锚点：附近 4 格不种树。屋身有 5x7 格那么大，给它两个锚点（屋根 + 门口）。
	var anchors: Array = []
	for n: Node2D in [$House, $Merchant, $ShippingBin, $Player]:
		anchors.append(_world_to_cell(n.global_position))
	anchors.append(_world_to_cell($House.to_global(Vector2(40, -100))))
	anchors.append(_world_to_cell($House.to_global(Vector2(50, 28))))
	# ❗室内那块「屋子」在**世界坐标里是真实存在的野地**（屋下 288px 起），
	#   树要是长在那儿，进屋后会有一棵树穿墙画在房间里。整块都避开。
	var inner_from := _world_to_cell($House.global_position + Vector2(-16, 272))
	var inner_to := _world_to_cell($House.global_position + Vector2(304, 496))

	var noise := FastNoiseLite.new()
	noise.seed = TREE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = TREE_NOISE_FREQ
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED
	var placed := 0
	for c in _land_set.keys():
		if Trees.trees.size() >= TREE_MAX:
			break
		if not _tree_spot_ok(c, anchors, inner_from, inner_to):
			continue
		var nv := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
		var density: float = smoothstep(0.35, 0.9, nv) * TREE_DENSITY
		if rng.randf() >= density:
			continue
		var r := rng.randf()
		var stage := Trees.ST_MATURE
		if r < 0.12:
			stage = Trees.ST_SAPLING
		elif r < 0.32:
			stage = Trees.ST_YOUNG
		Trees.plant(c, _hash2(c + Vector2i(7, 13)) % 2, stage)
		placed += 1
	print("[树] 全岛种了 %d 棵(上限 %d)" % [placed, TREE_MAX])

# 这格能不能长树：非田、离桥远、四邻都是陆地（树冠 32 宽，悬到水里很怪）、
# 离建筑锚点 4 格开外、不压室内。
func _tree_spot_ok(c: Vector2i, anchors: Array, inner_from: Vector2i, inner_to: Vector2i) -> bool:
	if Farm.tilled.has(c) or is_bridge_cell(c):
		return false
	if _sand_set.has(c):          # 沙滩上不长树
		return false
	for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
		if not _land_set.has(nb) or is_bridge_cell(nb):
			return false
	for a in anchors:
		var ac: Vector2i = a
		if maxi(absi(c.x - ac.x), absi(c.y - ac.y)) < 4:
			return false
	if c.x >= inner_from.x and c.x <= inner_to.x and c.y >= inner_from.y and c.y <= inner_to.y:
		return false
	return true

func _on_tree_changed(c: Vector2i) -> void:
	if not Trees.trees.has(c):
		return
	var t: Dictionary = Trees.trees[c]
	if _falling_cells.has(c):
		_falling_cells[c] = int(t.stage)     # 倒下动画播完再换贴图（见 hit_tree）
		return
	var n: Node2D = tree_nodes.get(c)
	if n == null:
		n = preload("res://scene/tree_node.gd").new()
		n.name = "Tree%d_%d" % [c.x, c.y]
		n.cell = c
		n.variant = int(t.variant)
		n.position = _cell_tree_pos(c)
		add_child(n)
		tree_nodes[c] = n
	n.apply_stage(int(t.stage))

func _on_tree_removed(c: Vector2i) -> void:
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
# 都没找到就原样返回 fallback，让 hit_tree 老实报 MISS。
func pick_tree_cell(mouse_world: Vector2, fallback: Vector2i) -> Vector2i:
	# 鼠标就搁在自己身上时，"指哪砍哪"没有指向性 —— 玩家按使用键常常压根没挪鼠标。
	# 这时跳过①直接看身边那棵，免得被"头顶上悬着的那棵（别人）的树冠"截胡。
	var on_self := has_node("Player") \
		and mouse_world.distance_to($Player.global_position) < float(Farm.TILE_SIZE)

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

	var pc: Vector2i = _world_to_cell($Player.global_position)
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
func hit_tree(c: Vector2i) -> Dictionary:
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
				n2.fell_done.connect(_on_tree_fell_done)
				n2.play_fell()
				shake_screen(2.0, 0.25)   # e33d 树倒震屏
	# 科技树加成：锻铁斧 +1 / 木匠行会 +2（见 research.gd）—— 必须放在 match 之外
	var wood: int = int(res.wood)
	if wood > 0:
		wood += Research.wood_bonus()
	var seeds: int = int(res.seeds)
	if wood > 0 or seeds > 0:
		_spawn_tree_drops(c, wood, seeds)
	return res

func _on_tree_fell_done(c: Vector2i) -> void:
	_falling_cells.erase(c)
	_on_tree_changed(c)      # 补上树桩节点

func _spawn_tree_drops(c: Vector2i, wood: int, seeds: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var wood_item: ItemData = load("res://item/wood.tres")
	var seed_item: ItemData = load("res://item/tree_seed.tres")
	var base := _cell_tree_pos(c)
	for i in wood:
		_spawn_pickup(wood_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))
	for i in seeds:
		_spawn_pickup(seed_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))

# 掉落物：item_pickup.gd 没有 tscn，代码把 Area2D + 贴图 + 碰撞拼起来。
# ❗item 要在 add_child **之前**赋值 —— _ready 里就要用它设贴图。
func _spawn_pickup(item: ItemData, pos: Vector2) -> void:
	if item == null:
		return
	var pk: Area2D = preload("res://item_pickup.gd").new()
	pk.item = item
	pk.amount = 1
	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	pk.add_child(spr)
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 7.0
	cs.shape = sh
	pk.add_child(cs)
	pk.position = pos
	add_child(pk)

# ---------------- 岩石 / 铁矿露头 ----------------
# 和树一个套路：OreVein 只存数据发信号，这里摆 rock_node 显示节点、处理掉落。
# 固定种子程序化撒；镐子敲碎普通岩石掉石头、铁矿露头掉铁矿（见 ore_data.gd）。
func _build_rocks() -> void:
	# ❗这个函数可能被调多次（开局一次、开新档 reset 后再补一次）—— 必须幂等
	if OreVein.rock_changed.is_connected(_on_rock_changed):
		OreVein.rock_changed.disconnect(_on_rock_changed)
	if OreVein.rock_removed.is_connected(_on_rock_removed):
		OreVein.rock_removed.disconnect(_on_rock_removed)
	for n in rock_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	OreVein.reset()
	rock_nodes.clear()
	OreVein.rock_changed.connect(_on_rock_changed)
	OreVein.rock_removed.connect(_on_rock_removed)

	# 让位锚点：建筑附近 + 矿井 + 码头 + 屋内那块野地，都不摆石头
	var anchors: Array = []
	for n: Node2D in [$House, $Merchant, $ShippingBin, $Player]:
		anchors.append(_world_to_cell(n.global_position))
	anchors.append(mine_cell)
	anchors.append(_dock_cell())
	var inner_from := _world_to_cell($House.global_position + Vector2(-16, 272))
	var inner_to := _world_to_cell($House.global_position + Vector2(304, 496))

	var rng := RandomNumberGenerator.new()
	rng.seed = ROCK_SEED
	var placed := 0
	for c in _land_set.keys():
		if OreVein.rocks.size() >= ROCK_MAX:
			break
		if not _rock_spot_ok(c, anchors, inner_from, inner_to):
			continue
		if rng.randf() >= ROCK_DENSITY:
			continue
		var kind := OreVein.KIND_ROCK
		if rng.randf() < ROCK_IRON_RATIO:
			kind = OreVein.KIND_IRON
		OreVein.place(c, kind, _hash2(c + Vector2i(3, 11)) % 4)
		placed += 1
	print("[矿] 全岛撒了 %d 处岩石/铁矿(上限 %d)" % [placed, ROCK_MAX])

# 这格能不能摆石头：非田、没树、离锚点 3 格开外、四邻都是陆地（三石堆 22 宽会悬到邻格）。
func _rock_spot_ok(c: Vector2i, anchors: Array, inner_from: Vector2i, inner_to: Vector2i) -> bool:
	if Farm.tilled.has(c) or is_bridge_cell(c) or Trees.is_blocked(c) or OreVein.is_blocked(c):
		return false
	if _sand_set.has(c):          # 沙滩上不长石头
		return false
	for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
		if not _land_set.has(nb) or is_bridge_cell(nb):
			return false
	for a in anchors:
		var ac: Vector2i = a
		if maxi(absi(c.x - ac.x), absi(c.y - ac.y)) < 3:
			return false
	if c.x >= inner_from.x and c.x <= inner_to.x and c.y >= inner_from.y and c.y <= inner_to.y:
		return false
	return true

# ---------------- 每夜自然补植 ----------------
# 用户要求：树和石头要"较快"更新，但别长在耕田与建筑附近。
# 每天清晨（睡觉结算 advance_day 发的 new_day）随机挑空地补几棵树苗、长回几块岩石。
# 复用开局撒点的让位判定（_tree_spot_ok / _rock_spot_ok），再额外避开：
# 耕田周边两格（树冠/岩石影别压庄稼）、玩家建筑（Structures）周边、铺装（木地板/小径）。

func _respawn_nature(_day: int) -> void:
	_respawn_trees()
	_respawn_rocks()

# 补植用的锚点：建筑群 + 矿井 + 码头（跟开局撒点同一套让位规则）
func _nature_anchors() -> Array:
	var anchors: Array = []
	for n: Node2D in [$House, $Merchant, $ShippingBin, $Player]:
		anchors.append(_world_to_cell(n.global_position))
	anchors.append(mine_cell)
	anchors.append(_dock_cell())
	return anchors

# 耕田附近（含对角 radius 圈）不让野物冒出来
func _near_tilled(c: Vector2i, radius: int) -> bool:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if Farm.tilled.has(c + Vector2i(dx, dy)):
				return true
	return false

# 玩家建筑附近（Structures 占格 + 周边一圈）不让野物冒出来
func _near_structures(c: Vector2i, radius: int) -> bool:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if Structures.is_blocked(c + Vector2i(dx, dy)):
				return true
	return false

func _respawn_trees() -> void:
	if Trees.trees.size() >= TREE_MAX:
		return
	var anchors := _nature_anchors()
	var inner_from := _world_to_cell($House.global_position + Vector2(-16, 272))
	var inner_to := _world_to_cell($House.global_position + Vector2(304, 496))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var land: Array = _land_set.keys()
	if land.is_empty():
		return
	var spawned := 0
	for _try in RESPAWN_TRIES:
		if spawned >= RESPAWN_TREES_PER_DAY or Trees.trees.size() >= TREE_MAX:
			break
		var c: Vector2i = land[rng.randi() % land.size()]
		if Trees.is_blocked(c) or OreVein.is_blocked(c) or Floor.is_floored(c):
			continue
		if not _tree_spot_ok(c, anchors, inner_from, inner_to):
			continue
		if _near_tilled(c, 2) or _near_structures(c, 2):
			continue
		# 一半幼苗一半小树：小树两天就能成材，更新节奏快一点
		var stage := Trees.ST_SAPLING if rng.randf() < 0.5 else Trees.ST_YOUNG
		if Trees.plant(c, _hash2(c + Vector2i(7, 13)) % 2, stage):
			spawned += 1
	if spawned > 0:
		print("[树] 清晨补种了 %d 棵(全岛 %d)" % [spawned, Trees.trees.size()])

func _respawn_rocks() -> void:
	if OreVein.rocks.size() >= ROCK_MAX:
		return
	var anchors := _nature_anchors()
	var inner_from := _world_to_cell($House.global_position + Vector2(-16, 272))
	var inner_to := _world_to_cell($House.global_position + Vector2(304, 496))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var land: Array = _land_set.keys()
	if land.is_empty():
		return
	var spawned := 0
	for _try in RESPAWN_TRIES:
		if spawned >= RESPAWN_ROCKS_PER_DAY or OreVein.rocks.size() >= ROCK_MAX:
			break
		var c: Vector2i = land[rng.randi() % land.size()]
		if not _rock_spot_ok(c, anchors, inner_from, inner_to):
			continue
		if _near_tilled(c, 1) or _near_structures(c, 1):
			continue
		var kind := OreVein.KIND_ROCK
		if rng.randf() < ROCK_IRON_RATIO:
			kind = OreVein.KIND_IRON
		if OreVein.place(c, kind, _hash2(c + Vector2i(3, 11)) % 4):
			spawned += 1
	if spawned > 0:
		print("[矿] 清晨长回了 %d 处岩石(全岛 %d)" % [spawned, OreVein.rocks.size()])

func _on_rock_changed(c: Vector2i) -> void:
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
		n.position = _cell_tree_pos(c)   # 跟树一样：底部踩在格子底边（y_sort 排序点）
		add_child(n)
		rock_nodes[c] = n

func _on_rock_removed(c: Vector2i) -> void:
	var n: Node2D = rock_nodes.get(c)
	if n == null:
		return
	rock_nodes.erase(c)
	n.play_broken()      # 原地小跳 + 淡出，掉落由 hit_rock 生成

# 鼠标指的是哪块石头（player 挥镐前先问这句）。跟 pick_tree_cell 同一套退让：
# ① 按贴图矩形命中（1:1 视觉最高 22x16，留点余量好点中）② 鼠标那一格 ③ 玩家身边一圈。
func pick_rock_cell(mouse_world: Vector2, fallback: Vector2i) -> Vector2i:
	var on_self := has_node("Player") \
		and mouse_world.distance_to($Player.global_position) < float(Farm.TILE_SIZE)
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
	var pc: Vector2i = _world_to_cell($Player.global_position)
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
func hit_rock(c: Vector2i) -> Dictionary:
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
			_spawn_rock_drops(c, int(res.stone), int(res.iron))
	return res

func _spawn_rock_drops(c: Vector2i, stone: int, iron: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stone_item: ItemData = load("res://item/stone.tres")
	var iron_item: ItemData = load("res://item/iron_ore.tres")
	var base := _cell_tree_pos(c)
	for i in stone:
		_spawn_pickup(stone_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))
	for i in iron:
		_spawn_pickup(iron_item, base + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 10.0)))

# ---------------- 工作台 / 熔炉（玩家摆放的设施） ----------------
# 和岩石一个套路：Structures 只存数据发信号，这里摆 station_node 显示节点。
# 摆放/挖回在 player（手持物品点地 = 摆；手持镐子点设施 = 挖回），按 F = 点火/取铁。

func _build_stations() -> void:
	# ❗这个函数可能被调多次（开局一次、开新档 reset 后再来一次）—— 必须幂等
	if Structures.station_changed.is_connected(_on_station_changed):
		Structures.station_changed.disconnect(_on_station_changed)
	if Structures.station_removed.is_connected(_on_station_removed):
		Structures.station_removed.disconnect(_on_station_removed)
	if Structures.site_changed.is_connected(_sync_site_node):
		Structures.site_changed.disconnect(_sync_site_node)
	for n in station_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	station_nodes.clear()
	_station_hits.clear()
	Structures.station_changed.connect(_on_station_changed)
	Structures.station_removed.connect(_on_station_removed)
	Structures.site_changed.connect(_sync_site_node)
	for c in Structures.stations.keys():
		_on_station_changed(c)
	_sync_site_node()      # 读档/新档后按工地状态摆（或撤）脚手架

func _on_station_changed(c: Vector2i) -> void:
	if not Structures.stations.has(c):
		return
	var s: Dictionary = Structures.stations[c]
	var n: Node2D = station_nodes.get(c)
	if n == null:
		# 铁匠铺/水井用专属节点；工作台/熔炉还是 32x32 的小设施
		if String(s.kind) == Structures.KIND_BLACKSMITH:
			n = preload("res://scene/blacksmith_node.gd").new()
		elif String(s.kind) == Structures.KIND_WELL:
			n = preload("res://scene/well_node.gd").new()
		elif String(s.kind) == Structures.KIND_COOP:
			n = preload("res://scene/coop_node.gd").new()
		elif String(s.kind) == Structures.KIND_LAMP:
			n = preload("res://scene/lamp_node.gd").new()
		elif String(s.kind) == Structures.KIND_HUT:
			n = preload("res://scene/hut_node.gd").new()
		elif String(s.kind) == Structures.KIND_HIVE:
			n = preload("res://scene/hive_node.gd").new()
		elif String(s.kind) == Structures.KIND_CHEST:
			n = preload("res://scene/chest_node.gd").new()
		elif Structures.is_farm_kind(String(s.kind)):
			# e49 农场畜牧线（畜棚/马厩/筒仓/温室/磨坊/围栏/木桥）共用一个节点
			n = preload("res://scene/farm_building_node.gd").new()
		else:
			n = preload("res://scene/station_node.gd").new()
		n.name = "Station%d_%d" % [c.x, c.y]
		n.cell = c
		n.kind = String(s.kind)
		n.position = _cell_tree_pos(c)   # 底部踩在格子底边（y_sort 排序点）
		add_child(n)
		station_nodes[c] = n
	# 熔炼状态变化（点火/出炉）由 station_node 自己 _process 轮询 Structures，不用额外推

func _on_station_removed(c: Vector2i) -> void:
	var n: Node2D = station_nodes.get(c)
	if n == null:
		return
	station_nodes.erase(c)
	n.play_removed()      # 小跳 + 淡出；物品返还由 hit_station 生成

# 工地脚手架：Structures.site 有内容就摆在锚点格，落成/清空就撤掉
func _sync_site_node() -> void:
	if Structures.site_busy():
		var c := Vector2i(Structures.site["anchor"])
		if _site_node == null or not is_instance_valid(_site_node):
			_site_node = preload("res://scene/site_node.gd").new()
			_site_node.kind = String(Structures.site["kind"])   # 工地轮廓跟建筑类型走(e24a)
			add_child(_site_node)
		_site_node.cell = c
		_site_node.position = _cell_tree_pos(c)   # 底部踩在格子底边（y_sort 排序点）
	else:
		if _site_node != null and is_instance_valid(_site_node):
			_site_node.queue_free()
		_site_node = null

# 鼠标正指着哪一座设施（按贴图矩形命中，取最近的那座）。没指着就返回 NO_CELL。
# e44 从 pick_station_cell 里抽出来 —— 建筑模式的「悬停高亮」也要用同一套命中判定，
# 但它**不能**带 pick_station_cell 后面那两档退让（面前/身边），否则鼠标随便放哪都亮。
func _station_under_mouse(mouse_world: Vector2) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for key in station_nodes.keys():
		var n: Node2D = station_nodes[key]
		if n == null or not is_instance_valid(n):
			continue
		var base: Vector2 = n.global_position
		# 设施矩形：小设施 32x34；铁匠铺这类大房子节点自带 hit_rect
		var rect: Rect2 = n.hit_rect() if n.has_method("hit_rect") \
			else Rect2(base + Vector2(-16.0, -32.0), Vector2(32.0, 34.0))
		if not rect.has_point(mouse_world):
			continue
		var d: float = base.distance_squared_to(mouse_world)
		if d < best_d:
			best_d = d
			best = key
	return best

# 镐子指的是哪座设施（player 挥镐先问这句）。跟 pick_rock_cell 同一套退让：
# ① 按贴图矩形命中 ② 面前那格本来就是设施 ③ 玩家身边一圈。没找到就原样返回 fallback。
func pick_station_cell(mouse_world: Vector2, fallback: Vector2i) -> Vector2i:
	var hit := _station_under_mouse(mouse_world)
	if hit != NO_CELL:
		return hit
	if Structures.has_station(fallback):
		return fallback
	var pc: Vector2i = _world_to_cell(player.global_position)
	var near := fallback
	var nd := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2i = fallback + Vector2i(dx, dy)
			if not Structures.has_station(c):
				continue
			var d2: float = Vector2(c - pc).length_squared()
			if d2 < nd:
				nd = d2
				near = c
	if nd < INF:
		return near
	return fallback

# e30e: 拆建筑不再一镐子就没 —— 同一座设施累计敲满 10 下才真拆。
# 计数按格子记（会话内有效），拆掉即清；每敲一下节点小抖 + 提示进度。
const STATION_HITS_NEEDED := 10
var _station_hits := {}

# player 挥镐点设施走这里；返回 {result: 0 没设施 / 1 还在拆 / 2 拆掉了, kind}
func hit_station_once(c: Vector2i) -> Dictionary:
	if not Structures.has_station(c):
		_station_hits.erase(c)
		return {"result": 0, "kind": ""}
	var n := int(_station_hits.get(c, 0)) + 1
	if n >= STATION_HITS_NEEDED:
		_station_hits.erase(c)
		return hit_station(c)
	_station_hits[c] = n
	var node: Node2D = station_nodes.get(c)
	if node != null and is_instance_valid(node):
		var tw := create_tween()
		tw.tween_property(node, "position:x", node.position.x + 1.5, 0.04)
		tw.tween_property(node, "position:x", node.position.x, 0.06)
	if player != null:
		player._flash("拆除中 %d/%d" % [n, STATION_HITS_NEEDED])
	return {"result": 1, "kind": ""}

# 镐子拆设施（第 10 下才到这里）：熔炼到一半的木头/铁矿不返还，算打碎了。
# 铁匠铺/水井这类建筑拆掉返还木头/石头/铁（钱和人工不退）。
# 返回 {result: 2 拆掉了, kind}
func hit_station(c: Vector2i) -> Dictionary:
	if not Structures.has_station(c):
		return {"result": 0, "kind": ""}
	var n_chick := Structures.chickens_of(c)   # 先抓: remove 之后字典就没了, 再查全是 0
	var n_egg := Structures.eggs_of(c)
	var n_honey := Structures.honey_of(c)
	var n_in_chest: Array = Structures.chest_items(c).duplicate(true)   # e45 拆箱子先把货抓出来
	var n_produce: Dictionary = Structures.produce_dict(c).duplicate(true)   # e49 拆棚先把畜产抓出来
	var kind := Structures.remove(c)   # remove 里发信号 -> _on_station_removed 播动画
	match kind:
		Structures.KIND_FURNACE:
			_spawn_pickup(load("res://item/furnace.tres"), _cell_tree_pos(c))
		Structures.KIND_BLACKSMITH, Structures.KIND_WELL, Structures.KIND_COOP, \
				Structures.KIND_HUT, Structures.KIND_HIVE, Structures.KIND_CHEST, \
				Structures.KIND_BARN, Structures.KIND_STABLE, Structures.KIND_SILO, \
				Structures.KIND_GREENHOUSE, Structures.KIND_MILL, \
				Structures.KIND_FENCE, Structures.KIND_BRIDGE:
			var cost: Dictionary = Structures.building_cost(kind)
			var base := _cell_tree_pos(c)
			var spread := [Vector2(-14, -2), Vector2(0, -6), Vector2(14, -2),
				Vector2(-7, 2), Vector2(7, 4), Vector2(0, 2), Vector2(-10, 6),
				Vector2(10, -6), Vector2(-2, -8), Vector2(4, -4), Vector2(-4, 6),
				Vector2(12, 4), Vector2(-12, -6), Vector2(2, 8), Vector2(8, 8),
				Vector2(-8, -10), Vector2(16, 0), Vector2(-16, 4), Vector2(0, 10), Vector2(6, -10)]
			var si := 0
			for key in ["wood", "stone", "iron"]:
				var it: ItemData = load("res://item/%s.tres" % key)
				for _i in int(cost.get(key, 0)):
					_spawn_pickup(it, base + spread[si % spread.size()])
					si += 1
			# 鸡舍拆掉：蛋掉地上捡；鸡不走道具（e30p），转移到别的有空位的鸡舍，
			# 没地方去就只能走散了
			if kind == Structures.KIND_COOP:
				for _ei in n_egg:
					_spawn_pickup(load("res://item/egg.tres"), base + spread[si % spread.size()])
					si += 1
				for _ci in n_chick:
					if _relocate_chicken(c):
						continue
					break   # 全岛都没有空位了, 剩下的鸡走散（提示在 _relocate_chicken 里给过一次）
			# 蜂箱拆掉：箱里攒的蜜掉地上捡（蜂蜜是食物, 不返还建箱子的料以外的东西）
			if kind == Structures.KIND_HIVE:
				for _hi in n_honey:
					_spawn_pickup(load("res://item/honey.tres"), base + spread[si % spread.size()])
					si += 1
			# e45 储物箱拆掉：箱里存的东西一件不吞, 全掉地上捡回去
			if Structures.is_container_kind(kind):
				for e in n_in_chest:
					var cit: ItemData = (e as Dictionary).get("item", null)
					if cit == null:
						continue
					for _ci in int((e as Dictionary).get("count", 0)):
						_spawn_pickup(cit, base + spread[si % spread.size()])
						si += 1
			# e49 畜棚/马厩拆掉：栏里攒的畜产掉地上捡回去（牲口本身不是道具, 跟鸡不一样）
			if n_produce.size() > 0:
				for sp in n_produce:
					var pit: ItemData = load(String(Structures.animal_product_path(String(sp))))
					if pit == null:
						continue
					for _pi in int(n_produce[sp]):
						_spawn_pickup(pit, base + spread[si % spread.size()])
						si += 1
		_:
			_spawn_pickup(load("res://item/workbench.tres"), _cell_tree_pos(c))
	return {"result": 2, "kind": kind}

# F 在设施边：熔炉点火（耗 1 木头 + 1 铁矿）/ 看进度 / 取铁锭；工作台提示去背包。
# 返回 true 表示 F 被吃掉了。
#
# e36h 分两步找：先照旧扫玩家本身那 3x3 格（小设施都只占一格，够用），
#   扫不到再看「大建筑」自己的 interact_rect（鸡舍）。原因是 Structures.stations 只记
#   锚点那一格，而锚点在鸡舍最下面一行的底边 —— 玩家站在门前/两侧时，3x3 窗口够不到锚点，
#   于是必须绕到屋后按 F 才好使（玩家报的 bug）。大建筑的可交互区跟「走近浮提示」的
#   reach 区重合，改成「提示露出来就按得开」，四周任意一边都行。
func _try_station_interact() -> bool:
	if player == null:
		return false
	var pc := _world_to_cell(player.global_position)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2i = pc + Vector2i(dx, dy)
			if _station_interact_cell(c):
				return true
	var pp: Vector2 = player.global_position
	var best_c := Vector2i.ZERO
	var best_d := INF
	for key in station_nodes.keys():
		# ❗这里不能标 Node2D 类型: interact_rect() 是各设施脚本自己的方法,
		#   Node2D 的类型表里没有它, 标了类型编译期就报「找不到函数」。
		var n = station_nodes[key]
		if n == null or not is_instance_valid(n) or not n.has_method("interact_rect"):
			continue
		var rect: Rect2 = n.call("interact_rect")
		if not rect.has_point(pp):
			continue
		var d: float = n.global_position.distance_squared_to(pp)
		if d < best_d:
			best_d = d
			best_c = key
	if best_d < INF:
		return _station_interact_cell(best_c)
	return false

# e36i 左键点了设施头上的「F xxx」框（走 station_hint_clicked）：功能跟按 F 一模一样
func _station_interact_cell(c: Vector2i) -> bool:
	if not Structures.has_station(c):
		return false
	match String(Structures.kind_of(c)):
		Structures.KIND_FURNACE:
			match String(Structures.state_of(c)):
				Structures.ST_IDLE:
					var wood: ItemData = load("res://item/wood.tres")
					var ore: ItemData = load("res://item/iron_ore.tres")
					if Inventory.count_item(wood) < 1 or Inventory.count_item(ore) < 1:
						player._flash("熔炉: 点火要 1 木头 + 1 铁矿", "error")
					else:
						Inventory.remove_item(wood, 1)
						Inventory.remove_item(ore, 1)
						Structures.start_smelt(c)
						player._flash("点火了, 一会儿回来取铁锭")
				Structures.ST_SMELTING:
					player._flash("熔炉正炼着呢 (%d%%)" % int(Structures.smelt_progress(c) * 100.0))
				Structures.ST_READY:
					Structures.take_iron(c)
					_spawn_pickup(load("res://item/iron.tres"), _cell_tree_pos(c))
					player._flash("出炉一块铁锭")
			return true
		Structures.KIND_WORKBENCH:
			# e30p: 按 F 直达工作台配方页（原来只提示按 B 自己翻）
			if backpack_panel != null:
				backpack_panel.open_craft("wb")
			return true
		Structures.KIND_WELL:
			# 老水井的 F 打水搬过来了（原来在 well.gd，井改成可建造建筑后归这里管）
			return _fill_from_well(c)
		Structures.KIND_BLACKSMITH:
			# e30p: 按 F 直达铁匠铺配方页（升级 e28f 起就在背包建造页, 不在 F 上）
			if backpack_panel != null:
				backpack_panel.open_craft("smith")
			return true
		Structures.KIND_COOP:
			# e30p: 按 F 打开鸡舍管理界面 —— 收蛋/买鸡/卖鸡/扩建都在里面办，
			# 鸡不再走道具链路（商人不卖小鸡道具了）
			if coop_panel != null:
				coop_panel.open(c)
			return true
		Structures.KIND_HIVE:
			# e44b 收蜜：攒的罐数一次全进背包（装不下就原样存回箱里）
			var jars := Structures.take_honey(c)
			if jars <= 0:
				player._flash("蜂箱还空着, 明天早上再来")
			elif Inventory.add_item(load("res://item/honey.tres"), jars):
				Audio.play_sfx("harvest", -6.0)
				player._flash("收了 %d 罐蜂蜜" % jars)
			else:
				Structures.stations[c]["honey"] = jars   # 背包满：蜜先存回去
				player._flash("背包满了, 放不下蜂蜜", "error")
			return true
		Structures.KIND_CHEST:
			# e45 储物箱：按 F 开左右两栏的存取面板（左箱里 / 右背包）
			if chest_panel != null:
				chest_panel.open(c)
			return true
	# e49 农场畜牧线（畜棚/马厩/筒仓/温室/磨坊/围栏/木桥）：F 交给节点自己认领。
	# 节点那边也有一条 _unhandled_input 的路，这里再兜一层 —— 不赌父子节点
	# 「未处理输入」的传播次序（谁先谁吃掉都只开一次面板，见 farm_building_node.activate）。
	return Structures.interact_farm(c)

# e36i 鼠标左键点了设施头上的「F xxx」提示框 = 按 F（面板/功能走同一条派发）
func station_hint_clicked(c: Vector2i) -> void:
	_station_interact_cell(c)

# e30p: 打水逻辑抽出来 —— F 和左键点水井共用
# e30q: 水井左键打水 —— 点击水井格 = 打水（跟 F 一样; 建造走背包建造页, 不存在手持水井冲突）
func well_click(mouse_world: Vector2, target: Vector2i) -> bool:
	var c := pick_station_cell(mouse_world, target)
	if not Structures.has_station(c) or String(Structures.kind_of(c)) != Structures.KIND_WELL:
		return false
	return _fill_from_well(c)

func _fill_from_well(c: Vector2i) -> bool:
	if Inventory.is_can_full():
		player._flash("水壶已经是满的了")
	else:
		Inventory.fill_water()
		Audio.play_sfx("fill")
		player._flash("打满水了! %d/%d" % [Inventory.water_max(), Inventory.water_max()])
		player.play_tool_animation("fetch")
	return true

# ---------------- 鸡舍管理界面背后的四个动作（e30p） ----------------
# 买一只小鸡直接入住（120 金）。返回 true = 成交
func coop_buy_chicken(c: Vector2i) -> bool:
	if not Structures.has_station(c) or String(Structures.kind_of(c)) != Structures.KIND_COOP:
		return false
	if Structures.chickens_of(c) >= Structures.coop_cap_of(c):
		return false
	if not Wallet.spend_money(Structures.COOP_BUY_FEE):
		return false
	Structures.add_chicken(c)
	Audio.play_sfx("harvest", -8.0, 1.4)
	return true

# 卖掉一只鸡（90 金）。返回 true = 成交
func coop_sell_chicken(c: Vector2i) -> bool:
	if not Structures.remove_chicken(c):
		return false
	Wallet.add_money(Structures.COOP_SELL_FEE)
	Audio.play_sfx("coin", -4.0)
	return true

# 一键收蛋：攒的蛋一次全进背包（装不下就原样存回舍里，返回 0）
func coop_take_eggs(c: Vector2i) -> int:
	var got := Structures.take_eggs(c)
	if got <= 0:
		return 0
	if Inventory.add_item(load("res://item/egg.tres"), got):
		Audio.play_sfx("harvest", -6.0)
		return got
	Structures.stations[c]["eggs"] = got   # 背包满：蛋先存回去
	return 0

# 扩建鸡舍（80*lv 金, 实付 COOP_UP_FEE * 当前等级）。返回 true = 升上去了
func coop_upgrade(c: Vector2i) -> bool:
	if not Structures.has_station(c) or String(Structures.kind_of(c)) != Structures.KIND_COOP:
		return false
	var lv := Structures.level_of(c)
	if lv >= 3:
		return false
	if not Wallet.spend_money(Structures.COOP_UP_FEE * lv):
		return false
	Structures.set_level(c, lv + 1)
	Audio.play_sfx("coin", -4.0)
	return true

# e30p: 拆鸡舍时把一只鸡转移到别的还有空位的鸡舍。返回 false = 全岛都住满了（剩下的走散）
func _relocate_chicken(from: Vector2i) -> bool:
	for cell in Structures.stations.keys():
		var c: Vector2i = cell
		if c == from or String(Structures.kind_of(c)) != Structures.KIND_COOP:
			continue
		if Structures.chickens_of(c) < Structures.coop_cap_of(c):
			Structures.add_chicken(c)
			player._flash("鸡搬去别的鸡舍住了")
			return true
	return false

# 左键点熔炉：手持铁矿 = 放进去烧（配方同 F 点火: 1 木 + 1 铁）；出炉了 = 左键直接取铁。
# 手持镐子保持原样（那是拆设施）；点中的不是熔炉就不吃点击（返回 false 走各自行为）。
func furnace_click(mouse_world: Vector2, target: Vector2i, held: ItemData) -> bool:
	if held != null and held.display_name == "镐子":
		return false
	var c := pick_station_cell(mouse_world, target)
	if not Structures.has_station(c) or String(Structures.kind_of(c)) != Structures.KIND_FURNACE:
		return false
	match String(Structures.state_of(c)):
		Structures.ST_READY:
			Structures.take_iron(c)
			_spawn_pickup(load("res://item/iron.tres"), _cell_tree_pos(c))
			if player != null:
				player._flash("出炉一块铁锭")
		Structures.ST_SMELTING:
			if player != null:
				player._flash("熔炉正炼着呢 (%d%%)" % int(Structures.smelt_progress(c) * 100.0))
		Structures.ST_IDLE:
			# 只有手里攥着铁矿才算「放进去烧」；拿别的点空炉不吃点击（比如手持熔炉继续摆放）
			var ore: ItemData = load("res://item/iron_ore.tres")
			if held != ore:
				return false
			var wood: ItemData = load("res://item/wood.tres")
			if Inventory.count_item(wood) < 1:
				if player != null:
					player._flash("熔炉: 放矿点火还要 1 木头", "error")
				return true
			Inventory.remove_item(wood, 1)
			Inventory.remove_item(ore, 1)
			Structures.start_smelt(c)
			if player != null:
				player._flash("矿扔进炉了, 一会儿回来取铁锭")
	return true

# 玩家是否站在工作台旁（背包 craft 页判定工作台配方能不能做用）
func player_near_workbench() -> bool:
	if player == null:
		return false
	return Structures.near_workbench(_world_to_cell(player.global_position))

# 玩家是否站在铁匠铺旁（返回附近最高等级，0 = 不在旁边）。craft 页打造盔甲用
func player_blacksmith_level() -> int:
	if player == null:
		return 0
	return Structures.near_blacksmith(_world_to_cell(player.global_position))

# ---------------- 建造模式（星露谷式：ghost 跟着鼠标, 左键放下） ----------------
# 入口：背包「建造」页点「选位置」-> start_build_mode -> 回到地图摆 -> 左键确认。
# 造价：金钱 + 材料一次付清；人工（人·天）每晚按派活面板「工地」栏派的人数积累，
# 攒够 cost.labor 自动落成（见 Structures.start_site / add_site_work）。一次只能盖一座。

func is_build_mode() -> bool:
	return build_kind != ""

func start_build_mode(kind: String) -> bool:
	if build_kind != "":
		_cancel_build()
	if Structures.building_cost(kind).is_empty():
		return false
	if not _can_pay_build(kind):
		return false
	build_kind = kind
	_make_ghost()
	Audio.play_sfx("ui_open", -8.0)
	if player != null:
		player._flash("左键放置 / 右键或 Esc 取消")
	return true

func _cancel_build() -> void:
	build_kind = ""
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_ok = false

func _make_ghost() -> void:
	_ghost = _make_ghost_for(build_kind, {})
	add_child(_ghost)

# e44 抽出建 ghost 的分流（新建筑在这里加分支）；payload 只有建筑模式搬房子时才给
# （同伴小屋要按原来那款外形预览, 不然搬着搬着外形会跳）。
func _make_ghost_for(kind: String, payload: Dictionary) -> Node2D:
	var n: Node2D
	match kind:
		Structures.KIND_WELL:
			n = preload("res://scene/well_node.gd").new()
		Structures.KIND_COOP:
			n = preload("res://scene/coop_node.gd").new()
		Structures.KIND_LAMP:
			n = preload("res://scene/lamp_node.gd").new()
		Structures.KIND_HUT:
			n = preload("res://scene/hut_node.gd").new()
		Structures.KIND_HIVE:
			n = preload("res://scene/hive_node.gd").new()
		Structures.KIND_CHEST:
			n = preload("res://scene/chest_node.gd").new()
		_:
			if Structures.is_farm_kind(kind):
				n = preload("res://scene/farm_building_node.gd").new()   # e49 预览也走真节点
			else:
				n = preload("res://scene/blacksmith_node.gd").new()
	n.is_ghost = true                 # 预览不建碰撞
	n.z_index = 100                   # 盖在所有地图元素上面
	n.modulate = Color(0.55, 1.0, 0.55, 0.6)
	# 同伴小屋：预览也要用原来那款外形（hut_node 只在没给 variant 时问 Structures）
	if n.has_method("set_variant") and payload.has("variant"):
		n.call("set_variant", int(payload["variant"]))
	return n

# 建筑地基占的格子：铁匠铺宽 9 格 x 深 3 格（144x90 的房子 -> 底边三行当地基），
# anchor 是底边中间那格；水井小巧，就占锚点 1 格；路灯更小，同样只占 1 格；
# 鸡舍 96x112 -> 底边两行 x 6 格（anchor 底边中间偏右一格）；
# e44 同伴小屋 80~128 宽 -> 底边两行 x 8 格；e44b 蜂箱 16x32 -> 只占锚点 1 格；
# e47 储物箱 16x16 -> 只占锚点 1 格
func building_footprint(anchor: Vector2i, kind: String = "blacksmith") -> Array:
	if kind == Structures.KIND_WELL:
		return [anchor]
	if kind == Structures.KIND_LAMP:
		return [anchor]
	if kind == Structures.KIND_HIVE:
		return [anchor]
	if kind == Structures.KIND_CHEST:
		# e47 箱子贴图改成一只 16x16 的箱子（原来是 32x32 = 上下两只叠一起）-> 只占锚点 1 格
		return [anchor]
	if Structures.is_farm_kind(kind):
		# e49 农场畜牧线：占几格由 structures.gd 的 FARM_FOOT 那张表说了算
		return Structures.farm_footprint(anchor, kind)
	if kind == Structures.KIND_COOP:
		var coop: Array = []
		for dx in range(-3, 3):
			for dy in range(-1, 1):
				coop.append(anchor + Vector2i(dx, dy))
		return coop
	if kind == Structures.KIND_HUT:
		var hut: Array = []
		for dx in range(-4, 4):
			for dy in range(-1, 1):
				hut.append(anchor + Vector2i(dx, dy))
		return hut
	var cells: Array = []
	for dx in range(-4, 5):
		for dy in range(-2, 1):
			cells.append(anchor + Vector2i(dx, dy))
	return cells

# e30o: 大建筑(铁匠铺/水井/鸡舍)占多格，但 Structures 只记锚点格 ——
# 手持工作台/熔炉点在建筑身体格上会跟房子叠成一团（工作台重叠 bug）。
# c 落在任一建筑的地基里就拦。小设施(工作台/熔炉)格子 Structures 直接拦，不用这里管。
func station_footprint_blocked(c: Vector2i) -> bool:
	for key in Structures.stations.keys():
		var kind := String(Structures.stations[key]["kind"])
		if kind == Structures.KIND_WORKBENCH or kind == Structures.KIND_FURNACE:
			continue
		if building_footprint(Vector2i(key), kind).has(c):
			return true
	return false

# 这块地能不能盖：水/桥/沙滩/耕地/庄稼/设施/地板上不行；
# 树、石头、矿不算障碍 —— 建筑可以直接压上去（动工时自动推平，见 _confirm_build）。
# 另外锚点别贴着住宅/商人/售卖箱/矿井/码头，也别压在玩家自己身上。
func _building_site_ok(anchor: Vector2i) -> bool:
	return _site_ok_for(anchor, build_kind)

# e44 抽出「这块地能不能摆这座建筑」：建造模式用 build_kind，建筑模式搬房子用要搬的那座
# 的种类（两边的地基大小不一样，判定要跟着走）。
func _site_ok_for(anchor: Vector2i, kind: String) -> bool:
	for c in building_footprint(anchor, kind):
		if is_water(c) or is_bridge_cell(c) or is_sand(c):
			return false
		if Farm.is_tilled(c) or Farm.has_crop(c):
			return false
		if Structures.is_blocked(c) or Floor.is_floored(c):
			return false
	# e47: 判定再放宽一档。这几条原来都是「以节点所在格为圆心的距离圈」——
	#   摆东西时人必然贴着 ghost 站, 半径 4 的圈等于「玩家身边 4 格全禁建」,
	#   于是满地空位却哪都放不下。现在按占地算：
	#     · 玩家: 只有脚下那格被地基占住才拦（不再是一圈 4 格）
	#     · 住宅: 按屋身算 7x11 的矩形（5x7 的屋身 + 门口那两格）, 门口的院子让出来
	#     · 商人 / 售卖箱 / 矿井 / 码头: 距离圈各收紧一格
	var fp: Array = building_footprint(anchor, kind)
	if player != null and is_instance_valid(player):
		if fp.has(_world_to_cell(player.global_position)):
			return false
	if is_instance_valid($House):
		# ❗屋身是 5x7 格（见 _nature_anchors 的注释）, 而 $House 的原点在屋身上,
		#   所以往上一行行铺; 前后各留一点余量, 别把门口堵死。
		var house_box := Rect2i(_world_to_cell($House.global_position) + Vector2i(-3, -8),
			Vector2i(7, 11))
		for c in fp:
			if house_box.has_point(c):
				return false
	for pair in [[$Merchant, 2], [$ShippingBin, 1]]:
		var n: Node2D = pair[0]
		if n == null or not is_instance_valid(n):
			continue
		if _world_to_cell(n.global_position).distance_to(anchor) < int(pair[1]):
			return false
	if mine_cell.distance_to(anchor) < 2 or _dock_cell().distance_to(anchor) < 2:
		return false
	return true

# 钱料够不够（只是查，不扣）。人工不再预支：动工后每晚派活攒人天
func _can_pay_build(kind: String) -> bool:
	var cost: Dictionary = Structures.building_cost(kind)
	# 婚恋 perk（珞琳）: 建筑金币花费 -10%
	var coin_need := int(round(float(int(cost.get("coin", 0))) * Marriage.perk_mult("build")))
	if Wallet.money < coin_need:
		return false
	for key in ["wood", "stone", "iron"]:
		var it: ItemData = load("res://item/%s.tres" % key)
		if Inventory.count_item(it) < int(cost.get(key, 0)):
			return false
	return true

func _pay_build(kind: String) -> void:
	var cost: Dictionary = Structures.building_cost(kind)
	if int(cost.get("coin", 0)) > 0:
		Wallet.spend_money(int(round(float(int(cost["coin"])) * Marriage.perk_mult("build"))))
	for key in ["wood", "stone", "iron"]:
		var need := int(cost.get(key, 0))
		if need > 0:
			Inventory.remove_item(load("res://item/%s.tres" % key), need)

func _confirm_build() -> void:
	var anchor := _world_to_cell(get_global_mouse_position())
	if not _building_site_ok(anchor):
		Audio.play_sfx("error", -6.0)
		if player != null:
			player._flash("这里放不下 -- 水面/沙滩/庄稼/地板/别的建筑上都压不得", "error")
		return
	if not _can_pay_build(build_kind):
		Audio.play_sfx("error", -6.0)
		if player != null:
			player._flash("钱或材料不够了", "error")
		return
	# e38d labor = 0 的小件（路灯）不占工地名额：它当场就立起来，跟施工中的那座不冲突
	var cost: Dictionary = Structures.building_cost(build_kind)
	var need_labor := int(cost.get("labor", 1))
	if need_labor > 0 and Structures.site_busy():
		Audio.play_sfx("error", -6.0)
		if player != null:
			player._flash("已经有一座工地在施工了 -- 一次只能盖一座", "error")
		return
	var bname: String = cost.get("name", build_kind)
	_pay_build(build_kind)
	# 地基压到树/石头/矿就推平：树连根清掉（含树桩），岩石铁矿直接碎掉，不补偿
	for c in building_footprint(anchor, build_kind):
		Trees.clear_cell(c)
		OreVein.clear_cell(c)
	if not Structures.start_site(anchor, build_kind):
		_cancel_build()
		return
	_sync_site_node()
	Audio.play_sfx("chop", -4.0, 0.9)
	if player != null:
		if need_labor > 0:
			player._flash("%s动工了 - 夜里在派活面板派人施工" % bname)
		else:
			player._flash("%s立好了" % bname)
	_cancel_build()

# ---------------- e44 建筑模式（搬已建好的建筑） ----------------
# 入口：背包「建造」页点「建筑模式」-> 回地图上搬。
# 两步交互（跟建造模式正好反过来：先点建筑、再点地面）：
#   ① 还没拾起：鼠标底下的那座建筑亮起来，左键点它 = 拾起（从地图上摘下来）
#   ② 拾起后：ghost 跟着鼠标，绿 = 能放 / 红 = 不能放；左键落下 / 右键放回原处
# 搬移**不花钱不扣料**，设施数据整份搬过去（等级/鸡/蛋/蜂蜜/小屋外形都跟着走），
# 所以搬完跟搬前完全一样 —— 实现就是 Structures.remove + restore_station。
# 放下之后不退模式：可以接着搬下一座。Esc/B/T 退出。
const NO_CELL := Vector2i(9999, 9999)
const MOVE_HOVER_TINT := Color(1.45, 1.45, 0.6)   # 悬停高亮（提亮 + 泛黄）

func is_move_mode() -> bool:
	return _move_mode

func start_move_mode() -> bool:
	if _move_mode:
		return true
	if build_kind != "":
		_cancel_build()
	_move_mode = true
	_move_hover = NO_CELL
	_move_from = NO_CELL
	_move_payload = {}
	_move_ghost = null
	_move_ok = false
	# 整屏的「F xxx」框在这个模式里不吃鼠标 —— 否则想搬个鸡舍/水井、恰好站在旁边时，
	# 点在提示框上反而开出了它的面板，而不是把房子拾起来（见 key_hint.click_locked）。
	preload("res://scene/key_hint.gd").click_locked = true
	Audio.play_sfx("ui_open", -8.0)
	if player != null:
		player._flash("建筑模式: 左键点建筑拾起来 / 右键或 Esc 退出")
	return true

func _exit_move() -> void:
	_set_move_hover(NO_CELL)
	_move_mode = false
	_move_payload = {}
	_move_from = NO_CELL
	_clear_move_ghost()
	preload("res://scene/key_hint.gd").click_locked = false

# 放下之后还留着模式（接着搬下一座），只有「右键/Esc 且手里没货」才真退出去
func _cancel_move() -> void:
	if not _move_payload.is_empty():
		_move_put_back()
		return
	_exit_move()
	if player != null:
		player._flash("退出建筑模式")

func _clear_move_ghost() -> void:
	if _move_ghost != null and is_instance_valid(_move_ghost):
		_move_ghost.queue_free()
	_move_ghost = null
	_move_ok = false

func _tick_move_mode() -> void:
	if _move_ghost != null and is_instance_valid(_move_ghost):
		# 手里搬着东西：ghost 跟鼠标走
		var anchor := _world_to_cell(get_global_mouse_position())
		_move_ghost.position = _cell_tree_pos(anchor)
		_move_ok = _site_ok_for(anchor, String(_move_payload.get("kind", "")))
		_move_ghost.modulate = Color(0.55, 1.0, 0.55, 0.6) if _move_ok \
			else Color(1.0, 0.4, 0.35, 0.55)
		return
	_set_move_hover(_movable_at_mouse())

# 鼠标底下那座**能搬的**建筑。工作台/熔炉是拿在手里摆的小设施（Structures.BUILDINGS
# 里没有它们），建筑模式不搬它们 —— 一来它们本来随手就能挪，二来它们没有成套的
# 大房子贴图，做预览会串味。
func _movable_at_mouse() -> Vector2i:
	var c := _station_under_mouse(get_global_mouse_position())
	if c == NO_CELL or Structures.building_cost(Structures.kind_of(c)).is_empty():
		return NO_CELL
	return c

func _set_move_hover(c: Vector2i) -> void:
	if c == _move_hover:
		return
	if _move_hover != NO_CELL:
		var old: Node2D = station_nodes.get(_move_hover)
		if old != null and is_instance_valid(old):
			old.modulate = Color.WHITE
	_move_hover = c
	if c == NO_CELL:
		return
	var n: Node2D = station_nodes.get(c)
	if n != null and is_instance_valid(n):
		n.modulate = MOVE_HOVER_TINT

func _move_click() -> void:
	if _move_payload.is_empty():
		var c := _movable_at_mouse()
		if c == NO_CELL or not _move_pick_up(c):
			Audio.play_sfx("error", -6.0)
			if player != null:
				player._flash("把鼠标指到建筑上再点左键", "error")
		return
	_move_drop()

func _move_right_click() -> void:
	if _move_payload.is_empty():
		_cancel_move()
		return
	_move_put_back()

# 拾起一座：数据整份抄下来（remove 之后字典里就没了），地图上先摘掉
func _move_pick_up(c: Vector2i) -> bool:
	if not Structures.has_station(c):
		return false
	if Structures.building_cost(Structures.kind_of(c)).is_empty():
		return false   # 工作台/熔炉这种小设施不搬（见 _movable_at_mouse）
	_move_hover = NO_CELL
	_move_from = c
	_move_payload = Structures.stations[c].duplicate(true)
	Structures.remove(c)          # 发 station_removed -> 节点播消失动画
	_clear_move_ghost()
	_move_ghost = _make_ghost_for(String(_move_payload.get("kind", "")), _move_payload)
	add_child(_move_ghost)
	if player != null:
		player._flash("左键放下 / 右键放回原处")
	return true

# 落到鼠标那一格（成功与否都不退模式：失败留在手里接着找地方）
func _move_drop() -> void:
	var anchor := _world_to_cell(get_global_mouse_position())
	if not _site_ok_for(anchor, String(_move_payload.get("kind", ""))):
		Audio.play_sfx("error", -6.0)
		if player != null:
			player._flash("这里放不下 -- 水面/沙滩/庄稼/地板/别的建筑上都压不得", "error")
		return
	Structures.restore_station(anchor, _move_payload)
	_move_payload = {}
	_move_from = NO_CELL
	_clear_move_ghost()
	Audio.play_sfx("chop", -4.0, 0.9)
	if player != null:
		player._flash("搬好了, 还能接着搬下一座")

# 放回原处（右键取消这次拾起）：原地刚被自己腾空，一定放得回去
func _move_put_back() -> void:
	var payload := _move_payload
	var from := _move_from
	_move_payload = {}
	_move_from = NO_CELL
	_clear_move_ghost()
	if payload.is_empty():
		return
	Structures.restore_station(from, payload)
	if player != null:
		player._flash("放回原处了")

# ---------------- 矿井 ----------------
# 矿井盖在玩家出生点附近（_pick_mine_cell 选的格）：矿门 + 门口的矿石点缀。
# 劳动力在派活面板(T)里安排「采石/采铁」，每天早上结算产出（见 _on_day_ended）。
func _pick_mine_cell() -> Vector2i:
	# 只认河西侧（玩家干活的那半边，码头在河东）的开阔草地，离建筑/码头 4 格开外；
	# 位置往出生点右上方偏一段（用户要求矿井挪到右上的草地上），在那一带选最近的格。
	var anchors: Array = []
	for n: Node2D in [$House, $Merchant, $ShippingBin, $Player]:
		anchors.append(_world_to_cell(n.global_position))
	anchors.append(_dock_cell())
	var inner_from := _world_to_cell($House.global_position + Vector2(-16, 272))
	var inner_to := _world_to_cell($House.global_position + Vector2(304, 496))
	var pc := _world_to_cell($Player.global_position)
	var target := pc + Vector2i(5, -5)   # 目标带：出生点右上 5 格附近
	var best := Vector2i(9999, 9999)
	var best_d := INF
	for c in _land_set.keys():
		if c.x >= RIVER_CX or is_bridge_cell(c):
			continue
		if is_sand(c):               # 矿井要盖在草地上，沙滩不要
			continue
		var ok := true
		for nb in [c + Vector2i.UP, c + Vector2i.DOWN, c + Vector2i.LEFT, c + Vector2i.RIGHT]:
			if not _land_set.has(nb) or is_bridge_cell(nb):
				ok = false
				break
		if not ok:
			continue
		if c.x >= inner_from.x and c.x <= inner_to.x and c.y >= inner_from.y and c.y <= inner_to.y:
			continue
		var d := float(absi(c.x - target.x) + absi(c.y - target.y))
		if absi(c.x - pc.x) + absi(c.y - pc.y) < 5:   # 别贴着玩家出生点
			continue
		var clear := true
		for a in anchors:
			var ac: Vector2i = a
			if maxi(absi(c.x - ac.x), absi(c.y - ac.y)) < 4:
				clear = false
				break
		if not clear:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best

func _setup_mine() -> void:
	if mine_cell.x == 9999:      # 全岛找不到落脚格（理论不会发生）：静默跳过
		return
	var root := Node2D.new()
	root.name = "Mine"
	root.position = _cell_tree_pos(mine_cell)   # 底边踩格线，跟树/石头一个对齐法
	add_child(root)
	# 矿门：Door Mine.png 两帧 32x32，取左帧放大 2 倍（底边对齐原点）
	var door := Sprite2D.new()
	door.centered = false
	var dtex := AtlasTexture.new()
	dtex.atlas = SoftRes.tex(MINE_DOOR_SHEET)
	dtex.region = Rect2(0, 0, 32, 32)
	door.texture = dtex
	door.scale = Vector2(2, 2)
	door.position = Vector2(-32, -63)
	root.add_child(door)
	# 门口两侧摆两块矿石地砖（stone with minerals.png 16x16 网格，内容偏格子下半）
	for cfg in [[0, -46.0], [2, 30.0]]:
		var pr := Sprite2D.new()
		pr.centered = false
		var ptex := AtlasTexture.new()
		ptex.atlas = SoftRes.tex(MINE_ORE_SHEET)
		ptex.region = Rect2(int(cfg[0]) * 16, 0, 16, 16)
		pr.texture = ptex
		pr.position = Vector2(float(cfg[1]) - 8.0, -13)
		root.add_child(pr)
	# 碰撞：门口那一条过不去（layer 4 = 静态体层，只有玩家的 mask 里有）
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(52, 12)
	cs.shape = sh
	cs.position = Vector2(0, -6)
	body.add_child(cs)
	root.add_child(body)

# F 在矿井边：提示去派活面板安排下井（矿井没有独立面板）
func _try_mine_hint() -> bool:
	if player == null or mine_cell.x == 9999:
		return false
	var mp := _cell_tree_pos(mine_cell)
	if player.global_position.distance_to(mp) > 96.0:
		return false
	player._flash("矿井: 按 T 打开派活面板, 安排伙伴采石/采铁")
	return true

# ---------------- 耕地四周的过渡地形（田埂/土路）----------------
# 耕地和草地之间不能硬碰硬，要有一圈过渡。做法跟 soil_layer 一样：
# 遍历所有「紧挨着耕地」的草地图格，按它跟耕地的相对方位拼出田埂图块。
# 关键：监听 Farm.tilled_added/removed，游戏里新开的地也会实时长出田埂。
func _build_field_border() -> void:
	if grid_layer.tile_set == null:
		return
	var tsz := grid_layer.tile_set.tile_size

	# 16 格田埂图块并排成一张 16x1 小图集，图块号 = 耕地方位掩码（1上 2下 4左 8右）
	var sheet := Image.create_empty(16 * tsz.x, tsz.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in 16:
		_draw_border_tile(sheet, i * tsz.x, i, tsz)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(sheet)
	for i in 16:
		atlas.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = tsz
	ts.add_source(atlas, 0)

	border_layer = TileMapLayer.new()
	border_layer.name = "FieldBorderTileMapLayer"
	border_layer.tile_set = ts
	border_layer.position = grid_layer.position
	add_child(border_layer)
	# 排在草地之上、耕地(soil)之下：耕地本体盖住田埂内缘，田埂只在耕地外露出
	move_child(border_layer, decor_layer.get_index() + 1)

	Farm.tilled_added.connect(_on_tilled_changed)
	Farm.tilled_removed.connect(_on_tilled_changed)
	# 开场已有的耕地也要长出田埂
	for pos in Farm.tilled.keys():
		_on_tilled_changed(pos)
	print("[田埂] 耕地四周的过渡地形已生成")

# 某块耕地变动了，刷新它周围（含它本身）的田埂状态。
# 包含它本身是必须的：本来这格是草地，被画了田埂；变成耕地后必须清掉。
func _on_tilled_changed(pos: Vector2i) -> void:
	if border_layer == null:
		return
	_refresh_border_cell(pos)
	for c in _ring(pos):
		_refresh_border_cell(c)

func _ring(pos: Vector2i) -> Array:
	return [
		pos + Vector2i(-1, -1), pos + Vector2i(0, -1), pos + Vector2i(1, -1),
		pos + Vector2i(-1, 0),                       pos + Vector2i(1, 0),
		pos + Vector2i(-1, 1),  pos + Vector2i(0, 1),  pos + Vector2i(1, 1),
	]

# 重画某个格子上的田埂：田埂只画在「草地、非耕地、非水」的格上。
# 只要不满足条件，就 erase_cell 把之前的记录清掉，避免「之前是草地画了、
# 后来变成耕地却没擦」留下的脏格子。
func _refresh_border_cell(c: Vector2i) -> void:
	if Farm.tilled.has(c):
		border_layer.erase_cell(c)   # 这格本身是耕地，不画田埂
		return
	if grid_layer.get_cell_source_id(c) == -1:
		border_layer.erase_cell(c)   # 不是草地（可能是水面/空），清掉
		return
	if water_layer.get_cell_source_id(c) != -1:
		border_layer.erase_cell(c)   # 水面不画田埂
		return
	var idx := 0
	if Farm.tilled.has(c + Vector2i.UP):    idx |= 1
	if Farm.tilled.has(c + Vector2i.DOWN):  idx |= 2
	if Farm.tilled.has(c + Vector2i.LEFT):  idx |= 4
	if Farm.tilled.has(c + Vector2i.RIGHT): idx |= 8
	if idx == 0:
		border_layer.erase_cell(c)
	else:
		border_layer.set_cell(c, 0, Vector2i(idx, 0))

# 画第 idx 号田埂图块：跟耕地接壤的那一边，画一条「土色到草色」的渐变过渡
func _draw_border_tile(sheet: Image, ox: int, idx: int, tsz: Vector2i) -> void:
	var w := tsz.x
	var h := tsz.y
	if idx & 1:   # 上边是耕地 -> 顶边画一条土色过渡
		for x in w:
			for d in BORDER_W:
				_blend_px(sheet, ox + x, d, BORDER_BAND[d])
	if idx & 2:   # 下边
		for x in w:
			for d in BORDER_W:
				_blend_px(sheet, ox + x, h - 1 - d, BORDER_BAND[d])
	if idx & 4:   # 左边
		for y in h:
			for d in BORDER_W:
				_blend_px(sheet, ox + d, y, BORDER_BAND[d])
	if idx & 8:   # 右边
		for y in h:
			for d in BORDER_W:
				_blend_px(sheet, ox + w - 1 - d, y, BORDER_BAND[d])

# 把场景里手画的耕地接管过来：
# 先一次性灌满 Farm.tilled，再统一发 tilled_added —— 这样 soil_layer 画第一格时
# 就知道周围有没有邻居，直接出正确的边缘/拐角瓦块，不会被来回改。
# 碰到水面（池塘）或桥面的格子要跳过：桥上不能有田。
func _restore_field() -> void:
	var cells: Array = authored_field.take_authored_cells()
	if cells.is_empty():
		return
	var kept: Array = []
	for c in cells:
		if water_layer.get_cell_source_id(c) != -1:
			continue
		if is_bridge_cell(c):
			continue
		kept.append(c)
		Farm.tilled[c] = true
	for c in kept:
		Farm.tilled_added.emit(c)
	print("[农田] 接管了 %d 格已开垦的耕地(绕开 %d 格水面)" % [kept.size(), cells.size() - kept.size()])

# ---------------- 睡觉 + 夜晚结算 ----------------
func _build_sleep_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NightOverlay"
	layer.layer = 100
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_fade_label = Label.new()
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.add_theme_font_override("font", FONT_PIX)
	_fade_label.add_theme_font_size_override("font_size", 22)
	_fade_label.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	_fade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade_label)
	_fade_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 夜晚结算画面：加在黑幕/文字之后 → 天然画在它们上面，不用另抬层号
	var sp := preload("res://settlement_ui.gd").new()
	sp.name = "Settlement"
	layer.add_child(sp)
	settlement_panel = sp

	# 给伙伴派活的面板：同一层、加在结算画面之后。两张不会同时开
	# （流程是「结算 → 点继续 → 才弹派活」），所以顺序只是保险。
	var ap := preload("res://assign_ui.gd").new()
	ap.name = "Assign"
	layer.add_child(ap)
	ap.setup(self, Slaves.map_from, Slaves.map_to)
	ap.closed.connect(func():
		if not _sleeping:
			_set_player_frozen(false))
	assign_panel = ap

	# 作弊面板：同一层、最后挂（画在最上面）。按 P 唤醒
	var cp := preload("res://cheat_ui.gd").new()
	cp.name = "Cheat"
	layer.add_child(cp)
	cp.closed.connect(func(): _set_player_frozen(false))
	cheat_panel = cp

# 睡觉 → 黑幕 → 结算（卖货入账）→ 换日 → 天亮。
# ❗顺序很重要：钱必须在「换日」之前算好并显示出来，
#   玩家看到的才是「今晚卖了多少、现在有多少钱」。
func _on_day_ended() -> void:
	if _sleeping:
		return
	_cancel_build()            # 睡觉前还捏着建筑没放下就算了，明天再建
	_sleeping = true
	_set_player_frozen(true)
	Audio.play_sfx("sleep")
	Audio.duck(-10.0, 0.6)

	_fade_label.text = "睡着了..."
	await _fade_to(0.78, 0.7)

	# —— 睡前兜底：今天派下去、伙伴没干完的活，现在强行补完 ——
	# ❗要在弹「派活面板」**之前**做：面板上涂的是明天的计划，别把明天的也秒完成。
	var finished := _force_finish_work()

	# —— 售卖箱兜底结算（e29b: 关箱即售, 正常到不了这里; 未关箱的残留货照旧卖掉明早到账）——
	var shipped: Array = []
	var income := 0
	if shipping_bin != null and shipping_bin.has_method("collect"):
		var res: Dictionary = shipping_bin.collect()
		shipped = res.get("items", [])
		income = int(res.get("total", 0))
		if income > 0:
			Wallet.add_money(income)
			Legion.gain_exp(1)      # e13h: 做买卖也长一点主角经验

	# —— 研究进展：今晚的点数现在就入账（换日时不会再算一次），好在结算面板上播报 ——
	var research_lines: Array = []
	if Research.has_method("settle_night"):
		research_lines = _research_report_lines(Research.settle_night())
	# 明天就是新的一周：提醒玩家准备槽里的政策卡明早上任（隔周生效）
	if TimeManager.day % 7 == 0 and not Research.pending.is_empty():
		research_lines.append("新的一周将至: 准备中的 %d 张政策卡明早上任" % Research.pending.size())

	_fade_label.text = ""
	if settlement_panel != null and settlement_panel.has_method("show_summary"):
		settlement_panel.show_summary(
			TimeManager.date_text(), TimeManager.day, shipped, income, Wallet.money,
			"伙伴们把没干完的 %d 格活补完了" % finished if finished > 0 else "",
			research_lines)
		await settlement_panel.closed

	# —— 结算之后：给伙伴派活（涂色地图）。白天就照这张图闲逛 ——
	if assign_panel != null:
		assign_panel.open()
		await assign_panel.closed

	# —— 夜间施工：工地 / 码头 / 铁匠铺按今晚派的人数推进（1 人干一晚 = 1 人天）——
	# 工地和修码头共用「工地」名单：有建筑工地就盖楼，没有才修码头。
	var build_done := ""
	var smith_done := ""
	var heads := Slaves.build_heads()   # 工匠树加成：一个人顶 1+N 个人手
	if Structures.site_busy():
		var nm := Structures.site_name()
		if Structures.add_site_work(heads):
			build_done = nm
			Legion.gain_exp(3)          # e13h: 建成一座设施也长主角经验
	elif Voyage.dock_state == Voyage.DOCK_FUNDED:
		if _settle_dock():
			build_done = "废弃码头"
	else:
		Slaves.clear_dock_crew()      # 没在施工：名单留着没意义
	if Crafting.smith_busy():
		# e41c: 打铁是队列 —— 人工先喂队首, 多出来的顺延给下一件, 一晚可能出好几件
		var made: Array = Crafting.add_smith_work(Slaves.craft_heads())
		if not made.is_empty():
			smith_done = ", ".join(made)
	else:
		Slaves.clear_craft_crew()     # 没有制造中项目：名单留着没意义

	# —— 矿井：下井的伙伴今晚采出的石头/铁矿，明早交货 ——
	var mine_rng := RandomNumberGenerator.new()
	mine_rng.randomize()
	var mine_yield: Dictionary = OreVein.settle_mine_day(Slaves.mine_crew, mine_rng)
	var mine_stone := int(mine_yield.get("stone", 0))
	var mine_iron := int(mine_yield.get("iron", 0))
	# 婚恋 perk（珂丹）: 矿井产出 +15%
	mine_stone = int(round(float(mine_stone) * Marriage.perk_mult("mine")))
	mine_iron = int(round(float(mine_iron) * Marriage.perk_mult("mine")))
	if mine_stone > 0:
		Inventory.add_item(load("res://item/stone.tres"), mine_stone)
	if mine_iron > 0:
		Inventory.add_item(load("res://item/iron_ore.tres"), mine_iron)

	# —— 鸡舍：早上鸡下蛋（风暴天鸡吓得不敢下）——
	var eggs_laid := Structures.lay_eggs(Weather.is_storm())
	# —— 蜂箱：早上攒蜜（冬天蜜蜂不出巢 / 风暴天也一样不产）——
	var honey_made := Structures.make_honey(Weather.is_storm(), TimeManager.season == 3)
	# —— e49 畜棚/马厩：栏里的牲口早上各产一份（风暴天/冬天不产, 跟鸡蛋一条规矩）——
	var animal_made: Dictionary = Structures.make_animal_produce(
		Weather.is_storm(), TimeManager.season == 3)
	var animal_total := int(animal_made.get("total", 0))

	TimeManager.advance_day()
	Audio.unduck(0.8)
	if not Research.last_promoted.is_empty():
		# 周初换班：昨晚还在准备槽的政策卡今天正式生效（隔周生效）
		var names: Array = []
		for n in Research.last_promoted:
			names.append(str(n))
		_fade_label.text = "%s\n新的一周: %s 生效了" % [TimeManager.date_text(), ", ".join(names)]
		Research.last_promoted = []
	else:
		_fade_label.text = "%s\n新的一天开始了" % TimeManager.date_text()

	await get_tree().create_timer(1.2).timeout
	_fade_label.text = ""
	await _fade_to(0.0, 0.7)
	_set_player_frozen(false)
	_sleeping = false
	if player != null:
		if build_done == "废弃码头":
			player._flash("废弃码头修好了! 去那儿造船, 按 F 出海")
		elif not build_done.is_empty():
			player._flash("%s盖好了!" % build_done)
		elif not smith_done.is_empty():
			player._flash("铁匠铺夜里出件: %s" % smith_done)
		elif mine_stone > 0 or mine_iron > 0:
			player._flash("矿井夜班交货: 石头 x%d, 铁矿 x%d" % [mine_stone, mine_iron])
		if eggs_laid > 0:
			player._flash("鸡舍的鸡下了 %d 个蛋, 去收吧" % eggs_laid)
		elif honey_made > 0:
			player._flash("蜂箱攒了 %d 罐蜜, 去收吧" % honey_made)
		elif animal_total > 0:
			player._flash("畜棚攒了 %d 份畜产, 去收吧" % animal_total)

	# —— 换日流程全部走完 ——
	# ❗这是**唯一**的存档时机：走到这儿 TimeManager 已经翻到新一天的早上 6 点。
	#   存档时间有且只有每天早上 6 点 —— 关窗兜底、退回主页面都不写档。
	SaveManager.save_game(self)

func _fade_to(target: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", target, dur)
	await tw.finished

# 夜里结算码头施工：今天派了几个人去修，就往进度里加几个人天。
# 返回 true = 今天就修好了（天亮后给玩家一句提示）。
func _settle_dock() -> bool:
	if Voyage.dock_state != Voyage.DOCK_FUNDED:
		Slaves.clear_dock_crew()      # 没在施工（或已经建好）：名单留着没意义
		return false
	return Voyage.add_dock_work(Slaves.build_heads())

# 睡前兜底：把今天没干完的活强行补完（用的跟伙伴白天同一套 Slaves.apply_task）。
# 返回真正补完了几格；水里的格子干不了，直接勾掉不再排。
func _force_finish_work() -> int:
	var n := 0
	for c in Slaves.undone_cells():
		if is_water(c):
			Slaves.mark_done(c)
			continue
		if Slaves.apply_task(c) == Slaves.APPLY_OK:
			n += 1
	return n

# ---------------- 夜间研究播报 ----------------
# 把今晚入账的研究点和「现在能研究什么」写成几行字，交给结算面板显示。
# 行数压到 3 行以内 —— 结算面板只有 340px 宽，行多了会挤。
# ❗全部用 ASCII 标点：IPix.ttf 没有全角括号/顿号之类的字形，会渲染成方块。
func _research_report_lines(rep: Dictionary) -> Array:
	var out: Array = []
	if rep.is_empty():
		return out
	var th := int(rep.get("tech_heads", 0))
	var ah := int(rep.get("admin_heads", 0))
	if th <= 0 and ah <= 0:
		out.append("今晚没人钻研 - 打开背包的科技/行政页派人")
		return out
	if th > 0:
		out.append("科技 +%d 点 (共 %d)  %d 人钻研" % [
			int(rep.get("tech_gain", 0)), int(rep.get("tech_total", 0)), th])
	if ah > 0:
		out.append("行政 +%d 点 (共 %d)  %d 人钻研" % [
			int(rep.get("admin_gain", 0)), int(rep.get("admin_total", 0)), ah])
	var ready: Array = Research.ready_list("tech", 3) + Research.ready_list("admin", 3)
	if not ready.is_empty():
		out.append("可研究: %s" % _join_names(ready))
	return out

# ["轮作法", "锻铁斧"] -> "轮作法 / 锻铁斧"
func _join_names(names: Array) -> String:
	var s := ""
	for i in names.size():
		if i > 0:
			s += " / "
		s += String(names[i])
	return s

# ---------------- 开局 ----------------
# 开局给的东西：一把锄头 + 一把斧头 + 一把镐子 + 洒水壶 + 几颗种子 + 一些土豆 + 一点木头。
# 土豆种子给得多一点（够把一小片地种满），另外直接送几个土豆可以马上拿去卖，
# 免得开局只能干等作物长。镐子用来敲岛上的岩石/铁矿露头。
func _give_starting_items() -> void:
	var hoe: ItemData = load("res://item/hoe.tres")
	var axe: ItemData = load("res://item/axe.tres")
	var pickaxe: ItemData = load("res://item/pickaxe.tres")
	var can: ItemData = load("res://item/watering_can.tres")
	var seed: ItemData = load("res://item/seed.tres")            # 土豆种子
	var potato: ItemData = load("res://item/potato.tres")
	var wood: ItemData = load("res://item/wood.tres")
	if hoe != null:
		Inventory.add_item(hoe, 1)
	if axe != null:
		Inventory.add_item(axe, 1)
	if pickaxe != null:
		Inventory.add_item(pickaxe, 1)
	if can != null:
		Inventory.add_item(can, 1)
	if seed != null:
		Inventory.add_item(seed, 24)
	if potato != null:
		Inventory.add_item(potato, 6)
	if wood != null:
		Inventory.add_item(wood, 5)

func _sync_current_item() -> void:
	player.current_item = Inventory.hotbar_item(0)

# ---------------- 存档（读档还原用） ----------------
# _build_trees 是「程序化撒树」（固定种子），读档时树的数据被换成了存档里的，
# 显示节点必须跟着重建：先全拆，再逐格补。
# ❗_apply 里已经调过一次；这里做成幂等（重复调用不炸也不翻倍），自检里会连调验证。
func rebuild_trees_from_save() -> void:
	for c in tree_nodes.keys():
		var n: Node = tree_nodes[c]
		if is_instance_valid(n):
			n.queue_free()
	tree_nodes.clear()
	_falling_cells.clear()
	for c in Trees.trees.keys():
		_on_tree_changed(c)      # 走正常信号路径建节点，跟开局撒树同一套代码

# 岩石的读档还原（save_manager._apply 里调）：数据已被换成存档的，
# 显示节点重建一遍。做成幂等（重复调用不炸也不翻倍），跟 rebuild_trees_from_save 对齐。
func rebuild_rocks_from_save() -> void:
	for c in rock_nodes.keys():
		var n: Node = rock_nodes[c]
		if is_instance_valid(n):
			n.queue_free()
	rock_nodes.clear()
	for c in OreVein.rocks.keys():
		_on_rock_changed(c)

# 工作台/熔炉的读档还原（save_manager._apply 里调）：数据已被换成存档的，
# 显示节点重建一遍。幂等，跟 rebuild_rocks_from_save 对齐。
func rebuild_stations_from_save() -> void:
	for c in station_nodes.keys():
		var n: Node = station_nodes[c]
		if is_instance_valid(n):
			n.queue_free()
	station_nodes.clear()
	for c in Structures.stations.keys():
		_on_station_changed(c)

# 把玩家放回存档时的位置，室内/室外的显示与碰撞一并还原（不播进门/出门动画）。
func apply_player_state(pos: Vector2, indoors: bool) -> void:
	player.global_position = pos
	var house := get_node_or_null("House")
	if house != null and house.has_method("set_indoors_visual"):
		house.set_indoors_visual(indoors)
	else:
		player.indoors = indoors
