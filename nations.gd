# nations.gd —— Autoload，名字：Nations
# 大陆的国家 / 城镇 / 好感度 / 协议 数据层（远征玩法的核心账本）
#
# 设计（第四轮需求）：
#   · 大陆上有 5 个国家，每国 3 座城镇（1 主城 + 2 属镇），钉在海图的大陆上，
#     格子坐标由 scene/world_map.gd 画成城镇标记、scene/mainland.gd 按镇进场。
#   · 每国一条好感度（0-100）：城镇里聊天 +1、送礼 +5（花 200 金）；达到门槛后
#     可签「商盟」（日入 40 金）或「盟约」（日入 60 金 + 巡逻队友善 + 攻城可请援军）。
#   · 个人交情另记一本账（p_favor）：领主按镇、百夫长按国，碰面聊天 +1、
#     登门送礼 +5；外交页那种只报国名的送礼只涨国家好感，不动个人账。
#   · 协议签下起 PACT_DAYS 天后到期作废，到期当天早上发一条通告。
#   · 每天早上（TimeManager.new_day）结算一次：协议收入进钱包 + 检查到期。
#   · 攻城打赢某国守军：该国好感重创 + 协议撕毁（scene/battle_map.gd 胜利时调用）。
#
# ❗城镇坐标全部落在巨岛的陆地里（2026-09-19 e11 巨岛改版后重排）：巨岛是
#   「离图边 7+噪声*4 格的矩形海岸 + 四角挖圆 + 东南角 BAY_R=62 弧形海峡」，
#   十五镇全部距图边 >12 格、距海峡圆心(200,140) >66 格、避开三条河
#   （东西长河 y~66 摆到 62-70 / 西河 x~52 摆到 47-57 / 出发岛小河）——
#   城镇绝不会生成在水里。西北草原给了游牧的苍狼部（e11d）。
# ❗所有 UI 文案遵守 IPix 字体约束：不用全角「」、不用 | 和 ->，箭头一律 ASCII ->。
extends Node

signal changed                # 好感/协议变动（城镇面板刷新用）

# —— 数值表 ——
const FAVOR_MAX := 100
const FAVOR_MIN := -100       # e27e: 关系能跌成负数 —— 攻城/宣战掉好感不再封在 0
const CHAT_FAVOR := 1         # 每次聊天 +
const GIFT_COST := 200        # 送一次礼的花销
const GIFT_FAVOR := 5         # 送一次礼 +
const TRADE_NEED := 40        # 签商盟的好感门槛
const ALLY_NEED := 70         # 签盟约的好感门槛
const PACT_DAYS := 28         # 协议有效期（一季）
const TRADE_INCOME := 40      # 商盟：每天固定收入
const ALLY_INCOME := 60       # 盟约：每天固定收入（含通商）
# e27e: 贸易镇也能打了 —— 原来不设防(0 守军)连城都没有, 现在配 3 人守备
const GARRISON_OF := {"capital": 7, "military": 5, "trade": 3}   # 满编守军
const GARRISON_REGROW := 10   # 破城后守军重整的天数
const WAR_DAYS := 60          # e27e: 战争持续天数(到期自动停战, 免得永远签不了约)
const WAR_DECLARE_COST := 30  # e27e: 主动递战书要花的外交点(声望)
const SIEGE_LOOT_BASE := 120  # 攻城战利品底数（城里的库房）
const SIEGE_LOOT_PER := 35    # 每名守军额外带来的战利品

# —— 占城治理（e26a）——打下的城要经营: 收税 / 派驻军压不满 / 满 100 爆叛乱
# e52: 税入大幅上调（原来 30/55 —— 打下城的回报太薄, 没人愿意经营）
const OCCUPY_TAX := 90        # 占领的属镇/军镇每天税入
const OCCUPY_CAP_TAX := 165   # 占领的首都每天税入
const PGAR_MAX := 3           # 每座占领城最多驻几支驻军
const PGAR_COST := 120        # 派一支驻军的花销（每支每天 +UNREST_PER_GAR 点忠诚）
const CALM_COST := 80         # 安抚一次的花销（忠诚 +CALM_DOWN）
const CALM_DOWN := 45         # e52: 面板上按「忠诚 +N」讲（内部仍是不满 -N, 忠诚 = 100 - 不满）
const UNREST_BASE := 8        # 没人管时不满度每天自然上涨
const UNREST_PER_GAR := 2     # 每支驻军压下的日涨幅
const REBEL_UNREST := 100     # e52: 不满到这条线当天就爆叛乱（面板上要报给玩家看, 所以提出来）

# —— 占城建设（e27h）——花钱修葺城池, 繁荣上去了税也多收
const BUILD_COST := 150        # 建设一次的花销
const BUILD_UP := 8            # 每次建设繁荣 +
const PROSPERITY_START := 30   # 城破之初的繁荣（百废待兴）

# —— 国战（e26b）——AI 国家互相攻伐: 远征队开到别国城下, 城头换旗
const WAR_CHANCE := 0.18      # 每天早上小概率爆发一桩远征
const RECLAIM_CD_DAYS := 12   # e34e: 同一座城的反扑冷却, 防双方天天来回拉锯

# —— 五国 ——
# id / 显示名 / 队伍配色（巡逻队标记、面板横幅用）/ 一句话立场
# mounted: 是否「以骑兵为主」的国家 —— 海图巡逻骑马出行, 战斗敌军混编骑兵
const NATIONS := [
	{"id": "chenxi", "name": "晨曦王国", "color": Color(0.86, 0.38, 0.33),
		"desc": "靠海吃饭的商人之国, 港口林立", "mounted": false},
	{"id": "beiling", "name": "北岭公国", "color": Color(0.42, 0.60, 0.90),
		"desc": "雪山脚下的老牌公国, 民风坚忍", "mounted": false},
	{"id": "xichuan", "name": "西川王国", "color": Color(0.45, 0.72, 0.42),
		"desc": "河谷沃野的农业之国, 粮仓天下", "mounted": false},
	{"id": "tieyan", "name": "铁岩氏族", "color": Color(0.62, 0.52, 0.72),
		"desc": "铁与岩的氏族联盟, 穷兵黩武", "mounted": false},
	{"id": "canglang", "name": "苍狼部", "color": Color(0.80, 0.66, 0.36),
		"desc": "西北草原的游牧帐落, 骑射立国", "mounted": true},
]

# 骑兵国判定：海图巡逻队骑不骑马、战斗守军带不带骑兵, 都看这一处
func is_mounted(id: String) -> bool:
	return bool(nation(id).get("mounted", false))

# —— 十五座城镇 ——
# kind: capital 主城(首领坐镇, 可攻城) / trade 贸易镇(市集) / military 军镇(封臣驻防, 可攻城)
# cell 是海图格子坐标（16px 一格），world_map / mainland 都按它找位置。
# 2026-09-19 e11 巨岛改版后重排：五国分片而治 —— 苍狼部西北草原 / 北岭东北 /
# 铁岩中部山地 / 西川西南河谷 / 晨曦东南沿海, 中间留出清晰的国界带
# （海图上按「离哪座城最近」划归属, 见 world_map 国界层）。
const TOWNS := {
	"chenxi_cap": {"name": "晨曦城", "nation": "chenxi", "kind": "capital",
		"cell": Vector2i(148, 94)},
	"chenxi_port": {"name": "鹭洲港", "nation": "chenxi", "kind": "trade",
		"cell": Vector2i(160, 82)},
	"chenxi_bridge": {"name": "石桥镇", "nation": "chenxi", "kind": "trade",
		"cell": Vector2i(132, 90)},
	"beiling_cap": {"name": "北岭城", "nation": "beiling", "kind": "capital",
		"cell": Vector2i(132, 24)},
	"beiling_valley": {"name": "霜河谷", "nation": "beiling", "kind": "trade",
		"cell": Vector2i(118, 32)},
	"beiling_pine": {"name": "松风镇", "nation": "beiling", "kind": "trade",
		"cell": Vector2i(150, 32)},
	"xichuan_cap": {"name": "西川城", "nation": "xichuan", "kind": "capital",
		"cell": Vector2i(30, 86)},
	"xichuan_gold": {"name": "金穗镇", "nation": "xichuan", "kind": "trade",
		"cell": Vector2i(72, 88)},
	"xichuan_reed": {"name": "苇泽港", "nation": "xichuan", "kind": "trade",
		"cell": Vector2i(30, 74)},
	"tieyan_cap": {"name": "铁岩堡", "nation": "tieyan", "kind": "capital",
		"cell": Vector2i(104, 46)},
	"tieyan_stone": {"name": "黑石镇", "nation": "tieyan", "kind": "military",
		"cell": Vector2i(92, 36)},
	"tieyan_cliff": {"name": "断崖寨", "nation": "tieyan", "kind": "military",
		"cell": Vector2i(116, 58)},
	"canglang_cap": {"name": "苍狼帐", "nation": "canglang", "kind": "capital",
		"cell": Vector2i(32, 30)},
	"canglang_pasture": {"name": "白马滩", "nation": "canglang", "kind": "trade",
		"cell": Vector2i(44, 24)},
	"canglang_camp": {"name": "套马营", "nation": "canglang", "kind": "military",
		"cell": Vector2i(28, 40)},
}

# —— 十五镇的领主 ——（主城是国主, 属镇是封臣; 头像 lord_<镇id>.png）
const LORD_NAMES := {
	"chenxi_cap": {"title": "晨曦王", "name": "奥朗"},
	"chenxi_port": {"title": "港侯", "name": "温楼"},
	"chenxi_bridge": {"title": "桥伯", "name": "柳原"},
	"beiling_cap": {"title": "女大公", "name": "希尔达"},
	"beiling_valley": {"title": "谷伯", "name": "洛恩"},
	"beiling_pine": {"title": "松伯", "name": "卡佳"},
	"xichuan_cap": {"title": "西川王", "name": "苏禾"},
	"xichuan_gold": {"title": "金穗伯", "name": "麦冬"},
	"xichuan_reed": {"title": "芦伯", "name": "苇青"},
	"tieyan_cap": {"title": "大汗", "name": "赫连烈"},
	"tieyan_stone": {"title": "石台吉", "name": "巴图"},
	"tieyan_cliff": {"title": "崖台吉", "name": "苏赫"},
	"canglang_cap": {"title": "苍狼王", "name": "孛罗"},
	"canglang_pasture": {"title": "滩主", "name": "哈剌"},
	"canglang_camp": {"title": "套马将", "name": "脱欢"},
}

# —— 五国巡逻队长 ——（e36n: 各国称号不同, 不再一律叫「百夫长」; 头像 captain_<国id>.png）
const CAPTAIN_NAMES := {
	"chenxi": "秦戈", "beiling": "白山", "xichuan": "田石", "tieyan": "那颜",
	"canglang": "哈丹",
}

# —— 五国巡逻队长的称号（e36n）——
# 各国军制/营生不一样, 头衔也该有本国味道:
#   晨曦靠海为商   -> 港口护卫长（护商路）
#   北岭雪山老牌公国 -> 雪境巡逻长（守边）
#   西川河谷农业国 -> 粮道护卫长（护粮）
#   铁岩氏族穷兵黩武 -> 氏族骑兵长
#   苍狼部草原游牧 -> 草原游骑长
# 面板标题 / 好感条 / 聊天对话框统一取这个称号。
const CAPTAIN_TITLES := {
	"chenxi": "港口护卫长", "beiling": "雪境巡逻长", "xichuan": "粮道护卫长",
	"tieyan": "氏族骑兵长", "canglang": "草原游骑长",
}

# —— 聊天闲话（按国家轮着说，纯风味；领主/百夫长有各自的私房话）——
const CHAT_LINES := {
	"chenxi": [
		["海风带来远客, 欢迎你, 朋友.",
			"晨曦的商路四通八达, 缺的只是人手."],
		["等商路重开, 什么货在这都能卖出价.",
			"到时候少不了你的份, 先处好交情要紧.",
			"生意人的规矩: 朋友多了路好走."],
	],
	"beiling": [
		["北岭的雪一下就是一整季.",
			"炉子边烤着火的时候, 谁都不想出门."],
		["狼群比去年更凶了, 猎户都不敢进山.",
			"公爵大人正为过冬的粮草发愁.",
			"你要是运粮来, 公国记你的好."],
	],
	"xichuan": [
		["西川的麦子今年收成不错.",
			"仓里堆得下, 就是缺人手收."],
		["苇泽港的渔获一年比一年少.",
			"金穗镇的粮车天不亮就出发了.",
			"种地的人起得比鸡早, 睡得比狗晚."],
	],
	"tieyan": [
		["铁岩的炉火从不熄灭.",
			"岩堡的城墙比十年前又高了一丈."],
		["氏族只敬重强者和好铁.",
			"你要是能打, 哪儿都有你的位置.",
			"你要是能种地, 也一样受人敬重."],
	],
	"canglang": [
		["草原上的风比马还快, 别在苍狼部面前掉队.",
			"狼群认头狼, 部民认套马的手."],
		["西边的沙丘跑马, 三圈下来马不喘人不喘.",
			"哪天你也能跑这三圈, 咱们就是朋友.",
			"草原上的交情, 是马背上处出来的."],
	],
}

# —— 领主的私房话（按镇分线：主城是国王, 属镇是封臣, 一人一个性子）——
const LORD_LINES := {
	"chenxi_cap": [
		["金子不问出身, 只问眼光. 你有一双好眼睛.",
			"晨曦的王冠, 是商队一单一单挣回来的."],
		["想把买卖做大? 好感就是本钱, 商路就是钱路.",
			"签下商盟, 你的货就能挂晨曦的旗走南闯北.",
			"本王不做亏本的买卖, 但从不亏待朋友."],
	],
	"chenxi_port": [
		["鹭洲的海风里都是香料味, 闻着就让人想做生意.",
			"港口的税册比诗还动人, 每一行都是金子."],
		["远道的朋友, 看看码头的新船再走不迟.",
			"东边那条三桅船, 装得下一整个货栈.",
			"做港口生意的秘诀? 眼睛放亮, 嘴巴放甜."],
	],
	"chenxi_bridge": [
		["账要一笔一笔算, 交情要一天一天处.",
			"石桥镇的过桥税又涨了两成, 好生意啊."],
		["好感换商盟, 商盟生金子. 这笔账划算.",
			"你要是不信, 我把账本拿来给你算.",
			"账房的规矩: 数字不说谎, 说谎的是人."],
	],
	"beiling_cap": [
		["北岭的冬天冻掉过我三根手指, 冻不掉北岭人的骨头.",
			"年轻人, 尊重是拿雪一铲一铲换来的."],
		["过冬的粮草还差着数, 公国不敢有半点闪失.",
			"你要是有门路弄到粮, 北岭记你一辈子.",
			"雪停之前, 谁都不能倒下."],
	],
	"beiling_valley": [
		["霜河谷的狼皮, 全大陆的皮匠都抢着要.",
			"喝酒要喝透, 交人要交心. 你算个实在人."],
		["山里的猎物越来越精, 人也得跟着精.",
			"上个月我追一头白狼追了三天三夜.",
			"结果? 它请我喝了雪水, 哈哈."],
	],
	"beiling_pine": [
		["松风镇的每一棵树, 都是公国的城墙.",
			"边境不比腹地, 我说话直, 你别见怪."],
		["雪线又上移了, 猎户的日子一年难似一年.",
			"守住这片林子, 就是守住北岭的南门.",
			"有朝一日狼烟起, 这里的树一棵都不会倒."],
	],
	"xichuan_cap": [
		["民以食为天, 西川的仓廪就是天下人的胆气.",
			"种地的人不骗土地, 土地也就不骗人."],
		["愿意开块田吗? 西川敬重每一个种地的人.",
			"仓里有粮, 心里不慌, 这是老理.",
			"你田里的收成, 西川的史册会记一笔."],
	],
	"xichuan_gold": [
		["金穗镇的麦子磨出的粉, 揉面不粘手.",
			"看天吃饭的人最敬实在人, 你的田我听说了."],
		["今年雨水好, 粮车一直排到镇口.",
			"新麦下来先给老人孩子, 这是镇上的规矩.",
			"要买粮趁早, 秋后粮价一天一个样."],
	],
	"xichuan_reed": [
		["苇泽港的芦苇荡, 秋天白得像下雪.",
			"渔获一年比一年少, 水倒一年比一年清."],
		["船家不问来路, 只问交情.",
			"你是头一个走进这片苇荡的农夫.",
			"哪天来, 我带你出港看日出."],
	],
	"tieyan_cap": [
		["炉火不熄, 铁岩不倒. 你来得正好.",
			"氏族的规矩简单: 强者敬酒, 弱者让路."],
		["会种地的手也抡得动铁锹, 我喜欢这样的部民.",
			"铁锅也是铁, 种地的也是好汉.",
			"坐. 喝完这碗马奶酒再说话."],
	],
	"tieyan_stone": [
		["黑石镇的墙是整块山岩凿的, 攻不破.",
			"俺不懂绕弯子, 你行不行, 处处就知道."],
		["台吉的印章是石头刻的, 说出的话也是.",
			"这镇上的人, 一辈子只信两样: 石头和汗水.",
			"你也信这个? 那就是自己人."],
	],
	"tieyan_cliff": [
		["断崖下面, 埋着不服氏族的名字.",
			"一只眼睛, 反而看得更准."],
		["想让苏赫记住你? 拿本事来.",
			"我这只眼是在崖下丢的, 记性却没丢.",
			"帮过我的, 断崖记得; 背过我的, 也记得."],
	],
	"canglang_cap": [
		["帐外拴着的每匹马, 都是苍狼部的胆气.",
			"王帐的规矩跟狼群一样: 跑得快的先吃肉."],
		["会骑马的朋友都受王帐欢迎, 会种地的也行.",
			"草原缺粮, 你的麦子比金子还贵重.",
			"长生天看着, 王帐不亏待朋友."],
	],
	"canglang_pasture": [
		["白马滩的马驹, 开春就能换三头羊.",
			"滩上的风把人吹成沙色, 也把马养得油亮."],
		["牧人看天吃饭, 帐落看水草搬家.",
			"看中哪匹马? 开个价, 交情好的让三成.",
			"明年开春来, 教你套马."],
	],
	"canglang_camp": [
		["套马杆比我岁数还大, 从没空手回来过.",
			"营里的野马桀骜, 驯服了就是草原上最快的刀."],
		["想让脱欢服你? 先上马跑赢我再说.",
			"开玩笑了. 会种地的朋友, 不用跑赢我.",
			"营里的马奶酒管够, 坐下慢慢聊."],
	],
}

# —— 巡逻队长的军中话（按国分线）——
const CAPTAIN_LINES := {
	"chenxi": [
		["商队的货, 一根绳子松了我都睡不着.",
			"护了十二年商路, 缺胳膊的买卖不做."],
		["上头交代了, 好好谈生意, 别动刀子.",
			"刀子留给不长眼的贼, 笑脸留给正经客.",
			"有事随时来军帐找我, 别客气."],
	],
	"beiling": [
		["公国的军饷没少过一个铜板, 也没多过一个.",
			"雪原行军, 队尾踩着队头的脚印才不会掉队."],
		["巡逻长的职责: 让每个人活着回家.",
			"在北岭, 活着回去比打胜仗更难.",
			"你面色红润, 是个有福气的人."],
	],
	"xichuan": [
		["粮道就是西川的血管, 我们是血管里的卫兵.",
			"护粮比种粮清闲, 责任一点不轻."],
		["田里收成好, 我们脸上也有光.",
			"秋收那阵子, 我们护粮护到脚不沾地.",
			"庄稼人的汗水, 值得一刀一枪去护."],
	],
	"tieyan": [
		["马蹄踩过的地方, 都是氏族的猎场.",
			"巡逻是苦差, 但氏族的刀从不生锈."],
		["别盯着盔羽看, 它来自一头不肯服输的白狼.",
			"追了它四十里, 它回头咬我, 我敬它是条汉子.",
			"后来它成了我的坐骑. 就这么简单."],
	],
	"canglang": [
		["巡逻靠马腿, 扎营靠狗腿, 吃肉靠套马的手.",
			"草原上没有走不完的路, 只有跑累的马."],
		["部里的骑兵个个能射, 你要是朋友就别怕.",
			"朋友来了有马奶酒, 贼来了有套索.",
			"你走你的路, 有事喊一嗓子就行."],
	],
}

# —— 运行时状态（存档走 to_dict/from_dict）——
var favor := {}          # 国家id -> 好感 0-100
var p_favor := {}        # 个人好感: 领主=镇id / 百夫长=cap_国id -> 0-100
var pact := {}           # 国家id -> "" / "商盟" / "盟约"
var pact_until := {}     # 国家id -> 到期总天数（0 = 没签）
var garrison := {}       # 城镇id -> 剩余守军（没记录 = 满编）
var garrison_until := {} # 城镇id -> 守军重整完成日（破城时间 + REGROW）
# 城镇id -> 被玩家占领（城破之后插上你的旗：海图国界层会把这座城的地划进你的领地,
# 国界线跟着挪 —— 见 world_map.gd 的 Borders 层）。
var occupied := {}
var notices: Array[String] = []   # 事件通告（海图 HUD / 城镇面板取走显示）

# ---------------- 声望与主从契约（e13g） ----------------
signal prestige_changed            # 声望变了（外交页刷新用）

const MERC_NEED := 20              # 签「雇佣兵」协议要的声望
const VASSAL_NEED := 50            # 签「封臣」协议要的声望（可从雇佣兵升级）
const PRESTIGE_BANDIT := 2         # 打赢山贼/海寇 +
const PRESTIGE_PATROL := 3         # 打赢国家巡逻 +
const PRESTIGE_SIEGE := 5          # 攻城获胜 +
const FIEF_INCOME := 40            # 封地城每天带来的岁入（e15b: 对齐商盟 40, 别让高门槛契约吃亏）
const FIEF_CAP_INCOME := 65        # 封地是首都时更高（略超盟约 60）

var prestige := 0                  # 玩家声望：打仗 / 海外贸易攒, 签约的门槛
const SEA_PRESTIGE_PER := 1000     # 海外贸易每累积卖出这么多金 +1 声望（e29a）
var sea_gold_acc := 0              # 海外贸易累积卖出金（声望折算账本, e29a; 随存档持久化）
var contract := ""                 # "" / "雇佣兵" / "封臣"（同一时间只能签一个国家）
var liege := ""                    # 宗主国 id
var fief := ""                     # 封地城 id（封臣才有: 那座城算自己的, 每天有岁入）
var player_nation_name := "潮汐港"  # 玩家给自己国家起的名字（e13d 首城后可自定义）
var at_war := {}                   # 国家id -> 停战到期日（e27e: 攻城/递战书/叛变都宣战, 到期自动停战）
var _first_conq_fired := false     # 第一次攻下城池的事件旗（只烧一次）

# —— 占城治理状态（e26a）——
var p_gar := {}                    # 城镇id -> 玩家驻军数 0..PGAR_MAX（每支压不满）
var unrest := {}                   # 城镇id -> 不满度 0-100（满 100 爆叛乱）
var prosperity := {}               # 城镇id -> 繁荣 0-100（e27h: 建设涨, 税入跟着涨）
var pending_rebels: Array[String] = []  # 爆了叛乱的城（world_map 每天取走去刷叛军队伍）

# —— 国战状态（e26b）——
var town_owner := {}               # 城镇id -> 现控制国 id（空 = 原属国; 玩家占城走 occupied）
var pending_wars: Array = []       # [{from: 攻方国id, tid: 目标城}] world_map 每天取走刷远征队
# e34e: 丢城反扑 —— 城池易主时丢城国记一笔, 次日必发兵收复（不走 WAR_CHANCE 抽签）
var pending_reclaims: Array = []   # [{from: 丢城国id, tid: 城镇id}]
var reclaim_cd := {}               # 城镇id -> 反扑冷却到期日
# e52d: 国与国的战争账本（外交页亮给玩家看）—— 键 "a|b"(字典序), 值 = 停战到期日
var ai_war := {}

func add_prestige(n: int) -> void:
	prestige = clampi(prestige + n, 0, 999)
	prestige_changed.emit()

# e29a: 海外贸易声望改按流水折算 —— 每累积卖出 SEA_PRESTIGE_PER 金 +1 声望。
# 账本挂在 Nations 侧随存档走（箱内货/在途本来就不入档, 声望进度不能跟着丢）。
# 返回本次到账实际换到的声望数（0 = 还没攒够 1000）。
func add_sea_gold(gold: int) -> int:
	sea_gold_acc += gold
	var gained := int(sea_gold_acc / float(SEA_PRESTIGE_PER))
	if gained > 0:
		sea_gold_acc -= gained * SEA_PRESTIGE_PER
		add_prestige(gained)
	return gained

# 能不能跟 nid 签 kind（"雇佣兵"/"封臣"）：空串 = 能, 否则给玩家看的理由
func can_sign_contract(nid: String, kind: String) -> String:
	if at_war_with(nid):
		return "两国正在交战, 谈不了约"
	if contract != "":
		if contract == "雇佣兵" and kind == "封臣" and liege == nid:
			return ""                    # 雇佣兵可以原地升级成封臣
		var lname := String(nation(liege).get("name", liege))
		return "你已经和 %s 签着%s协议 (一身不事二主)" % [lname, contract]
	var need := MERC_NEED if kind == "雇佣兵" else VASSAL_NEED
	if prestige < need:
		return "声望不够 (%d, 还差 %d)" % [prestige, need - prestige]
	return ""

# 签约。封臣要挑一座城当封地（fief_town）。
func sign_contract(nid: String, kind: String, fief_town := "") -> bool:
	if can_sign_contract(nid, kind) != "":
		return false
	if kind == "封臣" and fief_town != "" and not TOWNS.has(fief_town):
		return false
	contract = kind
	liege = nid
	if kind == "封臣":
		fief = fief_town
	var nname := String(nation(nid).get("name", nid))
	if kind == "雇佣兵":
		push_notice("%s雇下了你: 替它打仗, 赏金和声望都翻着算" % nname)
	else:
		var tname := String(TOWNS.get(fief, {}).get("name", fief))
		push_notice("你向 %s 称臣, 领了 %s 做封地, 每天有岁入" % [nname, tname])
	changed.emit()
	Quests.complete("contract_first")   # e32: 签下第一份契约
	# e42: 裂土封王是剧情节点 —— 签下封臣契约那一刻放一段过场
	if kind == "封臣":
		Cutscenes.play_once("ms_lord", 1.2)
	return true

# 雇佣兵解约（封臣不能无损解约 —— 想走就叛变）
func sever_contract() -> String:
	if contract == "":
		return "没有签着任何协议"
	if contract == "封臣":
		return "封臣不能一纸了断, 要走就叛变 (带上封地, 与宗主开战)"
	var lname := String(nation(liege).get("name", liege))
	contract = ""
	liege = ""
	push_notice("雇佣兵契约已解除 (%s)" % lname)
	changed.emit()
	return ""

# 封臣叛变：封地真变成自己的（occupied 插旗）, 与宗主国开战
func betray_liege() -> String:
	if contract != "封臣":
		return "只有封臣能叛变"
	var lname := String(nation(liege).get("name", liege))
	occupied[fief] = true
	start_war(liege)                 # e27e: 叛变 = 正式宣战（60 天后自动停战）
	favor[liege] = FAVOR_MIN         # 撕破脸: 关系直接跌穿底
	push_notice("你带着封地叛出 %s! 两国自此刀兵相见" % lname)
	contract = ""
	liege = ""
	fief = ""
	changed.emit()
	return ""

# 第一次攻下城池的事件旗：谁调走谁负责放庆祝（world_map）
func pop_first_conquest() -> bool:
	if _first_conq_fired:
		_first_conq_fired = false
		return true
	return false

func rename_player_nation(new_name: String) -> void:
	player_nation_name = new_name.strip_edges()
	if player_nation_name == "":
		player_nation_name = "潮汐港"
	changed.emit()

func _ready() -> void:
	reset_for_new_game()
	TimeManager.new_day.connect(_on_new_day)

# ---------------- 查询 ----------------
func nation(id: String) -> Dictionary:
	for n in NATIONS:
		if n["id"] == id:
			return n
	return {}

func nation_ids() -> Array:
	var out: Array = []
	for n in NATIONS:
		out.append(n["id"])
	return out

func towns_of(nid: String) -> Array:
	var out: Array = []
	for tid in TOWNS.keys():
		if TOWNS[tid]["nation"] == nid:
			out.append(tid)
	return out

func favor_of(nid: String) -> int:
	return int(favor.get(nid, 0))

# 个人好感查询: 领主按镇, 百夫长按国
func lord_favor_of(tid: String) -> int:
	return int(p_favor.get(tid, 0))

func captain_favor_of(nid: String) -> int:
	return int(p_favor.get("cap_" + nid, 0))

func pact_of(nid: String) -> String:
	return String(pact.get(nid, ""))

func pact_left(nid: String) -> int:
	if pact_of(nid) == "":
		return 0
	return maxi(0, int(pact_until.get(nid, 0)) - total_days())

func is_trade(nid: String) -> bool:
	return pact_of(nid) != ""

func is_allied(nid: String) -> bool:
	return pact_of(nid) == "盟约"

func daily_income() -> int:
	var sum := 0
	for nid in nation_ids():
		match pact_of(nid):
			"商盟":
				sum += TRADE_INCOME
			"盟约":
				sum += ALLY_INCOME
	return sum

func total_days() -> int:
	return (TimeManager.year - 1) * 112 + TimeManager.season * 28 + TimeManager.day

# ---------------- 交往 ----------------
func add_favor(nid: String, n: int) -> void:
	# e27e: 下限 FAVOR_MIN —— 打仗/攻城能把关系打进负数
	favor[nid] = clampi(favor_of(nid) + n, FAVOR_MIN, FAVOR_MAX)
	changed.emit()

# 个人好感（领主=镇id, 百夫长=cap_国id）: 只有碰面聊天/登门送礼才涨
func add_person_favor(pid: String, n: int) -> void:
	p_favor[pid] = clampi(int(p_favor.get(pid, 0)) + n, 0, FAVOR_MAX)
	changed.emit()

# 聊天核心：+1 好感（e18: 台词已升级为「对话组」—— 每组 2~3 段, 这里只管记账,
# 台词本身由 town_lines / captain_lines 预先取好喂给对话框）
func _chat(nid: String) -> void:
	add_favor(nid, CHAT_FAVOR)

# 取一组对话（2~3 段, 不落账）—— e18: 对话按「天+时辰+好感」轮组, 同一天说的话固定
func _chat_group(lines: Array, nid: String) -> Array:
	var grp: Array = lines[(total_days() + TimeManager.hour + favor_of(nid)) % lines.size()]
	return grp

# 聊天（按国家轮着说——兜底旧接口, 返回一组台词）
func chat(nid: String) -> Array:
	var lines: Array = CHAT_LINES.get(nid, [["..."]])
	return _chat_group(lines, nid)

# 城镇聊天：对面是领主（主城=国王, 属镇=封臣），一人一套话术
func chat_town(tid: String) -> Array:
	var nid := String(TOWNS.get(tid, {}).get("nation", ""))
	var lines: Array = LORD_LINES.get(tid, CHAT_LINES.get(nid, [["..."]]))
	if LORD_LINES.has(tid):
		add_person_favor(tid, CHAT_FAVOR)   # 领主个人也记一分工夫
	_chat(nid)
	return _chat_group(lines, nid)

# 巡逻队聊天：对面是百夫长
func chat_captain(nid: String) -> Array:
	var lines: Array = CAPTAIN_LINES.get(nid, CHAT_LINES.get(nid, [["..."]]))
	if CAPTAIN_LINES.has(nid):
		add_person_favor("cap_" + nid, CHAT_FAVOR)
	_chat(nid)
	return _chat_group(lines, nid)

# e16g/e18: 只取一组台词不落账 —— 聊天先弹对话框把这段话说完, 玩家翻完关掉框的
# 那一下才真调 chat_town / chat_captain 记好感（"对话框出来才算聊了天"）。
# 选组公式和 _chat_group 完全一致, 所以关框落账时说的还是同一组话。
func town_lines(tid: String) -> Array:
	var nid := String(TOWNS.get(tid, {}).get("nation", ""))
	var lines: Array = LORD_LINES.get(tid, CHAT_LINES.get(nid, [["..."]]))
	return _chat_group(lines, nid)

func captain_lines(nid: String) -> Array:
	var lines: Array = CAPTAIN_LINES.get(nid, CHAT_LINES.get(nid, [["..."]]))
	return _chat_group(lines, nid)

# 领主查询：{"title": "晨曦王", "name": "奥朗"}
func lord_of(tid: String) -> Dictionary:
	return LORD_NAMES.get(tid, {})

func lord_full(tid: String) -> String:
	var l: Dictionary = LORD_NAMES.get(tid, {})
	if l.is_empty():
		return ""
	return "%s %s" % [String(l.get("title", "")), String(l.get("name", ""))]

func captain_name(nid: String) -> String:
	return String(CAPTAIN_NAMES.get(nid, ""))

# e36n: 巡逻队长的称号按国别特色走（晨曦港口护卫长 / 北岭雪境巡逻长 ...）。
# 表里漏了国就退回通用的「巡逻队长」, 免得面板上出现空称号。
func captain_title(nid: String) -> String:
	return String(CAPTAIN_TITLES.get(nid, "巡逻队长"))

# 送礼：花钱买好感。成功返回风味回应，金币不够返回 ""（面板自己提示）。
# who 是收礼人名字（领主 / 百夫长），不传就用国名。
# pid 是收礼人的个人好感键（领主=镇id, 百夫长=cap_国id）：登门送礼才记个人交情，
# 外交页那种只报国名的送礼（pid 空）只涨国家好感。回话按个人交情分三档。
func gift(nid: String, who := "", pid := "") -> String:
	if not Wallet.spend_money(GIFT_COST):
		return ""
	add_favor(nid, GIFT_FAVOR)
	if pid != "":
		add_person_favor(pid, GIFT_FAVOR)
	var who_name := who if who != "" else String(nation(nid).get("name", nid))
	var pf := 30
	if pid != "":
		pf = int(p_favor.get(pid, 0))
	if pf >= 60:
		return "%s收下了礼物, 说要记你这份情." % who_name
	if pf >= 25:
		return "%s收下了礼物, 很是高兴." % who_name
	return "%s收下了礼物, 礼数周全, 话不多." % who_name

# 签约检查：返回 "" 表示可以签，否则返回原因（面板直接显示）
func can_sign(nid: String, kind: String) -> String:
	var need := TRADE_NEED if kind == "商盟" else ALLY_NEED
	if favor_of(nid) < need:
		return "好感不足 (需要 %d, 现在 %d)" % [need, favor_of(nid)]
	if pact_of(nid) == kind and pact_left(nid) > 0:
		return "协议还在有效期内"
	return ""

# 签协议：盟约覆盖商盟（等于升级），续签也走这里
func sign_pact(nid: String, kind: String) -> bool:
	if can_sign(nid, kind) != "":
		return false
	pact[nid] = kind
	pact_until[nid] = total_days() + PACT_DAYS
	var nname := String(nation(nid).get("name", nid))
	push_notice("与%s缔结%s, 有效 %d 天" % [nname, kind, PACT_DAYS])
	changed.emit()
	# e43: 缔盟是剧情节点 —— 商盟 / 盟约各放一段过场 (一段一通, 按国家记)
	if kind == "商盟":
		Cutscenes.play_once("nat_pact", 1.2, cut_ctx(nid))
	elif kind == "盟约":
		Cutscenes.play_once("nat_ally", 1.2, cut_ctx(nid))
	return true

# e43: 国家级过场的上下文 —— 国名 + 旗色进布景和台词; seen 尾让每个国家各放一次
func cut_ctx(nid: String) -> Dictionary:
	var n := nation(nid)
	return {
		"nation": String(n.get("name", nid)),
		"color": n.get("color", Color(0.72, 0.72, 0.74)),
		"seen": nid,
	}

# 撕毁/到期都走这里
func break_pact(nid: String, why := "") -> void:
	if pact_of(nid) == "":
		return
	var kind := pact_of(nid)
	pact[nid] = ""
	pact_until[nid] = 0
	var nname := String(nation(nid).get("name", nid))
	push_notice("%s的%s已失效%s" % [nname, kind, why])
	changed.emit()

# —— 战争状态（e27e）——
# 跟 nid 是否处于交战中（过期未清账时按没打处理, 当天晚些的每日结算会摘掉）
func at_war_with(nid: String) -> bool:
	return at_war.has(nid) and total_days() < int(at_war[nid])

# 宣战（攻城破城/叛变/递战书都走这里）。到期自动停战; 签着的协议当场撕毁。
func start_war(nid: String) -> void:
	if nid == "" or at_war_with(nid):
		return
	at_war[nid] = total_days() + WAR_DAYS
	break_pact(nid, "(宣战)")
	changed.emit()

# —— e52d: 国与国的战争（AI 远征/反扑开拔时记一笔, 到期自动休战; 外交页展示用）——
func _war_key(a: String, b: String) -> String:
	if a < b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]

func start_ai_war(a: String, b: String) -> void:
	if a == "" or b == "" or a == b:
		return
	if not nation_ids().has(a) or not nation_ids().has(b):
		return
	if ai_warring(a, b):
		return
	ai_war[_war_key(a, b)] = total_days() + WAR_DAYS

# 两个国家是否正在交战（按日期判, 过期未清账也算停战）
func ai_warring(a: String, b: String) -> bool:
	var k := _war_key(a, b)
	return ai_war.has(k) and total_days() < int(ai_war[k])

# nid 现在正跟哪些国家交战（国与国; 跟玩家的那条线看 at_war）
func ai_wars_of(nid: String) -> Array:
	var out := []
	for oid in nation_ids():
		if oid != nid and ai_warring(nid, oid):
			out.append(oid)
	return out

# 这两国还打多少天（没在打返回 0）
func ai_war_left(a: String, b: String) -> int:
	var k := _war_key(a, b)
	if not ai_war.has(k):
		return 0
	return maxi(0, int(ai_war[k]) - total_days())

# 主动递战书（议事厅/城镇面板用, 花外交点）。返回 "" = 成功, 否则是给面板看的理由
func declare_war(nid: String) -> String:
	if nid == "":
		return "没有国家可宣战"
	if at_war_with(nid):
		return "两国已经在交战"
	if prestige < WAR_DECLARE_COST:
		return "外交点不够 (要 %d, 现有 %d)" % [WAR_DECLARE_COST, prestige]
	prestige -= WAR_DECLARE_COST
	prestige_changed.emit()
	start_war(nid)
	add_favor(nid, -60)
	var nname := String(nation(nid).get("name", nid))
	push_notice("你向 %s 递了战书! 两国的军队从此见面就打" % nname)
	changed.emit()
	# e43: 递战书是剧情节点 —— 一段过场 (每个国家各放一次)
	Cutscenes.play_once("nat_war", 1.2, cut_ctx(nid))
	return ""

# ---------------- 攻城 ----------------
func garrison_max(tid: String) -> int:
	return int(GARRISON_OF.get(String(TOWNS.get(tid, {}).get("kind", "")), 0))

func garrison_of(tid: String) -> int:
	var cap := garrison_max(tid)
	if cap <= 0:
		return 0
	var until := int(garrison_until.get(tid, 0))
	if until > 0 and total_days() >= until:
		garrison.erase(tid)            # 重整期满：回到满编
		garrison_until.erase(tid)
		return cap
	return int(garrison.get(tid, cap))

# 该国军事力量：现控制各镇的守军之和（e26b: 按易主后的账算, 打掉会掉, 重整期回升）
func army_power(nid: String) -> int:
	var sum := 0
	for tid in ai_towns_of(nid):
		sum += garrison_of(tid)
	return sum

# 军力一句话评级（外交面板 / 断言用）
func army_word(nid: String) -> String:
	var p := army_power(nid)
	if p >= 15:
		return "兵强马壮"
	if p >= 10:
		return "武备整肃"
	if p >= 6:
		return "守备平平"
	return "不堪一击"

# 返回 "" 表示可以攻城，否则返回原因（议事厅按钮直接显示）
# e27e: 各城都能打了 —— 贸易镇也配了守军(3 人), 不再挡人; 只剩盟约和重整期两道限制
func can_siege(tid: String) -> String:
	if is_allied(owner_nation_of(tid)):     # e26b: 按现控制国算, 别打进盟友新占的城
		return "盟约之邦, 不能背盟攻城"
	if garrison_of(tid) <= 0:
		return "守军已溃, 重整还需 %d 天" % maxi(0, int(garrison_until.get(tid, 0)) - total_days())
	return ""

func siege_reward(tid: String) -> int:
	return SIEGE_LOOT_BASE + garrison_of(tid) * SIEGE_LOOT_PER

# 打赢某座城的守军：守军清零 + 好感重创 + 宣战 + 协议撕毁，返回战利品（battle_map 胜利时调用）
func on_siege_victory(tid: String) -> int:
	var left := garrison_of(tid)
	garrison[tid] = 0
	garrison_until[tid] = total_days() + GARRISON_REGROW
	var nid := owner_nation_of(tid)      # e26b: 先取现控制国 —— 谁占着打谁
	occupied[tid] = true                 # 插旗: 这片地划进你的领地, 国界线挪动
	town_owner.erase(tid)                # e26b: 城归玩家了, 旧主记账清掉
	p_gar[tid] = 0                       # 治理开账: 驻军 0, 人心未附（e26a）
	unrest[tid] = 45
	prosperity[tid] = PROSPERITY_START   # e27h: 城破百废待兴, 繁荣从低处起步
	add_favor(nid, -60)
	start_war(nid)                       # e27e: 攻打行为 = 直接宣战, 两国军队见面就打
	break_pact(nid, "(城破失守)")
	var nname := String(nation(nid).get("name", nid))
	var tname := String(TOWNS.get(tid, {}).get("name", tid))
	push_notice("%s城破, 守军溃散, %s对你宣战! 两军自此见面就打" % [tname, nname])
	push_notice("%s已归你占领, 国界线上你的旗色往外推了一截" % tname)
	if not _first_conq_fired:
		_first_conq_fired = true      # 首城事件（e13d）: world_map 胜利结算时取走放庆祝
	Quests.complete("siege_first")    # e32: 攻下第一座城
	_queue_reclaim(nid, tid)          # e34e: 丢了城的国会记仇, 次日发兵来抢
	return SIEGE_LOOT_BASE + left * SIEGE_LOOT_PER

# ---------------- 占城治理（e26a）----------------
func occupy_tax(tid: String) -> int:
	if not occupied.has(tid):
		return 0
	var base := OCCUPY_CAP_TAX if String(TOWNS.get(tid, {}).get("kind", "")) == "capital" else OCCUPY_TAX
	# e27h: 繁荣加成 —— 繁荣 100 时税入 1.5 倍
	return int(round(base * (1.0 + prosperity_of(tid) / 100.0 * 0.5)))

func pgar_of(tid: String) -> int:
	return int(p_gar.get(tid, 0)) if occupied.has(tid) else 0

func unrest_of(tid: String) -> int:
	return int(unrest.get(tid, 0)) if occupied.has(tid) else 0

# e27h: 繁荣/忠诚 —— 管理页三栏之二（军力看 pgar_of）
func prosperity_of(tid: String) -> int:
	return int(prosperity.get(tid, 0)) if occupied.has(tid) else 0

func loyalty_of(tid: String) -> int:
	return 100 - unrest_of(tid)     # 忠诚与不满一体两面

# 修葺建设（花钱, 一次 +BUILD_UP 繁荣, 税入跟着水涨船高）。返回 "" = 成功, 否则是给面板看的理由
func build_town(tid: String) -> String:
	if not occupied.has(tid):
		return "这不是你的占领城"
	if prosperity_of(tid) >= 100:
		return "百业兴旺, 无需再建"
	if not Wallet.spend_money(BUILD_COST):
		return "钱不够 (要 %d 金)" % BUILD_COST
	prosperity[tid] = mini(100, prosperity_of(tid) + BUILD_UP)
	changed.emit()
	return ""

# 派一支驻军（花钱; 每支每天 +UNREST_PER_GAR 点忠诚）。返回 "" = 成功, 否则是给面板看的理由
func station_garrison(tid: String) -> String:
	if not occupied.has(tid):
		return "这不是你的占领城"
	if pgar_of(tid) >= PGAR_MAX:
		return "驻军已满编 (%d 支)" % PGAR_MAX
	if not Wallet.spend_money(PGAR_COST):
		return "钱不够 (要 %d 金)" % PGAR_COST
	p_gar[tid] = pgar_of(tid) + 1
	changed.emit()
	return ""

# 安抚民心（花钱, 一次 +CALM_DOWN 忠诚 —— 也就是不满 -CALM_DOWN）
func calm_town(tid: String) -> String:
	if not occupied.has(tid):
		return "这不是你的占领城"
	if unrest_of(tid) <= 0:
		return "民心安定, 不用安抚"
	if not Wallet.spend_money(CALM_COST):
		return "钱不够 (要 %d 金)" % CALM_COST
	unrest[tid] = maxi(0, unrest_of(tid) - CALM_DOWN)
	changed.emit()
	return ""

# 爆叛乱的城队列（world_map 每天取走: 在城附近刷叛军队伍）
func pop_rebels() -> Array:
	var out := pending_rebels.duplicate()
	pending_rebels.clear()
	return out

func _fire_rebellion(tid: String) -> void:
	occupied.erase(tid)              # 城头变换大王旗: 归还原属国, 税也停了
	p_gar.erase(tid)
	unrest[tid] = 0
	prosperity.erase(tid)            # e27h: 城丢了, 修葺的心血也一笔勾销
	var tname := String(TOWNS.get(tid, {}).get("name", tid))
	push_notice("%s爆发叛乱! 你的旗被扯了下来, 那里不再交税" % tname)
	pending_rebels.append(tid)

# ---------------- 国战（e26b）----------------
# 现控制国（AI 视角; 玩家占领的城走 occupied 判定, 这里只管 AI 之间的易主）
func owner_nation_of(tid: String) -> String:
	return String(town_owner.get(tid, String(TOWNS.get(tid, {}).get("nation", ""))))

# 该国现控制的城（不算玩家占领的）
func ai_towns_of(nid: String) -> Array:
	var out: Array = []
	for tid in TOWNS.keys():
		if owner_nation_of(tid) == nid and not occupied.has(tid):
			out.append(tid)
	return out

# 远征队列（world_map 每天取走: 刷远征队伍上地图）
func pop_wars() -> Array:
	var out := pending_wars.duplicate(true)
	pending_wars.clear()
	return out

# AI 攻方接管这座城: 换旗 + 守军折损半编 + 封地/占领账清理（world_map 远征队进城时调）
func ai_conquer_town(tid: String, attacker: String) -> void:
	var t: Dictionary = TOWNS.get(tid, {})
	if t.is_empty() or owner_nation_of(tid) == attacker or occupied.has(tid):
		return                           # 玩家占着的城谁也啃不动（e26b 保险）
	var def := owner_nation_of(tid)
	town_owner[tid] = attacker
	occupied.erase(tid)              # 保险: 远征队不啃玩家的城, 账要对得上
	p_gar.erase(tid)
	unrest.erase(tid)
	var gmax := garrison_max(tid)
	garrison[tid] = maxi(1, gmax / 2) if gmax > 0 else 0   # 新守军只有半编; 贸易镇守备薄(3), 易主后剩 1
	garrison_until.erase(tid)
	var an := String(nation(attacker).get("name", attacker))
	var dn := String(nation(def).get("name", def))
	var tn := String(t.get("name", tid))
	push_notice("%s攻陷了%s, %s的旗被扯了下来" % [an, tn, dn])
	# 玩家的封地被打没了: 契约作废
	if fief == tid and contract != "":
		push_notice("封地 %s 易主! 你与宗主的契约作废" % tn)
		contract = ""
		liege = ""
		fief = ""
	_queue_reclaim(def, tid)          # e34e: 丢城的 AI 也会记仇, 次日发兵收复
	changed.emit()

# e34e: 丢城反扑记账 —— 冷却中的城不重复记（防双方来回拉锯刷屏）
func _queue_reclaim(loser: String, tid: String) -> void:
	if loser == "" or total_days() < int(reclaim_cd.get(tid, 0)):
		return
	reclaim_cd[tid] = total_days() + RECLAIM_CD_DAYS
	pending_reclaims.append({"from": loser, "tid": tid})

# e34e: 玩家的占领城被围攻到进度走完 -> 城丢了归攻方（world_map 攻城进度走满时调）
func player_town_lost(tid: String, attacker: String) -> void:
	if not occupied.has(tid):
		return
	occupied.erase(tid)
	p_gar.erase(tid)
	unrest.erase(tid)
	prosperity.erase(tid)
	town_owner[tid] = attacker
	var gmax := garrison_max(tid)
	garrison[tid] = maxi(1, gmax / 2) if gmax > 0 else 0   # 新主接手半编守军, 与 ai_conquer 同规
	garrison_until.erase(tid)
	add_favor(attacker, -30)
	var tn := String(TOWNS.get(tid, {}).get("name", tid))
	push_notice("%s失守! 城头变了旗色, 那里不再向你交税" % tn)
	changed.emit()
	# e43: 丢城是剧情节点 —— 一段过场 (每座城各放一次, 免得天天丢天天看)
	var ctx := cut_ctx(attacker)
	ctx["town"] = tn
	ctx["seen"] = tid
	Cutscenes.play_once("nat_lost", 1.0, ctx)

# 挑一个打得动的国家, 再挑离它最近的一座别国城（不挑玩家的占领城 —— 玩家的城谁也啃不动）
func _maybe_launch_war() -> void:
	var attackers: Array = []
	for nid in nation_ids():
		if ai_towns_of(nid).size() < 2:
			continue                  # 就剩一两座城的家底, 别出去浪
		attackers.append(nid)
	if attackers.is_empty():
		return
	var atk: String = attackers[randi() % attackers.size()]
	var best := ""
	var bd := INF
	for tid in TOWNS.keys():
		var cur := owner_nation_of(tid)
		if cur == atk or occupied.has(tid):
			continue
		var d2 := INF
		for home_tid in ai_towns_of(atk):
			var hc: Vector2i = TOWNS[home_tid]["cell"]
			var tc: Vector2i = TOWNS[tid]["cell"]
			var dd := float((hc.x - tc.x) * (hc.x - tc.x) + (hc.y - tc.y) * (hc.y - tc.y))
			if dd < d2:
				d2 = dd
		if d2 < bd:
			bd = d2
			best = tid
	if best == "":
		return
	pending_wars.append({"from": atk, "tid": best})
	start_ai_war(atk, String(owner_nation_of(best)))   # e52d: 记一笔国与国的战争
	var an := String(nation(atk).get("name", atk))
	var dn := String(nation(owner_nation_of(best)).get("name", ""))
	push_notice("%s对%s宣战! 远征军已开拔" % [an, dn])

# ---------------- 每日结算 ----------------
func _on_new_day(_day: int) -> void:
	for nid in nation_ids():
		match pact_of(nid):
			"商盟":
				Wallet.add_money(TRADE_INCOME)
			"盟约":
				Wallet.add_money(ALLY_INCOME)
	if daily_income() > 0:
		push_notice("贸易收入 +%d 金" % daily_income())
	# 封臣的封地岁入（e13g）: 首都比普通城高
	if contract == "封臣" and fief != "":
		var inc := FIEF_INCOME
		if String(TOWNS.get(fief, {}).get("kind", "")) == "capital":
			inc = FIEF_CAP_INCOME
		Wallet.add_money(inc)
		push_notice("封地 %s 岁入 +%d 金" % [String(TOWNS.get(fief, {}).get("name", fief)), inc])
	# 占城治理（e26a）: 每天收税 + 不满度涨落 + 满 100 爆叛乱
	var tax := 0
	for tid in occupied.keys():
		tax += occupy_tax(tid)
	if tax > 0:
		Wallet.add_money(tax)
		push_notice("占领城税入 +%d 金" % tax)
	for tid in occupied.keys().duplicate():
		var grow := UNREST_BASE - pgar_of(tid) * UNREST_PER_GAR
		var u := unrest_of(tid) + maxi(1, grow)
		if u >= REBEL_UNREST:
			_fire_rebellion(tid)     # 里面会 erase occupied —— 所以上面要 duplicate 遍历
		else:
			unrest[tid] = u
	# e27h: 占领城百废渐兴, 繁荣每天自然 +1（建设是大头, 这个是兜底回血）
	for tid in occupied.keys():
		prosperity[tid] = mini(100, prosperity_of(tid) + 1)
	for nid in nation_ids():
		if pact_of(nid) != "" and pact_left(nid) <= 0:
			break_pact(nid)          # 到期作废（里面会发通告）
	# e34e: 丢城反扑 —— 丢过城的国次日必定发兵收复, 不走抽签
	for r in pending_reclaims:
		var rid := String(r.get("from", ""))
		var rtid := String(r.get("tid", ""))
		if not TOWNS.has(rtid) or not nation_ids().has(rid):
			continue
		pending_wars.append({"from": rid, "tid": rtid})
		if not occupied.has(rtid):    # e52d: 反扑的也是国与国的仗（打玩家占领城不算）
			start_ai_war(rid, String(owner_nation_of(rtid)))
		push_notice("%s誓要收复%s, 复仇军已开拔!" % [
			String(nation(rid).get("name", rid)),
			String(TOWNS.get(rtid, {}).get("name", rtid))])
	pending_reclaims.clear()
	# 国战（e26b）: 小概率哪国开拔远征军去打邻国的城
	if randf() < WAR_CHANCE:
		_maybe_launch_war()
	# 战争到期自动停战（e27e）: 战争疲劳, 刀兵各收 —— 好感不会自己回升, 但能重新谈约
	for nid in at_war.keys().duplicate():
		if total_days() >= int(at_war[nid]):
			at_war.erase(nid)
			push_notice("%s与你休战: 两国的刀兵各自收了" % String(nation(nid).get("name", nid)))
	# e52d: 国与国的战争也到期休战（悄悄收场, 不发通告免得刷屏）
	for k in ai_war.keys().duplicate():
		if total_days() >= int(ai_war[k]):
			ai_war.erase(k)

# ---------------- 通告队列 ----------------
func push_notice(text: String) -> void:
	notices.append(text)
	while notices.size() > 6:
		notices.pop_front()

# 取走全部通告（海图进城 / 面板打开时显示）
func drain_notices() -> Array[String]:
	var out := notices.duplicate()
	notices.clear()
	return out

# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	return {
		"favor": favor.duplicate(),
		"p_favor": p_favor.duplicate(),
		"pact": pact.duplicate(),
		"pact_until": pact_until.duplicate(),
		"garrison": garrison.duplicate(),
		"garrison_until": garrison_until.duplicate(),
		"occupied": occupied.keys(),
		"p_gar": p_gar.duplicate(),
		"unrest": unrest.duplicate(),
		"prosperity": prosperity.duplicate(),
		"pending_rebels": pending_rebels.duplicate(),
		"town_owner": town_owner.duplicate(),
		"pending_wars": pending_wars.duplicate(true),
		"pending_reclaims": pending_reclaims.duplicate(true),   # e34e
		"reclaim_cd": reclaim_cd.duplicate(),                   # e34e
		"prestige": prestige,
		"sea_gold_acc": sea_gold_acc,
		"contract": contract,
		"liege": liege,
		"fief": fief,
		"player_nation_name": player_nation_name,
		"at_war": at_war.keys(),
		"ai_war": ai_war.duplicate(),                           # e52d
	}

func from_dict(d: Dictionary) -> void:
	var fv: Dictionary = d.get("favor", {})
	var pt: Dictionary = d.get("pact", {})
	var pu: Dictionary = d.get("pact_until", {})
	for nid in nation_ids():
		favor[nid] = clampi(int(fv.get(nid, 0)), FAVOR_MIN, FAVOR_MAX)
		var k := String(pt.get(nid, ""))
		pact[nid] = k if k == "商盟" or k == "盟约" else ""
		pact_until[nid] = int(pu.get(nid, 0))
	p_favor = (d.get("p_favor", {}) as Dictionary).duplicate()
	for pid in p_favor.keys():
		p_favor[pid] = clampi(int(p_favor[pid]), 0, FAVOR_MAX)
	garrison = (d.get("garrison", {}) as Dictionary).duplicate()
	garrison_until = (d.get("garrison_until", {}) as Dictionary).duplicate()
	occupied.clear()
	for tid in (d.get("occupied", []) as Array):
		if TOWNS.has(String(tid)):
			occupied[String(tid)] = true
	# 占城治理（e26a）: 账本只认现存的占领城
	p_gar.clear()
	unrest.clear()
	prosperity.clear()
	var pg: Dictionary = d.get("p_gar", {})
	var un: Dictionary = d.get("unrest", {})
	var pr: Dictionary = d.get("prosperity", {})
	for tid in occupied.keys():
		p_gar[tid] = clampi(int(pg.get(tid, 0)), 0, PGAR_MAX)
		unrest[tid] = clampi(int(un.get(tid, 0)), 0, 100)
		prosperity[tid] = clampi(int(pr.get(tid, 0)), 0, 100)   # e27h: 旧档没有此账本, 默认 0 再靠每日 +1 涨
	pending_rebels.clear()
	for tid in (d.get("pending_rebels", []) as Array):
		if TOWNS.has(String(tid)):
			pending_rebels.append(String(tid))
	# 国战账本（e26b）: 易主只认合法的城+国, 远征队列整条还原
	town_owner.clear()
	var to: Dictionary = d.get("town_owner", {})
	for tid in to.keys():
		var tk := String(tid)
		if TOWNS.has(tk) and nation_ids().has(String(to[tid])):
			town_owner[tk] = String(to[tid])
	pending_wars.clear()
	for w in (d.get("pending_wars", []) as Array):
		var wd: Dictionary = w
		var wk := String(wd.get("from", ""))
		var wt := String(wd.get("tid", ""))
		if TOWNS.has(wt) and nation_ids().has(wk):
			pending_wars.append({"from": wk, "tid": wt})
	# e34e: 反扑队列与冷却一并还原（旧档没有这两本账, 走默认空）
	pending_reclaims.clear()
	for w in (d.get("pending_reclaims", []) as Array):
		var rd: Dictionary = w
		var rk := String(rd.get("from", ""))
		var rt := String(rd.get("tid", ""))
		if TOWNS.has(rt) and nation_ids().has(rk):
			pending_reclaims.append({"from": rk, "tid": rt})
	reclaim_cd = (d.get("reclaim_cd", {}) as Dictionary).duplicate()
	prestige = clampi(int(d.get("prestige", 0)), 0, 999)
	sea_gold_acc = maxi(int(d.get("sea_gold_acc", 0)), 0)
	contract = String(d.get("contract", ""))
	contract = contract if contract == "雇佣兵" or contract == "封臣" else ""
	liege = String(d.get("liege", ""))
	fief = String(d.get("fief", ""))
	player_nation_name = String(d.get("player_nation_name", "潮汐港"))
	if player_nation_name == "":
		player_nation_name = "潮汐港"
	at_war.clear()
	# e27e: 存档只存国家id列表, 值统一给满战争期; 旧档(true)也兼容
	for nid in (d.get("at_war", []) as Array):
		if nation_ids().has(String(nid)):
			at_war[String(nid)] = total_days() + WAR_DAYS
	# e52d: 国与国战争账本（旧档没有, 走默认空）
	ai_war.clear()
	var aw: Dictionary = d.get("ai_war", {})
	for k in aw.keys():
		var wp := String(k).split("|")
		if wp.size() == 2 and nation_ids().has(wp[0]) and nation_ids().has(wp[1]):
			ai_war[String(k)] = maxi(int(aw[k]), total_days() + 1)
	changed.emit()

func reset_for_new_game() -> void:
	favor.clear()
	p_favor.clear()
	pact.clear()
	pact_until.clear()
	garrison.clear()
	garrison_until.clear()
	occupied.clear()
	p_gar.clear()
	unrest.clear()
	prosperity.clear()
	pending_rebels.clear()
	town_owner.clear()
	pending_wars.clear()
	pending_reclaims.clear()
	reclaim_cd.clear()
	notices.clear()
	prestige = 0
	contract = ""
	liege = ""
	fief = ""
	player_nation_name = "潮汐港"
	at_war.clear()
	ai_war.clear()                    # e52d
	_first_conq_fired = false
	for nid in nation_ids():
		favor[nid] = 0
		pact[nid] = ""
		pact_until[nid] = 0
	changed.emit()
