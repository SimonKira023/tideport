# slaves.gd —— Autoload，名字：Slaves
# 管理「伙伴（奴隶）」的数量 + 夜晚分配下去的任务 + 每个伙伴的个体信息。
#
# 玩法骨架（跟用户对过的设计）：
#   · 傍晚在篝火边花钱「招募伙伴」（招前能看清人），越往后越贵
#   · 每晚睡觉时（结算画面之后）弹出一张**可涂色的地图**，
#     左键涂色 = 派活，右键擦除。颜色代表工种：耕地 / 浇水 / 播种
#   · 每个伙伴能派 CELLS_PER_SLAVE 格活 → **伙伴越多，能涂的格子越多**
#   · 白天伙伴在农场里闲逛，**哪片涂得多，那片人就多**
#
# 这里只管「数据」：几个人、每格派了什么活、还剩多少额度，
# 以及每个伙伴自己的**姓名 / 好感 / 食物偏好 / 今天喂没喂、聊没聊**。
# 谁去干活、怎么走，交给 scene/slave_npc.gd；涂色界面交给 assign_ui.gd。
extends Node

signal changed            # 人数或任务分配变了（面板/闲逛逻辑都听这个）

# —— 工种 ——
# 用整数存，方便塞进 Dictionary（Vector2i -> int）
const TASK_TILL := 1      # 耕地
const TASK_WATER := 2     # 浇水
const TASK_PLANT := 3     # 播种

const TASK_NAMES := {
	TASK_TILL: "耕地",
	TASK_WATER: "浇水",
	TASK_PLANT: "播种",
}
# 涂色用的颜色。挑的都是跟草地/泥土**以及底图**能分开、彼此也能分开的色相：
#   耕地 = 土黄褐（底图耕地是暗棕），浇水 = 亮青蓝（底图水是深藏蓝），播种 = 亮嫩绿（底图草地偏橄榄）
# ❗「浇水」刻意比水面的蓝亮很多：不然在河边涂的格子跟水糊成一片，看不出派没派活。
const TASK_COLORS := {
	TASK_TILL: Color(0.85, 0.55, 0.14),
	TASK_WATER: Color(0.29, 0.78, 1.00),
	TASK_PLANT: Color(0.33, 0.90, 0.38),
}

const CELLS_PER_SLAVE := 12     # 每个伙伴能派多少格活（基础劳动力）
const BASE_CAP := 3             # 伙伴上限基础值 (e44: 岛上每盖一座同伴小屋 +1, 见 refresh_cap)
var CAP := BASE_CAP             # 伙伴上限: 基础 3 + 同伴小屋数 (Structures 侧调 refresh_cap 刷新)

# —— 好感 ——
# e56: 聊天纯聊天不加好感; 喂食 + 送礼合并成「赠送」（give）, 只走 GIFT_AFFECTION 一个口径
const AFFECTION_MAX := 10       # 好感上限（心数）
const GIFT_AFFECTION := 2       # 每天第一次赠送加的好感（送中爱好 x2, 生日当天再 x2）
const AFF_ATK_STEP := 4         # 好感收益：每攒满 4 点好感, 伙伴打仗 +1 攻（10 满 = +2）

# —— 职业晋升树（双树：战斗 + 劳动）——
# 招进来都是「新兵」（战斗树起点，近战）和「帮工」（劳动树起点）。
# 战斗树三线三阶，新兵起都在近战，选一条线升到底：
#   近战: 新兵 - 刀客 - 剑士 - 咏剑士
#   远程: 新兵 - 弓手 - 神射手 - 狙击手
#   骑兵: 新兵 - 骑兵 - 枪骑兵 - 重骑兵
# 劳动树三线三阶（跟战斗树互不干扰，一人两条线都升），
# 三条线各涨一项属性（e41a 起属性有了正式名字，见 ATTR_NAMES）：
#   营造: 帮工 - 工匠 - 匠师 - 大匠     （涨「建造」：工地与铁匠铺一个人顶多人干活）
#   学问: 帮工 - 学徒 - 书生 - 学士     （涨「知识」：研究科技/行政点数更快）
#   丰饶: 帮工 - 园丁 - 农艺师 - 大地之友（涨「劳动」：派活格子更多, 浇水/下矿更强）
# 晋升不看历练：钱和料够就能升（钱进钱包, 料走背包; 兵种三阶晋升分别要整套甲
# 1/2/3 级 —— 皮甲/锁链甲/铁甲, 铁在熔炉里炼, 见 furnace / Crafting）。
# ❗箭头一律 ASCII（IPix.ttf 没有 → 的字形）。
const CLASSES := {
	"新兵":   {"atk": 0, "next": ["刀客", "弓手", "骑兵"], "cost": {}},
	"刀客":   {"atk": 1, "next": ["剑士"],   "cost": {"coin": 60, "armor": 1}},
	"弓手":   {"atk": 1, "next": ["神射手"], "cost": {"coin": 60, "armor": 1}},
	"骑兵":   {"atk": 1, "next": ["枪骑兵"], "cost": {"coin": 60, "armor": 1}},
	# e27g: 三阶晋升按阶吃甲 —— 一线整套甲1级(皮甲), 二线2级(锁链甲), 三线3级(铁甲);
	# cost.armor = 最低装备等级, 转职时扣掉背包里达标等级最低的那件。
	"剑士":   {"atk": 2, "next": ["咏剑士"], "cost": {"coin": 140, "iron": 1, "armor": 2}},
	"神射手": {"atk": 2, "next": ["狙击手"], "cost": {"coin": 140, "iron": 1, "armor": 2}},
	"枪骑兵": {"atk": 2, "next": ["重骑兵"], "cost": {"coin": 140, "iron": 1, "armor": 2}},
	"咏剑士": {"atk": 3, "next": [], "cost": {"coin": 260, "iron": 3, "armor": 3}},
	"狙击手": {"atk": 3, "next": [], "cost": {"coin": 260, "iron": 3, "armor": 3}},
	"重骑兵": {"atk": 3, "next": [], "cost": {"coin": 260, "iron": 3, "armor": 3}},
}
const LABOR_CLASSES := {
	"帮工": {"next": ["工匠", "学徒", "园丁"], "cost": {}},
	# build = 「建造」属性（工匠 1 = 在工地/铁匠铺一个人顶 2 人）
	# 落到 Structures.add_site_work（建筑）和 Slaves.craft_heads（打铁）
	# e27g: 劳动线成本上调 —— 学手艺不比当兵便宜, 拉开跟战斗线的差距
	"工匠": {"build": 1, "next": ["匠师"], "cost": {"coin": 120, "wood": 4}},
	"匠师": {"build": 2, "next": ["大匠"], "cost": {"coin": 280, "wood": 6, "stone": 4}},
	"大匠": {"build": 4, "next": [],       "cost": {"coin": 520, "stone": 8, "iron": 4}},
	# study = 「知识」属性（研究/行政的额外人手）, 落到 Research.tech_heads / admin_heads
	# e30s: 学者线数值加强（1/2/4 -> 2/3/6）—— 派一个人钻研本来太亏, 没人愿意走这条线
	"学徒": {"study": 2, "next": ["书生"], "cost": {"coin": 120, "wood": 2}},
	"书生": {"study": 3, "next": ["学士"], "cost": {"coin": 280, "wood": 4}},
	"学士": {"study": 6, "next": [],       "cost": {"coin": 520, "iron": 2}},
	# labor = 「劳动」属性（派活格子/浇水与下矿产出都按这个放大）
	# e30s: 劳动线数值加强（4/8/12 -> 6/12/20）—— 这条路只涨干活本事, 不加成够没人走
	# e52f: 农线再改名（壮丁/把式/田祖 -> 园丁/农艺师/大地之友）—— 少些土味, 多些远意
	"园丁": {"labor": 6,  "next": ["农艺师"], "cost": {"coin": 120}},
	"农艺师": {"labor": 12, "next": ["大地之友"], "cost": {"coin": 280}},
	"大地之友": {"labor": 20, "next": [],       "cost": {"coin": 520}},
}
# e30s: 劳动线改名对照（老档里的旧名字接到新名字上, 不然读档后卡在一条死路上）
# e52f: 两个时代的旧名都要接住 —— 农夫/老农/田翁 是最早的, 壮丁/把式/田祖 是上一版的
const LABOR_RENAMED := {
	"农夫": "园丁", "壮丁": "园丁",
	"老农": "农艺师", "把式": "农艺师",
	"田翁": "大地之友", "田祖": "大地之友",
}
# e41b: 战斗线改名对照（剑豪 -> 咏剑士）—— 同理, 旧档里的兵种名接上新名
const CLASS_RENAMED := {"剑豪": "咏剑士"}

# —— e53 花名册 —— 8 位伙伴(e55 缩编: 12 -> 8), 顺序 / 名字 / 初始职业全部固定, 不再随机掷人。
# 入队顺序严格按表推进: Slaves.count 就是 ROSTER 下标, 招募任务的状态机见 recruits.gd。
#   day  = 最早出现的日子（窗口制: 错过后隔 14 天重新开窗, 见 Recruits.WINDOW_DAYS）
#   need = 招募任务的完成条件（Recruits 核验; crops/coin/item 类在入队时扣账）
#   req  = 任务栏 / 篝火面板里给玩家看的一句话要求
# 名字按模型性别对齐（slave_npc.gd model_for: idx%4==0 是男模型 Alex, 其余女模型）:
# 布恩/塔洛是男名, 其余六位都是女名 —— 火边看到的脸、名字、对话头像永远同一人。
# 初始职业都偏低: 多数是起点的新兵/帮工, 咪露/海莉自带一手。
# ❗六位女性（娜雅/珞琳/咪露/海莉/珂丹/雪莱）全部是可结婚对象, 婚恋系统见 marriage.gd。
# ❗need 里 "flag" 对应 quests.gd 指引链的完成记录, "level" 看主角历练（Legion.level）。
const ROSTER := [
	{"id": "rq_00", "name": "布恩", "troop": "新兵", "labor": "帮工", "day": 1,
		"req": "请他到火边坐坐", "need": {}},
	{"id": "rq_01", "name": "娜雅", "troop": "新兵", "labor": "帮工", "day": 2,
		"req": "交给她 6 份作物", "need": {"crops": 6}},
	{"id": "rq_02", "name": "珞琳", "troop": "新兵", "labor": "帮工", "day": 4,
		"req": "盖起第一座建筑", "need": {"flag": "build_first"}},
	{"id": "rq_03", "name": "咪露", "troop": "刀客", "labor": "帮工", "day": 6,
		"req": "主角历练达到 2 级", "need": {"level": 2}},
	{"id": "rq_04", "name": "塔洛", "troop": "新兵", "labor": "帮工", "day": 8,
		"req": "替他还清 300 金币的债", "need": {"coin": 300}},
	{"id": "rq_05", "name": "海莉", "troop": "弓手", "labor": "帮工", "day": 10,
		"req": "驾驶船只出海过", "need": {"flag": "sail_first"}},
	{"id": "rq_06", "name": "珂丹", "troop": "新兵", "labor": "园丁", "day": 12,
		"req": "矿井产出过矿物", "need": {"flag": "mine_first"}},
	{"id": "rq_07", "name": "雪莱", "troop": "新兵", "labor": "帮工", "day": 14,
		"req": "完成第一项科技", "need": {"flag": "tech_first"}},
]

# —— e56 生日 —— 按花名册 id 查表: [季节, 当季第几天]（season 0春/1夏/2秋/3冬, day 1~28）。
# 一年 4 季 x 28 天, 8 人摊开在四季（同季的错开半个月）。日历页（backpack_ui）会把
# 有生日的格子标出来; 生日当天赠送的好感增量 x2。
const BIRTHDAYS := {
	"rq_00": [0, 7],    # 布恩   春季 7 日
	"rq_01": [0, 19],   # 娜雅   春季 19 日
	"rq_02": [1, 5],    # 珞琳   夏季 5 日
	"rq_03": [1, 23],   # 咪露   夏季 23 日
	"rq_04": [2, 11],   # 塔洛   秋季 11 日
	"rq_05": [2, 26],   # 海莉   秋季 26 日
	"rq_06": [3, 9],    # 珂丹   冬季 9 日
	"rq_07": [3, 21],   # 雪莱   冬季 21 日
}

# —— e56 爱好 —— 每人最爱的一件东西（物品显示名, 与 item/*.tres 的 display_name 对号）。
# 赠送栏（gift_picker）会提示 Ta 的爱好; 送中这个东西好感增量 x2。
const LIKES := {
	"rq_00": "烤土豆",    # 布恩   灶边烤出来的才有锅气
	"rq_01": "胡萝卜",    # 娜雅   地里刚拔的最甜
	"rq_02": "鸡蛋",      # 珞琳   鸡窝里还热乎的那种
	"rq_03": "河鲈",      # 咪露   刀客好口福, 爱吃鱼
	"rq_04": "南瓜派",    # 塔洛   甜食能还债一样治愈他
	"rq_05": "蜂蜜",      # 海莉   出海人的糖分补给
	"rq_06": "牛奶",      # 珂丹   园丁喝奶长力气
	"rq_07": "卷心菜汤",  # 雪莱   研究到半夜喝一口热汤
}

# —— e56 赠送白名单 —— 只有这三类能当礼物送出去（跟市场/城镇可卖口径一致）。
# 工具 / 装备 / 种子 / 地板 / 船 / 放置件这些「道具」都不收。
const GIFT_TYPES := ["作物", "食物", "材料"]

# —— e52e: 职业图标 —— 晋升树卡片名字旁的小图（16x16, 取自 Farm RPG 素材包）
# 战斗线用武器, 材质档随阶位递进（木/铜/铁/金）; 劳动线营造用镐、学问用法杖和书、
# 丰饶用镰刀。整图写路径字符串, 图集切格写 [路径, x, y, w, h]（同 Research.ICONS）。
const WPN_DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Weapons and Armor/"
const CLASS_ICONS := {
	# 战斗树 —— 近战: 木剑 铜剑 铁剑 金剑; 远程: 木弓 铁弓 金弓; 骑兵: 木箭 铜箭 铁箭
	"新兵": WPN_DIR + "1. Wood/Sword.png",
	"刀客": WPN_DIR + "2. Cooper/Sword.png",
	"剑士": WPN_DIR + "3. Iron/Sword.png",
	"咏剑士": WPN_DIR + "4. Gold/Sword.png",
	"弓手": WPN_DIR + "1. Wood/Bow.png",
	"神射手": WPN_DIR + "3. Iron/Bow.png",
	"狙击手": WPN_DIR + "4. Gold/Bow.png",
	"骑兵": WPN_DIR + "1. Wood/Arrow.png",
	"枪骑兵": WPN_DIR + "2. Cooper/Arrow.png",
	"重骑兵": WPN_DIR + "3. Iron/Arrow.png",
	# 劳动树 —— 营造: 镐随阶换材质; 学问: 法杖起步, 书生/学士取书页图集的格
	"帮工": WPN_DIR + "1. Wood/Pickaxe.png",
	"工匠": WPN_DIR + "2. Cooper/Pickaxe.png",
	"匠师": WPN_DIR + "3. Iron/Pickaxe.png",
	"大匠": WPN_DIR + "4. Gold/Pickaxe.png",
	"学徒": WPN_DIR + "1. Wood/Staff.png",
	"书生": ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Books.png", 32, 0, 16, 16],
	"学士": ["res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/RPG icons/Extras/Books.png", 48, 0, 16, 16],
	# 丰饶 —— 镰刀随阶换材质（园丁 木镰 / 农艺师 铜镰 / 大地之友 金镰）
	"园丁": WPN_DIR + "1. Wood/Sickle.png",
	"农艺师": WPN_DIR + "2. Cooper/Sickle.png",
	"大地之友": WPN_DIR + "4. Gold/Sickle.png",
}

# 取职业图标：整图直接 load, 数组则切 AtlasTexture（写法同 Research.icon_for）。
# 素材缺失时返回 null, 卡片就只显示名字, 不至于报错。
func class_icon_for(id: String) -> Texture2D:
	if not CLASS_ICONS.has(id):
		return null
	var v: Variant = CLASS_ICONS[id]
	var path := ""
	var region := Rect2()
	if v is String:
		path = String(v)
	elif v is Array and (v as Array).size() >= 5:
		var arr: Array = v
		path = String(arr[0])
		region = Rect2(int(arr[1]), int(arr[2]), int(arr[3]), int(arr[4]))
	if path == "" or not ResourceLoader.exists(path):
		return null
	if region.size == Vector2.ZERO:
		return load(path) as Texture2D
	var at := AtlasTexture.new()
	at.atlas = load(path) as Texture2D
	at.region = region
	return at

# —— 三项属性（e41a）——
# 干活的人看这三项（战斗属性另有一套: atk/hp）。
# 名字只在这儿写一次：面板、详情页、瓦片标签全从 ATTR_NAMES 取，免得文案各写各的。
const ATTR_NAMES := {"build": "建造", "labor": "劳动", "study": "知识"}
const ATTR_ORDER := ["build", "labor", "study"]

# 随机名字池已在 e53 拆除 —— 伙伴的名字改由 ROSTER 花名册固定
# （命名风格不变: 岛民语式的自造词, 男名偏硬辅音收尾, 女名偏元音流转）。

# 可涂色的地图范围（格子号，跟 game.gd 同一个网格）。
# 默认值 = game.gd 的 ISLAND_FROM/TO（核心陆地）；game.gd 开场会覆盖一次，
# 这样两边永远一致，不用手抄。
var map_from := Vector2i(-26, -4)
var map_to := Vector2i(42, 38)

var count := 0                  # 伙伴人数（= slaves.size()，两者始终同步）
var slaves := []                # 每个伙伴的个体数据：{name, affection, gift_today, hp, max_hp, troop, labor, squad}
var expedition := []            # 出征名单（已取消手动勾选）：始终自动同步为全员出海，不占当天劳动
# 派去搞研究的伙伴序号（Esc 面板的科技页/行政页勾选）。
# 跟出海一样是「占人」的：被占用的人既不下地干活，也不上战场。
var research_tech := []         # 派去研究科技树的
var research_admin := []        # 派去研究行政树的
# 派去「工地」的（盖建筑 / 修码头共用一份名单）：
#   有建筑工地 -> 人数投给工地；没有 -> 投给待施工的码头。哪边都没有时这名单没意义。
var dock_crew := []
# 派去矿井下井挖矿的：[{"i": 序号, "job": "stone"/"iron"}]
# 矿井工每天早上稳定产出石头/铁矿，不用下地涂格子。
var mine_crew := []
# 派去铁匠铺打铁的（制造中项目存在时才有意义，人数每晚往制造进度里积累）。
var craft_crew := []
var assignments := {}           # Vector2i -> TASK_*
# 玩家开着涂色面板（白天按 T / 夜里自动弹）时为 true：
# 伙伴全部原地歇着，不挑活不干活 —— 「玩家在绘制时伙伴不干活」。
var paused := false
# 今天已经**真的干完**的格子。
# ❗它跟 assignments 是两回事：assignments 是「计划」，夜里涂的色一直留着（方便复看/复涂），
#   done_today 是「执行结果」，由 scene/slave_npc.gd 干完活后打勾，换日时清空。
#   分开存的好处：伙伴不会盯着同一格反复锄；而夜里那张涂色地图还能原样显示计划。
var done_today := {}            # Vector2i -> true

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)
	backfill_combat()                     # 旧档没有战斗字段 -> 补默认值

# 伙伴上限 = 基础 3 + 岛上已盖好的同伴小屋数（每盖一座 +1）。
# e44: 原来「每完成一项行政研究 +1」的加成取消了 —— 想多带人就去盖小屋。
# 由 Structures 的 place/remove/restore_station 推送刷新（Slaves 比 Structures
# 先加载，反过来在 _ready 里连不上它的信号，所以走主动调用）。
func refresh_cap() -> void:
	var n := BASE_CAP + Structures.hut_count()
	if CAP != n:
		CAP = n
		changed.emit()                    # 篝火/酒馆页监听 changed，会按新上限重画

# 开新档：人、派活、出征/研究/修码头的名单全清（由 save_manager.reset_all 调用）。
# ❗注意跟 clear_all() 的区别：clear_all 只是「夜里清掉派活」，人不走；
#   这个是开新档，一个伙伴都不能留 —— 新档开局是 0 个伙伴。
func reset_for_new_game() -> void:
	slaves.clear()
	count = 0
	expedition.clear()
	research_tech.clear()
	research_admin.clear()
	dock_crew.clear()
	mine_crew.clear()
	craft_crew.clear()
	assignments.clear()
	done_today.clear()
	paused = false
	_preview_cache.clear()
	changed.emit()

# e41i: 骑兵的血上限比步兵厚一截（人 + 马都算血）—— 别处读 max_hp 时就是这个数
const CAVALRY_HP_BONUS := 14
# 战斗树里的骑兵职业（跟 troop.gd 的 MOUNTED_KINDS 对齐, 那边加人这边也要加）
const MOUNTED_TROOPS := ["骑兵", "枪骑兵", "重骑兵"]

func is_mounted_troop(t: String) -> bool:
	return t in MOUNTED_TROOPS

# 某个伙伴的血上限 = 军团基准 + （骑兵的话）马的那份
func troop_max_hp(t: String) -> int:
	return Legion.ally_max_hp() + (CAVALRY_HP_BONUS if is_mounted_troop(t) else 0)

func _on_new_day(_day: int) -> void:
	# 每天重置「今天送过」标记 —— 第二天又能赠送（e56: 喂食/聊天标记已拆, 赠送只剩这一个）
	for s in slaves:
		s["gift_today"] = false
		# 军团：睡一觉血回满，倒下的伙伴也爬起来。
		# 血上限每天重算 —— 这样行政卡「同袍」一挂上、或者当天转职成了骑兵,
		# 都在第二天生效（挂卡/转职是常驻状态，不需要重招人）
		s["max_hp"] = troop_max_hp(String(s.get("troop", "刀客")))
		s["hp"] = int(s["max_hp"])
	if done_today.is_empty():
		changed.emit()
		return
	done_today.clear()
	changed.emit()

# 军团战斗字段：老存档的伙伴字典里没有 hp/max_hp，补上默认值。
# 兵种（troop）也是后来加的：旧档补成「刀客」（近战）。
func backfill_combat() -> void:
	var dirty := false
	for s in slaves:
		if not s.has("max_hp"):
			# e41i: 骑兵算血要带上马的那份（别处读 max_hp 跟这儿一致）
			s["max_hp"] = troop_max_hp(String(s.get("troop", "刀客")))
			dirty = true
		if not s.has("hp"):
			s["hp"] = int(s["max_hp"])
			dirty = true
		if not s.has("troop"):
			s["troop"] = "刀客"
			dirty = true
		# e41b: 战斗线改过名（剑豪 -> 咏剑士），旧档按对照表接上
		elif CLASS_RENAMED.has(String(s["troop"])):
			s["troop"] = String(CLASS_RENAMED[String(s["troop"])])
			dirty = true
		# 编队（squad）也是后来加的：旧档按兵种补（刀客 1 队 / 弓手 2 队）
		if not s.has("squad") or int(s["squad"]) < 1 or int(s["squad"]) > 3:
			s["squad"] = 1 if String(s.get("troop", "刀客")) == "刀客" else 2
			dirty = true
		# 劳动树（labor）是后来加的：旧档没有就补成起点「帮工」。
		# （旧档里的 potential/xp 字段已废弃, 留在存档 dict 里无害, 不再读写。）
		if not s.has("labor"):
			s["labor"] = "帮工"
			dirty = true
		# e30s: 劳动线改过名（农夫/老农/田翁 -> 园丁/农艺师/大地之友），旧档按对照表接上
		elif LABOR_RENAMED.has(String(s["labor"])):
			s["labor"] = String(LABOR_RENAMED[String(s["labor"])])
			dirty = true
		# 送礼标记也是后来加的：旧档补一个「今天没送过」
		if not s.has("gift_today"):
			s["gift_today"] = false
			dirty = true
	# 名单里可能有序号已经越界（读档/减员后），顺手清掉。
	# 同一个伙伴也只允许占一个位置：研究科技 / 研究行政 / 修码头 / 下井 / 打铁 互斥。
	var used := {}
	var clean: Array = []
	for i in research_tech:
		if i >= 0 and i < slaves.size() and not used.has(i):
			used[i] = true
			clean.append(i)
	if clean.size() != research_tech.size():
		dirty = true
	research_tech = clean
	clean = []
	for i in research_admin:
		if i >= 0 and i < slaves.size() and not used.has(i):
			used[i] = true
			clean.append(i)
	if clean.size() != research_admin.size():
		dirty = true
	research_admin = clean
	clean = []
	for i in dock_crew:
		if i >= 0 and i < slaves.size() and not used.has(i):
			used[i] = true
			clean.append(i)
	if clean.size() != dock_crew.size():
		dirty = true
	dock_crew = clean
	# 矿井工：同样只留序号合法的；同一个人只许占一个位置
	clean = []
	for w in mine_crew:
		var mi := int(w.get("i", -1))
		if mi >= 0 and mi < slaves.size() and not used.has(mi):
			used[mi] = true
			clean.append(w)
	if clean.size() != mine_crew.size():
		dirty = true
	mine_crew = clean
	clean = []
	for i in craft_crew:
		if i >= 0 and i < slaves.size() and not used.has(i):
			used[i] = true
			clean.append(i)
	if clean.size() != craft_crew.size():
		dirty = true
	craft_crew = clean
	_sync_expedition()                   # 全员自动出海
	if dirty:
		changed.emit()

# ---------------- 出征名单（全自动） ----------------
# 已取消「勾选谁明天出海」的选项：所有伙伴默认全员跟主角出海，且出海不占当天劳动。
# expedition 变量保留只为兼容 game.gd / battle_map 等旧引用，始终与全员名单同步。
func _sync_expedition() -> void:
	var want := []
	for i in slaves.size():
		want.append(i)
	if expedition != want:
		expedition = want

# ---------------- 修码头的人力 ----------------
# 工地/码头动工（付过钱和材料）之后，在派活面板里勾人去挑土搬木头。
# 勾中的人白天不下地；睡觉时按人数往施工进度里加，攒够人天就建成。
func toggle_dock(i: int) -> bool:
	if i < 0 or i >= slaves.size():
		return false
	if dock_crew.has(i):
		dock_crew.erase(i)
	else:
		dock_crew.append(i)
		# 同样一个人只能占一个位置
		research_tech.erase(i)
		research_admin.erase(i)
		craft_crew.erase(i)
		_mine_erase(i)
	changed.emit()
	return true

func is_dock(i: int) -> bool:
	return dock_crew.has(i)

# 今天派了几个人去修码头
func dock_heads() -> int:
	return dock_crew.size()

# 今天工地上的「有效人手」：人数 + 劳动树「工匠-匠师-大匠」的建筑加成
# （工匠会带帮手，一个人顶 1+N 个劳动力 —— 夜间施工/修码头都按这个算）。
func build_heads() -> int:
	var total := 0
	for i in dock_crew:
		total += 1 + build_bonus(slave_at(i))
	return total

# 码头建成（或存档里码头不在施工）后把这名单清空
func clear_dock_crew() -> void:
	if dock_crew.is_empty():
		return
	dock_crew.clear()
	changed.emit()

# ---------------- 打铁的人力 ----------------
# 打铁的人力：勾中的人每晚往制造进度里积累人工（见 Crafting.add_smith_work）。
# e41a: 跟工地同一套 —— 涨「建造」的人的这份加成也管打铁（一个人顶 1+N 个人手）。
func toggle_craft(i: int) -> bool:
	if i < 0 or i >= slaves.size():
		return false
	if craft_crew.has(i):
		craft_crew.erase(i)
	else:
		craft_crew.append(i)
		# 一个人只能占一个位置
		research_tech.erase(i)
		research_admin.erase(i)
		dock_crew.erase(i)
		_mine_erase(i)
	changed.emit()
	return true

func is_craft(i: int) -> bool:
	return craft_crew.has(i)

func craft_heads() -> int:
	# e41a: 铁匠铺里的「有效人手」= 人数 + 建造加成（工匠会带帮手, 一个人顶 1+N 个人手）
	var total := 0
	for i in craft_crew:
		total += 1 + build_bonus(slave_at(i))
	return total

# 出货（或清档）后把这名单清空
func clear_craft_crew() -> void:
	if craft_crew.is_empty():
		return
	craft_crew.clear()
	changed.emit()

# ---------------- 矿井人力 ----------------
# 派伙伴下井挖矿：job = "stone"（采石）/ "iron"（采铁）。
# 已在井里的人再按同岗位 = 收工回来；按另一个岗位 = 换岗位。
func toggle_mine(i: int, job: String) -> bool:
	if i < 0 or i >= slaves.size():
		return false
	if job != "stone" and job != "iron":
		return false
	for w in mine_crew:
		if int(w.get("i", -1)) == i:
			if String(w.get("job", "")) == job:
				mine_crew.erase(w)        # 同岗位再按一次 = 收工回来
			else:
				w["job"] = job            # 换岗位
			changed.emit()
			return true
	# 新下井：一个人只能占一个位置
	research_tech.erase(i)
	research_admin.erase(i)
	dock_crew.erase(i)
	craft_crew.erase(i)
	mine_crew.append({"i": i, "job": job})
	changed.emit()
	return true

func is_mine(i: int) -> bool:
	for w in mine_crew:
		if int(w.get("i", -1)) == i:
			return true
	return false

func mine_job_of(i: int) -> String:
	for w in mine_crew:
		if int(w.get("i", -1)) == i:
			return String(w.get("job", "stone"))
	return ""

# 从下井名单里撤掉某个人（研究/修码头/打铁互斥用）
func _mine_erase(i: int) -> void:
	for w in mine_crew.duplicate():
		if int(w.get("i", -1)) == i:
			mine_crew.erase(w)

# 今天井里有几个人
func mine_heads() -> int:
	return mine_crew.size()

# 出海名单里的伙伴数据（按序号顺序）
func expedition_slaves() -> Array:
	var out: Array = []
	for i in expedition:
		var s: Dictionary = slave_at(i)
		if not s.is_empty():
			out.append(s)
	return out

# ---------------- 研究劳动力（科技树 / 行政树） ----------------
# 把第 i 个伙伴派去研究某条树。tree = "tech" / "admin"。
# 再按一次 = 撤回来；派去另一条树 = 直接改派。
func set_research(i: int, tree: String) -> bool:
	if i < 0 or i >= slaves.size():
		return false
	if tree != "tech" and tree != "admin":
		return false
	var list: Array = research_tech if tree == "tech" else research_admin
	var other: Array = research_admin if tree == "tech" else research_tech
	var dirty := false
	if list.has(i):
		list.erase(i)
		dirty = true
	else:
		list.append(i)
		dirty = true
	if other.has(i):
		other.erase(i)
		dirty = true
	if dock_crew.has(i):
		dock_crew.erase(i)
		dirty = true
	if craft_crew.has(i):
		craft_crew.erase(i)
		dirty = true
	if is_mine(i):
		_mine_erase(i)
		dirty = true
	if dirty:
		changed.emit()
		Research.changed.emit()
	return true

func is_research(i: int, tree: String) -> bool:
	var list: Array = research_tech if tree == "tech" else research_admin
	return list.has(i)

# 两条树各派了几个人（UI 显示用）
func research_heads(tree: String) -> int:
	return research_tech.size() if tree == "tech" else research_admin.size()

# ---------------- 编队（1/2/3 三个自定义编队） ----------------
# 编队归属存在伙伴自己身上（s["squad"]），所以跨战斗、存档都记得住。
# 战斗中按 1/2/3 就是选这几个编队，0 或再按一次 = 全体。
const SQUAD_MAX := 3

func squad_of(i: int) -> int:
	var s: Dictionary = slave_at(i)
	return clampi(int(s.get("squad", 1)), 1, SQUAD_MAX)

# 把某个伙伴编到第 n 队（1..3）。
func set_squad(i: int, n: int) -> bool:
	var s: Dictionary = slave_at(i)
	if s.is_empty():
		return false
	var want := clampi(n, 1, SQUAD_MAX)
	if int(s.get("squad", 0)) == want:
		return false
	s["squad"] = want
	changed.emit()
	return true

# 第 n 队里有几个人（面板上显示"编队1 (3人)"用）
func squad_count(n: int) -> int:
	var c := 0
	for s in slaves:
		if clampi(int(s.get("squad", 1)), 1, SQUAD_MAX) == n:
			c += 1
	return c

# ---------------- 额度 ----------------
# 研究科技 / 研究行政 / 工地(修码头) / 下井挖矿 / 打铁 都算「占人」，
# 这些伙伴今天不下地干活。（出海已不占劳动：全员自动出海。）
func busy_count() -> int:
	var used := {}
	for i in research_tech:
		used[i] = true
	for i in research_admin:
		used[i] = true
	for i in dock_crew:
		used[i] = true
	for w in mine_crew:
		used[int(w.get("i", -1))] = true
	for i in craft_crew:
		used[i] = true
	return used.size()

func working_count() -> int:
	return maxi(0, count - busy_count())

# 每个伙伴每天能派几格活 = 基础 12 + 管理技能/劳役政策卡（见 Research）
func cells_per_slave() -> int:
	return CELLS_PER_SLAVE + Research.labor_bonus_per_head()

# 单个人的派活额度：基础额度 + 劳动树「园丁-农艺师-大地之友」的劳动加成。
# 下矿产出也按这个值的比例放大（见 OreVein.settle_mine_day）。
func slave_cells(s: Dictionary) -> int:
	return cells_per_slave() + labor_bonus_of(s)

# 今天的总派活额度：没被占用的伙伴逐人累加（劳动树高的人多出活）。
# e13i 工效分支: 主角管理技能 5 级选「工效」后, 每级再 +2 格。
func budget() -> int:
	var total := 0
	for i in slaves.size():
		if is_research(i, "tech") or is_research(i, "admin") \
				or is_dock(i) or is_mine(i) or is_craft(i):
			continue
		total += slave_cells(slaves[i])
	if Legion.branch_of("manage") == "a":
		total += 4 * Legion.branch_lv("manage")   # e28f 账房: 分支每级 +4 格 (比主干 +1 强)
	return total

func used() -> int:
	return assignments.size()

func remaining() -> int:
	return budget() - used()

func has_room() -> bool:
	return remaining() > 0

# ---------------- 派活 ----------------
func task_at(cell: Vector2i) -> int:
	return int(assignments.get(cell, 0))

func in_map(cell: Vector2i) -> bool:
	return cell.x >= map_from.x and cell.x <= map_to.x \
		and cell.y >= map_from.y and cell.y <= map_to.y

# 给某格派活。返回 true 表示这次真的改了东西（额度不够/改了同一格 -> false）。
func assign(cell: Vector2i, task: int) -> bool:
	if not in_map(cell) or task == 0:
		return false
	var old := task_at(cell)
	if old == task:
		return false
	if old == 0 and not has_room():
		return false                      # 新占一格但额度用完了
	assignments[cell] = task
	changed.emit()
	return true

func erase(cell: Vector2i) -> bool:
	if not assignments.has(cell):
		return false
	assignments.erase(cell)
	done_today.erase(cell)
	changed.emit()
	return true

# 只取消某一种工种的活（面板上那个「只取消浇水」按钮）。返回清掉了几格。
func erase_task(task: int) -> int:
	var cells: Array = []
	for c in assignments.keys():
		if int(assignments[c]) == task:
			cells.append(c)
	for c in cells:
		erase(c)
	return cells.size()

func clear_all() -> void:
	if assignments.is_empty() and done_today.is_empty():
		return
	assignments.clear()
	done_today.clear()
	changed.emit()

# 某种工种派了多少格
func count_of(task: int) -> int:
	var n := 0
	for v in assignments.values():
		if int(v) == task:
			n += 1
	return n

# ---------------- 招募 ----------------
var _preview_cache: Dictionary = {}     # 预览缓存：{idx: 那个人}，只在「人数变了」时重算

# 第 idx 位伙伴的档案：名字 / 初始职业都从 ROSTER 花名册里取, 不再随机。
# 篝火面板的「候选预览」和真正入队（recruit_roster）都走这里,
# 所以不存在「火边看着是娜雅, 招进来变成布恩」这种事。
func _roll_slave(idx: int) -> Dictionary:
	var row: Dictionary = ROSTER[idx % ROSTER.size()]
	return {
		"name": String(row["name"]),
		"affection": 0,
		"gift_today": false,             # 今天送过没（赠送每天一次）
		"max_hp": Legion.ally_max_hp(),   # 军团：伙伴血量（吃到行政卡「同袍」）
		"hp": Legion.ally_max_hp(),
		"troop": String(row["troop"]),    # 初始战斗职业（按花名册, 多数是起点的新兵）
		"labor": String(row["labor"]),    # 初始劳动职业（多数是帮工, 个别自带手艺）
		"squad": 1,                        # 编队默认 1 队（篝火面板可调）
	}

# 下一个会招到谁 —— **只算不改**（篝火面板在入队之前拿它显示）。
# 返回的字典跟真招进来那份逐字段相同（同一次 _roll_slave）。
func preview_next() -> Dictionary:
	if _preview_cache.has(count):
		return _preview_cache[count]
	var d := _roll_slave(count)
	_preview_cache = {count: d}          # 人数一变，旧的那份就没意义了，只留当前
	return d

# 让第 count 位伙伴入队（不收钱 —— 招募任务的条件核验与扣账都在 recruits.gd）。
# 候选顺序严格按 ROSTER: count 就是他的花名册序号。
func recruit_roster() -> void:
	slaves.append(_roll_slave(count))
	count += 1
	_sync_expedition()                   # 新伙伴自动出海
	_preview_cache.clear()               # 都招进来了，下一位重新算
	changed.emit()

# ---------------- 个体信息 ----------------
# 按序号取某个伙伴（0-based）。越界返回空字典。
func slave_at(i: int) -> Dictionary:
	if i < 0 or i >= slaves.size():
		return {}
	return slaves[i]

# 给某个伙伴改名。名字不能为空。返回是否成功。
func rename(i: int, new_name: String) -> bool:
	var s: Dictionary = slave_at(i)
	if s.is_empty():
		return false
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		return false
	s["name"] = trimmed
	changed.emit()
	return true

# ---------------- 生日 / 爱好 / 赠送（e56） ----------------
# 第 i 位伙伴的花名册 id（伙伴严格按 ROSTER 顺序入队, 下标就是花名册序号）。
func roster_id(i: int) -> String:
	if i < 0 or i >= slaves.size():
		return ""
	return String(ROSTER[i % ROSTER.size()]["id"])

# 第 i 位伙伴的生日: [季节, 当季第几天]; 查不到返回 (-1, -1)。
func birthday_of(i: int) -> Vector2i:
	var id := roster_id(i)
	if BIRTHDAYS.has(id):
		return Vector2i(int(BIRTHDAYS[id][0]), int(BIRTHDAYS[id][1]))
	return Vector2i(-1, -1)

# 今天是不是 Ta 的生日（对 TimeManager 的当前季节/日子）。
func is_birthday(i: int) -> bool:
	var b := birthday_of(i)
	return b.x >= 0 and b.x == TimeManager.season and b.y == TimeManager.day

# 生日的一行文案（"春季 7 日"）; 查不到返回空串。
func birthday_text(i: int) -> String:
	var b := birthday_of(i)
	if b.x < 0:
		return ""
	return "%s季 %d 日" % [TimeManager.SEASONS[b.x], b.y]

# 第 i 位伙伴最爱的事物（物品显示名）; 查不到返回空串。
func like_of(i: int) -> String:
	return String(LIKES.get(roster_id(i), ""))

# 赠送（e56: 喂食 + 送礼合并）: 选背包里的一份东西送出去。
#   · 只收 作物/食物/材料 这三类（工具/装备/种子这类「道具」不收）
#   · 每天第一次 +GIFT_AFFECTION; 送中爱好 x2; 生日当天增量再 x2（爱好 + 生日 = 4 倍）
# 返回加了的好感（0 = 今天已经送过 / 类型不收 / 没这伙伴）。
func give(i: int, item: ItemData) -> int:
	var s: Dictionary = slave_at(i)
	if s.is_empty() or item == null:
		return 0
	if not GIFT_TYPES.has(item.type):
		return 0
	if bool(s.get("gift_today", false)):
		return 0
	s["gift_today"] = true
	var gain := GIFT_AFFECTION
	if item.display_name == like_of(i):
		gain *= 2
	if is_birthday(i):
		gain *= 2
	s["affection"] = mini(AFFECTION_MAX, int(s["affection"]) + gain)
	changed.emit()
	return gain

# 好感收益：伙伴的攻击加成。每攒满 AFF_ATK_STEP 点好感 +1 攻
# （满好感 10 = +2 攻）。battle_map 出阵时拼进伙伴的最终攻击。
func affection_atk(aff: int) -> int:
	return clampi(aff, 0, AFFECTION_MAX) / AFF_ATK_STEP

# ---------------- 职业晋升树（双树：战斗 + 劳动） ----------------
# 战斗职业自带的攻击加成（最终攻击在 battle_map 里 = Legion.ally_atk() + 这个 + 好感加成 affection_atk）
func class_atk(troop: String) -> int:
	return int(CLASSES.get(troop, {}).get("atk", 0))

# 这个人战斗树下一步能晋升成什么（单目标兼容版, 取第一个分支）。
# 返回 "" 表示满阶（没得升了）。
func promote_target(s: Dictionary) -> String:
	var ts := promote_targets(s)
	return String(ts[0]) if ts.size() > 0 else ""

# 这个人战斗树**能转的所有职业**（新兵三选一: 近战/远程/骑兵, 之后顺着所选线往上）。
func promote_targets(s: Dictionary) -> Array:
	var nxt: Array = CLASSES.get(String(s.get("troop", "新兵")), {}).get("next", [])
	return nxt.duplicate()

# 战斗树里某职业的父职业（谁的 next 里有它）。根职业（新兵）返回 ""。
func prev_of(troop: String) -> String:
	for k in CLASSES:
		if (CLASSES[k]["next"] as Array).has(troop):
			return String(k)
	return ""

# 战斗树晋升到某档要的钱和料（cost 字典: {"coin": 140, "iron": 1}）。
func class_cost(troop: String) -> Dictionary:
	return CLASSES.get(troop, {}).get("cost", {})

# ---------------- 劳动树 ----------------
# 这个人劳动树下一步能晋升成什么（单目标兼容版）。
func labor_target(s: Dictionary) -> String:
	var ts := labor_targets(s)
	return String(ts[0]) if ts.size() > 0 else ""

# 这个人劳动树**能转的所有职业**（帮工三选一: 建筑/学者/劳动, 之后顺着所选线往上）。
func labor_targets(s: Dictionary) -> Array:
	var nxt: Array = LABOR_CLASSES.get(String(s.get("labor", "帮工")), {}).get("next", [])
	return nxt.duplicate()

# 劳动树里某职业的父职业。根职业（帮工）返回 ""。
func labor_prev_of(troop: String) -> String:
	for k in LABOR_CLASSES:
		if (LABOR_CLASSES[k]["next"] as Array).has(troop):
			return String(k)
	return ""

# 劳动树晋升到某档要的钱和料。
func labor_cost(troop: String) -> Dictionary:
	return LABOR_CLASSES.get(troop, {}).get("cost", {})

# —— 劳动树三大加成（都只看这个人当前的劳动职业）——
# 建筑加成：工地上这个人多顶几个人（0 = 平民）。game.gd 夜间结算 dock_effective() 用。
func build_bonus(s: Dictionary) -> int:
	return int(LABOR_CLASSES.get(String(s.get("labor", "帮工")), {}).get("build", 0))

# 学者加成：研究/行政点数上这个人多顶几个人。
func study_bonus(s: Dictionary) -> int:
	return int(LABOR_CLASSES.get(String(s.get("labor", "帮工")), {}).get("study", 0))

# 劳动加成：这个人每天多会几格活（下矿产出/派活额度都按劳动力放大）。
func labor_bonus_of(s: Dictionary) -> int:
	return int(LABOR_CLASSES.get(String(s.get("labor", "帮工")), {}).get("labor", 0))

# —— 三项属性（e41a）——
# 三个人读的地方都走这两个函数：attr_of 取数, attrs_text/attrs_short_text 出文案。
func attr_of(s: Dictionary, key: String) -> int:
	match key:
		"build":
			return build_bonus(s)
		"study":
			return study_bonus(s)
		"labor":
			return labor_bonus_of(s)
	return 0

# 全名版：建造 2   劳动 0   知识 0（详情页用）
func attrs_text(s: Dictionary) -> String:
	var parts: Array = []
	for k in ATTR_ORDER:
		parts.append("%s %d" % [ATTR_NAMES[k], attr_of(s, k)])
	return "   ".join(parts)

# 短名版：建2 劳0 知0（派活面板的瓦片上放不下全名）
const ATTR_SHORT := {"build": "建", "labor": "劳", "study": "知"}
func attrs_short_text(s: Dictionary) -> String:
	var parts: Array = []
	for k in ATTR_ORDER:
		parts.append("%s%d" % [ATTR_SHORT[k], attr_of(s, k)])
	return " ".join(parts)

# 把 cost 翻成人话（按钮/提示文案）。空返回 ""。箭头/竖线一律不用（IPix 字形限制）。
func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return ""
	var parts: Array = []
	if int(cost.get("coin", 0)) > 0:
		parts.append("%d金" % int(cost["coin"]))
	if int(cost.get("iron", 0)) > 0:
		parts.append("铁x%d" % int(cost["iron"]))
	if int(cost.get("wood", 0)) > 0:
		parts.append("木头x%d" % int(cost["wood"]))
	if int(cost.get("stone", 0)) > 0:
		parts.append("石头x%d" % int(cost["stone"]))
	if int(cost.get("armor", 0)) > 0:
		parts.append("整套甲%d级" % int(cost["armor"]))
	return " ".join(parts)

const IRON_ITEM := preload("res://item/iron.tres")
const WOOD_ITEM := preload("res://item/wood.tres")
const STONE_ITEM := preload("res://item/stone.tres")

# 背包里达标整套甲里等级最低的一件（晋升转职扣它）。没有达标的返回 null。
func find_armor(min_tier: int) -> ItemData:
	var best: ItemData = null
	var best_tier := 999
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		if it == null or int(s["count"]) <= 0:
			continue
		if it.type != "装备" or it.armor_tier < min_tier:
			continue
		if it.armor_tier < best_tier:
			best = it
			best_tier = it.armor_tier
	return best

# 钱和料够不够（只是查, 不扣）。
func can_afford(cost: Dictionary) -> bool:
	if int(cost.get("coin", 0)) > 0 and Wallet.money < int(cost["coin"]):
		return false
	if int(cost.get("iron", 0)) > 0 and Inventory.count_item(IRON_ITEM) < int(cost["iron"]):
		return false
	if int(cost.get("wood", 0)) > 0 and Inventory.count_item(WOOD_ITEM) < int(cost["wood"]):
		return false
	if int(cost.get("stone", 0)) > 0 and Inventory.count_item(STONE_ITEM) < int(cost["stone"]):
		return false
	if int(cost.get("armor", 0)) > 0 and find_armor(int(cost["armor"])) == null:
		return false
	return true

# 真正扣钱扣料。扣不动返回 false（调用方要先 can_afford, 这里兜底）。
func pay_cost(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	if int(cost.get("coin", 0)) > 0:
		Wallet.spend_money(int(cost["coin"]))
	if int(cost.get("iron", 0)) > 0:
		Inventory.remove_item(IRON_ITEM, int(cost["iron"]))
	if int(cost.get("wood", 0)) > 0:
		Inventory.remove_item(WOOD_ITEM, int(cost["wood"]))
	if int(cost.get("stone", 0)) > 0:
		Inventory.remove_item(STONE_ITEM, int(cost["stone"]))
	if int(cost.get("armor", 0)) > 0:
		var armor: ItemData = find_armor(int(cost["armor"]))
		if armor != null:
			Inventory.remove_item(armor, 1)
	return true

# 装甲档位色：职业越高披挂越亮（白 = 布衣 -> 银灰 = 皮甲锁子 -> 金铜 = 精钢甲）。
# 岛上闲逛和战场上都拿这个色乘到精灵 modulate 上 —— 像素包常用的整装 recolor 手法,
# 跟草地/资源包的柔和色阶是一个路数。
const ARMOR_TINT_ROOKIE := Color(1, 1, 1)
const ARMOR_TINT_VETERAN := Color(0.86, 0.92, 1.02)
const ARMOR_TINT_ELITE := Color(1.06, 0.97, 0.72)
func armor_tint(troop: String) -> Color:
	match troop:
		"剑士", "神射手", "枪骑兵":
			return ARMOR_TINT_VETERAN
		"咏剑士", "狙击手", "重骑兵":
			return ARMOR_TINT_ELITE
	return ARMOR_TINT_ROOKIE

# 战斗树还有没有得升（满阶返回 false）。钱料够不够由 promote() 把关。
func can_promote(i: int) -> bool:
	var s: Dictionary = slave_at(i)
	if s.is_empty():
		return false
	return promote_targets(s).size() > 0

# 晋升战斗树：钱和料够就能升（atk 涨、骑兵线换马匹模型）。
# target 传 "" 时取第一个分支（旧调用兼容）。钱料不够 / 目标不合法都拒绝。
func promote(i: int, target := "") -> bool:
	var s: Dictionary = slave_at(i)
	if s.is_empty():
		return false
	var allowed := promote_targets(s)
	if allowed.is_empty():
		return false
	if target == "":
		target = String(allowed[0])
	if not allowed.has(target):
		return false
	if not can_afford(class_cost(target)):
		return false
	if not pay_cost(class_cost(target)):
		return false
	s["troop"] = target
	changed.emit()
	return true

# 晋升劳动树（跟战斗树互不干扰, 一人两条线都能升）。
func promote_labor(i: int, target := "") -> bool:
	var s: Dictionary = slave_at(i)
	if s.is_empty():
		return false
	var allowed := labor_targets(s)
	if allowed.is_empty():
		return false
	if target == "":
		target = String(allowed[0])
	if not allowed.has(target):
		return false
	if not can_afford(labor_cost(target)):
		return false
	if not pay_cost(labor_cost(target)):
		return false
	s["labor"] = target
	changed.emit()
	return true

# ---------------- 执行进度（伙伴白天真的去干） ----------------
func is_done(cell: Vector2i) -> bool:
	return done_today.has(cell)

func mark_done(cell: Vector2i) -> void:
	if done_today.has(cell):
		return
	done_today[cell] = true
	changed.emit()

# 还没干完的活：伙伴照着这个列表去挑下一个目标。
# 干完的格子留在 assignments 里（地图上颜色不变）但不再派活 —— 免得同一个坑被反复锄。
func undone_cells() -> Array:
	var out: Array = []
	for c in assignments.keys():
		if not done_today.has(c):
			out.append(c)
	return out

# ---------------- 把活真正干出来 ----------------
# 结果代码：OK = 干完了（或没活可干）；BLOCKED = 条件不满足（没耕地/没种子），过会儿再试
const APPLY_OK := 0
const APPLY_BLOCKED := 1

const POTATO_SEED := preload("res://item/seed.tres")   # 优先土豆种子，跟开局给的一致

# 把某一格的活做出来：写进 Farm 的耕地/浇水/作物状态、从背包扣种子。
# 伙伴白天干活和睡前「强行补完」都走这一份逻辑，保证两处结果一致。
func apply_task(cell: Vector2i) -> int:
	if not assignments.has(cell) or done_today.has(cell):
		return APPLY_OK
	match task_at(cell):
		TASK_TILL:
			Farm.till(cell)
		TASK_WATER:
			if not Farm.is_tilled(cell):
				return APPLY_BLOCKED      # 还没耕地，浇不了
			Farm.water(cell)
		TASK_PLANT:
			if not Farm.is_tilled(cell):
				return APPLY_BLOCKED
			var s := _find_seed()
			if s == null:
				return APPLY_BLOCKED      # 背包里一颗种子都没有
			if Farm.plant(cell, s):
				Inventory.remove_item(s, 1)
		_:
			return APPLY_OK               # 未知工种：别动农场，直接勾掉
	mark_done(cell)
	return APPLY_OK

# 从背包里找一颗种子（优先土豆）
func _find_seed() -> ItemData:
	var fallback: ItemData = null
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		if it == null or int(s["count"]) <= 0 or it.type != "种子":
			continue
		if it == POTATO_SEED:
			return it
		if fallback == null:
			fallback = it
	return fallback

# ---------------- 白天闲逛用 ----------------
# 返回「已派活的格子」列表。空闲的伙伴就在这些格子里随机挑落点，
# 于是涂得密的地方被挑中的次数多 -> 那儿闲逛的人自然就多。
# ❗注意：这里返回的是**全部**已派活的格子（含已干完的），
#   因为「人多聚到活多的那片」是按涂色密度算的，跟干完没干完无关。
func assigned_cells() -> Array:
	return assignments.keys()

# 只挑某几种工种的格子
func cells_of(task: int) -> Array:
	var out: Array = []
	for c in assignments.keys():
		if int(assignments[c]) == task:
			out.append(c)
	return out
