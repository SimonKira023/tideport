# slave_npc.gd —— 白天的「伙伴（奴隶）」
#
# 他们白天真的在农场里干活，不是站着摆样子：
#   夜里派了活（涂色的那些格子）→ 白天走过去 → 挥锄头/浇水/播种 → 那一格真的变了
#   （耕地会长出耕地贴图、浇过水的变湿土、播下去的会冒苗 —— 全是 Farm 那套信号在管）
#
# 一个伙伴的行动循环：
#   LOITER(闲逛) ──有活──> GO_WORK(走过去) ──> WORK(干活动画) ──> REST(喘口气) ──> 再挑活
#   没活了就回到 LOITER，从「涂过色的格子」里随机挑落点 —— 挑的是格子而不是随机坐标，
#   所以涂得密的地方被挑中的概率天然就高，人群自动聚过去。
#
# e30s 岗位（派活页六大板块的另外五块）：
#   被派去矿井/工地/铁匠铺/研究的人白天**不下地浇水**，各自走到岗位上干自己的活
#   （抡镐 / 铲土 / 抡锤 / 站门口钻研），见 POST 状态与 _post_of。
#   ❗「远航出征」不算岗位：那份名单是「下次出海带谁」，人平时还在岛上过日子，
#     真出海那天由 game.gd 的 board_to 接手（走上船 -> 藏起来）。
#
# ❗活儿干完会在 Slaves.done_today 上打个勾（今天不再碰这一格）。
#   assignments（计划）不删 —— 夜里那张涂色地图还要原样显示，方便复看和复涂。
#
# 模型：四个「不是主角」的预制角色轮流当班（主角是 Josh，伙伴换人演，一眼能分清）。
# ❗节点原点在**脚下**（精灵画在原点上方 16 像素）—— 跟主角、水井、房子一个约定，
#   这样挂在 Game 下才能跟它们一起做 y_sort 前后遮挡。
extends Node2D

enum State { LOITER, GO_WORK, WORK, REST, BOARD, POST }

const STEP_MOVING := 0
const STEP_ARRIVED := 1
const STEP_BLOCKED := 2       # 前头是水，这一趟走不通

const CELL := 32              # 一帧 32x32
const ARRIVE_DIST := 2.5
const BLOCK_TIME := 8.0       # 这格暂时干不了（比如还没耕地/没种子），隔这么久再回来试
const HIT_RATIO := 0.55       # 动画播到 55% 时「落下去」—— 视觉上正在使劲那一下

# 四个「不是主角」的预制角色
const MODELS := ["Alex", "Lyria", "Manu", "Tori"]
# 每个模型的性别（跟 MODELS 一一对应, 素材包里的真实长相）:
#   Alex=男(橙金短发) / Lyria=女(棕红卷发) / Manu=女(深肤黑发白帽) / Tori=女(橙红长发)。
# 招募名字池（slaves.gd）和头像分组（tools/make_portraits.gd）都按这张表对齐。
const MODEL_MALE := [true, false, false, false]
# e94: 咪露提到第 1 把交椅（用户指定）。美术槽位映射: 咪露(0)->Tori(3),
# 布恩(1)->Alex(0), 娜雅(3)->Lyria(1); 其余序号即槽位。
# 没有搬动 MODELS/RECIPES 这两张真相源表 —— 靠这张映射把序号接到模型上。
const ART_SWAP := {0: 3, 1: 0, 3: 1}
# 正式花名册的身份卡: 立绘、实体、船员和战场共用这一份对应关系。
# 旧的 20 套配方保留给历史数据和通用兵种, 不再用取模决定正式伙伴身份。
const IDENTITIES := [
	{"key": "slave_00", "model": "Lyria", "sprite": "slave_00", "hair": "59392f", "cloth": "62538c", "eyes": "8b67c5", "hair_style": "Fawn", "eye_style": "Female", "eye_dark": "694b88", "eye_light": "8b67c5", "shirt": "486985", "shirt_shadow": "39516a", "pants": "30313d", "clip": "b49ac6", "outfit": "jacket", "trim": "b49ac6", "hair_palette": {"32131e": "36282b", "8a3625": "49312e", "ae4924": "59392f", "c46120": "754a39", "d9884c": "94634a"}},
	{"key": "slave_01", "model": "Alex", "hair": "9e4e30", "cloth": "50565c", "hair_style": "Josh", "eye_style": "Male", "eye_dark": "734636", "eye_light": "ae7955", "shirt": "eee2c9", "shirt_shadow": "d7c3a4", "pants": "41404a", "outfit": "jacket", "trim": "bda072"},
	{"key": "slave_02", "model": "Manu", "hair": "29252e", "cloth": "b86f78", "hair_style": "Iridessa", "eye_style": "Female", "eye_dark": "653d2c", "eye_light": "a9663c", "shirt": "b86f78", "shirt_shadow": "8f5262", "pants": "57434e", "outfit": "blouse", "trim": "eee2c9", "headwear": "Beret", "headwear_color": "eee2c9", "skin_light": "bc8261", "skin_shadow": "8a574a"},
	{"key": "slave_03", "model": "Lyria", "hair": "bf632f", "cloth": "c69b42", "hair_style": "Lyria", "eye_style": "Female", "eye_dark": "7f4d32", "eye_light": "c18750", "shirt": "c69b42", "shirt_shadow": "a67a36", "pants": "65473e", "outfit": "pinafore", "trim": "4e8b83", "ribbon": "4e8b83"},
	{"key": "slave_04", "model": "Alex", "hair": "30313d", "cloth": "4b6b53", "hair_style": "Standard", "eye_style": "Male", "eye_dark": "5c4e75", "eye_light": "8b759f", "shirt": "4b6b53", "shirt_shadow": "354b40", "pants": "40363b", "outfit": "open_shirt", "trim": "ab936a"},
	{"key": "slave_05", "model": "Tori", "hair": "303a53", "cloth": "c7b895", "hair_style": "Silvermist", "eye_style": "Female", "eye_dark": "415579", "eye_light": "788eb2", "shirt": "eee2c9", "shirt_shadow": "c7b895", "pants": "58616a", "outfit": "apron", "trim": "c7b895", "ribbon": "3f8088"},
	{"key": "slave_06", "model": "Manu", "hair": "c4ccd0", "cloth": "467f96", "hair_style": "Josh", "eye_style": "Male", "eye_dark": "3c6b58", "eye_light": "719d78", "shirt": "467f96", "shirt_shadow": "345c75", "pants": "424d5b", "outfit": "open_shirt", "trim": "d9d2b8", "headwear": "Beret", "headwear_color": "eee2c9"},
	{"key": "slave_07", "model": "Tori", "hair": "c0af8b", "cloth": "79738b", "hair_style": "Lyria", "eye_style": "Female", "eye_dark": "596681", "eye_light": "8d99b2", "shirt": "79738b", "shirt_shadow": "56536d", "pants": "494052", "outfit": "fur_coat", "trim": "eee2c9"},
]
const BODY_SCALE := Vector2.ONE
const BODY_OFFSET := Vector2(0, -18)
# 成年女性的轻柔面部配色. 保留身份与身体比例, 只减弱硬阴影、加自然气色。
const FACE_STYLES := {
	"slave_00": {"eye_ink": "594359", "shadow": "e6b6a0", "blush": "d9959b", "lip": "ab7278", "nose": "dabbaa"},
	"slave_02": {"eye_ink": "573c41", "shadow": "a46b59", "blush": "a97166", "lip": "83504b", "nose": "b87e62"},
	"slave_03": {"eye_ink": "67433e", "shadow": "e4b898", "blush": "e4a18a", "lip": "ae7764", "nose": "e2bd9c"},
	"slave_05": {"eye_ink": "4b435a", "shadow": "e4b9a7", "blush": "d89e9f", "lip": "a7737e", "nose": "e5c3af"},
	"slave_07": {"eye_ink": "62516d", "shadow": "e2bcb2", "blush": "d6a1ad", "lip": "a17c8c", "nose": "dfc1b6"},
	"lord_beiling_cap": {"eye_ink": "665975", "shadow": "e2c1bb", "blush": "cda8b6", "lip": "9d7c8f", "nose": "e2c8be"},
	"lord_beiling_pine": {"eye_ink": "614d47", "shadow": "e4bca6", "blush": "e1a793", "lip": "ae8075", "nose": "e4c3ab"},
	"captain_tieyan": {"eye_ink": "51414f", "shadow": "ddbaae", "blush": "c596a5", "lip": "9f7784", "nose": "dfbfb0"},
}
# 立绘辨识特征: 在原生动作上补发型轮廓、帽饰与服装, 不改变花名册或身体比例。
const PORTRAIT_FITS := {
	"slave_00": {"portrait_fit": "straight_pony", "hair_style": "Silvermist", "costume_fit": "vest", "hair_tie": "b49ac6", "earrings": "b4cce1"},
	"slave_02": {"portrait_fit": "kerchief_curls", "hair_style": "Lyria", "costume_fit": "pink_blouse", "headwear": "kerchief", "headwear_color": "f4e6ce"},
	"slave_03": {"portrait_fit": "curly_pony", "costume_fit": "suspenders", "hair_tie": "4e8b83"},
	"slave_05": {"portrait_fit": "long_straight", "costume_fit": "apron", "hair_tie": "3f8088"},
	"slave_07": {"portrait_fit": "long_waves", "costume_fit": "winter_coat"},
	"lord_beiling_cap": {"portrait_fit": "royal_long", "costume_fit": "royal_coat", "earrings": "b7d9e5"},
	"lord_beiling_pine": {"portrait_fit": "hood_braid", "hair_style": "Silvermist", "costume_fit": "hood_cloak"},
	"captain_tieyan": {"portrait_fit": "braided_pony", "costume_fit": "riding_jacket", "hair_tie": "b99a70"},
}
const APPEARANCE := preload("res://scene/character_appearance.gd")
const PLAYER_IDENTITY := {"key": "player", "hair_style": "Sebastian", "eye_style": "Male", "eye_dark": "315f59", "eye_light": "549184", "shirt": "eee2c9", "shirt_shadow": "d7c3a4", "pants": "66504b", "hair_palette": {"32131e": "44312f", "8a3625": "6d4636", "ae4924": "8b5d42", "c46120": "a47551", "d9884c": "ba9167"}}
# 领主和队长按头像键取资料. 这里只管美术身份, 不改存档、关系或性别规则。
const NAMED_IDENTITIES := {
	"lord_chenxi_cap": {
		"key": "lord_chenxi_cap",
		"hair_style": "Standard",
		"hair": "805039",
		"cloth": "8c4d54",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "eee2c9",
		"shirt_shadow": "8c4d54",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "d6c5a1",
		"beard": true,
		"crown": "c2a05b"
	},
	"lord_chenxi_port": {
		"key": "lord_chenxi_port",
		"hair_style": "Standard",
		"hair": "30313d",
		"cloth": "454650",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "eee2c9",
		"shirt_shadow": "454650",
		"pants": "45404b",
		"outfit": "jacket",
		"trim": "4b8a88"
	},
	"lord_chenxi_bridge": {
		"key": "lord_chenxi_bridge",
		"hair_style": "Sebastian",
		"hair": "b5b9b4",
		"cloth": "9e8e7b",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "9e8e7b",
		"shirt_shadow": "9e8e7b",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "d6c5a1",
		"beard": true,
		"glasses": true
	},
	"lord_beiling_cap": {
		"key": "lord_beiling_cap",
		"hair_style": "Silvermist",
		"hair": "b9ced6",
		"cloth": "879fba",
		"eye_style": "Female",
		"eye_dark": "8f78ab",
		"eye_light": "8f78ab",
		"shirt": "879fba",
		"shirt_shadow": "879fba",
		"pants": "45404b",
		"outfit": "fur_coat",
		"trim": "eee2c9",
		"crown": "bcc9d0"
	},
	"lord_beiling_valley": {
		"key": "lord_beiling_valley",
		"hair_style": "Josh",
		"hair": "30313d",
		"cloth": "4a607c",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "4a607c",
		"shirt_shadow": "4a607c",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "aa8564",
		"beard": true
	},
	"lord_beiling_pine": {
		"key": "lord_beiling_pine",
		"hair_style": "Iridessa",
		"hair": "805039",
		"cloth": "526e58",
		"eye_style": "Female",
		"eye_dark": "70906b",
		"eye_light": "70906b",
		"shirt": "526e58",
		"shirt_shadow": "526e58",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "d6c5a1",
		"ribbon": "7ca17a"
	},
	"lord_xichuan_cap": {
		"key": "lord_xichuan_cap",
		"hair_style": "Standard",
		"hair": "534035",
		"cloth": "4c6650",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "eee2c9",
		"shirt_shadow": "4c6650",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "d6c5a1",
		"beard": true
	},
	"lord_xichuan_gold": {
		"key": "lord_xichuan_gold",
		"hair_style": "Sebastian",
		"hair": "b78c4f",
		"cloth": "b1914d",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "b1914d",
		"shirt_shadow": "b1914d",
		"pants": "45404b",
		"outfit": "open_shirt",
		"trim": "d6c5a1",
		"skin_light": "d7a17b",
		"skin_shadow": "b27a5b"
	},
	"lord_xichuan_reed": {
		"key": "lord_xichuan_reed",
		"hair_style": "Standard",
		"hair": "34323d",
		"cloth": "72926d",
		"eye_style": "Male",
		"eye_dark": "8b759f",
		"eye_light": "8b759f",
		"shirt": "eee2c9",
		"shirt_shadow": "72926d",
		"pants": "45404b",
		"outfit": "jacket",
		"trim": "d6c5a1"
	},
	"lord_tieyan_cap": {
		"key": "lord_tieyan_cap",
		"hair_style": "Josh",
		"hair": "b9bebf",
		"cloth": "756580",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "756580",
		"shirt_shadow": "756580",
		"pants": "45404b",
		"outfit": "fur_coat",
		"trim": "cac5b6",
		"beard": true,
		"crown": "9a9b9b"
	},
	"lord_tieyan_stone": {
		"key": "lord_tieyan_stone",
		"hair_style": "Standard",
		"hair": "393142",
		"cloth": "72535f",
		"eye_style": "Male",
		"eye_dark": "80658f",
		"eye_light": "80658f",
		"shirt": "72535f",
		"shirt_shadow": "72535f",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "a2a8b2"
	},
	"lord_tieyan_cliff": {
		"key": "lord_tieyan_cliff",
		"hair_style": "Sebastian",
		"hair": "5c3d32",
		"cloth": "47434d",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "47434d",
		"shirt_shadow": "47434d",
		"pants": "45404b",
		"outfit": "fur_coat",
		"trim": "a3a0a0",
		"beard": true
	},
	"lord_canglang_cap": {
		"key": "lord_canglang_cap",
		"hair_style": "Fawn",
		"hair": "554035",
		"cloth": "83705a",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "83705a",
		"shirt_shadow": "83705a",
		"pants": "45404b",
		"outfit": "fur_coat",
		"trim": "e3d6b5",
		"beard": true,
		"crown": "ad8856"
	},
	"lord_canglang_pasture": {
		"key": "lord_canglang_pasture",
		"hair_style": "Josh",
		"hair": "b36738",
		"cloth": "5d7356",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "5d7356",
		"shirt_shadow": "5d7356",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "c2a36d"
	},
	"lord_canglang_camp": {
		"key": "lord_canglang_camp",
		"hair_style": "Iridessa",
		"hair": "5c4434",
		"cloth": "8a6a4d",
		"eye_style": "Male",
		"eye_dark": "b08950",
		"eye_light": "b08950",
		"shirt": "8a6a4d",
		"shirt_shadow": "8a6a4d",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "b49b5f"
	},
	"captain_chenxi": {
		"key": "captain_chenxi",
		"hair_style": "Sebastian",
		"hair": "654536",
		"cloth": "4c607e",
		"eye_style": "Male",
		"eye_dark": "6689ad",
		"eye_light": "6689ad",
		"shirt": "4c607e",
		"shirt_shadow": "4c607e",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "c28a70"
	},
	"captain_beiling": {
		"key": "captain_beiling",
		"hair_style": "Josh",
		"hair": "bfc7cb",
		"cloth": "8097ad",
		"eye_style": "Male",
		"eye_dark": "879eb8",
		"eye_light": "879eb8",
		"shirt": "8097ad",
		"shirt_shadow": "8097ad",
		"pants": "45404b",
		"outfit": "fur_coat",
		"trim": "eee2c9",
		"beard": true
	},
	"captain_xichuan": {
		"key": "captain_xichuan",
		"hair_style": "Standard",
		"hair": "a08352",
		"cloth": "6d7b52",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "6d7b52",
		"shirt_shadow": "6d7b52",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "b29b61",
		"beard": true,
		"skin_light": "d7a17b",
		"skin_shadow": "b27a5b"
	},
	"captain_tieyan": {
		"key": "captain_tieyan",
		"hair_style": "Fawn",
		"hair": "393142",
		"cloth": "79515f",
		"eye_style": "Female",
		"eye_dark": "8c759e",
		"eye_light": "8c759e",
		"shirt": "96818a",
		"shirt_shadow": "79515f",
		"pants": "45404b",
		"outfit": "jacket",
		"trim": "9b8269"
	},
	"captain_canglang": {
		"key": "captain_canglang",
		"hair_style": "Iridessa",
		"hair": "30313d",
		"cloth": "4f7b73",
		"eye_style": "Male",
		"eye_dark": "a8824e",
		"eye_light": "a8824e",
		"shirt": "4f7b73",
		"shirt_shadow": "4f7b73",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "a78b61"
	},
	"generic_pirate": {
		"key": "generic_pirate",
		"hair_style": "Josh",
		"hair": "805039",
		"cloth": "665d70",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "eee2c9",
		"shirt_shadow": "665d70",
		"pants": "45404b",
		"outfit": "jacket",
		"trim": "946f5f"
	},
	"generic_bandit": {
		"key": "generic_bandit",
		"hair_style": "Sebastian",
		"hair": "5b483b",
		"cloth": "727b5b",
		"eye_style": "Male",
		"eye_dark": "8e795a",
		"eye_light": "8e795a",
		"shirt": "727b5b",
		"shirt_shadow": "727b5b",
		"pants": "45404b",
		"outfit": "coat",
		"trim": "b1a17b"
	}
}

const MODEL_PATH := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/%s"

# 每种动作一张图：32px 一帧、一行一个朝向（行 0 朝下 / 1 朝上 / 2 侧面，左右靠 flip_h）
const SHEETS := {
	"idle":   {"file": "Idle.png",     "frames": 4, "fps": 7.0,  "loop": true},
	# walk 的 fps 只是个初值：真正跑起来由 _sync_walk_speed 按 speed 反推
	"walk":   {"file": "Walk.png",     "frames": 6, "fps": 10.0, "loop": true},
	"hoe":    {"file": "Hoe.png",      "frames": 6, "fps": 13.0, "loop": false},
	"water":  {"file": "Watering.png", "frames": 8, "fps": 13.0, "loop": false},
	"sickle": {"file": "Sickle.png",   "frames": 6, "fps": 13.0, "loop": false},
	# e30s 岗位动作：循环播（人整天待在岗位上，动作不能播一遍就僵住）
	"pickaxe": {"file": "Pickaxe.png", "frames": 6, "fps": 10.0, "loop": true},
	"shovel":  {"file": "Shovel.png",  "frames": 5, "fps": 9.0,  "loop": true},
	"axe":     {"file": "Axe.png",     "frames": 6, "fps": 10.0, "loop": true},
}
const DIR_ROW := {"down": 0, "up": 1, "side": 2}

# 工种 -> 干活用哪套动作。数字跟 slaves.gd 的 TASK_* 一一对应：
# 那边是 autoload 里的常量，const 表达式取不到，所以在这儿写死，由自检对账。
const T_TILL := 1
const T_WATER := 2
const T_PLANT := 3
const TASK_ANIM := {T_TILL: &"hoe", T_WATER: &"water", T_PLANT: &"sickle"}
# （播种扣种子 / 睡前补完的真正逻辑在 slaves.gd apply_task，这里只管演。）

# e30s 岗位 -> 干活动作 / 站定朝向。
# 「科研」没有书桌类素材，用待机代替（人站在家门口钻研，重点是「不去地里浇水」）。
const POST_ANIM := {
	"mine": &"pickaxe",
	"dock": &"shovel",
	"smith": &"axe",
	"research": &"idle",
}
const POST_FACING := {
	"mine": &"up",        # 面朝矿门
	"dock": &"down",
	"smith": &"down",
	"research": &"down",
}
# 岗位干活的音效间隔与音量（比下地干活轻一点：好几个人一起抡会吵）
const POST_SFX_DB := -18.0
const POST_SFX_GAP := Vector2(0.9, 1.6)

# —— e29c: 伙伴局部改色配方（RECIPES[i] = 第 i 个伙伴的色带清单）——
# 用户要求: 伙伴长相各不一样, 但**只改局部**(发色/服装的色相带), 不做整体染色 ——
# 整体 modulate 连皮肤眼睛一起染, 很怪。改色发生在贴图 Image 层:
# 色带内像素的色相平移到目标色, 高光/阴影的明度按倍率缩放(层次保留),
# 色带外的皮肤/眼睛/轮廓线一概不碰。
# ❗「第 i 个伙伴长什么样」唯一真相源的一部分: 白天实体、篝火边的人、背包卡片墙、
#   战场小兵、船员 —— 全部贴图都走 sheet_texture()/recipe_for() 同一套。
# 色带依据 4 个模型图集的实采样色相分布(probe_model_colors 探针):
#   Alex: 橙金发 hue[0.00,0.15] 饱和≥0.40 / 蓝背带裤 hue[0.56,0.68] 饱和≥0.35
#         (浅青内衬、皮肤饱和度低被 smin 挡住; 蓝眼睛 hue 0.526 被 0.56 下限挡住)
#   Lyria: 棕红发 hue[0.02,0.10] 饱和≥0.45 / 红裙 hue[0.88,1.00]
#   Manu: 黑发+白帽+粉衣 —— 粉衣跟皮肤同色相改不了; 白帽/眼白/刀光都是无色相的
#         亮像素, 逐行探针实锤挥剑图里帽子和剑刃根本分不开 —— 所以白帽不动,
#         只给黑发「挑染」: 暗带(v0.06~0.28 低饱和, 轮廓线 v<0.06 挡住)在所有
#         动作图里只落在头发区, 整条染成彩色并抬明度 = 黑发染出颜色
#   Tori: 橙红长发 hue[0.00,0.17] 饱和≥0.40 / 紫裙 hue[0.78,0.92] 饱和≥0.35
# 带参数: band=[hue 起,hue 止](可跨 0/1) / to=目标色相(缺省不动) / vmul=明度倍率
#         smul=饱和倍率 / sset=饱和度直接定值 / smin/smax=饱和门槛 / vmin/vmax=明度门槛
#         ytop/ybot=帧内 y 范围
# 超出 20 人(行政研究加员额外)按 i%20 回绕 —— 跟 model_for 的轮换同一套防御。
const RECIPES := [
	# ---- Alex 组(男·橙金短发+蓝背带裤): 布恩(slot0) / 塔洛(slot4) ----
	# e94: 配色对齐布恩新头像(棕红短发+绿外套)
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.04, "vmul": 0.65},    # 00 布恩: 棕红发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.33, "vmul": 0.75}], #    绿外套
	# e94: 配色对齐塔洛新头像(黑发+绿毛衣)
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.0, "sset": 0.06, "vmul": 0.5},   # 01 塔洛: 黑发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.32, "smul": 0.55, "vmul": 0.85}], # 绿毛衣
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.22, "vmul": 0.75},    # 08 橄榄发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.75, "vmul": 0.80}], #    暗紫裤
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.55, "vmul": 0.85},    # 12 青蓝发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.07, "vmul": 0.85}], #    赭棕裤
	[{"band": [0.00, 0.15], "smin": 0.40, "to": 0.80, "vmul": 0.90},    # 16 粉紫发
		{"band": [0.56, 0.68], "smin": 0.35, "to": 0.60, "smul": 0.12}], #    炭灰裤
	# ---- Lyria 组(女·棕红卷发+红裙): 娜雅(slot1) / 汐月(slot5) ----
	# e94: 配色对齐娜雅新头像(橙棕高马尾+黄衬衫)
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.07, "vmul": 1.15},    # 05 娜雅: 亮橙棕发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.13, "vmul": 1.00}], #    黄衬衫
	# e94: 配色对齐汐月新头像(黑长直+米色衣)
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.0, "sset": 0.08, "vmul": 0.5},   # 06 汐月: 黑发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.12, "smul": 0.18, "vmul": 1.3}], # 米色衣
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.52, "vmul": 0.80},    # 09 青发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.13, "vmul": 1.00}], #    金黄裙
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.72, "vmul": 0.80},    # 13 紫发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.85, "vmul": 0.90}], #    玫紫裙
	[{"band": [0.02, 0.10], "smin": 0.45, "to": 0.00, "vmul": 0.60},    # 17 暗红褐发
		{"band": [0.88, 1.00], "smin": 0.30, "to": 0.00, "smul": 0.15}], #    炭灰裙
	# ---- Manu 组(女·黑发白帽粉衣): 珞琳(slot2) / 珂丹(slot6) ----
	# 发带: v0.06~0.28 的暗低饱和像素(黑发), 轮廓线 v<0.06、眼白 v≥0.5 都被挡住
	# e94: 配色对齐珞琳新头像(棕红卷发+浅绿衫; 粉衣与皮肤同色相改不动, 只染发)
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.05, "sset": 0.50, "vmul": 1.7}],                        # 10 珞琳: 棕红发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.93, "sset": 0.55, "vmul": 1.9}],                        # 11 珂丹: 玫红发(保留)
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.55, "sset": 0.50, "vmul": 1.9}],                        # 12 青蓝发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.30, "sset": 0.50, "vmul": 1.9}],                        # 13 草绿发
	[{"band": [0.0, 1.0], "smax": 0.35, "vmin": 0.06, "vmax": 0.28,
		"to": 0.09, "sset": 0.60, "vmul": 1.9}],                        # 14 金橙发
	# ---- Tori 组(女·橙红长发+紫裙): 咪露(slot3) / 雪莱(slot7) ----
	# e94: 配色对齐咪露头像(棕发侧马尾+紫罗兰夹克 —— 裙带紫是本色正好)
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.05, "vmul": 0.60},    # 15 咪露: 深棕发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.75, "vmul": 0.95}], #    紫夹克
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.11, "vmul": 1.00},    # 16 雪莱: 金发(保留)
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.97, "vmul": 0.85}], #    酒红裙
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.45, "vmul": 0.80},    # 17 青绿发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.32, "vmul": 0.80}], #    苔绿裙
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.66, "vmul": 0.85},    # 18 蓝紫发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.07, "vmul": 0.85}], #    赭棕裙
	[{"band": [0.00, 0.17], "smin": 0.40, "to": 0.90, "vmul": 0.90},    # 19 玫红发
		{"band": [0.78, 0.92], "smin": 0.35, "to": 0.00, "smul": 0.15}], #    炭灰裙
]

# 走路的「一个循环迈多远」：从 Walk.png 里量出来的 ——
# 侧身那 6 帧里两只脚分得最开时中心差约 5 像素，一个循环两步 -> 约 10 像素。
# 速度按它反推动画帧率，脚就踩得住地（不会像溜冰）。
const WALK_STRIDE_PX := 10.0
const WALK_FPS_CAP := 22.0    # 安全上限：只防呆，正常速度碰不到（见 _sync_walk_speed）

# 由 game.gd 在 add_child **之前**赋值（_ready 里要靠它选脸）
var index := 0

# ❗setter 里改动画速度：速度是**唯一真相源**，帧率永远跟着它算，
#   所以以后无论把速度调快调慢，动画都自动配得上（这是用户提的「速度配得上动画」）。
var speed: float = 30.0:
	set(v):
		speed = v
		_sync_walk_speed()
var _sprite: AnimatedSprite2D
var _state := State.LOITER
# e100 实机演出: live_view 接管时冻结 AI、外部喊走位（压过昼夜隐藏/闲逛/干活整套循环）
var cs_frozen := false
var cs_target := Vector2.INF
var _target := Vector2.ZERO           # 闲逛落点
var _work_cell := Vector2i(-999, -999)
var _rest := 0.0
var _gaze_t := 0.0                    # e54: 歇着时下一次张望（换朝向）还有多久
var _work_t := 0.0                    # 当前动作还剩多久
var _work_hit := 0.0                  # 播到这个时刻「落下去」
var _work_applied := false
var _facing: StringName = &"down"
var _rng := RandomNumberGenerator.new()
var _blocked := {}                    # Vector2i -> 剩余冷却秒数

# —— P1 情绪气泡（emote_bubble.gd）——
# 闲着的时候随机冒一个心情泡（星露谷式）; 冷却拉长免得满屏都是泡泡
const EMOTE := preload("res://scene/emote_bubble.gd")
const MOOD_CD_MIN := 20.0             # 两次冒泡的最短间隔（秒）
const MOOD_CD_MAX := 45.0
var _mood_cd := 30.0                  # 距离下一次随机冒泡还有多久（开局错开, 别一进游戏齐冒）

# —— e30s 岗位 ——
var _post := ""                       # 当前岗位键（"" = 照料作物, 下地干活）
var _post_spot := Vector2.ZERO        # 岗位站位（换岗时重算, 免得每帧抖）
var _post_t := 0.0                    # 距离下一次「岗位上出声」还有多久

# —— 出海登船 ——
# 出海那天，全体伙伴被叫到码头边（game.gd 负责摆位置），
# 再走上最后几步 -> _aboard = true 就藏起来，白天那套「挑活/干活」循环整个不参与。
# 船上的人数就是 Slaves.expedition，海图的船队照着它画船员。
var _aboard := false
var _board_dest := Vector2.ZERO

# 玩家走近交互的检测
const TALK_RANGE := 22.0              # 半径（玩家中心到伙伴中心的距离 < 这个才提示对话）
var _area: Area2D = null              # 玩家的 CharacterBody2D 走进时会触发
var _shape: CollisionShape2D = null
var _key_hint: Node2D = null          # 头顶的「F 对话」常驻提示
var _player_in_range := false         # 玩家走进了这个伙伴的对话半径

func _ready() -> void:
	# e33 脚下的影子（跟主角同款）
	# e36d 之后主角把影子的居中点抬到了 y=-7（贴图 32x32 里视觉脚底就在那一行，
	# 留在 y=0 会比脚底低 7px，看着像影子跟人分了家）—— 伙伴这边也要跟上，别一边改一边没改。
	var _sh := preload("res://scene/shadow_util.gd").make_shadow(18, 7, 0.28)
	_sh.position = Vector2(0, -7)
	add_child(_sh)
	_sprite = AnimatedSprite2D.new()
	_sprite.position = BODY_OFFSET          # 拉长身体后脚底仍贴住影子。
	_sprite.sprite_frames = build_frames(model_for(index), index)
	_sprite.play(&"idle_down")
	# e94: 身形收瘦 —— 横向 0.86, 头身比例更接近头像立绘
	_sprite.scale = body_scale_for(index)
	add_child(_sprite)
	_sync_walk_speed()                  # 步伐帧率由速度反推（setup 里定了速度还会再算一次）
	# e28e: 物理碰撞体积 —— 玩家走近会被挡住，不再穿过伙伴身体。
	# ❗伙伴自己的走位是直写 global_position（不查物理），这层只拦玩家、不拖累自己：
	#   layer 跟建筑一样在位值 4（玩家的 mask 7 覆盖得到），mask 0 = 谁也不挡。
	var _blk := StaticBody2D.new()
	_blk.name = "BodyBlock"
	_blk.collision_layer = 4
	_blk.collision_mask = 0
	var _blk_shape := CollisionShape2D.new()
	var _blk_circle := CircleShape2D.new()
	_blk_circle.radius = 5.5
	_blk_shape.shape = _blk_circle
	_blk_shape.position = Vector2(0, -6)     # 跟玩家的碰撞圆同高（圆心都悬在脚踝上方）
	_blk.add_child(_blk_shape)
	add_child(_blk)
	# 交互检测 Area
	_area = Area2D.new()
	_area.name = "TalkArea"
	_area.collision_layer = 0
	_area.collision_mask = 1                # 玩家 CharacterBody2D 在 layer 1
	add_child(_area)
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TALK_RANGE
	_shape.shape = circle
	_shape.position = Vector2(0, -8)
	_area.add_child(_shape)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	# 头顶对话提示
	_key_hint = preload("res://scene/key_hint.gd").new()
	_key_hint.setup("F", "对话", -62.0)
	_key_hint.connect("clicked", _try_talk)   # e36i: 左键点这个框 = 按 F（字符串写法, _key_hint 是 Node2D）
	add_child(_key_hint)
	# 晋升换甲：职业一变（Slaves.changed）就把身上的装甲色重刷一遍
	Slaves.changed.connect(_refresh_outfit)

# 由 game.gd 在入树后调用：给号、定速度、撒在集合点附近
func setup(i: int, near: Vector2) -> void:
	index = i
	_rng.seed = 9871 + i * 7717
	speed = _rng.randf_range(24.0, 36.0)
	global_position = _dry_spot(near)          # ❗撒点要挑陆地：撒进水里人就泡在那儿了
	_refresh_outfit()
	_decide_next()

# 一身行头的装甲档位色（e29c: 发色/服装的「个人配色」已烘进贴图层, 见 RECIPES;
# modulate 这层只剩装甲 —— 职业晋升（Slaves.changed）时当场重刷: 布衣->银甲->金铜甲。
# 两层天然可乘, 贴图层的个人色不会被装甲色盖掉。
func _refresh_outfit() -> void:
	var troop := String(Slaves.slave_at(index).get("troop", "新兵"))
	# 岛上穿生活服, 晋升不再把皮肤、头发和衣服整体染成金属色。
	modulate = Color.WHITE

# 集合点附近找个不落水的落脚处（试不出来就退到最近的一片岸上，绝不站水里）
func _dry_spot(near: Vector2, radius := 44.0) -> Vector2:
	for _try in 24:
		var p := near + Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
		if not _is_water_at(p):
			return p
	return _cell_center(_nearest_land(near))

# ---------------- 动画表 ----------------
# 拼一套动画。idx 是伙伴序号 —— 贴图按 RECIPES[idx] 局部改色（e29c）,
# 所以「第 i 个伙伴」不管出现在农场/战场/篝火/船上都长同一张脸。
# 静态：篝火、面板、背包都直接调, 不用为抽一张小像实例化整个伙伴。
static func build_frames(model: String, idx: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	for key in SHEETS.keys():
		var info: Dictionary = SHEETS[key]
		var tex := sheet_texture(model, info["file"], idx)
		if tex == null:
			push_error("伙伴素材加载失败:%s / %s" % [model, info["file"]])
			continue
		for d in DIR_ROW.keys():
			var an := StringName("%s_%s" % [key, d])
			sf.add_animation(an)
			sf.set_animation_loop(an, bool(info["loop"]))
			sf.set_animation_speed(an, float(info["fps"]))
			var row: int = DIR_ROW[d]
			for i in int(info["frames"]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * CELL, row * CELL, CELL, CELL)
				sf.add_frame(an, at)
	return sf

# 让走路动画的帧率跟着 speed 走：速度 = 步幅 / 循环时长，所以
#   循环时长 = 步幅 / 速度，帧率 = 帧数 / 循环时长 = 速度 * 帧数 / 步幅。
# 这样「脚踩住地」和「速度」永远同时成立，改速度不用再回头调帧率。
func _sync_walk_speed() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var frames := float(SHEETS["walk"]["frames"])
	var fps := minf(WALK_FPS_CAP, speed * frames / WALK_STRIDE_PX)
	for d in DIR_ROW.keys():
		var an := StringName("walk_%s" % d)
		if _sprite.sprite_frames.has_animation(an):
			_sprite.sprite_frames.set_animation_speed(an, fps)

# 当前用的是哪个模型（自检用来确认「伙伴不是主角那张脸」）
func model_name() -> String:
	return model_for(index)

# ---------------- 「第 i 个伙伴长什么样」的唯一真相源 ----------------
# 白天在农场跑的伙伴、篝火边站着等你的人、篝火面板里的小像 —— 三处都走这里，
# 于是「招募前在火边看到的那张脸」跟「招进来之后的脸」必然是同一张。
# 伙伴 i 的美术槽位（默认就是 i；只有调换过出场顺序的两把交椅走 ART_SWAP）。
static func art_slot(i: int) -> int:
	var m := maxi(0, i)
	return int(ART_SWAP.get(m, m))

static func model_for(i: int) -> String:
	if i >= 0 and i < IDENTITIES.size():
		return String(IDENTITIES[i]["model"])
	return MODELS[art_slot(i) % MODELS.size()]

static func identity_for(i: int, portrait_fit: bool = true) -> Dictionary:
	return _face_profile(IDENTITIES[i].duplicate(true), portrait_fit) if i >= 0 and i < IDENTITIES.size() else {}

static func _face_profile(profile: Dictionary, portrait_fit: bool = true) -> Dictionary:
	var key: String = profile.get("key", "")
	if FACE_STYLES.has(key):
		profile["face_style"] = FACE_STYLES[key].duplicate(true)
	if portrait_fit and PORTRAIT_FITS.has(key):
		profile.merge(PORTRAIT_FITS[key], true)
	return profile

# 所有正式角色在原生像素中统一比例, 不再整体拉长头脸。
static func body_scale_for(i: int = -1) -> Vector2:
	return Vector2.ONE

# 角色共用外观入口. 未知身份留空, 不用另一个角色冒充。
static func profile_for(key: String, portrait_fit: bool = true) -> Dictionary:
	if key == "player":
		return PLAYER_IDENTITY.duplicate(true)
	if key.begins_with("slave_") and key.trim_prefix("slave_").is_valid_int():
		return identity_for(int(key.trim_prefix("slave_")), portrait_fit)
	return _face_profile(NAMED_IDENTITIES.get(key, {}).duplicate(true), portrait_fit)

static func named_texture(key: String, file: String = "Idle.png") -> Texture2D:
	var profile: Dictionary = profile_for(key)
	if NAMED_IDENTITIES.has(key) and file not in ["Idle.png", "Walk.png", "Sword.png", "Bow and Arrow.png", "Damage.png", "Dead.png"]:
		return null
	return APPEARANCE.texture(profile, file, key != "player") if not profile.is_empty() else null

# 通用人类也用原生图层, 历史超出花名册的编号仍可显示, 不改变原有编号。
static func generic_profile(model: String, variant: int = 0) -> Dictionary:
	var template: int = {"Alex": 1, "Manu": 2, "Lyria": 3, "Tori": 7}.get(model, 1)
	var profile: Dictionary = identity_for(template)
	profile["key"] = "generic_%s_%d" % [model, variant]
	return profile

static func generic_texture(model: String, file: String, variant: int = 0) -> Texture2D:
	return APPEARANCE.texture(generic_profile(model, variant), file, true)

static func mount_texture(key: String) -> Texture2D:
	var profile: Dictionary = profile_for(key)
	return APPEARANCE.mounted_texture(profile) if not profile.is_empty() else null

static func generic_mount_texture(model: String, variant: int = 0) -> Texture2D:
	return APPEARANCE.mounted_texture(generic_profile(model, variant))

static func named_frames(key: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	for action: String in ["idle", "walk"]:
		var file: String = "Idle.png" if action == "idle" else "Walk.png"
		var texture: Texture2D = named_texture(key, file)
		if texture == null:
			continue
		for direction: String in DIR_ROW:
			var animation := StringName(action + "_" + direction)
			sf.add_animation(animation)
			sf.set_animation_speed(animation, 7.0 if action == "idle" else 10.0)
			for frame in (4 if action == "idle" else 6):
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(frame * CELL, int(DIR_ROW[direction]) * CELL, CELL, CELL)
				sf.add_frame(animation, atlas)
	return sf

static func identity_recipe(model: String, i: int) -> Array:
	if i < 0 or i >= IDENTITIES.size():
		return recipe_for(i)
	var hair := Color(String(IDENTITIES[i]["hair"]))
	var cloth := Color(String(IDENTITIES[i]["cloth"]))
	var hair_band := [0.00, 0.17]
	var cloth_band := [0.78, 0.92]
	if model == "Alex":
		cloth_band = [0.56, 0.68]
	elif model == "Lyria":
		hair_band = [0.02, 0.10]
		cloth_band = [0.88, 1.00]
	elif model == "Manu":
		return [
			{"band": [0.0, 1.0], "vmin": 0.06, "vmax": 0.28, "smax": 0.35, "ytop": 4, "ybot": 19,
				"to": hair.h, "sset": hair.s, "vmul": maxf(1.0, hair.v * 5.0)},
			{"band": [0.88, 1.0], "smin": 0.25, "ytop": 18, "to": cloth.h, "sset": cloth.s, "vmul": cloth.v / 0.75},
		]
	return [
		{"band": hair_band, "smin": 0.40, "to": hair.h, "sset": hair.s, "vmul": hair.v / 0.85},
		{"band": cloth_band, "smin": 0.30, "to": cloth.h, "sset": cloth.s, "vmul": cloth.v / 0.75},
	]

# 配方在 RECIPES 里的下标。RECIPES 是按模型分组的布局:
#   [0..4]=Alex(00/04/08/12/16) [5..9]=Lyria(01/05/09/13/17)
#   [10..14]=Manu(02/06/10/14/18) [15..19]=Tori(03/07/11/15/19)
# 伙伴 i 的模型组 = 美术槽位 % 4（跟 model_for 同一规则）, 组内轮次 = (槽位 / 4) % 5,
# 超出 20 人自动回绕。
static func _recipe_index(i: int) -> int:
	var s := art_slot(i)
	return (s % MODELS.size()) * 5 + (s / MODELS.size()) % 5

# 第 i 个伙伴的改色配方
static func recipe_for(i: int) -> Array:
	return RECIPES[_recipe_index(i)]

# —— e29c: 改色贴图缓存 ——
# key = "模型|文件|配方序号"。五个消费方（农场实体/战场小兵/篝火人/两处面板小像/
# 船员）共用同一张贴图, 不重算也不重开显存。
static var _tex_cache := {}

# 模型图集的改色版。file 是模型目录里的文件名（Idle.png / Sword.png ...）。
# RECIPES[i] 为空（本色伙伴）直接回原图, 一个字节都不重排。
static func sheet_texture(model: String, file: String, i: int) -> Texture2D:
	if file not in APPEARANCE.NPC_FILES:
		return null
	var identity: Dictionary = identity_for(i)
	return APPEARANCE.texture(identity, file, true) if not identity.is_empty() else generic_texture(model, file, i)

static func _apply_identity_palette(img: Image, model: String, i: int) -> void:
	var identity: Dictionary = identity_for(i)
	var hair := Color(String(identity.get("hair", "75452e")))
	var cloth := Color(String(identity.get("cloth", "75416f")))
	var palette: Dictionary = {}
	if identity.has("eyes"):
		palette["8a9db8"] = Color(String(identity["eyes"]))
	match model:
		"Tori":
			_add_palette_ramp(palette, ["861b15", "ee6a0e", "ff9d0e", "ffc71b", "ffeb47"], hair, [0.48, 0.77, 0.95, 1.10, 1.28])
			_add_palette_ramp(palette, ["882b8f", "b83eab", "ffb0dd"], cloth, [0.65, 1.0, 1.28])
		"Alex":
			_add_palette_ramp(palette, ["861b15", "ff9d0e", "ffc71b", "ffeb47", "fff39c"], hair, [0.48, 0.77, 0.95, 1.12, 1.30])
			_add_palette_ramp(palette, ["1a3473", "286ed0"], cloth, [0.62, 1.0])
			palette["a7fce6"] = Color("e9dcc2")
		"Lyria":
			_add_palette_ramp(palette, ["32131e", "8a3625", "ae4924", "c46120", "d9884c"], hair, [0.35, 0.65, 0.85, 1.0, 1.18])
			_add_palette_ramp(palette, ["801620", "c41b24"], cloth, [0.65, 1.0])
		"Manu":
			_add_palette_ramp(palette, ["1d1d1d", "2f2f2f", "4e4e4e", "7b7b7b"], hair, [0.48, 0.72, 0.95, 1.15])
			_add_palette_ramp(palette, ["f27e7b", "ff9e93"], cloth, [0.72, 1.0])
			if i == 6:
				# 珂丹与珞琳复用骨架, 但肤色和服装必须与各自立绘一致。
				palette["bb5138"] = Color("c88361")
				palette["e68e5b"] = Color("f0bc8e")
	for y in img.get_height():
		for x in img.get_width():
			var pixel: Color = img.get_pixel(x, y)
			if pixel.a < 0.1:
				continue
			var key: String = pixel.to_html(false)
			if palette.has(key):
				var replacement: Color = palette[key]
				replacement.a = pixel.a
				img.set_pixel(x, y, replacement)

static func _add_palette_ramp(palette: Dictionary, colors: Array, target: Color, values: Array) -> void:
	for j in colors.size():
		palette[String(colors[j])] = target if is_equal_approx(float(values[j]), 1.0) else Color.from_hsv(target.h, target.s, clampf(target.v * float(values[j]), 0.0, 1.0))

# 主角的全套身体与作业动作也走同一入口, 防止站立穿白衣而挥锄变蓝衣。
static func player_texture(file: String) -> Texture2D:
	return APPEARANCE.texture(PLAYER_IDENTITY, file)

# 把一套色带刷到整张图集上。图集是 32px 帧的横排竖排, ytop/ybot 按「帧内行号」算。
# 命中第一条色带就停（后面的带不再叠加）—— 配方之间互不侵犯。
static func _apply_bands(img: Image, bands: Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		var ry := y % CELL
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < 0.1:
				continue
			for b in bands:
				if _band_hit(c, b, ry):
					img.set_pixel(x, y, _band_paint(c, b))
					break

# 一个像素落在不在色带里。色相带支持跨 0/1（比如红 0.88~1.00）。
static func _band_hit(c: Color, b: Dictionary, ry: int) -> bool:
	var band: Array = b.get("band", [0.0, 1.0])
	var h0 := float(band[0])
	var h1 := float(band[1])
	var h := c.h
	var in_hue: bool
	if h0 <= h1:
		in_hue = h >= h0 and h <= h1
	else:
		in_hue = h >= h0 or h <= h1
	if not in_hue:
		return false
	if c.s < float(b.get("smin", 0.0)) or c.s > float(b.get("smax", 1.0)):
		return false
	if c.v < float(b.get("vmin", 0.0)) or c.v > float(b.get("vmax", 1.0)):
		return false
	return ry >= int(b.get("ytop", 0)) and ry <= int(b.get("ybot", CELL - 1))

# 色带内的上色：hue 平移到目标色, 明度/饱和度按倍率缩放（sset 直接定值）,
# 保留原像素的明暗层次 —— 高光还是高光, 阴影还是阴影。
static func _band_paint(c: Color, b: Dictionary) -> Color:
	var h := c.h
	if b.has("to"):
		h = float(b["to"])
	var s := c.s * float(b.get("smul", 1.0))
	if b.has("sset"):
		s = float(b["sset"])
	var v := clampf(c.v * float(b.get("vmul", 1.0)), 0.0, 1.0)
	return Color.from_hsv(h, clampf(s, 0.0, 1.0), v, c.a)

# ---------------- 主循环 ----------------
func _process(delta: float) -> void:
	# 已经跟着船出海了：人在船上，岛上这套循环整个不参与
	if _aboard:
		return
	# e100 实机演出: 冻结 AI 只听导演的 —— 走位/站桩, 且夜里也保持可见（篝火夜话要人）
	if cs_frozen:
		if cs_target != Vector2.INF:
			if _step_toward(delta, cs_target) != STEP_MOVING:
				cs_target = Vector2.INF
				_play_loop(&"idle")
		else:
			_play_loop(&"idle")
		return
	var night := TimeManager.hour >= 19 or TimeManager.hour < 6
	if night and _state != State.BOARD:
		visible = false
		_state = State.LOITER                 # 天亮重新决定要干嘛
		_post = ""                            # 夜里重新看名单（白天可能又被改派过）
		return
	visible = true
	# 正在登船：只管走向船，别的活一概不接
	if _state == State.BOARD:
		_tick_board(delta)
		return
	# 玩家开着涂色面板（在绘制派活地图）时全部停下歇着：
	# 不挑新活、不挪步、手上那一下也不落 —— 松开面板（或睡醒）再继续。
	if Slaves.paused:
		if _state == State.WORK:
			_state = State.REST               # 动画作废，这格明天按「没干」重排
		_rest = maxf(_rest, 0.6)
		_play_loop(&"idle")
		return
	_tick_blocked(delta)

	# e30s 岗位：被派去矿井/工地/铁匠铺/研究的人不去地里浇水, 各自去岗位上干活。
	# 名单白天随时能改（派活面板 T），所以每帧对一次 —— 换岗了当场掉头。
	var post := _post_of()
	if post != _post:
		_post = post
		_post_spot = Vector2.ZERO             # 落点重算
		_post_t = 0.0
		if post == "":
			_decide_next()                    # 被撤回来 -> 回地里那套循环
		else:
			_state = State.POST
	if _post != "":
		_tick_post(delta)
		return

	match _state:
		State.REST:
			_rest -= delta
			_tick_gaze(delta)
			_play_loop(&"idle")
			if _rest <= 0.0:
				_decide_next()
		State.LOITER:
			_tick_loiter(delta)
		State.GO_WORK:
			_tick_go_work(delta)
		State.WORK:
			_tick_work(delta)

# 闲逛：走到落点 -> 歇一会儿 -> 再挑一个
func _tick_loiter(delta: float) -> void:
	var r := _step_toward(delta, _target)
	if r == STEP_MOVING:
		return
	_rest = _rng.randf_range(1.0, 3.0)
	_state = State.REST

# e54 歇着时的随机张望：隔一会儿换个朝向，像在打量四周
# （_play_loop/_anim_name 按 _facing 切朝向动画，改 _facing 即生效）
func _tick_gaze(delta: float) -> void:
	_gaze_t -= delta
	if _gaze_t > 0.0:
		return
	_gaze_t = _rng.randf_range(0.9, 2.2)
	var faces: Array[StringName] = [&"down", &"up", &"left", &"right"]
	_facing = faces[_rng.randi() % faces.size()]
	# P1 随机心情泡：歇着时摸奖冒一个（夜晚犯困 zzz, 白天发呆/哼歌/犯疑惑）
	_mood_cd -= _gaze_t
	if _mood_cd <= 0.0:
		_mood_cd = _rng.randf_range(MOOD_CD_MIN, MOOD_CD_MAX)
		var night := TimeManager.hour >= 19 or TimeManager.hour < 6
		var pool := ["zzz"] if night else ["...", "note", "?", "..."]
		EMOTE.pop_over(self, pool[_rng.randi() % pool.size()], 1.6, 26.0)

# 赶去干活：走到岗位 -> 开工。路上撞见水就放弃这一趟（这格先冻一会儿）
func _tick_go_work(delta: float) -> void:
	if not Slaves.assignments.has(_work_cell) or Slaves.is_done(_work_cell):
		_decide_next()
		return
	var r := _step_toward(delta, _stand_pos(_work_cell))
	if r == STEP_ARRIVED:
		_begin_work()
	elif r == STEP_BLOCKED:
		_block(_work_cell)
		_decide_next()

# 干活：播动作，放到 HIT_RATIO 时真正改变农场数据，播完歇口气
func _tick_work(delta: float) -> void:
	_work_t -= delta
	if not _work_applied and _work_t <= _work_hit:
		_work_applied = true
		_apply_work()
	if _work_t <= 0.0:
		_state = State.REST
		_rest = _rng.randf_range(0.5, 1.3)

# ---------------- 出海登船 / 返航下船 ----------------
# game.gd 在出海前把人摆到码头边，再调这个：走向船 -> 到了就藏起来。
# ❗目的地是码头/栈桥上的点，不是水里的船 —— _step_toward 撞到水会 STEP_BLOCKED，
#   所以人自然停在岸线上，看起来就是「走到码头边上船」。
func board_to(dest: Vector2) -> void:
	_aboard = false
	_board_dest = dest
	_state = State.BOARD
	visible = true
	set_process(true)

func _tick_board(delta: float) -> void:
	if _step_toward(delta, _board_dest) != STEP_MOVING:
		_aboard = true
		visible = false
		set_process(false)

# 返航：在码头边重新出现，接着挑活干
func unboard(pos: Vector2) -> void:
	_aboard = false
	visible = true
	set_process(true)
	global_position = _dry_spot(pos, 30.0)
	_decide_next()

func is_aboard() -> bool:
	return _aboard

# 兜底：到点了还没走到船边（被地形挤住 / 绕远路）就直接算上船 ——
# 不能因为一个人走不到位就把整趟出海卡在那儿。
func board_now() -> void:
	_aboard = true
	visible = false
	set_process(false)

# ---------------- 走位 ----------------
# 返回 STEP_MOVING / STEP_ARRIVED / STEP_BLOCKED
func _step_toward(delta: float, dest: Vector2) -> int:
	# 兜底：万一人已经站在水里了（旧存档 / 撒点撒歪），先把他挪到最近的岸上，
	# 绝不让他「在水里走」。
	if _is_water_at(global_position):
		global_position = _cell_center(_nearest_land(global_position))
		return STEP_BLOCKED
	var to := dest - global_position
	if to.length() < ARRIVE_DIST:
		return STEP_ARRIVED
	var dir := to.normalized()
	_facing = _dir_name(dir)
	# ❗先看水再迈步：判定放在 _play_loop 前面，撞水的那一帧就不该摆出走路姿势
	var next := global_position + dir * speed * delta
	if _is_water_at(next):
		_play_loop(&"idle")
		return STEP_BLOCKED
	_play_loop(&"walk")
	global_position = next
	return STEP_MOVING

# 离这个点最近的一格陆地（螺旋往外找，找到就停）
func _nearest_land(pos: Vector2) -> Vector2i:
	var g := _game()
	if g == null:
		return Vector2i.ZERO
	var local := pos - Farm.grid_origin
	var c := Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE))
	for r in 12:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t := c + Vector2i(dx, dy)
				if not _is_cell_water(t):
					return t
	return c

func _is_water_at(pos: Vector2) -> bool:
	var g := _game()
	if g == null or not g.has_method("is_water"):
		return false
	var local := pos - Farm.grid_origin
	return g.is_water(Vector2i(floori(local.x / Farm.TILE_SIZE), floori(local.y / Farm.TILE_SIZE)))

# 一格的格子中心（世界坐标）
func _cell_center(cell: Vector2i) -> Vector2:
	return Farm.grid_origin + Vector2(cell.x * Farm.TILE_SIZE + 8, cell.y * Farm.TILE_SIZE + 8)

func _is_cell_water(cell: Vector2i) -> bool:
	var g := _game()
	if g == null or not g.has_method("is_water"):
		return false
	return g.is_water(cell)

# 干活的站位：就站在那一格上（略微偏一点，几个人一起干不会完全重叠）
func _stand_pos(cell: Vector2i) -> Vector2:
	return _cell_center(cell) + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))

# ---------------- 干活 ----------------
func _begin_work() -> void:
	var task := Slaves.task_at(_work_cell)
	var anim: StringName = TASK_ANIM.get(task, &"hoe")
	_work_t = _play_once(anim)
	if _work_t <= 0.0:                 # 动画缺帧就直接生效，别卡住
		_apply_work()
		_state = State.REST
		_rest = 0.5
		return
	_work_hit = _work_t * HIT_RATIO
	_work_applied = false
	_state = State.WORK

# 真正把活干出来。写进 Farm 的逻辑在 Slaves.apply_task（跟睡前「强行补完」共用一份），
# 这里只负责：水里勾掉、干不了的进冷却、按工种配音效。
func _apply_work() -> void:
	var c := _work_cell
	if not Slaves.assignments.has(c) or Slaves.is_done(c):
		return
	if _is_cell_water(c):
		Slaves.mark_done(c)            # 水里没法干活，别再排它了
		return
	var task := Slaves.task_at(c)
	if Slaves.apply_task(c) != Slaves.APPLY_OK:
		_block(c)                      # 还没耕地 / 背包没种子 —— 过会儿再来看看
		return
	match task:
		Slaves.TASK_TILL:
			Audio.play_sfx("hoe", -15.0, _rng.randf_range(0.92, 1.08))
		Slaves.TASK_WATER:
			Audio.play_sfx("water", -15.0, _rng.randf_range(0.92, 1.08))
		Slaves.TASK_PLANT:
			Audio.play_sfx("plant", -15.0, _rng.randf_range(0.92, 1.08))

# ---------------- 岗位干活（e30s） ----------------
# 这个人在派活页上归哪个板块（空 = 照料作物, 也就是没被别的岗位占住, 下地浇水）。
# 数据层保证一个人只占一个岗位（slaves.gd 的 toggle 之间互斥），所以判断顺序无所谓。
# ❗「远航出征」不算岗位：那份名单是「下次出海带谁」, 人平时还在岛上过日子;
#   真出海那天由 game.gd 的 _board_expedition -> board_to 接手（见 _process 的 BOARD 分支）。
func _post_of() -> String:
	if Slaves.is_research(index, "tech") or Slaves.is_research(index, "admin"):
		return "research"
	if Slaves.is_dock(index):
		return "dock"
	if Slaves.is_craft(index):
		return "smith"
	if Slaves.is_mine(index):
		return "mine"
	return ""

# 岗位站位（世界坐标）。找不到对应设施就退回农田中心 —— 宁可站着也别站着不动就消失。
func _post_pos() -> Vector2:
	match _post:
		"mine":
			var g := _game()
			if g != null:
				var raw: Variant = g.get("mine_cell")
				if raw is Vector2i and (raw as Vector2i).x != 9999:
					return _cell_center((raw as Vector2i) + Vector2i(0, 1))   # 站矿门外一格
		"dock":
			var site: Dictionary = Structures.site
			if not site.is_empty():
				return _cell_center(Vector2i(site.get("anchor", Vector2i.ZERO)))
			var g2 := _game()
			if g2 != null:
				var dk: Variant = g2.get("dock")
				if dk is Node2D:
					return (dk as Node2D).global_position + Vector2(-8, 20)
		"smith":
			var bc := _blacksmith_cell()
			if bc.x != 9999:
				return _cell_center(bc + Vector2i(0, 1))                 # 站砧子外面一格
		"research":
			var g3 := _game()
			if g3 != null:
				var h: Node2D = g3.get_node_or_null("House")
				if h != null:
					return h.global_position + Vector2(0, 46)
	return _field_center()

# 场上第一座铁匠铺所在格（没盖就 9999）
func _blacksmith_cell() -> Vector2i:
	for c in Structures.stations.keys():
		if String((Structures.stations[c] as Dictionary).get("kind", "")) == Structures.KIND_BLACKSMITH:
			return c
	return Vector2i(9999, 9999)

# 岗位上的循环：走到位 -> 面朝岗位站定 -> 循环播干活动作 -> 隔一会儿出一声
func _tick_post(delta: float) -> void:
	if _post_spot == Vector2.ZERO:
		_post_spot = _dry_spot(_post_pos(), 16.0)     # 落点也要挑陆地
	var r := _step_toward(delta, _post_spot)
	if r == STEP_MOVING:
		return
	_facing = POST_FACING.get(_post, &"down")
	var anim: StringName = POST_ANIM.get(_post, &"idle")
	_play_loop(anim)
	_post_t -= delta
	if _post_t <= 0.0:
		_post_t = _rng.randf_range(POST_SFX_GAP.x, POST_SFX_GAP.y)
		_post_sfx()

# 岗位上那一下的响动：矿/工地/打铁各用一种音高，听得出是三种活
func _post_sfx() -> void:
	match _post:
		"mine":
			Audio.play_sfx("hoe", POST_SFX_DB, _rng.randf_range(0.90, 1.04))
		"dock":
			Audio.play_sfx("hoe", POST_SFX_DB, _rng.randf_range(0.80, 0.92))
		"smith":
			Audio.play_sfx("hoe", POST_SFX_DB, _rng.randf_range(1.06, 1.20))

# ---------------- 冷却 ----------------
func _block(cell: Vector2i) -> void:
	_blocked[cell] = BLOCK_TIME

func _tick_blocked(delta: float) -> void:
	if _blocked.is_empty():
		return
	for c in _blocked.keys():
		var t: float = float(_blocked[c]) - delta
		if t <= 0.0:
			_blocked.erase(c)
		else:
			_blocked[c] = t

# ---------------- 挑活 / 挑落点 ----------------
# 下一步干嘛：有没干完的活就去干活，没有就闲逛
func _decide_next() -> void:
	if _acquire_job():
		_state = State.GO_WORK
	else:
		_pick_target()
		_state = State.LOITER

# 挑一格还没干的活。从最近的几格里随机挑一个 —— 不总盯着同一格，
# 人也不会都挤在同一个点上，但又不会大老远绕到岛另一头。
func _acquire_job() -> bool:
	var pool: Array = []
	for c in Slaves.undone_cells():
		if _blocked.has(c):
			continue
		if _is_cell_water(c):
			continue
		pool.append(c)
	if pool.is_empty():
		return false
	pool.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _dist2(a) < _dist2(b))
	var n: int = mini(3, pool.size())
	_work_cell = pool[_rng.randi_range(0, n - 1)]
	return true

func _dist2(c: Vector2i) -> float:
	return global_position.distance_squared_to(_cell_center(c))

# 闲逛落点：优先挑「已派活的格子」（涂得密的区域被挑中的概率高）
func _pick_target() -> void:
	var meal: Node = get_tree().get_first_node_in_group("port_life")
	if meal != null and meal.gathering():
		var seat: Vector2 = meal.seat_for(index)
		if meal.seat_available(seat):
			_target = seat
			return
	# ❗落点要过滤掉水格：涂色面板允许涂到水面上，但人不能站水里
	var cells: Array = []
	for c in Slaves.assigned_cells():
		if not _is_cell_water(c):
			cells.append(c)
	if cells.is_empty():
		# 还没派过活（或派的活全在水里）：就在耕地一带随便晃
		_target = _dry_spot(_field_center(), 150.0)
		return
	var c: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
	# ❗落点必须还在这一格里面（_stand_pos 的 ±3 已经够错开了，再加抖动就会跑到隔壁格）
	_target = _stand_pos(c)

# 耕地的中心（世界坐标）—— 一格都没派活时的兜底集合点
func _field_center() -> Vector2:
	var cells: Array = Farm.tilled.keys()
	if cells.is_empty():
		return Farm.grid_origin
	var sum := Vector2i.ZERO
	for c in cells:
		sum += c
	var avg := Vector2(sum.x, sum.y) / float(cells.size())
	return Farm.grid_origin + avg * Farm.TILE_SIZE

# ---------------- 播动画 ----------------
func _play_loop(prefix: StringName) -> void:
	var an := _anim_name(prefix)
	if _sprite.animation != an and _sprite.sprite_frames.has_animation(an):
		_sprite.play(an)
	_sprite.flip_h = (_facing == &"left")

# 播一次不循环的动作，返回它的时长（秒）
func _play_once(prefix: StringName) -> float:
	var an := _anim_name(prefix)
	if not _sprite.sprite_frames.has_animation(an):
		return 0.0
	_sprite.speed_scale = 1.0
	_sprite.play(an)
	_sprite.flip_h = (_facing == &"left")
	var fps := _sprite.sprite_frames.get_animation_speed(an)
	if fps <= 0.0:
		return 0.0
	return float(_sprite.sprite_frames.get_frame_count(an)) / fps

func _dir_name(dir: Vector2) -> StringName:
	if absf(dir.x) >= absf(dir.y):
		return &"right" if dir.x > 0 else &"left"
	return &"down" if dir.y > 0 else &"up"

# 素材只有三行（下 / 上 / 侧），左右是同一张「侧身图」水平翻过来的。
# ❗以前是直接拿朝向去拼动画名（walk_left / walk_right），这两个动画根本不存在 ——
#   结果伙伴往左右走的时候动画压根不播，一直僵在上一张「朝下」的姿势上。
#   现在统一走这里：左右都翻成 side，真正的左右靠 flip_h 区分。
func _anim_name(prefix: StringName) -> StringName:
	if _facing == &"left" or _facing == &"right":
		return StringName("%s_side" % String(prefix))
	return StringName("%s_%s" % [String(prefix), String(_facing)])

func _game() -> Node:
	return get_tree().get_first_node_in_group("game")

# ---------------- 走近对话 ----------------
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _key_hint != null:
			_key_hint.show_hint()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _key_hint != null:
			_key_hint.hide_hint()

# 在主场景里挂的伙伴处理 F 键：打开 dialogue_ui
# （夜晚时伙伴不可见，自然不会触发）
func _try_talk() -> bool:
	if not _player_in_range:
		return false
	var night := TimeManager.hour >= 19 or TimeManager.hour < 6
	if night:
		return false
	if Slaves.paused:
		return false
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	if dialogue != null and dialogue.has_method("open_panel"):
		dialogue.open_panel(index)
		return true
	return false
