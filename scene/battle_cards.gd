# scene/battle_cards.gd —— KARDS 式卡牌战斗（共享前线 · 手操行动版）
#
# 规则（对齐 KARDS, 前进 / 进攻手操, 前线双方共抢）：
#   · 战场三排: 单条共享前线（双方部队都能站, 互相抢占） + 己方支援线
#   · 每回合每支部队只做一个动作: 部署 / 前进 / 进攻
#   · 前进 / 进攻都要花该部队卡面上的「行动费」; 进攻由玩家手操: 点部队 → 点目标
#   · 敌军占着前线时只能打他们, 敌前线没有他们的部队才能直击大营（大营血 15）
#   · 骑兵系 = 低油（普通骑兵行动 1 点, 高级骑兵行动免费）; 弓手系 = 支援线也能进攻
#     步兵系 = 守护（左右相邻的友军不受攻击 / 直伤法术伤害）
#   · 反击: 进攻方打到没死的部队会被反击掉血（弓手在远处放箭免反击）; 每回合 +1 费（封顶 10）, 回合开始抽 1 张, 手牌上限 8
#   · 我方先手抽 3, 敌方后手抽 4
#
# 主角在这套系统里只是统帅: 不出场、没有技能, 只比大营血量。
# 卡池与数值全在 scene/cards_data.gd; 这里只管画、点、回合流转与结算。
extends Node2D

const CardsData := preload("res://scene/cards_data.gd")
const CardFace := preload("res://scene/card_face.gd")
const IrisWipe := preload("res://scene/iris_wipe.gd")
const FxPalette := preload("res://scene/fx_palette.gd")   # P5: 飘字色板 + 打击三连
const FONT_PIX := preload("res://resources/font/IPix.ttf")
const WPANEL := preload("res://wood_panel.gd")   # e92: 战斗桌面直接复用全局手绘木板

# ---------------- 设计尺寸（画布固定 1152x648, 里面全用这套坐标） ----------------
const VW := 1152.0
const VH := 648.0
const SLOT_W := 96.0
const SLOT_H := 90.0
const SLOT_GAP := 10.0

const Y_FOE_BAR := 12.0
const H_BAR := 46.0
const Y_FOE_SUP := 62.0
const Y_FRONT := 164.0             # 共享前线（一条, 双方部队混排）
const Y_MID := 404.0               # 大营挨打浮字锚点（支援线与手牌之间）
const Y_MY_SUP := 254.0            # 支援线紧贴前线（前线 164 + 槽高 90, 无间隔）
const Y_HAND := 456.0
const HAND_W := 92.0
const HAND_H := 150.0

# e93 卡面立绘: 源图 _card.png 172x288 (显示 88x146 满幅铺卡, 2x 采样) / _icon.png 80x88 (槽位)
# 由 AI 生成后 PIL 归一（见 2026-10-07 工作日志）; 旧 make_card_art.gd 管线已停用, 别再跑它覆盖
const ART_W := 88.0
const ART_H := 146.0
const ICON_W := 40.0
const ICON_H := 44.0

const C_MY := Color("4c777b")
const C_FOE := Color("b36b58")
const C_OK := Color("78945d")
const C_SEL := Color("efd18e")
const C_DIM := Color(0.38, 0.40, 0.46)
const C_GOLD := Color("9c712f")
const C_TXT := Color("503827")

# 遭遇的敌人队伍（Voyage.enter_battle / enter_siege 在 add_child 之前 set 进来）
var party: Dictionary = {}
var is_siege := false
var _arch := "army"               # 敌方流派: rush / swarm / burn / army（数据层判定）

# ---------------- 战场状态 ----------------
var _my_support: Array = [null, null, null, null]
var _foe_support: Array = [null, null, null, null]
var _front: Array = [null, null, null, null, null, null, null]   # 共享前线: 双方部队混排, 按单位 side 分敌我（词条可缩到 3 槽, 数组恒 7 位不 resize）

var _my_deck: Array = []
var _foe_deck: Array = []
var _my_hand: Array = []
var _foe_hand: Array = []
var _my_camp := 0
var _my_camp_max := 0
var _foe_camp := 0
var _foe_camp_max := 0
var _cost := 0
var _cost_max := 0
var _foe_cost := 0
var _foe_cost_max := 0

var _turn_no := 0
var _whose := "my"
var _over := false
var _closing := false
var _ai_busy := false
var _killed := 0                  # 这场打掉的敌军部队数（算战果）
var _uid := 0

# 战场词条（特殊场景, 见 CardsData.SCENARIOS）: 攻城 / 接舷 / 夜袭 / 野战
var _sc_id := "field"
var _sc: Dictionary = {}
var _front_slots := 7             # 前线槽数（接舷战只有 3, 其余词条 7）
var _turn_limit := 0              # 回合上限（攻城 12 回合攻不下算粮尽）
var _no_atk1 := false             # 第 1 回合双方都不能攻击（夜袭）

# 法术选目标模式: {"hand_idx": int, "card": Dictionary, "target": "ally"/"foe"}
var _pending: Dictionary = {}
# 手操攻击 (KARDS 式): 点我方部队 = 选中, 点敌军任意行 = 出手, 记下攻击发起者 {"row","idx"}
var _atk_sel: Dictionary = {}

# e92: 手牌拖拽态 {idx, p, off, home, rot, moved}; 空 = 没在拖
var _drag: Dictionary = {}
var _drag_tw: Tween = null

# 战果（结算页展示）
var _st_exp := 0
var _st_coin := 0
var _st_prest := 0
var _settle_result := ""
var _settle_armed := false
var _settle_hud: CanvasLayer = null

# ---------------- 界面节点 ----------------
var _layer: CanvasLayer = null
var _stage: Control = null
var _field_layer: Control = null
var _hand_layer: Control = null
var _lbl_foe: Label = null
var _lbl_foe_bar: ColorRect = null
var _lbl_camp: Label = null
var _bar_camp: ColorRect = null
var _lbl_cost: Label = null
var _lbl_deck: Label = null
var _lbl_hint: Label = null
var _lbl_tactics: Label = null
var _retreat_dialog: ConfirmationDialog = null
var _btn_end: Button = null
var _hint_tw: Tween = null
var _bar_foe: Panel = null        # 顶部敌情条（攻击模式下可点 = 直击大营）
var _lbl_sc: Label = null         # 词条标签（右上角: 「坚城」这类）
var _foe_hand_pips: Array[Panel] = []   # d2: 敌情条 KARDS 式手牌牌背 (8 格, 可见数 = 敌手牌数)
var _lbl_foe_hand: Label = null   # d2: 敌手牌数数字
var _fx: Control = null           # 演出层（浮字/闪光/冲刺/横幅）, 永远盖在最上面
var _card_preview: Control = null
var _view := Vector2.ZERO         # 视口尺寸（震屏算基准位置用）
var _shake_tw: Tween = null
var _post_mat: ShaderMaterial = null   # E1/E2 战场后处理（泛光 + 情绪滤镜）
var _mood := 0.0                       # 当前情绪值（-1 大优 .. +1 危急）
var _mood_tw: Tween = null

# 出牌历史: {turn, side, name, cost}（左侧抽屉可翻看, 敌我双记）
var _play_log: Array = []
var _hist_drawer: Panel = null         # 左侧出牌历史抽屉（收起只露「史」标签）
var _hist_list: VBoxContainer = null
var _hist_open := false
var _foe_fx_n := 0                     # 敌军出牌小卡计数（错开停留高度用）

# e96 KARDS 式大营: 双方 HP 圆章（大数字一眼可读）+ 受损烟火点（越残越旺）
var _coin_my_camp: Control = null
var _coin_foe_camp: Control = null
var _my_dmg_dots: Array = []           # {sprite, th} th=显形血量阈值(占比)
var _foe_dmg_dots: Array = []
# e97: 拖拽攻击 —— 按住我方部队拖到目标松手即出手（KARDS 手感）; 瞄准线画在 fx 层
var _aim := {}                         # {row, idx, from, moved, targets, line, out, self_cancel}

# ---------------- 入口 ----------------
func _ready() -> void:
	add_to_group("battle")
	Voyage.set_battle_slow(false)      # 卡牌战不慢放（上一场留下的慢速清干净）
	is_siege = String(party.get("siege", "")) != ""
	_arch = CardsData.foe_archetype(party)
	# 战场词条: 攻城 / 接舷 / 夜袭 / 野战（规则真的改, 不是换皮）
	_sc_id = CardsData.scenario_of(party)
	_sc = CardsData.scenario(_sc_id)
	_front_slots = clampi(int(_sc.get("front", 7)), 1, 7)
	_turn_limit = int(_sc.get("lim", 0))
	_no_atk1 = bool(_sc.get("no_atk1", false))
	# 同一支敌军/同一座城每次洗出一样的牌（selftest 可复现, 也能让玩家记住对手路数）
	var base := absi((str(party.get("id", "")) + str(party.get("siege", "")) + str(party.get("type", ""))).hash())
	_my_deck = CardsData.player_deck(base)
	_foe_deck = CardsData.foe_deck(party, base + 1)
	_my_camp_max = CardsData.CAMP_HP
	_my_camp = _my_camp_max
	_foe_camp_max = CardsData.foe_camp_hp(party)
	_foe_camp = _foe_camp_max
	for i in 3:
		_draw_card("my")               # 我方先手: 3 张
	for i in 3:
		_draw_card("foe")              # 敌方后手: 3 张 (d1 削弱, 原 4 张)
	_build_ui()
	Audio.play_sfx("stinger", -8.0)   # P6: 登场号 —— 两记和弦叠在军鼓 BGM 上
	_start_my_turn()
	_flash("点手牌下部队 / 点场上部队选行动(前进 / 进攻) / 结束回合换敌方")
	if _sc_id != "field":
		_show_banner(String(_sc["name"]), String(_sc["desc"]))
	# d10: 入场黑幕由 Voyage.enter_battle/enter_siege 的 iris "out" 全程负责
	# （收黑 -> 黑幕中切场景 -> 展开），这里不再叠一层 "in"，免得旧画面闪一帧。

func _exit_tree() -> void:
	Voyage.set_battle_slow(false)

func _unhandled_input(ev: InputEvent) -> void:
	var me := ev as InputEventMouseButton
	if me != null and me.pressed and me.button_index == MOUSE_BUTTON_RIGHT:
		_clear_sel()
		return
	var key := ev as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			_clear_sel()
		elif key.keycode == KEY_SPACE and _btn_end != null and not _btn_end.disabled:
			_on_end_turn()                 # e96: 空格结束回合（KARDS 习惯）

# ---------------- 回合流转 ----------------
func _start_my_turn() -> void:
	if _over:
		return
	# 攻城限时: 回合耗尽 = 粮尽撤兵（守方守住了）
	if _turn_limit > 0 and _turn_no + 1 > _turn_limit:
		_flash("粮尽, 攻城只能到此为止")
		_show_banner("粮尽", "回合耗尽, 攻城被迫中止")
		_settle("defeat")
		return
	_turn_no += 1
	_whose = "my"
	# 首回合 2 费: 原来 1 费开局手里全是 2 费牌, 点出去全是「费用不足」, 玩家像被锁了手
	_cost_max = mini(CardsData.COST_CAP, (_cost_max + 1) if _turn_no > 1 else 2)
	_cost = _cost_max
	_clear_acted("my")
	_draw_card("my")
	_refresh_all()
	if _turn_no > 1:
		Audio.play_sfx("ui_open", -12.0)
		_show_banner("你的回合", "第 %d 回合 / %d 费" % [_turn_no, _cost])

func _on_end_turn() -> void:
	if _over or _ai_busy or _whose != "my":
		return
	_clear_sel()
	_ai_turn()

# 敌方回合: 出牌 -> 前进 -> 手操攻击（按流派挑目标, 不再无脑全打）
func _ai_turn() -> void:
	_ai_busy = true
	_whose = "foe"
	_clear_sel()
	_show_banner("敌方回合", "%s 动了" % CardsData.arch_name_of(_arch))
	Audio.play_sfx("ui_open", -12.0)
	# d1 削弱: 敌方每两回合才涨 1 费 (我方照旧每回合 +1), 后期费用被压住, 大兵上得更慢
	if _turn_no == 1:
		_foe_cost_max = 2              # 首回合同步 2 费
	elif _turn_no % 2 == 0:
		_foe_cost_max = mini(CardsData.COST_CAP, _foe_cost_max + 1)
	_foe_cost = _foe_cost_max
	_clear_acted("foe")
	_draw_card("foe")
	_refresh_all()
	await _pause(0.5)
	if _closing:
		return
	var guard := 0
	while guard < 20 and not _over:
		guard += 1
		if not _ai_step():
			break
		_refresh_all()
		await _pause(0.42)
		if _closing:
			return
	guard = 0
	while guard < 20 and not _over:
		guard += 1
		if not _ai_should_promote() or not _ai_promote():
			break
		_refresh_all()
		await _pause(0.32)
		if _closing:
			return
	if _over:
		_ai_busy = false
		return
	await _pause(0.35)
	if _closing:
		return
	await _ai_attacks()
	_refresh_all()
	if _check_over():
		_ai_busy = false
		return
	await _pause(0.45)
	if _closing:
		return
	_ai_busy = false
	if not _over:
		_start_my_turn()

func _pause(t: float) -> void:
	await get_tree().create_timer(t).timeout

# 敌方 AI（步4）: 按流派给每张牌打分, 每步挑当下最值的那张打出去。
#   rush  骑兵国快攻 —— 攻高的骑兵优先 (低油), 费尽量花光
#   swarm 山贼/哥布林人海 —— 廉价单位铺满支援线, 增援最香
#   burn  海寇/魔物直伤 —— 直伤法术优先砸大营, 飞斧点对方最凶的
#   army  国家正规军 —— 攻血均衡, 弓手加分
func _ai_step() -> bool:
	var best := -1
	var best_score := -999.0
	for i in _foe_hand.size():
		var card: Dictionary = _foe_hand[i]
		if int(card["cost"]) > _foe_cost:
			continue
		var s := _ai_score(card)
		if s > best_score:
			best_score = s
			best = i
	if best < 0:
		return false
	var pick: Dictionary = _foe_hand[best]
	var cost := int(pick["cost"])
	if String(pick["type"]) == "unit":
		# e96 部署落位（KARDS 思路）: rush 前线有空位直接顶上去省推进费;
		# 守护兵挑挨着自己人的空支援位（守护不护自己, 邻居没了掩护就空转）
		var kw := String(pick.get("kw", ""))
		var slot := -1
		var to_front := false
		if kw != "guard" and _arch == "rush" and _first_empty(_front, _front_slots) >= 0:
			slot = _first_empty(_front, _front_slots)
			to_front = true
		if slot < 0:
			slot = _first_empty(_row("foe", "support"))
		if slot < 0:
			slot = _first_empty(_front, _front_slots)
			to_front = true
		if slot < 0:
			return false
		if kw == "guard" and not to_front:
			slot = _ai_guard_slot(slot)
		_foe_hand.remove_at(best)
		_foe_cost -= cost
		var u := _new_unit(pick, "foe")
		if to_front:
			_front[slot] = u
		else:
			_row("foe", "support")[slot] = u
		# 骑兵上场当回合就能动; 其余部队部署已算一个动作
		if String(pick.get("kw", "")) != "cav":
			u["acted"] = true
		_log_play("foe", pick)
		Audio.play_sfx("deploy", -4.0)
		_fx_foe_card(pick)
		_flash("敌军 %s 下场" % String(pick["name"]))
		return true
	var side := ""
	var row := ""
	var idx := -1
	if String(pick.get("spell", "")) == "unit_dmg":
		var hit := _ai_pick_target()
		if hit.is_empty():
			return false
		side = String(hit["side"])
		row = String(hit["row"])
		idx = int(hit["idx"])
	_foe_hand.remove_at(best)
	_foe_cost -= cost
	_cast_spell(pick, "foe", side, idx, row)
	_fx_foe_card(pick)
	_flash("敌军 %s" % String(pick["name"]))
	return true

func _ai_score(card: Dictionary) -> float:
	var cost := int(card["cost"])
	var s := 0.0
	if String(card["type"]) == "unit":
		if _first_empty(_row("foe", "support")) < 0 and _first_empty(_front, _front_slots) < 0:
			return -999.0
		var kw := String(card.get("kw", ""))
		s = float(int(card["atk"]) * 2 + int(card["hp"]))
		if kw == "cav":
			s += 1.5
		elif kw == "ranged":
			s += 1.5
		elif kw == "guard":
			s += 1.0
		match _arch:
			"rush":
				s += 1.5 * float(int(card["atk"]))
				if kw == "cav":
					s += 2.0
			"swarm":
				# 人海: 不看单张多猛, 看「每费能换多少身板」—— 多铺人比养一个大块头强
				s = float(int(card["atk"]) * 2 + int(card["hp"])) / maxf(1.0, float(cost)) * 1.8
				s += 0.6 * float(int(card["hp"]))
			"burn":
				s -= 1.5                       # 海寇: 牌面让位给直伤
			"army":
				if kw == "ranged":
					s += 2.0
				s += 0.8 * float(int(card["hp"]))
	else:
		match String(card.get("spell", "")):
			"camp_dmg":
				s = 6.0 if _arch == "burn" else 3.0
				# e96 终结: 这一发能打穿玩家大营就无条件最优先（KARDS 式斩杀意识）
				if int(card.get("dmg", 0)) >= _my_camp:
					s = 999.0
			"unit_dmg":
				s = 5.0 if not _all_units("my").is_empty() else -999.0
			"summon2":
				var room := 0
				for slot: Variant in _row("foe", "support"):
					if slot == null:
						room += 1
				s = 5.0 if room >= 2 else (1.0 if room == 1 else -999.0)
			"atk_all":
				s = 2.0 + 0.8 * float(_all_units("foe").size())
	s += 0.2 * float(cost)                     # 同分优先把费花掉, 别攒着
	return s

# 还有费就推进前线; 人海先铺满人、海寇先把手里的直伤打出去
func _ai_should_promote() -> bool:
	if _foe_cost < 1:
		return false
	if _first_empty(_front, _front_slots) < 0:
		return false
	for u: Variant in _foe_support:
		if u == null or int((u["card"] as Dictionary).get("act", 1)) > _foe_cost:
			continue
		for card: Dictionary in _foe_hand:
			var cost := int(card["cost"])
			if cost > _foe_cost:
				continue
			if _arch == "swarm" and String(card.get("type", "")) == "unit":
				return false
			if _arch == "burn" and String(card.get("type", "")) == "spell":
				return false
		return true
	return false

# 花行动费把支援线最前面的部队推上前线
func _ai_promote() -> bool:
	var slot := _first_empty(_front, _front_slots)
	if slot < 0:
		return false
	var from := -1
	var act := 0
	for i in _foe_support.size():
		var v: Variant = _foe_support[i]
		if v == null:
			continue
		var a := int((v["card"] as Dictionary).get("act", 1))
		if a <= _foe_cost:
			from = i
			act = a
			break
	if from < 0:
		return false
	_foe_cost -= act
	var u: Dictionary = _foe_support[from]
	_foe_support[from] = null
	u["acted"] = true
	_front[slot] = u
	Audio.play_sfx("move", -4.0)
	_flash("敌军 %s 前进前线" % String((u["card"] as Dictionary)["name"]))
	return true

# 飞斧打谁: 挑我方攻最高的那个（没有就算空）。前线是共享的, 得按单位 side 过滤。
# 被守护的优先跳过（邻居会挡, 砸了白砸）; 全都被守护才退而求其次砸守护者自己
func _ai_pick_target() -> Dictionary:
	var best := {}
	var best_atk := -1
	var guarded := {}
	var guarded_atk := -1
	for row in ["front", "support"]:
		var arr := _row("my", row)
		for i in arr.size():
			var v: Variant = arr[i]
			if v == null or String((v as Dictionary)["side"]) != "my":
				continue
			var a := int((v as Dictionary)["atk"])
			if _is_guarded("my", row, i):
				if a > guarded_atk:
					guarded_atk = a
					guarded = {"side": "my", "row": row, "idx": i}
				continue
			if a > best_atk:
				best_atk = a
				best = {"side": "my", "row": row, "idx": i}
	return best if not best.is_empty() else guarded

# 守护: (side,row,idx) 的左右邻居有同阵营守护兵（kw=guard）时, 这一格受到的
# 攻击 / 直伤法术被挡下。守护只护邻居不护自己; 前线共享, 邻居按单位 side 分敌我
func _is_guarded(side: String, row: String, idx: int) -> bool:
	var arr := _row(side, row)
	# 守护者始终可以被攻击, 防止两名守护者互保形成无敌死局。
	if idx >= 0 and idx < arr.size() and arr[idx] != null:
		if String((arr[idx]["card"] as Dictionary).get("kw", "")) == "guard":
			return false
	for off: int in [-1, 1]:
		var j := idx + off
		if j < 0 or j >= arr.size():
			continue
		var v: Variant = arr[j]
		if v == null:
			continue
		if String((v as Dictionary)["side"]) == side \
			and String(((v as Dictionary)["card"] as Dictionary).get("kw", "")) == "guard":
			return true
	return false

# ---------------- 行动 / 攻击 ----------------
# 每回合每支部队只做一个动作: 部署 / 前进 / 进攻
func _can_act(u: Dictionary) -> bool:
	if bool(u.get("acted", false)):
		return false
	return true

# 一支部队现在能打谁: 敌军前线 + 敌军支援线（底层）的部队都能打 (c6),
# 敌前线没有他们的部队才能直击大营
# 返回 [{"side","row","idx"}...] 或 [{"kind":"camp","side"}]
func _attack_targets(u: Dictionary) -> Array:
	var side := String(u["side"])
	var enemy := "foe" if side == "my" else "my"
	var out: Array = []
	var front_clear := true
	for i in _front.size():
		var v: Variant = _front[i]
		if v != null and String((v as Dictionary)["side"]) == enemy:
			front_clear = false
			if not _is_guarded(enemy, "front", i):
				out.append({"side": enemy, "row": "front", "idx": i})
	for i in _row(enemy, "support").size():
		var s: Variant = _row(enemy, "support")[i]
		if s != null and not _is_guarded(enemy, "support", i):
			out.append({"side": enemy, "row": "support", "idx": i})
	if front_clear:
		out.append({"kind": "camp", "side": enemy})
	return out

# 手操攻击的完整校验链: 全过了才真打（扣行动费 + 标记已行动 + 结算）
func _do_attack(side: String, row: String, idx: int, target: Dictionary) -> bool:
	if _over:
		return false
	var arr := _row(side, row)
	if idx < 0 or idx >= arr.size() or arr[idx] == null:
		return false
	var u: Dictionary = arr[idx]
	if String(u["side"]) != side:
		return false
	if not _can_act(u):
		if side == "my":
			_flash("这支部队已经行动过了")
		return false
	if row == "support" and String((u["card"] as Dictionary).get("kw", "")) != "ranged":
		if side == "my":
			_flash("支援线只有射手能发起攻击")
		return false
	if _no_atk1 and _turn_no <= 1:
		if side == "my":
			_flash("夜色太浓, 第 1 回合谁也打不着")
		return false
	var act := int((u["card"] as Dictionary).get("act", 1))
	if ( _cost if side == "my" else _foe_cost ) < act:
		if side == "my":
			_flash("进攻要 %d 点行动费" % act)
		return false
	var ok := false
	for t: Dictionary in _attack_targets(u):
		if bool(t.get("kind", "") == "camp") != bool(target.get("kind", "") == "camp"):
			continue
		if t.get("kind", "") == "camp":
			ok = String(t["side"]) == String(target.get("side", ""))
		else:
			ok = String(t["side"]) == String(target.get("side", "")) \
				and String(t["row"]) == String(target.get("row", "")) \
				and int(t["idx"]) == int(target.get("idx", -1))
		if ok:
			break
	if not ok:
		if side == "my":
			_flash("目标受守护或已失效, 请选择高亮目标. 本次不消耗费用.")
		return false
	if side == "my":
		_cost -= act
	else:
		_foe_cost -= act
	u["acted"] = true
	Audio.play_sfx("attack", -2.0)
	_strike(u, target)
	return true

# 一支部队打一记: target 来自 _attack_targets（{"side","row","idx"} 打单位 / {"kind":"camp"} 砸大营）。
# 打击逻辑是同步的（自检/探针直接调它）, 演出全走 _fx 层的非阻塞 tween, 不卡流程。近战打没死会被反击。
func _strike(u: Dictionary, target: Dictionary) -> void:
	if _over:
		return
	var side := String(u["side"])
	var atk := int(u["atk"])
	var from := _find_slot(u)
	if String(target.get("kind", "")) != "camp":
		var trow := String(target["row"])
		var arr := _row(String(target["side"]), trow)
		var ti := int(target["idx"])
		if ti < 0 or ti >= arr.size() or arr[ti] == null:
			return
		var d: Dictionary = arr[ti]
		var tp := _slot_pos(String(target["side"]), trow, ti) + Vector2(SLOT_W * 0.5, SLOT_H * 0.5)
		# 守护: 目标的左右邻居有同阵营守护兵, 这记攻击被挡下（守护不护守护者自己）
		if _is_guarded(String(target["side"]), trow, ti):
			_dash(from, tp, side)
			_float_text("守护", tp, FxPalette.GUARD, 16)
			_slot_flash(tp)
			Audio.play_sfx("chop", -12.0, 0.8)
			_flash("%s 被邻居掩护, 攻击落空" % String((d["card"] as Dictionary)["name"]))
			return
		d["hp"] = int(d["hp"]) - atk
		_dash(from, tp, side)
		if int(d["hp"]) <= 0:
			arr[ti] = null
			if String(target["side"]) == "foe":
				_killed += 1
			_float_text("击倒", tp, FxPalette.GAIN, 17)
			_slot_flash(tp)
			_shatter(tp, Color(0.85, 0.72, 0.5))     # e92: 木牌碎裂
			_shake(1.8)                              # e92: 击杀轻震
			# P5 打击三连: 僵直一瞬 + 辐射速度线 + 短白闪（击杀的"砰"）
			FxPalette.hit_stop()
			FxPalette.speed_lines(_fx, tp)
			FxPalette.flash(get_tree(), Color(1.0, 0.97, 0.88), 0.20, 0.12)
			Audio.play_sfx("fell", -6.0, 1.06)
			_flash("%s 被击倒" % String((d["card"] as Dictionary)["name"]))
			return
		_recoil(tp, tp - from)                       # e96: 受击后仰
		_float_text("-%d" % atk, tp, FxPalette.HURT, 15)
		_slot_flash(tp)
		Audio.play_sfx("chop", -9.0, 1.2)
		_flash("%s 受伤 %d" % [String((d["card"] as Dictionary)["name"]), atk])
		# 反击: 目标没死就还一手 —— 射手在远处放箭免吃反击; 守护格挡/砸大营不还手
		if String((u["card"] as Dictionary).get("kw", "")) == "ranged":
			return
		var ratk := int(d["atk"])
		u["hp"] = int(u["hp"]) - ratk
		var fp := _find_slot(u)
		_recoil(fp, fp - tp)                         # e96: 反击方也被顶一下
		_float_text("反击 -%d" % ratk, fp, FxPalette.HURT, 15)
		_slot_flash(fp)
		Audio.play_sfx("chop", -9.0, 0.9)
		_flash("%s 反击 %s -%d" % [String((d["card"] as Dictionary)["name"]), String((u["card"] as Dictionary)["name"]), ratk])
		if int(u["hp"]) <= 0:
			_slain_at(int(u["uid"]), side)
			if side == "foe":
				_killed += 1
			_float_text("击倒", fp, FxPalette.GAIN, 17)
			_shatter(fp, Color(0.85, 0.72, 0.5))     # e92: 反杀也碎
			FxPalette.hit_stop()                     # P5: 反杀同样给一记僵直
			FxPalette.speed_lines(_fx, fp)
			Audio.play_sfx("fell", -6.0, 1.06)
			_flash("%s 被反杀" % String((u["card"] as Dictionary)["name"]))
		return
	if String(target["side"]) == "foe":
		_foe_camp = maxi(0, _foe_camp - atk)
		_flash("敌方大营 -%d" % atk)
	else:
		_my_camp = maxi(0, _my_camp - atk)
		_flash("我方大营 -%d" % atk)
	_camp_hit_fx(String(target["side"]), atk)

# 伤亡出口: 按 uid 找到该单位的槽位并清出（反击反杀走这里, _killed 由调用方记）
func _slain_at(uid: int, side: String) -> void:
	for row: String in ["front", "support"]:
		var arr := _row(side, row)
		for i in arr.size():
			var v: Variant = arr[i]
			if v != null and int((v as Dictionary).get("uid", -1)) == uid:
				arr[i] = null
				return

# e96 KARDS 式局势评估: 场上双方部队力量 + 大营血量比折算。
# >0 敌方占优（该去打脸压死）, <0 落后（该换血清场）。
func _ai_board_edge() -> float:
	var foe_p := 0.0
	var my_p := 0.0
	for row in ["front", "support"]:
		for u: Variant in _row("foe", row):
			if u != null:
				foe_p += float((u as Dictionary)["atk"]) + float((u as Dictionary)["hp"])
		for u: Variant in _row("my", row):
			if u != null:
				my_p += float((u as Dictionary)["atk"]) + float((u as Dictionary)["hp"])
	foe_p += 10.0 * float(_foe_camp) / float(maxi(1, _foe_camp_max))
	my_p += 10.0 * float(_my_camp) / float(maxi(1, _my_camp_max))
	return foe_p - my_p

# 守护兵落位: 优先站到有己方邻居的空支援位（守护不护自己, 邻居没了掩护就空转）
func _ai_guard_slot(fallback: int) -> int:
	var arr := _row("foe", "support")
	for i in arr.size():
		if arr[i] != null:
			continue
		if (i > 0 and arr[i - 1] != null) or (i < arr.size() - 1 and arr[i + 1] != null):
			return i
	return fallback

# 敌方 AI 手操攻击: 能击杀 > 砸大营 > 打高威胁, 一支一支来（带停顿, 看得清）。
# 候选打不出去就换下一个发起者, 绝不整回合罢工（旧版一失败就 break, 敌军整场不动）。
func _ai_attacks() -> void:
	if _no_atk1 and _turn_no <= 1:
		return                          # 夜袭: 第 1 回合谁都打不着, 别白耗停顿
	var guard := 0
	while guard < 12 and not _over and not _closing:
		guard += 1
		var tried := {}                 # 打不出去的发起者这轮跳过（行:槽 记名）
		var acted := false
		while true:
			var best_score := -999.0
			var best := {}
			var best_t: Dictionary = {}
			for row in ["front", "support"]:
				var arr := _row("foe", row)
				for i in arr.size():
					var v: Variant = arr[i]
					if v == null or String((v as Dictionary)["side"]) != "foe":
						continue
					if tried.has("%s:%d" % [row, i]):
						continue
					var u: Dictionary = v
					if not _can_act(u):
						continue
					if row == "support" and String((u["card"] as Dictionary).get("kw", "")) != "ranged":
						continue        # 支援线只有射手够得着（与 _do_attack 校验一致）
					if int((u["card"] as Dictionary).get("act", 1)) > _foe_cost:
						continue
					for t: Dictionary in _attack_targets(u):
						var s := _ai_attack_score(u, t)
						if s > best_score:
							best_score = s
							best = {"row": row, "idx": i}
							best_t = t
			if best.is_empty():
				break
			var brow := String(best["row"])
			if _do_attack("foe", brow, int(best["idx"]), best_t):
				acted = true
				_refresh_all()
				await _pause(0.42)
				break
			tried["%s:%d" % [brow, int(best["idx"])]] = true
		if not acted:
			break

# AI 给一次攻击打分（e96 KARDS 化）:
#   终结技 > 击杀 > 局势导向（领先打脸压死 / 落后换血清场）, 亏本买卖（反击能打死发起者）会掂量
func _ai_attack_score(u: Dictionary, t: Dictionary) -> float:
	var atk := int(u["atk"])
	if t.get("kind", "") == "camp":
		if atk >= _my_camp:
			return 999.0                        # 终结: 这记能打穿大营就别犹豫
		var edge := _ai_board_edge()
		return 14.0 + float(atk) + clampf(edge, -6.0, 6.0) * 0.8   # 领先才去打脸, 落后打脸是送
	if _is_guarded(String(t["side"]), String(t["row"]), int(t["idx"])):
		return -999.0
	var arr := _row(String(t["side"]), String(t["row"]))
	var d: Dictionary = arr[int(t["idx"])]
	var s := 0.0
	if int(d["hp"]) <= atk:
		s = 60.0 + float(atk) * 3.0 + float(d["atk"])
	else:
		s = 10.0 + float(atk) * 2.0 + float(d["atk"])
		# 亏本买卖: 反击能把发起者打死 / 打残就别硬上（射手免反击不受此罚）
		if String((u["card"] as Dictionary).get("kw", "")) != "ranged":
			var ratk := int(d["atk"])
			if ratk >= int(u["hp"]):
				s -= 40.0
			elif ratk * 2 >= int(u["hp"]):
				s -= 8.0
		var edge2 := _ai_board_edge()
		if edge2 < 0.0:
			s += clampf(-edge2, 0.0, 8.0) * 0.3     # 落后时更执着于清场换血
	return s

func _check_over() -> bool:
	if _over:
		return true
	if _foe_camp <= 0:
		_settle("victory")
		return true
	if _my_camp <= 0:
		_settle("defeat")
		return true
	return false

# ---------------- 出牌 / 推进 ----------------
# ---------------- e92: 手牌拖拽 ----------------
# 按下手牌 = 拖拽候选; 不动松手 = 原点击行为(_on_hand); 拖起来松手 = 落到指到的槽。
# 法术拖到场上 = 进入选目标（跟点它一样）; 落点不合法 = 弹回原位 + 提示。
func _drag_begin(idx: int, p: Control) -> void:
	_hide_card_preview()
	if _over or _ai_busy or _whose != "my":
		return
	if _drag_tw != null and _drag_tw.is_valid():
		_drag_tw.kill()
	_drag = {"idx": idx, "p": p, "off": _stage.get_local_mouse_position() - p.position,
		"home": p.position, "rot": p.rotation_degrees, "moved": false}
	p.z_index = 30
	_card_pop(p, 1.08, 0.10)

func _drag_move() -> void:
	if _drag.is_empty():
		return
	var p: Control = _drag.get("p")
	if p == null:
		return
	var pos := _stage.get_local_mouse_position() - (_drag["off"] as Vector2)
	pos.x = clampf(pos.x, -HAND_W * 0.4, VW - HAND_W * 0.6)
	pos.y = clampf(pos.y, 0.0, VH - HAND_H * 0.5)
	if not bool(_drag["moved"]) and pos.distance_to(_drag["home"] as Vector2) > 14.0:
		_drag["moved"] = true
		p.rotation_degrees = 0.0           # 拖起来: 扇形回正, 拿在手里
	if bool(_drag["moved"]):
		p.position = pos

func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_drag_move()
		_aim_move()
		return
	var me := ev as InputEventMouseButton
	if me == null:
		return
	if me.button_index == MOUSE_BUTTON_RIGHT:
		if me.pressed and not _drag.is_empty():
			var pr: Control = _drag.get("p")
			var hr: Vector2 = _drag.get("home", Vector2.ZERO)
			var rr: float = float(_drag.get("rot", 0.0))
			_drag = {}                          # 右键断拖: 弹回
			_spring(pr, hr, rr)
		elif me.pressed and not _aim.is_empty():
			_aim_cancel()
		return
	if me.button_index != MOUSE_BUTTON_LEFT or me.pressed:
		return
	# e97: 左键松手 = 结算（旧版要再按一下才结算, 手感断裂）
	if not _drag.is_empty():
		var p: Control = _drag.get("p")
		var idx := int(_drag.get("idx", -1))
		var home: Vector2 = _drag.get("home", Vector2.ZERO)
		var rot: float = float(_drag.get("rot", 0.0))
		var moved := bool(_drag.get("moved", false))
		var drop: Dictionary = _drop_target(p.position + Vector2(HAND_W * 0.5, HAND_H * 0.5)) \
			if moved else {}
		_drag = {}
		p.z_index = 0
		if not moved:
			p.rotation_degrees = rot            # 原地按一下 = 点击, 走老逻辑
			_card_pop(p, 1.0, 0.10)
			_on_hand(idx)
			return
		var card: Dictionary = _my_hand[idx]
		if String(card["type"]) == "spell":
			if drop.is_empty():
				_spring(p, home, rot)           # 沒拖到场上: 弹回
			else:
				_on_hand(idx)                   # 拖到场上 = 点它（进选目标/直接施放, 手牌会重建）
			return
		var ok := true
		if drop.is_empty():
			ok = false
		else:
			var row := String(drop["row"])
			var slot := int(drop["slot"])
			var occupied: bool = ((_front[slot] if row == "front" else _my_support[slot]) != null)
			if occupied:
				_flash("这个位置已经有部队了")
				ok = false
			elif row == "front" and _first_empty(_my_support) >= 0:
				_flash("部队先下支援线; 点场上部队可前进前线")
				ok = false
		if ok:
			_deploy_to(idx, String(drop["row"]), int(drop["slot"]))
		else:
			_spring(p, home, rot)
	elif not _aim.is_empty():
		_aim_release()

# 弹回扇形原位（拖拽结束后的收拾动作）
func _spring(p: Control, home: Vector2, rot: float) -> void:
	if _drag_tw != null and _drag_tw.is_valid():
		_drag_tw.kill()
	_drag_tw = create_tween()
	_drag_tw.set_parallel(true)
	_drag_tw.tween_property(p, "position", home, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_drag_tw.tween_property(p, "rotation_degrees", rot, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drag_tw.tween_property(p, "scale", Vector2.ONE, 0.22)

# 松手落点: 中心点落在哪条线的哪个槽（不合法返回 {}）
func _drop_target(center: Vector2) -> Dictionary:
	for cfg: Dictionary in [{"row": "support", "y": Y_MY_SUP}, {"row": "front", "y": Y_FRONT}]:
		var y: float = cfg["y"]
		if center.y < y or center.y > y + SLOT_H:
			continue
		var row := String(cfg["row"])
		var n := _row_slots(row)
		var x0 := _row_x(n)
		var si := int(floorf((center.x - x0) / (SLOT_W + SLOT_GAP)))
		if si >= 0 and si < n:
			return {"row": row, "slot": si}
	return {}

# ---------------- e97: 拖拽攻击 + 瞄准线 ----------------
# 按下我方可行动部队: 记录出发点与合法目标集, 起一根瞄准线（出手在松手时结算）
func _aim_try_begin(side: String, row: String, idx: int) -> void:
	if side != "my" or _over or _ai_busy or _whose != "my":
		return
	if not _pending.is_empty():
		return                        # 法术目标态不抢这条交互
	var arr := _row("my", row)
	if idx < 0 or idx >= arr.size() or arr[idx] == null:
		return
	var u: Dictionary = arr[idx]
	if not _can_pick(row, idx) or not _can_act(u):
		return
	var targets := _attack_targets(u)
	if targets.is_empty():
		return
	_aim_cancel()                     # 防叠
	_aim = {"row": row, "idx": idx,
		"from": _slot_pos("my", row, idx) + Vector2(SLOT_W * 0.5, SLOT_H * 0.5),
		"moved": false, "targets": targets,
		"self_cancel": not _atk_sel.is_empty()
			and row == String(_atk_sel.get("row", "")) and idx == int(_atk_sel.get("idx", -1))}
	var out := Line2D.new()           # 深色描边
	out.width = 4.5
	out.default_color = Color(0.08, 0.06, 0.04, 0.6)
	var ln := Line2D.new()            # 亮芯
	ln.width = 2.0
	ln.default_color = Color(1.0, 0.86, 0.45, 0.92)
	ln.points = PackedVector2Array([_aim["from"], _aim["from"]])
	out.points = ln.points
	_fx.add_child(out)
	_fx.add_child(ln)
	_aim["line"] = ln
	_aim["out"] = out

func _aim_move() -> void:
	if _aim.is_empty():
		return
	var mp := _stage.get_local_mouse_position()
	var from: Vector2 = _aim["from"]
	if not bool(_aim["moved"]) and mp.distance_to(from) > 12.0:
		_aim["moved"] = true
	var pts := PackedVector2Array([from, mp])
	(_aim["line"] as Line2D).points = pts
	var ol := _aim["out"] as Line2D
	ol.points = pts
	ol.width = (_aim["line"] as Line2D).width + 2.5

func _aim_cancel() -> void:
	if _aim.is_empty():
		return
	if _aim.get("line") != null:
		(_aim["line"] as Node).queue_free()
	if _aim.get("out") != null:
		(_aim["out"] as Node).queue_free()
	_aim = {}

# 松手: 落点对上合法目标就出手; 支援线部队拖到前线空格 = 前进; 点自己 = 取消
func _aim_release() -> void:
	var mp := _stage.get_local_mouse_position()
	var moved := bool(_aim.get("moved", false))
	var row := String(_aim["row"])
	var idx := int(_aim["idx"])
	var targets: Array = _aim["targets"]
	var self_cancel := bool(_aim.get("self_cancel", false))
	_aim_cancel()
	if not moved:
		if self_cancel:
			_clear_sel()                  # 点自己 = 取消（老语义）
		return
	var t := _aim_target_at(mp)
	if not t.is_empty() and _aim_match(t, targets):
		if _do_attack("my", row, idx, t):
			_atk_sel = {}
			_refresh_all()
			_check_over()
		return
	# 拖到前线空格 = 支援线部队前进（拖拽版的前进手势）
	if not t.is_empty() and String(t.get("side", "")) == "my" and String(t.get("row", "")) == "front" \
			and row == "support" and _front[int(t["idx"])] == null:
		_atk_sel = {}
		_advance_to(idx, int(t["idx"]))

# 松手落点 -> 槽位/大营（无匹配返回 {}）
func _aim_target_at(pos: Vector2) -> Dictionary:
	for cfg: Dictionary in [{"side": "my", "row": "support"}, {"side": "my", "row": "front"},
			{"side": "foe", "row": "front"}, {"side": "foe", "row": "support"}]:
		var row := String(cfg["row"])
		var n := _row_slots(row)
		var x0 := _row_x(n)
		var y := _row_y(String(cfg["side"]), row)
		if pos.y < y or pos.y > y + SLOT_H:
			continue
		var si := int(floorf((pos.x - x0) / (SLOT_W + SLOT_GAP)))
		if si >= 0 and si < n:
			return {"side": String(cfg["side"]), "row": row, "idx": si}
	if _bar_foe != null:
		var r := Rect2(_bar_foe.position, _bar_foe.size)
		if r.has_point(pos):
			return {"kind": "camp", "side": "foe"}
	return {}

func _aim_match(t: Dictionary, targets: Array) -> bool:
	for v: Variant in targets:
		var d := v as Dictionary
		if String(d.get("kind", "")) == String(t.get("kind", "")) \
				and String(d.get("side", "")) == String(t.get("side", "")) \
				and String(d.get("row", "")) == String(t.get("row", "")) \
				and int(d.get("idx", -1)) == int(t.get("idx", -1)):
			return true
	return false

func _card_pop(p: Control, s: float, dur := 0.12) -> void:
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2(s, s), dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_hand(idx: int) -> void:
	if _over or _ai_busy or _whose != "my":
		return
	if int(_pending.get("hand_idx", -1)) == idx:      # 再点一次 = 取消
		_clear_sel()
		return
	if not _pending.is_empty():
		_pending = {}      # 换点别的牌: 丢掉法术目标态, 否则手牌 remove_at 会按旧索引串位
	var card: Dictionary = _my_hand[idx]
	var cost := int(card["cost"])
	if _cost < cost:
		_flash("费用不足 (这张要 %d 费)" % cost)
		return
	if String(card["type"]) == "spell":
		var tgt := String(card.get("target", ""))
		if tgt == "ally" and _all_units("my").is_empty():
			_flash("没有可指定的友军")
			return
		if tgt == "foe" and _all_units("foe").is_empty():
			_flash("没有可指定的敌军")
			return
		if tgt == "":
			_my_hand.remove_at(idx)
			_cost -= cost
			_cast_spell(card, "my", "", -1, "")
			_flash("%s!" % String(card["name"]))
			_refresh_all()
			_check_over()
			return
		_pending = {"hand_idx": idx, "card": card, "target": tgt}
		_refresh_all()
		_flash("选一个目标 (右键 / Esc 取消)")
		return
	var slot := _first_empty(_row("my", "support"))
	var row := "support"
	if slot < 0:                       # 支援线满了: 直接下前线空位
		slot = _first_empty(_front, _front_slots)
		row = "front"
	if slot < 0:
		_flash("支援线和前线都满了")
		return
	_deploy_to(idx, row, slot)

# 前进: 支援线自己的部队花「行动费」上前线（进最左边的空位）
func _advance(i: int) -> void:
	var slot := _first_empty(_front, _front_slots)
	if slot < 0:
		_flash("前线已经站满了")
		return
	_advance_to(i, slot)

# 前进落到指定格（点菜单自动选最左空位走这里）
func _advance_to(i: int, slot: int) -> void:
	var v: Variant = _my_support[i]
	if v == null:
		return
	var u: Dictionary = v
	if not _can_act(u):
		_flash("这支部队已经行动过了")
		return
	var act := int((u["card"] as Dictionary).get("act", 1))
	if _cost < act:
		_flash("前进要 %d 点行动费" % act)
		return
	_cost -= act
	_my_support[i] = null
	u["acted"] = true
	_front[slot] = u
	Audio.play_sfx("move", -4.0)
	_flash("%s 前进前线 (-%d 点)" % [String((u["card"] as Dictionary)["name"]), act])
	_refresh_all()

func _on_slot(side: String, row: String, idx: int) -> void:
	if _over or _ai_busy or _whose != "my":
		return
	if not _pending.is_empty():
		var tgt := String(_pending.get("target", ""))
		# 前线是共享的: 按单位自己的 side 判敌我
		var unit: Variant = _row(side, row)[idx]
		if unit == null:
			return
		var uside := String((unit as Dictionary)["side"])
		if (tgt == "ally" and uside != "my") or (tgt == "foe" and uside != "foe"):
			return
		var card: Dictionary = _pending["card"]
		_my_hand.remove_at(int(_pending["hand_idx"]))
		_cost -= int(card["cost"])
		_cast_spell(card, "my", side, idx, row)
		_clear_sel()
		_refresh_all()
		_check_over()
		return
	if not _atk_sel.is_empty():
		var from: Dictionary = _atk_sel
		if row == String(from["row"]) and idx == int(from["idx"]):
			if _aim.is_empty():
				_clear_sel()                # 再点自己 = 取消（拖拽态的取消在松手时结算）
			return
		var clicked: Variant = _row(side, row)[idx]
		if clicked != null and String((clicked as Dictionary)["side"]) == "foe":
			if _do_attack("my", String(from["row"]), int(from["idx"]), {"side": "foe", "row": row, "idx": idx}):
				_atk_sel = {}
				_refresh_all()
				_check_over()
			return
		if clicked == null and row == "front" and String(from["row"]) == "support":
			_atk_sel = {}                       # 点前线空格 = 支援线部队前进
			_advance_to(int(from["idx"]), idx)
			return
		if clicked != null and _can_pick(row, idx):
			_atk_sel = {"row": row, "idx": idx}   # 点我方其他可选部队 = 换选
			_refresh_all()
			return
		_clear_sel()
		return
	# 普通模式: 点我方部队 = 选中 (KARDS 式), 提示下一步
	if (side == "my" or row == "front") and _can_pick(row, idx):
		_atk_sel = {"row": row, "idx": idx}
		var pick_u: Dictionary = _row("my", row)[idx]
		var sup_hint := " / 点前线空格前进" if row == "support" else ""
		_flash("选中 %s: 点敌方部队出手%s (右键取消)" % [String((pick_u["card"] as Dictionary)["name"]), sup_hint])
		_refresh_all()

# 部署共用尾段（手牌点击自动选格走这里）
func _deploy_to(idx: int, row: String, slot: int) -> void:
	var card: Dictionary = _my_hand[idx]
	_my_hand.remove_at(idx)
	_cost -= int(card["cost"])
	var u := _new_unit(card, "my")
	if row == "front":
		_front[slot] = u
	else:
		_row("my", "support")[slot] = u
	# 骑兵上场当回合就能动; 其余部队部署已算一个动作
	if String(card.get("kw", "")) != "cav":
		u["acted"] = true
	_log_play("my", card)
	Audio.play_sfx("deploy", -4.0)
	_deploy_ring(_slot_pos("my", row, slot) + Vector2(SLOT_W * 0.5, SLOT_H * 0.5))   # e92: 落场金环
	_flash("%s 下场" % String(card["name"]))
	_refresh_all()
	_check_over()

# ---------------- 法术效果 ----------------
# caster = 谁放的（"my"/"foe"）; side/row/idx = 被指定的目标（无目标的法术传空）
func _cast_spell(card: Dictionary, caster: String, side: String, idx: int, row: String) -> void:
	_log_play(caster, card)               # 法术进出牌历史（双方都在这统一记）
	var other := "foe" if caster == "my" else "my"
	match String(card.get("spell", "")):
		"buff":
			var arr := _row(side, row)
			if idx < 0 or idx >= arr.size() or arr[idx] == null:
				return
			var n := int(card.get("n", 1))
			var u: Dictionary = arr[idx]
			u["atk"] = int(u["atk"]) + n
			u["hp"] = int(u["hp"]) + n
			u["max_hp"] = int(u["max_hp"]) + n
		"hp_all":
			for u: Dictionary in _all_units(caster):
				u["hp"] = int(u["hp"]) + int(card.get("n", 1))
				u["max_hp"] = int(u["max_hp"]) + int(card.get("n", 1))
		"atk_all":
			for u: Dictionary in _all_units(caster):
				u["atk"] = int(u["atk"]) + int(card.get("n", 1))
		"coin2":
			var cn := int(card.get("n", 2))
			if caster == "my":
				_cost += cn
			else:
				_foe_cost += cn
		"draw2":
			for i in int(card.get("n", 2)):
				_draw_card(caster)
		"heal":
			var hn := int(card.get("n", 4))
			if caster == "my":
				_my_camp = mini(_my_camp_max, _my_camp + hn)
			else:
				_foe_camp = mini(_foe_camp_max, _foe_camp + hn)
		"camp_dmg":
			var cdmg: int = int(card.get("dmg", 3))
			if other == "my":
				_my_camp = maxi(0, _my_camp - cdmg)
			else:
				_foe_camp = maxi(0, _foe_camp - cdmg)
		"unit_dmg":
			var arr2 := _row(side, row)
			if idx < 0 or idx >= arr2.size() or arr2[idx] == null:
				return
			# 守护: 目标的左右邻居有守护兵, 直伤法术也被挡下
			if _is_guarded(side, row, idx):
				var dp := _slot_pos(side, row, idx) + Vector2(SLOT_W * 0.5, SLOT_H * 0.5)
				_float_text("守护", dp, Color(0.55, 0.90, 0.75), 16)
				_flash("%s 被邻居掩护, 法术落空" % String(((arr2[idx] as Dictionary)["card"] as Dictionary)["name"]))
				return
			var d: Dictionary = arr2[idx]
			d["hp"] = int(d["hp"]) - int(card.get("dmg", 2))
			if int(d["hp"]) <= 0:
				arr2[idx] = null
				if side == "foe":
					_killed += 1
			else:
				arr2[idx] = d
		"summon2":
			for i in 2:
				var slot := _first_empty(_row(caster, "support"))
				if slot < 0:
					break
				var m := _new_unit(CardsData.summon_card(), caster)
				_row(caster, "support")[slot] = m
				m["acted"] = true

# ---------------- 小工具 ----------------
func _row(side: String, row: String) -> Array:
	# 前线是共享的: 谁来要都给同一条; 支援线才分敌我
	if row == "front":
		return _front
	return _foe_support if side == "foe" else _my_support

func _find_slot(u: Dictionary) -> Vector2:
	# 按 uid 在三条线上找单位所在槽位, 返回槽位左上角坐标（演出用）
	for row: String in ["front", "support"]:
		var arr := _row(String(u["side"]), row)
		for i in arr.size():
			var v: Variant = arr[i]
			if v != null and int((v as Dictionary).get("uid", -1)) == int(u["uid"]):
				return _slot_pos(String(u["side"]), row, i)
	return Vector2(VW, VH) * 0.5

func _new_unit(card: Dictionary, side := "my") -> Dictionary:
	_uid += 1
	# 城墙掩护 / 守军披甲: 敌方登场的部队多加血（词条 hp）
	var bonus := int(_sc.get("hp", 0)) if side == "foe" else 0
	return {
		"card": card, "side": side, "hp": int(card["hp"]) + bonus,
		"max_hp": int(card["hp"]) + bonus,
		"atk": int(card["atk"]), "acted": false, "uid": _uid,
		"gold": bool(card.get("gold", false)),
	}

func _all_units(side: String) -> Array:
	var out: Array = []
	for u: Variant in _front:
		if u != null and String((u as Dictionary)["side"]) == side:
			out.append(u)
	for u: Variant in _row(side, "support"):
		if u != null:
			out.append(u)
	return out

func _first_empty(arr: Array, cap := 0) -> int:
	var n: int = arr.size() if cap <= 0 else mini(cap, arr.size())
	for i in n:
		if arr[i] == null:
			return i
	return -1

func _clear_acted(side: String) -> void:
	for u: Dictionary in _all_units(side):
		u["acted"] = false

func _draw_card(side: String) -> void:
	var deck: Array = _my_deck if side == "my" else _foe_deck
	var hand: Array = _my_hand if side == "my" else _foe_hand
	if deck.is_empty():
		return
	var card: Variant = deck.pop_back()
	if hand.size() >= CardsData.HAND_CAP:
		return                          # 手牌满了: 抽到就烧掉
	hand.append(card)

func _clear_sel() -> void:
	_aim_cancel()                             # e97: 取消选中顺带收掉瞄准线
	if _pending.is_empty() and _atk_sel.is_empty():
		return
	_pending = {}
	_atk_sel = {}
	_refresh_all()

# ---------------- 界面 ----------------
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "CardsHUD"
	add_child(_layer)
	var bg := ColorRect.new()
	# 底色随词条配桌面木色（桌面背景铺不到的扩张边露的就是它, 颜色不搭会穿帮）
	match _sc_id:
		"siege":
			bg.color = Color(0.12, 0.105, 0.105)
		"boarding":
			bg.color = Color(0.10, 0.075, 0.05)
		"night":
			bg.color = Color(0.075, 0.058, 0.045)
		_:
			bg.color = UiStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(bg)
	# B2 径向暗角: 中心透四角暗, 战场有纵深不吃文字
	var vin := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var gg := Gradient.new()
	gg.set_color(0, Color(0, 0, 0, 0.0))
	gg.set_color(1, Color(0, 0, 0, 0.42))
	gt.gradient = gg
	gt.width = 64
	gt.height = 36
	vin.texture = gt
	vin.set_anchors_preset(Control.PRESET_FULL_RECT)
	vin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(vin)
	_stage = Control.new()
	_stage.set_meta("cozy_surface", true)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = Vector2(VW, VH)
	_layer.add_child(_stage)
	# 程序化战斗背景: 挂 _stage 最底（画布内）, 按词条变体
	_build_scenery()
	# E1 战场后处理: 泛光+色温垫在战场画面之上（bg/战场在它下面, 结算页是独立层不罩）
	# 夜袭词条整场浸冷月色; 情绪(mood)随大营血量差在 _refresh_hud 里喂
	var post := ColorRect.new()
	post.name = "PostFX"
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = preload("res://scene/fx_post.gdshader")
	_post_mat.set_shader_parameter("strength", 0.42)
	_post_mat.set_shader_parameter("night", 0.85 if _sc_id == "night" else 0.0)
	post.material = _post_mat
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(post)
	# preset 进树后再铺 + 窗口尺寸变化时重铺（同 game.gd 修法: 先铺不跟随视口扩张, 底部露亮带）
	post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(func() -> void:
		post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT))
	_recenter()
	get_viewport().size_changed.connect(_recenter)

	_field_layer = Control.new()
	_field_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_layer.size = Vector2(VW, VH)
	_stage.add_child(_field_layer)
	_hand_layer = Control.new()
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_layer.size = Vector2(VW, VH)
	_stage.add_child(_hand_layer)

	# 顶部敌情条
	_bar_foe = _mk_panel(Vector2(VW - 32.0, H_BAR), UiStyle.INK, UiStyle.EDGE, 2)
	_bar_foe.position = Vector2(16, Y_FOE_BAR)
	_bar_foe.gui_input.connect(_on_bar_click)
	_stage.add_child(_bar_foe)
	_lbl_foe = _mk_label("", 13, C_TXT, 578.0, 18)
	_lbl_foe.position = Vector2(34, 4)          # 让开左端的营旗旗面（旗面右缘约 27）
	_bar_foe.add_child(_lbl_foe)
	# d2: KARDS 式敌方手牌牌背行 —— 8 格牌背 + 数字, 敌手牌多少一眼可见
	for i in 8:
		var pip := _mk_panel(Vector2(12, 16), Color(0.16, 0.22, 0.38), Color(0.45, 0.52, 0.68), 1)
		pip.position = Vector2(448 + i * 14, 3)
		_bar_foe.add_child(pip)
		_foe_hand_pips.append(pip)
	_lbl_foe_hand = _mk_label("", 13, C_TXT, 30.0, 18)
	_lbl_foe_hand.position = Vector2(562, 4)
	_bar_foe.add_child(_lbl_foe_hand)
	_lbl_sc = _mk_label("", 13, C_GOLD, 360.0, 18)
	_lbl_sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lbl_sc.position = Vector2(608, 4)
	_bar_foe.add_child(_lbl_sc)
	var fbar_bg := ColorRect.new()
	fbar_bg.color = Color(0, 0, 0, 0.6)
	fbar_bg.position = Vector2(12, 26)
	fbar_bg.size = Vector2(300, 10)
	fbar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_foe.add_child(fbar_bg)
	_lbl_foe_bar = ColorRect.new()
	_lbl_foe_bar.color = C_FOE
	_lbl_foe_bar.size = Vector2(300, 10)
	_lbl_foe_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fbar_bg.add_child(_lbl_foe_bar)
	var btn_ret := _mk_button("撤退", 110.0)
	btn_ret.position = Vector2(VW - 32.0 - 118.0, 9)
	btn_ret.pressed.connect(_on_retreat)
	_bar_foe.add_child(btn_ret)
	# e96 KARDS 式敌方大营: HP 圆章 + 受损烟火点
	var fc := _mk_coin(str(_foe_camp), Vector2(968, 11), Color(0.28, 0.10, 0.10), Color(0.98, 0.55, 0.45))
	_bar_foe.add_child(fc)
	_coin_foe_camp = fc
	for d: Dictionary in [
			{"pos": Vector2(292, 38), "r": 8.0, "col": Color(0.5, 0.5, 0.55, 0.28), "th": 0.6},
			{"pos": Vector2(312, 42), "r": 6.0, "col": Color(0.5, 0.5, 0.55, 0.26), "th": 0.6},
			{"pos": Vector2(240, 40), "r": 8.0, "col": Color(1.0, 0.55, 0.22, 0.30), "th": 0.3},
			{"pos": Vector2(262, 42), "r": 6.0, "col": Color(1.0, 0.48, 0.18, 0.32), "th": 0.3},
			{"pos": Vector2(280, 38), "r": 7.0, "col": Color(1.0, 0.62, 0.25, 0.28), "th": 0.3}]:
		_foe_dmg_dots.append(_mk_glow_dot(_bar_foe, d["pos"], d["r"], d["col"], d["th"]))
	# B4 敌方大营旗: 顶条左端一面红旗
	_make_flag(_bar_foe, Vector2(10, 44), 28.0, Color(0.78, 0.34, 0.30))

	# 左下我方大营 / 费用
	var camp := _mk_panel(Vector2(180, 158), UiStyle.INK, UiStyle.EDGE, 2)
	camp.position = Vector2(16, 448)
	_stage.add_child(camp)
	var ttl := _mk_label("我方大营", 13, C_MY, 150.0, 18)
	ttl.position = Vector2(32, 6)
	camp.add_child(ttl)
	_lbl_camp = _mk_label("", 12, C_TXT, 164.0, 16)
	_lbl_camp.position = Vector2(8, 26)
	camp.add_child(_lbl_camp)
	var cbar := ColorRect.new()
	cbar.color = Color(0, 0, 0, 0.6)
	cbar.position = Vector2(8, 46)
	cbar.size = Vector2(164, 12)
	cbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camp.add_child(cbar)
	_bar_camp = ColorRect.new()
	_bar_camp.color = Color(0.36, 0.78, 0.31)
	_bar_camp.size = Vector2(164, 12)
	_bar_camp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbar.add_child(_bar_camp)
	_lbl_cost = _mk_label("", 26, Color(0.55, 0.85, 1.0), 164.0, 32)
	_lbl_cost.position = Vector2(8, 66)
	camp.add_child(_lbl_cost)
	_lbl_deck = _mk_label("", 12, Color(0.72, 0.70, 0.64), 164.0, 16)
	_lbl_deck.position = Vector2(8, 104)
	camp.add_child(_lbl_deck)
	# B4 我方大营旗: 挪进面板右上角内侧（原 (20,8) 旗杆穿出面板顶、旗面压「我方大营」标题）
	_make_flag(camp, Vector2(146, 40), 34.0, Color(0.30, 0.50, 0.85))
	# e96 KARDS 式大营: HP 圆章（大数字）+ 受损烟火点
	var myc := _mk_coin(str(_my_camp), Vector2(6, 120), Color(0.10, 0.26, 0.12), Color(0.55, 0.95, 0.55))
	myc.scale = Vector2(1.35, 1.35)
	camp.add_child(myc)
	_coin_my_camp = myc
	for d: Dictionary in [
			{"pos": Vector2(98, 138), "r": 9.0, "col": Color(0.5, 0.5, 0.55, 0.30), "th": 0.6},
			{"pos": Vector2(120, 146), "r": 7.0, "col": Color(0.5, 0.5, 0.55, 0.28), "th": 0.6},
			{"pos": Vector2(64, 140), "r": 9.0, "col": Color(1.0, 0.55, 0.22, 0.32), "th": 0.3},
			{"pos": Vector2(88, 148), "r": 7.0, "col": Color(1.0, 0.48, 0.18, 0.34), "th": 0.3},
			{"pos": Vector2(108, 140), "r": 8.0, "col": Color(1.0, 0.62, 0.25, 0.30), "th": 0.3}]:
		_my_dmg_dots.append(_mk_glow_dot(camp, d["pos"], d["r"], d["col"], d["th"]))

	# 右下结束回合 (e97: KARDS 式大按钮 + 空格提示)
	_btn_end = _mk_button("结束回合 (空格)", 190.0)
	_btn_end.position = Vector2(VW - 206.0, 586.0)
	_btn_end.size = Vector2(190.0, 38.0)
	_btn_end.add_theme_font_size_override("font_size", 15)
	var sb_end := StyleBoxFlat.new()
	sb_end.bg_color = Color("305b56")
	sb_end.border_color = C_GOLD
	sb_end.set_border_width_all(2)
	sb_end.set_corner_radius_all(2)
	var sb_end_h := sb_end.duplicate() as StyleBoxFlat
	sb_end_h.bg_color = Color("42746b")
	var sb_end_d := sb_end.duplicate() as StyleBoxFlat
	sb_end_d.bg_color = UiStyle.SURFACE
	sb_end_d.border_color = Color(0.45, 0.40, 0.30)
	_btn_end.add_theme_stylebox_override("normal", sb_end)
	_btn_end.add_theme_stylebox_override("hover", sb_end_h)
	_btn_end.add_theme_stylebox_override("pressed", sb_end_h)
	_btn_end.add_theme_stylebox_override("disabled", sb_end_d)
	_btn_end.pressed.connect(_on_end_turn)
	_stage.add_child(_btn_end)

	# 提示条: 放中框(304)与我方支援线(360)之间的空带 —— 手牌区在下面, 别跟牌重叠
	_lbl_hint = _mk_label("", 13, C_GOLD, 660.0, 20)
	_lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_hint.position = Vector2(VW * 0.5 - 330.0, 374.0)
	_stage.add_child(_lbl_hint)
	_lbl_tactics = _mk_label("", 12, UiStyle.PAPER, 800.0, 34.0)
	_lbl_tactics.position = Vector2(176, 406)
	_lbl_tactics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_tactics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage.add_child(_lbl_tactics)
	_retreat_dialog = ConfirmationDialog.new()
	_retreat_dialog.title = "离开战斗"
	_retreat_dialog.dialog_text = "确认撤退? 本场未获得的战利品不会结算."
	_retreat_dialog.ok_button_text = "确认撤退"
	_retreat_dialog.cancel_button_text = "继续战斗"
	_retreat_dialog.theme = UiStyle.shared_theme
	_retreat_dialog.confirmed.connect(_commit_retreat)
	_layer.add_child(_retreat_dialog)

	# 出牌历史抽屉: 挂在演出层之下（小卡从它上面飞过）, 点「史」标签滑出
	_build_hist_drawer()

	# 演出层: 必须是 _stage 的最后一个孩子（永远盖在最上面）, 自己不吃鼠标
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.size = Vector2(VW, VH)
	_stage.add_child(_fx)

# ---------------- 战斗背景 ----------------
# KARDS 式桌面: 整屏一块深色木桌（横板 + 板缝 + 木纹 + 明度错缝）, 中央铺一块
# 呢面战场桌垫, 部队/回合牌都落垫上; 词条只调木色与桌垫色
#（野战暖木 / 攻城冷灰木 / 接舷湿甲板 / 夜袭乌木）。全部低对比, 只给氛围不抢 UI。
func _build_scenery() -> void:
	var sc := Control.new()
	sc.name = "TacticalBoard"
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.size = Vector2(VW, VH)
	_stage.add_child(sc)
	# 海图桌面以低对比布面和分区留白承托卡牌, 不再平铺高对比木板纹理。
	var surface: Color = Color("d9c296")
	if _sc_id == "night":
		surface = Color("c5bdab")
	elif _sc_id == "siege":
		surface = Color("d0bc98")
	var background := ColorRect.new()
	background.color = surface
	background.size = Vector2(VW, VH)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(background)
	# 稀疏海图刻线仅占背景, 强度低于阵营边框和行动高亮。
	for x in range(32, int(VW), 64):
		var line := ColorRect.new()
		line.color = Color(0.65, 0.78, 0.73, 0.035)
		line.position = Vector2(x, 60)
		line.size = Vector2(1, 360)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(line)
	for y in range(76, 420, 64):
		var line := ColorRect.new()
		line.color = Color(0.65, 0.78, 0.73, 0.035)
		line.position = Vector2(24, y)
		line.size = Vector2(VW - 48, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(line)
	for spec: Dictionary in [
		{"y": Y_FOE_SUP, "n": 4, "color": C_FOE},
		{"y": Y_FRONT, "n": _front_slots, "color": UiStyle.GOLD},
		{"y": Y_MY_SUP, "n": 4, "color": C_MY}]:
		var panel := Panel.new()
		var edge: Color = spec["color"]
		var style: StyleBoxFlat = UiStyle.panel(Color("ebdbb8"), Color(edge, 0.55), 0)
		style.border_width_top = 1
		panel.add_theme_stylebox_override("panel", style)
		panel.position = Vector2(_row_x(int(spec["n"])) - 6, float(spec["y"]) - 4)
		panel.size = Vector2(_row_w(int(spec["n"])) + 12, SLOT_H + 8)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(panel)
	var hand_back := Panel.new()
	hand_back.add_theme_stylebox_override("panel", UiStyle.panel(Color("e9d6ac"), UiStyle.EDGE, 0))
	hand_back.position = Vector2(202, Y_HAND - 12)
	hand_back.size = Vector2(VW - 420, HAND_H + 32)
	hand_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(hand_back)
func _recenter() -> void:
	if _stage == null:
		return
	_view = get_viewport_rect().size
	# contain 缩放: 任何窗口比例下整个 1152x648 战场完整可见（底色由全屏 bg 铺, 不会露裁边）
	var s := minf(_view.x / VW, _view.y / VH)
	_stage.scale = Vector2(s, s)
	_stage.position = Vector2(floorf((_view.x - VW * s) * 0.5), floorf((_view.y - VH * s) * 0.5))

func _refresh_all() -> void:
	_rebuild_field()
	_rebuild_hand()
	_refresh_hud()

func _refresh_tactics() -> void:
	if _lbl_tactics == null:
		return
	if _over:
		_lbl_tactics.text = "战斗已结束, 查看本场战果."
	elif _ai_busy or _whose != "my":
		_lbl_tactics.text = "对手正在行动, 留意前线和大营."
	elif not _pending.is_empty():
		_lbl_tactics.text = "选择高亮目标施放卡牌. 右键或 Esc 取消."
	elif not _atk_sel.is_empty():
		_lbl_tactics.text = "悬停敌军查看伤害与反击. 点击高亮目标进攻, 或拖到前线空位前进."
	else:
		var ready := 0
		for unit: Dictionary in _all_units("my"):
			if _can_act(unit) and int((unit["card"] as Dictionary).get("act", 1)) <= _cost:
				ready += 1
		_lbl_tactics.text = "第 %d 回合 | 剩余 %d 费 | %d 支部队可行动 | 先部署, 再推进, 最后攻击大营" % [_turn_no, _cost, ready]

func _selection_can_target(side: String, row: String, idx: int) -> bool:
	if _atk_sel.is_empty() or not _sel_can_hit():
		return false
	var source: Array = _row("my", String(_atk_sel["row"]))
	var source_idx: int = int(_atk_sel["idx"])
	if source_idx < 0 or source_idx >= source.size() or source[source_idx] == null:
		return false
	for target: Dictionary in _attack_targets(source[source_idx]):
		if target.get("kind", "") != "camp" and String(target.get("side", "")) == side \
			and String(target.get("row", "")) == row and int(target.get("idx", -1)) == idx:
			return true
	return false

# 预览与结算共用守护判定及击杀免反击规则, 不在 UI 另造一套伤害公式。
func attack_preview(target: Dictionary) -> String:
	if _atk_sel.is_empty():
		return "先选择我方部队."
	var source: Array = _row("my", String(_atk_sel["row"]))
	var source_idx: int = int(_atk_sel["idx"])
	if source_idx < 0 or source_idx >= source.size() or source[source_idx] == null:
		return "所选部队已离场."
	var unit: Dictionary = source[source_idx]
	var side: String = String(target.get("side", "foe"))
	var row: String = String(target.get("row", "front"))
	var idx: int = int(target.get("idx", -1))
	if not _selection_can_target(side, row, idx):
		return "不能进攻这个目标. 受守护的部队需要先解除掩护."
	var victim: Dictionary = _row(side, row)[idx]
	var damage: int = int(unit["atk"])
	var killed: bool = damage >= int(victim["hp"])
	var ranged: bool = String((unit["card"] as Dictionary).get("kw", "")) == "ranged"
	var retaliation: int = 0 if killed or ranged else int(victim["atk"])
	return "造成 %d 伤害%s | 反击 %d%s | 消耗 %d 费" % [damage, " (击倒)" if killed else "", retaliation,
		" (我方会倒下)" if retaliation >= int(unit["hp"]) else "", int((unit["card"] as Dictionary).get("act", 1))]

func _refresh_hud() -> void:
	_refresh_tactics()
	var nm := _foe_display()
	_lbl_foe.text = "%s / %s   大营 %d/%d   牌库 %d" % [
		nm, CardsData.arch_name(party), _foe_camp, _foe_camp_max, _foe_deck.size()]
	# d2: 敌方手牌 = 牌背格可见数 + 数字（手牌数不再塞文字里, 一眼可读）
	for i in _foe_hand_pips.size():
		_foe_hand_pips[i].visible = i < _foe_hand.size()
	if _lbl_foe_hand != null:
		_lbl_foe_hand.text = str(_foe_hand.size())
	if _lbl_sc != null:
		var tag := String(_sc.get("name", "野战"))
		if _turn_limit > 0:
			tag += "   剩余 %d 回合" % maxi(0, _turn_limit - _turn_no + 1)
		_lbl_sc.text = tag
		_lbl_sc.add_theme_color_override("font_color",
			C_GOLD if _sc_id != "field" else Color(0.72, 0.70, 0.64))
	_lbl_foe_bar.size.x = 300.0 * clampf(float(_foe_camp) / float(maxi(1, _foe_camp_max)), 0.0, 1.0)
	_lbl_camp.text = "%d / %d" % [_my_camp, _my_camp_max]
	_bar_camp.color = Color(0.36, 0.78, 0.31) if _my_camp * 2 >= _my_camp_max \
		else (Color(0.9, 0.75, 0.2) if _my_camp * 4 >= _my_camp_max else Color(0.82, 0.25, 0.2))
	_bar_camp.size.x = 164.0 * clampf(float(_my_camp) / float(maxi(1, _my_camp_max)), 0.0, 1.0)
	_lbl_cost.text = "费用 %d / %d" % [_cost, _cost_max]
	_lbl_deck.text = "牌库 %d   敌方费用 %d/%d" % [_my_deck.size(), _foe_cost, _foe_cost_max]
	if _coin_my_camp != null:
		(_coin_my_camp.get_child(0) as Label).text = str(_my_camp)
	if _coin_foe_camp != null:
		(_coin_foe_camp.get_child(0) as Label).text = str(_foe_camp)
	_sync_camp_dots()
	if _btn_end != null:
		_btn_end.disabled = _over or _ai_busy or _whose != "my"
	# 攻击选目标模式: 敌前线没有他们的部队时, 点顶部敌情条 = 直击大营
	if _bar_foe != null:
		var camp_ok := false
		if not _atk_sel.is_empty() and _whose == "my" and not _over and not _ai_busy:
			var from: Dictionary = _atk_sel
			var arr := _row("my", String(from["row"]))
			var fi := int(from["idx"])
			if fi < arr.size() and arr[fi] != null:
				for t: Dictionary in _attack_targets(arr[fi]):
					if t.get("kind", "") == "camp":
						camp_ok = true
						break
		_bar_foe.mouse_filter = Control.MOUSE_FILTER_STOP if camp_ok else Control.MOUSE_FILTER_IGNORE
		_bar_foe.tooltip_text = "直击大营!" if camp_ok else ""
	# E2 情绪滤镜: 双方大营血量差定战局氛围——我方越劣势画面越红越压抑, 大优镀暖金
	if _post_mat != null:
		var dm := float(_my_camp) / float(maxi(1, _my_camp_max)) \
			- float(_foe_camp) / float(maxi(1, _foe_camp_max))
		var want := clampf(-dm * 1.8, -1.0, 1.0)
		if absf(want - _mood) > 0.01:
			if _mood_tw != null and _mood_tw.is_valid():
				_mood_tw.kill()
			_mood_tw = create_tween()
			_mood_tw.tween_method(_set_mood, _mood, want, 0.8) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _set_mood(v: float) -> void:
	_mood = v
	if _post_mat != null:
		_post_mat.set_shader_parameter("mood", v)

# e96: 大营受损状态（KARDS: 总部越残越冒烟火）—— 自发光圆点按血量阈值点亮,
# 加法混合从低 alpha 起步（HDR+泛光纪律），不呼吸不 tween（免 _process 顶基准）
func _mk_glow_dot(parent: Control, pos: Vector2, r: float, col: Color, th: float) -> Sprite2D:
	var s := Sprite2D.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	gt.gradient = g
	gt.width = 32
	gt.height = 32
	s.texture = gt
	s.scale = Vector2(r / 16.0, r / 16.0)
	s.position = pos
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.visible = false
	s.set_meta("th", th)
	parent.add_child(s)
	return s

func _sync_camp_dots() -> void:
	var mr := float(_my_camp) / float(maxi(1, _my_camp_max))
	for d: Variant in _my_dmg_dots:
		var s := d as Sprite2D
		s.visible = mr < float(s.get_meta("th"))
	var fr := float(_foe_camp) / float(maxi(1, _foe_camp_max))
	for d: Variant in _foe_dmg_dots:
		var s := d as Sprite2D
		s.visible = fr < float(s.get_meta("th"))

func _foe_display() -> String:
	var tid := String(party.get("siege", ""))
	if tid != "" and Nations.TOWNS.has(tid):
		return "守军: %s" % String((Nations.TOWNS[tid] as Dictionary)["name"])
	var nid := String(party.get("nation", ""))
	if nid != "":
		for n: Dictionary in Nations.NATIONS:
			if String(n["id"]) == nid:
				return "敌军: %s" % String(n["name"])
	return "敌军: %s" % String(party.get("type", "来犯之敌"))

func _rebuild_field() -> void:
	_hide_card_preview()
	for c in _field_layer.get_children():
		c.queue_free()
	_stage_row_label("敌方支援线", Y_FOE_SUP, Color(0.78, 0.52, 0.48), 4)
	_stage_row_label("前线(共抢)", Y_FRONT, C_GOLD, _front_slots)
	_stage_row_label("我方支援线", Y_MY_SUP, Color(0.48, 0.62, 0.92), 4)
	for i in 4:
		_field_layer.add_child(_make_slot("foe", "support", i, _slot_pos("foe", "support", i)))
	for i in _front_slots:
		_field_layer.add_child(_make_slot("", "front", i, _slot_pos("", "front", i)))
	for i in 4:
		_field_layer.add_child(_make_slot("my", "support", i, _slot_pos("my", "support", i)))

func _stage_row_label(txt: String, y: float, col: Color, n: int) -> void:
	var l := _mk_label(txt, 12, col, 110.0, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.position = Vector2(_row_x(n) - 118.0, y + SLOT_H * 0.5 - 8.0)
	_field_layer.add_child(l)

func _row_y(side: String, row: String) -> float:
	# 前线只有一条, 不分敌我; 支援线才看 side
	if row == "front":
		return Y_FRONT
	return Y_FOE_SUP if side == "foe" else Y_MY_SUP

func _make_slot(side: String, row: String, idx: int, pos: Vector2) -> Control:
	var unit: Variant = _row(side, row)[idx]
	var u_side := ""
	var bg := Color(0.09, 0.10, 0.13, 0.72)       # e92: 空槽提亮 + 提高不透明度, 槽位轮廓不再若隐若现
	var border := Color(0.46, 0.49, 0.57)
	var clickable := false
	var targetable := false
	if unit != null:
		u_side = String((unit as Dictionary).get("side", side))
		var g := bool((unit as Dictionary).get("gold", false))
		border = C_GOLD if g else (C_FOE if u_side == "foe" else C_MY)
		# B3 满阶金卡: 暖底衬金框, 一眼贵
		bg = Color(0.16, 0.14, 0.085, 0.95) if g else Color(0.14, 0.13, 0.16, 0.95)
	elif side == "my" and row == "support":
		bg = Color(0.13, 0.17, 0.23, 0.85)      # 可以下牌的空位: 再亮一档
		border = Color(0.40, 0.52, 0.66)
	if not _over and not _ai_busy and _whose == "my":
		if not _pending.is_empty() and unit != null:
			clickable = _pending.get("target", "") == ("ally" if u_side == "my" else "foe")
		elif not _atk_sel.is_empty():
			# 选目标模式: 自己的部队（点 = 取消/换选）+ 敌军任意行（点 = 出手）+ 前线空格（支援线选中时 = 前进）
			if unit != null:
				clickable = (u_side == "my" and (row == String(_atk_sel["row"]) and idx == int(_atk_sel["idx"]) \
					or _can_pick(row, idx))) \
					or (u_side == "foe" and _selection_can_target(u_side, row, idx))
				targetable = u_side == "foe" and _selection_can_target(u_side, row, idx)
			elif row == "front" and String(_atk_sel.get("row", "")) == "support":
				clickable = true                      # 支援线部队前进的落点
		elif unit != null and u_side == "my":
			clickable = _can_pick(row, idx)
	if clickable:
		border = C_SEL if targetable else C_OK
	var p := _mk_panel(Vector2(SLOT_W, SLOT_H), bg, border, 2)
	p.position = pos
	if targetable:
		# e96: 合法目标呼吸高亮 —— 亮暗脉动一眼看出能打谁（tween 绑在槽位自身, 重建时自动销毁）
		var btw := p.create_tween()
		btw.set_loops()
		btw.tween_property(p, "modulate", Color(1.38, 1.38, 1.18, 1.0), 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		btw.tween_property(p, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if unit != null:
		_fill_unit(p, unit as Dictionary)
		p.mouse_entered.connect(func() -> void:
			var current: Dictionary = (unit as Dictionary)["card"].duplicate()
			current["atk"] = int((unit as Dictionary)["atk"])
			current["hp"] = int((unit as Dictionary)["hp"])
			_show_card_preview(current, u_side))
		p.mouse_exited.connect(_hide_card_preview)
		# e92: 任何场上有人的槽都吃鼠标 —— 悬停出提示, 右键照常取消选中
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.tooltip_text = _unit_tip(unit as Dictionary)
		p.mouse_entered.connect(func():
			if _lbl_tactics != null and not _atk_sel.is_empty() and u_side == "foe":
				_lbl_tactics.text = attack_preview({"side": u_side, "row": row, "idx": idx}))
		p.mouse_exited.connect(_refresh_tactics)
		p.gui_input.connect(func(ev: InputEvent) -> void:
			var me := ev as InputEventMouseButton
			if me == null or not me.pressed:
				return
			if me.button_index == MOUSE_BUTTON_RIGHT:
				_clear_sel()
			elif me.button_index == MOUSE_BUTTON_LEFT and clickable:
				_aim_try_begin(side, row, idx)   # e97: 顺手起拖拽瞄准
				_on_slot(side, row, idx))
		if not _can_act(unit as Dictionary):
			p.modulate = Color(0.66, 0.66, 0.70)   # 已行动: 压暗
	elif clickable:
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev: InputEvent) -> void:
			var me := ev as InputEventMouseButton
			if me == null or not me.pressed:
				return
			if me.button_index == MOUSE_BUTTON_RIGHT:
				_clear_sel()
			elif me.button_index == MOUSE_BUTTON_LEFT:
				_aim_try_begin(side, row, idx)   # e97: 空槽起不了瞄准（函数内自会拒绝）
				_on_slot(side, row, idx))
	return p

# e92: 场上部队悬停提示（双方都给全 —— 「对面卡牌效果我方不清楚」的主修法之一）
func _unit_tip(u: Dictionary) -> String:
	var card: Dictionary = u["card"]
	var kw := String(card.get("kw", ""))
	var kwd := ""
	if kw == "cav":
		kwd = "\n骑兵: 上场当回合就能动, 高级骑兵行动免费"
	elif kw == "guard":
		kwd = "\n守护: 左右相邻的友军不受攻击 / 直伤法术伤害"
	elif kw == "ranged":
		kwd = "\n射手: 在支援线也能进攻, 放箭免吃反击"
	var txt := "%s  攻%d 血%d 行动%d%s" % [String(card["name"]),
		int(u["atk"]), int(u["hp"]), int(card.get("act", 1)), kwd]
	if bool(u.get("acted", false)):
		txt += "\n(本回合已行动)"
	return txt

func _fill_unit(p: Control, unit: Dictionary) -> void:
	var card: Dictionary = unit["card"]
	var side := String(unit.get("side", "my"))
	var icon := CardsData.art_icon_of(card, side)
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(2, 2)
		tr.size = Vector2(SLOT_W - 4.0, 56.0)                  # e93: 立绘铺满槽宽, 人物看得清
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
	# e92: 名字条衬底 —— 名字不再直接糊在立绘/槽底上
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.38)
	strip.position = Vector2(2, 58.0)
	strip.size = Vector2(SLOT_W - 4.0, 15)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(strip)
	var nm := _mk_label(String(card["name"]), 11, C_TXT, SLOT_W - 4.0, 14)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.position = Vector2(2, 59.0)
	p.add_child(nm)
	var kw := String(card.get("kw", ""))
	if kw != "":
		# 骑 / 守 / 射 缩到右上角小角标: 骑=低油(金棕) 守=掩护邻居(钢绿) 射=后排可射(蓝)
		var kb := _mk_badge(_kw_badge_txt(kw),
			Vector2(SLOT_W - 24.0, 2), _kw_badge_col(kw))
		kb.get_child(0).add_theme_color_override("font_color", C_GOLD)
		p.add_child(kb)
	p.add_child(_mk_badge(str(int(unit["atk"])), Vector2(4, SLOT_H - 22.0), Color(0.55, 0.16, 0.14)))
	p.add_child(_mk_badge(str(int(unit["hp"])), Vector2(SLOT_W - 26.0, SLOT_H - 22.0), Color(0.14, 0.42, 0.18)))
	# 行动费徽章: 这支部队前进 / 进攻各要付的点数
	p.add_child(_mk_badge("行%d" % int(card.get("act", 1)), Vector2(SLOT_W - 24.0, 22.0), Color(0.36, 0.30, 0.48)))

func _show_card_preview(card: Dictionary, side: String) -> void:
	_hide_card_preview()
	if _fx == null or not _drag.is_empty():
		return
	_card_preview = CardFace.build(card, side, Vector2(184, 300))
	_card_preview.position = Vector2(VW - 194, 104)
	_card_preview.z_index = 50
	_fx.add_child(_card_preview)

func _hide_card_preview() -> void:
	if is_instance_valid(_card_preview):
		_card_preview.queue_free()
	_card_preview = null

func _rebuild_hand() -> void:
	_hide_card_preview()
	for c in _hand_layer.get_children():
		c.queue_free()
	var n := _my_hand.size()
	if n <= 0:
		return
	var step := HAND_W + 6.0
	var total := float(n) * step - 6.0
	if total > 700.0:          # 手牌区收窄: 扇形旋转后两端卡角会外扩, 8 张时刚好让开大营面板与结束按钮
		step = 700.0 / float(n)
		total = float(n) * step
	var x0 := (VW - total) * 0.5
	for i in n:
		_hand_layer.add_child(_make_hand_card(i, Vector2(x0 + float(i) * step, Y_HAND)))

func _make_hand_card(idx: int, pos: Vector2) -> Control:
	var card: Dictionary = _my_hand[idx]
	var cost := int(card["cost"])
	var is_spell := String(card["type"]) == "spell"
	var border := Color(0.55, 0.72, 0.95) if is_spell else Color(0.88, 0.76, 0.5)
	var card_bg := Color(0.10, 0.12, 0.16, 0.96)
	# B3 满阶金卡: 古金框 + 暖底, 跟选中黄和费用不足的暗红拉开
	if bool(card.get("gold", false)) and not is_spell:
		border = Color(0.90, 0.72, 0.28)
		card_bg = Color(0.13, 0.11, 0.065, 0.96)
	if cost > _cost or _over or _ai_busy or _whose != "my":
		border = Color(0.44, 0.34, 0.34)
	var sel := int(_pending.get("hand_idx", -1)) == idx
	if sel:
		border = C_SEL
	# B1 手牌扇形: 轴心设在牌底下方, 离中心越远转得越多并沿弧线下坠; 选中的牌回正上浮
	var off := float(idx) - float(_my_hand.size() - 1) * 0.5
	var arc := off * off * 1.4
	var p := _mk_panel(Vector2(HAND_W, HAND_H), card_bg, border, 2)
	p.pivot_offset = Vector2(HAND_W * 0.5, HAND_H + 30.0)
	p.rotation_degrees = 0.0 if sel else clampf(off * 2.6, -10.0, 10.0)
	p.position = pos + Vector2(0.0, -14.0 if sel else arc)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev: InputEvent) -> void:
		var me := ev as InputEventMouseButton
		if me == null or not me.pressed:
			return
		if me.button_index == MOUSE_BUTTON_RIGHT:
			_clear_sel()
		elif me.button_index == MOUSE_BUTTON_LEFT:
			_drag_begin(idx, p))            # e92: 按下即进入拖拽候选（不动 = 点击, 动了 = 拖）
	# e92: 悬停放大 —— 手牌是牌桌上的主角, 指到哪张哪张浮起来
	p.mouse_entered.connect(func() -> void:
		if _drag.is_empty():
			_show_card_preview(card, "my")
		if _drag.is_empty() and not sel:
			_card_pop(p, 1.10, 0.10))
	p.mouse_exited.connect(func() -> void:
		_hide_card_preview()
		if _drag.is_empty() or _drag.get("p") != p:
			_card_pop(p, 1.0, 0.10))
	var face := CardFace.build(card, "my", Vector2(HAND_W - 4, HAND_H - 4))
	face.position = Vector2(2, 2)
	p.add_child(face)
	p.tooltip_text = String(card.get("desc", "")) if is_spell else _unit_tip({
		"card": card, "atk": int(card["atk"]), "hp": int(card["hp"]), "acted": false})

	return p

# e93: 卡底渐变压字层（名字/攻血/描述的底座, 上透下黑）
func _mk_scrim(r: Rect2) -> Control:
	var tr := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0),
		Color(0.02, 0.02, 0.04, 0.55), Color(0.01, 0.01, 0.03, 0.92)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	tr.texture = gt
	tr.position = r.position
	tr.size = r.size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# e93: 圆章（KARDS 式费用/攻血圆徽, 双色环）
func _mk_coin(txt: String, pos: Vector2, bg: Color, ring: Color) -> Control:
	var d := 24.0
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = ring
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _mk_label(txt, 12, Color(1, 1, 1), d, d)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(0, -2)
	p.add_child(l)
	return p

# 关键词角标的文字与底色（槽位 / 手牌共用）: 骑(低油) 守(守护) 射(后排可射)
func _kw_badge_txt(kw: String) -> String:
	return "骑" if kw == "cav" else ("守" if kw == "guard" else "射")

func _kw_badge_col(kw: String) -> Color:
	if kw == "cav":
		return Color(0.62, 0.46, 0.10)
	return Color(0.16, 0.45, 0.30) if kw == "guard" else Color(0.16, 0.40, 0.52)

# ---------------- 点选攻击 (c6: KARDS 式, 弹菜单已废) ----------------
# 这支部队点下去有没有意义: 没行动过 + 够行动费 + 能前进或能打
func _can_pick(row: String, idx: int) -> bool:
	var arr := _row("my", row)
	if idx < 0 or idx >= arr.size() or arr[idx] == null:
		return false
	var u: Dictionary = arr[idx]
	if String(u["side"]) != "my" or not _can_act(u):
		return false
	var act := int((u["card"] as Dictionary).get("act", 1))
	if _cost < act:
		return false
	if row == "support" and _first_empty(_front, _front_slots) >= 0:
		return true                      # 能前进: 就够格选中（夜袭回合 1 也能挪）
	if _no_atk1 and _turn_no <= 1:
		return false
	if row == "support" and String((u["card"] as Dictionary).get("kw", "")) != "ranged":
		return false                     # 前线满了又打不了: 选了也没事可做
	return not _attack_targets(u).is_empty()

# 当前选中的部队此刻发起得了攻击吗（支援线只有射手, 夜袭回合 1 谁也打不着）
func _sel_can_hit() -> bool:
	if _atk_sel.is_empty():
		return false
	var arr := _row("my", String(_atk_sel["row"]))
	var i := int(_atk_sel["idx"])
	if i < 0 or i >= arr.size() or arr[i] == null:
		return false
	var u: Dictionary = arr[i]
	if _no_atk1 and _turn_no <= 1:
		return false
	if String(_atk_sel["row"]) == "support" \
			and String((u["card"] as Dictionary).get("kw", "")) != "ranged":
		return false
	return not _attack_targets(u).is_empty()

# 攻击模式下点顶部敌情条 = 直击大营（敌前线没有他们的部队才合法）
func _on_bar_click(ev: InputEvent) -> void:
	var me := ev as InputEventMouseButton
	if me == null or not me.pressed or me.button_index != MOUSE_BUTTON_LEFT:
		return
	if _atk_sel.is_empty() or _over or _ai_busy or _whose != "my":
		return
	var from: Dictionary = _atk_sel
	var arr := _row("my", String(from["row"]))
	var fi := int(from["idx"])
	if fi >= arr.size() or arr[fi] == null:
		return
	for t: Dictionary in _attack_targets(arr[fi]):
		if t.get("kind", "") == "camp":
			if _do_attack("my", String(from["row"]), fi, t):
				_refresh_all()
				_check_over()
			return

# ---------------- 通用控件 ----------------
func _mk_label(txt: String, size: int, col: Color, w: float, h: float) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", FONT_PIX)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.size = Vector2(w, h)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _mk_badge(txt: String, pos: Vector2, col: Color) -> Control:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = Vector2(22, 18)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _mk_label(txt, 12, Color(1, 1, 1), 22.0, 18.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 0)
	p.add_child(l)
	return p

func _mk_panel(size: Vector2, bg: Color, border: Color, bw: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _mk_button(txt: String, w: float) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_override("font", FONT_PIX)
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(w, 28)
	return b

# B4 大营旗: 旗杆 + 燕尾旗面（cutscene_base._flag_prop 同款语言）, 旗面 scale.x 循环微摆模拟风
func _make_flag(parent: Control, pos: Vector2, h: float, cloth: Color) -> void:
	var box := Node2D.new()
	box.position = pos
	var pole := Polygon2D.new()
	pole.polygon = PackedVector2Array([
		Vector2(-1.5, 0.0), Vector2(1.5, 0.0), Vector2(1.5, -h), Vector2(-1.5, -h)])
	pole.color = Color(0.26, 0.21, 0.16)
	box.add_child(pole)
	var face := Polygon2D.new()
	face.polygon = PackedVector2Array([
		Vector2(1.5, -h), Vector2(h * 0.62, -h + 5.0),
		Vector2(h * 0.58, -h + h * 0.44), Vector2(1.5, -h + h * 0.52)])
	face.color = cloth
	box.add_child(face)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(face, "scale:x", 0.88, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(face, "scale:x", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	parent.add_child(box)

# B5 五角星多边形（结算星级用, 程序化画星不依赖字体字形）
func _star_poly(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var ang := -PI * 0.5 + float(k) * PI * 0.2
		pts.append(Vector2(cos(ang), sin(ang)) * (r if k % 2 == 0 else r * 0.45))
	return pts

func _flash(msg: String) -> void:
	if _lbl_hint == null:
		return
	_lbl_hint.text = msg
	_lbl_hint.modulate = Color(1, 1, 1, 1)
	if _hint_tw != null and _hint_tw.is_valid():
		_hint_tw.kill()
	_hint_tw = create_tween()
	_hint_tw.tween_interval(2.2)
	_hint_tw.tween_property(_lbl_hint, "modulate:a", 0.8, 1.0)

# ---------------- 出牌历史 ----------------
# 左侧抽屉: 收起时只露一个「史」标签, 点开滑出; 敌军出牌另有小卡飞到左侧停留的演出
func _build_hist_drawer() -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.10, 0.94)
	sb.border_color = Color(0.45, 0.38, 0.30)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(-166.0, 64.0)
	p.size = Vector2(200.0, 378.0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(p)
	_hist_drawer = p
	var ttl := _mk_label("出牌历史", 13, C_GOLD, 150.0, 20)
	ttl.position = Vector2(10, 8)
	p.add_child(ttl)
	_hist_list = VBoxContainer.new()
	_hist_list.position = Vector2(10, 34)
	_hist_list.size = Vector2(180, 336)
	_hist_list.add_theme_constant_override("separation", 1)
	_hist_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_hist_list)
	var tab := _mk_button("史", 30.0)
	tab.position = Vector2(164.0, 6.0)
	tab.size = Vector2(30.0, 26.0)
	tab.tooltip_text = "出牌历史"
	tab.pressed.connect(_toggle_hist)
	p.add_child(tab)
	_refresh_hist()

func _toggle_hist() -> void:
	_hist_open = not _hist_open
	Audio.play_sfx("ui_click", -8.0)
	_refresh_hist()
	if _hist_drawer == null:
		return
	var tw := create_tween()
	tw.tween_property(_hist_drawer, "position:x", (0.0 if _hist_open else -166.0), 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# 谁出了什么牌: 敌我双记, 抽屉里最新在上（最多留 60 条）
func _log_play(caster: String, card: Dictionary) -> void:
	_play_log.append({"turn": _turn_no, "side": caster,
		"name": String(card.get("name", "?")), "cost": int(card.get("cost", 0))})
	if _play_log.size() > 60:
		_play_log.pop_front()          # 老记录让位
	if _hist_open:
		_refresh_hist()

func _refresh_hist() -> void:
	if _hist_list == null:
		return
	for c: Node in _hist_list.get_children():
		_hist_list.remove_child(c)
		c.queue_free()
	var n: int = _play_log.size()
	for k: int in range(n - 1, maxi(-1, n - 17), -1):
		var e: Dictionary = _play_log[k]
		var mine := String(e["side"]) == "my"
		var l := _mk_label("T%d %s %s %d费" % [int(e["turn"]), "我" if mine else "敌",
			e["name"], int(e["cost"])],
			11, Color(0.62, 0.78, 1.0) if mine else Color(1.0, 0.66, 0.60), 180.0, 18.0)
		_hist_list.add_child(l)

# 敌军出牌演出（e92 加料版）: 带立绘/关键词/效果描述的大一点的卡, 从右上（敌军手牌方向）
# 滑到左侧停一拍让人看清「对面到底打了什么」, 再甩出屏幕左缘
func _fx_foe_card(card: Dictionary) -> void:
	if _fx == null:
		return
	var W := 132.0
	var H := 190.0
	var p := _mk_panel(Vector2(W, H), Color(0.13, 0.10, 0.09, 0.97), C_FOE, 2)
	var y1 := 180.0 + float(_foe_fx_n % 3) * 40.0
	_foe_fx_n += 1
	p.position = Vector2(VW - 150.0, 70.0)
	p.pivot_offset = Vector2(W * 0.5, H * 0.5)
	p.scale = Vector2(0.7, 0.7)
	# 顶标: 红底白字「敌方打出」—— 不看历史也知道这卡是谁的
	var hd := _mk_panel(Vector2(W, 18.0), Color(0.45, 0.14, 0.11, 0.95), Color(0, 0, 0, 0), 0)
	p.add_child(hd)
	var hl := _mk_label("敌 方 打 出", 10, Color(1.0, 0.82, 0.78), W, 18.0)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd.add_child(hl)
	var face := CardFace.build(card, "foe", Vector2(W - 4, H - 22))
	face.position = Vector2(2, 20)
	p.add_child(face)

	_fx.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "position", Vector2(20.0, y1), 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)                    # e92: 停留加长, 来得及读完效果
	tw.tween_property(p, "position:x", -160.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.28).set_delay(0.06)
	tw.tween_callback(p.queue_free)

# ---------------- 演出 ----------------
# 全部走 _fx 覆盖层（_stage 的最后一个孩子）: 逻辑照旧同步跑, 这里只挂非阻塞 tween。
# 不能直接给槽位节点做动画 —— _refresh_all() -> _rebuild_field() 每次都 queue_free 重建它们。
#
# 一行有几个槽: 前线受词条限制（接舷战只有 3 个）, 支援线固定 4
func _row_slots(row: String) -> int:
	return _front_slots if row == "front" else 4

# n 个槽的总宽 / 整行居中的起始 x（少于 4 槽时整行居中）
func _row_w(n: int) -> float:
	return float(n) * SLOT_W + float(maxi(0, n - 1)) * SLOT_GAP

func _row_x(n: int) -> float:
	return (VW - _row_w(n)) * 0.5

func _slot_pos(side: String, row: String, idx: int) -> Vector2:
	var n := _row_slots(row)
	return Vector2(_row_x(n) + float(idx) * (SLOT_W + SLOT_GAP), _row_y(side, row))

# 飘字: 战场某处冒出一行字, 上飘 + 淡出
func _float_text(txt: String, at: Vector2, col: Color, fsize: int) -> void:
	if _fx == null:
		return
	var l := _mk_label(txt, fsize, col, 160.0, 22)
	l.clip_text = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = at - Vector2(80.0, 30.0)
	l.pivot_offset = Vector2(80.0, 11.0)
	l.scale = Vector2(1.6, 1.6)               # e92: 先弹后收, 数字砸在脸上
	_fx.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 26.0, 0.74) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.55).set_delay(0.35)
	tw.tween_callback(l.queue_free)

# e92: 击杀碎裂 —— 木牌打散成几片小木屑, 抛物线飞散旋转淡出
func _shatter(at: Vector2, col: Color) -> void:
	if _fx == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for k in 7:
		var r := ColorRect.new()
		r.color = Color(col.r, col.g, col.b, 0.92)
		r.size = Vector2(4 + rng.randi() % 4, 3 + rng.randi() % 4)
		r.position = at - r.size * 0.5
		r.rotation = rng.randf() * TAU
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(r)
		var dir := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.3, -0.2)) \
			* rng.randf_range(42.0, 92.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(r, "position", r.position + dir + Vector2(0, 46.0), 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "rotation", r.rotation + rng.randf_range(-3.0, 3.0), 0.55)
		tw.tween_property(r, "modulate:a", 0.0, 0.40).set_delay(0.15)
		tw.chain().tween_callback(r.queue_free)

# e92: 部署落场 —— 槽位上一圈金环绽开（部队从「手里」落到「桌上」的分量感）
func _deploy_ring(at: Vector2) -> void:
	if _fx == null:
		return
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.86, 0.45, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(SLOT_W, SLOT_H)
	p.position = at - p.size * 0.5
	p.pivot_offset = p.size * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(p)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(p, "scale", Vector2(1.28, 1.28), 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 0.0, 0.32)
	tw.chain().tween_callback(p.queue_free)

func _slot_flash(at: Vector2) -> void:
	if _fx == null:
		return
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.35)
	r.position = at - Vector2(SLOT_W * 0.5, SLOT_H * 0.5)
	r.size = Vector2(SLOT_W, SLOT_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 0.0, 0.4)
	tw.tween_callback(r.queue_free)

func _screen_flash(col: Color) -> void:
	if _fx == null:
		return
	var r := ColorRect.new()
	r.color = col
	r.size = Vector2(VW, VH)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = Color(1, 1, 1, 0)
	_fx.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 1.0, 0.10)
	tw.tween_property(r, "modulate:a", 0.0, 0.5)
	tw.tween_callback(r.queue_free)

# 攻击飞出去的那一下: 一条柔光拖尾顺着弹道滑向目标
func _dash(from: Vector2, to: Vector2, side: String) -> void:
	if _fx == null:
		return
	var col := C_MY if side == "my" else C_FOE
	var d := ColorRect.new()
	d.color = Color(col.r, col.g, col.b, 0.75)
	d.size = Vector2(18, 5)
	d.pivot_offset = Vector2(9, 2.5)
	d.rotation = (to - from).angle()
	d.position = from - d.pivot_offset
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(d)
	var tw := create_tween()
	tw.tween_property(d, "position", to - d.pivot_offset, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(d, "modulate:a", 0.0, 0.18)
	tw.tween_callback(d.queue_free)

# e96: 受击后仰 —— 目标槽位框向攻击来向弹开再弹回（fx 层画框, 不动真实槽位）
func _recoil(at: Vector2, dir: Vector2) -> void:
	if _fx == null:
		return
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.0)
	sb.border_color = Color(1.0, 0.5, 0.35, 0.7)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(SLOT_W, SLOT_H)
	p.position = at - p.size * 0.5
	p.pivot_offset = p.size * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(p)
	var off := dir.normalized() * 7.0 if dir.length() > 0.1 else Vector2(0, 7)
	var tw := create_tween()
	tw.tween_property(p, "position", p.position + off, 0.05)
	tw.tween_property(p, "position", at - p.size * 0.5, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 0.0, 0.1)
	tw.tween_callback(p.queue_free)

# 大营挨打: 全屏闪 + 震屏 + 飘字（我方大营还要抖血条）
func _camp_hit_fx(enemy: String, atk: int) -> void:
	var col := C_FOE if enemy == "foe" else Color(0.95, 0.50, 0.35)
	_screen_flash(Color(col.r, col.g, col.b, 0.14))
	_shake(2.5)
	if enemy == "my":
		_bar_shake()
	var at := Vector2(VW * 0.5, Y_MID + 4.0) if enemy == "foe" else Vector2(VW * 0.5, Y_MID + 30.0)
	_float_text("-%d" % atk, at, FxPalette.HURT, 20)
	FxPalette.speed_lines(_fx, at)   # P5: 大营挨打也来一束辐射线
	Audio.play_sfx("thunder", -14.0, 0.85)

# 震屏: 整个战场抖一下（大营挨打等重击场面用）
func _shake(amp: float) -> void:
	if _stage == null:
		return
	var x0 := _stage.position.x
	var y0 := _stage.position.y
	var tw := create_tween()
	for i in 4:
		var dx := amp if i % 2 == 0 else -amp
		tw.tween_property(_stage, "position", Vector2(x0 + dx, y0 + amp * 0.6), 0.045)
	tw.tween_property(_stage, "position", Vector2(x0, y0), 0.05)

func _bar_shake() -> void:
	if _bar_camp == null:
		return
	var x0 := _bar_camp.position.x
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_bar_camp, "position:x", x0 + (3.0 if i % 2 == 0 else -3.0), 0.045)
	tw.tween_property(_bar_camp, "position:x", x0, 0.05)

# 回合 / 词条横幅: 从中央滑入, 停一会儿再淡出
func _show_banner(title: String, sub: String) -> void:
	if _fx == null:
		return
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(0, VH * 0.5 - 52.0)
	box.size = Vector2(VW, 104.0)
	box.modulate = Color(1, 1, 1, 0)
	_fx.add_child(box)
	var strip := ColorRect.new()
	strip.color = Color(0.04, 0.04, 0.06, 0.82)
	strip.size = Vector2(VW, 104.0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(strip)
	var line1 := ColorRect.new()
	line1.color = C_GOLD
	line1.position = Vector2(VW * 0.5 - 220.0, 0)
	line1.size = Vector2(440, 2)
	line1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line1)
	var line2 := line1.duplicate() as ColorRect
	line2.position = Vector2(VW * 0.5 - 220.0, 102.0)
	box.add_child(line2)
	var t := _mk_label(title, 30, C_GOLD, VW, 42.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 6)
	t.position = Vector2(0, 12)
	box.add_child(t)
	var s := _mk_label(sub, 13, Color(0.88, 0.86, 0.78), VW, 22.0)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.clip_text = false
	s.position = Vector2(0, 62)
	box.add_child(s)
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(box, "position:y", box.position.y + 8.0, 0.18)
	tw.tween_interval(1.5)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)

func _on_retreat() -> void:
	if _closing:
		return
	if _retreat_dialog != null:
		_retreat_dialog.popup_centered(Vector2i(420, 160))
		return
	_commit_retreat()

func _commit_retreat() -> void:
	if _closing:
		return
	_closing = true
	# C1 iris 收场: 先收黑, mid 回调切场景
	var mid := func() -> void: Voyage.end_battle("retreat")
	IrisWipe.play("out", mid)

# ---------------- 结算 ----------------
func _settle(result: String) -> void:
	if _over:
		if _settle_hud != null:
			return
	_over = true
	_ai_busy = false
	_settle_result = result
	_settle_armed = false
	_closing = true                     # 结算后 AI 协程不再往下走
	Voyage.set_battle_slow(false)
	if result == "victory":
		_compute_rewards()
	_refresh_all()
	_show_settlement(result)

# 战果与旧战场（battle_map）同量级、同一套契约/声望/里程碑规则
func _compute_rewards() -> void:
	_st_exp = 30 + Legion.level * 6 + 12 * _killed
	_st_coin = int(round(float(30 + Legion.level * 10 + 10 * _killed) * Research.battle_coin_mult() * Marriage.perk_mult("voyage")))
	if is_siege:
		_st_coin += Nations.on_siege_victory(String(party["siege"]))
	var ptype := String(party.get("type", ""))
	_st_prest = Nations.PRESTIGE_SIEGE if is_siege \
		else (Nations.PRESTIGE_PATROL if ptype == "巡逻" else Nations.PRESTIGE_BANDIT)
	if Nations.contract != "":
		var foe_nid := String(party.get("nation", ""))
		var is_bandit := ptype == "山贼" or ptype == "海寇" or ptype == "哥布林" or ptype == "魔物"
		var is_foe_of_liege := foe_nid != "" and foe_nid != Nations.liege \
			and (Nations.at_war_with(foe_nid) or Nations.favor_of(foe_nid) < 20)
		if is_bandit:
			_st_coin = int(round(float(_st_coin) * 1.5))
			_st_prest += 1
		elif is_foe_of_liege:
			_st_coin *= 2
			_st_prest += 2
	Legion.gain_exp(_st_exp)
	Nations.add_prestige(_st_prest)
	Wallet.add_money(_st_coin)
	if ptype == "海寇" or ptype == "巡逻":
		Quests.note_navy_win()
		Quests.complete("navy_first")

func _show_settlement(result: String) -> void:
	Audio.set_scene_bgm("settle")
	var hud := CanvasLayer.new()
	hud.name = "SettleHUD"
	_settle_hud = hud
	add_child(hud)
	hud.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(dim)
	var rows: Array = []
	var dead_cnt := 0                  # B5: 出征阵亡数（评星用）
	rows.append(["我方大营", _my_camp, maxi(1, _my_camp_max)])
	rows.append(["敌方大营", _foe_camp, maxi(1, _foe_camp_max)])
	rows.append(["主角", Legion.player_hp, Legion.player_max_hp()])
	for idx: Variant in Slaves.expedition:
		var s: Dictionary = Slaves.slave_at(int(idx))
		if s.is_empty():
			continue
		if int(s.get("hp", 0)) <= 0:
			dead_cnt += 1
		rows.append(["%s(%s)" % [String(s.get("name", "?")), String(s.get("troop", "刀客"))],
			int(s.get("hp", 0)), int(s.get("max_hp", 30))])
	var pw := 392.0
	var ph := 116.0 + float(rows.size()) * 24.0
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.95)
	sb.border_color = Color(0.85, 0.72, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = Vector2(VW * 0.5 - pw * 0.5, VH * 0.5 - ph * 0.5)
	panel.size = Vector2(pw, ph)
	hud.add_child(panel)
	var win := result == "victory"
	var title := _mk_label("胜 利!" if win else "败 北", 18, C_GOLD if win else Color(0.8, 0.45, 0.4), pw, 24.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 5)
	title.position = Vector2(0, 12)
	panel.add_child(title)
	# B5 结算星级: 大营血量七成以上 / 击破三队以上 / 出征无人阵亡, 三条占几条算几星（胜保底一星）
	var stars := 0
	if win:
		var cond := 0
		if float(_my_camp) / float(maxi(1, _my_camp_max)) >= 0.7:
			cond += 1
		if _killed >= 3:
			cond += 1
		if dead_cnt == 0:
			cond += 1
		stars = 3 if cond >= 3 else (2 if cond == 2 else 1)
	for k in 3:
		var st := Polygon2D.new()
		st.polygon = _star_poly(11.0)
		st.color = C_GOLD if k < stars else Color(0.26, 0.24, 0.20)
		st.position = Vector2(pw * 0.5 + (float(k) - 1.0) * 34.0, 50.0)
		if stars > 0:
			st.scale = Vector2.ZERO      # 得星逐颗弹出, 败北三颗暗星直接摆好
			var stw := create_tween()
			stw.tween_interval(0.85 + float(k) * 0.16)
			stw.tween_property(st, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		panel.add_child(st)
	var y := 64.0
	for r: Array in rows:
		_settle_row(panel, String(r[0]), int(r[1]), int(r[2]), y)
		y += 24.0
	var gains := _mk_label("", 13, Color(1, 0.88, 0.5) if win else Color(0.75, 0.72, 0.66), pw, 20.0)
	gains.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gains.position = Vector2(0, y)
	panel.add_child(gains)
	if win:
		_gains_roll(gains)              # 数字从 0 滚到实际收益
	else:
		gains.text = "金币 +0   声望 +0   经验 +0"
	var cont := _mk_button("继续", 120.0)
	cont.position = Vector2(pw * 0.5 - 60.0, ph - 32.0)
	cont.pressed.connect(_close_settlement)
	panel.add_child(cont)
	for eater: Control in [panel, dim]:
		eater.gui_input.connect(func(ev: InputEvent) -> void:
			var me := ev as InputEventMouseButton
			if me != null and me.pressed and _settle_armed:
				_close_settlement())
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_callback(func() -> void:
		if _settle_hud != null:
			_settle_hud.visible = true
			_settle_armed = true)

# 结算收益数字滚动: 面板弹出后从 0 一路滚到实得（看着比直接蹦数字有质感）
func _gains_roll(l: Label) -> void:
	var tw := create_tween()
	tw.tween_interval(0.75)
	tw.tween_method(func(t: float) -> void:
		l.text = "金币 +%d   声望 +%d   经验 +%d" % [
			int(round(float(_st_coin) * t)), int(round(float(_st_prest) * t)),
			int(round(float(_st_exp) * t))], 0.0, 1.0, 0.6)
	tw.tween_callback(func() -> void:
		l.text = "金币 +%d   声望 +%d   经验 +%d" % [_st_coin, _st_prest, _st_exp])

func _settle_row(parent: Control, disp: String, hp: int, mhp: int, y: float) -> void:
	var nm := _mk_label(disp, 12, Color(0.92, 0.88, 0.8), 130.0, 16.0)
	nm.position = Vector2(20, y)
	parent.add_child(nm)
	var ratio := clampf(float(maxi(hp, 0)) / float(maxi(1, mhp)), 0.0, 1.0)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.position = Vector2(156, y + 3)
	bar.size = Vector2(120, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	var fill := ColorRect.new()
	fill.color = Color(0.36, 0.78, 0.31) if ratio >= 0.5 \
		else (Color(0.9, 0.75, 0.2) if ratio >= 0.25 else Color(0.82, 0.25, 0.2))
	fill.size = Vector2(120.0 * ratio, 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var txt := _mk_label("%d/%d  %d%%" % [maxi(hp, 0), maxi(1, mhp), int(round(ratio * 100.0))],
		12, Color(0.85, 0.85, 0.75), 92.0, 16.0)
	txt.position = Vector2(284, y)
	parent.add_child(txt)

func _close_settlement() -> void:
	if _settle_hud == null:
		return
	_settle_hud.queue_free()
	_settle_hud = null
	# C1 iris 收场: 先收黑, mid 回调切场景, 再展开亮出世界地图
	var mid2 := func() -> void: Voyage.end_battle(_settle_result)
	IrisWipe.play("out", mid2)
