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

func _ready() -> void:
	# ghost 预览只有 game._make_ghost_for 里一句 new() + is_ghost = true, 不喂 kind ——
	# 所以自己回头问 game 在摆哪一样（建造模式的 build_kind / 搬房子的 _move_payload）。
	if kind == "":
		kind = _guess_kind()
	var look: Dictionary = Structures.farm_look(kind)
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

func _about() -> void:
	match kind:
		Structures.KIND_GREENHOUSE:
			_flash("棚前那 4x3 块地不看出季节, 过季也不枯")
		Structures.KIND_FENCE:
			_flash("一小段篱笆, 铺一排围出院子 (不挡路)")
		Structures.KIND_BRIDGE:
			_flash("一小块桥面, 铺一排过水沟")
		_:
			pass

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