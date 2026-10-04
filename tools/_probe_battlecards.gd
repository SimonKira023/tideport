extends Node
# 卡牌战场探针: 回合流转 / 出牌 / 前进 / 手操攻击 / 法术 / 结算
# 跑法: Godot_console.exe --headless --path . res://tools/_probe_battlecards.tscn
const CD := preload("res://scene/cards_data.gd")
const BC := preload("res://scene/battle_cards.gd")

var _pass := 0
var _fail := 0

func chk(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func mk(b: Node, cname: String, atk: int, hp: int, kw: String, side := "my") -> Dictionary:
	return b._new_unit(CD.unit_card(cname, 1, atk, hp, kw), side)

func new_battle(btype: String, size: int) -> Node:
	var b: Node = BC.new()
	b.set("party", {"type": btype, "size": size, "id": 7})
	add_child(b)
	return b

func _ready() -> void:
	# 兜底: 任何一条断言把脚本炸停都不会留个卡住的 Godot 进程
	var watchdog := get_tree().create_timer(90.0)
	watchdog.timeout.connect(func() -> void: get_tree().quit())
	await _run()
	print("---- 卡牌战场: %d pass / %d fail ----" % [_pass, _fail])
	print("全部通过 ✔" if _fail == 0 else "有失败项 ✘")
	get_tree().quit()

func _run() -> void:
	SaveManager.enabled = false
	Slaves.slaves.clear()
	Slaves.slaves.append({"name": "阿大", "troop": "重骑兵", "labor": "帮工", "hp": 30, "max_hp": 30, "affection": 90})
	Slaves.slaves.append({"name": "阿二", "troop": "弓手", "labor": "帮工", "hp": 30, "max_hp": 30, "affection": 10})
	Slaves.expedition = [0, 1]

	# ===== 开局: 我方先手抽 3 + 回合开始抽 1, 敌方后手抽 3 (d1 削弱) + 自己回合抽 1 =====
	var b := new_battle("海寇", 3)
	chk(b._my_hand.size() == 4, "我方开局手牌 4 (先手 3 + 回合抽 1)")
	chk(b._foe_hand.size() == 3, "敌方开局手牌 3 (后手 3, d1 削弱; 第 4 张在它自己回合抽)")
	# 新卡组系统: 同伴不自动进牌库, 底子 = 主角 1 + 基础牌 3x3; 同伴/法术要自己编进卡组
	var expect_deck := 1 + CD.BASICS.size() * CD.BASIC_COPIES
	chk(b._my_deck.size() + b._my_hand.size() == expect_deck
			and b._foe_deck.size() + b._foe_hand.size() == 20,
		"我方牌库+手牌 = %d+%d (期望 %d: 主角 + 基础牌, 同伴自己编) / 敌方 %d+%d (期望 20)"
			% [b._my_deck.size(), b._my_hand.size(), expect_deck,
				b._foe_deck.size(), b._foe_hand.size()])
	chk(b._my_camp == 15 and b._foe_camp == 15, "双方大营 15 (规模 3 不加成)")
	chk(b._cost == 2 and b._cost_max == 2, "第 1 回合 2 费 (首回合能打出 1-2 费牌)")
	chk(b._whose == "my" and b._turn_no == 1, "开局是我的第 1 回合")
	chk(b.party.get("type", "") == "海寇" and String(b._foe_display()).contains("海寇"), "敌方显示名")

	# ===== 出单位卡: 进支援线最左空位, 当回合标记已行动 =====
	b._my_hand = [CD.unit_card("测试兵", 1, 3, 4, "")]
	b._cost = 5
	b._on_hand(0)
	chk(b._my_support[0] != null and b._my_support[0]["card"]["name"] == "测试兵", "单位卡下场进支援线")
	chk(b._cost == 4, "出牌扣费 5 -> 4")
	chk(bool(b._my_support[0]["acted"]), "刚下场的部队当回合已行动")
	chk(b._my_hand.is_empty(), "手牌出掉了")

	# ===== 费用不足拦截 =====
	b._my_hand = [CD.unit_card("贵兵", 9, 9, 9, "")]
	b._cost = 1
	b._on_hand(0)
	chk(b._my_hand.size() == 1 and b._my_support[1] == null, "费用不足不出牌")

	# ===== 前进前线: 花 1 点行动费, 进最左空位 =====
	b._my_hand.clear()
	b._my_support[0]["acted"] = false
	b._cost = 2
	b._advance(0)
	chk(b._front[0] != null and b._my_support[0] == null, "支援线 -> 共享前线")
	chk(b._cost == 1, "前进扣 1 点行动费")
	chk(bool(b._front[0]["acted"]), "刚前进的部队当回合已行动")

	# ===== 前线满了不让推 =====
	b._my_support[1] = mk(b, "二队", 1, 1, "")
	for i in 4:
		if b._front[i] == null:
			b._front[i] = mk(b, "占位%d" % i, 0, 1, "")
	b._cost = 3
	b._advance(1)
	chk(b._my_support[1] != null and b._cost == 3, "前线满了推进失败且不扣费")

	# ===== 手操攻击: 敌军占着前线只能打他们 =====
	b._front = [mk(b, "我甲", 2, 5, ""), mk(b, "敌甲", 1, 3, "", "foe"), null, null]
	b._my_support = [null, null, null, null]
	var striker: Dictionary = b._front[0]
	b._cost = 9
	chk(b._do_attack("my", "front", 0, {"side": "foe", "row": "front", "idx": 1}),
		"手操进攻真打得出去")
	chk(int(b._front[1]["hp"]) == 1, "攻击落在敌方前线部队 (3 血吃 2 伤剩 1)")

	# ===== 打死移除 + 击杀计数 =====
	striker["acted"] = false
	b._front[1] = mk(b, "脆皮", 1, 1, "", "foe")
	b._killed = 0
	b._do_attack("my", "front", 0, {"side": "foe", "row": "front", "idx": 1})
	chk(b._front[1] == null and b._killed == 1, "打死后移除 + 击杀计数 1")

	# ===== 对方前线空了直击大营 =====
	striker["acted"] = false
	b._foe_camp = 15
	chk(b._do_attack("my", "front", 0, {"kind": "camp", "side": "foe"}),
		"敌前线空: 手操直击大营")
	chk(b._foe_camp == 13, "大营 15 -> 13 (2 攻)")
	chk(not b._do_attack("my", "front", 0, {"kind": "camp", "side": "foe"}),
		"已行动的部队打不出第二下 (骑兵才例外)")

	# ===== 支援线: 弓手参战, 近战不参战 =====
	b._front = [null, null, null, null]
	b._my_support = [mk(b, "我弓", 2, 3, "ranged"), mk(b, "我刀", 5, 3, ""), null, null]
	b._foe_camp = 15
	b._cost = 9
	chk(not b._do_attack("my", "support", 1, {"kind": "camp", "side": "foe"}),
		"支援线近战打不出去")
	chk(b._do_attack("my", "support", 0, {"kind": "camp", "side": "foe"})
		and b._foe_camp == 13, "支援线弓手参战直击大营 15 -> 13")

	# ===== 骑兵: 低油下场不打, 靠行动费出击 =====
	b._front = [mk(b, "敌乙", 1, 2, "", "foe"), null, null, null]
	b._my_support = [null, null, null, null]
	b._my_hand = [CD.unit_card("快马", 2, 3, 3, "cav")]
	b._cost = 9
	b._on_hand(0)
	chk(b._front[0] != null, "骑兵下场不立刻打 (冲锋已移除, 敌兵还在)")
	chk(b._my_support[0] != null and String(b._my_support[0]["card"]["kw"]) == "cav", "骑兵兵留在支援线")

	# ===== 法术: 驿马传令抽 2 / 互市加费 / 引水回血 =====
	b._my_hand = [CD.spell_card_of("m_admin_road")]
	b._cost = 9
	var h0: int = b._my_hand.size()
	b._on_hand(0)
	chk(b._my_hand.size() == h0 - 1 + 2, "驿马传令: 打出后净 +1 张 (抽 2)")
	b._my_hand = [CD.spell_card_of("m_admin_trade")]
	b._cost = 2
	b._on_hand(0)
	chk(b._cost == 3, "互市获利: 花 1 得 2 -> 净 +1 费")
	b._my_camp = 5
	b._my_hand = [CD.spell_card_of("m_ditch")]
	b._cost = 9
	b._on_hand(0)
	chk(b._my_camp == 10, "引水: 大营 +5")
	b._my_camp = 15
	b._my_hand = [CD.spell_card_of("m_ditch")]
	b._cost = 9
	b._on_hand(0)
	chk(b._my_camp == 15, "引水: 大营回满不再溢出")

	# ===== 指定目标法术: 沃土点自己人 +1攻 +1血 =====
	b._front = [mk(b, "靶子", 2, 3, ""), null, null, null]
	b._my_support = [null, null, null, null]
	b._my_hand = [CD.spell_card_of("m_fert")]
	b._cost = 9
	b._on_hand(0)
	chk(not b._pending.is_empty() and String(b._pending["target"]) == "ally", "沃土进入选目标模式")
	b._on_slot("my", "front", 0)
	chk(int(b._front[0]["atk"]) == 3 and int(b._front[0]["hp"]) == 4, "沃土生效 +1攻 +1血")
	chk(b._pending.is_empty() and b._my_hand.is_empty(), "选完目标退出选目标模式")

	# ===== 敌方法术: 火油罐直伤 / 飞斧点单位 / 增援铺场 =====
	var b2 := new_battle("巡逻", 3)
	b2._my_camp = 15
	b2._cast_spell(CD.foe_spell_card("fire"), "foe", "", -1, "")
	chk(b2._my_camp == 12, "火油罐: 我方大营 -3")
	b2._front = [mk(b2, "受斧", 1, 5, ""), null, null, null]
	var hit: Dictionary = b2._ai_pick_target()
	b2._cast_spell(CD.foe_spell_card("axe"), "foe", String(hit["side"]), int(hit["idx"]), String(hit["row"]))
	chk(int(b2._front[0]["hp"]) == 3, "飞斧: 指定单位 -2")
	b2._cast_spell(CD.foe_spell_card("reinforce"), "foe", "", -1, "")
	chk(b2._foe_support[0] != null and b2._foe_support[1] != null, "增援: 铺两个 1/1 民夫")

	# ===== 敌方大营随规模/等级加血 =====
	var b3 := new_battle("山贼", 9)
	chk(b3._foe_camp > 15, "大军规模敌方大营加成 %d" % b3._foe_camp)
	chk(b3._foe_camp == CD.foe_camp_hp({"type": "山贼", "size": 9}), "大营血与数据层一致")

	# ===== 攻城: 显示名取城名 + 声望按攻城算 =====
	var bs: Node = BC.new()
	bs.set("party", {"type": "攻城", "size": 4, "siege": "chenxi_cap"})
	add_child(bs)
	chk(String(bs._foe_display()).contains("晨曦城"), "攻城显示守军城名")
	chk(bs.is_siege, "攻城标记")

	# ===== 大营归零 -> 结算 + 奖励入账 =====
	var b4 := new_battle("海寇", 3)
	var coin0 := Wallet.money
	b4._foe_camp = 2
	b4._front = [mk(b4, "终结者", 5, 5, ""), null, null, null]
	b4._my_support = [null, null, null, null]
	b4._cost = 9
	var lv0: int = Legion.level          # gain_exp 可能升级, 算式按结算当时的等级算
	b4._do_attack("my", "front", 0, {"kind": "camp", "side": "foe"})
	var over: bool = b4._check_over()
	chk(over and b4._over, "敌方大营归零 -> 战斗结束")
	chk(b4._settle_result == "victory", "结算判为胜利")
	chk(b4._st_exp == 30 + lv0 * 6 + 12 * b4._killed, "经验算式 30+等级*6+12*击杀")
	chk(b4._st_coin > 0 and Wallet.money == coin0 + b4._st_coin, "金币入账 %d" % b4._st_coin)
	chk(b4._st_prest == Nations.PRESTIGE_BANDIT, "山贼/海寇声望档位")
	chk(b4._settle_hud != null, "弹出结算浮层")

	# ===== 我方大营归零 -> 败北 =====
	var b5 := new_battle("海寇", 3)
	b5._my_camp = 1
	b5._front = [mk(b5, "屠夫", 6, 6, "", "foe"), null, null, null]
	b5._foe_cost = 9
	b5._do_attack("foe", "front", 0, {"kind": "camp", "side": "my"})
	chk(b5._check_over() and b5._settle_result == "defeat", "我方大营归零 -> 败北")
	chk(b5._st_coin == 0, "败北不发奖励")

	# ===== 结束回合: 走完整流程（我方开打 -> 敌方 AI -> 回到我方） =====
	var b6 := new_battle("山贼", 3)
	b6._my_hand = [CD.unit_card("前排", 1, 2, 3, "")]
	b6._cost = 4
	b6._on_hand(0)
	b6._on_end_turn()
	await get_tree().create_timer(4.0).timeout
	chk(b6._whose == "my" and b6._turn_no == 2, "回合流转: 敌方走完回到我方第 2 回合")
	chk(b6._cost_max == 3 and b6._cost == 3, "第 2 回合 3 费")
	chk(b6._foe_cost_max == 2, "敌方第 1 回合也是 2 费 (同步首回合)")
	var foe_on_field := false
	for u: Variant in b6._foe_support:
		if u != null:
			foe_on_field = true
	for v: Variant in b6._front:
		if v != null and String((v as Dictionary)["side"]) == "foe":
			foe_on_field = true
	chk(foe_on_field, "敌方 AI 出了牌并推进过")

	# ===== 敌方流派打分（步4）: 同费下偏好不同 =====
	var ba := new_battle("巡逻", 3)              # 东北角有一支巡逻队 -> army
	var t_cav := CD.unit_card("铁骑", 1, 2, 1, "cav")
	var t_cheap := CD.unit_card("民夫", 1, 1, 2, "")
	var t_sword := CD.unit_card("刀客", 2, 2, 3, "")
	var t_bow := CD.unit_card("弓手", 2, 2, 2, "ranged")
	var t_thug := CD.unit_card("匪首", 3, 3, 3, "")
	var t_fire := CD.foe_spell_card("fire")
	var t_raid := CD.unit_card("海寇", 2, 2, 2, "")
	ba._arch = "rush"
	chk(ba._ai_score(t_cav) > ba._ai_score(t_cheap), "rush: 骑兵 > 民夫")
	ba._arch = "swarm"
	chk(ba._ai_score(t_cheap) > ba._ai_score(t_thug), "swarm: 廉价人海 > 贵的大块头")
	ba._arch = "burn"
	chk(ba._ai_score(t_fire) > ba._ai_score(t_raid), "burn: 直伤法术 > 单位")
	ba._arch = "army"
	chk(ba._ai_score(t_bow) >= ba._ai_score(t_sword), "army: 弓手不低于刀客")
	chk(ba._ai_score(t_fire) < 6.0, "同样的火油罐 army 不如 burn 看重")
	ba._arch = "burn"
	chk(ba._ai_score(t_fire) >= 6.0, "burn 给火油罐最高权重")

	# ===== 出牌前置条件 =====
	chk(ba._ai_score(CD.foe_spell_card("axe")) < -100.0, "飞斧: 我方场上没人时不出")
	ba._front = [mk(ba, "靶", 1, 1, ""), null, null, null]
	chk(ba._ai_score(CD.foe_spell_card("axe")) > 0.0, "飞斧: 有人可打就出")
	for i in 4:
		ba._foe_support[i] = mk(ba, "占位%d" % i, 1, 1, "")
	chk(ba._ai_score(CD.unit_card("民夫", 1, 1, 2, "")) > 0.0,
		"支援线满但前线有空位: 还能下单位 (直接进前线)")
	for i in ba._front.size():
		if ba._front[i] == null:
			ba._front[i] = mk(ba, "前占%d" % i, 1, 1, "")
	chk(ba._ai_score(CD.unit_card("民夫", 1, 1, 2, "")) < -100.0,
		"支援线+前线都满: 不再评分出单位")

	# ===== 推进闸门: 人海/海寇先把牌打完 =====
	var bp := new_battle("山贼", 3)
	bp._foe_support[0] = mk(bp, "前排", 1, 1, "")
	bp._foe_cost = 5
	bp._foe_hand = [CD.unit_card("民夫", 1, 1, 2, "")]
	chk(not bp._ai_should_promote(), "swarm: 手里还有便宜单位时先铺人不推进")
	bp._foe_hand = []
	chk(bp._ai_should_promote(), "swarm: 手牌打完就该推进了")
	bp._arch = "burn"
	bp._foe_hand = [CD.foe_spell_card("fire")]
	chk(not bp._ai_should_promote(), "burn: 手里有直伤先打牌不推进")
	bp._foe_hand = []
	bp._foe_cost = 0
	chk(not bp._ai_should_promote(), "没钱不推进")

	# ===== 手牌上限 8 =====
	var b7 := new_battle("海寇", 3)
	b7._my_hand.clear()
	b7._my_deck = []
	for i in 20:
		b7._my_deck.append(CD.basic_card("spike"))
	for i in 20:
		b7._draw_card("my")
	chk(b7._my_hand.size() == CD.HAND_CAP, "手牌封顶 %d 张" % CD.HAND_CAP)