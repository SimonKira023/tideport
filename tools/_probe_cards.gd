extends Node
# 卡牌数据层探针: 卡池数值 / 牌库构成(队伍即牌库) / 行政支援卡 / 敌方四流派 / 图标
# 跑法: Godot_console.exe --headless --path . res://tools/_probe_cards.tscn
const CD := preload("res://scene/cards_data.gd")

var _pass := 0
var _fail := 0

func chk(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _ready() -> void:
	SaveManager.enabled = false          # 别碰玩家真档
	# —— 造三个假伙伴: 重骑兵(满阶+好感90) / 弓手 / 新兵 ——
	Slaves.slaves.clear()
	Slaves.slaves.append({"name": "阿大", "troop": "重骑兵", "labor": "帮工", "hp": 30, "max_hp": 30, "affection": 90})
	Slaves.slaves.append({"name": "阿二", "troop": "弓手", "labor": "帮工", "hp": 30, "max_hp": 30, "affection": 10})
	Slaves.slaves.append({"name": "阿三", "troop": "新兵", "labor": "帮工", "hp": 30, "max_hp": 30, "affection": 0})
	Slaves.expedition = [0, 1, 2]
	# ===== 伙伴卡数值 =====
	var c0 := CD.partner_card(0)
	chk(int(c0["cost"]) == 4 and int(c0["atk"]) == 6 and int(c0["hp"]) == 6,
		"重骑兵卡 费4攻6血6 (1+档3 / 2+职业3+好感1 / 3+档3)")
	chk(bool(c0["gold"]) and String(c0["kw"]) == "cav", "重骑兵卡 金卡 + 骑兵")
	var c1 := CD.partner_card(1)
	chk(String(c1["kw"]) == "ranged" and not bool(c1["gold"]), "弓手卡 后排可射 + 非金")
	var c2 := CD.partner_card(2)
	chk(int(c2["cost"]) == 1 and int(c2["atk"]) == 2 and int(c2["hp"]) == 3, "新兵卡 费1攻2血3")
	# ===== 牌库构成: 主角 1 + 基础牌 9; 新卡组系统同伴/法术要自己编进卡组 =====
	var deck := CD.player_deck(20260930)
	var expect_deck := 1 + CD.BASICS.size() * CD.BASIC_COPIES
	chk(deck.size() == expect_deck, "牌库 = 主角 1 + 基础牌 9 = %d 张 (卡组空, 同伴自己编)" % expect_deck)
	var hero_cnt := 0
	var basic_cnt := {}
	for k in CD.BASICS.keys():
		basic_cnt[String(k)] = 0
	for c in deck:
		if String(c["key"]) == "hero":
			hero_cnt += 1
		if basic_cnt.has(String(c["key"])):
			basic_cnt[String(c["key"])] += 1
	chk(hero_cnt == 1, "主角金卡就一张, 永远在卡组")
	for k in basic_cnt:
		chk(int(basic_cnt[k]) == CD.BASIC_COPIES, "基础牌 %s 固定带 %d 张" % [k, CD.BASIC_COPIES])
	# ===== 法术卡进牌库: 研究(科技/行政)给的 m_ 卡, 编进卡组才进牌库 =====
	Research.deck = ["m_admin_drill", "m_admin_hu", "m_fert"]
	var deck2 := CD.player_deck(7)
	var spell_names := {}
	for c in deck2:
		if String(c["type"]) == "spell":
			spell_names[String(c["key"])] = true
	chk(spell_names.has("m_admin_drill") and spell_names.has("m_admin_hu") and spell_names.has("m_fert"),
		"编进卡组的法术 (行政 严明操练/编户齐民 + 科技 沃土) 进牌库")
	chk(not spell_names.has("horns") and not spell_names.has("fire"), "敌方法术不会混进玩家卡组")
	Research.deck = []                   # 测完清掉, 别污染后面的断言
	# ===== 敌方四流派 =====
	for arch in ["rush", "swarm", "burn", "army"]:
		var party := {"type": "海寇", "size": 3}
		match arch:
			"rush":
				party = {"type": "巡逻", "size": 4, "nation": "canglang"}
			"swarm":
				party = {"type": "山贼", "size": 4}
			"burn":
				party = {"type": "海寇", "size": 4}
			"army":
				party = {"type": "巡逻", "size": 4, "nation": "chenxi"}
		var d := CD.foe_deck(party, 42)
		chk(d.size() == 20, "流派 %s 卡组 20 张" % arch)
		for c in d:
			chk(c.has("cost") and int(c["cost"]) >= 1, "流派 %s 卡牌有费用" % arch)
			break
	chk(CD.foe_archetype({"type": "巡逻", "size": 4, "nation": "canglang"}) == "rush", "苍狼部(骑兵国)巡逻 = 快攻")
	chk(CD.foe_archetype({"type": "山贼", "size": 4}) == "swarm", "山贼 = 人海")
	chk(CD.foe_archetype({"type": "海寇", "size": 4}) == "burn", "海寇 = 直伤")
	chk(CD.foe_archetype({"type": "巡逻", "size": 4, "nation": "chenxi"}) == "army", "晨曦王国 = 混编")
	# 攻城挂城名也认国: TOWNS 里随便挑一座
	if Nations.TOWNS.size() > 0:
		var tid: String = String(Nations.TOWNS.keys()[0])
		var a := CD.foe_archetype({"type": "攻城", "siege": tid})
		chk(a == "rush" or a == "army", "攻城按城属国分流 (%s)" % a)
	# ===== 大营血水涨船高 =====
	var hp_small := CD.foe_camp_hp({"type": "海寇", "size": 3})
	var hp_big := CD.foe_camp_hp({"type": "海寇", "size": 8})
	chk(hp_small == CD.CAMP_HP and hp_big > hp_small, "大营血 15 起步, 兵多加血 (%d -> %d)" % [hp_small, hp_big])
	# ===== 图标 / 卡面立绘 =====
	chk(CD.icon_of(c0) != null, "伙伴卡有职业图标")
	var sp := CD.spell_card_of("m_admin_drill")
	chk(CD.icon_of(sp) != null, "法术卡有行政图标")
	var fs := CD.foe_spell_card("fire")
	fs["name"] = "火油罐"
	chk(CD.icon_of(fs) != null, "敌方法术也有图标")
	chk(CD.art_of(c0, "my") != null, "伙伴卡有手牌立绘")
	chk(CD.art_of(CD.summon_card(), "my") != null, "民夫令牌有手牌立绘 (复用民兵美术)")
	chk(CD.art_of(fs, "foe") != null, "敌方法术有手牌立绘")
	var foe_unit := CD.unit_card("山贼", 1, 1, 3, "")
	chk(CD.art_icon_of(foe_unit, "foe") != null, "敌方单位有槽位小图")
	# ===== 洗牌确定性 =====
	var a1 := CD.shuffled([1, 2, 3, 4, 5, 6, 7, 8], 99)
	var a2 := CD.shuffled([1, 2, 3, 4, 5, 6, 7, 8], 99)
	chk(a1 == a2, "同种子洗牌结果一致")
	print("---- %d pass / %d fail ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
