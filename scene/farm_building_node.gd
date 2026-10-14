# scene/farm_building_node.gd —— e49 农场畜牧线的七座建筑/构件共用节点
# 畜棚/马厩/筒仓/温室/磨坊/围栏/木桥 全走这一个脚本：
#   · 贴图 + 裁剪矩形从 Structures.farm_look(kind) 拿（表跟造价表一起放在 structures.gd,
#     加新的一批房子只改那张表, 不用再抄一遍节点）；
#   · 原点在**建筑底部中间那一格**（父节点开了 y_sort, 排序点落在底边）；
#   · 畜棚/马厩额外挂一个 livestock_node 画出栏里的牲口。
# 按 F 干什么（见 activate）：
#   畜棚/马厩 -> 开农场管理面板（买卖牲口 / 收畜产 / 扩建）
#   筒仓     -> 开储物箱面板（game 早就建好 chest_panel 了, 复用它, 零额外接线）
#   磨坊     -> 把背包里的小麦全磨成面粉
#   温室/围栏/木桥 -> 只飘一句提示（它们管的是「地」和「路」, 没有面板）
#
# ❗为什么 F 在这里自己认领（_unhandled_input）而不是等 game 派发：
#   game._station_interact_cell 是硬编码 kind 的 match, 没有这批新 kind 的分支;
#   而 game.gd 不许改。所以这里用 _unhandled_input 自己接 —— 顺带两条保险:
#     a) 用 _unhandled_input 而不是 _input：面板开着时面板的 _input 会吃掉 F 并
#        set_input_as_handled, 整个 _unhandled_input 阶段都不跑, 不会出现「按 F 想关
#        面板, 关了又被这里立刻打开」;
#     b) Structures.interact_farm(c) 也留了一条按格派发的路（game 那边想接就一行）。
extends Node2D

var cell := Vector2i.ZERO
var kind := ""              # Structures.KIND_*
var is_ghost := false       # 建造模式的半透明预览：不建碰撞、不带提示

var _spr: Sprite2D = null
var _hint: Node2D = null
var _reach := Vector2(120, 56)
var _in_reach := false
var _w := 16.0
var _h := 16.0
var _livestock: Node2D = null
# 2026-10-06 夜景提升：夜间窗火 + 铺面招牌灯（不违和的发光点）
var _windows: Array = []
var _sign: Sprite2D = null      # 铺面招牌（木牌, 只有做买卖的几座有）
var _sign_lamp: Sprite2D = null # 招牌边上挑的那盏小灯（加法柔光, 不是真光源）
var _win_light: PointLight2D = null  # 窗灯：给整面墙铺暖的真灯（关阴影, 见 light_util.make_window_light）
var _lit := false               # 亮/灭只在 light_util.glow_hour_now() 一处判定
var _wind_t := -1.0             # e90 招牌风摆相位（<0 = 未初始化, 按格子错开）

func _ready() -> void:
	# ghost 预览只有 game._make_ghost_for 里一句 new() + is_ghost = true, 不喂 kind ——
	# 所以自己回头问 game 在摆哪一样（建造模式的 build_kind / 搬房子的 _move_payload）。
	if kind == "":
		kind = _guess_kind()
	# farm_look/bld_look: 农场畜牧线(畜棚/马厩/筒仓/温室/磨坊/围栏/木桥)
	# + 城镇功能建筑(军营/书院/市集/面包房/织造坊) 共用这一张外观表
	var look: Dictionary = Structures.bld_look(kind)
	if look.is_empty():
		look = Structures.farm_look(Structures.KIND_BARN)   # 兜底, 别画成一张空图
	var rect: Rect2 = look.get("rect", Rect2(0, 0, 16, 16))
	_w = rect.size.x
	_h = rect.size.y
	_spr = Sprite2D.new()
	_spr.centered = false
	_spr.position = Vector2(-_w / 2.0, -_h)
	var tex_path := String(look.get("tex", ""))
	if tex_path != "":
		# 第三方素材不入库(见 README), 缺失时留空不崩
		var fb_base := SoftRes.tex(tex_path)
		var at := AtlasTexture.new()
		at.atlas = fb_base      # 缺失时为 null, 建筑留空但碰撞照常
		at.region = rect
		_spr.texture = at
		if fb_base == null:
			push_warning("[素材] %s 贴图缺失, 已留空" % kind)
	add_child(_spr)

	if is_ghost:
		return                 # 预览只是张图：不挡路、不带提示、不带牲口

	add_to_group("farm_station")     # Structures.interact_farm 按这个组找节点
	# e33 脚下的影子（跟鸡舍/同伴小屋一个套路）
	add_child(preload("res://scene/shadow_util.gd").make_shadow(_w * 0.82, 14, 0.18))
	_build_windows()      # 2026-10-06: 外墙窗火（夜里点亮）
	_build_sign()         # 2026-10-06: 铺面招牌灯（只有市集/面包房/织造坊有）

	# 碰撞：贴底的矮矩形（最下面那一行），layer 4 只有玩家的 mask 里有。
	# ❗围栏/木桥**不建碰撞**：围栏是划地盘的装饰（跟木地板一样, 不该把自己卡住）,
	#   木桥必须能踩过去, 挡路就成了「架了桥反而过不去」。
	if kind != Structures.KIND_FENCE and kind != Structures.KIND_BRIDGE:
		var body := StaticBody2D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var sh := RectangleShape2D.new()
		sh.size = Vector2(maxf(16.0, _w - 6.0), 18)
		cs.shape = sh
		cs.position = Vector2(0, -9)
		body.add_child(cs)
		add_child(body)

	# 走近浮出「F xxx」提示：交互区和提示区是**同一个矩形** ——
	# 提示看得见就一定按得开 F（鸡舍那个「得绕到屋后按 F」的坑不重犯）。
	_reach = Vector2(maxf(120.0, _w + 28.0), 56.0)
	var reach := Area2D.new()
	reach.collision_layer = 0
	reach.collision_mask = 1        # 只探玩家（玩家在 layer 1）
	var rcs := CollisionShape2D.new()
	var rsh := RectangleShape2D.new()
	rsh.size = _reach
	rcs.shape = rsh
	rcs.position = Vector2(0, -12)
	reach.add_child(rcs)
	reach.body_entered.connect(_on_reach.bind(true))
	reach.body_exited.connect(_on_reach.bind(false))
	add_child(reach)

	_hint = preload("res://scene/key_hint.gd").new()
	# 提示文案写死成建筑名, 不做动态改字 —— key_hint.setup 不重置内部 _shown,
	# 在显示中改字会让提示再也不出来（见 key_hint.gd）。畜产数量在面板里报。
	_hint.setup("F", String(Structures.building_cost(kind).get("name", "农场")), -_h - 12.0)
	_hint.connect("clicked", _on_hint_clicked)   # 左键点这个框 = 按 F
	add_child(_hint)

	# 畜棚/马厩：栏里那群会走的牲口
	if kind == Structures.KIND_BARN or kind == Structures.KIND_STABLE:
		_livestock = preload("res://scene/livestock_node.gd").new()
		add_child(_livestock)
		_livestock.call("setup", cell, _w - 8.0)

# ghost 预览时回头问 game 在摆什么（Node.get 走属性名, 下划线开头照样读得到）
func _guess_kind() -> String:
	var g := get_tree().get_first_node_in_group("game")
	if g == null:
		return Structures.KIND_BARN
	var k := String(g.get("build_kind"))
	if k != "":
		return k
	var mp: Variant = g.get("_move_payload")
	if mp is Dictionary and (mp as Dictionary).has("kind"):
		return String((mp as Dictionary)["kind"])
	return Structures.KIND_BARN

func _on_reach(b: Node2D, on: bool) -> void:
	if not b.is_in_group("player") or _hint == null:
		return
	_in_reach = on
	if on:
		_hint.show_hint()
	else:
		_hint.hide_hint()

# 镐子/鼠标命中的矩形（世界坐标）：game.pick_station_cell 用
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-_w / 2.0, -_h - 2.0), Vector2(_w, _h + 4.0))

# 按 F 可交互的矩形（世界坐标）：game._try_station_interact 用它挑最近的一座
func interact_rect() -> Rect2:
	return Rect2(global_position + Vector2(0, -12) - _reach * 0.5, _reach)

# ---------------- F ----------------
func _unhandled_input(event: InputEvent) -> void:
	if is_ghost or not _in_reach:
		return
	if not event.is_action_pressed("interact"):
		return
	var panel := _live_panel()
	if panel != null and bool(panel.call("is_open")):
		return                     # 面板正开着: 这一下 F 归面板关它, 别关了又开
	activate()
	get_viewport().set_input_as_handled()

# 左键点了头上的「F xxx」框：功能跟按 F 完全一样（不绕 game, 少一根线）
func _on_hint_clicked() -> void:
	activate()

# 按 F / 点提示 / Structures.interact_farm 三条路都汇到这里
func activate() -> void:
	if is_ghost:
		return
	match kind:
		Structures.KIND_BARN, Structures.KIND_STABLE:
			_open_farm_panel()
		Structures.KIND_SILO:
			_open_chest_panel()
		Structures.KIND_MILL:
			_grind()
		Structures.KIND_BAKERY:
			_bake()
		Structures.KIND_WEAVER:
			_weave()
		_:
			_about()

# 畜棚/马厩的管理面板：面板节点由这里按需建（game 没为它留 _setup_* 那条线）
func _open_farm_panel() -> void:
	var p := _ensure_farm_panel()
	if p == null:
		return
	p.call("open", cell)

func _ensure_farm_panel() -> Node:
	var p := get_tree().get_first_node_in_group("farm_panel")
	if p != null:
		return p
	var g := get_tree().get_first_node_in_group("game")
	if g == null:
		return null
	var made := preload("res://scene/farm_panel.gd").new()
	made.name = "FarmPanel"
	# 跟 game 建鸡舍/箱子面板一样挂在 HUD(CanvasLayer) 下 —— Control 挂在
	# CanvasLayer 上不自己声明全屏的话会挤在左上角。
	var hud: Variant = g.get("hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).add_child(made)
	else:
		g.add_child(made)
	return made

# 筒仓复用一个储物箱面板（structures.gd 里筒仓也算容器, chest_items/chest_deposit 都认它）
func _open_chest_panel() -> void:
	var p := get_tree().get_first_node_in_group("chest_panel")
	if p == null:
		return
	p.call("open", cell)

func _grind() -> void:
	var n: int = Structures.mill_grind(cell)
	if n > 0:
		Audio.play_sfx("harvest", -6.0)
		_flash("磨了 %d 袋面粉" % n)
	else:
		_flash("背包里没有小麦, 磨不了")

# 面包房: 面粉 x2 -> 面包
func _bake() -> void:
	var n: int = Structures.bakery_bake(cell)
	if n > 0:
		Audio.play_sfx("harvest", -6.0)
		_flash("烤了 %d 个面包" % n)
	else:
		_flash("面粉不够 (2 袋面粉烤 1 个面包)")

# 织造坊: 羊毛 x3 -> 布
func _weave() -> void:
	var n: int = Structures.weaver_weave(cell)
	if n > 0:
		Audio.play_sfx("harvest", -6.0)
		_flash("织了 %d 匹布" % n)
	else:
		_flash("羊毛不够 (3 份羊毛织 1 匹布)")

func _about() -> void:
	match kind:
		Structures.KIND_GREENHOUSE:
			_flash("棚前那 4x3 块地不看出季节, 过季也不枯")
		Structures.KIND_FENCE:
			_flash("一小段篱笆, 铺一排围出院子 (不挡路)")
		Structures.KIND_BRIDGE:
			_flash("一小块桥面, 铺一排过水沟")
		Structures.KIND_BARRACKS:
			_flash("军营已立 - 研究解锁的部队牌现在能编进出征卡组了")
		Structures.KIND_ACADEMY:
			_flash("书院已立 - 研究解锁的法术牌现在能编进出征卡组了")
		Structures.KIND_MARKET:
			_flash("市集已立 - 售卖箱的海外贸易渠道开放了")
		_:
			pass

# ---------------- 2026-10-06 夜间窗火 ----------------
# 外墙上 2~3 扇小窗，天黑了点亮（加法柔光, 不建 PointLight2D —— 建筑多, 真灯会爆灯池。
# 后处理 bloom 会把这点亮放成一片暖晕, 所以「撒亮点」比「架真灯」划算得多）。
# 色温按用途分开（军营暖黄/书院冷白/市集招牌黄…）, 夜里一眼能认出哪栋是哪栋。
func _build_windows() -> void:
	if _w < 20.0 or _h < 20.0:
		return                            # 围栏/木桥这种小件不点窗
	var lu := preload("res://scene/light_util.gd")
	var base: Color = Structures.TOWN_GLOW.get(kind, Structures.WINDOW_GLOW_DEFAULT)
	var rng := RandomNumberGenerator.new()
	# ❗种子带上 cell：同一种建筑盖两座, 窗火的亮度/明灭位置也各不相同 ——
	#   只按 kind 定种会让两座军营长得一模一样（一排同款亮窗最显廉价）。
	rng.seed = absi(hash("%s:%s" % [kind, str(cell)]))
	var n := rng.randi_range(2, 3)
	for i in n:
		# window_tint 顺手决定这扇是亮是黑（约 1/5 黑着 = 屋里没人, 见 light_util）
		# scale 1.0：跟贴图自带的窗格差不多大 —— 光斑比窗户大一圈会变成"贴在墙上的橙色牌子",
		# 要的是"窗户里透着光"（2026-10-06 探针实测 1.7/3.5 都太大）。
		var g := lu.make_window_glow(lu.window_tint(base, rng), 1.0)
		var fx := lerpf(-_w * 0.26, _w * 0.26, float(i) / maxf(1.0, float(n - 1)))
		var fy := -_h * 0.52 - rng.randf_range(0.0, _h * 0.10)
		g.position = Vector2(fx, fy)
		g.visible = false
		add_child(g)
		_windows.append(g)
	# 窗灯（真灯）：窗火 sprite 只做出"窗格亮着"的形体, 真正把墙面/地面铺暖的是这盏。
	# ❗只给城镇建筑（做买卖/住人）—— 农场栏舍和畜棚不加, 免得夜里一座岛几十盏真灯。
	# 关掉阴影后它比路灯便宜得多（见 light_util.make_window_light）。
	if Structures.is_town_kind(kind) and not _windows.is_empty():
		var wc := Vector2.ZERO
		for w in _windows:
			wc += (w as Sprite2D).position
		wc /= float(_windows.size())
		_win_light = lu.make_window_light(base, 0.80, 1.9)
		_win_light.position = wc + Vector2(0.0, 8.0)   # 光心略往窗下压, 让窗台和门前都吃到光
		_win_light.enabled = false
		add_child(_win_light)

# 铺面招牌灯：市集/面包房/织造坊这类"做买卖的"在门脸上方挂一块木招牌,
# 招牌边挑一盏小灯。夜里一排铺子里谁是做生意的, 一眼认得出 ——
# 也是「暖橘渔村」暖点里最像"人烟"的那一批（窗是住家, 招牌是营生）。
# 只给加法柔光, 不建 PointLight2D（商铺多, 每家架真灯会把 8~12 盏的灯池撑爆）。
func _build_sign() -> void:
	match kind:
		Structures.KIND_MARKET, Structures.KIND_BAKERY, Structures.KIND_WEAVER:
			pass
		_:
			return
	var lu := preload("res://scene/light_util.gd")
	# 木牌挂在门脸右上方：杆子从牌顶往上接到屋檐, 所以 position.y 要往上抬一截。
	var anchor := Vector2(_w * 0.20, -_h + 4.0)
	_sign = Sprite2D.new()
	_sign.texture = _make_sign_tex()
	_sign.centered = false
	_sign.position = anchor
	add_child(_sign)
	# 招牌灯：牌子下方吊着的那点暖光（比窗火小, 但更"实"一点 —— 它有实体招牌托着）
	# 透明度留一档余量（0.70）：加法满不透明叠在浅色牌面上同样会过曝成白。
	var sc: Color = Structures.TOWN_GLOW.get(kind, Structures.WINDOW_GLOW_DEFAULT)
	_sign_lamp = lu.make_glow(Color(sc.r, sc.g, sc.b, 0.50), 0.85, 2.1)   # e90: HDR 后 0.70->0.50
	# 挂在招牌底下当子节点：招牌风摆（_process 里绕吊杆打摆）时灯跟着一起晃
	_sign_lamp.position = Vector2(7.0, 9.0)
	_sign_lamp.visible = false
	_sign.add_child(_sign_lamp)

# 一块小木招牌：横杆 + 吊牌 + 牌面描边（程序化画, 跟灯塔/码头同一套语言）
func _make_sign_tex() -> ImageTexture:
	var w := 20
	var h := 16
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood := Color8(78, 52, 32)
	var wood_l := Color8(110, 76, 46)
	var wood_d := Color8(52, 34, 21)
	var board := Color8(168, 120, 66)
	for y in h:
		img.set_pixel(0, y, wood)          # 吊杆（左端一根立柱, 从牌顶往下插进墙里）
		img.set_pixel(1, y, wood_l)
	for x in range(0, 14):                 # 横挑臂
		img.set_pixel(x, 2, wood)
		img.set_pixel(x, 3, wood_l)
	for y in range(4, 15):                 # 牌面
		for x in range(2, 15):
			img.set_pixel(x, y, board)
	for y in range(4, 15):                 # 牌面上下描边
		img.set_pixel(2, y, wood_d)
		img.set_pixel(14, y, wood_d)
	for x in range(2, 15):
		img.set_pixel(x, 4, wood_d)
		img.set_pixel(x, 14, wood_d)
	return ImageTexture.create_from_image(img)

# 跟着色调钟点/熄灯（窗火 + 招牌灯同一个总闸, 见 light_util.glow_hour_now）
func _sync_windows() -> void:
	if _windows.is_empty() and _sign_lamp == null:
		return
	var want := preload("res://scene/light_util.gd").glow_hour_now()
	if want == _lit:
		return
	_lit = want
	for g in _windows:
		(g as Sprite2D).visible = want
	if _win_light != null:
		_win_light.enabled = want
	if _sign_lamp != null:
		_sign_lamp.visible = want

func _process(_delta: float) -> void:
	if is_ghost:
		return
	_sync_windows()
	# e90 招牌风摆：吊牌绕吊杆顶点（贴图原点, centered=false 所以在左上角）轻轻打摆,
	# 相位按格子错开、风雨天摆得更凶 —— 跟树梢风摆同一套语言。招牌灯挂在牌下跟着一起晃。
	if _sign != null:
		if _wind_t < 0.0:
			_wind_t = float(absi(cell.x * 71 + cell.y * 137) % 628) * 0.01
		_wind_t += _delta
		var amp := 0.055
		if Weather.is_storm():
			amp = 0.13
		elif Weather.is_rain():
			amp = 0.09
		_sign.rotation = sin(_wind_t * 1.7) * amp

# ---------------- 小工具 ----------------
func _live_panel() -> Node:
	if kind == Structures.KIND_BARN or kind == Structures.KIND_STABLE:
		return get_tree().get_first_node_in_group("farm_panel")
	if kind == Structures.KIND_SILO:
		return get_tree().get_first_node_in_group("chest_panel")
	return null

# 借玩家头顶的飘字（面板/提示都这么提示, 见 coop_panel）。
# ❗player._flash 的第二个参数是**音效名**不是「种类」, 传错了会去 play 一个不存在的音。
func _flash(text: String, bad := false) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g == null:
		return
	var p: Variant = g.get("player")
	if p != null and (p as Node).has_method("_flash"):
		(p as Node).call("_flash", text, "error" if bad else "")

# 被镐子拆掉：小跳 + 淡出（材料/畜产返还由 game 那边办）
func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)