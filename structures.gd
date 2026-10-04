# structures.gd —— Autoload，名字：Structures
# 管理玩家摆放的「建筑设施」：工作台 + 熔炉。
#   · 工作台：摆出来后靠近它，背包 craft 页解锁「工作台配方」（更复杂的工具/器械）
#   · 熔炉：花 1 木头 + 1 铁矿点火熔炼，过一段时间出 1 铁锭；
#     手持镐子挖一下可以拆掉、返还物品
# 跟 OreVein 一个套路：这里只存数据 + 发信号，贴图/动画由 scene/station_node.gd 画。
extends Node

signal station_changed(cell: Vector2i)   # 摆好了 / 状态变了（点火、出铁）
signal station_removed(cell: Vector2i)   # 被镐子拆掉了
signal site_changed                      # 工地变化（开工 / 每晚推进 / 建成）

const KIND_WORKBENCH := "workbench"
const KIND_FURNACE := "furnace"
const KIND_BLACKSMITH := "blacksmith"   # 铁匠铺：建造系统的第一座建筑，可升级，等级越高能打造越好的盔甲
const KIND_WELL := "well"               # 水井：站旁边按 F 给洒水壶打满水（开局那口老井拆成了这个）
const KIND_COOP := "coop"               # 鸡舍：把买来的小鸡住进去，每天早上下一轮蛋，站旁边按 F 收蛋
const KIND_LAMP := "lamp"               # e38d 路灯：材料少、不用人工，放下即成，天黑自己亮
const KIND_HUT := "hut"                 # e44 同伴小屋：每盖一座, 伙伴上限 +1; 每座外形都不一样
const KIND_HIVE := "hive"               # e44b 蜂箱：每天早上攒 1 罐蜂蜜, 站旁边按 F 收
const KIND_CHEST := "chest"             # e45 储物箱：站旁边按 F 开箱存取, 腾背包用

# e49 农场畜牧线（Farm RPG 素材包「Farm Buildings」那一批房子）。
# 这一批跟鸡舍不同：鸡舍一格锚点 + 屋前一块交互区；这几座是**多格地基**的大房子
# （地基形状见 farm_footprint），畜棚/马厩里还住着会走动的牲口（见 livestock_node）。
const KIND_BARN := "barn"               # 畜棚：养牛/羊/山羊/鸭/鸵鸟, 每天早上各产一份畜产
const KIND_STABLE := "stable"           # 马厩：养马（马不产畜产, 是骑乘/行军的牲口）
const KIND_SILO := "silo"               # 筒仓：囤粮的圆仓, 跟储物箱一样按 F 存取
const KIND_GREENHOUSE := "greenhouse"   # 温室：棚前那 4x3 块地不看出季节, 过季也不枯
const KIND_MILL := "mill"               # 磨坊：按 F 把背包里的小麦磨成面粉
const KIND_FENCE := "fence"             # 围栏：1x1 篱笆, 只是好看和划地盘, 不挡路
const KIND_BRIDGE := "bridge"           # 木桥：1x1 便桥, 想架在水上得让 game 放行水面判定

# e44 同伴小屋的一批外形 —— 每盖一座按「已有几座」顺次取下一款, 取完 7 款再从头轮。
# 每款 = {tex 贴图, rect 裁剪矩形}；rect 是探针量出来的「紧贴不透明内容」的框,
# 绘制尺寸就是裁剪尺寸(1:1, 像素画不缩放)。文件都取自同一套 Farm RPG 素材包, 风格不打架。
const HUT_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/"
const HUT_LOOKS := [
	{"tex": HUT_SHEET + "NPCS houses/Base houses.png", "rect": Rect2(704, 185, 80, 146)},
	{"tex": HUT_SHEET + "NPCS houses/Base houses.png", "rect": Rect2(672, 57, 95, 104)},
	{"tex": HUT_SHEET + "NPCS houses/Base houses.png", "rect": Rect2(545, 77, 106, 94)},
	{"tex": HUT_SHEET + "3.png", "rect": Rect2(2, 13, 124, 87)},
	{"tex": HUT_SHEET + "7.png", "rect": Rect2(4, 3, 124, 93)},
	{"tex": HUT_SHEET + "11.png", "rect": Rect2(4, 9, 124, 87)},
	{"tex": HUT_SHEET + "NPCS houses/Blacksmith/Blacksmith2.png", "rect": Rect2(4, 7, 72, 87)},
]

# 取第 variant 款外形（越界就绕回来）。返回 {} 不会发生 —— 表空时兜第 0 款。
func hut_look(variant: int) -> Dictionary:
	if HUT_LOOKS.is_empty():
		return {}
	var n := HUT_LOOKS.size()
	return HUT_LOOKS[((variant % n) + n) % n]

# ---------------- e49 农场建筑的外观表 ----------------
# 每座建筑 = {tex 贴图, rect 裁剪矩形, w 绘制宽, h 绘制高}。
# rect 都是探针量出来的「紧贴单体不透明内容」的框 —— 这几张表把同一栋楼**上下叠了两遍**
# （上栋 + 下栋），直接按整表取会把两栋楼一起画出来（第一版就栽在这），所以只取第一栋。
# 围栏/木桥是 16x16 的小格件，按单格取，铺一排就是一道栏/一条桥。
const FARM_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/Farm Buildings/"
const FENCE_SHEET := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Fence and Bridge/"

const FARM_LOOKS := {
	KIND_BARN: {"tex": FARM_SHEET + "Barn/Barn.png", "rect": Rect2(7, 4, 78, 76)},
	KIND_STABLE: {"tex": FARM_SHEET + "Stable/Stable.png", "rect": Rect2(24, 10, 76, 54)},
	KIND_SILO: {"tex": FARM_SHEET + "Silo/Silo.png", "rect": Rect2(5, 6, 39, 73)},
	KIND_GREENHOUSE: {"tex": FARM_SHEET + "Greenhouse/Greenhouse.png", "rect": Rect2(15, 7, 60, 81)},
	KIND_MILL: {"tex": FARM_SHEET + "Mill/Mill.png", "rect": Rect2(7, 7, 66, 89)},
	KIND_FENCE: {"tex": FENCE_SHEET + "Fence Wood.png", "rect": Rect2(48, 0, 16, 16)},
	KIND_BRIDGE: {"tex": FENCE_SHEET + "Bridge.png", "rect": Rect2(32, 16, 16, 16)},
}

# 这一批建筑的 kind 清单（game 里想一行接入就能用 is_farm_kind 判断）
const FARM_KINDS := [KIND_BARN, KIND_STABLE, KIND_SILO, KIND_GREENHOUSE,
	KIND_MILL, KIND_FENCE, KIND_BRIDGE]

func is_farm_kind(kind: String) -> bool:
	return FARM_KINDS.has(kind)

# 取某座农场建筑的贴图/裁剪（没有就返回 {}）。绘制尺寸直接取 rect.size（像素画 1:1）。
func farm_look(kind: String) -> Dictionary:
	return FARM_LOOKS.get(kind, {})

# e49 地基：anchor = 底边**中间**那一格，dy 为负向上（跟 game.building_footprint 同一套规矩）。
# 围栏/木桥只有 anchor 一格；房子里最大的畜棚 5x3（够摆下一群牲口）。
# ❗这张表就是「新建筑要占几格」的唯一真相源 —— game.building_footprint 里加一行
#   `if Structures.is_farm_kind(kind): return Structures.farm_footprint(anchor, kind)` 即可。
const FARM_FOOT := {
	KIND_BARN: Rect2i(-2, -2, 5, 3),
	KIND_STABLE: Rect2i(-2, -1, 4, 2),
	KIND_SILO: Rect2i(-1, -1, 3, 2),
	KIND_GREENHOUSE: Rect2i(-2, -2, 4, 3),
	KIND_MILL: Rect2i(-2, -2, 4, 3),
}

func farm_footprint(anchor: Vector2i, kind: String) -> Array:
	var r: Rect2i = FARM_FOOT.get(kind, Rect2i(0, 0, 1, 1))
	var out: Array = []
	for dy in range(r.position.y, r.position.y + r.size.y):
		for dx in range(r.position.x, r.position.x + r.size.x):
			out.append(anchor + Vector2i(dx, dy))
	return out

# e49 温室棚前那块「不看出季节」的地：房前 dy +1..+3、dx -2..+1 的 4x3 矩形。
# 为什么不挖棚底下的格子：地基格被 Structures.is_blocked 拦着不许耕地（game 的老规矩）。
# 这块地归 Farm 用（plant 放行季节、换季不枯死），判定就走这个函数。
const GREENHOUSE_BED := Rect2i(-2, 1, 4, 3)

func is_greenhouse_cell(c: Vector2i) -> bool:
	for key in stations.keys():
		if String(stations[key].kind) != KIND_GREENHOUSE:
			continue
		var d: Vector2i = c - Vector2i(key)
		if d.x >= GREENHOUSE_BED.position.x and d.x < GREENHOUSE_BED.position.x + GREENHOUSE_BED.size.x \
				and d.y >= GREENHOUSE_BED.position.y and d.y < GREENHOUSE_BED.position.y + GREENHOUSE_BED.size.y:
			return true
	return false

# 储物箱能装几格（一格 = 一叠；同一件东西自动并叠，叠满了另开一格）
const CHEST_SLOTS := 20

# 建造菜单数据（backpack_ui 建造页 / game 摆放模式共用）。
# coin 金钱 / wood 木头 / stone 石头 / iron 铁锭 都是数量。
# labor = 建成需要的人工（人·天）：开工时钱料一次付清，之后每晚按派去工地的人数积累，
# 攒够就建成（见 start_site / add_site_work）。人数在每晚的派活面板「工地」栏调整。
# ❗labor = 0 的是「不用人工的小件」：不排工地，钱料付清当场落成（路灯，见 start_site）。
# 拆掉时返还 wood/stone/iron（钱和人工不退）。
const BUILDINGS := {
	KIND_BLACKSMITH: {
		"name": "铁匠铺",
		"desc": "打造整套盔甲的地方 (站旁边按 B 制作), 还能花钱升级",
		"coin": 150, "wood": 10, "stone": 8, "iron": 2, "labor": 6,
	},
	KIND_WELL: {
		"name": "水井",
		"desc": "站旁边按 F 或左键点它, 给洒水壶打满水, 不用特地跑去河边",
		"coin": 30, "wood": 5, "stone": 10, "iron": 0, "labor": 2,
	},
	KIND_COOP: {
		"name": "鸡舍",
		"desc": "按 F 开管理界面: 收蛋/买鸡/卖鸡/扩建, 每天早上下一轮蛋",
		"coin": 100, "wood": 8, "stone": 4, "iron": 0, "labor": 4,
	},
	KIND_LAMP: {
		"name": "路灯",
		"desc": "摆在路边照亮一小圈, 天黑自己亮, 天亮自己灭; 不用人工, 放下即成",
		"coin": 20, "wood": 2, "stone": 2, "iron": 0, "labor": 0,
	},
	KIND_HUT: {
		"name": "同伴小屋",
		"desc": "给伙伴住的小屋, 每盖一座伙伴上限 +1; 每盖一座外形都不一样",
		"coin": 120, "wood": 8, "stone": 4, "iron": 0, "labor": 3,
	},
	KIND_HIVE: {
		"name": "蜂箱",
		"desc": "放在屋边养蜂, 每天早上攒 1 罐蜂蜜 (冬天和风暴天不产), 站旁边按 F 收",
		"coin": 60, "wood": 4, "stone": 0, "iron": 1, "labor": 0,
	},
	KIND_CHEST: {
		"name": "储物箱",
		"desc": "把暂时用不上的东西存进去 (共 %d 格), 站旁边按 F 开箱存取, 不占背包" % CHEST_SLOTS,
		"coin": 50, "wood": 6, "stone": 0, "iron": 0, "labor": 0,
	},
	# —— e49 农场畜牧线 ——
	KIND_BARN: {
		"name": "畜棚",
		"desc": "养牛/羊/山羊/鸭/鸵鸟的地方 (站旁边按 F 买卖/收畜产), 每天早上每头各产一份",
		"coin": 220, "wood": 16, "stone": 6, "iron": 1, "labor": 8,
	},
	KIND_STABLE: {
		"name": "马厩",
		"desc": "养马的地方 (站旁边按 F 买卖), 马不产畜产, 是骑乘和行军用的牲口",
		"coin": 180, "wood": 14, "stone": 8, "iron": 2, "labor": 7,
	},
	KIND_SILO: {
		"name": "筒仓",
		"desc": "囤谷物的圆仓 (共 %d 格), 站旁边按 F 存取, 跟储物箱一样用" % CHEST_SLOTS,
		"coin": 140, "wood": 6, "stone": 12, "iron": 0, "labor": 5,
	},
	KIND_GREENHOUSE: {
		"name": "温室",
		"desc": "棚前那 4x3 块地不看出季节, 什么种子都能种, 过季也不会枯",
		"coin": 260, "wood": 12, "stone": 8, "iron": 3, "labor": 10,
	},
	KIND_MILL: {
		"name": "磨坊",
		"desc": "站旁边按 F, 把背包里的小麦磨成面粉 (1 袋小麦出 1 袋面粉), 面粉更值钱",
		"coin": 160, "wood": 12, "stone": 6, "iron": 1, "labor": 6,
	},
	KIND_FENCE: {
		"name": "围栏",
		"desc": "一小段木篱笆, 铺一排围出院子; 只是好看不挡路, 不用人工, 放下即成",
		"coin": 6, "wood": 2, "stone": 0, "iron": 0, "labor": 0,
	},
	KIND_BRIDGE: {
		"name": "木桥",
		"desc": "一小块桥面, 铺一排能踩过窄水沟; 不用人工, 放下即成 (水面通行要 game 放行)",
		"coin": 20, "wood": 4, "stone": 0, "iron": 0, "labor": 0,
	},
}

func building_cost(kind: String) -> Dictionary:
	return BUILDINGS.get(kind, {})

const SMELT_TIME := 20.0                 # 熔一炉要多少秒

# 熔炉状态
const ST_IDLE := "idle"                  # 待点火
const ST_SMELTING := "smelting"          # 熔炼中
const ST_READY := "ready"                # 铁锭出炉，待取

# cell -> {kind:String, state:String, t:float}
var stations := {}

# 工地（建筑施工中）：一次只能盖一座。
# {"kind": String, "anchor": Vector2i, "work": int, "need": int}；空字典 = 没有工地。
# 开工时钱料已付清，每晚按派去工地的人数往 work 里加，攒够 need 自动 place() 落成。
var site := {}

func _process(delta: float) -> void:
	if stations.is_empty():
		return
	for c in stations.keys():
		var s: Dictionary = stations[c]
		if String(s.state) == ST_SMELTING:
			s.t = float(s.t) + delta
			if float(s.t) >= SMELT_TIME:
				s.t = 0.0
				s.state = ST_READY
				station_changed.emit(c)

# 重开地图（game._ready）时清空，防止加载两次场景后设施翻倍
func reset() -> void:
	stations.clear()
	site = {}

func has_station(c: Vector2i) -> bool:
	return stations.has(c)

# 有设施的格子不能耕地 / 铺地板 / 种树 / 摆别的
func is_blocked(c: Vector2i) -> bool:
	if stations.has(c):
		return true
	return site_cells().has(c)

# ---------------- 工地（建筑要一晚一晚盖） ----------------
func site_busy() -> bool:
	return not site.is_empty()

func site_name() -> String:
	if site.is_empty():
		return ""
	return String(building_cost(String(site["kind"])).get("name", "建筑"))

# 工地占用的格子 = 建筑地基（跟 building_footprint 同一套，game.gd 里定）。
# 这里只存锚点，地基格子由 game 的 footprint 布局决定 —— 为了不互相抄布局，
# Structures 只拦锚点格，地基其余格子的拦截由 game._building_site_ok 之外的地方
# 用 site_footprint 回调查（见下）。
var footprint_rule: Callable = Callable()   # func(anchor: Vector2i) -> Array[Vector2i]

func site_cells() -> Array:
	if site.is_empty():
		return []
	if footprint_rule.is_valid():
		return footprint_rule.call(Vector2i(site["anchor"]))
	return [Vector2i(site["anchor"])]

# 开工：钱料已由调用方付清，这里记下工地开始施工。
# e38d labor = 0 的小件（路灯）不排工地：当场落成，省掉「派人施工」那一晚。
func start_site(anchor: Vector2i, kind: String) -> bool:
	if not site.is_empty() or stations.has(anchor):
		return false
	var cost := building_cost(kind)
	if cost.is_empty():
		return false
	if int(cost.get("labor", 1)) <= 0:
		return place(anchor, kind)
	site = {"kind": kind, "anchor": anchor, "work": 0, "need": maxi(1, int(cost.get("labor", 1)))}
	site_changed.emit()
	return true

# 每晚推进：heads = 今晚派去工地的人数（1 人干一晚 = 1 人工）。
# 攒够 need 就地 place() 落成并清空工地。返回 true = 今晚建成了。
func add_site_work(heads: int) -> bool:
	if site.is_empty() or heads <= 0:
		return false
	var anchor := Vector2i(site["anchor"])
	var kind := String(site["kind"])
	site["work"] = int(site["work"]) + heads
	if int(site["work"]) < int(site["need"]):
		site_changed.emit()
		return false
	site = {}
	place(anchor, kind)          # 发 station_changed -> game 建真房子
	site_changed.emit()
	return true

# e24c: 取消工地 —— 清空工地并把建筑的材料耗费还给调用方（钱和人工不退，
# 跟镐子拆房同一套规矩）。返回退的材料 {wood,stone,iron}；没有工地返回 {}。
func cancel_site() -> Dictionary:
	if site.is_empty():
		return {}
	var cost := building_cost(String(site["kind"]))
	site = {}
	site_changed.emit()
	return {
		"wood": int(cost.get("wood", 0)),
		"stone": int(cost.get("stone", 0)),
		"iron": int(cost.get("iron", 0)),
	}

func kind_of(c: Vector2i) -> String:
	if not stations.has(c):
		return ""
	return String(stations[c].kind)

func state_of(c: Vector2i) -> String:
	if not stations.has(c):
		return ""
	return String(stations[c].state)

# 摆一座设施。存档恢复也走这里（level 字段熔炉/工作台用不上，铁匠铺用；
# chickens/eggs 只有鸡舍用，honey 只有蜂箱用，variant 只有同伴小屋用，
# items 只有储物箱用 —— 通用放着省得序列化分流）
# restore = true 是读档重建（save_manager 走这条），不算玩家盖房子 —— 否则读一个
# 已经有建筑的存档会白送 build_first 完成、还往任务栏塞一条多余的下一环（e32）。
func place(c: Vector2i, kind: String, restore := false) -> bool:
	if stations.has(c):
		return false
	# e44 同伴小屋：外形按「已有几座」顺次往下取 —— 后盖的跟先盖的长得不一样。
	# ❗得先数再插：插入之后再数会把自己也算进去, 第一座就从编号 1 起步了。
	var hut_n := hut_count()
	stations[c] = {"kind": kind, "state": ST_IDLE, "t": 0.0, "level": 1,
		"chickens": 0, "eggs": 0, "honey": 0, "variant": 0, "items": [],
		"animals": {}, "produce": {}}
	if kind == KIND_HUT:
		stations[c]["variant"] = hut_n
	station_changed.emit(c)
	if not restore:
		Quests.complete("build_first")   # e32: 盖起第一座建筑
	if kind == KIND_HUT:
		Slaves.refresh_cap()             # e44: 小屋落成 -> 伙伴上限 +1
	return true

# e44 建筑模式：把一座建筑原样放回/搬到指定格子（字段整份搬过去, 不花钱不扣料）
func restore_station(c: Vector2i, data: Dictionary) -> bool:
	if data.is_empty() or stations.has(c):
		return false
	stations[c] = data.duplicate(true)
	station_changed.emit(c)
	if String(stations[c].get("kind", "")) == KIND_HUT:
		Slaves.refresh_cap()
	return true

# 岛上现在有几座同伴小屋（伙伴上限 = 基础 3 + 这个数, 见 slaves.refresh_cap）
func hut_count() -> int:
	var n := 0
	for c in stations.keys():
		if String(stations[c].kind) == KIND_HUT:
			n += 1
	return n

func variant_of(c: Vector2i) -> int:
	if not stations.has(c):
		return 0
	return int(stations[c].get("variant", 0))

# e44 建筑模式用：岛上有没有「能搬的建筑」。
# 工作台/熔炉这种拿在手里摆的小设施不算（BUILDINGS 里没有它们）。
func has_movable() -> bool:
	for c in stations.keys():
		if not building_cost(String(stations[c].kind)).is_empty():
			return true
	return false

func level_of(c: Vector2i) -> int:
	if not stations.has(c):
		return 0
	return int(stations[c].get("level", 1))

func set_level(c: Vector2i, lv: int) -> void:
	if not stations.has(c):
		return
	stations[c]["level"] = maxi(1, lv)
	station_changed.emit(c)

# 拆掉（挖回）。返回设施种类（"" 表示本来就没有）
func remove(c: Vector2i) -> String:
	if not stations.has(c):
		return ""
	var kind := String(stations[c].kind)
	stations.erase(c)
	station_removed.emit(c)
	if kind == KIND_HUT:
		Slaves.refresh_cap()             # e44: 小屋拆了, 伙伴上限立刻掉回去
	return kind

# 熔炉点火（扣 1 木头 + 1 铁矿由调用方办，这里只切状态）
func start_smelt(c: Vector2i) -> bool:
	if not stations.has(c):
		return false
	var s: Dictionary = stations[c]
	if String(s.kind) != KIND_FURNACE or String(s.state) != ST_IDLE:
		return false
	s.state = ST_SMELTING
	s.t = 0.0
	station_changed.emit(c)
	return true

# 取走炼好的铁锭（发放铁锭由调用方办，这里只切状态）
func take_iron(c: Vector2i) -> bool:
	if not stations.has(c):
		return false
	var s: Dictionary = stations[c]
	if String(s.kind) != KIND_FURNACE or String(s.state) != ST_READY:
		return false
	s.state = ST_IDLE
	s.t = 0.0
	station_changed.emit(c)
	return true

# 熔炼进度 0~1（提示文字用）
func smelt_progress(c: Vector2i) -> float:
	if not stations.has(c):
		return 0.0
	var s: Dictionary = stations[c]
	if String(s.state) != ST_SMELTING:
		return 0.0
	return clampf(float(s.t) / SMELT_TIME, 0.0, 1.0)

# 玩家所在格附近（切比雪夫距离 radius 格内）有没有工作台。
# 背包 craft 页用这句判定「工作台配方」能不能做。
func near_workbench(player_cell: Vector2i, radius := 2) -> bool:
	for c in stations.keys():
		if String(stations[c].kind) != KIND_WORKBENCH:
			continue
		if maxi(absi(c.x - player_cell.x), absi(c.y - player_cell.y)) <= radius:
			return true
	return false

# 玩家附近有没有铁匠铺（craft 页打造/升级盔甲用）。返回附近最高那座的等级（0 = 附近没有）
func near_blacksmith(player_cell: Vector2i, radius := 2) -> int:
	var best := 0
	for c in stations.keys():
		if String(stations[c].kind) != KIND_BLACKSMITH:
			continue
		if maxi(absi(c.x - player_cell.x), absi(c.y - player_cell.y)) <= radius:
			best = maxi(best, level_of(c))
	return best

# ---------------- 鸡舍（养鸡） ----------------
# e30p: 鸡不走道具链路了（商人不卖小鸡道具），买/卖都在鸡舍管理界面里办；
# 容量改等级制 —— Lv1 住 3 只，每升一级多住 1 只（扩建走管理界面，80*lv 金）
const COOP_UP_FEE := 80     # 扩建基准价（实付 = 80 * 当前等级）
const COOP_BUY_FEE := 120   # 买一只小鸡入住
const COOP_SELL_FEE := 90   # 卖掉一只鸡

func chickens_of(c: Vector2i) -> int:
	if not stations.has(c):
		return 0
	return int(stations[c].get("chickens", 0))

func eggs_of(c: Vector2i) -> int:
	if not stations.has(c):
		return 0
	return int(stations[c].get("eggs", 0))

# 这座鸡舍现在能住几只（随等级涨：Lv1=3 / Lv2=4 / Lv3=5）
func coop_cap_of(c: Vector2i) -> int:
	return 2 + level_of(c)

# 小鸡入住（容量拦住）。返回 true = 住进去了
func add_chicken(c: Vector2i) -> bool:
	if not stations.has(c) or String(stations[c].kind) != KIND_COOP:
		return false
	if chickens_of(c) >= coop_cap_of(c):
		return false
	stations[c]["chickens"] = chickens_of(c) + 1
	station_changed.emit(c)
	return true

# e30p: 卖掉一只鸡（管理界面用）。返回 true = 卖掉了
func remove_chicken(c: Vector2i) -> bool:
	if not stations.has(c) or String(stations[c].kind) != KIND_COOP:
		return false
	if chickens_of(c) <= 0:
		return false
	stations[c]["chickens"] = chickens_of(c) - 1
	station_changed.emit(c)
	return true

# 收蛋：把攒的蛋一次取走（发放由调用方办），返回取到的个数
func take_eggs(c: Vector2i) -> int:
	if not stations.has(c):
		return 0
	var n := int(stations[c].get("eggs", 0))
	stations[c]["eggs"] = 0
	if n > 0:
		station_changed.emit(c)
	return n

# 清晨下蛋：每只鸡下一个（风暴天鸡吓得不下）。返回全岛下了多少个
func lay_eggs(storm: bool) -> int:
	if storm:
		return 0
	var total := 0
	for c in stations.keys():
		var s: Dictionary = stations[c]
		if String(s.kind) != KIND_COOP:
			continue
		var n := int(s.get("chickens", 0))
		if n > 0:
			s["eggs"] = int(s.get("eggs", 0)) + n
			total += n
			station_changed.emit(c)
	return total

# ---------------- 蜂箱（e44b 养蜂） ----------------
# 每天早上每座蜂箱攒 1 罐蜜（冬天蜜蜂不出巢、风暴天也一样不产）。
# 攒够 HIVE_MAX 罐就不再涨 —— 得玩家站旁边按 F 收走，不然一直是个满箱。
const HIVE_MAX := 5

func hive_count() -> int:
	var n := 0
	for c in stations.keys():
		if String(stations[c].kind) == KIND_HIVE:
			n += 1
	return n

func honey_of(c: Vector2i) -> int:
	if not stations.has(c):
		return 0
	return int(stations[c].get("honey", 0))

# 收蜜：把攒的一次全取走（发放由调用方办），返回取到的罐数
func take_honey(c: Vector2i) -> int:
	if not stations.has(c) or String(stations[c].kind) != KIND_HIVE:
		return 0
	var n := int(stations[c].get("honey", 0))
	stations[c]["honey"] = 0
	if n > 0:
		station_changed.emit(c)
	return n

# 清晨产蜜：每座蜂箱 +1（封顶 HIVE_MAX）。返回全岛攒了多少罐
func make_honey(storm: bool, winter: bool) -> int:
	if storm or winter:
		return 0
	var total := 0
	for c in stations.keys():
		var s: Dictionary = stations[c]
		if String(s.kind) != KIND_HIVE:
			continue
		var have := int(s.get("honey", 0))
		if have >= HIVE_MAX:
			continue
		s["honey"] = have + 1
		total += 1
		station_changed.emit(c)
	return total

# ---------------- 储物箱 (e45) ----------------
# e49: 筒仓也走这一套（同一份「格列表」逻辑, 只是外形/造价不同）—— 所以下面所有判定
# 一律走 is_container_kind, 别再直接判 KIND_CHEST, 否则筒仓会变成「点不开的空壳」。
func is_container_kind(kind: String) -> bool:
	return kind == KIND_CHEST or kind == KIND_SILO

# 箱里的东西存成一份「格」列表：[{item: ItemData, count: int}, ...]，最前面是先进去的。
# 同一件东西自动并叠（叠到 max_stack 就另开一格），所以箱里不会出现两行同种东西。
# 存档时按 resource_path 写出去（save_manager 那条老规矩），搬箱子（建筑模式）时整份跟着走。

func chest_items(c: Vector2i) -> Array:
	if not stations.has(c) or not is_container_kind(String(stations[c].kind)):
		return []
	return stations[c].get("items", [])

# 用掉几格（不是几件）：一件东西叠满 max_stack 就再占一格
func chest_used_slots(c: Vector2i) -> int:
	return chest_items(c).size()

func chest_full(c: Vector2i) -> bool:
	return chest_used_slots(c) >= CHEST_SLOTS

# 箱里一共多少件（UI 上显示「共 N 件」用）
func chest_count(c: Vector2i) -> int:
	var n := 0
	for e in chest_items(c):
		n += int((e as Dictionary).get("count", 0))
	return n

# 存进去 n 个，返回实际收下的数量（箱满了就只收得下这么多 —— 不足 1 格也收）
func chest_deposit(c: Vector2i, item: ItemData, n: int) -> int:
	if item == null or n <= 0 or stations.has(c) == false:
		return 0
	if not is_container_kind(String(stations[c].kind)):
		return 0
	if not stations[c].has("items"):
		stations[c]["items"] = []
	var list: Array = stations[c]["items"]
	var left := n
	# 先并到已有的同类叠里
	for e in list:
		if left <= 0:
			break
		var d: Dictionary = e
		if d["item"] == item and int(d["count"]) < item.max_stack:
			var add := mini(item.max_stack - int(d["count"]), left)
			d["count"] = int(d["count"]) + add
			left -= add
	# 再开新格
	while left > 0 and list.size() < CHEST_SLOTS:
		var add2 := mini(item.max_stack, left)
		list.append({"item": item, "count": add2})
		left -= add2
	var got := n - left
	if got > 0:
		station_changed.emit(c)
	return got

# 从第 idx 格取出来：all=true 取整格，否则只取 1 个。
# 返回 {item: ItemData, count: int}（取不出来就是空字典 —— 调用方负责塞进背包）
func chest_take(c: Vector2i, idx: int, all: bool) -> Dictionary:
	var list := chest_items(c)
	if idx < 0 or idx >= list.size():
		return {}
	var d: Dictionary = list[idx]
	var it: ItemData = d.get("item", null)
	if it == null:
		return {}
	var have := int(d.get("count", 0))
	var take := have if all else 1
	take = mini(take, have)
	if take <= 0:
		return {}
	d["count"] = have - take
	if int(d["count"]) <= 0:
		list.remove_at(idx)
	station_changed.emit(c)
	return {"item": it, "count": take}

# 把箱里的东西一次打包给调用方（每一格一项，原样搬走，箱里清空）。
# 拆箱子/全部取出用 —— 调用方按能装多少收多少, 收不下的自己塞回箱里。
func chest_drain(c: Vector2i) -> Array:
	var list := chest_items(c)
	var out := list.duplicate(true)
	list.clear()
	if out.size() > 0:
		station_changed.emit(c)
	return out

# e46 一键整理：把箱里的东西并叠 + 排序（工具排最前, 后面按类型分组, 见 Inventory.arrange）。
# 返回 true = 真的排了（箱里有东西）；空箱没必要动, 让 UI 自己报「箱子是空的」。
func sort_chest(c: Vector2i) -> bool:
	var list := chest_items(c)
	if list.is_empty():
		return false
	stations[c]["items"] = Inventory.arrange(list)
	station_changed.emit(c)
	return true

# ---------------- e49 家畜（畜棚 / 马厩） ----------------
# 一头牲口 = 一个种类 id。住哪几头记在 station 字典的 animals（{种类: 头数}），
# 每天早上**每头各产 1 份**畜产，攒在同格的 produce（{种类: 份数}）里，站旁边按 F 收。
# 为什么按种类分别攒：一份畜产只对应一种物品（牛奶/羊毛/山羊奶/鸭蛋/鸵鸟蛋）,
# 按种类攒才能知道收的时候该发什么、上限该拦谁。
# 收成上限按种类算（攒满 PRODUCE_MAX 就不再涨）—— 跟蜂箱同一个道理, 得人来收。
# 冬天/风暴天不产（跟鸡蛋一套规矩, 见 game 的晨间结算）。
# 卖价 = 买价 x 0.6（活物贬值比死物慢, 但也别指望倒卖赚钱）。
const ANIMAL_COW := "cow"
const ANIMAL_SHEEP := "sheep"
const ANIMAL_GOAT := "goat"
const ANIMAL_DUCK := "duck"
const ANIMAL_OSTRICH := "ostrich"
const ANIMAL_HORSE := "horse"

# 哪种棚能住哪些牲口。马只能进马厩（畜棚是产奶产毛的, 不混养）。
const BARN_ANIMALS := [ANIMAL_COW, ANIMAL_SHEEP, ANIMAL_GOAT, ANIMAL_DUCK, ANIMAL_OSTRICH]
const STABLE_ANIMALS := [ANIMAL_HORSE]

# 种类表：name 界面用；buy 买入价；item 每天产出的物品路径（"" = 不产, 比如马）；
# prod 产出物的中文名（面板上写「牛奶 3 份」用）。
const ANIMALS := {
	ANIMAL_COW: {"name": "牛", "buy": 300, "item": "res://item/milk.tres", "prod": "牛奶"},
	ANIMAL_SHEEP: {"name": "羊", "buy": 240, "item": "res://item/wool.tres", "prod": "羊毛"},
	ANIMAL_GOAT: {"name": "山羊", "buy": 200, "item": "res://item/goat_milk.tres", "prod": "山羊奶"},
	ANIMAL_DUCK: {"name": "鸭", "buy": 160, "item": "res://item/duck_egg.tres", "prod": "鸭蛋"},
	ANIMAL_OSTRICH: {"name": "鸵鸟", "buy": 380, "item": "res://item/ostrich_egg.tres", "prod": "鸵鸟蛋"},
	ANIMAL_HORSE: {"name": "马", "buy": 500, "item": "", "prod": ""},
}

const PRODUCE_MAX := 8       # 同一种畜产在一座棚里最多攒几份（满了等人来收）
const ANIMAL_UP_FEE := 100   # 扩建基准价（实付 = 100 * 当前等级, 跟鸡舍同一套算法）
const BARN_BASE_CAP := 4     # 畜棚 Lv1 住 4 头, 每升一级 +1
const STABLE_BASE_CAP := 3   # 马厩 Lv1 住 3 匹

const WHEAT_PATH := "res://item/wheat.tres"
const FLOUR_PATH := "res://item/flour.tres"

# 这种棚能住哪些牲口（不是畜棚/马厩就返回空 —— 调用方拿它当「这棚能不能养」的判据）
func animal_kinds_for(kind: String) -> Array:
	if kind == KIND_BARN:
		return BARN_ANIMALS
	if kind == KIND_STABLE:
		return STABLE_ANIMALS
	return []

func animal_name(sp: String) -> String:
	return String(ANIMALS.get(sp, {}).get("name", sp))

func animal_buy_fee(sp: String) -> int:
	return int(ANIMALS.get(sp, {}).get("buy", 0))

# 卖价 = 买价 x 0.6（写成函数, 免得面板和别处两套算法对不上）
func animal_sell_fee(sp: String) -> int:
	return int(round(float(animal_buy_fee(sp)) * 0.6))

# 这种牲口每天产什么（物品路径, "" = 不产）
func animal_product_path(sp: String) -> String:
	return String(ANIMALS.get(sp, {}).get("item", ""))

# station 字典里那两个字段是 place() 建的；旧档载入的也补上（免得 get 到处判空）
func animals_dict(c: Vector2i) -> Dictionary:
	if not stations.has(c):
		return {}
	if not stations[c].has("animals"):
		stations[c]["animals"] = {}
	return stations[c]["animals"]

func produce_dict(c: Vector2i) -> Dictionary:
	if not stations.has(c):
		return {}
	if not stations[c].has("produce"):
		stations[c]["produce"] = {}
	return stations[c]["produce"]

func animals_of(c: Vector2i) -> Dictionary:
	return animals_dict(c)

func count_of_species(c: Vector2i, sp: String) -> int:
	return int(animals_dict(c).get(sp, 0))

# 这座棚一共住了几头（容量判定用）
func animal_count_of(c: Vector2i) -> int:
	var n := 0
	for sp in animals_dict(c):
		n += int(animals_dict(c)[sp])
	return n

# 这座棚能住几头（Lv1 = BARN_BASE_CAP/STABLE_BASE_CAP, 每升一级 +1）
func animal_cap_of(c: Vector2i) -> int:
	var k := kind_of(c)
	if k == KIND_BARN:
		return BARN_BASE_CAP + level_of(c)
	if k == KIND_STABLE:
		return STABLE_BASE_CAP + level_of(c)
	return 0

# 买一头入住（钱由调用方扣）。返回 true = 住进去了
func add_animal(c: Vector2i, sp: String) -> bool:
	if not stations.has(c):
		return false
	if not animal_kinds_for(kind_of(c)).has(sp):
		return false                      # 这种牲口住不进这种棚
	if animal_count_of(c) >= animal_cap_of(c):
		return false                      # 住满了
	var a := animals_dict(c)
	a[sp] = int(a.get(sp, 0)) + 1
	station_changed.emit(c)
	return true

# 卖掉一头（钱由调用方加）。返回 true = 卖掉了
func remove_animal(c: Vector2i, sp: String) -> bool:
	if not stations.has(c):
		return false
	if count_of_species(c, sp) <= 0:
		return false
	var a := animals_dict(c)
	a[sp] = int(a[sp]) - 1
	if int(a[sp]) <= 0:
		a.erase(sp)
		# 卖走了这个种类的最后一头, 那份没来得及收的畜产也跟着走 ——
		# 不然棚里会留一份「无主的奶」, 收的时候还得现查还有没有这种牲口。
		produce_dict(c).erase(sp)
	station_changed.emit(c)
	return true

# 某座棚某种畜产攒了几份 / 一共攒了几份
func produce_of_species(c: Vector2i, sp: String) -> int:
	return int(produce_dict(c).get(sp, 0))

func produce_count(c: Vector2i) -> int:
	var n := 0
	for sp in produce_dict(c):
		n += int(produce_dict(c)[sp])
	return n

# 收某种畜产：一次全取走发进背包。返回 {item: ItemData, count: int}（没得收返回 {}）。
# 背包塞不下的部分放回棚里（不白扣玩家的东西）。
func take_produce_item(c: Vector2i, sp: String) -> Dictionary:
	if not stations.has(c):
		return {}
	var path := animal_product_path(sp)
	if path == "":
		return {}
	var n := produce_of_species(c, sp)
	if n <= 0:
		return {}
	var it: ItemData = load(path)
	if it == null:
		return {}
	produce_dict(c).erase(sp)
	var got := grant_with_refund(it, n, null)
	if got < n:
		produce_dict(c)[sp] = int(produce_dict(c).get(sp, 0)) + (n - got)
	if got > 0:
		station_changed.emit(c)
	return {"item": it, "count": got}

# 清晨产畜产：畜棚/马厩里每头产 1 份（风暴天/冬天不产, 跟鸡蛋一样）。
# 返回全岛产了多少份 total + 每种收到多少（{种类: 份数}）—— 面板按种类报「牛奶 +2」。
func make_animal_produce(storm: bool, winter: bool) -> Dictionary:
	var out := {"total": 0, "by_species": {}}
	if storm or winter:
		return out
	for c in stations.keys():
		var s: Dictionary = stations[c]
		var k := String(s.kind)
		if k != KIND_BARN and k != KIND_STABLE:
			continue
		var a: Dictionary = s.get("animals", {})
		if a.is_empty():
			continue
		var p: Dictionary = s.get("produce", {})
		var touched := false
		for sp in a:
			var heads := int(a[sp])
			if heads <= 0:
				continue
			if animal_product_path(String(sp)) == "":
				continue                  # 马不产东西
			var have := int(p.get(sp, 0))
			var add := mini(heads, PRODUCE_MAX - have)
			if add <= 0:
				continue
			p[sp] = have + add
			out["total"] = int(out["total"]) + add
			out["by_species"][sp] = int(out["by_species"].get(sp, 0)) + add
			touched = true
		if touched:
			station_changed.emit(c)
	return out

# 发 n 份 item 进背包；装不下的退回 n 份同名 fallback（拿什么换的就退什么, 玩家不亏）。
# 返回实际发出去多少份。磨面/收畜产共用（Inventory.add_item 是「能塞多少塞多少」,
# 单看它的返回值分不清「一份没进」和「进了一半」, 所以这里前后各数一次库存再对账）。
func grant_with_refund(item: ItemData, n: int, fallback: ItemData) -> int:
	if item == null or n <= 0:
		return 0
	var before := Inventory.count_item(item)
	if Inventory.add_item(item, n):
		return n
	# add_item 是「能塞多少塞多少」: 加完再数一次, 差值才是本次真到手的份数,
	# 剩下的按 fallback 退回去（fallback = null 表示调用方自己负责退, 比如退回棚里）。
	var got := maxi(0, Inventory.count_item(item) - before)
	var back := n - got
	if back > 0 and fallback != null:
		Inventory.add_item(fallback, back)
	return got

# ---------------- e49 磨坊 ----------------
# 按 F 把背包里的小麦全磨成面粉（1:1）。磨坊的意义是「把 5 金的原料变成 22 金的货」,
# 不烧钱也不烧时间 —— 想更硬核可以以后按人天排队, 现在没必要。
# 返回磨了几袋；没小麦返回 0（调用方拿它决定提示什么）。
func mill_grind(c: Vector2i) -> int:
	if not stations.has(c) or String(stations[c].kind) != KIND_MILL:
		return 0
	var wheat: ItemData = load(WHEAT_PATH)
	var flour: ItemData = load(FLOUR_PATH)
	if wheat == null or flour == null:
		return 0
	var have := Inventory.count_item(wheat)
	if have <= 0:
		return 0
	Inventory.remove_item(wheat, have)
	var got := grant_with_refund(flour, have, wheat)
	if got > 0:
		station_changed.emit(c)
	return got

# ---------------- e49 农场建筑的 F 派发 ----------------
# 这一批新建筑 game 不认识（_station_interact_cell 是硬编码 kind 的 match, 新 kind
# 走不到任何分支），所以 F 得有别的路认领。两条路都留着, 谁先跑谁吃这一下:
#   1) farm_building_node 自己在 _unhandled_input 里认领（不依赖 game）—— 默认生效;
#   2) game._station_interact_cell 里加一行 `if Structures.interact_farm(c): return true`
#      —— 想走 game 的老派发时用, 两条路同时存在也只开一次面板（见下面 activate 的守卫）。
# 为什么留第 2 条：_unhandled_input 在父节点与子节点之间的传播次序不好保证,
# 多这一条能让父代理一行接死, 不必赌顺序。
func interact_farm(c: Vector2i) -> bool:
	var n := _farm_node_of(c)
	if n == null:
		return false
	n.call("activate")
	return true

# 按格子找那座农场建筑的显示节点（节点自己进了 farm_station 组并记着 cell）。
func _farm_node_of(c: Vector2i) -> Node:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("farm_station"):
		var v: Variant = n.get("cell")
		if v != null and Vector2i(v) == c:
			return n
	return null
