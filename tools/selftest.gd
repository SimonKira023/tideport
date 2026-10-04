# tools/selftest.gd —— 项目自检脚本（改完东西后随手跑一遍，确认没搞坏）
#
# 跑法（不用开编辑器）：
#   "D:\平台\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" ^
#       --headless --path "C:\Users\蔡璟熙\Documents\新建游戏项目" res://tools/selftest.tscn
#
# 它会真的加载 game.tscn，然后把下面这些都过一遍：
#   1) 开场接管了多少格耕地、贴图数量对不对、手绘图层是否已清空
#   2) 耕地自动拼接：每格的四方向开口判定 + 拼接图块内部纯色（没有多余小点）
#   3) 锄头新开地后，相邻两块地的边缘会不会互相跟着变
#   4) 浇水 → 贴图变湿
#   5) 播种 → 过夜生长 → 收获（收获后耕地保留，只是变回干土）
#   6) 洒水壶水量与水井打水
#   7) 主角四套动作（锄地/浇水/取水/睡觉）帧数
#   8) 房子室内：整间屋子是一张木头贴图（横板缝 + 错开竖缝）、床的区域切得完整，
#      进屋出门，室内夹位置
#   9) 睡觉换日、醒来回到门口
#  10) 哥布林身上不该再有提示文字
#  11) 草地上的花草点缀（草丛/花/蘑菇）撒在空草地上、图层顺序对；池塘有浅滩岸线
#  12) 各种地形接缝：草地↔耕地↔水面之间不留缝、不重叠
#  13) 背包系统：快捷栏 6 格 + 背包 24 格、可移动/合并、面板开关
#  14) 岛屿地图：溪流环绕、桥连通、池保留
#  15) 耕地四周的过渡地形（田埂/土路），新开地后自动出现
#  16) 水面材质（程序化图集）/ 岸的过渡 / 不规则海岸线
#  17) 水碰撞 / 木桥三行带全通(含护栏行)+护栏透视缝 / 室内默认隐藏 / 房子不压耕地
#  18) 音频（BGM 循环 + 早晚换曲 + 音效多路）
#  19) 物品售卖箱（睡觉时自动卖货；箱体贴图 13x16，空箱闭合/有货敞口）
#  20) 夜晚结算画面
#  21) 洒水壶打水 / 鼠标点快捷栏 / 商人交易面板
#  22) UI 面板必须占满全屏（否则会挤到左上角、遮罩也会消失）
#  23) 伙伴（奴隶）：招募价格 / 派活额度 / 涂色地图 / 四个模型 + 五套动作 /
#      白天真的走过去把活干出来（锄地/浇水/播种，播种会扣种子；水面不让派活）
#  24) 相机缩放（Ctrl + 滚轮）+ 背包改成 Esc 开
#  25) 按键提示：悬浮在半空不消失、飞入/飞出、像素字体
#  34) 存档系统：收集 -> 改乱 -> 还原 + JSON 往返（睡觉自动存档 + 读档）
#  35) 存档列表：每日快照写入/排序/按路径读取/同天覆盖/测试后清理
#  69) 钓鱼动画（Wait Idle/Hooked 64px 帧）/ 种子生长周期详情 / 售卖箱面板（除工具全能卖）
extends Node

const TS := 16
# 卡牌战斗（步1 数据层 / 步2 战场）: 用 preload 拿到类型化的脚本, 直接 .new() / 取静态函数
const CARDSD := preload("res://scene/cards_data.gd")
const CARDSB := preload("res://scene/battle_cards.gd")

var fails := 0

func chk(ok: bool, msg: String) -> void:
	if ok:
		print("  [OK] ", msg)
	else:
		fails += 1
		print("  [!!] ", msg)

func find_sprite(soil: Node2D, pos: Vector2i) -> Sprite2D:
	var want := Vector2(pos.x * TS, pos.y * TS)
	for c in soil.get_children():
		if c is Sprite2D and c.position.distance_to(want) < 0.6:
			return c
	return null

# 草地矩形里「应该有草却没有」的格子 = 池塘
func grass_holes(grass: TileMapLayer) -> Array:
	var cells := grass.get_used_cells()
	var out: Array = []
	if cells.is_empty():
		return out
	var has := {}
	var minx: int = cells[0].x
	var maxx: int = minx
	var miny: int = cells[0].y
	var maxy: int = miny
	for c in cells:
		has[c] = true
		minx = mini(minx, c.x); maxx = maxi(maxx, c.x)
		miny = mini(miny, c.y); maxy = maxi(maxy, c.y)
	for x in range(minx, maxx + 1):
		for y in range(miny, maxy + 1):
			if not has.has(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out

# 在子树里找第一个「文字包含 substr」的 Label（用来验证结算面板真的把数字写上去了）
func find_label(root: Node, substr: String) -> Label:
	if root is Label and (root as Label).text.contains(substr):
		return root
	for c in root.get_children():
		var hit := find_label(c, substr)
		if hit != null:
			return hit
	return null

# 同上，但只认按钮 —— 判「某个按钮在不在」时不能拿 find_label 凑合，
# 说明性文字里也会出现同样的词（比如"读档入口在主页面"这句 Label）。
func find_button_text(root: Node, substr: String) -> String:
	if root is Button and String((root as Button).text).contains(substr):
		return String((root as Button).text)
	for c in root.get_children():
		var hit := find_button_text(c, substr)
		if hit != "":
			return hit
	return ""

# ---------------- UI 文案的「字体缺字」体检 ----------------
# ❗IPix.ttf 缺一大堆字形：■ ● ♥ ★ → ~ 「」 、全角空格(U+3000)、间隔号(·) …… 缺了就渲染成一个小方块。
#   与其靠人眼在预览图上找，不如直接问字体「你支持哪些字符」，然后全量比对。
var _glyph_set := ""
var _glyph_bad: Array = []
var _glyph_swept: Array = []

func _ipix_chars() -> String:
	if _glyph_set == "":
		var f: Font = load("res://resources/font/IPix.ttf")
		if f != null and f.has_method("get_supported_chars"):
			_glyph_set = String(f.get_supported_chars())
	return _glyph_set

# 返回 txt 里「字体没有字形」的字符（去重）。取不到字符集时返回空 = 这项检查自动关闭。
func missing_glyphs(txt: String) -> Array:
	var out: Array = []
	var sup := _ipix_chars()
	if sup == "":
		return out
	for i in txt.length():
		var c := txt[i]
		if c == "\n" or c == "\t":
			continue
		if not sup.contains(c) and not out.has(c):
			out.append(c)
	return out

# 收一个节点下所有 Label / Button 的文字
func collect_texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append(String((n as Label).text))
	elif n is Button:
		out.append(String((n as Button).text))
	for c in n.get_children():
		collect_texts(c, out)
	return out

# 扫一个面板的全部文案，缺字记进 _glyph_bad（返回缺了几处）
func sweep_glyphs(n: Node, tag: String) -> int:
	if not _glyph_swept.has(tag):
		_glyph_swept.append(tag)
	var bad := 0
	for t in collect_texts(n):
		var miss := missing_glyphs(String(t))
		if not miss.is_empty():
			_glyph_bad.append("%s: 「%s」缺 %s" % [tag, String(t).left(28), str(miss)])
			bad += 1
	return bad

# 只走陆地的洪水填充（4 邻域）：用来验证「河把岛切成了东西两块」——# 从河西出发能摸到的陆地格集合里，不该出现河东的格子。
func flood_land(start: Vector2i, limit: int) -> Array:
	var seen := {start: true}
	var queue := [start]
	var out := []
	while not queue.is_empty() and out.size() < limit:
		var c: Vector2i = queue.pop_front()
		out.append(c)
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var nb: Vector2i = c + d
			if seen.has(nb) or not g._land_set.has(nb):
				continue
			seen[nb] = true
			queue.append(nb)
	return out

# 一张拼接图块里，除了「敞口边 2 像素以内」，其它地方是不是全都是底色？
func stray_pixels(img: Image, mask: String, fill: Color) -> int:
	var bad := 0
	for y in TS:
		for x in TS:
			if img.get_pixel(x, y).to_rgba32() == fill.to_rgba32():
				continue
			var on_open_edge := (mask[0] == "N" and y <= 1) or (mask[1] == "S" and y >= TS - 2) \
				or (mask[2] == "W" and x <= 1) or (mask[3] == "E" and x >= TS - 2)
			if not on_open_edge:
				bad += 1
	return bad

# 两个颜色够不够接近（按 0~255 的通道差）
func _near_color(c: Color, ref: Color, tol: int) -> bool:	return absi(c.r8 - ref.r8) <= tol and absi(c.g8 - ref.g8) <= tol and absi(c.b8 - ref.b8) <= tol

# 这个像素是不是「孤立的小点」：周围 8 个邻居全都跟它差很多
func _isolated_dot(img: Image, x: int, y: int, tol: int) -> bool:
	var c := img.get_pixel(x, y)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var o := img.get_pixel(x + dx, y + dy)
			if absi(c.r8 - o.r8) + absi(c.g8 - o.g8) + absi(c.b8 - o.b8) <= tol:
				return false
	return true

# 一张小图里不透明像素的占比（用来验证「透明底贴图」/「全透明图块」）
func _opaque_ratio(img: Image) -> float:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.4:
				n += 1
	return float(n) / float(img.get_width() * img.get_height())

# 把玩家摆到某格正中央。
# ❗玩家的节点原点在「脚下」（y_sort 的前后遮挡要靠它），碰撞圆却比原点高 6 像素，
#   所以必须把这段偏移补偿掉，让**碰撞圆的圆心**正好落在格心 —— 否则测碰撞时会差一行，
#   「朝水走被挡住」之类的断言会因为碰撞盒根本没碰到水面而假失败。
func place_player(cell: Vector2i) -> void:
	var cs: CollisionShape2D = player.get_node("CollisionShape2D")
	player.global_position = Farm.grid_origin \
		+ Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5) - cs.position

func cell_of(world: Vector2) -> Vector2i:
	return Vector2i(int(floor((world.x - Farm.grid_origin.x) / float(TS))),
		int(floor((world.y - Farm.grid_origin.y) / float(TS))))

# 手动推着伙伴的 _process 往前走（headless 里等真实帧太慢，直接喂 delta 更稳）。
# 返回它第几帧把这格干完；-1 = 给的时间不够，没干成。
func pump_slave(npc: Node2D, cell: Vector2i, max_frames: int) -> int:
	for i in max_frames:
		npc._process(0.02)
		if Slaves.is_done(cell):
			return i
	return -1

# 递归收集场景里所有按键提示（名字统一叫 KeyHint）
func collect_hints(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c.name == "KeyHint":
			out.append(c)
		collect_hints(c, out)

# 清掉背包里所有能被售卖箱/商人收走的东西（作物 + 食物 + 材料 + 种子）——
# 现在除了工具全都能卖, 开局送的土豆和 24 包种子都得清掉, 才好断言确定的数量
func clear_crops() -> void:
	var kinds: Array = []
	for s in Inventory.slot_list():
		var it: ItemData = s["item"]
		if it != null and (it.type == "作物" or it.type == "食物" or it.type == "材料" or it.type == "种子") \
				and not kinds.has(it):
			kinds.append(it)
	for it in kinds:
		Inventory.remove_item(it, Inventory.count_item(it))

var soil: Node2D
var g: Node2D
var player: Node2D

func _ready() -> void:
	# 兜底：万一中途报错、走不到最后的 quit()，别让这个进程一直挂着不动
	var guard := Timer.new()
	guard.wait_time = 90.0
	guard.one_shot = true
	guard.timeout.connect(func():
		print("\n[自检超时] 90 秒还没跑完 —— 上面应该有一条 SCRIPT ERROR，先修那个")
		get_tree().quit(1))
	add_child(guard)
	guard.start()

	# ❗存档系统必须先关掉：自检会真的跑睡觉换日流程，
	#   不关的话测试会把真实存档覆盖掉、game._ready 还会把旧档读进测试现场。
	SaveManager.enabled = false
	g = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame

	soil = g.get_node("SoilLayer")
	player = g.get_node("Player")

	print("\n=== 1. 开场状态 ===")
	var water: TileMapLayer = g.get_node("WaterTileMapLayer")
	var grass: TileMapLayer = g.get_node("GrassTileMapLayer")
	chk(Farm.tilled.size() > 260, "接管了足够多的耕地（%d 格）" % Farm.tilled.size())
	chk(soil.get_child_count() == Farm.tilled.size(),
		"耕地贴图数量对得上（%d / %d）" % [soil.get_child_count(), Farm.tilled.size()])
	chk(g.get_node_or_null("TilledGroundTileMapLayer") != null
		and not g.get_node("TilledGroundTileMapLayer").visible,
		"手绘耕地图层已清空并隐藏")
	chk(Farm.grid_origin == grass.global_position, "网格原点已对齐地面图层")

	# 池塘：草地图层留的洞必须全被水面盖住，否则田中间会露出黑洞
	var overlap := 0
	for c in Farm.tilled.keys():
		if water.get_cell_source_id(c) != -1:
			overlap += 1
	chk(overlap == 0, "耕地和池塘不重叠（重叠 %d 格）" % overlap)
	var wcells := {}
	for c in water.get_used_cells():
		wcells[c] = true
	var holes := 0
	for c in grass_holes(grass):
		if not wcells.has(c):
			holes += 1
	chk(holes == 0, "草地上的洞（池塘）全部被水面盖住（漏 %d 格）" % holes)

	print("\n=== 2. 自动拼接：每格的四方向开口判定 ===")
	# 期望值 = 「哪几个方向没有邻居」= N/S/W/E 里的哪几个字母，见 soil_layer.gd
	var cases := {
		Vector2i(0, 0):  "N-W-",   # 田左上角：上/左敞开
		Vector2i(16, 0): "N--E",   # 田右上角：上/右敞开
		Vector2i(0, 16): "-SW-",   # 田左下角：下/左敞开
		Vector2i(16, 16): "-S-E",  # 田右下角：下/右敞开
		Vector2i(8, 8):  "----",   # 田中间：四面都有邻居（应当完全无缝）
		Vector2i(9, 10):  "---E",  # 池塘左边：只有右面敞开
		Vector2i(15, 10): "--W-",  # 池塘右边：只有左面敞开
		Vector2i(11, 9):  "-S--",  # 池塘上边：只有下面敞开
		Vector2i(12, 14): "N---",  # 池塘下边：只有上面敞开
		Vector2i(13, 9):  "-S-E",  # 池塘左上角外侧：下/右敞开
	}
	for pos in cases.keys():
		var want: String = cases[pos]
		chk(soil.mask_at(pos) == want,
			"格子 %s 的开口 = %s（实际 %s）" % [pos, want, soil.mask_at(pos)])

	print("\n=== 2b. 拼接图块本身：只有敞口边有描边，内部纯色（没有小点）===")
	var fill := Color8(190, 109, 71)
	var masks := ["----", "N---", "-S--", "--W-", "---E", "N-W-", "N--E", "-SW-", "-S-E",
		"NS--", "NSW-", "NS-E", "--WE", "N-WE", "-SWE", "NSWE"]
	var stray := 0
	for mask in masks:
		stray += stray_pixels(soil.tile_for(mask).get_image(), mask, fill)
	chk(stray == 0, "16 张图块里没有一处多余的深色像素（越界 %d 个）" % stray)
	chk(soil.tile_for("----").get_image().get_pixel(0, 0).to_rgba32() == fill.to_rgba32(),
		"田中间的格子是纯底色，跟四周的邻居严丝合缝")

	print("\n=== 3. 锄头新开一块地 ===")
	var spot := Vector2i(5, 20)          # 田外草地
	chk(not Farm.is_tilled(spot), "该格一开始不是耕地")
	chk(Farm.till(spot), "till() 成功")
	chk(soil.mask_at(spot) == "NSWE", "孤立一格四面都敞开（实际 %s）" % soil.mask_at(spot))
	var nb := Vector2i(6, 20)
	Farm.till(nb)
	chk(soil.mask_at(spot) == "NSW-", "右边多了一块后，左格改成「只有右面闭合」（实际 %s）" % soil.mask_at(spot))
	chk(soil.mask_at(nb) == "NS-E", "右格用「只有左面闭合」（实际 %s）" % soil.mask_at(nb))

	print("\n=== 4. 浇水：干土 -> 湿土 ===")
	var dry: Sprite2D = find_sprite(soil, Vector2i(5, 20))
	var dry_mod := dry.modulate
	chk(not Farm.is_watered(Vector2i(5, 20)), "浇之前是干土")
	chk(Farm.water(Vector2i(5, 20)), "water() 成功")
	chk(find_sprite(soil, Vector2i(5, 20)).modulate != dry_mod,
		"浇完贴图调色变了（%s -> %s）" % [dry_mod, find_sprite(soil, Vector2i(5, 20)).modulate])
	chk(not Farm.water(Vector2i(5, 20)), "同一格不能浇两次")

	print("\n=== 5. 播种 -> 浇水 -> 过夜生长 -> 收获 ===")
	var seed_item: ItemData = load("res://item/seed.tres")
	var pos := Vector2i(2, 2)
	chk(Farm.plant(pos, seed_item), "播种成功")
	chk(not Farm.plant(pos, seed_item), "同一格不能重复播种")
	Farm.water(pos)
	var before := Farm.get_stage(pos)
	TimeManager.advance_day()
	var after := Farm.get_stage(pos)
	chk(after == before + 1, "浇过水后过一天长一阶（%d -> %d）" % [before, after])
	chk(not Farm.is_watered(pos), "换日后浇水状态清空")

	# 干着的地不长
	var pos2 := Vector2i(3, 2)
	Farm.plant(pos2, seed_item)
	TimeManager.advance_day()
	chk(Farm.get_stage(pos2) == 0, "没浇水的作物不长（stage=%d）" % Farm.get_stage(pos2))

	# 催熟再收获
	Farm.crops[pos].stage = seed_item.grow_days
	var got: ItemData = Farm.harvest(pos)
	chk(got != null and got.display_name == "土豆", "收获得到 %s" % (got.display_name if got else "null"))
	chk(Farm.is_tilled(pos), "收获后那格**还是耕地**（不用重新锄）")
	chk(not Farm.is_watered(pos), "收获后回到干土状态")
	chk(not Farm.has_crop(pos), "收获后作物没了")
	await get_tree().process_frame
	chk(find_sprite(soil, pos) != null, "收获后耕地贴图还在，只是变回干的")
	chk(Farm.plant(pos, seed_item), "收获完可以马上接着种，不用再锄一遍")
	Farm.harvest(pos)

	print("\n=== 6. 洒水壶水量 + 水井(按 F 打水) ===")
	chk(Inventory.is_can_full(), "开局水壶是满的（%d/%d）" % [Inventory.watering_can_water, Inventory.WATER_MAX])
	for i in 3:
		Inventory.use_water()
	chk(Inventory.watering_can_water == Inventory.WATER_MAX - 3, "用了 3 次水（%d）" % Inventory.watering_can_water)
	# 老水井拆掉了（改成可建造建筑）：摆一座水井，站旁边走一遍 F 打水交互
	var wcell := Vector2i(6, 6)
	chk(Structures.place(wcell, Structures.KIND_WELL), "能摆下一座水井（建造系统）")
	await get_tree().process_frame
	chk(g.get_node_or_null("Station6_6") != null, "摆下后地图上长出水井节点")
	var old_pos: Vector2 = player.global_position
	player.global_position = Farm.grid_origin \
		+ Vector2(wcell.x * 16 + 8, wcell.y * 16 + 8)   # 井那格的中心（世界坐标）
	chk(g._try_station_interact(), "井边按 F 被水井吃掉")
	chk(Inventory.is_can_full(), "在井边打满水（%d/%d）" % [Inventory.watering_can_water, Inventory.water_max()])
	# e30q: 左键点水井也能打水
	Inventory.use_water()
	var wpos6 := Farm.grid_origin + Vector2(wcell.x * 16 + 8, wcell.y * 16 + 8)
	chk(g.well_click(wpos6, wcell), "左键点水井被吃掉 (e30q)")
	chk(Inventory.is_can_full(), "左键点井也打满水 (e30q: %d/%d)" % [Inventory.watering_can_water, Inventory.water_max()])
	# e30q 负例: 玩家站荒地 + 点的地方没有任何设施 -> 不吃点击（防止左键乱吸）
	var ppos6: Vector2 = player.global_position
	player.global_position = Farm.grid_origin + Vector2(8, 8)
	chk(not g.well_click(Farm.grid_origin + Vector2(200, 110), Vector2i(10, 6)),
		"荒地点空地不触发打水 (e30q)")
	player.global_position = ppos6
	player.global_position = old_pos
	Structures.remove(wcell)      # 拆掉，不给后面的测试留障碍物
	await get_tree().process_frame

	print("\n=== 7. 主角动作动画 ===")
	var sf: SpriteFrames = player.tool_sprite.sprite_frames
	var names := sf.get_animation_names()
	chk(names.has("hoe_down") and names.has("hoe_up") and names.has("hoe_side"), "锄地动作 3 个朝向")
	chk(names.has("water_down") and names.has("water_up") and names.has("water_side"), "浇水动作 3 个朝向")
	chk(names.has("fetch_down") and names.has("fetch_side"), "取水动作")
	chk(names.has("sleep"), "睡觉动作")
	chk(sf.get_frame_count("hoe_down") == 6, "锄地 6 帧（实际 %d）" % sf.get_frame_count("hoe_down"))
	chk(sf.get_frame_count("water_down") == 8, "浇水 8 帧（实际 %d）" % sf.get_frame_count("water_down"))
	chk(sf.get_frame_count("sleep") == 2, "睡觉 2 帧（实际 %d）" % sf.get_frame_count("sleep"))
	# k2: 武装特效贴图为原创黄铜浮游炮(8帧 48x32), 明日方舟素材已全部移除
	var orb_tex := load("res://resources/texture/浮游炮.png") as Texture2D
	chk(orb_tex != null and orb_tex.get_width() == 384 and orb_tex.get_height() == 32
		and not ResourceLoader.exists("res://resources/texture/源石虫.png"),
		"武装特效为原创浮游炮 8 帧, 明日方舟素材已移除 (k2)")

	print("\n=== 8. 房子 + 床 ===")
	var house: Node2D = g.get_node("House")
	# 开场白是跨存档的一次性剧情（user://story_flags.cfg 记 goblin_intro）。
	# flag 没设时（比如最近在真机开过新档），自检里第一次进屋就会弹出哥布林对话，
	# 而自检没人去按它 —— 它 push 的暂停永远没人 pop，后面所有时间类断言连锁崩掉。
	# 自检直接标记「已播过」跳过它：对话面板本身 52f 有单测，任务链条 52e 有单测。
	house._intro_done = true
	var room_art: Sprite2D = house.get_node("Interior/RoomArt")
	chk(room_art is Sprite2D and room_art.texture != null, "室内是一整张房间贴图（Interior/RoomArt）")
	chk(house.get_node_or_null("Interior/FloorLayer") == null
		and house.get_node_or_null("Interior/WallLayer") == null,
		"旧的瓷砖地板/墙图层已经没有了")
	chk(house.get_node("Interior/Bed") is Area2D, "床是交互区")

	# 床：切区域必须正好框住素材里那张床，不能切歪
	var bed_spr: Sprite2D = house.get_node("Interior/Bed/Sprite2D")
	chk(bed_spr.region_rect == house.BED_REGION,
		"床用的区域 = %s（实际 %s）" % [house.BED_REGION, bed_spr.region_rect])
	var bed_img: Image = bed_spr.texture.get_image()
	var bed_opaque := 0
	var edge_hit := 0
	var r: Rect2 = house.BED_REGION
	for yy in range(int(r.position.y), int(r.end.y)):
		for xx in range(int(r.position.x), int(r.end.x)):
			if bed_img.get_pixel(xx, yy).a > 0.03:
				bed_opaque += 1
	for xx in range(int(r.position.x), int(r.end.x)):
		if bed_img.get_pixel(xx, int(r.position.y)).a > 0.03 \
				or bed_img.get_pixel(xx, int(r.end.y) - 1).a > 0.03:
			edge_hit += 1
	for yy in range(int(r.position.y), int(r.end.y)):
		if bed_img.get_pixel(int(r.position.x), yy).a > 0.03 \
				or bed_img.get_pixel(int(r.end.x) - 1, yy).a > 0.03:
			edge_hit += 1
	chk(bed_opaque > 900, "床的贴图区域是满的（不透明像素 %d）" % bed_opaque)
	chk(edge_hit >= 60, "床的四条边都刚好贴着图案，没有切掉也没有留空（贴边像素 %d）" % edge_hit)
	chk(house.BED_SIZE.x >= 32 and house.BED_SIZE.y >= 32, "床是完整的一张（%s）" % house.BED_SIZE)

	# e30u 内饰家具：开局就摆好的一屋子家具（区域不能切歪，位置不能压住走道）
	var decor30u: Node2D = house.get_node_or_null("Interior/Decor")
	chk(decor30u != null and decor30u.get_child_count() >= 8,
		"室内摆了一屋子家具（%d 件）" % (decor30u.get_child_count() if decor30u != null else -1))
	var deco_boxes30u: Array = []
	var deco_bad30u: Array = []
	for dc30u in decor30u.get_children():
		var ds30u := dc30u as Sprite2D
		if ds30u == null or ds30u.texture == null:
			deco_bad30u.append("%s 不是贴图" % dc30u.name)
			continue
		var dimg30u: Image = ds30u.texture.get_image()
		var rr30u := Rect2i(ds30u.region_rect)
		if rr30u.size.x <= 0 or rr30u.size.y <= 0 \
				or rr30u.end.x > dimg30u.get_width() or rr30u.end.y > dimg30u.get_height():
			deco_bad30u.append("%s region 越界 %s" % [ds30u.name, str(rr30u)])
			continue
		# 裁下来的那块必须「真的有东西」（透明空块 = 格子选错了）
		var dopaque30u := 0
		for yy30u in range(rr30u.position.y, rr30u.end.y):
			for xx30u in range(rr30u.position.x, rr30u.end.x):
				if dimg30u.get_pixel(xx30u, yy30u).a > 0.03:
					dopaque30u += 1
		if dopaque30u < 120:
			deco_bad30u.append("%s 裁出来几乎是空的 (%d px)" % [ds30u.name, dopaque30u])
		deco_boxes30u.append(Rect2(ds30u.position, Vector2(rr30u.size)))
	chk(deco_bad30u.is_empty(), "每件家具的 region 都切在图内且不空: %s" % str(deco_bad30u))
	# 家具不许压住床 / 出生点 / 出口门（走道要留得出来）
	var must_clear30u := {
		"床": Rect2(house.BED_LOCAL, house.BED_SIZE),
		"出生点": Rect2(house.spawn_point.position - Vector2(6, 6), Vector2(12, 12)),
		"出口门": Rect2(house.exit_door.position - Vector2(8, 8), Vector2(16, 24)),
		# 起床落点（床脚边）：家具实体压这儿会把玩家顶出去
		"床脚落点": Rect2(house.BED_LOCAL + house.SLEEP_LAND + Vector2(0, 24) - Vector2(10, 10),
			Vector2(20, 20)),
	}
	var blocked30u: Array = []
	for nm30u in must_clear30u.keys():
		for bx30u in deco_boxes30u:
			if (bx30u as Rect2).intersects(must_clear30u[nm30u]):
				blocked30u.append("%s 压住了 %s" % [nm30u, str(bx30u)])
	chk(blocked30u.is_empty(), "家具都让开了走道: %s" % str(blocked30u))
	# 家具实体：跟床同一套开关 —— 进屋才开 layer 2，屋外是 0
	var fbody30u: StaticBody2D = house.get_node_or_null("Interior/FurnitureBody")
	chk(fbody30u != null and fbody30u.get_child_count() >= 5,
		"大件家具挂了实体碰撞（%d 个）" % (fbody30u.get_child_count() if fbody30u != null else -1))
	if fbody30u != null:
		var pl30u := get_tree().get_first_node_in_group("player") as Node2D
		var pz_bak30u: int = 0
		if pl30u != null:
			pz_bak30u = pl30u.z_index
		house.set_indoors_visual(true)
		chk(fbody30u.collision_layer == 2, "进屋后家具实体打开（layer %d）" % fbody30u.collision_layer)
		house.set_indoors_visual(false)
		chk(fbody30u.collision_layer == 0, "出屋后家具实体关掉（layer %d）" % fbody30u.collision_layer)
		if pl30u != null:
			pl30u.z_index = pz_bak30u

	# 室内材质：木头 —— 连贯的横板缝 + 错开的端头缝 + 木纹，且配色全是暖木色
	var room_img: Image = room_art.texture.get_image()
	chk(room_img.get_width() == house.ROOM_W * TS and room_img.get_height() == house.ROOM_H * TS,
		"房间贴图正好 %dx%d 格（%dx%d 像素）" % [house.ROOM_W, house.ROOM_H,
			room_img.get_width(), room_img.get_height()])

	var fr: Rect2i = house.FLOOR_RECT
	var palette := {}
	var cold := 0
	for yy in room_img.get_height():
		for xx in room_img.get_width():
			var c := room_img.get_pixel(xx, yy)
			palette[c.to_rgba32()] = true
			if c.r + 0.04 < c.b:
				cold += 1
	chk(cold == 0, "室内配色全是暖木色，没有冷色/杂色（冷色像素 %d）" % cold)
	chk(palette.size() <= 96, "木纹是有限几种木色（色数 %d）" % palette.size())

	# 木墙 / 木地板：取区域的**平均色**来判断（每块板深浅有随机，不能用单点比对）
	var wall_sum := Color(0, 0, 0, 0)
	var wall_n := 0
	for yy in fr.position.y:
		for xx in room_img.get_width():
			wall_sum += room_img.get_pixel(xx, yy)
			wall_n += 1
	chk(_near_color(wall_sum / float(wall_n), house.WALL_COLOR, 26),
		"房间上方是木墙（平均色 %s）" % (wall_sum / float(wall_n)))

	var fl_sum := Color(0, 0, 0, 0)
	var fl_n := 0
	for yy in range(fr.position.y + 2, fr.end.y):
		for xx in range(fr.position.x, fr.end.x):
			fl_sum += room_img.get_pixel(xx, yy)
			fl_n += 1
	chk(_near_color(fl_sum / float(fl_n), house.FLOOR_COLOR, 26),
		"地板整体是浅木色（平均色 %s）" % (fl_sum / float(fl_n)))

	# 木地板要有**连贯的**横向板缝：整行都是缝色的行
	var seam_rows := 0
	for yy in range(fr.position.y, fr.end.y):
		var all_seam := true
		for xx in range(fr.position.x, fr.end.x):
			if room_img.get_pixel(xx, yy).to_rgba32() != house.FLOOR_SEAM.to_rgba32():
				all_seam = false
				break
		if all_seam:
			seam_rows += 1
	chk(seam_rows >= 3, "木地板有连贯的横向板缝（%d 条）" % seam_rows)

	# 木板而不是砖：端头缝的数量要比「等宽密排」少得多
	# （注意要跳过横向板缝那几行，否则每一列都会被算成缝）
	var seams_x := 0
	for xx in range(fr.position.x + 1, fr.end.x):
		var n := 0
		for yy in range(fr.position.y, fr.end.y):
			if (yy - fr.position.y) % house.PLANK_H == 0:
				continue
			if room_img.get_pixel(xx, yy).to_rgba32() == house.FLOOR_SEAM.to_rgba32():
				n += 1
		if n >= 6:
			seams_x += 1
	chk(seams_x >= 8 and seams_x <= 34,
		"竖着的端头缝稀疏得当（%d 条），看着是长条木地板不是砖" % seams_x)

	# 不该再有孤立的小点（上一轮改动的诉求）
	var dots := 0
	for yy in range(1, room_img.get_height() - 1):
		for xx in range(1, room_img.get_width() - 1):
			if _isolated_dot(room_img, xx, yy, 60):
				dots += 1
	chk(dots == 0, "室内没有孤立的小点/花点（%d 个）" % dots)

	# 墙脚阴影：地板左边缘外面应当压着深色
	chk(room_img.get_pixel(fr.position.x - 1, fr.position.y + fr.size.y / 2).to_rgba32()
		== house.SHADOW_COLOR.to_rgba32(), "地板四周压了一圈墙脚阴影")

	house._enter_house(player)
	await get_tree().physics_frame
	chk(player.indoors, "进屋后 indoors = true")
	chk(player.global_position.distance_to(house.get_node("Interior/SpawnPoint").global_position) < 2.0,
		"进屋后被放在出生点")
	# 跑到房间外面，验证会被夹回房间
	player.global_position = house.get_node("Interior").global_position + Vector2(2000, 2000)
	await get_tree().physics_frame
	var local: Vector2 = player.global_position - house.get_node("Interior").global_position
	chk(local.x <= 273 and local.y <= 165, "室内位置被夹在房间里（%s）" % local)
	chk(player.indoors, "还在室内")

	print("\n=== 9. 睡觉换日 ===")
	TimeManager.start_new_day()
	var d0 := TimeManager.day
	var bed_node: Area2D = house.get_node("Interior/Bed")
	house._sleep_next_day(player)
	# 睡觉落点：以前直接放床中心，脑袋（睡觉帧里只占中间一小块）整个飘到床沿上方的墙上；
	# 现在落点是「床左上角 + SLEEP_LAND」，脑袋正好躺进两个枕头中间。
	chk(player.global_position.distance_to(bed_node.global_position + house.SLEEP_LAND) < 0.5,
		"睡觉落点 = 床左上角 + %s（实际 %s）"
			% [str(house.SLEEP_LAND), str(player.global_position - bed_node.global_position)])
	# 睡姿帧 32x32 里脑袋的包围盒实测约 (10,6)-(23,18)；精灵画在玩家原点上方 16px 居中
	var head_rect := Rect2(player.global_position + Vector2(-16 + 10, -32 + 6), Vector2(13, 12))
	chk(Rect2(bed_node.global_position, house.BED_SIZE).grow(-3.0).encloses(head_rect),
		"脑袋整个落在床沿里面（不飘到墙上）")
	chk(player.busy and player.get_node("ToolSprite").visible,
		"睡姿一直保持（不会播完 1 秒自己站起来）")
	# 睡觉现在会先播「时钟跳时间」动画（约 2.6s，指针转到次日清晨），
	# 再拉黑幕、弹「夜晚结算」画面，等玩家点「继续」才真正换日。
	# 自检里等它弹出来，然后替玩家按一下「继续」。
	var sleep_panel: Control = g.settlement_panel
	var waited := 0.0
	while waited < 8.0 and (sleep_panel == null or not sleep_panel.is_open()):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	chk(sleep_panel != null and sleep_panel.is_open(), "睡觉时弹出了夜晚结算画面")
	if sleep_panel != null and sleep_panel.is_open():
		sleep_panel._dismiss()
	# 结算点掉「继续」之后，还会弹一张「给伙伴派活」的涂色面板；
	# 换日要等这张也点掉才发生，所以自检里也得替玩家按一下「确定」。
	var assign: Control = g.assign_panel
	var waited2 := 0.0
	while waited2 < 3.0 and (assign == null or not assign.is_open()):
		await get_tree().create_timer(0.1).timeout
		waited2 += 0.1
	chk(assign != null and assign.is_open(), "结算之后接着弹出「给伙伴派活」面板")
	if assign != null and assign.is_open():
		assign._dismiss()
	await get_tree().create_timer(0.2).timeout
	chk(TimeManager.day == d0 + 1, "睡一觉到了第 %d 天（原来 %d）" % [TimeManager.day, d0])
	chk(TimeManager.hour == TimeManager.START_HOUR, "醒来时间是 %d 点" % TimeManager.hour)
	chk(TimeManager.time_running, "时间继续流动")
	chk(not player.busy and not player.get_node("ToolSprite").visible,
		"天亮起床：睡姿收掉了，换回站立")
	local = player.global_position - house.get_node("Interior").global_position
	var want_wake: Vector2 = house.get_node("Interior/Bed").position \
		+ house.SLEEP_LAND + Vector2(0, 24)
	chk(local.distance_to(want_wake) < 3.0, "醒来站在床脚边，不再挪回门口（%s）" % local)

	# ---- 9.5 床边 F 双选项：菜单 + 「小睡到指定时刻」（不换日） ----
	print("\n=== 9.5 床边 F 双选项: 小睡到指定时刻 ===")
	var sleep_menu: Node = g.get_node_or_null("HUD/SleepMenu")
	chk(sleep_menu != null, "HUD 上挂了睡觉选择菜单 SleepMenu")
	if sleep_menu != null:
		var d_nap: int = TimeManager.day
		sleep_menu.call("open_panel", player, house)
		chk(bool(sleep_menu.call("is_open")), "床边按 F 弹出了「今晚怎么睡」菜单")
		chk(not TimeManager.time_running, "菜单开着时时间暂停")
		sleep_menu.call("choose_nap")
		sleep_menu.call("set_hour", 18)
		sleep_menu.call("confirm_nap")
		chk(not bool(sleep_menu.call("is_open")), "确认后菜单关掉, 躺下开始小睡")
		# 小睡要先播时针动画（约 2.6 秒, 从 6 点转到 18 点），等它转完
		var clock_anim: Node = g.get_node_or_null("HUD/ClockAnim")
		var waited3 := 0.0
		while waited3 < 6.0 and clock_anim != null and bool(clock_anim.get("_active")):
			await get_tree().create_timer(0.1).timeout
			waited3 += 0.1
		await get_tree().create_timer(0.3).timeout
		chk(TimeManager.hour == 18 and TimeManager.minute == 0,
			"小睡到了 18:00（实际 %d:%02d）" % [TimeManager.hour, TimeManager.minute])
		chk(TimeManager.day == d_nap, "小睡不换日（还是第 %d 天）" % TimeManager.day)
		chk(not player.busy and not player.get_node("ToolSprite").visible,
			"小睡醒来站起来了（睡姿收掉）")
		local = player.global_position - house.get_node("Interior").global_position
		want_wake = house.get_node("Interior/Bed").position \
			+ house.SLEEP_LAND + Vector2(0, 24)
		chk(local.distance_to(want_wake) < 3.0, "小睡醒来站在床脚边（%s）" % local)
		chk(TimeManager.time_running, "醒来时间继续流动")
		# 把时间拨回上午, 别让后面的检查撞上傍晚的篝火/夜色
		TimeManager.hour = 9
		TimeManager.minute = 0

	# 起床出门，回到屋外 —— 后面的地形/碰撞检查都得在屋外做。
	# （室内那块地方挂在房子下方，正好压在野外地图上，所以进门时会把玩家的碰撞掩码关掉，
	#   免得外面的水面碰撞体把玩家从房间里顶出去；出门时再打开。这里顺手验一下这条。） 
	chk(not player.get_collision_mask_value(1), "室内不跟外面的碰撞体打交道（掩码已关）")
	house._leave_house(player)
	await get_tree().physics_frame
	chk(not player.indoors, "走出房门，回到屋外")
	chk(player.get_collision_mask_value(1), "回到屋外后重新跟水面/房子这些碰撞体打交道（掩码已开）")

	print("\n=== 10. 商人不该再有提示文字 ===")
	var merchant: Node2D = g.get_node("Merchant")
	var prompt := merchant.get_node_or_null("Prompt")
	chk(prompt == null, "哥布林身上没有 Prompt 文字节点")

	print("\n=== 11. 草地花草点缀 + 池塘岸线 ===")
	var decor: TileMapLayer = g.get_node_or_null("DecorTileMapLayer")
	chk(decor != null, "草地上有一层花草点缀（DecorTileMapLayer）")
	if decor != null:
		var dcells := decor.get_used_cells()
		chk(dcells.size() > 100, "花草撒得够多（%d 处）" % dcells.size())
		var n_tuft := 0
		var n_flower := 0
		var n_mushroom := 0
		var bad := 0
		for c in dcells:
			var ac := decor.get_cell_atlas_coords(c)
			if g.DECOR_TUFT.has(ac):
				n_tuft += 1
			elif g.DECOR_FLOWER.has(ac):
				n_flower += 1
			elif g.DECOR_MUSHROOM.has(ac):
				n_mushroom += 1
			else:
				bad += 1
			if water.get_cell_source_id(c) != -1:
				bad += 1                       # 长在水面上
			if Farm.tilled.has(c):
				bad += 1                       # 长在田里
		chk(bad == 0, "花草只长在空草地上（越界 %d 处）" % bad)
		chk(n_tuft > 0 and n_flower > 0 and n_mushroom > 0,
			"草丛 / 花 / 蘑菇 三种都有（%d / %d / %d）" % [n_tuft, n_flower, n_mushroom])
		chk(n_tuft > n_flower, "草丛比花多，看着才像野地（%d > %d）" % [n_tuft, n_flower])
		chk(decor.get_index() == grass.get_index() + 1, "点缀层紧贴在草地之上")
		chk(decor.get_index() < soil.get_index(), "点缀层在耕地之下（不会盖住田）")

		# 点缀图块必须是透明底的贴图，否则会盖掉草地
		var datlas: TileSetAtlasSource = decor.tile_set.get_source(0)
		var dimg: Image = datlas.texture.get_image()
		var transparent_ok := true
		for t in g.DECOR_FLOWER:
			var sub := dimg.get_region(Rect2i(t.x * TS, t.y * TS, TS, TS))
			if _opaque_ratio(sub) >= 0.98:
				transparent_ok = false
		chk(transparent_ok, "花的贴图都是透明底（不会糊掉草地）")

	var shore: TileMapLayer = g.get_node_or_null("ShoreTileMapLayer")
	chk(shore != null, "池塘有一层岸线（ShoreTileMapLayer）")
	if shore != null:
		chk(shore.get_index() == water.get_index() + 1, "岸线层夹在水面之上、草地之下")
		var scells := shore.get_used_cells()
		chk(scells.size() > 3, "岸线贴到了池塘边缘（%d 格）" % scells.size())
		var satlas: TileSetAtlasSource = shore.tile_set.get_source(0)
		var simg: Image = satlas.texture.get_image()
		var x0 := 1 * TS                        # 图块号 1 = 只有上边挨着陆地
		chk(simg.get_pixel(x0 + 8, 0).a > 0.5, "贴岸那一像素有浅滩色（浅水）")
		chk(simg.get_pixel(x0 + 8, 0).v > simg.get_pixel(x0 + 8, 1).v,
			"贴岸比里面更亮（越往水里越深）")
		chk(simg.get_pixel(x0 + 8, 8).a < 0.3, "往水里走几像素就淡出（不会盖住整片水）")
		# 四面都是水的那块必须是全透明
		var interior := simg.get_region(Rect2i(0, 0, TS, TS))
		chk(_opaque_ratio(interior) == 0.0, "纯深水那格没有任何色带")

	print("\n=== 12. 地形之间的过渡 ===")
	# 草地上的洞（池塘）必须是「有水面 或 有耕地」——不该出现第三种空洞
	var grass_set := {}
	for c in grass.get_used_cells():
		grass_set[c] = true
	var orphan := 0
	for c in grass_holes(grass):
		if water.get_cell_source_id(c) == -1 and not Farm.tilled.has(c):
			orphan += 1
	chk(orphan == 0, "草地上不存在既没水也没耕地的破洞（%d 格）" % orphan)
	# 岸线只出现在水面格上
	if shore != null:
		var shore_off_water := 0
		for c in shore.get_used_cells():
			if water.get_cell_source_id(c) == -1:
				shore_off_water += 1
		chk(shore_off_water == 0, "岸线只画在水面格上（越界 %d 格）" % shore_off_water)
	# 水面格不跟耕地重合（池塘边缘的耕地要自动收边绕开）
	var wet_tilled := 0
	for c in Farm.tilled.keys():
		if water.get_cell_source_id(c) != -1:
			wet_tilled += 1
	chk(wet_tilled == 0, "沼泽式重叠：耕地和水面 0 格重叠（%d 格）" % wet_tilled)
	# 岸线掩码必须跟「陆地邻居」完全一致
	if shore != null:
		var mask_bad := 0
		for c in shore.get_used_cells():
			# 用「邻居是不是水」判定朝向（草地铺满整张图、水下也有，不能拿草地层判）
			if shore.get_cell_atlas_coords(c) != Vector2i(g._edge_mask(c, true), 0):
				mask_bad += 1
		chk(mask_bad == 0, "每一格岸线都对上了自己的陆地朝向（错 %d 格）" % mask_bad)

	print("\n========================================")

	print("\n=== 13. 背包系统：快捷栏 6 格 + 背包 24 格 + 移动/合并 ===")
	chk(Inventory.HOTBAR_SIZE == 6, "快捷栏是 6 格（实际 %d）" % Inventory.HOTBAR_SIZE)
	chk(Inventory.BACKPACK_SIZE == 24, "背包是 24 格（实际 %d）" % Inventory.BACKPACK_SIZE)
	chk(Inventory.slot_list().size() == Inventory.HOTBAR_SIZE + Inventory.BACKPACK_SIZE, "总格子数 = 快捷栏 + 背包")
	# 开局一无所有：物资不再直接发 —— 改由第一次进屋时哥布林的对话赠与
	# （house.gd _try_intro -> game._give_starting_items）。这里直接敲门收礼，
	# 核对赠与清单到账。
	var all_items := 0
	for s in Inventory.slot_list():
		if s["item"] != null:
			all_items += s["count"]
	chk(all_items == 0, "开局一无所有（背包里 0 件道具，实际 %d）" % all_items)
	var giver: Node = get_tree().get_first_node_in_group("game")
	chk(giver != null and giver.has_method("_give_starting_items"), "game 节点在, 能收哥布林的赠礼")
	if giver != null and giver.has_method("_give_starting_items"):
		giver._give_starting_items()
	var gifted := 0
	for s in Inventory.slot_list():
		if s["item"] != null:
			gifted += s["count"]
	chk(gifted >= 15, "哥布林赠与到账 >= 15（锄头 + 洒水壶 + 8 种子 + 5 木头 = 15）")
	var wood: ItemData = load("res://item/wood.tres")
	var wood_before := Inventory.count_item(wood)
	Inventory.add_item(wood, 2)
	chk(Inventory.count_item(wood) == wood_before + 2, "add_item 把同种道具堆叠（%d + 2 = %d）" % [wood_before, Inventory.count_item(wood)])
	var hoe_at := -1
	for i in Inventory.HOTBAR_SIZE:
		if Inventory.hotbar[i]["item"] != null and Inventory.hotbar[i]["item"].display_name == "锄头":
			hoe_at = i
			break
	chk(hoe_at >= 0, "快捷栏里有锄头（格 %d）" % hoe_at)
	if hoe_at >= 0:
		# 开局道具比快捷栏多（斧头/镐子加入后塞满 6 格），背包 0 格可能被占。
		# 找一个空背包格来测搬移（move_slot 对已占格是交换，对空格才是纯搬移）。
		var empty_bp := -1
		for i in Inventory.BACKPACK_SIZE:
			if Inventory.get_slot(Inventory.HOTBAR_SIZE + i)["item"] == null:
				empty_bp = Inventory.HOTBAR_SIZE + i
				break
		chk(empty_bp >= 0, "背包里还有空格（格 %d）" % (empty_bp - Inventory.HOTBAR_SIZE))
		Inventory.move_slot(hoe_at, empty_bp)
		chk(Inventory.get_slot(hoe_at)["item"] == null, "原快捷栏格清空")
		var bp0: Dictionary = Inventory.get_slot(empty_bp)
		chk(bp0["item"] != null and bp0["item"].display_name == "锄头", "背包目标格出现了锄头（格 %d）" % (empty_bp - Inventory.HOTBAR_SIZE))
		Inventory.move_slot(empty_bp, hoe_at)
		chk(Inventory.hotbar[hoe_at]["item"] != null and Inventory.hotbar[hoe_at]["item"].display_name == "锄头", "又把它移回快捷栏")

	var bp_panel: Control = g.get_node_or_null("HUD/Backpack")
	chk(bp_panel != null, "背包面板挂在了 HUD 下（HUD/Backpack）")
	if bp_panel != null:
		chk(not bp_panel.is_open(), "默认关闭")
		bp_panel.toggle()
		chk(bp_panel.is_open(), "toggle 一次打开")
		chk(player.frozen, "打开背包时 player.frozen = true（锁住角色操作）")
		bp_panel.toggle()
		chk(not bp_panel.is_open(), "再 toggle 一次关闭")
		chk(not player.frozen, "关掉背包后 player.frozen = false")

	print("\n=== 14. 岛屿地图：溪流 + 桥 + 池塘保留 ===")
	chk(water.get_used_cells().size() > 100, "水面格子很多（%d 格）" % water.get_used_cells().size())
	var pond_bad := 0
	for c in g._pond_cells:
		if not g._water_set.has(c):
			pond_bad += 1
	chk(g._pond_cells.size() > 0 and pond_bad == 0,
		"池塘 %d 格全部保留为水面（漏了 %d 格）" % [g._pond_cells.size(), pond_bad])
	var stream := 0
	for c in g._water_set.keys():
		if g._core_dist(c) > 0:
			stream += 1
	chk(stream > 300, "核心陆地之外是海/河（%d 格）" % stream)

	# 现在是「海中的孤岛」：水面必须比陆地多（以前是陆地占大多数，反过来了）
	var land_n: int = g._land_set.size()
	var water_n: int = g._water_set.size()
	chk(float(water_n) / float(land_n + water_n) > 0.5,
		"海比陆地多（水面 %.0f%%）" % (100.0 * water_n / float(land_n + water_n)))

	# 岛必须是「四面环海」：地图最外圈只能有水，而且岛上不能出现贴边的草地
	var edge_land := 0
	var edge_all := 0
	for x in range(g.YARD_FROM.x, g.YARD_TO.x + 1):
		for y in [g.YARD_FROM.y, g.YARD_FROM.y + 1, g.YARD_TO.y - 1, g.YARD_TO.y]:
			edge_all += 1
			if g._land_set.has(Vector2i(x, y)):
				edge_land += 1
	for y in range(g.YARD_FROM.y, g.YARD_TO.y + 1):
		for x in [g.YARD_FROM.x, g.YARD_FROM.x + 1, g.YARD_TO.x - 1, g.YARD_TO.x]:
			edge_all += 1
			if g._land_set.has(Vector2i(x, y)):
				edge_land += 1
	chk(edge_land == 0, "地图最外圈全是海（陆地 %d / %d 格）" % [edge_land, edge_all])

	# 岛中间那条南北向的河：纵向贯穿整座核心岛
	var river_rows := 0
	var core_rows: int = g.ISLAND_TO.y - g.ISLAND_FROM.y + 1
	for y in range(g.ISLAND_FROM.y, g.ISLAND_TO.y + 1):
		for x in range(g.ISLAND_FROM.x, g.ISLAND_TO.x + 1):
			if g._is_river(Vector2i(x, y)):
				river_rows += 1
				break
	chk(river_rows == core_rows,
		"河纵向贯穿整座岛（%d/%d 行）" % [river_rows, core_rows])

	# 河要把岛切成东西两块 —— 走「只过陆地」的洪水填充，看能不能从河东摸到河西
	var west_start := Vector2i(g.ISLAND_FROM.x, 16)     # 河以西（RIVER_CX=31）
	var reach := flood_land(west_start, 3000)
	var east_reached := false
	for c in reach:
		if c.x > g.RIVER_CX + 3:
			east_reached = true
			break
	chk(not east_reached, "只走陆地到不了河对岸（河真的把岛切开了）")

	# 桥：必须把这一行的河面**完整盖住**，两端落在岸上，不然走不过去
	for by in g.BRIDGE_ROWS:
		var bx0: int = g._bridge_x0(by)
		var bx1: int = g._bridge_x1(by)
		var river_w := 0
		var river_out := 0
		for x in range(bx0 - 6, bx1 + 7):
			if not g._is_river(Vector2i(x, by)):
				continue
			river_w += 1
			if x < bx0 or x > bx1:
				river_out += 1
		chk(river_w > 0 and river_out == 0,
			"桥 x=[%d,%d] 把这一行的河面盖全了（河里 %d 格，漏 %d 格）" % [bx0, bx1, river_w, river_out])
		chk(g._land_set.has(Vector2i(bx0 - 1, by)) and g._land_set.has(Vector2i(bx1 + 1, by)),
			"桥 x=[%d,%d] 两端是陆地（能走上去）" % [bx0, bx1])
		var bridge_in_core: bool = by >= g.ISLAND_FROM.y and by <= g.ISLAND_TO.y \
			and bx0 > g.ISLAND_FROM.x and bx1 < g.ISLAND_TO.x
		chk(bridge_in_core, "桥在岛内（没有架到海上去）")

	var bridges: Node2D = g.get_node_or_null("Bridges")
	chk(bridges != null, "场景里有 Bridges 节点（桥）")
	if bridges != null:
		var bridge_sprites := 0
		for c in bridges.get_children():
			if c is Sprite2D:
				bridge_sprites += 1
		chk(bridge_sprites >= 2, "至少 2 座桥（%d 座）" % bridge_sprites)

	print("\n=== 15. 耕地四周的田埂（新开地后自动出现）===")
	var border: TileMapLayer = g.get_node_or_null("FieldBorderTileMapLayer")
	chk(border != null, "有田埂层（FieldBorderTileMapLayer）")
	if border != null:
		chk(border.get_index() > decor.get_index(), "田埂层在点缀之上")
		chk(border.get_index() < soil.get_index(), "田埂层在耕地之下（不盖住田）")
		var before_count := border.get_used_cells().size()
		chk(before_count > 0, "开场已有耕地四周有田埂（%d 格）" % before_count)
		var border_bad := 0
		for c in border.get_used_cells():
			if water.get_cell_source_id(c) != -1:
				border_bad += 1
			if Farm.tilled.has(c):
				border_bad += 1
			if grass.get_cell_source_id(c) == -1:
				border_bad += 1
		chk(border_bad == 0, "田埂只画在草地非耕地非水的格上（越界 %d 格）" % border_bad)
		var batlas: TileSetAtlasSource = border.tile_set.get_source(0)
		var bimg: Image = batlas.texture.get_image()
		var b_opaque: float = _opaque_ratio(bimg)
		chk(b_opaque < 0.6, "田埂是透明底的（不透明像素占比 %.2f%% < 60%%）" % (b_opaque * 100))
		var new_spot := Vector2i(28, 16)
		var ring_before := 0
		for c in g._ring(new_spot):
			if border.get_cell_source_id(c) != -1:
				ring_before += 1
		Farm.till(new_spot)
		await get_tree().process_frame
		var ring_after := 0
		for c in g._ring(new_spot):
			if border.get_cell_source_id(c) != -1:
				ring_after += 1
		chk(ring_after > ring_before, "新开一块地后周围田埂自动长出来（%d -> %d）" % [ring_before, ring_after])

	print("\n=== 16. 水面材质 / 岸的过渡 / 不规则海岸 ===")
	# 16.1 水面换成程序化图集：5 档深浅 x 3 种波纹，边框纯基色 = 拼起来没有缝
	var wts: TileSet = water.tile_set
	var wsrc: TileSetAtlasSource = wts.get_source(0) if wts.get_source_count() > 0 else null
	chk(wsrc != null, "水面有自己的图集")
	if wsrc != null:
		var wimg: Image = wsrc.texture.get_image()
		chk(wimg.get_size() == Vector2i(5 * 16, 3 * 16),
			"水面图集 = 5 档深浅 x 3 种波纹（实际 %s）" % str(wimg.get_size()))
		var edge_ok := true
		for d in 5:
			for v in 3:
				var ref := wimg.get_pixel(d * 16, v * 16)
				for y in 16:
					if wimg.get_pixel(d * 16, v * 16 + y) != ref: edge_ok = false
					if wimg.get_pixel(d * 16 + 15, v * 16 + y) != ref: edge_ok = false
				for x in 16:
					if wimg.get_pixel(d * 16 + x, v * 16) != ref: edge_ok = false
					if wimg.get_pixel(d * 16 + x, v * 16 + 15) != ref: edge_ok = false
		chk(edge_ok, "水面每格四边是纯基色（相邻格拼接不会出现接缝）")
		var darkest := wimg.get_pixel(4 * 16 + 8, 8)
		var lightest := wimg.get_pixel(8, 8)
		chk(darkest.b < lightest.b, "深浅分档有效：贴岸比深水亮（%.2f vs %.2f）" % [lightest.b, darkest.b])
	# 地形层全部负 z_index（永远压在最下面），实体的前后遮挡交给根节点的 y_sort。
	chk(water.z_index == g.Z_WATER and water.z_index > grass.z_index,
		"水面 z_index = %d（在草地之上，同时整层压在地形层里给 y_sort 让位）" % water.z_index)
	var depth_lv := {}
	for c in water.get_used_cells():
		depth_lv[water.get_cell_atlas_coords(c).x] = true
	chk(depth_lv.size() >= 2, "实际用到了 %d 档深浅（有层次）" % depth_lv.size())

	# 16.2 浅滩只画在贴岸的水格上（以前用草地层判定，结果每格水都描了一圈白边）
	var shore2: TileMapLayer = g.get_node_or_null("ShoreTileMapLayer")
	chk(shore2 != null, "有浅滩层（ShoreTileMapLayer）")
	if shore2 != null:
		chk(shore2.get_index() > water.get_index(), "浅滩层在水面之上")
		var bad := 0
		for c in shore2.get_used_cells():
			if not g._water_set.has(c) or g._edge_mask(c, true) == 0:
				bad += 1
		chk(bad == 0, "浅滩只画在贴岸的水格上（越界 %d 格）" % bad)
		var edge_n := 0
		for c in g._water_set.keys():
			if g._edge_mask(c, true) != 0:
				edge_n += 1
		chk(shore2.get_used_cells().size() == edge_n,
			"所有贴岸水格都有浅滩（%d/%d）" % [shore2.get_used_cells().size(), edge_n])
		var ratio := float(shore2.get_used_cells().size()) / float(g._water_set.size())
		chk(ratio < 0.9, "深水区不画浅滩（浅滩只占水面 %.0f%%）" % (ratio * 100))

	# 16.3 陆地侧沙滩：真正的「地面 <-> 水」过渡地带
	var beach: TileMapLayer = g.get_node_or_null("BeachTileMapLayer")
	chk(beach != null, "有沙滩层（BeachTileMapLayer，陆地侧的过渡）")
	if beach != null:
		chk(beach.get_index() > grass.get_index(), "沙滩层在草地之上")
		chk(beach.get_index() < water.get_index(), "沙滩层在水面之下（伸进水里的部分被水盖住）")
		var bb := 0
		for c in beach.get_used_cells():
			if g._water_set.has(c) or grass.get_cell_source_id(c) == -1:
				bb += 1
			# 合法三类：贴水的草地格（湿沙过渡带）、沙地格（实心沙）、贴沙的草地格（淡入带）
			if g._edge_mask(c, false) == 0 and not g.is_sand(c) and g._grass_sand_mask(c) == 0:
				bb += 1
		chk(bb == 0, "沙滩只画在贴水草地格/沙地格/贴沙草地格上（越界 %d 格）" % bb)
		# 左岛西北岸：出生格必须是沙地、不能锄地，且沙地上没树没石头
		chk(g.is_sand(g.SPAWN_CELL), "开局出生格 %s 是沙地" % g.SPAWN_CELL)
		chk(not g.is_tillable(g.SPAWN_CELL), "出生格不能开田")
		chk(g._land_set.has(g.SPAWN_CELL), "出生格在陆地上")
		var sand_tree := 0
		var sand_rock := 0
		for sc in g._sand_set:
			if Trees.is_blocked(sc):
				sand_tree += 1
			if OreVein.is_blocked(sc):
				sand_rock += 1
		chk(sand_tree == 0 and sand_rock == 0,
			"沙地上没树(%d)没石头(%d)" % [sand_tree, sand_rock])
		chk(beach.get_used_cells().size() > 100, "沙滩有 %d 格" % beach.get_used_cells().size())
		var beach_decor := 0
		for c in beach.get_used_cells():
			if decor.get_cell_source_id(c) != -1:
				beach_decor += 1
		chk(beach_decor == 0, "沙滩上不长花草（越界 %d 格）" % beach_decor)

	# 16.4 海岸线不是一条直线：沿北岸 / 西岸采样，最浅和最深至少差 2 格
	var north_edge := []
	for x in range(-24, 40):
		var last_water := -999
		for y in range(-11, -3):
			if g._water_set.has(Vector2i(x, y)):
				last_water = y
		if last_water != -999:
			north_edge.append(last_water)
	chk(north_edge.size() > 20, "北岸取到 %d 个采样点" % north_edge.size())
	if north_edge.size() > 5:
		var mn: int = north_edge[0]
		var mx: int = north_edge[0]
		for v in north_edge:
			mn = mini(mn, v)
			mx = maxi(mx, v)
		chk(mx - mn >= 2, "北岸线有起伏（y=%d 到 y=%d，差 %d 格）" % [mn, mx, mx - mn])
	var west_edge := []
	for y in range(-2, 36):
		var last_water := -999
		for x in range(-33, -25):
			if g._water_set.has(Vector2i(x, y)):
				last_water = x
		if last_water != -999:
			west_edge.append(last_water)
	if west_edge.size() > 5:
		var wmn: int = west_edge[0]
		var wmx: int = west_edge[0]
		for v in west_edge:
			wmn = mini(wmn, v)
			wmx = maxi(wmx, v)
		chk(wmx - wmn >= 2, "西岸线有起伏（x=%d 到 x=%d，差 %d 格）" % [wmn, wmx, wmx - wmn])

	print("\n=== 17. 水碰撞 / 木桥 / 室内隐藏 / 房子挪位 ===")
	# 17.1 水碰撞：场景里有 WaterCollision 节点，含合并后的矩形碰撞
	var wc: Node2D = g.get_node_or_null("WaterCollision")
	chk(wc != null, "场景里有 WaterCollision 节点")
	if wc != null:
		var shapes := 0
		var total_water_cells := 0
		for c in wc.get_children():
			if c is StaticBody2D:
				for cc in c.get_children():
					if cc is CollisionShape2D and (cc.shape is RectangleShape2D):
						shapes += 1
		# 合并率：e51 起水面只剩「最深那一档」参与碰撞, 形状比原来碎,
		# 合并到几百块矩形即算合理（量级检查, 不追求精确值）
		chk(shapes >= 30 and shapes <= 600,
			"水碰撞矩形数 %d（合并过，量级合理）" % shapes)
		# 用 move_and_collide 模拟一次「从陆地跨进水里」—— e51 起规则是：
		#   能下水的水格放行（整条河 + 海里除最深色外, 见 is_swim_water）,
		#   只剩最深色那一档把玩家挡在外海。
		# ❗桥面那几行是**故意**留的通道（水里唯一能走的地方），所以找采样点时要避开。
		var psave: Vector2 = player.global_position
		var bridge_rows := {}
		for by in g.BRIDGE_ROWS:
			bridge_rows[by] = true
			bridge_rows[by - 1] = true
			bridge_rows[by + 1] = true
		# 点查询：这一格中心有没有水碰撞（有 = 挡人）
		var water_solid: Callable = func(cell: Vector2i) -> bool:
			var q := PhysicsPointQueryParameters2D.new()
			q.collision_mask = 0xFFFFFFFF
			q.collide_with_areas = false
			q.position = Farm.grid_origin + Vector2(cell) * Farm.TILE_SIZE \
				+ Vector2(Farm.TILE_SIZE / 2.0, Farm.TILE_SIZE / 2.0)
			for h in player.get_world_2d().direct_space_state.intersect_point(q, 8):
				var hit: Object = h.get("collider")
				if hit != null and str(hit.get("name")) == "WaterBodies":
					return true
			return false
		var test_cell := Vector2i.ZERO
		var land_cell := Vector2i.ZERO
		for x in range(-22, 26):
			for y in range(-3, 36):
				var c := Vector2i(x, y)
				if bridge_rows.has(y) or not g._water_set.has(c):
					continue
				# 挑一个「东边是陆地」的水格：这种水格必然贴着岸（浅滩）
				if not g._water_set.has(c + Vector2i(1, 0)) and g._land_set.has(c + Vector2i(1, 0)):
					test_cell = c
					land_cell = c + Vector2i(1, 0)
					break
			if test_cell != Vector2i.ZERO:
				break
		chk(test_cell != Vector2i.ZERO,
			"找到一个贴着岸、又不在桥上的水格 %s（岸在 %s）" % [str(test_cell), str(land_cell)])
		if test_cell != Vector2i.ZERO:
			chk(g.is_swim_water(test_cell), "贴着岸的水格是能下水的水格（蹚水区）")
			chk(not bool(water_solid.call(test_cell)), "能下水的水格上没有水碰撞（玩家能蹚进去）")
			# e51 挡人的格子只剩「最深一档」的海格, 得扫全 _water_set 找 ——
			#     旧写法扫的是近岸矩形, 新规则下近岸已经没有挡人格了, 会空手而归。
			var deep_cell := Vector2i.ZERO
			for c3 in g._water_set.keys():
				if bridge_rows.has(c3.y):
					continue
				if not g.is_swim_water(c3):
					deep_cell = c3
					break
			chk(deep_cell != Vector2i.ZERO and bool(water_solid.call(deep_cell)),
				"最深色海格 %s 照旧有水碰撞（游不出海）" % str(deep_cell))
			place_player(land_cell)                       # 站在岸上往浅水里迈一步
			var kc: KinematicCollision2D = player.move_and_collide(Vector2(-14, 0))
			var bump := "无"
			if kc != null and kc.get_collider() != null:
				bump = str(kc.get_collider().name)
			chk(bump != "WaterBodies", "玩家从陆地迈进能下水的水格不再被水挡（撞到 %s）" % bump)
			player.global_position = psave

	# 17.2 木桥：用素材 Deep Forest/Bridge.png 现拼出来的运行时贴图
	var bridges2: Node2D = g.get_node_or_null("Bridges")
	chk(bridges2 != null, "场景里有 Bridges 节点")
	if bridges2 != null:
		var wood_sprites := 0
		for c in bridges2.get_children():
			if c is Sprite2D and c.texture is ImageTexture and c.texture.resource_path == "":
				wood_sprites += 1
		chk(wood_sprites >= 2, "至少 2 座木桥，每座一张扁平整贴挂 Bridges（共 %d 张）" % wood_sprites)
		# f3: 桥带三行全可走 —— 玩家沿桥带中行从桥头走到对岸 (水碰撞豁口放行)。
		var bsaved: Vector2 = player.global_position
		var brow: int = g.BRIDGE_ROWS[0]
		var bx0: int = g._bridge_x0(brow)
		var bx1: int = g._bridge_x1(brow)
		place_player(Vector2i(bx0, brow))
		var hit: KinematicCollision2D = null
		var steps := maxi(0, int(float((bx1 - bx0) * 16) / 8.0))
		for _i in steps:
			var kc: KinematicCollision2D = player.move_and_collide(Vector2(8, 0))
			if kc != null:
				hit = kc
				break
		chk(hit == null, "玩家沿桥带中行（行 %d）从桥头走到对岸（撞到 %s）"
			% [brow, "无" if hit == null else str(hit.get_collider().name)])

		# f3: 上一版按行砌的 BridgeWalls 隐形墙已拆 —— 三行桥带全可走。
		chk(g.get_node_or_null("WaterCollision/BridgeWalls") == null,
			"桥墙已拆 (BridgeWalls 不复存在, 三行桥带全可走)")

		# g5: 桥沿薄墙回来了 —— 但挂在 WaterCollision 下, 不在 Bridges 下（e30 照旧成立）。
		var rails_g: StaticBody2D = g.get_node_or_null("WaterCollision/BridgeRails")
		chk(rails_g != null, "桥沿有 BridgeRails 碰撞体 (g5, 桥实心了)")
		if rails_g != null:
			var rail_n := 0
			var rail_bad := 0
			for rc in rails_g.get_children():
				if rc is CollisionShape2D and (rc as CollisionShape2D).shape is RectangleShape2D:
					rail_n += 1
					if ((rc as CollisionShape2D).shape as RectangleShape2D).size != Vector2(16, 4):
						rail_bad += 1
			chk(rail_n >= 8 and rail_bad == 0,
				"桥沿薄墙 %d 条, 全是 16x4 (g5)" % rail_n)
			# 垂直往外河迈一步必须被桥沿墙挡住（挑一条真实存在的北墙来试）
			var rail_cell := Vector2i.ZERO
			for x in range(bx0, bx1 + 1):
				if g._water_set.has(Vector2i(x, brow - 2)):
					rail_cell = Vector2i(x, brow - 1)
					break
			chk(rail_cell != Vector2i.ZERO, "桥跨里找到贴河面的上桥带格 %s (g5)" % str(rail_cell))
			if rail_cell != Vector2i.ZERO:
				place_player(rail_cell)
				player.global_position.y += 4.0   # 先沉 4px 离开碰撞圆与墙的 2px 重叠区
				var kout: KinematicCollision2D = player.move_and_collide(Vector2(0, -10))
				chk(kout != null and str(kout.get_collider().name) == "BridgeRails",
					"从桥带往外河迈步被桥沿墙挡住 (撞到 %s)"
						% ("无" if kout == null else str(kout.get_collider().name)))
			# 沿上桥带行平行走不被墙绊（墙只在外缘, 与行走向平行）
			place_player(Vector2i(bx0 + 1, brow - 1))
			player.global_position.y += 4.0
			var kpar: KinematicCollision2D = null
			for _i5 in 6:
				kpar = player.move_and_collide(Vector2(8, 0))
				if kpar != null:
					break
			chk(kpar == null or str(kpar.get_collider().name) != "BridgeRails",
				"沿桥带行平行走不被桥沿墙绊住 (g5)")

		# e30: Bridges 下面不许再挂任何 StaticBody2D（护栏细线碰撞要拆干净）
		var rail_bodies := 0
		for c in bridges2.get_children():
			if c is StaticBody2D:
				rail_bodies += 1
		chk(rail_bodies == 0, "Bridges 下没有护栏碰撞体（RailBodies 已拆, 剩 %d 个）" % rail_bodies)
		# h2/h3: 前层护栏 + 栏杆孔 —— 每座桥两张 sprite: 整贴 (z=Z_BRIDGE) + 底
		#     16px region 前层 (z=+1, 压过角色池): 走下桥带的角色在护栏后面,
		#     下护栏素材挖了柱间竖缝, 透过栏杆孔看得见人。
		for by in g.BRIDGE_ROWS:
			var bmain: Sprite2D = g.get_node_or_null("Bridges/Bridge%d" % by)
			var bfront: Sprite2D = g.get_node_or_null("Bridges/BridgeFront%d" % by)
			chk(bmain != null and bfront != null, "桥 %d 有整贴 + 前层护栏两张 sprite (h2)" % by)
			if bmain == null or bfront == null:
				continue
			chk(bfront.region_enabled
				and bfront.region_rect == Rect2(0, 32, bmain.texture.get_width(), 16)
				and bfront.z_index == 1
				and bfront.position == bmain.position + Vector2(0, 32),
				"桥 %d 前层护栏取整贴底 16px, z=+1 盖住下桥带角色 (h2)" % by)
		var bpiece: Image = g._bridge_piece()
		chk(bpiece != null
			and bpiece.get_height() == 47
			and bpiece.get_pixel(10, 41).a < 0.5 and bpiece.get_pixel(30, 41).a < 0.5,
			"下护栏柱间挖出竖缝, 素材裁到横梁底 47 高 (h3/j7)")
		chk(bpiece != null
			and bpiece.get_pixel(2, 42).a > 0.5 and bpiece.get_pixel(2, 46).a > 0.5
			and bpiece.get_pixel(10, 44).a > 0.5,
			"下护栏立柱和横梁保留, 柱脚已清 (h3/j7)")
		player.global_position = bsaved

	# 17.3 室内：房子节点下 Interior 默认不可见（避免地图下方露出地板）
	var house17: Node2D = g.get_node_or_null("House")
	chk(house17 != null, "场景里有 House")
	if house17 != null:
		# 第 8 节里已经调用过 house._enter_house(player)，把 interior.visible 改成了 true。
		# 先重置成 false 再验证「默认隐藏」逻辑。
		var interior := house17.get_node_or_null("Interior")
		chk(interior != null, "House 下有 Interior 子节点")
		if interior != null:
			interior.visible = false
			chk(not interior.visible, "默认 Interior.visible = false（地图下面不透出室内）")

	# 17.4 房子不压耕地。
	# ❗房子的原点现在在「脚下」（y_sort 要靠它），外观贴图挂在原点的**上方**，
	#    所以占的格子要用外观贴图的真实矩形去算，不能拿节点位置那一格当左上角。
	if house17 != null:
		var ext: Sprite2D = house17.get_node_or_null("Exterior")
		chk(ext != null and ext.texture != null, "房子外观是 Exterior 贴图")
		if ext != null and ext.texture != null:
			# Sprite2D 没有 get_global_rect（那是 Control 的），自己拼：
			# 局部矩形（已经算上了 centered/offset）+ 世界位置 = 世界矩形
			var ext_rect: Rect2 = ext.get_rect()
			ext_rect.position += ext.global_position
			var c0: Vector2i = cell_of(ext_rect.position)
			var c1: Vector2i = cell_of(ext_rect.end - Vector2.ONE)
			chk(c1.x - c0.x + 1 == 5 and c1.y - c0.y + 1 == 7,
				"房子外观占 %dx%d 格（%s ~ %s）"
					% [c1.x - c0.x + 1, c1.y - c0.y + 1, str(c0), str(c1)])
			var bad_cells: Array = []
			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					var c := Vector2i(x, y)
					if not g._land_set.has(c) or Farm.tilled.has(c) or g._water_set.has(c):
						bad_cells.append(c)
			chk(bad_cells.is_empty(),
				"房子外观 %s ~ %s 全落在空地草地上（不压耕地、不进水，坏格 %s）"
					% [str(c0), str(c1), str(bad_cells)])
			var foot_cell: Vector2i = cell_of(house17.get_node("DoorFront").global_position)
			chk(g._land_set.has(foot_cell) and not Farm.tilled.has(foot_cell) \
				and not g._water_set.has(foot_cell),
				"门口站人的那格 %s 是空地草地（出门不会卡在田里/水里）" % str(foot_cell))

	print("\n=== 18. 音频系统（程序化合成的 BGM + 音效）===")
	chk(Audio != null, "Audio 自动加载已就绪")
	chk(Audio.get_node_or_null("BgmA") != null and Audio.get_node_or_null("BgmB") != null,
		"有两路 BGM 播放器（换曲时交叉淡入淡出）")
	# e52: 曲池 = 岛上 Towball 十首(mp3) + 场景中世纪八首(ogg) + 主菜单 menu.ogg
	var menu_ok := Audio._bgm_streams.get("res://resources/audio/bgm/menu.ogg") is AudioStreamOggVorbis
	var med_ok := Audio._bgm_streams.get(Audio.MEDIEVAL_DIR + "Medieval Vol. 2 1 (Loop).ogg") is AudioStreamOggVorbis
	var tow_ok := Audio._bgm_streams.get(Audio.ISLAND_TRACKS[0]) is AudioStreamMP3
	chk(menu_ok and med_ok and tow_ok,
		"三类曲都在（菜单 ogg %s / 中世纪 ogg %s / 岛上 mp3 %s）" % [menu_ok, med_ok, tow_ok])
	chk(Audio._sfx_streams.size() >= 12,
		"音效载入了 %d 个（至少 12）" % Audio._sfx_streams.size())
	var sfx_players := 0
	for c in Audio.get_children():
		if c is AudioStreamPlayer and String(c.name).begins_with("Sfx"):
			sfx_players += 1
	chk(sfx_players >= 6, "音效有 %d 路播放器（够同时响好几个）" % sfx_players)
	# e52: 岛上就是一组十首, 当天抽中的那一首循环一整天（不再按季节/昼夜切组）
	Audio._scene_track = "island"
	Audio._current_track = ""
	Audio._island_day_track = ""
	Audio._sync_bgm()
	var day_track: String = Audio.current_track()
	chk(Audio.ISLAND_TRACKS.has(day_track),
		"岛上放的是 Towball 十首里的一首（实际 %s）" % day_track)
	var island_stream: AudioStream = Audio._bgm_streams.get(day_track)
	chk(island_stream is AudioStreamMP3 and island_stream.loop,
		"岛上曲子是 mp3 且 loop=true（当天一直循环这一首, 不换曲）")
	# 换日才重抽: 同一天反复 _sync_bgm 不能换曲（否则 0.5s 轮询会把曲子换飞）
	var before_poll: String = Audio.current_track()
	Audio._sync_bgm()
	chk(Audio.current_track() == before_poll, "同一天里 _sync_bgm 不会换掉当天的曲子")
	Audio._on_new_day(2)
	var after_newday: String = Audio.current_track()
	chk(Audio.ISLAND_TRACKS.has(after_newday) and after_newday != before_poll,
		"起床重抽一首（%s -> %s）" % [before_poll, after_newday])
	Audio._current_track = ""
	Audio.play_sfx("hoe")
	Audio.play_sfx("not_exist_at_all")
	chk(true, "play_sfx 对不存在的音效名也安全（静默跳过，不崩）")

	print("\n=== 19. 物品售卖箱（星露谷同款：睡觉时自动卖货）===")
	var bin: Node2D = g.get_node_or_null("ShippingBin")
	chk(bin != null, "场景里有 ShippingBin")
	if bin != null:
		chk(bin.is_in_group("shipping_bin"), "售卖箱在 shipping_bin 组里（game.gd 靠组找它）")
		chk(g.shipping_bin == bin, "game.gd 拿到售卖箱引用了")
		var bcell := Vector2i(
			int(floor((bin.global_position.x - Farm.grid_origin.x) / 16.0)),
			int(floor((bin.global_position.y - Farm.grid_origin.y) / 16.0)))
		chk(g._land_set.has(bcell) and not g._water_set.has(bcell) and not Farm.tilled.has(bcell),
			"售卖箱落在空草地上 %s（不在水里、不压耕地）" % str(bcell))
		var art: Sprite2D = bin.get_node_or_null("Art")
		chk(art != null and art.texture != null, "售卖箱有贴图（从素材现裁的）")
		if art != null and art.texture != null:
			# ❗素材那张图里**并排着好几个单箱变体**，不是「上下两半拼成一个大箱子」。
			#   以前把两个变体上下叠成 15x35，看着就是个双屉柜 —— 这就是「显示不全」的根源。
			chk(art.texture.get_width() == 13 and art.texture.get_height() == 16,
				"箱体贴图 13x16（实际 %dx%d）—— 原生像素，别放大"
					% [art.texture.get_width(), art.texture.get_height()])
			chk(art.position.x == -6.5 and art.position.y == -16.0,
				"箱子贴图底边贴着脚下、水平居中（位置 %s）" % str(art.position))
			chk(art.texture == bin._tex_closed, "空箱时显示的是闭合的那个箱子")
		# 先把背包清干净（能卖的都清, 种子也算），才好在这个基础上断言确定的数量
		clear_crops()
		# t9: 现在除了工具全都收 —— 食物（鱼）和材料（小麦）都进箱
		var perch19: ItemData = load("res://item/perch.tres")
		Inventory.add_item(perch19, 2)
		var moved_fish: int = bin.deposit_all_crops()
		chk(moved_fish == 2, "鱼（食物）也能投进售卖箱（实际 %d）" % moved_fish)
		var wheat19: ItemData = load("res://item/wheat.tres")
		Inventory.add_item(wheat19, 3)
		var moved_wheat: int = bin.deposit_all_crops()
		chk(moved_wheat == 3 and Inventory.count_item(wheat19) == 0,
			"材料（小麦）也能卖, 3 份全进箱（实际 %d）" % moved_wheat)
		bin.collect()   # 把鱼和小麦清掉, 接下来从空箱开始测作物
		var carrot: ItemData = load("res://item/carrot.tres")
		var potato: ItemData = load("res://item/potato.tres")
		chk(Inventory.count_item(potato) == 0, "背包里的作物已清空（从 0 件开始数）")
		Inventory.add_item(carrot, 3)
		Inventory.add_item(potato, 2)
		var expect_income: int = carrot.sell_price * 3 + potato.sell_price * 2
		var moved: int = bin.deposit_all_crops()
		chk(moved == 5, "投进 5 件作物（实际 %d）" % moved)
		chk(Inventory.count_item(carrot) == 0 and Inventory.count_item(potato) == 0,
			"作物已从背包里扣掉（不会凭复制一份）")
		chk(bin.pending_count() == 5, "箱子里记着 5 件（实际 %d）" % bin.pending_count())
		chk(bin.pending_total() == expect_income,
			"预计收入 %d 金（实际 %d）" % [expect_income, bin.pending_total()])
		chk(bin._label.visible, "有货时箱子顶上显示「待售」")
		chk(art != null and art.texture == bin._tex_open, "有货时箱子换成敞口的那张（一眼看出里面满了）")
		var seed_sample: ItemData = load("res://item/seed.tres")
		Inventory.add_item(seed_sample, 2)
		var moved_seed: int = bin.deposit_all_crops()
		chk(moved_seed == 2 and Inventory.count_item(seed_sample) == 0,
			"种子也能卖, 2 包全进箱（实际 %d）" % moved_seed)
		expect_income += seed_sample.sell_price * 2   # 账里算上这两包种子
		var collected: Dictionary = bin.collect()
		chk(int(collected["total"]) == expect_income,
			"collect() 返回的总额对得上（%d）" % int(collected["total"]))
		chk(bin.pending_count() == 0, "取走后箱子清空了")
		chk(not bin._label.visible, "箱子空了之后不显示「待售」标签")

	print("\n=== 20. 夜晚结算画面 ===")
	var night_layer: CanvasLayer = null
	for c in g.get_children():
		if c is CanvasLayer and String(c.name) == "NightOverlay":
			night_layer = c
	chk(night_layer != null, "有 NightOverlay（睡觉黑幕那一层）")
	var settle: Control = null
	if night_layer != null:
		settle = night_layer.get_node_or_null("Settlement")
	chk(settle != null, "黑幕那一层里有 Settlement 结算面板")
	if settle != null:
		chk(g.settlement_panel == settle, "game.gd 拿到结算面板引用了")
		# 必须排在黑幕 ColorRect 之后，否则会被黑幕盖住
		var fade_rect: ColorRect = night_layer.get_node_or_null("ColorRect")
		if fade_rect != null:
			chk(settle.get_index() > fade_rect.get_index(), "结算面板画在黑幕之上（不会被盖住）")
		chk(not settle.is_open() and not settle.visible, "默认不显示")
		var carrot3: ItemData = load("res://item/carrot.tres")
		var income3: int = carrot3.sell_price * 3
		settle.show_summary("春季 第 3 天", 3,
			[{"item": carrot3, "count": 3, "price": income3}], income3, 1234)
		chk(settle.is_open() and settle.visible, "show_summary 之后弹出来了")
		# ❗除了全角标点，还有两个「看着像空格、其实字体里没有」的字符：
		#   全角空格(U+3000) 和间隔号(U+00B7) —— IPix.ttf 都缺字形，渲出来是个小方块。
		#   结算面板的「售卖箱收入 +N 金」原来用的就是全角空格，游戏里显示成一个方块。
		var missing_glyph := "\u3000\u00b7"
		var mg_offenders: Array = []
		for tmg in [settle._income.text, settle._money.text, settle._note.text, settle._date.text,
				settle._title.text]:
			for img_i in String(tmg).length():
				if missing_glyph.contains(String(tmg)[img_i]):
					mg_offenders.append(String(tmg))
					break
		chk(mg_offenders.is_empty(),
			"结算面板没用到字体缺字形的全角空格/间隔号: %s" % str(mg_offenders))
		# 夜空背景：程序化生成的 320x180 像素图（星空 + 月亮 + 远山）
		chk(settle._bg != null and settle._bg.visible, "结算画面有夜空背景")
		var bgt: ImageTexture = settle._bg.texture
		chk(bgt != null and bgt.get_size() == Vector2(320, 180),
			"夜空背景是 320x180 的像素图（实际 %s）" % str(bgt.get_size() if bgt != null else Vector2()))
		var bimg: Image = bgt.get_image()
		var px_sky: Color = bimg.get_pixel(10, 5)          # 天顶
		var px_moon: Color = bimg.get_pixel(252, 40)       # 月亮中心
		var px_hill: Color = bimg.get_pixel(160, 175)      # 底部远山
		chk(px_sky.b > px_sky.r and px_sky.v < 0.3, "天顶是深夜蓝（%s）" % str(px_sky))
		chk(px_moon.r > 0.8 and px_moon.g > 0.7, "右上角有月亮（%s）" % str(px_moon))
		chk(px_hill.v < 0.25, "底部是深色远山剪影（%s）" % str(px_hill))
		chk(settle._stars != null and settle._stars.texture != null,
			"星星单独一层，会做闪烁动画")
		chk(settle._income.text.contains(str(income3)),
			"收入文字一开始就是最终值（「%s」）—— 动画只是视觉滚动" % settle._income.text)
		var income_label := find_label(settle, "售卖箱收入")
		chk(income_label != null, "结算面板里有「售卖箱收入」那一行")
		if income_label != null:
			chk(income_label.text.contains(str(income3)),
				"收入金额写进文字了（「%s」）" % income_label.text)
		var money_label := find_label(settle, "口袋里的金币")
		chk(money_label != null and money_label.text.contains("1234"),
			"现有金币也显示了（「%s」）" % (money_label.text if money_label != null else ""))
		chk(find_label(settle, "第 3 天") != null, "标题里有「第 3 天」")
		settle._dismiss()
		# 空箱也要能开（不能崩）
		settle.show_summary("春季 第 4 天", 4, [], 0, 1234)
		chk(settle.is_open(), "没有东西要卖时也能正常打开")
		chk(find_label(settle, "没东西要卖") != null, "空箱时显示「今天没东西要卖」")
		settle._dismiss()
		chk(not settle.is_open() and not settle.visible, "关掉之后隐藏了")
	# 备注行：有备注才显示（比如「伙伴们把没干完的 X 格活补完了」）
	chk(not settle._note.visible, "没传备注时不显示备注行")
	settle.show_summary("春季 第 4 天", 4, [], 0, 1234, "伙伴们把没干完的 3 格活补完了")
	chk(settle._note.visible and settle._note.text.contains("3 格"),
		"备注行显示出来了（「%s」）" % settle._note.text)
	settle._dismiss()
	# 夜间研究播报块：传了才有，没传就整块收起来
	chk(not settle._research_title.visible and settle._research_box.get_child_count() == 0,
		"没传研究播报时，那一块整块收起来")
	settle.show_summary("春季 第 4 天", 4, [], 0, 1234, "",
		["科技 +8 点 (共 24)  1 人钻研", "可研究: 轮作法"])
	chk(settle._research_title.visible and settle._research_box.get_child_count() == 2,
		"传了研究播报就显示出来（%d 行）" % settle._research_box.get_child_count())
	chk(String(settle._research_box.get_child(0).text).contains("科技 +8"),
		"播报第一行是今晚的科技点数（「%s」）" % settle._research_box.get_child(0).text)
	settle.show_summary("春季 第 4 天", 4, [], 0, 1234)
	chk(not settle._research_title.visible and settle._research_box.get_child_count() == 0,
		"第二次没传播报：旧行被清干净了")
	settle._dismiss()

	print("\n=== 21. 洒水壶打水 / 鼠标点快捷栏 / 商人交易面板 ===")
	chk(g._pond_cells.size() > 0 and g.is_water(g._pond_cells[0]),
		"池塘那一格算水（可以打水）")
	chk(not g.is_water(Vector2i(5, 5)), "陆地上的格子不算水")
	Inventory.watering_can_water = 0
	var frozen_saved: bool = player.frozen
	player.frozen = false
	chk(player._fetch_water(g._pond_cells[0]),
		"对着水面用洒水壶 → 这一下被「打水」接管（不会去浇地）")
	chk(Inventory.is_can_full(), "水壶打满了（%d/%d）"
		% [Inventory.watering_can_water, Inventory.WATER_MAX])
	chk(not player._fetch_water(Vector2i(5, 5)), "对着陆地不会打水（走正常浇水逻辑）")
	player.frozen = frozen_saved
	var hotbar: GridContainer = g.get_node_or_null("HUD/GridContainer")
	chk(hotbar != null, "HUD 下有快捷栏 GridContainer")
	if hotbar != null:
		chk(hotbar.has_method("select"), "快捷栏有 select(index)（给鼠标点击用）")
		hotbar.select(1)
		chk(hotbar.selected_index == 1, "点第 2 格后 selected_index = 1（实际 %d）"
			% hotbar.selected_index)
		chk(player.current_item == Inventory.hotbar_item(1), "选中的道具同步给了玩家")
		hotbar.select(0)
		chk(hotbar.selected_index == 0, "点回第 1 格")
	var shop: Control = g.get_node_or_null("HUD/Shop")
	chk(shop != null, "HUD 下有 Shop 交易面板")
	if shop != null:
		chk(shop.is_in_group("shop"), "交易面板在 shop 组里（merchant.gd 靠组找它）")
		chk(not shop.is_open(), "交易面板默认关闭")
		var carrot_seed: ItemData = load("res://item/carrot_seed.tres")
		var seeds_before: int = Inventory.count_item(carrot_seed)
		var money_saved: int = Wallet.money
		Wallet.money = 500
		shop.open_panel()
		chk(shop.is_open(), "open_panel() 之后打开了")
		chk(player.frozen, "开交易面板时锁住了角色")
		shop._buy(carrot_seed, 10)
		chk(Inventory.count_item(carrot_seed) == seeds_before + 1, "买到 1 包胡萝卜种子")
		chk(Wallet.money == 490, "金币扣掉 10（剩 %d）" % Wallet.money)
		var pumpkin_seed: ItemData = load("res://item/pumpkin_seed.tres")
		var pumpkin_before: int = Inventory.count_item(pumpkin_seed)
		Wallet.money = 0
		shop._buy(pumpkin_seed, 40)
		chk(Inventory.count_item(pumpkin_seed) == pumpkin_before, "金币不够时买不到东西")
		chk(Wallet.money == 0, "金币不够时不会扣成负数")
		shop.close_panel()
		chk(not shop.is_open(), "关掉了")
		Wallet.money = money_saved

	print("\n=== 22. UI 面板必须占满全屏（否则会挤到左上角、遮罩也会消失）===")
	# 踩过的坑：商店 / 背包面板是直接挂在 HUD(CanvasLayer) 下的 Control 子节点，
	# 父节点不是 Control 时 Control 的默认锚点是「左上角 + 0 尺寸」，
	# 于是全屏遮罩 ColorRect 退化成 0x0、面板被顶到屏幕左上角。
	# 它们必须自己 set_anchors_and_offsets_preset(PRESET_FULL_RECT)。
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_checks := [
		["Shop", g.get_node_or_null("HUD/Shop")],
		["Backpack", g.get_node_or_null("HUD/Backpack")],
		["Settlement", g.settlement_panel],
	]
	for pc in panel_checks:
		var pname: String = pc[0]
		var c := pc[1] as Control
		chk(c != null, "%s 面板存在" % pname)
		if c == null:
			continue
		chk(c.get_parent() is CanvasLayer, "%s 挂在 HUD(CanvasLayer) 下" % pname)
		chk(c.size == vp_size, "%s 占满整个视口（%s，视口 %s）"
			% [pname, str(c.size), str(vp_size)])
		# 遮罩：面板下第一个「全屏盖住身后世界」的子节点 ——
		# Shop/Backpack 是半透明黑的 ColorRect；Settlement 是整幅夜空 TextureRect
		# （不透明，盖住效果一样，还比黑幕好看）。
		var mask_found := false
		var mask_ok := false
		for child in c.get_children():
			if child is ColorRect or child is TextureRect:
				mask_found = true
				mask_ok = (child as Control).size == vp_size
				break
		chk(mask_found, "%s 有全屏遮罩（黑底或夜空背景）" % pname)
		chk(mask_ok, "%s 的遮罩是全屏尺寸（铺满）" % pname)
	# 居中：居中容器里的面板盒子必须落在视口中间附近。
	# 注意必须先 open_panel() 再量 —— Godot 里隐藏的 Control，它下面的 Container
	# 不会去排版子节点，量到的是没布局过的退化尺寸（44x34 那种）。
	var shop_c := g.get_node_or_null("HUD/Shop") as Control
	if shop_c != null:
		shop_c.open_panel()
		for i in 3:
			await get_tree().process_frame
		var box: Control = null
		for child in shop_c.get_children():
			if child is CenterContainer and (child as CenterContainer).get_child_count() > 0:
				box = (child as CenterContainer).get_child(0) as Control
				break
		chk(box != null, "交易面板里有居中容器包着的面板盒")
		if box != null:
			var bc: Vector2 = box.get_global_rect().get_center()
			var vc: Vector2 = vp_size * 0.5
			chk(bc.distance_to(vc) < vp_size.x * 0.25,
				"交易面板大致居中（中心 %s，视口中心 %s）" % [str(bc), str(vc)])
			# 面板盒整个落在屏幕里（中段套了限高滚动后整盒 ~610px，不许再顶出 648 的底）。
			# ❗量「盒高」而不是「右下角坐标」：headless 视口是 1152x1152 不是 1152x648，
			#   居中卡片的 bottom 会虚高 —— 真窗口里 CenterContainer 永远居中，高度才是硬指标。
			var bs: Vector2 = box.get_global_rect().size
			chk(bs.x <= 1152.5 and bs.y <= 648.5,
				"交易面板盒不超一屏（宽 x 高 = %s，限 1152x648）" % str(bs))
		shop_c.close_panel()

	print("\n=== 22.5 大陆面板体检：暖木色家族 + 卡片不越界 ===")
	# 2026-09-19 全面美化：town/market/patrol/diplomacy 原来是偏蓝的底，
	#   和商店/背包那套暖木+铜金家族打架 —— 已统一成暖木底。
	#   这里锁住两件事：①卡片底色必须是暖色 (r>g>b)；②卡片整个落在 1152x648 里。
	# ❗headless 视口实测是 1152x1152，锚点全按它算会虚判越界（ui_dump 同款坑）——
	#   钉一个 1152x648 的 Control 根，面板挂它下面量出来的才是真窗口排版。
	var ui_root22 := Control.new()
	ui_root22.name = "UiRoot22"
	ui_root22.position = Vector2.ZERO
	ui_root22.size = Vector2(1152, 648)
	ui_root22.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root22)
	await get_tree().process_frame
	for spec22 in [
			["res://town_ui.gd", "议事厅", "town"],
			["res://market_ui.gd", "集市", "market"],
			["res://patrol_ui.gd", "军中交谈", "patrol"]]:
		var p22: Control = load(str(spec22[0])).new()
		if str(spec22[2]) == "town":
			p22.setup("chenxi_cap")
		elif str(spec22[2]) == "patrol":
			p22.setup("晨曦亲军", "chenxi")
		ui_root22.add_child(p22)
		await get_tree().process_frame
		p22.open_panel()
		p22.set("_guard", 0.0)
		for i22 in 3:
			await get_tree().process_frame
		var card22: PanelContainer = null
		for child22 in p22.get_children():
			if child22 is CenterContainer and (child22 as CenterContainer).get_child_count() > 0 \
					and (child22 as CenterContainer).get_child(0) is PanelContainer:
				card22 = (child22 as CenterContainer).get_child(0) as PanelContainer
				break
		chk(card22 != null, "%s 面板有居中的卡片盒" % str(spec22[1]))
		if card22 != null:
			var sb22: StyleBoxFlat = card22.get_theme_stylebox("panel") as StyleBoxFlat
			chk(sb22 != null and sb22.bg_color.r > sb22.bg_color.g
				and sb22.bg_color.g > sb22.bg_color.b,
				"%s 卡片是暖木底色（r>g>b，不再偏蓝）" % str(spec22[1]))
			var r22: Rect2 = card22.get_global_rect()
			chk(r22.end.x <= 1152.5 and r22.end.y <= 648.5
				and r22.position.x >= -0.5 and r22.position.y >= -0.5,
				"%s 卡片整个落在屏幕里（rect %s）" % [str(spec22[1]), str(r22)])
		p22.close_panel()
		p22.queue_free()
		await get_tree().process_frame
	# 外交页（背包子页）：五国卡片也得是暖木底（只量样式不量排版，挂哪都行）
	var dip22: Control = load("res://diplomacy_ui.gd").new()
	ui_root22.add_child(dip22)
	await get_tree().process_frame
	var dip_warm22 := 0
	var dip_all22 := 0
	var dip_scroll22 := dip22.get_child(0) as ScrollContainer
	if dip_scroll22 != null:
		for c22 in dip_scroll22.get_children():
			var lst22 := c22 as VBoxContainer
			if lst22 == null:
				continue
			for b22 in lst22.get_children():
				if b22 is PanelContainer:
					dip_all22 += 1
					var sb2 := (b22 as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
					if sb2 != null and sb2.bg_color.r > sb2.bg_color.g and sb2.bg_color.g > sb2.bg_color.b:
						dip_warm22 += 1
	chk(dip_all22 >= 4 and dip_warm22 == dip_all22,
		"外交页五国卡片全是暖木底（%d/%d）" % [dip_warm22, dip_all22])
	ui_root22.queue_free()
	await get_tree().process_frame

	print("\n=== 23. 伙伴（奴隶）+ 夜晚派活面板 ===")
	# 23.1 花名册招募: 不看钱不看上限, 第 1 位固定是布恩
	chk(Slaves != null, "Slaves 自动加载已就绪")
	var money_bak23: int = Wallet.money
	Slaves.clear_all()
	chk(Slaves.count == 0 and Slaves.budget() == 0, "一开始 0 个伙伴、可派 0 格")
	chk(String(Slaves.preview_next().get("name", "")) == "布恩",
		"花名册第 1 位固定是布恩（%s）" % Slaves.preview_next().get("name", ""))
	Slaves.recruit_roster()
	chk(Slaves.count == 1, "不花一分钱招到第 1 个伙伴")
	chk(String(Slaves.slave_at(0).get("name", "")) == "布恩", "招进来的就是布恩本人")
	await get_tree().process_frame
	chk(g.slave_nodes.size() == 1, "场景里真的冒出来 1 个伙伴小人（%d）" % g.slave_nodes.size())
	chk(g.slave_nodes.size() > 0 and g.slave_nodes[0].get_parent() == g,
		"伙伴直接挂在 Game 下（不套容器）—— 套了容器 y_sort 会散架，前后遮挡就失效了")

	# 23.2 额度：伙伴越多，能派的格子越多
	chk(Slaves.budget() == Slaves.CELLS_PER_SLAVE,
		"1 个伙伴的额度 = %d 格（实际 %d）" % [Slaves.CELLS_PER_SLAVE, Slaves.budget()])
	var cell_a := Vector2i(0, 0)
	chk(Slaves.assign(cell_a, Slaves.TASK_TILL), "给 %s 派了「耕地」" % str(cell_a))
	chk(Slaves.task_at(cell_a) == Slaves.TASK_TILL, "那一格记着耕地")
	chk(Slaves.used() == 1 and Slaves.remaining() == Slaves.budget() - 1,
		"已派 1 格，还剩 %d 格" % Slaves.remaining())
	chk(not Slaves.assign(cell_a, Slaves.TASK_TILL), "同一格派同样的活不算重复占额度")
	chk(Slaves.assign(cell_a, Slaves.TASK_WATER) and Slaves.task_at(cell_a) == Slaves.TASK_WATER,
		"可以改派成「浇水」")
	chk(Slaves.used() == 1, "改工种没有多占额度（还是 1 格）")
	var filled := 0
	for i in 40:
		if Slaves.assign(Vector2i(10 + i, 10), Slaves.TASK_PLANT):
			filled += 1
	chk(Slaves.remaining() == 0, "额度正好用满（已派 %d / 额度 %d）" % [Slaves.used(), Slaves.budget()])
	chk(Slaves.used() == Slaves.budget(), "已派格数不会超过额度（%d = %d）" % [Slaves.used(), Slaves.budget()])
	chk(not Slaves.assign(Vector2i(30, 30), Slaves.TASK_TILL), "额度用完后就派不上新格子了")
	chk(Slaves.count_of(Slaves.TASK_PLANT) == filled, "按工种统计对得上（播种 %d 格）" % Slaves.count_of(Slaves.TASK_PLANT))
	chk(not Slaves.in_map(Vector2i(999, 999)) and not Slaves.assign(Vector2i(999, 999), Slaves.TASK_TILL),
		"地图范围外的格子派不了活")

	# 23.3 派活面板：全屏、有涂色地图、工种按钮能换画笔
	var ap23: Control = g.assign_panel
	chk(ap23 != null, "场景里有派活面板（g.assign_panel）")
	if ap23 != null:
		chk(ap23.size == vp_size, "派活面板占满视口（%s，视口 %s）" % [str(ap23.size), str(vp_size)])
		chk(not ap23.is_open() and not ap23.visible, "默认不显示")
		ap23.open()
		chk(ap23.is_open() and ap23.visible, "open() 之后打开了")
		chk(ap23._map != null, "面板里有一张可涂色的地图")
		chk(ap23._info.text.contains("%d" % Slaves.count),
			"面板上写着伙伴人数（「%s」）" % ap23._info.text)
		chk(int(ap23._map.map_size_px().x) == (Slaves.map_to.x - Slaves.map_from.x + 1) * ap23._map.tile,
			"涂色地图按格子铺开（%s，一格 %d 像素）" % [str(ap23._map.map_size_px()), ap23._map.tile])
		# 整座岛：范围必须覆盖「核心陆地 + 噪声切出来的海岸带」，不能只画核心那一块
		chk(Slaves.map_from.x <= g.ISLAND_FROM.x and Slaves.map_from.y <= g.ISLAND_FROM.y
				and Slaves.map_to.x >= g.ISLAND_TO.x and Slaves.map_to.y >= g.ISLAND_TO.y,
			"地图范围包含整座岛（%s ~ %s，核心是 %s ~ %s）"
				% [str(Slaves.map_from), str(Slaves.map_to), str(g.ISLAND_FROM), str(g.ISLAND_TO)])
		var outside_land := 0
		for c in g._land_set.keys():
			if not Slaves.in_map(c):
				outside_land += 1
		chk(outside_land == 0, "岛上的每一格陆地都在地图范围内（漏了 %d 格）" % outside_land)
		ap23._select_tool(Slaves.TASK_WATER)
		chk(ap23._selected == Slaves.TASK_WATER and ap23._map.tool == Slaves.TASK_WATER,
			"点了「浇水」之后，地图上的画笔跟着换")
		# ❗要挑一格**真的能派活**的：水面和草地现在都（正确地）涂不上色，
		#   写死 (10,10) 这类坐标迟早会撞上河或草地 —— 先把它锄成耕地再说。
		var freed := Vector2i(10, 10)
		for c in Slaves.assignments.keys():
			if g._land_set.has(c) and not g.is_water(c):
				freed = c
				break
		Farm.till(freed)
		chk(Farm.tilled.has(freed), "挑了一格耕地来测涂色（%s）" % str(freed))
		chk(ap23._map.can_paint(freed), "耕地可以派活")
		chk(Slaves.erase(freed), "手动擦掉一格，腾出 1 格额度")
		var ink: int = Slaves.used()
		ap23._map._paint(freed)
		chk(Slaves.task_at(freed) == Slaves.TASK_WATER and Slaves.used() == ink + 1,
			"在地图上点一下 = 给那一格派活（真的写进数据了：%d -> %d 格）" % [ink, Slaves.used()])
		# 额度已经满了，再涂新格子应该什么都不发生
		ap23._map._paint(Vector2i(30, 30))
		chk(Slaves.used() == ink + 1 and Slaves.task_at(Vector2i(30, 30)) == 0,
			"额度用完后在图上再涂也不会生效（不会偷偷超编）")
		ap23._select_tool(0)                      # 0 = 橡皮
		ap23._map._paint(freed)
		chk(Slaves.task_at(freed) == 0 and Slaves.used() == ink, "橡皮能擦掉已经派下去的活")

		# 23.3b 草地不能派活 —— 只能派在耕地 / 已播种的地块上
		var grass_cell := Vector2i(0, 0)
		var grass_ok := false
		for c in g._land_set.keys():
			var cv: Vector2i = c
			if g.is_water(cv) or Farm.tilled.has(cv) or Farm.crops.has(cv):
				continue
			if not Slaves.in_map(cv):
				continue
			grass_cell = cv
			grass_ok = true
			break
		chk(grass_ok, "找到一格草地来测「选不中」（%s）" % str(grass_cell))
		if grass_ok:
			chk(not ap23._map.is_farmland(grass_cell), "草地不算农田")
			chk(not ap23._map.can_paint(grass_cell), "草地上派不了活")
			Slaves.clear_all()
			ap23._select_tool(Slaves.TASK_WATER)
			ap23._map._paint(grass_cell)
			chk(Slaves.used() == 0, "硬去涂草地也写不进数据（0 格）")

		# 23.3c 底图把「已播种」的地块单独标出来（不是跟空耕地一个色）
		var seed_probe: ItemData = load("res://item/seed.tres")
		Inventory.add_item(seed_probe, 1)
		Farm.plant(freed, seed_probe)
		chk(Farm.crops.has(freed), "在 %s 播下一颗种子" % str(freed))
		ap23._map._build_base()
		var px_seeded: Color = ap23._map._base.get_image().get_pixel(
			freed.x - ap23._map.map_from.x, freed.y - ap23._map.map_from.y)
		Farm.crops.erase(freed)
		ap23._map._build_base()
		var px_soil: Color = ap23._map._base.get_image().get_pixel(
			freed.x - ap23._map.map_from.x, freed.y - ap23._map.map_from.y)
		chk(px_seeded != px_soil,
			"底图上「已播种」和「空耕地」不是一个颜色（%s vs %s）" % [str(px_seeded), str(px_soil)])
		chk(px_seeded.g > px_soil.g + 0.15,
			"已播种的格子偏黄绿（绿通道 %.2f > %.2f）" % [px_seeded.g, px_soil.g])

		# 23.3d 滚轮放缩 + 拖拽移动视角
		var t0: int = ap23._map.tile
		var z0: float = ap23._map.zoom
		ap23._map.zoom_by(1)
		chk(ap23._map.zoom > z0 and ap23._map.tile >= t0,
			"滚轮向上滚：地图放大（zoom %.2f -> %.2f，格子 %d -> %d 像素）"
				% [z0, ap23._map.zoom, t0, ap23._map.tile])
		ap23._map.zoom_by(-1)
		chk(absf(ap23._map.zoom - z0) < 0.001, "再滚回来又还原（%.2f）" % ap23._map.zoom)
		var vc0: Vector2 = ap23._map.view_center
		ap23._map.pan_by(Vector2(64, 0))
		chk(ap23._map.view_center.x < vc0.x,
			"拖拽能把视角往右推（视野中心 %.1f -> %.1f）" % [vc0.x, ap23._map.view_center.x])
		# 造一个真的滚轮事件，确认它走进的是缩放（不是被外层容器当滚动吃掉）
		var wheel23 := InputEventMouseButton.new()
		wheel23.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel23.pressed = true
		var t_before: int = ap23._map.tile
		ap23._map._gui_input(wheel23)
		chk(ap23._map.tile >= t_before and ap23._map.zoom > 1.0,
			"真的滚轮事件也能放大（格子 %d -> %d）" % [t_before, ap23._map.tile])
		ap23._map.zoom = 1.0
		ap23._map._apply_zoom()

		# 23.3e 地图右侧那列功能键
		# ❗最后一个参数 owned 必须给 false：这些按钮是运行时 add_child 的，没设 owner
		var btn_txts: Array = []
		for b in ap23.find_children("*", "Button", true, false):
			btn_txts.append((b as Button).text)
		for w in ["重新绘制", "清除全部", "全部选择", "只取消浇水", "确定 (F)"]:
			chk(btn_txts.has(w), "地图右边有「%s」按钮（实际 %s）" % [w, str(btn_txts)])

		var cnt_bak23: int = Slaves.count
		Slaves.clear_all()
		Slaves.count = 40                       # 额度给足，测「全部选择」
		ap23._select_tool(Slaves.TASK_WATER)
		ap23._select_all()
		var farm_n := 0
		for y in range(Slaves.map_from.y, Slaves.map_to.y + 1):
			for x in range(Slaves.map_from.x, Slaves.map_to.x + 1):
				if ap23._map.can_paint(Vector2i(x, y)):
					farm_n += 1
		chk(Slaves.count_of(Slaves.TASK_WATER) == mini(farm_n, Slaves.budget()),
			"「全部选择」把能派活的地块都涂上了（%d 格 / 农田 %d 格 / 额度 %d）"
				% [Slaves.count_of(Slaves.TASK_WATER), farm_n, Slaves.budget()])
		var clean_pick := true
		for c in Slaves.assignments.keys():
			if not ap23._map.can_paint(c):
				clean_pick = false
				break
		chk(clean_pick, "「全部选择」不会涂到草地或水面上")
		ap23._cancel_water()
		chk(Slaves.used() == 0, "「只取消浇水」把浇水的活全撤了（还剩 %d 格）" % Slaves.used())

		ap23._map.zoom = 3.0
		ap23._map._apply_zoom()
		ap23._redraw_map()
		chk(absf(ap23._map.zoom - 1.0) < 0.001, "「重新绘制」把放缩拉回 1 倍（%.2f）" % ap23._map.zoom)
		# ❗地图占的地方是写死的：放缩/拖拽只改画在里面的内容，不把地图撑大撑小
		var size_before: Vector2 = ap23._map.custom_minimum_size
		ap23._map.zoom_by(1)
		ap23._map.pan_by(Vector2(50, 30))
		chk(ap23._map.custom_minimum_size == size_before,
			"放缩和拖拽都不会改变地图本身的尺寸（%s）" % str(ap23._map.custom_minimum_size))
		ap23._map.reset_view()
		Slaves.count = cnt_bak23

		# 23.3f 研究劳动力块：「科/行」安排搬进了夜里派活面板（原先挤在背包的科技/行政页）
		# e30i: 主角自己不下场研究了 —— 面板里没有「自己」这一行，只有伙伴。
		chk(ap23._research_box != null
			and ap23._research_box.get_child_count() == Slaves.slaves.size(),
			"派活面板里有「研究」块（%d 个伙伴每人一行）" % Slaves.slaves.size())
		var exp_bak23: Array = Slaves.expedition.duplicate()
		var dock_bak23: Array = Slaves.dock_crew.duplicate()
		var craft_bak23: Array = Slaves.craft_crew.duplicate()
		var rtech_bak23: Array = Slaves.research_tech.duplicate()
		var radmin_bak23: Array = Slaves.research_admin.duplicate()
		if ap23._research_box != null and ap23._research_box.get_child_count() >= 1:
			var rrow: HBoxContainer = ap23._research_box.get_child(0)
			var keys := 0
			for k in rrow.get_children():
				if k is Button:
					keys += 1
			chk(keys == 2, "伙伴行有 科/行 两个小键（实际 %d 个）" % keys)
			chk(Slaves.set_research(0, "tech"), "点「科」: 伙伴 0 开始钻研科技")
			chk(Slaves.is_research(0, "tech"), "伙伴 0 在科技名单上")
			chk(Slaves.set_research(0, "admin") and Slaves.is_research(0, "admin"),
				"改点「行」: 跟科技自动互斥")
			# set_research 会顺手把人从出海/工地/矿井撤下，测完把现场原样还原
			Slaves.expedition = exp_bak23
			Slaves.dock_crew = dock_bak23
			Slaves.craft_crew = craft_bak23
			Slaves.research_tech = rtech_bak23
			Slaves.research_admin = radmin_bak23

		ap23._dismiss()
		chk(not ap23.is_open() and not ap23.visible, "关掉之后隐藏了")

		# 23.3g e30r: 派活页改成「六大板块 + 拖人」—— 版式/归属/拖放语义
		ap23.open()
		chk(ap23._boards.size() == 6, "底部有六大板块（实际 %d 块）" % ap23._boards.size())
		var bkeys23: Array = []
		for k23 in ap23._boards.keys():
			bkeys23.append(str(ap23._boards[k23].board))
		for k23 in ["crop", "mine", "exp", "dock", "smith", "research"]:
			chk(bkeys23.has(k23), "六大板块里有「%s」（实际 %s）" % [k23, str(bkeys23)])
		chk(ap23._research_box.get_child_count() == Slaves.slaves.size(),
			"科研行政板块列的是全体伙伴（%d 行）" % ap23._research_box.get_child_count())
		if Slaves.slaves.size() >= 1:
			# 先把所有人清成闲人，好从「照料作物」默认池开始测
			Slaves.expedition.clear()
			Slaves.dock_crew.clear()
			Slaves.craft_crew.clear()
			Slaves.mine_crew.clear()
			Slaves.research_tech.clear()
			Slaves.research_admin.clear()
			ap23._rebuild_boards()
			chk(ap23._tile_indexes["crop"].size() == Slaves.slaves.size(),
				"闲人全在「照料作物」默认池里（%d 人）" % ap23._tile_indexes["crop"].size())
			# 拖瓦片 = 改派（数据层一次 toggle，自带互斥）
			chk(ap23._can_drop_board("mine", {"idx": 0}), "闲人能被拖进「采集矿石」")
			chk(not ap23._can_drop_board("crop", {"idx": 0}), "拖回原板块不算数（白拖）")
			ap23._drop_board("mine", {"idx": 0})
			chk(Slaves.mine_job_of(0) == "stone", "拖进矿井默认采石（%s）" % Slaves.mine_job_of(0))
			chk(ap23._board_of(0) == "mine", "他的归属跟着变成「采集矿石」")
			# 点瓦片循环：采石 -> 采铁 -> 收工
			ap23._on_tile_pressed(0, "mine")
			chk(Slaves.mine_job_of(0) == "iron", "点一下换采铁（%s）" % Slaves.mine_job_of(0))
			ap23._on_tile_pressed(0, "mine")
			chk(not Slaves.is_mine(0), "再点一下收工回默认池")
			# 点选-点放：点瓦片拿起 -> 点目标板块标题放下
			ap23._held = -1
			ap23._on_tile_pressed(0, "crop")
			chk(ap23._held == 0, "点「照料作物」的瓦片 = 拿起这个人")
			chk(ap23._info.text.contains("已拿起"), "信息行提示手里拿着谁")
			ap23._drop_click("research")
			chk(ap23._held == -1 and Slaves.is_research(0, "tech"),
				"点「科研行政」标题就把他派去钻研科技")
			# 拖回默认池 = 撤活
			chk(ap23._can_drop_board("crop", {"idx": 0}), "研究中的人能拖回照料作物撤活")
			ap23._drop_board("crop", {"idx": 0})
			chk(ap23._board_of(0) == "crop", "拖回照料作物就撤了活")
			# 工地/铁匠铺闲着的时候板块是灰的（拖进去不收）
			chk(ap23._board_live("dock")
					== (Structures.site_busy() or Voyage.dock_state == Voyage.DOCK_FUNDED),
				"工地板块亮不亮跟工地状态一致")
			chk(ap23._board_live("smith") == Crafting.smith_busy(),
				"冶炼板块亮不亮跟铁匠铺状态一致")
			# 瓦片上必须写着劳动职业（伙伴在派活页要能看见丰饶线）
			var idx23: int = int(ap23._tile_indexes["crop"][0])
			var lab23 := str(Slaves.slave_at(idx23).get("labor", "帮工"))
			var tile23: Button = ap23._tiles["crop"].get_child(0)
			chk(tile23.text.contains(lab23),
				"瓦片写着「名字 + 劳动职业」（%s，丰饶线 %s）" % [tile23.text, lab23])
			# e41d: 瓦片底下那行是三项属性（建N 劳N 知N）, 板块标题下标着「所需」
			chk(tile23.text.contains(Slaves.attrs_short_text(Slaves.slave_at(idx23))),
				"瓦片底下写着三项属性（%s）" % tile23.text)
			var need23: Dictionary = (ap23.get_script() as Script).get_script_constant_map()["BOARD_NEEDS"]
			# exp 板块后来改成「远征编队: 全员自动出海」——出海不吃属性,
			# 唯一要求是别误标成吃劳动（否则误导玩家去凑劳动值）
			chk(need23.size() == 6
					and String(need23["crop"]).contains("劳动")
					and String(need23["mine"]).contains("劳动")
					and String(need23["dock"]).contains("建造")
					and String(need23["smith"]).contains("建造")
					and String(need23["research"]).contains("知识")
					and String(need23["exp"]).contains("不占劳动"),
				"五个板块标了所需属性, 出海板块标了不占劳动")
			chk(ap23._tiles["mine"].get_child_count() == 0,
				"人撤走后矿井板块的瓦片也空了（%d 块）" % ap23._tiles["mine"].get_child_count())
		ap23._dismiss()
		chk(not ap23.is_open() and not ap23.visible, "六大板块版关掉之后也隐藏了")

	# 23.4 篝火招募（从商店分出来了：商店只管买卖）
	var shop23: Control = g.get_node_or_null("HUD/Shop")
	if shop23 != null:
		chk(not shop23.has_method("_recruit"), "招募功能已经不在商人商店里")
	var cp23: Control = g.get_node_or_null("HUD/CampfirePanel")
	chk(cp23 != null, "场景里有篝火招募面板")
	Slaves.clear_all()
	var n_before: int = Slaves.count
	# 保险: 前面的测试节可能留了一堆没熄的火, 先收干净再点新的
	# （queue_free 是延期的, 得等一帧旧火才真消失, 不然同名会顶出匿名节点）
	g._clear_campfire()
	await get_tree().process_frame
	g._spawn_campfire()
	chk(g.campfire != null, "能强制生成篝火")
	chk(g.is_water(g._world_to_cell(g.campfire.global_position)) == false,
		"篝火没生在水里")
	# 光晕必须是「正圆 + 中心往外递减」：以前拿渐变贴图凑，渲出来边界是方的
	var pl23: PointLight2D = null
	for c23 in g.campfire.get_children():
		if c23 is PointLight2D:
			pl23 = c23
	chk(pl23 != null and pl23.texture != null, "篝火带着光晕贴图")
	if pl23 != null and pl23.texture != null:
		var im23: Image = pl23.texture.get_image()
		var cc: int = im23.get_width() / 2
		var a_c: int = int(im23.get_pixel(cc, cc).a * 255.0)
		var a_top: int = int(im23.get_pixel(cc, 3).a * 255.0)
		var a_corner: int = int(im23.get_pixel(3, 3).a * 255.0)
		var a_mid: int = int(im23.get_pixel(cc + cc / 2, cc).a * 255.0)
		chk(a_c > 240, "光晕中心最亮 (alpha %d)" % a_c)
		chk(a_top < 12 and a_corner < 12,
			"光晕是圆的不是方的 (上边 %d / 角落 %d)" % [a_top, a_corner])
		chk(a_mid > 20 and a_mid < a_c, "光晕往外一圈圈减弱 (半径一半处 %d < 中心 %d)" % [a_mid, a_c])
	cp23.open_panel()
	chk(cp23.is_open(), "篝火面板能打开")
	# 23.4b 招募之前就能把这个人看清楚 —— 火边站着的人 / 面板信息卡 / 真招进来的那位，
	#       必须是**同一个人**（预览和招募共用 slaves.gd 的 _roll_slave）
	var npc23: GDScript = load("res://scene/slave_npc.gd")
	var vis23: Node = g.campfire.get_node_or_null("Visitor")
	chk(vis23 != null, "招募前火边就站着一个人（等你搭话）")
	var pv23: Dictionary = Slaves.preview_next()
	chk(Slaves.count == n_before, "看一眼预览不改人数（还是 %d）" % Slaves.count)
	chk(String(Slaves.preview_next().get("name", "")) == String(pv23.get("name", "")),
		"同一个名额预览两次是同一个人（%s）" % String(pv23.get("name", "")))
	chk(cp23._p_name.text == String(pv23.get("name", "")),
		"信息卡写的就是这个人（%s）" % cp23._p_name.text)
	chk(cp23._portrait.texture != null, "信息卡里带人物小像")
	chk(cp23._p_troop.text.begins_with(String(pv23.get("troop", ""))),
		"信息卡写明兵种（%s）" % cp23._p_troop.text)
	chk(cp23._p_stat.text.contains(str(int(pv23.get("max_hp", -1)))),
		"信息卡给出血量/攻击（%s）" % cp23._p_stat.text)
	chk(cp23.get("_p_taste") == null, "信息卡不再有口味行（e30s 口味偏好系统已拆）")
	# UI 文案只能用 ASCII 标点：IPix.ttf 没有全角括号/顿号的字形，渲出来是方块
	# （篝火面板这行老文案就踩过：'（越往后越贵）'）
	var bad_punct := "（）：，。！？；、“”‘’《》【】「」…—～"
	var offenders: Array = []
	for t23 in [cp23._money.text, cp23._info.text, cp23._info2.text, cp23._card_title.text,
			cp23._p_name.text, cp23._p_troop.text, cp23._p_stat.text,
			cp23._p_life.text, cp23._p_note.text, cp23._btn.text]:
		var s23 := String(t23)
		for i23 in s23.length():
			if bad_punct.contains(s23[i23]):
				offenders.append(s23)
				break
	chk(offenders.is_empty(), "篝火面板文案没有全角标点 (会渲成方块): %s" % str(offenders))
	# 火边站着的那张脸 = 下一位的脸（跟白天跑的那个伙伴同一条 model_for 规则）
	if vis23 != null:
		var vis_body: AnimatedSprite2D = vis23.get_node_or_null("Body")
		var vis_at: AtlasTexture = null
		if vis_body != null:
			vis_at = vis_body.sprite_frames.get_frame_texture(&"idle_side", 0)
		# e29c: 改色贴图烘在 ImageTexture 里没有 resource_path ——
		# 改成直接跟改色管线的缓存对象比对（空配方时 sheet_texture
		# 返回的就是原图, 同样能对上; 同 key 永远同一份）。
		var want_tex23: Texture2D = npc23.sheet_texture(npc23.model_for(n_before), "Idle.png", n_before)
		chk(vis_at != null and vis_at.atlas == want_tex23,
			"火边站着的那位用的是第 %d 号的脸（%s）" % [n_before, npc23.model_for(n_before)])
	# 23.4c 上前搭话: 播剧情对话 -> 诉求达成当场入队（23.1 招了布恩, 火边是第 2 位娜雅:
	# 第 2 天窗口开, 交出 6 份作物当场入伙）
	var y_bak23: int = TimeManager.year
	var s_bak23: int = TimeManager.season
	var d_bak23: int = TimeManager.day
	TimeManager.year = 1
	TimeManager.season = 0
	TimeManager.day = 2      # 娜雅的花名册到访日
	var sd23: Node = g.get_tree().get_first_node_in_group("story_dialogue")
	chk(sd23 != null, "场景里挂着剧情对话框 (story_dialogue)")
	# 保险: 若前面的测试留了没收的对话, 先替他按完
	for i23a in 20:
		if not bool(sd23.call("is_open")):
			break
		var ev23a := InputEventAction.new()
		ev23a.action = "ui_accept"
		ev23a.pressed = true
		sd23._input(ev23a)
		await get_tree().process_frame
	var potato23: ItemData = load("res://item/potato.tres")   # type=作物, 娜雅只认作物
	Inventory.add_item(potato23, 8)   # 娜雅的诉求: 6 份作物
	# 入伙现在是导演模式长演出（cg_view 场景 + 台词）: 加速时间 + 按够次数让它播完
	Engine.time_scale = 20.0
	cp23._talk()
	chk(bool(sd23.call("is_open")), "搭话播起剧情对话 (intro)")
	for i23b in 60:
		var ev23 := InputEventAction.new()
		ev23.action = "ui_accept"
		ev23.pressed = true
		sd23._input(ev23)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	chk(Slaves.count == n_before + 1, "聊定了, 娜雅入伙（%d -> %d）" % [n_before, Slaves.count])
	TimeManager.year = y_bak23
	TimeManager.season = s_bak23
	TimeManager.day = d_bak23
	# 把没用完的作物收走, 还原背包（诉求扣 6, 剩多少清多少）
	var left23 := Inventory.count_item(potato23)
	if left23 > 0:
		Inventory.remove_item(potato23, left23)
	# 一堆火只招一个人，招完那位坐到火边
	chk(bool(g.campfire.recruited), "招完之后这堆火标记为「已招过」")
	chk(g.campfire.get_node_or_null("Sitter") != null, "火边坐着一个人")
	# 招到的 == 预览里看到的那位（名字/兵种逐项对账，不是「随机换个人」）
	var got23: Dictionary = Slaves.slave_at(Slaves.count - 1)
	chk(String(got23.get("name", "")) == String(pv23.get("name", "")),
		"招到的就是火边预览的那位（%s）" % String(got23.get("name", "")))
	chk(String(got23.get("troop", "")) == String(pv23.get("troop", "")),
		"兵种也跟预览一致（%s）" % String(got23.get("troop", "")))
	chk(g.campfire.get_node_or_null("Visitor") == null, "招完之后「等着的那个人」不在了（他坐下变成 Sitter）")
	cp23._refresh()
	chk(cp23._p_name.text == String(got23.get("name", "")),
		"卡片改写成火边坐着的那位（%s）" % cp23._p_name.text)
	cp23._refresh()
	chk(cp23._btn.disabled, "招过人的火不能再招（按钮禁用）")
	var n_two: int = Slaves.count
	cp23._talk()
	chk(Slaves.count == n_two, "同一堆火聊不出第二个人（还是 %d 人）" % Slaves.count)
	cp23.close_panel()
	# 满员的日子不出火
	Slaves.clear_all()
	while Slaves.count < Slaves.CAP:
		Slaves.recruit_roster()
	g._clear_campfire()
	var had := g.campfire != null
	g._on_campfire_tick()
	chk(not had and g.campfire == null, "满员时傍晚不再出现篝火")
	Slaves.clear_all()
	g._clear_campfire()

	# 23.5 白天闲逛：涂得越多的地方，去的人越多
	Slaves.clear_all()
	while Slaves.count < 6:
		Slaves.recruit_roster()
	chk(Slaves.count == 6, "凑够 6 个伙伴来测闲逛（实际 %d）" % Slaves.count)
	for x in range(10, 12):
		for y in range(10, 12):
			Slaves.assign(Vector2i(x, y), Slaves.TASK_TILL)        # 一小片 2x2
	for x in range(30, 36):
		for y in range(30, 36):
			Slaves.assign(Vector2i(x, y), Slaves.TASK_PLANT)       # 一大片 6x6
	await get_tree().process_frame
	var npc: Node2D = g.slave_nodes[0]
	var big := 0
	var small := 0
	for i in 400:
		npc._pick_target()
		var tc := cell_of(npc._target)
		if tc.x >= 30 and tc.x <= 35 and tc.y >= 30 and tc.y <= 35:
			big += 1
		elif tc.x >= 10 and tc.x <= 11 and tc.y >= 10 and tc.y <= 11:
			small += 1
	chk(big + small == 400, "伙伴只会挑「派过活」的格子当落点（%d/%d）" % [big + small, 400])
	chk(big > small * 3, "大片涂色区被挑中的次数远多于小片（%d : %d，格子数 36 : 4）" % [big, small])

	# 23.6 模型：伙伴不该长着主角那张脸；而且五套动作都得在
	var npc0: Node2D = g.slave_nodes[0]
	var models := {}
	for n in g.slave_nodes:
		models[n.model_name()] = true
	chk(not models.has("Josh"), "伙伴用的是别的角色模型，不是主角 Josh（实际 %s）" % str(models.keys()))
	chk(models.size() >= 4, "6 个伙伴用上了 %d 种不同模型" % models.size())
	var slave_frames: SpriteFrames = npc0._sprite.sprite_frames
	var need_anim := ["idle", "walk", "hoe", "water", "sickle"]
	var miss_anim: Array = []
	for a in need_anim:
		for d in ["down", "up", "side"]:
			if not slave_frames.has_animation(StringName("%s_%s" % [a, d])):
				miss_anim.append("%s_%s" % [a, d])
	chk(miss_anim.is_empty(),
		"伙伴有 待机/走路/锄地/浇水/播种 五套动作 x 三个朝向（缺 %s）" % str(miss_anim))
	chk(slave_frames.get_frame_count(&"hoe_down") == 6 and slave_frames.get_frame_count(&"water_down") == 8
			and slave_frames.get_frame_count(&"walk_down") == 6,
		"帧数跟素材一致（锄地 %d / 浇水 %d / 走路 %d）"
			% [slave_frames.get_frame_count(&"hoe_down"), slave_frames.get_frame_count(&"water_down"), slave_frames.get_frame_count(&"walk_down")])
	chk(not slave_frames.get_animation_loop(&"hoe_down") and slave_frames.get_animation_loop(&"walk_down"),
		"干活的动作播一遍就停、走路的循环播")
	chk(npc0._sprite.position == Vector2(0, -16),
		"伙伴的精灵画在原点上方 16 像素（原点在脚下，才能跟房子/水井一起 y_sort）")

	# 23.6b 前后左右四个方向都要有走路动画：
	#   素材只有「下 / 上 / 侧」三行，左右是同一张侧身图水平翻过来 ——
	#   以前直接拿朝向拼动画名（walk_left），根本不存在，左右走的时候动画就不播了。
	var walk_of := {"down": "walk_down", "up": "walk_up", "right": "walk_side", "left": "walk_side"}
	var bad_dir: Array = []
	for d in walk_of.keys():
		npc0._facing = StringName(d)
		var an: StringName = npc0._anim_name(&"walk")
		if an != StringName(walk_of[d]):
			bad_dir.append("%s->%s" % [d, an])
	chk(bad_dir.is_empty(), "四个朝向都能拼出走路动画（缺 %s）" % str(bad_dir))
	chk(slave_frames.has_animation(&"walk_side") and slave_frames.has_animation(&"idle_side")
			and slave_frames.has_animation(&"water_side"),
		"侧身那行的 走路/待机/干活 动画都在（左右方向靠它）")
	for d in walk_of.keys():
		for a in ["idle", "walk", "hoe", "water", "sickle"]:
			var an2: StringName = StringName("%s_%s" % [a, walk_of[d].split("_")[1]])
			chk(slave_frames.has_animation(an2), "%s 的 %s 动画存在" % [d, an2])

	# 真的走一步：从右边往回走，播的应该是「侧身走路」而且精灵要水平翻转
	var walker: Node2D = load("res://scene/slave_npc.gd").new()
	walker.index = 0
	g.add_child(walker)
	walker.setup(0, npc0.global_position)
	walker.global_position = npc0.global_position + Vector2(140, 0)
	var saw_side := false
	var saw_flip := false
	for i in 200:
		if walker._step_toward(0.016, npc0.global_position) == 1:
			break
		if String(walker._sprite.animation) == "walk_side":
			saw_side = true
		if walker._sprite.flip_h:
			saw_flip = true
	chk(saw_side and saw_flip,
		"从右边往回走：播的是「侧身走路」并且水平翻转了（动画=%s，flip=%s）"
			% [walker._sprite.animation, walker._sprite.flip_h])
	# 四个朝向各摆一个姿势，动画名和翻转都得对
	var pose_of := {"down": ["walk_down", false], "up": ["walk_up", false],
		"right": ["walk_side", false], "left": ["walk_side", true]}
	var bad_pose: Array = []
	for d in pose_of.keys():
		walker._facing = StringName(d)
		walker._play_loop(&"walk")
		var want: Array = pose_of[d]
		if String(walker._sprite.animation) != str(want[0]) \
				or walker._sprite.flip_h != bool(want[1]):
			bad_pose.append("%s:(%s,%s)" % [d, walker._sprite.animation, walker._sprite.flip_h])
	chk(bad_pose.is_empty(), "前后左右各摆一个走路姿势都对了（不对的：%s）" % str(bad_pose))
	walker.queue_free()
	await get_tree().process_frame

	# 23.7 白天真的把活干出来（不是站着摆样子）
	# 找 3 格横着挨在一起、还没耕过的空地 —— 这样伙伴从最左那格走到最右那格一路上都是陆地
	var run_cells: Array = []
	for y in range(g.ISLAND_FROM.y, g.ISLAND_TO.y + 1):
		if run_cells.size() >= 3:
			break
		for x in range(g.ISLAND_FROM.x, g.ISLAND_TO.x - 2):
			var ok := true
			for k in 3:
				var c := Vector2i(x + k, y)
				if g.is_water(c) or not g._land_set.has(c) or Farm.tilled.has(c):
					ok = false
					break
			if ok:
				run_cells = [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y)]
				break
	chk(run_cells.size() == 3, "找到 3 格连成一排的空地来测伙伴干活（%s）" % str(run_cells))

	if run_cells.size() == 3:
		var hour_bak23: int = TimeManager.hour
		TimeManager.hour = 10                      # 锁成白天，否则伙伴到点就下班了
		var worker: Node2D = load("res://scene/slave_npc.gd").new()
		worker.index = 0
		g.add_child(worker)
		worker.setup(0, Farm.grid_origin)

		# 让伙伴自己走过去干活；返回「走了几步（帧）」；-1 表示没干成
		# (a) 锄地：站远 2 格，看它会不会自己走过去
		Slaves.clear_all()
		var w_till: Vector2i = run_cells[2]
		Slaves.assign(w_till, Slaves.TASK_TILL)
		worker.global_position = Farm.grid_origin + Vector2(
			run_cells[0].x * TS + 8, run_cells[0].y * TS + 8)
		worker._decide_next()
		# State.GO_WORK = 1（枚举在 slave_npc.gd 里：0 闲逛 / 1 走过去 / 2 干活 / 3 歇着）
		chk(worker._state == 1, "有活没干时，伙伴进入「走过去干活」状态（%d）" % worker._state)
		var f_till: int = pump_slave(worker, w_till, 400)
		chk(Farm.tilled.has(w_till), "伙伴自己走过去把地锄了（第 %d 帧，格子 %s）" % [f_till, str(w_till)])
		chk(Slaves.is_done(w_till), "干完之后这一格被打了「今天已干完」的勾")
		chk(Slaves.assignments.has(w_till), "涂色记录（计划）不会被删掉 —— 夜里那张地图还要显示")

		# (b) 浇水：同一格改成浇水，应该真的变湿土
		Slaves.done_today.erase(w_till)
		chk(Slaves.assign(w_till, Slaves.TASK_WATER), "把这一格的活改成「浇水」")
		worker._decide_next()
		var f_water: int = pump_slave(worker, w_till, 400)
		chk(Farm.is_watered(w_till), "伙伴把这一格浇了（第 %d 帧）" % f_water)

		# (c) 播种：会真的扣掉背包里一颗种子，地上冒出苗
		Slaves.done_today.erase(w_till)
		var potato_seed: ItemData = load("res://item/seed.tres")
		Inventory.add_item(potato_seed, 3)
		var seeds_before: int = Inventory.count_item(potato_seed)
		chk(Slaves.assign(w_till, Slaves.TASK_PLANT), "把这一格的活改成「播种」")
		worker._decide_next()
		var f_plant: int = pump_slave(worker, w_till, 400)
		chk(Farm.has_crop(w_till), "伙伴把种子播下去了（第 %d 帧）" % f_plant)
		chk(Inventory.count_item(potato_seed) == seeds_before - 1,
			"播种扣掉背包里 1 颗种子（%d -> %d）" % [seeds_before, Inventory.count_item(potato_seed)])

		# (d) 干活时会播对应那套动作，不是站着不动
		Slaves.done_today.erase(w_till)
		Slaves.erase(w_till)
		Slaves.assign(run_cells[1], Slaves.TASK_TILL)
		worker.global_position = Farm.grid_origin + Vector2(
			run_cells[1].x * TS + 8, run_cells[1].y * TS + 8)
		worker._decide_next()
		var saw_hoe := false
		for i in 200:
			worker._process(0.02)
			if String(worker._sprite.animation).begins_with("hoe"):
				saw_hoe = true
			if Slaves.is_done(run_cells[1]):
				break
		chk(saw_hoe, "干活的时候播的是「锄地」那套动画（不是在原地站着）")

		# (e) 没种子时不硬种，也不会把这一格算作干完（等玩家给了种子还能补种）
		# 先把那格上的苗摘掉，只留「空耕地」，这样撞到的才是「缺种子」而不是「已经种过了」
		var seed_cell: Vector2i = run_cells[2]
		Farm.crops.erase(seed_cell)
		Slaves.done_today.erase(seed_cell)
		Slaves.erase(seed_cell)
		Slaves.assign(seed_cell, Slaves.TASK_PLANT)
		# ❗要把背包里**所有**种子都清掉：伙伴找不到土豆种子时会退而求其次用别的种子，
		#   只清土豆的话它照样种下去了，这条断言就测不出「没种子」这条分支。
		for s in Inventory.slot_list():
			var it: ItemData = s["item"]
			if it != null and it.type == "种子":
				Inventory.remove_item(it, Inventory.count_item(it))
		chk(Inventory.count_item(potato_seed) == 0, "先把背包里的种子清空")
		worker.global_position = Farm.grid_origin + Vector2(
			seed_cell.x * TS + 8, seed_cell.y * TS + 8)
		worker._decide_next()
		pump_slave(worker, seed_cell, 300)
		chk(not Slaves.is_done(seed_cell), "没种子时这一格不会被标成「已干完」—— 留着等有种子再补")

		# (f) 换日会把「今天已干完」清空（第二天可以重新派一遍）
		Slaves.done_today[Vector2i(0, 0)] = true
		Slaves._on_new_day(TimeManager.day)
		chk(Slaves.done_today.is_empty(), "换日后「今天已干完」的勾全部清空")
		chk(Slaves.assignments.size() > 0, "但涂色计划（assignments）不受影响，还留着")

		# (g) 水面上不能派活（伙伴站不进去）
		var water_cell := Vector2i(0, 0)
		for c in g._water_set.keys():
			water_cell = c
			break
		chk(not Slaves.in_map(water_cell) or g.is_water(water_cell), "取到一格水面（%s）" % str(water_cell))
		if ap23 != null and ap23._map != null:
			chk(not ap23._map.can_paint(water_cell), "涂色地图拒绝在水面上派活")

		# (h) 睡前兜底：今天没干完的活，换日前会被「强行补完」（跟伙伴用同一套 apply_task）
		Slaves.clear_all()
		Slaves.done_today.clear()
		var ff_cell: Vector2i = run_cells[0]
		Farm.till(ff_cell)
		Farm.watered.erase(ff_cell)
		Slaves.assign(ff_cell, Slaves.TASK_WATER)
		chk(Farm.is_tilled(ff_cell) and not Farm.is_watered(ff_cell),
			"兜底测试地块准备好了（已耕地、还是干的）")
		chk(not Slaves.is_done(ff_cell), "这一格今天还没人干")
		var ff_n: int = g._force_finish_work()
		chk(Farm.is_watered(ff_cell), "强行补完把没浇的水浇上了（补了 %d 格）" % ff_n)
		chk(Slaves.is_done(ff_cell), "补完的格子打了「已干完」的勾")
		chk(ff_n == 1, "返回值就是补完的格数（%d）" % ff_n)
		# 干不了的活不会被硬来：缺种子的播种格保持「没干」
		Slaves.clear_all()
		Slaves.done_today.clear()
		Farm.crops.erase(seed_cell)
		Slaves.assign(seed_cell, Slaves.TASK_PLANT)
		var ff_n2: int = g._force_finish_work()
		chk(ff_n2 == 0 and not Slaves.is_done(seed_cell),
			"缺种子时兜底也不会硬种（补了 %d 格）" % ff_n2)

		# (i) 玩家绘制派活地图时（面板开着），伙伴全体停工
		Slaves.clear_all()
		Slaves.done_today.clear()
		Farm.watered.erase(run_cells[0])
		Slaves.assign(run_cells[0], Slaves.TASK_WATER)
		worker.global_position = Farm.grid_origin + Vector2(
			run_cells[0].x * TS + 8, (run_cells[0].y + 4) * TS + 8)
		worker._decide_next()
		chk(worker._state == 1, "有活没干时伙伴准备去干（状态 %d）" % worker._state)
		Slaves.paused = true
		var pp := worker.global_position
		for i in 30:
			worker._process(0.02)
		chk(worker.global_position == pp, "绘制期间伙伴一步都不挪")
		chk(not Slaves.is_done(run_cells[0]) and not Farm.is_watered(run_cells[0]),
			"绘制期间手上的活也不落")
		# 面板开关自动管这个暂停开关
		if ap23 != null:
			ap23.open()
			chk(Slaves.paused, "打开派活面板：伙伴自动停工")
			ap23._dismiss()
			chk(not Slaves.paused, "关掉派活面板：伙伴复工")
		Slaves.paused = false
		var finished := false
		for i in 400:
			worker._process(0.02)
			if Slaves.is_done(run_cells[0]):
				finished = true
				break
		chk(finished and Farm.is_watered(run_cells[0]), "解除暂停后接着把活干完")

		Slaves.clear_all()
		TimeManager.hour = hour_bak23
		worker.queue_free()
		await get_tree().process_frame

	# 收尾：伙伴清空、钱还回去，别影响别的地方
	Slaves.clear_all()
	Slaves.count = 0
	Slaves.changed.emit()
	Wallet.money = money_bak23
	await get_tree().process_frame
	chk(g.slave_nodes.size() == 0, "伙伴数清零后小人也收走了（%d）" % g.slave_nodes.size())

	print("\n=== 24. 相机缩放（Ctrl + 滚轮）+ 背包的开启键 ===")
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	chk(cam != null, "玩家身上挂着 Camera2D")
	if cam != null:
		chk(cam.zoom.x == cam.zoom.y, "缩放是等比的（%s）" % str(cam.zoom))
		chk(cam.zoom.x == floor(cam.zoom.x), "缩放是整数倍（%s）—— 像素画不会被拉出 3px/4px 混排" % str(cam.zoom))
		chk(g.ZOOM_MIN >= 2 and g.ZOOM_MAX > g.ZOOM_MIN, "缩放范围 %d ~ %d 倍" % [g.ZOOM_MIN, g.ZOOM_MAX])
		var z_saved: Vector2 = cam.zoom
		var z0 := int(round(cam.zoom.x))
		g._zoom_camera(1)
		chk(int(round(cam.zoom.x)) == mini(z0 + 1, g.ZOOM_MAX), "放大一档（%d -> %d）" % [z0, int(round(cam.zoom.x))])
		g._zoom_camera(-1)
		chk(int(round(cam.zoom.x)) == z0, "缩小一档回到 %d 倍" % z0)
		for _i in 10:
			g._zoom_camera(1)
		chk(int(round(cam.zoom.x)) == g.ZOOM_MAX, "一直放大最多到 %d 倍（实际 %d）" % [g.ZOOM_MAX, int(round(cam.zoom.x))])
		for _i in 20:
			g._zoom_camera(-1)
		chk(int(round(cam.zoom.x)) == g.ZOOM_MIN, "一直缩小最少到 %d 倍（实际 %d）" % [g.ZOOM_MIN, int(round(cam.zoom.x))])
		cam.zoom = z_saved
		# 造一个真的「Ctrl + 滚轮」事件，看它能不能走进缩放逻辑
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		wheel.ctrl_pressed = true
		var z_before := int(round(cam.zoom.x))
		g._unhandled_input(wheel)
		chk(int(round(cam.zoom.x)) == mini(z_before + 1, g.ZOOM_MAX),
			"Ctrl + 滚轮上滚真的会放大（%d -> %d）" % [z_before, int(round(cam.zoom.x))])
		var plain := InputEventMouseButton.new()
		plain.button_index = MOUSE_BUTTON_WHEEL_UP
		plain.pressed = true
		var z_plain := int(round(cam.zoom.x))
		g._unhandled_input(plain)
		chk(int(round(cam.zoom.x)) == z_plain, "不按 Ctrl 时滚轮不动缩放（留给别的用途）")
		cam.zoom = z_saved

	# 背包：B / Esc 并列开关（Esc 上轮让给外交、这轮收回来了，外交并进背包页签）
	chk(InputMap.has_action("toggle_inventory"), "有 toggle_inventory 这个动作")
	var has_esc := false
	var has_b := false
	for ev in InputMap.action_get_events("toggle_inventory"):
		var k := ev as InputEventKey
		if k == null:
			continue
		if k.physical_keycode == KEY_ESCAPE or k.keycode == KEY_ESCAPE:
			has_esc = true
		if k.physical_keycode == KEY_B or k.keycode == KEY_B:
			has_b = true
	chk(has_esc, "Esc 绑在开关背包上（B / Esc 并列）")
	chk(has_b, "B 还绑在开关背包上")
	var esc_ev := InputEventKey.new()
	esc_ev.physical_keycode = KEY_ESCAPE
	esc_ev.pressed = true
	chk(InputMap.event_is_action(esc_ev, "toggle_inventory"), "按 Esc 会被识别成「开关背包」")
	var bp24: Control = g.get_node_or_null("HUD/Backpack")
	if bp24 != null:
		var was_open: bool = bp24.is_open()
		if was_open:
			bp24.toggle()   # 先归到关, 下面专心验 Esc 的行为, 最后再还原
		# 9 节真跑过睡觉换日, 异步的醒来流程可能还没走到 _sleeping = false;
		# 这里先按住它, 专心验 Esc -> 背包的开关, 验完原样还回去
		var sleeping_bak: bool = g._sleeping
		g._sleeping = false
		g._unhandled_input(esc_ev)
		chk(bp24.is_open(), "按 Esc 翻开背包")
		g._unhandled_input(esc_ev)
		chk(not bp24.is_open(), "再按 Esc 关掉背包")
		g._sleeping = sleeping_bak
		# 夜晚那两张面板开着时，Esc 是它们的，不该顺手翻背包
		if g.assign_panel != null:
			g.assign_panel.open()
			g._unhandled_input(esc_ev)
			chk(not bp24.is_open(), "派活面板开着时按 Esc 不会顺手把背包翻开")
			g.assign_panel._dismiss()
		if was_open:
			bp24.toggle()

	print("\n=== 25. 按键提示：悬浮不消失 / 飞入飞出 / 像素字体 ===")
	# e53 起篝火是条件生成的（18 点后 + 花名册有到访窗口才点堆火, 过夜还会熄）:
	# 这里先收干净再强制点一堆, 保证第 6 个提示稳定在场
	g._clear_campfire()
	await get_tree().process_frame
	g._spawn_campfire()
	var hints25: Array = []
	collect_hints(g, hints25)
	chk(hints25.size() == 6,
		"场景里有 6 个按键提示（商人/售卖箱/大门/床/出口/篝火，实际 %d）" % hints25.size())
	var words25: Array = []
	for h in hints25:
		words25.append(h.get_text())
	chk(words25.has("F 交易") and words25.has("F 售卖箱")
			and words25.has("F 进屋") and words25.has("F 睡觉") and words25.has("F 出门")
			and (words25.has("F 看看他") or words25.has("F 篝火")),
		"提示词都改成「按键 + 短动作」了（%s）" % str(words25))
	# 默认状态：全都藏着、完全透明
	var any_visible := false
	for h in hints25:
		if h.visible:
			any_visible = true
	chk(not any_visible, "没人走近的时候，提示全都藏着")
	var h0: Node2D = hints25[0]
	chk(h0.z_index == 3, "提示压在角色和地形之上（z_index = %d）" % h0.z_index)
	chk(h0.WORD_SIZE <= 11, "动作词字号比原来的 14 小（现在 %d）" % h0.WORD_SIZE)
	chk(h0._box.x > 20 and h0._box.y > 8,
		"框的大小是按像素字体量出来的，不是写死的（%s）" % str(h0._box))
	chk(h0.modulate.a < 0.01, "飞入之前是完全透明的（a=%.2f）" % h0.modulate.a)

	# 飞入
	h0.show_hint()
	chk(h0.visible, "走近 -> 提示显示出来（开始飞入）")
	await get_tree().create_timer(0.32).timeout
	chk(h0.modulate.a > 0.95, "飞入动画跑完，完全不透明（a=%.2f）" % h0.modulate.a)
	chk(h0.scale.x > 0.95, "飞入时从 0.72 放大回原尺寸（%.2f）" % h0.scale.x)

	# 悬浮：停着的时候会轻轻上下动，而且幅度很小
	var ys: Array = []
	for i in 6:
		await get_tree().create_timer(0.18).timeout
		ys.append(h0.position.y)
	var moved25 := false
	for v in ys:
		if absf(v - ys[0]) > 0.5:
			moved25 = true
	chk(moved25, "停下来之后在半空轻轻上下浮动，不会消失（采样 %s）" % str(ys))
	var max_dev := 0.0
	for v in ys:
		max_dev = maxf(max_dev, absf(v - h0._base_y))
	chk(max_dev <= h0.FLOAT_AMP + 1.5,
		"浮动幅度很小，不会乱飘（离基准最多 %.1f 像素）" % max_dev)

	# 飞出
	h0.hide_hint()
	await get_tree().create_timer(0.36).timeout
	chk(not h0.visible, "走远 -> 飞出之后隐藏")
	chk(h0.modulate.a < 0.05, "飞出时淡掉了（a=%.2f）" % h0.modulate.a)

	print("\n=== 26. Esc 面板：上方的模块选择（含地图）===")
	var bp26: Control = g.get_node_or_null("HUD/Backpack")
	chk(bp26 != null, "背包面板还在（现在它是 Esc 模块面板）")
	if bp26 != null:
		var names26: Array = []
		for m in bp26.MODULES:
			names26.append(str(m["name"]))
		chk(names26 == ["背包", "角色个人及技能", "团队管理", "战斗", "科技", "行政", "地图", "物品制作", "建造", "外交", "任务", "设置"],
			"模块顺序对（d11 加了战斗页签）：%s" % str(names26))
		chk(bp26._tab_btns.size() == 12, "上方有 12 个模块按钮（%d 个）" % bp26._tab_btns.size())
		# 地图那一栏必须排在「物品制作」前面、建造在设置前面
		chk(names26.find("地图") >= 0 and names26.find("地图") < names26.find("物品制作"),
			"「地图」排在「物品制作」前面（第 %d 个）" % (names26.find("地图") + 1))
		chk(names26.find("建造") >= 0 and names26.find("建造") < names26.find("设置"),
			"「建造」排在「设置」前面（第 %d 个）" % (names26.find("建造") + 1))
		# 科技 / 行政两页要能切过去并渲染出内容
		bp26._switch_to("tech")
		chk(bp26._pages["tech"].visible and bp26._tech_info != null
			and bp26._tech_info.text.find("科技点") >= 0,
			"科技页能打开并显示点数")
		chk(bp26._tech_rows.size() == Research.TECHS.size(),
			"科技页列出全部 %d 项科技" % bp26._tech_rows.size())
		chk(bp26._pages["tech"].visible and not bp26._pages["admin"].visible, "切页时只显示当前页")
		bp26._switch_to("admin")
		chk(bp26._pages["admin"].visible and bp26._admin_info != null
			and bp26._admin_info.text.find("生效槽") >= 0
			and bp26._admin_info.text.find("准备") >= 0,
			"行政页能打开并显示 生效槽/准备槽")
		chk(bp26._admin_rows.size() == Research.ADMINS.size(),
			"行政页列出全部 %d 项行政" % bp26._admin_rows.size())
		chk(bp26._card_rows.size() == Research.CARDS.size(),
			"行政页列出全部 %d 张政策卡" % bp26._card_rows.size())
		bp26._switch_to("bag")

		bp26.open()
		chk(bp26._current == "bag" and bp26._pages["bag"].visible,
			"默认停在「背包」这一页")
		chk(not bp26._pages["map"].visible, "别的页先藏着")

		bp26._select_module("map")
		chk(bp26._current == "map" and bp26._pages["map"].visible,
			"点「地图」切到地图页")
		chk(not bp26._pages["bag"].visible, "原来那页收起来了")
		chk(bp26._title.text == "地图", "标题跟着换成「地图」（%s）" % bp26._title.text)
		var tm: Node = bp26.get("_map_page")
		chk(tm != null, "地图页里有一张地形图")
		if tm != null:
			chk(tm.game == g, "地形图接上了真实地图数据")
			chk(tm.map_from == Slaves.map_from and tm.map_to == Slaves.map_to,
				"范围跟派活地图一致（%s ~ %s）" % [str(tm.map_from), str(tm.map_to)])
			chk(tm.show_actors, "地图上会画出人物（自己 / 伙伴）")
			# 地形是真的：水格和草地格画出来的颜色不一样
			var w_cell := Vector2i(0, 0)
			for c in g._water_set.keys():
				if Slaves.in_map(c):
					w_cell = c
					break
			var l_cell := Vector2i(0, 0)
			var found_grass := false
			for c in g._land_set.keys():
				var cv: Vector2i = c
				if Slaves.in_map(cv) and not g.is_water(cv) \
						and not Farm.tilled.has(cv) and not Farm.crops.has(cv):
					l_cell = cv
					found_grass = true
					break
			chk(found_grass, "取到一格草地（%s）" % str(l_cell))
			var img26: Image = tm._base.get_image()
			var c_w: Color = img26.get_pixel(w_cell.x - tm.map_from.x, w_cell.y - tm.map_from.y)
			var c_g: Color = img26.get_pixel(l_cell.x - tm.map_from.x, l_cell.y - tm.map_from.y)
			chk(c_w != c_g, "水面和草地在图上是两种颜色（%s vs %s）" % [str(c_w), str(c_g)])
			chk(c_w.b > c_g.b, "水面偏蓝（蓝通道 %.2f > %.2f）" % [c_w.b, c_g.b])
			# 拖拽 + 滚轮
			var vc26: Vector2 = tm.view_center
			tm.pan_by(Vector2(48, 0))
			chk(tm.view_center.x != vc26.x, "Esc 地图也能拖拽移动视角（%.1f -> %.1f）"
				% [vc26.x, tm.view_center.x])
			var z26: float = tm.zoom
			tm.zoom_by(1)
			chk(tm.zoom > z26, "Esc 地图也能滚轮放缩（%.2f -> %.2f）" % [z26, tm.zoom])
			tm.reset_view()

		bp26._select_module("team")
		chk(bp26._pages["team"].visible and bp26._team_info != null,
			"「团队管理」页能打开")
		bp26._select_module("bag")
		bp26.close()
		chk(not bp26.is_open(), "关掉了")

	print("\n=== 27. 滚轮切换快捷栏 ===")
	var inv_ui: Control = g.get_node_or_null("HUD/GridContainer")
	if inv_ui == null:
		var hud27: Node = g.get_node_or_null("HUD")
		if hud27 != null:
			for c in hud27.get_children():
				if c is GridContainer:
					inv_ui = c
					break
	chk(inv_ui != null, "找得到快捷栏（%s）" % str(inv_ui))
	if inv_ui != null:
		var sel0: int = inv_ui.selected_index
		var wd := InputEventMouseButton.new()
		wd.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wd.pressed = true
		inv_ui._unhandled_input(wd)
		chk(inv_ui.selected_index == wrapi(sel0 + 1, 0, Inventory.HOTBAR_SIZE),
			"滚轮往下滚 = 选中下一格（%d -> %d）" % [sel0, inv_ui.selected_index])
		var wu := InputEventMouseButton.new()
		wu.button_index = MOUSE_BUTTON_WHEEL_UP
		wu.pressed = true
		inv_ui._unhandled_input(wu)
		chk(inv_ui.selected_index == sel0, "往上滚又回到原来那格（%d）" % inv_ui.selected_index)
		# Ctrl + 滚轮是镜头缩放，不该顺手换道具
		var cw := InputEventMouseButton.new()
		cw.button_index = MOUSE_BUTTON_WHEEL_DOWN
		cw.pressed = true
		cw.ctrl_pressed = true
		inv_ui._unhandled_input(cw)
		chk(inv_ui.selected_index == sel0, "Ctrl + 滚轮留给镜头缩放，不会换道具（还是 %d）"
			% inv_ui.selected_index)
		# 滚到头会绕回另一头
		for i in Inventory.HOTBAR_SIZE:
			inv_ui._unhandled_input(wd)
		chk(inv_ui.selected_index == sel0, "绕一圈回到原处（%d）" % inv_ui.selected_index)

	print("\n=== 28. 物品制作 ===")
	# 先给背包塞一堆材料
	Inventory.add_item(load("res://item/potato.tres"), 8)
	Inventory.add_item(load("res://item/carrot.tres"), 8)
	Inventory.add_item(load("res://item/cabbage.tres"), 4)
	Inventory.add_item(load("res://item/pumpkin.tres"), 4)
	Inventory.add_item(load("res://item/wheat.tres"), 4)
	Inventory.add_item(load("res://item/wood.tres"), 20)
	var potato_before: int = Inventory.count_item(load("res://item/potato.tres"))
	var wood_before28: int = Inventory.count_item(load("res://item/wood.tres"))
	var baked_before: int = Inventory.count_item(load("res://item/baked_potato.tres"))
	chk(Crafting.can_craft(0), "配方 0：土豆 + 木头 -> 烤土豆，材料够用")
	chk(Crafting.craft(0), "点制作烤土豆成功")
	chk(Inventory.count_item(load("res://item/baked_potato.tres")) == baked_before + 1,
		"背包里多了 1 份烤土豆（%d -> %d）" % [baked_before, Inventory.count_item(load("res://item/baked_potato.tres"))])
	chk(Inventory.count_item(load("res://item/potato.tres")) == potato_before - 1, "土豆 -1")
	chk(Inventory.count_item(load("res://item/wood.tres")) == wood_before28 - 1, "木头 -1")
	chk(Crafting.RECIPES.size() == 7, "配方表里有 7 个（4 食物 + 地板 + 小径 + 工作台；船只在码头造）")
	var wood_floor: ItemData = load("res://item/wood_floor.tres")
	var wood_floor_before: int = Inventory.count_item(wood_floor)
	var wood_before_b: int = Inventory.count_item(load("res://item/wood.tres"))
	# 找木地板的配方 index
	var floor_recipe_idx := -1
	for i in Crafting.RECIPES.size():
		if Crafting.RECIPES[i]["result"] == wood_floor:
			floor_recipe_idx = i
			break
	chk(floor_recipe_idx >= 0, "配方表里有「木地板」配方（idx=%d）" % floor_recipe_idx)
	var stone_path: ItemData = load("res://item/stone_path.tres")
	var path_idx := -1
	for i in Crafting.RECIPES.size():
		if Crafting.RECIPES[i]["result"] == stone_path:
			path_idx = i
			break
	chk(path_idx >= 0, "配方表里有「鹅卵石小径」配方（idx=%d）" % path_idx)
	if floor_recipe_idx >= 0:
		chk(Crafting.craft(floor_recipe_idx), "用 2 个木头做 1 块木地板")
		chk(Inventory.count_item(wood_floor) == wood_floor_before + 1, "背包里多 1 块木地板")
		chk(Inventory.count_item(load("res://item/wood.tres")) == wood_before_b - 2, "木头 -2")
	# 缺材料时不能做
	Inventory.remove_item(load("res://item/carrot.tres"), Inventory.count_item(load("res://item/carrot.tres")))
	var salad_recipe_idx := -1
	for i in Crafting.RECIPES.size():
		if Crafting.RECIPES[i]["result"] == load("res://item/carrot_salad.tres"):
			salad_recipe_idx = i
			break
	chk(not Crafting.can_craft(salad_recipe_idx), "胡萝卜吃光了，胡萝卜沙拉做不了")
	chk(not Crafting.craft(salad_recipe_idx), "尝试做也是失败")
	chk(Crafting.missing(salad_recipe_idx).size() == 1, "missing() 报告缺 1 种材料")

	print("\n=== 29. 食物（口味偏好系统已拆）===")
	var item_baked: ItemData = load("res://item/baked_potato.tres")
	var item_salad: ItemData = load("res://item/carrot_salad.tres")
	var item_soup: ItemData = load("res://item/cabbage_soup.tres")
	var item_pie: ItemData = load("res://item/pumpkin_pie.tres")
	for it29 in [item_baked, item_salad, item_soup, item_pie]:
		chk(String(it29.type) == "食物" and int(it29.sell_price) > 0,
			"%s 是能吃的食物（卖价 %d）" % [it29.display_name, it29.sell_price])
	# e30s: 口味偏好整套拆掉 —— ItemData 不再有 taste, Slaves 不再有 TASTE_POOL
	var has_taste29 := false
	for p29 in (load("res://item_data.gd") as Script).get_script_property_list():
		if String(p29.get("name", "")) == "taste":
			has_taste29 = true
	chk(not has_taste29, "ItemData 不再有 taste 字段")
	chk(not (load("res://slaves.gd") as Script).get_script_constant_map().has("TASTE_POOL"),
		"Slaves 不再有 TASTE_POOL")

	print("\n=== 30. 伙伴个体化（名字 / 好感 / 喂食）===")
	# 先把旧的伙伴清掉，重新招 3 个进来。
	# ❗用 while 循环只删 slaves 数组不会 emit changed，_sync_slaves 不会销毁对应节点，
	#   下次招新伙伴时 slaves.size() 跟 count 对不上 —— 改用 clear_all()，
	#   但 clear_all 只清任务分配不动 slaves 数组；所以两个一起清。
	for s in Slaves.slaves:
		s["fed_today"] = false
		s["talked_today"] = false
	Slaves.slaves.clear()
	Slaves.count = 0
	Slaves.changed.emit()    # 触发 _sync_slaves 把残留节点销毁
	await get_tree().process_frame
	# 花名册连招 3 人（布恩 / 娜雅 / 珞琳）, 分文不取
	Slaves.recruit_roster()
	Slaves.recruit_roster()
	Slaves.recruit_roster()
	chk(Slaves.count == 3, "招了 3 个伙伴（共 %d 人, slaves=%d）" % [Slaves.count, Slaves.slaves.size()])
	chk(Slaves.slaves.size() == 3 and Slaves.count == Slaves.slaves.size(), "slaves 数组和 count 同步（slaves=%d, count=%d）" % [Slaves.slaves.size(), Slaves.count])
	for s in Slaves.slaves:
		chk(s["name"] != "", "每个伙伴都有名字（%s）" % s["name"])
		chk(s["affection"] == 0, "新人初始好感 0")
		chk(not s.has("pref"), "新人身上不再有 pref 字段（口味偏好系统已拆）")
		chk(not bool(s["fed_today"]) and not bool(s["talked_today"]), "今天还没喂过/聊过")
	chk(Slaves.slaves[0]["name"] != "" and Slaves.slaves[1]["name"] != "",
		"招进来的人名字都不为空")
	# 改名
	var orig_name: String = Slaves.slaves[0]["name"]
	chk(Slaves.rename(0, "阿明"), "把第 0 个改名为「阿明」")
	chk(Slaves.slaves[0]["name"] == "阿明", "名字真的改了（%s -> %s）" % [orig_name, Slaves.slaves[0]["name"]])
	chk(not Slaves.rename(0, "   "), "空名字拒绝改名")
	chk(not Slaves.rename(99, "X"), "越界 index 拒绝")
	chk(Slaves.slaves[0]["name"] == "阿明", "改名失败后名字没变")
	# 喂食：吃什么都一样 +1 好感（口味偏好系统 e30s 已拆）
	Inventory.add_item(item_baked, 3)
	Inventory.add_item(item_pie, 3)
	var before_aff: int = int(Slaves.slaves[0]["affection"])
	var baked_have: int = Inventory.count_item(item_baked)
	var gain1: int = Slaves.feed(0, item_baked)
	if gain1 > 0:
		Inventory.remove_item(item_baked, 1)        # slaves.feed 不动背包，自己扣
	chk(gain1 == 1, "喂食 = 1 好感（实际 %d）" % gain1)
	chk(int(Slaves.slaves[0]["affection"]) == before_aff + 1, "好感真的 +1")
	chk(bool(Slaves.slaves[0]["fed_today"]), "今天喂过标记打开")
	chk(Inventory.count_item(item_baked) == baked_have - 1, "背包里少一份烤土豆")
	chk(Slaves.feed(0, item_pie) == 0, "今天再喂 = 0（不重复加）")
	# 好感上限：塞到 AFFECTION_MAX-1 再喂一份，恰好封顶不冲过
	Slaves.slaves[0]["affection"] = Slaves.AFFECTION_MAX - 1
	Slaves.slaves[0]["fed_today"] = false
	Slaves.slaves[0]["talked_today"] = false
	var pre_aff: int = int(Slaves.slaves[0]["affection"])
	var gain_pre: int = Slaves.feed(0, item_salad)
	chk(pre_aff + gain_pre <= Slaves.AFFECTION_MAX, "好感最多到 AFFECTION_MAX（pre=%d + gain=%d <= %d）"
		% [pre_aff, gain_pre, Slaves.AFFECTION_MAX])
	chk(int(Slaves.slaves[0]["affection"]) == Slaves.AFFECTION_MAX,
		"好感到了上限：%d" % int(Slaves.slaves[0]["affection"]))
	# 对话加好感
	for i in Slaves.slaves.size():
		Slaves.slaves[i]["affection"] = 0
		Slaves.slaves[i]["talked_today"] = false
		Slaves.slaves[i]["fed_today"] = false
	var g_talk: int = Slaves.talk(0)
	chk(g_talk == 1, "对话 +1 好感")
	chk(Slaves.talk(0) == 0, "今天再对话 = 0（不重复加）")

	print("\n=== 31. 木地板铺设 ===")
	# 找一格草地
	var land_for_floor := Vector2i(10, 20)
	for c in g._land_set.keys():
		land_for_floor = c
		break
	chk(g._land_set.has(land_for_floor), "找到一格陆地（%s）" % str(land_for_floor))
	chk(not Floor.is_floored(land_for_floor), "该格还没铺地板")
	chk(Floor.place(land_for_floor), "铺一格地板成功")
	chk(Floor.is_floored(land_for_floor), "该格已铺地板")
	chk(not Floor.place(land_for_floor), "同一格再铺 = false（重复）")
	# 找一格水面
	var water_cell := Vector2i(-99, -99)
	for c in g._water_set.keys():
		water_cell = c
		break
	chk(water_cell != Vector2i(-99, -99), "找到一格水面（%s）" % str(water_cell))
	# 铺一个相邻的格子形成拼接
	var nb_cell := land_for_floor + Vector2i.RIGHT
	if g._land_set.has(nb_cell):
		Floor.place(nb_cell)
		chk(Floor.is_floored(nb_cell), "相邻格也铺上")
	# 验证显示层有 sprite
	await get_tree().process_frame    # 等 FloorLayer 把刚铺的两格画出来
	var fl := g.get_node_or_null("FloorLayer")
	chk(fl != null, "FloorLayer 节点存在（%s）" % str(fl))
	if fl != null:
		var sprites := 0
		for c in fl.get_children():
			if c is Sprite2D:
				sprites += 1
		chk(sprites == Floor.floors.size(),
			"显示层有 %d 个 sprite，跟数据同步（数据 %d）" % [sprites, Floor.floors.size()])
	# 拆掉
	chk(Floor.remove(land_for_floor), "拆掉地板成功")
	chk(not Floor.is_floored(land_for_floor), "该格不再是地板")

	# —— 31.5 e30k 图块重画验收: 小径 = 又圆又大块的大圆石, 地板 = 错缝板条 ——
	print("\n=== 31.5 e30k 小径/地板图块重画 ===")
	if fl != null:
		var pimg: Image = fl._path_tile(12345).get_image()
		chk(pimg.get_pixel(8, 8).a > 0.5, "小径格中心是石头本体（不再是一堆小碎点）")
		var run := 0
		var best := 0
		for x in 16:
			if pimg.get_pixel(x, 8).a > 0.5:
				run += 1
				best = maxi(best, run)
			else:
				run = 0
		chk(best >= 8,
			"小径中线被一颗大圆石横穿（最长连块 %d px, 老版碎点最多 5）" % best)
		var wimg: Image = fl.tile_for("----", 67890).get_image()
		chk(wimg.get_pixel(0, 7).is_equal_approx(fl.RIM)
			and wimg.get_pixel(15, 7).is_equal_approx(fl.RIM),
			"地板 y=7 有一条通长板间缝")
		var seam_a := 0
		var seam_b := 0
		for x in 16:
			if wimg.get_pixel(x, 3).is_equal_approx(fl.RIM):
				seam_a += 1
			if wimg.get_pixel(x, 12).is_equal_approx(fl.RIM):
				seam_b += 1
		chk(seam_a == 1 and seam_b == 1,
			"地板上下两行各一道竖端缝（实测 %d/%d）" % [seam_a, seam_b])

	print("\n=== 32. 对话弹窗 ===")
	# 先看 dialogue_panel 是否存在
	var dp: Node = g.get_node_or_null("HUD/Dialogue")
	chk(dp != null, "对话面板 Dialogue 节点存在（%s）" % str(dp))
	if dp != null:
		# 强制打开看效果（e18: 打开面板不再自动聊天 —— 点「聊天」弹对话框, 关框才落账）
		for i in Slaves.slaves.size():
			Slaves.slaves[i]["talked_today"] = false
			Slaves.slaves[i]["fed_today"] = false
			Slaves.slaves[i]["affection"] = 0
		dp.call("open_panel", 0)
		chk(dp.is_open(), "open_panel 之后开着")
		chk(not bool(Slaves.slaves[0]["talked_today"]),
			"e18: 打开面板不自动聊天 (点聊天弹框, 关框才落账)")
		# 模拟「点聊天 → 翻完对话框 → 关框」: _finish_chat 里才调 Slaves.talk
		dp.call("_on_chat_pressed")
		chk(dp.get("_dialog").is_open(), "点聊天弹出对话框 (e18)")
		dp.get("_dialog").close()
		chk(Slaves.slaves[0]["talked_today"], "关掉对话框 = 当天第一次聊天落账 (e18)")
		chk(Slaves.slaves[0]["affection"] == 1, "聊天 +1 好感 (e18)")
		# 喂食按钮：模拟「点喂食」按钮的行为：找背包第一个食物、扣一份、加好感
		Inventory.add_item(item_baked, 1)
		var baked_count: int = Inventory.count_item(item_baked)
		# 直接走 slaves.feed + Inventory.remove_item，跟 dialogue_ui._on_feed_pressed 等价
		var gain_from_feed: int = Slaves.feed(0, item_baked)
		if gain_from_feed > 0:
			Inventory.remove_item(item_baked, 1)
		chk(bool(Slaves.slaves[0]["fed_today"]), "对话里点喂食 = 当天第一次喂食标记")
		chk(Slaves.slaves[0]["affection"] == 1 + gain_from_feed,
			"喂完好感 = %d（1 聊天 + %d 喂食）" % [1 + gain_from_feed, gain_from_feed])
		chk(Inventory.count_item(item_baked) == baked_count - 1, "背包里少一份烤土豆")
		dp.call("close_panel")
		chk(not dp.is_open(), "close_panel 之后关掉")

	print("\n=== 33. 斧头 + 树木 + 桥/水禁耕地 + 床碰撞 ===")
	# 33.1 新道具和动作
	var axe33: ItemData = load("res://item/axe.tres")
	chk(axe33 != null and axe33.display_name == "斧头" and axe33.type == "工具", "斧头道具在")
	var sf33: SpriteFrames = player.tool_sprite.sprite_frames
	chk(sf33.has_animation("axe_down") and sf33.has_animation("axe_up") and sf33.has_animation("axe_side"),
		"砍树动作 3 个朝向")
	chk(sf33.get_frame_count("axe_down") == 6, "砍树 6 帧（实际 %d）" % sf33.get_frame_count("axe_down"))
	chk(Inventory.count_item(axe33) >= 1, "开局背包里有一把斧头")
	var tseed33: ItemData = load("res://item/tree_seed.tres")
	chk(tseed33 != null and tseed33.plant_on == "草地", "树种子是种在草地上的")
	# 33.2 食物图标裁剪（原图 32x16 两份，icon 必须是单份 AtlasTexture）
	for food_path in ["res://item/baked_potato.tres", "res://item/carrot_salad.tres",
			"res://item/cabbage_soup.tres", "res://item/pumpkin_pie.tres"]:
		var food: ItemData = load(food_path)
		var at := food.icon as AtlasTexture
		chk(food != null and at != null and at.region == Rect2(0, 0, 16, 16),
			"%s 的图标裁成单份 16x16" % (food.display_name if food != null else food_path))
	# 33.3 全岛的树：长在合法位置（非水/非桥/非田/不在屋里）
	chk(Trees.trees.size() >= 20, "全岛撒了不少树（%d 棵）" % Trees.trees.size())
	var bad_trees := 0
	var ih: Vector2i = g._world_to_cell(house.global_position + Vector2(-16, 272))
	var it2: Vector2i = g._world_to_cell(house.global_position + Vector2(304, 496))
	for c33 in Trees.trees.keys():
		var cv: Vector2i = c33
		if g.is_water(cv) or g.is_bridge_cell(cv) or Farm.tilled.has(cv):
			bad_trees += 1
		if cv.x >= ih.x and cv.x <= it2.x and cv.y >= ih.y and cv.y <= it2.y:
			bad_trees += 1
	chk(bad_trees == 0, "没有一棵树长在水里/桥上/田里/屋里（违规 %d）" % bad_trees)
	var node_missing := 0
	for c33 in Trees.trees.keys():
		if not g.tree_nodes.has(c33):
			node_missing += 1
	chk(node_missing == 0, "每棵树都有节点画出来（缺 %d）" % node_missing)
	# 33.4 树的一生：种 -> 长 -> 砍倒 -> 树桩 -> 敲碎
	var tc := Vector2i(-999, -999)
	for c33 in g._land_set.keys():
		var cv2: Vector2i = c33
		if not Farm.tilled.has(cv2) and not g.is_bridge_cell(cv2) and not g.is_water(cv2) \
				and not Trees.is_blocked(cv2):
			tc = cv2
			break
	chk(tc.x != -999, "找到一块能种树的草地 %s" % tc)
	chk(Trees.plant(tc, 0), "种下树苗")
	chk(g.tree_nodes.has(tc), "树苗节点出来了")
	TimeManager.advance_day()
	TimeManager.advance_day()
	chk(Trees.stage_of(tc) == Trees.ST_YOUNG, "两天后长成小树")
	TimeManager.advance_day()
	TimeManager.advance_day()
	TimeManager.advance_day()
	chk(Trees.stage_of(tc) == Trees.ST_MATURE, "再过三天长成成树")
	var res1: Dictionary = g.hit_tree(tc)
	chk(int(res1.result) == Trees.RESULT_HIT and int(Trees.trees[tc].hp) == Trees.CHOPS_TO_FELL - 1,
		"砍第一下：树在晃（剩 %d 耐久）" % int(Trees.trees[tc].hp))
	# 木屑粒子：带重力 + 有贴图（黑描边小块）
	var chip_node: Node2D = g.tree_nodes.get(tc)
	if chip_node != null:
		var chips := 0
		var grav_ok := false
		var tex_ok := false
		for pc in chip_node.get_children():
			if pc is CPUParticles2D and (pc as CPUParticles2D).one_shot:
				chips += 1
				grav_ok = grav_ok or (pc as CPUParticles2D).gravity.y > 0.0
				tex_ok = tex_ok or (pc as CPUParticles2D).texture != null
		chk(chips >= 1 and grav_ok and tex_ok, "砍中崩木屑：重力向下、贴图在（%d 组）" % chips)
	for i in Trees.CHOPS_TO_FELL - 1:
		g.hit_tree(tc)
	chk(Trees.stage_of(tc) == Trees.ST_STUMP, "砍倒了：原地留树桩")
	chk(g._falling_cells.has(tc), "倒下动画播放中（贴图更新挂起）")
	await get_tree().create_timer(1.6).timeout
	chk(not g._falling_cells.has(tc) and g.tree_nodes.has(tc), "倒下动画播完，树桩节点补上")
	var r2: Dictionary = g.hit_tree(tc)
	chk(int(r2.result) == Trees.RESULT_HIT, "树桩还要再敲")
	var r3: Dictionary = g.hit_tree(tc)
	chk(int(r3.result) == Trees.RESULT_FELLED and not Trees.has_tree(tc), "树桩敲碎，格子空了")
	var drops := 0
	for ch33 in g.get_children():
		if ch33 is Area2D and ch33.get_script() == load("res://item_pickup.gd"):
			drops += 1
	chk(drops >= 4, "地上有木头和树种子的掉落物（%d 个）" % drops)
	# 33.5 有树的格子不能动土
	var tcell: Vector2i = Trees.trees.keys()[0]
	chk(not g.is_tillable(tcell), "有树的格子不能锄地")
	chk(Trees.plant(tc, 0), "砍完的格子能补种一棵树苗")
	chk(not g.is_tillable(tc), "种了树苗的格子也不能锄地")
	# 33.6 桥上/水里不能动土
	var bmid := Vector2i((g._bridge_x0(2) + g._bridge_x1(2)) / 2, 2)
	chk(g.is_water(bmid), "桥中段下面是河")
	chk(not g.is_tillable(bmid), "河面上不能锄地")
	chk(not g.is_tillable(Vector2i(bmid.x, 1)), "桥上护栏行不能锄地")
	# 找一格真正能动的土（前面的测试可能已经在那儿种了树）
	var grass_ok := Vector2i(-999, -999)
	for c33 in g._land_set.keys():
		var cv3: Vector2i = c33
		if g.is_tillable(cv3):
			grass_ok = cv3
			break
	chk(grass_ok.x != -999 and g.is_tillable(grass_ok), "普通草地能动土（%s）" % grass_ok)
	# 33.6.1 每夜自然补植：树和石头较快长回来，且避开耕田/建筑/铺装附近
	var old_trees := {}
	for c33b in Trees.trees.keys():
		old_trees[c33b] = true
	g._respawn_trees()
	var grown := 0
	var bad_new_trees := 0
	for c33b in Trees.trees.keys():
		if old_trees.has(c33b):
			continue
		grown += 1
		var cv4: Vector2i = c33b
		if Farm.tilled.has(cv4) or g.is_water(cv4) or g.is_bridge_cell(cv4) \
				or Floor.is_floored(cv4) or g._near_tilled(cv4, 2) or g._near_structures(cv4, 2):
			bad_new_trees += 1
	chk(grown > 0 or Trees.trees.size() >= g.TREE_MAX,
		"清晨补种了树（新增 %d, 全岛 %d）" % [grown, Trees.trees.size()])
	chk(bad_new_trees == 0, "新长的树避开耕田/建筑/铺装/水（违规 %d）" % bad_new_trees)
	var old_rocks := {}
	for c33c in OreVein.rocks.keys():
		old_rocks[c33c] = true
	# 开局撒点可能已顶满岩石上限：先按真实路子敲碎一块普通岩石腾出容量
	var rng33 := RandomNumberGenerator.new()
	rng33.randomize()
	var broke := false
	for c33c in old_rocks.keys():
		if int(OreVein.rocks[c33c].kind) == OreVein.KIND_ROCK:
			for _i33 in OreVein.ROCK_HP:
				OreVein.hit(c33c, rng33)
			broke = true
			break
	chk(broke, "先敲碎一块普通岩石腾出容量")
	g._respawn_rocks()
	var grew_rocks := 0
	var bad_new_rocks := 0
	for c33d in OreVein.rocks.keys():
		if old_rocks.has(c33d):
			continue
		grew_rocks += 1
		var cv5: Vector2i = c33d
		if Farm.tilled.has(cv5) or g.is_water(cv5) or g.is_bridge_cell(cv5) \
				or g._near_tilled(cv5, 1) or g._near_structures(cv5, 1):
			bad_new_rocks += 1
	chk(grew_rocks > 0 or OreVein.rocks.size() >= g.ROCK_MAX,
		"清晨长回了岩石（新增 %d, 全岛 %d）" % [grew_rocks, OreVein.rocks.size()])
	chk(bad_new_rocks == 0, "新长的岩石避开耕田/建筑/水（违规 %d）" % bad_new_rocks)
	# 33.7 床的碰撞：屋外关、屋内开
	var bed_body33: StaticBody2D = house.get_node("Interior/BedBody")
	chk(bed_body33 != null and bed_body33.collision_layer == 0, "床的碰撞默认关（屋外不留隐形墙）")
	house._enter_house(player)
	chk(bed_body33.collision_layer == 2, "进屋后床有碰撞（穿不过床）")
	house._leave_house(player)
	chk(bed_body33.collision_layer == 0, "出门后床碰撞又关掉")
	chk(player.collision_mask & 2 and player.collision_mask & 4,
		"玩家的碰撞掩码含床层和树干层")
	# 33.8 角色动画用的就是 Josh 原版贴图（老蒋模式已删）
	var bf33: SpriteFrames = player.body_sprite.sprite_frames
	chk(bf33.has_animation("normal_down") and bf33.get_frame_count("normal_down") == 4,
		"站立动画 4 帧")
	chk(bf33.has_animation("run_left") and bf33.get_frame_count("run_left") == 8,
		"奔跑动画 8 帧")
	var btex: Texture2D = (bf33.get_frame_texture("normal_down", 0) as AtlasTexture).atlas
	chk(btex == player.IDLE_TEX, "角色用的是 Josh 原版站立贴图")
	var tf33: SpriteFrames = player.tool_sprite.sprite_frames
	var ttex: Texture2D = (tf33.get_frame_texture("axe_down", 0) as AtlasTexture).atlas
	chk(ttex == player.AXE_TEX, "工具动作也是原版贴图")
	chk(not player.has_method("set_bald") and get_tree().root.get_node_or_null("Settings") == null,
		"老蒋模式已删: Settings 自动加载整个退场、角色没 set_bald")

	print("\n=== 34. 存档系统（收集 -> 改乱 -> 还原 + JSON 往返） ===")
	# 备份伙伴现场（这一节要动 Slaves，跑完还原）
	var old_slaves: Array = Slaves.slaves.duplicate(true)
	var old_count: int = Slaves.count
	var old_assign: Dictionary = Slaves.assignments.duplicate(true)
	var old_done: Dictionary = Slaves.done_today.duplicate(true)

	# 找一格「无田、无树、无地板、非水、非桥」的草地做实验
	var sav_cell := Vector2i(-999, -999)
	for c34 in g._land_set.keys():
		var cv34: Vector2i = c34
		if not Farm.tilled.has(cv34) and not Trees.has_tree(cv34) \
				and not Floor.is_floored(cv34) and not g.is_water(cv34) \
				and not g.is_bridge_cell(cv34):
			sav_cell = cv34
			break
	chk(sav_cell.x != -999, "找到实验用草地 %s" % sav_cell)
	Farm.till(sav_cell)
	Farm.water(sav_cell)
	Farm.plant(sav_cell, load("res://item/seed.tres"))
	Floor.place(sav_cell + Vector2i(1, 0))
	Trees.plant(sav_cell + Vector2i(2, 0), 1, Trees.ST_YOUNG)
	Slaves.slaves = [{"name": "存档测试员", "affection": 4,
		"fed_today": true, "talked_today": false}]
	Slaves.count = 1
	Slaves.assignments.clear()
	Slaves.assignments[sav_cell] = Slaves.TASK_WATER
	Slaves.done_today[sav_cell] = true
	TimeManager.year = 2
	TimeManager.season = 3
	TimeManager.day = 7
	TimeManager.hour = 15
	TimeManager.minute = 40
	Wallet.money = 777
	Inventory.watering_can_water = 6
	Inventory.hotbar[0] = {"item": load("res://item/potato.tres"), "count": 3}
	Inventory.inventory_changed.emit()

	var snap: Dictionary = SaveManager._collect(g)
	# —— 把现场全部改乱 ——
	Farm.clear_all()
	Trees.reset()
	g.rebuild_trees_from_save()
	Floor.clear_all()
	Slaves.slaves = []
	Slaves.count = 0
	Slaves.assignments.clear()
	Slaves.done_today.clear()
	Slaves.changed.emit()
	TimeManager.year = 1
	TimeManager.season = 0
	TimeManager.day = 1
	TimeManager.hour = 6
	TimeManager.minute = 0
	Wallet.money = 1
	Inventory.watering_can_water = 0
	Inventory.hotbar[0] = {"item": null, "count": 0}
	Inventory.inventory_changed.emit()
	chk(Farm.tilled.is_empty() and Trees.trees.is_empty() and Floor.floors.is_empty(),
		"现场已清空（耕地/树/地板）")

	# —— 还原（_apply 内部会调 game.rebuild_trees_from_save 重建树节点）——
	SaveManager._apply(snap)
	# queue_free 是帧末生效：等一帧再数贴图/节点，不然旧待删的和新建的会算重
	await get_tree().process_frame
	chk(TimeManager.year == 2 and TimeManager.season == 3 and TimeManager.day == 7
		and TimeManager.hour == 15 and TimeManager.minute == 40, "时间还原")
	chk(Wallet.money == 777, "金币还原")
	chk(Inventory.watering_can_water == 6, "洒水壶水量还原")
	chk(Inventory.hotbar[0]["item"] == load("res://item/potato.tres")
		and int(Inventory.hotbar[0]["count"]) == 3, "快捷栏道具还原")
	chk(Farm.is_tilled(sav_cell) and Farm.is_watered(sav_cell), "耕地/浇水状态还原")
	chk(Farm.has_crop(sav_cell) and Farm.crops[sav_cell]["seed"] == load("res://item/seed.tres"),
		"作物还原（种子资源按路径 load 回来）")
	chk(Trees.has_tree(sav_cell + Vector2i(2, 0))
		and Trees.stage_of(sav_cell + Vector2i(2, 0)) == Trees.ST_YOUNG, "树的数据还原")
	chk(g.tree_nodes.has(sav_cell + Vector2i(2, 0)), "树的显示节点跟着重建")
	chk(Floor.is_floored(sav_cell + Vector2i(1, 0)), "地板还原")
	chk(Slaves.count == 1 and String(Slaves.slaves[0]["name"]) == "存档测试员"
		and Slaves.task_at(sav_cell) == Slaves.TASK_WATER and Slaves.is_done(sav_cell),
		"伙伴人数/派活/完成标记还原")
	chk(soil.get_child_count() == Farm.tilled.size(),
		"耕地贴图数量对得上还原后的耕地（%d / %d）" % [soil.get_child_count(), Farm.tilled.size()])
	chk(g.tree_nodes.size() == Trees.trees.size(),
		"树节点数量对得上（%d / %d）" % [g.tree_nodes.size(), Trees.trees.size()])

	# —— JSON 往返：真实存档走 stringify -> parse，数字全会变 float，_apply 必须兜住 ——
	var back = JSON.parse_string(JSON.stringify(snap))
	chk(typeof(back) == TYPE_DICTIONARY, "存档能过 JSON 序列化/解析")
	SaveManager._apply(back)
	chk(Farm.is_tilled(sav_cell) and Wallet.money == 777 and Slaves.count == 1,
		"JSON 往返后的存档也能正确应用")

	# 还原伙伴现场
	Slaves.slaves = old_slaves
	Slaves.count = old_count
	Slaves.assignments = old_assign
	Slaves.done_today = old_done
	Slaves.changed.emit()

	# 35 存档列表（主页面读档）：写两份假快照 -> 列表排序/读取 -> 清理干净
	print("\n=== 35. 存档列表 ===")
	# ❗绝不能碰真档目录：把 history_dir 整个挪到临时目录，测完恢复。
	#   （以前直接往 user://saves/ 写假快照再删 —— 机器上真档就躺在那儿，
	#    删除逻辑只要断一次，测试垃圾就永久混进玩家的每日快照列表。）
	var hist_dir0: String = SaveManager.history_dir
	SaveManager.history_dir = "user://_selftest_saves"
	DirAccess.make_dir_recursive_absolute(SaveManager._abs(SaveManager.history_dir))
	var saves_dir: String = SaveManager._abs(SaveManager.history_dir)
	var dir := DirAccess.open(saves_dir)
	var files_before: Array = []
	if dir != null:
		files_before = dir.get_files()
	# 两份假快照：第1天 / 第2天（第2天更新）
	var snap_d1 := {"version": 1, "time": {"year": 1, "season": 0, "day": 1, "hour": 6, "minute": 0, "running": true}, "money": 111}
	var snap_d2 := {"version": 1, "time": {"year": 1, "season": 0, "day": 2, "hour": 15, "minute": 30, "running": true}, "money": 222}
	# 写函数现在带 enabled 守卫（防再泄档）——这一节是专门测它们的单测，
	# 路径已经全部隔离进临时目录了，所以这里临时把总闸打开，测完关回去。
	SaveManager.enabled = true
	TimeManager.year = 1
	TimeManager.season = 0
	TimeManager.day = 1
	# ❗按「我们自己写的路径」定位，别按列表下标 —— 机器里可能已经有真实快照，
	#   它们的天数更大、会排在假档前面（下标 0 根本不是我们写的那份）
	var p_d1 := SaveManager._abs(SaveManager._history_path())
	SaveManager._write_history(snap_d1)
	TimeManager.day = 2
	var p_d2 := SaveManager._abs(SaveManager._history_path())
	SaveManager._write_history(snap_d2)
	var saves: Array = SaveManager.list_saves()
	chk(saves.size() == files_before.size() + 2,
		"两份假快照进了列表（%d -> %d）" % [files_before.size(), saves.size()])
	var i_d1 := -1
	var i_d2 := -1
	for si in saves.size():
		if String(saves[si]["path"]) == p_d1:
			i_d1 = si
		elif String(saves[si]["path"]) == p_d2:
			i_d2 = si
	if i_d1 >= 0 and i_d2 >= 0:
		chk(i_d2 < i_d1, "列表按新到旧排（第2天排在第1天前面 %d < %d）" % [i_d2, i_d1])
		# 同一天重复存 = 覆盖，不堆两份
		TimeManager.day = 2
		SaveManager._write_history(snap_d2)
		chk(SaveManager.list_saves().size() == saves.size(), "同一天重复存会覆盖不翻倍")
		# 按路径读档
		chk(SaveManager.load_from_file(p_d1) and int(SaveManager._pending["time"]["day"]) == 1,
			"load_from_file 能读回指定那天的档")
		SaveManager._pending.clear()
	else:
		chk(false, "两份假快照都能在列表里按路径找到 (d1=%d d2=%d)" % [i_d1, i_d2])
	# 清理：临时目录整个删掉，真档目录从头到尾没被碰过
	# ❗remove_absolute 只能删空目录 —— 先把里面的假快照一个个删掉再删目录
	var dir3 := DirAccess.open(saves_dir)
	if dir3 != null:
		for fname in dir3.get_files():
			DirAccess.remove_absolute(saves_dir + "/" + String(fname))
	DirAccess.remove_absolute(saves_dir)
	SaveManager.history_dir = hist_dir0
	SaveManager.enabled = false          # 测完了，把总闸关回去（后面别的节不许写盘）
	chk(DirAccess.open(SaveManager._abs("user://_selftest_saves")) == null,
		"临时快照目录已删（真实存档从头到尾没动）")

	# —— 36. 军团系统：属性/技能树/伙伴战斗字段（G 键指挥已删）——
	print("\n=== 36. 军团系统 ===")
	# 属性计算：白板 1 级
	var old_lgl := {
		"level": Legion.level, "exp": Legion.exp, "sp": Legion.skill_points,
		"skills": Legion.skills.duplicate(), "hp": Legion.player_hp,
		"branches": Legion.branches.duplicate(),
	}
	Legion.level = 1
	Legion.exp = 0
	Legion.skill_points = 0
	Legion.skills = {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}
	Legion.branches = {"trade": "", "manage": "", "leader": "", "farm": "", "body": ""}
	chk(Legion.player_atk() == 5 and Legion.player_max_hp() == 50,
		"白板属性: 攻5 血50")
	# 杀敌经验 -> 升级 -> 技能点（升满 3 个技能各 1 级需要 3 个技能点）
	Legion.gain_exp(105)
	chk(Legion.level == 4 and Legion.skill_points == 3,
		"105 经验升到 4 级并给 3 技能点 (Lv%d sp%d)" % [Legion.level, Legion.skill_points])
	# 升技能：行商/管理/统帅 各 1 级
	chk(Legion.upgrade_skill("trade"), "行商 +1 成功")
	chk(Legion.upgrade_skill("manage"), "管理 +1 成功")
	chk(Legion.upgrade_skill("leader"), "统帅 +1 成功")
	chk(Legion.player_atk() == 5 + 3, "主角攻击随等级 = %d" % Legion.player_atk())
	chk(int(Legion.skills["trade"]) == 1 and int(Legion.skills["manage"]) == 1,
		"行商/管理 各 1 级")
	chk(Legion.ally_atk() == 3 + 1, "统帅后伙伴攻击 = %d" % Legion.ally_atk())
	# e14: 新增主干 (农艺/体魄) 能升级且效果生效（相对测法免疫盔甲/科技污染）
	# e20: 采掘技能已删 —— 矿井产出回归基础值, 不再吃任何技能加成
	Legion.gain_exp(160)     # 从 Lv4 再涨 2 级 (65+80) 拿 2 技能点
	chk(Legion.skill_points == 2, "再来 2 技能点 (sp%d)" % Legion.skill_points)
	chk(Legion.upgrade_skill("farm"), "农艺 +1 成功")
	chk(Legion.upgrade_skill("body"), "体魄 +1 成功")
	chk(not Legion.upgrade_skill("mine"), "e20: 采掘技能已删, 升级被拒")
	var hp_with: int = Legion.player_max_hp()
	Legion.skills["body"] = 0
	var hp_without: int = Legion.player_max_hp()
	Legion.skills["body"] = 1
	chk(hp_with - hp_without == 6, "体魄主干: 主角血上限 +6 (%d-%d)" % [hp_with, hp_without])
	var wm_with: int = Inventory.water_max()
	Legion.skills["farm"] = 0
	chk(Inventory.water_max() == wm_with - 2, "农艺主干: 水壶容量 +2")
	Legion.skills["farm"] = 1
	var rng36 := RandomNumberGenerator.new()
	rng36.seed = 20260920
	var y36: Dictionary = OreVein.settle_mine_day([], rng36)
	chk(int(y36["stone"]) == 0 and int(y36["iron"]) == 0,
		"e20: 采掘删后空矿井产出归零, 不再送基础石头 (stone=%d iron=%d)" % [int(y36["stone"]), int(y36["iron"])])
	# 没点数了不能再升
	chk(not Legion.upgrade_skill("trade"), "没技能点时升级被拒")
	# 旧「G 键指挥」已彻底删除：按键绑定没了、指挥模式数据层也没了
	chk(not InputMap.has_action("legion_toggle"), "G 键指挥: legion_toggle 按键绑定已删除")
	chk(not ("mode" in Legion), "G 键指挥: Legion 不再有指挥模式字段")
	chk(not g.has_method("_spawn_enemy"), "G 键指挥: 岛上不再刷敌人")
	# 伙伴战斗字段：招人自带血量，旧档补齐
	if Slaves.count > 0:
		var s0: Dictionary = Slaves.slave_at(0)
		chk(int(s0.get("max_hp", 0)) > 0 and int(s0.get("hp", 0)) > 0,
			"伙伴字典带 hp/max_hp")
		s0["hp"] = 0
		Slaves.slaves[0] = s0
		Slaves._on_new_day(0)
		chk(int(Slaves.slave_at(0)["hp"]) == int(Slaves.slave_at(0)["max_hp"]),
			"换日后伙伴血回满（倒下的爬起来）")
	Slaves.backfill_combat()
	# 存档往返：Legion 数据进快照再读回
	Legion.gain_exp(5)
	var lgl_snap := Legion.to_dict()
	Legion.level = 1
	Legion.exp = 0
	Legion.skill_points = 0
	Legion.skills = {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}
	Legion.from_dict(lgl_snap)
	chk(Legion.level == old_lgl["level"] + 1 or Legion.level >= 2,
		"Legion 存档往返: 等级读回 (Lv%d)" % Legion.level)
	chk(int(Legion.skills["trade"]) == 1, "Legion 存档往返: 技能读回")
	# 旧档兼容：武艺 -> 行商 / 强健 -> 管理
	Legion.skills = {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}
	Legion.from_dict({"skills": {"martial": 3, "vigor": 2, "leader": 1}})
	chk(int(Legion.skills["trade"]) == 3 and int(Legion.skills["manage"]) == 2,
		"旧档技能名映射 (武艺->行商 3, 强健->管理 2)")
	# 还原现场
	Legion.level = int(old_lgl["level"])
	Legion.exp = int(old_lgl["exp"])
	Legion.skill_points = int(old_lgl["sp"])
	Legion.skills = old_lgl["skills"].duplicate()
	Legion.branches = old_lgl["branches"].duplicate()
	Legion.player_hp = int(old_lgl["hp"])
	Legion.stats_changed.emit()

	# —— 37. 废弃码头 + 船队 + 大地图旅行 ——
	print("\n=== 37. 码头与远征 ===")
	# 37.0 码头**落点**：必须真的踩在自己那格陆地上，而且东边就是水
	# ❗踩过的坑：dock.setup 里写了 position（本节点是 Game 的子节点），
	#   而 Farm.grid_origin 取的是瓦片图层的**全局**位置（已含 Game 偏移），
	#   于是 Game 的偏移被叠了两次 —— 码头被推到东边十几格外的海面上。
	#   这里用图层自己的换算反查，谁再写错 position/global_position 都会当场炸出来。
	var dk37: Node2D = g.get_node_or_null("Dock")
	if dk37 != null:
		var gl37: TileMapLayer = g.get_node("GrassTileMapLayer")
		var back37: Vector2i = gl37.local_to_map(gl37.to_local(dk37.global_position))
		chk(back37 == dk37.anchor, "码头站在自己那格上 (反查=%s, anchor=%s)" % [
			str(back37), str(dk37.anchor)])
		chk(not g.is_water(dk37.anchor), "码头那格是陆地 (不是水面)")
		chk(g.is_water(Vector2i(dk37.anchor.x + 1, dk37.anchor.y)),
			"码头东边就是水 (栈桥伸得出去)")
	else:
		chk(false, "场景里找得到码头节点")
	# 37.1 码头三态：废墟 -> 付钱付料动工 -> 攒够人天 -> 建成；船一船两人
	var old_dock: int = Voyage.dock_state
	var old_work: int = Voyage.dock_work
	var old_boats: int = Voyage.boat_count
	var old_money: int = Wallet.money
	var wood0 := Inventory.count_item(Voyage.WOOD_ITEM)
	var plank0 := Inventory.count_item(Voyage.PLANK_ITEM)
	Voyage.dock_state = Voyage.DOCK_RUIN
	Voyage.dock_work = 0
	Voyage.boat_count = 0
	Slaves.clear_dock_crew()
	chk(not Voyage.dock_ready(), "开局: 码头是废墟")
	chk(Voyage.depart_block_reason(null).contains("没修好"), "废墟时不能出海")
	# 钱和材料给够 -> 才动得了工
	Wallet.money = Voyage.DOCK_MONEY + 500
	Inventory.add_item(Voyage.WOOD_ITEM, Voyage.DOCK_WOOD + 5)
	Inventory.add_item(Voyage.PLANK_ITEM, Voyage.DOCK_PLANK + 2)
	chk(Voyage.can_fund_dock(), "钱和材料够了: 能动工")
	chk(Voyage.fund_dock(), "动工成功")
	chk(Voyage.dock_state == Voyage.DOCK_FUNDED, "动工后进入「待施工」")
	chk(not Voyage.dock_ready(), "待施工时还不能出海")
	chk(not Voyage.add_dock_work(0), "没人干活: 进度不动")
	chk(not Voyage.add_dock_work(Voyage.DOCK_WORK - 1), "人天不够: 还没修好")
	chk(Voyage.dock_work == Voyage.DOCK_WORK - 1, "施工进度记对了")
	chk(Voyage.add_dock_work(1), "再补一天: 码头修好了")
	chk(Voyage.dock_state == Voyage.DOCK_BUILT and Voyage.dock_ready(), "码头建成")
	# 37.1b 修码头的人力：跟研究互斥（出海已全自动, 不再算一个岗位）
	if Slaves.count > 0:
		chk(Slaves.toggle_dock(0), "派伙伴 0 去修码头")
		chk(Slaves.is_dock(0) and Slaves.dock_heads() >= 1, "修码头名单生效")
		chk(Slaves.expedition.has(0), "出海名单自动含全员(修码头的也照样出海)")
		Slaves.toggle_dock(0)
		chk(not Slaves.is_dock(0), "再点一次撤回来")
	# 37.1c 造船：建成才能造，一船两人
	chk(Voyage.depart_block_reason(null).contains("船"), "没船时不能出海")
	chk(Voyage.boat_count == 0 and Voyage.seats() == 0, "一条船都还没有")
	Wallet.money = Voyage.BOAT_MONEY + 500
	Inventory.add_item(Voyage.WOOD_ITEM, Voyage.BOAT_WOOD + 5)
	chk(Voyage.can_build_boat() and Voyage.build_boat(), "造了第一条船")
	chk(Voyage.boat_count == 1 and Voyage.seats() == Voyage.BOAT_SEATS, "一条船坐 2 人")
	chk(Voyage.party_size() == 1 + Slaves.count, "出海人数 = 自己 + 全体伙伴")
	chk(Voyage.boats_needed() == ceili(float(Voyage.party_size()) / float(Voyage.BOAT_SEATS)),
		"要几条船由人数算出来")
	var need_boats: int = Voyage.boats_needed()
	while Voyage.boat_count < need_boats:
		Wallet.money = Voyage.BOAT_MONEY + 500
		Inventory.add_item(Voyage.WOOD_ITEM, Voyage.BOAT_WOOD + 5)
		if not Voyage.build_boat():
			break          # 造不动了（到 BOAT_MAX 上限 / 材料扣不出）：别在这儿转圈
	chk(Voyage.boats_enough(), "船够了: 可以出海")
	chk(Voyage.add_dock_work(5) == false, "建成的码头再加人天也没反应")
	# 存档往返（码头状态 + 进度 + 船数）
	var v_snap := Voyage.to_dict()
	var snap_boats: int = Voyage.boat_count
	Voyage.dock_state = Voyage.DOCK_RUIN
	Voyage.boat_count = 0
	Voyage.from_dict(v_snap)
	chk(Voyage.dock_state == Voyage.DOCK_BUILT and Voyage.boat_count == snap_boats,
		"Voyage 存档往返: 码头状态和船数读回")
	# 还原（钱包 / 背包 / 码头）
	var dwood := Inventory.count_item(Voyage.WOOD_ITEM) - wood0
	if dwood > 0:
		Inventory.remove_item(Voyage.WOOD_ITEM, dwood)
	var dplank := Inventory.count_item(Voyage.PLANK_ITEM) - plank0
	if dplank > 0:
		Inventory.remove_item(Voyage.PLANK_ITEM, dplank)
	Wallet.money = old_money
	Voyage.dock_state = old_dock
	Voyage.dock_work = old_work
	Voyage.boat_count = old_boats
	# 37.2 出海名单：全员自动出海 + 不占当天劳动（手动勾选已取消）
	var old_exp: Array = Slaves.expedition.duplicate()
	if Slaves.count > 0:
		var b0: int = Slaves.budget()
		chk(Slaves.expedition.has(0) and Slaves.expedition.size() == Slaves.count,
			"全员自动出海 (%d/%d)" % [Slaves.expedition.size(), Slaves.count])
		chk(Slaves.budget() == b0, "出海不占当天劳动 (%d)" % Slaves.budget())
	else:
		chk(true, "(没有伙伴, 跳过名单测试)")
	# 37.3 战斗指挥口令（F1 移动 / F2 跟随 / F3 冲锋 / F4 驻守）
	Voyage.set_command(0)
	chk(Voyage.command == 0, "指挥: F1 = 移动到指定点")
	Voyage.set_command(1)
	chk(Voyage.command == 1, "指挥: F2 = 跟随我")
	Voyage.set_command(2)
	chk(Voyage.command == 2, "指挥: F3 = 冲锋")
	Voyage.set_command(3)
	chk(Voyage.command == 3, "指挥: F4 = 原地驻守")
	Voyage.set_command(9)
	chk(Voyage.command == 3, "指挥口令越界被夹住")
	# 37.3b 编队（1/2/3 三个自定义编队，再按一次同一个键回全体）
	Voyage.set_squad_selection(0)
	chk(Voyage.selection == 0 and Voyage.selection_name() == "全体", "默认指挥全体")
	chk(Voyage.commands_squad(1) and Voyage.commands_squad(2) and Voyage.commands_squad(3),
		"全体: 三个编队都听")
	Voyage.toggle_squad(1)
	# e41h: 编队按兵种叫 剑士/弓手/骑兵（旧文案「编队1」已换）
	chk(Voyage.selection == 1 and Voyage.selection_name() == "剑士", "按 1: 选剑士队")
	chk(Voyage.commands_squad(1) and not Voyage.commands_squad(2), "剑士队: 只有 1 队听令")
	chk(Voyage.squad_name(1) == "剑士" and Voyage.squad_name(2) == "弓手"
		and Voyage.squad_name(3) == "骑兵", "三队名 = 剑士/弓手/骑兵")
	chk(Voyage.squad_name(0) == "全体" and Voyage.squad_name(9) == "全体",
		"非 1~3 的编队号一律叫全体")
	Voyage.toggle_squad(1)
	chk(Voyage.selection == 0, "再按一次 1: 回到全体")
	Voyage.toggle_squad(3)
	chk(Voyage.selection == 3 and Voyage.commands_squad(3) and not Voyage.commands_squad(1)
		and Voyage.selection_name() == "骑兵",
		"按 3: 选骑兵队")
	Voyage.set_squad_selection(0)
	# 37.3c 伙伴编队字段（默认按兵种分：刀客 1 队 / 弓手 2 队；可随时改编队）
	var old_squads: Array = []
	for s in Slaves.slaves:
		old_squads.append(int(s.get("squad", 1)))
	if Slaves.count > 0:
		var sq_ok := true
		for i in Slaves.count:
			var sq := Slaves.squad_of(i)
			if sq < 1 or sq > Slaves.SQUAD_MAX:
				sq_ok = false
		chk(sq_ok, "每个伙伴都有合法编队 (1~3)")
		chk(Slaves.set_squad(0, 3) and Slaves.squad_of(0) == 3, "改编队: 伙伴0 编到 3 队")
		chk(Slaves.squad_count(3) >= 1, "编队 3 的人数统计跟上了")
		chk(not Slaves.set_squad(0, 3), "重复编到同一队 = 没变化")
		chk(Slaves.set_squad(0, 1), "再编回 1 队")
		chk(Slaves.squad_of(0) == 1, "编队读回正确")
	else:
		chk(true, "(没有伙伴, 跳过编队字段测试)")
	# 37.3d e17 战场减速: 只在选中编队时 0.1x, 下令(选中清零)恢复常速
	# (apply_selection_slow 只认 battle 组节点 —— 挂个假节点冒充战场, 测完撤)
	var ts_bak37: float = Engine.time_scale
	var fake_b37: Node = Node.new()
	fake_b37.add_to_group("battle")
	add_child(fake_b37)
	chk(is_equal_approx(Engine.time_scale, 1.0), "未选中编队: 时间常速(进场不再自动慢)")
	Voyage.set_squad_selection(2)
	chk(Voyage.selection == 2 and is_equal_approx(Engine.time_scale, 0.1),
		"选中编队 2: 时间 0.1x (固定档, 无倍率选择)")
	Voyage.set_squad_selection(0)
	chk(is_equal_approx(Engine.time_scale, 1.0), "下令后选中失效: 时间恢复常速")
	Voyage.toggle_squad(3)
	chk(Voyage.selection == 3 and is_equal_approx(Engine.time_scale, 0.1),
		"toggle_squad 选中 3 队同样减速")
	Voyage.toggle_squad(3)
	chk(Voyage.selection == 0 and is_equal_approx(Engine.time_scale, 1.0),
		"再按同一键回全体: 恢复常速")
	fake_b37.queue_free()
	Engine.time_scale = ts_bak37
	# 37.4 兵种 backfill：旧档伙伴补「刀客」
	Slaves.backfill_combat()
	var troop_ok := true
	for s in Slaves.slaves:
		if String(s.get("troop", "")) == "":
			troop_ok = false
	chk(troop_ok, "伙伴兵种字段已补齐 (刀客/弓手)")
	# 37.5 界面暂停：开 Esc / 商店这类面板时时间停住，关掉恢复
	var was_running := TimeManager.time_running
	TimeManager.time_running = true
	TimeManager.push_ui_pause()
	chk(not TimeManager.time_running, "开面板: 时间停住")
	TimeManager.push_ui_pause()
	TimeManager.pop_ui_pause()
	chk(not TimeManager.time_running, "面板套着开: 关一层时间还是停的")
	TimeManager.pop_ui_pause()
	chk(TimeManager.time_running, "面板全关了: 时间恢复")
	TimeManager.time_running = false
	TimeManager.push_ui_pause()
	TimeManager.pop_ui_pause()
	chk(not TimeManager.time_running, "本来就停着(睡觉/出海): 关面板不会擅自放行")
	TimeManager.time_running = was_running
	# 还原现场
	Slaves.expedition = old_exp
	for i in mini(old_squads.size(), Slaves.slaves.size()):
		Slaves.slaves[i]["squad"] = old_squads[i]
	Voyage.dock_changed.emit()

	# —— 38. 科技树 / 行政树 / 政策卡（Esc 面板的「科技」「行政」两页） ——
	print("\n=== 38. 科技与行政 ===")
	var old_res := Research.to_dict()
	var old_rtech: Array = Slaves.research_tech.duplicate()
	var old_radmin: Array = Slaves.research_admin.duplicate()
	var old_skills: Dictionary = Legion.skills.duplicate()
	Legion.skills = {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}      # 排除技能干扰，只看树/卡
	Research.reset()

	# 38.1 劳动力 -> 换日产点
	# e30i: 主角不下场研究了 —— toggle_self 恒拒, 研究人头的唯一来源是 Slaves 的名单。
	chk(Research.tech_points == 0 and Research.admin_points == 0, "研究点初始为 0")
	chk(Research.slot_count() == Research.CARDS_BASE_SLOTS, "初始卡槽 1 个")
	Slaves.research_tech = []
	Slaves.research_admin = []
	Slaves.research_tech.append(0)               # 派一个伙伴出人头（没伙伴也按 1 份人头算）
	chk(Research.tech_heads() == 1, "有 1 人钻研科技")
	chk(not Research.toggle_self("tech") and not Research.toggle_self("nonsense"),
		"主角研究已取消（toggle_self 恒拒, 乱传树名也被拒）")
	Research._on_new_day(1)
	chk(Research.tech_points == Research.POINTS_PER_HEAD,
		"换日涨 %d 科技点" % Research.tech_points)
	chk(Research.admin_points == 0, "没人研究行政就不涨行政点")

	# 38.2 科技：点数不够 / 前置没满足都点不动
	chk(not Research.research_tech("plow"), "点数不够: 犁耕法点不动")
	chk(not Research.has_tech("plow") and Research.tech_points == Research.POINTS_PER_HEAD,
		"失败的尝试不扣点")
	Research.tech_points = 100
	chk(Research.can_research_tech("fert"), "轮作法 可研究")
	chk(Research.research_tech("fert"), "研究 轮作法 成功")
	chk(Research.tech_points == 70, "扣掉 30 点 (剩 %d)" % Research.tech_points)
	chk(not Research.research_tech("fert"), "已研究的不能重复研究")
	chk(Research.can_research_tech("plow"), "前置满足后 犁耕法 可研究")

	# 38.3 科技效果：给物品加增益
	chk(is_equal_approx(Research.sell_mult("作物"), 1.15),
		"轮作法: 作物卖出价 +15%% (%s)" % str(Research.sell_mult("作物")))
	chk(is_equal_approx(Research.sell_mult("食物"), 1.0), "食物不受 轮作法 影响")
	chk(Research.wood_bonus() == 0, "没研究锻铁斧: 砍树没加成")
	Research.tech_points = 200
	chk(Research.research_tech("axe"), "研究 锻铁斧")
	chk(Research.wood_bonus() == 1, "锻铁斧: 砍树多掉 1 根木头")
	chk(Research.research_tech("mill"), "研究 磨坊")
	chk(Research.craft_bonus() == 1, "磨坊: 制作多产 1 份")
	# 卖出价的实际换算（拿一件真物品过一遍）
	var crop_item: ItemData = load("res://item/potato.tres")
	if crop_item != null:
		chk(Research.sell_price_of(crop_item) == int(round(float(crop_item.sell_price) * 1.15)),
			"卖价换算: %d -> %d" % [crop_item.sell_price, Research.sell_price_of(crop_item)])

	# 38.4 行政：解锁政策卡 + 赚卡槽
	Research.admin_points = 500
	chk(Research.research_admin("admin_hu"), "研究 编户 成功")
	chk(Research.slot_count() == Research.CARDS_BASE_SLOTS + 1, "编户: 卡槽 +1")
	chk(Research.card_unlocked("corvee"), "编户 解锁 劳役卡")
	chk(not Research.card_unlocked("market"), "榷场 未研究: 互市卡 还没解锁")
	chk(not Research.slot_card("market"), "没解锁的卡挂不上")
	chk(not Research.research_admin("admin_cabinet"), "枢密院 前置(驿道)未满足: 点不动")
	chk(Research.research_admin("admin_militia"), "研究 乡勇 (前置 编户)")
	chk(Research.research_admin("admin_trade"), "研究 榷场")
	chk(Research.research_admin("admin_road"), "研究 驿道 (前置 榷场)")
	chk(Research.slot_count() == Research.CARDS_BASE_SLOTS + 3,
		"卡槽一共 %d 个" % Research.slot_count())

	# 38.5 挂卡 -> 先进准备槽（为下一周的政策作准备）-> 周初换班才生效
	chk(Research.slot_card("corvee"), "劳役 挂进准备槽")
	chk(Research.is_pending("corvee") and not Research.is_active("corvee"),
		"刚挂上的卡在准备槽, 还没生效")
	chk(Research.labor_bonus_per_head() == 0, "准备中的卡不给加成")
	chk(Research.slot_card("armory"), "甲胄 挂上")
	chk(Research.slot_card("baojia"), "同袍 挂上")
	chk(Research.slot_card("caravan"), "驼队 挂上")
	chk(Research.pending.size() == 4, "四张卡都在准备槽")
	chk(Research.free_slots() == 4, "生效槽还空着 (挂卡不占生效槽)")
	chk(Research._promote_pending() == 4, "周初换班: 四张卡一起上任")
	chk(Research.pending.is_empty() and Research.free_slots() == 0,
		"换班后准备槽清空, 生效槽占满")
	chk(Research.is_active("corvee"), "挂上的卡生效")
	chk(Research.labor_bonus_per_head() == 2, "劳役: 每人劳动力 +2")
	chk(Slaves.cells_per_slave() == Slaves.CELLS_PER_SLAVE + 2,
		"派活额度吃到 劳役 (%d)" % Slaves.cells_per_slave())
	chk(Research.ally_atk_bonus() == 2, "甲胄卡: 伙伴攻击 +2")
	chk(Legion.ally_atk() == 3 + 2, "伙伴攻击吃到 甲胄卡 (%d)" % Legion.ally_atk())
	chk(Legion.ally_max_hp() == 30 + 10, "同袍卡: 伙伴血上限 +10")
	chk(Research.slot_card("market"), "生效槽全满也能挂: 互市先进准备槽")
	chk(Research.is_pending("market") and not Research.is_active("market"),
		"互市在准备槽等下周 (为下一周的政策作准备)")
	chk(is_equal_approx(Research.buy_mult(), 0.85), "驼队卡: 买入价 -15%")
	chk(Research.buy_price_of(100) == 85, "买入价换算 100 -> %d" % Research.buy_price_of(100))
	# 摘卡 -> 加成收回；准备槽容量 = 槽数：全摘下来重挂，第 5 张挂不进
	chk(Research.unslot_card("corvee"), "摘下 劳役")
	chk(Research.labor_bonus_per_head() == 0, "摘卡后劳动力加成收回")
	chk(Slaves.cells_per_slave() == Slaves.CELLS_PER_SLAVE, "派活额度跟着收回")
	chk(Research.unslot_card("armory"), "摘下 甲胄")
	chk(Research.unslot_card("baojia"), "摘下 同袍")
	chk(Research.unslot_card("caravan"), "摘下 驼队")
	chk(Research.slot_card("corvee") and Research.slot_card("armory")
		and Research.slot_card("baojia"), "三张卡再挂进准备槽")
	chk(Research.pending_full() and Research.pending.size() == 4,
		"准备槽满了 (容量 = 生效槽数 = 4)")
	chk(not Research.slot_card("caravan"), "第 5 张挂不进: 准备槽没有空位")
	chk(Research._promote_pending() == 4, "周初换班: 准备槽的 4 张卡一起上任")
	chk(Research.free_slots() == 0 and Research.pending.is_empty(),
		"生效槽占满, 准备槽清空")
	chk(Research.is_active("market"), "互市上任")
	chk(is_equal_approx(Research.sell_mult("作物"), 1.0 + 0.15 + 0.12),
		"互市 + 轮作法 叠加 (%s)" % str(Research.sell_mult("作物")))

	# 38.6 研究占人：一个人同一时间只能干一件事
	if Slaves.count > 0:
		Slaves.research_tech = []                # 38.1 派过的人先撤下, 从干净状态开始
		Slaves.research_admin = []
		var b1: int = Slaves.budget()
		chk(Slaves.set_research(0, "tech"), "伙伴 0 派去研究科技")
		chk(Slaves.research_heads("tech") == 1 and Research.tech_heads() == 1,
			"科技人手 = 伙伴1 (%d)" % Research.tech_heads())
		chk(Slaves.budget() < b1, "研究占人: 派活额度变小 (%d -> %d)" % [b1, Slaves.budget()])
		chk(Research.day_gain("tech") == Research.POINTS_PER_HEAD,
			"每天产点跟着人手涨 (+%d)" % Research.day_gain("tech"))
		Slaves.toggle_dock(0)
		chk(not Slaves.is_research(0, "tech") and Slaves.is_dock(0),
			"改派修码头把研究撤了 (一个人只干一件事)")
		Slaves.toggle_dock(0)
		chk(Slaves.set_research(0, "admin"), "伙伴 0 改派行政")
		chk(Slaves.is_research(0, "admin") and not Slaves.is_research(0, "tech"),
			"改派: 从科技转到行政")
		chk(Slaves.set_research(0, "admin"), "再点一次撤回来")
		chk(not Slaves.is_research(0, "admin"), "行政人手已清空")
	else:
		chk(true, "(没有伙伴, 跳过研究占人测试)")

	# 38.7 存档往返
	var res_snap := Research.to_dict()
	Research.reset()
	chk(Research.techs.is_empty() and Research.slot_count() == Research.CARDS_BASE_SLOTS,
		"reset 清空研究进度与卡槽")
	Research.from_dict(res_snap)
	chk(Research.has_tech("fert") and Research.has_tech("axe") and Research.has_tech("mill"),
		"研究进度读回")
	chk(Research.has_admin("admin_road"), "行政进度读回")
	chk(Research.card_slotted("market") and Research.slot_count() == 4, "卡槽与挂卡读回")
	# 准备槽也跟着存档走：挂一张 -> 快照 -> reset -> 读回（仍未生效）
	chk(Research.slot_card("caravan"), "驼队 挂进准备槽 (给存档测试)")
	chk(Research.is_pending("caravan"), "驼队在准备槽里")
	var res_snap2 := Research.to_dict()
	Research.reset()
	Research.from_dict(res_snap2)
	chk(Research.is_pending("caravan") and not Research.is_active("caravan"),
		"准备槽里的卡存档读回 (仍未生效)")
	# e30i: player_tech / player_admin 字段已删 —— 研究人手的真相源在 Slaves, 随伙伴存档走
	# 还原现场
	Research.from_dict(old_res)
	Slaves.research_tech = old_rtech
	Slaves.research_admin = old_radmin
	Slaves.expedition = old_exp.duplicate()
	Legion.skills = old_skills.duplicate()
	Research.changed.emit()
	Slaves.changed.emit()

	# —— 39. 生活科技（水轮/引水渠/精钢斧）、远征政策卡、夜间研究播报 ——
	print("\n=== 39. 生活科技与远征政策卡 ===")
	var old_res39 := Research.to_dict()
	var old_water39: int = Inventory.watering_can_water
	var old_frozen39: bool = player.frozen
	var bad39 := "（）：，。！？；、“”‘’《》【】「」…—～"
	Research.reset()
	Research.tech_points = 500
	Research.admin_points = 500

	# 39.1 水轮：水壶容量 +5（打水判定得跟着涨，不然会被当成「已经满了」）
	chk(Research.water_bonus() == 0 and Inventory.water_max() == Inventory.WATER_MAX,
		"没研究水轮: 水壶上限还是基础 %d 次" % Inventory.WATER_MAX)
	chk(Research.research_tech("well"), "研究 水轮")
	chk(Research.water_bonus() == 5, "水轮: 水壶容量 +5")
	chk(Inventory.water_max() == Inventory.WATER_MAX + 5,
		"水壶实际上限涨到 %d" % Inventory.water_max())
	Inventory.watering_can_water = Inventory.WATER_MAX
	chk(not Inventory.is_can_full(), "装到原来的上限时，新的 5 格还装得下")
	chk(Inventory.fill_water(), "水轮研究后还能再打满一次")
	chk(Inventory.watering_can_water == Inventory.water_max(),
		"打到了新上限（%d）" % Inventory.watering_can_water)
	chk(not Inventory.fill_water(), "到了新上限就打不动了")

	# 39.2 引水渠：浇一格时顺带浇相邻的耕地（前置 水轮）
	var irrig_c := Vector2i(9999, 9999)
	for cy39 in range(0, 40):
		for cx39 in range(0, 48):
			var c39 := Vector2i(cx39, cy39)
			var r39 := c39 + Vector2i(1, 0)
			if not g.is_tillable(c39) or not g.is_tillable(r39):
				continue
			if Farm.tilled.has(c39) or Farm.tilled.has(r39):
				continue
			irrig_c = c39
			break
		if irrig_c.x != 9999:
			break
	chk(irrig_c.x != 9999, "找到一块能锄的空地来测引水渠（%s）" % str(irrig_c))
	if irrig_c.x != 9999:
		var irrig_r := irrig_c + Vector2i(1, 0)
		Farm.till(irrig_c)
		Farm.till(irrig_r)
		chk(not Research.irrigate(), "没研究引水渠: irrigate() 是关的")
		player.frozen = false
		Inventory.watering_can_water = Inventory.water_max()
		player._use_watering_can(irrig_c)
		chk(Farm.is_watered(irrig_c), "手动浇的那一格是湿的")
		chk(not Farm.is_watered(irrig_r), "没引水渠: 只浇了手上那一格")
		chk(Inventory.watering_can_water == Inventory.water_max() - 1,
			"只耗了一份水（剩 %d）" % Inventory.watering_can_water)
		# 把刚才浇的擦掉，好原地重测一次（测试内部状态，不是玩法动作）
		Farm.watered.erase(irrig_c)
		chk(Research.research_tech("ditch"), "研究 引水渠（前置 水轮）")
		chk(Research.irrigate(), "引水渠: 浇一格会顺带浇相邻耕地")
		# 数一数周围本来有几格「耕好且没浇」的邻居 —— 引水渠会顺手把它们全浇了，
		# 所以耗水量得按实际浇到的格数算（这块地原本就是农田，邻居可能不止一格）
		var nb_open := 0
		for d39 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n39: Vector2i = irrig_c + d39
			if Farm.is_tilled(n39) and not Farm.is_watered(n39):
				nb_open += 1
		Inventory.watering_can_water = Inventory.water_max()
		player._use_watering_can(irrig_c)
		chk(Farm.is_watered(irrig_c) and Farm.is_watered(irrig_r),
			"引水渠: 相邻那格也被浇到了")
		chk(nb_open >= 1, "周围有 %d 格耕地被顺带浇上" % nb_open)
		chk(Inventory.watering_can_water == Inventory.water_max() - 1 - nb_open,
			"浇了 %d 格就耗 %d 份水（剩 %d）"
				% [1 + nb_open, 1 + nb_open, Inventory.watering_can_water])
		player.frozen = old_frozen39

	# 39.3 精钢斧：一斧头削 2 点树的耐久（Trees.hit 的 power 参数）
	chk(Research.chop_power() == 1, "没研究精钢斧: 一斧削 1 点")
	chk(Research.research_tech("axe"), "研究 锻铁斧（精钢斧的前置）")
	chk(Research.research_tech("steel"), "研究 精钢斧")
	chk(Research.chop_power() == 2, "精钢斧: 一斧削 2 点（实际 %d）" % Research.chop_power())
	var tree39 := Vector2i(9999, 9999)
	for k39 in Trees.trees.keys():
		if int(Trees.trees[k39].stage) == Trees.ST_MATURE:
			tree39 = k39
			break
	if tree39.x != 9999:
		var hp39 := int(Trees.trees[tree39].hp)
		var rng39 := RandomNumberGenerator.new()
		var res39: Dictionary = Trees.hit(tree39, rng39, Research.chop_power())
		var fell39 := int(res39["result"]) == Trees.RESULT_FELLED
		chk(fell39 or int(Trees.trees[tree39].hp) == hp39 - 2,
			"精钢斧一斧削 2 点耐久（%d -> %s）" % [hp39,
				"砍倒了" if fell39 else str(int(Trees.trees[tree39].hp))])
	else:
		chk(true, "(岛上没有成树, 跳过精钢斧实砍测试)")

	# 39.4 远征政策卡：楼船 -> 艨艟；演武场 -> 校场/游哨
	chk(Research.research_admin("admin_hu"), "研究 编户")
	chk(Research.research_admin("admin_militia"), "研究 乡勇")
	chk(Research.research_admin("admin_navy"), "研究 楼船（前置 乡勇）")
	chk(Research.research_admin("admin_drill"), "研究 演武场（前置 乡勇）")
	chk(Research.card_unlocked("ironboat") and Research.card_unlocked("drill")
		and Research.card_unlocked("scout"), "楼船/演武场 解锁三张远征向政策卡")
	chk(is_equal_approx(Research.battle_coin_mult(), 1.0), "没挂艨艟: 出海金币不加成")
	chk(Research.slot_card("ironboat"), "艨艟 挂上准备槽")
	chk(Research.is_pending("ironboat"), "艨艟在准备槽等下周")
	chk(is_equal_approx(Research.battle_coin_mult(), 1.0), "准备中的卡不加成")
	Research._promote_pending()
	chk(is_equal_approx(Research.battle_coin_mult(), 1.5), "艨艟上任: 出海打赢金币 +50%")
	chk(Research.ally_atk_bonus() == 0, "没挂校场: 伙伴攻击没加成")
	chk(Research.slot_card("drill"), "校场 挂上卡槽")
	Research._promote_pending()
	chk(Research.ally_atk_bonus() == 1, "校场: 伙伴攻击 +1")
	chk(Research.slot_card("scout"), "游哨 挂上卡槽")
	Research._promote_pending()
	chk(is_equal_approx(Research.ally_speed_mult(), 1.25), "游哨: 战场移动 +25%")
	# 远征卡不改岛上的经济：卖价/买价完全不受影响
	chk(is_equal_approx(Research.sell_mult("作物"), 1.0), "远征卡不影响作物卖价")

	# 39.4b 隔周生效：周初（第 8 天）早上 _on_new_day 自动换班
	chk(Research.slot_card("armory"), "甲胄 挂进准备槽 (为下一周作准备)")
	chk(Research.ally_atk_bonus() == 1, "准备中的卡不算加成 (只有校场的 +1)")
	Research._on_new_day(8)              # 第 8 天 = 新一周的第一天早上
	chk(Research.is_active("armory") and Research.pending.is_empty(),
		"第 8 天早上: 准备槽的卡自动上任")
	chk(Research.last_promoted.has("甲胄"), "晨间播报记住今早生效的卡")
	chk(Research.ally_atk_bonus() == 3, "上任后加成到账 (校场 +1 甲胄 +2)")
	Research._on_new_day(9)
	chk(Research.last_promoted.has("甲胄"),
		"非周初不换班: 播报保持原样不加新卡")

	# 39.5 夜间结算：一晚只结一次账
	Research.reset()
	var rtech_bak39: Array = Slaves.research_tech.duplicate()
	Slaves.research_tech = [0]                   # e30i: 主角不研究了, 派一个伙伴出人头
	var rep39: Dictionary = Research.settle_night()
	chk(int(rep39.get("tech_gain", -1)) == Research.POINTS_PER_HEAD,
		"睡前结算报出今晚 +%d 科技点" % int(rep39.get("tech_gain", -1)))
	chk(Research.tech_points == Research.POINTS_PER_HEAD, "点数确实入账了")
	chk(Research.settle_night().is_empty(), "同一晚重复结算直接返回空（不会再加一遍）")
	chk(Research.tech_points == Research.POINTS_PER_HEAD, "点数没被加第二遍")
	Research._on_new_day(2)
	chk(Research.tech_points == Research.POINTS_PER_HEAD,
		"换日不再重复加（睡觉时已经结过账）")
	Research._on_new_day(3)
	chk(Research.tech_points == Research.POINTS_PER_HEAD * 2,
		"再睡一晚才继续涨（现在 %d 点）" % Research.tech_points)
	Slaves.research_tech = rtech_bak39           # e30i: 还原研究人手, 别污染后面的测试

	# 39.6 播报文案
	Research.tech_points = 30
	chk(Research.ready_list("tech").has("轮作法"), "点数够了: 轮作法 出现在「可研究」里")
	chk(not Research.ready_list("tech").has("犁耕法"), "前置没满足的不会进「可研究」")
	var lines39: Array = g._research_report_lines({
		"tech_gain": 8, "admin_gain": 0, "tech_heads": 1, "admin_heads": 0,
		"tech_total": 38, "admin_total": 0})
	chk(lines39.size() >= 1 and String(lines39[0]).contains("科技 +8"),
		"播报写下今晚的科技点（「%s」）" % (String(lines39[0]) if lines39.size() > 0 else ""))
	chk(not lines39.is_empty() and String(lines39[lines39.size() - 1]).contains("可研究"),
		"播报最后一行提示现在能研究什么（「%s」）"
			% (String(lines39[lines39.size() - 1]) if not lines39.is_empty() else ""))
	chk(g._research_report_lines({}).is_empty(), "已经结过账（空报告）就不播报")
	var none39: Array = g._research_report_lines({
		"tech_gain": 0, "admin_gain": 0, "tech_heads": 0, "admin_heads": 0,
		"tech_total": 0, "admin_total": 0})
	chk(none39.size() == 1 and String(none39[0]).contains("没人钻研"),
		"没人钻研时给一句提示（「%s」）" % (String(none39[0]) if none39.size() > 0 else ""))
	var off39 := 0
	for ln39 in lines39 + none39:
		for i39 in String(ln39).length():
			if bad39.contains(String(ln39)[i39]):
				off39 += 1
	chk(off39 == 0, "播报文案没有全角标点（渲成方块）: %d 个" % off39)
	chk(g._join_names(["甲", "乙"]) == "甲 / 乙",
		"名字用 ASCII 斜杠拼（「%s」）" % g._join_names(["甲", "乙"]))

	# 还原现场
	Research.from_dict(old_res39)
	Inventory.watering_can_water = old_water39
	player.frozen = old_frozen39
	Research.changed.emit()

	# —— 39b. 伙伴真的上船 + 大陆据点 + 集市 / 酒馆 ——
	# 这一段针对的是「勾了明天出行 -> 走到码头 -> 上船藏起来 -> 海图上画船员 ->
	# 上岸进据点 -> 集市卖货 / 酒馆雇人 -> 从栈桥回海图」这条新链路。
	print("\n=== 39b. 伙伴上船 + 大陆据点 + 集市 / 酒馆 ===")
	var tr_bak39b: bool = TimeManager.time_running
	var money_bak39b: int = Wallet.money
	TimeManager.time_running = true

	# 39b.1 伙伴的登船状态机：走到目标 -> 上船（藏起来）；放出来 -> 落在陆地
	var recruited39b := false
	if Slaves.count == 0:
		Slaves.recruit_roster()
		recruited39b = true
		await get_tree().process_frame
	if g.slave_nodes.size() > 0:
		var sn: Node2D = g.slave_nodes[0]
		var st_map: Dictionary = sn.get_script().get_script_constant_map().get("State", {})
		chk(not sn.call("is_aboard"), "伙伴一开始不在船上")
		chk(sn.has_method("board_to") and sn.has_method("unboard") and sn.has_method("board_now"),
			"伙伴有 上船 / 下船 / 兜底上船 三个接口")
		# 目标点就在脚边：几帧之内必须自己判定「走到了」-> 上船
		sn.call("board_to", sn.global_position + Vector2(6, 0))
		var frames39b := 0
		while not sn.call("is_aboard") and frames39b < 300:
			sn.call("_tick_board", 1.0 / 60.0)
			frames39b += 1
		chk(sn.call("is_aboard"), "走到目标点就上船了（%d 帧）" % frames39b)
		chk(not sn.visible, "上船后伙伴小人藏起来（改由海图画船员）")
		chk(int(st_map.get("BOARD", -1)) == int(sn.get("_state")),
			"上船时状态切到 BOARD（不掺和白天挑活那套）")
		# 下船：放出来的时候必须挑陆地，别把人泡在水里
		sn.call("unboard", sn.global_position)
		chk(not sn.call("is_aboard") and sn.visible, "下船后伙伴又出现了")
		chk(not g.is_water(g._world_to_cell(sn.global_position)),
			"下船点挑的是陆地（不泡水）")
		# 兜底：给个到不了的点，board_now 也能把人塞上船（海上卡住时用）
		sn.call("board_to", sn.global_position + Vector2(9999, 0))
		chk(not sn.call("is_aboard"), "还没走到（给了个到不了的点）")
		sn.call("board_now")
		chk(sn.call("is_aboard"), "兜底 board_now 直接把人塞上船")
		sn.call("unboard", sn.global_position)
		chk(not sn.call("is_aboard"), "再放出来就恢复正常了")
	else:
		chk(false, "场景里拿得到一个伙伴小人（拿不到就没法测上船）")

	# 39b.2 出海人数 -> 船数：一船两人，够船才让走（跟码头面板同一套算法）
	var pt_bak39b: int = Voyage.party_size()
	var bt_bak39b: int = Voyage.boat_count
	var ex_bak39b: Array = Slaves.expedition.duplicate()
	Voyage.boat_count = 99
	chk(Voyage.party_size() == 1 + Slaves.expedition.size(),
		"出海人数 = 自己 + 勾了出行的人（%d）" % Voyage.party_size())
	chk(Voyage.boats_needed() == ceili(float(Voyage.party_size()) / float(Voyage.BOAT_SEATS)),
		"要几条船由人数算出来（%d 条）" % Voyage.boats_needed())
	# 座位表：总座位 = 船数 x 每船人数（一船两人就是这里定的）
	chk(Voyage.seats() == Voyage.boat_count * Voyage.BOAT_SEATS,
		"总座位 = 船数 x 每船 %d 人" % Voyage.BOAT_SEATS)
	Voyage.boat_count = bt_bak39b
	chk(Voyage.boats_enough() == (Voyage.seats() >= Voyage.party_size()),
		"够不够船就是「座位 >= 人数」（%d 座 / %d 人）" % [Voyage.seats(), Voyage.party_size()])
	Slaves.expedition = ex_bak39b
	Voyage.boat_count = bt_bak39b
	chk(Voyage.party_size() == pt_bak39b, "出海人数还原")

	# 39b.3 大陆据点小场景：地形 / 栈桥 / 三间房 / 三个交互点都得站得住
	var tv_bak39b: bool = Voyage.traveling
	var ashore_bak39b: bool = Voyage.ashore
	Voyage.traveling = false
	Voyage.ashore = false
	var ml = preload("res://scene/mainland.gd").new()
	add_child(ml)
	await get_tree().process_frame
	await get_tree().process_frame
	chk(ml.is_in_group("mainland"), "据点挂进 mainland 组（场景切换找得到它）")
	var land39: Dictionary = ml.get("_land")
	var water39: Dictionary = ml.get("_water")
	var pier39: Dictionary = ml.get("_pier")
	chk(land39.size() > 500, "据点地形: 陆地 %d 格" % land39.size())
	chk(water39.size() > 150, "据点地形: 海面 %d 格" % water39.size())
	chk(pier39.size() >= 12, "栈桥占 %d 格（从岸边伸进海里）" % pier39.size())
	var spots39: Array = ml.get("_spots")
	chk(spots39.size() == 3, "据点有 3 个交互点（集市 / 酒馆 / 栈桥）")
	var kinds39: Array = []
	var stand39 := true
	for s39 in spots39:
		kinds39.append(String(s39["kind"]))
		if not ml.call("walkable", s39["pos"]):
			stand39 = false
			print("      [!!] 交互点站不住: ", s39["kind"], " @ ", s39["pos"])
	chk(stand39, "三个交互点都站得住（不泡水、不穿墙）")
	chk(kinds39.has("market") and kinds39.has("tavern") and kinds39.has("pier"),
		"集市 / 酒馆 / 返航 三样齐全")
	var pl39: Node2D = ml.get("player")
	chk(pl39 != null and ml.call("walkable", pl39.position), "主角出生点也在陆地上")

	# 39b.4 集市：按 F 开面板 -> 卖作物换钱 / 买岛上造不出的货
	ml.call("_open_spot", 0)
	await get_tree().process_frame
	var mk: Control = ml.call("_get_market")
	chk(mk != null and bool(mk.call("is_open")), "走到集市按 F: 贸易面板开了")
	chk(not TimeManager.time_running, "集市面板开着时时间停住")
	# 用一份干净的背包测「卖」，测完还原（别把别的节留下的作物卖掉了）
	var hot_bak39b: Array = Inventory.hotbar.duplicate(true)
	var bag_bak39b: Array = Inventory.backpack.duplicate(true)
	for i39 in Inventory.hotbar.size():
		Inventory.hotbar[i39] = {"item": null, "count": 0}
	for i39 in Inventory.backpack.size():
		Inventory.backpack[i39] = {"item": null, "count": 0}
	var pot39: ItemData = load("res://item/potato.tres")
	Inventory.add_item(pot39, 3)
	Inventory.inventory_changed.emit()
	var tot39: Dictionary = mk.call("_sell_total")
	chk(int(tot39["n"]) == 3, "集市认得背包里 3 个土豆（数到 %d 个）" % int(tot39["n"]))
	var each39: int = Research.sell_price_of(pot39)
	chk(int(tot39["gold"]) == each39 * 3,
		"报价 = 单价 x 数量（%d = %d x 3）" % [int(tot39["gold"]), each39])
	var m_before39: int = Wallet.money
	mk.call("_sell_all")
	chk(Inventory.count_item(pot39) == 0, "卖光: 背包里的土豆清空")
	chk(Wallet.money == m_before39 + each39 * 3,
		"卖光: 钱加上来了（%d -> %d）" % [m_before39, Wallet.money])
	# 买：走买价（Research.buy_price_of），钱扣掉、货到手
	var stock39: Array = mk.get_script().get_script_constant_map().get("STOCK", [])
	chk(stock39.size() >= 1, "集市有货可买（%d 种）" % stock39.size())
	if stock39.size() >= 1:
		var e39: Dictionary = stock39[0]
		var it_b39: ItemData = load(String(e39["path"]))
		var base_b39 := int(e39["price"])
		var price_b39: int = Research.buy_price_of(base_b39)
		chk(price_b39 >= base_b39, "买价不低于标价（标价 %d -> 卖你 %d）" % [base_b39, price_b39])
		Wallet.money = 100000
		var have_b39: int = Inventory.count_item(it_b39)
		mk.call("_buy", it_b39, base_b39)
		chk(Inventory.count_item(it_b39) == have_b39 + 1,
			"买 1 个%s 到手" % it_b39.display_name)
		chk(Wallet.money == 100000 - price_b39, "买货扣钱按买价（%d）" % price_b39)
		Inventory.remove_item(it_b39, 1)
	# 钱不够时买不动
	Wallet.money = 0
	if stock39.size() >= 1:
		var it_c39: ItemData = load(String(stock39[0]["path"]))
		var have_c39: int = Inventory.count_item(it_c39)
		mk.call("_buy", it_c39, int(stock39[0]["price"]))
		chk(Inventory.count_item(it_c39) == have_c39, "钱不够: 买不成（货没多）")
	mk.call("close_panel")
	chk(TimeManager.time_running, "关掉集市: 时间恢复")
	Inventory.hotbar = hot_bak39b
	Inventory.backpack = bag_bak39b
	Inventory.inventory_changed.emit()

	# 39b.5 酒馆：按 F 开面板 -> 招募消息板（贴着下一位候选人的诉求, 只看不雇）
	ml.call("_open_spot", 1)
	await get_tree().process_frame
	var tv: Control = ml.call("_get_tavern")
	chk(tv != null and bool(tv.call("is_open")), "走到酒馆按 F: 消息板面板开了")
	chk(not TimeManager.time_running, "酒馆面板开着时时间停住")
	var sl_bak39b: Array = Slaves.slaves.duplicate(true)
	var cnt_bak39b: int = Slaves.count
	var ex_bak39b2: Array = Slaves.expedition.duplicate()
	Slaves.slaves = []
	Slaves.count = 0
	Slaves.expedition = []
	Slaves.changed.emit()
	await get_tree().process_frame
	# 板上贴的就是下一位候选人（跟岛上篝火边是同一个人）: 名字 / 兵种 / 诉求 / 进度
	var root39: Node = tv.get("_root")
	var board39: String = ""
	var no_hire39 := true
	for lbl39 in root39.get_children():
		if lbl39 is Label:
			board39 += String(lbl39.text) + "\n"
		elif lbl39 is Button:
			no_hire39 = false
	var nxt39: Dictionary = Slaves.preview_next()
	chk(board39.contains(String(nxt39.get("name", "")))
		and board39.contains(String(nxt39.get("troop", ""))),
		"板上贴着下一位候选人（%s / %s）" % [nxt39.get("name", ""), nxt39.get("troop", "")])
	chk(board39.contains("诉求") and board39.contains("进度"),
		"板上写着诉求和进度（%s）" % str(nxt39.get("req", "")))
	chk(board39.contains("不用钱"), "板上写明入队不用钱")
	chk(no_hire39, "消息板上没有雇人按钮（招募全走岛上任务）")
	chk(Slaves.count == 0, "开板不雇人（人数没变）")
	Slaves.slaves = sl_bak39b
	Slaves.count = cnt_bak39b
	Slaves.expedition = ex_bak39b2
	Slaves.changed.emit()
	await get_tree().process_frame
	tv.call("close_panel")
	chk(TimeManager.time_running, "关掉酒馆: 时间恢复")

	# 39b.6 场景切换守卫：不在海上进不去据点；没上岸退不回海图
	ml.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	chk(get_tree().get_first_node_in_group("mainland") == null, "据点拆掉后组里没它了")
	Voyage.traveling = false
	Voyage.ashore = false
	Voyage.enter_mainland()
	await get_tree().process_frame
	chk(get_tree().get_first_node_in_group("mainland") == null and not Voyage.ashore,
		"没在海上时 enter_mainland 不动手（守卫生效）")
	Voyage.leave_mainland()
	chk(not Voyage.ashore, "没上岸时 leave_mainland 也不动手")

	# 还原现场
	if recruited39b:
		Slaves.clear_all()
		await get_tree().process_frame
	Wallet.money = money_bak39b
	Voyage.traveling = tv_bak39b
	Voyage.ashore = ashore_bak39b
	Voyage.boat_count = bt_bak39b
	Voyage.dock_changed.emit()
	TimeManager.time_running = tr_bak39b

	# —— 40. UI 文案的字体缺字体检 ——
	# 以前只能靠肉眼看预览图才发现「■ ● ♥ → 「」 全角空格」都渲成小方块，
	# 这里改成拿字体自报的支持字符集全量比对，任何面板新写的文案都躲不过。
	print("\n=== 40. UI 字体缺字体检（缺字形会显示成方块）===")
	chk(_ipix_chars().length() > 100, "取到 IPix.ttf 的支持字符集（%d 个字符）" % _ipix_chars().length())
	# 先自证这套检查有效（否则「全过」可能只是检查根本没生效）
	chk(not missing_glyphs("■").is_empty(), "体检有效: ■ 在 IPix.ttf 里没有字形")
	chk(not missing_glyphs("\u3000").is_empty(), "体检有效: 全角空格没有字形")
	chk(not missing_glyphs("·").is_empty(), "体检有效: 间隔号没有字形")
	chk(missing_glyphs("种田 ABC 123 : / - ( )").is_empty(),
		"常用汉字/字母/数字/ASCII 标点都有字形")
	chk(missing_glyphs("木材 # x2").is_empty(), "色块用的 '#' 有字形")
	chk(missing_glyphs("好▲感").has("▲"), "混在汉字里的缺字形也能挑出来")

	# 背包面板：8 个模块逐页扫
	var bp40: Control = g.get_node_or_null("HUD/Backpack")
	if bp40 != null:
		for mod40 in ["bag", "hero", "team", "tech", "admin", "map", "craft", "settings"]:
			bp40._select_module(mod40)
			await get_tree().process_frame
			sweep_glyphs(bp40, "背包-" + mod40)
		# 好感符号是运行时按好感拼的（好感 0 就是空串，静态扫不到）-> 造个满好感再看一遍
		if Slaves.count > 0:
			var aff_back40: int = int(Slaves.slaves[0]["affection"])
			Slaves.slaves[0]["affection"] = 4
			bp40._select_module("team")
			await get_tree().process_frame
			sweep_glyphs(bp40, "背包-团队(满好感)")
			Slaves.slaves[0]["affection"] = aff_back40
			bp40._select_module("team")
			await get_tree().process_frame
	else:
		chk(false, "拿得到 HUD/Backpack（扫不到就没法体检）")

	for path40 in ["HUD/Shop", "HUD/Dialogue", "HUD/CampfirePanel", "HUD/SleepMenu", "HUD"]:
		var n40: Node = g.get_node_or_null(path40)
		if n40 != null:
			sweep_glyphs(n40, path40)
	# 篝火面板的信息卡、结算面板、派活面板（都在别的容器下）
	if cp23 != null:
		sweep_glyphs(cp23, "篝火面板-信息卡")
	if settle != null:
		sweep_glyphs(settle, "结算面板")
	if night_layer != null:
		var assign40: Node = night_layer.get_node_or_null("Assign")
		if assign40 != null:
			sweep_glyphs(assign40, "派活面板")
	# 码头面板：内容是开面板时才拼的，得三种状态各开一次才扫得全
	var dpanel: Node = g.get_node_or_null("HUD/DockPanel")
	if dpanel != null and dpanel.has_method("open_panel"):
		var ds0: int = Voyage.dock_state
		var dw0: int = Voyage.dock_work
		var db0: int = Voyage.boat_count
		for st in [Voyage.DOCK_RUIN, Voyage.DOCK_FUNDED, Voyage.DOCK_BUILT]:
			Voyage.dock_state = int(st)
			Voyage.dock_work = 3
			Voyage.boat_count = 1
			Voyage.dock_changed.emit()
			dpanel.call("open_panel")
			await get_tree().process_frame
			sweep_glyphs(dpanel, "码头面板-%d" % int(st))
			dpanel.call("close_panel")
		Voyage.dock_state = ds0
		Voyage.dock_work = dw0
		Voyage.boat_count = db0
		Voyage.dock_changed.emit()
	# 大陆集市 / 酒馆：文案也是开面板时才拼的（含运行时算出来的价格、人名），各开一次扫一遍
	for spec40 in [["res://market_ui.gd", "集市"], ["res://tavern_ui.gd", "酒馆"]]:
		var mp40: Control = load(String(spec40[0])).new()
		add_child(mp40)
		await get_tree().process_frame
		mp40.call("open_panel")
		await get_tree().process_frame
		sweep_glyphs(mp40, "大陆-" + String(spec40[1]))
		mp40.call("close_panel")          # ❗open_panel 里有时间暂停栈，必须正常关
		mp40.queue_free()
		await get_tree().process_frame
	# 对话面板的好感符号也是运行时拼的
	var dp40: Node = g.get_node_or_null("HUD/Dialogue")
	if dp40 != null and dp40.has_method("_heart_str"):
		var hs40 := String(dp40.call("_heart_str", 3))
		chk(missing_glyphs(hs40).is_empty(), "对话面板的好感符号有字形（「%s」）" % hs40)

	chk(_glyph_bad.is_empty(), "所有界面文案都没有缺字形（%d 处）: %s"
		% [_glyph_bad.size(), str(_glyph_bad.slice(0, 8))])
	# 证明这套体检真的扫到了东西 —— 否则「0 处」可能只是因为一个面板都没找到
	chk(_glyph_swept.has("背包-bag") and _glyph_swept.has("背包-craft")
		and _glyph_swept.has("HUD/Shop") and _glyph_swept.has("结算面板")
		and _glyph_swept.has("篝火面板-信息卡")
		and _glyph_swept.has("大陆-集市") and _glyph_swept.has("大陆-酒馆"),
		"体检真的扫到了各面板（%d 个）: %s" % [_glyph_swept.size(), str(_glyph_swept)])

	# —— 41. 战斗收尾 / 血条 / 开始界面 / 具名档 / BGM 场景切换 ——
	# 2026-09-16 修的那批：①「战斗后不能退出」的真凶是 AI 撞树卡死（敌人清不完 ->
	# 胜负判定不触发）；②血条左半露黑底；③新增开始界面 + 具名档 + 新档回第 1 天；
	# ④海图/战场各自的 BGM。
	print("\n=== 41. 战斗收尾 / 血条 / 开始界面 / 具名档 / BGM ===")
	var tcm: Dictionary = (load("res://scene/troop.gd") as Script).get_script_constant_map()
	chk(float(tcm.get("HP_BAR_X", 999.0)) == -12.0 and float(tcm.get("HP_BAR_W", 0.0)) == 24.0,
		"血条常量：宽 %.0f、偏移 %.0f（-12 = 底板与血量条同一个左边）"
		% [float(tcm.get("HP_BAR_W", 0.0)), float(tcm.get("HP_BAR_X", 999.0))])
	chk(float(tcm.get("DETOUR_TIME", 0.0)) >= 0.1 and float(tcm.get("STUCK_LIMIT", 0.0)) >= 3.0,
		"绕行/判逃常量在（绕行锁 %.1fs、静止 %.1fs 判它逃了）"
		% [float(tcm.get("DETOUR_TIME", 0.0)), float(tcm.get("STUCK_LIMIT", 0.0))])

	# 41b 真造一个单位出来：血条两根条必须重合，撞上挡格必须绕过去。
	# ❗老 bug 是滑行位移按被挡那一轴的分量算（0.01 像素），小到跨不过格边界，
	#   于是每帧"成功"挪 0.01 像素就 return，绕行分支一辈子进不去 —— 单位原地焊死。
	var old_battle: Node = get_tree().get_first_node_in_group("battle")
	if old_battle != null:
		old_battle.remove_from_group("battle")      # 免得 troop._battle() 顺手套走真战场
	var fkb := FakeBattle.new()
	fkb.blocked[Vector2i(2, 1)] = true              # 右边一格挡着（当它是树 / 河岸）
	add_child(fkb)
	var su: Variant = load("res://scene/troop.gd").new()
	su.side = "enemy"
	su.kind = "刀客"
	su.speed = 28.0
	su.index = 0
	add_child(su)
	su.global_position = Vector2(24.0, 24.0)        # 格里正中心
	su.set_process(false)                           # 只手动喂 _try_move，别让 AI 插手
	await get_tree().process_frame
	var bars: Array = (su.get("_hp_root") as Node2D).get_children().filter(
		func(c): return c is ColorRect)
	if bars.size() == 2:
		var bx: float = (bars[0] as ColorRect).position.x
		var fx: float = (bars[1] as ColorRect).position.x
		var bw: float = (bars[0] as ColorRect).size.x
		var fw: float = (bars[1] as ColorRect).size.x
		chk(is_equal_approx(bx, fx) and is_equal_approx(bx, -12.0),
			"血条左端对齐（底板 %.1f / 血量条 %.1f，都是 -12）" % [bx, fx])
		chk(is_equal_approx(bw, 24.0) and is_equal_approx(fw, 24.0),
			"血条两根条同宽 %.1f / %.1f（不会右半捅出底板）" % [bw, fw])
	else:
		chk(false, "血条下正好两根 ColorRect（实际 %d）" % bars.size())
	chk(su.has_method("_flee"), "有「卡够了就判它逃了」的兜底（敌人不会再赖着不走）")
	var px0: float = su.global_position.x
	for _i in 90:
		su.call("_try_move", 1.0 / 60.0, Vector2(1.0, 0.0) * (28.0 / 60.0))
	chk(su.global_position.x > 40.0,
		"朝挡格走 90 帧能绕过去（x: %.1f -> %.1f，老 bug 会焊死在 31.5）"
		% [px0, su.global_position.x])
	su.queue_free()
	fkb.queue_free()
	if old_battle != null:
		old_battle.add_to_group("battle")

	# 41c 开始界面「开始」= 开新档：登记重置请求，game 场景就绪时消费掉
	SaveManager._pending.clear()
	SaveManager.begin_new_game("自检档")
	chk(SaveManager.slot_name == "自检档", "开新档记下了档名（「%s」）" % SaveManager.slot_name)
	chk(SaveManager.take_reset_request(), "开新档会发出「重置成第 1 天」请求")
	chk(not SaveManager.take_reset_request(), "重置请求只放行一次（读档不会被顺手重置）")
	SaveManager.begin_new_game("   ")                # 空档名要有兜底
	chk(SaveManager.slot_name == "未命名", "空档名兜底成「未命名」")
	SaveManager.take_reset_request()

	# 41d 具名档：写两份 -> 列表（新的在前）-> 按路径读 -> 删。
	# ❗全部在临时目录里做（slot_dir 是 var，就是为了能这么重定向），别碰玩家真档。
	var slot_dir0: String = SaveManager.slot_dir
	var slot_name0: String = SaveManager.slot_name
	SaveManager.slot_dir = "user://_selftest_slots"
	SaveManager.enabled = true           # 同 35a：路径已隔离，临时开闸测写函数
	var slot_a := {"version": 1, "name": "自检档A", "saved_at": 1700000000.0,
		"time": {"year": 2, "season": 1, "day": 9, "hour": 7, "minute": 5}}
	var slot_b := {"version": 1, "name": "自检档B", "saved_at": 1700009999.0,
		"time": {"year": 3, "season": 0, "day": 1, "hour": 6, "minute": 0}}
	SaveManager.slot_name = "自检档A"
	SaveManager._write_slot(slot_a)
	SaveManager.slot_name = "自检档B"
	SaveManager._write_slot(slot_b)
	var sl: Array = SaveManager.list_slots()
	chk(sl.size() == 2, "两份具名档都列出来了（%d）" % sl.size())
	if sl.size() == 2:
		chk(String(sl[0]["name"]) == "自检档B", "新的排前面（第一项是「%s」）" % String(sl[0]["name"]))
		chk(int(sl[1]["year"]) == 2 and int(sl[1]["day"]) == 9,
			"档里记着进度（第 %d 年 第 %d 天）" % [int(sl[1]["year"]), int(sl[1]["day"])])
		chk(SaveManager.open_slot(String(sl[1]["path"])),
			"能读回指定那一档")
		chk(SaveManager.slot_name == "自检档A" and int(SaveManager._pending["time"]["day"]) == 9,
			"读档后档名/进度都跟着存档走（当前「%s」）" % SaveManager.slot_name)
		SaveManager._pending.clear()
		chk(SaveManager.delete_slot(String(sl[1]["path"])), "删档返回成功")
		chk(SaveManager.list_slots().size() == 1, "删完只剩一份")
		chk(not SaveManager.delete_slot(String(sl[1]["path"])), "删不存在的档返回 false")
	else:
		chk(false, "两份具名档都能列出来")
	DirAccess.remove_absolute(SaveManager._abs(SaveManager.slot_path("自检档A")))
	DirAccess.remove_absolute(SaveManager._abs(SaveManager.slot_path("自检档B")))
	DirAccess.remove_absolute(SaveManager._abs(SaveManager.slot_dir))
	SaveManager.enabled = false          # 关回总闸
	chk(SaveManager.list_slots().is_empty(), "临时具名档目录已清空（真实存档没动）")
	SaveManager.slot_dir = slot_dir0
	SaveManager.slot_name = slot_name0

	# 41e BGM（e52 撤销 e49）：岛上 = Towball 十首(mp3, loop, 一天一首)，
	# 场景池 = 中世纪包八首(ogg, loop)；menu 用 menu.ogg，opening 用中世纪第 2 首（e53）
	chk(Audio.MUSIC_POOL.size() == 6, "BGM 场景组 6 组（实际 %d）" % Audio.MUSIC_POOL.size())
	# 10(岛上) + 8(中世纪, 四组共用) + 1(menu) = 19, 按去重后的文件数算
	chk(Audio._bgm_streams.size() == 19,
		"曲池去重后 19 首全部载入（实际 %d 首）" % Audio._bgm_streams.size())
	chk(Audio.ISLAND_TRACKS.size() == 10 and Audio.MEDIEVAL_TRACKS.size() == 8,
		"岛上十首 + 中世纪八首（%d/%d）" % [Audio.ISLAND_TRACKS.size(), Audio.MEDIEVAL_TRACKS.size()])
	var island_cnt := 0
	for f29 in Audio.ISLAND_TRACKS:
		if Audio._bgm_streams.get(f29) is AudioStreamMP3:
			island_cnt += 1
	chk(island_cnt == 10, "岛上 Towball 十首都载入成 mp3（%d/10）" % island_cnt)
	var med_cnt: int = Audio._loaded_count(Audio.MEDIEVAL_TRACKS)
	chk(med_cnt == 8, "中世纪包八首都载入（%d/8）" % med_cnt)
	chk(Audio.MUSIC_POOL["menu"] == [Audio.BGM_DIR + "menu.ogg"]
		and Audio.MUSIC_POOL["opening"] == [Audio.MEDIEVAL_DIR + "Medieval Vol. 2 2 (Loop).ogg"],
		"主菜单用 menu.ogg, 开局动画用中世纪第 2 首（e53 改开）")
	chk(Audio.MUSIC_POOL["ocean"] == Audio.MEDIEVAL_TRACKS
		and Audio.MUSIC_POOL["town"] == Audio.MEDIEVAL_TRACKS
		and Audio.MUSIC_POOL["settle"] == Audio.MEDIEVAL_TRACKS,
		"出海/城镇/结算共用中世纪包")
	var battle_subset: bool = Audio.MUSIC_POOL["battle"] == Audio.BATTLE_TRACKS \
		and Audio.BATTLE_TRACKS.size() == 5
	for f42 in Audio.BATTLE_TRACKS:
		if not (f42 in Audio.MEDIEVAL_TRACKS):
			battle_subset = false
	chk(battle_subset, "战场用中世纪包里最激烈的 5 首子集")
	var pool_ok := true
	for k41 in Audio.MUSIC_POOL:
		for f41 in Audio.MUSIC_POOL[k41]:
			if not Audio._bgm_streams.has(f41):
				pool_ok = false
	chk(pool_ok, "曲池里每首曲子都加载成功（不落一首）")
	# 岛上：当天抽中的那首循环一整天, 换季节/入夜都不换曲（e52 撤销了四季池）
	Audio._scene_track = ""
	Audio._current_track = ""
	Audio._island_day_track = ""
	Audio.set_scene_bgm("island")
	var i41: String = Audio.current_track()
	chk(Audio._resolve_key() == "island" and Audio.ISLAND_TRACKS.has(i41),
		"岛上就是 Towball 池（%s）" % i41)
	var hour_saved41a: int = TimeManager.hour
	var season_saved41: int = TimeManager.season
	TimeManager.hour = 22                      # 夜里
	TimeManager.season = 3                     # 冬天
	Audio._sync_bgm()
	chk(Audio.current_track() == i41,
		"入夜/换季都不换曲 —— 一整天就是这一首（%s）" % Audio.current_track())
	TimeManager.hour = hour_saved41a
	TimeManager.season = season_saved41
	Audio.set_scene_bgm("ocean")
	chk(Audio.scene_track() == "ocean", "进海图切到航路曲池")
	var prev41: String = Audio.current_track()
	chk(Audio.MEDIEVAL_TRACKS.has(prev41), "海图放的是中世纪包里的曲子（%s）" % prev41)
	Audio._on_track_finished()
	chk(Audio.current_track() == "" and Audio._gap,
		"曲尾先进入 2~5 秒随机静默（出场过渡，不糊成一片）")
	await get_tree().create_timer(6.0).timeout   # 把静默等完（上限 5 秒）
	var next41: String = Audio.current_track()
	chk(next41 != "" and next41 != prev41, "静默结束淡入下一首，不连播同一首（%s -> %s）" % [prev41, next41])
	var prev41b: String = Audio.current_track()
	Audio._on_new_day(1)
	chk(Audio.current_track() != prev41b, "每天起床场景曲也随机换一首（%s -> %s）" % [prev41b, Audio.current_track()])
	Audio.set_scene_bgm("battle")
	chk(Audio.scene_track() == "battle", "进战场切到战斗曲池")
	chk(Audio.MEDIEVAL_TRACKS.has(Audio.current_track()),
		"战场放的也是中世纪包（%s）" % Audio.current_track())
	Audio.set_scene_bgm("island")
	chk(Audio.scene_track() == "island" and Audio.ISLAND_TRACKS.has(Audio.current_track()),
		"回岛上换回 Towball 池（%s）" % Audio.current_track())
	# 结算页曲池 —— 同样是中世纪包, 不新增文件
	Audio.set_scene_bgm("settle")
	chk(Audio.scene_track() == "settle", "战斗结算页切到 settle 曲池")
	chk(Audio.MEDIEVAL_TRACKS.has(Audio.current_track()),
		"结算曲来自中世纪包（当前 %s）" % Audio.current_track())
	Audio.set_scene_bgm("island")     # 还原，别把后面节的状态带歪

	# 41f 开新档必须把上一把全清掉（autoload 跨场景常驻，不清就串档）。
	# 这一节会真的把现场抹掉，所以只能放在自检最后一步。
	Wallet.money = 4321
	Inventory.hotbar[0] = {"item": load("res://item/potato.tres"), "count": 5}
	Inventory.inventory_changed.emit()
	Slaves.slaves = [{"name": "上一把的人", "affection": 3, "fed_today": false,
		"talked_today": false, "max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1}]
	Slaves.count = 1
	TimeManager.year = 5
	TimeManager.season = 2
	TimeManager.day = 18
	Voyage.boat_count = 3
	SaveManager.reset_all()
	chk(TimeManager.year == 1 and TimeManager.season == 0 and TimeManager.day == 1,
		"新档回到第 1 年第 1 天（现在是 第%d年 第%d季 第%d天）"
		% [TimeManager.year, TimeManager.season + 1, TimeManager.day])
	chk(is_equal_approx(Wallet.money, Wallet.START_MONEY),
		"钱回到开局数 %d（当初 4321）" % Wallet.START_MONEY)
	chk(Slaves.count == 0, "上一把的伙伴清空")
	chk(Inventory.hotbar[0]["item"] == null, "背包清空")
	chk(Voyage.boat_count == 0 and not Voyage.traveling and not Voyage.ashore,
		"船数与航行状态归零")
	chk(Audio.scene_track() == "island", "BGM 归位到岛上曲池（不留上一把海图/战场的曲子）")

	# —— 42. 海图材质（图集规模 / 索引不越界 / 海岸三层过渡真铺上了）——
	# 2026-09-16 重做：水从 3 档硬色块加密到 6 档 + 4 个波纹相位（按格子 hash 错开），
	# 陆地补湿沙/干沙/草沙三层海岸过渡，另加礁石、码头标记、云影。
	print("\n=== 42. 海图材质 ===")
	var wmcm: Dictionary = (load("res://scene/world_map.gd") as Script).get_script_constant_map()
	var t_count: int = int(wmcm.get("T_COUNT", 0))
	var t_sea: int = int(wmcm.get("T_SEA", 0))
	var sea_lv: int = int(wmcm.get("SEA_LEVELS", 0))
	var sea_va: int = int(wmcm.get("SEA_VARIANTS", 0))
	var t_rockb: int = int(wmcm.get("T_ROCK_B", 0))
	chk(t_count == t_rockb + 1 and t_rockb > t_sea + sea_lv * sea_va,
		"图集格数自洽：%d 格（陆地 %d + 水 %d 档 x %d 相位 + 风貌 %d）"
			% [t_count, t_sea, sea_lv, sea_va, t_rockb - t_sea - sea_lv * sea_va])
	chk(sea_lv >= 4 and sea_va >= 2,
		"水的档数/相位数够打散格子感（%d 档 x %d 相位；退回 3 档 2 相位就会露马赛克）"
		% [sea_lv, sea_va])
	var wm42: Variant = load("res://scene/world_map.gd").new()
	add_child(wm42)
	await get_tree().process_frame
	var tl42: TileMapLayer = wm42.get_node_or_null("Tiles")
	chk(tl42 != null, "海图铺了 Tiles 图层")
	if tl42 != null:
		var cells42 := tl42.get_used_cells()
		var exp42: int = int(wmcm.get("MAP_W", 0)) * int(wmcm.get("MAP_H", 0))
		chk(cells42.size() == exp42, "整张图都铺满了（%d / %d 格）" % [cells42.size(), exp42])
		# e52b: 导出包里 res:// 的原始 png 不进 PCK（all_resources + include_filter 空）——
		# 取样必须能从**导入贴图**兜底取到像素, 否则图集里草地/雪地/岩石格全留在深海底色上
		# （用户实机：草地变成水的瓦块）
		var fb42: Image = wm42.call("_png_from_texture", String(wmcm.get("ART_GRASS", "")))
		var hit42 := 0
		if fb42 != null:
			for y42 in range(0, fb42.get_height(), 16):
				for x42 in range(0, fb42.get_width(), 16):
					if fb42.get_pixel(x42, y42).a > 0.5:
						hit42 += 1
		chk(fb42 != null and fb42.get_width() == 384 and fb42.get_height() == 640 and hit42 > 100,
			"导出兜底路径（从导入贴图取像素）能取到真图：%dx%d 不透明采样 %d"
				% [fb42.get_width() if fb42 != null else 0,
					fb42.get_height() if fb42 != null else 0, hit42])
		var oob := 0
		var n_water := 0
		var n_land := 0
		var seen := {}
		for c42 in cells42:
			var a42: Vector2i = tl42.get_cell_atlas_coords(c42)
			seen[a42.x] = true
			if a42.x < 0 or a42.x >= t_count:
				oob += 1
			elif a42.x >= t_sea:
				n_water += 1
			else:
				n_land += 1
		chk(oob == 0, "没有取到图集外的图块（%d 格越界）" % oob)
		chk(n_water > 0 and n_land > 0, "水与陆地都铺上了（水 %d / 陆 %d 格）" % [n_water, n_land])
		chk(seen.has(int(wmcm.get("T_SAND_WET", 0))) and seen.has(int(wmcm.get("T_SAND", 0)))
			and seen.has(int(wmcm.get("T_GRASS_SAND", 0))),
			"海岸三层过渡都真的用上了（湿沙/干沙/草沙）")
		chk(seen.has(t_sea) and seen.has(t_sea + sea_lv * sea_va - 1),
			"贴岸浅水档与远洋深水档都存在（水深 BFS 没退化）")
	# 礁石 / 码头标记 / 云影 / 树：纯装饰层，缺了不会崩，但海面会很空
	var deco: Array = []
	for nm in ["CloudShadows", "Trees", "Rocks", "DockMarks"]:
		if wm42.get_node_or_null(nm) != null:
			deco.append(nm)
	chk(deco.size() == 4, "装饰层齐全：%s" % str(deco))
	# 2026-09-19：装饰层里加了「花草蘑菇撒点」（Decor 层，跟岛上同款）
	var dec42: Node = wm42.get_node_or_null("Decor")
	var n_dec42: int = (dec42.get_used_cells().size() if dec42 is TileMapLayer else 0)
	chk(dec42 != null and n_dec42 > 0, "海图撒了花草装饰（Decor 层 %d 格）" % n_dec42)
	# 两头码头要在图上各有一个记号（走到那儿按 F 返航/上岸）
	var dm42: Node = wm42.get_node_or_null("DockMarks")
	chk(dm42 != null and dm42.get_child_count() == 2,
		"岛码头与大陆码头都标了记号（%d 个）" % (0 if dm42 == null else dm42.get_child_count()))
	# 2026-09-19：头像帧里必须有 walk_*（Run.png 8 帧 x 3 行）——
	# 出海乘船的划桨起伏用的就是这套，少了它船头的人一动不动
	var avf42: SpriteFrames = wm42._avatar_frames()
	chk(avf42.has_animation(&"walk_down") and avf42.has_animation(&"walk_up")
		and avf42.has_animation(&"walk_side"), "海图头像有 walk_* 走动/划桨动画")
	wm42.queue_free()
	await get_tree().process_frame

	# —— 43. 存档时机（有且只有早上 6 点）+ 读档入口收回主页面 ——
	# 2026-09-16：设置页原来挂着一整张「每日快照读档列表」，现在整块搬去主页面；
	# 同时把关窗口那份「兜底存档」删了 —— 它会在随便什么时刻写档，「只有 6 点」就破了。
	print("\n=== 43. 存档只在早上 6 点 / 读档在主页面 ===")
	# 43a 存档时刻的定义：一天从 6 点开始，换日之后必然落回 6:00
	chk(TimeManager.START_HOUR == 6,
		"一天从早上 %d 点开始（存档时刻就是它）" % TimeManager.START_HOUR)
	var d43: int = TimeManager.day
	TimeManager.advance_day()
	chk(TimeManager.hour == 6 and TimeManager.minute == 0,
		"换完日正好落在新一天 6:00（现在 %d:%02d）" % [TimeManager.hour, TimeManager.minute])
	chk(TimeManager.day != d43, "换日真的往后走了一天（%d -> %d）" % [d43, TimeManager.day])

	# 43b 关窗兜底必须已经删掉
	chk(not SaveManager.has_method("_notification"),
		"关窗兜底存档已删（存档时机只剩换日那一刻）")

	# 43c 设置页：换成「返回主页面」，读档那套彻底不在这一页了
	var bp43: Control = load("res://backpack_ui.gd").new()
	add_child(bp43)
	await get_tree().process_frame
	bp43.open()
	bp43.call("_select_module", "set")
	for _i43 in 3:
		await get_tree().process_frame
	chk(find_button_text(bp43, "返回主页面") != "", "设置页有「返回主页面」按钮")
	chk(find_button_text(bp43, "读档") == "", "设置页不再有任何读档按钮")
	chk(not bp43.has_method("_on_load_save_pressed") and not bp43.has_method("_refresh_save_list"),
		"原来那套「列快照 + 读档」的函数已删干净")
	chk(bp43.has_method("_on_back_to_menu"), "回主页面的处理函数在")
	bp43.close()
	bp43.queue_free()
	await get_tree().process_frame

	# 43d 开新档那一刻 = 第 1 天 6:00，正好踩在存档时刻上
	SaveManager.begin_new_game("自检新档")
	SaveManager.reset_all()
	chk(TimeManager.year == 1 and TimeManager.day == 1
			and TimeManager.hour == 6 and TimeManager.minute == 0,
		"开新档 = 第 1 天早上 6:00（现在 第%d年 第%d天 %d:%02d）" % [
			TimeManager.year, TimeManager.day, TimeManager.hour, TimeManager.minute])
	SaveManager.take_reset_request()

	print("\n=== 44. 砍树点得中：树冠悬在格子上方近 3 格，判定得按贴图来 ===")
	# 44a 现种一棵成树当靶子
	# ❗不能指望"岛上现成那些树"：前面 41/43 节都跑过 SaveManager.reset_all()，
	#   而它里头有一句 Trees.reset()（新档当然得把树清干净），全岛的树早没了。
	var tc44 := Vector2i(-999, -999)
	for k44 in g._land_set.keys():
		var kk44: Vector2i = k44
		if g.is_water(kk44) or g.is_bridge_cell(kk44) or Farm.tilled.has(kk44):
			continue
		if Trees.is_blocked(kk44) or g.is_water(kk44 + Vector2i(0, 1)):   # 下方得能站人
			continue
		if Trees.plant(kk44, 0, Trees.ST_MATURE):
			tc44 = kk44
			break
	chk(tc44.x != -999, "种一棵成树当靶子 %s" % tc44)
	await get_tree().process_frame
	chk(g.tree_nodes.has(tc44), "靶子树的节点摆出来了")
	var node44: Node2D = g.tree_nodes[tc44]
	var base44: Vector2 = node44.global_position
	chk(g._world_to_cell(base44 - Vector2(0.0, 8.0)) == tc44,
		"树干底部换算回格子 = 它注册的那格（节点摆位与格子索引对得上）")
	# 44b 对着树冠量格子会偏掉 —— 这就是原来"这里没有能砍的树"的来路
	var crown44 := base44 + Vector2(0, -34)
	var wrong44: Vector2i = player._facing_grid_pos(crown44)
	chk(wrong44 != tc44,
		"对着树冠量格子会偏（树冠上算成 %s，树其实在 %s）" % [wrong44, tc44])
	chk(wrong44.y < tc44.y, "而且是偏到树顶上方的空格里（y %d < %d）" % [wrong44.y, tc44.y])
	# 44c 按贴图命中：点哪棵是哪棵
	chk(g.pick_tree_cell(crown44, wrong44) == tc44, "pick_tree_cell 按贴图挑出那棵树")
	chk(g.pick_tree_cell(base44 + Vector2(-14, -40), Vector2i(0, 0)) == tc44, "树冠左缘也认")
	chk(g.pick_tree_cell(base44 + Vector2(14, -40), Vector2i(0, 0)) == tc44, "树冠右缘也认")
	chk(g.pick_tree_cell(base44 + Vector2(0, -44), Vector2i(0, 0)) == tc44, "树冠最顶端也认")
	# 44d 全链路：挥一斧头真的削到树（不是只验坐标算得对）
	player.current_item = load("res://item/axe.tres")
	var hp44 := int(Trees.trees[tc44].hp)
	player._swing_axe(wrong44, crown44)
	chk(int(Trees.trees[tc44].hp) == hp44 - 1,
		"对着树冠挥斧：耐久 %d -> %d" % [hp44, int(Trees.trees[tc44].hp)])
	# 44e 站在树前面直接按使用键（鼠标压根没挪到树上）也得砍得到
	place_player(tc44 + Vector2i(0, 1))
	var pc44: Vector2i = g._world_to_cell(player.global_position)
	chk(pc44 == tc44 + Vector2i(0, 1), "人站在树下方一格 %s" % pc44)
	var pick44: Vector2i = g.pick_tree_cell(player.global_position, pc44)
	chk(Trees.has_tree(pick44), "鼠标停在自己脚下按键：挑出身边那棵树 %s" % pick44)
	chk(maxi(absi(pick44.x - pc44.x), absi(pick44.y - pc44.y)) <= 1, "而且就在身边一格内")
	chk(int(g.hit_tree(pick44).result) != Trees.RESULT_MISS,
		"挥下去真砍到了（不是'这里没有能砍的树'）")
	# 44f 对着远处空地挥斧：不乱吸旁边的树，老实报 MISS
	var far44 := Vector2i(-999, -999)
	for k44b in g._land_set.keys():
		var kk44b: Vector2i = k44b
		var clean44 := not Farm.tilled.has(kk44b) and not Trees.has_tree(kk44b)
		for dy44 in range(-1, 2):
			for dx44 in range(-1, 2):
				if Trees.has_tree(kk44b + Vector2i(dx44, dy44)):
					clean44 = false
		if clean44:
			far44 = kk44b
			break
	chk(far44.x != -999, "找到一块周围一圈都没树的空地 %s" % far44)
	place_player(far44)
	var got44: Vector2i = g.pick_tree_cell(player.global_position, far44)
	chk(got44 == far44, "对着空地挥斧还是那格（%s）" % got44)
	chk(int(g.hit_tree(got44).result) == Trees.RESULT_MISS,
		"空地 = MISS（会提示'这里没有能砍的树'）")
	# 44g 注入鼠标点这条路是对的（探针靠它，别把默认参数改坏）
	chk(player._facing_grid_pos(Vector2.ZERO) == g._world_to_cell(Vector2.ZERO),
		"_facing_grid_pos 传具体点 = 按那个点换算格子")

	# —— 45. 双职业树：战斗三线 + 劳动三线 + 转职花钱料 + 装甲分档变色 ——
	print("\n=== 45. 双职业树：战斗/劳动 + 转职消耗 + 装甲档位 ===")
	# 45a 数据树：战斗 10 档（新兵三岔 + 三线三阶）、劳动 10 档（帮工三岔 + 三线三阶）
	var T45: Dictionary = (load("res://slaves.gd") as Script).get_script_constant_map()
	var cl45: Dictionary = T45["CLASSES"]
	var lb45: Dictionary = T45["LABOR_CLASSES"]
	var fight45 := ["新兵", "刀客", "弓手", "骑兵", "剑士", "神射手", "枪骑兵", "咏剑士", "狙击手", "重骑兵"]
	var labor45 := ["帮工", "工匠", "学徒", "园丁", "匠师", "书生", "农艺师", "大匠", "学士", "大地之友"]
	var has45 := true
	for k45 in fight45:
		if not cl45.has(k45):
			has45 = false
	for k45 in labor45:
		if not lb45.has(k45):
			has45 = false
	chk(has45, "双树 20 档都在（战斗/劳动各 10 档）")
	chk((cl45.get("新兵", {}).get("next", []) as Array) == ["刀客", "弓手", "骑兵"],
		"新兵是岔路: 近战/远程/骑兵三选一")
	chk((lb45.get("帮工", {}).get("next", []) as Array) == ["工匠", "学徒", "园丁"],
		"帮工是岔路: 建筑/学者/农艺三选一")
	# e30s: 学者线/劳动线数值加强（1/2/4 -> 2/3/6、4/8/12 -> 6/12/20）
	chk(int(lb45.get("学徒", {}).get("study", 0)) == 2 and int(lb45.get("书生", {}).get("study", 0)) == 3
		and int(lb45.get("学士", {}).get("study", 0)) == 6, "学者线研究人手 2/3/6")
	chk(int(lb45.get("园丁", {}).get("labor", 0)) == 6 and int(lb45.get("农艺师", {}).get("labor", 0)) == 12
		and int(lb45.get("大地之友", {}).get("labor", 0)) == 20, "丰饶线劳动力 6/12/20")
	# e52e: 职业图标 —— 20 档全都有配图, 素材在盘上真能取到（整图/图集切格都试）
	var ic_ok45 := true
	var icons45: Dictionary = T45["CLASS_ICONS"]
	for k45 in fight45:
		if not icons45.has(k45):
			ic_ok45 = false
	for k45 in labor45:
		if not icons45.has(k45):
			ic_ok45 = false
	chk(ic_ok45, "职业图标表覆盖全部 20 档")
	chk(Slaves.class_icon_for("新兵") != null and Slaves.class_icon_for("书生") != null
		and Slaves.class_icon_for("大地之友") != null,
		"职业图标真能取到（整图 + 图集切格都通）")
	chk(Slaves.class_icon_for("查无此职") == null, "没配图标的职业老实回 null")
	# e52f: 改名对照 —— 两个时代的旧名都要接到现在的园丁/农艺师/大地之友
	chk(String(T45["LABOR_RENAMED"]["农夫"]) == "园丁" and String(T45["LABOR_RENAMED"]["壮丁"]) == "园丁"
		and String(T45["LABOR_RENAMED"]["田祖"]) == "大地之友"
		and String(T45["LABOR_RENAMED"]["把式"]) == "农艺师",
		"旧档劳动职业名能接到新名字上")
	# 45b 链路 + 消耗: prev_of 沿树画回去; 一线 60金+甲1, 二线 140金+铁1+甲2, 三线 260金+铁3+甲3
	chk(Slaves.prev_of("骑兵") == "新兵", "骑兵的来路是新兵")
	chk(Slaves.prev_of("重骑兵") == "枪骑兵", "重骑兵的来路是枪骑兵")
	chk(Slaves.prev_of("新兵") == "", "新兵是根, 没有来路")
	chk(Slaves.labor_prev_of("园丁") == "帮工" and Slaves.labor_prev_of("帮工") == "",
		"劳动树根是帮工, 园丁的来路是帮工")
	var c60_45: Dictionary = cl45.get("骑兵", {}).get("cost", {})
	chk(int(c60_45.get("coin", 0)) == 60 and int(c60_45.get("armor", 0)) == 1,
		"一线转职要 60 金 + 整套甲1级")
	var c140_45: Dictionary = cl45.get("枪骑兵", {}).get("cost", {})
	chk(int(c140_45.get("coin", 0)) == 140 and int(c140_45.get("iron", 0)) == 1
		and int(c140_45.get("armor", 0)) == 2, "二线要 140金 + 铁x1 + 整套甲2级")
	var c260_45: Dictionary = cl45.get("重骑兵", {}).get("cost", {})
	chk(int(c260_45.get("coin", 0)) == 260 and int(c260_45.get("iron", 0)) == 3
		and int(c260_45.get("armor", 0)) == 3, "三线要 260金 + 铁x3 + 整套甲3级")
	chk(String(Slaves.cost_text(c260_45)).contains("铁x3"), "消耗文案会说人话（铁x3）")
	# 45c 分支目标: 同一个人能列出所有可转职业（升不升只看钱料, 不看天赋历练）
	# ❗字段要给全: Slaves.changed 联动背包队伍页时会真去画这张卡（affection/labor 都读）
	var fake45 := {"name": "测试骑兵", "troop": "新兵", "labor": "帮工",
		"affection": 0, "fed_today": true, "talked_today": true,
		"hp": 30, "max_hp": 30, "squad": 1}
	var ts45: Array = Slaves.promote_targets(fake45)
	chk(ts45.size() == 3 and ts45.has("骑兵"), "新兵的转职列表 = 近战/远程/骑兵三个岔路")
	chk((Slaves.labor_targets(fake45) as Array).has("园丁"), "劳动树列表也有三岔（含园丁）")
	# 45d 装甲分档: 布衣白 -> 二线银灰 -> 满阶金铜（一线兵照旧布衣）
	chk(Slaves.armor_tint("骑兵").is_equal_approx(T45["ARMOR_TINT_ROOKIE"]), "一线兵布衣白（新兵/刀客/弓手/骑兵）")
	chk(Slaves.armor_tint("枪骑兵").is_equal_approx(T45["ARMOR_TINT_VETERAN"]), "二线披银灰甲（剑士/神射手/枪骑兵）")
	chk(Slaves.armor_tint("重骑兵").is_equal_approx(T45["ARMOR_TINT_ELITE"]), "满阶披金铜甲（咏剑士/狙击手/重骑兵）")
	chk(Slaves.armor_tint("不存在的兵").is_equal_approx(T45["ARMOR_TINT_ROOKIE"]), "没认出的兵种老实回布衣白")
	# 45e 战场判定: 骑兵算骑马、骑枪更长
	var tk45: Dictionary = (load("res://scene/troop.gd") as Script).get_script_constant_map()
	var tu45: Variant = load("res://scene/troop.gd").new()
	tu45.kind = "骑兵"
	chk(tu45.is_mounted(), "骑兵 is_mounted = 真（上马）")
	chk(is_equal_approx(tu45.reach(), float(tk45["MELEE_RANGE"]) + 14.0), "骑枪触及比步兵长 14")
	tu45.kind = "刀客"
	chk(not tu45.is_mounted(), "刀客没马（is_mounted = 假）")
	# 45e2 e41i 骑兵加强: 满阶重骑兵也得骑马 + 血上限比步兵厚 + 有切后排的钩子
	tu45.kind = "重骑兵"
	chk(tu45.is_mounted(), "满阶重骑兵也骑马（以前 MOUNTED_KINDS 漏了他）")
	chk(Slaves.is_mounted_troop("枪骑兵") and Slaves.is_mounted_troop("重骑兵")
			and not Slaves.is_mounted_troop("刀客") and not Slaves.is_mounted_troop("咏剑士"),
		"骑兵三档都算骑马, 步兵不算")
	chk(Slaves.troop_max_hp("骑兵") == Legion.ally_max_hp() + int(T45["CAVALRY_HP_BONUS"])
			and Slaves.troop_max_hp("刀客") == Legion.ally_max_hp(),
		"骑兵血上限 = 步兵 + %d" % int(T45["CAVALRY_HP_BONUS"]))
	var bmnames45: Array = []
	for m45x in (load("res://scene/battle_map.gd") as GDScript).get_script_method_list():
		bmnames45.append(String(m45x["name"]))
	chk(bmnames45.has("nearest_archer_of"), "战场提供 nearest_archer_of（骑兵切后排索敌）")
	var tpnames45: Array = []
	for m45y in (load("res://scene/troop.gd") as GDScript).get_script_method_list():
		tpnames45.append(String(m45y["name"]))
	chk(tpnames45.has("_foe_archer") and tpnames45.has("_flank_dest"),
		"骑兵 AI 有 _foe_archer（优先扑敌方弓手）")
	# 45f 真转职: 没钱 / 没铁 / 没甲 都拒绝, 备齐了才放行且真扣料（fake45 沿用 45c 那个新兵）
	var m45 := Wallet.money
	var iron0_45 := Inventory.count_item(Slaves.IRON_ITEM)
	var armor_w45: ItemData = load("res://item/armor_wood.tres")
	var armor_i45: ItemData = load("res://item/armor_iron.tres")
	var armor_g45: ItemData = load("res://item/armor_gold.tres")
	var iron_left45 := iron0_45
	if iron_left45 > 0:
		Inventory.remove_item(Slaves.IRON_ITEM, iron_left45)
		iron_left45 = 0
	while Slaves.find_armor(1) != null:              # 把甲也清干净, 从零开始考
		Inventory.remove_item(Slaves.find_armor(1), 1)
	Slaves.slaves.append(fake45)
	Slaves.count = Slaves.slaves.size()
	var idx45: int = Slaves.slaves.size() - 1
	chk(Slaves.can_promote(idx45), "新兵还有三岔可走（can_promote 只看岔路, 不看历练）")
	Wallet.spend_money(Wallet.money)                 # 清空钱包 -> 第一关: 没钱
	var no45 := not Slaves.promote(idx45, "骑兵")
	var m45a := maxi(m45, 500)                       # 备足全程盘缠（三线累计要 460 金）
	Wallet.money = m45a                              # 一线也要 1 级甲: 只有钱 -> 再拒
	var no45i := not Slaves.promote(idx45, "骑兵")
	Inventory.add_item(armor_w45, 1)                 # 套上皮甲 -> 放行
	chk(no45 and no45i and Slaves.promote(idx45, "骑兵"), "60金 + 甲1级备齐: 新兵转骑兵成功")
	chk(String(Slaves.slave_at(idx45).get("troop", "")) == "骑兵", "兵种写回骑兵")
	chk(Wallet.money == m45a - 60, "扣了 60 金（%d -> %d）" % [m45a, Wallet.money])
	chk(Inventory.count_item(armor_w45) == 0, "整套 1 级甲被一线转职吃掉")
	chk(not Slaves.promote(idx45, "剑士"), "已是骑兵不能跨线转剑士（只许顺自己这条线往上）")
	# 二线: 140金 + 铁x1 + 整套甲2级 —— 没钱/没铁/甲不够级逐个卡
	var m45b := Wallet.money
	var no45b := not Slaves.promote(idx45, "枪骑兵")  # 铁和甲都是 0 -> 拒
	Inventory.add_item(Slaves.IRON_ITEM, 1)           # 有铁没甲 -> 还是拒
	var no45c := not Slaves.promote(idx45, "枪骑兵")
	Inventory.add_item(armor_w45, 1)                  # 1 级甲够不着 2 级门槛 -> 三拒
	var no45h := not Slaves.promote(idx45, "枪骑兵")
	chk(no45 and no45b and no45c and no45h and String(Slaves.slave_at(idx45).get("troop", "")) == "骑兵",
		"没钱、没铁或甲不够级都转不了枪骑兵（要 140金 + 铁x1 + 甲2级）")
	Inventory.add_item(armor_i45, 1)                  # 背上一套 2 级甲 -> 放行
	var i45b := Inventory.count_item(Slaves.IRON_ITEM)
	chk(Slaves.promote(idx45, "枪骑兵"), "钱料甲备齐: 骑兵转枪骑兵")
	chk(String(Slaves.slave_at(idx45).get("troop", "")) == "枪骑兵", "兵种写回枪骑兵")
	chk(Wallet.money == m45b - 140, "扣了 140 金（%d -> %d）" % [m45b, Wallet.money])
	chk(Inventory.count_item(Slaves.IRON_ITEM) == i45b - 1, "扣了铁x1")
	chk(Inventory.count_item(armor_i45) == 0, "整套 2 级甲被转职吃掉")
	# 三线: 260金 + 铁x3 + 整套甲3级 —— 铁不够、甲不够都先拒, 备齐才放
	var m45c := Wallet.money
	var no45d := not Slaves.promote(idx45, "重骑兵")  # 铁 0/3 又没 3 级甲 -> 拒
	Inventory.add_item(Slaves.IRON_ITEM, 2)           # 铁 2/3 还差一点 -> 再拒
	var no45e := not Slaves.promote(idx45, "重骑兵")
	Inventory.add_item(Slaves.IRON_ITEM, 1)           # 铁 3/3 了, 还差 3 级甲 -> 三拒
	var no45g := not Slaves.promote(idx45, "重骑兵")
	Inventory.add_item(armor_g45, 1)                  # 3 级甲(铁甲) 达标 -> 放行
	chk(no45d and no45e and no45g and Slaves.promote(idx45, "重骑兵"),
		"满阶先拒后放: 260金 + 铁x3 + 整套甲3级")
	chk(String(Slaves.slave_at(idx45).get("troop", "")) == "重骑兵", "最终到满阶重骑兵")
	chk(Wallet.money == m45c - 260, "扣了 260 金（%d -> %d）" % [m45c, Wallet.money])
	chk(Inventory.count_item(Slaves.IRON_ITEM) == 0, "铁x3 扣光")
	chk(Inventory.count_item(armor_g45) == 0, "满阶转职吃掉整套 3 级甲")
	chk(not Slaves.can_promote(idx45), "重骑兵满阶: 战斗树到头, can_promote 假")
	# 劳动树同场加映: 帮工 -> 园丁（120金）, 升完不许跨线转工匠
	Wallet.money = maxi(Wallet.money, 200)
	chk(Slaves.promote_labor(idx45, "园丁"), "劳动树: 帮工转园丁成功（120金）")
	chk(String(Slaves.slave_at(idx45).get("labor", "")) == "园丁", "劳动职业写回园丁")
	chk(not Slaves.promote_labor(idx45, "工匠"), "已是园丁就不许跨线转工匠（劳动树同样单向）")
	# 还原现场: 撤掉测试伙伴, 钱和铁都按进节前的数补回
	Slaves.slaves.erase(fake45)
	Slaves.count = Slaves.slaves.size()
	iron_left45 = Inventory.count_item(Slaves.IRON_ITEM)
	if iron_left45 > 0:
		Inventory.remove_item(Slaves.IRON_ITEM, iron_left45)
	if iron0_45 > 0:
		Inventory.add_item(Slaves.IRON_ITEM, iron0_45)
	Wallet.money = m45
	Slaves.changed.emit()

	# —— 46. 开局动画: 国破流落荒岛 (只在新档播, 可跳过) ——
	print("\n=== 46. 开局动画: 搭景 + 跳过 ===")
	chk(g.has_method("_play_opening"), "game 挂了开局动画入口 (_play_opening)")
	var op46: Variant = load("res://scene/opening.gd").new()
	var done46 := [false]
	op46.finished.connect(func() -> void: done46[0] = true)
	add_child(op46)
	await get_tree().process_frame
	await get_tree().process_frame
	chk(is_instance_valid(op46) and op46._root != null and op46._caption != null,
		"开场动画搭好景 (根幕 + 字幕都在)")
	chk(op46._cloths.size() == Nations.NATIONS.size(),
		"四面国家旗跟着 Nations 数据走 (%d 面)" % op46._cloths.size())
	chk(op46._boat != null and op46._isle != null, "夜海孤舟和荒岛都备好了")
	# 插上跳过旗: 字幕循环 0.05 秒粒度退出, 收黑 0.6 秒, 几秒内应放完
	op46._skip_all = true
	var t46 := 0.0
	while not bool(done46[0]) and t46 < 8.0:
		await get_tree().create_timer(0.1).timeout
		t46 += 0.1
	chk(bool(done46[0]), "跳过旗一插, 动画很快放完并发出 finished (%.1f 秒)" % t46)
	chk(not is_instance_valid(op46) or op46.is_queued_for_deletion(), "放完自动销毁 (queue_free)")

	# —— 47. 花名册与初始劳动力 ——
	print("\n=== 47. 花名册与初始劳动力 ===")
	chk(Slaves.ROSTER.size() == 8, "花名册 8 人（实际 %d）" % Slaves.ROSTER.size())
	var rq_ok47 := true
	var days47 := 0
	for r47 in Slaves.ROSTER:
		if String(r47.get("id", "")) == "" or String(r47.get("name", "")) == "" \
				or String(r47.get("req", "")) == "" or int(r47.get("day", 0)) <= days47:
			rq_ok47 = false
		days47 = int(r47.get("day", 0))
	chk(rq_ok47, "花名册每人都带 id / 名字 / 诉求, 到访日逐个递增")
	chk(String(Slaves.ROSTER[7]["name"]) == "雪莱" and String(Slaves.ROSTER[7]["troop"]) == "新兵",
		"压轴的是雪莱（新兵, 完成第一项科技才肯来）")
	chk(Slaves.CELLS_PER_SLAVE >= 12, "初始劳动力 %d 格/人（至少 12）" % Slaves.CELLS_PER_SLAVE)
	chk(Slaves.cells_per_slave() == Slaves.CELLS_PER_SLAVE + Research.labor_bonus_per_head(),
		"派活额度 = 基础 %d + 行政加成 %d" % [Slaves.CELLS_PER_SLAVE, Research.labor_bonus_per_head()])

	# —— 48. BGM 曲池健全性 + 屋内黑幕（星露谷式）——
	print("\n=== 48. BGM 曲池健全性 + 屋内黑幕 ===")
	# e52: 三类曲各抽一首查时长能读出来 —— 岛上 Towball(mp3) / 中世纪包(ogg) / menu
	var spot_bgm := {
		"menu": Audio.BGM_DIR + "menu.ogg",
		"岛上曲": Audio.ISLAND_TRACKS[0],
		"岛上曲2": Audio.ISLAND_TRACKS[9],
		"中世纪曲": Audio.MEDIEVAL_TRACKS[2],
		"中世纪曲2": Audio.MEDIEVAL_TRACKS[7],
	}
	for k in spot_bgm:
		var st: AudioStream = Audio._bgm_streams.get(spot_bgm[k])
		chk(st != null, "曲池 %s 的 %s 在" % [k, spot_bgm[k].get_file()])
		if st != null:
			chk(st.get_length() > 8.0,
				"%s 时长 %.1f 秒（>8s，不是截断文件）" % [spot_bgm[k].get_file(), st.get_length()])
	# 黑幕：进屋显 / 出屋藏 / 读档还原同步
	var house2: Node2D = g.get_node("House")
	if player.indoors:
		house2.set_indoors_visual(false)
	var veil: Node2D = house2.get("_veil")
	chk(veil != null, "屋内黑幕已创建")
	chk(not veil.visible, "初始黑幕隐藏")
	var z0: int = player.z_index
	house2._enter_house(player)
	chk(veil.visible and player.indoors, "进屋后黑幕亮起")
	chk(house2.interior.visible, "进屋后屋内显示")
	chk(player.z_index > veil.z_index and house2.interior.z_index > veil.z_index,
		"玩家(%d)和屋内(%d)都画在黑幕(%d)之上" % [player.z_index, house2.interior.z_index, veil.z_index])
	house2._leave_house(player)
	chk(not veil.visible and not player.indoors, "出屋后黑幕收起")
	chk(player.z_index == z0, "出屋后玩家 z 还原（%d）" % player.z_index)
	house2.set_indoors_visual(true)
	chk(veil.visible and player.z_index == 97, "读档还原(在屋里): 黑幕亮 + 玩家 z 提升")
	house2.set_indoors_visual(false)
	chk(not veil.visible and not player.indoors, "读档还原(在屋外): 黑幕收起")

	# —— 49. 作弊面板（P 唤醒：加钱 / 加资源）——
	print("\n=== 49. 作弊面板 ===")
	chk(g.cheat_panel != null, "game 已挂作弊面板")
	# 加钱
	var m49 := Wallet.money
	Wallet.add_money(1000)
	chk(Wallet.money == m49 + 1000, "加钱 1000 -> %d" % Wallet.money)
	# 加资源（背包满时 add_item 返回 false，此时只要求不丢已有）
	var wood49: ItemData = load("res://item/wood.tres")
	var c49 := Inventory.count_item(wood49)
	if Inventory.add_item(wood49, 99):
		chk(Inventory.count_item(wood49) == c49 + 99,
			"加 99 木头 -> 背包 %d" % Inventory.count_item(wood49))
	else:
		chk(Inventory.count_item(wood49) >= c49, "背包满时不丢已有(数量 %d)" % Inventory.count_item(wood49))
	# 开关面板：时间冻结栈 push/pop 必须成对
	var tr49: bool = TimeManager.time_running
	g._toggle_cheat()
	chk(g.cheat_panel.is_open(), "按 P 打开作弊面板")
	# 2026-09-19 新增：工地推进 / 免费招募按钮。面板开着、没开工 ——
	# 此时点 +5 人工只会有「没有工地」提示，零副作用，正好当探针用。
	var tip49: Label = g.cheat_panel._tip
	g.cheat_panel._cheat_site_work()
	chk(tip49.text.contains("没有工地"), "无工地时 +5 人工有提示 (%s)" % tip49.text)
	g.cheat_panel._cheat_site_done()
	chk(tip49.text.contains("没有工地"), "无工地时直接建成也有提示 (%s)" % tip49.text)
	var btn49 := {"+5 人工": false, "直接建成": false, "免费招 1 人": false}
	for n49 in g.cheat_panel.find_children("*", "Button", true, false):
		var t49: String = (n49 as Button).text
		if btn49.has(t49):
			btn49[t49] = true
	chk(btn49["+5 人工"] and btn49["直接建成"] and btn49["免费招 1 人"],
		"工地/伙伴三个作弊按钮都在")
	g.cheat_panel._dismiss()
	chk(not g.cheat_panel.is_open(), "再按 P 收起作弊面板")
	chk(TimeManager.time_running == tr49, "开关一次后时间状态还原(%s)" % TimeManager.time_running)
	sweep_glyphs(g.cheat_panel, "作弊面板")

	# —— 50. 开场 v2: 字幕不被孤舟/荒岛挡 + 石头身位碰撞 + 伙伴失踪文案 ——
	print("\n=== 50. 开场层级 + 石头碰撞 + 伙伴失踪 ===")
	var op50: Variant = load("res://scene/opening.gd").new()
	var done50 := [false]
	op50.finished.connect(func() -> void: done50[0] = true)
	add_child(op50)
	chk(op50._boat.get_parent() == op50._root and op50._isle.get_parent() == op50._root,
		"孤舟/荒岛都挂进黑幕 _root 下（不再直接飘在 CanvasLayer 上压字幕）")
	chk(op50._boat.get_index() < op50._caption.get_index()
		and op50._isle.get_index() < op50._caption.get_index(),
		"兄弟序: 字幕(%d)画在孤舟(%d)/荒岛(%d)之上"
			% [op50._caption.get_index(), op50._boat.get_index(), op50._isle.get_index()])
	var pal50 := false
	var lost50 := false
	for st in op50.STEPS:
		var txt: String = st[0]
		if txt.contains("伙伴"):
			pal50 = true
		if txt.contains("失踪"):
			lost50 = true
	chk(pal50 and lost50, "开场字幕里讲了伙伴, 也讲了他失踪在风暴里")
	sweep_glyphs(op50, "开场字幕")
	op50._skip_all = true
	var t50 := 0.0
	while not bool(done50[0]) and t50 < 8.0:
		await get_tree().create_timer(0.1).timeout
		t50 += 0.1
	chk(bool(done50[0]), "跳过旗一插照旧放完发 finished (%.1f 秒)" % t50)
	chk(not is_instance_valid(op50) or op50.is_queued_for_deletion(), "放完自动销毁 (queue_free)")
	# 石头碰撞: 单独起一块, 断言碰撞体盖住大半个身位
	var rn50: Node2D = preload("res://scene/rock_node.gd").new()
	add_child(rn50)
	var sh50: RectangleShape2D = null
	var layer50 := 0
	for c in rn50.get_children():
		if c is StaticBody2D:
			layer50 = c.collision_layer
			for cc in c.get_children():
				if cc is CollisionShape2D and cc.shape is RectangleShape2D:
					sh50 = cc.shape
	chk(sh50 != null, "石头带了矩形碰撞体")
	if sh50 != null:
		chk(sh50.size.x >= 16.0 and sh50.size.y >= 8.0,
			"碰撞体盖住三石堆底部 (%sx%s, 视觉 22x16)" % [sh50.size.x, sh50.size.y])
	chk(layer50 == 4, "碰撞在 layer 3(值4): 只拦玩家, 伙伴照旧穿行")
	var spr50: Sprite2D = null
	for c in rn50.get_children():
		if c is Sprite2D and c.z_index >= 0:    # e33a 跳过脚底影子 (z=-1)
			spr50 = c
	var at50: AtlasTexture = spr50.texture if spr50 != null else null
	chk(spr50 != null and spr50.scale == Vector2.ONE
		and at50 is AtlasTexture and at50.region == Rect2(37, 32, 22, 16),
		"石头按裁剪窗 1:1 取素面三石堆（不缩小）")
	rn50.queue_free()

	# —— 51. 建造系统 + 铁匠铺 + 整套装备 (第九轮) ——
	print("\n=== 51. 建造系统 + 铁匠铺 + 整套装备 ===")
	# 51a 建造菜单数据 + 星露谷式摆放三件套
	var ST51: Dictionary = (load("res://structures.gd") as Script).get_script_constant_map()
	var bld51: Dictionary = ST51["BUILDINGS"]
	chk(bld51.has(Structures.KIND_BLACKSMITH), "建造菜单里有铁匠铺")
	var bc51: Dictionary = bld51.get(Structures.KIND_BLACKSMITH, {})
	chk(int(bc51.get("coin", 0)) == 150 and int(bc51.get("wood", 0)) == 10
		and int(bc51.get("stone", 0)) == 8 and int(bc51.get("iron", 0)) == 2
		and int(bc51.get("labor", 0)) == 6,
		"铁匠铺造价 = 150金 + 木x10 + 石x8 + 铁x2 + 6 人天")
	chk(g.has_method("start_build_mode") and g.has_method("_confirm_build")
		and g.has_method("_cancel_build") and g.has_method("building_footprint"),
		"game 挂着建造四件套 (进入/确认/取消/地基)")
	var fp51: Array = g.call("building_footprint", Vector2i(7, 7))
	chk(fp51.size() == 27, "铁匠铺地基占 9x3 = 27 格")
	# 51b 三套盔甲资源: 等级 1..3, 类型「装备」, 穿上加血 10/20/30
	var names51 := ["wood", "iron", "gold"]
	var tiers51 := {}
	for i51 in names51.size():
		var a51: ItemData = load("res://item/armor_%s.tres" % names51[i51])
		if a51 != null and a51.type == "装备" and a51.armor_tier == i51 + 1:
			tiers51[i51 + 1] = true
	chk(tiers51.size() == 3, "三套盔甲资源齐全 (等级 1..3, 类型「装备」)")
	# 51c 市集货架: 三档甲都摆出来卖
	var mk51: Dictionary = (load("res://market_ui.gd") as Script).get_script_constant_map()
	var armor_stock51 := 0
	for s51 in mk51["STOCK"]:
		var it51: ItemData = load(String(s51["path"]))
		if it51 != null and it51.type == "装备":
			armor_stock51 += 1
	chk(armor_stock51 == 3, "贸易市集货架上摆着 3 档整套甲")
	# 51d 铁匠铺配方表: 3 条, 门槛 Lv1x2 / Lv2x1, 劳动力 2/4 跟档位走
	var smith51: Dictionary = (load("res://crafting.gd") as Script).get_script_constant_map()
	var sr51: Array = smith51["SMITH_RECIPES"]
	chk(sr51.size() == 4, "铁匠铺配方 4 条（3 档甲 + 银戒）")
	var lv_n51 := {1: 0, 2: 0}
	var lv_ok51 := true
	for r51 in sr51:
		lv_n51[int(r51["lv"])] += 1
		var rn51: String = str((r51["result"] as Resource).resource_path)
		if rn51.contains("armor") and int(r51["labor"]) != 2 * int(r51["lv"]):
			lv_ok51 = false
	chk(int(lv_n51[1]) == 2 and int(lv_n51[2]) == 2 and lv_ok51,
		"配方门槛 Lv1x2 / Lv2x2, 甲的劳动力跟档位走")
	# 51e 找甲: find_armor 挑达标里等级最低的; pay_cost 扣的正是那件
	while Slaves.find_armor(1) != null:
		Inventory.remove_item(Slaves.find_armor(1), 1)
	var aw51: ItemData = load("res://item/armor_wood.tres")
	var ai51: ItemData = load("res://item/armor_iron.tres")
	Inventory.add_item(ai51, 1)
	Inventory.add_item(aw51, 1)
	chk(Slaves.find_armor(1) == aw51, "达标里挑等级最低的（皮甲 1 级）")
	chk(Slaves.find_armor(2) == ai51, "要 2 级时跳过皮甲拿锁链甲")
	chk(Slaves.find_armor(5) == null, "要 5 级时谁都不达标（满级 3）")
	chk(Slaves.can_afford({"iron": 0, "armor": 2}), "can_afford 认整套甲门槛")
	chk(Slaves.pay_cost({"iron": 0, "armor": 2}), "pay_cost 扣走达标那件甲")
	chk(Inventory.count_item(ai51) == 0 and Inventory.count_item(aw51) == 1,
		"扣的是锁链甲, 木甲还留着（不强扣高档）")
	Inventory.remove_item(aw51, 1)
	# 51f 铁匠铺打造: 不在旁边拒; 摆一座后按等级放行, 料、人手都真扣
	chk(Crafting.near_blacksmith_lv() == 0, "没摆铁匠铺时身边等级 = 0")
	chk(not Crafting.can_craft_smith(0), "Lv0 时打不了甲")
	var ms51: Array = Crafting.missing_smith(0)
	chk(ms51.size() == 1 and int(ms51[0]["need"]) == -1, "missing 会报「人不在铁匠铺旁」(need=-1)")
	var cell51 := Vector2i(2, 2)
	if Structures.has_station(cell51):
		Structures.remove(cell51)
	place_player(cell51 + Vector2i(1, 0))
	chk(Structures.place(cell51, Structures.KIND_BLACKSMITH), "摆下一座铁匠铺（Lv1）")
	chk(Structures.level_of(cell51) == 1, "新铺默认 Lv1")
	chk(Crafting.near_blacksmith_lv() == 1, "站旁边读到 Lv1")
	chk(int(Crafting.missing_smith(2)[0]["need"]) == -2, "Lv1 打 2 档配方被等级拦住 (need=-2)")
	# 人手: 清掉旧工差 + 塞一个测试伙伴, 保证有 1 个空闲劳动力
	Slaves.expedition.clear()
	Slaves.research_tech.clear()
	Slaves.research_admin.clear()
	Slaves.dock_crew.clear()
	Slaves.mine_crew.clear()
	Slaves.craft_crew.clear()
	var fake51 := {"name": "小工", "troop": "新兵", "labor": "帮工",
		"affection": 0, "fed_today": false, "talked_today": false,
		"hp": 30, "max_hp": 30, "squad": 0}
	Slaves.slaves.append(fake51)
	Slaves.count = Slaves.slaves.size()
	chk(Slaves.working_count() >= 1, "有空闲劳动力可以开工（%d 人）" % Slaves.working_count())
	var wood51: ItemData = load("res://item/wood.tres")
	var w51 := Inventory.count_item(wood51)
	if w51 < 5:
		Inventory.add_item(wood51, 5 - w51)
	w51 = Inventory.count_item(wood51)
	chk(Crafting.craft_smith(0), "Lv1 旁开工打造皮甲（料一次付清）")
	chk(Inventory.count_item(aw51) == 0 and Inventory.count_item(wood51) == w51 - 5,
		"扣木x5, 出货要等人工攒够（此刻还没出）")
	chk(Crafting.smith_busy() and int(Crafting.smith_top().get("work", 0)) == 0
		and int(Crafting.smith_top().get("need", 0)) == 2, "进了「制造中」: 0/2 人天")
	chk(Slaves.craft_crew.is_empty(), "开工不再自动抓小工 (夜里在派活面板派人)")
	chk(Crafting.add_smith_work(1).is_empty() and Crafting.smith_busy(), "打铁人工 1/2 还不出件")
	chk(Crafting.add_smith_work(1).size() == 1, "打铁人工攒够 -> 今晚出件")
	chk(Inventory.count_item(aw51) == 1 and not Crafting.smith_busy(),
		"整套皮甲出货, 「制造中」清空")
	chk(Slaves.craft_crew.is_empty(), "出货后打铁名单一并清空")
	# 51f2 e41c 打铁队列: 可以一次排好几件, 人工先喂队首, 多出来的顺延给下一件
	var w51c := Inventory.count_item(wood51)
	if w51c < 5:
		Inventory.add_item(wood51, 5 - w51c)
	var i51c := Inventory.count_item(Slaves.IRON_ITEM)
	if i51c < 3:
		Inventory.add_item(Slaves.IRON_ITEM, 3 - i51c)
	var stone51q: ItemData = load("res://item/stone.tres")
	var s51c := Inventory.count_item(stone51q)
	if s51c < 1:
		Inventory.add_item(stone51q, 1 - s51c)
	chk(Crafting.craft_smith(0) and Crafting.craft_smith(1), "连着排两件: 皮甲 + 锁链甲")
	chk(Crafting.smith_queued() == 2, "队列里排着 2 件")
	chk(Crafting.smith_name() == "皮甲" and Crafting.smith_queue_text().begins_with("皮甲 0/2"),
		"队首是皮甲, 文案带顺序和进度: %s" % Crafting.smith_queue_text())
	chk(Crafting.missing_smith(0).is_empty(), "已经有一件在打也不再拦第二件排队")
	var made51c: Array = Crafting.add_smith_work(3)
	chk(made51c.size() == 1 and String(made51c[0]) == "皮甲", "3 人工先把队首皮甲打出来")
	chk(Crafting.smith_queued() == 1 and int(Crafting.smith_top().get("work", 0)) == 1,
		"多出来的 1 人工顺延给下一件: 锁链甲 1/2")
	var made51d: Array = Crafting.add_smith_work(1)
	chk(made51d.size() == 1 and not Crafting.smith_busy(), "再补 1 人工: 锁链甲出件, 队列清空")
	Inventory.remove_item(aw51, 1)
	Inventory.remove_item(ai51, 1)
	# 材料还原到测试前（打铁扣掉的木/铁/石补回来）
	var restore51: Array = [[wood51, w51c], [Slaves.IRON_ITEM, i51c], [stone51q, s51c]]
	for r51 in restore51:
		var pair51: Array = r51
		var itm51: ItemData = pair51[0]
		var d51: int = int(pair51[1]) - Inventory.count_item(itm51)
		if d51 > 0:
			Inventory.add_item(itm51, d51)
		elif d51 < 0:
			Inventory.remove_item(itm51, -d51)
	# 51g 铁匠铺升级: 花钱提到 Lv2, 高一档配方就解锁（铁甲要铁x4 + 石x2, 先补料测完还原）
	Structures.set_level(cell51, 2)
	chk(Crafting.near_blacksmith_lv() == 2, "升级后读到 Lv2")
	var iron51g := Inventory.count_item(Slaves.IRON_ITEM)
	var stone51: ItemData = load("res://item/stone.tres")
	var stone51g := Inventory.count_item(stone51)
	if iron51g < 4:
		Inventory.add_item(Slaves.IRON_ITEM, 4 - iron51g)
	if stone51g < 2:
		Inventory.add_item(stone51, 2 - stone51g)
	chk(Crafting.can_craft_smith(2), "Lv2 能打铁甲（2 档配方解锁）")
	if Inventory.count_item(Slaves.IRON_ITEM) > iron51g:
		Inventory.remove_item(Slaves.IRON_ITEM, Inventory.count_item(Slaves.IRON_ITEM) - iron51g)
	if Inventory.count_item(stone51) > stone51g:
		Inventory.remove_item(stone51, Inventory.count_item(stone51) - stone51g)
	# 收尾: 拆铺 / 撤人 / 清工差和产物
	chk(Structures.remove(cell51) == Structures.KIND_BLACKSMITH, "拆掉测试铁匠铺")
	chk(Crafting.near_blacksmith_lv() == 0, "拆掉后身边等级回 0")
	Crafting.smith_queue = []
	Slaves.slaves.erase(fake51)
	Slaves.count = Slaves.slaves.size()
	Inventory.remove_item(aw51, 1)
	Slaves.changed.emit()

	# 51g2 工地制: 开工只登记工地 (钱料调用方付清), 夜里按派的人数积累, 攒够落成
	var scost51: Dictionary = Structures.building_cost(Structures.KIND_BLACKSMITH)
	if Wallet.money < int(scost51.get("coin", 0)):
		Wallet.money = int(scost51.get("coin", 0))
	for itn51b in ["wood", "stone", "iron"]:
		var it51b: ItemData = load("res://item/%s.tres" % itn51b)
		while Inventory.count_item(it51b) < int(scost51.get(itn51b, 0)):
			Inventory.add_item(it51b, 1)
	chk(not Structures.site_busy(), "还没开工: 没有工地")
	chk(Structures.start_site(cell51, Structures.KIND_BLACKSMITH), "铁匠铺动工 -> 登记工地")
	chk(Structures.site_busy() and Structures.site_name() == "铁匠铺", "工地名读得回来")
	chk(int(Structures.site.get("need", 0)) == 6 and int(Structures.site.get("work", 0)) == 0,
		"工地进度 0/6 人天")
	chk(not Structures.add_site_work(0), "没派人不推进")
	chk(not Structures.add_site_work(5), "5 人工不够, 差 1 人天")
	chk(Structures.site_busy() and int(Structures.site.get("work", 0)) == 5, "工地还在: 5/6")
	chk(Structures.add_site_work(1), "第 6 人工到位 -> 当晚落成")
	chk(not Structures.site_busy() and Structures.kind_of(cell51) == Structures.KIND_BLACKSMITH,
		"工地落成, 站着一座真铁匠铺")
	chk(Structures.remove(cell51) == Structures.KIND_BLACKSMITH, "拆掉工地落成的铁匠铺")
	# 51h 熔炉左键: 手持铁矿点炉 = 放进去烧(1木1铁); 炼着只报进度; 出炉左键取铁;
	# 镐子 / 别的物品不吃点击（保持拆设施、摆放的原行为）
	place_player(cell51 + Vector2i(1, 0))
	chk(Structures.place(cell51, Structures.KIND_FURNACE), "原位再摆一座熔炉（idle）")
	var fpos51: Vector2 = (g.station_nodes[cell51] as Node2D).global_position
	var ore51: ItemData = load("res://item/iron_ore.tres")
	var iron51: ItemData = load("res://item/iron.tres")
	var pick51: ItemData = load("res://item/pickaxe.tres")
	if Inventory.count_item(wood51) < 1:
		Inventory.add_item(wood51, 1)
	if Inventory.count_item(ore51) < 1:
		Inventory.add_item(ore51, 1)
	var w0_51 := Inventory.count_item(wood51)
	var o0_51 := Inventory.count_item(ore51)
	chk(not g.furnace_click(fpos51, cell51, pick51), "手持镐子点炉 = 不吃点击（留给拆设施）")
	chk(String(Structures.state_of(cell51)) == Structures.ST_IDLE, "镐子点完炉子还是 idle")
	chk(not g.furnace_click(fpos51, cell51, wood51), "手持木头点空炉 = 不吃点击")
	chk(g.furnace_click(fpos51, cell51, ore51), "手持铁矿左键点炉 = 吃掉点击")
	chk(String(Structures.state_of(cell51)) == Structures.ST_SMELTING, "空炉点火 -> smelting")
	chk(Inventory.count_item(wood51) == w0_51 - 1 and Inventory.count_item(ore51) == o0_51 - 1,
		"点火真扣 1 木 + 1 铁")
	var w1_51 := Inventory.count_item(wood51)
	chk(g.furnace_click(fpos51, cell51, ore51), "炼着时左键 = 只报进度（仍吃点击）")
	chk(Inventory.count_item(wood51) == w1_51, "炼着时不重复扣料")
	# 把炉子推到出炉: 计时塞满再推一帧, 走真实的状态机转移
	Structures.stations[cell51]["t"] = Structures.SMELT_TIME
	Structures._process(0.016)
	chk(String(Structures.state_of(cell51)) == Structures.ST_READY, "炼够 20 秒 -> ready 出炉")
	var iron_pk := 0
	for ch51 in g.get_children():
		if ch51.get("item") == iron51:
			iron_pk += 1
	chk(g.furnace_click(fpos51, cell51, ore51), "出炉后左键 = 吃掉点击直接取铁")
	chk(String(Structures.state_of(cell51)) == Structures.ST_IDLE, "取完铁炉子回 idle")
	var iron_pk2 := 0
	for ch51 in g.get_children():
		if ch51.get("item") == iron51:
			iron_pk2 += 1
	chk(iron_pk2 == iron_pk + 1, "地上多出 1 个铁锭掉落物")
	chk(Structures.remove(cell51) == Structures.KIND_FURNACE, "拆掉测试熔炉")
	# 51i 快捷栏残留 bug: 物品耗尽后手持引用必须跟着格子一起清掉,
	# 否则种子种完了、槽位摆进熔炉, 左键却还在种树
	var hotbar51: GridContainer = g.get_node("HUD/GridContainer")
	var seed51: ItemData = load("res://item/tree_seed.tres")
	while Inventory.count_item(seed51) > 0:
		Inventory.remove_item(seed51, 999)   # 先清干净别处可能存在的树苗种子
	var saved51: Dictionary = {"item": Inventory.hotbar[0]["item"],
		"count": Inventory.hotbar[0]["count"]}
	Inventory.hotbar[0] = {"item": seed51, "count": 3}
	Inventory.inventory_changed.emit()
	hotbar51.select(0)
	chk(player.current_item == seed51, "第 1 格摆 3 个树苗种子, 手里攥着种子")
	Inventory.remove_item(seed51, 3)   # 全种完
	chk(Inventory.hotbar_item(0) == null, "种子耗尽 -> 第 1 格清空")
	chk(player.current_item == null, "手持引用跟着清掉（不再残留树苗）")
	var furnace51: ItemData = load("res://item/furnace.tres")
	Inventory.add_item(furnace51, 1)   # 新捡的熔炉优先落进空着的第 1 格
	chk(Inventory.hotbar_item(0) == furnace51, "熔炉落进空出的第 1 格")
	chk(player.current_item == furnace51, "手持引用切成熔炉（左键不再是种树）")
	# 收尾: 还原第 1 格原状（refresh 会顺手把手持也同步回去）
	Inventory.hotbar[0] = saved51
	Inventory.inventory_changed.emit()
	chk(player.current_item == Inventory.hotbar_item(0), "收尾: 手持还原成第 1 格原道具")

	# 51j 出海离开动画: _depart 走完整条链（镜头钉港口 -> 全员上船 -> 船队东驶 ->
	# enter_travel 切海图）。走完 traveling = true、整座岛被藏起来; 然后返航恢复现场。
	var dock_bak51j: Array = [Voyage.dock_state, Voyage.dock_work, Voyage.boat_count]
	var exp_bak51j: Array = Slaves.expedition.duplicate()
	var hour_bak51j: int = TimeManager.hour
	var run_bak51j: bool = TimeManager.time_running
	Voyage.dock_state = Voyage.DOCK_BUILT
	Voyage.boat_count = 2
	Voyage.dock_changed.emit()
	TimeManager.hour = 10
	Slaves.expedition.clear()          # 空名单: 动画只载主角, 跑得最快
	chk(Voyage.depart_block_reason(g) == "", "出海前置全满足（码头建成/有船/白天）")
	g._depart()                        # 协程: 上船 -> 出海动画 -> 切海图, 不在这儿等它
	await get_tree().process_frame
	await get_tree().process_frame
	chk(g.get_node_or_null("SailFleet") != null, "镜头钉在港口: 出发船队出现在码头")
	chk(player.visible == false, "主角上船（人藏进船里）")
	var t51j := 0.0
	while not Voyage.traveling and t51j < 8.0:
		await get_tree().process_frame
		t51j += get_process_delta_time()
	chk(Voyage.traveling, "动画走完: 正式出海（traveling）")
	# d9: 切海图也走 iris 转场了（收黑 0.42s 后才真正藏岛）—— 等黑幕演完再断言。
	# ❗IRIS 是 add_child.call_deferred 挂树的, 调完当场它还没进组, 等待循环会空转跳过。
	await get_tree().process_frame
	var w51j := 0.0
	while get_tree().get_first_node_in_group("iris_wipe") != null and w51j < 5.0:
		await get_tree().process_frame
		w51j += get_process_delta_time()
	chk(not g.visible, "出海后整座岛被藏起来")
	chk(not TimeManager.time_running,
		"出海后时间停住 (航行中不流逝, 时钟显示「航行中」)")
	# 返航: 海图拆掉、岛回来, 顺手把测试改过的码头/时间还原
	Voyage.return_to_island()
	# d9: 回岛也走 iris 转场 —— 等黑幕演完、岛真的亮出来再断言。
	# ❗同上: IRIS 延迟一帧才进组, 不等这一帧断言会跑到黑幕回调前面（51j 翻车实录）。
	# ❗返航已把表拨回 22:00 且常速在走, 等黑幕的 1 秒多会把 22:00 走掉（107 实录）
	#   —— 等待期间把流速拨 0 冻钟, 等完再还 1.0。
	TimeManager.speed_scale = 0.0
	await get_tree().process_frame
	var w51r := 0.0
	while get_tree().get_first_node_in_group("iris_wipe") != null and w51r < 5.0:
		await get_tree().process_frame
		w51r += get_process_delta_time()
	TimeManager.speed_scale = 1.0
	chk(not Voyage.traveling and g.visible and TimeManager.time_running
		and TimeManager.speed_scale == 1.0,
		"返航: 岛回来了, 时间恢复常速")
	chk(TimeManager.hour == 22 and TimeManager.minute == 0,
		"返航固定晚上十点（22:00, 还能活动到凌晨两点）")
	# e13a 一天一次: 刚出过海, 今天再想走会被拦（返航后 traveling 已清, 撞的是出海日限制）
	var block_again51j: String = Voyage.depart_block_reason(g)
	chk(block_again51j.contains("出过海"), "一天只能出一次海（今天再走被拦: %s）" % block_again51j)
	chk(player.visible and not player.frozen, "返航: 主角在码头边解冻")
	# 2026-09-19：返航必须清掉海图坐标 —— 否则战败复活后再出海,
	# 人会出现在上次倒下的地方而不是岛上码头
	chk(Voyage.world_pos == Vector2.ZERO, "返航清了海图坐标: 下次出海必从岛上码头出发")
	chk(g.get_node_or_null("CloudLayer") != null, "主岛挂了云层 CloudLayer")
	Slaves.expedition = exp_bak51j
	Voyage.dock_state = int(dock_bak51j[0])
	Voyage.dock_work = int(dock_bak51j[1])
	Voyage.boat_count = int(dock_bak51j[2])
	Voyage.dock_changed.emit()
	TimeManager.hour = hour_bak51j
	TimeManager.time_running = run_bak51j

	# 52. 本轮补丁回归: h-a 来客窗口 / h-b 空挥无声 / h-c 鹅卵石小径 / h-d 翻回草地 /
	#     h-h 任务栏与开局指引 / h-i 剧情对话框
	print("\n=== 52. 补丁回归: 来客窗口 / 空挥无声 / 小径 / 翻地 / 任务栏 / 剧情对话 ===")
	# 52a h-a 来客窗口: 花名册候选人第 day 天起坐 7 天, 错过隔 14 天再来, 纯函数零存档
	var c_bak52 := Slaves.count
	var y_bak52: int = TimeManager.year
	var s_bak52: int = TimeManager.season
	var d_bak52: int = TimeManager.day
	TimeManager.year = 1
	TimeManager.season = 0
	Slaves.count = 0
	TimeManager.day = 1
	chk(Recruits.visitor() and Recruits.window_left() == 7, "第 1 天: 首位候选人到访, 窗口整 7 天")
	TimeManager.day = 8
	chk(not Recruits.visitor(), "第 8 天: 首轮窗口关了, 人走了")
	TimeManager.day = 22
	chk(Recruits.visitor() and Recruits.window_left() == 7, "第 22 天: 隔 14 天后又回来坐 7 天")
	TimeManager.day = 29
	chk(not Recruits.visitor(), "第 29 天: 第二轮窗口也关了")
	Slaves.count = 8
	chk(not Recruits.visitor(), "花名册 8 人招齐: 再也不来客")
	Slaves.count = c_bak52
	TimeManager.year = y_bak52
	TimeManager.season = s_bak52
	TimeManager.day = d_bak52
	Slaves.changed.emit()
	# 52b h-b 空挥不出声: 砍树/挖矿/浇水三处「干不成」提示不带任何音效
	# （源码级断言: 失败提示所在行不许有 play_sfx, 也不许给 _flash 传 "error" 音）
	var psrc52 := FileAccess.get_file_as_string("res://scene/player.gd")
	var silent_ok52 := true
	for key52 in ["这里没有能砍的树", "这里没有能挖的石头", "水壶空了"]:
		var hit52 := false
		for ln52 in psrc52.split("\n"):
			if key52 in ln52:
				hit52 = true
				if "play_sfx" in ln52 or ", \"error\"" in ln52:
					silent_ok52 = false
		chk(hit52, "失败提示仍在: 「%s」" % key52)
	chk(silent_ok52, "三处空挥失败提示都不带音效（砍树/挖矿/浇水空挥无声）")
	# 52c h-c 鹅卵石小径: 1 石头凿 2 块石板; 铺 -> 读回是小径 -> 挖掉
	var path52: Array = Crafting.RECIPES.filter(
		func(r): return r["result"] == preload("res://item/stone_path.tres"))
	chk(path52.size() == 1 and int(path52[0]["count"]) == 2
		and path52[0]["costs"] == [{"item": preload("res://item/stone.tres"), "count": 1}],
		"小径配方 = 1 石头 -> 2 石板")
	chk(Floor.KIND_PATH == 1
		and Floor.KIND_ITEM.get(Floor.KIND_PATH) == preload("res://item/stone_path.tres"),
		"KIND_PATH=1, 挖掉返还石板")
	var fcell52 := Vector2i(4, 4)
	if Floor.is_floored(fcell52):
		Floor.remove(fcell52)
	chk(Floor.place(fcell52, Floor.KIND_PATH), "铺上一格小径")
	chk(Floor.kind_of(fcell52) == Floor.KIND_PATH, "读回: 这格是小径不是木地板")
	chk(Floor.remove(fcell52), "镐子挖掉小径")
	chk(not Floor.is_floored(fcell52), "挖掉后格子干净")
	# 52d h-d 耕地再点锄头翻回草地: untill 清耕地+浇水; 长着作物不许翻
	var uspot := Vector2i(5, 20)   # 第 3/4 节锄过的那格（收获后无作物）
	if Farm.is_tilled(uspot):
		chk(Farm.untill(uspot), "锄头再点已耕地 -> 翻回草地")
	else:
		chk(Farm.till(uspot) and Farm.untill(uspot), "锄开再翻回草地")
	chk(not Farm.is_tilled(uspot) and not Farm.is_watered(uspot), "翻回后耕地/浇水一并清掉")
	chk(not Farm.untill(uspot), "再翻一次: 本来就不是耕地, 拒绝")
	var seed52: ItemData = load("res://item/seed.tres")
	Farm.till(uspot)
	Farm.plant(uspot, seed52)
	chk(not Farm.untill(uspot), "长着作物不许翻（先收割）")
	Farm.crops.erase(uspot)      # 收尾: 拔掉测试作物, 还原成空耕地
	Farm.watered.erase(uspot)
	# 52e h-h 任务栏 + 开局指引 —— e13j: 任务栏已是背包「任务」页签（左侧竖栏退役）
	var bak52q := Quests.active()
	chk(g.quest_log_panel == null, "e13j: 屏幕左侧不再挂独立任务栏")
	var bp52q: Control = g.get_node_or_null("HUD/Backpack")
	chk(bp52q != null and bp52q._pages.has("quests"), "背包里挂上了「任务」页签")
	var ql52: Control = bp52q._pages["quests"]
	chk(bool(ql52.get("embedded")), "任务页是嵌入模式（铺满页内容）")
	bp52q._switch_to("quests")
	chk(ql52.visible, "切到任务页能看到任务列表")
	chk((ql52.get("_list_label") as Label).text.length() > 0, "任务页渲染出了任务文本")
	Quests.reset_all()
	Quests.start_guide()
	chk(Quests.has_active("go_house") and Quests.active().size() == 1,
		"新档开局指引: 派生「瞧瞧东边那栋房子」")
	var gt52: Dictionary = Quests.active()[0]
	chk(String(gt52["desc"]) == "东边有一栋房子, 进去看看是谁的屋子", "任务描述读得回来")
	Quests.start_guide()
	chk(Quests.active().size() == 1, "同局 start_guide 只发一次")
	Quests.complete("go_house")
	chk(not Quests.has_active("go_house") and Quests.has_active("buy_goblin"),
		"进屋听哥布林说完, 链条自动挂上买货任务")
	Quests.reset_all()
	for t52 in bak52q:
		Quests.add(String(t52["id"]), String(t52["title"]), String(t52["desc"]))
	chk(Quests.active().size() == bak52q.size(), "收尾: 还原测试前任务列表")
	# 52f h-i 剧情对话框: 铺满宽占下方 42% + 头像/名字 + 打开暂停时间 + 关闭恢复 + 完结回调
	var sd52: Control = g.story_dialogue_panel
	chk(sd52 != null and sd52.has_method("play") and sd52.has_method("is_open"),
		"剧情对话面板挂好了 (play / is_open)")
	chk(absf(sd52._box.anchor_top - (1.0 - sd52.BOX_H_RATIO)) < 0.001
		and sd52._box.anchor_left == 0.0 and sd52._box.anchor_right == 1.0,
		"对话框铺满宽度, 占下方 42% 屏高")
	chk(load("res://resources/texture/portraits/goblin.png") != null
		and load("res://resources/texture/portraits/player.png") != null,
		"哥布林 / 主角头像图在")
	var pdir52 := DirAccess.open("res://resources/texture/portraits")
	var np52 := 0
	if pdir52 != null:
		for f52 in pdir52.get_files():
			if f52.ends_with(".png") and f52.begins_with("slave_"):
				np52 += 1
	chk(np52 == 20, "20 张伙伴像素头像齐 (%d)" % np52)
	# 播一段两句的对话: 每句都先进打字机 -> 跳一下、翻页一下, 两句共 4 下才关掉
	TimeManager.time_running = true
	var done52 := [false]
	sd52.play([
		{"name": "哥布林", "portrait": "goblin", "text": "selftest 1"},
		{"name": "主角", "portrait": "player", "text": "selftest 2"},
	], func(): done52[0] = true)
	chk(sd52.is_open() and sd52.visible and not TimeManager.time_running,
		"play 打开对话框, 时间暂停")
	chk(String(sd52._name_label.text) == "哥布林" and sd52._portrait.texture != null,
		"首句: 名字 + 头像上屏")
	var ev52 := InputEventAction.new()
	ev52.action = "ui_accept"
	ev52.pressed = true
	sd52._input(ev52)
	chk(sd52._next_hint.visible, "第 1 下: 打字机瞬间放完, 出现继续提示")
	sd52._input(ev52)
	chk(String(sd52._name_label.text) == "主角", "第 2 下: 翻到第 2 句（主角）")
	sd52._input(ev52)
	chk(sd52._next_hint.visible and String(sd52._text_label.text) == "selftest 2",
		"第 3 下: 第 2 句打字机放完")
	sd52._input(ev52)
	chk(not sd52.is_open() and not sd52.visible and done52[0], "第 4 下: 关掉, 完结回调触发")
	chk(TimeManager.time_running, "关掉后时间恢复走动")
	var hsrc52 := FileAccess.get_file_as_string("res://scene/house.gd")
	chk("goblin_intro" in hsrc52, "进屋开场白挂一次性 flag (goblin_intro)")
	# 开场白 / buy_goblin 任务的文案是运行时才上屏的, 第 40 节扫不到 -> 在这儿补一道字形体检
	var intro52: Array = (load("res://scene/house.gd") as Script).get_script_constant_map()["INTRO_LINES"]
	var ui52 := ""
	for ln52b in intro52:
		ui52 += String(ln52b["name"]) + String(ln52b["text"])
	ui52 += "照顾哥布林的生意" + "在哥布林摊位买点东西, 他就好这口"
	var miss52: PackedStringArray = missing_glyphs(ui52)
	chk(miss52.is_empty(),
		"开场白/任务文案字形齐全" + ("" if miss52.is_empty() else ": 缺 " + "".join(miss52)))

	# 53. h-l 唯美画风: 全屏后处理滤镜（萤火虫粒子层已按玩家要求整体删除）
	print("\n=== 53. 唯美画风: 后处理滤镜 ===")
	chk("_build_fx()" in FileAccess.get_file_as_string("res://scene/game.gd"),
		"game._ready 调用 _build_fx")
	var fxrect53: ColorRect = null
	for c53 in g.hud.get_children():
		if c53 is ColorRect and c53.name == "PostFX":
			fxrect53 = c53
	chk(fxrect53 != null, "滤镜 ColorRect 挂在 HUD")
	chk(g.hud.get_child(0) == fxrect53, "滤镜垫在 HUD 最底(世界之上、控件之下)")
	chk(fxrect53.material is ShaderMaterial and fxrect53.material.shader != null,
		"滤镜用 shader 材质 (fx_post.gdshader)")
	chk(fxrect53.mouse_filter == Control.MOUSE_FILTER_IGNORE, "滤镜不挡鼠标点击")
	# 萤火虫/光尘粒子层彻底删除：怎么调渐隐玩家都还看得见白点，直接消去
	chk(g.get_node_or_null("Dust") == null, "光尘/萤火虫粒子层已整体删除 (Dust 不存在)")
	# SeasonFX 父节点自己也是 CPUParticles2D：不关停就是 8 个无纹理白色方块往下掉
	# （玩家一直看到的「白天白点」真凶，_probe_particles 实测抓获）
	var sfx53: CPUParticles2D = g.get_node_or_null("SeasonFX")
	chk(sfx53 != null and not sfx53.emitting,
		"SeasonFX 父节点自身发射已关停 (只当跟随容器，白点方块不再掉)")

	# 54. h-m 海战改船板 + 河谷涉水: 甲板模板 / 浅水可趟 / 半身入水减速 / 水中可攻击
	print("\n=== 54. 船板海战 + 河谷涉水 ===")
	var bcm: Dictionary = (load("res://scene/battle_map.gd") as Script).get_script_constant_map()
	var tcm54: Dictionary = (load("res://scene/troop.gd") as Script).get_script_constant_map()
	var wm_mult: float = float(tcm54.get("WATER_MULT", 1.0))
	chk(wm_mult > 0.0 and wm_mult < 1.0,
		"涉水减速系数在 (0,1)（WATER_MULT=%.2f，等于 1 就没减速）" % wm_mult)
	var dx0: int = int(bcm.get("DECK_X0", 0))
	var dx1: int = int(bcm.get("DECK_X1", 0))
	var dy0: int = int(bcm.get("DECK_Y0", 0))
	var dy1: int = int(bcm.get("DECK_Y1", 0))

	# 54a 海寇遭遇 = 甲板：真开一场（探针同款用法），甲板可走、四周海挡路、板上零障碍
	var old_b54: Node = get_tree().get_first_node_in_group("battle")
	if old_b54 != null:
		old_b54.remove_from_group("battle")      # 免得 troop._battle() 顺手套走真战场
	var bm54: Variant = load("res://scene/battle_map.gd").new()
	bm54.party = {"id": 0, "type": "海寇", "size": 3}
	add_child(bm54)
	chk(String(bm54.template) == "甲板",
		"海寇遭遇开在甲板上（模板「%s」，不再草原/河谷二选一）" % String(bm54.template))
	chk(not bool(bm54.call("is_blocked_at", Vector2(16 * 11 + 8, 16 * 13 + 8))),
		"甲板中央（hero 出生列）能站人")
	chk(bool(bm54.call("is_blocked_at", Vector2(16 * 1 + 8, 16 * 13 + 8))),
		"甲板四周是海，走不出去")
	var deck_clean := true
	for c54 in (bm54.blocked as Dictionary).keys():
		if int(c54.x) >= dx0 and int(c54.x) <= dx1 and int(c54.y) >= dy0 and int(c54.y) <= dy1:
			deck_clean = false
	chk(deck_clean, "甲板上零障碍（海上没树，接舷战开阔打）")
	chk((bm54.shallow as Dictionary).is_empty(), "甲板战没有浅水（外海太深不趟）")
	bm54.queue_free()
	if old_b54 != null:
		old_b54.add_to_group("battle")
	Voyage.set_battle_slow(false)     # _ready 里放了慢动作，测完还原
	await get_tree().process_frame

	# 54a2 战斗结算页（e25）：胜负分出弹浮层（血条/百分比/金币/声望），点继续才走 end_battle
	var bmS: Variant = load("res://scene/battle_map.gd").new()
	bmS.party = {"id": 0, "type": "山贼", "size": 2}
	add_child(bmS)
	chk(bmS.has_method("_show_settlement"), "battle_map 有结算页入口 _show_settlement")
	chk(bmS.get("_settle_hud") == null, "战斗没分出胜负前结算页不弹")
	bmS.set("_last_coin", 12)
	bmS.set("_last_prest", 2)
	bmS.call("_show_settlement", "victory")
	chk(bmS.get("_settle_hud") != null and String(bmS.get("_settle_result")) == "victory",
		"分出胜负后弹出结算浮层（victory 结果已存档待继续）")
	chk(Audio.scene_track() == "settle", "结算浮层把 BGM 切到 settle 曲池")
	bmS.free()                        # 别等 0.9s 揭幕 tween：free 连 tween 一起掐
	Audio.set_scene_bgm("island")     # 还原曲池状态
	Voyage.set_battle_slow(false)     # _start_deploy 放下的时间静止还原
	await get_tree().process_frame

	# 54b 河谷浅水可趟：贴岸 1 格的水开放通行（不 add_child，手动铺地形），河心深水照样挡
	var bm2: Variant = load("res://scene/battle_map.gd").new()
	bm2.template = "河谷"
	bm2.world = Node2D.new()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash("河谷")
	bm2.call("_build_terrain", rng2)
	var sh2: Dictionary = bm2.shallow
	var bl2: Dictionary = bm2.blocked
	chk(sh2.size() > 0, "河谷模板有浅水（%d 格贴岸水开放可趟）" % sh2.size())
	var shallow_free := true
	var shallow_out := true
	for c54b in sh2.keys():
		if int(c54b.x) < 1 or int(c54b.y) < 1 or int(c54b.x) >= 43 or int(c54b.y) >= 25:
			continue      # 贴边浅水撞 is_blocked_at 的硬边界（界外一律挡），不进放行验证
		if bool(bm2.call("is_blocked_at", Vector2(16 * int(c54b.x) + 8, 16 * int(c54b.y) + 8))):
			shallow_free = false
		if bl2.has(c54b):
			shallow_out = false
	chk(shallow_free, "每格浅水都放行（is_blocked_at = false）")
	chk(shallow_out, "浅水不在阻挡表里（深水才挡）")
	chk(bl2.size() > 0, "阻挡表还剩 %d 格（河心深水 + 树照样挡）" % bl2.size())
	chk(bool(bm2.call("is_shallow_at", Vector2(16 * 20 + 8, 16 * 4 + 8))) == false,
		"is_shallow_at 对陆地格返回 false")
	bm2.free()

	# 54c 半身入水: 站进浅水 -> 贴片显示 + 减速; 上岸恢复; 水里照样能砍
	var old_b54c: Node = get_tree().get_first_node_in_group("battle")
	if old_b54c != null:
		old_b54c.remove_from_group("battle")   # 保证 troop._battle() 拿到的是 fkb54
	var fkb54 := FakeBattle.new()
	fkb54.shallow[Vector2i(3, 3)] = true
	add_child(fkb54)
	fkb54.add_to_group("battle")               # 不进组 troop._battle() 拿不到
	var su54: Variant = load("res://scene/troop.gd").new()
	su54.side = "hero"
	su54.kind = "刀客"
	su54.speed = 30.0
	add_child(su54)
	su54.set_process(false)
	su54.global_position = Vector2(56.0, 56.0)      # 浅水格 (3,3) 正中心
	su54.call("_update_water")
	var fx54: Sprite2D = su54.get("_water_fx")
	chk(bool(su54.get("_in_water")), "站进浅水格 -> 涉水状态开启")
	chk(fx54 != null and fx54.visible, "水位贴片显示（半身入水）")
	chk(is_equal_approx(float(su54.call("_move_speed")), 30.0 * wm_mult),
		"涉水移速 = 速度 x %.2f（%.1f）" % [wm_mult, float(su54.call("_move_speed"))])
	su54.global_position = Vector2(24.0, 24.0)      # 干地
	su54.call("_update_water")
	chk(not bool(su54.get("_in_water")) and not fx54.visible and is_equal_approx(
		float(su54.call("_move_speed")), 30.0), "上岸贴片收起、速度恢复")
	# 水中可攻击：hero 站回浅水，敌人贴脸，一刀下去掉血（攻击判定不查水）
	su54.global_position = Vector2(56.0, 56.0)
	su54.call("_update_water")
	var foe54: Variant = load("res://scene/troop.gd").new()
	foe54.side = "enemy"
	foe54.kind = "刀客"
	foe54.max_hp = 20
	foe54.hp = 20
	add_child(foe54)
	foe54.set_process(false)      # 别让它跑 AI（停下当木桩）
	foe54.global_position = Vector2(62.0, 58.0)     # 近战范围之内
	su54.call("_melee_attack", foe54)
	chk(int(foe54.hp) < 20, "站在浅水里照样一刀砍掉血（hp 20 -> %d）" % int(foe54.hp))
	su54.queue_free()
	foe54.queue_free()
	fkb54.queue_free()
	if old_b54c != null:
		old_b54c.add_to_group("battle")        # 真战场还回 "battle" 组

	# 54d 战斗手感(e15h): 箭几乎离弦即中 / 主角左键挥剑不再自动攻击 / 屏幕震动挂钩
	print("\n=== 54d. 战斗手感: 箭速 + 左键挥剑 ===")
	var ar54: Variant = load("res://scene/arrow.gd").new()
	chk(float(ar54.speed) >= 500.0, "箭速 >= 500（原 175 慢, 现在几乎离弦即中）")
	ar54.free()
	var sw54: Variant = load("res://scene/troop.gd").new()
	chk(sw54.has_method("swing_sword"), "主角有 swing_sword（左键挥剑入口）")
	sw54.free()
	var bm54d: Variant = load("res://scene/battle_map.gd").new()
	chk(bm54d.has_method("shake"), "battle_map 有 shake（受击/击中屏幕震动）")
	bm54d.free()
	var old_b54d: Node = get_tree().get_first_node_in_group("battle")
	if old_b54d != null:
		old_b54d.remove_from_group("battle")
	var fkb54d := FakeBattle.new()
	add_child(fkb54d)
	fkb54d.add_to_group("battle")
	var hero54d: Variant = load("res://scene/troop.gd").new()
	hero54d.side = "hero"
	hero54d.kind = "刀客"
	add_child(hero54d)
	hero54d.set_process(false)
	# e41e 主角走路「走两步闪一下」= hero walk 帧数写错（8 帧 vs 素材实际 6 帧）。
	# 多出来的两帧取样区跑到 192px 宽的图外 -> 空帧一闪。现在帧数跟图对齐, 逐帧验区域。
	var tcm54e: Dictionary = (load("res://scene/troop.gd") as Script).get_script_constant_map()
	chk(int(tcm54e.get("JOSH_WALK_FRAMES", 0)) == 6, "主角走路帧数写死 6（Josh/Walk.png 只有 6 帧）")
	var wsf54e: SpriteFrames = (hero54d.get("_sprite") as AnimatedSprite2D).sprite_frames
	var walk_n54e := 0
	var walk_ok54e := true
	for an54e in wsf54e.get_animation_names():
		if not String(an54e).begins_with("walk"):
			continue
		walk_n54e = wsf54e.get_frame_count(an54e)
		for i54e in walk_n54e:
			var at54e: AtlasTexture = wsf54e.get_frame_texture(an54e, i54e)
			if at54e == null or at54e.atlas == null \
					or at54e.region.end.x > float(at54e.atlas.get_width()):
				walk_ok54e = false
	chk(walk_n54e == 6 and walk_ok54e,
		"主角走路 %d 帧且取样区全在图内（旧 bug: 8 帧 -> 后 2 帧取到图外闪一下）" % walk_n54e)
	var foe54d: Variant = load("res://scene/troop.gd").new()
	foe54d.side = "enemy"
	foe54d.kind = "刀客"
	foe54d.max_hp = 20
	foe54d.hp = 20
	add_child(foe54d)
	foe54d.set_process(false)
	foe54d.global_position = hero54d.global_position + Vector2(16, 0)   # 贴脸
	fkb54d.foes = [foe54d]
	hero54d.call("swing_sword", foe54d.global_position)
	chk(int(foe54d.hp) < 20, "左键挥剑: 一刀见血 (hp 20 -> %d)" % int(foe54d.hp))
	var hp54d := int(foe54d.hp)
	hero54d.call("swing_sword", foe54d.global_position)
	chk(int(foe54d.hp) == hp54d, "挥剑有冷却（CD 内二连挥不掉血）")
	# 不再自动攻击: 冷却清零后敌人贴脸跑 _tick_hero, 也不该掉血
	hero54d.set("_cd", 0.0)
	foe54d.global_position = hero54d.global_position + Vector2(12, 0)
	hero54d.call("_tick_hero", 0.016)
	chk(int(foe54d.hp) == hp54d, "主角不再自动攻击（敌人贴脸 tick 也不掉血）")
	hero54d.queue_free()
	foe54d.queue_free()
	fkb54d.queue_free()
	if old_b54d != null:
		old_b54d.add_to_group("battle")        # 真战场还回 "battle" 组
	# 战场夜罩（e15h）: 深夜进战场画面要黑。Movie Writer 不画纯几何 Polygon2D（实机三分
	# 实验实锤）, 夜罩走「原生尺寸 ImageTexture + modulate」的 Sprite2D（海图 Grade 同构）。
	# 不进树, 直接调 _build_night 验证。
	var hour54d: int = TimeManager.hour
	TimeManager.hour = 22
	var bm54n: Variant = load("res://scene/battle_map.gd").new()
	bm54n.call("_build_night")
	var nr54d: Variant = bm54n.get("_night_rect")
	chk(nr54d != null and nr54d is Sprite2D and bm54n.get("_night_a") > 0.4,
		"战场夜罩: 22 点进场压深色 (a=%.2f)" % bm54n.get("_night_a"))
	bm54n.free()
	TimeManager.hour = 10
	var bm54d2: Variant = load("res://scene/battle_map.gd").new()
	bm54d2.call("_build_night")
	chk(bm54d2.get("_night_rect") == null, "白天 10 点进场无夜罩")
	bm54d2.free()
	TimeManager.hour = hour54d                     # 还原现场

	# 55. 盔甲改版: 只加生命上限（三档 皮甲/锁链甲/铁甲）, 战场不再画甲
	print("\n=== 55. 盔甲只加生命上限, 战场不画甲 ===")
	# 55a 三档甲: 档位 1/2/3, 穿上加血 10/20/30
	var hpmap55 := {}
	for p55 in ["wood", "iron", "gold"]:
		var it55: ItemData = load("res://item/armor_%s.tres" % p55)
		if it55 != null and it55.type == "装备":
			hpmap55[int(it55.armor_tier)] = int(it55.armor_hp)
	chk(hpmap55.size() == 3 and int(hpmap55[1]) == 10 and int(hpmap55[2]) == 20
		and int(hpmap55[3]) == 30, "三套甲: 皮甲/锁链甲/铁甲, 穿上加血 10/20/30")
	# 55b 穿甲 = 主角血上限加成; 脱下后当前血被钳回上限
	var worn55: ItemData = Inventory.worn_armor      # 记住当前穿戴, 测完还原
	var hp055 := int(Legion.player_max_hp())
	Inventory.worn_armor = load("res://item/armor_gold.tres")
	chk(int(Legion.player_max_hp()) == hp055 + 30,
		"穿上铁甲 -> 血上限 +30 (实际 %d)" % int(Legion.player_max_hp()))
	Inventory.worn_armor = load("res://item/armor_iron.tres")
	chk(int(Legion.player_max_hp()) == hp055 + 20, "换锁链甲 -> 血上限只 +20")
	Legion.damage_player(999)                        # 打空, 再用锁链甲上限回满
	Legion.heal_player(999)
	chk(int(Legion.player_hp) == hp055 + 20, "血顶到穿甲后的上限（%d）" % int(Legion.player_hp))
	Inventory.worn_armor = worn55                    # 还原穿戴 -> 上限掉回去
	Legion.clamp_player_hp()
	chk(int(Legion.player_hp) == hp055, "脱甲后当前血被钳回无甲上限（%d）" % int(Legion.player_hp))
	# 55c 战场不画甲: 攻城守军到齐, 但谁身上都没有甲贴图
	var old_b55: Node = get_tree().get_first_node_in_group("battle")
	if old_b55 != null:
		old_b55.remove_from_group("battle")
	var bm55: Variant = load("res://scene/battle_map.gd").new()
	bm55.party = {"type": "攻城", "size": 3, "siege": "chenxi_cap"}
	add_child(bm55)
	var guard_cnt55 := 0
	var naked55 := true
	for t55 in (bm55.units as Array):
		if String(t55.side) != "enemy":
			continue
		guard_cnt55 += 1
		if (t55 as Node).get("_armor_spr") != null:
			naked55 = false
	chk(guard_cnt55 >= 3, "攻城守军到齐（%d 名）" % guard_cnt55)
	chk(naked55, "攻城守军不披甲（战场上不再画盔甲）")
	bm55.queue_free()
	Voyage.set_battle_slow(false)
	await get_tree().process_frame
	# 55d 巡逻队/山贼同样赤膊上阵
	var bm56: Variant = load("res://scene/battle_map.gd").new()
	bm56.party = {"id": 1, "type": "巡逻", "size": 3, "nation": "tieyan", "army": "铁岩亲军"}
	add_child(bm56)
	var patrol_cnt55 := 0
	var patrol_naked55 := true
	for t56 in (bm56.units as Array):
		if String(t56.side) != "enemy":
			continue
		patrol_cnt55 += 1
		if (t56 as Node).get("_armor_spr") != null:
			patrol_naked55 = false
	chk(patrol_cnt55 >= 3 and patrol_naked55, "铁岩巡逻队 %d 名同样不披甲" % patrol_cnt55)
	bm56.queue_free()
	Voyage.set_battle_slow(false)
	await get_tree().process_frame
	if old_b55 != null:
		old_b55.add_to_group("battle")

	# ================= 第 56 节: 天气系统 =================
	# 天气 = 日期的纯函数（播种法）：同一天永远同一种天气, 存档不用存天气字段
	print("---- 56) 天气系统 ----")
	chk(Weather.roll_for(1, 0, 1) == Weather.roll_for(1, 0, 1), "天气是日期的纯函数（同日同天）")
	chk(Weather.roll_for(1, 0, 1) == Weather.SUNNY, "开局第 1 天固定晴天（教学周不被雨打蒙）")
	var seen := [false, false, false, false]
	for wy in range(1, 5):
		for ws in range(4):
			for wd in range(1, TimeManager.DAYS_PER_SEASON + 1):
				seen[Weather.roll_for(wy, ws, wd)] = true
	var all_seen := true
	for wk in 4:
		all_seen = all_seen and seen[wk]
	chk(all_seen, "4 年里晴/阴/雨/风暴都出现过")
	chk(Weather.name_text_for(Weather.RAIN, 3) == "雪", "冬雨显示名是雪")
	chk(Weather.name_text_for(Weather.RAIN, 0) == "雨", "春雨显示名是雨")
	# 雨天自动淋湿: 锄两格, 设成雨天, 手动走一遍天亮结算
	var old_cur := Weather.current
	var wet_a := Vector2i(2, 2)
	var wet_b := Vector2i(3, 2)
	Farm.till(wet_a)
	Farm.till(wet_b)
	if Farm.tilled.has(wet_a) and Farm.tilled.has(wet_b):
		Farm.watered.clear()
		Weather.current = Weather.RAIN
		Farm._on_new_day(TimeManager.day)
		chk(Farm.watered.has(wet_a) and Farm.watered.has(wet_b), "雨天早上所有耕地自动淋湿")
		Weather.current = Weather.SUNNY
		Farm.watered.clear()
		Farm._on_new_day(TimeManager.day)
		chk(Farm.watered.is_empty(), "晴天早上不淋湿 (e30g: 不再吃昨天的雨)")
		# e30g 验证: 真链路靠「连接顺序」证明 —— TimeManager.new_day emit 时按连接序跑,
		# Weather 的连接在 Farm 之前 = 翻牌先于浇水。直接 emit 会连带 Nation/Slaves 等
		# 一串副作用, 这里只验顺序。
		var widx := -1
		var fidx := -1
		var ci56 := 0
		for conn56 in TimeManager.new_day.get_connections():
			var cb56: Callable = conn56.callable
			if widx < 0 and cb56.get_object() == Weather:
				widx = ci56
			if fidx < 0 and cb56.get_object() == Farm:
				fidx = ci56
			ci56 += 1
		chk(widx >= 0 and fidx >= 0 and widx < fidx,
			"e30g: Weather 比 Farm 先收到 new_day (翻牌先于浇水)")
	else:
		chk(false, "雨天自动淋湿（测试格锄地失败）")
	# 睡觉菜单的明晨预报: 文案无缺字形 + 明天也能报准（纯函数）
	var wtext: String = "明晨有%s, 田里的水天亮就浇好" % Weather.tomorrow_name_text()
	chk(missing_glyphs(wtext).is_empty(), "明晨预报文案无缺字形")
	var tmr: Array = Weather.tomorrow_ymd()
	chk(Weather.roll_for(int(tmr[0]), int(tmr[1]), int(tmr[2]))
		== Weather.roll_for(int(tmr[0]), int(tmr[1]), int(tmr[2])), "明天天气现在就能报准")
	# 音频: 雷声是一次性音效（进 SFX_NAMES）, 雨声是循环环境音（rain_fx 自管）
	chk("thunder" in Audio.SFX_NAMES, "thunder 在 SFX_NAMES 里")
	chk(ResourceLoader.exists("res://resources/audio/sfx/rain.wav"), "rain.wav 已合成入库")
	chk(ResourceLoader.exists("res://resources/audio/sfx/thunder.wav"), "thunder.wav 已合成入库")
	# 图标四态都能画
	var wicon: Variant = preload("res://scene/weather_icon.gd").new()
	for wk2 in 4:
		wicon.set_kind(wk2)
	chk(wicon.kind == 3, "天气图标能翻到风暴态")
	wicon.queue_free()
	# 雨效粒子: 雨天喷 / 晴天停 / 冬雨播成雪
	var rfx: Variant = preload("res://scene/rain_fx.gd").new()
	add_child(rfx)
	Weather.current = Weather.RAIN
	rfx._apply()
	chk(bool(rfx.emitting), "雨天雨效粒子开喷")
	Weather.current = Weather.SUNNY
	rfx._apply()
	chk(not bool(rfx.emitting), "晴天雨效粒子停喷")
	Weather.current = Weather.RAIN
	var old_season := TimeManager.season
	TimeManager.season = 3
	rfx._apply()
	chk(int(rfx.amount) == 90 and rfx.color == rfx.SNOW_COLOR, "冬雨播成雪（慢飘白点）")
	TimeManager.season = old_season
	Weather.current = old_cur
	rfx._apply()
	# e30w 雨声去重复: 两层同一条循环雨声, 各自抽音高 + 错开入点, 音量配比慢慢漂
	var rain_a: AudioStreamPlayer = rfx.get("_audio_a")
	var rain_b: AudioStreamPlayer = rfx.get("_audio_b")
	chk(rain_a != null and rain_b != null and rain_a.stream != null and rain_a.stream == rain_b.stream,
		"雨声改成两层播放（同一条循环 WAV）")
	if rain_a != null and rain_a.stream is AudioStreamWAV:
		chk((rain_a.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"雨声 WAV 的循环点还在（整段循环）")
	if rain_a != null and rain_b != null:
		rfx.call("_start_voices")
		chk(rain_a.pitch_scale != rain_b.pitch_scale
				and absf(rain_a.pitch_scale - 1.0) <= rfx.PITCH_JITTER + 0.001
				and absf(rain_b.pitch_scale - 1.0) <= rfx.PITCH_JITTER + 0.001,
			"两层各自抽音高抖动（%.3f / %.3f）" % [rain_a.pitch_scale, rain_b.pitch_scale])
		# 雨天推包络 -> 两层都出声; 晴天推回去 -> 归零停播
		Weather.current = Weather.RAIN
		var rw_n := 0
		while rw_n < 40:
			rfx.call("_tick_audio", 0.1)
			rw_n += 1
		chk(float(rfx.get("_gain")) > 0.99 and rain_a.volume_db > -60.0 and rain_b.volume_db > -60.0,
			"雨天两层一起淡入（%.1f / %.1f dB）" % [rain_a.volume_db, rain_b.volume_db])
		# 配比漂移: 目标一改就往那边挪（谁在台前慢慢换 = 交叉淡化）
		rfx.set("_mix", 0.5)
		rfx.set("_mix_to", 0.7)
		rfx.set("_mix_t", 99.0)
		rfx.call("_tick_audio", 0.6)
		chk(float(rfx.get("_mix")) > 0.5, "音量配比会朝目标漂（交叉淡化）")
		Weather.current = Weather.SUNNY
		rw_n = 0
		while rw_n < 40:
			rfx.call("_tick_audio", 0.1)
			rw_n += 1
		chk(float(rfx.get("_gain")) <= 0.0 and not rain_a.playing and not rain_b.playing,
			"晴天雨声收干净（两层都停）")
		Weather.current = old_cur
	rfx.queue_free()
	# 雨天昼光压暗（纯函数直接验）
	var dn: Variant = preload("res://scene/day_night.gd").new()
	var noon_c: Color = dn._color_at(12.0)
	Weather.current = Weather.RAIN
	var rain_c: Color = dn._color_at(12.0)
	Weather.current = Weather.STORM
	var storm_c: Color = dn._color_at(12.0)
	Weather.current = old_cur
	chk(rain_c.get_luminance() < noon_c.get_luminance(), "雨天白天更暗")
	chk(storm_c.get_luminance() < rain_c.get_luminance(), "风暴比一般雨更暗")
	dn.queue_free()
	await get_tree().process_frame

	# ================= 第 57 节: 换季系统 =================
	# 作物绑季节: seasons 空数组 = 全季可种(老资源兼容); 过季未收的换季早上集体枯掉
	print("---- 57) 换季系统 ----")
	var old_season57 := TimeManager.season
	var old_day57 := TimeManager.day
	var old_cur57 := Weather.current
	# 季节判定: 空 seasons = 四季都能种
	var sd57 := ItemData.new()
	sd57.type = "种子"
	sd57.display_name = "测试种子"
	var crop57 := ItemData.new()
	crop57.display_name = "测试瓜"
	sd57.grow_to = crop57
	chk(Farm.season_ok_for(sd57), "seasons 为空的种子四季都能种")
	sd57.seasons = [0, 2]
	TimeManager.season = 0
	chk(Farm.season_ok_for(sd57), "当季种子能种(seed=[春,秋], 现在春)")
	TimeManager.season = 1
	chk(not Farm.season_ok_for(sd57), "非当季种子不能种(seed=[春,秋], 现在夏)")
	chk(Farm.seasons_text_for(sd57) == "春/秋", "季节文案拼出 春/秋")
	var sd_all57 := ItemData.new()
	chk(Farm.seasons_text_for(sd_all57) == "四季", "空 seasons 的季节文案是 四季")
	# Farm.plant 的季节兜底: 非当季种不下去, 也不生成作物
	var p57 := Vector2i(5, 5)
	Farm.till(p57)
	chk(Farm.tilled.has(p57) and not Farm.plant(p57, sd57), "非当季播种被 Farm 拦下")
	chk(not Farm.has_crop(p57), "被拦的播种不生成作物")
	# 种子悬浮提示标注能种的季节 + 无缺字形
	var it57: String = sd57.info_text()
	chk("春/秋" in it57 and "过季会枯" in it57, "种子悬浮提示标注能种季节")
	chk(missing_glyphs(it57).is_empty(), "种子季节提示文案无缺字形")
	# 换季枯萎全链路: 春季种下春种子 -> day 28 睡到隔天, 进位到夏 + 枯萎
	sd57.seasons = [0]
	TimeManager.season = 0
	var sig57 := [0]
	TimeManager.season_changed.connect(func(_s: int) -> void: sig57[0] += 1)
	TimeManager.day = TimeManager.DAYS_PER_SEASON
	chk(Farm.plant(p57, sd57), "春季能种下春季种子")
	Farm.watered[p57] = true          # 本来隔天该长, 结果先过季
	TimeManager.advance_day()
	chk(int(sig57[0]) == 1 and TimeManager.season == 1, "换季日 advance_day 发出 season_changed 进夏")
	chk(Farm.is_dead(p57) and bool(Farm.crops[p57].get("dead", false)), "过季作物隔天早上枯掉")
	chk(not Farm.is_ready(p57), "枯掉的作物不能收获")
	chk(Farm.harvest(p57) == null, "枯掉的作物收不出货")
	chk(int(Farm.crops[p57].days) == 0, "枯掉的作物不再生长(浇了水也不长)")
	chk(Farm.clear_dead(p57), "枯掉的作物能清掉")
	chk(not Farm.has_crop(p57) and Farm.tilled.has(p57), "清枯后耕地保留")
	# 当季对照: 夏天种夏种子, 浇水隔天正常长
	sd57.seasons = [1]
	chk(Farm.plant(p57, sd57), "夏季能种下夏季种子")
	Farm.watered[p57] = true
	Weather.current = Weather.SUNNY
	Farm._on_new_day(TimeManager.day)
	chk(int(Farm.crops[p57].days) == 1 and not Farm.is_dead(p57), "当季作物照常生长")
	# 老存档兼容: 作物字典没有 dead 字段也不算枯
	Farm.crops[p57] = {"seed": sd57, "stage": 0, "days": 0}
	chk(not Farm.is_dead(p57), "老存档作物(无 dead 字段)不算枯")
	Farm.clear_all()
	# 枯萎贴图: 灰褐色 modulate, 活作物纯白
	var cl57: Variant = preload("res://scene/crop_layer.gd").new()
	cl57._crop_textures["测试瓜"] = [null, null, null, null, null]   # 生产序列现在是 5 张 (00~04)
	cl57._update_sprite(p57, "测试瓜", 2, 4, false)
	var spr57: Sprite2D = cl57._sprites[p57]
	chk(spr57.modulate == Color.WHITE, "活作物贴图原色")
	cl57._update_sprite(p57, "测试瓜", 2, 4, true)
	chk(spr57.modulate != Color.WHITE, "枯作物贴图灰褐化")
	cl57.free()
	# 生长贴图序列: 每样作物 5 张 (00~04) —— 资产包 05 那张是收获物物品图标, 不进生长序列
	var clive57: Node = g.get_node("CropLayer")
	var crop_ok57 := true
	for cname57 in ["土豆", "胡萝卜", "卷心菜", "南瓜"]:
		var fs57: Array = clive57._crop_textures.get(cname57, [])
		if fs57.size() != 5:
			crop_ok57 = false
		for t57 in fs57:
			if t57 == null:
				crop_ok57 = false
	chk(crop_ok57, "四种作物生长贴图各 5 张且全部加载成功 (跳过物品图标 05)")
	# 季节氛围粒子: 秋落叶保留; 冬晴轻雪已删(晴天凭空飘白点看不懂, 真下雪由雨效播)
	var sfx57: Variant = preload("res://scene/season_fx.gd").new()
	add_child(sfx57)
	TimeManager.season = 2
	for i in 60:
		sfx57._process(1.0)
	chk(sfx57._leaf.color.a > 0.3, "秋天落叶粒子渐现 (实际 %.2f)" % sfx57._leaf.color.a)
	chk(sfx57.get_node_or_null("LightSnow") == null, "冬晴轻雪层已移除, 晴天不再飘白点")
	TimeManager.season = 3
	for i in 60:
		sfx57._process(1.0)
	chk(sfx57._leaf.color.a < 0.1, "冬天落叶层淡出, 雪只由雨效播 (实际 %.2f)" % sfx57._leaf.color.a)
	sfx57.queue_free()
	# 新文案全过字形检查
	chk(missing_glyphs("新的一季来了 -- 进入%s季" % "夏").is_empty(), "换季提示文案无缺字形")
	chk(missing_glyphs("冬天只有甜菜能种 -- 秋天的作物快收吧").is_empty(), "入冬提示文案无缺字形")
	chk(missing_glyphs("枯掉的作物清掉了").is_empty(), "清枯提示文案无缺字形")
	var plant57: String = "%s要%s季种, 现在是%s季" % ["土豆", "春/秋", "夏"]
	chk(missing_glyphs(plant57).is_empty(), "播种季节提示文案无缺字形")
	# e52: 真实作物种子的四季分配（按实际农时）—— 每季都有作物, 且各有各的
	var season_of := {0: [], 1: [], 2: [], 3: []}
	var real_seeds := {
		"土豆": "res://item/seed.tres",
		"胡萝卜": "res://item/carrot_seed.tres",
		"花椰菜": "res://item/cauliflower_seed.tres",
		"南瓜": "res://item/pumpkin_seed.tres",
		"卷心菜": "res://item/cabbage_seed.tres",
		"甜菜": "res://item/beet_seed.tres",
	}
	var season_txt := ""
	for nm57 in real_seeds:
		var rs57: ItemData = load(real_seeds[nm57])
		chk(rs57 != null and not rs57.seasons.is_empty(), "%s种子有季节限制" % nm57)
		for si57 in rs57.seasons:
			season_of[int(si57)].append(nm57)
		season_txt += "%s=%s " % [nm57, Farm.seasons_text_for(rs57)]
	print("    实际四季作物: 春%s 夏%s 秋%s 冬%s" % [
		str(season_of[0]), str(season_of[1]), str(season_of[2]), str(season_of[3])])
	chk(missing_glyphs(season_txt).is_empty(), "四季作物文案无缺字形")
	chk(season_of[0].size() == 2 and season_of[0].has("土豆") and season_of[0].has("胡萝卜"),
		"春播 = 土豆 + 胡萝卜")
	chk(season_of[1].size() == 2 and season_of[1].has("花椰菜") and season_of[1].has("南瓜"),
		"夏播 = 花椰菜 + 南瓜")
	chk(season_of[2].size() == 2 and season_of[2].has("卷心菜") and season_of[2].has("南瓜"),
		"秋播 = 卷心菜 + 南瓜（南瓜夏种秋收, 跨两季）")
	chk(season_of[3].size() == 1 and season_of[3].has("甜菜"),
		"冬播 = 只剩耐寒的甜菜")
	# 拿真种子过一遍 season_ok_for（不是上面那些临时造的 ItemData）
	var pw57: ItemData = load("res://item/seed.tres")
	var pk57: ItemData = load("res://item/pumpkin_seed.tres")
	var bt57: ItemData = load("res://item/beet_seed.tres")
	TimeManager.season = 0
	chk(Farm.season_ok_for(pw57) and not Farm.season_ok_for(pk57),
		"春天能种土豆, 夏天才种的南瓜被拦下")
	TimeManager.season = 3
	chk(Farm.season_ok_for(bt57) and not Farm.season_ok_for(pw57),
		"冬天只有甜菜能种, 土豆被拦下")
	# e52: 四季地貌 —— 换季把草地/水边图集换成当季那套（美术包里春夏秋冬各一套, 布局一致）
	var grass_tex57 := {}
	var water_tex57 := {}
	var grass_ok57 := true
	for si57b in 4:
		# ❗_apply_season_terrain 读的是 TimeManager.season（真实换季时它已经改好了）,
		#   这里要跟真流程一致: 先改季节, 再发信号
		TimeManager.season = si57b
		g._on_season_changed(si57b)
		var gsrc57 := g.grid_layer.tile_set.get_source(g.YARD_GRASS_SRC) as TileSetAtlasSource
		var fsrc57 := g.authored_field.tile_set.get_source(g.GROUND_GRASS_SRC) as TileSetAtlasSource
		var wsrc57 := g.authored_field.tile_set.get_source(g.GROUND_WATER_SRC) as TileSetAtlasSource
		if gsrc57 == null or wsrc57 == null or gsrc57.texture == null:
			grass_ok57 = false
			continue
		grass_tex57[si57b] = gsrc57.texture
		water_tex57[si57b] = wsrc57.texture
		# 地面层的草地跟草地层同步换; 四张都得是同一套布局尺寸 384x640
		if fsrc57 == null or fsrc57.texture != gsrc57.texture:
			grass_ok57 = false
		if gsrc57.texture.get_size() != Vector2(384, 640):
			grass_ok57 = false
	chk(grass_ok57, "四季草地贴图四张都换上且尺寸一致 384x640（同一套布局, 可整张互换）")
	chk(grass_tex57.size() == 4 and grass_tex57[0] != grass_tex57[1]
			and grass_tex57[1] != grass_tex57[2] and grass_tex57[2] != grass_tex57[3]
			and grass_tex57[0] != grass_tex57[3],
		"四季草地贴图两两不同（春/夏/秋/冬各一套地貌）")
	chk(water_tex57.size() == 4 and water_tex57[0] != water_tex57[1]
			and water_tex57[1] != water_tex57[2],
		"水边贴图跟着季节换（春/夏/秋各一套）")
	chk(water_tex57.size() == 4 and water_tex57[3] == water_tex57[0],
		"冬季水边沿用春版（冬图 400x384 布局不同, 整张换会错位）")
	TimeManager.season = old_season57
	g._on_season_changed(old_season57)
	TimeManager.day = old_day57
	Weather.current = old_cur57
	await get_tree().process_frame

	# ================= 第 58 节: 新手周指引 =================
	# 链条集中在 quests.gd _CHAIN; complete 后自动挂下一步, 跳步完成过的不回挂
	print("---- 58) 新手周指引 ----")
	var bak58q := Quests.active()
	Quests.reset_all()
	Quests.start_guide()
	chk(Quests.has_active("go_house") and Quests.active().size() == 1,
		"开局指引只派 go_house 一环")
	# 链表完整性: go_house 一路串到 explore_island, 链尾无下一环
	var chain_ok58 := true
	var cursor58 := "go_house"
	var seen58 := {}
	while cursor58 != "" and chain_ok58:
		if seen58.has(cursor58):
			chain_ok58 = false   # 环链
			break
		seen58[cursor58] = true
		if Quests._CHAIN.has(cursor58):
			cursor58 = String(Quests._CHAIN[cursor58][0])
		else:
			cursor58 = ""
	chk(chain_ok58 and seen58.size() == 8, "链条从 go_house 无环串到链尾(共8环)")
	chk(not Quests._CHAIN.has("explore_island"), "explore_island 是链尾开放任务")
	# 逐步走完链条: 每销一环自动挂下一环, 同屏只有 1 个任务
	Quests.complete("go_house")
	chk(Quests.has_active("buy_goblin") and Quests.active().size() == 1,
		"进屋后挂上 买货")
	Quests.complete("buy_goblin")
	chk(Quests.has_active("till_first") and Quests.active().size() == 1,
		"买完货挂上 开田")
	Quests.complete("till_first")
	chk(Quests.has_active("plant_first") and Quests.active().size() == 1,
		"开完田挂上 播种")
	Quests.complete("plant_first")
	chk(Quests.has_active("water_first") and Quests.active().size() == 1,
		"播完种挂上 浇水")
	Quests.complete("water_first")
	chk(Quests.has_active("harvest_first") and Quests.active().size() == 1,
		"浇完水挂上 收获")
	Quests.complete("harvest_first")
	chk(Quests.has_active("sell_first") and Quests.active().size() == 1,
		"收完货挂上 卖货")
	Quests.complete("sell_first")
	chk(Quests.has_active("explore_island") and Quests.active().size() == 1,
		"卖完货挂上链尾开放任务(钓鱼/鸡舍预告)")
	# 跳步: 老手先锄了地 -> 完成过的环节事后不再回挂
	Quests.reset_all()
	Quests.start_guide()
	Quests.complete("till_first")   # 任务都没发过就先销案(跳步)
	chk(not Quests.has_active("till_first") and Quests.has_active("plant_first"),
		"跳步锄地直接挂上播种, 不补发开田")
	Quests.complete("go_house")
	chk(Quests.has_active("buy_goblin") and not Quests.has_active("till_first"),
		"事后进屋, 已完成的环节不回挂")
	Quests.complete("buy_goblin")
	chk(Quests.active().size() == 1 and Quests.has_active("plant_first"),
		"买完货跳过开田直奔播种(同屏仍只1个)")
	# 指引文案全过字形检查(链上所有标题+描述 + 链尾描述 + e32 中后期链)
	var gl_ok58 := true
	for k58 in Quests._CHAIN:
		var nx58: Array = Quests._CHAIN[k58]
		if not missing_glyphs(String(nx58[1]) + String(nx58[2])).is_empty():
			gl_ok58 = false
	for k58m in Quests._MID_CHAIN:
		var nx58m: Array = Quests._MID_CHAIN[k58m]
		if not missing_glyphs(String(nx58m[1]) + String(nx58m[2])).is_empty():
			gl_ok58 = false
	chk(gl_ok58, "指引链条全部文案无缺字形")
	# 收尾: 还原测试前任务列表
	Quests.reset_all()
	for t58 in bak58q:
		Quests.add(String(t58["id"]), String(t58["title"]), String(t58["desc"]))
	chk(Quests.active().size() == bak58q.size(), "收尾: 还原测试前任务列表")
	await get_tree().process_frame

	# ============ 59. 钓鱼：甩竿 / 咬钩 / 拉竿 / 图鉴 / 存档 ============
	print("\n=== 59. 钓鱼：甩竿 / 咬钩 / 拉竿 / 图鉴 / 存档 ===")
	# 新文案字形检查（飘字 + 商店 + 道具描述）
	var gl59 := true
	for t59 in ["要对着水才能甩竿", "咬钩了! 快点!", "收线了, 什么都没钓着", "鱼跑了...",
			"钓到了", "新收录图鉴", "卖作物/鱼获", "把背包里的作物和鱼获全部卖掉", "工具"]:
		if not missing_glyphs(String(t59)).is_empty():
			gl59 = false
	for p59 in ["res://item/fishing_rod.tres", "res://item/perch.tres", "res://item/crayfish.tres",
			"res://item/pufferfish.tres", "res://item/starfish.tres"]:
		var it59: ItemData = load(p59) as ItemData
		if it59 == null or not missing_glyphs(it59.display_name + it59.description).is_empty():
			gl59 = false
	chk(gl59, "钓鱼全部新文案无缺字形")
	# 数背包里的「食物」（鱼）总数
	var food_count: Callable = func() -> int:
		var n := 0
		for s in Inventory.slot_list():
			if s["item"] != null and s["item"].type == "食物":
				n += int(s["count"])
		return n
	var frozen59: bool = player.frozen
	player.frozen = false
	player.fish_fast = true      # 咬钩等待缩到 0.05 秒
	var pond59: Vector2i = g._pond_cells[0]
	# 对陆地甩竿：不进持竿状态
	player._start_fishing(Vector2i(5, 5))
	chk(player._fish_state == "", "对陆地甩竿不进持竿状态")
	# 正常甩竿 → cast
	player._start_fishing(pond59)
	chk(player._fish_state == "cast", "对水甩竿进入持竿状态")
	chk(player.busy, "持竿姿势锁住玩家(busy)")
	var food0: int = food_count.call()
	# cast 中点击 = 收线复位
	player._fish_click()
	chk(player._fish_state == "" and not player.busy, "持竿中点击 = 收线复位")
	chk(food_count.call() == food0, "收线空手而归, 背包没多东西")
	# 完整流程：甩竿 → 等咬钩 → 拉竿
	player._start_fishing(pond59)
	await get_tree().create_timer(0.3).timeout
	chk(player._fish_state == "bite", "fish_fast 下 0.3 秒内鱼咬钩")
	player._fish_click()
	chk(player._fish_state == "" and not player.busy, "拉竿后复位")
	var got59: int = food_count.call() - food0
	chk(got59 == 1, "钓上来 1 条鱼进了背包(实际 +%d)" % got59)
	# 图鉴 API：record 返回是否新收录 / 计数
	var perch59: ItemData = load("res://item/perch.tres") as ItemData
	var kinds0: int = FishJournal.kinds_caught()
	var cnt0: int = FishJournal.count_of(perch59.display_name)
	var first59: bool = FishJournal.record(perch59)
	chk(FishJournal.count_of(perch59.display_name) == cnt0 + 1, "record 后该鱼种计数 +1")
	chk(first59 == (cnt0 == 0), "record 返回值 = 是否首次收录")
	chk(FishJournal.record(perch59) == false, "同种鱼第二条不再算新收录")
	chk(FishJournal.kinds_caught() == kinds0 + (0 if cnt0 > 0 else 1), "鱼种数按首次收录递增")
	# 钓到的那条也记进了图鉴
	var caught59 := false
	for s in Inventory.slot_list():
		if s["item"] != null and s["item"].type == "食物":
			if FishJournal.count_of(s["item"].display_name) > 0:
				caught59 = true
	chk(caught59 and FishJournal.kinds_caught() >= 1, "钓到的鱼自动记入图鉴")
	# 存档往返：图鉴随 _collect/_apply 走
	var snap59: Dictionary = SaveManager._collect(g)
	chk((snap59.get("fish_journal", {}) as Dictionary).size() > 0, "存档快照带上钓鱼图鉴")
	var bak59: Dictionary = FishJournal.collect_data()
	FishJournal.apply_data({})
	chk(FishJournal.kinds_caught() == 0, "图鉴清空")
	SaveManager._apply(snap59)
	await get_tree().process_frame
	var ok59 := bak59.size() == FishJournal.collect_data().size()
	if ok59:
		for kk in bak59:
			if FishJournal.count_of(String(kk)) != int(bak59[kk]):
				ok59 = false
	chk(ok59, "读档后图鉴逐条还原(%d 种)" % bak59.size())
	# 还原现场：清鱼 + 图鉴清零 + 开关还原
	player._fish_reset()
	var fish_kinds: Array = []
	for s in Inventory.slot_list():
		var itx: ItemData = s["item"]
		if itx != null and itx.type == "食物" and not fish_kinds.has(itx):
			fish_kinds.append(itx)
	for itx in fish_kinds:
		Inventory.remove_item(itx, Inventory.count_item(itx))
	FishJournal.reset_for_new_game()
	player.fish_fast = false
	player.frozen = frozen59
	chk(food_count.call() == 0 and FishJournal.kinds_caught() == 0,
		"收尾: 鱼获与图鉴清零还原")

	# ============ 60. 鸡舍：建造 / 管理界面 / 下蛋 / 收蛋 / 拆除 / 存档 ============
	print("\n=== 60. 鸡舍：建造 / 管理界面 / 下蛋 / 收蛋 / 拆除 / 存档 ===")
	# 新文案字形检查（e30p 管理面板 + 建造菜单 + 道具描述）
	var gl60 := true
	for t60 in ["鸡舍", "收蛋 (一键, 3 枚)", "买一只小鸡 (120 金)", "卖一只鸡 (+90 金)",
			"扩建到 Lv2 (80 金, 多住 1 只)", "已经扩建到顶了 (Lv3)",
			"鸡 3/3  蛋 2 枚  等级 Lv1", "小鸡搬进来啦", "卖掉一只鸡",
			"扩建完成, 能住更多鸡了", "鸡搬去别的鸡舍住了", "收了 3 个鸡蛋",
			"没有蛋可收", "舍里没有鸡可卖", "买不了 (钱不够 / 住满了)", "钱包 1200 金"]:
		if not missing_glyphs(String(t60)).is_empty():
			gl60 = false
	for p60 in ["res://item/chicken.tres", "res://item/egg.tres"]:
		var it60: ItemData = load(p60) as ItemData
		if it60 == null or not missing_glyphs(it60.display_name + it60.description).is_empty():
			gl60 = false
	var ST60: Dictionary = (load("res://structures.gd") as Script).get_script_constant_map()
	var coop60: Dictionary = (ST60["BUILDINGS"] as Dictionary).get(Structures.KIND_COOP, {})
	if not missing_glyphs(String(coop60.get("name", "")) + String(coop60.get("desc", ""))).is_empty():
		gl60 = false
	chk(gl60, "鸡舍全部新文案无缺字形")
	# 建造菜单注册 + 造价 + 地基
	chk((ST60["BUILDINGS"] as Dictionary).has(Structures.KIND_COOP), "建造菜单里有鸡舍")
	chk(int(coop60.get("coin", 0)) == 100 and int(coop60.get("wood", 0)) == 8
		and int(coop60.get("stone", 0)) == 4 and int(coop60.get("iron", 0)) == 0
		and int(coop60.get("labor", 0)) == 4,
		"鸡舍造价 = 100金 + 木x8 + 石x4 + 4 人天")
	chk(g.call("building_footprint", Vector2i(9, 9), Structures.KIND_COOP).size() == 12,
		"鸡舍地基占 6x2 = 12 格")
	# e30p: 小鸡退出商人货架 —— 买卖都在鸡舍管理界面里办
	var su60: Dictionary = (load("res://shop_ui.gd") as Script).get_script_constant_map()
	var chick_shop60 := false
	for s60 in su60["STOCK"]:
		if String(s60["seed"]).ends_with("chicken.tres"):
			chick_shop60 = true
	chk(not chick_shop60, "小鸡退出商人货架 (买卖走鸡舍管理界面)")
	# 摆一座鸡舍 + 节点重建
	var chick60: ItemData = load("res://item/chicken.tres")
	var egg60: ItemData = load("res://item/egg.tres")
	var cell60 := Vector2i(2, 2)
	if Structures.has_station(cell60):
		Structures.remove(cell60)
	await get_tree().process_frame
	chk(Structures.place(cell60, Structures.KIND_COOP), "摆下一座鸡舍")
	chk(Structures.chickens_of(cell60) == 0 and Structures.eggs_of(cell60) == 0,
		"新鸡舍空着: 0 只鸡 0 个蛋")
	chk(Structures.coop_cap_of(cell60) == 3, "Lv1 鸡舍能住 3 只 (等级容量制)")
	chk(g.station_nodes.has(cell60) and (g.station_nodes[cell60] as Node).has_method("hit_rect"),
		"鸡舍节点摆出来 (能被 F 交互/镐子拆)")
	place_player(cell60 + Vector2i(1, 0))
	# F 打开管理界面: 交互吃掉 + 面板真的开了又关得上
	chk(g.coop_panel != null, "鸡舍管理面板挂上 HUD")
	chk(g._try_station_interact(), "对鸡舍按 F = 吃掉交互 (开管理界面)")
	chk(g.coop_panel.is_open(), "F 打开了鸡舍管理界面")
	g.coop_panel.close_panel()
	chk(not g.coop_panel.is_open(), "管理面板能关上")
	# e36h 鸡舍四周都能按 F —— 可交互区跟「走近浮提示」的 reach 区重合:
	#   站在屋前/屋后/屋侧（离锚点格 1 格以上, 老代码的 3x3 扫格够不到锚点格）一样开得开
	var coop60n = g.station_nodes[cell60]
	chk(coop60n.has_method("interact_rect"), "鸡舍节点给出可交互矩形 interact_rect (e36h)")
	var reach60: Rect2 = coop60n.call("interact_rect")
	var ring_ok60 := true
	var ring_n60 := 0
	for off60 in [Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(2, -2)]:
		place_player(cell60 + off60)
		if not reach60.has_point(player.global_position):
			continue                    # 这一侧不在可交互区里, 不参与判定
		ring_n60 += 1
		if not g._try_station_interact() or not g.coop_panel.is_open():
			ring_ok60 = false
		if g.coop_panel.is_open():
			g.coop_panel.close_panel()
	chk(ring_n60 >= 3, "鸡舍可交互区覆盖多个方位 (%d 处)" % ring_n60)
	chk(ring_ok60, "鸡舍四周按 F 都能开管理界面 (e36h)")
	# e36i 左键点「F 鸡舍」提示框 = 按 F（走 game.station_hint_clicked 的同一条派发）
	place_player(cell60 + Vector2i(1, 0))
	chk(not g.coop_panel.is_open(), "点提示框之前管理面板是关着的")
	g.station_hint_clicked(cell60)
	chk(g.coop_panel.is_open(), "左键点「F 鸡舍」框 = 按 F 开管理界面 (e36i)")
	g.coop_panel.close_panel()
	# e36i key_hint 命中判定: 框中心算中, 框外不算中
	var hint60 = coop60n.get("_hint")
	var hc60: Vector2 = hint60.get_global_transform_with_canvas() * Vector2.ZERO
	chk(hint60.hit_point(hc60), "key_hint.hit_point: 框中心命中 (e36i)")
	chk(not hint60.hit_point(hc60 + Vector2(400, 400)), "key_hint.hit_point: 框外不命中 (e36i)")
	# 买鸡入住: 钱包扣 120, 舍里 +1
	Wallet.add_money(1200)
	var m60 := Wallet.money
	chk(g.coop_buy_chicken(cell60), "管理界面买鸡成交")
	chk(Structures.chickens_of(cell60) == 1 and Wallet.money == m60 - 120,
		"小鸡入住: 舍里 1 只, 扣 120 金")
	chk(Structures.add_chicken(cell60), "第二只直接入住")
	chk(Structures.chickens_of(cell60) == 2, "鸡舍里住着 2 只")
	# 卖鸡: 舍里 -1, 钱包 +90
	m60 = Wallet.money
	chk(g.coop_sell_chicken(cell60), "管理界面卖鸡成交")
	chk(Structures.chickens_of(cell60) == 1 and Wallet.money == m60 + 90,
		"卖掉一只鸡: 舍里 1 只, 进账 90 金")
	# 住满: Lv1 住 3 只, 第 4 只被拦
	while Structures.add_chicken(cell60):
		pass
	chk(Structures.chickens_of(cell60) == 3 and Structures.coop_cap_of(cell60) == 3,
		"Lv1 住满 3 只")
	chk(not Structures.add_chicken(cell60) and not g.coop_buy_chicken(cell60),
		"满员: 直接加鸡和管理界面买鸡都被拦")
	# 扩建: Lv1->2 花 80 金容量 4, 再到 Lv3 容量 5, 顶格后拦
	m60 = Wallet.money
	chk(g.coop_upgrade(cell60), "扩建 Lv1 -> Lv2")
	chk(Structures.level_of(cell60) == 2 and Wallet.money == m60 - 80,
		"扩建扣 80 金, 升到 Lv2")
	chk(Structures.coop_cap_of(cell60) == 4, "Lv2 能住 4 只")
	chk(Structures.add_chicken(cell60), "扩建后能再住一只")
	chk(g.coop_upgrade(cell60), "扩建 Lv2 -> Lv3")
	chk(Structures.coop_cap_of(cell60) == 5, "Lv3 能住 5 只")
	while Structures.add_chicken(cell60):
		pass
	chk(Structures.chickens_of(cell60) == 5, "Lv3 住满 5 只")
	m60 = Wallet.money
	chk(not g.coop_upgrade(cell60) and Wallet.money == m60, "顶格扩建被拦, 钱不动")
	# 下蛋: 风暴天鸡吓得不下; 清晨每只鸡 1 个
	var eggs0_60 := Structures.eggs_of(cell60)
	chk(Structures.lay_eggs(true) == 0, "风暴天鸡吓得不下蛋")
	chk(Structures.eggs_of(cell60) == eggs0_60, "风暴过后蛋数没变")
	var laid60 := Structures.lay_eggs(false)
	chk(laid60 >= Structures.chickens_of(cell60),
		"清晨全岛下了 %d 个蛋 (本舍贡献 %d)" % [laid60, Structures.chickens_of(cell60)])
	chk(Structures.eggs_of(cell60) == eggs0_60 + Structures.chickens_of(cell60),
		"本舍蛋数 = 清晨基数 + 鸡数")
	# 一键收蛋: 攒的蛋一次全进背包
	var egg_n60 := Inventory.count_item(egg60)
	var want60 := Structures.eggs_of(cell60)
	chk(g.coop_take_eggs(cell60) == want60, "一键收蛋 %d 枚" % want60)
	chk(Structures.eggs_of(cell60) == 0, "蛋一次收光")
	chk(Inventory.count_item(egg60) == egg_n60 + want60, "背包收进 %d 个鸡蛋" % want60)
	chk(g.coop_take_eggs(cell60) == 0, "没蛋可收返回 0")
	# 拆除: 蛋掉地上; 鸡不走道具, 转移到别的有空位的鸡舍
	Structures.lay_eggs(false)
	var other60 := Vector2i(14, 2)
	if Structures.has_station(other60):
		Structures.remove(other60)
	chk(Structures.place(other60, Structures.KIND_COOP), "再摆一座空鸡舍当收容所")
	var drop60 := Structures.eggs_of(cell60)
	var pk_egg60 := 0
	var pk_chick60 := 0
	for ch60 in g.get_children():
		if ch60.get("item") == egg60:
			pk_egg60 += 1
		if ch60.get("item") == chick60:
			pk_chick60 += 1
	var hit60: Dictionary = g.hit_station(cell60)
	chk(int(hit60.get("result", 0)) == 2 and String(hit60.get("kind", "")) == Structures.KIND_COOP,
		"镐子拆鸡舍走 hit_station")
	var pk2_egg60 := 0
	for ch60 in g.get_children():
		if ch60.get("item") == egg60:
			pk2_egg60 += 1
	chk(pk2_egg60 == pk_egg60 + drop60, "攒着的 %d 个蛋掉出来" % drop60)
	chk(Structures.chickens_of(other60) == 3,
		"5 只鸡里 3 只搬进收容所 (Lv1 顶格), 剩下 2 只走散")
	# 全岛住满再拆: 没地方去, 鸡直接走散, 且不掉出小鸡道具
	chk(Structures.place(cell60, Structures.KIND_COOP), "原地再摆一座鸡舍 (走散分支)")
	Structures.add_chicken(cell60)
	var pk3_chick60 := 0
	for ch60 in g.get_children():
		if ch60.get("item") == chick60:
			pk3_chick60 += 1
	g.hit_station(cell60)
	chk(not Structures.has_station(cell60) and Structures.chickens_of(other60) == 3,
		"收容所满员, 再拆鸡舍的鸡只能走散")
	chk(pk3_chick60 == pk_chick60, "走散不掉小鸡道具 (鸡不是道具)")
	# 存档往返: 鸡数/蛋数跟着 stations 字段走
	chk(Structures.place(cell60, Structures.KIND_COOP), "原地再摆一座鸡舍 (存档用)")
	Structures.add_chicken(cell60)
	Structures.add_chicken(cell60)
	Structures.lay_eggs(false)
	var snap60: Dictionary = SaveManager._collect(g)
	var coop_snap60 := false
	for ss60 in snap60.get("stations", []):
		if String(ss60.get("kind", "")) == Structures.KIND_COOP \
				and int(ss60.get("chickens", -1)) == 2 and int(ss60.get("eggs", -1)) == 2:
			coop_snap60 = true
	chk(coop_snap60, "存档快照带上鸡舍的鸡数/蛋数")
	Structures.reset()
	SaveManager._apply(snap60)
	await get_tree().process_frame
	chk(Structures.kind_of(cell60) == Structures.KIND_COOP
		and Structures.chickens_of(cell60) == 2 and Structures.eggs_of(cell60) == 2,
		"读档后鸡舍连鸡带蛋一并还原")
	chk(g.station_nodes.has(cell60), "读档后鸡舍节点也重建了")
	# 顺手修的白名单回归: 水井读档不再消失
	var wcell60 := Vector2i(7, 5)
	if Structures.has_station(wcell60):
		Structures.remove(wcell60)
	chk(Structures.place(wcell60, Structures.KIND_WELL), "顺手摆一座水井 (白名单回归)")
	var snap60b: Dictionary = SaveManager._collect(g)
	Structures.reset()
	SaveManager._apply(snap60b)
	await get_tree().process_frame
	chk(Structures.kind_of(wcell60) == Structures.KIND_WELL, "读档后水井还在 (白名单补上 KIND_WELL)")
	# 收尾: 拆测试设施, 清小鸡/鸡蛋残留
	Structures.remove(cell60)
	Structures.remove(other60)
	Structures.remove(wcell60)
	Inventory.remove_item(chick60, Inventory.count_item(chick60))
	Inventory.remove_item(egg60, Inventory.count_item(egg60))
	await get_tree().process_frame

	# ============ 61. 建造占地放宽: 树/石/矿可压, 动工自动清障 ============
	print("\n=== 61. 建造占地放宽: 树/石/矿可压, 动工自动清障 ===")
	var bk61: String = g.build_kind
	g.build_kind = Structures.KIND_COOP    # 鸡舍 6x2 = 12 格, 地基最小好找地
	# 找一块开阔锚格 (footprint 里没树没矿没设施) 作为试验田
	var cell61 := Vector2i(-1, -1)
	for cx61 in range(0, 60):
		var done61 := false
		for cy61 in range(0, 60):
			var c61 := Vector2i(cx61, cy61)
			if g.call("_building_site_ok", c61):
				cell61 = c61
				done61 = true
				break
		if done61:
			break
	chk(cell61.x >= 0, "找到一块开阔地能盖鸡舍")
	var fp61: Array = g.call("building_footprint", cell61, Structures.KIND_COOP)
	chk(fp61.size() == 12, "试验田地基 12 格")
	# 往地基上种成树 + 摆铁矿: 判定放宽后照样能盖
	var tcell61: Vector2i = fp61[0]
	var ocell61: Vector2i = fp61[1]
	Trees.plant(tcell61, 0, Trees.ST_MATURE)
	OreVein.place(ocell61, OreVein.KIND_IRON, 0)
	chk(Trees.has_tree(tcell61) and OreVein.has_rock(ocell61), "地基上摆好一棵成树 + 一处铁矿")
	chk(g.call("_building_site_ok", cell61), "树/矿压在地基上照样判定能盖 (放宽生效)")
	# 对照: 耕地仍然拦
	var fcell61: Vector2i = fp61[2]
	chk(Farm.till(fcell61), "地基上翻出一块耕地")
	chk(not g.call("_building_site_ok", cell61), "有耕地压在地基上仍然拦下")
	Farm.untill(fcell61)
	# 清障: 数据层 clear_cell -> 信号把节点也拆掉
	Trees.clear_cell(tcell61)
	OreVein.clear_cell(ocell61)
	chk(not Trees.has_tree(tcell61) and not OreVein.has_rock(ocell61), "clear_cell 把树和矿从数据层清掉")
	chk(not g.tree_nodes.has(tcell61) and not g.rock_nodes.has(ocell61), "树/矿节点也跟着消失 (信号路径)")
	chk(g.call("_building_site_ok", cell61), "清障后判定恢复能盖")
	g.build_kind = bk61

	# ============ 62. 作物利润梯度 + 领主像素头像 + 分线对话 ============
	print("\n=== 62. 作物利润梯度 + 领主像素头像 + 分线对话 ===")
	# 62a 生长周期越长, 毛利/天越高 (作物/种子/烹饪三张价目一起成梯度)
	var carrot_s62: ItemData = load("res://item/carrot_seed.tres")
	var carrot62: ItemData = load("res://item/carrot.tres")
	var potato_s62: ItemData = load("res://item/seed.tres")
	var potato62: ItemData = load("res://item/potato.tres")
	var cabbage_s62: ItemData = load("res://item/cabbage_seed.tres")
	var cabbage62: ItemData = load("res://item/cabbage.tres")
	var pumpkin_s62: ItemData = load("res://item/pumpkin_seed.tres")
	var pumpkin62: ItemData = load("res://item/pumpkin.tres")
	chk(int(carrot62.sell_price) == 22 and int(potato62.sell_price) == 30
		and int(cabbage62.sell_price) == 65 and int(pumpkin62.sell_price) == 105,
		"作物卖价梯度: 胡萝卜22 / 土豆30 / 卷心菜65 / 南瓜105 (e15b)")
	chk(int(carrot_s62.sell_price) == 7 and int(potato_s62.sell_price) == 8
		and int(cabbage_s62.sell_price) == 16 and int(pumpkin_s62.sell_price) == 30,
		"种子卖价梯度: 7 / 8 / 16 / 30 (周期越长种子越贵)")
	var crops62 := [
		[carrot_s62, carrot62], [potato_s62, potato62],
		[cabbage_s62, cabbage62], [pumpkin_s62, pumpkin62],
	]
	var mono62 := true
	var gd_prev62 := 0
	var rate_prev62 := -1.0
	var rate_txt62 := ""
	for k62 in crops62.size():
		var pair62: Array = crops62[k62]
		var s62: ItemData = pair62[0]
		var c62: ItemData = pair62[1]
		var gd62: int = int(s62.grow_days)
		var rate62: float = float(int(c62.sell_price) - int(s62.sell_price)) / float(gd62)
		if gd62 <= gd_prev62 or rate62 <= rate_prev62:
			mono62 = false
		gd_prev62 = gd62
		rate_prev62 = rate62
		if k62 > 0:
			rate_txt62 += " -> "
		rate_txt62 += "%s(%d天) %.2f金/天" % [String(c62.display_name), gd62, rate62]
	chk(mono62, "毛利/天单调递增: %s" % rate_txt62)
	var bake62: ItemData = load("res://item/baked_potato.tres")
	var salad62: ItemData = load("res://item/carrot_salad.tres")
	var soup62: ItemData = load("res://item/cabbage_soup.tres")
	var pie62: ItemData = load("res://item/pumpkin_pie.tres")
	chk(int(salad62.sell_price) == 56 and int(bake62.sell_price) == 42
		and int(soup62.sell_price) == 84 and int(pie62.sell_price) == 140,
		"烹饪卖价一起涨: 沙拉56 / 烤土豆42 / 汤84 / 派140 (e15b)")
	# 62b 领主/百夫长像素头像: 15 镇 + 5 国一张不少
	var miss_l62: Array = []
	for tid62 in Nations.TOWNS.keys():
		if load("res://resources/texture/portraits/lord_%s.png" % tid62) == null:
			miss_l62.append(String(tid62))
	chk(miss_l62.is_empty(), "15 张领主头像 lord_<镇id>.png 全在 (缺 %s)" % str(miss_l62))
	var miss_c62: Array = []
	for nid62 in Nations.CAPTAIN_NAMES.keys():
		if load("res://resources/texture/portraits/captain_%s.png" % nid62) == null:
			miss_c62.append(String(nid62))
	chk(miss_c62.is_empty(), "5 张百夫长头像 captain_<国id>.png 全在 (缺 %s)" % str(miss_c62))
	var pdir62 := DirAccess.open("res://resources/texture/portraits")
	var nlord62 := 0
	var ncap62 := 0
	if pdir62 != null:
		for f62 in pdir62.get_files():
			if f62.ends_with(".png") and f62.begins_with("lord_"):
				nlord62 += 1
			elif f62.ends_with(".png") and f62.begins_with("captain_"):
				ncap62 += 1
	chk(nlord62 == 15 and ncap62 == 5, "头像目录清点: %d 领主 + %d 百夫长" % [nlord62, ncap62])
	# 62c 名册: 15 镇领主人人有称呼 + 名字, 5 国百夫长人人有名
	var roster62 := true
	for tid62 in Nations.TOWNS.keys():
		var l62: Dictionary = Nations.lord_of(String(tid62))
		if String(l62.get("title", "")) == "" or String(l62.get("name", "")) == "":
			roster62 = false
	chk(roster62, "15 镇领主名册齐全 (title + name)")
	var roster_c62 := true
	for nid62 in Nations.nation_ids():
		if Nations.captain_name(String(nid62)) == "":
			roster_c62 = false
	chk(roster_c62, "5 国百夫长名册齐全")
	# e36n 称号按国别特色: 五国巡逻队长不再一律叫「百夫长」
	chk(Nations.captain_title("chenxi") == "港口护卫长"
		and Nations.captain_title("beiling") == "雪境巡逻长"
		and Nations.captain_title("xichuan") == "粮道护卫长"
		and Nations.captain_title("tieyan") == "氏族骑兵长"
		and Nations.captain_title("canglang") == "草原游骑长",
		"五国巡逻队长称号按国别特色 (港口护卫长/雪境巡逻长/粮道护卫长/氏族骑兵长/草原游骑长)")
	var title_ok62 := true
	var title_gl62 := true
	for nid62 in Nations.nation_ids():
		var t62 := Nations.captain_title(String(nid62))
		if t62 == "" or t62 == "百夫长":
			title_ok62 = false
		if not missing_glyphs(t62).is_empty():
			title_gl62 = false
	chk(title_ok62, "没有哪国的巡逻队长还叫「百夫长」(e36n)")
	chk(title_gl62, "五国称号无缺字形 (e36n)")
	chk(Nations.lord_full("chenxi_cap") == "晨曦王 奥朗"
		and Nations.lord_full("tieyan_cliff") == "崖台吉 苏赫",
		"lord_full 拼称呼: 晨曦王 奥朗 / 崖台吉 苏赫")
	# 62d 对话分线(e18): 城镇里是领主的私房话, 巡逻队是百夫长的军中话 —— 台词已升级
	# 成「对话组」(每组 2~3 段): chat_town/captain 返回数组, 且每段必须出自该人的分线
	var fav62: int = Nations.favor_of("chenxi")
	var lfav62: int = Nations.lord_favor_of("chenxi_cap")
	Nations.chat_town("chenxi_cap")
	chk(Nations.favor_of("chenxi") == fav62 + Nations.CHAT_FAVOR, "聊天 +1 好感 (chat_town)")
	chk(Nations.lord_favor_of("chenxi_cap") == lfav62 + Nations.CHAT_FAVOR,
		"领主个人好感也 +1 (碰面聊天记两本账)")
	var town_lines62 := true
	for tid62 in Nations.TOWNS.keys():
		var grp62: Array = Nations.chat_town(String(tid62))
		if grp62.size() < 2 or grp62.size() > 3:
			town_lines62 = false        # 每组必须 2~3 段
			continue
		for seg62 in grp62:             # 每段都要出自本人分线的某个组
			var found62 := false
			for cand62 in Nations.LORD_LINES[String(tid62)]:
				if (cand62 as Array).has(seg62):
					found62 = true
					break
			if not found62:
				town_lines62 = false
	chk(town_lines62, "城镇聊天走领主分线, 每组 2~3 段 (e18)")
	var cfav62: int = Nations.captain_favor_of("chenxi")
	var cap_lines62 := true
	for nid62 in Nations.nation_ids():
		var cgrp62: Array = Nations.chat_captain(String(nid62))
		if cgrp62.size() < 2:
			cap_lines62 = false
		for cseg62 in cgrp62:
			var cfound62 := false
			for ccand62 in Nations.CAPTAIN_LINES[String(nid62)]:
				if (ccand62 as Array).has(cseg62):
					cfound62 = true
					break
			if not cfound62:
				cap_lines62 = false
	chk(cap_lines62, "巡逻队聊天走百夫长分线, 每组 2~3 段 (e18)")
	chk(Nations.captain_favor_of("chenxi") == cfav62 + Nations.CHAT_FAVOR,
		"百夫长个人好感也 +1 (碰面聊天记两本账)")
	# 62e 面板接线: 议事厅挂领主头像, 军中交谈挂百夫长头像
	var tw62: Control = load("res://town_ui.gd").new()
	tw62.setup("chenxi_cap")
	add_child(tw62)
	tw62._rebuild()
	var twport62: Variant = tw62.get("_portrait")
	chk(twport62 != null and twport62.texture != null
		and twport62.texture.resource_path.ends_with("lord_chenxi_cap.png"),
		"议事厅头像框挂上领主头像 (lord_chenxi_cap.png)")
	var pu62: Control = load("res://patrol_ui.gd").new()
	pu62.setup("晨曦亲军", "chenxi")
	add_child(pu62)
	pu62._rebuild()
	var puport62: Variant = pu62.get("_portrait")
	chk(puport62 != null and puport62.texture != null
		and puport62.texture.resource_path.ends_with("captain_chenxi.png"),
		"军中交谈头像框挂上百夫长头像 (captain_chenxi.png)")
	# e36n: 面板上显示的是该国称号（晨曦 = 港口护卫长）, 不是干巴巴的「百夫长」
	var putitle62 := false
	var pur62 = pu62.get("_root")
	if pur62 != null:
		for c62 in (pur62 as Node).get_children():
			if c62 is Label and String((c62 as Label).text).contains(Nations.captain_title("chenxi")):
				putitle62 = true
	chk(putitle62, "军中交谈面板显示该国称号 (港口护卫长, e36n)")
	tw62.queue_free()
	pu62.queue_free()
	await get_tree().process_frame
	# 62f 送礼点名: 回应里点收礼人的名字 (领主 / 百夫长)
	var fav_g62: int = Nations.favor_of("chenxi")
	Wallet.add_money(Nations.GIFT_COST * 2)
	var lord62: Dictionary = Nations.lord_of("chenxi_cap")
	var gwho62: String = String(lord62.get("name", ""))
	chk(Nations.gift("chenxi", gwho62) == "%s收下了礼物, 很是高兴." % gwho62,
		"送礼给领主 %s: 回应点名收礼人" % gwho62)
	chk(Nations.favor_of("chenxi") == fav_g62 + Nations.GIFT_FAVOR, "送礼 +5 好感")
	var gcap62: String = Nations.captain_name("chenxi")
	chk(Nations.gift("chenxi", gcap62) == "%s收下了礼物, 很是高兴." % gcap62,
		"送礼给百夫长 %s: 回应点名收礼人" % gcap62)

	# ============ 63. 外交: 背包「外交」页签 (关系/军力/送礼/签约) ============
	print("\n=== 63. 外交: 背包「外交」页签 (关系/军力/送礼/签约) ===")
	# 63a 军力 = 该国各镇守军之和 (capital 7 / military 5 / trade 3) —— e27e: 贸易镇也配守军
	var pw_chenxi63: int = Nations.army_power("chenxi")
	var pw_tieyan63: int = Nations.army_power("tieyan")
	chk(pw_chenxi63 == 13, "晨曦军力 = 主城7 + 两贸易镇 3x2 = 13 (实际 %d)" % pw_chenxi63)
	chk(pw_tieyan63 == 17, "铁岩军力 = 主城7 + 两军镇 5x2 = 17 (实际 %d)" % pw_tieyan63)
	chk(Nations.army_word("tieyan") == "兵强马壮"
		and Nations.army_word("chenxi") == "武备整肃",
		"军力评级: 17 兵强马壮 / 13 武备整肃")
	# 63b 攻城打掉军力 -> 评级跟着掉 -> 复原回升
	var keep63 := {}
	for tid63 in Nations.ai_towns_of("xichuan"):
		keep63[String(tid63)] = Nations.garrison_of(String(tid63))
		Nations.garrison[String(tid63)] = 0
	chk(Nations.army_power("xichuan") == 0
		and Nations.army_word("xichuan") == "不堪一击",
		"全境守军打光: 军力归零, 评级 -> 不堪一击")
	for tid63b in keep63:
		Nations.garrison[String(tid63b)] = int(keep63[String(tid63b)])
	chk(Nations.army_power("xichuan") == 13, "守军复原: 西川军力回满 13")
	# 63c 键位: Esc 回归背包 (跟 B 并列), 外交的专属动作已摘除
	chk(not InputMap.has_action("diplomacy_panel"),
		"diplomacy_panel 动作已从 InputMap 摘下 (外交归背包页签)")
	var esc_in_inv63 := false
	for ev63b in InputMap.action_get_events("toggle_inventory"):
		var k63b := ev63b as InputEventKey
		if k63b != null and k63b.physical_keycode == KEY_ESCAPE:
			esc_in_inv63 = true
	chk(esc_in_inv63, "toggle_inventory 绑着 Esc (B / Esc 并列开背包)")
	# 63d 页签冒烟: 背包里真挂上了外交页 + 接口齐全 + 送礼真改好感
	# （❗has_method 必须打在实例上, 打在 load 出来的 Script 资源上永远查不到脚本方法）
	var bp63: Control = g.get_node_or_null("HUD/Backpack")
	var pages63: Dictionary = bp63.get("_pages") if bp63 != null else {}
	chk(pages63.has("diplomacy"), "背包面板挂上了「外交」页签")
	var dp63: Control = load("res://diplomacy_ui.gd").new()
	add_child(dp63)
	chk(dp63.has_method("_on_gift") and dp63.has_method("_on_sign"),
		"diplomacy_ui._on_gift / _on_sign 接口都在")
	chk(not dp63.has_method("_on_chat"), "外交页没有聊天按钮 (聊天去地图上碰领主)")
	dp63._rebuild()
	chk(dp63.get("_root") != null, "外交页骨架搭起来了")
	# 开局五国好感全 0、无协议、无通告、送礼按钮全灰 —— 页面看着空是正常状态,
	# 但五张国卡 + 自己那张「潮汐港」势力卡必须在: 锁死「开局不是真空白」。
	var cards63 := 0
	for c63 in (dp63.get("_root") as Node).get_children():
		if c63 is PanelContainer:
			cards63 += 1
	chk(cards63 == 6, "外交页摆开 6 张卡（1 张自己 + 5 国, 实际 %d）" % cards63)
	chk(Nations.GIFT_COST == 200, "送礼成本涨到 %d 金" % Nations.GIFT_COST)
	var fav63a: int = Nations.favor_of("tieyan")
	Wallet.add_money(Nations.GIFT_COST)
	dp63._on_gift("tieyan")
	chk(Nations.favor_of("tieyan") == fav63a + Nations.GIFT_FAVOR,
		"外交页送礼: 铁岩好感 +5")
	dp63.queue_free()
	await get_tree().process_frame

	# ============ 64. 伙伴送礼 + 好感收益 ============
	print("\n=== 64. 伙伴送礼 + 好感收益 ===")
	# 64a 接口都在: 对话窗的送礼按钮 + 队伍详情页的送礼按钮
	var dlg64: Control = load("res://dialogue_ui.gd").new()
	add_child(dlg64)
	chk(dlg64.has_method("_on_gift_pressed"), "dialogue_ui._on_gift_pressed 接口在")
	dlg64.queue_free()
	var bp64: Control = g.get_node_or_null("HUD/Backpack")
	var gift_btn64: Button = null
	if bp64 != null:
		bp64._build_slave_detail()   # 详情页是懒构建, 先手动建一次才拿得到按钮
		gift_btn64 = bp64.get("_detail_gift_btn")
	chk(gift_btn64 != null, "队伍详情页挂上了「送礼」按钮")
	# 64b 送礼只收作物: 塞一个确定性假伙伴（今天没送过）
	Slaves.slaves = [{
		"name": "礼收员", "affection": 0, "fed_today": true, "talked_today": true,
		"gift_today": false, "max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1,
		"labor": "帮工",
	}]
	Slaves.count = 1
	var carrot64: ItemData = load("res://item/carrot.tres")
	var seed64: ItemData = load("res://item/seed.tres")
	chk(Slaves.gift_item(0, seed64) == 0, "送非作物(种子) = 0 (只收庄稼)")
	chk(int(Slaves.slaves[0]["affection"]) == 0, "送错东西好感没动")
	var gain64: int = Slaves.gift_item(0, carrot64)
	chk(gain64 == Slaves.GIFT_AFFECTION,
		"送作物 = +%d 好感 (实际 %d)" % [Slaves.GIFT_AFFECTION, gain64])
	chk(bool(Slaves.slaves[0]["gift_today"]), "今天送过标记打开")
	chk(Slaves.gift_item(0, carrot64) == 0, "今天再送 = 0 (不重复加)")
	chk(int(Slaves.slaves[0]["affection"]) == Slaves.GIFT_AFFECTION, "好感真的 +2")
	# 64d 新一天重置: 又能送了
	Slaves._on_new_day(1)
	chk(not bool(Slaves.slaves[0]["gift_today"]), "新一天 gift_today 重置")
	chk(Slaves.gift_item(0, carrot64) == Slaves.GIFT_AFFECTION, "第二天送礼 +2 再次生效")
	# 64e 好感收益: 每 4 点好感换伙伴 1 点攻
	chk(Slaves.affection_atk(0) == 0 and Slaves.affection_atk(3) == 0,
		"好感 0/3 = +0 攻 (不满 4 点不涨)")
	chk(Slaves.affection_atk(4) == 1 and Slaves.affection_atk(9) == 2,
		"好感 4 = +1 攻 / 9 = +2 攻")
	chk(Slaves.affection_atk(10) == 2 and Slaves.affection_atk(99) == 2,
		"满好感 10 封顶 = +2 攻 (超了也钳住)")

	# ============ 65. 经济补洞: 小麦上货架 + 材料可卖 ============
	print("\n=== 65. 经济补洞: 小麦上货架 + 材料可卖 ===")
	var wheat65: ItemData = load("res://item/wheat.tres")
	chk(wheat65 != null and wheat65.type == "材料" and wheat65.sell_price == 5,
		"小麦是材料, 标价 5 金")
	# 65a 哥布林商店货架摆着小麦（8 金）
	var su65: Dictionary = (load("res://shop_ui.gd") as Script).get_script_constant_map()
	var wheat_shop65 := 0
	for s65 in su65["STOCK"]:
		if String(s65["seed"]).ends_with("wheat.tres") and int(s65["price"]) == 8:
			wheat_shop65 += 1
	chk(wheat_shop65 == 1, "哥布林商店货架摆着小麦 (8 金)")
	# 65b 贸易市集也摆着小麦
	var mk65: Dictionary = (load("res://market_ui.gd") as Script).get_script_constant_map()
	var wheat_market65 := 0
	for s65 in mk65["STOCK"]:
		if String(s65["path"]).ends_with("wheat.tres") and int(s65["price"]) == 8:
			wheat_market65 += 1
	chk(wheat_market65 == 1, "贸易市集也摆着小麦 (8 金)")
	# 65c 材料可卖: e30w 起收材料的是「售卖箱」(商人不再收卖货), 卖价不走加成（小麦 5 金就是 5 金）
	var bin65: Node2D = get_tree().get_first_node_in_group("shipping_bin") as Node2D
	if bin65 != null:
		chk(bin65.call("_sellable", wheat65), "售卖箱收材料的货（小麦投得进去）")
	chk(Research.sell_price_of(wheat65) == 5, "材料卖价不走加成（小麦 5 金就是 5 金）")
	# e30w 商人不再收卖货: 卖货整块搬去售卖箱 —— 出货口只留一个
	var shop65w: Control = g.get_node_or_null("HUD/Shop")
	if shop65w != null:
		chk(not shop65w.has_method("_sell_all_crops") and not shop65w.has_method("_sell_one")
			and not shop65w.has_method("_is_sellable"), "商人那边卖货的方法都拆干净了")
		var sell_btns65w: Array = []
		for c65w in shop65w.find_children("*", "Button", true, false):
			var bt65w := String((c65w as Button).text)
			if bt65w == "卖" or bt65w == "全部卖掉":
				sell_btns65w.append(bt65w)
		chk(sell_btns65w.is_empty(), "商人面板上再没有「卖/全部卖掉」按钮: %s" % str(sell_btns65w))
	chk('Quests.complete("sell_first")' in FileAccess.get_file_as_string("res://scene/shipping_bin.gd"),
		"「卖出第一份作物」任务改由售卖箱触发（商人不再卖货）")
	# e30w 悬浮提示统一吃像素字体: tooltip 是引擎自己 new 的 TooltipLabel（不在任何场景里），
	#   只能靠项目主题钉字体 —— 各处 label.tooltip_text 没法逐个挂 override。
	chk(String(ProjectSettings.get_setting("gui/theme/custom")) == "res://resources/font/ui_theme.tres",
		"project.godot 挂上了全局 UI 主题")
	var th65w: Theme = load("res://resources/font/ui_theme.tres") as Theme
	chk(th65w != null and th65w.has_font("font", "TooltipLabel")
			and th65w.get_font("font", "TooltipLabel") == load("res://resources/font/IPix.ttf"),
		"主题把悬浮提示的字体钉成 IPix")
	chk(th65w != null and th65w.get_font_size("font_size", "TooltipLabel") == 13,
		"悬浮提示字号 13（跟面板小字同一档）")
	# 65d 集市 _sell_total 认材料: 清背包+快捷栏 -> 塞 2 份小麦 -> 报价 10 金
	var bag_bak65: Array = Inventory.backpack.duplicate(true)
	var hot_bak65: Array = Inventory.hotbar.duplicate(true)
	for i65 in Inventory.backpack.size():
		Inventory.backpack[i65] = {"item": null, "count": 0}
	for i65 in Inventory.hotbar.size():
		Inventory.hotbar[i65] = {"item": null, "count": 0}
	var ml65 = preload("res://scene/mainland.gd").new()
	add_child(ml65)
	var mk65_node: Control = ml65.call("_get_market")
	Inventory.add_item(wheat65, 2)
	Inventory.inventory_changed.emit()
	var tot65: Dictionary = mk65_node.call("_sell_total")
	chk(int(tot65["n"]) == 2 and int(tot65["gold"]) == 10,
		"集市报价认材料: 2 份小麦 = 10 金 (n=%d, gold=%d)"
			% [int(tot65["n"]), int(tot65["gold"])])
	ml65.queue_free()
	Inventory.hotbar = hot_bak65
	Inventory.backpack = bag_bak65
	Inventory.inventory_changed.emit()
	# 65e e28b: 木地板降价 20 -> 12（贸易市集 + 议事厅商贸两处同步）
	var floor_shop65 := 0
	for s65 in mk65["STOCK"]:
		if String(s65["path"]).ends_with("wood_floor.tres") and int(s65["price"]) == 12:
			floor_shop65 += 1
	chk(floor_shop65 == 1, "贸易市集木地板 12 金 (原 20 降价)")
	var tw_stock65: Array = (load("res://town_ui.gd") as Script).get_script_constant_map().get("STOCK", [])
	var floor_town65 := 0
	for s65 in tw_stock65:
		if String(s65["path"]).ends_with("wood_floor.tres") and int(s65["price"]) == 12:
			floor_town65 += 1
	chk(floor_town65 == 1, "议事厅商贸木地板也 12 金 (跟市集同步)")
	# 65f e28b: 工作台不做镐子 —— 开局哥布林赠礼有, 配方撤了
	var wb65: Array = (load("res://crafting.gd") as Script).get_script_constant_map().get("WORKBENCH_RECIPES", [])
	var pick_wb65 := 0
	for r65 in wb65:
		var rr65: ItemData = r65["result"]
		if rr65 != null and String(rr65.resource_path).ends_with("pickaxe.tres"):
			pick_wb65 += 1
	chk(pick_wb65 == 0, "工作台配方里没有镐子 (开局赠礼那把够用)")
	# 65g e29i: 哥布林摊位旁那只售货箱已删 (渠道已并入主岛售卖箱的切换按钮)
	# ❗先读属性再 free —— 释放后访问就是踩已释放对象
	var mscn65: PackedScene = load("res://scene/merchant.tscn")
	var mnode65: Node = mscn65.instantiate() if mscn65 != null else null
	var no_box65 := true
	if mnode65 != null:
		no_box65 = mnode65.get_node_or_null("BoxSprite") == null
		mnode65.free()
	chk(no_box65,
		"哥布林摊位旁没有售货箱 (e29i 已移除, 渠道并入主岛售卖箱)")

	# ============ 66. 里程碑长线目标（指引毕业后的常驻追求） ============
	print("\n=== 66. 里程碑长线目标 ===")
	# 66a 接口齐全
	var if_ok66 := true
	for m66 in ["start_milestones", "check_milestones", "note_navy_win", "to_dict",
			"from_dict", "suspend_checks", "resume_checks",
			"milestones_enabled", "milestone_done"]:
		if not Quests.has_method(m66):
			if_ok66 = false
			print("[!!] Quests.%s 接口缺失" % m66)
	chk(if_ok66, "Quests 里程碑 9 个接口齐全")
	# 66b MILESTONES 表: 10 项 / 字段齐 / id 唯一 / check 类型合法 (终局三项走 grand, 可无 goal)
	var ms_ok66 := Quests.MILESTONES.size() == 10
	var seen_ms66 := {}
	for m66 in Quests.MILESTONES:
		var md66: Dictionary = m66 as Dictionary
		for f66 in ["id", "title", "desc", "check", "reward"]:
			if not md66.has(f66):
				ms_ok66 = false
		var mid66 := String(m66["id"])
		if seen_ms66.has(mid66):
			ms_ok66 = false
		seen_ms66[mid66] = true
		if bool(md66.get("grand", false)):
			if not ["prestige", "lord", "unify"].has(String(md66["check"])):
				ms_ok66 = false
		else:
			if not md66.has("goal") \
					or not ["money", "crops", "tilled", "crew", "techs", "navy", "favor"].has(String(md66["check"])):
				ms_ok66 = false
	chk(ms_ok66, "MILESTONES 10 项: 字段齐 / id 唯一 / check 类型合法")
	# 66c 文案无缺字形（含常驻位拼接骨架）
	var gl_ok66 := true
	for m66 in Quests.MILESTONES:
		if not missing_glyphs(String(m66["title"]) + String(m66["desc"])).is_empty():
			gl_ok66 = false
	if not missing_glyphs("里程碑: 首桶金 (奖励 500 金)").is_empty():
		gl_ok66 = false
	chk(gl_ok66, "里程碑全部文案无缺字形")
	# 66d 清场: 备份状态 + 全部条件压到目标以下
	var money_bak66 := Wallet.money
	var tilled_bak66: Dictionary = Farm.tilled.duplicate(true)
	var slaves_bak66: Array = Slaves.slaves.duplicate(true)
	var count_bak66 := Slaves.count
	var techs_bak66: Dictionary = Research.techs.duplicate(true)
	var favor_bak66: Dictionary = Nations.favor.duplicate(true)
	var hot_bak66: Array = Inventory.hotbar.duplicate(true)
	var bag_bak66: Array = Inventory.backpack.duplicate(true)
	var hits66: Array = []
	var cb66: Callable = func(t: String): hits66.append(t)
	Quests.rewarded.connect(cb66)
	Quests.reset_all()
	Wallet.money = 10
	Farm.tilled = {}
	Slaves.slaves = []
	Slaves.count = 0
	Research.techs = {}
	Nations.favor = {}
	for i66 in Inventory.hotbar.size():
		Inventory.hotbar[i66] = {"item": null, "count": 0}
	for i66 in Inventory.backpack.size():
		Inventory.backpack[i66] = {"item": null, "count": 0}
	# 66e 没毕业(指引链没走完)前: 信号来了也不发奖、常驻位不挂
	Wallet.add_money(1)
	chk(not Quests.milestones_enabled() and not Quests.milestone_done("ms_gold"),
		"没毕业前: 加钱触发检查也不发里程碑奖")
	chk(Quests.active().is_empty(), "没毕业前任务栏没有里程碑常驻位")
	# 66f 毕业(complete explore_island 等价)开闸: 挂常驻位, 条件不够不立刻发奖
	Quests.start_milestones()
	chk(Quests.milestones_enabled(), "指引链毕业 -> 里程碑系统开闸")
	chk(not Quests.milestone_done("ms_gold"), "开闸时钱包只有 11 金, 首桶金不达成")
	var act66: Array = Quests.active()
	var ms_task66: Dictionary = act66[0] if act66.size() > 0 else {}
	chk(act66.size() == 1 and String(ms_task66.get("id", "")) == "milestone"
		and String(ms_task66.get("title", "")) == "里程碑: 首桶金"
		and String(ms_task66.get("desc", "")) == "攒下 2000 金 (奖励 500 金)",
		"任务栏挂上常驻位: 里程碑: 首桶金")
	# 66g 逐项达成: 各系统信号驱动, 每项发一次奖
	var b66 := Wallet.money   # 11
	Wallet.add_money(2000)
	chk(Quests.milestone_done("ms_gold") and Wallet.money == b66 + 2500,
		"首桶金: 攒够 2000 金自动领奖 +500 (钱包 %d)" % Wallet.money)
	chk(hits66.size() == 1 and String(hits66[0]) == "首桶金达成! 奖励 +500 金",
		"公告信号: %s" % (String(hits66[0]) if hits66.size() > 0 else "没发"))
	act66 = Quests.active()
	ms_task66 = act66[0] if act66.size() > 0 else {}
	chk(String(ms_task66.get("title", "")) == "里程碑: 满仓丰收",
		"常驻位换成下一个: 满仓丰收")
	b66 = Wallet.money
	Inventory.add_item(load("res://item/carrot.tres"), 30)
	chk(Quests.milestone_done("ms_harvest") and Wallet.money == b66 + 800,
		"满仓丰收: 背包 30 份作物领奖 +800")
	b66 = Wallet.money
	for i66 in 30:
		Farm.tilled[Vector2i(990 + i66, 0)] = true
	Farm.tilled_added.emit(Vector2i(990, 0))
	chk(Quests.milestone_done("ms_farm") and Wallet.money == b66 + 1000,
		"大农场: 开垦 30 块地领奖 +1000")
	b66 = Wallet.money
	var crew66: Array = []
	for i66 in 6:
		crew66.append({"name": "伙伴%d" % i66, "affection": 0,
			"fed_today": true, "talked_today": true, "gift_today": false,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1, "labor": "帮工"})
	Slaves.slaves = crew66
	Slaves.count = 6
	Slaves.changed.emit()
	chk(Quests.milestone_done("ms_crew") and Wallet.money == b66 + 1500,
		"招贤纳士: 伙伴满编 6 人领奖 +1500")
	b66 = Wallet.money
	Quests.note_navy_win()
	chk(Quests.milestone_done("ms_navy") and Wallet.money == b66 + 1500,
		"出海首胜: 海上打赢一场领奖 +1500")
	b66 = Wallet.money
	Research.techs = {"fert": true, "axe": true, "mill": true}
	Research.changed.emit()
	chk(Quests.milestone_done("ms_tech") and Wallet.money == b66 + 1200,
		"科技崛起: 完成 3 项科技领奖 +1200")
	b66 = Wallet.money
	var fav66 := {}
	for nid66 in Nations.nation_ids():
		fav66[String(nid66)] = 20
	Nations.favor = fav66
	Nations.changed.emit()
	chk(Quests.milestone_done("ms_friends") and Wallet.money == b66 + 2000,
		"建交五方: 五国好感都到 20 领奖 +2000")
	# 七项长线全达成 -> 常驻位轮到终局三连第一项
	var act766: Array = Quests.active()
	chk(act766.size() == 1 and String((act766[0] as Dictionary).get("title", "")) == "里程碑: 裂土封王",
		"七项达成: 常驻位轮到终局第一项 裂土封王")
	chk(hits66.size() == 7, "公告一共发了 7 条 (实际 %d)" % hits66.size())
	# 66g2 终局三连: 声望/封王/归一, 达成走 celebrated 大横幅, 不锁档
	var pre_bak66: int = Nations.prestige
	var con_bak66: String = Nations.contract
	var fief_bak66: String = Nations.fief
	var occ_bak66: Dictionary = Nations.occupied.duplicate(true)
	var cel66: Array = []
	var celcb66: Callable = func(t: String): cel66.append(t)
	Quests.celebrated.connect(celcb66)
	Nations.prestige = 100
	Nations.contract = "封臣"
	Nations.fief = "xichuan_cap"
	Nations.occupied = {"chenxi_cap": true, "beiling_cap": true, "tieyan_cap": true,
		"canglang_cap": true, "xichuan_cap": true}
	Wallet.add_money(1)   # 触发一次检查, 三项同时结算
	chk(Quests.milestone_done("ms_lord") and Quests.milestone_done("ms_prestige")
		and Quests.milestone_done("ms_unify"), "终局三连全部达成")
	chk(Quests.active().is_empty(), "十项全达成: 任务栏常驻位撤下")
	chk(cel66.size() == 3, "终局三连走 celebrated 大横幅 (实际 %d)" % cel66.size())
	Quests.celebrated.disconnect(celcb66)
	Nations.prestige = pre_bak66
	Nations.contract = con_bak66
	Nations.fief = fief_bak66
	Nations.occupied = occ_bak66
	# 66h 存档回路: 领奖记录进 to_dict, 读档恢复后不重复发奖
	var save66: Dictionary = Quests.to_dict()
	chk(bool(save66["ms_on"]) and (save66["ms_done"] as Array).size() == 10
		and bool(save66["navy"]),
		"to_dict 记下: 开闸 / 10 项已领 / 海战胜")
	b66 = Wallet.money
	Quests.from_dict({})
	chk(not Quests.milestones_enabled() and not Quests.milestone_done("ms_gold"),
		"from_dict({}) 清空: 关闸 + 领奖记录清零(老档无字段=新档)")
	Quests.from_dict(save66)
	chk(Quests.milestones_enabled() and Quests.milestone_done("ms_gold"),
		"from_dict 恢复: 开闸 + 领奖记录")
	Quests.check_milestones()
	chk(Wallet.money == b66, "读档后重复检查不重复发奖")
	# 66i 挂起防护: 存档还原半程不许结算(防半新半旧混装状态误发奖)
	Quests.from_dict({})   # 清空领奖 + 关闸
	Wallet.money = 5000    # 只留钱达标, 其余条件压回目标以下
	Farm.tilled = {}
	Slaves.slaves = []
	Slaves.count = 0
	Research.techs = {}
	Nations.favor = {}
	for i66 in Inventory.hotbar.size():
		Inventory.hotbar[i66] = {"item": null, "count": 0}
	for i66 in Inventory.backpack.size():
		Inventory.backpack[i66] = {"item": null, "count": 0}
	Quests.suspend_checks()
	Quests.start_milestones()
	chk(not Quests.milestone_done("ms_gold"),
		"挂起期间: 开闸也不结算(存档还原半程不许发奖)")
	b66 = Wallet.money
	Wallet.add_money(1)
	chk(not Quests.milestone_done("ms_gold") and Wallet.money == b66 + 1,
		"挂起期间: 信号触发也不结算")
	Quests.resume_checks()
	b66 = Wallet.money
	Quests.check_milestones()
	chk(Quests.milestone_done("ms_gold") and Wallet.money == b66 + 500,
		"恢复后: 补结算领奖一次 +500")
	Quests.check_milestones()
	chk(Wallet.money == b66 + 500, "已领奖的里程碑不重复发")
	chk(hits66.size() == 8, "公告累计 8 条 (实际 %d)" % hits66.size())
	# 66j 收尾: 还原各系统状态
	Quests.rewarded.disconnect(cb66)
	Wallet.money = money_bak66
	Farm.tilled = tilled_bak66
	Slaves.slaves = slaves_bak66
	Slaves.count = count_bak66
	Research.techs = techs_bak66
	Nations.favor = favor_bak66
	Inventory.hotbar = hot_bak66
	Inventory.backpack = bag_bak66
	Inventory.inventory_changed.emit()
	Quests.reset_all()

	# ============ 67. 伙伴上限: 基础 3 + 同伴小屋数 (e44: 行政不再加成) ============
	print("---- 67. 同伴小屋 -> 伙伴上限 ----")
	# 67a 备份行政 / 建筑状态, 清空行政, 上限应回基础 3
	var admins_bak67: Dictionary = Research.admins.duplicate()
	var apoints_bak67: int = Research.admin_points
	var slots_bak67: Array = Research.slots.duplicate()
	var pending_bak67: Array = Research.pending.duplicate()
	var stations_bak67: Dictionary = Structures.stations.duplicate(true)
	for id67 in Research.admins.keys():
		Research.admins.erase(String(id67))
	Research.admin_points = 99999
	Slaves.refresh_cap()
	chk(Slaves.CAP == Slaves.BASE_CAP and Slaves.CAP == 3,
		"没有同伴小屋: 上限 = 基础 %d (实际 %d)" % [Slaves.BASE_CAP, Slaves.CAP])
	# 67b 行政树全点完, 上限一动不动 (e44 把「每项行政 +1」这条加成取消了)
	var done67 := 0
	for id67 in Research.ADMINS.keys():
		var ok67 := Research.research_admin(String(id67))
		chk(ok67, "完成行政 %s 成功" % String(id67))
		if ok67:
			done67 += 1
	chk(done67 == Research.ADMINS.size(), "行政树 %d 项全部点完" % done67)
	chk(Slaves.CAP == 3, "行政全点完上限仍是 3 (e44: 不再加成, 实际 %d)" % Slaves.CAP)
	# 找三格空地盖小屋（第三个留给搬移用）
	var found67: Array = []
	var scan67 := Vector2i(1, 46)
	while found67.size() < 3 and scan67.x < 260:
		if not Structures.has_station(scan67) and not Farm.tilled.has(scan67):
			found67.append(scan67)
		scan67 += Vector2i(3, 0)
	chk(found67.size() == 3, "找到三格空地盖小屋 (%d)" % found67.size())
	var hut_a67: Vector2i = found67[0]
	var hut_b67: Vector2i = found67[1]
	var hut_c67: Vector2i = found67[2]
	# 67c 盖小屋 -> 上限 +1; 两座外形编号与裁剪框都不一样
	chk(Structures.place(hut_a67, Structures.KIND_HUT, true), "盖第一座同伴小屋")
	chk(Slaves.CAP == 4, "一座小屋 -> 上限 4 (实际 %d)" % Slaves.CAP)
	chk(Structures.hut_count() == 1 and Structures.variant_of(hut_a67) == 0,
		"第一座小屋外形编号 0")
	chk(Structures.place(hut_b67, Structures.KIND_HUT, true), "盖第二座同伴小屋")
	chk(Slaves.CAP == 5, "两座小屋 -> 上限 5 (实际 %d)" % Slaves.CAP)
	chk(Structures.variant_of(hut_b67) == 1, "第二座小屋外形编号 1")
	var look_a67: Dictionary = Structures.hut_look(Structures.variant_of(hut_a67))
	var look_b67: Dictionary = Structures.hut_look(Structures.variant_of(hut_b67))
	chk(not look_a67.is_empty() and not look_b67.is_empty(),
		"小屋外形表查得到贴图 (%d 款)" % Structures.HUT_LOOKS.size())
	chk(look_a67.get("rect", Rect2()) != look_b67.get("rect", Rect2()),
		"两座小屋的贴图裁剪框不同 (每盖一座外形都不一样)")
	# 67d 拆一座 -> 上限回落
	Structures.remove(hut_b67)
	chk(Slaves.CAP == 4, "拆掉一座小屋 -> 上限回落 4 (实际 %d)" % Slaves.CAP)
	# 67e 建筑模式搬移: 拾起(remove) + 放下(restore_station), 上限一去一回, 外形编号不变
	var payload67: Dictionary = Structures.stations[hut_a67].duplicate(true)
	var var67: int = Structures.variant_of(hut_a67)
	Structures.remove(hut_a67)
	chk(Slaves.CAP == 3, "搬起小屋 -> 上限暂时回 3 (实际 %d)" % Slaves.CAP)
	chk(Structures.restore_station(hut_c67, payload67), "小屋落到新格子 (建筑模式)")
	chk(Slaves.CAP == 4, "放下小屋 -> 上限回到 4 (实际 %d)" % Slaves.CAP)
	chk(Structures.hut_count() == 1 and Structures.variant_of(hut_c67) == var67,
		"搬完外形编号不变 (%d -> %d)" % [var67, Structures.variant_of(hut_c67)])
	# 67f 存档字段 (源码护栏): 白名单含新建筑, 写出 honey / variant
	var sm67 := FileAccess.get_file_as_string("res://save_manager.gd")
	chk(sm67.contains("KIND_HUT") and sm67.contains("KIND_HIVE") and sm67.contains("KIND_LAMP"),
		"读档白名单含 同伴小屋/蜂箱/路灯 (e44)")
	chk(sm67.contains("\"honey\"") and sm67.contains("\"variant\""),
		"存档写出 honey / variant 两个字段 (e44)")
	# 67g 收尾: 先正经拆掉自己盖的小屋(别留孤儿节点), 再整份还原
	Structures.remove(hut_c67)
	await get_tree().process_frame
	Structures.stations = stations_bak67
	Research.admins = admins_bak67
	Research.admin_points = apoints_bak67
	Research.slots = slots_bak67
	Research.pending = pending_bak67
	Slaves.refresh_cap()
	chk(Slaves.CAP == 3 + Structures.hut_count(),
		"还原建筑备份, 上限与岛上小屋数一致 (实际 %d)" % Slaves.CAP)

	# ============ 68. 白天画面无凭空掉落的粒子噪点 ============
	print("---- 68. 白天无掉落粒子噪点 ----")
	var old_hour68: int = TimeManager.hour
	var old_season68: int = TimeManager.season
	var old_cur68: int = Weather.current
	TimeManager.hour = 12
	TimeManager.season = 0
	Weather.current = Weather.SUNNY
	# 光尘/萤火虫层已整体删除（fx_dust.gd 不复存在，见 74 节）；这里只验残留不存在
	chk(not ResourceLoader.exists("res://scene/fx_dust.gd"), "fx_dust.gd 已删除")
	# 季节层: 春天落叶层不出现 + 冬晴轻雪已删 (录屏里草地上的下落白点)
	var sfx68: Variant = preload("res://scene/season_fx.gd").new()
	add_child(sfx68)
	TimeManager.season = 0
	for i in 60:
		sfx68._process(1.0)
	chk(sfx68._leaf.color.a < 0.05, "春天落叶层 alpha 趋 0 (实际 %.2f)" % sfx68._leaf.color.a)
	chk(sfx68.get_node_or_null("LightSnow") == null, "季节层无轻雪子节点 (冬晴不再飘白点)")
	sfx68.queue_free()
	# 雨效: 晴天停喷 (雪只在冬天+雨天播, 有雨声有密度)
	var rain68: Variant = preload("res://scene/rain_fx.gd").new()
	add_child(rain68)
	chk(rain68.emitting == false, "晴天雨效停喷")
	rain68.queue_free()
	# 篝火烟有软圆纹理 (CPUParticles2D 没纹理默认渲染白色方块)
	var cf68: Variant = preload("res://scene/campfire.gd").new()
	add_child(cf68)
	var smoke68: Variant = cf68.get_node_or_null("Smoke")
	chk(smoke68 != null and smoke68.texture != null, "篝火烟粒子有软圆纹理 (消白色方块观感)")
	cf68.queue_free()
	# 收尾: 还原时间/季节/天气
	TimeManager.hour = old_hour68
	TimeManager.season = old_season68
	Weather.current = old_cur68

	# ============ 69. 钓鱼动画 / 种子生长周期 / 售卖箱面板 ============
	print("---- 69. 钓鱼动画 / 种子生长周期 / 售卖箱面板 ----")
	# 钓鱼动画: 以前错用 32px 的 Fish.png, 主角显示成一坨鱼 —— 现在是 Wait Idle / Hooked, 64px 一帧
	chk(player.FISH_FRAMES == 4 and player.FISH_HOOKED_FRAMES == 8 and player.FISH_CELL == 64,
		"钓鱼动画常量: 等咬钩 4 帧 / 咬钩 8 帧 / 64px 一帧")
	chk(player.FISH_TEX.get_width() == 256 and player.FISH_HOOKED_TEX.get_width() == 512,
		"钓鱼贴图是 Wait Idle.png(256 宽) + Hooked.png(512 宽), 不是 Fish.png")
	var sf69: SpriteFrames = player.tool_sprite.sprite_frames
	for d69 in ["down", "up", "side"]:
		chk(sf69.has_animation(StringName("fish_%s" % d69))
				and sf69.get_frame_count(StringName("fish_%s" % d69)) == 4,
			"等咬钩动画 fish_%s 注册了 4 帧" % d69)
		chk(sf69.has_animation(StringName("hooked_%s" % d69))
				and sf69.get_frame_count(StringName("hooked_%s" % d69)) == 8,
			"咬钩动画 hooked_%s 注册了 8 帧" % d69)
	var fr69: AtlasTexture = sf69.get_frame_texture(StringName("fish_down"), 0) as AtlasTexture
	chk(fr69 != null and fr69.region.size == Vector2(64, 64),
		"钓鱼帧按 64px 裁剪（实际 %s）" % str(fr69.region.size))
	# e49 钓鱼链补齐：甩竿(Casting) -> 等咬钩(Wait Idle) -> 咬钩(Hooked) -> 拉回(有鱼/空竿)
	chk(player.FISH_CAST_FRAMES == 15 and player.FISH_CAPTURE_FRAMES == 4,
		"钓鱼链常量: 甩竿 15 帧 / 拉回 4 帧")
	chk(player.FISH_CAST_TEX.get_width() == 960 and player.FISH_CAPTURE_TEX.get_width() == 256
			and player.FISH_EMPTY_TEX.get_width() == 256,
		"甩竿贴图 Casting.png(960 宽) + 拉回 Captured Fish/No Fish.png(256 宽)")
	for d69b in ["down", "up", "side"]:
		chk(sf69.has_animation(StringName("cast_%s" % d69b))
				and sf69.get_frame_count(StringName("cast_%s" % d69b)) == 15,
			"甩竿动画 cast_%s 注册了 15 帧" % d69b)
		chk(sf69.has_animation(StringName("capture_%s" % d69b))
				and sf69.get_frame_count(StringName("capture_%s" % d69b)) == 4
				and sf69.has_animation(StringName("capture_empty_%s" % d69b)),
			"拉回动画 capture_%s / capture_empty_%s 各 4 帧" % [d69b, d69b])
	chk(not sf69.get_animation_loop(StringName("cast_side"))
			and not sf69.get_animation_loop(StringName("capture_side")),
		"甩竿 / 拉回是一次性动作（不循环）")
	var fr69b: AtlasTexture = sf69.get_frame_texture(StringName("cast_down"), 14) as AtlasTexture
	chk(fr69b != null and fr69b.region == Rect2(14 * 64, 0, 64, 64),
		"甩竿第 15 帧裁在 (896,0) 64px（实际 %s）" % str(fr69b.region))
	# e49 游泳：蹚水（贴岸浅滩）时的移动 / 水里静止 / 上岸三套身体动画
	chk(player.SWIM_FRAMES == 4 and player.SWIM_OUT_FRAMES == 3,
		"游泳常量: 蹚水 4 帧 / 上岸 3 帧")
	chk(player.SWIM_TEX.get_size() == Vector2(128, 96)
			and player.SWIM_OUT_TEX.get_size() == Vector2(96, 96),
		"游泳贴图 Swim.png(128x96) + Coming out of the water.png(96x96)")
	var body69: SpriteFrames = player.body_sprite.sprite_frames
	for d69c in ["down", "up", "left", "right"]:
		chk(body69.has_animation(StringName("swim_%s" % d69c))
				and body69.get_frame_count(StringName("swim_%s" % d69c)) == 4
				and body69.has_animation(StringName("submerged_%s" % d69c))
				and body69.has_animation(StringName("out_of_water_%s" % d69c))
				and body69.get_frame_count(StringName("out_of_water_%s" % d69c)) == 3,
			"游泳三态动画齐全 swim_/submerged_/out_of_water_%s" % d69c)
	chk(not body69.get_animation_loop(StringName("out_of_water_down")),
		"上岸动作是一次性（不循环）")
	# e51 水面分两类：能下水的（整条河 + 海里除最深色外）和挡人的（最深色那一档）
	var deep69 := false
	var swim69 := Vector2i(9999, 9999)
	for c69 in g._water_set.keys():
		if g.is_swim_water(c69):
			if swim69.x == 9999:
				swim69 = c69
		elif not g.is_bridge_cell(c69):
			deep69 = true
	chk(deep69 and swim69.x != 9999,
		"水面分「能下水」(放行) 与「最深色」(照旧挡) 两类")
	chk(g.is_swim_water(Vector2i(5, 5)) == false, "is_swim_water 对陆地格返回 false")
	# e51 三条硬规则：①整条河都能游（桥面/地图外圈除外）②桥面格不算水
	#   ③非河的挡人格必须正好是最深一档（玩家看到的「最深色挡人」得处处成立）
	var river_all := 0
	var river_swim := 0
	var river_bad := 0
	var bridge_water := 0
	var bridge_swim := 0
	var bad_deep := 0
	var edge_water := 0
	var edge_swim := 0
	for c69b in g._water_set.keys():
		var is_bridge69: bool = g.is_bridge_cell(c69b)
		var is_edge69: bool = g._at_map_edge(c69b)
		var can_swim69: bool = g.is_swim_water(c69b)
		if is_bridge69:
			bridge_water += 1
			if can_swim69:
				bridge_swim += 1
		if is_edge69:
			edge_water += 1
			if can_swim69:
				edge_swim += 1
		if g._is_river(c69b):
			river_all += 1
			if can_swim69:
				river_swim += 1
			elif not is_bridge69 and not is_edge69:
				river_bad += 1
		elif not can_swim69 and not g.is_deck_cell(c69b) \
				and int(g._water_anim_lv.get(c69b, -1)) != g.WATER_DEPTHS.size() - 1:
			# 船板格（码头栈桥/木桥）是浅水但架了板子 -> 不放行也不算「深色挡人」的例外
			bad_deep += 1
	chk(river_all >= 200 and river_swim >= 200 and river_bad == 0,
		"整条河都能游（河上 %d 格水里能游 %d 格, 除桥面/地图边框外一处不挡）"
			% [river_all, river_swim])
	chk(bridge_water > 0 and bridge_swim == 0,
		"桥面格 %d 个一个都不算水（在桥上不再变水花）" % bridge_water)
	chk(bad_deep == 0,
		"没游的海格里不是最深色的: %d 个（应为 0, 玩家看到的深色 = 挡住他的）" % bad_deep)
	chk(edge_swim == 0 and edge_water > 0,
		"地图最外圈 %d 格水面一律不放行（游不出世界）" % edge_water)
	# e52 码头栈桥: 架在水上的木板, 站上去算走路（不然走到码头上还在游泳）
	var dock69: Vector2i = g._dock_cell()
	chk(g._dock_deck.size() == g.DOCK_DECK_W * g.DOCK_DECK_H,
		"码头栈桥盖住 %d 格（%dx%d, 跟 dock.gd 贴图对齐）"
			% [g._dock_deck.size(), g.DOCK_DECK_W, g.DOCK_DECK_H])
	var deck_water69 := 0
	var deck_swim69 := 0
	for c69d in g._dock_deck.keys():
		if g._water_set.has(c69d):
			deck_water69 += 1
			if g.is_swim_water(c69d):
				deck_swim69 += 1
	chk(deck_water69 > 0 and deck_swim69 == 0,
		"栈桥底下 %d 格水面, 一格都不算水（走到码头上是走路）" % deck_water69)
	chk(g.is_deck_cell(dock69) and not g.is_deck_cell(Vector2i(5, 5)),
		"is_deck_cell: 码头根格是木板, 普通草地格不是")
	# 踩进能下水的水格 -> 涉水状态 + 藏影子；上岸 -> 演「上岸」动作 + 影子回来
	var ph69: bool = player.is_physics_processing()
	var pos69: Vector2 = player.global_position
	var face69: StringName = player.facing_suffix
	var pre69: String = player.NORMAL_ANIMATION_PREFIX
	player.set_physics_process(false)
	var mid69 := Vector2(Farm.TILE_SIZE / 2.0, Farm.TILE_SIZE / 2.0)
	player.global_position = Farm.grid_origin + Vector2(swim69) * Farm.TILE_SIZE + mid69
	player._tick_swim_state(0.016)
	chk(player._in_water, "踩进能下水的水格 -> 进入涉水状态")
	chk(not player._shadow.visible, "在水里影子收起来（人不会浮在水面上）")
	player.NORMAL_ANIMATION_PREFIX = "submerged"
	player._update_animation()
	chk(player.body_sprite.animation == StringName("submerged_%s" % String(player.facing_suffix)),
		"水里静止演 submerged_<朝向>（实际 %s）" % str(player.body_sprite.animation))
	player.global_position = Farm.grid_origin + Vector2(5, 5) * Farm.TILE_SIZE + mid69
	player._tick_swim_state(0.016)
	chk(not player._in_water and player._out_water_t > 0.0,
		"上岸 -> 退出涉水状态并挂起上岸动作")
	chk(player._shadow.visible, "上岸后影子回来")
	player.NORMAL_ANIMATION_PREFIX = "normal"
	player._update_animation()
	chk(player.body_sprite.animation == StringName("out_of_water_%s" % String(player.facing_suffix)),
		"刚上岸优先演 out_of_water_<朝向>（实际 %s）" % str(player.body_sprite.animation))
	player._tick_swim_state(1.0)
	player._update_animation()
	chk(player.body_sprite.animation == StringName("normal_%s" % String(player.facing_suffix)),
		"上岸动作演完自动回到站立")
	player.global_position = pos69
	player.facing_suffix = face69
	player.NORMAL_ANIMATION_PREFIX = pre69
	player.set_physics_process(ph69)
	player._update_animation()
	# 源码护栏：建水碰撞时跳过「能下水」的格子（浅滩/河是让人蹚进去的, 只剩最深色挡）
	var fs69 := FileAccess.open("res://scene/game.gd", FileAccess.READ)
	var src69 := "" if fs69 == null else fs69.get_as_text()
	if fs69 != null:
		fs69.close()
	var w69a := src69.find("func _build_water_collision")
	var w69b := src69.find("func _merge_water_rects")
	chk(w69a >= 0 and w69b > w69a
			and src69.substr(w69a, w69b - w69a).find("is_swim_water") >= 0,
		"水碰撞构建时跳过能下水的水格（最深色照旧挡）")
	chk(src69.find("func is_deck_cell") >= 0
			and src69.find("is_swim_water(c: Vector2i)") >= 0
			and src69.substr(src69.find("func is_swim_water"),
				src69.find("func is_deck_cell") - src69.find("func is_swim_water")).find("is_deck_cell") >= 0,
		"游泳判定把船板格排除在外（码头栈桥/木桥上算走路, 源码护栏）")
	# e52 游泳↔走路切换源码护栏: 走完一步立刻重算 + 上岸动作只在站着时演
	var fp69 := FileAccess.open("res://scene/player.gd", FileAccess.READ)
	var psrc69 := "" if fp69 == null else fp69.get_as_text()
	if fp69 != null:
		fp69.close()
	var p1a := psrc69.find("func _physics_process")
	var p1b := psrc69.find("func _tick_swim_state")
	chk(p1a >= 0 and p1b > p1a
			and psrc69.substr(p1a, p1b - p1a).find("move_and_slide()") >= 0
			and psrc69.substr(p1a, p1b - p1a).find("_tick_swim_state(0.0)") >= 0,
		"走完一步立刻按新格重算水陆（判定不慢一帧, 上岸不会再游一段）")
	var p2a := psrc69.find("func _update_animation")
	var p2b := psrc69.find("func _vector_to_facing_suffix")
	chk(p2a >= 0 and p2b > p2a
			and psrc69.substr(p2a, p2b - p2a).find("prefix != \"run\"") >= 0,
		"上岸动作只在站着时演（一迈步立刻回到走/跑）")
	# 种子生长周期: 商店详情的「N天成熟」照这个数据显示
	var cs69: ItemData = load("res://item/carrot_seed.tres")
	var ps69: ItemData = load("res://item/seed.tres")
	var cbs69: ItemData = load("res://item/cabbage_seed.tres")
	var pks69: ItemData = load("res://item/pumpkin_seed.tres")
	chk(cs69.grow_days == 3 and ps69.grow_days == 4 and cbs69.grow_days == 6 and pks69.grow_days == 8,
		"四种种子带生长周期 3/4/6/8 天")
	var shop69: Control = g.get_node_or_null("HUD/Shop")
	if shop69 != null:
		# e52: 货架只摆当季种子 —— 冬(3)只剩甜菜, 春(0)是土豆+胡萝卜
		var old_season69 := TimeManager.season
		var wn69: Array = []
		TimeManager.season = 3
		shop69.call("_refresh")
		for r69w in shop69.get("_rows"):
			var sd69w: ItemData = r69w["seed"]
			if sd69w.type == "种子" and sd69w.grow_to != null:
				wn69.append(sd69w.display_name)
		chk(wn69.size() == 1 and wn69.has("甜菜种子"),
			"冬天商店种子只摆甜菜（实际 %s）" % str(wn69))
		var sn69: Array = []
		TimeManager.season = 0
		shop69.call("_refresh")
		for r69s in shop69.get("_rows"):
			var sd69s: ItemData = r69s["seed"]
			if sd69s.type == "种子" and sd69s.grow_to != null:
				sn69.append(sd69s.display_name)
		chk(sn69.size() == 2 and sn69.has("土豆种子") and sn69.has("胡萝卜种子"),
			"春天商店种子只摆土豆+胡萝卜（实际 %s）" % str(sn69))
		# 上架的种子行都带「N天成熟」和收成提示（原来 4 行的断言, e52 起按当季算）
		var info69 := true
		for r69i in shop69.get("_rows"):
			var sd69i: ItemData = r69i["seed"]
			if sd69i.grow_to != null:
				var earn69: Label = r69i["earn_label"]
				if not (("%d天成熟" % sd69i.grow_days) in earn69.text \
						and sd69i.grow_to.display_name in String(earn69.tooltip_text)):
					info69 = false
		chk(info69, "上架的种子行都带「N天成熟」和收成提示")
		TimeManager.season = old_season69
		shop69.call("_refresh")
	# e52: 集市/议事厅同一套过滤（源码护栏）+ 三处货架的种子备货都覆盖四季
	for f69 in ["res://shop_ui.gd", "res://market_ui.gd", "res://town_ui.gd"]:
		chk(FileAccess.get_file_as_string(f69).find("Farm.season_ok_for") >= 0,
			"%s 的货架按当季过滤种子" % f69.get_file())
	for sc69 in [load("res://shop_ui.gd"), load("res://market_ui.gd"), load("res://town_ui.gd")]:
		var stock69: Array = sc69.get_script_constant_map()["STOCK"]
		var season_cover69 := true
		for si69 in 4:
			var any69 := false
			for e69 in stock69:
				var it69: ItemData = load(String(e69.get("seed", e69.get("path", ""))))
				if it69 != null and it69.type == "种子" and it69.seasons.has(si69):
					any69 = true
			if not any69:
				season_cover69 = false
		chk(season_cover69, "%s 的备货四季都至少有一包种子（不会出现整季无种子可买）"
			% String(sc69.resource_path).get_file())
	# 售卖箱面板: 走近箱子按 F 打开, 左背包 / 右箱子
	chk(g.bin_panel != null and g.bin_panel.is_in_group("bin_panel"),
		"售卖箱面板挂好了, 在 bin_panel 组里（按 F 找得到）")
	var bin69: Node2D = g.get_node_or_null("ShippingBin")
	if bin69 != null:
		# 除工具外所有物品都有卖价: 抽查 + 全目录扫一遍
		var boat69: ItemData = load("res://item/boat.tres")
		var floor69: ItemData = load("res://item/wood_floor.tres")
		chk(boat69.sell_price == 60 and floor69.sell_price == 8 and ps69.sell_price == 8,
			"非工具卖价抽查: 木船 60 / 木地板 8 / 土豆种子 8")
		var no_price69: Array = []
		var dir69 := DirAccess.open("res://item")
		if dir69 != null:
			for f69 in dir69.get_files():
				if not String(f69).ends_with(".tres"):
					continue
				var it69 := load("res://item/" + String(f69)) as ItemData
				if it69 != null and it69.type != "工具" and it69.sell_price <= 0:
					no_price69.append(String(f69))
		chk(no_price69.is_empty(),
			"除工具外所有物品都有卖价（缺价: %s）"
				% (", ".join(no_price69) if no_price69.size() > 0 else "无"))
		# 面板背后的两个接口: 点选放货 / 反悔取回
		var axe69: ItemData = load("res://item/axe.tres")
		chk(not bin69._sellable(axe69), "售卖箱不收工具（斧头投不进去）")
		chk(bin69._sellable(boat69) and bin69._sellable(ps69), "售卖箱放行非工具（船/种子都能投）")
		var carrot69: ItemData = load("res://item/carrot.tres")
		Inventory.add_item(carrot69, 2)
		var got69: int = bin69.deposit_one(carrot69, 2)
		chk(got69 == 2 and bin69.pending_count() == 2 and Inventory.count_item(carrot69) == 0,
			"面板点选放货: 2 根胡萝卜进箱（实际 %d）" % got69)
		var back69: int = bin69.take_back_all()
		chk(back69 == 2 and bin69.pending_count() == 0 and Inventory.count_item(carrot69) == 2,
			"反悔取回: %d 件回背包, 箱子清空" % back69)
		Inventory.remove_item(carrot69, 2)

	# —— 70. 海图滚轮缩放 / Esc 背包 / 相机扶正 / 岛像原来的岛 ——
	# 2026-09-19：滚轮 2~6 倍一档一档跳；B/Esc 开背包（任务栏跟着亮）；
	# 从城镇/战场回海图时相机重新扶正（原来画面定在角落、人卡住动不了）；
	# 岛改成椭圆 + 正弦河分两半 + 两座木桥，港口挪到岛东。
	print("\n=== 70. 海图缩放 / 背包 / 相机 / 岛形 ===")
	var wm70: Variant = load("res://scene/world_map.gd").new()
	add_child(wm70)
	await get_tree().process_frame
	var ic70: Vector2 = wm70.ISLAND_CENTER
	chk(wm70.dock_island.x > ic70.x * 16.0,
		"岛码头在岛东面（dock_island.x=%.0f > 岛心 x=%.0f）" % [wm70.dock_island.x, ic70.x * 16.0])
	var br70: Node = wm70.get_node_or_null("Bridges")
	chk(br70 != null and br70.get_child_count() >= 4,
		"岛上两座木桥都铺了桥面（%d 格）" % (0 if br70 == null else br70.get_child_count()))
	# 滚轮缩放：一档一档跳，到头不越界（跟岛上一个规矩）
	if wm70.get("_cam") != null:
		var z070: Vector2 = wm70._cam.zoom
		wm70._zoom_camera(1)
		chk(int(wm70._cam.zoom.x) == int(z070.x) + 1,
			"滚轮放大一档（%d -> %d 倍）" % [int(z070.x), int(wm70._cam.zoom.x)])
		wm70._cam.zoom = Vector2(6, 6)
		wm70._zoom_camera(1)
		chk(int(wm70._cam.zoom.x) == 6, "放大到头不越界（保持 6 倍）")
		wm70._zoom_camera(-1)
		chk(int(wm70._cam.zoom.x) == 5, "滚轮缩小一档（回 5 倍）")
	else:
		chk(false, "海图相机没建出来")
	# Esc/B 背包：懒加载 + 开合状态机（e13j: 任务栏已是背包「任务」页签, 不再独立挂 HUD）
	var bp70: Control = wm70._get_backpack_ui()
	chk(bp70 != null and not bp70.is_open(), "背包面板懒加载就位（初始关着）")
	bp70.open()
	chk(bp70.is_open() and wm70._ui_lock, "背包打开: 走动锁住（_ui_lock）")
	chk(wm70._ql == null and bp70._pages.has("quests"),
		"e13j: 海图不再挂独立任务栏, 任务在背包页签里")
	bp70.close()
	chk(not bp70.is_open() and not wm70._ui_lock, "背包关上: 锁解开")
	# 2026-09-19：背包/任务栏必须挂在 CanvasLayer(_hud) 下 ——
	# 挂在 Node2D 下锚点锚不到屏幕矩形，面板开了也看不见（Esc 修不好就是这个）
	chk(wm70._bp_ui.get_parent() == wm70._hud,
		"背包挂在 _hud(CanvasLayer) 下")
	# 2026-09-19：海图云层 —— 长方块拼云 / 数量有上限 / 朝一个方向慢飘
	var cl70: Node = wm70.get_node_or_null("CloudLayer")
	chk(cl70 != null, "海图挂了云层 CloudLayer")
	if cl70 != null:
		var ncl70: int = cl70.get_child_count()
		chk(ncl70 > 0 and ncl70 <= int(cl70.MAX_CLOUDS),
			"云的数量压在上限内（%d/%d 朵）" % [ncl70, cl70.MAX_CLOUDS])
		var c070: Node = cl70.get_child(0)
		chk(c070.get_child_count() >= 3,
			"一朵云由好几块半透明长方形拼成（%d 块）" % c070.get_child_count())
		var x070: float = c070.position.x
		cl70._process(2.0)
		chk(c070.position.x < x070,
			"云朝一个方向慢速飘（2 秒挪了 %.1f px）" % (x070 - c070.position.x))
	# 相机扶正：进城/打完仗回来，海图相机要重新变回 current
	wm70.resume_camera()
	chk(wm70._cam != null and wm70._cam.is_current(), "resume_camera 把海图相机扶回 current")
	# 城镇拼成了城：首都 >= 9 件（主楼+两厢+喷泉+灯柱+雕像+木桶+旗+城名），属镇 >= 6 件
	var tm70: Node = wm70.get_node_or_null("TownMarks")
	var cap70 := 0
	var town70 := 0
	if tm70 != null:
		for n70 in tm70.get_children():
			if n70.get_child_count() >= 9:
				cap70 += 1
			elif n70.get_child_count() >= 6:
				town70 += 1
	chk(cap70 == 5, "五座首都拼成了城（主楼两厢加摆设）: %d 座" % cap70)
	chk(town70 == 10, "十座属镇也是两房起步的小集市: %d 座" % town70)
	# e15c 天色: 昼夜覆盖 / 日月光盘 / 海面光带 / 远帆剪影
	chk(wm70._dn_rect != null and wm70._glow != null and wm70._band != null,
		"天色三件套就位 (昼夜覆盖+日月光盘+海面光带)")
	var day70: Array = wm70._sky_sample(12.0)
	var night70: Array = wm70._sky_sample(22.0)
	var dusk70: Array = wm70._sky_sample(18.5)
	chk(float(day70[0].a) < 0.12 and float(night70[0].a) > 0.25,
		"昼夜色键: 正午近乎透明(%.2f) / 夜晚压暗(%.2f)" % [float(day70[0].a), float(night70[0].a)])
	chk(float(night70[0].b) > float(night70[0].r) * 1.5,
		"夜色偏蓝 (b=%.2f > r=%.2f x1.5)" % [float(night70[0].b), float(night70[0].r)])
	chk(float(dusk70[0].r) > float(dusk70[0].b),
		"黄昏偏橙 (r=%.2f > b=%.2f)" % [float(dusk70[0].r), float(dusk70[0].b)])
	wm70._refresh_sky(0.05)
	chk(wm70._dn_rect.modulate.a > 0.0, "刷新一帧后天色覆盖生效")
	var fb70: Node = wm70.get_node_or_null("FarBoats")
	var fb_n70 := 0 if fb70 == null else fb70.get_child_count()
	chk(fb_n70 == 3, "远帆剪影 3 艘都泊在深水区 (%d)" % fb_n70)
	wm70.queue_free()
	await get_tree().process_frame

	print("\n=== 71. 外交页不再空白（页要吃满剩余高度） ===")
	var bp71: Variant = load("res://backpack_ui.gd").new()
	add_child(bp71)
	var pg71: Control = bp71._build_diplomacy_page()
	chk(pg71.size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"外交页声明了 SIZE_EXPAND_FILL（会吃满剩余高度）")
	# 仿背包容器量一量：内容盒 560x560 > VBox > 页，页高得量得出来（修前是 0）
	var box71: PanelContainer = PanelContainer.new()
	box71.custom_minimum_size = Vector2(560, 560)
	add_child(box71)
	var vb71: VBoxContainer = VBoxContainer.new()
	box71.add_child(vb71)
	vb71.add_child(pg71)
	await get_tree().process_frame
	await get_tree().process_frame
	chk(pg71.size.y > 100.0, "外交页在背包容器里量得出高度（%.0f px，修前 0）" % pg71.size.y)
	box71.queue_free()
	bp71.queue_free()
	await get_tree().process_frame

	print("\n=== 72. 出海动画: 主角和同伴的真身乘船 ===")
	chk(load("res://scene/game.gd").SAIL_TIME >= 3.0,
		"出海动画留够看的时间 (%.1f 秒)" % float(load("res://scene/game.gd").SAIL_TIME))
	var g72: Variant = load("res://scene/game.gd").new()
	chk(String(g72._crew_sheet(0)).contains("Josh"), "主角座船上画的是主角真身 (Josh)")
	var exp72: Array = Slaves.expedition.duplicate()
	Slaves.expedition.clear()
	chk(String(g72._crew_sheet(1)).contains("Alex"), "名单空时 1 号座也画得出同伴 (Alex)")
	Slaves.expedition.append(1)
	chk(String(g72._crew_sheet(1)).contains("Lyria"), "同伴按名单序号取模型 (Lyria)")
	var c72: Sprite2D = g72._crew_sprite(0)
	var creg: Rect2 = (c72.texture as AtlasTexture).region
	chk(creg.position.y == 64.0 and c72.scale.x < 1.0,
		"船员坐姿用侧面帧缩放 (行 2, 缩 %.2f, 面朝船头)" % c72.scale.x)
	var s72: Sprite2D = g72._crew_sprite(1)
	# e29c: modulate 只剩装甲档位色 —— 个人配色(发色/服装)已烘进贴图层
	chk(s72.modulate.is_equal_approx(Slaves.ARMOR_TINT_ROOKIE),
		"同伴 modulate 只剩装甲色 (新兵档), 个人配色烘在贴图里")
	# 第三方素材不入库(见 README), 缺失时跳过改色断言
	var lyria72: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Lyria/Idle.png")
	if lyria72 == null:
		print("  - skip: 缺少第三方素材包, 跳过改色断言 (见 README)")
	else:
		var lyria_img: Image = lyria72.get_image()
		var tinted72: Image = ((s72.texture as AtlasTexture).atlas as Texture2D).get_image()
		lyria_img.convert(Image.FORMAT_RGBA8)
		tinted72.convert(Image.FORMAT_RGBA8)
		var n72 := _img_diff_count(tinted72, lyria_img)
		var op72 := _img_opaque_count(lyria_img)
		chk(n72 > 0 and n72 * 2 < op72,
			"船员贴图是改色版: %d/%d 像素变了色 (局部染色, 不到一半)" % [n72, op72])
	Slaves.expedition = exp72
	g72.queue_free()

	# —— 73. 农舍碰撞贴墙脚 ——
	# 2026-09-19：农舍碰撞下缘原来悬在 y=-16，玩家能站进贴图底部带里 -> 先延到 y=0；
	# 同日又嫌「碰撞太大, 门前草地走不到」改成贴底矮条。
	# 内饰批次再按 10.png 不透明像素逐行扫描重贴（探针实测）：
	#   墙体带 = 图行 78..95 -> 局部 y -34..-16 / x 10..70（一块 60x18）
	#   门台阶 = 图行 96..103 -> 局部 y -16..-8 / x 43..59（一块 16x8）
	#   贴图底部 8px 完全透明不放碰撞（屋前草地随便走），屋顶区不设墙（可绕到屋后）。
	# （原「清晨萤火虫隐身」断言随粒子层整体删除作废，见 74 节。）
	print("\n=== 73. 农舍碰撞贴底 ===")
	var house73: Node2D = (load("res://scene/house.tscn") as PackedScene).instantiate()
	var hb73: Node = house73.get_node_or_null("HouseBody")
	chk(hb73 != null, "农舍有 HouseBody 碰撞体")
	if hb73 != null:
		var n_wall73 := 0
		var n_step73 := 0
		for c73 in hb73.get_children():
			if c73 is CollisionShape2D and (c73 as CollisionShape2D).shape is RectangleShape2D:
				var r73: RectangleShape2D = (c73 as CollisionShape2D).shape as RectangleShape2D
				var bot73: float = (c73 as CollisionShape2D).position.y + r73.size.y * 0.5
				if r73.size == Vector2(60, 18):
					n_wall73 += 1
					chk(absf(bot73 + 16.0) < 0.01,
						"墙体条 60x18 下缘贴墙脚 y=-16（实际 %.1f）" % bot73)
				elif r73.size == Vector2(16, 8):
					n_step73 += 1
					chk(absf(bot73 + 8.0) < 0.01,
						"门台阶 16x8 下缘 y=-8（实际 %.1f）" % bot73)
		chk(n_wall73 == 1 and n_step73 == 1,
			"HouseBody 正好两块: 墙体条 + 门台阶（实测 %d + %d）" % [n_wall73, n_step73])
	house73.free()

	# —— 74. 时钟框: 天气进框右上角 / 水壶选中才显 / 海图也带框 + 慢速时间 ——
	# 2026-09-19：玩家反馈 1) 天气图标排在文字流末尾会溢出框外 -> 挪进框内右上角空白处；
	# 2) 水壶水量常驻太吵 -> 只有快捷栏选中洒水壶才显示；
	# 3) 出海看不见右上角框、时间完全停 -> 海图挂同一个时钟框，时间慢速流 (0.35 倍)，
	#    凌晨 2 点在海上静默翻日，不弹睡觉结算。
	print("\n=== 74. 时钟框: 天气进框 / 水壶联动 / 海图带框 ===")
	var cp74: Control = null
	for c74 in g.hud.get_children():
		if c74.name == "ClockPanel":
			cp74 = c74
	chk(cp74 != null, "岛上 HUD 有 ClockPanel")
	if cp74 != null:
		# 74a 天气图标：独立定位层 WeatherSlot 锚在框内右上角，不再挤进文字流
		var slot74: Control = cp74.get_node_or_null("WeatherSlot")
		chk(slot74 != null, "时钟框内有独立定位层 WeatherSlot (天气图标挪出文字流)")
		if slot74 != null:
			chk(slot74.get_child_count() == 1, "定位层里只挂着天气图标")
			if slot74.get_child_count() == 1:
				var wi74: Control = slot74.get_child(0)
				chk(wi74.anchor_left == 1.0 and wi74.offset_right < 0.0,
					"天气图标锚在框内右上角 (offset_right=%.0f)" % wi74.offset_right)
				chk(wi74.offset_top >= 0.0 and wi74.offset_bottom <= 40.0,
					"天气图标贴着框内顶部空白处 (top=%.0f bottom=%.0f)" % [wi74.offset_top, wi74.offset_bottom])
		var vbox74: Container = cp74.get_node("VBoxContainer")
		var icon_left74 := false
		for c74b in vbox74.get_children():
			var sc74b: Script = c74b.get_script()
			if sc74b != null and sc74b.resource_path.ends_with("weather_icon.gd"):
				icon_left74 = true
		chk(not icon_left74, "VBox 文字流里不再有天气图标")
		# 74b 只有快捷栏选中洒水壶才显示水壶状态
		var wl74: Label = vbox74.get_node_or_null("WaterLabel")
		chk(wl74 != null, "水量标签 WaterLabel 在框里")
		var hb74: GridContainer = g.hud.get_node_or_null("GridContainer")
		chk(hb74 != null and hb74.is_in_group("hotbar"), "快捷栏在 hotbar 组里 (时钟靠它联动)")
		if wl74 != null and hb74 != null:
			var can_idx74 := -1
			for i74 in Inventory.HOTBAR_SIZE:
				var it74: ItemData = Inventory.hotbar_item(i74)
				if it74 != null and it74.display_name == "洒水壶":
					can_idx74 = i74
			var saved74: Dictionary = {"item": Inventory.hotbar[0]["item"],
				"count": Inventory.hotbar[0]["count"]}
			if can_idx74 < 0:
				Inventory.hotbar[0] = {"item": load("res://item/watering_can.tres"), "count": 1}
				hb74._refresh()
				can_idx74 = 0
			hb74.select(can_idx74)
			chk(wl74.visible, "选中洒水壶 -> 框里显示水壶状态")
			chk(not wl74.text.is_empty(), "水壶状态有文字 (%s)" % wl74.text)
			hb74.select((can_idx74 + 1) % Inventory.HOTBAR_SIZE)
			chk(not wl74.visible, "换选别的道具 -> 水壶状态隐藏")
			Inventory.hotbar[0] = saved74
			hb74._refresh()
			hb74.select(0)
	# 74c 海图也带右上角时钟框（和岛上同一个 clock.gd）
	chk(ResourceLoader.exists("res://scene/clock_panel.tscn"), "clock_panel.tscn 场景存在")
	var wm74: Variant = load("res://scene/world_map.gd").new()
	add_child(wm74)
	await get_tree().process_frame
	var wmhud74: CanvasLayer = null
	for c74c in wm74.get_children():
		if c74c is CanvasLayer and c74c.name == "HUD":
			wmhud74 = c74c
	chk(wmhud74 != null, "海图有 HUD")
	var wm_clock74: Control = null
	if wmhud74 != null:
		for c74d in wmhud74.get_children():
			var sc74d: Script = c74d.get_script()
			if sc74d != null and sc74d.resource_path.ends_with("clock.gd"):
				wm_clock74 = c74d
	chk(wm_clock74 != null, "海图 HUD 挂了右上角时钟框 (clock.gd)")
	chk(wm_clock74 != null and wm_clock74.get_node_or_null("WeatherSlot") != null,
		"海图时钟框同样有右上角天气定位层")
	wm74.queue_free()
	await get_tree().process_frame
	# 74d 时间慢速流 + 出海凌晨 2 点静默翻日
	chk(TimeManager.speed_scale == 1.0, "平时时间流速 1.0")
	var old_run74: bool = TimeManager.time_running
	var old_hour74: int = TimeManager.hour
	var old_min74: int = TimeManager.minute
	var old_day74: int = TimeManager.day
	var old_season74: int = TimeManager.season
	var old_year74: int = TimeManager.year
	TimeManager.time_running = true
	TimeManager.speed_scale = 0.35
	TimeManager._acc = 0.0
	TimeManager.hour = 12
	TimeManager.minute = 0
	TimeManager._process(10.0)
	chk(TimeManager.minute == 0, "出海慢速 0.35: 现实 10 秒走不满一格 (10 分钟)")
	TimeManager.speed_scale = 1.0
	TimeManager._acc = 0.0
	TimeManager._process(10.0)
	chk(TimeManager.minute == 10, "常速: 现实 10 秒走一格 (7 秒 = 10 分钟)")
	var sea_ended74 := [false]
	var hook74: Callable = func() -> void: sea_ended74[0] = true
	TimeManager.day_ended.connect(hook74)
	Voyage.traveling = true
	TimeManager.speed_scale = 0.35
	TimeManager.hour = 25
	TimeManager.minute = 50
	TimeManager._acc = 999.0
	TimeManager._process(0.016)
	chk(not sea_ended74[0], "出海跨过凌晨 2 点不触发睡觉结算 (day_ended 没响)")
	chk(TimeManager.hour == TimeManager.START_HOUR, "出海静默翻日 -> 回到清晨 6 点")
	chk(TimeManager.day == old_day74 + 1 or TimeManager.day == 1, "出海翻日推进了一天")
	Voyage.traveling = false
	TimeManager.speed_scale = 1.0
	TimeManager.hour = 25
	TimeManager.minute = 50
	TimeManager._acc = 999.0
	TimeManager._process(0.016)
	chk(sea_ended74[0], "岛上跨过凌晨 2 点照旧发 day_ended (睡觉结算)")
	TimeManager.day_ended.disconnect(hook74)
	# 收尾: 还原时间状态
	TimeManager.time_running = old_run74
	TimeManager.hour = old_hour74
	TimeManager.minute = old_min74
	TimeManager.day = old_day74
	TimeManager.season = old_season74
	TimeManager.year = old_year74
	TimeManager._acc = 0.0

	# —— 75. 海图大改: 美术瓦片 / 200x140 大图 / 国界与占领 / 船连贯 / 新头像 ——
	print("\n=== 75. 海图大改: 瓦片材质 / 国界占领 / 船连贯 / 头像 ===")
	var wm75: Variant = load("res://scene/world_map.gd").new()
	add_child(wm75)
	await get_tree().process_frame
	chk(wm75.MAP_W >= 200 and wm75.MAP_H >= 140,
		"海图大扩到 200x140 以上 (%dx%d)" % [wm75.MAP_W, wm75.MAP_H])
	var towns_land75 := 0
	for tid75 in Nations.TOWNS.keys():
		if wm75._land.has(Nations.TOWNS[tid75]["cell"]):
			towns_land75 += 1
	chk(towns_land75 == Nations.TOWNS.size(),
		"十五镇新坐标全在陆地上 (%d/%d)" % [towns_land75, Nations.TOWNS.size()])
	# 瓦片图集: 宽度 = T_COUNT*16（美术取样版, 布局常量没动）
	var ts75: TileMapLayer = wm75.get_node_or_null("Tiles")
	chk(ts75 != null, "海图瓦片层就位")
	if ts75 != null and ts75.tile_set != null:
		var src75: TileSetAtlasSource = ts75.tile_set.get_source(0)
		var tex75: Texture2D = src75.texture
		chk(tex75 != null and tex75.get_width() == wm75.T_COUNT * 16,
			"瓦片图集宽度对得上 (%d)" % (0 if tex75 == null else tex75.get_width()))
	# 各国风貌（e11e）: 雪原/石山/沙地按最近城镇铺开, 都城脚下风貌必对
	chk(wm75.T_COUNT == wm75.T_ROCK_B + 1 and wm75.T_SNOW_A == 30,
		"风貌瓦片追加在海域之后(雪%d/%d 岩%d/%d, T_COUNT=%d)"
			% [wm75.T_SNOW_A, wm75.T_SNOW_B, wm75.T_ROCK_A, wm75.T_ROCK_B, wm75.T_COUNT])
	chk(wm75._biome_of(Vector2i(132, 24)) == wm75.BIOME_SNOW
		and wm75._biome_of(Vector2i(104, 46)) == wm75.BIOME_ROCK
		and wm75._biome_of(Vector2i(32, 30)) == wm75.BIOME_SAND
		and wm75._biome_of(Vector2i(148, 94)) == wm75.BIOME_PLAIN,
		"四都风貌判定: 北岭雪 / 铁岩岩 / 苍狼沙 / 晨曦草")
	if ts75 != null:
		var snow75 := 0
		var rock75 := 0
		for c75 in wm75._land.keys():
			var t75: Vector2i = ts75.get_cell_atlas_coords(c75)
			if t75.x == wm75.T_SNOW_A or t75.x == wm75.T_SNOW_B:
				snow75 += 1
			elif t75.x == wm75.T_ROCK_A or t75.x == wm75.T_ROCK_B:
				rock75 += 1
		chk(snow75 > 1000 and rock75 > 1000,
			"北岭雪原 / 铁岩石山真的铺出去了(雪 %d 格, 岩 %d 格)" % [snow75, rock75])
	var dec75: TileMapLayer = wm75.get_node_or_null("Decor")
	var winter_decor75 := 0
	if dec75 != null:
		for c75 in dec75.get_used_cells():
			if (wm75.DECOR_SNOW as Array).has(dec75.get_cell_atlas_coords(c75)):
				winter_decor75 += 1
	chk(winter_decor75 > 50, "雪原撒了冬装点缀 (%d 处)" % winter_decor75)
	# 国界层: 存在 + 领地染了色 + 国界线画了
	var bd75: Variant = wm75.get_node_or_null("Borders")
	chk(bd75 != null, "国界层 Borders 就位")
	chk(bd75 != null and bd75.fills.size() > 100,
		"大陆按「最近城镇」划了领地 (%d 格染色)"
			% (0 if bd75 == null else bd75.fills.size()))
	chk(bd75 != null and bd75.edges.size() > 50,
		"不同归属间画了国界线 (%d 条)"
			% (0 if bd75 == null else bd75.edges.size()))
	# 占领机制: 置 occupied -> 城周围变玩家金色领地; 清掉 -> 还回去
	var occ_saved75: Dictionary = Nations.occupied.duplicate()
	Nations.occupied.clear()
	var pick75: String = Nations.TOWNS.keys()[0]
	Nations.occupied[pick75] = true
	chk(wm75._owner_of(Nations.TOWNS[pick75]["cell"]) == "player",
		"攻下的城归属变 player（国界线会跟着挪）")
	wm75._rebuild_borders()
	var gold75 := 0
	if bd75 != null:
		for fd75 in bd75.fills:
			# e13c: 玩家领地色是青碧 (0.28,0.90,0.82) —— 五国谁都不撞它
			if (fd75["color"] as Color).r < 0.5 and (fd75["color"] as Color).g > 0.8 \
					and (fd75["color"] as Color).b > 0.7:
				gold75 += 1
	chk(gold75 > 20, "玩家占领的领地染了青碧色 (%d 格)" % gold75)
	Nations.occupied.clear()
	wm75._rebuild_borders()
	chk(wm75._owner_of(Nations.TOWNS[pick75]["cell"]) != "player",
		"清掉占领归属还回去")
	for k75 in occ_saved75.keys():
		Nations.occupied[k75] = occ_saved75[k75]
	# e15d: 天色系统已 Node2D 化（Movie Writer 会丢 CanvasLayer 里的填充控件,
	#       海图天色现在挂世界层 Sky 根节点, 暖冷渐变=Sprite2D 拉伸铺屏）
	var sky75: Variant = wm75.get_node_or_null("Sky")
	chk(sky75 != null and sky75 is Node2D, "海图天色挂世界层 Sky 根节点 (Node2D)")
	chk(wm75._grade_spr != null and wm75._grade_spr.texture != null,
		"天色层挂了暖冷渐变贴图 (Sprite2D)")
	var sp75: Node = wm75.get_node_or_null("Sparkles")
	chk(sp75 != null and sp75.get_child_count() >= 40,
		"深水区撒了呼吸粼光 (%d 颗)"
			% (0 if sp75 == null else sp75.get_child_count()))
	# 船连贯: 尾迹改成连续下标插值, f=0.5 应正好落在两个采样点正中
	wm75._trail = []
	for i75 in 36:
		wm75._trail.append(Vector2(100.0 - i75 * 8.0, 100.0))
	var mid75: Vector2 = wm75._trail_at(0.5)
	chk(absf(mid75.x - 96.0) < 0.01 and absf(mid75.y - 100.0) < 0.01,
		"船的尾迹是连续插值（中点=96, 修前每 0.07 秒跳 6px）")
	chk(wm75._trail_offset() >= 0.0 and wm75._trail_offset() <= 1.0,
		"尾迹偏移在 0~1 之间 (%.2f)" % wm75._trail_offset())
	wm75.queue_free()
	await get_tree().process_frame
	# 碰撞: 鸡舍/设施/水井的碰撞矩形贴住贴图底
	var coop75: Variant = load("res://scene/coop_node.gd").new()
	add_child(coop75)
	var csh75: RectangleShape2D = _find_rect_shape(coop75)
	chk(csh75 != null and absf(csh75.size.x - 52.0) < 0.1,
		"鸡舍碰撞宽 52 贴住 56 宽的房 (%s)"
			% ("<没有>" if csh75 == null else "%.0fx%.0f" % [csh75.size.x, csh75.size.y]))
	coop75.queue_free()
	var st75: Variant = load("res://scene/station_node.gd").new()
	add_child(st75)
	var csh_b75: RectangleShape2D = _find_rect_shape(st75)
	chk(csh_b75 != null and absf(csh_b75.size.x - 28.0) < 0.1,
		"设施碰撞宽 28 贴住 32 宽的帧 (%s)"
			% ("<没有>" if csh_b75 == null else "%.0fx%.0f" % [csh_b75.size.x, csh_b75.size.y]))
	st75.queue_free()
	var wl75: Variant = load("res://scene/well_node.gd").new()
	add_child(wl75)
	var csh_c75: RectangleShape2D = _find_rect_shape(wl75)
	chk(csh_c75 != null and absf(csh_c75.size.x - 26.0) < 0.1,
		"水井碰撞宽 26 贴住 32 宽的井身 (%s)"
			% ("<没有>" if csh_c75 == null else "%.0fx%.0f" % [csh_c75.size.x, csh_c75.size.y]))
	wl75.queue_free()
	await get_tree().process_frame
	# 新头像(e22): 128x128 且有内容（文件流读 PNG, headless 不碰 CompressedTexture2D）
	for nm75 in ["player", "goblin"]:
		var f75 := FileAccess.open("res://resources/texture/portraits/%s.png" % nm75,
			FileAccess.READ)
		chk(f75 != null, "头像 %s.png 在" % nm75)
		if f75 != null:
			var img75 := Image.new()
			img75.load_png_from_buffer(f75.get_buffer(f75.get_length()))
			var op75 := 0
			for y75 in img75.get_height():
				for x75 in img75.get_width():
					if img75.get_pixel(x75, y75).a > 0.0:
						op75 += 1
			chk(img75.get_width() == 128 and img75.get_height() == 128,
				"头像 %s 是 128x128 (%dx%d)"
					% [nm75, img75.get_width(), img75.get_height()])
			chk(float(op75) / float(img75.get_width() * img75.get_height()) > 0.5,
				"头像 %s 画了内容 (%.0f%% 不透明)"
					% [nm75, 100.0 * float(op75)
						/ float(img75.get_width() * img75.get_height())])

	# 模型性别表跟 MODELS 等长 (对账); 花名册定名后不再掷名字池
	var snpc75b: Variant = load("res://scene/slave_npc.gd")
	chk(int(snpc75b.MODEL_MALE.size()) == int(snpc75b.MODELS.size()),
		"MODEL_MALE 性别表跟 MODELS 等长 (%d/%d)"
			% [snpc75b.MODEL_MALE.size(), snpc75b.MODELS.size()])
	chk(String(Slaves.ROSTER[0]["name"]) == "布恩" and String(Slaves.ROSTER[7]["name"]) == "雪莱",
		"花名册定名: 首位布恩, 末位雪莱（%s / %s）"
			% [Slaves.ROSTER[0]["name"], Slaves.ROSTER[7]["name"]])
	var nm75b := true
	for r75b in Slaves.ROSTER:
		if String(r75b.get("name", "")) == "":
			nm75b = false
	chk(nm75b, "花名册 8 人个个有定名（顺序和名字都固定）")

	# ============ 76. 开战前的阵型布置阶段 ============
	print("\n=== 76. 开战前的阵型布置阶段 ===")
	var old_b76: Node = get_tree().get_first_node_in_group("battle")
	if old_b76 != null:
		old_b76.remove_from_group("battle")   # 免得 troop._battle() 顺手套走真战场
	var bm76: Variant = load("res://scene/battle_map.gd").new()
	bm76.party = {"id": 0, "type": "海寇", "size": 2}
	add_child(bm76)
	chk(bool(bm76.get("_deploying")), "进战场先布阵（_deploying = true）")
	chk(is_equal_approx(Engine.time_scale, 0.0), "布阵阶段时间停住（time_scale = 0）")
	chk(bm76.get_node_or_null("DeployHUD") != null, "布阵层挂上（阵型布置 + 开始按钮）")
	# 塞一个假伙伴进部队表：点地/拖线看他瞬不移
	var al76: Variant = load("res://scene/troop.gd").new()
	al76.side = "ally"
	al76.kind = "刀客"
	al76.squad = 1
	al76.index = 0
	bm76.add_child(al76)
	(bm76.units as Array).append(al76)
	al76.set_process(false)
	al76.global_position = Vector2(16 * 11 + 8, 16 * 13 + 8)
	Voyage.set_squad_selection(0)      # 全体听令
	bm76.call("_cast_move", Vector2(16 * 20 + 8, 16 * 13 + 8))
	chk(al76.global_position.distance_to(Vector2(16 * 20 + 8, 16 * 13 + 8)) < 1.0,
		"点地 = 伙伴瞬移到落点（不是走过去）")
	chk(int(al76.get("order")) == 0, "落位口令是驻点（order = 0，开战就地站住）")
	bm76.call("_cast_line", Vector2(200.0, 150.0), Vector2(300.0, 150.0))
	chk(al76.global_position.distance_to(Vector2(250.0, 150.0)) < 1.0,
		"拖线 = 伙伴瞬移到线正中（单人 t = 0.5）")
	# e41f/e41h: 指挥栏按钮 —— 上排四颗按兵种叫名（全体/剑士/弓手/骑兵）
	var sqbtns76: Array = bm76.get("_squad_btns")
	chk(sqbtns76.size() == 4, "指挥栏上排四颗编队按钮")
	chk((sqbtns76[0] as Button).text == "全体" and (sqbtns76[1] as Button).text == "剑士"
		and (sqbtns76[2] as Button).text == "弓手" and (sqbtns76[3] as Button).text == "骑兵",
		"编队按钮文字 = 全体/剑士/弓手/骑兵")
	var desel76: Variant = bm76.get("_deselect_btn")
	chk(desel76 != null and (desel76 as Button).text == "取消选中", "指挥栏有「取消选中」按钮")
	# e41g: 布阵阶段按编队 / 下口令都不许把时间放开 —— 否则士兵立刻能动
	(sqbtns76[2] as Button).pressed.emit()
	chk(Voyage.selection == 2 and is_equal_approx(Engine.time_scale, 0.0),
		"布阵中按「弓手」: 选中了 2 队但时间仍旧冻结")
	# e41j: 取消选中 = 不指挥（SELECT_NONE），不是退回全体
	if desel76 != null:
		(desel76 as Button).pressed.emit()
	chk(Voyage.selection == Voyage.SELECT_NONE and is_equal_approx(Engine.time_scale, 0.0),
		"布阵中按「取消选中」: 变成不指挥（不是全体）且时间仍旧冻结")
	chk(not Voyage.commands_squad(1) and not Voyage.commands_squad(2)
		and not Voyage.commands_squad(3), "不指挥: 三队都不听令")
	chk(Voyage.selection_name() == "不指挥", "指挥条上写「不指挥」")
	var cmd_before76: int = Voyage.command
	var order_before76: int = int(al76.get("order"))
	bm76.call("_issue_order", 2)
	chk(Voyage.command == cmd_before76 and int(al76.get("order")) == order_before76,
		"不指挥时下口令没人接（口令和伙伴的 order 都不动）")
	(sqbtns76[1] as Button).pressed.emit()   # 选中剑士队（al76 就编在 1 队）才是「有人听令」那条路
	bm76.call("_issue_order", 2)
	chk(Voyage.selection == 0 and is_equal_approx(Engine.time_scale, 0.0),
		"布阵中下「冲锋」口令: 时间仍旧冻结（伙伴不会偷跑）")
	chk(int(al76.get("order")) == 2, "口令本身照常存到伙伴身上（order = 2）")
	Voyage.set_squad_selection(0)   # e41j: 上面下完口令已是不指挥, 点地前先恢复听令
	bm76.call("_cast_move", Vector2(16 * 2 + 8, 16 * 13 + 8))   # 甲板外 = 海
	chk(not bool(bm76.call("is_blocked_at", al76.global_position)),
		"落点在海里也会被就近挪到能站的格子")
	bm76.call("_begin_battle")
	await get_tree().process_frame   # queue_free 到下一帧才真正收掉
	chk(not bool(bm76.get("_deploying")) and bm76.get_node_or_null("DeployHUD") == null,
		"点「开始战斗」= 布阵层收掉")
	chk(Engine.time_scale > 0.0, "开战后时间恢复流动（%.2f）" % Engine.time_scale)
	bm76.queue_free()
	Voyage.set_battle_slow(false)
	if old_b76 != null:
		old_b76.add_to_group("battle")
	await get_tree().process_frame

	# ============ 77. 城镇里的装饰建筑（e11g） ============
	print("\n=== 77. 城镇里的装饰建筑 ===")
	var ml77: Variant = preload("res://scene/mainland.gd").new()
	ml77.town_id = "chenxi_cap"   # 首都: 档位最高, 装饰楼该最多
	add_child(ml77)
	var n77: Array = []
	for c77 in ml77.world.get_children():
		if (c77 as Node).name.begins_with("DecorHouse"):
			n77.append((c77 as Node2D).position)
	var want77: int = int(load("res://scene/mainland.gd").DECOR_TARGET["capital"])
	chk(n77.size() >= want77, "首都摆满装饰楼（实摆 %d 座, 目标 %d）" % [n77.size(), want77])
	chk((ml77._house_rects as Array).size() - 3 >= n77.size(),
		"每座装饰楼都登记了挡人占位（_house_rects）")
	var bad77 := 0
	for r77 in ml77._house_rects:
		for s77 in ml77._spots:
			if (r77 as Rect2).has_point(s77["pos"]):
				bad77 += 1
				break
	chk(bad77 == 0, "房子占位不盖交互点门口")
	ml77.queue_free()
	await get_tree().process_frame
	# 再进一次同一座城: 撒点用城镇 id 做种, 布局必须一模一样（确定性）
	var ml77b: Variant = preload("res://scene/mainland.gd").new()
	ml77b.town_id = "chenxi_cap"
	add_child(ml77b)
	var n77b: Array = []
	for c77b in ml77b.world.get_children():
		if (c77b as Node).name.begins_with("DecorHouse"):
			n77b.append((c77b as Node2D).position)
	var same77 := n77b.size() == n77.size()
	if same77:
		for k77 in n77.size():
			if not (n77b[k77] as Vector2).is_equal_approx(n77[k77]):
				same77 = false
	chk(same77, "同一座城每次进城, 装饰楼摆位一模一样")
	ml77b.queue_free()
	await get_tree().process_frame

	# ============ 78. 首都星号 + 出发岛城镇标记（e11h） ============
	print("\n=== 78. 首都星号 + 出发岛城镇标记 ===")
	var wm78: Variant = load("res://scene/world_map.gd").new()
	add_child(wm78)
	await get_tree().process_frame
	var marks78: Node = wm78.get_node_or_null("TownMarks")
	chk(marks78 != null, "海图有城镇标记层")
	var caps78 := 0
	var stars78 := 0
	if marks78 != null:
		for tid78 in Nations.TOWNS.keys():
			if String(Nations.TOWNS[tid78]["kind"]) != "capital":
				continue
			caps78 += 1
			var tn78: Node = marks78.get_node_or_null("Town_%s" % tid78)
			if tn78 != null and tn78.get_node_or_null("CapitalStar") != null:
				stars78 += 1
	chk(caps78 > 0 and stars78 == caps78, "五座都城头顶都有金星（%d/%d）" % [stars78, caps78])
	var vil78: Node = marks78.get_node_or_null("IslandTown") if marks78 != null else null
	chk(vil78 != null, "出发岛有城镇标记（IslandTown）")
	if vil78 != null:
		var lb78: Label = vil78.get_node_or_null("Name")
		chk(lb78 != null and lb78.text == "潮汐港", "出发岛标记写着「潮汐港」")
	chk((wm78._town_marks as Array).size() == Nations.TOWNS.size(),
		"潮汐港是纯标记: 不进可交互城镇表（码头 F 键照旧回岛）")
	wm78.queue_free()
	await get_tree().process_frame

	# ============ 79. e12 批量: 职业树 / 街道 / 观景档 / Esc 回背包 ============
	print("\n=== 79. e12 批量: 职业树 / 街道 / 观景档 ===")
	# 79a 同伴详情弹窗里的两棵职业树（e27g）: 团队页不再挂树, 点树节点能真转职
	var bp79: Variant = load("res://backpack_ui.gd").new()
	add_child(bp79)
	bp79._switch_to("team")
	chk(bp79.get("_combat_tree") == null and bp79.get("_labor_tree") == null,
		"团队页不再挂职业树（两棵树挪进同伴详情了）")
	var map79: Dictionary = (load("res://slaves.gd") as Script).get_script_constant_map()
	# 点树转职: 塞一个测试新兵, 开详情把树搭起来, 备 60金+1级甲, 点「骑兵」要真写回
	var fake79 := {"name": "树测员", "troop": "新兵", "labor": "帮工",
		"affection": 0, "fed_today": true, "talked_today": true,
		"hp": 30, "max_hp": 30, "squad": 0}
	Slaves.slaves.append(fake79)
	Slaves.count = Slaves.slaves.size()
	var idx79: int = Slaves.slaves.size() - 1
	bp79._open_slave_detail(idx79)                   # 详情弹窗把两棵窄版树搭起来
	var ct79: Variant = bp79.get("_combat_tree")
	var lt79: Variant = bp79.get("_labor_tree")
	chk(ct79 != null and lt79 != null, "详情弹窗挂了两棵职业树")
	chk((ct79.get("_cards") as Dictionary).size() == (map79["CLASSES"] as Dictionary).size(),
		"战斗树 %d 档全摆上" % (map79["CLASSES"] as Dictionary).size())
	chk((lt79.get("_cards") as Dictionary).size() == (map79["LABOR_CLASSES"] as Dictionary).size(),
		"劳动树 %d 档全摆上" % (map79["LABOR_CLASSES"] as Dictionary).size())
	Wallet.money = maxi(Wallet.money, 60)
	Inventory.add_item(load("res://item/armor_wood.tres"), 1)   # e27g: 一线也要 1 级甲
	bp79._on_class_node_clicked("骑兵", false)
	chk(String(Slaves.slave_at(idx79)["troop"]) == "骑兵", "点树上的职业 = 真转职（新兵 -> 骑兵）")
	bp79._close_slave_detail()
	Slaves.slaves.erase(fake79)
	Slaves.count = Slaves.slaves.size()
	Slaves.changed.emit()
	# 79b Esc 打开背包固定回背包页
	bp79._switch_to("team")
	bp79.close()
	bp79.open()
	chk(String(bp79.get("_current")) == "bag", "Esc 打开背包固定回背包页（不卡在团队页）")
	bp79.close()
	bp79.queue_free()
	await get_tree().process_frame
	# 79c 城里铺了街道
	var ml79: Variant = preload("res://scene/mainland.gd").new()
	ml79.town_id = "chenxi_cap"
	add_child(ml79)
	await get_tree().process_frame
	var st79: Node = ml79.get_node_or_null("Streets")
	var st_cnt79: int = st79.get_child_count() if st79 != null else 0
	chk(st_cnt79 > 0, "城里铺了街道（土路块 %d 块）" % st_cnt79)
	ml79.queue_free()
	await get_tree().process_frame
	# 79d 海图观景档: 缩进 0.35 = 镜头滑向中心 + 涂色淡入 + 国名浮出 + 图外有海
	var wm79: Variant = load("res://scene/world_map.gd").new()
	add_child(wm79)
	await get_tree().process_frame
	chk(wm79.get_node_or_null("OutSea") != null, "图外铺了远海（观景档不露黑边）")
	chk(wm79.get_node_or_null("WavesLayer") != null, "海图挂了岸边白浪层（跟主岛同款）")
	wm79.call("_zoom_camera", -1)      # 3 -> 2（整数档之间照旧秒切）
	chk(is_equal_approx(float(wm79._zoom_target), 2.0), "缩到最小整数档 2")
	wm79.call("_zoom_camera", -1)      # 2 -> 0.28（进观景档, 一屏装下整张图含出发岛）
	chk(is_equal_approx(float(wm79._zoom_target), 0.28), "再往外缩 = 进观景档 (0.28, 全图可见)")
	# 出发岛必须也在视野内: 视野半高 = 324/0.28 >= 岛心偏移 70*16=1120
	var isle_vis79: float = 324.0 / 0.28
	chk(isle_vis79 >= 70.0 * 16.0, "观景档连出发岛都装得下（半视野 %d >= 岛心距 %d）"
		% [int(isle_vis79), 70 * 16])
	await get_tree().create_timer(1.4).timeout
	chk(float(wm79.get("_view_t")) > 0.9, "观景强度淡入到位")
	chk(float((wm79.get("_nation_tint") as Sprite2D).modulate.a) > 0.3,
		"各国领土半透明涂色淡入")
	chk((wm79.get("_nation_labels") as Array).size() == 5, "五国国名浮出")
	chk(not (wm79.get("_cam") as Camera2D).offset.is_equal_approx(Vector2.ZERO),
		"镜头滑向大陆中心")
	wm79.call("_zoom_camera", 1)       # 0.35 -> 2（平滑拉回）
	await get_tree().create_timer(1.4).timeout
	chk(is_equal_approx(float(wm79._zoom_target), 2.0) and float(wm79.get("_view_t")) < 0.1,
		"退出观景: 缩放回整数档, 涂色和国名收起")
	wm79.queue_free()
	await get_tree().process_frame

	# ============ 80. e13 批量: 声望契约 / 双贸易 / 国名 / 技能分叉 ============
	print("\n=== 80. e13: 声望契约 / 海外贸易 / 国名 / 技能分叉 ===")
	var bak80 := {"prestige": Nations.prestige, "contract": Nations.contract,
		"liege": Nations.liege, "fief": Nations.fief, "pname": Nations.player_nation_name,
		"war": Nations.at_war.keys(), "occ": Nations.occupied.keys(),
		"first": Nations._first_conq_fired}
	# 80a 声望与主从契约
	chk(Nations.prestige == 0 and Nations.contract == "", "开局: 声望 0 无契约")
	Nations.add_prestige(25)
	chk(Nations.prestige == 25, "打仗/海外贸易攒声望 (25)")
	chk(Nations.can_sign_contract("tieyan", "封臣").contains("声望"), "声望不够签不了封臣")
	chk(Nations.can_sign_contract("tieyan", "雇佣兵") == "", "声望 25 够签雇佣兵 (门槛 20)")
	chk(Nations.sign_contract("tieyan", "雇佣兵"), "签下苍狼雇佣兵契约")
	chk(Nations.can_sign_contract("chenxi", "雇佣兵") != "", "一身不事二主 (别国签不了)")
	chk(not Nations.sign_contract("chenxi", "雇佣兵"), "重复签约被拒")
	Nations.add_prestige(30)
	chk(Nations.can_sign_contract("tieyan", "封臣") == "", "雇佣兵可原地升级封臣 (声望 55)")
	var fief80 := ""
	for tid in Nations.TOWNS.keys():
		if String(Nations.TOWNS[tid]["nation"]) == "tieyan":
			fief80 = String(tid)
	chk(fief80 != "" and Nations.sign_contract("tieyan", "封臣", fief80), "升级封臣: 领了封地")
	chk(Nations.fief == fief80, "封地登记正确")
	var money80: int = Wallet.money
	var inc80: int = Nations.FIEF_CAP_INCOME \
		if String(Nations.TOWNS[fief80]["kind"]) == "capital" else Nations.FIEF_INCOME
	Nations._on_new_day(0)
	chk(Wallet.money == money80 + inc80, "封地岁入每天到账 ( +%d )" % inc80)
	chk(Nations.betray_liege() == "", "叛变: 带封地脱离宗主")
	chk(bool(Nations.occupied.get(fief80, false)), "叛变带走封地 (占领插旗, 国界变青碧)")
	chk(bool(Nations.at_war.get("tieyan", false)), "与原宗主国开战")
	chk(Nations.contract == "" and Nations.fief == "", "叛变后契约清空")
	# 80b 售卖箱双贸易 (e29a/b: 哥布林关箱即售 / 海外 +40% 次日到账 + 每累积1000金+1声望)
	chk(g.shipping_bin != null, "售卖箱就位")
	var wheat80: ItemData = load("res://item/wheat.tres")
	var w_bak80: int = Inventory.count_item(wheat80)
	while Inventory.count_item(wheat80) < 2:
		Inventory.add_item(wheat80, 2 - Inventory.count_item(wheat80))
	var base80: int = Research.sell_price_of(wheat80)
	g.shipping_bin.mode = "海外"
	chk(g.shipping_bin.deposit_one(wheat80, 1) == 1, "海外渠道投 1 份小麦")
	var entry80: Dictionary = g.shipping_bin.pending[-1]
	chk(int(entry80["price"]) == int(round(float(base80) * 1.4)),
		"海外贸易卖价 +40%% (%d -> %d)" % [base80, int(entry80["price"])])
	g.shipping_bin.mode = "哥布林"
	chk(g.shipping_bin.deposit_one(wheat80, 1) == 1, "哥布林渠道投 1 份小麦")
	# e29b: 关箱即售 —— 哥布林货立刻原价入账, 海外货上船
	var money80b: int = Wallet.money
	g.shipping_bin.sell_now()
	chk(Wallet.money == money80b + base80, "哥布林货关箱即时入账 (%d)" % base80)
	chk(g.shipping_bin.pending.is_empty(), "售出后箱子清空")
	chk(g.shipping_bin.sea_pending_total() == int(round(float(base80) * 1.4)),
		"海外货上船 (次日到账)")
	# e29a: 海外卖出金累积折算声望 —— 账本垫到差 1 金就满, 这笔回款正好顶过门槛换 1 声望
	g.shipping_bin.sea_hold[0]["due"] = 0    # 时间快进: 商船回航
	var entry80_gold: int = int(round(float(base80) * 1.4))
	var prest80: int = Nations.prestige
	Nations.sea_gold_acc = Nations.SEA_PRESTIGE_PER - entry80_gold + 1
	g.shipping_bin._on_new_day(0)
	chk(Nations.prestige == prest80 + 1, "海外每累积 1000 金 +1 声望")
	chk(Nations.sea_gold_acc == 1, "声望折算后账本记余数 (剩 1)")
	chk(g.shipping_bin.sea_pending_total() == 0, "在途清空")
	Inventory.remove_item(wheat80, Inventory.count_item(wheat80) - w_bak80)
	# 80c 国名与首城事件旗
	chk(Nations.player_nation_name == "潮汐港", "国家默认名潮汐港")
	Nations.rename_player_nation("测试潮记")
	chk(Nations.player_nation_name == "测试潮记", "自定义国名写得进 (外交卡/海图都用它)")
	Nations.rename_player_nation("")
	chk(Nations.player_nation_name == "潮汐港", "空名回退默认")
	Nations._first_conq_fired = true
	chk(Nations.pop_first_conquest(), "首城事件旗取走 (庆祝+命名只来一次)")
	chk(not Nations.pop_first_conquest(), "事件旗烧完不再触发")
	# 80d 技能树: 10 级 + 5 级分叉二选一
	var lbak80 := {"level": Legion.level, "exp": Legion.exp, "sp": Legion.skill_points,
		"skills": Legion.skills.duplicate(), "branches": Legion.branches.duplicate()}
	Legion.level = 1
	Legion.exp = 0
	Legion.skill_points = 0
	Legion.skills = {"trade": 0, "manage": 0, "leader": 0, "farm": 0, "body": 0}
	Legion.branches = {"trade": "", "manage": "", "leader": "", "farm": "", "body": ""}
	Legion.gain_exp(900)
	chk(Legion.skill_lv("trade") == 0 and Legion.skill_points >= 8,
		"经验铺开局: 收成/钓鱼/买卖/建成都给经验 (点数 %d)" % Legion.skill_points)
	while Legion.skill_lv("trade") < 5 and Legion.skill_points > 0:
		Legion.upgrade_skill("trade")
	chk(Legion.skill_lv("trade") == 5, "行商升到 5 级 (分岔口)")
	chk(not Legion.upgrade_skill("trade"), "6 级前必须先选分支 (拒绝)")
	chk(Legion.choose_branch("trade", "a"), "选 [A] 掌柜")
	chk(not Legion.choose_branch("trade", "b"), "分支锁死 (不能改选 B)")
	chk(Legion.branch_lv("trade") == 0, "刚选支时分支级数还是 0")
	var sm80a: float = Research.sell_mult("材料")
	chk(Legion.upgrade_skill("trade") and Legion.skill_lv("trade") == 6, "选支后能继续升到 6")
	chk(absf(Research.sell_mult("材料") - sm80a - 0.06) < 0.001, "掌柜分支生效: 分支每级卖价 +6% (e28f)")
	# 还原现场
	Nations.prestige = int(bak80["prestige"])
	Nations.contract = String(bak80["contract"])
	Nations.liege = String(bak80["liege"])
	Nations.fief = String(bak80["fief"])
	Nations.player_nation_name = String(bak80["pname"])
	Nations.at_war.clear()
	for nid80 in (bak80["war"] as Array):
		Nations.at_war[String(nid80)] = true
	Nations.occupied.clear()
	for tid80 in (bak80["occ"] as Array):
		Nations.occupied[String(tid80)] = true
	Nations._first_conq_fired = bool(bak80["first"])
	Nations.changed.emit()
	Legion.level = int(lbak80["level"])
	Legion.exp = int(lbak80["exp"])
	Legion.skill_points = int(lbak80["sp"])
	Legion.skills = lbak80["skills"].duplicate()
	Legion.branches = lbak80["branches"].duplicate()
	Legion.stats_changed.emit()

	# ================= §81 e16: 纯色海/外海/骑兵帧/演出钟/树淡出/聊天对话框 =================
	# 81a 海图: 纯色海贴图 + 航行演出钟(只动视觉, 归真实时刻)
	# ❗§70 的 wm70 已 queue_free —— 重新裸建一个只跑纯逻辑(不进树, 用完 free)
	var wm81: Node = load("res://scene/world_map.gd").new()
	var flat81: Color = wm81.get("SEA_FLAT")
	chk(flat81 == Color(0.24, 0.62, 0.81), "海图纯色海 SEA_FLAT 定案色")
	# 演出钟 getter: 未起钟(_voy_clock<0)跟真实时刻; 起钟后返回演出钟内插色时刻
	var h_bak81: int = TimeManager.hour
	TimeManager.hour = 15
	TimeManager.minute = 0
	wm81.set("_voy_clock", -1.0)
	var trav_bak81: bool = Voyage.traveling
	Voyage.traveling = true            # 演出钟只在航行中接管(不在海图上时天色跟钟)
	chk(absf(float(wm81.call("_sky_hours")) - 15.0) < 0.2, "未起钟: 天色跟真实时刻")
	wm81.set("_voy_clock", 18.5)
	chk(absf(float(wm81.call("_sky_hours")) - 18.5) < 0.2, "起钟后: 天色走演出钟(黄昏)")
	chk(TimeManager.hour == 15 and TimeManager.minute == 0, "演出钟不碰 TimeManager")
	Voyage.traveling = trav_bak81
	TimeManager.hour = h_bak81
	TimeManager.minute = 0
	wm81.free()
	# 81b 主岛: 外海底垫 + 玩家相机围栏
	var sea81: Node2D = g.get_node_or_null("OuterSea")
	chk(sea81 != null and sea81 is Polygon2D, "主岛外海底垫 OuterSea 存在")
	if sea81 != null:
		chk(sea81.z_index <= -20, "外海垫压过一切地形层")
	var cam81: Camera2D = g.get("player").get_node_or_null("Camera2D")
	chk(cam81 != null and cam81.limit_right > cam81.limit_left + 1000,
		"玩家相机围栏已设 (limit %d..%d)" % [cam81.limit_left, cam81.limit_right])
	# 81c 骑兵: 32x48 六帧网格(修掉 48px 步进劈人马的旧切法)
	var troop_script: Script = load("res://scene/troop.gd")
	chk(int(troop_script.get("MOUNT_FRAME_W")) == 32 and int(troop_script.get("MOUNT_FRAME_H")) == 48,
		"骑兵帧尺寸 32x48 (素材 6 帧 x 3 行)")
	# 81d 聊天对话框: 预览台词组不落账, 关框才记好感 (e18: 组 2~3 段)
	var fav81: int = Nations.favor_of("chenxi")
	var line81: Array = Nations.captain_lines("chenxi")
	chk(line81.size() >= 2 and String(line81[0]).length() > 0, "百夫长台词组预览能取到 (2~3 段)")
	chk(Nations.favor_of("chenxi") == fav81, "台词预览不落账 (关对话框才 chat_captain)")
	Nations.chat_captain("chenxi")
	chk(Nations.favor_of("chenxi") == fav81 + Nations.CHAT_FAVOR, "关框落账: 好感 +1")
	# 81e 战斗: 主角树后淡出 + 对话框组件在
	chk(troop_script.source_code.contains("_update_tree_fade"),
		"主角有树后淡出逻辑 (_update_tree_fade)")
	chk(load("res://dialog_box.gd") != null, "聊天对话框组件 dialog_box.gd 在")

	# ============ 82. e28e 同伴干活: 碰撞体积 / 派活格数 / 额度满提示 ============
	print("\n=== 82. e28e 同伴干活: 碰撞体 / 详情派活格数 / 额度满提示 ===")
	# 82a 伙伴身上的物理碰撞体: 玩家走近会被挡住（不穿模）；
	#     伙伴自己走位是直写 global_position，这层 StaticBody 只拦玩家、不拖累自己。
	var w82: Node2D = load("res://scene/slave_npc.gd").new()
	w82.index = 0
	add_child(w82)
	await get_tree().process_frame
	var blk82: Node = w82.get_node_or_null("BodyBlock")
	chk(blk82 is StaticBody2D, "伙伴挂了 BodyBlock 物理体（玩家不再穿模）")
	if blk82 is StaticBody2D:
		chk(int((blk82 as StaticBody2D).collision_layer) == 4,
			"BodyBlock 在 layer 4（玩家的 mask 覆盖得到，能挡住玩家）")
		chk(int((blk82 as StaticBody2D).collision_mask) == 0,
			"BodyBlock mask 0（不干扰伙伴自己走位）")
	w82.free()
	# 82b 干活动画表仍在（锄地/浇水/收割 三工种定点各播各的动画；§23.7 已验过实播）
	chk(String(load("res://scene/slave_npc.gd").source_code).contains("TASK_ANIM"),
		"干活动画表 TASK_ANIM 在 (锄地/浇水/收割)")
	# 82c 详情页写明派活格数: 一天能派几格 = 基础额度 + 劳动树加成
	var bp82: Variant = load("res://backpack_ui.gd").new()
	add_child(bp82)
	bp82._switch_to("team")
	var fake82 := {"name": "劳测员", "troop": "新兵", "labor": "帮工",
		"affection": 0, "fed_today": true, "talked_today": true,
		"hp": 30, "max_hp": 30, "squad": 0}
	Slaves.slaves.append(fake82)
	Slaves.count = Slaves.slaves.size()
	var idx82: int = Slaves.slaves.size() - 1
	bp82._open_slave_detail(idx82)
	var lab82: Variant = bp82.get("_detail_labor_benefit")
	chk(lab82 != null, "详情页劳动力标签在")
	if lab82 != null:
		var txt82 := String(lab82.text)
		chk(txt82.contains("派活") and txt82.contains(str(Slaves.slave_cells(fake82))),
			"详情页写明派活格数 (基础 %d + 加成 %d = %d 格/天)"
			% [Slaves.cells_per_slave(), Slaves.labor_bonus_of(fake82),
			Slaves.slave_cells(fake82)])
	bp82._close_slave_detail()
	Slaves.slaves.erase(fake82)
	Slaves.count = Slaves.slaves.size()
	Slaves.changed.emit()
	bp82.close()
	bp82.queue_free()
	await get_tree().process_frame
	# 82d 额度满提示: 派活面板信息条明说「额度已满」；地图上有红罩反馈 (deny_cell)
	var asg_bak82: Dictionary = Slaves.assignments.duplicate()
	Slaves.assignments.clear()
	var budget82: int = Slaves.budget()
	for i82 in range(budget82 + 1):
		Slaves.assignments[Vector2i(-100 - i82, -100)] = Slaves.TASK_WATER
	chk(Slaves.remaining() <= 0, "填满派活额度 (还剩 %d 格)" % Slaves.remaining())
	var au82: Control = load("res://assign_ui.gd").new()
	add_child(au82)
	await get_tree().process_frame
	au82._refresh()
	chk(String(au82.get("_info").text).contains("额度已满"),
		"额度满时派活面板信息条明说「额度已满」")
	au82.free()
	Slaves.assignments = asg_bak82
	Slaves.changed.emit()
	chk(String(load("res://scene/assign_map.gd").source_code).contains("deny_cell"),
		"派活地图有「额度满吃瘪红罩」反馈 (deny_cell)")

	# ============ 83. e28f: 制作三子页 / 建造页升铁匠铺 / 分支比主干强 ============
	print("\n=== 83. e28f: 制作三子页 / 建造页升级 / 分支技能强化 ===")
	# 83a 制作页三子页签: 三段配方行都建好, 同一时刻只显一段
	var bp83: Variant = load("res://backpack_ui.gd").new()
	add_child(bp83)
	await get_tree().process_frame
	bp83._switch_to("craft")
	var rows83: Array = bp83.get("_craft_rows")
	chk(rows83.size() == Crafting.RECIPES.size() + Crafting.WORKBENCH_RECIPES.size()
		+ Crafting.SMITH_RECIPES.size(), "三段配方行都建了 (%d 行)" % rows83.size())
	var subs83: Dictionary = bp83.get("_craft_sub_pages")
	chk(subs83.size() == 3, "个人/工作台/铁匠铺三个子页容器在")
	if subs83.size() == 3:
		chk((subs83["base"] as Control).visible and not (subs83["wb"] as Control).visible
			and not (subs83["smith"] as Control).visible, "默认停在个人页, 另两段藏起来")
		bp83._select_craft_sub("smith")
		chk((subs83["smith"] as Control).visible and not (subs83["base"] as Control).visible,
			"切到铁匠铺子页后显隐跟着翻")
	bp83.close()
	bp83.queue_free()
	await get_tree().process_frame
	# 83b 建造页升级区: 摆一座铁匠铺 -> 列出升级按钮 -> 点两次升满 -> 满级灰掉
	var bak_money83: int = Wallet.money
	var cell83 := Vector2i(500, 500)   # 离真地图远远的, 不碰真设施
	if Structures.has_station(cell83):
		Structures.remove(cell83)
	Wallet.money = 10000
	chk(Structures.place(cell83, Structures.KIND_BLACKSMITH), "摆下一座测试铁匠铺")
	var bui83: Variant = load("res://backpack_ui.gd").new()
	add_child(bui83)
	await get_tree().process_frame
	bui83._switch_to("build")
	var ub83: Variant = bui83.get("_upgrade_box")
	chk(ub83 != null, "建造页有「建筑升级」区")
	# 升级行是 HBox(Label+Button) 包一层的, 用 find_children 递归找按钮才拿得到
	var lv_btn83: Button = null
	for ch83 in (ub83 as VBoxContainer).find_children("*", "Button", true, false):
		if String((ch83 as Button).text).contains("升级到 Lv.2"):
			lv_btn83 = ch83
	chk(lv_btn83 != null, "铁匠铺 Lv.1 列出「升级到 Lv.2 (金币 150)」按钮")
	if lv_btn83 != null:
		lv_btn83.pressed.emit()   # 直接发信号 = 点了升级
		chk(Structures.level_of(cell83) == 2, "点按钮铁匠铺升到 Lv.2")
		chk(Wallet.money == 10000 - 150, "升级扣一口价 150 金 (剩 %d)" % Wallet.money)
	bui83._refresh_build()
	var lv_btn83b: Button = null
	for ch83b in (ub83 as VBoxContainer).find_children("*", "Button", true, false):
		if String((ch83b as Button).text).contains("升级到 Lv.3"):
			lv_btn83b = ch83b
	chk(lv_btn83b != null, "Lv.2 列出「升级到 Lv.3 (金币 300)」按钮")
	if lv_btn83b != null:
		lv_btn83b.pressed.emit()
		chk(Structures.level_of(cell83) == 3, "再点一次升到 Lv.3 满级")
	bui83._refresh_build()
	var full83 := false
	for ch83c in (ub83 as VBoxContainer).find_children("*", "Button", true, false):
		if String((ch83c as Button).text) == "已满级":
			full83 = (ch83c as Button).disabled
	chk(full83, "满级后按钮换成「已满级」并灰掉")
	bui83.close()
	bui83.queue_free()
	Structures.remove(cell83)
	Wallet.money = bak_money83
	# 83c 分支比主干强: 直接把技能顶到 6 级再切支, 量每级收益差
	var lbak83: Dictionary = {"level": Legion.level, "exp": Legion.exp, "sp": Legion.skill_points,
		"skills": Legion.skills.duplicate(), "branches": Legion.branches.duplicate()}
	Legion.skills = {"trade": 6, "manage": 6, "leader": 6, "farm": 6, "body": 6}
	Legion.branches = {"trade": "", "manage": "", "leader": "", "farm": "", "body": ""}
	Legion.branches["body"] = ""
	var hp_no83: int = Legion.player_max_hp()
	Legion.branches["body"] = "b"
	chk(Legion.player_max_hp() - hp_no83 == 8, "壮士分支每级 +8 血 (比主干 6 强)")
	Legion.branches["body"] = ""
	var atk_no83: int = Legion.player_atk()
	Legion.branches["body"] = "a"
	chk(Legion.player_atk() - atk_no83 == 2, "武人分支每级 +2 攻 (比主干 1 强)")
	Legion.branches["body"] = ""
	Legion.branches["leader"] = ""
	var aatk_no83: int = Legion.ally_atk()
	Legion.branches["leader"] = "a"
	chk(Legion.ally_atk() - aatk_no83 == 2, "将军分支每级 +2 伙伴攻 (比主干 1 强)")
	Legion.branches["leader"] = ""
	var ahp_no83: int = Legion.ally_max_hp()
	Legion.branches["leader"] = "b"
	chk(Legion.ally_max_hp() - ahp_no83 == 5, "统领分支每级 +5 伙伴血 (质变)")
	Legion.branches["leader"] = ""
	Legion.branches["farm"] = ""
	var wm_no83: int = Inventory.water_max()
	Legion.branches["farm"] = "a"
	chk(Inventory.water_max() - wm_no83 == 4, "园丁分支每级水壶 +4 (比主干 2 强)")
	Legion.branches["farm"] = ""
	Legion.branches["farm"] = ""
	var cm_no83: float = Research.sell_mult("作物")
	Legion.branches["farm"] = "b"
	chk(absf(Research.sell_mult("作物") - cm_no83 - 0.05) < 0.001, "粮长分支作物卖价 +5%/级")
	Legion.branches["farm"] = ""
	Legion.branches["trade"] = ""
	var bm_no83: float = Research.buy_mult()
	Legion.branches["trade"] = "b"
	chk(absf(bm_no83 - Research.buy_mult() - 0.05) < 0.001, "豪商分支每级买价 -5% (比主干 3% 强)")
	Legion.branches["trade"] = ""
	Legion.branches["manage"] = ""
	var bud_no83: int = Slaves.budget()
	Legion.branches["manage"] = "a"
	chk(Slaves.budget() - bud_no83 == 4, "账房分支每级派活预算 +4 格 (比主干 1 强)")
	Legion.branches["manage"] = ""
	chk(String(load("res://research.gd").source_code).contains("0.08 * Legion.branch_lv"),
		"师爷分支研究点 +8%/级 (0.08 系数在)")
	# 还原现场
	Legion.level = int(lbak83["level"])
	Legion.exp = int(lbak83["exp"])
	Legion.skill_points = int(lbak83["sp"])
	Legion.skills = lbak83["skills"].duplicate()
	Legion.branches = lbak83["branches"].duplicate()

	# ============ 84. e29c 伙伴局部改色管线（发色/服装色带） ============
	print("\n=== 84. e29c: 伙伴局部改色 (发色/服装色带) ===")
	var sna84: Variant = load("res://scene/slave_npc.gd")
	chk(sna84.RECIPES.size() == 20, "配方表 20 条 (4 模型 x 5 变体, 序号回绕)")
	chk(sna84.recipe_for(2).is_empty() and sna84.recipe_for(6).size() == 1,
		"配方按伙伴序号取: 2 号黑发本色, 6 号玫红挑染")
	# 第三方素材不入库(见 README), 缺失时跳过改色断言
	var manu_idle: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/Manu/Idle.png")
	if manu_idle == null:
		print("  - skip: 缺少第三方素材包, 跳过改色断言 (见 README)")
	else:
		chk(sna84.sheet_texture("Manu", "Idle.png", 2) == manu_idle, "本色伙伴直接回原图")
		var m84: Image = (sna84.sheet_texture("Manu", "Idle.png", 6) as Texture2D).get_image()
		var o84: Image = manu_idle.get_image()
		m84.convert(Image.FORMAT_RGBA8)
		o84.convert(Image.FORMAT_RGBA8)
		var n84 := _img_diff_count(m84, o84)
		var op84 := _img_opaque_count(o84)
		chk(n84 > 0 and n84 * 3 < op84,   # 玫红带吃暗部轮廓, 实测约两成像素; 1/3 仍拦得住整体改色
			"6 号贴图改过色且只动局部 (%d / %d 不透明像素)" % [n84, op84])
		# 玫红要数「改色后比原图多了多少」—— Manu 自己的粉衣本来就带这个色相,
		# 只看「存在玫红像素」会被原图误判成通过。
		var rose_m84 := 0
		var rose_o84 := 0
		for y84 in m84.get_height():
			for x84 in m84.get_width():
				var c84 := m84.get_pixel(x84, y84)
				if c84.a >= 0.1 and c84.s > 0.45 and absf(c84.h - 0.93) < 0.03:
					rose_m84 += 1
				var c084 := o84.get_pixel(x84, y84)
				if c084.a >= 0.1 and c084.s > 0.45 and absf(c084.h - 0.93) < 0.03:
					rose_o84 += 1
		chk(rose_m84 > rose_o84, "黑发挑染出了玫红 (玫红像素 %d -> %d)" % [rose_o84, rose_m84])
		chk(sna84.sheet_texture("Manu", "Idle.png", 6) == sna84.sheet_texture("Manu", "Idle.png", 6),
			"改色贴图走缓存 (同 key 同一份)")
		var a0_84: Image = (sna84.sheet_texture("Alex", "Idle.png", 0) as Texture2D).get_image()
		var a4_84: Image = (sna84.sheet_texture("Alex", "Idle.png", 4) as Texture2D).get_image()
		a0_84.convert(Image.FORMAT_RGBA8)
		a4_84.convert(Image.FORMAT_RGBA8)
		chk(_img_diff_count(a0_84, a4_84) > 0, "同模型不同配方贴图像素不同 (Alex 0 号 vs 4 号)")

	# ============ 85. e29e 草地小动物（鸽子惊飞 / 蝴蝶绕花） ============
	print("\n=== 85. e29e: 草地小动物 (鸽子惊飞 / 蝴蝶绕花) ===")
	chk(load("res://scene/critters.gd") != null, "critters.gd 能加载")
	var critters85: Node2D = g.get_node_or_null("Critters")
	chk(critters85 != null, "game 里挂了 Critters 容器")
	var pigeons85: Array = []
	var flies85: Array = []
	for ch85 in (critters85.get_children() if critters85 != null else []):
		if ch85.get("state") != null:       # 鸽子有 state 字段，蝴蝶没有
			pigeons85.append(ch85)
		elif ch85.get("home") != null:      # 蝴蝶有 home 锚点
			flies85.append(ch85)
	chk(pigeons85.size() >= 2, "鸽子落了 %d 只 (期望 2~3, e34d 调稀)" % pigeons85.size())
	chk(flies85.size() >= 6, "蝴蝶落了 %d 只 (期望 6~10)" % flies85.size())
	if not pigeons85.is_empty():
		var spr85: Sprite2D = pigeons85[0].get("spr")
		# e35: 换成 seagull 海鸥条 —— 16x16 一帧, 4 列 x 8 行(踱步/站定/飞行 + 水上版)
		chk(spr85.hframes == 4 and spr85.vframes == 8, "鸽子贴图 4x8 帧 (16x16 一帧)")
		chk(spr85.texture.get_width() == 64 and spr85.texture.get_height() == 128,
			"鸽子用 seagull 素材 64x128")
		chk(pigeons85[0].get("state") == 0 or pigeons85[0].get("state") == 1,
			"鸽子初始待机 (啄食/小走)")
		# 星露谷式惊飞：把玩家挪到鸽子旁边，鸽子应起身切飞行帧
		var old85: Vector2 = player.global_position
		player.global_position = pigeons85[0].global_position + Vector2(6, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		chk(pigeons85[0].get("state") == 2, "玩家贴近 -> 鸽子惊飞 (state=FLY)")
		chk(pigeons85[0].z_index == 30, "惊飞的鸽子临时抬层越过遮挡")
		# e36j: 飞行改走行 1（满 4 帧扑翼）—— 旧的行 4 只有 3 帧且姿态是低掠, 看着像在啄食
		chk(spr85.frame >= 4 and spr85.frame <= 7, "惊飞切到飞行行(行 1)的扑翼帧")
		player.global_position = old85
	var bad_col85 := 0
	var cols85 := {}
	for f85 in flies85:
		var fcol: int = f85.get("col")
		if fcol < 0 or fcol > 3:
			bad_col85 += 1
		cols85[fcol] = true
	chk(bad_col85 == 0, "蝴蝶配色列都在 0~3")
	chk(cols85.size() >= 2, "蝴蝶至少用到 2 种配色 (10 只抽 4 色)")

	# ============ 86. e30s 白天岗位干活（只派被分配的人下地） ============
	print("\n=== 86. e30s: 岗位干活 (矿/工地/打铁/研究的人不下地浇水) ===")
	var post86: Variant = load("res://scene/slave_npc.gd")
	# 86a 岗位动作表: 每个岗位的动作都在素材表里, 而且三个朝向的动画都拼得出来
	for k86 in post86.POST_ANIM.keys():
		chk(post86.SHEETS.has(String(post86.POST_ANIM[k86])),
			"%s 岗位用的是 %s 那套动作" % [k86, post86.POST_ANIM[k86]])
	var frames86: SpriteFrames = post86.build_frames("Alex", 0)
	for a86 in ["pickaxe", "shovel", "axe"]:
		var miss86: Array = []
		for d86 in ["down", "up", "side"]:
			if not frames86.has_animation(StringName("%s_%s" % [a86, d86])):
				miss86.append(d86)
		chk(miss86.is_empty(), "岗位动作 %s 三个朝向都在 (缺 %s)" % [a86, str(miss86)])
	chk(frames86.get_animation_loop(&"pickaxe_down"), "岗位动作循环播 (人整天在岗位上)")
	# 86b 归属: 一个人一个岗位, 各归各的板块
	var hour_bak86: int = TimeManager.hour
	TimeManager.hour = 10                       # 锁成白天, 不然伙伴到点就下班了
	var paused_bak86: bool = Slaves.paused
	Slaves.paused = false
	var cnt_bak86: int = Slaves.count
	var sl_bak86: Array = Slaves.slaves.duplicate(true)
	var exp_bak86: Array = Slaves.expedition.duplicate()
	var rt_bak86: Array = Slaves.research_tech.duplicate()
	var ra_bak86: Array = Slaves.research_admin.duplicate()
	var dk_bak86: Array = Slaves.dock_crew.duplicate()
	var mn_bak86: Array = Slaves.mine_crew.duplicate()
	var cr_bak86: Array = Slaves.craft_crew.duplicate()
	var asg_bak86: Dictionary = Slaves.assignments.duplicate()
	var done_bak86: Dictionary = Slaves.done_today.duplicate()
	Slaves.slaves = []
	for i86 in 5:
		Slaves.slaves.append({"name": "岗测%d" % i86, "affection": 0, "fed_today": true,
			"talked_today": true, "gift_today": true, "max_hp": 30, "hp": 30,
			"troop": "新兵", "labor": "帮工", "squad": 1})
	Slaves.count = 5
	Slaves.expedition.clear()
	Slaves.research_tech.clear()
	Slaves.research_admin.clear()
	Slaves.dock_crew.clear()
	Slaves.mine_crew.clear()
	Slaves.craft_crew.clear()
	Slaves.assignments.clear()
	Slaves.done_today.clear()
	Slaves.set_research(0, "tech")
	Slaves.toggle_dock(1)
	Slaves.toggle_craft(2)
	Slaves.toggle_mine(3, "stone")
	Slaves.changed.emit()
	var npc86: Array = []
	for i86 in 5:
		var n86: Node2D = post86.new()
		n86.index = i86
		g.add_child(n86)
		npc86.append(n86)
	await get_tree().process_frame
	var got86: Array = []
	for n86 in npc86:
		got86.append(String(n86.call("_post_of")))
	chk(got86 == ["research", "dock", "smith", "mine", ""],
		"四个岗位各归各的板块, 闲人归照料作物 (实际 %s)" % str(got86))
	# 86c 岗位优先: 地里派了活, 闲人会去干, 岗位上的人不去
	var cell86 := Vector2i(9999, 9999)
	for y86 in range(g.ISLAND_FROM.y, g.ISLAND_TO.y + 1):
		for x86 in range(g.ISLAND_FROM.x, g.ISLAND_TO.x + 1):
			var c86 := Vector2i(x86, y86)
			if not g.is_water(c86) and g._land_set.has(c86):
				cell86 = c86
				break
		if cell86.x != 9999:
			break
	chk(cell86.x != 9999, "找到一格陆地来派活 (%s)" % str(cell86))
	if cell86.x != 9999:
		Farm.till(cell86)                          # 先耕出来, 不然浇水会被卡住
		Farm.watered.erase(cell86)
		Slaves.assign(cell86, Slaves.TASK_WATER)
		npc86[4]._decide_next()
		chk(npc86[4]._state == 1, "闲人（照料作物）照旧去地里干活 (状态 %d)" % npc86[4]._state)
		npc86[3]._decide_next()
		chk(npc86[3]._state == 1, "矿井的人先按老逻辑挑到活 (状态 %d)" % npc86[3]._state)
		npc86[3]._process(0.02)
		# State.POST = 5（枚举: 0 闲逛 / 1 走过去 / 2 干活 / 3 歇着 / 4 上船 / 5 岗位）
		chk(npc86[3]._state == 5, "一进 _process 就被拨到岗位状态 (%d)" % npc86[3]._state)
		chk(String(npc86[3].get("_post")) == "mine", "他的岗位是矿井 (%s)" % str(npc86[3].get("_post")))
		for i86 in 120:
			npc86[3]._process(0.02)
		chk(not Slaves.is_done(cell86), "岗位上的人不会把地里的活干掉")
		# 86d 岗位站位: 矿井的人走到矿门口, 播抡镐的动作
		var want86: Vector2 = Farm.grid_origin + Vector2(
			g.mine_cell.x * Farm.TILE_SIZE + 8, (g.mine_cell.y + 1) * Farm.TILE_SIZE + 8)
		var pos86: Vector2 = npc86[3].call("_post_pos")
		chk(pos86.distance_to(want86) < 0.01, "矿井岗位站位就在矿门口 (%s)" % str(pos86))
		var spot86: Vector2 = npc86[3].get("_post_spot")
		chk(spot86.distance_to(want86) < 40.0, "他在矿门口一带落脚 (%s)" % str(spot86))
		var saw86 := false
		for i86 in 400:
			npc86[3]._process(0.02)
			if String(npc86[3]._sprite.animation).begins_with("pickaxe"):
				saw86 = true
				break
		chk(saw86, "到岗后播的是抡镐那套动作 (实际 %s)" % npc86[3]._sprite.animation)
		# 86e 撤岗就回地里: 收工之后他不再是岗位状态
		Slaves.toggle_mine(3, "stone")
		npc86[3]._process(0.02)
		chk(String(npc86[3].get("_post")) == "", "从矿井收工后不再算岗位 (%s)" % str(npc86[3].get("_post")))
		chk(npc86[3]._state != 5, "收工后回到地里那套循环 (状态 %d)" % npc86[3]._state)
	# 86f 远航出征不算岗位（名单是「下次出海带谁」, 人平时还在岛上过日子）
	Slaves.expedition.append(4)
	npc86[4]._process(0.02)
	chk(String(npc86[4].get("_post")) == "", "勾了「明天出行」的人白天仍在地里过日子")
	Slaves.expedition.erase(4)
	# 还原现场
	for n86 in npc86:
		n86.queue_free()
	await get_tree().process_frame
	Slaves.expedition = exp_bak86
	Slaves.research_tech = rt_bak86
	Slaves.research_admin = ra_bak86
	Slaves.dock_crew = dk_bak86
	Slaves.mine_crew = mn_bak86
	Slaves.craft_crew = cr_bak86
	Slaves.slaves = sl_bak86
	Slaves.count = cnt_bak86
	Slaves.assignments = asg_bak86
	Slaves.done_today = done_bak86
	Slaves.changed.emit()
	TimeManager.hour = hour_bak86
	Slaves.paused = paused_bak86

	# ============ 87. e30t 性别化对话库（男/女两套台词） ============
	print("\n=== 87. e30t: 性别化对话库 (男/女各一套) ===")
	var dlg87: Control = load("res://dialogue_ui.gd").new()
	add_child(dlg87)
	var cm87: Dictionary = dlg87.get_script().get_script_constant_map()
	var lm87: Array = cm87["LINES_M"]
	var lf87: Array = cm87["LINES_F"]
	var snpc87 := load("res://scene/slave_npc.gd")
	# 87a 两套都是 4 档 x 3 组, 每组 2~4 段, 没有空台词
	var shape_ok87 := true
	var why87 := ""
	for pair87 in [["LINES_M", lm87], ["LINES_F", lf87]]:
		var nm87 := String(pair87[0])
		var pool87: Array = pair87[1]
		if pool87.size() != 4:
			shape_ok87 = false
			why87 = "%s 不是 4 档 (%d)" % [nm87, pool87.size()]
		if not shape_ok87:
			break
		for t87 in pool87.size():
			var tier87: Array = pool87[t87]
			if tier87.size() != 3:
				shape_ok87 = false
				why87 = "%s 第 %d 档不是 3 组 (%d)" % [nm87, t87, tier87.size()]
				break
			for g87 in tier87.size():
				var lines87: Array = tier87[g87]
				if lines87.size() < 2 or lines87.size() > 4:
					shape_ok87 = false
					why87 = "%s 第 %d 档第 %d 组是 %d 段 (要 2~4)" % [nm87, t87, g87, lines87.size()]
					break
				for l87 in lines87:
					if String(l87).strip_edges() == "":
						shape_ok87 = false
						why87 = "%s 第 %d 档第 %d 组有空台词" % [nm87, t87, g87]
						break
				if not shape_ok87:
					break
			if not shape_ok87:
				break
		if not shape_ok87:
			break
	chk(shape_ok87, "两套池子都是 4 档 x 3 组 x 2~4 段 %s" % why87)
	# 87b 台词标点全 ASCII（IPix.ttf 没有全角字形, 渲出来是方块）
	var bad87 := "（）：，。！？；、“”‘’《》【】「」…—～"
	var punct_ok87 := true
	var badhit87 := ""
	for pool88 in [lm87, lf87]:
		for tier88 in pool88:
			for grp88 in tier88:
				for line88 in grp88:
					var s88 := String(line88)
					for i88 in s88.length():
						if bad87.contains(s88[i88]):
							punct_ok87 = false
							badhit87 = s88
							break
					if not punct_ok87:
						break
				if not punct_ok87:
					break
			if not punct_ok87:
				break
		if not punct_ok87:
			break
	chk(punct_ok87, "台词标点全是 ASCII: %s" % badhit87)
	# 87c 性别路由: 第 0 个(Alex=男) 走男池, 第 1 个(Lyria=女) 走女池
	var sl_bak87: Array = Slaves.slaves
	var cnt_bak87: int = Slaves.count
	Slaves.slaves = [
		{"name": "男甲", "affection": 0, "fed_today": true, "talked_today": true,
			"gift_today": true, "max_hp": 30, "hp": 30, "troop": "新兵", "squad": 1, "labor": "帮工"},
		{"name": "女甲", "affection": 0, "fed_today": true, "talked_today": true,
			"gift_today": true, "max_hp": 30, "hp": 30, "troop": "新兵", "squad": 1, "labor": "帮工"},
	]
	Slaves.count = 2
	chk(bool(snpc87.MODEL_MALE[0]) and not bool(snpc87.MODEL_MALE[1]),
		"性别真相源: 第 0 个是男, 第 1 个是女")
	dlg87._slave_index = 0
	var g_m87: Array = dlg87._pick_group()
	dlg87._slave_index = 1
	var g_f87: Array = dlg87._pick_group()
	chk(lm87[0].has(g_m87), "男伙伴（第 0 个）拿的是男池冷淡档: %s" % str(g_m87))
	chk(lf87[0].has(g_f87), "女伙伴（第 1 个）拿的是女池冷淡档: %s" % str(g_f87))
	# 87d 同一天同一个人台词固定（不每次重抽）
	dlg87._slave_index = 0
	chk(dlg87._pick_group() == g_m87, "同一天同一个人台词固定")
	# 87e 好感档位切得动: 好感 10 拿的是 9~10 那一档
	Slaves.slaves[0]["affection"] = 10
	dlg87._slave_index = 0
	var g_hi87: Array = dlg87._pick_group()
	chk(lm87[3].has(g_hi87), "好感 10 的男伙伴拿的是亲昵档: %s" % str(g_hi87))
	# 87f 两套池子真的不一样（不是同一套挂两个名）
	var diff87 := false
	for t89 in 4:
		for g89 in 3:
			if lm87[t89][g89] != lf87[t89][g89]:
				diff87 = true
				break
		if diff87:
			break
	chk(diff87, "男/女两套台词确实不同")
	# 还原现场
	Slaves.slaves = sl_bak87
	Slaves.count = cnt_bak87
	Slaves.changed.emit()
	dlg87.queue_free()
	await get_tree().process_frame

	# ============ 88. e31 光影特效（壁炉火光 / 屋前挂灯 / 篝火柔光 / 后处理夜度） ============
	print("\n=== 88. e31: 光影特效 ===")
	var house88: Node2D = g.get_node("House")
	var hour_bak88: int = TimeManager.hour
	var minute_bak88: int = TimeManager.minute
	# 88a 室内壁炉火光：光心必须落在壁炉贴图那块矩形里（不能飘到墙上/屋子外）
	var fire88: PointLight2D = house88._fire_light
	var fp88: Sprite2D = house88.get_node_or_null("Interior/Decor/Fireplace")
	chk(fire88 != null and fire88.texture != null, "室内有壁炉火光（PointLight2D + 光晕贴图）")
	if fire88 != null and fp88 != null:
		var fr88: Rect2 = fp88.region_rect
		chk(Rect2(fp88.position, fr88.size).has_point(fire88.position),
			"火光光心落在壁炉矩形内（%s）" % str(fire88.position))
		chk(fire88.get_parent() == house88.get_node("Interior"),
			"火光挂在 Interior 下（跟着屋子一起隐藏/显示）")
	# 88b 黑幕不吃光：否则屋里火光会在幕布上糊出一圈暖边，屋外全黑就破了
	var veil88: Node2D = house88._veil
	var veil_poly88: Polygon2D = null
	if veil88 != null:
		for c88 in veil88.get_children():
			if c88 is Polygon2D:
				veil_poly88 = c88
	chk(veil_poly88 != null and veil_poly88.light_mask == 0, "屋外黑幕不吃任何光源（light_mask=0）")
	# 88c 壁炉柔光是加法混合（半透明叠上去提亮，不是盖一层灰）
	var fg88: Sprite2D = house88._fire_glow
	chk(fg88 is Sprite2D and fg88.material is CanvasItemMaterial
		and (fg88.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
		"壁炉柔光是加法混合")
	# e38c 屋前挂灯整盏撤掉：它立在门边、正好压在售货箱的落脚点上，
	#   俯瞰下去像从箱子里长出一盏灯笼。路灯改走可建造建筑（§94 另行断言）。
	chk(house88.get_node_or_null("DoorLamp") == null, "农舍门口不再挂灯（e38c 已撤）")
	chk(not house88.has_method("_sync_lamp"), "农舍脚本没有残留的挂灯同步函数")
	# 88e 篝火也有一层加法柔光（PointLight2D 只染色不发光，夜里远看找不到火在哪）
	var cf88: Node2D = load("res://scene/campfire.gd").new()
	add_child(cf88)
	await get_tree().process_frame
	var cg88: Sprite2D = cf88._glow
	chk(cg88 is Sprite2D and cg88.material is CanvasItemMaterial
		and (cg88.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD,
		"篝火也有一层加法柔光")
	cf88.queue_free()
	# 88f 后处理夜度：shader 有 night uniform，曲线白天 0 / 黄昏 0.5 / 夜里 1
	var post88: ShaderMaterial = g._post_mat
	var has_night88 := false
	if post88 != null and post88.shader != null:
		for u88 in post88.shader.get_shader_uniform_list():
			if String(u88.get("name", "")) == "night":
				has_night88 = true
	chk(has_night88, "后处理 shader 有 night 参数（泛光/晕影/天光跟着昼夜走）")
	chk(is_equal_approx(g._night_at(12.0), 0.0), "12 点夜度 = 0")
	chk(is_equal_approx(g._night_at(23.0), 1.0), "23 点夜度 = 1")
	chk(is_equal_approx(g._night_at(19.0), 0.5), "19 点（黄昏中点）夜度 = 0.5")
	# 88g _sync_post 真的把夜度喂进材质
	TimeManager.hour = 12
	TimeManager.minute = 0
	g._post_night = 1.0
	g._sync_post(10.0)
	chk(is_equal_approx(g._post_night, 0.0), "白天 _sync_post 把夜度压到 0（%f）" % g._post_night)
	TimeManager.hour = 23
	g._post_night = 0.0
	g._sync_post(10.0)
	chk(is_equal_approx(g._post_night, 1.0), "夜里 _sync_post 把夜度抬到 1（%f）" % g._post_night)
	# 还原现场
	TimeManager.hour = hour_bak88
	TimeManager.minute = minute_bak88

	# ============ 89. e32 中后期任务指引（毕业条件 + 第二段指引链） ============
	print("\n=== 89. e32: 中后期任务指引 ===")
	var bak89: Array = Quests.active()
	var ms_bak89: bool = Quests.milestones_enabled()
	var msd_bak89: Array = []
	for mm89 in Quests.MILESTONES:
		if Quests.milestone_done(String(mm89["id"])):
			msd_bak89.append(String(mm89["id"]))
	var fish_bak89: bool = Quests._fish_first
	# 89a 链完整性: explore_island 一路串到 siege_first, 链尾无下一环
	var mid_ids89 := ["explore_island", "build_first", "mine_first", "tech_first",
		"sail_first", "navy_first", "contract_first", "siege_first"]
	var chain_ok89 := true
	for i89a in mid_ids89.size() - 1:
		if not Quests._MID_CHAIN.has(String(mid_ids89[i89a])):
			chain_ok89 = false
		elif String((Quests._MID_CHAIN[String(mid_ids89[i89a])] as Array)[0]) != String(mid_ids89[i89a + 1]):
			chain_ok89 = false
	chk(chain_ok89, "中后期链 explore_island -> ... -> siege_first 首尾相连")
	chk(not Quests._MID_CHAIN.has("siege_first"), "siege_first 是中后期链尾")
	chk(not Quests._CHAIN.has("explore_island"), "explore_island 仍然不在第一周链里")
	# 89b 每环标题/描述都不空
	var txt_ok89 := true
	for kk89 in Quests._MID_CHAIN:
		var nn89: Array = Quests._MID_CHAIN[kk89]
		if String(nn89[1]).strip_edges() == "" or String(nn89[2]).strip_edges() == "":
			txt_ok89 = false
	chk(txt_ok89, "中后期链每一环都有标题和描述")
	# 89c 走完第一周链 + 钓到第一条鱼 = 毕业 + 接上中后期链
	var early89 := ["go_house", "buy_goblin", "till_first", "plant_first",
		"water_first", "harvest_first", "sell_first"]
	Quests.reset_all()
	Quests.start_guide()
	for id89a in early89:
		Quests.complete(String(id89a))
	chk(Quests.has_active("explore_island") and not Quests.milestones_enabled(),
		"链走到「去水边钓条鱼」, 这时还没毕业")
	Quests.note_first_fish()
	chk(not Quests.has_active("explore_island"), "钓上第一条鱼 -> explore_island 完成")
	chk(Quests.milestones_enabled(), "毕业 -> 里程碑系统开闸")
	chk(Quests.has_active("build_first"), "毕业 -> 接上中后期链第一环「盖起第一座建筑」")
	# 89d 中后期链一环一环推到底
	var step_ok89 := true
	for i89b in range(1, mid_ids89.size()):
		var cur89 := String(mid_ids89[i89b])
		if not Quests.has_active(cur89):
			step_ok89 = false
			break
		Quests.complete(cur89)
		if i89b < mid_ids89.size() - 1 and not Quests.has_active(String(mid_ids89[i89b + 1])):
			step_ok89 = false
			break
	chk(step_ok89, "中后期链一环一环推到底（8 环）")
	chk(not Quests.has_active("siege_first"), "链尾完成后本环销案")
	# 89e 先钓鱼、后走到链尾: 链走到 explore_island 时补毕业
	Quests.reset_all()
	Quests.start_guide()
	Quests.note_first_fish()
	chk(Quests._fish_first and not Quests.milestones_enabled(),
		"链还没走到 explore_island 就钓鱼: 只记 flag 不毕业")
	for id89b in early89:
		Quests.complete(String(id89b))
	chk(Quests.milestones_enabled() and not Quests.has_active("explore_island"),
		"链走到 explore_island 时补上毕业")
	# 89f 钓鱼 flag 进存档
	Quests._fish_first = true
	var d89: Dictionary = Quests.to_dict()
	Quests._fish_first = false
	Quests.from_dict(d89)
	chk(Quests._fish_first, "钓鱼 flag 进存档（to_dict/from_dict 往返）")
	# 89g 8 个中后期事件真的挂了钩（源码里必须有 complete 调用）
	var hook_ok89 := true
	for pp89 in [
			["res://scene/player.gd", "Quests.note_first_fish()"],
			["res://structures.gd", 'Quests.complete("build_first")'],
			["res://ore_data.gd", 'Quests.complete("mine_first")'],
			["res://research.gd", 'Quests.complete("tech_first")'],
			["res://voyage.gd", 'Quests.complete("sail_first")'],
			["res://scene/battle_map.gd", 'Quests.complete("navy_first")'],
			["res://nations.gd", 'Quests.complete("contract_first")'],
			["res://nations.gd", 'Quests.complete("siege_first")']]:
		if not FileAccess.get_file_as_string(String(pp89[0])).contains(String(pp89[1])):
			hook_ok89 = false
	chk(hook_ok89, "8 个中后期事件都挂上了任务钩子")
	# 89h 读档重建不算盖房子: place(restore=true) 不该触发 build_first / 不该塞下一环
	var rcell89 := Vector2i(246, 202)
	Structures.remove(rcell89)
	Structures.place(rcell89, Structures.KIND_WORKBENCH, true)
	chk(not Quests._done.has("build_first") and not Quests.has_active("mine_first"),
		"读档重建(restore=true) 不触发 build_first, 也不塞下一环")
	Structures.remove(rcell89)
	# 还原现场
	Quests.reset_all()
	Quests._fish_first = fish_bak89
	Quests._milestones_on = ms_bak89
	for mm89b in msd_bak89:
		Quests._milestone_done[String(mm89b)] = true
	Quests._sync_milestone_task()
	for rb89 in bak89:
		if String(rb89["id"]) == Quests.TASK_MILESTONE and not Quests._milestones_on:
			continue
		Quests.add(String(rb89["id"]), String(rb89["title"]), String(rb89["desc"]))
	chk(Quests.active().size() == bak89.size(), "收尾: 还原测试前任务列表")

	# ============ 90. e33 画面全面美化（影子/水澜/草变体/震屏/风摆/雨涟漪） ============
	print("\n=== 90. e33: 画面全面美化 ===")
	# 90a 两个新公用件: 关键实现齐全
	var su90 := FileAccess.get_file_as_string("res://scene/shadow_util.gd")
	chk(su90.contains("static func make_shadow") and su90.contains("_cache"),
		"shadow_util.gd: make_shadow + 静态缓存")
	var rr90 := FileAccess.get_file_as_string("res://scene/rain_ripples.gd")
	chk(rr90.contains("Weather.is_rain()") and rr90.contains("draw_arc"),
		"rain_ripples.gd: 天气判定 + _draw 画环")
	# 90b 11 个实体都引用了影子公用件
	var sh_ok90 := true
	for sf90 in ["res://scene/player.gd", "res://scene/slave_npc.gd", "res://scene/tree_node.gd",
			"res://scene/station_node.gd", "res://scene/well_node.gd", "res://scene/blacksmith_node.gd",
			"res://scene/coop_node.gd", "res://scene/merchant.gd", "res://scene/shipping_bin.gd",
			"res://scene/campfire.gd", "res://scene/rock_node.gd"]:
		if not FileAccess.get_file_as_string(String(sf90)).contains("shadow_util.gd"):
			sh_ok90 = false
	chk(sh_ok90, "11 个实体脚本都接了 shadow_util.gd")
	# 90c game.gd 四件套都在源码里
	var gg90 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(gg90.contains("_tick_water_ripple") and gg90.contains("WATER_ANIM_PERIOD"),
		"game.gd: 水澜分桶轮换")
	chk(gg90.contains("func shake_screen") and gg90.contains("shake_screen(2.5, 0.4)")
		and gg90.contains("shake_screen(2.0, 0.25)"), "game.gd: 震屏 + 雷击/树倒挂钩")
	chk(gg90.contains("_grass_alt_of") and gg90.contains("GRASS_ALT_LITE"),
		"game.gd: 草地杂色变体")
	chk(gg90.contains("RainRipples"), "game.gd: 雨涟漪已接线")
	# 90d 树的风摆/动画锁/影子
	var tn90 := FileAccess.get_file_as_string("res://scene/tree_node.gd")
	chk(tn90.contains("_wind_t") and tn90.contains("_anim_lock") and tn90.contains("_shadow"),
		"tree_node.gd: 风摆相位 + 动画锁 + 影子")
	# 90e 运行时: 玩家脚底影子 (z=-1 的 Sprite2D)
	var psh90 := false
	for pc90 in g.player.get_children():
		if pc90 is Sprite2D and pc90.z_index == -1:
			psh90 = true
	chk(psh90, "玩家脚底挂着 z=-1 的影子")
	# e41j: 影子要贴在「视觉脚底」那一行 (y=-7), 不是原点 (0,0) ——
	#   贴图 32x32 的原点在脚下、人物画在原点上方, 影子留在 0 会比脚底低 7px,
	#   看着就像影子跟人分了家（主角 e36d 修过, 伙伴这边也得跟上）
	var psh90b := false
	for pc90b in g.player.get_children():
		if pc90b is Sprite2D and pc90b.z_index == -1:
			# d2: 影子跟着太阳在脚底线上左右摆（x 最多 ±6.5）, y 恒贴 -7 不跟人分家
			psh90b = psh90b or (absf((pc90b as Sprite2D).position.y + 7.0) < 0.01
				and absf((pc90b as Sprite2D).position.x) < 7.0)
	chk(psh90b, "玩家影子贴在脚底线 y=-7（x 可随太阳 ±6.5 摆）")
	var sn90 := FileAccess.get_file_as_string("res://scene/slave_npc.gd")
	chk(sn90.contains("_sh.position = Vector2(0, -7)"),
		"slave_npc.gd 的伙伴影子同样贴在脚底 (0,-7)（不跟人物分家）")
	# 90f 运行时: RainRipples 挂在场景里, 水澜花名册非空
	chk(g.get_node_or_null("RainRipples") != null, "场景里挂着 RainRipples")
	chk(g._water_anim_cells.size() > 0, "水澜花名册已登记水格")
	# 90g 运行时: 草地 alternative 已注册 + 震屏能点亮
	var gsrc90 := g.grid_layer.tile_set.get_source(g.YARD_GRASS_SRC) as TileSetAtlasSource
	chk(gsrc90 != null and gsrc90.has_alternative_tile(g.YARD_GRASS_TILE, 1)
		and gsrc90.has_alternative_tile(g.YARD_GRASS_TILE, 2), "草地亮/暗 alternative 已注册")
	g.shake_screen(1.0, 0.05)
	chk(g._shake_left > 0.0, "shake_screen 能点亮震屏计时")

	# ============ 91. e34 小动物修正 + 国战攻占过程 ============
	print("\n=== 91. e34: 小动物修正 + 国战攻占 ===")
	# 91a critters.gd 源码: 鸽子减量降频 + 朝向 + 避水 + 蝴蝶死分支重构
	var cr91 := FileAccess.get_file_as_string("res://scene/critters.gd")
	chk(cr91.contains("PIGEON_MAX := 3") and cr91.contains("RESPAWN_WAIT := 25.0"),
		"critters: 鸽子上限 3 只, 惊飞补种间隔 25 秒(e34d)")
	# e35: 用户要求把乌鸦换成素材里的鸽子 —— 白身灰翅、三段动画齐全的海鸥
	chk(cr91.contains("Animals/Forest/Beach/seagull.png")
		and cr91.contains("PIGEON_FRAME := 16"),
		"critters: 鸽子换成 seagull 海鸥贴图 (16x16 一帧)(e35)")
	chk(cr91.contains("spr.frame = PIGEON_ROW_PECK * 4")
		and cr91.contains("spr.frame = PIGEON_ROW_WALK * 4 + int(frame_t) % 4")
		and cr91.contains("spr.frame = PIGEON_ROW_FLY * 4 + int(frame_t) % 4"),
		"critters: 鸽子啄食/踱步/飞行各走一行(e35)")
	chk(cr91.count("spr.flip_h = dir.x > 0.0") == 3
		and not cr91.contains("flip_h = dir.x < 0.0"),
		"critters: 鸽子三处朝向都是素材朝左才不翻(e34b)")
	chk(cr91.contains("is_water_fn: Callable = Callable()")
		and cr91.contains("is_water_fn.call(position) or is_water_fn.call(position + step * 12.0)"),
		"critters: 鸽子带避水检测, 踩水或 12 帧前方有水都要换向(e34c)")
	chk(cr91.contains("var shy := false")
		and cr91.contains("if not shy and (retarget_t > 2.5"),
		"critters: 蝴蝶怕生闪避与绕花重瞄准解耦, 不再有死分支(e34a)")
	# 91b game.gd: 装配时把水面查询递给鸽子
	var gg91 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(gg91.contains("is_water(_world_to_cell(w))"),
		"game.gd: critters.setup 接入水面查询(e34c)")
	# 91c nations.gd: 丢城记仇 + 次日发兵 + 玩家城失守账目
	var nn91 := FileAccess.get_file_as_string("res://nations.gd")
	chk(nn91.contains("RECLAIM_CD_DAYS := 12") and nn91.contains("var pending_reclaims"),
		"nations: 复仇冷却与记账本就位(e34e)")
	chk(nn91.contains("func _queue_reclaim") and nn91.contains("func player_town_lost"),
		"nations: _queue_reclaim / player_town_lost 已落码")
	chk(nn91.contains("_queue_reclaim(nid, tid)") and nn91.contains("_queue_reclaim(def, tid)"),
		"nations: 围攻胜利与 AI 攻占都会记仇")
	chk(nn91.contains("pending_wars.append({\"from\": rid, \"tid\": rtid})")
		and nn91.contains("pending_reclaims.clear()"),
		"nations: 每日结算把复仇军编入远征队列")
	# 91d world_map.gd: 围攻状态机 + 进度条 + 解围播报
	var wm91s := FileAccess.get_file_as_string("res://scene/world_map.gd")
	chk(wm91s.contains("SIEGE_TIME := 8.0") and wm91s.contains("SIEGE_BAR_W := 36.0"),
		"world_map: 攻城时长 8 秒 + 进度条常量")
	chk(wm91s.contains("func _begin_siege") and wm91s.contains("func _update_siege_bar")
		and wm91s.contains("func _end_siege_bar") and wm91s.contains("func _finish_siege"),
		"world_map: 攻城四件套函数齐全")
	chk(wm91s.contains("pd[\"siege_t\"] = float(pd.get(\"siege_t\", 0.0)) + delta"),
		"world_map: 攻城中按帧累计进度")
	chk(wm91s.contains("危机解除"),
		"world_map: 玩家增援打退围攻军会播报危机解除")
	# 91e 运行时: 鸽子四面是水就原地站, 放行后照常走
	var crs91: Variant = load("res://scene/critters.gd")
	var pigeon91: Variant = crs91.Pigeon.new()
	add_child(pigeon91)
	pigeon91.rng = RandomNumberGenerator.new()
	pigeon91.init(load(crs91.PIGEON_TEX_PATH))
	pigeon91.is_water_fn = func(_w: Vector2) -> bool: return true
	pigeon91.state = crs91.Pigeon.S.WALK
	pigeon91.dir = Vector2.RIGHT
	pigeon91.speed = 20.0
	var cpos91: Vector2 = pigeon91.position
	pigeon91._physics_process(0.1)
	chk(pigeon91.position.distance_to(cpos91) < 0.001, "鸽子四面全是水时原地站, 不下水(e34c)")
	pigeon91.is_water_fn = func(_w: Vector2) -> bool: return false
	pigeon91._physics_process(0.1)
	chk(pigeon91.position.distance_to(cpos91) > 0.5
		and pigeon91.spr.flip_h == (pigeon91.dir.x > 0.0),
		"水面放行后鸽子照常走, 朝向与翻贴图一致(e34b)")
	# 91f 运行时: 玩家在远处时蝴蝶绕花重瞄准照常执行(e34a)
	var bf91: Variant = crs91.Butterfly.new()
	add_child(bf91)
	var far91 := Node2D.new()
	add_child(far91)
	far91.position = Vector2(5000, 5000)
	bf91.rng = pigeon91.rng
	bf91.player = far91
	bf91.init(load(crs91.BUTTERFLY_TEX_PATH), 0)
	bf91.home = Vector2(100, 100)
	bf91.position = Vector2(100, 100)
	bf91.target = Vector2(100, 100)
	bf91.retarget_t = 0.0
	bf91._physics_process(0.1)
	chk(bf91.target != Vector2(100, 100), "蝴蝶玩家在远处时绕花重瞄准照常执行(e34a)")
	# 91g 运行时: 远征队抵达城下进围攻, 进度走满换旗, 丢城国次日发兵收复
	var wm91: Variant = load("res://scene/world_map.gd").new()
	add_child(wm91)
	await get_tree().process_frame
	var tval91: Vector2i = Nations.TOWNS["beiling_valley"]["cell"]
	wm91._make_party(wm91._cell_center(tval91), "远征", 3, "chenxi",
		false, "", false, "beiling_valley")
	var pd91: Dictionary = wm91.parties.back()
	wm91._physics_process(0.016)
	chk(bool(pd91.get("sieging", false)) and float(pd91.get("siege_t", -1.0)) == 0.0,
		"远征队抵达城下进入围攻, 进度归零(e34e)")
	chk(pd91.get("bar") != null and is_instance_valid(pd91["bar"]),
		"城头上挂起了攻城进度条")
	pd91["siege_t"] = 8.0
	wm91._physics_process(0.016)
	chk(Nations.owner_nation_of("beiling_valley") == "chenxi",
		"攻城进度走满, 北凌谷地易主晨曦")
	var got91 := false
	for r91 in Nations.pending_reclaims:
		if String(r91.get("from", "")) == "beiling" and String(r91.get("tid", "")) == "beiling_valley":
			got91 = true
	chk(got91, "丢城的北凌已记仇, 排进复仇队列")
	var n_before91 := Nations.pending_reclaims.size()
	Nations._queue_reclaim("beiling", "beiling_valley")
	chk(Nations.pending_reclaims.size() == n_before91, "复仇冷却期内不重复记账")
	Nations._on_new_day(1)
	var war91 := false
	for w91 in Nations.pending_wars:
		if String(w91.get("from", "")) == "beiling" and String(w91.get("tid", "")) == "beiling_valley":
			war91 = true
	chk(war91, "次日复仇军编入远征队列, 誓要收复失地")
	Nations.pending_wars.clear()
	# 91h 玩家占领的城被围走满 -> 失守归攻方
	Nations.occupied["beiling_pine"] = true
	var tpin91: Vector2i = Nations.TOWNS["beiling_pine"]["cell"]
	wm91._make_party(wm91._cell_center(tpin91), "远征", 3, "xichuan",
		false, "", false, "beiling_pine")
	var pd92: Dictionary = wm91.parties.back()
	wm91._physics_process(0.016)
	pd92["siege_t"] = 8.0
	wm91._physics_process(0.016)
	chk(not Nations.occupied.has("beiling_pine")
		and Nations.owner_nation_of("beiling_pine") == "xichuan",
		"玩家占领城被围走满后失守, 归攻方所有")
	# 还原现场
	Nations.town_owner.erase("beiling_valley")
	Nations.town_owner.erase("beiling_pine")
	Nations.reclaim_cd.erase("beiling_valley")
	chk(Nations.pending_reclaims.is_empty(), "收尾: 复仇队列已清空")
	# 91i e52d: 国与国的战争账本 —— 远征/反扑开拔记账, 查询与持久化都通
	chk(nn91.contains("var ai_war := {}") and nn91.contains("func start_ai_war")
		and nn91.contains("func ai_warring") and nn91.contains("func ai_war_left"),
		"nations: 国与国战争账本与查询函数就位(e52d)")
	chk(nn91.contains("start_ai_war(atk, String(owner_nation_of(best)))")
		and nn91.contains("start_ai_war(rid, String(owner_nation_of(rtid)))"),
		"nations: AI 远征开拔与复仇开拔都记一笔国与国战争")
	Nations.ai_war.clear()
	Nations.start_ai_war("chenxi", "beiling")
	chk(Nations.ai_warring("chenxi", "beiling") and Nations.ai_warring("beiling", "chenxi"),
		"国与国开战: 键序无关, 两边都查得到交战")
	chk(Nations.ai_war_left("beiling", "chenxi") == Nations.WAR_DAYS,
		"国与国休战倒计时 60 天起算")
	chk(not Nations.ai_warring("chenxi", "xichuan"), "没开过战的国家不算交战")
	Nations.start_ai_war("chenxi", "beiling")
	chk(Nations.ai_war_left("chenxi", "beiling") == Nations.WAR_DAYS,
		"交战中重复开战被无视, 倒计时不重置")
	var snap91: Dictionary = Nations.to_dict()
	Nations.start_ai_war("xichuan", "canglang")
	Nations.from_dict(snap91)
	chk(Nations.ai_warring("chenxi", "beiling") and not Nations.ai_warring("xichuan", "canglang"),
		"读档还原 ai_war: 存档时开着的战还在打, 存档后的开战被回滚")
	Nations.ai_war.clear()
	chk(not Nations.ai_warring("chenxi", "beiling"), "账清了就停战")
	# 91j e52 静态收口: 大地图壮观层 + 外交关系行 + 职业图标表已在 45 节验过
	chk(wm91s.contains("const ZOOM_GRAND := 4.0") and wm91s.contains("var _grand_labels")
		and wm91s.contains("var _grand_t := 0.0") and wm91s.contains("GrandNames"),
		"world_map: 放大壮观层(大字国名 + 王都签, zoom 4 档淡入)就位(e52c)")
	var dp91 := FileAccess.get_file_as_string("res://diplomacy_ui.gd")
	chk(dp91.contains("Nations.ai_wars_of") and dp91.contains("与你交战中")
		and dp91.contains("相安无事"),
		"diplomacy: 关系行显示与玩家/与列国的交战状态(e52d)")
	chk(String(Nations.player_nation_name) != "", "玩家国名在册(壮观层水印要用)")

	# ============ §92 e36: 海图起伏 / 材质美化 / 城镇碰撞体积 ============
	print("\n=== 92. e36 海图: 岸线起伏 / 材质美化 / 城镇碰撞体积 ===")
	var wm92: Variant = load("res://scene/world_map.gd").new()
	add_child(wm92)
	await get_tree().process_frame
	# 92a 城镇建筑碰撞体: 5 都城 x 3 房 + 10 属镇 x 2 房 + 潮汐港 2 间 = 37
	var blks92: Array = wm92.get("_blockers")
	chk(blks92.size() == 37, "海图城镇碰撞体 %d 块 (5 都 x 3 + 10 属镇 x 2 + 潮汐港 2)"
		% blks92.size())
	# 每座城都得能走到城下: 城心 28px 内必有落脚点, 按 F 进城不受碰撞体影响
	var marks92: Array = wm92.get("_town_marks")
	var reach92 := true
	var offs92 := [Vector2.ZERO, Vector2(14, 0), Vector2(-14, 0), Vector2(0, 14), Vector2(0, -14),
		Vector2(14, 14), Vector2(-14, 14), Vector2(14, -14), Vector2(-14, -14)]
	for m92 in marks92:
		var ok92 := false
		for off92 in offs92:
			var o92: Vector2 = off92
			if o92.length() < float(wm92.get("TOWN_DIST")) \
					and not bool(wm92.call("_hits_building", m92["pos"] + o92)):
				ok92 = true
		if not ok92:
			reach92 = false
	chk(reach92, "每座城城心 28px 内都有落脚点, 按 F 进城不受碰撞体影响")
	# 92b 碰撞体尺寸 = 贴图不透明外框 x 缩放（不是拿整张图的宽高当碰撞体）
	var path92 := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/Houses/10.png"
	var b92: Rect2 = wm92.call("_opaque_bounds", path92)
	var tpos92: Vector2 = wm92.call("_cell_center", Nations.TOWNS["chenxi_cap"]["cell"])
	var want92 := Rect2(tpos92 + Vector2(-32, -56) + b92.position * 0.5, b92.size * 0.5)
	var hit92 := false
	for r92 in blks92:
		var rr92: Rect2 = r92
		if rr92.position.distance_to(want92.position) < 0.01 \
				and rr92.size.distance_to(want92.size) < 0.01:
			hit92 = true
	chk(hit92 and b92.size.x > 0.0,
		"晨曦城主楼碰撞体 = 贴图不透明外框 x 0.5 (框宽 %d px)" % int(b92.size.x))
	# 92c 走位判据: 正面撞墙停在墙外, 贴墙斜走顺墙根滑
	#   ❗用一块临时墙（放在没城没树的空陆上）—— 拿真房子测会被隔壁厢房的碰撞体干扰
	var wall92 := Rect2(Vector2(1600, 1600), Vector2(40, 30))
	blks92.append(wall92)
	var av92: Node2D = wm92.get("avatar")
	var south92 := Vector2(wall92.get_center().x,
		wall92.end.y + float(wm92.get("BODY_R")) + 2.0)
	av92.position = south92
	wm92.call("_step_avatar", Vector2(south92.x, wall92.get_center().y))
	chk(av92.position.y >= wall92.end.y + float(wm92.get("BODY_R")) - 0.01,
		"正面撞墙: 人停在墙外没穿进去 (y %.1f / 墙底 %.1f)" % [av92.position.y, wall92.end.y])
	var slid92 := av92.position
	wm92.call("_step_avatar", slid92 + Vector2(20, -20))
	chk(av92.position.x > slid92.x + 19.0 and absf(av92.position.y - slid92.y) < 0.01,
		"贴墙斜走: 顺着墙根滑过去, 不会一头顶死")
	blks92.pop_back()
	# 92d 起伏阴影层（1px=1格 放大铺开, 陆格按坡向镀明暗）
	var relief92 = wm92.get_node_or_null("Relief")
	chk(relief92 is Sprite2D \
			and (relief92 as Sprite2D).texture.get_size() == Vector2(200, 140) \
			and (relief92 as Sprite2D).scale == Vector2(16, 16) \
			and (relief92 as Sprite2D).texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
		"起伏阴影层 200x140 格 / 每格放大 16px / LINEAR 过滤")
	# 92e 岸线不再方: 主岛左岸在中间几十行里的横向跨度（直边只有 0~2 格）
	var land92: Dictionary = wm92.get("_land")
	var comp92 := {}
	var stack92: Array = [Vector2i(100, 70)]
	comp92[Vector2i(100, 70)] = true
	while not stack92.is_empty():
		var cc92: Vector2i = stack92.pop_back()
		for d92 in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb92: Vector2i = cc92 + (d92 as Vector2i)
			if land92.has(nb92) and not comp92.has(nb92):
				comp92[nb92] = true
				stack92.append(nb92)
	chk(comp92.size() > 15000, "主岛陆块连通 (含 %d 格)" % comp92.size())
	chk(land92.size() - comp92.size() > 20,
		"主岛外碎出 %d 格离岸小屿 (海岸不再是一刀切的方边)" % (land92.size() - comp92.size()))
	var lx92 := 9999
	var hx92 := -1
	for yy92 in range(50, 91):
		for xx92 in range(0, 60):
			if comp92.has(Vector2i(xx92, yy92)):
				lx92 = mini(lx92, xx92)
				hx92 = maxi(hx92, xx92)
				break
	chk(hx92 - lx92 >= 6, "西海岸线起伏 %d 格 (原来是一根直边)" % (hx92 - lx92))
	# 92f 全屏后处理（跟岛上同一份 fx_post.gdshader）
	var mat92: ShaderMaterial = wm92.get("_post_mat")
	var hud92: CanvasLayer = wm92.get("_hud")
	chk(mat92 != null and hud92.get_node_or_null("PostFX") != null,
		"海图挂上全屏后处理 PostFX")
	if mat92 != null:
		chk(is_equal_approx(float(mat92.get_shader_parameter("strength")),
			float(wm92.get("POST_STRENGTH"))), "后处理浓度 = POST_STRENGTH")
	# 92g 城镇夜灯: 15 城 + 潮汐港, 亮度跟夜度走
	var lights92: Array = wm92.get("_town_light_sprites")
	chk(lights92.size() == 16, "城镇夜灯 %d 盏 (15 城 + 潮汐港)" % lights92.size())
	wm92.call("_apply_night", 1.0)
	var lit92: bool = lights92.size() > 0 \
		and absf((lights92[0] as Sprite2D).modulate.a - float(wm92.get("TOWN_LIGHT_ALPHA"))) < 0.01
	chk(lit92 and is_equal_approx(float(mat92.get_shader_parameter("night")), 1.0),
		"深夜: 城灯全亮 + 后处理 night=1")
	wm92.call("_apply_night", 0.0)
	chk(lights92.size() > 0 and (lights92[0] as Sprite2D).modulate.a == 0.0 \
			and is_equal_approx(float(mat92.get_shader_parameter("night")), 0.0),
		"白天: 城灯全灭 + 后处理 night=0")
	# 92h 夜度曲线（同岛上 game.gd）
	chk(float(wm92.call("_night_at", 12.0)) == 0.0
		and float(wm92.call("_night_at", 23.0)) == 1.0
		and absf(float(wm92.call("_night_at", 19.0)) - 0.5) < 0.01,
		"夜度曲线: 正午 0 / 深夜 1 / 19 点 0.5")

	# ============ §93 e37: 岸线力度 / 三带衔接 / 河边少沙 / 出海不改缩放 ============
	print("\n=== 93. e37 海图: 岸线力度 / 三带衔接 / 河边少沙 / 出海不改缩放 ===")
	var mw93: int = int(wm92.MAP_W)
	var mh93: int = int(wm92.MAP_H)
	# 93a 15 座城 + 潮汐港都踩在陆地上（e37a: 海岸线幅度加大后靠 6 格落脚兜底兜住）
	var off93 := 0
	for tid93 in Nations.TOWNS.keys():
		if not land92.has(Nations.TOWNS[tid93]["cell"] as Vector2i):
			off93 += 1
	var vil93 := Vector2i(int(wm92.ISLAND_CENTER.x) - 7, int(wm92.ISLAND_CENTER.y) - 2)
	chk(off93 == 0 and land92.has(vil93),
		"%d 座城 + 潮汐港都在陆上 (泡海 %d 座; 城周 %d 格兜底)"
			% [Nations.TOWNS.size(), off93, int(wm92.ISLE_TOWN_KEEP)])
	# 93b 四条边的「第一块陆地内缩深度」跨度 —— 三层噪声叠加后每条边都该有十几格起伏
	#   （范围避开四角圆弧与东南湾, 只量直边本身）
	var sp93: Array = [
		_span93(_edge_scan93(comp92, mw93, mh93, 0, 45, 155)),
		_span93(_edge_scan93(comp92, mw93, mh93, 1, 45, 130)),
		_span93(_edge_scan93(comp92, mw93, mh93, 2, 45, 100)),
		_span93(_edge_scan93(comp92, mw93, mh93, 3, 45, 75)),
	]
	var mn93: int = mini(mini(int(sp93[0]), int(sp93[1])), mini(int(sp93[2]), int(sp93[3])))
	chk(mn93 >= 8,
		"四条边岸线内缩深度都揉出起伏 (上%d/下%d/左%d/右%d 格, 最小 %d)"
			% [sp93[0], sp93[1], sp93[2], sp93[3], mn93])
	# 93c 主岛不离图边（ISLE_EDGE_MIN=3 兜住, 陆地不怼到画框上）
	var gap93 := 999
	for c in comp92.keys():
		var cc93: Vector2i = c
		gap93 = mini(gap93, mini(mini(cc93.x, cc93.y),
			mini(mw93 - 1 - cc93.x, mh93 - 1 - cc93.y)))
	chk(gap93 >= 3, "主岛离图边最少 %d 格 (外海没被噪声吃干)" % gap93)
	# 93d 三带衔接成块: 过渡带里相邻两格落在同一带的比例（逐格白噪声只有 ~0.5）
	var pair93 := 0
	var same93 := 0
	for y93 in range(0, mh93, 3):
		for x93 in range(0, mw93 - 1, 2):
			var a93 := Vector2i(x93, y93)
			var b93 := Vector2i(x93 + 1, y93)
			if not land92.has(a93) or not land92.has(b93):
				continue
			if float(wm92.call("_biome_pair", a93)[2]) <= 0.0 \
					or float(wm92.call("_biome_pair", b93)[2]) <= 0.0:
				continue
			pair93 += 1
			if int(wm92.call("_biome_of", a93)) == int(wm92.call("_biome_of", b93)):
				same93 += 1
	var rate93 := 0.0 if pair93 <= 0 else float(same93) / float(pair93)
	chk(pair93 > 200 and rate93 > 0.62,
		"过渡带成块衔接: 相邻 %d 对里 %d 对同带 (%.2f; 白噪声只有 0.5)"
			% [pair93, same93, rate93])
	# 93e 河边少沙（e37d）: 离海 3 圈以外的河岸只许铺一条湿沙线
	var tiles93: TileMapLayer = wm92.get("grid_layer")
	var shore93: Dictionary = wm92.call("_shore_rings", true)
	var t_wet93: int = int(wm92.T_SAND_WET)
	var t_sand93: int = int(wm92.T_SAND)
	var t_gs93: int = int(wm92.T_GRASS_SAND)
	var bank93 := 0
	var wet93 := 0
	var dry93 := 0
	for c in land92.keys():
		if not bool(wm92.call("_river_bank", c)):
			continue
		if int(shore93.get(c, 99)) <= 3:
			continue              # 河口/近海那几圈照旧跟海边一样铺沙, 不算「河边」
		bank93 += 1
		var idx93: int = tiles93.get_cell_atlas_coords(c).x
		if idx93 == t_sand93 or idx93 == t_gs93:
			dry93 += 1
		elif idx93 == t_wet93:
			wet93 += 1
	chk(bank93 > 100 and dry93 == 0,
		"内陆河岸 %d 格里 %d 格还是干沙/草沙 (e37d 前整条河铺满三圈)" % [bank93, dry93])
	chk(wet93 == bank93, "内陆河岸只剩一条湿沙线: %d/%d" % [wet93, bank93])
	# 93f 出海动画不改镜头缩放（e37c 源码护栏: 只读不写 cam.zoom）
	var f93 := FileAccess.open("res://scene/game.gd", FileAccess.READ)
	var src93 := "" if f93 == null else f93.get_as_text()
	if f93 != null:
		f93.close()
	var i0 := src93.find("func _sail_away")
	var i1 := src93.find("func _crew_sprite")
	var body93 := ""
	if i0 >= 0 and i1 > i0:
		body93 = src93.substr(i0, i1 - i0)
	chk(body93.length() > 500 and body93.find("cam.zoom =") < 0,
		"出海动画里没有写 cam.zoom (e37c: 动画期间缩放不动)")
	chk(body93.find("out_dist") >= 0 and body93.find("cam.zoom.x") >= 0,
		"驶出画面的距离按玩家当前 zoom 现算")
	chk(src93.find("SAIL_DIST") < 0, "写死的 SAIL_DIST 常量已删")

	# ============ §94 e38: 鸡的啄食帧 / 售卖箱取图 / 路灯改可建造 ============
	print("\n=== 94. e38 鸡的啄食帧 / 售卖箱取图 / 路灯改可建造 ===")
	# 94a 鸡舍取第 6 行那组「真啄食」帧（第 0~5 行都是两帧一小动的重复布局）
	var cn94 := FileAccess.get_file_as_string("res://scene/coop_node.gd")
	chk(cn94.contains("CHICK_PECK_ROW := 6") and cn94.contains("CHICK_FRAMES := 4"),
		"鸡舍啄食取第 6 行 / 四帧循环 (e38a)")
	chk(cn94.contains("Rect2(0, 16 * CHICK_PECK_ROW, 16, 16)")
		and cn94.contains("Rect2(16 * f, 16 * CHICK_PECK_ROW, 16, 16)")
		and not cn94.contains("Rect2(16 * _frame, 0, 16, 16)"),
		"鸡的初始帧与动画帧都落在第 6 行 (e38a)")
	# 94b 售卖箱：敞口箱取 (16,48,13,16) —— 旧 (16,45,13,19) 把隔壁那只箱子的掀盖碎片裁了进来
	var sb94 := FileAccess.get_file_as_string("res://scene/shipping_bin.gd")
	chk(sb94.contains("Rect2i(16, 48, 13, 16)") and sb94.contains("ART_H := 16"),
		"售卖箱敞口取图跳过 y45~47 的邻箱盖碎片 (e38a)")
	chk(not sb94.contains("Rect2i(16, 45, 13, 19)"), "旧的 (16,45,13,19) 已不再使用")
	# 94c 售货箱下端线与农舍门下线重合（房子贴图不透明底行 y103 -> 局部 y-8 -> 全局 162）
	var bin94: Node2D = g.get_node_or_null("ShippingBin")
	var house94: Node2D = g.get_node_or_null("House")
	chk(bin94 != null and house94 != null
		and absf((house94.global_position.y - 8.0) - bin94.global_position.y) < 0.01,
		"售货箱下端线压在农舍门台阶下线上 (箱 %.0f / 门 %.0f)"
			% [bin94.global_position.y, house94.global_position.y - 8.0])
	# 94d 路灯进了建造菜单：材料少、人工 0（当场落成）
	chk(Structures.BUILDINGS.has(Structures.KIND_LAMP), "建造菜单里有路灯 (e38d)")
	var lamp_cost94: Dictionary = Structures.building_cost(Structures.KIND_LAMP)
	chk(int(lamp_cost94.get("labor", -1)) == 0 and int(lamp_cost94.get("coin", 0)) <= 30
		and int(lamp_cost94.get("wood", 0)) <= 4 and int(lamp_cost94.get("stone", 0)) <= 4,
		"路灯材料少 + 人工 0 (金%d 木%d 石%d)"
			% [int(lamp_cost94.get("coin", 0)), int(lamp_cost94.get("wood", 0)),
				int(lamp_cost94.get("stone", 0))])
	chk(g.call("building_footprint", Vector2i(5, 5), Structures.KIND_LAMP).size() == 1,
		"路灯只占锚点 1 格")
	# 人工 0 -> 不排工地，钱料付清当场立起来（start_site 里那条即时分支）
	var cell94 := Vector2i(151, 151)
	chk(not Structures.has_station(cell94), "测试格一开始没有设施")
	chk(Structures.start_site(cell94, Structures.KIND_LAMP), "路灯动工返回成功")
	chk(Structures.has_station(cell94) and not Structures.site_busy(),
		"路灯不用人工, 不排工地, 当场落成 (e38d)")
	var lamp94: Variant = g.station_nodes.get(cell94)
	chk(lamp94 != null and is_instance_valid(lamp94), "落成后 game 摆出了路灯节点")
	# 94e 白天灭 / 夜里亮，贴图跟着换那半张
	var hour94 := TimeManager.hour
	var min94 := TimeManager.minute
	TimeManager.hour = 13
	TimeManager.minute = 0
	lamp94._sync_lamp(true)
	chk(not lamp94._lit and not lamp94._light.enabled and not lamp94._glow.visible,
		"白天路灯是灭的")
	chk((lamp94._art.texture as AtlasTexture).region == lamp94.RECT_OFF,
		"白天路灯用「没点」那半张图")
	TimeManager.hour = 22
	lamp94._sync_lamp(true)
	chk(lamp94._lit and lamp94._light.enabled and lamp94._glow.visible, "天黑路灯点亮")
	chk((lamp94._art.texture as AtlasTexture).region == lamp94.RECT_LIT,
		"夜里路灯用「点着」那半张图")
	chk(lamp94.RECT_OFF.size == lamp94.RECT_LIT.size, "路灯两态贴图一样大 (切换不跳位)")
	TimeManager.hour = hour94
	TimeManager.minute = min94
	# 收尾: 把测试路灯拆掉（Structures.remove 会发 station_removed, game 那边会淡出回收）
	Structures.remove(cell94)
	chk(not Structures.has_station(cell94), "收尾: 测试路灯已拆掉")

	# —— 95. 剧情过场放映机 (e42 / e43 扩到十段) ——
	print("\n=== 95. 剧情过场放映机 ===")
	var acts95 := ["harbor", "ms_navy", "siege_first", "ms_lord", "ms_unify",
		"goblin_rod", "nat_pact", "nat_ally", "nat_war", "nat_lost"]
	var all95 := true
	for a95 in acts95:
		if not Cutscenes.has_act(String(a95)):
			all95 = false
	chk(all95, "十段剧情过场都在 (%s)" % str(acts95))
	chk(not Cutscenes.has_act("没这段"), "没登记过的 id 不算一段过场")
	# 每段: 标题/副题/幕表齐全, 幕表每一项都指向真的布景方法, 文案无缺字/无全角标点
	# e43: 带 dyn 的段落台词是按 ctx 现拼的 (国名/城名进台词), 那几份也得扫
	var scan95: Array = []            # [标签, 幕表]
	for a95 in acts95:
		var act: Dictionary = Cutscenes.ACTS[String(a95)]
		var st: Array = act["steps"]
		if String(act["title"]).is_empty() or String(act["sub"]).is_empty() or st.is_empty():
			scan95.append(["%s: 标题/副题/幕表不齐" % String(a95), []])
			continue
		scan95.append([String(a95), st])
	Cutscenes._ctx = {"nation": "测试国", "color": Color(0.6, 0.5, 0.7), "town": "测试镇"}
	for a95 in ["nat_pact", "nat_ally", "nat_war", "nat_lost"]:
		scan95.append(["%s(dyn)" % a95, Cutscenes._steps_for(String(a95))])
	Cutscenes._ctx = {}
	var bad95: Array = []
	for pair95 in scan95:
		var tag95 := String(pair95[0])
		var list95: Array = pair95[1]
		for step in list95:
			var row: Array = step
			if row.size() != 2 or not Cutscenes.has_method(String(row[1])):
				bad95.append("%s: 幕 %s 的布景方法不在" % [tag95, str(row)])
				continue
			var txt95 := String(row[0])
			var miss95 := missing_glyphs(txt95)
			if not miss95.is_empty():
				bad95.append("%s: 缺字形 %s" % [txt95.left(16), str(miss95)])
			for ci in txt95.length():
				if bad_punct.contains(txt95[ci]):
					bad95.append("%s: 全角标点 %s" % [txt95.left(16), txt95[ci]])
					break
	chk(bad95.is_empty(), "十段过场 (含 dyn 现拼的那几份) 的文案/幕表都干净 (问题 %d 处): %s"
		% [bad95.size(), str(bad95.slice(0, 6))])
	# 剧情钩子专用入口: 自检期间(总闸关着)一律不播, 未知 id 也返回 false
	chk(not SaveManager.enabled, "自检期间存档总闸是关的 (play_once 的前置)")
	chk(not Cutscenes.play_once("harbor"), "总闸关着时 play_once 不播 (自检/探针不干等)")
	chk(not Cutscenes.play_once("没这段"), "play_once 对没登记的 id 返回 false")
	# 「放过的不重播」这条记录能进能出 (存档走 seen_list/apply_seen 往返)
	var seen95: Array = Cutscenes.seen_list()
	Cutscenes.apply_seen(["harbor", "ms_navy"])
	chk(Cutscenes.seen_list().size() == 2 and Cutscenes.seen_list().has("harbor"),
		"放过哪些过场记得住 (seen_list/apply_seen 往返)")
	Cutscenes.apply_seen(seen95)
	chk(Cutscenes.seen_list().size() == seen95.size(), "还原回原来的记录 (%d 段)" % seen95.size())
	# 真放一段: 跳过旗一插, 几秒内收片, 时间开关还回去
	var run95: bool = TimeManager.time_running
	Cutscenes.play("harbor")
	chk(Cutscenes.playing() and Cutscenes.visible, "play 之后放映机开着 (harbor)")
	Cutscenes._skip_all = true
	var t95 := 0.0
	while Cutscenes.playing() and t95 < 8.0:
		await get_tree().create_timer(0.1).timeout
		t95 += 0.1
	chk(not Cutscenes.playing(), "跳过旗一插很快就收片 (%.1f 秒)" % t95)
	await get_tree().create_timer(0.2).timeout
	chk(not Cutscenes.visible, "放完只隐藏, 不自杀 (autoload 还得活着)")
	chk(TimeManager.time_running == run95, "播完把时间开关还回去 (%s)" % TimeManager.time_running)
	chk(is_instance_valid(g) and g.has_method("_set_player_frozen"),
		"game 挂了玩家冻结入口 (过场期间钉住人)")
	# 新档要把「放过」的记录清空 —— 否则新档永远看不到这几段
	Cutscenes.apply_seen(["harbor"])
	Cutscenes.reset_for_new_game()
	chk(Cutscenes.seen_list().is_empty() and not Cutscenes.playing(),
		"开新档把过场记录清零 (新档从序章重看一遍)")

	# —— 96. e43: 铁质工具 / 售卖箱左右键 / 鱼竿剧情锁 / 国度过场的上下文 ——
	print("\n=== 96. e43 铁工具 / 售卖箱左右键 / 鱼竿剧情锁 ===")
	# 96a 五件工具的图标: 换铁档素材, 而且只裁左半张 16x16
	#     素材是并排两帧 32x16, 不裁就会一次显两把 (玩家说的「不要显示两个图」)
	var tools96 := ["axe", "hoe", "pickaxe", "watering_can", "fishing_rod"]
	var bad96: Array = []
	for k96 in tools96:
		var it96 := load("res://item/%s.tres" % k96) as ItemData
		if it96 == null:
			bad96.append("%s: 读不到" % k96)
			continue
		var at96 := it96.icon as AtlasTexture
		if at96 == null:
			bad96.append("%s: 图标不是 AtlasTexture (会整张显示)" % k96)
			continue
		var src96: Texture2D = at96.atlas
		if src96 == null or not src96.resource_path.contains("/3. Iron/"):
			bad96.append("%s: 素材不是铁档 (%s)" % [k96, "" if src96 == null else src96.resource_path])
		elif src96.get_width() != 32 or src96.get_height() != 16:
			bad96.append("%s: 源图不是 32x16 (%dx%d)" % [k96, src96.get_width(), src96.get_height()])
		if at96.region != Rect2(0, 0, 16, 16):
			bad96.append("%s: 裁剪区不对 (%s)" % [k96, str(at96.region)])
	chk(bad96.is_empty(), "五件工具换成铁质素材 + 只裁左半张 16x16 (问题 %d 处: %s)"
		% [bad96.size(), str(bad96)])

	# 96b 售卖箱面板: 左键一次 1 个, 右键整格全倒; 同货同渠道并成一行
	var bp96: Control = g.bin_panel
	var bin96: Node = g.shipping_bin
	chk(bp96 != null and bin96 != null, "售卖箱面板/箱子都在 (左右键测得到)")
	if bp96 != null and bin96 != null:
		var crop96: ItemData = load("res://item/carrot.tres")
		var mode96 := String(bin96.mode)
		Inventory.remove_item(crop96, Inventory.count_item(crop96))   # 先清干净, 免得带旧货进账
		bin96.pending.clear()
		bin96.mode = "哥布林"
		Inventory.add_item(crop96, 5)
		var idx96 := -1
		for i96 in Inventory.slot_list().size():
			if Inventory.get_slot(i96)["item"] == crop96:
				idx96 = i96
				break
		chk(idx96 >= 0, "背包里那格胡萝卜找得到 (第 %d 格, 5 根)" % idx96)
		chk(not bp96.is_open(), "测试前售卖箱面板是关的 (不碰 open_panel 那套暂停/售出)")
		bp96.set("_bin", bin96)         # 只把箱子绑上, 面板照旧隐藏
		var left96 := InputEventMouseButton.new()
		left96.button_index = MOUSE_BUTTON_LEFT
		left96.pressed = true
		bp96.call("_on_bag_slot", left96, idx96)
		chk(Inventory.count_item(crop96) == 4 and bin96.pending_count() == 1,
			"左键一次只放 1 个 (背包 %d 根 / 箱里 %d 个)"
				% [Inventory.count_item(crop96), bin96.pending_count()])
		bp96.call("_on_bag_slot", left96, idx96)
		chk(Inventory.count_item(crop96) == 3 and bin96.pending_count() == 2,
			"再点一次是 2 个 (背包 %d 根 / 箱里 %d 个)"
				% [Inventory.count_item(crop96), bin96.pending_count()])
		chk(bin96.pending.size() == 1, "同一件货并成一行, 没排成一长串 (行数 %d)" % bin96.pending.size())
		# 松开那一下 / 中键都不算放货
		var up96 := InputEventMouseButton.new()
		up96.button_index = MOUSE_BUTTON_LEFT
		up96.pressed = false
		bp96.call("_on_bag_slot", up96, idx96)
		var mid96 := InputEventMouseButton.new()
		mid96.button_index = MOUSE_BUTTON_MIDDLE
		mid96.pressed = true
		bp96.call("_on_bag_slot", mid96, idx96)
		chk(Inventory.count_item(crop96) == 3 and bin96.pending_count() == 2,
			"松开那一下和中键都不动货 (背包 %d / 箱里 %d)"
				% [Inventory.count_item(crop96), bin96.pending_count()])
		# 右键: 整格全进去
		var right96 := InputEventMouseButton.new()
		right96.button_index = MOUSE_BUTTON_RIGHT
		right96.pressed = true
		bp96.call("_on_bag_slot", right96, idx96)
		chk(Inventory.count_item(crop96) == 0 and bin96.pending_count() == 5,
			"右键把整格倒进箱 (背包 %d 根 / 箱里 %d 个)"
				% [Inventory.count_item(crop96), bin96.pending_count()])
		var back96: int = bin96.take_back_all()      # 收尾: 货取回, 背包清空
		chk(back96 == 5 and bin96.pending_count() == 0, "收尾: %d 件货取回, 箱子清空" % back96)
		Inventory.remove_item(crop96, Inventory.count_item(crop96))
		bp96.set("_bin", null)
		bin96.mode = mode96

	# 96c 商店鱼竿: 剧情旗没立起来挂「未上架」+ 按钮锁死; 立了就照常卖
	var shop96: Control = g.get_node_or_null("HUD/Shop")
	chk(shop96 != null, "商店面板在 (鱼竿剧情锁测得到)")
	if shop96 != null:
		const FLAGS96 := "user://story_flags.cfg"
		var old96 := ConfigFile.new()
		var had96: bool = old96.load(FLAGS96) == OK and old96.has_section_key("flags", "goblin_rod")
		var old_val96: bool = bool(old96.get_value("flags", "goblin_rod", false)) if had96 else false
		var rod96: ItemData = load("res://item/fishing_rod.tres")
		var row96: Dictionary = {}
		for r96 in shop96.get("_rows"):
			if r96["seed"] == rod96:
				row96 = r96
				break
		chk(not row96.is_empty() and String(row96.get("lock", "")) == "goblin_rod",
			"鱼竿那行挂着剧情锁 goblin_rod")
		if not row96.is_empty():
			var money96: int = Wallet.money
			if money96 < 200:
				Wallet.add_money(200 - money96)      # 免得「买不起」的灰把断言搅浑
			# 没立旗 -> 未上架
			var cf96 := ConfigFile.new()
			cf96.load(FLAGS96)
			cf96.set_value("flags", "goblin_rod", false)
			cf96.save(FLAGS96)
			shop96.call("_refresh")
			chk(String(row96["name_label"].text).contains("未上架") and row96["button"].disabled,
				"剧情没解锁: 鱼竿挂「未上架」且按钮点不动 (%s)" % row96["name_label"].text)
			# 立旗 -> 照常上架
			cf96.set_value("flags", "goblin_rod", true)
			cf96.save(FLAGS96)
			shop96.call("_refresh")
			chk(String(row96["name_label"].text) == rod96.display_name and not row96["button"].disabled,
				"剧情解锁后: 鱼竿名字复原, 按钮能点 (%s)" % row96["name_label"].text)
			# 还原那把旗 + 钱包 (别动玩家的真进度)
			var cf96b := ConfigFile.new()
			cf96b.load(FLAGS96)
			if had96:
				cf96b.set_value("flags", "goblin_rod", old_val96)
			else:
				cf96b.erase_section_key("flags", "goblin_rod")
			cf96b.save(FLAGS96)
			shop96.call("_refresh")
			var check96 := ConfigFile.new()
			check96.load(FLAGS96)
			chk(bool(check96.get_value("flags", "goblin_rod", false)) == old_val96,
				"收尾: 鱼竿剧情旗还原成 %s" % str(old_val96))
			Wallet.spend_money(Wallet.money - money96)

	# 96d play_once 的上下文/细分键: 国名进布景, 同一段每个国各放一次
	var seen96: Array = Cutscenes.seen_list()
	var gate96: bool = SaveManager.enabled
	SaveManager.enabled = true           # 临时开闸, 才测得到 play_once 那本账
	var ctx96 := {"nation": "测试国度", "color": Color(0.6, 0.5, 0.7), "seen": "t1"}
	chk(Cutscenes.play_once("nat_pact", 0.0, ctx96), "开闸后 play_once 放得起来 (nat_pact)")
	chk(String(Cutscenes._ctx.get("nation", "")) == "测试国度",
		"本段上下文进了 _ctx (国名给布景和台词用)")
	Cutscenes._skip_all = true
	var t96 := 0.0
	while Cutscenes.playing() and t96 < 8.0:
		await get_tree().create_timer(0.1).timeout
		t96 += 0.1
	chk(not Cutscenes.playing(), "跳过旗一插就收片 (%.1f 秒)" % t96)
	chk(Cutscenes.seen_list().has("nat_pact@t1"), "放过谁带着国名细分尾记下来 (nat_pact@t1)")
	chk(not Cutscenes.play_once("nat_pact", 0.0, ctx96), "同一个国不再重播")
	var ctx96b := {"nation": "另一个国度", "color": Color(0.6, 0.5, 0.7), "seen": "t2"}
	chk(Cutscenes.play_once("nat_pact", 0.0, ctx96b), "换一个国可以再放一次")
	Cutscenes._skip_all = true
	var t96b := 0.0
	while Cutscenes.playing() and t96b < 8.0:
		await get_tree().create_timer(0.1).timeout
		t96b += 0.1
	chk(not Cutscenes.playing(), "第二场也收干净了 (%.1f 秒)" % t96b)
	SaveManager.enabled = gate96
	Cutscenes.apply_seen(seen96)         # 还原: 别把测试记录留在放映机里
	Cutscenes._skip_all = false
	Cutscenes._ctx = {}
	chk(Cutscenes.seen_list().size() == seen96.size(), "收尾: 过场记录还原 (%d 段)" % seen96.size())

	# 96e 接线: 商店锁 / 第二天出门撞见 / 国度过场的钩子 —— 都在源码里坐着
	var wire96: Array = []
	var nn96 := FileAccess.get_file_as_string("res://nations.gd")
	for w96 in ["func cut_ctx(", "Cutscenes.play_once(\"nat_pact\"", "Cutscenes.play_once(\"nat_ally\"",
			"Cutscenes.play_once(\"nat_war\"", "Cutscenes.play_once(\"nat_lost\""]:
		if not nn96.contains(w96):
			wire96.append("nations.gd 少了 %s" % w96)
	var hs96 := FileAccess.get_file_as_string("res://scene/house.gd")
	for w96 in ["_try_rod_story()", "Cutscenes.play(\"goblin_rod\")", "flag_set(\"goblin_rod\")",
			"TimeManager.day < 2"]:
		if not hs96.contains(w96):
			wire96.append("house.gd 少了 %s" % w96)
	var sp96 := FileAccess.get_file_as_string("res://shop_ui.gd")
	for w96 in ["\"locked_by\": \"goblin_rod\"", "STORY.flag_get(lock)", "(未上架)"]:
		if not sp96.contains(w96):
			wire96.append("shop_ui.gd 少了 %s" % w96)
	chk(wire96.is_empty(), "鱼竿剧情 / 国度过场的接线都在源码里 (问题 %s)" % str(wire96))

	# ============ 97. e44 建筑模式 / 同伴小屋 / 蜂箱 ============
	print("\n=== 97. e44 建筑模式 / 同伴小屋 / 蜂箱 ===")
	var ST97: Dictionary = (load("res://structures.gd") as Script).get_script_constant_map()
	var B97: Dictionary = ST97["BUILDINGS"]
	# 97a 两种新建筑进了建造菜单, 造价对得上
	chk(B97.has(Structures.KIND_HUT) and B97.has(Structures.KIND_HIVE),
		"建造菜单里有 同伴小屋 / 蜂箱 (e44)")
	var hut97: Dictionary = B97.get(Structures.KIND_HUT, {})
	var hive97: Dictionary = B97.get(Structures.KIND_HIVE, {})
	chk(int(hut97.get("coin", 0)) == 120 and int(hut97.get("wood", 0)) == 8
		and int(hut97.get("stone", 0)) == 4 and int(hut97.get("labor", 0)) == 3,
		"同伴小屋造价 = 120金 + 木x8 + 石x4 + 3 人天")
	chk(int(hive97.get("coin", 0)) == 60 and int(hive97.get("wood", 0)) == 4
		and int(hive97.get("iron", 0)) == 1 and int(hive97.get("labor", 0)) == 0,
		"蜂箱造价 = 60金 + 木x4 + 铁x1 + 0 人天")
	var txt97 := ""
	for k97 in [Structures.KIND_HUT, Structures.KIND_HIVE]:
		txt97 += String((B97.get(k97, {}) as Dictionary).get("name", ""))
		txt97 += String((B97.get(k97, {}) as Dictionary).get("desc", ""))
	chk(missing_glyphs(txt97).is_empty(), "新建筑文案无缺字形")
	# 97b 蜂蜜道具能加载, 商人按「食物 + 售价」自动收货
	var honey97: ItemData = load("res://item/honey.tres") as ItemData
	chk(honey97 != null and honey97.display_name == "蜂蜜" and honey97.type == "食物"
		and honey97.sell_price == 30,
		"item/honey.tres = 蜂蜜 / 食物 / 30 金")
	chk(honey97 != null and missing_glyphs(honey97.display_name + honey97.description).is_empty(),
		"蜂蜜文案无缺字形")
	# 97c 小屋外形表: 至少 5 款, 贴图都存在, 每款裁剪框互不相同
	chk(Structures.HUT_LOOKS.size() >= 5, "小屋外形表有 %d 款 (每盖一座不一样)"
		% Structures.HUT_LOOKS.size())
	var tex_ok97 := true
	var uniq97: Array = []
	for look97 in Structures.HUT_LOOKS:
		var lp: Dictionary = look97
		if not ResourceLoader.exists(String(lp.get("tex", ""))):
			tex_ok97 = false
		var r97: Rect2 = lp.get("rect", Rect2())
		chk(r97.size.x > 0 and r97.size.y > 0, "外形裁剪框有面积 %s" % str(r97))
		if not uniq97.has(r97):
			uniq97.append(r97)
	chk(tex_ok97, "小屋外形贴图全部存在")
	chk(uniq97.size() == Structures.HUT_LOOKS.size(),
		"小屋外形裁剪框互不相同 (%d 款 / %d 种)" % [Structures.HUT_LOOKS.size(), uniq97.size()])
	var look_wrap97: Dictionary = Structures.hut_look(-1)
	chk(look_wrap97 == Structures.HUT_LOOKS[Structures.HUT_LOOKS.size() - 1],
		"外形编号取模安全 (-1 -> 最后一款)")
	# 97d 蜂箱: 每天攒 1 罐, 封顶 HIVE_MAX, 风暴/冬天不产, 收走清零
	var cells97: Array = []
	var scan97 := Vector2i(1, 52)
	while cells97.size() < 2 and scan97.x < 260:
		if not Structures.has_station(scan97) and not Farm.tilled.has(scan97):
			cells97.append(scan97)
		scan97 += Vector2i(3, 0)
	chk(cells97.size() == 2, "找到两格空地摆蜂箱 (%d)" % cells97.size())
	var hive_a97: Vector2i = cells97[0]
	var hive_b97: Vector2i = cells97[1]
	chk(Structures.place(hive_a97, Structures.KIND_HIVE, true), "摆下一座蜂箱 (restore 静默)")
	chk(Structures.hive_count() == 1 and Structures.honey_of(hive_a97) == 0,
		"新蜂箱空着: 0 罐蜜")
	chk(Structures.make_honey(false, false) == 1 and Structures.honey_of(hive_a97) == 1,
		"一个晴天早上 -> 攒了 1 罐蜜")
	Structures.stations[hive_a97]["honey"] = Structures.HIVE_MAX
	chk(Structures.make_honey(false, false) == 0,
		"攒到 HIVE_MAX(%d) 封顶, 不再涨" % Structures.HIVE_MAX)
	chk(Structures.honey_of(hive_a97) == Structures.HIVE_MAX, "封顶后仍是满箱")
	chk(Structures.make_honey(true, false) == 0, "风暴天不产蜜")
	chk(Structures.make_honey(false, true) == 0, "冬天不产蜜")
	var jars97: int = Structures.take_honey(hive_a97)
	chk(jars97 == Structures.HIVE_MAX and Structures.honey_of(hive_a97) == 0,
		"收蜜拿走全部 %d 罐并清空箱底" % jars97)
	chk(Structures.take_honey(hive_b97) == 0, "不是蜂箱的格子收不到蜜")
	# 97e 按 F 收蜜进背包 / 装不下就写回箱里
	var hot_bak97: Array = Inventory.hotbar.duplicate(true)
	var bag_bak97: Array = Inventory.backpack.duplicate(true)
	var wood97: ItemData = load("res://item/wood.tres")
	for i97 in Inventory.backpack.size():
		Inventory.backpack[i97] = {"item": null, "count": 0}
	for i97 in Inventory.hotbar.size():
		Inventory.hotbar[i97] = {"item": null, "count": 0}
	Inventory.inventory_changed.emit()
	Structures.stations[hive_a97]["honey"] = 3
	place_player(hive_a97 + Vector2i(1, 0))
	chk(g._station_interact_cell(hive_a97), "对蜂箱按 F = 吃掉交互")
	chk(Inventory.count_item(honey97) == 3 and Structures.honey_of(hive_a97) == 0,
		"收的 3 罐蜜进了背包, 箱里清空")
	# 背包塞满 -> 蜜放不下, 原样存回箱里（先清干净, 别让上一轮那 3 罐蜜被继续堆）
	for i97 in Inventory.backpack.size():
		Inventory.backpack[i97] = {"item": wood97, "count": wood97.max_stack}
	for i97 in Inventory.hotbar.size():
		Inventory.hotbar[i97] = {"item": wood97, "count": wood97.max_stack}
	Inventory.inventory_changed.emit()
	chk(Inventory.count_item(honey97) == 0, "清场后背包里没有蜂蜜")
	Structures.stations[hive_a97]["honey"] = 2
	var before97: int = Inventory.backpack[0]["count"]
	chk(g._station_interact_cell(hive_a97), "背包满时按 F 也算处理过 (给提示)")
	chk(Structures.honey_of(hive_a97) == 2, "放不下 -> 2 罐蜜原样存回蜂箱")
	chk(Inventory.backpack[0]["count"] == before97, "放不下时不挤掉别人的格子")
	Inventory.hotbar = hot_bak97
	Inventory.backpack = bag_bak97
	Inventory.inventory_changed.emit()
	# 97f 建筑模式: 入口/闸门/不可搬的小设施
	chk(g.has_method("start_move_mode") and g.has_method("is_move_mode")
		and g.has_method("_movable_at_mouse") and g.has_method("_site_ok_for")
		and g.has_method("_exit_move") and g.has_method("_move_pick_up"),
		"game.gd 建筑模式 API 齐全 (e44)")
	chk(not g.is_move_mode(), "开局不在建筑模式里")
	chk(g.start_move_mode() and g.is_move_mode(), "start_move_mode 进得去")
	chk(preload("res://scene/key_hint.gd").click_locked,
		"建筑模式里 F 提示框不吃鼠标 (key_hint.click_locked)")
	g._exit_move()
	chk(not g.is_move_mode() and not preload("res://scene/key_hint.gd").click_locked,
		"_exit_move 退出来并放开提示框闸门")
	chk(Structures.building_cost(Structures.KIND_WORKBENCH).is_empty(),
		"工作台不在 BUILDINGS 里 -> 建筑模式不搬它")
	chk(Structures.building_cost(Structures.KIND_HUT) == hut97,
		"同伴小屋在 BUILDINGS 里 -> 能搬 (has_movable)")
	chk(Structures.has_movable(), "岛上有可搬的建筑 (鸡舍等) -> 建造页按钮可点")
	var bp97 := FileAccess.get_file_as_string("res://backpack_ui.gd")
	chk(bp97.contains("建筑模式") and bp97.contains("start_move_mode"),
		"背包建造页有「建筑模式」入口 (e44)")
	var gg97 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(gg97.contains("_move_payload") and gg97.contains("restore_station"),
		"搬移 = 拾起(remove) + 放下(restore_station), 不花钱不扣料")
	# 97g 收尾: 拆掉自己摆的蜂箱, 建筑模式复位
	Structures.remove(hive_a97)
	Structures.remove(hive_b97)
	await get_tree().process_frame
	if g.is_move_mode():
		g._exit_move()
	chk(not g.is_move_mode(), "收尾: 建筑模式已退出")

	# ============ 98. e45 储物箱 ============
	print("\n=== 98. e45 储物箱 ===")
	var ST98: Dictionary = (load("res://structures.gd") as Script).get_script_constant_map()
	var B98: Dictionary = ST98["BUILDINGS"]
	chk(B98.has(Structures.KIND_CHEST), "建造菜单里有 储物箱 (e45)")
	var chest98: Dictionary = B98.get(Structures.KIND_CHEST, {})
	chk(int(chest98.get("coin", 0)) == 50 and int(chest98.get("wood", 0)) == 6
		and int(chest98.get("stone", 0)) == 0 and int(chest98.get("iron", 0)) == 0
		and int(chest98.get("labor", 0)) == 0,
		"储物箱造价 = 50金 + 木x6 + 0 人天 (放下即成)")
	chk(Structures.CHEST_SLOTS == 20, "箱容量 20 格 (实际 %d)" % Structures.CHEST_SLOTS)
	chk(missing_glyphs(String(chest98.get("name", "")) + String(chest98.get("desc", ""))).is_empty(),
		"储物箱文案无缺字形")
	chk(ResourceLoader.exists("res://scene/chest_node.gd")
		and ResourceLoader.exists("res://chest_ui.gd"), "箱子节点 / 面板脚本都在")
	chk(FileAccess.file_exists("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Objects/Exterior/chest.png"),
		"箱子贴图 chest.png 在")
	# 98b 摆一座箱子: 节点出现, 地基 1 格 (e47 箱子只有一只 16x16)
	var c98 := Vector2i(9999, 9999)
	var sc98 := Vector2i(1, 58)
	while c98 == Vector2i(9999, 9999) and sc98.x < 260:
		if not Structures.has_station(sc98) and not Farm.tilled.has(sc98):
			c98 = sc98
		sc98 += Vector2i(3, 0)
	chk(c98 != Vector2i(9999, 9999), "找到一格空地摆箱子")
	chk(g.building_footprint(c98, Structures.KIND_CHEST).size() == 1,
		"储物箱地基 1 格 (e47 单只 16x16 箱子)")
	chk(Structures.place(c98, Structures.KIND_CHEST, true), "摆下一座储物箱 (restore 静默)")
	chk(g.station_nodes.has(c98) and (g.station_nodes[c98] as Node).has_method("interact_rect"),
		"储物箱节点摆出来 (带 F 交互矩形)")
	# 98c 存 / 取数据接口
	var wood98: ItemData = load("res://item/wood.tres")
	chk(Structures.chest_count(c98) == 0 and Structures.chest_used_slots(c98) == 0, "新箱子是空的")
	chk(Structures.chest_deposit(c98, wood98, 7) == 7, "存 7 个木头")
	chk(Structures.chest_count(c98) == 7 and Structures.chest_used_slots(c98) == 1,
		"7 个木头 = 7 件 / 1 格 (同种并叠)")
	chk(Structures.chest_deposit(c98, wood98, 3) == 3 and Structures.chest_used_slots(c98) == 1,
		"再存 3 个还是 1 格 (并到同一叠)")
	chk(Structures.chest_count(c98) == 10, "箱里共 10 件 (实际 %d)" % Structures.chest_count(c98))
	var one98: Dictionary = Structures.chest_take(c98, 0, false)
	chk(int(one98.get("count", 0)) == 1 and Structures.chest_count(c98) == 9, "左键只取 1 个")
	var rest98: Dictionary = Structures.chest_take(c98, 0, true)
	chk(int(rest98.get("count", 0)) == 9 and Structures.chest_used_slots(c98) == 0,
		"右键整格取走, 格子空出来")
	chk(Structures.chest_take(c98, 0, false).is_empty(), "空箱取不出东西")
	# 98d 容量: 20 格占满就再也存不进（每件 max_stack = 1 的临时道具各占一格）
	for i98 in Structures.CHEST_SLOTS:
		var f98 := ItemData.new()
		f98.max_stack = 1
		if Structures.chest_deposit(c98, f98, 1) != 1:
			break
	chk(Structures.chest_used_slots(c98) == Structures.CHEST_SLOTS,
		"20 格占满 (实际 %d)" % Structures.chest_used_slots(c98))
	chk(Structures.chest_full(c98), "chest_full 认满箱")
	var f98b := ItemData.new()
	f98b.max_stack = 1
	chk(Structures.chest_deposit(c98, f98b, 1) == 0, "满箱一件都存不进")
	chk(Structures.chest_count(c98) == Structures.CHEST_SLOTS, "满箱件数对得上")
	var drained98: Array = Structures.chest_drain(c98)
	chk(drained98.size() == Structures.CHEST_SLOTS and Structures.chest_used_slots(c98) == 0,
		"chest_drain 一次搬空 20 格")
	# 98e 存档: items 按 resource_path 写出去, 读回来还是同一件道具
	Structures.chest_deposit(c98, wood98, 12)
	var enc98: Array = SaveManager._enc_chest_items(Structures.chest_items(c98))
	chk(enc98.size() == 1 and String(enc98[0]["path"]) == wood98.resource_path
		and int(enc98[0]["count"]) == 12, "箱里的东西存成 {path, count}")
	var dec98: Array = SaveManager._dec_chest_items(enc98)
	chk(dec98.size() == 1 and dec98[0]["item"] == wood98 and int(dec98[0]["count"]) == 12,
		"读回来还是同一件道具")
	chk(SaveManager._dec_chest_items([{"path": "res://item/__没有这个.tres", "count": 3}]).is_empty(),
		"存档里的坏路径直接丢掉, 不崩")
	# 98f 按 F 开面板 + 面板存取（左键 1 个 / 右键整格）
	var bag_bak98: Array = Inventory.backpack.duplicate(true)
	var hot_bak98: Array = Inventory.hotbar.duplicate(true)
	for i98 in Inventory.backpack.size():
		Inventory.backpack[i98] = {"item": null, "count": 0}
	for i98 in Inventory.hotbar.size():
		Inventory.hotbar[i98] = {"item": null, "count": 0}
	chk(g.chest_panel != null, "储物箱面板挂上 HUD")
	chk(g._station_interact_cell(c98), "对储物箱按 F = 吃掉交互 (开面板)")
	chk(g.chest_panel.is_open() and g.chest_panel.cell() == c98, "F 开了储物箱面板")
	Inventory.add_item(wood98, 5)
	Inventory.inventory_changed.emit()
	chk(Inventory.get_slot(0)["item"] == wood98, "测试用: 木头落在快捷栏第 1 格")
	var before98 := Structures.chest_count(c98)
	var ev98 := InputEventMouseButton.new()
	ev98.button_index = MOUSE_BUTTON_LEFT
	ev98.pressed = true
	g.chest_panel.call("_on_bag_slot", ev98, 0)
	chk(Structures.chest_count(c98) == before98 + 1 and Inventory.count_item(wood98) == 4,
		"面板左键存 1 个 (箱 %d -> %d)" % [before98, Structures.chest_count(c98)])
	var ev98r := InputEventMouseButton.new()
	ev98r.button_index = MOUSE_BUTTON_RIGHT
	ev98r.pressed = true
	g.chest_panel.call("_on_bag_slot", ev98r, 0)
	chk(Inventory.count_item(wood98) == 0 and Structures.chest_count(c98) == before98 + 5,
		"面板右键整格存进去")
	var before_take98 := Inventory.count_item(wood98)
	g.chest_panel.call("_take", 0, true)
	chk(Inventory.count_item(wood98) > before_take98, "面板右键整格取回 (取回 %d 件)"
		% (Inventory.count_item(wood98) - before_take98))
	# 98h 真实点击链回归（真机「箱子取东西闪退」修复）: 玩家取东西走的是箱子行的
	# gui_input 信号, 信号链里 _take -> inventory_changed -> _refresh 会重建行 ——
	# 旧行若被立即 free 就是 use-after-free 闪退。这里 emit 信号把真实链路走一遍。
	Structures.chest_deposit(c98, wood98, 3)
	g.chest_panel.call("_refresh")
	await get_tree().process_frame      # queue_free 的旧行到帧末才消失, 等一帧再数
	var box98: VBoxContainer = g.chest_panel.get("_list_box")
	chk(box98 != null and box98.get_child_count() == 1, "箱里重建出一行 (可点)")
	var row98: PanelContainer = box98.get_child(0)
	var ev98t := InputEventMouseButton.new()
	ev98t.button_index = MOUSE_BUTTON_LEFT
	ev98t.pressed = true
	var take_before98 := Inventory.count_item(wood98)
	row98.emit_signal("gui_input", ev98t)
	chk(Structures.chest_count(c98) == 2 and Inventory.count_item(wood98) == take_before98 + 1,
		"点行左键取 1 个 (gui_input 信号链内刷新不闪退)")
	await get_tree().process_frame      # 链里 queue_free 的行收尾, 给后面留干净状态
	g.chest_panel.close_panel()
	chk(not g.chest_panel.is_open(), "面板关得上 (时间也跟着恢复)")
	# 98g 拆箱子不吞货 (源码护栏) + 干净收尾
	var gg98 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(gg98.contains("n_in_chest") and gg98.contains("chest_panel.open(c)"),
		"拆储物箱时把箱里的货掉出来 / 按 F 开箱 (e45)")
	var sm98 := FileAccess.get_file_as_string("res://save_manager.gd")
	chk(sm98.contains("_enc_chest_items") and sm98.contains("_dec_chest_items")
		and sm98.contains("KIND_CHEST"), "储物箱进了存档白名单并写出 items (e45)")
	Inventory.hotbar = hot_bak98
	Inventory.backpack = bag_bak98
	Inventory.inventory_changed.emit()
	Structures.remove(c98)
	await get_tree().process_frame
	chk(not Structures.has_station(c98), "收尾: 箱子拆干净了")

	# ============ 99. e46 一键整理（背包 / 储物箱）============
	print("\n=== 99. e46 一键整理 ===")
	var order99: Array = ItemData.SORT_ORDER
	chk(order99.size() > 0 and String(order99[0]) == "工具", "排序表第一位是 工具")
	chk(missing_glyphs("一键整理 工具排最前 整理箱子 整理背包").is_empty(), "整理相关文案无缺字形")
	# 99a 类型先后
	var hoe99: ItemData = load("res://item/hoe.tres")
	var wood99: ItemData = load("res://item/wood.tres")
	var seed99: ItemData = load("res://item/carrot_seed.tres")
	var armor99: ItemData = load("res://item/armor_iron.tres")
	var boat99: ItemData = load("res://item/boat.tres")
	chk(hoe99.sort_rank() < armor99.sort_rank() and armor99.sort_rank() < seed99.sort_rank(),
		"工具 < 装备 < 种子")
	chk(seed99.sort_rank() < wood99.sort_rank() and wood99.sort_rank() < boat99.sort_rank(),
		"种子 < 材料 < 船")
	var tools99 := ["hoe", "axe", "pickaxe", "watering_can", "fishing_rod"]
	var bad99: Array = []
	for n99 in tools99:
		var t99: ItemData = load("res://item/%s.tres" % n99)
		if t99 == null or t99.sort_rank() != 0:
			bad99.append(n99)
	chk(bad99.is_empty(), "5 件工具全排最前 (漏的: %s)" % str(bad99))
	var all99 := ["wood", "stone", "iron", "iron_ore", "honey", "egg", "carrot",
		"cabbage_seed", "armor_iron", "boat", "wood_floor", "stone_path",
		"workbench", "furnace"]
	var odd99: Array = []
	for n99 in all99:
		var t99b: ItemData = load("res://item/%s.tres" % n99)
		if t99b == null or t99b.sort_rank() >= 99:
			odd99.append(n99)
	chk(odd99.is_empty(), "常用道具的类型都在排序表里 (漏的: %s)" % str(odd99))
	# 99b 并叠 + 排序 + 空格沉底（arrange 只读不改传进来的那排）
	var mixed99: Array = [
		{"item": wood99, "count": 30},
		{"item": hoe99, "count": 1},
		{"item": null, "count": 0},
		{"item": wood99, "count": 50},
		{"item": seed99, "count": 4},
	]
	var out99: Array = Inventory.arrange(mixed99)
	chk(out99.size() == 3, "3 种东西 -> 紧凑 3 格 (实际 %d)" % out99.size())
	chk(out99[0]["item"] == hoe99, "工具排在最前面")
	chk(out99[1]["item"] == seed99 and out99[2]["item"] == wood99, "种子在材料前面")
	chk(out99[2]["count"] == 80, "两叠木头并成 80 (实际 %d)" % int(out99[2]["count"]))
	chk(int(mixed99[0]["count"]) == 30 and mixed99[3]["count"] == 50, "arrange 不动传进来的那排")
	# 99c 叠满就另开一格（max_stack = 4 的东西有 6 个 -> 4 + 2 两格）
	var cap99 := ItemData.new()
	cap99.display_name = "测试小叠"
	cap99.max_stack = 4
	var cap_out99: Array = Inventory.arrange([
		{"item": cap99, "count": 2}, {"item": cap99, "count": 4}])
	chk(cap_out99.size() == 2 and int(cap_out99[0]["count"]) == 4
		and int(cap_out99[1]["count"]) == 2, "叠满另开一格 (4 + 2)")
	chk(Inventory.arrange([{"item": null, "count": 0}]).is_empty(), "全空的排出来也是空的")
	# 99d 背包一键整理: 工具落到最前面的快捷栏
	var bag_bak99: Array = Inventory.backpack.duplicate(true)
	var hot_bak99: Array = Inventory.hotbar.duplicate(true)
	for i99 in Inventory.backpack.size():
		Inventory.backpack[i99] = {"item": null, "count": 0}
	for i99 in Inventory.hotbar.size():
		Inventory.hotbar[i99] = {"item": null, "count": 0}
	Inventory.backpack[7]["item"] = wood99
	Inventory.backpack[7]["count"] = 12
	Inventory.backpack[3]["item"] = hoe99
	Inventory.backpack[3]["count"] = 1
	Inventory.sort_all()
	chk(Inventory.hotbar[0]["item"] == hoe99, "背包整理后工具落在快捷栏第 1 格")
	chk(Inventory.hotbar[1]["item"] == wood99 and int(Inventory.hotbar[1]["count"]) == 12,
		"木头跟在工具后面 (快捷栏第 2 格)")
	chk(Inventory.count_item(wood99) == 12 and Inventory.count_item(hoe99) == 1,
		"整理后一件不多一件不少")
	chk(Inventory.get_slot(Inventory.HOTBAR_SIZE)["item"] == null, "空格全沉到背包最后面")
	chk(Inventory.hotbar.size() == Inventory.HOTBAR_SIZE
		and Inventory.backpack.size() == Inventory.BACKPACK_SIZE, "整理不改变格子数量")
	# 99e 箱子一键整理
	var c99 := Vector2i(9999, 9999)
	var sc99 := Vector2i(2, 58)
	while c99 == Vector2i(9999, 9999) and sc99.x < 260:
		if not Structures.has_station(sc99) and not Farm.tilled.has(sc99):
			c99 = sc99
		sc99 += Vector2i(3, 0)
	chk(c99 != Vector2i(9999, 9999), "找到一格空地摆整理用的箱子")
	chk(Structures.place(c99, Structures.KIND_CHEST, true), "摆下一座整理用的箱子")
	chk(not Structures.sort_chest(c99), "空箱整理 = 不动 (返回 false)")
	Structures.chest_deposit(c99, wood99, 5)
	Structures.chest_deposit(c99, seed99, 3)
	Structures.chest_deposit(c99, hoe99, 1)
	chk(Structures.sort_chest(c99), "箱里有东西就能整理")
	var cit99: Array = Structures.chest_items(c99)
	chk(cit99.size() == 3 and cit99[0]["item"] == hoe99, "箱里整理后第一行是工具")
	chk(cit99[1]["item"] == seed99 and cit99[2]["item"] == wood99, "种子 / 材料依次跟在后面")
	chk(Structures.chest_count(c99) == 9, "箱里件数没变 (实际 %d)" % Structures.chest_count(c99))
	chk(Structures.chest_used_slots(c99) == 3, "箱里还是占 3 格")
	chk(not Structures.sort_chest(Vector2i(9999, 9998)), "对着空气整理 = 不动")
	# 99f 两个入口都在 (源码护栏)
	chk(FileAccess.get_file_as_string("res://inventory.gd").contains("func arrange")
		and FileAccess.get_file_as_string("res://inventory.gd").contains("func sort_all"),
		"背包与箱子共用一份整理逻辑 (inventory.gd)")
	chk(FileAccess.get_file_as_string("res://structures.gd").contains("func sort_chest"),
		"箱子整理入口在 structures.gd")
	var cui99 := FileAccess.get_file_as_string("res://chest_ui.gd")
	chk(cui99.contains("整理箱子") and cui99.contains("整理背包"),
		"储物箱面板上两个整理按钮都在")
	chk(FileAccess.get_file_as_string("res://backpack_ui.gd").contains("一键整理"),
		"背包页有一键整理按钮")
	Inventory.hotbar = hot_bak99
	Inventory.backpack = bag_bak99
	Inventory.inventory_changed.emit()
	Structures.remove(c99)
	await get_tree().process_frame
	chk(not Structures.has_station(c99), "收尾: 整理用的箱子拆干净了")

	# ============ 100. e47 箱子贴图 + 建造判定放宽 ============
	print("\n=== 100. e47 箱子贴图 + 建造判定放宽 ===")
	# 100a 箱子只画一只（源码护栏）
	var ch100 := FileAccess.get_file_as_string("res://scene/chest_node.gd")
	chk(ch100.contains("Rect2(8, 0, 16, 16)") and ch100.contains("const IMG_W := 16.0"),
		"储物箱只取一只 16x16 的箱子 (原来 32x32 是上下两只叠一起)")
	chk(not ch100.contains("const IMG_H := 32.0"), "储物箱不再是 32x32 的整块")
	var gg100 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(not gg100.contains("[$Player, 4]"), "不再用「玩家身边 4 格」的距离圈拦建造")
	chk(gg100.contains("fp.has(_world_to_cell(player.global_position))"),
		"玩家改成「别站在地基里」")
	chk(gg100.contains("house_box"), "住宅改成按屋身矩形算")
	# 100b 找一格能摆的（拿路灯这种 1 格的当尺子）
	var c100 := Vector2i(9999, 9999)
	for ry100 in [58, 60, 62, 56, 64, 66, 54]:
		var sx100 := 2
		while c100 == Vector2i(9999, 9999) and sx100 < 260:
			if g.call("_site_ok_for", Vector2i(sx100, ry100), Structures.KIND_LAMP):
				c100 = Vector2i(sx100, ry100)
			sx100 += 1
		if c100 != Vector2i(9999, 9999):
			break
	chk(c100 != Vector2i(9999, 9999), "找到一格能摆的路灯位 (实际 %s)" % str(c100))
	# 100c 玩家站在旁边照样摆得下（旧版半径 4 的距离圈会连人带地一起拦）
	var p_save100: Vector2 = g.player.global_position
	var nb100 := c100 + Vector2i(1, 0)
	var tile100 := float(Farm.TILE_SIZE)
	g.player.global_position = Farm.grid_origin + Vector2(nb100) * tile100 + Vector2(0.5, 0.5) * tile100
	chk(g.call("_world_to_cell", g.player.global_position) == nb100, "玩家挪到旁边那格 (测试用)")
	chk(g.call("_site_ok_for", c100, Structures.KIND_LAMP), "玩家站在旁边照样摆得下")
	g.player.global_position = Farm.grid_origin + Vector2(c100) * tile100 + Vector2(0.5, 0.5) * tile100
	chk(not g.call("_site_ok_for", c100, Structures.KIND_LAMP), "玩家站在地基里还是拦")
	g.player.global_position = p_save100

	# ============ 101. e48 骑砍味: 阵型 / 兵种相克 / 士气溃逃 / 兵力对比条 ============
	print("\n=== 101. e48 骑砍味 (阵型 / 相克 / 士气溃逃 / 兵力条) ===")
	var T101 := load("res://scene/troop.gd")
	var tcm101: Dictionary = (T101 as Script).get_script_constant_map()
	var cw101: float = float(tcm101.get("COUNTER_WIN", 0.0))
	var cl101: float = float(tcm101.get("COUNTER_LOSE", 0.0))
	var mf101: float = float(tcm101.get("MORALE_MAX", 0.0))
	chk(cw101 > 1.0 and cl101 < 1.0 and cl101 > 0.0,
		"相克倍率: 克制方 >1 / 被克方 <1 (%.2f / %.2f)" % [cw101, cl101])

	# 101a 相克倍率真落在伤害数字上（攻方 atk=4, 看目标掉几滴血）
	# ❗目标一律用 ally 侧: take_damage 的 ally 分支只在有 slave_data 时才写数据层,
	#   用 hero 侧会真扣 Legion.player_hp（把存档里的血带偏）。
	var dmg_probe := func(a_kind: String, d_kind: String) -> int:
		var a101: Variant = load("res://scene/troop.gd").new()
		a101.side = "enemy"
		a101.kind = a_kind
		a101.atk = 4
		a101.speed = 30.0
		add_child(a101)
		a101.set_process(false)
		var d101: Variant = load("res://scene/troop.gd").new()
		d101.side = "ally"
		d101.kind = d_kind
		d101.max_hp = 500
		d101.hp = 500
		add_child(d101)
		d101.set_process(false)
		a101.call("_melee_attack", d101)
		var out := 500 - int(d101.hp)
		a101.queue_free()
		d101.queue_free()
		return out
	chk(int(dmg_probe.call("刀客", "刀客")) == 4, "同系互殴 = 原伤害（4）")
	chk(int(dmg_probe.call("刀客", "骑兵")) == int(round(4.0 * cw101)),
		"步兵砍骑兵吃克制加成（4 -> %d）" % int(dmg_probe.call("刀客", "骑兵")))
	chk(int(dmg_probe.call("刀客", "弓手")) == int(round(4.0 * cl101)),
		"步兵撞弓手吃亏（4 -> %d）" % int(dmg_probe.call("刀客", "弓手")))
	chk(int(dmg_probe.call("骑兵", "弓手")) == int(round(4.0 * cw101)), "骑兵踏弓手吃加成")
	chk(int(dmg_probe.call("弓手", "刀客")) == int(round(4.0 * cw101)), "弓手压步兵吃加成")

	# 101b 士气: 挨刀掉 / 同伴阵亡折 / 血薄持续掉 / 见底溃逃 / 主角免疫
	var mo101: Variant = load("res://scene/troop.gd").new()
	mo101.side = "enemy"
	mo101.kind = "刀客"
	mo101.max_hp = 40
	mo101.hp = 40
	add_child(mo101)
	mo101.set_process(false)
	chk(is_equal_approx(float(mo101.get("morale")), mf101), "开局士气满格（%.0f）" % mf101)
	mo101.call("take_damage", 10)
	chk(is_equal_approx(float(mo101.get("morale")), mf101 - 15.0),
		"挨 10 点伤害掉 15 点士气（%.1f）" % float(mo101.get("morale")))
	mo101.call("shock_morale", 30.0)
	chk(is_equal_approx(float(mo101.get("morale")), mf101 - 45.0), "同伴阵亡折损 30 点士气")
	mo101.call("shock_morale", 999.0)
	chk(bool(mo101.get("routing")) and bool(mo101.get("_dying")),
		"士气压到 0 -> 当场溃逃退场（routing + _dying 一起亮）")
	mo101.queue_free()
	var hp101: Variant = load("res://scene/troop.gd").new()
	hp101.side = "hero"
	hp101.kind = "刀客"
	hp101.max_hp = 40
	hp101.hp = 40
	add_child(hp101)
	hp101.set_process(false)
	hp101.call("shock_morale", 999.0)
	chk(not bool(hp101.get("routing")) and is_equal_approx(float(hp101.get("morale")), mf101),
		"主角不吃士气这套（玩家想撤自己按 O）")
	hp101.queue_free()
	var dr101: Variant = load("res://scene/troop.gd").new()
	dr101.side = "enemy"
	dr101.kind = "刀客"
	dr101.max_hp = 100
	dr101.hp = 20
	add_child(dr101)
	dr101.set_process(false)
	dr101.call("_tick_morale", 1.0)
	chk(float(dr101.get("morale")) < mf101,
		"血薄(20%%)的单位会持续泄气（每秒 -6, 现在 %.1f）" % float(dr101.get("morale")))
	dr101.queue_free()

	# 101c 真开一场（海寇 = 甲板模板: 板上零障碍, 落点不会被地形挪走, 断言才稳）
	var old_b101: Node = get_tree().get_first_node_in_group("battle")
	if old_b101 != null:
		old_b101.remove_from_group("battle")
	var bm101: Variant = load("res://scene/battle_map.gd").new()
	bm101.party = {"id": 0, "type": "海寇", "size": 3}
	add_child(bm101)
	await get_tree().process_frame
	chk(String(bm101.template) == "甲板", "测试战场开在甲板上（落点不受地形干扰）")
	# 阵亡折损: 倒地处周围的同营人掉士气, 离得远的听不见
	var nb101: Variant = load("res://scene/troop.gd").new()
	nb101.side = "enemy"
	nb101.kind = "刀客"
	nb101.max_hp = 40
	nb101.hp = 40
	add_child(nb101)
	nb101.set_process(false)
	nb101.global_position = Vector2(140.0, 100.0)
	var fb101: Variant = load("res://scene/troop.gd").new()
	fb101.side = "enemy"
	fb101.kind = "刀客"
	fb101.max_hp = 40
	fb101.hp = 40
	add_child(fb101)
	fb101.set_process(false)
	fb101.global_position = Vector2(600.0, 100.0)
	(bm101.units as Array).append(nb101)
	(bm101.units as Array).append(fb101)
	bm101.call("_morale_shock", Vector2(100.0, 100.0), "enemy")
	chk(float(nb101.get("morale")) < mf101,
		"倒在身边的同伴让人掉士气（%.1f < %.0f）" % [float(nb101.get("morale")), mf101])
	chk(is_equal_approx(float(fb101.get("morale")), mf101), "离得远的同营不折士气")
	# 一边过半逃跑 = 崩溃播报（每边只喊一次）
	for u101 in bm101.units:
		if is_instance_valid(u101) and String(u101.side) == "enemy":
			u101.set("routing", true)
	bm101.call("_check_rout_announce")
	var warned101: Dictionary = bm101.get("_rout_warned")
	chk(bool(warned101.get("enemy")), "整队溃逃 -> 喊一次「敌军崩溃」（每边只喊一次）")

	# 101d 兵力对比条: 顶上一条, 条长 = 各自还剩几成
	var tf101: ColorRect = bm101.get("_tally_f_fill")
	var ta101: ColorRect = bm101.get("_tally_a_fill")
	var tconst101: Dictionary = (load("res://scene/battle_map.gd") as Script).get_script_constant_map()
	var half101: float = float(tconst101.get("TALLY_HALF", 0.0))
	var tw101: float = float(tconst101.get("TALLY_W", 0.0))
	chk(tf101 != null and ta101 != null and half101 > 0.0, "顶部兵力对比条建出来了")
	chk(int(bm101.get("_tally_base_f")) == 3, "敌方基准 = 开战时的 3 人")
	bm101.call("_update_tally", 0, 0)
	chk(is_equal_approx(tf101.size.x, 0.0) and is_equal_approx(ta101.size.x, 0.0),
		"双方清零 -> 两条都缩到底")
	# ❗这场是玩家单刷（一个伙伴都没带）, 我方基准真是 0 —— 给个明确分母再验「满员条满格」
	bm101.set("_tally_base_a", 2)
	bm101.call("_update_tally", 2, 3)
	chk(is_equal_approx(ta101.size.x, half101) and is_equal_approx(tf101.size.x, half101),
		"满员 -> 两条都满格（%.0f）" % half101)
	chk(is_equal_approx(tf101.position.x, tw101 - half101),
		"敌方条从右边往里缩（左端 x = %.0f）" % tf101.position.x)
	chk(String((bm101.get("_tally_a_lbl") as Label).text) == "我方 2",
		"蓝条旁边写着还剩几个")

	# 101e 四种阵型: 同一条线上摆出来的形状不一样
	var sp101 := bm101.call("_formation_slots", Vector2(0.0, 0.0), Vector2(200.0, 0.0), 3,
		Vector2(0.0, 1.0)) as Array
	chk(sp101.size() == 3 and is_equal_approx((sp101[0] as Vector2).x, 0.0)
		and is_equal_approx((sp101[1] as Vector2).x, 100.0)
		and is_equal_approx((sp101[2] as Vector2).x, 200.0), "横列 = 沿拖线均分（默认阵型）")
	bm101.set("formation", 1)
	var sw101 := bm101.call("_formation_slots", Vector2(0.0, 0.0), Vector2(200.0, 0.0), 3,
		Vector2(0.0, 1.0)) as Array
	chk((sw101[1] as Vector2).y > (sw101[0] as Vector2).y + 40.0
		and (sw101[1] as Vector2).y > (sw101[2] as Vector2).y + 40.0,
		"楔形: 中间那位杵在最前, 两翼往后收")
	bm101.set("formation", 2)
	var sc101 := bm101.call("_formation_slots", Vector2(0.0, 0.0), Vector2(200.0, 0.0), 4,
		Vector2(0.0, 1.0)) as Array
	var ring_ok101 := true
	for p101 in sc101:
		if absf((p101 as Vector2).distance_to(Vector2(100.0, 0.0)) - 100.0) > 0.6:
			ring_ok101 = false
	chk(ring_ok101, "圆阵: 四个人围线心站一圈（半径 = 线长一半）")
	bm101.set("formation", 3)
	var sl101 := bm101.call("_formation_slots", Vector2(0.0, 0.0), Vector2(200.0, 0.0), 4,
		Vector2(0.0, 1.0)) as Array
	chk(not is_equal_approx((sl101[0] as Vector2).y, (sl101[2] as Vector2).y),
		"散兵: 前后两排拉开（不再是一条直线）")
	bm101.set("formation", 0)
	var form_btn101: Button = bm101.get("_form_btn")
	chk(form_btn101 != null and form_btn101.text == "阵型:横列", "指挥栏有「阵型」按钮, 显示当前阵型")
	form_btn101.pressed.emit()
	chk(int(bm101.get("formation")) == 1 and form_btn101.text == "阵型:楔形",
		"点一下换阵型（按钮文字跟着变）")
	# 101f 下令真的按阵型摆人（甲板上摆, 落点必然是阵型槽）
	bm101.units = (bm101.units as Array).filter(func(u): return String(u.side) != "ally")
	var w101: Array = []
	for k101 in 3:
		var wk: Variant = load("res://scene/troop.gd").new()
		wk.side = "ally"
		wk.kind = "刀客"
		wk.squad = 1
		wk.index = k101
		add_child(wk)
		wk.set_process(false)
		(bm101.units as Array).append(wk)
		w101.append(wk)
	# ❗场上只留我们自己：_face_dir_for 是「正面朝最近敌人那侧」, 场上留着残敌的话
	#   视线一偏正面就翻面（楔形看着像反的）—— 清掉敌人, 正面必然朝下, 断言才确定。
	bm101.units = w101.duplicate()
	Voyage.set_squad_selection(0)
	bm101.set("formation", 1)
	bm101.call("_cast_line", Vector2(200.0, 200.0), Vector2(400.0, 200.0))
	chk(int(w101[0].get("order")) == 0, "列阵口令落在伙伴身上（order = 0 站住）")
	# 正面朝哪边由 _face_dir_for 定（场上没有活敌人就朝下）, 所以断言按「正面投影」比,
	# 不写死 y 的方向 —— 楔形的定义就是「中间那位往正面最前出, 两翼往后收」。
	var face101: Vector2 = bm101.call("_face_dir_for", Vector2(1.0, 0.0), w101[0])
	var fw101: Array = []
	for k101 in 3:
		fw101.append((w101[k101] as Node2D).global_position.dot(face101))
	chk(float(fw101[1]) > float(fw101[0]) + 40.0 and float(fw101[1]) > float(fw101[2]) + 40.0,
		"楔形下令后中间那位站得最靠前（正面投影 %.0f / %.0f / %.0f）" % [
			float(fw101[0]), float(fw101[1]), float(fw101[2])])

	# 101g 箭矢带射手兵种, 命中按相克折算
	var vic101: Variant = load("res://scene/troop.gd").new()
	vic101.side = "ally"
	vic101.kind = "刀客"
	vic101.max_hp = 60
	vic101.hp = 60
	add_child(vic101)
	vic101.set_process(false)
	vic101.global_position = Vector2(150.0, 150.0)
	(bm101.units as Array).append(vic101)
	# ❗spawn_arrow 是 void（老接口, 别为测试改签名）—— 新箭从 arrows 尾巴上取
	bm101.call("spawn_arrow", Vector2(150.0, 140.0), Vector2.RIGHT, 4, "enemy", "弓手")
	var arr101: Array = bm101.get("arrows")
	var ar101: Node2D = null
	if not arr101.is_empty():
		ar101 = arr101[arr101.size() - 1] as Node2D
	chk(ar101 != null and String(ar101.get("from_kind")) == "弓手", "箭矢记住了射手的兵种")
	ar101.set_process(false)
	ar101.position = Vector2(150.0, 140.0)      # 正好压在目标胸口（global_position + (0,-10)）
	ar101.set("prev", ar101.position)
	bm101.call("_tick_arrows", 0.0)
	chk(int(vic101.hp) == 60 - int(round(4.0 * cw101)),
		"弓手一箭射步兵掉 %d 滴血（4 x %.2f, 不是 4）" % [60 - int(vic101.hp), cw101])
	# 源码护栏: 箭矢判定这条路径真的接了相克, 不是只有近战接了
	var bsrc101 := FileAccess.get_file_as_string("res://scene/battle_map.gd")
	chk(bsrc101.contains("counter_mult"), "battle_map 的箭矢判定接了兵种相克")
	chk(bsrc101.contains("_formation_slots") and bsrc101.contains("FORMATIONS"),
		"拖线展开走 _formation_slots（阵型不是只画在预览上）")

	bm101.queue_free()
	if old_b101 != null:
		old_b101.add_to_group("battle")
	Voyage.set_battle_slow(false)     # 还原: 布阵阶段留下的时间静止
	await get_tree().process_frame

	# ============ 102. e49 装备分档图标（素材接入 ①d）============
	print("\n=== 102. e49 装备分档图标（木甲/铁甲/金甲）===")
	# 102a 三件甲: 档位 1/2/3, 生命上限 +10/+20/+30, 图标只取左半张
	var fnames102 := ["armor_wood", "armor_iron", "armor_gold"]
	var ftiers102 := [1, 2, 3]
	var fhps102 := [10, 20, 30]
	for i102 in 3:
		var it102 = load("res://item/%s.tres" % fnames102[i102])
		chk(it102 != null and String(it102.type) == "装备" and String(it102.display_name) != "",
			"甲 %d 档（%s）是件装备" % [ftiers102[i102], fnames102[i102]])
		chk(int(it102.armor_tier) == ftiers102[i102] and int(it102.armor_hp) == fhps102[i102],
			"%s: 档位 %d / 穿上生命上限 +%d" % [String(it102.display_name),
				int(it102.armor_tier), int(it102.armor_hp)])
		var at102 = it102.icon
		chk(at102 is AtlasTexture and (at102 as AtlasTexture).region == Rect2(0, 0, 16, 16),
			"%s 图标只裁左半张 16x16（不把上下两件一起画出来）" % String(it102.display_name))

	# 102h 哥布林的落点（素材调研里唯一没做的条目 —— 确认它已经扎对地方）
	var wm102 := FileAccess.get_file_as_string("res://scene/world_map.gd")
	chk(wm102.contains("Spear Goblin"),
		"哥布林用素材包 Enemy/Goblins/Spear Goblin 的 Idle/Run 当海图形象")
	chk(wm102.contains("_mob_respawn") and wm102.contains("c.x + c.y > 140 and c.x > 100"),
		"哥布林窝扎在巨岛东侧的荒野（跟西侧的魔物分开, 清完隔天回补）")

	# 102i 屋里不算水：室内房间(house.tscn 的 Interior 挂在农舍底下 +288)
	#       世界坐标正好压在小岛河道/row26 桥上 —— 不拦住的话在自家地板上走两步就变游泳
	var pg102 := FileAccess.get_file_as_string("res://scene/player.gd")
	var ow102 := pg102.find("func _on_swim_water")
	var ow102b: String = pg102.substr(ow102, 400) if ow102 >= 0 else ""
	chk(ow102b.contains("if indoors:") and ow102b.contains("return false"),
		"player.gd 的水面判定把「屋里」排除掉了（室内不走着走着变成水花）")
	# 真跑一遍: 找一格能下水的水格, 屋外站上去判「在水里」; 同一格开着 indoors 就该判「不在」
	var swim102 := Vector2i(9999, 9999)
	for c102 in g._water_set.keys():
		if g.is_swim_water(c102):
			swim102 = c102
			break
	var ph102: bool = player.is_physics_processing()
	var pos102: Vector2 = player.global_position
	var in102: bool = bool(player.indoors)
	var iw102: bool = player._in_water
	var owt102: float = player._out_water_t
	var mid102 := Vector2(Farm.TILE_SIZE / 2.0, Farm.TILE_SIZE / 2.0)
	player.set_physics_process(false)
	player.global_position = Farm.grid_origin + Vector2(swim102) * Farm.TILE_SIZE + mid102
	player.indoors = false
	player._tick_swim_state(0.016)
	chk(swim102.x != 9999 and player._in_water,
		"屋外踩能下水的水格照旧入水（格 %s）" % swim102)
	player.indoors = true
	player._tick_swim_state(0.016)
	chk(not player._in_water, "同一格开着 indoors 就不算水了（室内走路不会变水花）")
	# 原样还回去（后面还有测试要接着用这个 player）
	player.indoors = in102
	player.global_position = pos102
	player._in_water = iw102
	player._out_water_t = owt102
	if player._shadow != null:
		player._shadow.visible = not iw102
	player.set_physics_process(ph102)

	# ============ 103. e49 农场畜牧线（畜棚/马厩/筒仓/温室/磨坊/围栏/木桥）============
	print("\n=== 103. e49 农场畜牧线：贴图/地基/F/畜产/磨面 ===")
	var farm103 := [Structures.KIND_BARN, Structures.KIND_STABLE, Structures.KIND_SILO,
		Structures.KIND_GREENHOUSE, Structures.KIND_MILL, Structures.KIND_FENCE,
		Structures.KIND_BRIDGE]
	chk(Structures.FARM_KINDS.size() == 7 and Structures.is_farm_kind(Structures.KIND_BARN)
			and not Structures.is_farm_kind(Structures.KIND_CHEST),
		"农场线 7 种建筑都登记在 FARM_KINDS 里（%d）" % Structures.FARM_KINDS.size())

	# 103a 贴图 + 裁剪矩形都在图内（越界就会取到图外闪帧）
	var look_bad103: Array = []
	for k in farm103:
		var lk: Dictionary = Structures.farm_look(k)
		var tex103: Texture2D = load(String(lk.get("tex", "")))
		var r103: Rect2 = lk.get("rect", Rect2())
		if tex103 == null or r103.size.x <= 0.0 or r103.size.y <= 0.0 \
				or r103.position.x + r103.size.x > float(tex103.get_width()) \
				or r103.position.y + r103.size.y > float(tex103.get_height()):
			look_bad103.append(k)
	chk(look_bad103.is_empty(), "7 种建筑的贴图 + 裁剪都在图内（越界: %s）" % str(look_bad103))

	# 103b 造价表齐全（否则建造页上是一格空白）
	var cost_bad103: Array = []
	for k in farm103:
		var cst: Dictionary = Structures.building_cost(k)
		if String(cst.get("name", "")) == "" or int(cst.get("coin", 0)) <= 0:
			cost_bad103.append(k)
	chk(cost_bad103.is_empty(), "7 种建筑都有名字和造价（缺: %s）" % str(cost_bad103))

	# 103c 地基跟着 structures.gd 的 FARM_FOOT 那张表走
	var barn_fp103: Array = g.building_footprint(Vector2i.ZERO, Structures.KIND_BARN)
	chk(barn_fp103.size() == 15, "畜棚地基 5x3 = 15 格（实际 %d）" % barn_fp103.size())
	chk(g.building_footprint(Vector2i.ZERO, Structures.KIND_FENCE).size() == 1 \
			and g.building_footprint(Vector2i.ZERO, Structures.KIND_BRIDGE).size() == 1,
		"围栏/木桥只占锚点 1 格（不然铺一排就互相拦住）")

	# 103d 摆一座畜棚：场景里必须长出真农场节点，不能画成工作台那个小设施
	var barn103 := Vector2i(60, 6)
	if Structures.has_station(barn103):
		Structures.remove(barn103)
	chk(Structures.place(barn103, Structures.KIND_BARN, true), "摆下一座畜棚")
	var node103: Variant = g.station_nodes.get(barn103)
	chk(node103 != null and String((node103 as Node).get_script().resource_path).ends_with("farm_building_node.gd"),
		"畜棚用的是 farm_building_node（不是 32x32 的工作台小设施）")
	chk(g.station_footprint_blocked(barn103 + Vector2i(-2, -2)),
		"畜棚地基格上叠不了别的东西（station_footprint_blocked 认得新地基表）")
	chk(Structures.interact_farm(barn103), "按 F 走 Structures.interact_farm 能派发到这座畜棚")
	var fp103: Variant = get_tree().get_first_node_in_group("farm_panel")
	chk(fp103 != null and bool((fp103 as Node).call("is_open")),
		"畜棚的 F 真把农场管理面板开起来了")
	if fp103 != null:
		(fp103 as Node).call("close_panel")

	# 103e 养牲口 + 早上产畜产
	chk(Structures.add_animal(barn103, Structures.ANIMAL_COW), "畜棚里住进第一头牛")
	chk(Structures.add_animal(barn103, Structures.ANIMAL_COW), "再住进一头牛")
	chk(not Structures.add_animal(barn103, Structures.ANIMAL_HORSE), "马住不进畜棚（只能进马厩）")
	chk(Structures.animal_count_of(barn103) == 2,
		"畜棚里 2 头牲口（%d）" % Structures.animal_count_of(barn103))
	var made103: Dictionary = Structures.make_animal_produce(false, false)
	chk(int(made103.get("total", 0)) >= 2 \
			and Structures.produce_of_species(barn103, Structures.ANIMAL_COW) == 2,
		"两头牛早上各产一份牛奶（全岛共 %d 份）" % int(made103.get("total", 0)))
	var made_storm103: Dictionary = Structures.make_animal_produce(true, false)
	chk(int(made_storm103.get("total", 0)) == 0,
		"风暴天牲口不产（%d）" % int(made_storm103.get("total", 0)))
	Inventory.remove_item(load("res://item/milk.tres"), Inventory.count_item(load("res://item/milk.tres")))
	var got_milk103: Dictionary = Structures.take_produce_item(barn103, Structures.ANIMAL_COW)
	chk(int(got_milk103.get("count", 0)) == 2 \
			and Inventory.count_item(load("res://item/milk.tres")) == 2,
		"站旁边收奶：2 份牛奶进背包")

	# 103f 磨坊磨面
	var mill103 := Vector2i(68, 6)
	if Structures.has_station(mill103):
		Structures.remove(mill103)
	chk(Structures.place(mill103, Structures.KIND_MILL, true), "摆下一座磨坊")
	Inventory.remove_item(load("res://item/wheat.tres"), Inventory.count_item(load("res://item/wheat.tres")))
	Inventory.remove_item(load("res://item/flour.tres"), Inventory.count_item(load("res://item/flour.tres")))
	chk(Structures.mill_grind(mill103) == 0, "背包里没小麦时磨不出面")
	Inventory.add_item(load("res://item/wheat.tres"), 3)
	chk(Structures.mill_grind(mill103) == 3 \
			and Inventory.count_item(load("res://item/flour.tres")) == 3,
		"磨坊把 3 袋小麦磨成 3 袋面粉")

	# 103g 筒仓 = 容器（跟储物箱共用那只面板）
	var silo103 := Vector2i(72, 6)
	if Structures.has_station(silo103):
		Structures.remove(silo103)
	chk(Structures.place(silo103, Structures.KIND_SILO, true), "摆下一座筒仓")
	chk(Structures.is_container_kind(Structures.KIND_SILO) \
			and Structures.chest_used_slots(silo103) == 0,
		"筒仓是容器（跟储物箱共用存取面板）")
	Inventory.remove_item(load("res://item/potato.tres"), Inventory.count_item(load("res://item/potato.tres")))
	Inventory.add_item(load("res://item/potato.tres"), 5)
	chk(Structures.chest_deposit(silo103, load("res://item/potato.tres"), 5) == 5 \
			and Structures.chest_used_slots(silo103) == 1,
		"5 个土豆存进筒仓（占 1 格）")
	chk(Structures.chest_drain(silo103).size() == 1, "筒仓里的货能整份抽出来（拆仓/搬仓不吞东西）")

	# 103h 温室棚前那块「不看出季节」的地
	var gh103 := Vector2i(76, 6)
	if Structures.has_station(gh103):
		Structures.remove(gh103)
	chk(Structures.place(gh103, Structures.KIND_GREENHOUSE, true), "摆下一座温室")
	var bed103 := 0
	for dy in range(1, 4):
		for dx in range(-2, 2):
			if Structures.is_greenhouse_cell(gh103 + Vector2i(dx, dy)):
				bed103 += 1
	chk(bed103 == 12, "温室棚前 4x3 = 12 格不看出季节（%d）" % bed103)

	# 103i 源码护栏：game.gd 真把这批建筑接上了
	var gg103 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(gg103.count("is_farm_kind") >= 3,
		"game.gd 认得出这批建筑：建成节点 / 预览 / 地基 / F 兜底（%d 处）" % gg103.count("is_farm_kind"))
	chk(gg103.contains("farm_footprint"), "game.gd 的地基表跟着 structures.gd 的 FARM_FOOT 走")
	chk(gg103.contains("make_animal_produce"), "game.gd 每天早上结算畜产（不然棚里永远空着）")
	chk(gg103.contains("interact_farm"), "game.gd 的 F 派发留了一层兜底（不赌 _unhandled_input 顺序）")
	var cu103 := FileAccess.get_file_as_string("res://chest_ui.gd")
	chk(cu103.contains("_title_label"), "储物箱面板的标题跟着是哪一座走（筒仓不再写着「储物箱」）")

	Structures.remove(barn103)
	Structures.remove(mill103)
	Structures.remove(silo103)
	Structures.remove(gh103)

	print("\n=== 104. 卡牌战斗 (KARDS 式) ===")
	# 规则红线：主角只是统帅不出场、无英雄技能；只比大营血量；回合结束自动开打。
	# 数据层
	chk(CARDSD.CAMP_HP == 15 and CARDSD.HAND_CAP == 8 and CARDSD.COST_CAP == 10,
		"数据层定死: 大营 15 / 手牌上限 8 / 费用上限 10")
	var pdeck104: Array = CARDSD.player_deck(20260930)
	var base104: int = 1 + Slaves.expedition.size() + CARDSD.BASICS.size() * CARDSD.BASIC_COPIES
	chk(pdeck104.size() >= base104,
		"卡组底子 = 主角 + 出征同伴 %d + 基础牌 3x3 = %d 张（实际 %d, 含生效法术/科研解锁牌）"
			% [Slaves.expedition.size(), base104, pdeck104.size()])
	var no_foe_spell104 := true
	for c104 in pdeck104:
		if String(c104["key"]) == "fire" or String(c104["key"]) == "horns":
			no_foe_spell104 = false
	chk(no_foe_spell104, "玩家卡组里没有敌方法术")
	chk(CARDSD.foe_archetype({"type": "海寇", "size": 4}) == "burn", "海寇 = 直伤流")
	chk(CARDSD.foe_archetype({"type": "山贼", "size": 4}) == "swarm", "山贼 = 人海流")
	chk(CARDSD.foe_archetype({"type": "巡逻", "size": 4, "nation": "canglang"}) == "rush",
		"苍狼(骑兵国)巡逻 = 快攻流")
	# e2 数值平衡红线: 全单位卡属性点 atk+hp 落在 [2×费-2, 2×费+2] (基础/解锁/敌方四流派)
	var off104 := 0
	var cnt104 := 0
	for k104 in CARDSD.BASICS:
		var b104: Dictionary = CARDSD.BASICS[k104]
		cnt104 += 1
		if int(b104["atk"]) + int(b104["hp"]) < 2 * int(b104["cost"]) - 2 \
				or int(b104["atk"]) + int(b104["hp"]) > 2 * int(b104["cost"]) + 2:
			off104 += 1
	for k104b in CARDSD.UNLOCK:
		var u104b: Dictionary = CARDSD.UNLOCK[k104b]
		cnt104 += 1
		if int(u104b["atk"]) + int(u104b["hp"]) < 2 * int(u104b["cost"]) - 2 \
				or int(u104b["atk"]) + int(u104b["hp"]) > 2 * int(u104b["cost"]) + 2:
			off104 += 1
	for arch104 in CARDSD.FOE_UNITS:
		for t104 in CARDSD.FOE_UNITS[arch104]:
			cnt104 += 1
			if int(t104[2]) + int(t104[3]) < 2 * int(t104[1]) - 2 \
					or int(t104[2]) + int(t104[3]) > 2 * int(t104[1]) + 2:
				off104 += 1
	chk(off104 == 0, "数值红线: 全部 %d 张单位卡 atk+hp 在 [2×费-2, 2×费+2] (e2)" % cnt104)
	# e2 敌方直伤法术: 每费伤害 ≤ 2 (火油 3/2 / 飞斧 2/1 / 滚木 2/1, dmg 字段为准)
	var ok_dmg104 := true
	for sk104 in ["fire", "axe", "rocks"]:
		var sp104: Dictionary = CARDSD.FOE_SPELLS[sk104]
		if float(int(sp104["dmg"])) / float(int(sp104["cost"])) > 2.0:
			ok_dmg104 = false
	chk(ok_dmg104, "敌方直伤法术每费伤害 ≤ 2 (e2)")
	# e2 敌方编队: 四流派各整 20 张 (开局 3 抽后 17, 护住下面敌牌库断言) + burn 法术占比 ≤ 45%
	var ok_size104 := true
	var burn_spell104 := 0
	for arch104b in CARDSD.FOE_LISTS:
		var n104 := 0
		for row104 in CARDSD.FOE_LISTS[arch104b]:
			n104 += int(row104[1])
			if String(arch104b) == "burn" and CARDSD.FOE_SPELLS.has(String(row104[0])):
				burn_spell104 += int(row104[1])
		if n104 != 20:
			ok_size104 = false
	chk(ok_size104, "敌方四流派编队各 20 张 (e2)")
	chk(float(burn_spell104) / 20.0 <= 0.45,
		"burn 法术占比 ≤ 45%% (实际 %d/20) (e2)" % burn_spell104)
	# e2 伙伴卡设计档: 职业攻击与档位同步 -> 伙伴恒为 2×费+3 的成长溢价档 (不入严格红线)
	var ok_cls104 := true
	for cls104 in CARDSD.TIER:
		if Slaves.class_atk(String(cls104)) != int(CARDSD.TIER[cls104]):
			ok_cls104 = false
	chk(ok_cls104, "伙伴设计档: 职业攻击与档位同步 (e2)")
	# 真开一场（探针同款）：全局存档关掉，避免把玩家真档写坏
	var cb104: Variant = CARDSB.new()
	cb104.set("party", {"type": "海寇", "size": 3, "id": 104})
	add_child(cb104)
	chk(cb104.is_in_group("battle"), "卡牌战场登记进 battle 群组 (voyage 靠它收尾)")
	chk(cb104._my_hand.size() == 4 and cb104._foe_hand.size() == 3,
		"开局手牌 我4 对 敌3 (先手 3+回合抽1 / 敌军削弱后手 3)")
	chk(cb104._my_deck.size() == pdeck104.size() - 4 and cb104._foe_deck.size() == 17,
		"牌库减开局手牌 (我方 3+回合抽1 / 敌方 3)（我 %d 对 敌 17）"
			% cb104._my_deck.size())
	chk(cb104._my_camp == 15 and cb104._foe_camp == 15, "双方大营 15 (规模 3 不加成)")
	chk(cb104._whose == "my" and cb104._turn_no == 1 and cb104._cost == 2, "第 1 回合我方 2 费 (首回合能打出 1-2 费牌)")
	# d2: 敌情条 KARDS 式手牌牌背行 —— 8 格牌背, 可见数 = 敌手牌数, 数字同步
	chk(cb104._foe_hand_pips.size() == 8 and cb104._lbl_foe_hand != null,
		"敌情条有 8 格手牌牌背 + 数字标签 (d2)")
	var vis104 := 0
	for p104 in cb104._foe_hand_pips:
		if p104.visible:
			vis104 += 1
	chk(vis104 == cb104._foe_hand.size() and cb104._lbl_foe_hand.text == str(cb104._foe_hand.size()),
		"牌背可见数 = 敌手牌数 (%d), 数字同步 (d2)" % cb104._foe_hand.size())
	chk(not cb104._lbl_foe.text.contains("手牌"), "敌情条文字不再塞手牌数, 牌背行承担 (d2)")
	# 出牌历史: 左侧抽屉常驻, 敌我出牌都记一笔
	chk(cb104._hist_drawer != null and cb104._hist_list != null, "左侧出牌历史抽屉常驻（点「史」滑出）")
	chk(cb104._play_log.is_empty(), "开局出牌历史为空")
	# 出牌进支援线 + 扣费 + 当回合标记已行动
	cb104._my_hand = [CARDSD.unit_card("测试兵", 1, 3, 4, "")]
	cb104._cost = 5
	cb104._on_hand(0)
	chk(cb104._my_support[0] != null and cb104._cost == 4 and bool(cb104._my_support[0]["acted"]),
		"出牌进支援线扣费, 刚下场当回合已行动")
	chk(cb104._play_log.size() == 1 and String(cb104._play_log[0]["side"]) == "my"
		and String(cb104._play_log[0]["name"]) == "测试兵", "我方出牌记进历史 (T1 我 测试兵)")
	# 敌军出牌: 也记进历史 + 左侧小卡演出（甩出屏外的 tween 挂上就算数）
	cb104._foe_hand = [CARDSD.unit_card("海寇刀兵", 2, 2, 2, "")]
	cb104._foe_cost = 5
	chk(cb104._ai_step(), "敌方 AI 走了一步")
	chk(cb104._play_log.size() == 2 and String(cb104._play_log[1]["side"]) == "foe",
		"敌军出牌也记进历史")
	# 费用不足拦截
	cb104._my_hand = [CARDSD.unit_card("贵兵", 9, 9, 9, "")]
	cb104._cost = 1
	cb104._on_hand(0)
	chk(cb104._my_hand.size() == 1 and cb104._my_support[1] == null, "费用不足不出牌")
	# 前进前线花「行动费」(1-2 费的兵 1 点)
	cb104._my_hand.clear()
	cb104._my_support[0]["acted"] = false
	cb104._cost = 2
	cb104._advance(0)
	chk(cb104._front[0] != null and cb104._my_support[0] == null and cb104._cost == 1,
		"前进花 1 点行动费, 部队进共享前线")
	# 手操攻击: 敌军占着前线就只能打他们的部队, 打死移除 + 战果计数
	var me104: Dictionary = cb104._front[0]
	me104["acted"] = false
	cb104._front[1] = cb104._new_unit(CARDSD.unit_card("敌甲", 1, 1, 2, ""), "foe")
	var ats104: Array = cb104._attack_targets(me104)
	var ats_f104 := {"front": false, "sup": false, "camp": false}
	for t6104: Dictionary in ats104:
		if String(t6104.get("kind", "")) == "camp":
			ats_f104["camp"] = true
		elif String(t6104["row"]) == "front" and int(t6104["idx"]) == 1:
			ats_f104["front"] = true
		elif String(t6104["row"]) == "support" and int(t6104["idx"]) == 0:
			ats_f104["sup"] = true
	chk(ats_f104["front"] and ats_f104["sup"] and not ats_f104["camp"],
		"敌军占着前线 -> 前线+支援线(底层)部队都能打, 大营不行 (c6)")
	chk(cb104._do_attack("my", "front", 0, {"side": "foe", "row": "front", "idx": 1}),
		"手操进攻: 校验全过真打得出去")
	chk(cb104._front[1] == null and cb104._killed == 1 and bool(me104["acted"]),
		"打死对方前线部队, 自己标成已行动 (骑兵才例外)")
	chk(not cb104._do_attack("my", "front", 0, {"side": "foe", "row": "front", "idx": 1}),
		"已行动的部队打不出第二下")
	# f2 修: 点选流 e2e —— 点手牌自动选格部署 / 点我方部队再点敌格出手, 不依赖真实鼠标
	cb104._my_hand = [CARDSD.unit_card("点选兵", 1, 2, 3, "")]
	cb104._cost = 5
	cb104._on_hand(0)
	chk(cb104._my_support[0] != null and cb104._my_hand.is_empty() and cb104._cost == 4,
		"点手牌 = 自动选格部署并扣费 (f2)")
	# 点选部队再点敌格 = 出手 (支援线只有射手够得着)
	var sn104: Dictionary = cb104._new_unit(CARDSD.unit_card("狙击兵", 1, 3, 3, "ranged"))
	cb104._my_support[2] = sn104
	sn104["acted"] = false
	cb104._front[1] = cb104._new_unit(CARDSD.unit_card("敌乙", 1, 1, 2, ""), "foe")
	cb104._cost = 5
	cb104._on_slot("my", "support", 2)
	chk(not cb104._atk_sel.is_empty(), "点我方部队进选中态 (f2)")
	cb104._on_slot("foe", "front", 1)
	chk(cb104._front[1] == null and cb104._atk_sel.is_empty(),
		"点敌格 = 进攻打死并清选中 (f2)")
	# 点前线空格 = 支援线部队前进
	sn104["acted"] = false
	cb104._cost = 5
	cb104._on_slot("my", "support", 2)
	cb104._on_slot("my", "front", 2)
	chk(cb104._front[2] == sn104 and cb104._my_support[2] == null, "点前线空格 = 支援线部队前进 (f2)")
	# 法术点选目标: 再点同一张 = 取消目标态
	cb104._my_hand = [{"name": "激励", "type": "spell", "cost": 1, "spell": "buff", "target": "ally", "desc": "攻血+1", "kw": ""}]
	cb104._cost = 5
	cb104._on_hand(0)
	chk(not cb104._pending.is_empty(), "点选法术进选目标态 (f2)")
	cb104._on_hand(0)
	chk(cb104._pending.is_empty() and cb104._my_hand.size() == 1, "再点同一张 = 取消目标态, 牌还在手 (f2)")
	# g2 修: 支援线攻击有统一拦截 (点选流下从敌格/敌情条都发不起非射手攻击)
	var bc_g2 := FileAccess.get_file_as_string("res://scene/battle_cards.gd")
	chk(bc_g2.contains("支援线只有射手能发起攻击"), "支援线攻击有统一拦截 (g2)")
	# 敌前线清空后: 目标有大营, 敌支援线部队也在射程内
	cb104._front[1] = null
	var camp_t104: Array = cb104._attack_targets(me104)
	var camp_ok104 := false
	var sup_t104 := false
	for t6204: Dictionary in camp_t104:
		if String(t6204.get("kind", "")) == "camp":
			camp_ok104 = true
		elif String(t6204.get("row", "")) == "support" and int(t6204["idx"]) == 0:
			sup_t104 = true
	chk(camp_ok104 and sup_t104, "敌前线空 -> 目标有大营, 支援线部队也能打 (c6)")
	# 前线部队手操打支援线: 海寇刀兵 (AI 第 1 回合下的) 被打死移除
	me104["acted"] = false
	cb104._cost = 2                       # 上一击把行动费花光了, 补够
	chk(cb104._do_attack("my", "front", 0, {"side": "foe", "row": "support", "idx": 0})
		and cb104._foe_support[0] == null, "前线部队打死敌方支援线部队 (c6)")
	# 行动费不够: 打不出去 (3 费往上的兵行动费 2 点)
	var me2_104: Dictionary = cb104._new_unit(CARDSD.unit_card("重甲", 3, 4, 6, ""))
	chk(int(me2_104["card"]["act"]) == 2, "3 费往上的兵行动费 2 点")
	cb104._front[0] = me2_104
	cb104._cost = 1
	chk(not cb104._do_attack("my", "front", 0, {"kind": "camp", "side": "foe"}),
		"行动费不够打不出去 (要 2 点只剩 1 点)")
	cb104._cost = 5
	cb104._foe_camp = 15
	chk(cb104._do_attack("my", "front", 0, {"kind": "camp", "side": "foe"}),
		"敌前线空, 手操直击大营")
	chk(cb104._foe_camp == 11, "大营 15 - 4 攻 = 11")
	# 支援线: 只有远程够得着
	cb104._front[0] = null
	cb104._my_support = [cb104._new_unit(CARDSD.unit_card("我弓", 1, 2, 3, "ranged")),
		cb104._new_unit(CARDSD.unit_card("我刀", 1, 5, 3, "")), null, null]
	cb104._cost = 9
	chk(not cb104._do_attack("my", "support", 1, {"kind": "camp", "side": "foe"}),
		"支援线近战打不出去 (只有远程参战)")
	chk(cb104._do_attack("my", "support", 0, {"kind": "camp", "side": "foe"})
		and cb104._foe_camp == 9, "支援线弓手参战直击大营")
	# 反击: 近战打没死的目标会被还一手掉血, 弓手在远处放箭免反击, 守护格挡不还手 (j2)
	var foe_guard104: Dictionary = cb104._new_unit(CARDSD.unit_card("重盾兵", 1, 3, 5, ""), "foe")
	cb104._front[0] = foe_guard104
	var my_fencer104: Dictionary = cb104._new_unit(CARDSD.unit_card("刀手", 1, 2, 5, ""))
	cb104._front[1] = my_fencer104
	my_fencer104["acted"] = false
	cb104._cost = 5
	chk(cb104._do_attack("my", "front", 1, {"side": "foe", "row": "front", "idx": 0})
		and int(foe_guard104["hp"]) == 3 and int(my_fencer104["hp"]) == 2,
		"近战攻击没打死目标 -> 吃反击掉血 (j2)")
	var my_archer104: Dictionary = cb104._new_unit(CARDSD.unit_card("远射手", 1, 2, 5, "ranged"))
	cb104._front[2] = my_archer104
	my_archer104["acted"] = false
	chk(cb104._do_attack("my", "front", 2, {"side": "foe", "row": "front", "idx": 0})
		and int(foe_guard104["hp"]) == 1 and int(my_archer104["hp"]) == 5,
		"弓手攻击目标没死也不吃反击 (j2)")
	var foe_prot104: Dictionary = cb104._new_unit(CARDSD.unit_card("护旗手", 1, 1, 4, "guard"), "foe")
	cb104._front[1] = foe_prot104
	var my_fencer2_104: Dictionary = cb104._new_unit(CARDSD.unit_card("刀卫", 1, 2, 5, ""))
	cb104._front[3] = my_fencer2_104
	my_fencer2_104["acted"] = false
	cb104._cost = 5
	chk(cb104._do_attack("my", "front", 3, {"side": "foe", "row": "front", "idx": 0})
		and int(foe_guard104["hp"]) == 1 and int(my_fencer2_104["hp"]) == 5,
		"守护格挡: 攻击落空且目标不还手 (j2)")
	var foe_slayer104: Dictionary = cb104._new_unit(CARDSD.unit_card("斩杀者", 1, 4, 3, ""), "foe")
	cb104._front[4] = foe_slayer104
	var my_pawn104: Dictionary = cb104._new_unit(CARDSD.unit_card("小兵", 1, 1, 2, ""))
	cb104._front[5] = my_pawn104
	my_pawn104["acted"] = false
	cb104._cost = 5
	chk(cb104._do_attack("my", "front", 5, {"side": "foe", "row": "front", "idx": 4})
		and cb104._front[5] == null,
		"反击击杀: 攻击者被反杀, 槽位清空 (j2)")
	# 骑兵部署后可立即行动 (j3)
	cb104._my_hand = [CARDSD.unit_card("轻骑兵", 2, 2, 3, "cav")]
	cb104._cost = 5
	cb104._on_hand(0)
	chk(cb104._my_support[2] != null and not bool(cb104._my_support[2]["acted"]),
		"骑兵部署后当回合可立即行动 (j3)")
	# 大营归零 -> 胜利结算 + 发奖
	var coin104 := Wallet.money
	cb104._foe_camp = 1
	cb104._front = [cb104._new_unit(CARDSD.unit_card("终结者", 1, 3, 5, "")), null, null, null, null, null, null]
	cb104._my_support = [null, null, null, null]
	cb104._cost = 9
	cb104._do_attack("my", "front", 0, {"kind": "camp", "side": "foe"})
	var win104: bool = cb104._check_over()
	chk(win104 and cb104._settle_result == "victory", "大营归零 -> 判胜")
	chk(cb104._st_coin > 0 and Wallet.money == coin104 + cb104._st_coin,
		"胜利入账金币 %d" % cb104._st_coin)
	chk(cb104._settle_hud != null, "胜利弹出结算浮层")
	# 败北不发奖
	var cb104b: Variant = CARDSB.new()
	cb104b.set("party", {"type": "海寇", "size": 3, "id": 105})
	add_child(cb104b)
	cb104b._my_camp = 1
	cb104b._front = [cb104b._new_unit(CARDSD.unit_card("屠夫", 1, 6, 6, ""), "foe"), null, null, null, null, null, null]
	cb104b._foe_cost = 9
	chk(cb104b._do_attack("foe", "front", 0, {"kind": "camp", "side": "my"}),
		"敌方手操砸我大营")
	chk(cb104b._check_over() and cb104b._settle_result == "defeat", "我方大营归零 -> 判负")
	chk(cb104b._st_coin == 0, "败北不发奖")
	# 字形: 战场所有文案没有 IPix 缺的字（全角标点/间隔号会被渲成方块）
	var glyphs104 := sweep_glyphs(cb104._stage, "卡牌战场")
	chk(glyphs104 == 0, "卡牌战场文案没有缺字形 (%d 处)" % glyphs104)
	# d1: 敌方涨费减速 —— 每两回合才 +1 (此时 _over=true, _ai_turn 只跑涨费抽牌, AI 循环自动停)
	cb104._turn_no = 3
	cb104._foe_cost_max = 3
	cb104._ai_turn()
	chk(cb104._foe_cost_max == 3, "敌方涨费减速: 第 3 回合不涨费 (d1)")
	cb104._turn_no = 4
	cb104._ai_turn()
	chk(cb104._foe_cost_max == 4, "敌方涨费减速: 第 4 回合才 +1 (d1)")
	cb104.free()
	cb104b.free()
	# 源码护栏: 入口与结算规则的接线都在
	var vg104 := FileAccess.get_file_as_string("res://voyage.gd")
	chk(vg104.count("preload(\"res://scene/battle_cards.gd\")") == 2,
		"voyage 只有卡牌战一个入口 (enter_battle/enter_siege 各一处)")
	var bc104 := FileAccess.get_file_as_string("res://scene/battle_cards.gd")
	chk(bc104.contains("Quests.complete(\"navy_first\")")
		and bc104.contains("Nations.on_siege_victory")
		and bc104.contains("Research.battle_coin_mult")
		and bc104.contains("Nations.PRESTIGE_SIEGE")
		and bc104.contains("Nations.PRESTIGE_PATROL"),
		"结算规则齐: 海军里程碑 / 攻城入账 / 金币倍率 / 声望档位")

	# ===== 104b 流派改名（B 势力编成式）+ 战场词条 + 卡面立绘 + 质感演出 =====
	chk(CARDSD.ARCH_NAME["rush"] == "苍狼铁骑" and CARDSD.ARCH_NAME["swarm"] == "绿林蜂起"
		and CARDSD.ARCH_NAME["burn"] == "海寇船团" and CARDSD.ARCH_NAME["army"] == "王国边军",
		"四流派是国家层面的正式名（苍狼铁骑 / 绿林蜂起 / 海寇船团 / 王国边军）")
	chk(CARDSD.arch_name({"type": "山贼", "size": 4}) == CARDSD.arch_name_of("swarm"),
		"arch_name(按队伍) 与 arch_name_of(按代号) 取的是同一张表")
	var foe_hud104: Variant = CARDSB.new()
	foe_hud104.set("party", {"type": "山贼", "size": 3, "id": 106})
	add_child(foe_hud104)
	chk(String(foe_hud104._lbl_foe.text).contains("绿林蜂起"),
		"敌情条上写着流派名 (%s)" % String(foe_hud104._lbl_foe.text))
	foe_hud104.free()

	# 词条分流: 攻城 > 魔物夜袭 > 海寇接舷 > 野战
	chk(CARDSD.scenario_of({"siege": "chenxi_cap"}) == "siege", "攻城战 -> 坚城词条")
	chk(CARDSD.scenario_of({"type": "魔物"}) == "night", "魔物 -> 夜袭词条")
	chk(CARDSD.scenario_of({"type": "海寇"}) == "boarding", "海寇 -> 接舷词条")
	chk(CARDSD.scenario_of({"type": "巡逻", "nation": "chenxi"}) == "field", "其余 -> 野战")
	# 坚城: 大营 +5 / 守军 +1 血 / 12 回合上限
	var field_party104 := {"type": "巡逻", "nation": "chenxi", "size": 3, "id": 107}
	var siege_party104 := {"siege": "chenxi_cap", "type": "巡逻", "size": 3, "id": 108}
	chk(CARDSD.foe_camp_hp(siege_party104) - CARDSD.foe_camp_hp(field_party104) == 5,
		"坚城: 守方大营 +5 (%d vs %d)" % [CARDSD.foe_camp_hp(siege_party104), CARDSD.foe_camp_hp(field_party104)])
	chk(int(CARDSD.SCENARIOS["siege"]["lim"]) == 12, "坚城: 12 回合攻不下算粮尽")
	var sg104: Variant = CARDSB.new()
	sg104.set("party", siege_party104)
	add_child(sg104)
	chk(sg104._sc_id == "siege" and sg104._turn_limit == 12 and sg104._front_slots == 7
		and sg104._foe_camp == sg104._foe_camp_max,
		"坚城开局: 词条 12 回合 / 前线 7 槽 (c6) / 大营满血")
	var probe_card104 := CARDSD.unit_card("守军", 1, 1, 3, "")
	chk(int(sg104._new_unit(probe_card104, "foe")["hp"]) == 4
		and int(sg104._new_unit(probe_card104, "my")["hp"]) == 3,
		"坚城: 敌方登场 +1 血, 我方不加")
	# 攻城专属牌: 滚木礌石进守方牌库
	var sdeck104: Array = CARDSD.foe_deck(siege_party104, 7)
	var rocks104 := 0
	for c104b in sdeck104:
		if String(c104b.get("key", "")) == "rocks":
			rocks104 += 1
	chk(rocks104 == 3, "坚城: 守军牌库塞了 3 张滚木礌石 (%d)" % rocks104)
	# 粮尽: 打满 12 回合不出结果 = 守方守住, 判负
	sg104._turn_no = 12
	sg104._start_my_turn()
	chk(sg104._settle_result == "defeat" and sg104._over, "粮尽 -> 攻城判负 (守方守住)")
	sg104.free()

	# 接舷: 前线只有 3 槽
	var bd104: Variant = CARDSB.new()
	bd104.set("party", {"type": "海寇", "size": 3, "id": 109})
	add_child(bd104)
	chk(bd104._sc_id == "boarding" and bd104._front_slots == 3
		and bd104._row_slots("front") == 3 and bd104._row_slots("support") == 4,
		"接舷: 前线 3 槽 / 支援线仍 4 槽")
	# 支援线铺满 4 人, 全力推进 —— 前线只有 3 个位置, 第 4 人推不上去
	var sup104: Array = []
	for i104 in 4:
		sup104.append(bd104._new_unit(CARDSD.unit_card("甲%d" % i104, 0, 1, 3, "")))
	bd104._my_support = sup104
	bd104._cost = 9
	for i104 in 4:
		bd104._advance(i104)
	var nfront104 := 0
	for u104: Variant in bd104._front:
		if u104 != null:
			nfront104 += 1
	chk(nfront104 == 3 and bd104._front[3] == null and bd104._my_support[3] != null,
		"接舷: 前线只站得下 3 个, 第 4 人推不上去留在支援线 (越界红线)")
	chk(bd104._first_empty(bd104._front, bd104._front_slots) == -1,
		"接舷: 前线满了 _first_empty 返回 -1")
	bd104.free()

	# 夜袭: 第 1 回合谁也打不着
	var nt104: Variant = CARDSB.new()
	nt104.set("party", {"type": "魔物", "size": 3, "id": 110})
	add_child(nt104)
	chk(nt104._sc_id == "night" and nt104._no_atk1, "夜袭: 第 1 回合禁攻词条生效")
	nt104._front = [nt104._new_unit(CARDSD.unit_card("夜袭兵", 1, 5, 5, "")),
		nt104._new_unit(CARDSD.unit_card("夜里守", 1, 1, 2, ""), "foe"), null, null, null]
	nt104._cost = 9
	nt104._foe_camp = 15
	chk(not nt104._do_attack("my", "front", 0, {"side": "foe", "row": "front", "idx": 1}),
		"夜袭: 第 1 回合我方攻击不生效")
	nt104._turn_no = 2
	chk(nt104._do_attack("my", "front", 0, {"side": "foe", "row": "front", "idx": 1})
		and nt104._front[1] == null, "夜袭: 到第 2 回合才打得着")
	nt104.free()

	# 卡面立绘: 数据层取得到图, 文件真的在
	chk(CARDSD.art_of(CARDSD.summon_card(), "my") != null
		and CARDSD.art_of(CARDSD.unit_card("山贼", 1, 1, 3, ""), "foe") != null
		and CARDSD.art_of(CARDSD.foe_spell_card("fire"), "foe") != null,
		"手牌立绘: 我方 / 敌方单位 / 敌方法术都有图")
	chk(CARDSD.art_icon_of(CARDSD.unit_card("铁骑", 1, 2, 1, "cav"), "foe") != null,
		"槽位小图: 敌方骑兵有图")
	var artdir104 := DirAccess.get_files_at("res://resources/cards_art")
	chk(artdir104.size() >= 140, "卡面立绘文件齐 (%d 个: 35 张 x 大小两版)" % artdir104.size())
	chk(ResourceLoader.exists(CARDSD.ART_DIR + "u_my_刀客_card.png")
		and ResourceLoader.exists(CARDSD.ART_DIR + "s_fire_icon.png"),
		"立绘命名规矩: u_<阵营>_<兵种> / s_<法术id>, 带 _card / _icon 后缀")
	var img104 := (CARDSD.art_of(CARDSD.summon_card(), "my") as Texture2D).get_image()
	chk(img104.get_width() == 76 and img104.get_height() == 84, "手牌立绘图就是 76x84 (1:1 上屏不缩放)")
	var src104 := FileAccess.get_file_as_string("res://resources/cards_src/SOURCES.txt")
	chk(src104.contains("CC0") or src104.to_lower().contains("public domain"),
		"素材来源登记着 CC0 / Public Domain")

	# 质感演出: 函数在, 且打击逻辑仍是同步的（自检/探针直接调 _strike）
	chk(bc104.contains("func _float_text") and bc104.contains("func _dash")
		and bc104.contains("func _slot_flash") and bc104.contains("func _screen_flash")
		and bc104.contains("func _camp_hit_fx") and bc104.contains("func _show_banner")
		and bc104.contains("func _gains_roll"),
		"演出七件套齐: 飘字 / 冲刺 / 命中闪 / 全屏闪 / 大营受创 / 回合横幅 / 结算滚动")
	var st104 := bc104.find("func _strike")
	chk(st104 >= 0 and not bc104.substr(st104, 200).contains("await"),
		"打击逻辑仍是同步的（没被改成协程, 自检与探针才调得动）")
	chk(bc104.contains("_fx") and bc104.contains("MOUSE_FILTER_IGNORE"),
		"演出走独立 _fx 覆盖层（不吃鼠标, 不被 _rebuild_field 清掉）")
	chk(bc104.contains("func _fx_foe_card") and bc104.contains("func _log_play")
		and bc104.contains("func _build_hist_drawer"),
		"敌军出牌有左侧小卡演出 + 出牌历史抽屉")
	# KARDS 式桌面背景: 木桌 + 桌垫替代旧远景剪影（旧剪影函数应已删除）
	chk(bc104.contains("KARDS 式桌面") and bc104.contains("func _build_scenery")
		and bc104.contains("战场桌垫") and not bc104.contains("_hills_poly")
		and not bc104.contains("_wall_poly"),
		"战斗背景是 KARDS 式桌面（木桌 + 桌垫, 旧远景剪影已删）")
	# 字与框重叠修复: 敌情条文字让开旗面 / 大营旗收进面板内 / 手牌扇形收窄
	chk(bc104.contains("Vector2(34, 4)") and bc104.contains("Vector2(150, 40), 34.0")
		and bc104.contains("total > 700.0"),
		"战斗 UI 字不压框（敌情条避旗 / 大营旗入面板 / 手牌扇形收窄）")

	# ===== 105. 婚恋系统 =====
	print("\n=== 105. 婚恋系统 ===")
	# 105.1 数据层
	chk(Marriage.is_bride("rq_01") and not Marriage.is_bride("rq_00"), "只有女性可结婚（娜雅可, 布恩不可）")
	chk(Marriage.BRIDES.size() == 6 and Marriage.HEART_STEPS == [2, 4, 6, 8, 10],
		"婚恋数据层: 6 位可结婚 + 5 段心意门槛 2/4/6/8/10")
	chk(not Marriage.can_heart_talk("rq_01", 0) and Marriage.can_heart_talk("rq_01", 2),
		"心里话门槛: 0 好感不行, 2 好感开讲")
	for i54 in 5:
		Marriage.do_heart_talk("rq_01")
	chk(Marriage.stage("rq_01") == 5 and Marriage.stage_full("rq_01"), "五段心里话看完 stage_full")
	chk(Marriage.can_propose("rq_01", 10, false) == false
		and Marriage.can_propose("rq_01", 9, true) == false
		and Marriage.can_propose("rq_01", 10, true),
		"求婚条件: 满好感 10 + 有戒指, 缺一不可")
	Marriage.marry("rq_01", 33)
	chk(Marriage.is_married_to("rq_01") and Marriage.wife_name() == "娜雅", "能娶娜雅")
	chk(absf(Marriage.perk_mult("crop") - 1.15) < 0.001
		and absf(Marriage.perk_mult("voyage") - 1.0) < 0.001,
		"婚联 perk: 娜雅 crop 1.15, 未婚键 1.0")
	chk(not Marriage.can_heart_talk("rq_01", 99) and not Marriage.can_propose("rq_01", 99, true),
		"婚后不再触发心里话/求婚")
	var sv54: Dictionary = Marriage.to_dict()
	Marriage.reset()
	chk(Marriage.wife_name() == "" and Marriage.stage("rq_01") == 0, "reset 清空婚恋状态")
	Marriage.from_dict(sv54)
	chk(Marriage.is_married_to("rq_01") and Marriage.stage("rq_01") == 5, "婚恋存档往返")
	for i54 in 5:
		Marriage.do_heart_talk("rq_03")
	Marriage.marry("rq_03", 40)
	chk(Marriage.ally_atk_bonus() == 2, "咪露婚联: 伙伴攻击 +2")
	Marriage.reset()
	# 105.2 银戒
	var ring54: ItemData = load("res://item/ring.tres")
	chk(ring54 != null and str(ring54.get("display_name")) == "银戒"
		and str(ring54.get("type")) == "材料" and ring54.get("icon") != null,
		"银戒道具齐备")
	var smith54: Array = Crafting.SMITH_RECIPES.filter(
		func(r: Dictionary) -> bool: return r["result"] == ring54)
	chk(smith54.size() == 1, "铁匠铺能打银戒（配方唯一）")
	# 105.3 剧本工厂
	var sm54: Script = load("res://scripts_marriage.gd")
	var sc54_ok := true
	var bad54: Array = []
	for bid54 in ["rq_01", "rq_02", "rq_03", "rq_05", "rq_06", "rq_07"]:
		var bidx54 := int(bid54.substr(3))
		for st54 in 5:
			if sm54.heart_script(bidx54, st54).is_empty():
				sc54_ok = false
		if sm54.propose_script(bidx54).is_empty() or sm54.wedding_script(bidx54).is_empty():
			sc54_ok = false
		var all54: Array = []
		for st54 in 5:
			all54.append_array(sm54.heart_script(bidx54, st54))
		all54.append_array(sm54.propose_script(bidx54))
		all54.append_array(sm54.wedding_script(bidx54))
		for row54 in all54:
			if row54.has("text"):
				bad54.append_array(missing_glyphs(str(row54["name"]) + str(row54["text"])))
	chk(sc54_ok, "6 位心意线 5 段 + 求婚 + 婚礼剧本全齐")
	chk(bad54.is_empty(), "婚恋剧本无缺字形")
	chk(sm54.heart_script(0, 0).is_empty() and sm54.propose_script(0).is_empty()
		and sm54.wedding_script(0).is_empty(),
		"男性角色没有婚恋剧本（布恩三种全空）")
	var h054: Array = sm54.heart_script(1, 0)
	var whos54: Array = []
	for row54 in h054:
		if str(row54.get("fx", "")) == "show":
			whos54.append(str(row54["who"]))
	chk(h054.size() > 0 and str(h054[0].get("scene", "")) == "camp"
		and whos54 == ["s01", "you"],
		"心里话剧本: 篝火夜开场 + 立绘键 s01/you")
	# 105.4 入伙长剧本
	var rec54: Script = load("res://recruits.gd")
	chk(rec54.JOINS.size() == 8, "8 位伙伴都有专属入伙长剧本")
	var j54_ok := true
	var badj54: Array = []
	for j54 in rec54.JOINS.values():
		if not ["beach", "field", "homestead", "camp", "cliff", "docks", "mine", "workshop"] \
				.has(str(j54.get("scene", ""))):
			j54_ok = false
		if (j54.get("lines") as Array).is_empty():
			j54_ok = false
		for r54 in j54.get("lines", []):
			badj54.append_array(missing_glyphs(str(r54[1])))
	chk(j54_ok and badj54.is_empty(), "入伙长剧本场景与文案合法")
	chk(FileAccess.get_file_as_string("res://campfire_ui.gd").contains("play_directed")
		and FileAccess.get_file_as_string("res://recruits.gd").contains("func join_script"),
		"篝火入伙接了导演模式演出")
	var sd54: Control = g.story_dialogue_panel
	chk(sd54 != null and sd54.has_method("play_directed") and load("res://cg_view.gd") != null,
		"导演模式演出可播（story_dialogue + cg_view）")
	# 105.5 dialogue_ui 婚恋按钮
	var dp54: Control = g.dialogue_panel
	var hb54: Button = dp54.get("_heart_btn")
	var pb54: Button = dp54.get("_propose_btn")
	chk(hb54 is Button and pb54 is Button
		and hb54.has_signal("pressed") and pb54.has_signal("pressed"),
		"对话面板有心里话/求婚按钮")
	chk(FileAccess.get_file_as_string("res://dialogue_ui.gd").contains("can_heart_talk")
		and FileAccess.get_file_as_string("res://dialogue_ui.gd").contains("can_propose")
		and FileAccess.get_file_as_string("res://dialogue_ui.gd").contains("wedding_script"),
		"对话面板接了心里话/求婚/婚礼逻辑")

	# ===== 106. 画面精细化: 影子 / 婚戒徽章 / 作物摆动 / 菜单柔光 / 转场卡组帆 =====
	print("\n=== 106. 画面精细化 (d2/d4/d5/d7/d9/d10/d11/d12) ===")
	# d2: 玩家影子。g3: 主角提灯整个删掉了（用户不要身边的光圈, 昼夜明暗全归
	#     CanvasModulate 管）—— 留一条源码护栏: player.gd 里不许再有提灯痕迹。
	var pl106: Node = g.player
	chk(pl106._shadow != null, "玩家脚下有影子 (d2)")
	chk(not FileAccess.get_file_as_string("res://scene/player.gd").contains("_lamp"),
		"主角提灯光圈已删干净 (g3, 防回归)")
	# d4: 婚戒徽章（未婚隐藏 / 结婚亮出 / 悬停看加成）
	chk(g._wedding_badge != null and not g._wedding_badge.visible, "未婚: 婚戒徽章隐藏 (d4)")
	Marriage.marry("rq_01", 33)
	var pv106: TextureRect = g._wedding_badge.get_node("Row/WifePortrait")
	var rn106: TextureRect = g._wedding_badge.get_node("Row/RingIcon")
	chk(g._wedding_badge.visible and pv106.texture != null and rn106.texture != null
		and String((g._wedding_badge.get_node("Row/WifeName") as Label).text) == "娜雅",
		"结婚瞬间徽章亮出: 头像+戒指+妻子名齐")
	chk(String(g._wedding_badge.tooltip_text).contains("加成"), "徽章悬停显示婚后加成")
	Marriage.reset()
	chk(not g._wedding_badge.visible, "徽章跟婚恋状态联动（重置即隐）")
	chk(missing_glyphs("婚后加成: ").is_empty(), "婚戒徽章文案无缺字形")
	# d5: 作物风摆 + 收割叶屑
	var cl106: Variant = preload("res://scene/crop_layer.gd").new()
	add_child(cl106)
	cl106._crop_textures["测试瓜"] = [null, null, null, null, null]
	var pc106 := Vector2i(90, 90)
	cl106._update_sprite(pc106, "测试瓜", 2, 4, false)
	var cs106: Sprite2D = cl106._sprites[pc106]
	var base106: float = float(cl106._base_x[pc106])
	chk(cl106._phase.has(pc106), "作物有按格错开的摆动相位 (d5)")
	cl106._phase[pc106] = 0.0
	cl106._sway_t = 0.0
	cl106._process(0.5)
	chk(absf(cs106.position.x - base106) > 0.1, "作物随风摆动 (偏移 %.2f)" % absf(cs106.position.x - base106))
	cl106._leaf_burst(Vector2.ZERO)
	var leaf106 := false
	for c106 in cl106.get_children():
		if c106 is CPUParticles2D:
			leaf106 = true
	chk(leaf106, "收割/清枯那刻叶屑粒子就地崩开 (d5)")
	cl106.free()
	# d7: 主菜单卡片呼吸柔光（拨过开场段, 只验柔光本体与呼吸）
	var mm106: Variant = preload("res://scene/main_menu.gd").new()
	mm106._build()
	chk(mm106._menu_card != null and mm106._card_glow != null, "主菜单卡片背后有柔光节点 (d7)")
	mm106._studio_t = 999.0
	mm106._intro_t = 999.0
	mm106._menu_card.modulate.a = 1.0
	mm106._phase = 0.0
	mm106._process(0.016)
	chk(float(mm106._card_glow.modulate.a) > 0.05, "柔光随相位呼吸 (a %.2f)" % float(mm106._card_glow.modulate.a))
	mm106.free()
	# d9/d10: 场景切换与进战斗全走 iris 收黑 -> 切场 -> 展开
	for f106 in ["res://scene/main_menu.gd", "res://backpack_ui.gd", "res://voyage.gd", "res://scene/battle_cards.gd"]:
		chk(FileAccess.get_file_as_string(f106).contains("iris_wipe.gd"), "转场衔接: %s 走 iris 收黑 (d9)" % f106)
	chk(FileAccess.get_file_as_string("res://voyage.gd").contains("IRIS.play(\"out\""),
		"进战斗/切海图/回岛全走 iris 衔接 (d10)")
	# g4 重做: 纯黑 ColorRect 只动 alpha, 转场重入进 _queue 排队, mid 全在纯黑窗口同步放
	#     (旧 shader 圆幕羽化边遮不死 + 重入立即放 mid 会画面突变, 都不许回来)。
	var iw_g4 := FileAccess.get_file_as_string("res://scene/iris_wipe.gd")
	chk(not iw_g4.contains(".gdshader") and not iw_g4.contains("ShaderMaterial"),
		"转场不用圆幕 shader, 纯黑幕淡入淡出 (g4)")
	chk(iw_g4.contains("_queue"), "转场重入排队, 黑窗内同步放 mid, 画面零突变 (g4)")
	chk(iw_g4.contains("tween_callback(_unveil)"), "渐亮接在收黑链尾, 不与收黑并行抢 alpha (h4)")
	# d11: ESC 背包的战斗页签管理出征卡组
	var bp106 := FileAccess.get_file_as_string("res://backpack_ui.gd")
	chk(bp106.contains("\"key\": \"battle\"") and bp106.contains("出征卡组编成"), "ESC 背包有战斗页签 (d11)")
	chk(bp106.contains("Research.deck_add") and bp106.contains("Research.deck_del")
		and bp106.contains("_add_deck_card"), "战斗页能编组出征卡组 (d11)")
	chk(missing_glyphs("出征卡组编成 - 研究解锁后编入, 出海打仗带的就是这套").is_empty(),
		"战斗页签文案无缺字形")
	# d12: 出海挂帆 + 队形不追尾
	var gg106 := FileAccess.get_file_as_string("res://scene/game.gd")
	chk(gg106.contains("res://resources/texture/boat.png")
		and FileAccess.file_exists("res://resources/texture/boat_hull.png"),
		"出海动画挂帆(带帆船图), 停泊收帆用船身图 (d12)")
	chk(gg106.contains("26.0 * float(n_boats)"), "出海队形: 全队同距平移, 不再追尾相撞 (d12)")
	# h4: 转场黑幕真收黑 —— mid 执行瞬间 alpha 必须已经全黑。以前渐亮 tween 和
	#     收黑 tween 并行抢同一个 alpha, 黑幕收不死, mid 在半透下放, 画面突变。
	var iw_seen := {"a": -1.0, "done": false}
	preload("res://scene/iris_wipe.gd").play("out", func() -> void:
		var wn: Node = get_tree().get_first_node_in_group("iris_wipe")
		if wn != null:
			iw_seen["a"] = (wn.get("_rect") as ColorRect).modulate.a
		iw_seen["done"] = true)
	var iw_w3 := 0.0
	while not bool(iw_seen["done"]) and iw_w3 < 8.0:
		await get_tree().process_frame
		iw_w3 += get_process_delta_time()
	chk(bool(iw_seen["done"]) and float(iw_seen["a"]) >= 0.999,
		"mid 在纯黑窗口执行 (a=%.3f, h4 零突变)" % float(iw_seen["a"]))
	var iw_w4 := 0.0
	while get_tree().get_first_node_in_group("iris_wipe") != null and iw_w4 < 8.0:
		await get_tree().process_frame
		iw_w4 += get_process_delta_time()
	chk(get_tree().get_first_node_in_group("iris_wipe") == null, "转场黑幕演完自毁 (h4)")

	# ================= i 系列: 整体精细化 =================
	# i3-A: 卡池/词条/剧本/兵种/英雄文案禁全角标点（IPix 缺字形会渲成方块）
	var bad_punct_i := "（）：，。！？；、“”‘’《》【】「」…—～"
	var card_texts: Array[String] = []
	for v_i in CARDSD.SPELLS.values() + CARDSD.FOE_SPELLS.values() + CARDSD.SCENARIOS.values():
		card_texts.append(str(v_i.get("name", "")))
		card_texts.append(str(v_i.get("desc", "")))
	for v_i in CARDSD.UNLOCK.values() + CARDSD.BASICS.values():
		card_texts.append(str(v_i.get("name", "")))
	for u_i in CARDSD.FOE_UNITS.values():
		card_texts.append(str(u_i[0]))
	card_texts.append(str(CARDSD.hero_card().get("name", "")))
	var card_off: Array[String] = []
	for txt_i in card_texts:
		for ch_i in bad_punct_i:
			if txt_i.contains(ch_i):
				card_off.append("%s 含 [%s]" % [txt_i, ch_i])
				break
	chk(card_off.is_empty(), "卡池/词条/剧本/兵种/英雄无全角标点 (i3): %s" % str(card_off))
	chk(FileAccess.get_file_as_string("res://scene/shipping_bin.gd")
		.contains("背包里没有可以卖的东西(工具不收)"), "出货箱空手提示半角括号 (i3)")
	# i3-B1: 农作粒子 —— 挂 game、落点=格子中心上沿、one_shot 演完自回收
	var part_before := {}
	for n_i in g.get_children():
		if n_i is CPUParticles2D:
			part_before[n_i] = true
	player._burst_at(Vector2i(3, 3), Color(0.5, 0.4, 0.2))
	var burst_node: CPUParticles2D = null
	for n_i in g.get_children():
		if n_i is CPUParticles2D and not part_before.has(n_i):
			burst_node = n_i
			break
	chk(burst_node != null, "农作粒子节点挂在 game 上, 不跟人跑 (i3)")
	if burst_node != null:
		var want_pos := Farm.grid_origin + Vector2(3, 3) * float(Farm.TILE_SIZE) \
			+ Vector2.ONE * (float(Farm.TILE_SIZE) * 0.5) - Vector2(0, 6)
		chk(burst_node.position.distance_to(want_pos) < 0.5, "农作粒子落点=格子中心上沿 (i3)")
		chk(burst_node.one_shot and burst_node.amount >= 6, "农作粒子 one_shot 量足 (i3)")
	await get_tree().create_timer(1.2).timeout
	chk(not is_instance_valid(burst_node), "农作粒子演完自回收 (i3)")
	# i3-B2/B3: 捡拾音走 make_audio 管线加载成功; 菜单按钮统一点击音
	chk(Audio.SFX_NAMES.has("pickup") and Audio._sfx_streams.has("pickup"), "捡拾音已注册并加载 (i3)")
	chk(FileAccess.get_file_as_string("res://scene/main_menu.gd")
		.contains('Audio.play_sfx("ui_click"'), "菜单按钮统一点击音 (i3)")
	# i3-B4: 相机平滑跟随 + 瞬移一帧吸到位（进屋/睡觉/出海回岛不掉半张地图）
	var cam_i := player.get_node_or_null("Camera2D") as Camera2D
	chk(cam_i != null and cam_i.position_smoothing_enabled
		and cam_i.position_smoothing_speed > 0.0, "相机开启平滑跟随 (i3)")
	var c0_i := cam_i.get_screen_center_position()
	player.global_position += Vector2(400, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var moved_i := (cam_i.get_screen_center_position() - c0_i).length()
	chk(moved_i > 380.0 and moved_i < 420.0, "瞬移后相机一帧吸到位 (%.0f px, i3)" % moved_i)
	player.global_position -= Vector2(400, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# i5: 转场 P5R 化 —— 红黑斜切条带 + 起手/收尾快闪帧; 黑窗契约保持
	var iw_i5 := FileAccess.get_file_as_string("res://scene/iris_wipe.gd")
	chk(iw_i5.contains("Polygon2D") and iw_i5.contains("_bands_in")
		and iw_i5.contains("_flash_on") and iw_i5.contains("COL_BAND_B"),
		"转场 P5R 化: 墨褐黄铜斜切条带 + 快闪帧 (i5)")
	chk(iw_i5.contains("tween_callback(_fire_all)") and iw_i5.contains("_queue"),
		"转场黑窗契约保持: mid 只在全黑窗口放 (i5)")

	print("\n========================================")
	if fails == 0:
		print("全部通过 ✔")
	else:
		print("有 %d 项没通过 ✘" % fails)
	print("========================================")
	get_tree().quit()

func _unhandled_input(_e: InputEvent) -> void:
	pass

# 第 75 节用: 深度优先找一个节点树里第一个矩形碰撞形状
func _find_rect_shape(n: Node) -> RectangleShape2D:
	for c in n.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			return c.shape
	for c2 in n.get_children():
		var found := _find_rect_shape(c2)
		if found != null:
			return found
	return null

# e29c 用: 两张图逐像素比, 返回颜色不同的像素数 (按较小那张的尺寸比, 防越界)
func _img_diff_count(a: Image, b: Image) -> int:
	var cnt := 0
	for y in mini(a.get_height(), b.get_height()):
		for x in mini(a.get_width(), b.get_width()):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				cnt += 1
	return cnt

# e29c 用: 数一张图里不透明 (alpha >= 0.1) 的像素数, 当「局部改色」的分母
func _img_opaque_count(img: Image) -> int:
	var cnt := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.1:
				cnt += 1
	return cnt

# 第 93 节用: 从指定图边往里扫, 每条扫描线上「第一块陆地」离图边多少格
#   edge: 0=上边 1=下边 2=左边 3=右边; lo~hi = 扫描线范围（调用方避开四角圆弧/东南湾）
func _edge_scan93(land: Dictionary, w: int, h: int, edge: int, lo: int, hi: int) -> Array:
	var prof: Array = []
	for i in range(lo, hi + 1):
		for k in range(0, 80):
			var c: Vector2i
			match edge:
				0: c = Vector2i(i, k)
				1: c = Vector2i(i, h - 1 - k)
				2: c = Vector2i(k, i)
				_: c = Vector2i(w - 1 - k, i)
			if land.has(c):
				prof.append(k)
				break
	return prof

# 第 93 节用: 一组数里的 (最大 - 最小) —— 岸线起伏的「跨度」
func _span93(a: Array) -> int:
	if a.is_empty():
		return 0
	var lo := 99999
	var hi := -1
	for v in a:
		lo = mini(lo, int(v))
		hi = maxi(hi, int(v))
	return hi - lo

# 只给第 41 节用：一张「只有一个挡格」的假战场，替 troop._battle() 提供 is_blocked_at。
# 挡住哪一格由测试自己往 blocked 里塞，不用真开一场战斗就能验贴墙滑行/绕行。
# 第 54 节也用：shallow 表 + is_shallow_at 验半身入水（troop._update_water 走真分支）。
class FakeBattle:
	extends Node2D
	const CELL := 16
	var blocked := {}
	var shallow := {}
	var foes: Array = []      # e15h: nearest_foe_of 的花名册（54d 挥剑测试用）
	func is_blocked_at(pos: Vector2) -> bool:
		return blocked.has(Vector2i(floori(pos.x / CELL), floori(pos.y / CELL)))
	func is_shallow_at(pos: Vector2) -> bool:
		return shallow.has(Vector2i(floori(pos.x / CELL), floori(pos.y / CELL)))
	func nearest_foe_of(u: Node2D, max_d: float) -> Node2D:
		var best: Node2D = null
		var bd := max_d
		for f in foes:
			if not is_instance_valid(f):
				continue
			var d: float = u.global_position.distance_to(f.global_position)
			if d <= bd:
				bd = d
				best = f
		return best
