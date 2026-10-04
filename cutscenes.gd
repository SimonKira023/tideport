# cutscenes.gd —— Autoload, 名字: Cutscenes (e42)
#
# 剧情过场放映机: 序章之外的那几段「推动剧情」的过场, 都挂在这个常驻节点上。
# 它是 cutscene_base.gd 的子类, 所以自带整套布景工具箱 (天幕/星野/云/海/光晕/粒子/
# 剪影/暗角/闪白/震屏) 和幕驱动 (字幕/推进/跳过/finished)。
#
# 四个对外入口:
#   · play(id, delay, ctx)      —— 放一段 (忙就排队, 绝不丢)。给探针/自检用。
#   · play_once(id, delay, ctx) —— 剧情钩子专用: 不在 ACTS 里的 id 直接忽略, 放过的也不再放。
#                             自检/探针 (SaveManager.enabled == false) 一律不播。
#                             ctx 是本段的上下文 (国名/旗色/城名), 布景方法从 _ctx 里读;
#                             ctx["seen"] 是「不重播」的细分键 —— 同一段过场每个国家各放一次。
#   · playing()                 —— 有没有在放。
#   · seen_list / apply_seen / reset_for_new_game —— 给存档用 (_seen 进档, 不重播)。
#
# 当前十段 (id 就是里程碑/事件的 id, 钩子那边一行调用就接上了):
#   · harbor       码头落成, 潮风号下水      <- Voyage.build_boat() 造出第一条船
#   · ms_navy      出海首胜                  <- world_map 打赢第一场海战之后
#   · siege_first  攻下第一座城              <- 首城命名弹窗点「就这名了」之后
#   · ms_lord      裂土封王                  <- Nations.sign_contract() 签下封臣
#   · ms_unify     四海归一 (终章)            <- Quests 里程碑 ms_unify 达成
#   · goblin_rod   河边偶遇 (e43)             <- 第二天出门撞见哥布林钓鱼 (scene/house.gd)
#   · nat_pact     会盟 / 通商之约 (e43)      <- Nations.sign_pact() 商盟
#   · nat_ally     盟约 / 守望相助 (e43)      <- Nations.sign_pact() 盟约
#   · nat_war      宣战 / 递出战书 (e43)      <- Nations.declare_war()
#   · nat_lost     失城 / 城头易帜 (e43)      <- Nations.player_town_lost()
#
# ❗冻结分工: 这里只管自己 (TimeManager.time_running) 和覆盖层输入;
#   玩家的冻结由 game.gd 接 started/finished 信号去 _set_player_frozen()。
extends "res://scene/cutscene_base.gd"

const ACTS := {
	"harbor": {
		"title": "潮汐港", "sub": "码头落成",
		"steps": [
			["潮汐港的码头落成了. 木桩打进礁石, 栈桥一寸一寸探进海里.", "_harbor_1"],
			["新船顺着滚木滑进水里, 桅杆竖起来那一刻, 东南风正好吹到脸上.", "_harbor_2"],
			["你给它取名潮风号. 从今往后, 岛上的人可以往更远的地方走了.", "_harbor_3"],
		],
	},
	"ms_navy": {
		"title": "初战", "sub": "海上首胜",
		"steps": [
			["海寇的船比你的大, 帆比你的黑, 逆着风也能咬住你.", "_navy_1"],
			["伙伴握紧了缆绳, 谁都没说话. 你把手按在了刀柄上.", "_navy_2"],
			["一炷香之后, 海面上只剩一条还浮着的船. 那是你的船.", "_navy_3"],
		],
	},
	"siege_first": {
		"title": "城破", "sub": "旗色易主",
		"steps": [
			["城门在撞木下裂开的时候, 天刚蒙蒙亮.", "_siege_1"],
			["旧主的旗被放下来, 折好, 收进箱子底.", "_siege_2"],
			["你的旗升上去. 城头上的风忽然变得很响, 吹得旗面整面都展开了.", "_siege_3"],
		],
	},
	"ms_lord": {
		"title": "封王", "sub": "裂土之盟",
		"steps": [
			["契约摊在案上, 最后一行字上压着火漆.", "_lord_1"],
			["从今天起, 这片地姓你的姓, 这些人喊你主公.", "_lord_2"],
			["你还没习惯这个称呼, 但海图上那一片颜色, 已经换了.", "_lord_3"],
		],
	},
	"ms_unify": {
		"title": "终章", "sub": "四海归一",
		"steps": [
			["五座王都, 最后一面旗也落了下去.", "_unify_1"],
			["海图上的颜色, 如今只剩一种.", "_unify_2"],
			["风从东南来, 吹过整片海. 这里是你的潮汐港.", "_unify_3"],
		],
	},
	# e43: 哥布林钓鱼 —— 第二天出门撞见他在河边, 聊完才把鱼竿摆上摊子
	"goblin_rod": {
		"title": "鱼竿", "sub": "河边偶遇",
		"steps": [
			["第二天早上出门, 屋前静悄悄的. 河边蹲着个熟悉的身影, 一动也不动.", "_goblin_1"],
			["他手里居然握着根鱼竿. 竿梢猛地一沉, 那家伙蹦得比鱼还高.", "_goblin_2"],
			["他挠挠头: 被你看穿了. 想学? 鱼竿明天就给你摆上摊子.", "_goblin_3"],
		],
	},
	# —— e43 四段国家级过场 ——
	# dyn: 幕表由 _*_steps() 现拼 (国名/旗色/城名进台词); 静态那份是兜底, 也是自检扫字形的那份
	"nat_pact": {
		"title": "会盟", "sub": "通商之约", "dyn": "_pact_steps",
		"steps": [
			["商旗挂上栈桥, 货箱一只只卸下来.", "_pact_1"],
			["账房拨了一夜的算盘, 两边终于把数目对上了.", "_pact_2"],
			["从今往后, 你的货可以挂着商旗走南闯北.", "_pact_3"],
		],
	},
	"nat_ally": {
		"title": "盟约", "sub": "守望相助", "dyn": "_ally_steps",
		"steps": [
			["血酒摆在案上, 两边按着同一张契.", "_ally_1"],
			["海面上, 两国的船并排巡了一整夜.", "_ally_2"],
			["往后你有难, 他们会来; 他们有事, 你也得去.", "_ally_3"],
		],
	},
	"nat_war": {
		"title": "宣战", "sub": "递出战书", "dyn": "_war_steps",
		"steps": [
			["使者捧着战书进殿, 火漆在灯下红得刺眼.", "_war_1"],
			["他们的旗被取下来, 扔在阶前.", "_war_2"],
			["海图上那一角亮起血色. 从今天起, 那边不再是邻居.", "_war_3"],
		],
	},
	"nat_lost": {
		"title": "失城", "sub": "城头易帜", "dyn": "_lost_steps",
		"steps": [
			["消息是半夜到的: 城头打了一整天, 天没黑就断了箭.", "_lost_1"],
			["你的旗被扯下来, 踩进泥里.", "_lost_2"],
			["他们的旗升上去. 那座城, 不再向你交税.", "_lost_3"],
		],
	},
}

# 天幕配色 (跟序章一套口径)
const NIGHT_TOP := Color(0.03, 0.05, 0.12)
const NIGHT_BOT := Color(0.10, 0.14, 0.24)
const GOLD_TOP := Color(0.26, 0.28, 0.42)
const GOLD_BOT := Color(0.90, 0.70, 0.48)
const DUSK_TOP := Color(0.08, 0.07, 0.10)
const DUSK_BOT := Color(0.34, 0.20, 0.16)
const HALL_TOP := Color(0.09, 0.06, 0.08)
const HALL_BOT := Color(0.24, 0.14, 0.11)

var _active := ""                 # 正在放的 id (空 = 空闲)
var _queue: Array = []            # 等着放的 [{"id":..., "ctx":{}}]
var _seen := {}                   # 放过的 key -> true (进存档; key 可能带 @国名 的细分尾)
var _was_time_running := true     # 播片前的时间开关, 播完还回去
var _navy_foe: Node2D = null      # 初战那段的敌船 (1 幕造好, 2/3 幕接着用)
var _ctx := {}                    # 本段的上下文 (国名/旗色/城名), 布景方法从这里读
var _gob_fig: Node2D = null       # 哥布林钓鱼那段的人 (1 幕造好, 2/3 幕接着用)
var _gob_tip: Node2D = null       # 竿梢 (咬钩时抖一下)
var _gob_float: Node2D = null     # 浮子 (咬钩时往下沉)
var _crates: Array = []           # 会盟那段卸下来的货箱 (2 幕要一只只抬走)

func _ready() -> void:
	auto_run = false              # 常驻节点: 开局不自动放片
	free_on_finish = false        # 播完只隐藏, 不能自杀
	super._ready()

# ---------------- 对外入口 ----------------
func has_act(id: String) -> bool:
	return ACTS.has(id)

func playing() -> bool:
	return _active != "" or not _queue.is_empty()

func seen_list() -> Array:
	return _seen.keys()

func apply_seen(arr: Array) -> void:
	_seen.clear()
	for k in arr:
		_seen[String(k)] = true

func reset_for_new_game() -> void:
	_seen.clear()
	_queue.clear()
	_ctx = {}
	_active = ""

# 放一段。忙就排队, 绝不丢。ctx 是本段的上下文 (布景方法从 _ctx 里读国名/旗色)。
func play(id: String, delay := 0.0, ctx := {}) -> bool:
	if not has_act(id):
		return false
	if _active != "":
		for q in _queue:
			if String(q["id"]) == id:
				return true
		_queue.append({"id": id, "ctx": ctx})
		return true
	_begin(id, delay, ctx)
	return true

# 剧情钩子专用: 没有这段过场就当没这回事, 放过的也不再放。
# ❗SaveManager.enabled == false (自检/探针) 时不播 —— 别让测试干等二十秒。
# ctx["seen"] 有值时, 「放过没」按 id@尾 记 —— 会盟那种一段多放几次的过场就靠它。
func play_once(id: String, delay := 0.0, ctx := {}) -> bool:
	if not SaveManager.enabled:
		return false
	if not has_act(id):
		return false
	var key := id
	var tag := String(ctx.get("seen", ""))
	if tag != "":
		key = "%s@%s" % [id, tag]
	if bool(_seen.get(key, false)):
		return false
	_seen[key] = true             # 先记下: 免得同一段被排两遍
	return play(id, delay, ctx)

# 放片主流程 (含排队收尾)
func _begin(id: String, delay: float, ctx := {}) -> void:
	_active = id
	_ctx = ctx
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if _active != id:
			return                # 期间被 reset_for_new_game 清掉了
	_was_time_running = TimeManager.time_running
	TimeManager.time_running = false
	start_steps(_steps_for(id))
	await finished
	TimeManager.time_running = _was_time_running
	var next: Dictionary = {}
	if not _queue.is_empty():
		next = _queue.pop_front()
	_active = ""
	if not next.is_empty():
		await get_tree().create_timer(0.2).timeout
		_begin(String(next["id"]), 0.0, next.get("ctx", {}))

# 幕表: 标了 dyn 的段落按当下 ctx 现拼一份 (国名/城名进台词), 否则用静态那份
func _steps_for(id: String) -> Array:
	var act: Dictionary = ACTS[id]
	var dk := String(act.get("dyn", ""))
	if dk != "" and has_method(dk):
		return call(dk)
	return act["steps"]

# ---------------- 通用起手 ----------------
# 标题卡 + 换天 + 铺海 + 压暗角, 四段共用
func _open(title: String, sub: String, top: Color, bot: Color, horizon := 0.62) -> void:
	title_card(title, sub)
	sky_to(top, bot, 1.6)
	sea_on(horizon, 1.0, 1.6)
	vignette_on(0.45, 1.4)

# 一条帆船剪影 (跟序章的孤舟同款, 换色用): 返回节点, 调用方自己摆 x/y
func _boat_prop(x_frac: float, y_frac: float, s: float, hull_c: Color, sail_c: Color) -> Node2D:
	var v := _vw()
	var box := Node2D.new()
	box.position = Vector2(x_frac * v.x, y_frac * v.y)
	box.scale = Vector2(s, s)
	var hull := Polygon2D.new()
	hull.polygon = PackedVector2Array([
		Vector2(-26, 0), Vector2(26, 0), Vector2(17, 11), Vector2(-17, 11)])
	hull.color = hull_c
	box.add_child(hull)
	var rail := Polygon2D.new()
	rail.polygon = PackedVector2Array([
		Vector2(-26, 0), Vector2(26, 0), Vector2(26, 2), Vector2(-26, 2)])
	rail.color = hull_c.lightened(0.22)
	box.add_child(rail)
	var mast := Polygon2D.new()
	mast.polygon = PackedVector2Array([
		Vector2(-1.6, -30), Vector2(1.6, -30), Vector2(1.6, 0), Vector2(-1.6, 0)])
	mast.color = Color(0.26, 0.19, 0.13)
	box.add_child(mast)
	var sail := Polygon2D.new()
	sail.polygon = PackedVector2Array([
		Vector2(2, -28), Vector2(2, -3), Vector2(23, -6)])
	sail.color = sail_c
	box.add_child(sail)
	var jib := Polygon2D.new()
	jib.polygon = PackedVector2Array([
		Vector2(-2, -22), Vector2(-2, -4), Vector2(-15, -6)])
	jib.color = sail_c.darkened(0.10)
	box.add_child(jib)
	_add_prop(box)
	return box

# ---------------- 一: 码头落成, 潮风号下水 ----------------
func _harbor_1() -> void:
	_open("潮汐港", "码头落成", NIGHT_TOP, GOLD_BOT, 0.58)
	stars_on(0.0, 0.2)
	clouds_on(0.55, 1.6)
	glow_at(Vector2(0.20, 0.30), Color(1.0, 0.90, 0.70), 360.0, 0.55, 1.6)
	# 远山 + 一条伸进海里的栈桥
	_ridge([[0.0, 0.05], [0.12, 0.11], [0.24, 0.04], [0.34, 0.09], [0.46, 0.03],
		[0.58, 0.08], [0.70, 0.03], [0.84, 0.10], [1.0, 0.05]],
		0.66, Color(0.20, 0.22, 0.26, 0.85))
	var v := _vw()
	var pier := Polygon2D.new()
	pier.polygon = PackedVector2Array([
		Vector2(0.30 * v.x, 0.70 * v.y), Vector2(0.78 * v.x, 0.74 * v.y),
		Vector2(0.78 * v.x, 0.77 * v.y), Vector2(0.30 * v.x, 0.74 * v.y)])
	pier.color = Color(0.32, 0.24, 0.16)
	_add_prop(pier)
	for i in 5:
		var px := 0.34 + float(i) * 0.10
		var pile := Polygon2D.new()
		var py := 0.70 + float(i) * 0.008
		pile.polygon = PackedVector2Array([
			Vector2(px * v.x, py * v.y), Vector2(px * v.x + 4.0, py * v.y),
			Vector2(px * v.x + 4.0, py * v.y + 26.0), Vector2(px * v.x, py * v.y + 26.0)])
		pile.color = Color(0.24, 0.18, 0.12)
		_add_prop(pile)

func _harbor_2() -> void:
	sky_to(GOLD_BOT, Color(1.0, 0.84, 0.62), 1.2)
	glow_at(Vector2(0.46, 0.62), Color(1.0, 0.84, 0.50), 480.0, 0.60, 1.0)
	# 新船顺着滚木滑进水里
	var boat := _boat_prop(-0.06, 0.66, 1.9, Color(0.34, 0.22, 0.14), Color(0.96, 0.93, 0.86))
	boat.rotation_degrees = -4.0
	boat.position.y -= 40.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(boat, "position:x", 0.44 * _vw().x, 1.8)
	tw.tween_property(boat, "position:y", 0.66 * _vw().y, 1.8)
	tw.tween_property(boat, "rotation_degrees", 0.0, 1.8)
	shake(3.5, 0.7)

func _harbor_3() -> void:
	sky_to(Color(0.34, 0.44, 0.56), Color(1.0, 0.88, 0.70), 1.6)
	clouds_on(0.70, 1.6)
	glow_at(Vector2(0.62, 0.52), Color(1.0, 0.86, 0.52), 520.0, 0.55, 1.6)
	fx_on("fireflies", 30)
	title_card("潮风号", "出海")

# ---------------- 二: 出海首胜 ----------------
func _navy_1() -> void:
	_open("初战", "海上首胜", NIGHT_TOP, NIGHT_BOT, 0.60)
	stars_on(0.95, 1.6)
	clouds_on(0.30, 1.6)
	glow_at(Vector2(0.76, 0.26), Color(0.92, 0.94, 1.0), 300.0, 0.55, 1.6)
	# 敌船: 黑帆, 从右边压过来
	_navy_foe = _boat_prop(1.06, 0.56, 2.1, Color(0.14, 0.13, 0.16), Color(0.26, 0.24, 0.28))
	var tw := create_tween()
	tw.tween_property(_navy_foe, "position:x", 0.72 * _vw().x, 4.0)

func _navy_2() -> void:
	fx_on("embers", 90)
	glow_at(Vector2(0.72, 0.50), Color(1.0, 0.48, 0.20), 420.0, 0.70, 0.9)
	shake(7.0, 1.0)
	flash(Color(1.0, 0.60, 0.34), 0.30, 0.6)
	if _navy_foe != null:
		var tw := create_tween()
		tw.tween_property(_navy_foe, "position:x", 0.62 * _vw().x, 1.6)

func _navy_3() -> void:
	sky_to(Color(0.20, 0.24, 0.36), Color(0.92, 0.72, 0.54), 1.8)
	stars_on(0.0, 1.0)
	clouds_on(0.60, 1.6)
	sea_on(0.60, 1.0, 1.0)
	fx_off(1.2)
	glow_at(Vector2(0.62, 0.56), Color(1.0, 0.88, 0.58), 520.0, 0.60, 1.8)
	# 敌船沉下去
	if _navy_foe != null:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_navy_foe, "position:y", _navy_foe.position.y + 90.0, 2.4)
		tw.tween_property(_navy_foe, "rotation_degrees", 26.0, 2.4)
		tw.tween_property(_navy_foe, "modulate:a", 0.0, 2.4)
	title_card("首胜", "海上的第一条战报")

# ---------------- 三: 攻下第一座城 ----------------
func _siege_1() -> void:
	_open("城破", "旗色易主", DUSK_TOP, DUSK_BOT, 0.80)
	stars_on(0.35, 1.4)
	clouds_on(0.45, 1.6)
	_wall_tower(0.02, 0.34, 0.62, Color(0.11, 0.07, 0.08, 0.96))
	_wall_tower(0.36, 0.28, 0.66, Color(0.13, 0.08, 0.09, 0.96))
	_wall_tower(0.66, 0.34, 0.60, Color(0.11, 0.07, 0.08, 0.96))
	glow_at(Vector2(0.50, 0.72), Color(1.0, 0.46, 0.18), 480.0, 0.70, 1.6)
	vignette_on(0.62, 1.2)

func _siege_2() -> void:
	fx_on("embers", 130)
	glow_at(Vector2(0.42, 0.66), Color(1.0, 0.40, 0.14), 560.0, 0.85, 1.0)
	shake(6.0, 1.0)
	flash(Color(1.0, 0.62, 0.36), 0.32, 0.6)
	# 旧主的旗被放下来 (从城头转到地上)
	var fl := _flag_prop(0.50, 0.44, 74.0, Color(0.42, 0.30, 0.55))
	var box := fl[0] as Node2D
	var face := fl[1] as Polygon2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "rotation_degrees", 74.0, 2.2)
	tw.tween_property(box, "position:y", 0.66 * _vw().y, 2.2)
	tw.tween_property(face, "modulate:a", 0.35, 2.2)

func _siege_3() -> void:
	sky_to(Color(0.24, 0.26, 0.38), Color(0.94, 0.76, 0.54), 1.8)
	stars_on(0.0, 1.0)
	clouds_on(0.65, 1.6)
	fx_off(1.2)
	glow_at(Vector2(0.50, 0.42), Color(1.0, 0.86, 0.54), 540.0, 0.70, 1.8)
	# 你的旗升上城头
	var fl := _flag_prop(0.50, 0.62, 84.0, Color(0.86, 0.30, 0.26))
	var box := fl[0] as Node2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position:y", 0.40 * _vw().y, 2.6)
	tw.tween_property(box, "rotation_degrees", -3.0, 1.4)
	tw.chain().tween_property(box, "rotation_degrees", 2.5, 1.2)

# ---------------- 四: 裂土封王 ----------------
func _lord_1() -> void:
	title_card("封王", "裂土之盟")
	sky_to(HALL_TOP, HALL_BOT, 1.6)
	sea_off(0.02)
	vignette_on(0.70, 1.4)
	# 案几: 一条深色横带 + 两端烛火
	_band(0.58, 0.16, Color(0.13, 0.08, 0.07, 0.96))
	_band(0.575, 0.012, Color(0.24, 0.15, 0.11, 0.96))
	glow_at(Vector2(0.26, 0.52), Color(1.0, 0.72, 0.36), 220.0, 0.85, 1.4)
	glow_at(Vector2(0.74, 0.52), Color(1.0, 0.72, 0.36), 220.0, 0.85, 1.4)
	fx_on("embers", 26)

func _lord_2() -> void:
	# 契约摊开: 案上铺一张亮纸 + 一点火漆红
	_band(0.605, 0.045, Color(0.88, 0.84, 0.70, 0.92))
	var seal := Polygon2D.new()
	var v := _vw()
	seal.polygon = PackedVector2Array([
		Vector2(0.62 * v.x, 0.648 * v.y), Vector2(0.68 * v.x, 0.648 * v.y),
		Vector2(0.68 * v.x, 0.684 * v.y), Vector2(0.62 * v.x, 0.684 * v.y)])
	seal.color = Color(0.62, 0.16, 0.14, 0.95)
	_add_prop(seal)
	glow_at(Vector2(0.50, 0.62), Color(1.0, 0.80, 0.45), 380.0, 0.55, 1.2)

func _lord_3() -> void:
	glow_at(Vector2(0.50, 0.46), Color(1.0, 0.86, 0.52), 520.0, 0.70, 1.6)
	flash(Color(1.0, 0.86, 0.55), 0.42, 0.8)
	shake(2.5, 0.5)
	# 印落下去: 一枚红印从上方压到契约上
	var v := _vw()
	var stamp := Polygon2D.new()
	stamp.polygon = PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	stamp.color = Color(0.68, 0.18, 0.15)
	stamp.position = Vector2(0.65 * v.x, 0.40 * v.y)
	_add_prop(stamp)
	var tw := create_tween()
	tw.tween_property(stamp, "position:y", 0.662 * v.y, 0.8).set_trans(Tween.TRANS_BACK)

# ---------------- 五: 四海归一 (终章) ----------------
func _unify_1() -> void:
	_open("终章", "四海归一", NIGHT_TOP, NIGHT_BOT, 0.54)
	stars_on(1.0, 1.6)
	clouds_on(0.30, 1.8)
	glow_at(Vector2(0.60, 0.24), Color(0.94, 0.95, 1.0), 340.0, 0.55, 1.6)
	# 海平线上一排小旗 (五国的王都)
	var tints := [Color(0.42, 0.30, 0.55), Color(0.30, 0.44, 0.52),
		Color(0.52, 0.42, 0.24), Color(0.36, 0.30, 0.22), Color(0.34, 0.48, 0.30)]
	for i in tints.size():
		_flag_prop(0.16 + float(i) * 0.17, 0.505, 34.0, tints[i])

func _unify_2() -> void:
	# 五面旗一面面落下去 (旗杆节点都站在海平线 y 比例 0.505 上, 按位置挑出来)
	var tw := create_tween()
	tw.set_parallel(true)
	var n := 0
	for p in _props:
		var nd := p as Node2D
		if nd == null or nd.get_child_count() < 2:
			continue
		if absf(nd.position.y - 0.505 * _vw().y) > 2.0:
			continue
		tw.tween_property(nd, "rotation_degrees", 88.0, 1.1).set_delay(0.35 * float(n))
		tw.tween_property(nd, "modulate:a", 0.15, 1.1).set_delay(0.35 * float(n))
		n += 1
	fx_on("fireflies", 55)
	glow_at(Vector2(0.50, 0.60), Color(1.0, 0.84, 0.46), 560.0, 0.60, 2.0)

func _unify_3() -> void:
	sky_to(GOLD_TOP, GOLD_BOT, 2.4)
	stars_on(0.0, 1.4)
	clouds_on(0.80, 2.0)
	sea_on(0.60, 1.0, 1.0)
	glow_at(Vector2(0.50, 0.50), Color(1.0, 0.88, 0.54), 640.0, 0.85, 2.2)
	vignette_on(0.30, 1.8)
	flash(Color(1.0, 0.92, 0.70), 0.40, 1.2)
	# 只剩一面旗: 升到画面正中
	var fl := _flag_prop(0.50, 0.72, 92.0, Color(0.88, 0.32, 0.26))
	var box := fl[0] as Node2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position:y", 0.44 * _vw().y, 2.6)
	tw.tween_property(box, "scale", Vector2(1.3, 1.3), 2.6)
	title_card("潮汐港", "四海归一")

# ================= e43: 河边偶遇 (哥布林钓鱼竿) =================
# 一只蹲在河边的哥布林背影: 矮墩墩的身子 + 尖帽 + 尖耳朵 + 手里一根斜插出去的竿。
# 返回 [整个人, 竿梢] —— 竿梢挂浮子和钓线, 咬钩那一幕抖它。
func _goblin_prop(x_frac: float, y_frac: float, s: float) -> Array:
	var v := _vw()
	var box := Node2D.new()
	box.position = Vector2(x_frac * v.x, y_frac * v.y)
	box.scale = Vector2(s, s)
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-17, 0), Vector2(17, 0), Vector2(13, -21), Vector2(-12, -23)])
	body.color = Color(0.26, 0.34, 0.24)
	box.add_child(body)
	var head := Polygon2D.new()
	var hp := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		hp.append(Vector2(cos(a) * 11.0, -29.0 + sin(a) * 10.0))
	head.polygon = hp
	head.color = Color(0.31, 0.39, 0.27)
	box.add_child(head)
	var hat := Polygon2D.new()
	hat.polygon = PackedVector2Array([
		Vector2(-15, -33), Vector2(15, -33), Vector2(9, -47),
		Vector2(1, -54), Vector2(-6, -46)])
	hat.color = Color(0.44, 0.27, 0.31)
	box.add_child(hat)
	for sx in [-1.0, 1.0]:
		var ear := Polygon2D.new()
		ear.polygon = PackedVector2Array([
			Vector2(sx * 10.0, -30.0), Vector2(sx * 23.0, -39.0), Vector2(sx * 9.0, -24.0)])
		ear.color = Color(0.31, 0.39, 0.27)
		box.add_child(ear)
	# 竿: 从手里朝水的方向斜出去 (竿梢在左上方, 那是河面)
	var rod := Node2D.new()
	rod.position = Vector2(-6, -17)
	var shaft := Polygon2D.new()
	shaft.polygon = PackedVector2Array([
		Vector2(2, 3), Vector2(-46, -29), Vector2(-45, -26), Vector2(3, 6)])
	shaft.color = Color(0.36, 0.26, 0.17)
	rod.add_child(shaft)
	var tip := Node2D.new()
	tip.position = Vector2(-46, -28)
	rod.add_child(tip)
	box.add_child(rod)
	_add_prop(box)
	return [box, tip]

# 浮子 (一小截红白), 站在水面线上 —— 咬钩时往下沉一下
func _float_prop(x_frac: float, y_frac: float) -> Node2D:
	var v := _vw()
	var n := Node2D.new()
	n.position = Vector2(x_frac * v.x, y_frac * v.y)
	var top := Polygon2D.new()
	top.polygon = PackedVector2Array([
		Vector2(-1.4, -7), Vector2(1.4, -7), Vector2(1.4, -2), Vector2(-1.4, -2)])
	top.color = Color(0.88, 0.86, 0.80)
	n.add_child(top)
	var bot := Polygon2D.new()
	bot.polygon = PackedVector2Array([
		Vector2(-1.4, -2), Vector2(1.4, -2), Vector2(1.4, 4), Vector2(-1.4, 4)])
	bot.color = Color(0.80, 0.26, 0.22)
	n.add_child(bot)
	var ring := Polygon2D.new()
	ring.polygon = PackedVector2Array([
		Vector2(-9, 2), Vector2(9, 2), Vector2(7, 5), Vector2(-7, 5)])
	ring.color = Color(1.0, 0.98, 0.90, 0.20)
	n.add_child(ring)
	_add_prop(n)
	return n

func _goblin_1() -> void:
	_open("鱼竿", "河边偶遇", Color(0.10, 0.13, 0.21), Color(0.74, 0.68, 0.54), 0.62)
	stars_on(0.22, 1.4)
	clouds_on(0.35, 1.6)
	glow_at(Vector2(0.78, 0.26), Color(1.0, 0.90, 0.68), 320.0, 0.50, 1.6)
	# 对岸的芦苇带
	_ridge([[0.0, 0.05], [0.15, 0.09], [0.30, 0.04], [0.46, 0.08],
		[0.62, 0.03], [0.80, 0.07], [1.0, 0.04]], 0.625, Color(0.15, 0.19, 0.19, 0.92))
	# 河边的哥布林 (背影), 竿梢朝水面
	var gp := _goblin_prop(0.60, 0.74, 1.0)
	_gob_fig = gp[0] as Node2D
	_gob_tip = gp[1] as Node2D
	# 钓线: 从竿梢垂到水面
	var line := Polygon2D.new()
	line.polygon = PackedVector2Array([
		Vector2(-0.6, 0), Vector2(0.6, 0), Vector2(3.0, 32), Vector2(1.8, 32)])
	line.color = Color(0.84, 0.84, 0.82, 0.55)
	_gob_tip.add_child(line)
	# 浮子正好落在钓线末端 (竿梢 x-52 / y-45, 再往下走 32px 的线长)
	_gob_float = _float_prop(0.60 - 52.0 / _vw().x, 0.74 - 13.0 / _vw().y)

func _goblin_2() -> void:
	glow_at(Vector2(0.68, 0.34), Color(1.0, 0.88, 0.62), 360.0, 0.55, 1.1)
	fx_on("fireflies", 26)
	# 浮子一沉, 竿梢一挑
	if _gob_float != null:
		var fl := _gob_float
		var tw := create_tween()
		tw.tween_property(fl, "position:y", fl.position.y + 11.0, 0.45)
		tw.tween_property(fl, "position:y", fl.position.y, 0.25)
		tw.tween_property(fl, "position:y", fl.position.y + 5.0, 0.9)
	if _gob_tip != null:
		var tip := _gob_tip
		var tw2 := create_tween()
		tw2.tween_property(tip, "rotation_degrees", 20.0, 0.5)
		tw2.tween_property(tip, "rotation_degrees", -6.0, 0.7)
	shake(2.2, 0.45)

func _goblin_3() -> void:
	sky_to(Color(0.36, 0.46, 0.58), Color(1.0, 0.90, 0.72), 1.8)
	stars_on(0.0, 1.2)
	clouds_on(0.70, 1.6)
	glow_at(Vector2(0.50, 0.44), Color(1.0, 0.88, 0.54), 560.0, 0.70, 1.8)
	fx_on("fireflies", 42)
	vignette_on(0.32, 1.6)
	# 他回过头来 (整个身影翻个面), 鱼竿递过来
	if _gob_fig != null:
		var fig := _gob_fig
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(fig, "scale:x", -1.0, 1.4)
		tw.tween_property(fig, "position:x", fig.position.x - 34.0, 1.4)
	title_card("鱼竿", "哥布林进货了")

# ================= e43: 国家级事件过场 =================
# 布景方法从 _ctx 里读这一场是哪个国家 (名字 / 旗色), 台词由 _*_steps() 现拼
func _nat_name() -> String:
	var s := String(_ctx.get("nation", ""))
	return s if s != "" else "邻国"

func _nat_color() -> Color:
	var c: Variant = _ctx.get("color", null)
	if c is Color:
		return c
	return Color(0.72, 0.72, 0.74)

func _nat_town() -> String:
	var s := String(_ctx.get("town", ""))
	return s if s != "" else "那座城"

# 一个货箱 (栈桥上卸货用)
func _crate(x_frac: float, y_frac: float, s: float,
		tint := Color(0.44, 0.32, 0.20)) -> Node2D:
	var v := _vw()
	var box := Node2D.new()
	box.position = Vector2(x_frac * v.x, y_frac * v.y)
	box.scale = Vector2(s, s)
	var b := Polygon2D.new()
	b.polygon = PackedVector2Array([
		Vector2(-11, 0), Vector2(11, 0), Vector2(11, -15), Vector2(-11, -15)])
	b.color = tint
	box.add_child(b)
	var lid := Polygon2D.new()
	lid.polygon = PackedVector2Array([
		Vector2(-11, -15), Vector2(11, -15), Vector2(11, -19), Vector2(-11, -19)])
	lid.color = tint.lightened(0.20)
	box.add_child(lid)
	_add_prop(box)
	_crates.append(box)
	return box

# —— 会盟 / 通商之约 (商盟) ——
func _pact_steps() -> Array:
	var nm := _nat_name()
	return [
		["%s的商旗挂上栈桥, 货箱一只只卸下来." % nm, "_pact_1"],
		["账房拨了一夜的算盘, 两边终于把数目对上了.", "_pact_2"],
		["从今往后, 你的货可以挂着%s的旗走南闯北." % nm, "_pact_3"],
	]

func _pact_1() -> void:
	_crates.clear()               # 上回放的货箱早就 free 了, 别揣着旧引用
	_open("会盟", "通商之约", Color(0.12, 0.16, 0.26), Color(0.92, 0.78, 0.58), 0.60)
	stars_on(0.28, 1.4)
	clouds_on(0.42, 1.6)
	glow_at(Vector2(0.22, 0.26), Color(1.0, 0.90, 0.70), 320.0, 0.55, 1.6)
	_ridge([[0.0, 0.04], [0.14, 0.09], [0.30, 0.04], [0.48, 0.08],
		[0.66, 0.03], [0.84, 0.08], [1.0, 0.04]], 0.62, Color(0.17, 0.20, 0.26, 0.88))
	var v := _vw()
	var pier := Polygon2D.new()
	pier.polygon = PackedVector2Array([
		Vector2(0.24 * v.x, 0.697 * v.y), Vector2(0.80 * v.x, 0.712 * v.y),
		Vector2(0.80 * v.x, 0.746 * v.y), Vector2(0.24 * v.x, 0.731 * v.y)])
	pier.color = Color(0.30, 0.23, 0.16)
	_add_prop(pier)
	# 两面旗并排: 左是潮汐港的, 右是他们的 (旗色就是这一场的国色)
	var mine := _flag_prop(0.30, 0.700, 62.0, Color(0.86, 0.30, 0.26))
	var theirs := _flag_prop(0.74, 0.713, 62.0, _nat_color())
	var tw := create_tween()
	tw.set_parallel(true)
	for f in [mine[1], theirs[1]]:
		var face := f as Polygon2D
		face.scale = Vector2(0.15, 1.0)
		tw.tween_property(face, "scale:x", 1.0, 1.4)
	for i in 3:
		_crate(0.42 + float(i) * 0.09, 0.716, 0.9 - float(i) * 0.1)

func _pact_2() -> void:
	glow_at(Vector2(0.50, 0.66), Color(1.0, 0.84, 0.48), 460.0, 0.60, 1.2)
	# 货箱一只只抬上船 (往右飘出去 + 淡出)
	var n := 0
	for cr in _crates:
		var nd := cr as Node2D
		if nd == null or not is_instance_valid(nd):
			continue
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(nd, "position:x", nd.position.x + 110.0, 1.8).set_delay(0.28 * float(n))
		tw.tween_property(nd, "modulate:a", 0.0, 1.8).set_delay(0.28 * float(n))
		n += 1

func _pact_3() -> void:
	sky_to(GOLD_TOP, GOLD_BOT, 2.0)
	stars_on(0.0, 1.2)
	clouds_on(0.72, 1.8)
	sea_on(0.62, 1.0, 1.2)
	glow_at(Vector2(0.58, 0.54), Color(1.0, 0.88, 0.56), 560.0, 0.72, 2.0)
	fx_on("fireflies", 36)
	# 商船顺着光出海: 桅杆上挂这一场的国色帆
	var boat := _boat_prop(0.22, 0.635, 1.5, Color(0.34, 0.23, 0.15), _nat_color())
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(boat, "position:x", 0.86 * _vw().x, 3.4)
	tw.tween_property(boat, "position:y", 0.625 * _vw().y, 3.4)
	title_card(_nat_name(), "商盟已立")

# —— 盟约 / 守望相助 ——
func _ally_steps() -> Array:
	var nm := _nat_name()
	return [
		["案上摆着两碗血酒, %s的使者先端起了碗." % nm, "_ally_1"],
		["海面上, 两国的巡逻船并排巡了一整夜.", "_ally_2"],
		["往后你有难, %s会来; 他们有事, 你也得去." % nm, "_ally_3"],
	]

func _ally_1() -> void:
	title_card("盟约", "守望相助")
	sky_to(HALL_TOP, HALL_BOT, 1.6)
	sea_off(0.02)
	vignette_on(0.72, 1.4)
	_band(0.60, 0.15, Color(0.13, 0.08, 0.07, 0.96))
	_band(0.595, 0.012, Color(0.24, 0.15, 0.11, 0.96))
	# 两碗血酒: 一左一右, 各压一团光 (右碗的光偏国色)
	glow_at(Vector2(0.34, 0.545), Color(1.0, 0.70, 0.40), 180.0, 0.80, 1.4)
	glow_at(Vector2(0.66, 0.545), Color(1.0, 0.70, 0.40), 180.0, 0.80, 1.4)
	var v := _vw()
	for x in [0.34, 0.66]:
		var bowl := Polygon2D.new()
		bowl.polygon = PackedVector2Array([
			Vector2((x - 0.018) * v.x, 0.575 * v.y), Vector2((x + 0.018) * v.x, 0.575 * v.y),
			Vector2((x + 0.012) * v.x, 0.605 * v.y), Vector2((x - 0.012) * v.x, 0.605 * v.y)])
		bowl.color = Color(0.30, 0.22, 0.16)
		_add_prop(bowl)
		var wine := Polygon2D.new()
		wine.polygon = PackedVector2Array([
			Vector2((x - 0.010) * v.x, 0.578 * v.y), Vector2((x + 0.010) * v.x, 0.578 * v.y),
			Vector2((x + 0.008) * v.x, 0.590 * v.y), Vector2((x - 0.008) * v.x, 0.590 * v.y)])
		wine.color = Color(0.52, 0.10, 0.12)
		_add_prop(wine)
	fx_on("embers", 22)

func _ally_2() -> void:
	sky_to(Color(0.06, 0.09, 0.16), Color(0.14, 0.20, 0.30), 1.8)
	glow_at(Vector2(0.72, 0.22), Color(0.92, 0.94, 1.0), 300.0, 0.50, 1.6)
	stars_on(0.95, 1.4)
	clouds_on(0.28, 1.6)
	sea_on(0.60, 1.0, 1.4)
	fx_off(0.9)
	# 两条船并排巡航 (一条挂你的帆, 一条挂国色的帆)
	var a := _boat_prop(-0.06, 0.60, 1.7, Color(0.30, 0.21, 0.15), Color(0.94, 0.90, 0.84))
	var b := _boat_prop(-0.30, 0.655, 1.5, Color(0.26, 0.20, 0.16), _nat_color())
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(a, "position:x", 0.62 * _vw().x, 5.0)
	tw.tween_property(b, "position:x", 0.56 * _vw().x, 5.0)

func _ally_3() -> void:
	sky_to(Color(0.20, 0.26, 0.38), Color(0.94, 0.78, 0.56), 2.2)
	stars_on(0.0, 1.4)
	clouds_on(0.68, 1.8)
	glow_at(Vector2(0.50, 0.52), Color(1.0, 0.86, 0.54), 620.0, 0.78, 2.2)
	fx_on("fireflies", 44)
	# 两面旗交叉着立起来 (你的 + 他们的)
	var mine := _flag_prop(0.44, 0.62, 74.0, Color(0.86, 0.30, 0.26))
	var theirs := _flag_prop(0.56, 0.62, 74.0, _nat_color())
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mine[0], "rotation_degrees", -8.0, 2.0)
	tw.tween_property(theirs[0], "rotation_degrees", 8.0, 2.0)
	tw.tween_property(mine[0], "position:y", 0.50 * _vw().y, 2.4)
	tw.tween_property(theirs[0], "position:y", 0.50 * _vw().y, 2.4)
	title_card(_nat_name(), "盟约已缔")

# —— 宣战 / 递出战书 ——
func _war_steps() -> Array:
	var nm := _nat_name()
	return [
		["使者捧着战书进殿, 火漆在灯下红得刺眼.", "_war_1"],
		["%s的旗被取下来, 扔在阶前." % nm, "_war_2"],
		["海图上那一角亮起血色. 从今天起, %s不再是邻居." % nm, "_war_3"],
	]

func _war_1() -> void:
	title_card("宣战", "递出战书")
	sky_to(Color(0.09, 0.05, 0.07), Color(0.30, 0.12, 0.11), 1.6)
	sea_off(0.02)
	vignette_on(0.74, 1.4)
	# 殿: 两侧立柱剪影 + 中间的灯
	for x in [0.10, 0.24, 0.76, 0.90]:
		_band(x - 0.012, 0.90, Color(0.06, 0.04, 0.05, 0.96))
	glow_at(Vector2(0.50, 0.46), Color(1.0, 0.62, 0.30), 300.0, 0.72, 1.4)
	# 使者: 一高一矮两个剪影, 高的那个捧着一卷书
	var v := _vw()
	var scroll := Polygon2D.new()
	scroll.polygon = PackedVector2Array([
		Vector2(0.47 * v.x, 0.455 * v.y), Vector2(0.53 * v.x, 0.455 * v.y),
		Vector2(0.53 * v.x, 0.487 * v.y), Vector2(0.47 * v.x, 0.487 * v.y)])
	scroll.color = Color(0.90, 0.86, 0.72)
	_add_prop(scroll)
	var seal := Polygon2D.new()
	seal.polygon = PackedVector2Array([
		Vector2(0.492 * v.x, 0.470 * v.y), Vector2(0.508 * v.x, 0.470 * v.y),
		Vector2(0.508 * v.x, 0.483 * v.y), Vector2(0.492 * v.x, 0.483 * v.y)])
	seal.color = Color(0.72, 0.16, 0.14)
	_add_prop(seal)
	fx_on("embers", 40)

func _war_2() -> void:
	glow_at(Vector2(0.50, 0.60), Color(1.0, 0.50, 0.20), 420.0, 0.75, 1.0)
	flash(Color(1.0, 0.56, 0.28), 0.22, 0.5)
	# 他们的旗被取下来 (从上方转到阶前)
	var fl := _flag_prop(0.50, 0.40, 76.0, _nat_color())
	var box := fl[0] as Node2D
	var face := fl[1] as Polygon2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position:y", 0.74 * _vw().y, 1.8)
	tw.tween_property(box, "rotation_degrees", 78.0, 1.8)
	tw.tween_property(face, "modulate:a", 0.30, 1.8)

func _war_3() -> void:
	sky_to(Color(0.12, 0.05, 0.07), Color(0.52, 0.14, 0.12), 2.0)
	glow_at(Vector2(0.50, 0.54), Color(1.0, 0.30, 0.20), 640.0, 0.80, 2.0)
	stars_on(0.30, 1.2)
	shake(3.0, 0.7)
	# 海图上那一角: 一面立起来的旗, 血色在它背后亮开
	var fl := _flag_prop(0.50, 0.72, 88.0, _nat_color())
	var box := fl[0] as Node2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position:y", 0.44 * _vw().y, 2.4)
	tw.tween_property(box, "scale", Vector2(1.25, 1.25), 2.4)
	title_card(_nat_name(), "战书已递")

# —— 失城 / 城头易帜 ——
func _lost_steps() -> Array:
	var nm := _nat_name()
	var tn := _nat_town()
	return [
		["消息是半夜到的: %s的城头打了一整天, 天没黑就断了箭." % tn, "_lost_1"],
		["你的旗被扯下来, 踩进泥里.", "_lost_2"],
		["%s的旗升上去. %s, 不再向你交税." % [nm, tn], "_lost_3"],
	]

func _lost_1() -> void:
	_open("失城", "城头易帜", DUSK_TOP, Color(0.26, 0.14, 0.12), 0.78)
	stars_on(0.30, 1.4)
	clouds_on(0.42, 1.6)
	_wall_tower(0.04, 0.32, 0.64, Color(0.10, 0.06, 0.07, 0.96))
	_wall_tower(0.38, 0.26, 0.68, Color(0.12, 0.07, 0.08, 0.96))
	_wall_tower(0.66, 0.32, 0.62, Color(0.10, 0.06, 0.07, 0.96))
	glow_at(Vector2(0.36, 0.78), Color(1.0, 0.44, 0.18), 460.0, 0.70, 1.6)
	fx_on("embers", 80)

func _lost_2() -> void:
	glow_at(Vector2(0.42, 0.70), Color(1.0, 0.38, 0.14), 540.0, 0.82, 1.0)
	shake(5.0, 0.9)
	flash(Color(1.0, 0.60, 0.34), 0.26, 0.6)
	# 你的旗被扯下来
	var fl := _flag_prop(0.50, 0.42, 76.0, Color(0.86, 0.30, 0.26))
	var box := fl[0] as Node2D
	var face := fl[1] as Polygon2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "rotation_degrees", 82.0, 2.0)
	tw.tween_property(box, "position:y", 0.70 * _vw().y, 2.0)
	tw.tween_property(face, "modulate:a", 0.22, 2.0)

func _lost_3() -> void:
	sky_to(Color(0.07, 0.06, 0.10), Color(0.30, 0.16, 0.18), 1.8)
	glow_at(Vector2(0.50, 0.52), Color(0.92, 0.70, 0.40), 480.0, 0.55, 1.8)
	fx_off(1.4)
	# 他们的旗升上城头
	var fl := _flag_prop(0.50, 0.66, 82.0, _nat_color())
	var box := fl[0] as Node2D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(box, "position:y", 0.42 * _vw().y, 2.4)
	tw.tween_property(box, "rotation_degrees", -2.5, 1.3)
	tw.chain().tween_property(box, "rotation_degrees", 2.0, 1.1)
	title_card(_nat_town(), "城头易帜")