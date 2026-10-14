extends RefCounted
# scripts_marriage.gd —— 婚恋剧本工厂（静态）
#
# 三类剧本走 story_dialogue.play_directed 的实景舞台:
#   heart_script(slave_idx, stage)   五段生活事件, 按人物安排地点/动作/心事/回应
#   propose_script(slave_idx)        在两人熟悉的地点交付戒指, 答词每位专属
#   wedding_script(slave_idx)        海边亲友见证 -> 两人一起回家
# 台词行 {"name","portrait","text"}；指令行 {"fx": ...}。
# ❗标点只用 ASCII（IPix.ttf 没有全角字形）；文案不用「」『』等字符。

# ROSTER 名字（与 slaves.gd 同序；只有 6 位女性有婚恋剧本）
const NAMES := ["咪露", "布恩", "珞琳", "娜雅", "塔洛", "汐月", "珂丹", "雪莱"]
const FEMALE := [true, false, true, true, false, true, true, true]

static func _p(idx: int) -> String:
	return "slave_%02d" % idx

# 演员键由花名册序号决定, 与实景帧工厂和头像保持一致.
static func _f(idx: int) -> String:
	return "s%02d" % idx

static func _me() -> Dictionary:
	return {"name": "我", "portrait": "player"}

static func _her(idx: int) -> Dictionary:
	return {"name": String(Slaves.ROSTER[idx]["name"]), "portrait": _p(idx)}

# 台词行构造（GDScript 不支持字典展开 {**d, ...}，用 helper 拼）
static func _line(base: Dictionary, text: String) -> Dictionary:
	return {"name": base["name"], "portrait": base["portrait"], "text": text}

static func _available(idx: int) -> bool:
	return idx >= 0 and idx < NAMES.size() and FEMALE[idx]

# ---------------- 心里话 ----------------
# 每位 5 段（对应好感能门槛 2/4/6/8/10），行 = ["h"/"m", 文案]。
# 六位各有专属的"念想物"贯穿第 2 段：娜雅-铜勺 / 珞琳-木簪 / 咪露-旧布条 /
# 汐月-半枚罗盘 / 珂丹-种子袋 / 雪莱-写坏的算稿。
# 每段 = 地点/道具/正在做的小事/回应/心事/玩家支持/人物收束.
const HEART_EVENTS := {
	"rq_00": [
		[
			"camp",
			"sword",
			"刀口上还有个缺口. 先别靠太近, 我把这一遍磨完.",
			"我等你. 石头要不要换个平整的?",
			"......这块正好. 我总怕夜里睡熟了, 又有人走散.",
			"今天我陪你守前半夜. 后半夜, 你安心睡.",
			"那你坐这里. 有人替我看着火, 我就歇一会儿."
		],
		[
			"workshop",
			"sword",
			"这根木条是练步法用的. 你踩到线了, 再来一次.",
			"原来不是比谁出刀快, 是先站稳.",
			"对. 上次船晃的时候, 我连你的袖子都没抓住.",
			"这次我站稳了. 你退一步, 我就跟一步.",
			"......这回及格. 明天还来, 不许找借口."
		],
		[
			"camp",
			"cloth",
			"别扔那条旧布. 我还要缠回刀柄上.",
			"边都磨白了. 对你很重要吧?",
			"离家时从袖口撕的. 我娘缝的. 我一直没敢洗掉上面的盐.",
			"你不必现在放下它. 我陪你重新缠好.",
			"嗯. 这次不用攥那么紧, 也不会再丢了."
		],
		[
			"coast",
			"sword",
			"今天不练刀. 你过来一点, 我有话说.",
			"这里没有别人, 你慢慢说.",
			"我以前只想着守住身后的人. 现在, 也想有人站在我身边.",
			"那我就站这里. 够近吗?",
			"......再近半步. 不是命令, 是我想的."
		],
		[
			"camp",
			"cloth",
			"这条布我重新缝好了. 你看, 不会散了.",
			"针脚比上次整齐. 你练了很久?",
			"嗯. 有句话也练了很久. 我喜欢你, 想守着你, 也想被你惦记.",
			"我也喜欢你. 往后一起守, 一起回家.",
			"那就说定了. 今晚刀先放下, 我想好好看看你."
		]
	],
	"rq_02": [
		[
			"camp",
			"wood",
			"这块挡风板总往一边歪. 帮我扶住这头.",
			"这样行吗? 我再往里挪一点.",
			"行. 一个人能把它钉上, 可总要拆了再来.",
			"以后扶板子的事喊我. 不用拆第二遍.",
			"......好. 今晚终于能坐下, 听一会儿火声了."
		],
		[
			"workshop",
			"plan",
			"图纸上这两个凳子, 间隔是不是太远了?",
			"你坐一个, 我坐一个, 试试就知道.",
			"我改了三回. 一直只做一个人的家具, 忽然不会量了.",
			"现在这个距离, 刚好够把茶递给你.",
			"那就不改了. 另一个凳子, 给你留着."
		],
		[
			"workshop",
			"hairpin",
			"这根木簪磨好了. 先看, 别急着夸.",
			"连边角都圆了. 手指摸过去一点也不扎.",
			"本来想做得更好. 可刨这一根, 比搭梁还紧张.",
			"已经很好了. 我会认真收着.",
			"那就给你. 这回做的东西, 总算有了主人."
		],
		[
			"house",
			"plan",
			"门框量完了. 还差一个尺寸, 得请你站过来.",
			"站这里? 你怎么把尺收起来了?",
			"尺寸够了. 只是借个理由, 让你多留一会儿.",
			"那我不用理由, 也愿意留下.",
			"......嗯. 今后的图纸上, 都留你的位置."
		],
		[
			"house",
			"hairpin",
			"我带了木簪来. 今天没有活要你帮忙.",
			"那我们就坐一会儿.",
			"我喜欢你. 屋子盖好了总会交给别人, 可这个家, 我想和你一起住.",
			"我也是. 以后门里门外, 都有我们两个.",
			"好. 这句话不用画在图纸上, 我记得住."
		]
	],
	"rq_03": [
		[
			"camp",
			"bowl",
			"别站在烟里. 帮我尝尝这碗粥, 会不会太淡?",
			"刚好. 你自己的那碗呢?",
			"......还没盛. 以前做饭, 总怕最后不够别人吃.",
			"那先盛你的. 我在这里等, 咱们一起吃.",
			"好. 原来有人等我吃饭, 是这个滋味."
		],
		[
			"field",
			"grain",
			"这袋收成先留出来. 我想试着熬一锅不一样的粥.",
			"又是给大家做的?",
			"嗯......也想让你先尝. 我只会做饭, 不知道还能送你什么.",
			"让我帮你提这一袋. 一起做, 就是礼物了.",
			"行, 那你不能偷吃. 第一碗我亲手给你盛."
		],
		[
			"camp",
			"spoon",
			"这把铜勺是我娘留下的. 我今天才舍得拿出来.",
			"勺柄磨得发亮, 一定用过很多年.",
			"是啊. 船翻以后, 我总觉得再用一次, 念想就少一次.",
			"用它做一顿新的饭, 念想也会多一点.",
			"......你说得对. 今晚就用它, 给咱们盛粥."
		],
		[
			"camp",
			"bowl",
			"粥已经盛好两碗了. 今天你不用替我守火.",
			"那我坐哪边?",
			"这边. 近一点. 我想说话的时候, 不用隔着烟喊你.",
			"我听着. 你小声说也听得见.",
			"那我说......每天收工最盼的, 就是这一会儿."
		],
		[
			"camp",
			"spoon",
			"今天这锅没有替别人留. 就两碗, 咱们的.",
			"我闻着味道就来了.",
			"我喜欢你. 不是因为你爱喝我的粥, 是没看见你, 我就总想往路口瞧.",
			"我也喜欢你. 明天, 后天, 我都来陪你吃饭.",
			"好. 那碗你拿稳了, 我有点高兴得手抖."
		]
	],
	"rq_05": [
		[
			"camp",
			"compass",
			"你看这火光. 一亮一暗, 像我家那边的灯塔.",
			"你一直盯着, 是想家了?",
			"嗯. 船翻以后, 我再没看见过那盏灯. 不敢睡, 怕醒来又换了岸.",
			"这次不会. 天亮以后, 我们还在这里.",
			"那我试着闭会儿眼. 火别灭, 好吗?"
		],
		[
			"coast",
			"compass",
			"这枚罗盘不转了, 我却每天都拿着看.",
			"今天它指向哪里?",
			"哪儿也不指. 可你站到旁边时, 我忽然不着急修它了.",
			"先陪我看一会儿海吧. 不必马上赶路.",
			"好. 头一回有人告诉我, 停下来也算往前走."
		],
		[
			"coast",
			"compass",
			"给你看清楚. 罗盘只有半枚, 另一半和旧船沉了.",
			"断口都磨平了. 你带着它走了很远.",
			"以前怕忘记来处. 现在又怕自己不该喜欢新的地方.",
			"记着来处, 也可以喜欢这里. 我陪你.",
			"......那今天, 让它指一回回家的路."
		],
		[
			"coast",
			"compass",
			"风大, 站远了听不清. 你过来一点.",
			"这样能听见了吗?",
			"能. 其实风没有那么大. 是我想让你靠近.",
			"我本来就想往你这边走.",
			"那别急着回去. 我还有好多话, 只想说给你听."
		],
		[
			"coast",
			"compass",
			"今天不看罗盘了. 我知道自己要去哪儿.",
			"去哪儿? 我陪你走.",
			"我喜欢你. 不是因为需要同行的人, 是走了那么远, 最想回到你身边.",
			"我也喜欢你. 这里一直给你留着位置.",
			"那我的锚就落在这里. 下次出海, 我们一起回来."
		]
	],
	"rq_06": [
		[
			"camp",
			"seeds",
			"别踩这边. 我把栗子埋在灰里, 还没熟呢.",
			"火都快小了, 要添柴吗?",
			"不用. 有些东西催得太快, 里面反倒是生的. 我从前总等不住.",
			"那咱们坐着等. 我也学学你的办法.",
			"好. 你肯等, 这栗子就有两个人分了."
		],
		[
			"field",
			"seeds",
			"这一排苗总向一边歪. 你帮我挡一下风.",
			"这样? 小叶子好像不抖了.",
			"嗯. 我照顾苗惯了, 却总忘记自己也能请人搭把手.",
			"以后你看苗, 我帮你看风.",
			"那就搭伙. 先从今天这一小排开始."
		],
		[
			"field",
			"seeds",
			"这袋种子是我最后留的一份. 今天想分给你.",
			"这么金贵, 你舍得?",
			"舍得. 放在口袋里只能数日子, 种下去才有明年. 我一个人总下不了决心.",
			"我们一起种. 明年一起回来看看.",
			"好. 别种太深. 就像心事, 也得有地方透口气."
		],
		[
			"garden",
			"seeds",
			"来这里站一会儿. 两个人的影子刚好替苗挡住风.",
			"你选的位置真准.",
			"......也不全是为了苗. 我发现跟你待着, 不做什么也很高兴.",
			"那今天就不急着走.",
			"好. 这次不用等发芽, 现在就很不错."
		],
		[
			"field",
			"seeds",
			"还记得这袋种子吗? 我给明年也留了两个人的份.",
			"记得. 你说到时候要考我.",
			"今天先告诉你答案. 我喜欢你, 想和你把日子一年一年种下去.",
			"我也喜欢你. 明年的地, 我们一起整.",
			"那就说定了. 今年的春天, 比我想的还要长."
		]
	],
	"rq_07": [
		[
			"camp",
			"plan",
			"我记了三晚: 为什么坐到火边, 就容易说实话?",
			"你连这个也要算?",
			"是啊. 可纸上记满了, 轮到自己的事, 我就不敢写.",
			"不想写也没关系. 我可以先听.",
			"那先把纸放下. 今天试试, 不求答案的谈话."
		],
		[
			"house",
			"plan",
			"这笔账又错了. 数目没错, 可我总觉得少了一项.",
			"我们把两边放在一起看看.",
			"以前只算够不够活下去. 现在总想添上明年的事, 还有你想做的事.",
			"那就加一栏, 叫我们以后要做的事.",
			"好. 这一栏, 你也得签名."
		],
		[
			"workshop",
			"plan",
			"这张算稿第一行就错了, 可我一直留着.",
			"是什么题?",
			"上岛那天, 我算留在这里值不值得. 当时算出来不值得. 漏掉的那一项, 是你.",
			"现在改还来得及. 我们一起写新的.",
			"嗯. 旧稿我也留着, 提醒自己别再只算一个人."
		],
		[
			"house",
			"plan",
			"过来一点. 我有个推导, 缺个样本.",
			"样本是不是我?",
			"......是. 为什么你坐得越近, 我就越不想回去? 我算了三天.",
			"也许这次, 你不用算.",
			"那我试着相信自己的感觉. 你先别走."
		],
		[
			"camp",
			"plan",
			"这页草稿我写了好多遍. 今天不照着念了.",
			"我听着, 不着急.",
			"我喜欢你. 不是一道算出来的题, 是每天想到你, 就想把明天也过好.",
			"我也喜欢你. 往后的题, 我们慢慢一起解.",
			"好. 总算有一件事, 不需要在末尾打问号了."
		]
	]
}

static func heart_script(idx: int, stage: int) -> Array:
	if not _available(idx):
		return []
	var st := clampi(stage, 0, 4)
	var e: Array = HEART_EVENTS[_id(idx)][st]
	var her := _her(idx)
	var actor := _f(idx)
	var lines: Array = [
		{"fx": "bg", "scene": e[0], "title": NAMES[idx] + " / " + ["留下片刻", "一起做的小事", "珍藏", "靠近一点", "心意"][st]},
		{"fx": "show", "who": actor, "at": "ml"},
		{"fx": "show", "who": "you", "at": "r", "from": "entry_r"},
		{"fx": "prop", "kind": e[1], "at": [-1, -0.7]},
		{"fx": "face", "who": actor, "target": "you"},
		{"fx": "face", "who": "you", "target": actor},
		_line(her, e[2]),
		_line(_me(), e[3]),
	]
	if st == 0:
		lines.append({"fx": "act", "who": actor, "pose": "nod"})
		lines.append({"fx": "move", "who": "you", "to": "mr"})
	elif st == 1:
		lines.append({"fx": "move", "who": "you", "to": "mr"})
		lines.append({"fx": "give", "to": "you"})
	elif st == 2:
		lines.append({"fx": "give", "to": "you"})
	elif st == 3:
		lines.append({"fx": "move", "who": "you", "to": "mr"})
	else:
		lines.append({"fx": "face", "who": actor, "dir": "up"})
		lines.append({"fx": "wait", "t": 0.6})
		lines.append({"fx": "face", "who": actor, "target": "you"})
	lines.append(_line(her, e[4]))
	lines.append({"fx": "wait", "t": 0.4})
	if st in [2, 4]:
		lines.append({"choice": "我想告诉她......", "options": [
			{"text": e[5], "lines": [_line(_me(), e[5]), _line(her, e[6])]},
			{"text": "不用急着把话说完, 我会在这里陪你.", "lines": [
				_line(_me(), "不用急着把话说完, 我会在这里陪你."),
				_line(her, "......好. 让我再和你待一会儿. 今天这些话, 我只想说给你听.")]}]})
	else:
		lines.append(_line(_me(), e[5]))
		lines.append({"fx": "face", "who": "you", "target": actor})
		lines.append(_line(her, e[6]))
	lines.append({"fx": "emote", "who": actor, "kind": "heart" if st >= 3 else "note"})
	lines.append({"fx": "wait", "t": 0.6})
	return lines

static func _id(idx: int) -> String:
	return "rq_%02d" % idx

# ---------------- 求婚 ----------------
# 答词每位专属（她最后答应的两句）
const PROPOSE_REPLY := {
	"rq_00": ["你, 你什么时候备的戒指?! 我天天站你旁边站岗, 竟然一点都没察觉......", "......好. 我答应了. 刀客说话, 一个字就是一道令."],
	"rq_02": ["戒指.......先别给我戴上, 手上有木屑.", "好了. 戴吧. 这根手指, 往后就只干一件事: 牵着你."],
	"rq_03": ["粥, 火, 铜勺, 还有你.......全都在, 我还挑什么呢.", "好, 一百个好. 以后这口锅, 就煮我们两个人的粥."],
	"rq_05": ["我漂了半辈子海, 原来岸在这儿等着.", "我答应了. 往后你走到哪, 我的箭就落在哪."],
	"rq_06": ["急什么你.......好, 这次我也不急了, 我现在就答应.", "石头开花了. 你瞧, 我说的吧, 慢慢等, 都会有的."],
	"rq_07": ["这一题不用验证, 我直接给你满分.", "批了批了. 往后你的账本第一页, 户主写两个名字."],
}

static func propose_script(idx: int) -> Array:
	if not _available(idx):
		return []
	var actor := _f(idx)
	var her := _her(idx)
	var lines: Array = [
		{"fx": "bg", "scene": HEART_EVENTS[_id(idx)][4][0], "title": "一个郑重的约定"},
		{"fx": "show", "who": actor, "at": "ml"},
		{"fx": "show", "who": "you", "at": "r", "from": "entry_r"},
		{"fx": "face", "who": actor, "target": "you"},
		_line(her, "今天怎么这么安静? 你有话想对我说?"),
		{"fx": "move", "who": "you", "to": "mr"},
		{"fx": "face", "who": "you", "target": actor},
		_line(_me(), "嗯. 往后的日子, 我想每天都和你一起过."),
		{"fx": "prop", "kind": "ring", "at": [1, -0.7]},
		{"fx": "wait", "t": 0.7},
		_line(_me(), "嫁给我, 好吗?"),
		{"fx": "emote", "who": actor, "kind": "!"},
		{"fx": "wait", "t": 0.5},
	]
	for text in PROPOSE_REPLY[_id(idx)]:
		lines.append(_line(her, text))
	lines.append({"fx": "give", "to": actor})
	lines.append({"fx": "emote", "who": actor, "kind": "heart"})
	lines.append(_line(_me(), "那就说定了. 我们一起回家."))
	lines.append({"fx": "wait", "t": 0.8})
	return lines

# ---------------- 婚礼 ----------------
# 誓词每位专属（夜篝火那段她说的一句话）
const WEDDING_VOW := {
	"rq_00": "一起. 我的刀, 我的人, 从今天起都写你的名字.",
	"rq_02": "一起. 我把梁正好了, 你安心住一辈子.",
	"rq_03": "一起. 粥给你盛, 柴我来劈, 日子给你过, 一辈子不改口.",
	"rq_05": "一起. 我的锚落在这儿了, 风浪再大也不起锚.",
	"rq_06": "一起. 明年开春, 咱们把春天种得比今年更满.",
	"rq_07": "一起. 这道题我算明白了: 答案是你, 解是你, 全都是你.",
}

static func wedding_script(idx: int) -> Array:
	if not _available(idx):
		return []
	var actor := _f(idx)
	var her := _her(idx)
	var lines: Array = [{"fx": "bg", "scene": "beach", "title": "潮汐港的婚礼"},
		{"fx": "show", "who": actor, "at": "ml"},
		{"fx": "show", "who": "you", "at": "mr"}]
	# 只安排已经入伙的亲友, 两排错位, 不凭空让未认识的人参加.
	var guest := 0
	for i in Slaves.count:
		if i == idx:
			continue
		lines.append({"fx": "show", "who": _f(i), "at": [-3 + (guest % 4) * 2, -2 - floori(float(guest) / 4.0)]})
		lines.append({"fx": "face", "who": _f(i), "dir": "down"})
		guest += 1
	lines.append({"fx": "face", "who": actor, "target": "you"})
	lines.append({"fx": "face", "who": "you", "target": actor})
	lines.append(_line(her, "真没想到, 我的婚礼会在海边办. 大家真的都来陪我们了."))
	lines.append(_line(_me(), "他们陪我们走到这里. 往后的日子, 我想和你一起走."))
	lines.append({"fx": "prop", "kind": "ring", "at": [1, -0.7]})
	lines.append({"fx": "give", "to": actor})
	lines.append(_line(her, WEDDING_VOW[_id(idx)]))
	lines.append({"fx": "emote", "who": actor, "kind": "heart"})
	lines.append({"fx": "emote", "who": "you", "kind": "heart"})
	for i in Slaves.count:
		if i != idx:
			lines.append({"fx": "emote", "who": _f(i), "kind": "note"})
	lines.append({"fx": "wait", "t": 0.8})
	# 第二幕重新布置两人, 不再把镜头切到无人篝火.
	lines.append_array([
		{"fx": "bg", "scene": "house", "title": "一起回家"},
		{"fx": "show", "who": actor, "at": "ml"},
		{"fx": "show", "who": "you", "at": "mr"},
		{"fx": "face", "who": actor, "target": "you"},
		{"fx": "face", "who": "you", "target": actor},
		_line(her, "刚才还有点紧张. 现在只想和你, 安安静静地待一会儿."),
		_line(_me(), "好. 到家了."),
		{"fx": "wait", "t": 0.8}])
	return lines
