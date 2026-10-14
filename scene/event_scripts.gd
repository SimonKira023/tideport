extends RefCounted
# 全部主线事件用可见的人和道具讲述. 海上战报在返港后由伙伴交接.
const SCENES := ["camp", "house", "workshop", "garden", "field", "coast", "cliff", "docks", "harbor", "beach", "goblin", "wake"]
const COMMANDS := ["bg", "show", "move", "face", "act", "emote", "wait", "prop", "give", "focus", "cam", "hide", "sfx", "bgm", "bgm_off", "duck", "unduck"]

# 静态验收检查演员生命周期, 分支与道具交接, 防止文案完整而舞台缺人.
static func validate(script: Array, cast: Dictionary = {}) -> Array:
	var errors: Array = []
	var actors := cast.duplicate()
	var props := {}
	for row: Dictionary in script:
		var kind := str(row.get("fx", ""))
		if kind == "bg":
			actors.clear()
			props.clear()
			if not SCENES.has(str(row.get("scene", ""))):
				errors.append("未知地点: " + str(row.get("scene", "")))
		elif kind == "show":
			actors[str(row.get("who", ""))] = true
		elif kind in ["move", "face", "act", "emote", "focus"]:
			if not actors.has(str(row.get("who", ""))):
				errors.append("演员未登场: " + str(row.get("who", "")))
		elif kind == "prop":
			props[str(row.get("id", "object"))] = true
		elif kind == "give":
			if not props.has(str(row.get("id", "object"))) or not actors.has(str(row.get("to", ""))):
				errors.append("交接缺少道具或接收人")
		elif row.has("choice"):
			for option: Dictionary in row.get("options", []):
				errors.append_array(validate(option.get("lines", []), actors))
		if kind != "" and not COMMANDS.has(kind):
			errors.append("未知动作: " + kind)
	return errors

static func texts(script: Array) -> String:
	var result := ""
	for row: Dictionary in script:
		for key in ["title", "name", "text", "choice"]:
			result += str(row.get(key, ""))
		for option: Dictionary in row.get("options", []):
			result += str(option.get("text", "")) + texts(option.get("lines", []))
	return result
static func line(who: String, text: String) -> Dictionary:
	var name := "我"
	var portrait := "player"
	if who == "goblin":
		name = "哥布林"
		portrait = "goblin"
	elif who.begins_with("s"):
		var i := int(who.trim_prefix("s"))
		name = String(Slaves.ROSTER[i]["name"])
		portrait = "slave_%02d" % i
	return {"name": name, "portrait": portrait, "text": text}

static func pair(scene: String, who: String, title: String) -> Array:
	return [{"fx": "bg", "scene": scene, "title": title},
		{"fx": "show", "who": who, "at": "ml"},
		{"fx": "show", "who": "you", "at": "r", "from": "entry_r"},
		{"fx": "face", "who": who, "target": "you"},
		{"fx": "face", "who": "you", "target": who}]

static func opening() -> Array:
	var s: Array = [{"fx": "bg", "scene": "wake", "title": "风暴之后"},
		{"fx": "show", "who": "you", "at": "m"},
		{"fx": "face", "who": "you", "dir": "up"},
		{"name": "序章", "portrait": "", "text": "祖国晨曦被五国瓜分. 你和伙伴乘船逃离, 却在风暴中失散了."},
		{"fx": "wait", "t": 0.6},
		{"fx": "face", "who": "you", "dir": "right"},
		line("you", "......船呢? 大家在哪里?"),
		{"fx": "move", "who": "you", "to": "mr"},
		line("you", "那边有一间屋子......还有人在生火. 先去问问."),
		{"fx": "wait", "t": 0.4}]
	s.append_array(pair("goblin", "goblin", "桥头的陌生人"))
	s.append_array([
		{"fx": "emote", "who": "goblin", "kind": "!"},
		line("goblin", "哟, 昨晚被潮水送来的? 能走到这里, 命还挺硬."),
		line("you", "你见过和我一起漂来的人吗?"),
		{"fx": "face", "who": "goblin", "dir": "up"},
		{"fx": "wait", "t": 0.5},
		{"fx": "face", "who": "goblin", "target": "you"},
		line("goblin", "坡上昨夜有火光. 可你现在这个样子, 先别到处找."),
		{"fx": "prop", "kind": "plan", "at": [-1, -0.7]},
		{"fx": "give", "to": "you"},
		line("goblin", "往西那间空屋借你歇脚. 先进屋看看, 床边有能用的家当."),
		line("you", "谢谢. 我先站稳脚跟, 再把大家找回来."),
		line("goblin", "记着回来照顾生意. 这岛没名字, 日子可得有人过."),
		{"fx": "wait", "t": 0.6}])
	return s

static func rod() -> Array:
	var s := pair("goblin", "goblin", "藏不住的鱼竿")
	s.append_array([
		{"fx": "prop", "kind": "rod", "at": [-1, -0.5]},
		{"fx": "face", "who": "goblin", "dir": "up"},
		line("you", "原来你会钓鱼. 昨天怎么不告诉我?"),
		{"fx": "emote", "who": "goblin", "kind": "!"},
		{"fx": "face", "who": "goblin", "target": "you"},
		line("goblin", "嘘, 别吓跑了......哎, 咬钩了!"),
		{"fx": "act", "who": "goblin", "pose": "jump"},
		{"fx": "prop", "id": "catch", "kind": "fish", "at": [0, -0.5]},
		{"fx": "wait", "t": 0.6},
		line("you", "鱼都上岸了, 这下不能再藏着了吧?"),
		line("goblin", "行行行. 先看浮子, 沉下去再提竿, 别一着急就乱拽."),
		{"fx": "move", "who": "you", "to": "mr"},
		{"fx": "face", "who": "you", "target": "goblin"},
		line("goblin", "摊子那批竿子明天就摆上. 五十金一根, 想学就来."),
		line("you", "成交. 往后钓上来的鱼, 也照顾你的生意."),
		{"fx": "wait", "t": 0.5}])
	return s

static func naming() -> Array:
	var who := "s00" if Slaves.count > 0 else "goblin"
	var s := pair("house" if Slaves.count > 0 else "goblin", who, "给这个家一个名字")
	s.append_array([
		{"fx": "prop", "kind": "fish", "at": [1, -0.6]},
		line(who, "第一条鱼真的带回来了. 这地方, 总算有了过日子的样子."),
		line("you", "醒来那天, 我连这里叫什么都不知道."),
		{"fx": "move", "who": "you", "to": "mr"},
		{"fx": "face", "who": "you", "target": who},
		line(who, "潮水把人送来, 岸就把人接住. 叫潮汐港, 怎么样?"),
		line("you", "潮汐港. 就这个."),
		{"fx": "prop", "kind": "plan", "at": [-1, -0.6]},
		line(who, "那我记下了. 以后出门, 就有个能报给别人听的家了."),
		{"fx": "emote", "who": who, "kind": "note"},
		{"fx": "wait", "t": 0.6}])
	return s

const MILESTONES := {
	"harbor": ["harbor", "潮风号下水", "wood",
		"缆绳已经系好. 看, 潮风号稳稳浮住了.",
		"我真担心第一次下水会漏. 现在总算敢松口气了.",
		"船有了, 岸也有人等. 往后出海, 记得把大家平安带回来.",
		"嗯. 第一次出航, 我们一起去, 一起回来."],
	"ms_navy": ["harbor", "平安归港", "letter",
		"战报收到了. 可我还是想亲眼看见你们回来.",
		"都回来了. 刚才还握着缆绳的手, 现在才知道在抖.",
		"赢了也会害怕, 不丢人. 船要补, 人也要歇. 今晚先把饭吃好.",
		"好. 这场首胜, 是大家一起带回来的."],
	"siege_first": ["house", "第一座城的来信", "flag",
		"城里的消息来了. 门已经打开, 可百姓还不敢出屋.",
		"先把粮食和药送进去. 旗可以慢慢换, 人不能再挨饿.",
		"我把这句话写进回信. 他们需要知道, 新主人的第一道命令是什么.",
		"告诉他们, 先过好今天. 这座城, 我们一起守."],
	"ms_lord": ["house", "契约之后", "letter",
		"契约最后一处也盖好印了. 有人开始喊你主公了.",
		"我还不习惯. 以前想的是下一顿饭, 现在得想着许多人的明天.",
		"那就先把这张契收好. 称呼会慢慢习惯, 答应别人的事可不能忘.",
		"我记着. 今天起, 每个名字都要有着落."],
	"ms_unify": ["harbor", "远航的尽头", "map",
		"最后一封停战的消息到了. 海图上, 再没有要绕开的战线了.",
		"原来盼了这么久的事, 真到了, 只想回家坐一会儿.",
		"那就坐吧. 明天还有船要补, 田要浇. 潮汐港一直在这里等你.",
		"好. 往后的航线, 画去能一起过日子的地方."],
	"nat_pact": ["harbor", "通商的第一箱货", "grain",
		"%s的第一箱货到了. 先对清数目, 再搬进仓里.",
		"这边清点好了. 让船员也下来喝口水, 一路辛苦了.",
		"数目对上了, 来往也就开始了. 下次他们会认得这处码头.",
		"好. 把回程的货也备上, 别让他们空船回去."],
	"nat_ally": ["house", "留下的盟约", "letter",
		"这是和%s签下的盟约. 两边各留一份, 都已经盖印了.",
		"把联络的航线也记进去. 真有急事, 才找得到彼此.",
		"我记好了. 纸上写守望相助很容易, 以后要靠行动兑现.",
		"嗯. 也告诉大家, 海上多了一盏能认出来的灯."],
	"nat_war": ["house", "出发以前", "map",
		"给%s的战书递出去了. 往那边走的商船, 得先叫回来.",
		"先通知船员和商贩. 让他们避开交战的海域.",
		"路线已经标好. 你也看清楚, 打完以后, 还要沿着这条路回来.",
		"我会记得. 先护好岛上和船上的人."],
	"nat_lost": ["house", "失城的消息", "letter",
		"%s那边的消息送到了. %s失守, 守军已经撤出来了.",
		"先点清回来的人. 伤者安排休息, 失散的人继续找.",
		"我这就去安排. 城还能再争, 这些名字, 一个都不能漏.",
		"嗯. 我们先接住回来的人, 再商量下一步."]
}

static func milestone(id: String, ctx: Dictionary) -> Array:
	if id == "goblin_rod":
		return rod()
	var e: Array = MILESTONES[id]
	var who := "s00" if Slaves.count > 0 else "goblin"
	if id == "harbor" and Slaves.count > 2:
		who = "s02"
	elif id in ["nat_pact", "nat_ally", "ms_lord"] and Slaves.count > 4:
		who = "s04"
	var opening := str(e[3])
	if id in ["nat_pact", "nat_ally", "nat_war"]:
		opening = opening % str(ctx.get("nation", "邻国"))
	elif id == "nat_lost":
		opening = opening % [str(ctx.get("nation", "邻国")), str(ctx.get("town", "前线的城镇"))]
	var s := pair(e[0], who, e[1])
	s.append_array([
		{"fx": "prop", "kind": e[2], "at": [-1, -0.6]},
		line(who, opening),
		{"fx": "move", "who": "you", "to": "mr"},
		{"fx": "face", "who": "you", "target": who},
		line("you", e[4]),
		{"fx": "give", "to": "you"},
		{"fx": "wait", "t": 0.4},
		line(who, e[5]),
		line("you", e[6]),
		{"fx": "face", "who": who, "target": "you"},
		{"fx": "wait", "t": 0.7}])
	return s
