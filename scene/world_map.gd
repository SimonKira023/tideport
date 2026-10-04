# scene/world_map.gd —— 大地图旅行模式（骑砍式海图）
#
# 布局（2026-09-19 e11 巨岛改版）：整张海图 200x140 格（16px 一格），
#   · **西北到中部是一整块巨大的海岛**（占海图大部, 外海只剩一圈边），
#     岛上两条大河（中部东西向长河 + 西部南北向西河）把陆地分开, 一排木桥过河
#   · 各国有各国的风貌（e11e）：北岭雪原 / 铁岩石山 / 苍狼沙地 / 西川晨曦草原
#   · 主角所在的出发小岛在**东南**角（出发的船就停在这边的码头）
#   · 中间隔着一道海峡，海上有海寇船队逛荡，巨岛内陆有山贼游荡
#   · 撞上任意一支敌人 → 进预设战役地图开打（见 scene/battle_map.gd）
#
# 画面上是一支**船队**在移动（不是操纵小岛）：带几个伙伴出海就有几条船，
# 一船两人，船一条跟着一条拖在主角的尾迹上；在水上时船画出来、人坐在船里，
# 上岸（踩到陆地）船自动收起来换成步行，伙伴跟在后头走。
# 走到自家码头按 F 返航，走到大陆码头按 F 上岸（进 scene/mainland.gd 的据点小场景）。
# B / Esc 开背包（任务栏跟着亮），鼠标滚轮拉近拉远海图（整数倍缩放，跟岛上一个规矩）。
extends Node2D

const CELL := 16
# 2026-09-19 e11 巨岛改版：整张海图 200x140 格几乎被一块巨大的海岛撑满,
# 外海只剩薄薄一圈; 东南角一道弧形海峡湾, 主角的出发小岛就嵌在湾里。
const MAP_W := 200
const MAP_H := 140
const ISLAND_CENTER := Vector2(160, 116)    # 出发岛岛心（格子号，东南湾里）
const SEED := 20260915

# 巨岛海岸：离图边 ISLE_EDGE 格的「矩形海岸线」，噪声把边揉出 3~11 格起伏，
# 四角再挖出圆弧 —— 撑满整张海图，外海只剩薄薄一圈（用户要的「减小海域」）。
# e37a: 用户嫌「改的力度不够, 整体还是方的」—— 单层低频噪声只能把直边揉成波浪,
#   四条边的整体走向没变, 远看仍是一块圆角长方板。现在改成**三层不同频率**叠加:
#     低频(0.08)  大湾大岬, 一整条边有的鼓出去有的凹进来
#     中频(0.032) 更慢更宽 —— 主宰「这块地偏方还是偏斜」, 是打散轮廓的主力
#     高频(0.23)  碎湾小岬, 近看才有的手绘犬牙
#   再加上四角圆弧半径加倍, 剪影才彻底不是矩形。
const ISLE_EDGE := 7.0            # 海岸离图边的基准格数
const ISLE_EDGE_MIN := 3.0        # 外海最小圈数：三层噪声叠加后下界会压到负数(陆地怼到图边), 兜住
const ISLE_EDGE_NOISE := 8.0      # 低频揉边幅度（大湾大岬）
const ISLE_EDGE_MID := 4.5        # 中频揉边幅度（整条边的鼓/凹, 打散方形的关键）
const ISLE_MID_FREQ := 0.032      # 中频噪声频率（越慢越像「海岸走向」而不是「浪」）
# e36k: 单靠低频噪声，海岸还是一圈「圆角长方形」（用户: 太方了不好看）。
#   再叠一层高频细噪声揉出碎湾，岸线才有犬牙交错的手绘感。
const ISLE_EDGE_FINE := 2.5       # 高频揉边幅度（碎湾小岬）
const ISLE_FINE_FREQ := 0.23      # 高频噪声频率
# 四角圆弧半径（格子）—— e37a: 26 -> 38。上限钉死在 43.8 格: 苍狼帐 (32,30) 离
# 两条图边的距离是 sqrt(32²+30²)=43.9, 半径再大就会把苍狼帐泡进海里。
const ISLE_CORNER := 38.0
# 近岸碎屿（e36k）：主岛外贴岸那一圈水里点的小礁岛。取第三层噪声过阈值，
# 只在海岸 REACH 格以内长 —— 海岸看着是群岛, 不是一刀切下去的边。
const ISLE_SKERRY_FREQ := 0.30
const ISLE_SKERRY_TH := 0.66
const ISLE_SKERRY_REACH := 3      # 碎屿只长在离海岸 3 格以内的水里
const ISLE_TOWN_KEEP := 6         # 城镇落脚圈：城心 6 格内强拉成陆地（防被岸线噪声淹掉）
# 东南湾：从图角挖进来的一道弧形海峡（圆心钉在图角外），出发岛嵌在湾里，
# 出海的船从湾口出去沿着巨岛海岸跑 —— 湾北岸就是登上巨岛的码头。
const BAY_CORNER := Vector2(200, 140)
const BAY_R := 62.0
const BAY_SKERRY_GAP := 12.0      # 湾里不长碎屿（免得抢走大陆码头的位置）

# 岛上的小河：正弦摆的南北河道把出发岛分成东西两半，两座木桥接通两岸 ——
# 大地图上的出发岛看起来就是「原来那座岛」的缩样。
const ISLAND_RIVER_WOBBLE := 2.0            # 河道左右摆幅（格子）
const ISLAND_RIVER_FREQ := 0.16
const ISLAND_RIVER_PHASE := 1.7
const ISLAND_BRIDGE_ROWS := [111, 120]    # 桥所在的行（岛心 116, 河上留通的陆格 + 画桥面）

# 巨岛上的两条大河（跟岛河一个画法：正弦摆的河道, 桥线整行/列豁出来盖木板桥）：
#   · 中部一条东西向长河, 把巨岛切成南北两半
#   · 西部一条南北向河, 河西是西川的河谷沃野
const RIVER_EW_Y := 66.0          # 东西向长河基准线（y 摆动中心）
const RIVER_EW_FREQ := 0.10
const RIVER_EW_PHASE := 0.8
const RIVER_EW_WOBBLE := 4.0
const RIVER_EW_HALF := 1.6        # 河道半宽（格子）
const RIVER_EW_BRIDGE_COLS := [92, 128]   # 跨东西河的桥列
const RIVER_W_X := 52.0           # 西部南北河基准线（x 摆动中心）
const RIVER_W_FREQ := 0.14
const RIVER_W_PHASE := 2.3
const RIVER_W_WOBBLE := 3.5
const RIVER_W_HALF := 1.6
const RIVER_W_BRIDGE_ROWS := [48, 88]     # 跨西河的桥行

# ---------------- 海图材质（真·美术瓦片版）----------------
# 图集布局：0-2 草地三变体 · 3 草沙过渡 · 4 干沙 · 5 湿沙
#          6 起是海水：6 档深浅 x 4 个波纹相位 = 24 格，索引 = T_SEA + 档*4 + 变体
#          30-33 各国风貌（e11e）：30/31 雪（北岭）· 32/33 岩（铁岩）；苍狼沙地复用 3/4 号格
# 2026-09-19 大改：底纹不再在程序里画马赛克, 直接从素材包的瓦片图里取样 ——
#   草地 = Tileset Grass Spring 三块草地格, 沙滩 = Beach animations 的沙格,
#   海水 = 四块水格按 6 档水深重新调色(波纹纹理保留, 颜色压进 SEA 梯度)。
#   档数/相位数(6x4)不能减 —— 相邻格纹理全对齐时一大片海会浮出重复方格。
const T_GRASS_A := 0
const T_GRASS_B := 1
const T_GRASS_C := 2
const T_GRASS_SAND := 3
const T_SAND := 4
const T_SAND_WET := 5
const T_SEA := 6
const SEA_LEVELS := 6         # 水深分几档（越大过渡越顺，格子感越弱）
const SEA_VARIANTS := 4       # 每档几个波纹相位
# 各国风貌底纹（e11e）：追加在海域之后 —— 0-29 的老索引一个不动，
# §75 的图集宽度断言按 T_COUNT 动态算，加瓦片不用改 selftest。
const T_SNOW_A := 30        # 北岭雪原：纯白雪格
const T_SNOW_B := 31        # 北岭雪原：蓝白雪格（变体防大片同纹）
const T_ROCK_A := 32        # 铁岩石山：裂纹石格
const T_ROCK_B := 33        # 铁岩石山：暗平石格
const T_COUNT := T_ROCK_B + 1

# 美术瓦片来源。❗用文件流读 PNG —— headless 下 CompressedTexture2D 的像素读不得
# (项目记忆里的坑); 取样格坐标是 _probe_tiles.gd 探针实测出来的。
const ART_GRASS := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Spring.png"
const ART_BEACH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Beach animations tiles.png"
# ❗草地只许取「整格纯色」的草块（_probe_grassscan.gd 实测: (9,18)/(21,18) 等零色差）。
#   早先取的 (4,0)/(7,1)/(10,2) 是草↔土拼接的**边缘块**（game.gd 明确警告过那排不是草丛），
#   铺满大陆就是用户截图里那片黑十字纹 + 橙红格纹。
#   三格都用 (9,18) —— 岛上 yard 同款亮绿（game.gd YARD_GRASS_TILE），铺出来就是
#   「图一」那片干净草地；草地质感交给 _scatter_decor 的花草点缀，不靠底纹。
const ART_GRASS_CELLS := [Vector2i(9, 18), Vector2i(9, 18), Vector2i(9, 18)]
# 2026-09-19 二次修图（_probe_beachscan.gd 实测全图逐格色差）：
#   · 沙格 (12,0) 是拱门/洞窟装饰块（用户截图里满地棕色拱形就是它），真沙在
#     (12,12)/(13,12)/(14,12) —— 亮沙色 + 细沙粒杂点（dev=0.271，纯色又不像塑料）。
#   · 水格要用「无米色浪钩」的：旧四格里 (1,2)/(4,5) 带米色新月浪钩，铺哪哪乱。
#     新四格全是深蓝底 + 零星白沫点，经 _sea_tile 重映射后 = 平静海面 + 偶尔闪光。
const ART_SEA_CELLS := [Vector2i(9, 2), Vector2i(5, 13), Vector2i(9, 6), Vector2i(10, 14)]
# 风貌底纹素材（_probe_biome.gd 拼图目检选格）：雪取 Tileset Grass Winter 的整格纯雪，
# 石取 Rock Caves 的洞窟地面 —— 都是整格纹理，没有草土/墙沿的拼接边。
const ART_WINTER := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Tileset Grass Winter.png"
const ART_ROCK := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/Rock Caves.png"
const ART_SNOW_CELLS := [Vector2i(9, 18), Vector2i(21, 18)]   # 纯白 / 蓝白
const ART_ROCK_CELLS := [Vector2i(4, 4), Vector2i(9, 15)]     # 裂纹石 / 暗平石
# 草地上的花草点缀 —— 跟岛上 game.gd 同一套 ALL props seasons.png 撒法：
# 透明底单格贴图，低频噪声管疏密（成片花丛 + 留白才像野地，均匀撒就是花毯）。
const ART_PROPS := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Tileset/ALL props seasons.png"
const DECOR_TUFT := [
	Vector2i(1, 0), Vector2i(5, 0), Vector2i(1, 1), Vector2i(5, 1),
	Vector2i(10, 0), Vector2i(10, 1),
]
const DECOR_FLOWER := [
	Vector2i(11, 0), Vector2i(12, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(2, 1), Vector2i(8, 1), Vector2i(12, 1),
	Vector2i(11, 3), Vector2i(12, 3),
]
const DECOR_MUSHROOM := [Vector2i(13, 0), Vector2i(13, 1), Vector2i(11, 2)]
const DECOR_MUSHROOM_SHARE := 0.04
const DECOR_FLOWER_SHARE := 0.30      # 累计：0~0.04 蘑菇，0.04~0.30 花，其余都是草丛
const DECOR_MAX_DENSITY := 0.42
const DECOR_NOISE_FREQ := 0.085
# 风貌点缀（同一条 ALL props 上的冬装/石滩/旱地小件，_probe_biome.gd 目检过非空格）：
# 雪原撒冬青丛+枯枝，石山撒石蘑菇+刺丛，沙地只留枯枝刺丛（密度另减半）。
const DECOR_SNOW := [Vector2i(4, 4), Vector2i(6, 4), Vector2i(8, 4), Vector2i(14, 4), Vector2i(0, 4)]
const DECOR_ROCK := [Vector2i(12, 2), Vector2i(13, 2), Vector2i(9, 2), Vector2i(10, 5)]
const DECOR_SAND := [Vector2i(10, 5), Vector2i(12, 2)]
# 风貌划分（e11e）：陆格底纹按「离哪国的城镇最近」分 ——
# 北岭雪原 / 铁岩石山 / 苍狼沙地 / 西川晨曦草原。过渡带不做硬切：
# 两种风貌的城镇距离差小于 BIOME_BAND 时按概率抖动混铺，边界犬牙交错。
const BIOME_SNOW := 0
const BIOME_ROCK := 1
const BIOME_SAND := 2
const BIOME_PLAIN := 3
const BIOME_OF_NATION := {
	"beiling": BIOME_SNOW, "tieyan": BIOME_ROCK, "canglang": BIOME_SAND,
	"xichuan": BIOME_PLAIN, "chenxi": BIOME_PLAIN,
}
# e37b: 过渡带 11 -> 17 格 —— 三带（岩/雪/草）交界处原来只有一条窄缝,
# 两种材质几乎硬碰硬, 空白处还能看见一条直边。
const BIOME_BAND := 17.0
# 过渡带的「犬牙」用一张独立噪声画: 老版逐格取 hash 抖, 是白噪声 —— 一格一格
# 撒盐, 远看像电视雪花。改成连贯噪声过阈值, 同一片区域连成一坨, 边界才有
# 手绘岛上那种伸进去的舌头（BIOME_JAG 拉对比 = 舌头更长更明显）。
const BIOME_JAG_FREQ := 0.17
const BIOME_JAG := 1.9
const BIOME_MIX := 0.55       # 分界线上最多混入多少比例的邻带（0.55 = 大半仍是本带）
const BIOME_DECOR_MIX := 0.45 # 过渡带上的点缀有多大比例换成邻带的（草木石雪混生）
# 从贴岸浅滩到远洋。❗步进不是均匀的：浅水区（亮）差得小、远洋差得大 ——
# 人眼对亮部差异敏感，浅滩这样才显得细腻，远洋又仍然看得出深邃。
const SEA := [
	Color(0.44, 0.82, 0.87), Color(0.39, 0.77, 0.86), Color(0.33, 0.71, 0.84),
	Color(0.25, 0.63, 0.81), Color(0.17, 0.54, 0.78), Color(0.10, 0.45, 0.72),
]
const N8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
# e16a: 海水改纯色 —— 旧版六档深浅 x 四种波纹相位, 深浅档边界是硬切换,
# 远看就是一块块深浅色斑(用户截图实测)。现在整片海一个颜色, 波光交给
# waves_layer 浪线和 Sparkles 粼光, 不再往贴图里烘纹理。取 SEA 梯度中档。
const SEA_FLAT := Color(0.24, 0.62, 0.81)
# e36k/e36l 起伏阴影（用户: 大地图太方、太素）：一张 1px=1格 的「坡向光照图」
# 按 CELL 放大 LINEAR 铺开 —— 陆地立刻有了丘陵的明暗, 不再是一张平铺色纸。
# 高度场 = 两层噪声, 明暗 = 高度梯度点乘固定光向（光从西北来, 东南背光留影）。
const RELIEF_HI_FREQ := 0.045
const RELIEF_LO_FREQ := 0.12
const RELIEF_LO_GAIN := 0.42
const RELIEF_GAIN := 0.85
const RELIEF_MAX := 0.30          # 明暗最大 alpha（再大就成了脏斑）
const RELIEF_LIGHT := Vector2(-0.62, -0.78)
const RELIEF_LIT := Color(1.0, 0.98, 0.90)
const RELIEF_SHADE := Color(0.05, 0.09, 0.16)
# 城镇夜灯（e36l）：入夜后每座城亮一团暖光, 海图夜里不再是死蓝一片。
const TOWN_LIGHT_ALPHA := 0.45
const TOWN_LIGHT_SCALE := 1.15
const TOWN_LIGHT_GLOW := Color(1.0, 0.80, 0.46)
# 玩家占领的领地在国界层里染的颜色（e13c: 青碧色 —— 五国是红蓝绿紫金, 谁都不撞它）
const PLAYER_TERRITORY := Color(0.28, 0.90, 0.82)

var _sea_d := {}              # Vector2i -> 离岸水深档（_sea_depths 算一次，撒礁石还要用）
var grid_layer: TileMapLayer = null   # 底图瓦片层（waves_layer 要从这读绘制原点）
var _zoom_target := 3.0       # 缩放目标档（观景档之间平滑过渡, 整数档之间秒切）
var _view_t := 0.0            # 观景强度 0..1: 镜头偏移 / 涂色 / 国名淡入都跟它走
var _nation_tint: Sprite2D    # 各国领土半透明涂色（一张 1px=1格 的图放大铺开）
var _nation_labels: Array = []        # 观景档浮出的国名
# e52c: 放大壮观层 —— zoom 4 档起淡入的大字国名 + 都城签（领土微染色也跟着加一点）
var _grand_labels: Array = []
var _grand_t := 0.0

# —— 天色系统（e15c 唯美化: 王国新风）——
# ❗全走世界层 Node2D: Movie Writer (--write-movie) 实测会把 CanvasLayer 里的
#   ColorRect/TextureRect 填充类控件整批丢掉(普通运行正常, 探针出图+成片对比实锤),
#   Node2D(Polygon2D/Sprite2D, 云层同款)两种模式都正常渲染。
var _sky_root: Node2D         # 天色根(跟随相机视野铺满屏幕, 观景档缩放反向补偿)
var _grade_spr: Sprite2D      # 暖冷渐变+暗角(e12e)
var _dn_rect: Sprite2D        # 昼夜覆盖色（按时刻插值, 出海时间停=定格出发那一刻的天色）
var _glow: Sprite2D           # 太阳/月亮柔光盘（加法混合, 沿浅弧扫过天际）
var _band: Sprite2D           # 海面光带（一道斜向的加法光, 白天金/夜里月光冷白）
var _spark_holder: Node2D     # 粼光层（夜里转冷白 = 星光倒影）
var _farboats: Node2D         # 远帆剪影（深水区慢慢漂的小黑帆）
var _farboat_info: Array = []
var _sky_t := 0.0             # 天色动画累计秒（光带呼吸 / 远帆起伏用）
# e16d: 航行演出钟 —— 出海时间停摆(e13a), 天色若一直定格出发时刻, 航程再长
# 也就一个色调。改为: 海图上时天色由 _voy_clock 驱动, VOY_DAY_SEC 秒转完一天,
# 白天/黄昏/夜晚轮流播一遍; ❗只动视觉, TimeManager 照旧不走(下船拨回晚十点)。
const VOY_DAY_SEC := 40.0
var _voy_clock := -1.0        # <0 = 未初始化(首次刷新时衔接出发时刻)

const SPEED_WATER := 88.0                   # 乘船快
const SPEED_LAND := 62.0
const ENCOUNTER_DIST := 15.0                # 撞上敌人的距离
const SIEGE_TIME := 8.0                     # e34e: 攻城进度走满所需秒数, 走完才真正易主
const SIEGE_BAR_W := 36.0                   # e34e: 攻城进度条宽（像素）
const DOCK_DIST := 26.0                     # 码头交互距离
const TOWN_DIST := 28.0                     # 城镇交互距离（进城；城拼大了圈也放宽）
const PATROL_DIST := 24.0                   # 巡逻军队交互距离（军中交谈）
const CARAVAN_DIST := 24.0                  # e26d 商队交互距离（买特产 / 打劫 / 放行）
const BOTTLE_DIST := 20.0                   # e26d 漂流瓶拾取距离
# e26d 商队的货单（item/*.tres 的 key, 面板打开时展示一件当"特产"）
const CARAVAN_GOODS := ["perch", "crayfish", "pufferfish", "starfish", "wheat",
	"pumpkin", "egg", "pumpkin_pie", "cabbage_soup", "carrot_salad", "baked_potato"]
const ZOOM_MIN := 2                         # 滚轮缩放档位范围（整数倍防像素抖动，默认 3）
const ZOOM_MAX := 6
# 观景档（e12h）: 再往外缩就进入 0.28 倍的「全景」—— 一屏装下整张图（200x140 格 =
# 3200x2240px, 需 zoom <= 0.289）, 出发岛也能看到; 镜头滑向全图中心, 各国领土从国界
# 开始淡入半透明涂色 + 浮出国名; 图外也铺一层远海色, 黑边不露头。
const ZOOM_VIEW := 0.28
# e52c: 放大壮观档 —— 拉到 4 倍及以上, 大字国名 + 都城签淡入, 领土也染上一层薄薄的国色
const ZOOM_GRAND := 4.0
const VIEW_CENTER := Vector2(100, 70)       # 观景镜头中心（全图几何中心, 格子号）
const Z_SHORE := 0                          # waves_layer.setup 要的层级号（海图按树序, 0 即可）

# —— 船队（人越多船越多，一船两人）——
# 主角走过的位置记成一串「尾迹」，船和船员都排在尾迹上：
#   船 i 取尾迹第 i*TRAIL_PER_BOAT 点 -> 一条船跟着一条船，像拖在后面的浪
#   船员 j 取尾迹更靠后的点 -> 在水上坐在船里，上岸后自己跟着走
const TRAIL_STEP := 0.07
const TRAIL_MAX := 36
const TRAIL_PER_BOAT := 7
const TRAIL_PER_CREW := 3
# 船员的衣服颜色（在 32px 的船上一眼能数出几个人）
const CREW_COLORS := [
	Color(0.90, 0.42, 0.36), Color(0.42, 0.62, 0.90), Color(0.52, 0.78, 0.44),
	Color(0.86, 0.72, 0.34), Color(0.74, 0.50, 0.86), Color(0.40, 0.80, 0.78),
]

const FONT_PIX := preload("res://resources/font/IPix.ttf")
# 两条船贴图（e40：给船加帆、船体照封面美化 —— 珊瑚船帮 + 米白船缘 + 木甲板）：
#   BOAT_TEX      带帆帆船 32x44（上半桅杆/主帆/前帆/小旗，下半船身）—— 只给大地图船队用
#   BOAT_HULL_TEX 只画船身 32x20 —— 停泊的船 / 出海动画 / 海上队伍：那些地方船挨得近
#                 （泊位行距 15~22px）或船上站着真人，挂帆会互相压、挡脑袋
const BOAT_TEX := preload("res://resources/texture/boat.png")
const BOAT_HULL_TEX := preload("res://resources/texture/boat_hull.png")
# e35 光影：跟岛上同一份光源公用件（圆光晕贴图带缓存, 不会每盏灯重画一遍）
const LIGHT_UTIL := preload("res://scene/light_util.gd")
# e35 唯美化：跟岛上同一份全屏后处理（泛光/色温分离/柔光/饱和/晕影）
const FX_POST := preload("res://scene/fx_post.gdshader")
const JOSH_IDLE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Idle.png"
const JOSH_RUN := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Josh/Run.png"
# 海图上各支队伍的形象池（避开主角的 Josh，别满地图都是同一个人）。
# 素材包 Pre-made 四个预置角色，各有 Idle.png(4 帧) + Run.png(8 帧) x 3 行。
const SKIN_DIRS := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Alex",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Manu",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Lyria",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Tori",
]
# 队伍 -> 皮肤：海寇 Alex / 山贼 Manu；五国巡逻各分一个，再加国色 tint 就各有其相。
const SKIN_PIRATE := 0
const SKIN_BANDIT := 1
const SKIN_OF_NATION := {"chenxi": 2, "beiling": 3, "xichuan": 1, "tieyan": 0, "canglang": 4}

# 城镇标记用的素材（跟岛上同一套 Tiny Asset Pack）：首都多间房拼一座城
# e19: 城镇房子按国家特色配（Houses 1-12 里挑）—— 雪顶「圣诞屋」只留给北岭雪国,
# 其它国换无雪的红陶/藤蔓/橙墙屋, 再叠 25% 国色 tint, 一眼认出是谁家的城。
# 顺序: [主楼, 左厢, 右厢, 小屋]
const HOUSE_DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/"
const HOUSE_OF_NATION := {
	"chenxi": ["10.png", "8.png", "11.png", "3.png"],   # 晨曦: 橙墙小店+红陶商店, 商贵气
	"beiling": ["1.png", "12.png", "4.png", "1.png"],   # 北岭: 雪顶石屋/木屋 —— 雪是特色
	"xichuan": ["2.png", "9.png", "11.png", "9.png"],   # 西川: 绿藤田园屋
	"tieyan": ["7.png", "11.png", "3.png", "7.png"],    # 铁岩: 深瓦烟囱屋, 炭火气
	"canglang": ["3.png", "11.png", "8.png", "10.png"], # 苍狼: 红陶宽屋, 草原驿馆气
}
const HOUSE_DEFAULT := ["3.png", "8.png", "11.png", "7.png"]
const DECO_FOUNTAIN := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Water fountain.png"
const DECO_LAMP := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Street Lamp.png"
const DECO_STATUE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Stone Statue.png"
const DECO_BARRELS := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Stacked Barrels.png"

var _land := {}              # Vector2i -> true
var _water := {}             # Vector2i -> true
var _river := {}             # Vector2i -> true（e37d: 只记河格, 岸沙按它减圈）
var _biome_n: FastNoiseLite = null   # e37b: 风貌过渡带的犬牙噪声（懒建一次）
var dock_island := Vector2.ZERO      # 世界坐标
var dock_continent := Vector2.ZERO
var avatar: Node2D
var _av_sprite: AnimatedSprite2D
var _fleet: Node2D           # 船队 + 船员（画在主角下面）
var _boat_sprites: Array = []
var _crew: Array = []
var _trail: Array = []       # 主角走过的位置，最新在前
var _trail_t := 0.0
var _cam: Camera2D
var _hud: CanvasLayer
var _hint: Label
var parties: Array = []      # {id, pos, dir, t, type, size, node}
var _next_id := 0
var _encounter_cd := 0.0
var _active_party := -1      # 正在打的敌人队伍 id（战斗回来用）
var _town_marks: Array = []  # {tid, pos, node} 城镇旗帜标记
var _near_town := ""         # 当前走近的城镇 id（"" = 没有近来）
var _near_patrol := -1       # 当前走近的巡逻军队 party id（-1 = 没有）
var _patrol_ui: Control = null   # 军中交谈面板（懒加载）
var _ui_lock := false        # 面板开着时锁住走动和遭遇判定
var _bp_ui: Control = null   # 背包面板（懒加载，B / Esc 开合）
var _ql: Control = null      # 任务栏（生命周期跟着背包走）
var _near_caravan := -1      # e26d: 当前走近的商队 party id（-1 = 没有）
var _bottles: Array = []     # e26d: 漂流瓶 {pos, node}
var _near_bottle := -1       # e26d: 走近的漂流瓶下标（-1 = 没有）
var _was_water := false      # e26e: 上一帧是否在水上（切换沿喷水花）
var _ring_tex: Texture2D = null   # e26e: 换旗波纹的圆环贴图（懒生成一次）
# e40: 船队朝哪边（false = 船头朝右/东）。boat.png 的船头是画在右边的,
#   往西走要整队镜像, 不然船是「倒着开」的。只在横向走的时候改, 上下走保留上一次朝向。
var _boat_flip := false

# —— e35 唯美化（用户: 海图太素, 要跟初始岛一个级别）——
var _post_mat: ShaderMaterial = null   # 全屏后处理（跟岛上同一份 scene/fx_post.gdshader）
var _post_night := 0.0                 # 夜度（0 白天 / 1 深夜, 慢慢过渡, 别日落那刻啪地跳）
var _blockers: Array = []              # 建筑碰撞矩形（世界坐标, 主角走位判据）
var _bounds_cache := {}                # 贴图路径 -> 不透明像素外框（Rect2, 一张只量一次）
const BODY_R := 6.0                    # 主角脚下碰撞半径（同 player.tscn 的 CircleShape2D）
const POST_STRENGTH := 0.62            # 后处理浓度（岛上 1.0 全开; 海图压一档, 城名看得清）
var _town_light_sprites: Array = []    # 城镇夜灯（加法柔光, 亮度跟夜度走）

func _ready() -> void:
	add_to_group("world_map")
	_build_terrain()
	_build_out_sea()
	_paint_tiles()
	_build_relief()
	_build_waves_map()
	_scatter_decor()
	_build_cloud_shadows()
	_build_cloud_layer()
	_build_town_marks()
	_build_town_lights()
	_scatter_trees()
	_scatter_rocks()
	_build_bridges()
	_build_dock_marks()
	_build_borders()
	_build_nation_view()
	_setup_avatar()
	_spawn_parties()
	TimeManager.new_day.connect(_on_new_day_wm)   # e26a: 每天取走叛乱队列刷叛军
	_build_fx()
	_build_hud()

# 图外铺一层远海色（e12h）: 拉到观景档时视野比整张图还大, 图外也是水色不露黑边。
func _build_out_sea() -> void:
	var r := Sprite2D.new()
	r.name = "OutSea"
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	r.texture = ImageTexture.create_from_image(img)
	r.centered = false
	r.position = Vector2(-4096, -4096)
	r.scale = Vector2(float(MAP_W) * CELL + 8192.0, float(MAP_H) * CELL + 8192.0)
	r.modulate = SEA[SEA_LEVELS - 1]
	r.z_index = -100            # 压在所有东西底下（z 相对根累加, 负值垫底）
	add_child(r)

# 岸边白浪（e12f）: 直接复用主岛那条会呼吸的浪线层（scene/waves_layer.gd）。
# 它要的 grid_layer/_water/_edge_mask/_hash2/Z_SHORE 本脚本都接得上。
func _build_waves_map() -> void:
	var waves: Node2D = load("res://scene/waves_layer.gd").new()
	waves.name = "WavesLayer"
	add_child(waves)
	waves.setup(self)

# 这格的哪几边贴着陆地（waves_layer 画浪线用）——跟 game.gd 同款, 水集是 _water。
func _edge_mask(c: Vector2i, want_land: bool) -> int:
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	var idx := 0
	for i in 4:
		var nb: Vector2i = c + dirs[i]
		if nb.x < 0 or nb.y < 0 or nb.x >= MAP_W or nb.y >= MAP_H:
			continue
		if _land.has(nb) == want_land:
			idx |= bits[i]
	return idx

func _hash2(c: Vector2i) -> int:
	var h: int = c.x * 374761393 + c.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

# 观景档的国家涂色 + 国名（e12h）: 一张 1px=1格 的领土色图放大铺开（alpha 跟 _view_t 走）,
# 国名浮在各都城上空。树序挂在城镇标记之前 —— 旗子/星号/城名不被涂色盖住。
func _build_nation_view() -> void:
	var img := Image.create_empty(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	var sum := {}   # owner -> [x累计, y累计, 格数]（大字国名的领土质心, e52c）
	for c in _land.keys():
		var ow := _owner_of(c)
		if ow == "":
			continue
		var col := _owner_color(ow)
		img.set_pixel(c.x, c.y, Color(col.r, col.g, col.b, 1.0))
		var acc: Array = sum.get_or_add(ow, [0.0, 0.0, 0])
		acc[0] += float(c.x)
		acc[1] += float(c.y)
		acc[2] += 1
	_nation_tint = Sprite2D.new()
	_nation_tint.name = "NationTint"
	_nation_tint.texture = ImageTexture.create_from_image(img)
	_nation_tint.centered = false
	_nation_tint.scale = Vector2(CELL, CELL)
	_nation_tint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_nation_tint.modulate = Color(1, 1, 1, 0.0)
	add_child(_nation_tint)
	var holder := Node2D.new()
	holder.name = "NationNames"
	add_child(holder)
	for n in Nations.NATIONS:
		var cap := _capital_cell(String(n["id"]))
		if cap == Vector2i(-1, -1):
			continue
		var lb := Label.new()
		lb.text = String(n["name"])
		lb.add_theme_font_override("font", FONT_PIX)
		lb.add_theme_font_size_override("font_size", 40)
		lb.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
		lb.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.06, 0.9))
		lb.add_theme_constant_override("outline_size", 8)
		lb.position = _cell_center(cap) + Vector2(-64, -120)
		lb.modulate = Color(1, 1, 1, 0)
		holder.add_child(lb)
		_nation_labels.append(lb)
	# 自己的领地名（e13d）: 攻下城后写玩家的国名, 跟着涂色一起淡入
	if not Nations.occupied.is_empty():
		var pb := _nation_name_label(Nations.player_nation_name,
			_cell_center(Vector2i(Nations.TOWNS[String(Nations.occupied.keys()[0])]["cell"])))
		holder.add_child(pb)
		_nation_labels.append(pb)
	# e52c: 放大壮观层 —— zoom 4 档起淡入: 大字国名压在领土质心（全战地图范）,
	# 都城上再浮一张「国名 王都」签。z=1: 涂色之上、城镇标记(z=2)之下, 旗子城名照旧清晰。
	var grand := Node2D.new()
	grand.name = "GrandNames"
	grand.z_index = 1
	add_child(grand)
	for ow in sum.keys():
		var acc: Array = sum[ow]
		var nm := ""
		var wcol := Color.WHITE
		if ow == "player":
			if Nations.occupied.is_empty():
				continue
			nm = Nations.player_nation_name
			wcol = PLAYER_TERRITORY.lightened(0.30)
		else:
			nm = String(Nations.nation(String(ow)).get("name", ""))
			wcol = _owner_color(String(ow))
		if nm == "":
			continue
		var at := _cell_center(Vector2i(int(acc[0] / float(acc[2])), int(acc[1] / float(acc[2]))))
		var wm := Label.new()
		wm.text = nm
		wm.add_theme_font_override("font", FONT_PIX)
		wm.add_theme_font_size_override("font_size", 48)
		wm.add_theme_color_override("font_color", wcol.lightened(0.30))
		wm.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.05, 0.85))
		wm.add_theme_constant_override("outline_size", 10)
		wm.size = Vector2(600, 64)
		wm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wm.position = at - Vector2(300, 32)
		wm.modulate = Color(1, 1, 1, 0)
		wm.set_meta("a", 0.45)          # 水印常驻半透: 大而不糊
		grand.add_child(wm)
		_grand_labels.append(wm)
	for n in Nations.NATIONS:
		var cap := _capital_cell(String(n["id"]))
		if cap == Vector2i(-1, -1):
			continue
		var tag := Label.new()
		tag.text = "%s 王都" % String(n["name"])
		tag.add_theme_font_override("font", FONT_PIX)
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color",
			(Nations.nation(String(n["id"])).get("color", Color(0.85, 0.78, 0.5)) as Color).lightened(0.35))
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		tag.add_theme_constant_override("outline_size", 4)
		tag.size = Vector2(240, 18)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.position = _cell_center(cap) - Vector2(120, 118)
		tag.modulate = Color(1, 1, 1, 0)
		tag.set_meta("a", 0.95)
		grand.add_child(tag)
		_grand_labels.append(tag)

func _nation_name_label(text: String, at: Vector2) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_override("font", FONT_PIX)
	lb.add_theme_font_size_override("font_size", 40)
	lb.add_theme_color_override("font_color", PLAYER_TERRITORY.lightened(0.25))
	lb.add_theme_color_override("font_outline_color", Color(0.10, 0.08, 0.06, 0.9))
	lb.add_theme_constant_override("outline_size", 8)
	lb.position = at + Vector2(-64, -120)
	lb.modulate = Color(1, 1, 1, 0)
	return lb

# 一国的都城格子号（没有归 Empty）
func _capital_cell(nid: String) -> Vector2i:
	for tid in Nations.TOWNS.keys():
		var t: Dictionary = Nations.TOWNS[tid]
		if String(t.get("nation", "")) == nid and String(t.get("kind", "")) == "capital":
			return Vector2i(t["cell"])
	return Vector2i(-1, -1)

# 天上的半透明白云：几块长方形拼一朵，整层朝一个方向慢飘
# （飘动/回收/补货/跟缩放都由 scene/cloud_layer.gd 自己管）
func _build_cloud_layer() -> void:
	var cl: Node2D = load("res://scene/cloud_layer.gd").new()
	cl.name = "CloudLayer"
	add_child(cl)

# ---------------- 地形 ----------------
func _build_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	# e37a: 中频「海岸走向」层 —— 频率只有低频的一半, 整条边一起鼓/一起凹,
	# 轮廓才有大尺度的偏斜, 不再是一圈等宽的波浪边。
	var mid := FastNoiseLite.new()
	mid.seed = SEED + 271
	mid.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mid.frequency = ISLE_MID_FREQ
	# e36k: 细噪声揉碎湾 + 第三层噪声点碎屿 —— 三层叠起来海岸才不是一条直边
	var fine := FastNoiseLite.new()
	fine.seed = SEED + 41
	fine.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fine.frequency = ISLE_FINE_FREQ
	var skerry := FastNoiseLite.new()
	skerry.seed = SEED + 83
	skerry.noise_type = FastNoiseLite.TYPE_SIMPLEX
	skerry.frequency = ISLE_SKERRY_FREQ
	for x in MAP_W:
		for y in MAP_H:
			var v: float = noise.get_noise_2d(float(x), float(y))
			var fx := float(x)
			var fy := float(y)
			# 到最近图边的格数（矩形海岸的基准距离）
			var ex := minf(fx, float(MAP_W) - fx)
			var ey := minf(fy, float(MAP_H) - fy)
			var gap := minf(ex, ey)
			var land := false
			# 巨岛：离图边 7+三层噪声 格的「矩形海岸」，噪声把边揉出起伏，
			# 四角挖圆 —— 撑满整张海图，外海只剩薄薄一圈。
			var edge := ISLE_EDGE + v * ISLE_EDGE_NOISE \
				+ mid.get_noise_2d(fx, fy) * ISLE_EDGE_MID \
				+ fine.get_noise_2d(fx, fy) * ISLE_EDGE_FINE
			# 下界兜住: 否则负的 edge 会把陆地怼到图边上, 海图四周没有开海
			edge = maxf(edge, ISLE_EDGE_MIN)
			if gap > edge:
				land = true
			# 四角圆弧：同时贴着两条边的角落区域挖出水（圆角海岸）
			if Vector2(ex, ey).length() < ISLE_CORNER:
				land = false
			# 东南湾：从图角挖进来一道弧形海峡（出发岛嵌在湾里）
			var bay_d := Vector2(fx, fy).distance_to(BAY_CORNER)
			if bay_d < BAY_R:
				land = false
			# 出发岛：湾中孤岛 —— 仿岛上的原型，椭圆岛身
			# 2026-09-19 半径 11/8.5 -> 14.5/11：用户要主岛绿地占大幅变多。
			var nx := (fx - ISLAND_CENTER.x) / 14.5
			var ny := (fy - ISLAND_CENTER.y) / 11.0
			var isle_v := nx * nx + ny * ny
			if isle_v < 1.0 + v * 0.35:
				land = true
			# 三条河（桥线豁出）：岛上的小河 + 中部东西长河 + 西部南北河
			if land and _river_cuts(x, y, isle_v):
				land = false
				_river[Vector2i(x, y)] = true    # e37d: 河格单独记一份, 岸边沙子按它减
			var c := Vector2i(x, y)
			if land:
				_land[c] = true
			else:
				_water[c] = true

	# 近岸碎屿（e36k）第二遍：只在主岛海岸 REACH 格以内的水里点礁屿。
	# ❗别用「离图边多少格」当判据 —— 四角挖圆后的水域也满足, 碎屿会撒到开阔外海上,
	#   把深水区打碎成一片浅滩（粼光/水深层次全没了）。
	var near := {}
	for c in _land.keys():
		var cc: Vector2i = c
		for dy in range(-ISLE_SKERRY_REACH, ISLE_SKERRY_REACH + 1):
			for dx in range(-ISLE_SKERRY_REACH, ISLE_SKERRY_REACH + 1):
				var t: Vector2i = cc + Vector2i(dx, dy)
				if _water.has(t):
					near[t] = true
	for c in near.keys():
		var sc: Vector2i = c
		if Vector2(sc).distance_to(BAY_CORNER) <= BAY_R + BAY_SKERRY_GAP:
			continue          # 湾里不长碎屿: 别抢走大陆码头的位置
		if skerry.get_noise_2d(float(sc.x), float(sc.y)) <= ISLE_SKERRY_TH:
			continue
		_water.erase(sc)
		_land[sc] = true

	# 城镇落脚点兜底（e37a）：海岸线幅度加大后, 理论上海边那座城可能被噪声吞进海里
	#   （最紧的两座离图边只有 24 格: 北岭城 / 白马滩）。城一旦泡水, 房子就立在海上。
	#   这里按 ISLE_TOWN_KEEP 格半径把城心周围强拉成陆地 —— 只在真被淹时才生效。
	for tid in Nations.TOWNS.keys():
		var tc: Vector2i = Nations.TOWNS[tid]["cell"]
		for dy in range(-ISLE_TOWN_KEEP, ISLE_TOWN_KEEP + 1):
			for dx in range(-ISLE_TOWN_KEEP, ISLE_TOWN_KEEP + 1):
				if dx * dx + dy * dy > ISLE_TOWN_KEEP * ISLE_TOWN_KEEP:
					continue
				var tc2: Vector2i = tc + Vector2i(dx, dy)
				if _water.has(tc2):
					_water.erase(tc2)
					_land[tc2] = true

	# 码头：出发岛的最靠东那格（x 最大，再取靠北优先）= 出发码头（港口在岛东面）；
	# 巨岛码头 = 岛外的陆格里离岛心最近的那格（海峡对岸, 出海一眼看得见）。
	var best_i := Vector2i(-1, -1)
	var best_c := Vector2i(-1, -1)
	var best_cd := INF
	for c in _land.keys():
		var ivx := (float(c.x) - ISLAND_CENTER.x) / 14.5
		var ivy := (float(c.y) - ISLAND_CENTER.y) / 11.0
		if ivx * ivx + ivy * ivy >= 1.4 \
				and Vector2(c).distance_to(ISLAND_CENTER) < best_cd:
			best_cd = Vector2(c).distance_to(ISLAND_CENTER)
			best_c = c
		if c.x >= ISLAND_CENTER.x - 14 and c.y >= ISLAND_CENTER.y - 14:
			if best_i == Vector2i(-1, -1) or c.x > best_i.x \
					or (c.x == best_i.x and c.y < best_i.y):
				best_i = c
	dock_island = _cell_center(best_i)
	dock_continent = _cell_center(best_c)
	Voyage.world_pos = dock_island if Voyage.world_pos == Vector2.ZERO else Voyage.world_pos

# 三条河的挖格判定（_build_terrain 用）：桥线整行/整列豁出来留给桥面。
# 岛上的小河只挖出发岛（isle_v 是出发岛椭圆值, 出了岛不挖 —— 别在巨岛上犁出一道沟）。
func _river_cuts(x: int, y: int, isle_v: float) -> bool:
	var fx := float(x)
	var fy := float(y)
	if isle_v < 1.5 and not ISLAND_BRIDGE_ROWS.has(y):
		var rc := float(ISLAND_CENTER.x) \
			+ sin(fy * ISLAND_RIVER_FREQ + ISLAND_RIVER_PHASE) * ISLAND_RIVER_WOBBLE
		if absf(fx - rc) < 1.6:
			return true
	if not RIVER_EW_BRIDGE_COLS.has(x):
		var ry := RIVER_EW_Y + sin(fx * RIVER_EW_FREQ + RIVER_EW_PHASE) * RIVER_EW_WOBBLE
		if absf(fy - ry) < RIVER_EW_HALF:
			return true
	if not RIVER_W_BRIDGE_ROWS.has(y):
		var cx := RIVER_W_X + sin(fy * RIVER_W_FREQ + RIVER_W_PHASE) * RIVER_W_WOBBLE
		if absf(fx - cx) < RIVER_W_HALF:
			return true
	return false

func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)

func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))

func is_water(pos: Vector2) -> bool:
	return _water.has(_cell_at(pos))

# ---------------- 贴图 ----------------
# e19: 采样回来的图统一提饱和(k) —— 海图的草/雪/岩直接取自素材图,
# 远看灰扑扑, 提一档才跟初始岛一个鲜艳劲。
const ART_SAT := 1.18

func _saturate(img: Image, k: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			var g := c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			img.set_pixel(x, y, Color(
				clampf(g + (c.r - g) * k, 0.0, 1.0),
				clampf(g + (c.g - g) * k, 0.0, 1.0),
				clampf(g + (c.b - g) * k, 0.0, 1.0), c.a))

func _paint_tiles() -> void:
	var grass := _load_png(ART_GRASS)
	var beach := _load_png(ART_BEACH)
	var winter := _load_png(ART_WINTER)
	var rockimg := _load_png(ART_ROCK)
	_saturate(grass, ART_SAT)
	_saturate(winter, ART_SAT)
	_saturate(rockimg, ART_SAT)
	var img := Image.create_empty(T_COUNT * CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(SEA[SEA_LEVELS - 1])
	for k in ART_GRASS_CELLS.size():
		_blit_cell(img, (T_GRASS_A + k) * CELL, grass, ART_GRASS_CELLS[k])
	# 沙滩三格改程序化（e12e: 主岛靠岸同款的纯色沙, 素材格上的贝壳浪钩纹理远看太花）
	_sand_tile(img, T_GRASS_SAND * CELL, grass, true, false)
	_sand_tile(img, T_SAND * CELL, grass, false, false)
	_sand_tile(img, T_SAND_WET * CELL, grass, false, true)
	for lv in SEA_LEVELS:
		for v in SEA_VARIANTS:
			_sea_tile(img, (T_SEA + lv * SEA_VARIANTS + v) * CELL, beach, ART_SEA_CELLS[v], lv)
	_blit_cell(img, T_SNOW_A * CELL, winter, ART_SNOW_CELLS[0])
	_blit_cell(img, T_SNOW_B * CELL, winter, ART_SNOW_CELLS[1])
	_blit_cell(img, T_ROCK_A * CELL, rockimg, ART_ROCK_CELLS[0])
	_blit_cell(img, T_ROCK_B * CELL, rockimg, ART_ROCK_CELLS[1])

	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(img)
	for i in T_COUNT:
		atlas.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_source(atlas, 0)

	grid_layer = TileMapLayer.new()
	grid_layer.name = "Tiles"
	grid_layer.tile_set = ts
	add_child(grid_layer)

	_sea_d = _sea_depths()
	var shore := _shore_rings(true)      # e37d: 只算「离海」的圈数, 河边不再自动铺沙
	for c in _water.keys():
		var lv: int = clampi(int(_sea_d.get(c, SEA_LEVELS - 1)), 0, SEA_LEVELS - 1)
		# 相位按格子坐标散开（hash 而不是 x*a+y*b，否则会浮出斜条纹）
		var v: int = absi(hash(c)) % SEA_VARIANTS
		grid_layer.set_cell(c, 0, Vector2i(T_SEA + lv * SEA_VARIANTS + v, 0))
	for c in _land.keys():
		var idx := T_GRASS_A
		var ring: int = int(shore.get(c, 99))
		# 出发岛绿地化（e12e）: 岛上只留贴水一圈湿沙线, 里圈全草 —— 沙漠感收掉
		var ivx := (float(c.x) - ISLAND_CENTER.x) / 14.5
		var ivy := (float(c.y) - ISLAND_CENTER.y) / 11.0
		if ivx * ivx + ivy * ivy < 1.3:
			idx = T_SAND_WET if (ring == 1 or _river_bank(c)) else _biome_grass(c)
		else:
			# e19: 海边沙圈收窄 —— 湿沙一圈 + 干沙半圈就过渡回草, 别再铺三圈沙
			# e37d: 河边另算 —— 只留一条湿沙线 (原来按「离水几圈」铺, 河岸三圈全是沙)
			if ring <= 3:
				match ring:
					1:
						idx = T_SAND_WET
					2:
						idx = T_SAND if absi(hash(c)) % 2 == 0 else T_GRASS_SAND
					_:
						idx = T_GRASS_SAND
			elif _river_bank(c):
				idx = T_SAND_WET
			else:
				idx = _biome_grass(c)
		grid_layer.set_cell(c, 0, Vector2i(idx, 0))

# e37d: 这格陆地是否紧贴河（8 邻里有河格）—— 河岸只铺一条湿沙线的判据
func _river_bank(c: Vector2i) -> bool:
	for nb in N8:
		if _river.has(c + nb):
			return true
	return false

# 起伏阴影（e36k/e36l）：一张 1px = 1格 的坡向光照图，按 CELL 放大铺开。
#   高度场 = 两层 simplex 噪声叠加；每格的高度梯度点乘固定光向 = 该格是迎光坡
#   还是背光坡，迎光的镀一层暖白、背光的压一层冷蓝 —— 平铺的草地立刻有了丘陵感。
# ❗LINEAR 过滤：1px=1格 放大 16 倍，用最近邻就是一格一格的色块棋盘。
#   水格留全透明（不透明度 0），所以阴影不会糊到海面上。
func _build_relief() -> void:
	var hi := FastNoiseLite.new()
	hi.seed = SEED + 313
	hi.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hi.frequency = RELIEF_HI_FREQ
	var lo := FastNoiseLite.new()
	lo.seed = SEED + 97
	lo.noise_type = FastNoiseLite.TYPE_SIMPLEX
	lo.frequency = RELIEF_LO_FREQ
	var img := Image.create_empty(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for c in _land.keys():
		var cc: Vector2i = c
		var h0 := _relief_h(hi, lo, float(cc.x), float(cc.y))
		var hx := _relief_h(hi, lo, float(cc.x) + 1.0, float(cc.y)) - h0
		var hy := _relief_h(hi, lo, float(cc.x), float(cc.y) + 1.0) - h0
		var lit := -(hx * RELIEF_LIGHT.x + hy * RELIEF_LIGHT.y) * RELIEF_GAIN
		if lit >= 0.0:
			img.set_pixel(cc.x, cc.y, Color(RELIEF_LIT.r, RELIEF_LIT.g, RELIEF_LIT.b,
				clampf(lit, 0.0, RELIEF_MAX)))
		else:
			img.set_pixel(cc.x, cc.y, Color(RELIEF_SHADE.r, RELIEF_SHADE.g, RELIEF_SHADE.b,
				clampf(-lit, 0.0, RELIEF_MAX)))
	var spr := Sprite2D.new()
	spr.name = "Relief"
	spr.texture = ImageTexture.create_from_image(img)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.centered = false
	spr.scale = Vector2(CELL, CELL)
	add_child(spr)

func _relief_h(hi: FastNoiseLite, lo: FastNoiseLite, x: float, y: float) -> float:
	return hi.get_noise_2d(x, y) + lo.get_noise_2d(x, y) * RELIEF_LO_GAIN

# 程序化沙滩格（e19: 纯色版）—— 旧版沙底上撒明暗噪点, 远看全是麻点(用户点名)。
# 现在就是一块干净的沙色: wet = 湿沙深一档, blend = 掺草过渡。
func _sand_tile(dst: Image, ox: int, grass: Image, blend: bool, wet: bool) -> void:
	var base := Color(0.84, 0.74, 0.48) if wet else Color(0.86, 0.78, 0.56)
	for y in CELL:
		for x in CELL:
			var c := base
			if blend:
				var g: Color = grass.get_pixel(ART_GRASS_CELLS[0].x * CELL + x,
					ART_GRASS_CELLS[0].y * CELL + y)
				c = g.lerp(c, 0.45)
			dst.set_pixel(ox + x, y, c)

# —— 各国风貌（e11e）——
# 内陆格底纹按「离哪国的城镇最近」分：北岭雪原 / 铁岩石山 / 苍狼沙地 / 其余草原。
# 边界不做硬切：离分界 BIOME_BAND 格以内按「连贯噪声」过阈值混铺邻带 ——
# 同一片区域连成一坨, 边界是伸出去的舌头, 不是逐格撒盐（e37b）。
func _biome_of(c: Vector2i) -> int:
	var p := _biome_pair(c)
	var band: float = p[2]
	var first: int = p[0]
	var second: int = p[1]
	if band <= 0.0:
		return first              # 离分界够远: 本带说了算, 不放邻带进来
	# 犬牙噪声懒建一次（_biome_of 是热循环, 每格都 new 一个太浪费）
	if _biome_n == null:
		_biome_n = FastNoiseLite.new()
		_biome_n.seed = SEED + 577
		_biome_n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_biome_n.frequency = BIOME_JAG_FREQ
	var n := _biome_n.get_noise_2d(float(c.x), float(c.y)) * 0.5 + 0.5
	n = clampf((n - 0.5) * BIOME_JAG + 0.5, 0.0, 1.0)
	if n < band * BIOME_MIX:
		return second             # 越靠近分界、又刚好落在噪声低处, 就越可能混成邻带
	return first

# 这格属于哪一带 / 最近的邻带是谁 / 离分界多近（0 = 本带深处, 1 = 正踩在分界线上）
func _biome_pair(c: Vector2i) -> Array:
	var d := [INF, INF, INF, INF]   # 下标 = 风貌，值 = 离该风貌最近城镇的距离
	for tid in Nations.TOWNS.keys():
		var t: Dictionary = Nations.TOWNS[tid]
		var b: int = BIOME_OF_NATION.get(String(t.get("nation", "")), -1)
		if b < 0:
			continue
		var dd: float = Vector2(c).distance_to(Vector2(t["cell"]))
		if dd < d[b]:
			d[b] = dd
	var order := [0, 1, 2, 3]
	order.sort_custom(func(x, y) -> bool: return d[x] < d[y])
	var gap: float = d[order[1]] - d[order[0]]
	var band := 0.0 if gap >= BIOME_BAND else 1.0 - gap / BIOME_BAND
	return [order[0], order[1], band]

# 内陆格的底纹瓦片：按风貌选雪/岩/沙/草，同风貌里再掺变体防大片同纹。
func _biome_grass(c: Vector2i) -> int:
	var h := absi(hash(c))
	match _biome_of(c):
		BIOME_SNOW:
			return T_SNOW_B if h % 3 == 0 else T_SNOW_A
		BIOME_ROCK:
			return T_ROCK_B if h % 4 == 0 else T_ROCK_A
		BIOME_SAND:
			var r := (h / 7) % 10   # 苍狼：三成干沙 + 五成草沙过渡, 狼旗下的沙原不是沙滩
			if r < 3:
				return T_SAND
			if r < 8:
				return T_GRASS_SAND
			return T_GRASS_A + h % 3
		_:
			return T_GRASS_A + h % 3

# 草地花草点缀：把岛上的那套撒法搬过来（草丛/花/蘑菇, 低频噪声管疏密）。
# 各国风貌各撒各的小件（e11e）：雪原冬青/石山石蘑菇/沙地枯枝刺丛（密度减半）。
# 只撒在离岸 4 圈以外 —— 沙滩过渡带不长花；图层紧挨 Tiles，
# 云影/城镇/树/主角都后加，天然压在点缀上面。
func _scatter_decor() -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(_load_png(ART_PROPS))
	var palette: Array = []
	palette.append_array(DECOR_MUSHROOM)
	palette.append_array(DECOR_FLOWER)
	palette.append_array(DECOR_TUFT)
	palette.append_array(DECOR_SNOW)
	palette.append_array(DECOR_ROCK)
	palette.append_array(DECOR_SAND)
	for t in palette:
		if not atlas.has_tile(t):
			atlas.create_tile(t)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_source(atlas, 0)
	var layer := TileMapLayer.new()
	layer.name = "Decor"
	layer.tile_set = ts
	add_child(layer)

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = DECOR_NOISE_FREQ
	var shore := _shore_rings()
	var tuft_band := 1.0 - (DECOR_MUSHROOM_SHARE + DECOR_FLOWER_SHARE)
	for c in _land.keys():
		if int(shore.get(c, 99)) < 4:
			continue
		var n := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
		var density := smoothstep(0.30, 0.88, n) * DECOR_MAX_DENSITY
		# e37b: 三带交界处掺邻带的草木石雪 —— 底纹是犬牙混铺, 点缀也跟着混,
		#   雪原边缘长石蘑菇、石山边缘长冬青, 边界才像自然过渡而不是两条色块对撞。
		var pair := _biome_pair(c)
		var biome: int = pair[0]
		if float(pair[2]) > 0.0 and rng.randf() < float(pair[2]) * BIOME_DECOR_MIX:
			biome = pair[1]
		match biome:
			BIOME_SAND:
				density *= 0.45     # 旱地疏朗，点缀减半
			BIOME_SNOW, BIOME_ROCK:
				density *= 0.8
		if rng.randf() >= density:
			continue
		var pick: Vector2i
		match biome:
			BIOME_SNOW:
				pick = DECOR_SNOW[rng.randi() % DECOR_SNOW.size()]
			BIOME_ROCK:
				pick = DECOR_ROCK[rng.randi() % DECOR_ROCK.size()]
			BIOME_SAND:
				pick = DECOR_SAND[rng.randi() % DECOR_SAND.size()]
			_:
				var r := rng.randf()
				if r < tuft_band:
					pick = DECOR_TUFT[rng.randi() % DECOR_TUFT.size()]
				elif r < tuft_band + DECOR_FLOWER_SHARE:
					pick = DECOR_FLOWER[rng.randi() % DECOR_FLOWER.size()]
				else:
					pick = DECOR_MUSHROOM[rng.randi() % DECOR_MUSHROOM.size()]
		layer.set_cell(c, 0, pick)

# —— 美术瓦片取样 ——
# 用文件流读素材 PNG（headless 下 CompressedTexture2D 的像素读不得, 项目记忆的坑）。
# ❗e52b 导出包修复：res:// 里那些**原始 png 不进 PCK**（export_presets 是 all_resources +
#   include_filter 空, 包里只有导入后的 .ctex）—— 导出后 FileAccess 读不到, 取样全空,
#   图集里草地/雪地/岩石那些格就留在 _paint_tiles 开头 fill() 的深海色上,
#   看起来就是「草地变成水的瓦块」（编辑器里跑不出这个毛病, 只在导出后有）。
#   所以文件流失败时改走导入贴图取像素。
func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var img := Image.new()
		if img.load_png_from_buffer(f.get_buffer(f.get_length())) == OK:
			img.convert(Image.FORMAT_RGBA8)
			return img
	return _png_from_texture(path)

# 兜底：从**导入后的贴图**取像素（导出包里只剩它）。
# 返回的是副本 —— 调用方 _saturate() 是原地改像素, 直接改共享贴图的 Image 会把 atlas 一起调花。
func _png_from_texture(path: String) -> Image:
	var tex := SoftRes.tex(path)
	var ti: Image = tex.get_image() if tex != null else null
	if ti == null or ti.get_width() < CELL or ti.get_height() < CELL:
		push_error("海图瓦片图读不到: " + path)
		return Image.create_empty(CELL, CELL, false, Image.FORMAT_RGBA8)
	var out := Image.new()
	out.copy_from(ti)
	out.convert(Image.FORMAT_RGBA8)
	return out

# 把素材图里 16x16 的一个源格原样拷到图集 ox 位置上。
func _blit_cell(dst: Image, ox: int, src: Image, cell: Vector2i) -> void:
	dst.blit_rect(src, Rect2i(cell.x * CELL, cell.y * CELL, CELL, CELL), Vector2i(ox, 0))

# 草沙过渡格已改程序化（_sand_tile），这两个旧取样工具随之退场。

# 海水格（e16a 纯色版）: 旧版保留美术水格的波纹纹理并按 SEA 六档调色 ——
# 深浅档边界硬切 + 四种相位变体纹理不一致, 远看是一块块色斑(用户截图实锤)。
# 现在海格全部画同一个纯色; 岸边过渡交给 waves_layer 浪线 + 浅滩沙圈。
func _sea_tile(dst: Image, ox: int, _src: Image, _cell: Vector2i, _lv: int) -> void:
	dst.fill_rect(Rect2i(ox, 0, CELL, CELL), SEA_FLAT)

# 离岸水深：贴岸 = 0，往外一圈 +1，最多 SEA_LEVELS-1 档。
# ❗走 8 邻而不是 4 邻：4 邻扩散会让斜着的海岸线留下一格宽的直角台阶。
func _sea_depths() -> Dictionary:
	var depth := {}
	var frontier: Array = []
	for c in _water.keys():
		depth[c] = SEA_LEVELS - 1
		for nb in N8:
			if _land.has(c + nb):
				depth[c] = 0
				frontier.append(c)
				break
	var d := 0
	while not frontier.is_empty() and d < SEA_LEVELS - 1:
		var nxt: Array = []
		for c in frontier:
			for nb in N8:
				var t: Vector2i = c + nb
				if _water.has(t) and int(depth[t]) > d + 1:
					depth[t] = d + 1
					nxt.append(t)
		frontier = nxt
		d += 1
	return depth

# 陆地离海边的圈数：1 = 紧贴水（湿沙）/ 2 = 干沙 / 3 = 草沙 / 99 = 内陆草地
# e37d: sea_only=true 时只认开海 —— 河格当陆地看, 于是「河边自动铺三圈沙」没了,
#   河岸改由 _paint_tiles 另铺一条湿沙线（用户: 大地图河边的沙子太多）。
func _shore_rings(sea_only: bool = false) -> Dictionary:
	var ring := {}
	var frontier: Array = []
	for c in _land.keys():
		ring[c] = 99
		for nb in N8:
			var t: Vector2i = c + nb
			if _water.has(t) and not (sea_only and _river.has(t)):
				ring[c] = 1
				frontier.append(c)
				break
	var k := 1
	while not frontier.is_empty() and k < 3:
		var nxt: Array = []
		for c in frontier:
			for nb in N8:
				var t: Vector2i = c + nb
				if _land.has(t) and int(ring[t]) > k + 1:
					ring[t] = k + 1
					nxt.append(t)
		frontier = nxt
		k += 1
	return ring

func P(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, c)

func R(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			P(img, x, y, c)

# ---------------- 树 / 礁石 / 码头标记（纯装饰，不挡船） ----------------
# e19: 树换成素材果树成树帧(战场同款 Cherry/Apricot 32x48, 帧号 6/3) ——
# 旧的 14x18 程序三角树太简陋(用户点名)。缩 0.9 贴 16px 格, NEAREST 干净像素。
const MAP_TREES := [
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Cherry Tree.png",
	"res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Crops/Fruits Tree/Spring/Apricot Tree.png",
]
const MAP_TREE_FRAME := [6, 3]        # 两种果树的「成树」帧号（同 scene/tree_node.gd）
const MAP_TREE_W := 32
const MAP_TREE_H := 48
var _trees_root: Node2D = null        # 全部树 Sprite2D 的容器（观景档整屏拉远时整体藏掉救帧率）

func _scatter_trees() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED + 999
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
	for bc in _bridge_cells():
		bridge_set[bc] = true
	var holder := Node2D.new()
	holder.name = "Trees"
	add_child(holder)
	_trees_root = holder
	for c in _land.keys():
		var v := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5
		if v < 0.72:
			continue
		# 码头附近留空，别把路挡了
		if _cell_center(c).distance_to(dock_island) < 40.0 \
				or _cell_center(c).distance_to(dock_continent) < 40.0:
			continue
		# 岛上两座木桥的桥面留空：树长在桥上像话吗
		if bridge_set.has(c):
			continue
		# 城镇周围也留空：旗子和小房不跟树挤在一块
		var near_town := false
		for m in _town_marks:
			if _cell_center(c).distance_to(m["pos"]) < 30.0:
				near_town = true
				break
		if near_town:
			continue
		var s := Sprite2D.new()
		s.texture = texs[absi(c.x * 13 + c.y * 7) % 2]   # 樱桃 / 杏树 交替，陆地不至一片同款
		s.position = _cell_center(c) + Vector2(0, -6)
		holder.add_child(s)

# 礁石：远洋里稀疏撒几块，给空旷的海面一点地标（不影响航行）
func _scatter_rocks() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED + 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.3
	var tex := _rock_tex()
	var holder := Node2D.new()
	holder.name = "Rocks"
	add_child(holder)
	for c in _water.keys():
		if int(_sea_d.get(c, 0)) < 3:       # 只挑够深的水，别糊在岸边
			continue
		if (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5 < 0.92:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.position = _cell_center(c) + Vector2(0, -2)
		holder.add_child(s)

func _rock_tex() -> ImageTexture:
	var img := Image.create_empty(14, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	R(img, 1, 8, 12, 9, Color(0.86, 0.94, 0.96, 0.85))      # 脚下一圈白浪
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
func _build_dock_marks() -> void:
	var tex := _dock_tex()
	var holder := Node2D.new()
	holder.name = "DockMarks"
	add_child(holder)
	for p in [dock_island, dock_continent]:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = p + Vector2(0, -6)
		holder.add_child(s)

func _dock_tex() -> ImageTexture:
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
func _bridge_cells() -> Array:
	var out: Array = []
	# 出发岛小河：南北河道, 桥是东西走向的整行
	for y in ISLAND_BRIDGE_ROWS:
		var rc := float(ISLAND_CENTER.x) \
			+ sin(float(y) * ISLAND_RIVER_FREQ + ISLAND_RIVER_PHASE) * ISLAND_RIVER_WOBBLE
		for x in range(int(floor(rc - 1.6)), int(ceil(rc + 1.6))):
			var c := Vector2i(x, y)
			if _land.has(c):
				out.append(c)
	# 中部东西长河：东西河道, 桥是南北走向的整列
	for x in RIVER_EW_BRIDGE_COLS:
		var ry := RIVER_EW_Y \
			+ sin(float(x) * RIVER_EW_FREQ + RIVER_EW_PHASE) * RIVER_EW_WOBBLE
		for y in range(int(floor(ry - RIVER_EW_HALF)), int(ceil(ry + RIVER_EW_HALF))):
			var c := Vector2i(x, y)
			if _land.has(c):
				out.append(c)
	# 西部南北河：南北河道, 桥是东西走向的整行
	for y in RIVER_W_BRIDGE_ROWS:
		var cx := RIVER_W_X \
			+ sin(float(y) * RIVER_W_FREQ + RIVER_W_PHASE) * RIVER_W_WOBBLE
		for x in range(int(floor(cx - RIVER_W_HALF)), int(ceil(cx + RIVER_W_HALF))):
			var c := Vector2i(x, y)
			if _land.has(c):
				out.append(c)
	return out

func _build_bridges() -> void:
	var tex := _bridge_tex()
	var holder := Node2D.new()
	holder.name = "Bridges"
	add_child(holder)
	for c in _bridge_cells():
		var s := Sprite2D.new()
		s.texture = tex
		s.position = _cell_center(c)
		holder.add_child(s)

func _bridge_tex() -> ImageTexture:
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

# ---------------- 城镇标记 ----------------
# 大陆上 12 座城镇按 kind 拼出不同的城（素材跟岛上同一套 Tiny Asset Pack）：
#   · 首都：主楼居中 + 左右两厢 + 喷泉雕像灯柱木桶 —— 是一座城，不是一件屋子
#   · 军镇：大屋压阵 + 副房 + 雕像，像个据点
#   · 贸易镇：两间屋 + 灯柱木桶，小集市的样子
# 国旗 + 城名照旧。走近了按 F 进城（Voyage.enter_town）。
# z_index 抬高：盖过树和云影，城镇是玩家要找的大目标。
func _build_town_marks() -> void:
	var holder := Node2D.new()
	holder.name = "TownMarks"
	holder.z_index = 2
	add_child(holder)
	for tid in Nations.TOWNS.keys():
		var t: Dictionary = Nations.TOWNS[tid]
		var pos := _cell_center(t["cell"])
		var nid := String(t["nation"])
		var ncol: Color = Nations.nation(nid).get("color", Color(0.8, 0.72, 0.42))
		var kind := String(t.get("kind", "trade"))
		# e19: 本国的四间房(主楼/左厢/右厢/小屋) + 25% 国色 tint —— 国家特色一眼辨
		var hs: Array = HOUSE_OF_NATION.get(nid, HOUSE_DEFAULT)
		var h_main := HOUSE_DIR + String(hs[0])
		var h_left := HOUSE_DIR + String(hs[1 % hs.size()])
		var h_right := HOUSE_DIR + String(hs[2 % hs.size()])
		var h_small := HOUSE_DIR + String(hs[hs.size() - 1])
		var tint := ncol.lerp(Color(1, 1, 1), 0.75)
		var n := Node2D.new()
		n.name = "Town_%s" % tid
		n.position = pos
		var flag_y := -50.0
		var label_y := -60.0
		match kind:
			"capital":
				_add_blocker(pos, _deco(n, h_main, 0.50, Vector2(-32, -56), tint), h_main)
				_add_blocker(pos, _deco(n, h_left, 0.35, Vector2(-56, -39), tint), h_left)
				_add_blocker(pos, _deco(n, h_right, 0.38, Vector2(16, -49), tint), h_right)
				_deco(n, DECO_FOUNTAIN, 0.30, Vector2(26, -19), Color(1, 1, 1), Vector2i(48, 64))
				_deco(n, DECO_LAMP, 0.28, Vector2(-42, -14), Color(1, 1, 1), Vector2i(32, 48))
				_deco(n, DECO_STATUE, 0.35, Vector2(-10, -17))
				_deco(n, DECO_BARRELS, 0.28, Vector2(44, -13))
				n.add_child(_make_capital_star())   # 星号: 一眼认出都城
				flag_y = -66.0
				label_y = -78.0
			"military":
				_add_blocker(pos, _deco(n, h_right, 0.42, Vector2(-27, -54), tint), h_right)
				_add_blocker(pos, _deco(n, h_small, 0.32, Vector2(26, -31), tint), h_small)
				_deco(n, DECO_STATUE, 0.35, Vector2(-36, -17))
				_deco(n, DECO_BARRELS, 0.28, Vector2(24, -14))
				flag_y = -62.0
				label_y = -72.0
			_:
				_add_blocker(pos, _deco(n, h_small, 0.45, Vector2(-18, -43), tint), h_small)
				_add_blocker(pos, _deco(n, h_left, 0.32, Vector2(16, -36), tint), h_left)
				_deco(n, DECO_BARRELS, 0.30, Vector2(8, -15))
				_deco(n, DECO_LAMP, 0.28, Vector2(-32, -14), Color(1, 1, 1), Vector2i(32, 48))
		var f := Sprite2D.new()
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		f.texture = _town_banner_tex(ncol)
		f.position = Vector2(14, flag_y)
		n.add_child(f)
		var l := Label.new()
		l.text = String(t["name"])
		l.add_theme_font_override("font", FONT_PIX)
		l.add_theme_font_size_override("font_size", 8)
		l.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.position = Vector2(-26, label_y)
		n.add_child(l)
		holder.add_child(n)
		_town_marks.append({"tid": tid, "pos": pos, "node": n})
	# 出发岛也是一处城镇（e11h）: 潮汐港 —— 主角的家, 海图上一眼能认出来。
	# 纯标记: 不进 _town_marks（码头按 F 回岛走的是原来的航路, 不重复给交互）。
	# e19: 屋子换藤蔓田园屋(不再引用已删的旧 HOUSE 常量)
	var vil := Node2D.new()
	vil.name = "IslandTown"
	vil.position = _cell_center(Vector2i(int(ISLAND_CENTER.x) - 7, int(ISLAND_CENTER.y) - 2))
	_add_blocker(vil.position, _deco(vil, HOUSE_DIR + "2.png", 0.38, Vector2(-20, -36)),
		HOUSE_DIR + "2.png")
	_add_blocker(vil.position, _deco(vil, HOUSE_DIR + "9.png", 0.28, Vector2(8, -28)),
		HOUSE_DIR + "9.png")
	_deco(vil, DECO_BARRELS, 0.26, Vector2(-2, -12))
	var vl := Label.new()
	vl.name = "Name"
	vl.text = "潮汐港"
	vl.add_theme_font_override("font", FONT_PIX)
	vl.add_theme_font_size_override("font_size", 8)
	vl.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	vl.add_theme_constant_override("outline_size", 3)
	vl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	vl.position = Vector2(-26, -48)
	vil.add_child(vl)
	holder.add_child(vil)

# 城镇夜灯（e36l）：入夜后每座城亮一团暖光 —— 海图夜里本来只剩一片死蓝,
# 现在城是亮点, 一眼能找到落脚处。
# ❗挂在天色层(z=60)之上: 夜色的半透明覆盖画在最上面, 灯若在它下面会被压暗一半。
func _build_town_lights() -> void:
	var holder := Node2D.new()
	holder.name = "TownLights"
	holder.z_index = 61
	add_child(holder)
	var spots: Array = []
	for tid in Nations.TOWNS.keys():
		spots.append(_cell_center(Nations.TOWNS[tid]["cell"]))
	spots.append(_cell_center(Vector2i(int(ISLAND_CENTER.x) - 7, int(ISLAND_CENTER.y) - 2)))
	for p in spots:
		var g := LIGHT_UTIL.make_glow(TOWN_LIGHT_GLOW, TOWN_LIGHT_SCALE, 2.1)
		g.position = (p as Vector2) + Vector2(0, -30)
		g.modulate.a = 0.0
		holder.add_child(g)
		_town_light_sprites.append(g)

# 夜度统一下发：后处理 night 参数 + 城镇夜灯亮度一起动, 不会一个亮一个没亮。
func _apply_night(nf: float) -> void:
	if _post_mat != null:
		_post_mat.set_shader_parameter("night", nf)
	for g in _town_light_sprites:
		(g as Sprite2D).modulate.a = nf * TOWN_LIGHT_ALPHA

# 夜度曲线（同岛上 game.gd）：8~17 点纯白天；17~21 点天在暗；21~5 点最暗；5~8 点天在亮
func _night_at(h: float) -> float:
	if h >= 8.0 and h < 17.0:
		return 0.0
	if h >= 17.0 and h < 21.0:
		return (h - 17.0) / 4.0
	if h >= 21.0 or h < 5.0:
		return 1.0
	return 1.0 - (h - 5.0) / 3.0

# 后处理跟着昼夜走：夜里泛光更浓、顶部天光转冷月光、晕影压深。慢慢过渡, 别日落那刻啪地跳。
func _sync_post(delta: float) -> void:
	var want := _night_at(_sky_hours())
	_post_night = move_toward(_post_night, want, delta * 0.5)
	_apply_night(_post_night)

# 都城头顶的金星（e11h）: 五角星, 深色衬底 + 金面, 挂在城名正上方
func _make_capital_star() -> Node2D:
	var star := Node2D.new()
	star.name = "CapitalStar"
	star.position = Vector2(0, -92)
	var pts := PackedVector2Array()
	for i in 10:
		var r := 6.0 if i % 2 == 0 else 2.6
		pts.append(Vector2.from_angle(-PI / 2.0 + TAU * float(i) / 10.0) * r)
	var halo := Polygon2D.new()
	halo.polygon = pts
	halo.scale = Vector2(1.5, 1.5)
	halo.color = Color(0.22, 0.12, 0.02)
	star.add_child(halo)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(1.0, 0.83, 0.25)
	star.add_child(poly)
	return star

# 一间房 / 一件摆设：NEAREST 缩放贴图，pos 是左上角（底边压着格中心线用负高）。
# e19: tint 可选 —— 房子叠 25% 国色, 摆设不叠保持素材原色。
# e36m: 返回精灵本身 —— 房子要拿它算碰撞矩形（贴图不透明区 x 缩放）。
func _deco(parent: Node2D, path: String, sc: float, pos: Vector2, tint := Color(1, 1, 1),
		frame := Vector2i.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if frame == Vector2i.ZERO:
		s.texture = SoftRes.tex(path)
	else:
		s.texture = _first_frame(path, frame.x, frame.y)
	s.centered = false
	s.scale = Vector2(sc, sc)
	s.position = pos
	s.modulate = tint
	parent.add_child(s)
	return s

# ---------------- 城镇碰撞体积（e36m）----------------
# 贴图的不透明像素外框（一张只量一次）—— 房子的碰撞矩形按它算, 才算「符合贴图」:
# 素材图四周有大片透明留白, 直接拿图宽图高当碰撞体, 人会在离墙老远的地方被挡住。
func _opaque_bounds(path: String) -> Rect2:
	if _bounds_cache.has(path):
		return _bounds_cache[path]
	var img := _load_png(path)
	var minx := img.get_width()
	var miny := img.get_height()
	var maxx := -1
	var maxy := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.15:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	var r := Rect2()
	if maxx >= 0:
		r = Rect2(float(minx), float(miny), float(maxx - minx + 1), float(maxy - miny + 1))
	_bounds_cache[path] = r
	return r

# 给一间房登记碰撞矩形：贴图不透明区 × 缩放, 平移到城镇节点所在处。
func _add_blocker(town_pos: Vector2, spr: Sprite2D, path: String) -> void:
	var b := _opaque_bounds(path)
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return
	var sc := spr.scale.x
	_blockers.append(Rect2(town_pos + spr.position + b.position * sc, b.size * sc))

# 主角脚下半径 BODY_R 的圆压到任何一间房 = 挡住（矩形按贴图不透明区算）。
func _hits_building(pos: Vector2) -> bool:
	for r in _blockers:
		var rr: Rect2 = r
		if pos.x + BODY_R > rr.position.x and pos.x - BODY_R < rr.end.x \
				and pos.y + BODY_R > rr.position.y and pos.y - BODY_R < rr.end.y:
			return true
	return false

# 喷泉 / 灯柱的图是动画帧拼的（喷泉 4x2 帧 48x64，灯柱 2 帧 32x48）：
# 抽第一帧当静图用，省得整张贴出来变成一排喷泉。
var _deco_atlas := {}             # 路径 -> AtlasTexture（第一帧，缓存）

func _first_frame(path: String, fw: int, fh: int) -> Texture2D:
	if not _deco_atlas.has(path):
		var at := AtlasTexture.new()
		at.atlas = SoftRes.tex(path)
		at.region = Rect2(0, 0, float(fw), float(fh))
		_deco_atlas[path] = at
	return _deco_atlas[path]

func _town_banner_tex(col: Color) -> ImageTexture:
	var img := Image.create_empty(9, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 18:                            # 杆
		img.set_pixel(0, y, Color(0.42, 0.30, 0.18))
	for y in range(0, 7):                   # 旗面：国色 + 暗边
		for x in range(1, 9):
			img.set_pixel(x, y, col if x < 8 else col.darkened(0.25))
	return ImageTexture.create_from_image(img)

# ---------------- 国界线 ----------------
# 大陆按「离哪座城最近」划归属（城被玩家攻下 = 那片地划进玩家金色领地），
# 归属不同的陆地格共享边上画国界**实线**：深色衬线打底 + 一条归属国色。
# 2026-09-19 重做（用户截图：虚线断断续续像裂缝）：
#   · 四方向查边 —— 沿海那段也画（领地圈到海岸就收口），不再走到海边凭空断掉；
#   · 只有一条边两侧有归属时才画，无主荒野不再描土灰线；
#   · 整条边一个颜色（这侧格子的归属色），不再 4 段虚线交错 —— 转角处相位
#     对不上就是「不连贯」的元凶，实线一劳永逸。
# 距所有城都超过 60 格的陆地算无主荒野（主角岛就是这么隔在国界外的）。
# 想看国界挪动：攻下一座城（Nations.on_siege_victory 置 occupied），
# on_battle_done 会调 _rebuild_borders 重画。
class BorderLayer extends Node2D:
	var fills: Array = []    # [{rect: Rect2, color: Color}]
	var edges: Array = []   # [{a: Vector2, b: Vector2, c: Color}]

	func redraw_map(f: Array, e: Array) -> void:
		fills = f
		edges = e
		queue_redraw()

	func _draw() -> void:
		for fd in fills:
			draw_rect(fd["rect"], fd["color"])
		for ed in edges:                        # 深色衬线打底，国色浮得出来
			draw_line(ed["a"], ed["b"], Color(0.14, 0.11, 0.09, 0.85), 3.0)
		for ed in edges:
			draw_line(ed["a"], ed["b"], ed["c"], 1.5)

var _borders: BorderLayer = null

func _build_borders() -> void:
	_borders = BorderLayer.new()
	_borders.name = "Borders"
	# 树序在 Tiles/树/码头之后、主角之前：国界盖过树影, 但不糊在玩家脸上。
	add_child(_borders)
	_rebuild_borders()

# 格子的归属：最近的城镇（60 格内）；城被玩家占了就整片归「player」。
func _owner_of(c: Vector2i) -> String:
	var best := ""
	var bd := 60.0 * 60.0
	for tid in Nations.TOWNS.keys():
		var tc: Vector2i = Nations.TOWNS[tid]["cell"]
		var d2 := float((c.x - tc.x) * (c.x - tc.x) + (c.y - tc.y) * (c.y - tc.y))
		if d2 < bd:
			bd = d2
			best = tid
	if best == "":
		return ""
	if Nations.occupied.has(best):
		return "player"
	return Nations.owner_nation_of(best)   # e26b: 按现控制国涂色, 国战打赢了国土跟着变色

func _owner_color(owner: String) -> Color:
	if owner == "player":
		return PLAYER_TERRITORY
	return Nations.nation(owner).get("color", Color(0.6, 0.65, 0.75))

# 重算归属重画国界（只在建图 / 打完仗调，不是每帧）。
func _rebuild_borders() -> void:
	if _borders == null:
		return
	var owner := {}
	var fills: Array = []
	for c in _land.keys():
		var o := _owner_of(c)
		owner[c] = o
		if o != "":
			var col := _owner_color(o)
			var a := 0.10 if o == "player" else 0.07
			fills.append({"rect": Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)),
				"color": Color(col.r, col.g, col.b, a)})
	var edges: Array = []
	# 陆-陆共享边只画一次（上/右归这格画），陆-海边从陆地这侧画
	# （海格自己不画边，所以四方向都要查 —— 领地沿海岸线收口，圈是闭合的）
	for c in _land.keys():
		var o: String = owner[c]
		for step in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + step
			var col := Color(0, 0, 0)
			if _land.has(n):
				if step.y == 1 or step.x == -1:
					continue              # 下/左邻边由邻格的上/右那笔画，不重复
				var o2: String = owner.get(n, "")
				if o == o2 or (o == "" and o2 == ""):
					continue
				col = _owner_color(o) if o != "" else _owner_color(o2)
			else:
				if o == "":
					continue              # 无主地的海岸不描边
				col = _owner_color(o)
			var p := Vector2(c) * CELL
			var a := p
			var b := p
			match step:
				Vector2i(0, -1):
					b = p + Vector2(CELL, 0)
				Vector2i(0, 1):
					a = p + Vector2(0, CELL)
					b = p + Vector2(CELL, CELL)
				Vector2i(-1, 0):
					b = p + Vector2(0, CELL)
				Vector2i(1, 0):
					a = p + Vector2(CELL, 0)
					b = p + Vector2(CELL, CELL)
			edges.append({"a": a, "b": b, "c": col})
	_borders.redraw_map(fills, edges)

# 走没走近哪座城镇（变了才刷 hint，不每帧重排字符串）
func _update_town_hint() -> void:
	var best := ""
	for m in _town_marks:
		if avatar.position.distance_to(m["pos"]) < TOWN_DIST:
			best = String(m["tid"])
			break
	if best == _near_town:
		return
	_near_town = best
	_hint.text = _hint_text()

# 云影：几块很淡的暗斑贴着海面慢慢飘。一大片纯色海水最缺的就是这种「活气」，
# 有了它深浅水之间的接缝也更容易被忽略。
# ❗这几张图单独开 LINEAR 过滤：云影是柔和渐变，用像素图那套最近邻会被切成色阶。
func _build_cloud_shadows() -> void:
	var tex := _cloud_shadow_tex()
	var holder := Node2D.new()
	holder.name = "CloudShadows"
	add_child(holder)                       # 在 Tiles 之后、Trees 之前 = 盖着海面、压着树底
	var rnd := RandomNumberGenerator.new()
	rnd.seed = SEED + 77
	for _i in 6:
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.modulate = Color(1, 1, 1, 0.13)
		var base := Vector2(rnd.randf_range(120.0, MAP_W * CELL - 120.0),
			rnd.randf_range(120.0, MAP_H * CELL - 120.0))
		s.position = base
		s.scale = Vector2(rnd.randf_range(2.2, 3.6), rnd.randf_range(1.7, 2.6))
		holder.add_child(s)
		# 横着飘：慢 + SINE 缓动，来回一趟好几十秒，不会晃眼
		var span := rnd.randf_range(200.0, 340.0)
		var dur := rnd.randf_range(30.0, 46.0)
		var tw := create_tween().set_loops()
		tw.tween_property(s, "position:x", base.x + span, dur).set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "position:x", base.x - span, dur * 1.4).set_trans(Tween.TRANS_SINE)

func _cloud_shadow_tex() -> ImageTexture:
	var w := 64
	var h := 36
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var nx := (float(x) + 0.5 - float(w) * 0.5) / (float(w) * 0.5)
			var ny := (float(y) + 0.5 - float(h) * 0.5) / (float(h) * 0.5)
			var a := 1.0 - clampf(sqrt(nx * nx + ny * ny), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.03, 0.14, 0.30, a * a))
	return ImageTexture.create_from_image(img)

# ---------------- 滤镜 / 光影 ----------------
# 跟主岛同一套思路：一张全屏渐变贴图压在画面最上面 —— 上暖（日光）下冷（深海底色）
# + 四角暗角；再往深水区撒一圈会呼吸的粼光。CanvasLayer 排在 HUD 之前，
# 时钟框和提示字都不吃滤镜。❗渐变贴图开 LINEAR：柔和渐变用最近邻会切成色阶。
func _build_fx() -> void:
	# 深水区的粼光：46 颗，各自呼吸（tween 循环），亮度/周期错开相位
	var holder := Node2D.new()
	holder.name = "Sparkles"
	add_child(holder)
	_spark_holder = holder
	var rnd := RandomNumberGenerator.new()
	rnd.seed = SEED + 5150
	var dot := _spark_tex()
	var made := 0
	var tries := 0
	while made < 46 and tries < 1600:
		tries += 1
		var c := Vector2i(rnd.randi_range(2, MAP_W - 3), rnd.randi_range(2, MAP_H - 3))
		if not _water.has(c) or int(_sea_d.get(c, 0)) < 3:
			continue                  # 只撒在够深的水上，岸边不凑热闹
		made += 1
		var s := Sprite2D.new()
		s.texture = dot
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = _cell_center(c) + Vector2(rnd.randf_range(-6.0, 6.0), rnd.randf_range(-6.0, 6.0))
		holder.add_child(s)
		var dur := rnd.randf_range(1.6, 3.2)
		var tw := create_tween().set_loops()
		tw.tween_property(s, "modulate:a", 0.55, dur * 0.5).from(0.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "modulate:a", 0.0, dur * 0.5).set_trans(Tween.TRANS_SINE)
	# e15c 唯美化: 暖冷渐变 + 昼夜天色 + 日月光盘 + 海面光带 + 顶边远海雾（王国新风）
	# 全走世界层 Node2D（Movie Writer 会丢 CanvasLayer 填充控件, 见天色系统成员区注释）
	_build_sky(self)
	_build_farboats()

# ---------------- 天色系统（e15c）----------------
# 全天色键: [小时, 覆盖色, 覆盖强度, 光盘色, 光盘强度, 光带强度]。
# 出海时时间停摆(e13a) -> 海图定格在出发那一刻的天色: 早上出海是晨光海,
# 晚十点回岛前是暮色海 —— 宣传片里直接拨 TimeManager.hour 就能拍黄昏。
const SKY_KEYS := [
	[0.0,  Color(0.05, 0.09, 0.24), 0.50, Color(0.72, 0.82, 1.00), 0.30, 0.07],
	[4.5,  Color(0.08, 0.12, 0.28), 0.46, Color(0.72, 0.82, 1.00), 0.26, 0.07],
	[6.0,  Color(1.00, 0.82, 0.64), 0.14, Color(1.00, 0.80, 0.55), 0.42, 0.12],
	[8.0,  Color(1.00, 0.96, 0.88), 0.05, Color(1.00, 0.92, 0.72), 0.32, 0.09],
	[16.0, Color(1.00, 0.94, 0.84), 0.10, Color(1.00, 0.88, 0.62), 0.34, 0.09],
	[18.5, Color(1.00, 0.55, 0.28), 0.42, Color(1.00, 0.60, 0.34), 0.46, 0.14],
	[20.0, Color(0.13, 0.16, 0.34), 0.46, Color(0.80, 0.86, 1.00), 0.22, 0.08],
	[24.0, Color(0.05, 0.09, 0.24), 0.50, Color(0.72, 0.82, 1.00), 0.30, 0.07],
]

func _build_sky(root: Node2D) -> void:
	# [牺牲品] 保险丝(同 battle_map._build_night 的配方): 战场实测 Movie 模式进场帧
	#   「最先建的那批含纹理节点」可能整批不渲染, 先扔一张图外深蓝块占住名额。
	#   海图天色窗口/Movie 双模式已探针实测正常(2026-09-20), 此块未证实必需, 留作保险。
	var sac := Sprite2D.new()
	var simg := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	simg.fill(Color(0.05, 0.07, 0.20, 0.5))
	sac.texture = ImageTexture.create_from_image(simg)
	sac.position = Vector2(-20000, -20000)   # 图外远海, 不入镜
	root.add_child(sac)
	# 天色根: 世界层 Node2D, 跟随相机铺满屏幕; z 抬到地图装饰之上, HUD(CanvasLayer)永远在其上
	_sky_root = Node2D.new()
	_sky_root.name = "Sky"
	_sky_root.z_index = 60
	root.add_child(_sky_root)
	var vp := get_viewport_rect().size
	# 暖冷渐变+暗角(e12e): 160x90 纹理 LINEAR 拉伸铺屏
	_grade_spr = Sprite2D.new()
	_grade_spr.name = "Grade"
	_grade_spr.texture = _grade_tex()
	_grade_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_grade_spr.centered = false
	_grade_spr.scale = vp / Vector2(160, 90)
	_sky_root.add_child(_grade_spr)
	# 顶边远海雾：8x64 纹理拉伸铺屏（纹理只有顶部带 alpha, 大气透视的错觉）
	var haze := Sprite2D.new()
	haze.name = "Haze"
	haze.texture = _haze_tex()
	haze.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	haze.centered = false
	haze.scale = vp / Vector2(8, 64)
	_sky_root.add_child(haze)
	# 昼夜覆盖色: 全屏块(load 全屏白 PNG 原生尺寸铺 + modulate 上色;
	# 窗口/Movie 双模式探针实测渲染正常 —— 早先「不渲染」是探针带画到视野外的误判)
	_dn_rect = Sprite2D.new()
	_dn_rect.name = "DayNight"
	_dn_rect.texture = load("res://resources/fx/white_screen.png")
	_dn_rect.centered = false
	_dn_rect.modulate = Color(1, 1, 1, 0)
	_sky_root.add_child(_dn_rect)
	# 太阳/月亮柔光盘 + 海面光带（都是加法混合; 根节点做缩放补偿, 子节点用屏幕坐标）
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Sprite2D.new()
	_glow.name = "SunMoon"
	_glow.texture = _glow_tex()
	_glow.material = add_mat
	_sky_root.add_child(_glow)
	_band = Sprite2D.new()
	_band.name = "LightBand"
	_band.texture = _band_tex()
	_band.material = add_mat
	_band.rotation_degrees = -14.0
	_sky_root.add_child(_band)

func _sky_hours() -> float:
	# e16d: 航行中天色走演出钟（真实时刻只在落地回岛后接管）
	if Voyage.traveling and _voy_clock >= 0.0:
		return _voy_clock
	return float(TimeManager.hour) + float(TimeManager.minute) / 60.0

# 按色键插值: 返回 [覆盖色(含alpha), 光盘色, 光盘强度, 光带强度]
func _sky_sample(t: float) -> Array:
	var keys: Array = SKY_KEYS
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var u := (t - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			var col: Color = (a[1] as Color).lerp(b[1], u)
			var al: float = lerpf(float(a[2]), float(b[2]), u)
			var gc: Color = (a[3] as Color).lerp(b[3], u)
			var ga: float = lerpf(float(a[4]), float(b[4]), u)
			var ba: float = lerpf(float(a[5]), float(b[5]), u)
			return [Color(col.r, col.g, col.b, al), gc, ga, ba]
	var last: Array = keys[-1]
	return [Color(last[1].r, last[1].g, last[1].b, float(last[2])), last[3], float(last[4]), float(last[5])]

func _refresh_sky(delta: float) -> void:
	_sky_t += delta
	# e16d: 航行演出钟推进 —— 首次衔接出发时刻, 之后每 VOY_DAY_SEC 秒转一天
	if Voyage.traveling:
		if _voy_clock < 0.0:
			_voy_clock = float(TimeManager.hour) + float(TimeManager.minute) / 60.0
		_voy_clock = fmod(_voy_clock + delta * (24.0 / VOY_DAY_SEC), 24.0)
	# 天色根跟随相机(世界层铺屏): 原点=屏幕左上角, 观景档拉远时 scale 反向补偿, 覆盖始终=全屏
	if _sky_root != null:
		var cam := get_viewport().get_camera_2d()
		if cam != null:
			var vp0 := get_viewport_rect().size
			_sky_root.global_position = cam.get_screen_center_position() - vp0 * 0.5 / cam.zoom.x
			_sky_root.scale = Vector2.ONE / cam.zoom.x
	if _dn_rect == null:
		return
	var s := _sky_sample(_sky_hours())
	_dn_rect.modulate = s[0]
	var vp := get_viewport_rect().size
	var t := _sky_hours()
	# 太阳/月亮沿浅弧扫: 白天 5.5~19.5 从左到右, 夜里走另外一段
	var day := t >= 5.5 and t < 19.5
	var u := 0.0
	if day:
		u = clampf((t - 5.5) / 14.0, 0.0, 1.0)
	else:
		u = clampf(fposmod(t - 19.5, 24.0) / 10.0, 0.0, 1.0)
	var gy := vp.y * (0.54 - 0.36 * sin(u * PI)) + sin(_sky_t * 0.7) * 2.0
	_glow.position = Vector2(lerpf(vp.x * 0.12, vp.x * 0.88, u), gy)
	_glow.modulate = Color(s[1].r, s[1].g, s[1].b, s[2])
	# 光带: 斜搭在海面上, 缓慢呼吸
	_band.modulate = Color(s[1].r * 0.85, s[1].g * 0.85, s[1].b, s[3] * (0.8 + 0.2 * sin(_sky_t * 0.5)))
	_band.position = Vector2(vp.x * 0.5, vp.y * (0.34 + 0.05 * sin(_sky_t * 0.23)))
	var bs := Vector2(vp.x * 1.9 / 256.0, vp.y * 0.42 / 24.0)
	_band.scale = bs
	# 粼光夜里转冷白 —— 星光落在海上的倒影感
	if _spark_holder != null:
		var nf := clampf(maxf((5.2 - t) / 1.6, (t - 19.8) / 1.6), 0.0, 1.0)
		_spark_holder.modulate = Color(1, 1, 1).lerp(Color(0.72, 0.85, 1.15), nf)
	# 远帆剪影慢漂（只在海图可见时动）
	if visible and _farboats != null:
		for info in _farboat_info:
			var sp: Sprite2D = info["spr"]
			var dir: float = float(info["speed"])
			var nx := sp.position.x + dir * delta
			if not is_water(Vector2(nx + signf(dir) * 10.0, sp.position.y)):
				info["speed"] = -dir          # 到岸边就掉头, 永远漂在水上
				nx = sp.position.x
			sp.position.x = nx
			sp.position.y = float(info["y0"]) + sin(_sky_t * 1.1 + float(info["ph"])) * 1.6

# 顶边雾: 8x64, 从天光色 alpha 0.15 淡到 0
func _haze_tex() -> ImageTexture:
	var img := Image.create_empty(8, 64, false, Image.FORMAT_RGBA8)
	var sky := Color(0.66, 0.80, 0.94)
	for y in 64:
		var a := 0.15 * pow(1.0 - float(y) / 63.0, 1.6)
		for x in 8:
			img.set_pixel(x, y, Color(sky.r, sky.g, sky.b, a))
	return ImageTexture.create_from_image(img)

# 日/月光盘: 64x64 径向柔光, (1-r)^2 衰减
func _glow_tex() -> ImageTexture:
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 2.0) * 0.55
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

# 海面光带: 256x24, 横向 sin 包络 + 纵向边缘淡出
func _band_tex() -> ImageTexture:
	var w := 256
	var h := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var env := pow(sin(PI * float(x) / float(w - 1)), 1.5)
		for y in h:
			var fy := 1.0 - absf(float(y) - float(h - 1) * 0.5) / (float(h) * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, env * fy * 0.5))
	return ImageTexture.create_from_image(img)

# 远帆剪影: 13x11 黑帆小船（深灰蓝, 半透明更远）
func _farboat_tex() -> ImageTexture:
	var img := Image.create_empty(13, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var sil := Color(0.10, 0.13, 0.20, 0.85)
	# 船身: 底部两行微外扩
	for x in range(1, 12):
		img.set_pixel(x, 9, sil)
		img.set_pixel(x, 8, sil)
	img.set_pixel(0, 8, sil)
	img.set_pixel(12, 8, sil)
	# 桅杆 + 三角帆
	for y in range(2, 9):
		img.set_pixel(6, y, sil)
	for y in range(3, 8):
		var ww := int(float(y - 2) * 0.9)
		for x in range(7, 7 + ww):
			img.set_pixel(x, y, Color(0.14, 0.17, 0.25, 0.7))
	return ImageTexture.create_from_image(img)

func _build_farboats() -> void:
	_farboats = Node2D.new()
	_farboats.name = "FarBoats"
	add_child(_farboats)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = SEED + 7777
	var tex := _farboat_tex()
	var made := 0
	var tries := 0
	while made < 3 and tries < 300:
		tries += 1
		var c := Vector2i(rnd.randi_range(4, MAP_W - 5), rnd.randi_range(4, MAP_H - 5))
		if not _water.has(c) or int(_sea_d.get(c, 0)) < 2:
			continue
		made += 1
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = _cell_center(c)
		s.modulate = Color(1, 1, 1, 0.55)
		s.flip_h = rnd.randf() < 0.5
		_farboats.add_child(s)
		_farboat_info.append({
			"spr": s,
			"speed": rnd.randf_range(4.5, 8.0) * (-1.0 if s.flip_h else 1.0),
			"y0": s.position.y,
			"ph": rnd.randf_range(0.0, TAU),
		})

# 全屏滤镜：只剩上暖 / 下冷的一层极淡色调（用户不要四周的暗角光晕）。
func _grade_tex() -> ImageTexture:
	var w := 160
	var h := 90
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var warm := Color(1.00, 0.95, 0.86)
	var cool := Color(0.88, 0.94, 1.00)
	for y in h:
		var t := float(y) / float(h - 1)
		var tc := warm.lerp(cool, t)
		for x in w:
			img.set_pixel(x, y, Color(tc.r, tc.g, tc.b, 0.06))
	return ImageTexture.create_from_image(img)

# 一颗粼光：3x3 亮心 + 四邻淡边
func _spark_tex() -> ImageTexture:
	var img := Image.create_empty(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(1, 1, Color(1, 1, 0.95))
	for p in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
		img.set_pixel(p.x, p.y, Color(1, 1, 0.95, 0.4))
	return ImageTexture.create_from_image(img)

# ---------------- 主角头像 + 船队 ----------------
func _setup_avatar() -> void:
	# 先把船队挂上（树序在前 = 画在下面），主角头像才压在船上面
	_fleet = Node2D.new()
	_fleet.name = "Fleet"
	add_child(_fleet)
	_build_fleet()

	avatar = Node2D.new()
	avatar.name = "Avatar"
	add_child(avatar)
	# ❗主角自己**不**再挂一条船：_build_fleet 画的第一条船就是他的座船
	#   （座位 0）。两处都画的话，两条船差几个像素叠在一起，看着像「双体船」。
	_av_sprite = AnimatedSprite2D.new()
	_av_sprite.position = Vector2(0, -14)
	_av_sprite.sprite_frames = _avatar_frames()
	_av_sprite.play(&"idle_down")
	avatar.add_child(_av_sprite)
	avatar.position = Voyage.world_pos
	for i in TRAIL_MAX:
		_trail.append(avatar.position)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(3, 3)
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = MAP_W * CELL
	_cam.limit_bottom = MAP_H * CELL
	avatar.add_child(_cam)
	_cam.make_current()

# 船队：出海要几条船就画几条（一船两人），每条船上坐着伙伴。
# ❗船员是按 Slaves.expedition 的人数画的 —— 勾了几个人出海，船上就有几个小人，
#   「人越多要的船越多」这件事在画面上直接看得见。
func _build_fleet() -> void:
	for c in _fleet.get_children():
		c.queue_free()
	_boat_sprites = []
	_crew = []
	for i in maxi(1, Voyage.boats_needed()):
		var s := Sprite2D.new()
		s.texture = BOAT_TEX
		# ❗带帆那张高 44（船身落在 25~42 行），offset 必须配 (0,-14)：
		#   centered 的绘制矩形 = position + offset - size/2 —— 这样船身才落回
		#   跟旧 32x20 图**逐像素一样**的位置，船员/船/主角的相对关系一点不漂。
		s.offset = Vector2(0, -14)
		s.position = Vector2(0, -2)
		# 头一条是主角坐的，画原尺寸；后面的护卫船略小一点，前后有层次
		if i > 0:
			s.scale = Vector2(0.88, 0.88)
			s.modulate = Color(0.92, 0.94, 1.0)
		_fleet.add_child(s)
		_boat_sprites.append(s)
	var seats := Voyage.BOAT_SEATS
	for k in Slaves.expedition.size():
		var s := Sprite2D.new()
		s.texture = _crew_tex(k)
		# 先按「零号座位是主角」的规矩摆一下；真正的每帧位置由 _update_fleet 定
		s.position = Vector2(_seat_x(k + 1), -9.0)
		s.z_index = 1                     # 坐在船面上（比船晚画一层就够，z 只是保险）
		_fleet.add_child(s)
		_crew.append(s)

# 海图上的人只有几像素高，用真人物贴图缩下去会糊 —— 直接画个 7x10 的小人
func _crew_tex(k: int) -> ImageTexture:
	var w := 7
	var h := 10
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var shirt: Color = CREW_COLORS[k % CREW_COLORS.size()]
	var skin := Color(0.95, 0.79, 0.61)
	var hair := Color(0.22, 0.15, 0.10)
	for y in range(1, 4):
		for x in range(2, 5):
			img.set_pixel(x, y, skin)
	for x in range(2, 5):
		img.set_pixel(x, 0, hair)
	for y in range(4, 8):
		for x in range(1, 6):
			img.set_pixel(x, y, shirt)
	# 两条胳膊：比身子深一档，看着有个人形
	img.set_pixel(1, 5, shirt.darkened(0.2))
	img.set_pixel(5, 5, shirt.darkened(0.2))
	for y in range(8, 10):
		img.set_pixel(2, y, Color(0.30, 0.24, 0.18))
		img.set_pixel(4, y, Color(0.30, 0.24, 0.18))
	return ImageTexture.create_from_image(img)

# 尾迹上第 f 个点 —— f 是**连续下标**（可以是小数）：
#   -1 = 主角此刻的实时位置, 0 = _trail[0]（最近一次采到的点）,
#   中间值 = 两点之间线性插值。船队每帧在采样点之间平滑滑过去 ——
#   原先只取整数点, 每 0.07 秒「啪」地跳 6px, 就是船一卡一卡的根子。
func _trail_at(f: float) -> Vector2:
	if _trail.is_empty() or avatar == null:
		return Vector2.ZERO
	if f <= -1.0:
		return avatar.position
	if f < 0.0:                       # 主角实时位置与最近采样点之间
		return avatar.position.lerp(_trail[0], f + 1.0)
	if _trail.size() < 2:
		return _trail[0]
	var i := clampi(floori(f), 0, _trail.size() - 2)
	var w := f - float(i)
	return (_trail[i] as Vector2).lerp(_trail[i + 1], w)

# 采样周期里剩的那一截（0~1）。船的下标 = 落后步数 + 它 —— 两次采样之间
# 船就是连续滑动的, 采样点切换的瞬间也不跳（换算过的连续性）。
func _trail_offset() -> float:
	return clampf(_trail_t / TRAIL_STEP, 0.0, 1.0)

# 每帧把船队摆到尾迹上；上岸（on_water = false）时船藏起来、船员改走路
func _update_fleet(on_water: bool) -> void:
	# e40: 海上**只显示船、不显示人** —— 主角贴图收进船里（0 号座位就是他的座船,
	#   他的「人」由船代替画出来）。上岸立刻放回来, 岛/陆地上走的还是那个 Josh。
	#   只藏贴图, avatar 节点本身不动 —— 相机挂在它下面, 藏节点会把镜头一起关掉。
	if _av_sprite != null:
		_av_sprite.visible = not on_water
	var off := _trail_offset()                # 连续下标：船在采样点之间平滑滑
	var seats := Voyage.BOAT_SEATS
	for i in _boat_sprites.size():
		var s: Sprite2D = _boat_sprites[i]
		s.visible = on_water
		s.flip_h = _boat_flip        # e40: 往西开时整队镜像（船头画在图的右边）
		# ❗头船（主角座船）直接钉在主角脚下 —— 不吃尾迹延迟，主角停船就停、
		#   主角拐弯船就拐，彻底贴住；早先它也走尾迹，永远慢一拍还一顿一顿。
		#   护卫船才沿尾迹滑行（有插值，照样连贯）。
		s.position = avatar.position if i == 0 \
			else _trail_at(i * TRAIL_PER_BOAT + off)
	for k in _crew.size():
		var c: Sprite2D = _crew[k]
		if on_water:
			# ❗座位号从 1 开始数：0 号座位是主角自己（他的贴图就画在 avatar 上）。
			#   坐头船的伙伴也直接钉在主角身上算座位偏移 —— 不然船贴住了、
			#   人还留在尾迹上，看着像坐到船外面漂。
			var seat: int = k + 1
			var bi: int = seat / seats
			var bp := avatar.position if bi == 0 \
				else _trail_at(bi * TRAIL_PER_BOAT + off)
			c.position = bp + Vector2(_seat_x(seat), -9.0)
		else:
			c.position = _trail_at(TRAIL_PER_CREW * (k + 1) + off - 1.0) + Vector2(0, -14)

# 第 seat 号座位坐在船的哪儿：0 号（主角）站船正中，1 号靠左舷，2 号靠右舷。
# 横向 10 px 是有讲究的 —— 再窄一点，同船的伙伴就会被主角 16 px 宽的贴图挡住脑袋。
func _seat_x(seat: int) -> float:
	var seats := maxi(1, Voyage.BOAT_SEATS)
	if seat <= 0:
		return 0.0
	if seats == 2:
		return -10.0 if (seat % 2) == 1 else 10.0
	# 以后要是一船三人以上，就沿船舷均匀排开（现在一船两人，走不到这支）
	return lerpf(-14.0, 14.0, float(seat % seats) / float(seats - 1))

func _avatar_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var rows := {"down": 0, "up": 1, "side": 2}
	# 站立：Idle.png 4 帧（第三方素材不入库(见 README), 缺失时留空不崩）
	var idle_tex: Texture2D = SoftRes.tex(JOSH_IDLE)
	for d in rows.keys():
		var an := StringName("idle_%s" % d)
		sf.add_animation(an)
		sf.set_animation_loop(an, true)
		sf.set_animation_speed(an, 6.0)
		for i in 4:
			var at := AtlasTexture.new()
			at.atlas = idle_tex
			at.region = Rect2(i * 32, rows[d] * 32, 32, 32)
			sf.add_frame(an, at)
	# 走动：Run.png 8 帧 x 3 行（跟岛上 player.gd 同一套行号）。
	# ❗出海乘船也是这套 —— 头像在船上一颠一颠地划桨，就是「乘船动画」；
	#   早先只放了 idle_*，走起来一动不动，看着像被冻住。
	var run_tex: Texture2D = SoftRes.tex(JOSH_RUN)
	for d in rows.keys():
		var an := StringName("walk_%s" % d)
		sf.add_animation(an)
		sf.set_animation_loop(an, true)
		sf.set_animation_speed(an, 10.0)
		for i in 8:
			var at := AtlasTexture.new()
			at.atlas = run_tex
			at.region = Rect2(i * 32, rows[d] * 32, 32, 32)
			sf.add_frame(an, at)
	return sf

# ---------------- 敌人游荡队 ----------------
func _spawn_parties() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + TimeManager.year * 1000 + TimeManager.season * 100 + TimeManager.day
	# 4 支海寇：在东南湾和湾口外的海面上逛（出海第一段航程的威胁）
	_try_spawn(rng, "海寇", 4, func(c: Vector2i) -> bool:
		return _water.has(c) \
			and Vector2(c).distance_to(BAY_CORNER) < 90.0)
	# 2 支山贼：巨岛内陆的陆地上逛（离出发岛远远的）
	_try_spawn(rng, "山贼", 2, func(c: Vector2i) -> bool:
		return _land.has(c) and c.x + c.y > 110 and c.x + c.y < 250)
	# e49: 2 支哥布林蛮族 —— 巨岛东侧的荒野窝着（比山贼更靠里、更荒, 六七人一伙）
	_try_spawn(rng, "哥布林", 2, func(c: Vector2i) -> bool:
		return _land.has(c) and c.x + c.y > 140 and c.x > 100, 4)
	# e49: 2 支魔物 —— 巨岛西侧山脚河谷成群出没（史莱姆/毒菇人一路）
	_try_spawn(rng, "魔物", 2, func(c: Vector2i) -> bool:
		return _land.has(c) and c.x + c.y > 140 and c.x <= 100, 3)
	# 每国 2 支巡逻军队：首领亲军（人多）+ 封臣军，在主城附近晃悠。
	# 中立不主动动武，走近按 F 军中交谈（聊天 / 送礼 / 签协议）。
	for n in Nations.NATIONS:
		var nid := String(n["id"])
		var cap: Dictionary = Nations.TOWNS.get(nid + "_cap", {})
		if cap.is_empty():
			continue
		var cap_cell: Vector2i = cap["cell"]
		_try_spawn_patrol(rng, nid, true, cap_cell)
		_try_spawn_patrol(rng, nid, false, cap_cell)

# 巡逻军队落点：主城附近 3~7 格的陆地上，别堵城门也别堵码头
func _try_spawn_patrol(rng: RandomNumberGenerator, nid: String, chief: bool,
		cap_cell: Vector2i) -> void:
	var tries := 0
	while tries < 300:
		tries += 1
		var c := cap_cell + Vector2i(rng.randi_range(-7, 7), rng.randi_range(-7, 7))
		if not _land.has(c):
			continue
		var cc := _cell_center(c)
		if cc.distance_to(_cell_center(cap_cell)) < 40.0:
			continue          # 别蹲在城门口
		if cc.distance_to(dock_island) < 60.0 or cc.distance_to(dock_continent) < 60.0:
			continue
		var nname := String(Nations.nation(nid).get("name", nid))
		var army := nname + ("亲军" if chief else "封臣军")
		var size := (4 if chief else 3) + rng.randi() % 2
		# 骑兵国（见 Nations.is_mounted）的巡逻队骑马出行
		_make_party(cc, "巡逻", size, nid, chief, army, Nations.is_mounted(nid))
		return

func _try_spawn(rng: RandomNumberGenerator, type: String, n: int, ok: Callable,
		min_size := 2) -> void:
	var tries := 0
	var made := 0
	while made < n and tries < 600:
		tries += 1
		var c := Vector2i(rng.randi_range(6, MAP_W - 7), rng.randi_range(6, MAP_H - 7))
		if not ok.call(c):
			continue
		# 别直接堵在码头门口
		if _cell_center(c).distance_to(dock_island) < 60.0 \
				or _cell_center(c).distance_to(dock_continent) < 60.0:
			continue
		# 也别堵在城镇门口（山贼蹲城门谁还敢进城）
		var too_close := false
		for m in _town_marks:
			if _cell_center(c).distance_to(m["pos"]) < 56.0:
				too_close = true
				break
		if too_close:
			continue
		_make_party(Vector2(c) * CELL + Vector2(8, 8), type, min_size + rng.randi() % 3)
		made += 1

# e26a: 占领城爆发叛乱 -> 在这座城附近刷一队叛军（Nations.pop_rebels 每天喂过来）
func spawn_rebels(tid: String) -> void:
	var t: Dictionary = Nations.TOWNS.get(tid, {})
	if t.is_empty():
		return
	var cap := 8 if String(t.get("kind", "")) == "capital" else 5
	var n := 2 if String(t.get("kind", "")) == "capital" else 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base: Vector2i = t.get("cell", Vector2i.ZERO)
	for i in n:
		for try_i in 60:
			var c := base + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
			if not _land.has(c):
				continue
			var cc := _cell_center(c)
			if cc.distance_to(_cell_center(base)) < 24.0:
				continue          # 别蹲在城门口
			_make_party(cc, "叛军", maxi(3, cap - i * 3), "", false, "", false)
			break
	announce("%s爆发叛乱! 叛军占了城外四野" % String(t.get("name", tid)), 3.5)

# e26a: 每天早上取走 Nations 的叛乱队列;
# e26b: 再取国战队列刷远征队, 海寇窝点被清剿后补员。
func _on_new_day_wm(_day: int) -> void:
	for tid in Nations.pop_rebels():
		spawn_rebels(tid)
	for w in Nations.pop_wars():
		spawn_expedition(String(w.get("from", "")), String(w.get("tid", "")))
	_pirate_respawn()
	_mob_respawn()                # e49: 哥布林窝 / 魔物群被清了也逐日回补
	_spawn_caravans()             # e26d: 每天抽签刷商队
	_spawn_bottles()              # e26d: 海上每天漂来漂流瓶
	_random_event()               # e26d: 奇遇抽签

# e26b: 海寇窝点周期刷新 —— 湾里海寇被清剿后, 每天早上补员回 4 支
func _pirate_respawn() -> void:
	var alive := 0
	for pd in parties:
		if String(pd.get("type", "")) == "海寇" and not bool(pd.get("gone", false)):
			alive += 1
	if alive >= 4:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_try_spawn(rng, "海寇", 4 - alive, func(c: Vector2i) -> bool:
		return _water.has(c) \
			and Vector2(c).distance_to(BAY_CORNER) < 90.0)

# e49: 哥布林窝 / 魔物群回补 —— 玩家清剿完, 隔天野外照样有得打（各保持 2 支）
func _mob_respawn() -> void:
	var gob := 0
	var mon := 0
	for pd in parties:
		if bool(pd.get("gone", false)):
			continue
		var t := String(pd.get("type", ""))
		if t == "哥布林":
			gob += 1
		elif t == "魔物":
			mon += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if gob < 2:
		_try_spawn(rng, "哥布林", 2 - gob, func(c: Vector2i) -> bool:
			return _land.has(c) and c.x + c.y > 140 and c.x > 100, 4)
	if mon < 2:
		_try_spawn(rng, "魔物", 2 - mon, func(c: Vector2i) -> bool:
			return _land.has(c) and c.x + c.y > 140 and c.x <= 100, 3)

# e26b: 国战远征队 —— 从攻方离目标最近的自家城集结, 直奔目标城换旗
func spawn_expedition(nid: String, tid: String) -> void:
	var goal: Dictionary = Nations.TOWNS.get(tid, {})
	if goal.is_empty() or String(goal.get("nation", "")) == nid:
		return
	var best_d := INF
	var start := Vector2.ZERO
	var found := false
	for otid in Nations.ai_towns_of(nid):
		var ot: Dictionary = Nations.TOWNS.get(otid, {})
		if ot.is_empty():
			continue
		var d: float = Vector2(ot.get("cell", Vector2i.ZERO) as Vector2i) \
				.distance_to(Vector2(goal.get("cell", Vector2i.ZERO) as Vector2i))
		if d < best_d:
			best_d = d
			start = _cell_center(ot.get("cell", Vector2i.ZERO) as Vector2i)
			found = true
	if not found:
		return
	_make_party(start + Vector2(0, 40.0), "远征", 3 + randi() % 3, nid,
			false, "", Nations.is_mounted(nid), tid)
	announce("%s远征军开拔! 目标: %s" % [
			String(Nations.nation(nid).get("name", nid)),
			String(goal.get("name", tid))], 3.5)

# ---------------- e34e 攻占过程 ----------------
# 远征队抵达城下 -> 进入围攻状态: 站桩敲城 + 城头挂攻城进度条,
# 进度走满 SIEGE_TIME 才真正易主; 期间玩家撞上打赢就解围（危机解除）。

func _begin_siege(pd: Dictionary, tcel: Vector2i) -> void:
	pd["sieging"] = true
	pd["siege_t"] = 0.0
	(pd["spr"] as AnimatedSprite2D).play(&"idle_down")
	var tid := String(pd["target"])
	var tname := String(Nations.TOWNS.get(tid, {}).get("name", tid))
	var an := String(Nations.nation(String(pd["nation"])).get("name", ""))
	if Nations.occupied.has(tid):
		announce("%s围攻%s! 速去增援, 打退敌军可解围!" % [an, tname], 4.0)
	else:
		announce("%s兵临%s城下, 正在攻占..." % [an, tname], 3.5)
	# 攻城进度条: 城头上方一条红条, 随进度涨
	var bar := Node2D.new()
	bar.position = _cell_center(tcel) + Vector2(-SIEGE_BAR_W * 0.5, -30.0)
	bar.z_index = 50
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.78)
	bg.size = Vector2(SIEGE_BAR_W, 5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.92, 0.32, 0.22, 0.95)
	fill.size = Vector2(0, 5)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	add_child(bar)
	pd["bar"] = bar
	pd["bar_fill"] = fill

# 攻城进度条每帧跟随（_process 的攻城分支调用）
func _update_siege_bar(pd: Dictionary) -> void:
	var fill: ColorRect = pd.get("bar_fill")
	if fill == null or not is_instance_valid(fill):
		return
	fill.size.x = SIEGE_BAR_W * clampf(float(pd.get("siege_t", 0.0)) / SIEGE_TIME, 0.0, 1.0)

# 摘掉攻城进度条（攻下 / 解围都调）
func _end_siege_bar(pd: Dictionary) -> void:
	var bar: Node = pd.get("bar")
	if bar != null and is_instance_valid(bar):
		bar.queue_free()
	pd.erase("bar")
	pd.erase("bar_fill")

# 攻城进度走满 -> 真正易主: 玩家占领的城走 Nations.player_town_lost,
# AI 的城走 ai_conquer_town（别家已抢先拿下的就白跑一趟, 就地解散）。
func _finish_siege(pd: Dictionary) -> void:
	var tid := String(pd["target"])
	var nid := String(pd["nation"])
	var tcel: Vector2i = Nations.TOWNS.get(tid, {}).get("cell", Vector2i.ZERO)
	var tname := String(Nations.TOWNS.get(tid, {}).get("name", tid))
	var an := String(Nations.nation(nid).get("name", nid))
	_end_siege_bar(pd)
	(pd["node"] as Node2D).queue_free()
	pd["gone"] = true
	var ncol: Color = Nations.nation(nid).get("color", Color(0.6, 0.65, 0.75))
	if Nations.occupied.has(tid):
		Nations.player_town_lost(tid, nid)
		_flag_ring(_cell_center(tcel), ncol)
		announce("%s攻陷了%s! 你的旗被扯了下来" % [an, tname], 4.0)
	elif Nations.owner_nation_of(tid) != nid:
		Nations.ai_conquer_town(tid, nid)
		_flag_ring(_cell_center(tcel), ncol)
		announce("%s拿下了%s, 城头变了旗色" % [an, tname], 3.5)

# ---------------- e26d 商队 / 漂流瓶 / 奇遇 ----------------

# e26d: 商队 —— 每天早上 65% 概率刷 1~2 支, 从随机国的一座城出发,
# 直奔别国任意一座城（复用远征的行军逻辑, 进城就地散伙）。
# 商队不主动动武也不触发遭遇战, 靠近按 F 买特产 / 打劫 / 放行。
func _spawn_caravans() -> void:
	if randf() > 0.65:
		return
	var n := 1 if randf() < 0.7 else 2
	var nids: Array = []
	for nat in Nations.NATIONS:
		nids.append(String(nat["id"]))
	if nids.is_empty():
		return
	var goal_pool: Array = Nations.TOWNS.keys()
	goal_pool.shuffle()
	for i in n:
		var from: String = nids[randi() % nids.size()]
		var towns: Array = Nations.ai_towns_of(from)
		if towns.is_empty():
			continue
		var origin: Vector2i = (Nations.TOWNS.get(String(towns[randi() % towns.size()]), {}) \
				as Dictionary).get("cell", Vector2i.ZERO)
		var goal := ""
		for tid in goal_pool:
			var td: Dictionary = Nations.TOWNS.get(tid, {})
			if not td.is_empty() and String(td.get("nation", "")) != from:
				goal = String(tid)
				break
		if goal == "":
			return
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for t in 60:
			var c: Vector2i = origin + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
			if not _land.has(c):
				continue
			var cc := _cell_center(c)
			if cc.distance_to(_cell_center(origin)) < 24.0:
				continue          # 别蹲在城门口
			_make_party(cc, "商队", 2 + rng.randi() % 2, from, false, "",
					Nations.is_mounted(from), goal)
			# 配一车货 + 一份报价（面板打开时展示）
			var npd: Dictionary = parties[parties.size() - 1]
			npd["goods"] = CARAVAN_GOODS[randi() % CARAVAN_GOODS.size()]
			npd["price"] = 25 + randi() % 21
			break

# e26d: 漂流瓶 —— 每天早上海上漂来 1~2 只（存瓶上限 5 只）, 划过去按 F 捞。
# 离码头和城镇远远的, 不跟它们抢 F 键的交互焦点。
func _spawn_bottles() -> void:
	_bottles = _bottles.filter(func(b): return is_instance_valid(b["node"]))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var want := mini(5 - _bottles.size(), 1 + rng.randi() % 2)
	for i in want:
		for t in 80:
			var c := Vector2i(rng.randi_range(6, MAP_W - 7), rng.randi_range(6, MAP_H - 7))
			if not _water.has(c):
				continue
			var pos := Vector2(c) * CELL + Vector2(8, 8)
			if pos.distance_to(dock_island) < 80.0 or pos.distance_to(dock_continent) < 80.0:
				continue
			var too_close := false
			for m in _town_marks:
				if pos.distance_to(m["pos"]) < 70.0:
					too_close = true
					break
			if too_close:
				continue
			_make_bottle(pos)
			break

func _make_bottle(pos: Vector2) -> void:
	var node := Node2D.new()
	node.position = pos
	var spr := Sprite2D.new()
	spr.texture = _bottle_tex()
	spr.scale = Vector2(1.6, 1.6)
	spr.position = Vector2(0, -6)
	node.add_child(spr)
	add_child(node)
	# 随浪轻轻起伏（小循环 tween 挂在瓶节点上, 捞走时跟着节点一起没）
	var tw := node.create_tween().set_loops()
	tw.tween_property(spr, "position:y", -9.0, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(spr, "position:y", -6.0, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bottles.append({"pos": pos, "node": node})

# 手搓一只 10x14 的像素漂流瓶: 软木塞 + 青玻璃 + 瓶中信（没有现成瓶子贴图）
func _bottle_tex() -> Texture2D:
	var img := Image.create(10, 14, false, Image.FORMAT_RGBA8)
	var glass := Color(0.45, 0.78, 0.72, 0.92)
	var cork := Color(0.62, 0.44, 0.28)
	var paper := Color(0.93, 0.88, 0.72)
	for y in range(3, 13):
		for x in range(2, 8):
			img.set_pixel(x, y, glass)
	for y in range(5, 11):
		for x in range(3, 7):
			img.set_pixel(x, y, paper)
	for x in range(3, 7):
		img.set_pixel(x, 2, glass)
		img.set_pixel(x, 1, cork)
	img.set_pixel(2, 2, glass)
	img.set_pixel(7, 2, glass)
	return ImageTexture.create_from_image(img)

# 捞瓶子: 55% 金币 / 45% 裹着的东西（鱼 / 农产品 1~2 件）
func _pick_bottle(idx: int) -> void:
	if idx < 0 or idx >= _bottles.size():
		return
	var b: Dictionary = _bottles[idx]
	_bottles.remove_at(idx)
	_near_bottle = -1
	var node: Node2D = b["node"]
	if is_instance_valid(node):
		node.queue_free()
	Audio.play_sfx("water", -6.0)
	if randi() % 100 < 55:
		var gold := 20 + randi() % 41
		Wallet.add_money(gold)
		Audio.play_sfx("coin", -4.0)
		_float_text(avatar.position, "+%d金币" % gold, Color(1, 0.88, 0.5))
		announce("捞起漂流瓶: 瓶里塞着 %d 枚金币!" % gold, 3.5)
	else:
		var keys := ["perch", "crayfish", "starfish", "wheat", "pumpkin", "egg",
			"carrot", "potato"]
		var it: ItemData = load("res://item/%s.tres" % String(keys[randi() % keys.size()]))
		var amount := 1 + randi() % 2
		if it != null:
			Inventory.add_item(it, amount)
			Audio.play_sfx("coin", -8.0, 1.2)
			_float_text(avatar.position, "%s x%d" % [it.display_name, amount], Color(0.85, 0.95, 0.8))
			announce("捞起漂流瓶: 瓶中信裹着 %s x%d" % [it.display_name, amount], 3.5)
		else:
			announce("捞起漂流瓶: 瓶中信被海水泡烂了", 3.5)
	_hint.text = _hint_text()

# e26d: 每天早上的奇遇抽签 —— 55% 平安无事, 45% 来一件小事（播报即生效）
func _random_event() -> void:
	if randi() % 100 < 55:
		return
	var pool := ["storm", "harvest", "trade", "flotsam", "rumor"]
	match pool[randi() % pool.size()]:
		"storm":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			_try_spawn(rng, "海寇", 1, func(c: Vector2i) -> bool:
				return _water.has(c) \
					and Vector2(c).distance_to(BAY_CORNER) < 110.0)
			announce("昨夜风暴扫过海面, 又一伙海寇漂进了湾里", 3.5)
		"harvest":
			var nids: Array = []
			for nat in Nations.NATIONS:
				nids.append(String(nat["id"]))
			if nids.is_empty():
				return
			var nid: String = nids[randi() % nids.size()]
			Nations.add_favor(nid, 2)
			Nations.push_notice("今年风调雨顺, %s的粮仓堆满了" % String(Nations.nation(nid).get("name", nid)))
			announce("%s迎来丰收祭, 对你的印象好了几分" % String(Nations.nation(nid).get("name", nid)), 3.5)
		"trade":
			Wallet.add_money(25)
			Audio.play_sfx("coin", -4.0)
			announce("贸易顺风! 过路商船缴了一笔税金 (+25)", 3.5)
		"flotsam":
			_spawn_bottles()
			announce("涨潮把好几只漂流瓶推上了海面", 3.5)
		"rumor":
			announce("酒馆水手在传: 远海漂着装满宝藏的瓶子", 3.5)

func _make_party(pos: Vector2, type: String, size: int, nation := "",
		chief := false, army_name := "", mounted := false, target := "") -> void:
	var node := Node2D.new()
	node.name = "Party%d" % _next_id
	node.position = pos
	var boat := Sprite2D.new()
	# 海寇坐的是船身（不挂帆）：一条队里还有 32px 高的真人站在船上, 帆会挡他脑袋
	boat.texture = BOAT_HULL_TEX
	boat.scale = Vector2(0.8, 0.8)
	boat.position = Vector2(0, -2)
	boat.visible = (type == "海寇")
	node.add_child(boat)
	var spr := AnimatedSprite2D.new()
	spr.position = Vector2(0, -14)
	# 各队各形象：海寇 Alex / 山贼 Manu / 五国巡逻和远征军按 SKIN_OF_NATION 分（再叠国色 tint）
	var skin := SKIN_PIRATE
	if type == "山贼":
		skin = SKIN_BANDIT
	elif type == "巡逻" or type == "远征" or type == "商队":
		skin = int(SKIN_OF_NATION.get(nation, 0))
	# 骑兵队：整幅「马+骑手」一张图 —— 人和马在同一个像素里, 天生同步,
	# 不会犯船队那种「马走一步人跟半步」的毛病。48px 帧缩到 2/3, 跟 32px 步兵等高。
	if mounted and (type == "巡逻" or type == "远征" or type == "商队"):
		spr.sprite_frames = _horse_frames()
		spr.scale = Vector2(2.0 / 3.0, 2.0 / 3.0)
	else:
		spr.sprite_frames = _party_frames(skin)
	spr.play(&"idle_down")
	node.add_child(spr)
	var l := Label.new()
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.position = Vector2(-20, -34)
	node.add_child(l)
	var pd := {
		"id": _next_id, "pos": pos, "dir": Vector2.ZERO, "t": 0.0,
		"type": type, "size": size, "node": node, "spr": spr, "lbl": l,
		"nation": nation, "chief": chief, "army": army_name, "pact": false,
		"mounted": mounted, "target": target,
	}
	if type == "巡逻":
		# 巡逻军队：按国配色 + 队名（亲军 / 封臣军），签了盟约变友军绿
		l.text = "%s x%d" % [army_name, size]
		pd["pact"] = Nations.is_trade(nation)
		_tint_patrol(pd)
	elif type == "商队":
		# e26d 商队：国色调掺金 = 走商不示警；靠近按 F 买特产 / 打劫
		var ccol: Color = Nations.nation(nation).get("color", Color(0.8, 0.7, 0.4))
		spr.modulate = ccol.lerp(Color(1, 0.95, 0.7), 0.35)
		l.text = "%s商队 x%d" % [String(Nations.nation(nation).get("name", nation)), size]
		l.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	elif type == "远征":
		# 远征军队：国色调红示警 + 国名标签（e26b 国战）
		var ecol: Color = Nations.nation(nation).get("color", Color(0.8, 0.5, 0.5))
		spr.modulate = ecol.lerp(Color(1, 0.6, 0.6), 0.3)
		l.text = "%s远征军 x%d" % [String(Nations.nation(nation).get("name", nation)), size]
		l.add_theme_color_override("font_color", Color(1, 0.75, 0.7))
	elif type == "哥布林" or type == "魔物":
		# e49: 蛮族绿皮 / 魔物紫皮 —— 跟赤红的野寇一眼分得开
		spr.sprite_frames = _mob_frames(type)
		var mcol := Color(0.85, 1.0, 0.8) if type == "哥布林" else Color(0.95, 0.82, 1.0)
		spr.modulate = mcol
		l.text = "%s x%d" % [type, size]
		l.add_theme_color_override("font_color", mcol)
	else:
		spr.modulate = Color(1.0, 0.55, 0.5)
		l.text = "%s x%d" % [type, size]
		l.add_theme_color_override("font_color", Color(1, 0.75, 0.7))
	add_child(node)
	parties.append(pd)
	_next_id += 1

# 巡逻军队配色：中立 = 国色调淡，签了协议 = 友军绿
func _tint_patrol(pd: Dictionary) -> void:
	var ncol: Color = Nations.nation(String(pd["nation"])).get("color", Color(0.6, 0.65, 0.75))
	var spr: AnimatedSprite2D = pd["spr"]
	var lbl: Label = pd["lbl"]
	if bool(pd["pact"]):
		spr.modulate = Color(0.55, 1.0, 0.55)
		lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	else:
		spr.modulate = ncol.lerp(Color(1, 1, 1), 0.35)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))

var _skin_frames := {}      # skin -> SpriteFrames（建一次复用，十来支队伍别各拼一套）

# 队伍帧图：Idle 4 帧 x3 向 + Run 8 帧 x3 向（行 0 下 / 1 上 / 2 侧，跟主角同一套行号）。
# 早先只有 Alex 的 idle_down 一套 —— 用户要前后左右动画 + 各队形象不同。
func _party_frames(skin: int) -> SpriteFrames:
	if _skin_frames.has(skin):
		return _skin_frames[skin]
	var base: String = SKIN_DIRS[wrapi(skin, 0, SKIN_DIRS.size())]
	var idle_tex: Texture2D = SoftRes.tex(base + "/Idle.png")
	var run_tex: Texture2D = SoftRes.tex(base + "/Run.png")
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var rows := {"down": 0, "up": 1, "side": 2}
	for d in rows.keys():
		var an := StringName("idle_%s" % d)
		sf.add_animation(an)
		sf.set_animation_loop(an, true)
		sf.set_animation_speed(an, 5.0)
		for i in 4:
			var at := AtlasTexture.new()
			at.atlas = idle_tex
			at.region = Rect2(i * 32, rows[d] * 32, 32, 32)
			sf.add_frame(an, at)
	for d in rows.keys():
		var an := StringName("walk_%s" % d)
		sf.add_animation(an)
		sf.set_animation_loop(an, true)
		sf.set_animation_speed(an, 10.0)
		for i in 8:
			var at := AtlasTexture.new()
			at.atlas = run_tex
			at.region = Rect2(i * 32, rows[d] * 32, 32, 32)
			sf.add_frame(an, at)
	_skin_frames[skin] = sf
	return sf

var _horse_sf: SpriteFrames = null

# 骑兵巡逻队的帧：Alex 马匹图 Horse run.png —— 192x144 = **6 帧 x 3 行的 32x48 网格**
# (e17c 改 32x48x6; 三行顺序跟人一样是 下/上/侧)。idle = 每行首帧（勒马）, walk = 整行 6 帧（策马）。
# ❗马和人画在同一帧里 —— 队伍怎么动都不会「人马分家」, 这正是用户点名的重点。
# ❗侧向帧默认朝**左**（马素材与步兵素材相反）—— flip 在游荡移动里按 mounted 区分。
func _horse_frames() -> SpriteFrames:
	if _horse_sf != null:
		return _horse_sf
	# 第三方素材不入库(见 README), 缺失时留空不崩
	var tex: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Alex/Horse/Horse run.png")
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var rows := {"down": 0, "up": 1, "side": 2}
	if tex != null:
		# e17c: Horse run.png 是 6 帧 x 3 行的 32x48 —— 早期照步兵的 48x48 x 4 帧切,
		# 马被劈成两半(海图巡逻骑兵贴图碎裂的根源, 战场 troop.gd 的 e16c 同源)。
		for d in rows.keys():
			var an_idle := StringName("idle_%s" % d)
			sf.add_animation(an_idle)
			sf.set_animation_loop(an_idle, true)
			sf.set_animation_speed(an_idle, 4.0)
			sf.add_frame(an_idle, _horse_at(tex, 0, int(rows[d])))
			var an_walk := StringName("walk_%s" % d)
			sf.add_animation(an_walk)
			sf.set_animation_loop(an_walk, true)
			sf.set_animation_speed(an_walk, 9.0)
			for i in 6:
				sf.add_frame(an_walk, _horse_at(tex, i, int(rows[d])))
	_horse_sf = sf
	return sf

func _horse_at(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 32, row * 48, 32, 48)
	return at

# ---------------- 哥布林 / 魔物的海图形象（e49） ----------------
# 素材: Enemy/ 下。跟人一样是 32x32 一格、纵向 4 行（下/上/侧/侧镜像, 只用前 3 行）,
# 帧数按图宽自动数 —— 哥布林有 Run(8 帧), 魔物只有 Walk(4~6 帧), 所以走这一套自动刷子,
# 不用人的「写死 4+8 帧」那套。
const MOB_MAP_DIR := {
	"哥布林": "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Enemy/Goblins/Spear Goblin",
	"魔物": "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Enemy/Myconid/Green",
}
var _mob_frames_cache := {}

func _mob_frames(type: String) -> SpriteFrames:
	if _mob_frames_cache.has(type):
		return _mob_frames_cache[type]
	var dir := String(MOB_MAP_DIR.get(type, MOB_MAP_DIR["魔物"]))
	var idle_tex: Texture2D = SoftRes.tex(dir + "/Idle.png")
	# Myconid 等魔物没有 Run 帧, 先探测再 load, 免得缺文件刷报错
	var run_tex: Texture2D = null
	if FileAccess.file_exists(dir + "/Run.png"):
		run_tex = SoftRes.tex(dir + "/Run.png")
	if run_tex == null:
		run_tex = SoftRes.tex(dir + "/Walk.png")
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	var rows := {"down": 0, "up": 1, "side": 2}
	for d in rows.keys():
		var an := StringName("idle_%s" % d)
		sf.add_animation(an)
		sf.set_animation_loop(an, true)
		sf.set_animation_speed(an, 5.0)
		_add_mob_row(sf, an, idle_tex, int(rows[d]))
		var an2 := StringName("walk_%s" % d)
		sf.add_animation(an2)
		sf.set_animation_loop(an2, true)
		sf.set_animation_speed(an2, 10.0)
		_add_mob_row(sf, an2, run_tex, int(rows[d]))
	_mob_frames_cache[type] = sf
	return sf

func _add_mob_row(sf: SpriteFrames, an: StringName, tex: Texture2D, row: int) -> void:
	if tex == null:
		return
	var n := maxi(1, int(tex.get_width() / 32))
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 32, row * 32, 32, 32)
		sf.add_frame(an, at)

# ---------------- HUD ----------------
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 2    # fx 天色层是 1: HUD 必须盖在天色上; 也避开 Movie Writer 同 layer 多层渲染丢层的坑
	add_child(_hud)
	# e36l 唯美化: 跟岛上同一份全屏后处理（泛光/色温分离/柔光/饱和/晕影）。
	# ❗垫在本层第 0 位 —— 只调世界画面, 提示字和时钟框画在它上面保持干净。
	var fx := ColorRect.new()
	fx.name = "PostFX"
	var mat := ShaderMaterial.new()
	mat.shader = FX_POST
	mat.set_shader_parameter("strength", POST_STRENGTH)
	fx.material = mat
	_post_mat = mat
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(fx)
	# preset 进树后再铺（同 game.gd: add_child 前铺不跟随视口扩张, 底部露亮带）
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(func() -> void:
		fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT))
	_hint = Label.new()
	_hint.text = _hint_text()
	_hint.add_theme_font_override("font", FONT_PIX)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_hint.position = Vector2(16, 12)
	_hud.add_child(_hint)
	# 右上角时钟框：和岛上同一个 clock.gd（日期/时间/钱/天气），出海也看得见。
	# 出海时间慢速流着（voyage.enter_travel 调 speed_scale），框里的时间跟着走。
	var clock: Control = (preload("res://scene/clock_panel.tscn") as PackedScene).instantiate()
	# 右上锚点: 任意窗口比例都距右 16px（固定 position 在高窗口会被裁出屏）
	clock.anchor_left = 1.0
	clock.anchor_right = 1.0
	clock.offset_left = -198.0
	clock.offset_right = -16.0
	clock.offset_top = 26.0
	clock.offset_bottom = 158.0
	_hud.add_child(clock)

# 左上角那几行说明。船队规模直接写在上面：人越多船越多，出海前就该心里有数。
func _hint_text() -> String:
	# e26d: 漂流瓶 / 商队提示放最前（离得最近的先亮出来）
	if _near_bottle >= 0 and _near_bottle < _bottles.size():
		return "海上漂着一只漂流瓶\n[F] 捞起来看看"
	if _near_caravan >= 0:
		var cd := _party_by_id(_near_caravan)
		if not cd.is_empty():
			var cn := String(Nations.nation(String(cd["nation"])).get("name", ""))
			return "%s商队 x%d\n[F] 做买卖 - 买特产 / 打劫 / 放行" % [
				cn, int(cd["size"])]
	if _near_patrol >= 0:
		var pd := _party_by_id(_near_patrol)
		if not pd.is_empty():
			var nname := String(Nations.nation(String(pd["nation"])).get("name", ""))
			return "%s (%s)\n[F] 军中交谈 - 聊天 / 送礼 / 签协议" % [String(pd["army"]), nname]
	if _near_town != "":
		var t: Dictionary = Nations.TOWNS.get(_near_town, {})
		var nid := String(t.get("nation", ""))
		var nname := String(Nations.nation(nid).get("name", ""))
		return "%s (%s)\n[F] 进城 - 集市 / 酒馆 / 议事厅" % [String(t.get("name", "")), nname]
	return "船 %d 艘 - 你 + %d 个伙伴 - 撞上敌人开打\nWASD 移动, 大陆在西北\n自家码头 F 返航 - 大陆码头 F 上岸 - 城镇 F 进城" % [
		Voyage.boats_needed(), Slaves.expedition.size()]

func _party_by_id(id: int) -> Dictionary:
	for p in parties:
		if int(p["id"]) == id:
			return p
	return {}

# 每帧找最近的巡逻军队（走近才提示军中交谈）
func _update_patrol_hint() -> void:
	var best := -1
	var bd := PATROL_DIST
	for p in parties:
		if String(p["type"]) != "巡逻":
			continue
		var d := avatar.position.distance_to(p["pos"])
		if d < bd:
			bd = d
			best = int(p["id"])
	if best != _near_patrol:
		_near_patrol = best
		_hint.text = _hint_text()

# e26d: 每帧找最近的商队（走近才提示做买卖）
func _update_caravan_hint() -> void:
	var best := -1
	var bd := CARAVAN_DIST
	for p in parties:
		if bool(p.get("gone", false)) or String(p["type"]) != "商队":
			continue
		var d := avatar.position.distance_to(p["pos"])
		if d < bd:
			bd = d
			best = int(p["id"])
	if best != _near_caravan:
		_near_caravan = best
		_hint.text = _hint_text()

# e26d: 每帧找最近的漂流瓶（划过去才提示按 F 捞）
func _update_bottle_hint() -> void:
	var best := -1
	var bd := BOTTLE_DIST
	for i in _bottles.size():
		var b: Dictionary = _bottles[i]
		if not is_instance_valid(b["node"]):
			continue
		var d := avatar.position.distance_to(b["pos"])
		if d < bd:
			bd = d
			best = i
	if best != _near_bottle:
		_near_bottle = best
		_hint.text = _hint_text()

func announce(text: String, dur := 3.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.62))
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# e26e: 播报从上方滑落到位, 淡入 - 停留 - 淡出
	l.position.y = 44
	l.modulate.a = 0.0
	_hud.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 60.0, 0.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.22)
	tw.chain().tween_interval(dur)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)

# ---------------- e26e 动画小件 ----------------
# 世界坐标飘字: 向上飘 26px 同时淡出, 1.1 秒散场（买卖 / 捞瓶子捡东西用）
func _float_text(pos: Vector2, txt: String, col := Color(1, 0.95, 0.75)) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.size = Vector2(240, 20)
	l.position = pos + Vector2(-120, -34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 60
	add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 26.0, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(l.queue_free)

# 水花: 主角上下船的一瞬间喷一小撮白点（CPUParticles2D 一发就散, 自回收）
func _splash(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 40
	p.amount = 12
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector2(0, -1)
	p.spread = 65.0
	p.initial_velocity_min = 22.0
	p.initial_velocity_max = 48.0
	p.gravity = Vector2(0, 110)
	p.scale_amount_min = 1.6
	p.scale_amount_max = 3.2
	p.color = Color(0.88, 0.96, 1.0, 0.85)
	add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(p.queue_free)

# 换旗波纹: 城头易主的地方炸开一圈国色圆环, 扩到 2.6 倍同时淡出
func _flag_ring(pos: Vector2, col: Color) -> void:
	if _ring_tex == null:
		var img := Image.create(36, 36, false, Image.FORMAT_RGBA8)
		var c := Vector2(17.5, 17.5)
		for y in 36:
			for x in 36:
				var d := c.distance_to(Vector2(x, y))
				if d >= 13.0 and d <= 16.0:
					img.set_pixel(x, y, Color(1, 1, 1, 0.9))
				elif d >= 11.0 and d < 13.0:
					img.set_pixel(x, y, Color(1, 1, 1, 0.35))
		_ring_tex = ImageTexture.create_from_image(img)
	var ring := Sprite2D.new()
	ring.texture = _ring_tex
	ring.position = pos
	ring.z_index = 45
	ring.modulate = Color(col.r, col.g, col.b, 0.9)
	ring.scale = Vector2(0.4, 0.4)
	add_child(ring)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(2.6, 2.6), 0.9) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.9) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)

# 面板弹入: 0.85 倍 + 透明起步, 回弹放大到原大（命名弹窗 / 商队弹窗共用）
func _pop_panel(panel: Control) -> void:
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var pop := func() -> void:
		panel.pivot_offset = panel.size / 2.0
		var tw := panel.create_tween()
		tw.set_parallel(true)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.24) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.14)
	pop.call_deferred()

# 走一步（e36m）：先按输入方向试, 撞上城镇建筑就沿墙滑（单轴退让, 先 X 后 Y）,
# 两轴都不行才原地不动 —— 贴着墙走会顺着墙根滑过去, 不会一头顶死在墙角。
func _step_avatar(want: Vector2) -> void:
	var pos := avatar.position
	if _hits_building(want):
		var slid_x := Vector2(want.x, pos.y)
		var slid_y := Vector2(pos.x, want.y)
		if not _hits_building(slid_x):
			want = slid_x
		elif not _hits_building(slid_y):
			want = slid_y
		else:
			want = pos
	avatar.position = Vector2(
		clampf(want.x, 8.0, MAP_W * CELL - 8.0),
		clampf(want.y, 8.0, MAP_H * CELL - 8.0))
	Voyage.world_pos = avatar.position

# ---------------- 主循环 ----------------
func _physics_process(delta: float) -> void:
	if not visible:
		return          # 战斗进行中（本场景被藏起来）：天色/后处理/缩放全部别推进
	# 观景档平滑（e12h）: 缩放 tween + 镜头滑向大陆中心 + 涂色/国名淡入。
	if _cam != null and not is_equal_approx(float(_cam.zoom.x), _zoom_target):
		_cam.zoom = (_cam.zoom as Vector2).lerp(Vector2(_zoom_target, _zoom_target),
			minf(1.0, delta * 6.0))
	# 观景档（zoom < 1 整图拉远）: 几千棵树全挤进一屏, 整体藏掉省一大笔绘制
	if _trees_root != null and _trees_root.visible == (_zoom_target < 1.0):
		_trees_root.visible = _zoom_target >= 1.0
	if _view_t > 0.0 or _zoom_target < 1.0:
		var want_v := 1.0 if _zoom_target < 1.0 else 0.0
		_view_t = move_toward(_view_t, want_v, delta * 1.4)
		var vc := Vector2(VIEW_CENTER.x * CELL, VIEW_CENTER.y * CELL)
		_cam.offset = (vc - avatar.position) * _view_t
		if _view_t > 0.5:
			_cam.limit_left = -4096
			_cam.limit_top = -4096
			_cam.limit_right = MAP_W * CELL + 4096
			_cam.limit_bottom = MAP_H * CELL + 4096
		elif _view_t < 0.02:
			_cam.offset = Vector2.ZERO
			_cam.limit_left = 0
			_cam.limit_top = 0
			_cam.limit_right = MAP_W * CELL
			_cam.limit_bottom = MAP_H * CELL
		for lb in _nation_labels:
			(lb as Label).modulate.a = _view_t
	# e52c: 放大壮观层 —— zoom 4 档起淡入（拉回 3 档即收）
	var want_g := 1.0 if _zoom_target >= ZOOM_GRAND else 0.0
	if _grand_t > 0.0 or want_g > 0.0:
		_grand_t = move_toward(_grand_t, want_g, delta * 1.8)
		for lb in _grand_labels:
			(lb as Label).modulate.a = float((lb as Label).get_meta("a")) * _grand_t
	if _nation_tint != null and (_view_t > 0.0 or _grand_t > 0.0):
		_nation_tint.modulate.a = minf(0.5, 0.40 * _view_t + 0.12 * _grand_t)
	_refresh_sky(delta)          # e15c: 昼夜天色 / 日月光盘 / 光带 / 远帆
	_sync_post(delta)            # e36l: 后处理夜度 + 城镇夜灯
	if _ui_lock:
		return          # 军中交谈面板开着：锁走动和遭遇判定
	_encounter_cd = maxf(0.0, _encounter_cd - delta)
	# 主角移动
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var on_water := is_water(avatar.position)
	if on_water != _was_water:      # e26e: 上下船切换沿, 喷一圈水花
		_splash(avatar.position)
		_was_water = on_water
	var speed := SPEED_WATER if on_water else SPEED_LAND
	if mv != Vector2.ZERO:
		_step_avatar(avatar.position + mv * speed * delta)
		# 头像朝向：走动切 walk_*（水上就是划桨的起伏 —— 乘船动画），停步回 idle_*
		var an: StringName
		if absf(mv.x) >= absf(mv.y):
			an = &"walk_side"
			_av_sprite.flip_h = mv.x < 0
			_boat_flip = mv.x < 0        # e40: 船队跟着掉头（船头画在右边）
		else:
			an = &"walk_up" if mv.y < 0 else &"walk_down"
		if _av_sprite.animation != an:
			_av_sprite.play(an)
	else:
		var cur := String(_av_sprite.animation)
		if cur.begins_with("walk_"):
			_av_sprite.play(StringName("idle_%s" % cur.trim_prefix("walk_")))
	# 尾迹：不管走没走都记（停下来时船队会慢慢赶上来，不会僵在半路）
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = TRAIL_STEP
		_trail.insert(0, avatar.position)
		while _trail.size() > TRAIL_MAX:
			_trail.pop_back()
	_update_fleet(on_water)
	_update_town_hint()
	_update_patrol_hint()
	_update_caravan_hint()        # e26d: 商队 / 漂流瓶的靠近提示
	_update_bottle_hint()
	# 敌人游荡 + 遭遇判定（e26b: 远征队直奔目标城, 其余随机游荡;
	# e26d: 商队也走目标城, 进城就地散伙）
	var remove_gone := false
	for p in parties:
		var pd: Dictionary = p
		var ptype := String(pd["type"])
		if String(pd.get("target", "")) != "" and (ptype == "远征" or ptype == "商队"):
			# —— 远征行军: 朝目标城走, 到城下先围攻一段时间再换旗（e34e;
			# 撞河就斜着绕）; 商队照旧进城散伙 ——
			var tcel: Vector2i = Nations.TOWNS.get(String(pd["target"]), {}).get("cell", Vector2i.ZERO)
			var to: Vector2 = _cell_center(tcel) - (pd["pos"] as Vector2)
			if ptype == "远征" and bool(pd.get("sieging", false)):
				# —— e34e: 攻城中 —— 围在城下敲城, 站桩不动; 进度走满才易主,
				# 期间玩家撞上打赢就解围（落到底部共用遭遇判定）
				pd["siege_t"] = float(pd.get("siege_t", 0.0)) + delta
				_update_siege_bar(pd)
				if float(pd["siege_t"]) >= SIEGE_TIME:
					_finish_siege(pd)
					remove_gone = true
					continue
			elif to.length() < 16.0:
				if ptype == "远征":
					_begin_siege(pd, tcel)   # e34e: 进城不再秒换旗, 先围攻一段时间
					continue
				# 商队进城散伙: 货进了城, 队伍就地解散（不播报, 免得刷屏）
				(pd["node"] as Node2D).queue_free()
				pd["gone"] = true
				remove_gone = true
				continue
			else:
				var edir: Vector2 = to.normalized()
				var nxt2: Vector2 = (pd["pos"] as Vector2) + edir * 20.0 * delta
				if is_water(nxt2):
					var slid: Vector2 = (pd["pos"] as Vector2) + edir.rotated(PI * 0.45) * 20.0 * delta
					if is_water(slid):
						slid = (pd["pos"] as Vector2) + edir.rotated(-PI * 0.45) * 20.0 * delta
					if not is_water(slid):
						nxt2 = slid
					else:
						nxt2 = pd["pos"]        # 四面是水: 先驻足, 下帧再试
				pd["pos"] = nxt2
				(pd["node"] as Node2D).position = pd["pos"]
				_party_anim(pd, edir)
			# 远征队不设防: 撞上玩家照样开打（下面共用遭遇判定）
		else:
			pd["t"] = float(pd["t"]) - delta
			if float(pd["t"]) <= 0.0:
				pd["t"] = randf_range(1.5, 3.5)
				pd["dir"] = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			var ppos: Vector2 = pd["pos"]
			# 骑兵队马腿快：游荡速度比步兵队快一截（只影响观感, 巡逻队不主动动武）
			var pspd := 16.0 * (1.35 if bool(pd.get("mounted", false)) else 1.0)
			var nxt: Vector2 = ppos + (pd["dir"] as Vector2) * pspd * delta
			# 海寇只走水，山贼只走陆：越界就换个方向
			var want_water: bool = (pd["type"] == "海寇")
			if is_water(nxt) != want_water:
				pd["dir"] = -(pd["dir"] as Vector2)
			else:
				pd["pos"] = nxt
			var node: Node2D = pd["node"]
			node.position = pd["pos"]
			# 朝向动画：按游荡方向切 walk_*（前后左右四向都有），折返/停步也不穿帮
			_party_anim(pd, pd["dir"] as Vector2)
		if String(pd["type"]) == "巡逻":
			# 巡逻队平时不主动动武：盟约状态变了就刷新友军色。
			# e27e: 宣战国的巡逻队不再是友军 —— 不 continue, 落到底下共用遭遇判定, 撞上就开打。
			var hostile := Nations.at_war_with(String(pd["nation"]))
			var friendly := Nations.is_trade(String(pd["nation"])) and not hostile
			if bool(pd["pact"]) != friendly:
				pd["pact"] = friendly
				_tint_patrol(pd)
			if not hostile:
				continue
		if String(pd["type"]) == "商队":
			continue      # e26d: 商队不主动开战, 靠近按 F 做买卖
		if _encounter_cd <= 0.0 and avatar.position.distance_to(pd["pos"]) < ENCOUNTER_DIST:
			_start_battle(int(pd["id"]))
			return
	if remove_gone:
		parties = parties.filter(func(pp): return not bool(pp.get("gone", false)))

# 按 dir 切 walk_* 四向帧（海寇/山贼/叛军/远征/巡逻通用）。
# e27b: 人/马素材侧向帧实测都默认朝**右**（e17c 记反了）—— 统一「朝左才翻」。
func _party_anim(pd: Dictionary, pdir: Vector2) -> void:
	var pspr: AnimatedSprite2D = pd["spr"]
	var pan: StringName
	if pdir.length_squared() < 0.01:
		pan = &"idle_down"
	elif absf(pdir.x) >= absf(pdir.y):
		pan = &"walk_side"
		pspr.flip_h = pdir.x < 0
	else:
		pan = &"walk_up" if pdir.y < 0 else &"walk_down"
	if pspr.animation != pan:
		pspr.play(pan)

func _start_battle(id: int) -> void:
	for p in parties:
		if int(p["id"]) == id:
			_active_party = id
			Voyage.enter_battle(p)
			return

# 战斗打完回来（Voyage.end_battle 调用）
func on_battle_done(result: String) -> void:
	var party_pos := Vector2.ZERO
	var found := false
	var remaining: Array = []
	for p in parties:
		if int(p["id"]) == _active_party and result == "victory":
			# e34e: 打退正在攻城的远征队 -> 摘进度条 + 公告危机解除, 城头保住
			if bool(p.get("sieging", false)):
				_end_siege_bar(p)
				var stid := String(p.get("target", ""))
				announce("%s的攻势被打退, %s危机解除!" % [
					String(Nations.nation(String(p.get("nation", ""))).get("name", "")),
					String(Nations.TOWNS.get(stid, {}).get("name", stid))], 4.0)
			party_pos = p["pos"]          # 打赢：队伍消失
			found = true
			var node: Node = p["node"]
			node.queue_free()
			continue
		remaining.append(p)
	parties = remaining
	_active_party = -1
	if found:
		# 头像往后退一段，免得落地就再撞上（攻城战没有队伍，原地站着就行）
		var away := (avatar.position - party_pos)
		if away.length() < 1.0:
			away = Vector2(-1, -1)
		avatar.position += away.normalized() * 46.0
		Voyage.world_pos = avatar.position
	_encounter_cd = 2.5
	# e26e: 打赢一场就在原地炸一圈己方旗色波纹（队伍 battleground / 攻城战场通用）
	if result == "victory":
		_flag_ring(party_pos if found else avatar.position, PLAYER_TERRITORY)
	# 攻城打赢会置 Nations.occupied —— 国界线挪了，重画一遍
	_rebuild_borders()
	# 首城事件（e13d）: 第一座城到手 -> 同伴围着主角庆祝 + 给自己的国家起名
	if result == "victory" and Nations.pop_first_conquest():
		_celebrate_first_conquest()
		_open_nation_naming()
	# e42: 剧情过场都在这里放 —— 此刻结算页已经点掉、海图回来了, 盖不住战果。
	#   放过的段 play_once 自己记得, 不用这儿判断。
	if result == "victory":
		if Quests.has_navy_win():
			Cutscenes.play_once("ms_navy", 1.0)
		if Quests.has_milestone("ms_unify"):
			Cutscenes.play_once("ms_unify", 2.2)

# ---------------- 首城庆祝 + 国家命名（e13d） ----------------
# 同伴小人围着主角转圈庆祝（转两圈半, 5 秒散场）, 公告大字报喜。
# 小人摆在外圈固定点位, pivot 自转时整圈跟着转 —— 转轴转 2.5 圈后散场。
func _celebrate_first_conquest() -> void:
	announce("攻下第一座城!  伙伴们围着你欢呼!", 4.0)
	var pivot := Node2D.new()
	pivot.name = "Cheer"
	pivot.position = avatar.position
	add_child(pivot)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = SEED + 777
	for i in 5:
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = _party_frames(rnd.randi_range(0, SKIN_DIRS.size() - 1))
		spr.play(&"walk_down")
		spr.position = Vector2(26, 0).rotated(TAU * float(i) / 5.0)
		pivot.add_child(spr)
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: pivot.rotation = a,
		0.0, TAU * 2.5, 5.0)
	tw.tween_callback(pivot.queue_free)

# 国家命名弹窗（e13d）: 挂 _hud 居中, 起完名立刻写进 Nations 并刷海图上的领地名
func _open_nation_naming() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(wrap)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.06, 0.98)
	sb.border_color = PLAYER_TERRITORY
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	wrap.add_child(panel)
	_pop_panel(panel)      # e26e: 面板弹入
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "攻下第一座城!  给你的国家起个名字"
	title.add_theme_font_override("font", FONT_PIX)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.65))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tip := Label.new()
	tip.text = "这个名字会写在外交页和海图上 (最长 8 个字)"
	tip.add_theme_font_override("font", FONT_PIX)
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	var edit := LineEdit.new()
	edit.text = Nations.player_nation_name
	edit.max_length = 8
	edit.add_theme_font_override("font", FONT_PIX)
	edit.add_theme_font_size_override("font_size", 18)
	edit.custom_minimum_size = Vector2(0, 40)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(edit)
	var ok := Button.new()
	ok.text = "就这名了"
	ok.add_theme_font_override("font", FONT_PIX)
	ok.add_theme_font_size_override("font_size", 14)
	ok.custom_minimum_size = Vector2(0, 36)
	ok.pressed.connect(func() -> void:
		var old13: String = Nations.player_nation_name
		Nations.rename_player_nation(edit.text)
		for lb in _nation_labels:
			if (lb as Label).text == old13:
				(lb as Label).text = Nations.player_nation_name
		for lb in _grand_labels:      # e52c: 放大层的大字水印也跟着改名
			if (lb as Label).text == old13:
				(lb as Label).text = Nations.player_nation_name
		Audio.play_sfx("coin", -4.0)
		announce("你的国家就叫「%s」了!" % Nations.player_nation_name, 3.5)
		wrap.queue_free()
		# e42: 城破之后旗色易主 —— 等报喜的横幅读一下再放, 别一上来就盖住
		Cutscenes.play_once("siege_first", 1.6))
	box.add_child(ok)
	edit.call_deferred("grab_focus")

func _unhandled_input(event: InputEvent) -> void:
	# 鼠标滚轮拉近拉远海图（整数倍缩放，跟岛上一个规矩，防像素抖动）
	# e18f: 背包(Esc 界面)开着时缩放停止响应 —— 外界冻住, 滚轮不许再拉海图
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		var bp_w := _get_backpack_ui()
		if bp_w != null and bp_w.is_open():
			return                     # 背包盖着: 滚轮不缩海图, 事件留给 GUI
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(-1)
			get_viewport().set_input_as_handled()
			return
	# B / Esc 开合背包（任务栏跟着亮）—— 军中交谈开着时先不凑热闹
	if event.is_action_pressed("toggle_inventory"):
		var bp := _get_backpack_ui()
		if bp != null and bp.is_open():
			bp.close()               # 背包开着就先关它 —— 不然按键被吞, 界面卡死
		elif not _ui_lock:
			bp.toggle()
		get_viewport().set_input_as_handled()
		return
	# e18f: 背包(Esc 界面)开着时 A/D(或方向键) 左右切页签 —— avatar 已被 _ui_lock 冻住
	if _ui_lock:
		var bp_ad := _get_backpack_ui()
		if bp_ad != null and bp_ad.is_open():
			if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
				bp_ad.cycle_tab(-1)
				get_viewport().set_input_as_handled()
				return
			if event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
				bp_ad.cycle_tab(1)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("interact"):
		if avatar.position.distance_to(dock_island) < DOCK_DIST:
			Voyage.return_to_island()
			get_viewport().set_input_as_handled()
			return
		if avatar.position.distance_to(dock_continent) < DOCK_DIST:
			# 大陆码头按 F = 上岸，进「大陆据点」小场景（集市 / 酒馆都在那儿）
			Voyage.enter_mainland()
			get_viewport().set_input_as_handled()
			return
		if _near_town != "":
			# 城镇按 F = 进城（城镇小场景：集市 / 酒馆 / 议事厅）
			Voyage.enter_town(_near_town)
			get_viewport().set_input_as_handled()
			return
		if _near_patrol >= 0 and not _ui_lock:
			# 巡逻军队按 F = 军中交谈（聊天 / 送礼 / 签协议）
			var pd := _party_by_id(_near_patrol)
			if not pd.is_empty():
				# e27e: 宣战国的队伍不接待 —— 见面就是刀兵, 谈不了
				if Nations.at_war_with(String(pd["nation"])):
					announce("两国交战中, 对面的军营不会接待你", 2.5)
					get_viewport().set_input_as_handled()
					return
				var ui := _get_patrol_ui()
				ui.setup(String(pd["army"]), String(pd["nation"]))
				ui.open_panel()
				_ui_lock = true
				get_viewport().set_input_as_handled()
			return
		if _near_caravan >= 0 and not _ui_lock:
			# e26d: 商队按 F = 做买卖（买特产 / 打劫 / 放行）
			var cpd := _party_by_id(_near_caravan)
			if not cpd.is_empty():
				_open_caravan_panel(cpd)
				get_viewport().set_input_as_handled()
			return
		if _near_bottle >= 0 and not _ui_lock:
			# e26d: 漂流瓶按 F = 捞起来
			_pick_bottle(_near_bottle)
			get_viewport().set_input_as_handled()

# 滚轮缩放：整数档 2~6 之间照旧秒切（防像素抖动的老规矩）；
# 在最小档再往外缩 = 滑进 0.35 倍观景档（平滑过渡, 镜头滑向地图中心 + 国家涂色淡入），
# 观景档里放大 = 平滑拉回最近的整数档。
func _zoom_camera(step: int) -> void:
	if _cam == null:
		return
	var now := _cam.zoom.x
	var target := now
	if step > 0:
		if now <= ZOOM_VIEW + 0.01:
			target = float(ZOOM_MIN)          # 观景档放大: 平滑回最近整数档
		else:
			target = float(mini(int(round(now)) + 1, ZOOM_MAX))
	else:
		if now >= float(ZOOM_MIN) - 0.01 and now <= float(ZOOM_MIN) + 0.01:
			target = ZOOM_VIEW                # 已是最小整数档: 进观景档
		elif now >= float(ZOOM_MIN) - 0.01:
			target = float(maxi(int(round(now)) - 1, ZOOM_MIN))
		else:
			return                            # 已经拉满观景档, 不白响
	if is_equal_approx(target, now):
		return
	_zoom_target = target
	if target >= 1.0 and now >= 1.0:
		_cam.zoom = Vector2(target, target)   # 整数档之间秒切
	Audio.play_sfx("ui_click", -14.0)

# 军中交谈面板（懒加载，仿城镇面板）
func _get_patrol_ui() -> Control:
	if _patrol_ui == null:
		_patrol_ui = load("res://patrol_ui.gd").new()
		_patrol_ui.closed.connect(_on_patrol_closed)
		# ❗Control 面板必须挂 CanvasLayer（_hud）—— 直接挂在 Node2D 下
		#   锚点锚不到屏幕矩形，面板开在错误位置/零尺寸（看得见按键吞了，看不见面板）
		_hud.add_child(_patrol_ui)
	return _patrol_ui

func _on_patrol_closed() -> void:
	_ui_lock = false
	_near_patrol = -1
	_hint.text = _hint_text()

# e26d: 商队买卖弹窗 —— 买特产 / 打劫 / 放行（套国家命名弹窗骨架, 挂 _hud）
func _open_caravan_panel(cpd: Dictionary) -> void:
	_ui_lock = true
	var nid := String(cpd["nation"])
	var nname := String(Nations.nation(nid).get("name", nid))
	var item: ItemData = load("res://item/%s.tres" % String(cpd.get("goods", "wheat")))
	var iname := "一捆杂货" if item == null else String(item.display_name)
	var price := int(cpd.get("price", 30))
	var wrap := CenterContainer.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(wrap)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.06, 0.98)
	sb.border_color = PLAYER_TERRITORY
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	wrap.add_child(panel)
	_pop_panel(panel)      # e26e: 面板弹入
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "%s商队停下来搭话" % nname
	title.add_theme_font_override("font", FONT_PIX)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.65))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tip := Label.new()
	tip.text = "车上的伙计举起一件%s: %d 枚金币, 不二价!" % [iname, price]
	tip.add_theme_font_override("font", FONT_PIX)
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.72, 0.68, 0.6))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tip)
	if item != null and item.icon != null:
		var ic := TextureRect.new()
		ic.texture = item.icon
		ic.custom_minimum_size = Vector2(52, 52)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icwrap := CenterContainer.new()
		icwrap.add_child(ic)
		box.add_child(icwrap)
	var buy := Button.new()
	buy.text = "买特产 (-%d 金币)" % price
	buy.add_theme_font_override("font", FONT_PIX)
	buy.add_theme_font_size_override("font_size", 14)
	buy.custom_minimum_size = Vector2(0, 36)
	buy.pressed.connect(func() -> void:
		if Wallet.spend_money(price):
			if item != null:
				Inventory.add_item(item, 1)
			Nations.add_favor(nid, 1)
			Audio.play_sfx("coin", -4.0)
			_float_text(avatar.position, "-%d金币" % price, Color(1, 0.62, 0.5))
			announce("买下%s, 装进了船舱" % iname, 3.0)
		else:
			Audio.play_sfx("error")
			announce("口袋里的钱不够, 商人摇了摇头", 3.0)
		_close_caravan_panel(wrap))
	box.add_child(buy)
	var rob := Button.new()
	rob.text = "打劫 (抢钱抢货, 结下梁子)"
	rob.add_theme_font_override("font", FONT_PIX)
	rob.add_theme_font_size_override("font_size", 14)
	rob.custom_minimum_size = Vector2(0, 36)
	rob.pressed.connect(func() -> void:
		var loot := 15 + randi() % 31
		Wallet.add_money(loot)
		_float_text(avatar.position, "+%d金币" % loot, Color(1, 0.88, 0.5))
		if item != null:
			Inventory.add_item(item, 1)
		Nations.add_favor(nid, -3)
		Nations.push_notice("%s的商队在海上被劫了, 他们记下了你的船帆" % nname)
		(cpd["node"] as Node2D).queue_free()
		parties.erase(cpd)
		Audio.play_sfx("coin", -4.0)
		announce("抢了 %d 枚金币和一车货... %s跟你记仇了" % [loot, nname], 3.5)
		_close_caravan_panel(wrap))
	box.add_child(rob)
	var let_pass := Button.new()
	let_pass.text = "放行 (商队鸣笛致谢)"
	let_pass.add_theme_font_override("font", FONT_PIX)
	let_pass.add_theme_font_size_override("font_size", 14)
	let_pass.custom_minimum_size = Vector2(0, 36)
	let_pass.pressed.connect(func() -> void:
		Nations.add_favor(nid, 1)
		Audio.play_sfx("ui_click", -6.0)
		announce("商队鸣笛致谢, 继续赶路", 2.5)
		_close_caravan_panel(wrap))
	box.add_child(let_pass)

func _close_caravan_panel(wrap: Control) -> void:
	wrap.queue_free()
	_ui_lock = false
	_near_caravan = -1
	_hint.text = _hint_text()

# 背包面板（懒加载）+ 任务栏 —— 跟城里一个规矩：背包亮任务栏跟着亮
# ❗跟 _get_patrol_ui 同一个坑：Control 得挂 _hud（CanvasLayer）才显示得出来，
#   挂在 Node2D 下就是「按 Esc 像没反应」（其实开了，只是看不见）。
func _get_backpack_ui() -> Control:
	if _bp_ui == null:
		_bp_ui = load("res://backpack_ui.gd").new()
		_bp_ui.name = "Backpack"
		_hud.add_child(_bp_ui)
		# e13j: 任务栏搬进背包「任务」页签, 海图上不再挂独立的左侧任务栏
		_bp_ui.opened.connect(func():
			_ui_lock = true)
		_bp_ui.closed.connect(func():
			_ui_lock = false)
	return _bp_ui

# 从城镇 / 战斗回到海图后，把海图相机重新扶正（进城时它被别的相机顶掉了）
func resume_camera() -> void:
	if _cam != null:
		_cam.make_current()
