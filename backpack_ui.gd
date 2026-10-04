# backpack_ui.gd —— Esc（或 B）打开的「模块面板」
#
# 上方是一排**模块选择**：背包 / 角色 / 团队 / 科技 / 行政 / 地图 / 制作 / 建造 / 外交 / 设置，
# 点哪个下面就显示哪个。默认停在「背包」。
#
# 目前真正有内容的：
#   · 背包   —— 快捷栏 + 背包 30 格，点两格交换/合并
#   · 团队管理 —— 看伙伴人数、派了多少活（**招募已从这一页去掉**：傍晚野外的篝火边按 F）
#   · 地图   —— 按真实地形实时画出来的岛（滚轮放缩 / 拖拽移动 / 黄点是自己、蓝点是伙伴）
#   · 角色个人及技能、物品制作、设置 —— 先把入口和版式搭好，内容还在建
extends Control

signal opened
signal closed
signal page_changed(key: String)   # 切页时发（任务栏靠它知道什么时候该让位）

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const NPC_SCRIPT := preload("res://scene/slave_npc.gd")   # 取伙伴立绘用（跟篝火面板同一套）
const DIPLOMACY_PAGE := preload("res://diplomacy_ui.gd")  # 外交页：五国卡片（送礼/签约在这里办）
const CardsData := preload("res://scene/cards_data.gd")   # 行政页「出征编组」: 解锁牌表在这
const IRIS := preload("res://scene/iris_wipe.gd")         # d9: 回主页面的 iris 黑幕转场

# 模块表：key / 名字 / 下面那行灰字说明
const MODULES := [
	{"key": "bag",   "name": "背包",           "hint": "点击两格交换物品 / 右键盔甲穿戴或脱下  -  B / Esc 关闭"},
	{"key": "hero",  "name": "角色个人及技能", "hint": "属性 / 技能树"},
	{"key": "team",  "name": "团队管理",       "hint": "查看伙伴人数与今天的派活进度"},
	{"key": "battle", "name": "战斗",          "hint": "卡组编成 - 同伴/法术/部队选 12 张带出征, 点科技或行政可看详情"},
	{"key": "tech",  "name": "科技",           "hint": "派劳动力研究 - 给作物/木材/制作加增益"},
	{"key": "admin", "name": "行政",           "hint": "派劳动力研究 - 解锁政策卡并赚卡槽"},
	{"key": "map",   "name": "地图",           "hint": "滚轮放缩  /  按住左键或中键拖拽移动视角"},
	{"key": "craft", "name": "物品制作",       "hint": "消耗材料做食物 / 地板  -  点配方即可"},
	{"key": "build", "name": "建造",           "hint": "选建筑 -> 回地图摆放: 左键放置 / 右键取消"},
	{"key": "diplomacy", "name": "外交",       "hint": "五国关系 / 武备 / 送礼 / 签约"},
	{"key": "quests", "name": "任务",          "hint": "当前进行中的任务一览 (e13j 从屏幕左侧搬进来)"},
	{"key": "set",   "name": "设置",           "hint": "音乐 / 画面 / 返回主页面"},
]

var _visible := false
var _drag_from := -1            # 已选中要移动的格子（线性索引），-1 = 未选
var _grid: GridContainer
var _panels: Array = []         # 线性索引 -> PanelContainer
var _title: Label
var _hint: Label
var _box: PanelContainer = null  # 内容盒：科技/行政/团队页要撑大，切页时改它的 min 尺寸
# 大页面尺寸：这几页内容多（树图 / 卡片列表），把内容盒撑到接近全屏；其余页按内容收缩
const PAGE_SIZES := {
	"tech": Vector2(1080, 588),
	"admin": Vector2(1080, 610),
	"team": Vector2(1080, 620),
	"hero": Vector2(1080, 620),
	"battle": Vector2(1080, 600),
	"build": Vector2(760, 420),
	"diplomacy": Vector2(560, 560),
}
var _tab_btns := {}             # key -> Button
var _pages := {}                # key -> Control
var _current := "bag"
var _team_info: Label = null
var _team_list: VBoxContainer = null
var _slave_btns: Array = []
# e12: 团队页职业树（像科技树那样摆开, 点节点给最近打开详情的伙伴转职）
var _last_slave: int = -1          # 最近打开详情的伙伴序号（树的晋升对象）
var _combat_tree: ClassTreeView = null
var _labor_tree: ClassTreeView = null
var _tree_target: Label = null     # 树顶的晋升对象提示行
var _hero_info: Label = null
# 伙伴详情弹窗（覆盖在团队页上方）
var _detail_panel: PanelContainer = null
var _detail_index: int = -1
var _detail_name_label: Label = null
var _detail_info_label: Label = null
var _detail_rename: LineEdit = null
var _detail_rename_btn: Button = null
var _detail_feed_btn: Button = null
var _detail_gift_btn: Button = null
var _detail_back_btn: Button = null
var _detail_class_benefit: Label = null       # e24: 当前战斗收益行
var _detail_labor_benefit: Label = null       # e24: 当前劳动收益行
var _portrait_cache := {}        # 伙伴序号 -> idle 立绘 Texture2D（取不到帧存 null）
var _map_page: Control = null
var _bgm_on := true
var _skill_tree: SkillTreeView = null   # e20: 技能树状图（替代旧的三行卡片）
var _hero_linked := false        # Legion.stats_changed 只连一次
# 设置页不再列存档快照（读档入口统一收在开始界面）。
# 科技 / 行政页
var _tech_info: Label = null
var _admin_info: Label = null
var _tech_rows := {}             # 科技id -> {panel}（树里的节点卡）
var _admin_rows := {}            # 行政id -> {panel}
var _tech_tree: ResearchTreeView = null   # 文明6 式树图
var _admin_tree: ResearchTreeView = null
var _slot_box: GridContainer = null
var _slot_labels: Array = []     # 生效槽面板（PanelContainer: 图标+文字）
var _pending_box: GridContainer = null
var _pending_labels: Array = []  # 准备槽面板（挂上还没生效，下周一早上上任）
var _card_rows := {}             # 卡id -> {panel, name, desc, btn}
var _research_linked := false    # Research.changed 只连一次
var _btl_info: Label = null      # 战斗页顶部信息行
var _btl_rows := {}              # 战斗页卡池行（p_同伴 / m_法术 / u_部队 三段共用）
var _btl_partner_grid: GridContainer = null  # 同伴卡网格（新招募伙伴要动态补建行）
var _btl_side: Label = null      # 战斗页右栏卡组明细
# 科技/行政详情弹窗（点树上的条目弹出, 展示效果明细 + 随研究解锁的法术卡）
var _rsch_wrap: CenterContainer = null
var _rsch_panel: PanelContainer = null
var _rsch_box: VBoxContainer = null
var _rsch_btn: Button = null
var _rsch_id := ""
var _rsch_tree := "tech"
# 团队页
var _team_stats := []            # 统计卡上的数字 Label（顺序：人数/可派/已派/已干完）

func _ready() -> void:
	# 见 shop_ui.gd 的注释：挂在 HUD(CanvasLayer) 下的 Control 默认是 0 尺寸，
	# 不自己声明全屏的话遮罩和居中都会失效（面板会挤在左上角）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panel()
	Inventory.inventory_changed.connect(_refresh)
	Inventory.inventory_changed.connect(_refresh_craft)

# ---------------- 搭界面 ----------------
func _build_panel() -> void:
	# 全屏遮罩
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	center.add_child(outer)

	# ---------- 上方：模块选择 ----------
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(tabs)
	for m in MODULES:
		var b := Button.new()
		b.text = m["name"]
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_override("font", PIXEL_FONT)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_select_module.bind(m["key"]))
		tabs.add_child(b)
		_tab_btns[m["key"]] = b

	# ---------- 下面：内容盒 ----------
	var box := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.12, 0.10, 0.09, 0.96)
	box_style.border_color = Color(0.55, 0.42, 0.28)
	box_style.set_border_width_all(3)
	box_style.set_corner_radius_all(6)
	box_style.content_margin_left = 20
	box_style.content_margin_right = 20
	box_style.content_margin_top = 14
	box_style.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", box_style)
	outer.add_child(box)
	_box = box

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	box.add_child(vbox)

	_title = _mk_label("", 22, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title)
	_hint = _mk_label("", 12, Color(0.8, 0.75, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_hint)

	for m in MODULES:
		var page := _build_page(str(m["key"]))
		page.visible = (m["key"] == _current)
		vbox.add_child(page)
		_pages[m["key"]] = page

	_switch_to(_current)

# 每个模块一页；现在只做「背包 / 团队管理 / 地图 / 物品制作」四页有内容
func _build_page(key: String) -> Control:
	match key:
		"bag":
			return _build_bag_page()
		"team":
			return _build_team_page()
		"battle":
			return _build_battle_page()
		"map":
			return _build_map_page()
		"craft":
			return _build_craft_page()
		"build":
			return _build_build_page()
		"hero":
			return _build_hero_page()
		"tech":
			return _build_tech_page()
		"admin":
			return _build_admin_page()
		"diplomacy":
			return _build_diplomacy_page()
		"quests":
			# e13j: 任务栏从屏幕左侧竖栏搬进背包, 变成普通一页
			var q: Control = preload("res://quest_log.gd").new()
			q.set("embedded", true)
			return q
		"set":
			return _build_settings_page()
	return _build_placeholder("这一块还在建 -- 先把入口留在这儿")

# ---------------- 背包页 ----------------
func _build_bag_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)

	_grid = GridContainer.new()
	_grid.columns = Inventory.BACKPACK_COLS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	wrap.add_child(_grid)

	var total := Inventory.HOTBAR_SIZE + Inventory.BACKPACK_SIZE
	for i in total:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(44, 44)
		panel.add_theme_stylebox_override("panel", _slot_style(i < Inventory.HOTBAR_SIZE))
		panel.set_meta("index", i)
		panel.gui_input.connect(_on_slot_input.bind(i))

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var label := Label.new()
		label.add_theme_font_override("font", PIXEL_FONT)
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var vb := VBoxContainer.new()
		vb.add_child(icon)
		vb.add_child(label)
		panel.add_child(vb)
		panel.set_meta("icon", icon)
		panel.set_meta("label", label)
		_grid.add_child(panel)
		_panels.append(panel)

	# e46 一键整理：快捷栏 + 背包 30 格整体重排（同种并叠, 工具排最前, 空格沉底）
	var sort_btn := Button.new()
	sort_btn.text = "一键整理 (工具排最前)"
	sort_btn.custom_minimum_size = Vector2(0, 30)
	sort_btn.add_theme_font_override("font", PIXEL_FONT)
	sort_btn.add_theme_font_size_override("font_size", 13)
	sort_btn.pressed.connect(_on_sort_bag)
	wrap.add_child(sort_btn)
	return wrap

# ---------------- 角色个人及技能页 ----------------
func _build_hero_page() -> Control:
	# e24: 整页套滚动兜底 —— 属性区+树+说明的高度随窗口涨落, 不再顶出面板底边
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_info = _mk_label("", 13, Color(0.9, 0.86, 0.76), HORIZONTAL_ALIGNMENT_LEFT)
	wrap.add_child(_hero_info)
	wrap.add_child(_mk_label("技能树 -- 五条主干各 10 级, 5 级时分岔二选一, 点下一个亮格升级 (打仗/收成/钓鱼/买卖/建成都长经验)",
		13, Color(0.95, 0.82, 0.5)))
	# e20: 技能树改成跟科技一样的树状图（tier 分列 + 连线 + 分支可视化）
	var tree_holder := CenterContainer.new()
	_skill_tree = SkillTreeView.new()
	# e24: 树实际只画到 x~728(LEFT_X+9列*GAP_X+NODE_W), 之前拍脑袋写 1040 宽
	# 直接顶出面板右边界 —— 「个人框显示超过边界」就是它。
	# 高度也别拍脑袋：5 行 x ROW_H(100) + 顶上 22 + 分叉下探 24+节点 22 + 行底小字 ~12
	# = 508。之前写 424 比 _draw 的实际内容矮了 80px，最后一行(体魄)被自己的矩形裁掉，
	# ScrollContainer 还以为没内容可滚 —— 树高必须跟画布一样诚实。
	_skill_tree.custom_minimum_size = Vector2(760, 508)
	_skill_tree.node_clicked.connect(_on_skill_node)
	tree_holder.add_child(_skill_tree)
	wrap.add_child(tree_holder)
	wrap.add_child(_mk_label("金=已点  绿=下一个可点  灰=未解锁;  每行下方小字 = 这条树每级的收益",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	if not _hero_linked:
		Legion.stats_changed.connect(_refresh_hero)
		_hero_linked = true
	_refresh_hero()
	scroll.add_child(wrap)
	return scroll

# e20: 技能树节点点击 —— which="" 主干升级 / "a"/"b" 选分支
func _on_skill_node(id: String, which: String) -> void:
	if which == "":
		if Legion.upgrade_skill(id):
			Audio.play_sfx("coin", -6.0)
		else:
			Audio.play_sfx("error", -6.0)
	else:
		if Legion.choose_branch(id, which):
			Audio.play_sfx("coin", -6.0)
		else:
			Audio.play_sfx("error", -6.0)
	_refresh_hero()

# ---------------- 科技页 ----------------
# 文明6 式树图：tier 分列、前置连线、节点卡片可点。
# ❗「研究劳动力」块已挪到夜晚派活面板（assign_ui），这里整幅宽都给树。
func _build_tech_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	_tech_info = _mk_label("", 13, Color(0.9, 0.86, 0.76))
	wrap.add_child(_tech_info)
	wrap.add_child(_legend_row([
		["已研究", Color(0.95, 0.82, 0.4)],
		["可研究", Color(0.55, 0.9, 0.45)],
		["点数未满", Color(0.85, 0.78, 0.6)],
		["前置未开", Color(0.45, 0.4, 0.35)],
	]))

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	wrap.add_child(main)

	# 左：树图（放进滚动盒，将来科技多了超宽/超高也能拖）
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(700, 424)
	main.add_child(scroll)
	_tech_tree = ResearchTreeView.new()
	_tech_tree.setup("tech", _on_research_pressed)
	scroll.add_child(_tech_tree)

	_tech_rows.clear()
	for id in Research.TECHS.keys():
		_tech_rows[String(id)] = {"panel": _tech_tree.card_of(String(id))}
	if not _research_linked:
		Research.changed.connect(_on_research_changed)
		_research_linked = true
	_refresh_tech()
	return wrap

# ---------------- 行政页 ----------------
# 上：树图 + 右侧栏（卡槽 + 劳动力）；下：政策卡牌桌（3 列卡片墙）。
func _build_admin_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	_admin_info = _mk_label("", 13, Color(0.9, 0.86, 0.76))
	wrap.add_child(_admin_info)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	wrap.add_child(main)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(700, 240)
	main.add_child(scroll)
	_admin_tree = ResearchTreeView.new()
	_admin_tree.setup("admin", _on_research_pressed)
	scroll.add_child(_admin_tree)
	_admin_rows.clear()
	for id in Research.ADMINS.keys():
		_admin_rows[String(id)] = {"panel": _admin_tree.card_of(String(id))}

	# 右侧栏：政策卡槽（挂卡才生效，两列排不然 6 个槽会撑爆侧栏）
	var side := _build_research_sidebar("政策卡槽 -- 挂上才生效")
	var side_v: VBoxContainer = side.get_child(0)
	side_v.add_child(_mk_label(" ", 2, Color(1, 1, 1)))          # 标题和卡槽之间隔一口气
	_slot_box = GridContainer.new()
	_slot_box.columns = 2
	_slot_box.add_theme_constant_override("h_separation", 5)
	_slot_box.add_theme_constant_override("v_separation", 4)
	side_v.add_child(_slot_box)
	side_v.add_child(_mk_label("准备槽 -- 为下一周的政策作准备", 11, Color(0.72, 0.78, 0.6)))
	_pending_box = GridContainer.new()
	_pending_box.columns = 2
	_pending_box.add_theme_constant_override("h_separation", 5)
	_pending_box.add_theme_constant_override("v_separation", 4)
	side_v.add_child(_pending_box)
	main.add_child(side)

	# 下：政策卡牌桌 + 出征编组（两块卡片墙都放进滚动区, 不然要顶破面板）
	var lower_scroll := ScrollContainer.new()
	lower_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower_scroll.custom_minimum_size = Vector2(0, 210)
	wrap.add_child(lower_scroll)
	var lower := VBoxContainer.new()
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_theme_constant_override("separation", 6)
	lower_scroll.add_child(lower)

	lower.add_child(_mk_label("政策卡 -- 研究行政解锁, 点 挂上 装进右侧卡槽",
		12, Color(0.85, 0.78, 0.6)))
	var cards := GridContainer.new()
	cards.columns = 4
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 5)
	lower.add_child(cards)
	_card_rows.clear()
	for id in Research.CARDS.keys():
		_card_rows[String(id)] = _add_card_card(cards, String(id))

	# 出征编组已挪到「战斗」页统一编组（同伴/法术/部队都在那边选）

	if not _research_linked:
		Research.changed.connect(_on_research_changed)
		_research_linked = true
	_refresh_admin()
	return wrap

# 科技/行政页共用的右侧栏（一个深色小面板，标题 + 内容由调用者接着填）
func _build_research_sidebar(title: String) -> PanelContainer:
	var side := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.075, 0.065, 0.94)
	sb.border_color = Color(0.42, 0.34, 0.24)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	side.add_theme_stylebox_override("panel", sb)
	side.custom_minimum_size = Vector2(300, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	side.add_child(v)
	v.add_child(_mk_label(title, 14, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	return side

# 图例行：色块 + 文字（说明树图上四种状态的颜色）
func _legend_row(entries: Array) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 6)
	for e in entries:
		var swatch := ColorRect.new()
		swatch.color = e[1] as Color
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(swatch)
		h.add_child(_mk_label(str(e[0]), 11, Color(0.72, 0.68, 0.6)))
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(10, 0)
		h.add_child(pad)
	return h

# 一张政策卡（牌面）：左图标 / 名字 / 效果 / [挂上|摘下]
func _add_card_card(parent: Node, id: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 74)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.13, 0.1, 0.98)
	sb.border_color = Color(0.4, 0.34, 0.26)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	var icon := TextureRect.new()
	icon.texture = Research.icon_for(id)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	var name_l := _mk_label("", 12, Color(0.95, 0.85, 0.5))
	v.add_child(name_l)
	var desc_l := _mk_label("", 10, Color(0.75, 0.7, 0.62))
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(0, 24)   # 预留两行, 长描述不再被截断
	v.add_child(desc_l)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 18)
	btn.add_theme_font_override("font", PIXEL_FONT)
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(_on_card_pressed.bind(id))
	v.add_child(btn)
	return {"panel": panel, "name": name_l, "desc": desc_l, "btn": btn}

func _on_research_pressed(id: String, tree: String) -> void:
	_open_research_detail(id, tree)   # 点条目先看详情（效果 + 送的卡）, 研究按钮在详情里

# ---------------- 科技/行政详情弹窗 ----------------
# 点树上条目弹出: 详细信息 + 效果明细 + 随研究解锁的战斗法术卡（行政还列政策卡）
func _open_research_detail(id: String, tree: String) -> void:
	if _rsch_panel == null:
		_build_research_detail()
	_rsch_id = id
	_rsch_tree = tree
	_rsch_wrap.visible = true
	_rsch_panel.visible = true   # 先亮出来再刷新, 否则刷新函数会被 not visible 早退
	_refresh_research_detail()
	Audio.play_sfx("ui_click")

func _close_research_detail() -> void:
	if _rsch_panel != null:
		_rsch_panel.visible = false
	if _rsch_wrap != null:
		_rsch_wrap.visible = false
	_rsch_id = ""

func _build_research_detail() -> void:
	# 与伙伴详情弹窗同一套浮层模式（wrap 必须 IGNORE, 不然关掉后整栏点不动）
	_rsch_wrap = CenterContainer.new()
	_rsch_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rsch_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rsch_wrap)
	_rsch_wrap.visible = false
	_rsch_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.06, 0.98)
	sb.border_color = Color(0.6, 0.45, 0.27)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	_rsch_panel.add_theme_stylebox_override("panel", sb)
	_rsch_wrap.add_child(_rsch_panel)
	_rsch_panel.visible = false

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, clampf(get_viewport_rect().size.y - 200.0, 300.0, 500.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rsch_panel.add_child(scroll)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)
	_rsch_box = VBoxContainer.new()           # 动态内容（每次打开清空重填）
	_rsch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rsch_box.add_theme_constant_override("separation", 5)
	outer.add_child(_rsch_box)
	# 底部按钮行：研究 + 关闭
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	outer.add_child(row)
	_rsch_btn = Button.new()
	_rsch_btn.custom_minimum_size = Vector2(200, 32)
	_rsch_btn.add_theme_font_override("font", PIXEL_FONT)
	_rsch_btn.add_theme_font_size_override("font_size", 13)
	_rsch_btn.pressed.connect(_on_detail_research_pressed)
	row.add_child(_rsch_btn)
	var close_b := Button.new()
	close_b.text = "关闭"
	close_b.custom_minimum_size = Vector2(100, 32)
	close_b.add_theme_font_override("font", PIXEL_FONT)
	close_b.add_theme_font_size_override("font_size", 13)
	close_b.pressed.connect(_close_research_detail)
	row.add_child(close_b)

func _refresh_research_detail() -> void:
	if _rsch_panel == null or not _rsch_panel.visible or _rsch_id == "":
		return
	for c in _rsch_box.get_children():
		c.queue_free()
	var tech := _rsch_tree == "tech"
	var table: Dictionary = Research.TECHS if tech else Research.ADMINS
	var t: Dictionary = table[_rsch_id]
	var done: bool = Research.has_tech(_rsch_id) if tech else Research.has_admin(_rsch_id)
	var tier := clampi(int(t.get("tier", 1)), 1, 4)
	var kind := "科技" if tech else "行政"
	# 标题 + 档位/状态
	_rsch_box.add_child(_mk_label("%s  ·  %s 第%s档" % [t["name"], kind,
		["一", "二", "三", "四"][tier - 1]], 20, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER))
	var ready: bool = Research.tech_ready(_rsch_id) if tech else Research.admin_ready(_rsch_id)
	var can: bool = Research.can_research_tech(_rsch_id) if tech else Research.can_research_admin(_rsch_id)
	if done:
		_rsch_box.add_child(_mk_label("已研究", 13, Color(0.55, 0.9, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	else:
		var status := "可研究"
		var col := Color(0.55, 0.9, 0.45)
		if not ready:
			var missing: Array[String] = []
			for r in t.get("req", []):
				var rid := String(r)
				if tech and not Research.has_tech(rid):
					missing.append(String(Research.TECHS[rid]["name"]))
				elif not tech and not Research.has_admin(rid):
					missing.append(String(Research.ADMINS[rid]["name"]))
			status = "前置未齐: 需先研究 %s" % ", ".join(missing)
			col = Color(0.95, 0.7, 0.45)
		elif not can:
			var pts: int = Research.tech_points if tech else Research.admin_points
			status = "点数不足 (现有 %d / 需 %d)" % [pts, int(t["cost"])]
			col = Color(0.95, 0.7, 0.45)
		_rsch_box.add_child(_mk_label(status, 12, col, HORIZONTAL_ALIGNMENT_CENTER))
	# 研究成本 + 一句话说明
	_rsch_box.add_child(_mk_label("研究成本: %d %s点" % [int(t["cost"]), kind],
		12, Color(0.85, 0.8, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	_rsch_box.add_child(_mk_label(String(t["desc"]), 13, Color(0.92, 0.9, 0.82),
		HORIZONTAL_ALIGNMENT_CENTER))
	# 效果明细
	_rsch_box.add_child(_mk_label("--- 效果明细 ---", 12, Color(0.72, 0.64, 0.52),
		HORIZONTAL_ALIGNMENT_CENTER))
	for line in _research_eff_lines(_rsch_id, tech):
		_rsch_box.add_child(_mk_label("· " + str(line), 12, Color(0.85, 0.88, 0.75),
			HORIZONTAL_ALIGNMENT_CENTER))
	# 随研究解锁的战斗法术卡（科技/行政都送一张, 越后期越强力）
	var sp_id := "m_" + _rsch_id
	if CardsData.SPELLS.has(sp_id):
		var sp: Dictionary = CardsData.SPELLS[sp_id]
		_rsch_box.add_child(_mk_label("--- 随研究的战斗法术卡 ---", 12, Color(0.72, 0.64, 0.52),
			HORIZONTAL_ALIGNMENT_CENTER))
		_rsch_box.add_child(_mk_label("「%s」  %d费" % [sp["name"], int(sp["cost"])],
			14, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
		_rsch_box.add_child(_mk_label(str(sp["desc"]), 12, Color(0.82, 0.78, 0.7),
			HORIZONTAL_ALIGNMENT_CENTER))
		_rsch_box.add_child(_mk_label("研究完成后进战斗页卡池, 编入卡组才能带上战场",
			10, Color(0.66, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	# 底部按钮状态
	_rsch_btn.visible = not done
	if not done:
		_rsch_btn.text = "研究（消耗 %d %s点）" % [int(t["cost"]), kind]
		_rsch_btn.disabled = not can

# 效果明细转可读文本（科技 eff / 行政 slots+政策卡）
func _research_eff_lines(id: String, tech: bool) -> Array:
	var out: Array = []
	if tech:
		var eff: Dictionary = Research.TECHS[id]["eff"]
		for k in eff.keys():
			match String(k):
				"crop":
					out.append("作物卖出价 +%d%%" % roundi(float(eff[k]) * 100.0))
				"food":
					out.append("食物卖出价 +%d%%" % roundi(float(eff[k]) * 100.0))
				"all":
					out.append("所有物品卖出价 +%d%%" % roundi(float(eff[k]) * 100.0))
				"wood":
					out.append("砍树额外掉 %d 根木头" % int(eff[k]))
				"craft":
					out.append("制作食物额外多产 %d 份" % int(eff[k]))
				"research":
					out.append("研究速度 +%d%%" % roundi(float(eff[k]) * 100.0))
				"water":
					out.append("水壶容量 +%d" % int(eff[k]))
				"irrigate":
					out.append("浇一格时顺带浇相邻耕地")
				"chop":
					out.append("砍树一斧顶两斧")
	else:
		var a: Dictionary = Research.ADMINS[id]
		if int(a.get("slots", 0)) > 0:
			out.append("政策卡槽 +%d" % int(a["slots"]))
		for cid in a.get("cards", []):
			var c: Dictionary = Research.CARDS[String(cid)]
			out.append("政策卡「%s」- %s" % [c["name"], c["desc"]])
	return out

func _on_detail_research_pressed() -> void:
	var ok: bool = Research.research_tech(_rsch_id) if _rsch_tree == "tech" \
		else Research.research_admin(_rsch_id)
	Audio.play_sfx("coin" if ok else "error", -6.0)
	if ok:
		_refresh_hero()          # 伙伴属性/劳动力可能变了，角色页顺手刷一下
	_on_research_changed()
	_refresh_research_detail()   # 弹窗重刷成「已研究」

# 出征编组一张解锁牌（牌面）：名字 / 数值 / [编入|撤下]
func _add_deck_card(parent: Node, id: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 74)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.13, 0.1, 0.98)
	sb.border_color = Color(0.4, 0.34, 0.26)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	var name_l := _mk_label("", 12, Color(0.95, 0.85, 0.5))
	v.add_child(name_l)
	var desc_l := _mk_label("", 10, Color(0.75, 0.7, 0.62))
	v.add_child(desc_l)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 6)
	v.add_child(bh)
	var btns := {}
	for tag in ["add", "del"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", PIXEL_FONT)
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(_on_deck_pressed.bind(id, tag == "add"))
		bh.add_child(b)
		btns[tag] = b
	return {"panel": panel, "name": name_l, "desc": desc_l, "add": btns["add"], "del": btns["del"]}

func _on_deck_pressed(id: String, adding: bool) -> void:
	var ok := Research.deck_add(id) if adding else Research.deck_del(id)
	Audio.play_sfx("ui_click" if ok else "error", -10.0)
	_on_research_changed()

func _on_card_pressed(id: String) -> void:
	var ok := false
	if Research.card_slotted(id):
		ok = Research.unslot_card(id)
	else:
		ok = Research.slot_card(id)
	Audio.play_sfx("ui_click" if ok else "error", -10.0)
	_on_research_changed()

func _on_research_changed() -> void:
	_refresh_tech()
	_refresh_admin()
	_refresh_battle()   # 战斗页没开时是空操作, 开着就即时刷新

func _refresh_tech() -> void:
	if _tech_info == null:
		return
	_tech_info.text = "第 %d 天   科技点 %d   每天 +%d   已研究 %d/%d   研究人手 %d 人" % [
		TimeManager.day, Research.tech_points, Research.day_gain("tech"),
		Research.techs.size(), Research.TECHS.size(), Research.tech_heads()]
	if _tech_tree != null:
		_tech_tree.refresh()

func _refresh_admin() -> void:
	if _admin_info == null:
		return
	_admin_info.text = "第 %d 天   行政点 %d   每天 +%d   已研究 %d/%d   生效槽 %d/%d   准备 %d/%d" % [
		TimeManager.day, Research.admin_points, Research.day_gain("admin"),
		Research.admins.size(), Research.ADMINS.size(),
		Research.slot_count() - Research.free_slots(), Research.slot_count(),
		Research.pending.size(), Research.slot_count()]
	if _admin_tree != null:
		_admin_tree.refresh()
	_refresh_slots()
	for id in _card_rows.keys():
		var r: Dictionary = _card_rows[id]
		var c: Dictionary = Research.CARDS[id]
		var unlocked := Research.card_unlocked(id)
		var slotted := Research.card_slotted(id)
		var waiting := Research.is_pending(id)
		(r["name"] as Label).text = "%s%s" % [c["name"],
			"  [生效中]" if slotted else ("  [准备中]" if waiting else "")]
		(r["name"] as Label).add_theme_color_override("font_color",
			Color(0.98, 0.88, 0.55) if slotted \
				else (Color(0.72, 0.85, 0.55) if waiting \
					else (Color(0.85, 0.88, 0.75) if unlocked else Color(0.6, 0.57, 0.52))))
		(r["desc"] as Label).text = str(c["desc"])
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.16, 0.1, 0.98) if slotted \
			else (Color(0.17, 0.17, 0.11, 0.98) if waiting else Color(0.16, 0.13, 0.1, 0.98))
		sb.border_color = Color(0.95, 0.78, 0.35) if slotted \
			else (Color(0.55, 0.72, 0.38) if waiting \
				else (Color(0.45, 0.55, 0.38) if unlocked else Color(0.36, 0.31, 0.26)))
		sb.set_border_width_all(2 if unlocked else 1)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		(r["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
		var btn: Button = r["btn"]
		btn.visible = unlocked
		btn.text = "摘下" if (slotted or waiting) else "挂上"
		btn.disabled = not slotted and not waiting \
			and (Research.free_slots() <= 0 or Research.pending_full())

# ---------------- 战斗页卡池行刷新（p_同伴 / m_法术 / u_部队 三类通用） ----------------
func _kw_text(kw: String) -> String:
	return {"cav": "骑-低油", "guard": "守-护邻", "ranged": "射-后排"}.get(kw, "")

# 编组条目的 [名字, 描述] 文案
func _battle_entry_texts(id: String) -> Array:
	var s := String(id)
	if s.begins_with("p_"):
		var card: Dictionary = CardsData.partner_card(int(s.substr(2)))
		var kwt := _kw_text(String(card["kw"]))
		return [String(card["name"]), "%d费 %d/%d%s" % [int(card["cost"]), int(card["atk"]),
			int(card["hp"]), ((" " + kwt) if kwt != "" else "")]]
	if s.begins_with("m_"):
		var t: Dictionary = CardsData.SPELLS[s]
		return [String(t["name"]), "%d费 法术 - %s" % [int(t["cost"]), t["desc"]]]
	var u: Dictionary = CardsData.UNLOCK[s]
	var kwt2 := _kw_text(String(u["kw"]))
	return [String(u["name"]), "%d费 %d/%d%s / %s" % [int(u["cost"]), int(u["atk"]), int(u["hp"]),
		((" " + kwt2) if kwt2 != "" else ""),
		("强力卡" if String(u["rarity"]) == "strong" else "精英卡")]]

func _refresh_battle_row(r: Dictionary, id: String) -> void:
	var unlocked := CardsData.deck_entry_unlocked(String(id))
	var cnt := Research.deck_count(String(id))
	var cap := CardsData.deck_entry_max(String(id))
	var full := cnt >= cap
	var texts := _battle_entry_texts(String(id))
	(r["name"] as Label).text = "%s  [%d/%d]%s" % [texts[0], cnt, cap,
		"  已编满" if full else ""]
	(r["name"] as Label).add_theme_color_override("font_color",
		Color(0.98, 0.88, 0.55) if full \
			else (Color(0.85, 0.88, 0.75) if unlocked else Color(0.6, 0.57, 0.52)))
	(r["desc"] as Label).text = str(texts[1])
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.16, 0.1, 0.98) if full else Color(0.16, 0.13, 0.1, 0.98)
	sb.border_color = Color(0.95, 0.78, 0.35) if full \
		else (Color(0.45, 0.55, 0.38) if unlocked else Color(0.36, 0.31, 0.26))
	sb.set_border_width_all(2 if unlocked else 1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	(r["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)
	var add_b: Button = r["add"]
	var del_b: Button = r["del"]
	add_b.visible = unlocked
	del_b.visible = unlocked
	add_b.text = "编入"
	del_b.text = "撤下"
	add_b.disabled = full or Research.deck_total() >= CardsData.DECK_CAP
	del_b.disabled = cnt <= 0

# ---------------- 战斗页（出征卡组编成） ----------------
# 左栏三段卡池：同伴卡 / 法术卡 / 部队牌；右栏出征卡组明细
func _build_battle_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	_btl_info = _mk_label("", 13, Color(0.9, 0.86, 0.76))
	wrap.add_child(_btl_info)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	wrap.add_child(main)

	# 左栏：三段卡池，可滚动
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 430)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	scroll.add_child(left)

	left.add_child(_mk_label("同伴卡 -- 出征伙伴一人一张", 12, Color(0.85, 0.78, 0.6)))
	_btl_partner_grid = _mk_battle_grid()
	left.add_child(_btl_partner_grid)
	_btl_rows.clear()
	for i in Slaves.count:
		_btl_rows["p_%d" % i] = _add_deck_card(_btl_partner_grid, "p_%d" % i)

	left.add_child(_mk_label("法术卡 -- 每研究一个科技/行政解锁一张, 越后期越强力",
		12, Color(0.85, 0.78, 0.6)))
	var spell_grid := _mk_battle_grid()
	left.add_child(spell_grid)
	for id in CardsData.SPELLS.keys():
		_btl_rows[String(id)] = _add_deck_card(spell_grid, String(id))

	left.add_child(_mk_label("部队牌 -- 研究解锁的部队 (强力卡限 4 张 / 精英卡限 2 张)",
		12, Color(0.85, 0.78, 0.6)))
	var unit_grid := _mk_battle_grid()
	left.add_child(unit_grid)
	for id in CardsData.UNLOCK.keys():
		_btl_rows[String(id)] = _add_deck_card(unit_grid, String(id))

	# 右栏：出征卡组构成（一眼看清会带上哪些牌）
	var side := _build_research_sidebar("出征卡组")
	var side_v: VBoxContainer = side.get_child(0)
	_btl_side = _mk_label("", 11, Color(0.82, 0.78, 0.7))
	_btl_side.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_v.add_child(_btl_side)

	if not _research_linked:
		Research.changed.connect(_on_research_changed)
		_research_linked = true
	return wrap

# 战斗页卡池网格（两列）
func _mk_battle_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 5)
	return g

func _refresh_battle() -> void:
	if _btl_info == null:
		return
	# 新招募的伙伴补建卡池行
	if _btl_partner_grid != null:
		for i in Slaves.count:
			var pid := "p_%d" % i
			if not _btl_rows.has(pid):
				_btl_rows[pid] = _add_deck_card(_btl_partner_grid, pid)
	_btl_info.text = "第 %d 天   卡组 %d/%d 张   全员自动出海, 出海不占当天劳动" % [
		TimeManager.day, Research.deck_total(), CardsData.DECK_CAP]
	for id in _btl_rows.keys():
		_refresh_battle_row(_btl_rows[id], String(id))
	if _btl_side != null:
		_btl_side.text = _deck_summary_text()

# 卡组构成明细：主角 + 基础牌固定不占名额, 编入的牌按 同伴/法术/部队 分组列出
func _deck_summary_text() -> String:
	var lines: Array[String] = []
	lines.append("卡组 %d/%d 张" % [Research.deck_total(), CardsData.DECK_CAP])
	lines.append("-- 固定 (不占名额) --")
	lines.append("主角亲征 x1")
	for id in CardsData.BASICS.keys():
		lines.append("%s x%d" % [CardsData.BASICS[id]["name"], CardsData.BASIC_COPIES])
	var secs := {"同伴": [], "法术": [], "部队": []}
	for id in Research.deck:
		var s := String(id)
		var key := "部队"
		if s.begins_with("p_"):
			key = "同伴"
		elif s.begins_with("m_"):
			key = "法术"
		var arr: Array = secs[key]
		arr.append(String(_battle_entry_texts(s)[0]))
	var any := false
	for sec in ["同伴", "法术", "部队"]:
		var arr: Array = secs[sec]
		if arr.is_empty():
			continue
		any = true
		lines.append("-- %s卡 --" % sec)
		var by_name := {}
		for nm in arr:
			by_name[nm] = int(by_name.get(nm, 0)) + 1
		for nm in by_name.keys():
			lines.append("%s x%d" % [nm, by_name[nm]])
	if not any:
		lines.append("-- (还没编入卡牌) --")
	return "\n".join(lines)

func _refresh_slots() -> void:
	if _slot_box == null:
		return
	var want := Research.slot_count()
	while _slot_labels.size() < want:
		var slot := _mk_slot_panel()
		_slot_box.add_child(slot)
		_slot_labels.append(slot)
	while _slot_labels.size() > want:
		var slot: Control = _slot_labels.pop_back()
		slot.queue_free()
	for i in _slot_labels.size():
		_fill_slot_panel(_slot_labels[i], String(Research.slots[i]) if i < Research.slots.size() else "", true)
	_refresh_pending_slots()

# 准备槽：挂上还没生效的卡，下周一早上（第 1/8/15/22 天）自动上任
func _refresh_pending_slots() -> void:
	if _pending_box == null:
		return
	var want := Research.pending.size()
	while _pending_labels.size() < want:
		var slot := _mk_slot_panel()
		_pending_box.add_child(slot)
		_pending_labels.append(slot)
	while _pending_labels.size() > want:
		var slot: Control = _pending_labels.pop_back()
		slot.queue_free()
	for i in _pending_labels.size():
		_fill_slot_panel(_pending_labels[i], String(Research.pending[i]), false)

# 一块槽位面板（生效槽/准备槽共用样式，靠 border 颜色区分）
func _mk_slot_panel() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(104, 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.15, 0.13)
	sb.border_color = Color(0.5, 0.4, 0.28)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 5
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	slot.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	slot.add_child(h)
	var icon := TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(16, 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var l := _mk_label("空槽", 11, Color(0.55, 0.52, 0.48), HORIZONTAL_ALIGNMENT_CENTER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	slot.set_meta("icon", icon)
	slot.set_meta("label", l)
	return slot

func _fill_slot_panel(slot: Control, cid: String, active: bool) -> void:
	var icon: TextureRect = slot.get_meta("icon")
	var l: Label = slot.get_meta("label")
	icon.texture = Research.icon_for(cid) if cid != "" else null
	if cid == "":
		l.text = "空槽"
		l.add_theme_color_override("font_color", Color(0.55, 0.52, 0.48))
	else:
		l.text = String(Research.CARDS[cid]["name"])
		l.add_theme_color_override("font_color",
			Color(0.98, 0.88, 0.55) if active else Color(0.72, 0.85, 0.55))
	var sb: StyleBoxFlat = slot.get_theme_stylebox("panel")
	sb.border_color = Color(0.95, 0.78, 0.35) if active else Color(0.5, 0.62, 0.4)

# ---------------- 团队管理页 ----------------
# 上：四张统计卡（人数 / 可派 / 已派 / 干完）；中：职业树两棵（战斗/劳动, 点节点转职）；
# 下：伙伴卡片墙（点头像卡开详情）+ 两条小贴士。整页套滚动, 伙伴多也翻得动。
func _build_team_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 8)
	_team_info = _mk_label("", 11, Color(0.72, 0.68, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	_team_stats.clear()

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	wrap.add_child(stats)
	for spec in [
		["伙伴", Color(0.98, 0.88, 0.55)],
		["今天可派", Color(0.55, 0.9, 0.45)],
		["已派格子", Color(0.55, 0.8, 0.95)],
		["已干完", Color(0.95, 0.7, 0.4)],
	]:
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.085, 0.07, 0.94)
		sb.border_color = Color(0.42, 0.34, 0.24)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.content_margin_top = 6
		sb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", sb)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		card.add_child(v)
		var val := _mk_label("0", 20, spec[1] as Color, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(val)
		v.add_child(_mk_label(str(spec[0]), 10, Color(0.66, 0.62, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
		_team_stats.append(val)

	wrap.add_child(_team_info)

	# e27g: 两棵职业树挪进同伴详情弹窗了 —— 团队页只留统计和名单, 不用再划上划下

	# 伙伴列表：每个伙伴一张卡（头像块 + 名字职业 + 好感条 + 状态徽章），点卡开详情
	_team_list = VBoxContainer.new()
	_team_list.add_theme_constant_override("separation", 6)
	wrap.add_child(_team_list)

	wrap.add_child(_mk_label("走近伙伴按 F 可以对话, 对话 + 喂食 + 送礼都加好感; 点伙伴卡看详情",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	wrap.add_child(_mk_label("招新伙伴: 傍晚野外会亮起篝火, 走近按 F",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	scroll.add_child(wrap)
	return scroll

# 职业配色（头像块底色）：新兵土灰，近战线越来越红，远程线越来越青
const TROOP_COLORS := {
	"新兵": Color(0.38, 0.34, 0.28),
	"刀客": Color(0.52, 0.24, 0.2),
	"剑士": Color(0.64, 0.32, 0.2),
	"咏剑士": Color(0.8, 0.46, 0.2),
	"弓手": Color(0.2, 0.4, 0.37),
	"神射手": Color(0.22, 0.52, 0.44),
	"狙击手": Color(0.26, 0.65, 0.52),
	"矛兵": Color(0.38, 0.34, 0.18),
}
func _troop_color(troop: String) -> Color:
	return TROOP_COLORS.get(troop, Color(0.34, 0.29, 0.23))

# 伙伴的正面站立小像：借 slave_npc 的贴图拼法抽 idle_down 第 0 帧。
# 取不到（贴图缺失之类）返回 null，调用方退回首字块 —— 面板不能因为少张图就崩。
func _slave_portrait(i: int) -> Texture2D:
	if _portrait_cache.has(i):
		return _portrait_cache[i] as Texture2D
	var tex: Texture2D = null
	var model := String(NPC_SCRIPT.model_for(i))
	if model != "":
		# e29c: 改色贴图管线 —— 每个伙伴的发色/服装色烘在贴图里, 静态直调
		var frames: SpriteFrames = NPC_SCRIPT.build_frames(model, i)
		if frames != null:
			tex = frames.get_frame_texture(&"idle_down", 0)
	_portrait_cache[i] = tex
	return tex

# 一个伙伴当前的占用心状态：[文字, 颜色]
func _slave_status(i: int) -> Array:
	if Slaves.is_research(i, "tech"):
		return ["钻研科技", Color(0.55, 0.9, 0.45)]
	if Slaves.is_research(i, "admin"):
		return ["钻研行政", Color(0.95, 0.8, 0.45)]
	if Slaves.is_dock(i):
		return ["修码头", Color(0.92, 0.6, 0.3)]
	return ["待命", Color(0.62, 0.58, 0.52)]

# 一张伙伴卡：头像色块（首字）+ 名字/职业 + 好感条 + 状态徽章 + [详情] 按钮
func _make_slave_card(i: int, s: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.075, 0.96)
	sb.border_color = Color(0.45, 0.36, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(0, 88)
	card.gui_input.connect(_on_card_gui_input.bind(i))
	card.tooltip_text = "点开 %s 的详情 (喂食 / 改名 / 晋升)" % str(s["name"])

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	# 头像块：职业色底 + 立绘小像（取不到帧就退回首字）
	var face := PanelContainer.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fb := StyleBoxFlat.new()
	var tc := _troop_color(str(s["troop"]))
	fb.bg_color = Color(tc.r, tc.g, tc.b, 0.95)
	fb.border_color = tc.lightened(0.25)
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(5)
	fb.content_margin_left = 2
	fb.content_margin_right = 2
	fb.content_margin_top = 2
	fb.content_margin_bottom = 2
	face.add_theme_stylebox_override("panel", fb)
	face.custom_minimum_size = Vector2(46, 46)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(face)
	var ptex := _slave_portrait(i)
	if ptex != null:
		# 32px 像素画放大必须用最近邻过滤，不然糊成一团（跟篝火小像同一套参数）
		var tr := TextureRect.new()
		tr.texture = ptex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.custom_minimum_size = Vector2(40, 40)
		face.add_child(tr)
	else:
		var fl := _mk_label(str(s["name"]).substr(0, 1), 18, Color(1, 0.94, 0.8),
			HORIZONTAL_ALIGNMENT_CENTER)
		fl.custom_minimum_size = Vector2(40, 0)
		face.add_child(fl)

	# 中间：名字 / 职业 + 好感条
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mid)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(name_row)
	name_row.add_child(_mk_label(str(s["name"]), 14, Color(1, 0.92, 0.75)))
	name_row.add_child(_mk_label(str(s["troop"]), 10,
		(_troop_color(str(s["troop"])) as Color).lightened(0.4)))
	# e30s: 卡片上也要看得见劳动职业（以前只在详情弹窗里），跟详情页劳动树标题同色
	name_row.add_child(_mk_label("劳 %s" % str(s.get("labor", "帮工")), 10,
		Color(0.75, 0.88, 0.62)))
	var aff: int = int(s["affection"])
	# ❗IPix.ttf 没有 | 的字形（渲出来是方块），竖条用大写 I 代替
	var hearts := ""
	for k in aff:
		hearts += "I"
	var blanks := ""
	for k in int(Slaves.AFFECTION_MAX) - aff:
		blanks += "."
	var aff_row := HBoxContainer.new()
	aff_row.add_theme_constant_override("separation", 0)
	aff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(aff_row)
	aff_row.add_child(_mk_label("好感 ", 10, Color(0.6, 0.56, 0.5)))
	if hearts != "":
		aff_row.add_child(_mk_label(hearts, 12, Color(0.98, 0.55, 0.6)))
	if blanks != "":
		aff_row.add_child(_mk_label(blanks, 12, Color(0.3, 0.27, 0.24)))

	# 右侧：状态徽章 + 详情按钮
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 4)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	var st := _slave_status(i)
	var badge := _mk_label(str(st[0]), 11, st[1] as Color, HORIZONTAL_ALIGNMENT_CENTER)
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(st[1].r, st[1].g, st[1].b, 0.16)
	bb.border_color = Color(st[1].r, st[1].g, st[1].b, 0.55)
	bb.set_border_width_all(1)
	bb.set_corner_radius_all(4)
	bb.content_margin_left = 8
	bb.content_margin_right = 8
	bb.content_margin_top = 2
	bb.content_margin_bottom = 2
	badge.add_theme_stylebox_override("normal", bb)
	right.add_child(badge)
	var btn := Button.new()
	btn.text = "详情"
	btn.custom_minimum_size = Vector2(56, 20)
	btn.add_theme_font_override("font", PIXEL_FONT)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_open_slave_detail.bind(i))
	right.add_child(btn)
	return card

# 点卡片空白处也能开详情（跟「详情」按钮等价）
func _on_card_gui_input(event: InputEvent, i: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_open_slave_detail(i)

# ---------------- 伙伴详情弹窗 ----------------
var _detail_wrap: CenterContainer = null   # e24: 详情浮层容器(关闭时一起藏, 不然它 STOP 挡住整栏)

func _open_slave_detail(idx: int) -> void:
	if _detail_panel == null:
		_build_slave_detail()
	_detail_index = idx
	_last_slave = idx            # 树的晋升对象也跟着换成这个伙伴
	_detail_wrap.visible = true
	_detail_panel.visible = true # 先亮出来再刷新, 否则 _refresh_slave_detail 会被 not visible 早退
	_refresh_slave_detail()
	_refresh_class_trees()
	Audio.play_sfx("ui_click")

func _close_slave_detail() -> void:
	if _detail_panel != null:
		_detail_panel.visible = false
	if _detail_wrap != null:
		_detail_wrap.visible = false
	_detail_index = -1
	_refresh_team()                  # 名字可能改了，回到列表要刷一下

func _build_slave_detail() -> void:
	# 卡片浮层：全屏透明居中容器 + 按内容收缩的卡片（不再整屏盖黑底）
	# ❗wrap 必须 mouse_filter=IGNORE：它盖满整栏，详情关掉后若还拦鼠标，
	#   页签/按钮全部点不动 —— 「点完详情 Esc 栏卡住」就是这个。
	_detail_wrap = CenterContainer.new()
	_detail_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_detail_wrap)
	_detail_wrap.visible = false
	_detail_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.06, 0.98)
	sb.border_color = Color(0.6, 0.45, 0.27)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	_detail_panel.add_theme_stylebox_override("panel", sb)
	_detail_wrap.add_child(_detail_panel)
	_detail_panel.visible = false

	# e30s: 详情页内容很高（两棵树 + 改名 + 喂食 + 送礼），直接塞进卡片会顶出屏幕底。
	#   跟角色页/科技页同一套路：限高 + 关横向滚动，竖向可以拖。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, clampf(get_viewport_rect().size.y - 160.0, 320.0, 620.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_detail_name_label = _mk_label("", 22, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_detail_name_label)
	_detail_info_label = _mk_label("", 13, Color(0.95, 0.7, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_detail_info_label)
	box.add_child(_mk_label("---", 11, Color(0.72, 0.64, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# e27g: 两棵升级树从团队页挪进来 —— 看谁的详情树就归谁, 点树上的职业直接转职
	_tree_target = _mk_label("", 11, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_tree_target)
	box.add_child(_mk_label("战斗树 (每升一阶 攻 +1; 三次晋升分别要整套甲 1/2/3 级)",
		12, Color(0.95, 0.75, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	_combat_tree = ClassTreeView.new()
	_combat_tree.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_combat_tree)
	_combat_tree.setup(false, _on_class_node_clicked, true)
	_detail_class_benefit = _mk_label("", 11, Color(0.85, 0.8, 0.6),
		HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_detail_class_benefit)
	box.add_child(_mk_label("劳动树 (帮工起步, 三线选一条升到底: 营造/学问/丰饶)",
		12, Color(0.75, 0.88, 0.62), HORIZONTAL_ALIGNMENT_CENTER))
	_labor_tree = ClassTreeView.new()
	_labor_tree.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_labor_tree)
	_labor_tree.setup(true, _on_class_node_clicked, true)
	_detail_labor_benefit = _mk_label("", 11, Color(0.8, 0.88, 0.68),
		HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_detail_labor_benefit)
	box.add_child(_mk_label("战斗: 新兵 0 攻 -> 一线 1 -> 二线 2 -> 满阶 3; 甲分三档 皮甲1/锁链甲2/铁甲3, 转职吃掉一件",
		10, Color(0.66, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_mk_label("劳动: 营造线=建造 +1/2/4 (工地与铁匠铺)  学问线=知识 +2/3/6 (研究)  丰饶线=劳动 +6/12/20 (浇水/下矿)",
		10, Color(0.66, 0.62, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# 改名
	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", 6)
	box.add_child(rename_row)
	_detail_rename = LineEdit.new()
	_detail_rename.placeholder_text = "给伙伴起个新名字"
	_detail_rename.custom_minimum_size = Vector2(220, 28)
	_detail_rename.max_length = 8
	_detail_rename.add_theme_font_override("font", PIXEL_FONT)
	_detail_rename.add_theme_font_size_override("font_size", 13)
	rename_row.add_child(_detail_rename)
	_detail_rename_btn = Button.new()
	_detail_rename_btn.text = "改名"
	_detail_rename_btn.custom_minimum_size = Vector2(60, 28)
	_detail_rename_btn.add_theme_font_override("font", PIXEL_FONT)
	_detail_rename_btn.add_theme_font_size_override("font_size", 12)
	_detail_rename_btn.pressed.connect(_on_rename_pressed)
	rename_row.add_child(_detail_rename_btn)

	box.add_child(_mk_label("(每天第一次对话 +1 好感, 第一次喂食 +1)",
		11, Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_mk_label("(每天第一次送礼 +2; 好感每 4 点换伙伴 1 点攻击)",
		11, Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_CENTER))

	# 喂食 / 送礼
	var feed_row := HBoxContainer.new()
	feed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	feed_row.add_theme_constant_override("separation", 8)
	box.add_child(feed_row)
	_detail_feed_btn = Button.new()
	_detail_feed_btn.text = "喂食 (选背包里的第一份食物)"
	_detail_feed_btn.custom_minimum_size = Vector2(280, 30)
	_detail_feed_btn.add_theme_font_override("font", PIXEL_FONT)
	_detail_feed_btn.add_theme_font_size_override("font_size", 13)
	_detail_feed_btn.pressed.connect(_on_feed_pressed_detail)
	feed_row.add_child(_detail_feed_btn)

	var gift_row := HBoxContainer.new()
	gift_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gift_row.add_theme_constant_override("separation", 8)
	box.add_child(gift_row)
	_detail_gift_btn = Button.new()
	_detail_gift_btn.text = "送礼 (选背包里的第一份作物)"
	_detail_gift_btn.custom_minimum_size = Vector2(280, 30)
	_detail_gift_btn.add_theme_font_override("font", PIXEL_FONT)
	_detail_gift_btn.add_theme_font_size_override("font_size", 13)
	_detail_gift_btn.pressed.connect(_on_gift_pressed_detail)
	gift_row.add_child(_detail_gift_btn)

	_detail_back_btn = Button.new()
	_detail_back_btn.text = "回到列表"
	_detail_back_btn.custom_minimum_size = Vector2(160, 30)
	_detail_back_btn.add_theme_font_override("font", PIXEL_FONT)
	_detail_back_btn.add_theme_font_size_override("font_size", 12)
	_detail_back_btn.pressed.connect(_close_slave_detail)
	box.add_child(_detail_back_btn)

func _refresh_slave_detail() -> void:
	if _detail_index < 0 or _detail_panel == null or not _detail_panel.visible:
		return
	var s: Dictionary = Slaves.slave_at(_detail_index)
	if s.is_empty():
		_close_slave_detail()
		return
	_detail_name_label.text = "%s" % s["name"]
	var aff: int = int(s["affection"])
	var hearts := ""
	for _k in aff:
		hearts += "*"
	_detail_info_label.text = "好感 %s  %d/%d\n今天%s聊过,%s喂过,%s送过礼" % [
		hearts, aff, Slaves.AFFECTION_MAX,
		"" if bool(s["talked_today"]) else "没",
		"" if bool(s["fed_today"]) else "没",
		"" if bool(s.get("gift_today", false)) else "没",
	]
	# 输入框默认填当前名（玩家可以编辑再点改名）
	if _detail_rename != null:
		_detail_rename.text = s["name"]
	# 喂食按钮：今天喂过就灰掉
	if _detail_feed_btn != null:
		_detail_feed_btn.disabled = bool(s["fed_today"])
		_detail_feed_btn.modulate = Color(0.7, 0.7, 0.7) if bool(s["fed_today"]) else Color(1, 1, 1)
	# 送礼按钮：今天送过就灰掉
	if _detail_gift_btn != null:
		_detail_gift_btn.disabled = bool(s.get("gift_today", false))
		_detail_gift_btn.modulate = Color(0.7, 0.7, 0.7) if bool(s.get("gift_today", false)) else Color(1, 1, 1)
	# e27g: 树的皮肤由 _refresh_class_trees 统一刷, 这里只更新两行当前收益
	var troop := String(s.get("troop", "新兵"))
	var cur_atk: int = int(Slaves.CLASSES.get(troop, {}).get("atk", 0))
	if _detail_class_benefit != null:
		_detail_class_benefit.text = "当前收益: 攻 +%d   (好感每 4 点再折 1 攻)" % cur_atk
	if _detail_labor_benefit != null:
		# e28e: 顺手把这人一天能派几格活也写出来（基础额度 + 劳动树加成）
		_detail_labor_benefit.text = "当前收益: %s   派活 %d 格/天 (基础 %d + 加成 %d)" % [
			_labor_benefit_text(String(s.get("labor", "帮工"))),
			Slaves.slave_cells(s), Slaves.cells_per_slave(), Slaves.labor_bonus_of(s)]

# e24: 劳动职业的收益文案（build=建造 / study=知识 / labor=劳动）
func _labor_benefit_text(cls: String) -> String:
	var d: Dictionary = Slaves.LABOR_CLASSES.get(cls, {})
	var parts: Array = []
	if d.has("build"):
		parts.append("%s +%d" % [Slaves.ATTR_NAMES["build"], int(d["build"])])
	if d.has("study"):
		parts.append("%s +%d" % [Slaves.ATTR_NAMES["study"], int(d["study"])])
	if d.has("labor"):
		parts.append("%s +%d" % [Slaves.ATTR_NAMES["labor"], int(d["labor"])])
	if parts.is_empty():
		return "无特殊收益"
	return " / ".join(parts)

func _on_rename_pressed() -> void:
	if _detail_index < 0 or _detail_rename == null:
		return
	var new_name := _detail_rename.text
	if Slaves.rename(_detail_index, new_name):
		Audio.play_sfx("ui_click")
		_refresh_slave_detail()
	else:
		Audio.play_sfx("error", -6.0)
	_flash_detail_info("名字不能为空")

func _on_feed_pressed_detail() -> void:
	if _detail_index < 0:
		return
	var s: Dictionary = Slaves.slave_at(_detail_index)
	if s.is_empty() or bool(s["fed_today"]):
		return
	# 找一份食物（食物类道具）
	var food: ItemData = null
	for sl in Inventory.slot_list():
		var it: ItemData = sl["item"]
		if it != null and it.type == "食物" and int(sl["count"]) > 0:
			food = it
			break
	if food == null:
		_flash_detail_info("背包里还没有食物,先去物品制作页做一份吧")
		Audio.play_sfx("error", -6.0)
		return
	var gain: int = Slaves.feed(_detail_index, food)
	if gain <= 0:
		_flash_detail_info("今天已经喂过了")
		return
	Inventory.remove_item(food, 1)
	Audio.play_sfx("buy")
	_flash_detail_info("喂了 1 份 %s, 好感 +%d" % [food.display_name, gain])
	_refresh_slave_detail()

func _on_gift_pressed_detail() -> void:
	if _detail_index < 0:
		return
	var s: Dictionary = Slaves.slave_at(_detail_index)
	if s.is_empty() or bool(s.get("gift_today", false)):
		return
	# 找一份作物（收获来的庄稼当礼物）
	var crop: ItemData = null
	for sl in Inventory.slot_list():
		var it: ItemData = sl["item"]
		if it != null and it.type == "作物" and int(sl["count"]) > 0:
			crop = it
			break
	if crop == null:
		_flash_detail_info("背包里还没有作物, 收了庄稼再拿来当礼物吧")
		Audio.play_sfx("error", -6.0)
		return
	var gain: int = Slaves.gift_item(_detail_index, crop)
	if gain <= 0:
		_flash_detail_info("今天已经送过礼物了")
		return
	Inventory.remove_item(crop, 1)
	Audio.play_sfx("buy")
	_flash_detail_info("送了 1 份 %s, 好感 +%d" % [crop.display_name, gain])
	_refresh_slave_detail()

func _flash_detail_info(text: String) -> void:
	if _detail_info_label == null:
		return
	var old := _detail_info_label.text
	_detail_info_label.text = text
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_detail_info_label, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		_detail_info_label.text = old
		_detail_info_label.modulate.a = 1.0)

# 刷新伙伴列表：每个伙伴一张卡，点卡打开详情弹窗
func _refresh_slave_list() -> void:
	if _team_list == null:
		return
	# 清掉旧的（owned=false 才能 get 到运行时 add 的控件）
	for c in _team_list.get_children():
		c.queue_free()
	_slave_btns.clear()
	for i in Slaves.slaves.size():
		var card := _make_slave_card(i, Slaves.slaves[i])
		_team_list.add_child(card)
		_slave_btns.append(card)
	if Slaves.slaves.is_empty():
		var hint := _mk_label("还没有伙伴 -- 傍晚去篝火看看, 招募一个吧",
			12, Color(0.78, 0.74, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
		hint.custom_minimum_size = Vector2(360, 40)
		_team_list.add_child(hint)

# ---------------- 地图页 ----------------
# ❗建面板的时候 Slaves.map_from/map_to 可能还没被 game.gd 覆盖成「整座岛」，
#   所以这里只把控件插进去，真正的 setup 留到**每次切到这一页**时再做。
func _build_map_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)

	_map_page = preload("res://scene/terrain_map.gd").new()
	_map_page.show_actors = true
	_map_page.auto_fit = false
	_map_page.custom_minimum_size = _map_box_size()
	wrap.add_child(_map_page)

	var legend := HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 12)
	wrap.add_child(legend)
	for entry in [
		# ❗色块前缀只能用字体里真有的字符：■ ● 在 IPix.ttf 里都没有字形（会显示成一个小方块）
		["# 已播种", Color(0.66, 0.82, 0.24)],
		["# 空耕地", Color(0.55, 0.34, 0.24)],
		["# 草地", Color(0.34, 0.52, 0.28)],
		["# 水面", Color(0.13, 0.28, 0.42)],
		["@ 自己", Color(1.00, 0.86, 0.32)],
		["o 伙伴", Color(0.40, 0.92, 1.00)],
	]:
		legend.add_child(_mk_label(str(entry[0]), 11, entry[1] as Color))
	return wrap

func _map_box_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1152, 648)
	return Vector2(clampf(vp.x - 220.0, 320.0, 820.0), clampf(vp.y - 300.0, 200.0, 420.0))

# ---------------- 物品制作页 ----------------
var _craft_rows: Array = []          # 配方对应的按钮列表，刷新时改文字/状态
var _craft_info: Label = null
# e28f: 配方拆三个子页签（个人/工作台/铁匠铺）, 一页只看一类, 不用滚半天才找到铁匠铺
var _craft_sub_pages := {}           # 子页 key -> VBoxContainer
var _craft_sub_btns := {}            # 子页 key -> 页签按钮
var _smith_queue_label: Label = null # e41c: 铁匠铺页顶上的队列一览（排队顺序 + 进度）

func _build_craft_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)

	var intro := _mk_label("点配方即可制作 -- 缺材料时按钮会灰掉", 12,
		Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(intro)

	# e28f: 三个子页签, 切换只显其中一段配方
	var sub_tabs := HBoxContainer.new()
	sub_tabs.add_theme_constant_override("separation", 4)
	sub_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(sub_tabs)
	for s in [{"key": "base", "name": "个人"},
			{"key": "wb", "name": "工作台"},
			{"key": "smith", "name": "铁匠铺"}]:
		var tb := Button.new()
		tb.text = str(s["name"])
		tb.custom_minimum_size = Vector2(150, 28)
		tb.add_theme_font_override("font", PIXEL_FONT)
		tb.add_theme_font_size_override("font_size", 13)
		tb.pressed.connect(_select_craft_sub.bind(str(s["key"])))
		sub_tabs.add_child(tb)
		_craft_sub_btns[str(s["key"])] = tb

	_craft_info = _mk_label("", 13, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(_craft_info)

	# 个人: 随手就能做的基础配方（食物 / 地板 / 工作台）
	var base_page := _craft_sub_page("base", wrap)
	for i in Crafting.RECIPES.size():
		var r: Dictionary = Crafting.RECIPES[i]
		var row := _craft_row_btn()
		row.pressed.connect(_on_craft_pressed.bind(i, false))
		base_page.add_child(row)
		_craft_rows.append({"btn": row, "idx": i, "result": r["result"], "wb": false})
	base_page.add_child(_mk_label("(手持木地板时点到草地/耕地上即可铺设)",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# 工作台: 要站在工作台旁边才能做（更复杂的工具和器械）
	var wb_page := _craft_sub_page("wb", wrap)
	wb_page.add_child(_mk_label("-- 要站在工作台旁边才能做 --", 12,
		Color(0.8, 0.7, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	for i in Crafting.WORKBENCH_RECIPES.size():
		var wb_r: Dictionary = Crafting.WORKBENCH_RECIPES[i]
		var wb_row := _craft_row_btn()
		wb_row.pressed.connect(_on_craft_pressed.bind(i, true))
		wb_page.add_child(wb_row)
		_craft_rows.append({"btn": wb_row, "idx": i, "result": wb_r["result"], "wb": true})

	# 铁匠铺配方页: 整套盔甲。要站在铁匠铺旁, 铁匠铺等级够才能打高档甲,
	# 开工时材料一次付清, 夜里在派活面板派「打铁」人工攒够了才出货。
	# e41c: 可以一次排好几件 —— 人工先喂队首, 攒够出货, 多出来的顺延给下一件。
	var sm_page := _craft_sub_page("smith", wrap)
	sm_page.add_child(_mk_label("-- 整套盔甲: 要站在铁匠铺旁, 材料一次付清, 夜里派人打铁 --", 12,
		Color(0.8, 0.7, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	_smith_queue_label = _mk_label("", 12, Color(0.92, 0.84, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	sm_page.add_child(_smith_queue_label)
	for i in Crafting.SMITH_RECIPES.size():
		var sm_r: Dictionary = Crafting.SMITH_RECIPES[i]
		var sm_row := _craft_row_btn()
		sm_row.pressed.connect(_on_craft_pressed.bind(i, false, true))
		sm_page.add_child(sm_row)
		_craft_rows.append({"btn": sm_row, "idx": i, "result": sm_r["result"], "smith": true})

	_select_craft_sub("base")
	return wrap

func _craft_sub_page(key: String, wrap: VBoxContainer) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 6)
	wrap.add_child(p)
	_craft_sub_pages[key] = p
	return p

func _craft_row_btn() -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(420, 44)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_font_override("font", PIXEL_FONT)
	row.add_theme_font_size_override("font_size", 13)
	return row

# e28f: 切制作子页签 —— 只显当前那段, 选中的页签字点亮
func _select_craft_sub(key: String) -> void:
	for k in _craft_sub_pages.keys():
		(_craft_sub_pages[k] as Control).visible = (k == key)
	for k in _craft_sub_btns.keys():
		var b: Button = _craft_sub_btns[k]
		if k == key:
			b.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
		else:
			b.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62))
	_refresh_craft()

func _refresh_craft() -> void:
	# e41c: 铁匠铺页顶上的队列一览（"打铁队列: 皮甲 1/2, 锁链甲 0/2"）
	if _smith_queue_label != null:
		if Crafting.smith_busy():
			_smith_queue_label.text = "打铁队列 (%d 件): %s" % [
				Crafting.smith_queued(), Crafting.smith_queue_text()]
		else:
			_smith_queue_label.text = "打铁队列: 空 (点了配方就排进来)"
	if _craft_rows.is_empty():
		return
	for entry in _craft_rows:
		var idx: int = int(entry["idx"])
		var wb: bool = bool(entry.get("wb", false))
		var smith: bool = bool(entry.get("smith", false))
		var r: Dictionary
		if smith:
			r = Crafting.SMITH_RECIPES[idx]
		else:
			r = Crafting.WORKBENCH_RECIPES[idx] if wb else Crafting.RECIPES[idx]
		var result: ItemData = r["result"]
		var btn: Button = entry["btn"]
		# 描述「材料1 + 材料2 -> 产物 x 1」
		# ❗箭头只能用 ASCII 的 "->"：IPix.ttf 里没有 U+2192(→) 的字形
		var label := " -> %s x %d" % [result.display_name, int(r["count"])]
		for c in r["costs"]:
			var it: ItemData = c["item"]
			label = "  %s x %d" % [it.display_name, int(c["count"])] + label
		var ok: bool
		if smith:
			# 铁匠铺行：门槛（等级/人工）写在最前面, 让玩家知道缺的是哪样
			label = "  人工x%d" % int(r["labor"]) + label
			label = "  铁匠铺Lv.%d" % int(r["lv"]) + label
			ok = Crafting.can_craft_smith(idx)
			if not ok:
				var sm_miss: Array = Crafting.missing_smith(idx)
				if sm_miss.size() > 0 and int(sm_miss[0].get("need", 0)) == -1:
					label = "(人不在铁匠铺旁) " + label
				elif sm_miss.size() > 0 and int(sm_miss[0].get("need", 0)) == -2:
					label = "(铁匠铺等级不够, 建造页花钱升级) " + label
		else:
			ok = Crafting.can_craft_workbench(idx) if wb else Crafting.can_craft(idx)
			if wb and not ok:
				# 材料够但人不在工作台旁：文案里给个原因，别让玩家一头雾水
				var miss: Array = Crafting.missing_workbench(idx)
				if miss.size() > 0 and int(miss[0].get("need", 0)) == -1:
					label = "(人不在工作台旁) " + label
		btn.text = label
		btn.disabled = not ok
		btn.modulate = Color(1, 1, 1) if ok else Color(0.75, 0.72, 0.7)

func _on_craft_pressed(idx: int, wb := false, smith := false) -> void:
	var r: Dictionary
	if smith:
		r = Crafting.SMITH_RECIPES[idx]
	else:
		r = Crafting.WORKBENCH_RECIPES[idx] if wb else Crafting.RECIPES[idx]
	var result: ItemData = r["result"]
	var ok: bool
	if smith:
		ok = Crafting.craft_smith(idx)
	else:
		ok = Crafting.craft_workbench(idx) if wb else Crafting.craft(idx)
	if ok:
		Audio.play_sfx("buy")
		if _craft_info != null:
			var done_text := "做好了 %s x %d" % [result.display_name, int(r["count"])]
			if smith:
				done_text = "排队了 %s x %d (材料已付清, 夜里派人打铁按队列顺序出货)" % [
					result.display_name, int(r["count"])]
			_craft_info.text = done_text
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_property(_craft_info, "modulate:a", 0.0, 0.4)
			tw.tween_callback(func() -> void:
				_craft_info.text = ""
				_craft_info.modulate.a = 1.0)
		_refresh_craft()
	else:
		Audio.play_sfx("error", -6.0)
		if _craft_info != null:
			if smith:
				var sm_miss: Array = Crafting.missing_smith(idx)
				var sm_why := "还缺 %d 样东西" % sm_miss.size()
				if sm_miss.size() > 0:
					match int(sm_miss[0].get("need", 0)):
						-1: sm_why = "要先站在铁匠铺旁边"
						-2: sm_why = "铁匠铺等级不够, 到建造页花钱升级"
				_craft_info.text = sm_why
				return
			var miss: Array = Crafting.missing_workbench(idx) if wb else Crafting.missing(idx)
			var why := "材料不够 -- 还缺 %d 种" % miss.size()
			if miss.size() > 0 and int(miss[0].get("need", 0)) == -1:
				why = "要先站在工作台旁边"
			_craft_info.text = why

# ---------------- 建造页 ----------------
# 星露谷式: 这页只选建筑, 点"选位置"关背包回地图, ghost 跟鼠标左键放/右键取消
var _build_rows := {}          # kind -> Button, 刷新时按支付能力灰显
var _build_info: Label = null
var _upgrade_box: VBoxContainer = null   # e28f: 建筑升级列表（刷新时整段重建）
var _site_label: Label = null      # e24c: 当前工地进度
var _site_cancel: Button = null    # e24c: 取消建筑
var _move_btn: Button = null       # e44: 建筑模式（搬已建好的建筑）入口

func _build_build_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)

	# e24c: 当前工地一览 —— 进度 + 取消（取消退材料, 钱和人工不退）
	_site_label = _mk_label("", 13, Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(_site_label)
	_site_cancel = Button.new()
	_site_cancel.text = "取消这块工地 (返还木头/石头/铁; 金币和已花人工不退)"
	_site_cancel.custom_minimum_size = Vector2(620, 32)
	_site_cancel.add_theme_font_override("font", PIXEL_FONT)
	_site_cancel.add_theme_font_size_override("font_size", 12)
	_site_cancel.pressed.connect(_on_site_cancel)
	wrap.add_child(_site_cancel)

	var intro := _mk_label("选建筑 -> 回地图摆放: 左键放置 / 右键取消", 12,
		Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(intro)

	_build_info = _mk_label("", 13, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(_build_info)

	# e44 建筑模式：已盖好的建筑可以随便挪地方（不花钱不扣料, 等级/鸡/蜂蜜都跟着走）
	_move_btn = Button.new()
	_move_btn.text = "建筑模式 -- 随意搬动已盖好的建筑 (不花钱)"
	_move_btn.custom_minimum_size = Vector2(620, 34)
	_move_btn.add_theme_font_override("font", PIXEL_FONT)
	_move_btn.add_theme_font_size_override("font_size", 13)
	_move_btn.pressed.connect(_on_move_mode)
	wrap.add_child(_move_btn)
	wrap.add_child(_mk_label("点它回地图: 左键点建筑拾起来 / 再左键放下 / 右键放回原处或退出",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# e28f: 建筑升级区 —— 铁匠铺升级从「站旁边按 F」搬进背包, 建造页也能花钱提级
	wrap.add_child(_mk_label("-- 建筑升级 --", 13, Color(1, 0.92, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER))
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 4)
	wrap.add_child(_upgrade_box)

	for kind in Structures.BUILDINGS:
		var info: Dictionary = Structures.BUILDINGS[kind]
		wrap.add_child(_mk_label("%s -- %s" % [info["name"], info["desc"]],
			13, Color(0.95, 0.9, 0.8)))
		var cost_text := "金币 %d   木头 %d   石头 %d   铁 %d   劳动力 %d" \
			% [int(info["coin"]), int(info["wood"]), int(info["stone"]),
			int(info["iron"]), int(info["labor"])]
		var row := Button.new()
		row.text = "选位置   " + cost_text
		row.custom_minimum_size = Vector2(620, 34)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_override("font", PIXEL_FONT)
		row.add_theme_font_size_override("font_size", 13)
		row.pressed.connect(_on_build_pick.bind(kind))
		wrap.add_child(row)
		_build_rows[kind] = row

	wrap.add_child(_mk_label("劳动力: 点建造当天占用, 第二天早上伙伴回归",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	return wrap

func _refresh_build() -> void:
	var g: Node = get_tree().get_first_node_in_group("game")
	for kind in _build_rows:
		var btn: Button = _build_rows[kind]
		var ok: bool = g != null and g.has_method("_can_pay_build") \
			and g._can_pay_build(kind)
		btn.disabled = not ok
		btn.modulate = Color(1, 1, 1) if ok else Color(0.75, 0.72, 0.7)
	# e24c: 当前工地进度 + 取消按钮（没有工地就藏起来）
	if Structures.site_busy():
		_site_label.text = "当前工地: %s  进度 %d/%d 人天" % [
			Structures.site_name(), int(Structures.site["work"]), int(Structures.site["need"])]
		_site_label.visible = true
		_site_cancel.visible = true
	else:
		_site_label.visible = false
		_site_cancel.visible = false
	# e44: 岛上连一座能搬的建筑都没有（只有工作台/熔炉）就把入口灰掉
	if _move_btn != null:
		_move_btn.disabled = not Structures.has_movable()
		_move_btn.modulate = Color(1, 1, 1) if not _move_btn.disabled else Color(0.75, 0.72, 0.7)
	_refresh_upgrades()   # e28f: 建筑升级列表跟着刷

# e44 建筑模式：关掉背包, 回地图上搬建筑（拾起/放下的交互在 game 里）
func _on_move_mode() -> void:
	var g: Node = get_tree().get_first_node_in_group("game")
	if g == null or not g.has_method("start_move_mode"):
		return
	g.start_move_mode()
	close()

# e24c: 取消工地 —— 材料全额退回背包（金币和已花的人工不退, 跟拆房同一套规矩）
func _on_site_cancel() -> void:
	var cost: Dictionary = Structures.cancel_site()
	if cost.is_empty():
		return
	for key in ["wood", "stone", "iron"]:
		var n := int(cost.get(key, 0))
		if n > 0:
			Inventory.add_item(load("res://item/%s.tres" % key), n)
	Audio.play_sfx("bin")
	_refresh_build()

# e28f: 建筑升级列表 —— 每次刷新整段重建（仿派活面板 _rebuild_dock 的做法）。
# 目前能升的只有铁匠铺（Lv.1-3, 一级比一级贵 150*现级）, 其余建筑没有等级概念。
func _refresh_upgrades() -> void:
	if _upgrade_box == null:
		return
	for c in _upgrade_box.get_children():
		_upgrade_box.remove_child(c)
		c.queue_free()
	var any := false
	for c in Structures.stations.keys():
		if String(Structures.stations[c]["kind"]) != Structures.KIND_BLACKSMITH:
			continue
		any = true
		var lv := Structures.level_of(c)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := _mk_label("铁匠铺 Lv.%d -- 等级越高能打越好的甲" % lv, 13,
			Color(0.95, 0.9, 0.8))
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(230, 30)
		btn.add_theme_font_override("font", PIXEL_FONT)
		btn.add_theme_font_size_override("font_size", 13)
		if lv >= 3:
			btn.text = "已满级"
			btn.disabled = true
		else:
			btn.text = "升级到 Lv.%d (金币 %d)" % [lv + 1, 150 * lv]
			btn.pressed.connect(_on_upgrade_station.bind(c))
		row.add_child(btn)
		_upgrade_box.add_child(row)
	if not any:
		_upgrade_box.add_child(_mk_label("还没有铁匠铺 -- 在下面盖一座, 就能在这儿升级",
			12, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

# e28f: 背包里直接升级铁匠铺（跟站旁边按 F 同价同效: 150*现级, set_level+1）
func _on_upgrade_station(c: Vector2i) -> void:
	var lv := Structures.level_of(c)
	if lv >= 3:
		return
	var up_fee := 150 * lv
	if Wallet.spend_money(up_fee):
		Structures.set_level(c, lv + 1)
		Audio.play_sfx("coin", -4.0)
		if _build_info != null:
			_build_info.text = "叮! 铁匠铺升到 Lv.%d (花了 %d 金), 能打更高档的甲了" % [lv + 1, up_fee]
	else:
		Audio.play_sfx("error", -6.0)
		if _build_info != null:
			_build_info.text = "金币不够 -- 铁匠铺升级要 %d 金" % up_fee
	_refresh_build()

func _on_build_pick(kind: String) -> void:
	var g: Node = get_tree().get_first_node_in_group("game")
	if g == null or not g.has_method("start_build_mode"):
		return
	if g.start_build_mode(kind):
		Audio.play_sfx("ui_click")
		close()
	else:
		Audio.play_sfx("error", -6.0)
		if _build_info != null:
			_build_info.text = "金币 / 材料 / 空闲劳动力不够 -- 先攒一攒"

# ---------------- 设置页 ----------------
func _build_settings_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	var bgm := CheckButton.new()
	bgm.text = "背景音乐(白天/夜晚自动换曲)"
	bgm.button_pressed = _bgm_on
	bgm.add_theme_font_override("font", PIXEL_FONT)
	bgm.add_theme_font_size_override("font_size", 13)
	bgm.toggled.connect(_on_bgm_toggled)
	wrap.add_child(bgm)

	# (e17: 战役慢动作倍率按钮已删 —— 减速改成「选中编队指挥时固定 0.1x」,
	#  下令后自动恢复常速, 不再有档位可调)

	wrap.add_child(_mk_label("镜头:Ctrl + 滚轮缩放视角    背包:B 或 Esc",
		12, Color(0.78, 0.74, 0.66)))

	# ---------- 存档：这页只说明时机 + 留一个回主页面的出口 ----------
	# ❗读档列表原本在这儿（列每日快照）。现在统一收在开始界面：
	#   主页面能看档名、看进度、读档、删档，入口一处就够，玩家不用记两个地方。
	wrap.add_child(_mk_label("-- 存档 --", 14, Color(1, 0.92, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER))
	wrap.add_child(_mk_label("每天早上 6 点自动存一次(睡完觉换日那一刻)",
		11, Color(0.7, 0.66, 0.58), HORIZONTAL_ALIGNMENT_CENTER))
	var back_btn := Button.new()
	back_btn.text = "返回主页面"
	back_btn.custom_minimum_size = Vector2(0, 30)
	back_btn.add_theme_font_override("font", PIXEL_FONT)
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.pressed.connect(_on_back_to_menu)
	wrap.add_child(back_btn)
	wrap.add_child(_mk_label("读档 / 开新档都在主页面的'加载存档'里",
		11, Color(0.62, 0.58, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	return wrap

# 回主页面（开始界面）。读档不在这页做了 —— 统一挪回主页面。
# ❗这里**不存盘**：存档时机有且只有每天早上 6 点那一次。
#   所以白天退回主页面 = 丢当天的进度、回到最近那个早上 6 点，这是故意的。
func _on_back_to_menu() -> void:
	Audio.play_sfx("ui_click")
	Audio.set_scene_bgm("")          # 万一停在海图/战场，把定曲交还给昼夜
	close()
	# d9: iris 收黑后再回主页面
	IRIS.play("out", func() -> void:
		get_tree().change_scene_to_file("res://scene/main_menu.tscn"))

func _on_bgm_toggled(on: bool) -> void:
	_bgm_on = on
	if on:
		Audio._sync_bgm()
	else:
		Audio.stop_bgm()
	Audio.play_sfx("ui_click", -8.0)

# ---------------- 占位页 ----------------
func _build_placeholder(text: String) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	var l := _mk_label(text, 13, Color(0.8, 0.76, 0.68), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 60)
	wrap.add_child(l)
	return wrap

func _mk_label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# ---------------- 外交页 ----------------
# 五国卡片都在 diplomacy_ui.gd（它自己接 Nations/Wallet 的变化信号）；
# 这里只负责实例化，切页时再刷一遍
func _build_diplomacy_page() -> Control:
	var p: Control = DIPLOMACY_PAGE.new()
	# 内容盒比页高时，得让页把剩余高度吃满 —— 不然 VBox 只分给它 min 高（0），
	# 里面的滚动容器跟着 0 高，五国卡片全画不出来（页面看着就是空的）
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return p

func _refresh_diplomacy() -> void:
	var p: Control = _pages.get("diplomacy")
	if p != null and p.has_method("_rebuild"):
		p.call("_rebuild")

# ---------------- 模块切换 ----------------
func _select_module(key: String) -> void:
	if key == _current:
		return
	Audio.play_sfx("ui_click", -10.0)
	_switch_to(key)

func _switch_to(key: String) -> void:
	_current = key
	# 科技/行政/团队页内容多，把内容盒撑大；其它页收回按内容自适应
	if _box != null:
		var sz: Vector2 = PAGE_SIZES.get(key, Vector2.ZERO)
		# 内容盒再想要多大，也不能把面板顶出屏幕：视口高 - 页签行(30) - 间距(8) - 余量
		# ❗hero 页 620 + 页签 38 = 658 > 默认视口 648，整块面板被顶出屏幕下沿。
		sz.y = minf(sz.y, get_viewport_rect().size.y - 60.0)
		_box.custom_minimum_size = sz
	for k in _pages.keys():
		var p: Control = _pages[k]
		p.visible = (k == key)
	for k in _tab_btns.keys():
		var b: Button = _tab_btns[k]
		b.modulate = Color(1, 1, 1) if k == key else Color(0.68, 0.65, 0.6)
		if k == key:
			b.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
		else:
			b.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62))
	for m in MODULES:
		if m["key"] == key:
			_title.text = str(m["name"])
			_hint.text = str(m["hint"])
	# 每页打开时刷一次自己的内容
	_refresh_page(key)
	page_changed.emit(key)

func _refresh_page(key: String) -> void:
	match key:
		"bag":
			_refresh()
		"hero":
			_refresh_hero()
		"team":
			_refresh_team()
		"battle":
			_refresh_battle()
		"map":
			_refresh_map_page()
		"craft":
			_refresh_craft()
		"build":
			_refresh_build()
		"tech":
			_refresh_tech()
		"admin":
			_refresh_admin()
		"diplomacy":
			_refresh_diplomacy()
		"set":
			pass      # 设置页没有要刷新的东西（读档列表搬去主页面后只剩几排静态开关）

# 地图页每次切过来都重画一遍：地形（新锄的地/刚播的种）和岛的范围都可能有变化
func _refresh_map_page() -> void:
	if _map_page == null:
		return
	var g: Node = get_tree().get_first_node_in_group("game")
	if g == null:
		return
	var box := _map_box_size()
	_map_page.custom_minimum_size = box
	if _map_page.game == null or _map_page.map_from != Slaves.map_from \
			or _map_page.map_to != Slaves.map_to:
		_map_page.setup(g, Slaves.map_from, Slaves.map_to, box)
	else:
		_map_page.refresh(box)

func _refresh_hero() -> void:
	if _hero_info == null:
		return
	_hero_info.text = "农场主  Lv.%d   经验 %d/%d   技能点 %d\n" \
		% [Legion.level, Legion.exp, Legion.exp_next(), Legion.skill_points] \
		+ "攻击 %d    血量 %d/%d    第 %d 天\n" \
		% [Legion.player_atk(), Legion.player_hp, Legion.player_max_hp(), TimeManager.day] \
		+ "伙伴 %d 人\n" % Slaves.count \
		+ "金币 %d" % Wallet.money
	# e20: 技能树状图刷新（替代旧的三行卡片）
	if _skill_tree != null:
		_skill_tree.refresh()

func _refresh_team() -> void:
	if _team_info == null:
		return
	var nums := [Slaves.count, Slaves.budget(), Slaves.used(), Slaves.done_today.size()]
	for i in _team_stats.size():
		if i < nums.size():
			(_team_stats[i] as Label).text = str(nums[i])
	_team_info.text = "可派 %d 格 - 已派 %d 格 (还剩 %d)   今天已干完 %d 格" % [
		Slaves.budget(), Slaves.used(), Slaves.remaining(), Slaves.done_today.size()]
	_refresh_slave_list()
	_refresh_class_trees()       # 树的皮肤跟晋升对象 / 钱料对齐
	# 详情面板开着时也同步刷一下（喂食/改名/加好感后回到列表能看到新值）
	if _detail_panel != null and _detail_panel.visible:
		_refresh_slave_detail()

# ═══════════════ 技能树视图（e20: 跟科技树一样摆开, 替代旧的三行卡片）═══════════════
# 五条主干各一棵横树: 主干 Lv1..5 一排 → 5 级分叉 → A/B 两排各 Lv6..10。
# 节点状态: 金底=已点亮 / 绿边=下一个可点(点它升级) / 青边=5 级选支 / 灰=未解锁。
# 5 级未选支时 A/B 首节点就是「选支」按钮, 点了锁死另一条(老规矩)。
class SkillTreeView:
	extends Control

	const FONT := preload("res://resources/font/IPix.ttf")
	const NODE_W := 56.0
	const NODE_H := 22.0
	const GAP_X := 64.0
	const ROW_H := 100.0
	const LEFT_X := 96.0
	const FORK_DY := 24.0

	signal node_clicked(id: String, which: String)   # which="" 升级 / "a"/"b" 选支

	func _init() -> void:
		# 与 _build_hero_page 里的覆盖值保持一致（760, 508）：宽度到第 9 列节点，
		# 高度 = 22 顶距 + 5x100 行距 + 24 分叉下探 + 22 节点高 + 行底小字
		custom_minimum_size = Vector2(760, 508)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func refresh() -> void:
		queue_redraw()

	# 第 idx 棵树的局部原点 y
	func _origin(idx: int) -> float:
		return 22.0 + float(idx) * ROW_H

	# 节点矩形: kind="trunk"(主干 Lv1..5) / "branch"(支线 Lv6..10, which="a"/"b")
	func _rect(id: String, kind: String, which: String, t: int) -> Rect2:
		var row := 0
		for key in Legion.SKILLS.keys():
			if String(key) == id:
				break
			row += 1
		var oy := _origin(row)
		if kind == "trunk":
			return Rect2(LEFT_X + float(t) * GAP_X, oy, NODE_W, NODE_H)
		return Rect2(LEFT_X + float(Legion.SKILL_SPLIT + t) * GAP_X,
			oy - FORK_DY if which == "a" else oy + FORK_DY, NODE_W, NODE_H)

	func _draw() -> void:
		var ids: Array = Legion.SKILLS.keys()
		for row in ids.size():
			var id: String = String(ids[row])
			var info: Dictionary = Legion.SKILLS[id]
			var oy := _origin(row)
			var lv := Legion.skill_lv(id)
			var br := Legion.branch_of(id)
			# 主干名
			draw_string(FONT, Vector2(6, oy + 6), String(info["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, 84, 13, Color(0.95, 0.86, 0.62))
			# 主干连线
			for t in Legion.SKILL_SPLIT - 1:
				var a := _rect(id, "trunk", "", t)
				var b := _rect(id, "trunk", "", t + 1)
				draw_line(Vector2(a.end.x, a.get_center().y),
					Vector2(b.position.x, b.get_center().y),
					Color(0.5, 0.42, 0.3), 2.0)
			# 分叉连线: 主干末节点 → A 首 / B 首(曼哈顿)
			var last := _rect(id, "trunk", "", Legion.SKILL_SPLIT - 1)
			var fa := _rect(id, "branch", "a", 0)
			var fb := _rect(id, "branch", "b", 0)
			var fork_x := last.end.x + 16.0
			var mid := Vector2(fork_x, last.get_center().y)
			draw_line(Vector2(last.end.x, last.get_center().y), mid,
				Color(0.5, 0.42, 0.3), 2.0)
			draw_line(mid, Vector2(fork_x, fa.get_center().y), Color(0.5, 0.42, 0.3), 2.0)
			draw_line(Vector2(fork_x, fa.get_center().y), fa.position, Color(0.5, 0.42, 0.3), 2.0)
			draw_line(mid, Vector2(fork_x, fb.get_center().y), Color(0.5, 0.42, 0.3), 2.0)
			draw_line(Vector2(fork_x, fb.get_center().y), fb.position, Color(0.5, 0.42, 0.3), 2.0)
			# 主干节点
			for t in Legion.SKILL_SPLIT:
				_draw_node(id, "trunk", "", t, lv, br, info)
			# 分支节点
			for t in Legion.SKILL_MAX - Legion.SKILL_SPLIT:
				_draw_node(id, "branch", "a", t, lv, br, info)
				_draw_node(id, "branch", "b", t, lv, br, info)
			# e24: 行底收益标注 —— 主干每级收益 + 已选/两条分支的收益
			# (行内节点带占 oy-24..oy+46, oy+56 往下是行间空带, 正好放一行小字)
			var tip := String(info["desc"])
			var a_info: Dictionary = info["a"]
			var b_info: Dictionary = info["b"]
			if br == "a":
				tip += "   |   %s: %s" % [String(a_info["name"]), String(a_info["desc"])]
			elif br == "b":
				tip += "   |   %s: %s" % [String(b_info["name"]), String(b_info["desc"])]
			else:
				tip += "   |   %s: %s  /  %s: %s" % [String(a_info["name"]),
					String(a_info["desc"]), String(b_info["name"]), String(b_info["desc"])]
			draw_string(FONT, Vector2(LEFT_X, oy + 66), tip,
				HORIZONTAL_ALIGNMENT_LEFT, 660, 10, Color(0.72, 0.66, 0.52))

	func _node_state(id: String, kind: String, which: String, t: int,
			lv: int, br: String) -> Dictionary:
		# 返回 {lit, clickable, dim, text}
		var absolute := t + 1 if kind == "trunk" else Legion.SKILL_SPLIT + t + 1
		var lit := lv >= absolute
		var dim := false
		var clickable := false
		var text := "Lv.%d" % absolute
		if kind == "branch":
			var bn: Dictionary = Legion.SKILLS[id][which]
			text = "%s %d" % [String(bn["name"]), absolute]
			if br != "" and br != which:
				dim = true                     # 没选的那条整排褪色
		if lit:
			return {"lit": true, "clickable": false, "dim": dim, "text": text}
		var sp := Legion.skill_points > 0
		if lv < Legion.SKILL_SPLIT:
			# 主干区: 下一个 = 第 lv+1 级(分支节点全锁)
			if kind == "trunk" and t == lv and sp:
				clickable = true
		else:
			if br == "":
				# 5 级未选支: A/B 首节点 = 选支按钮
				if kind == "branch" and t == 0 and sp:
					clickable = true
					text = "选 %s" % which.to_upper()
			else:
				# 已选支: 选中那条的下一个可升
				if kind == "branch" and which == br and t == lv - Legion.SKILL_SPLIT and sp:
					clickable = true
		return {"lit": false, "clickable": clickable, "dim": dim, "text": text}

	func _draw_node(id: String, kind: String, which: String, t: int,
			lv: int, br: String, info: Dictionary) -> void:
		var r := _rect(id, kind, which, t)
		var st: Dictionary = _node_state(id, kind, which, t, lv, br)
		var bg := Color(0.32, 0.30, 0.27)
		var border := Color(0.45, 0.40, 0.34)
		var txt := Color(0.62, 0.58, 0.52)
		if bool(st["lit"]):
			bg = Color(0.85, 0.68, 0.25)
			border = Color(0.55, 0.40, 0.10)
			txt = Color(0.25, 0.16, 0.05)
		elif bool(st["clickable"]):
			bg = Color(0.30, 0.42, 0.30)
			border = Color(0.55, 0.9, 0.45)
			txt = Color(0.9, 0.95, 0.85)
		if bool(st["dim"]):
			bg.a = 0.4
			border.a = 0.3
			txt.a = 0.35
		draw_rect(r, bg)
		draw_rect(r, border, false, 2.0)
		var ts := FONT.get_string_size(String(st["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(FONT, Vector2(r.position.x + (r.size.x - ts.x) * 0.5,
			r.position.y + r.size.y * 0.5 + 4.0), String(st["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, txt)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var ids: Array = Legion.SKILLS.keys()
		for row in ids.size():
			var id: String = String(ids[row])
			var lv := Legion.skill_lv(id)
			var br := Legion.branch_of(id)
			for t in Legion.SKILL_SPLIT:
				if _rect(id, "trunk", "", t).has_point(mb.position):
					var st: Dictionary = _node_state(id, "trunk", "", t, lv, br)
					if bool(st["clickable"]):
						node_clicked.emit(id, "")
					return
			for which in ["a", "b"]:
				for t in Legion.SKILL_MAX - Legion.SKILL_SPLIT:
					if _rect(id, "branch", which, t).has_point(mb.position):
						var st2: Dictionary = _node_state(id, "branch", which, t, lv, br)
						if bool(st2["clickable"]):
							# 5 级未选支时 A/B 首节点 = 选支(发 which); 已选支 = 升级(发 "")
							node_clicked.emit(id, which if (lv >= Legion.SKILL_SPLIT
								and br == "") else "")
						return

# ---------------- 职业树（e12: 像科技树那样摆开两棵树, 点节点转职） ----------------
# 把伙伴上下文（走过链 / 当前职业 / 可转列表 / 钱料够不够）喂给两棵树并刷新提示行
func _refresh_class_trees() -> void:
	if _combat_tree == null or _labor_tree == null:
		return
	var chain_c: Array = []
	var chain_l: Array = []
	var tg_c: Array = []
	var tg_l: Array = []
	var aff_c := {}
	var aff_l := {}
	var cur_c := ""
	var cur_l := ""
	var has_target := _last_slave >= 0 and _last_slave < Slaves.slaves.size()
	if has_target:
		var s: Dictionary = Slaves.slave_at(_last_slave)
		cur_c = String(s["troop"])
		cur_l = String(s["labor"])
		var x := cur_c
		while x != "":
			chain_c.push_front(x)
			x = Slaves.prev_of(x)
		x = cur_l
		while x != "":
			chain_l.push_front(x)
			x = Slaves.labor_prev_of(x)
		for t in Slaves.promote_targets(s):
			tg_c.append(String(t))
			aff_c[String(t)] = Slaves.can_afford(Slaves.CLASSES[String(t)]["cost"])
		for t in Slaves.labor_targets(s):
			tg_l.append(String(t))
			aff_l[String(t)] = Slaves.can_afford(Slaves.LABOR_CLASSES[String(t)]["cost"])
	_combat_tree.set_target(chain_c, cur_c, tg_c, aff_c)
	_labor_tree.set_target(chain_l, cur_l, tg_l, aff_l)
	if _tree_target != null:
		if has_target:
			var s2: Dictionary = Slaves.slave_at(_last_slave)
			_tree_target.text = "晋升对象: %s (战斗 %s / 劳动 %s) - 点树上的职业就能转职" \
				% [s2["name"], s2["troop"], s2["labor"]]
		else:
			_tree_target.text = "先在下面点开一个伙伴, 这两棵树才会挂到他身上"

# 点树上的职业节点：给晋升对象转职（战斗/劳动两树共用）
func _on_class_node_clicked(cname: String, labor: bool) -> void:
	if _last_slave < 0 or _last_slave >= Slaves.slaves.size():
		_tree_prompt("先点伙伴卡打开详情, 再点树上的职业转职")
		return
	var s: Dictionary = Slaves.slave_at(_last_slave)
	var now := String(s["labor"]) if labor else String(s["troop"])
	if cname == now:
		_tree_prompt("%s 已经是 %s 了" % [str(s["name"]), cname])
		return
	var targets: Array = Slaves.labor_targets(s) if labor else Slaves.promote_targets(s)
	if not targets.has(cname):
		_tree_prompt("%s 不在 %s 的%s晋升线上" % [cname, now, "劳动" if labor else "战斗"])
		return
	var table: Dictionary = Slaves.LABOR_CLASSES if labor else Slaves.CLASSES
	var ok := Slaves.promote_labor(_last_slave, cname) if labor \
		else Slaves.promote(_last_slave, cname)
	if ok:
		Audio.play_sfx("coin", -4.0)
		_tree_prompt("%s 转职成功: %s -> %s" % [str(s["name"]), now, cname])
		_refresh_team()
	else:
		Audio.play_sfx("error", -6.0)
		_tree_prompt("钱料不够: %s 要 %s" % [cname, Slaves.cost_text(table[cname]["cost"])])

func _tree_prompt(text: String) -> void:
	if _tree_target != null:
		_tree_target.text = text

# ---------------- 背包格子 ----------------
func _slot_style(is_hotbar: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if is_hotbar:
		sb.bg_color = Color(0.22, 0.18, 0.14, 0.9)
		sb.border_color = Color(0.6, 0.48, 0.34)
	else:
		sb.bg_color = Color(0.16, 0.14, 0.12, 0.9)
		sb.border_color = Color(0.4, 0.35, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	return sb

func _selected_slot_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.4, 0.32, 0.2, 0.95)
	sb.border_color = Color(1, 0.85, 0.4)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	return sb

func _refresh() -> void:
	if _grid == null:
		return
	var list := Inventory.slot_list()
	for i in list.size():
		var panel: PanelContainer = _panels[i]
		var icon: TextureRect = panel.get_meta("icon")
		var label: Label = panel.get_meta("label")
		var s: Dictionary = list[i]
		if s["item"] != null:
			icon.texture = s["item"].icon
			label.text = str(s["count"]) if s["count"] > 1 else ""
			# e8: 穿戴中的盔甲金色高亮 + 悬浮提示带一句（再右键就脱下）
			var worn_now: bool = Inventory.worn_armor != null \
				and s["item"] == Inventory.worn_armor
			icon.modulate = Color(1.0, 0.88, 0.45) if worn_now else Color.WHITE
			panel.tooltip_text = s["item"].info_text() \
				+ ("\n[穿戴中] 右键脱下" if worn_now else "")
		else:
			icon.texture = null
			label.text = ""
			icon.modulate = Color.WHITE
			panel.tooltip_text = ""
	_update_drag_highlight()
	if _current == "team":
		_refresh_team()
	elif _current == "hero":
		_refresh_hero()

func _update_drag_highlight() -> void:
	for i in _panels.size():
		var panel: PanelContainer = _panels[i]
		if _drag_from == i:
			panel.add_theme_stylebox_override("panel", _selected_slot_style())
		else:
			panel.add_theme_stylebox_override("panel", _slot_style(i < Inventory.HOTBAR_SIZE))

func _on_slot_input(event: InputEvent, index: int) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	# e8: 右键 = 穿戴 / 脱下盔甲（战斗里伙伴披的就是这件）
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_toggle_wear(index)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drag_from == -1:
		# 第一次点击：选中要移动的格子（格子里得有东西）
		var s: Dictionary = Inventory.get_slot(index)
		if s["item"] == null:
			return
		_drag_from = index
		Audio.play_sfx("ui_click")
		_update_drag_highlight()
	else:
		# 第二次点击：执行移动/合并
		if _drag_from == index:
			_drag_from = -1
			_update_drag_highlight()
			return
		Inventory.move_slot(_drag_from, index)
		_drag_from = -1
		Audio.play_sfx("ui_click")
		_update_drag_highlight()

# e46 一键整理（背包页那颗按钮）：快捷栏 + 背包一起排 ——
# 排完工具会落到最前面的快捷栏里, 按 1~6 直接拿。储物箱面板里有同款「整理背包」。
func _on_sort_bag() -> void:
	Inventory.sort_all()
	Audio.play_sfx("ui_click")
	_refresh()

# e8: 右键盔甲 = 穿上 / 脱下。只认「装备」类型的盔甲（armor_tier > 0）,
# 穿哪件记在 Inventory.worn_armor —— battle_map 里主角方的甲全看它。
# 同一件再点一次右键就是脱下（道具本体始终留在背包格子里）。
func _toggle_wear(index: int) -> void:
	var s: Dictionary = Inventory.get_slot(index)
	var it: ItemData = s["item"]
	if it == null or String(it.type) != "装备" or int(it.armor_tier) <= 0:
		return
	Inventory.worn_armor = null if Inventory.worn_armor == it else it
	Legion.clamp_player_hp()      # 血上限跟着甲变了, 当前血别超出范围
	Audio.play_sfx("ui_click")
	_refresh()

# ---------------- 开合 ----------------
# e18f: A/D 左右切页签（game.gd 在背包开着时把 move_left/right 转发过来）, 循环
func cycle_tab(dir: int) -> void:
	var n := MODULES.size()
	for i in n:
		if String(MODULES[i]["key"]) == _current:
			_switch_to(String(MODULES[(i + dir + n) % n]["key"]))
			Audio.play_sfx("ui_click", -10.0)
			return

func toggle() -> void:
	if _visible:
		close()
	else:
		open()

# e30p: 对工作台/铁匠铺按 F 直达对应制造子页（"wb"/"smith"，缺省开在个人页）
func open_craft(sub: String = "base") -> void:
	open()
	_switch_to("craft")
	_select_craft_sub(sub)

func open() -> void:
	_visible = true
	_drag_from = -1
	_switch_to("bag")      # 每次打开都回到背包首页（上次关在团队/科技页也不带回来）
	_refresh()
	show()
	TimeManager.push_ui_pause()      # 翻背包的时候时间停住
	Audio.play_sfx("ui_open")
	opened.emit()

func close() -> void:
	if not _visible:
		return
	_visible = false
	_drag_from = -1
	if _detail_panel != null and _detail_panel.visible:
		_close_slave_detail()      # e24: Esc 直接关栏时, 详情浮层一起收起来
	hide()
	TimeManager.pop_ui_pause()
	Audio.play_sfx("ui_close")
	closed.emit()

func is_open() -> bool:
	return _visible


# ═══════════════ 科技/行政树视图（文明6 式）═══════════════
# 一整块 Control：tier 分列的节点卡片 + 前置连线 + 时代列标题 + 淡点阵底。
# 节点可点（点击 = 研究），状态四档：已研究金 / 可研究绿 / 点数未满米 / 前置未开灰。
# 布局算法：先把各列竖排，然后迭代几轮「子节点往父节点中线均值靠拢」，
# 同列按目标 y 排序后自上而下排（挤了就顺延），最后每列整体垂直居中 ——
# 数据量小，几轮就能摆出文明6 那种主干分叉的缠绕感。
# ============ 职业树视图（e12: 团队页两棵树, 摆法仿下面的 ResearchTreeView） ============
# 战斗树（新兵 -> 三岔 -> 二线 -> 满阶）/ 劳动树（帮工起步）都从 CLASSES 表自动推 tier。
# 节点皮肤按「晋升对象」画: 当前职业金边 / 走过的链亮棕 / 可转且钱够绿 / 可转缺钱暗黄 / 无关灰。
class ClassTreeView:
	extends Control

	const FONT := preload("res://resources/font/IPix.ttf")
	const COL_NAMES := ["起步", "一线", "二线", "三线", "四线"]
	# e27g: 尺寸改成变量 —— 详情弹窗里用窄版(compact)把两棵树收进 600 宽的卡片
	var NODE_W := 168.0
	var NODE_H := 42.0
	var COL_GAP := 44.0
	var ROW_GAP := 10.0
	var HEAD_H := 24.0
	var _name_fs := 13
	var _cost_fs := 10

	var labor := false
	var _cb: Callable
	var _cards := {}        # 职业名 -> PanelContainer
	var _rects := {}        # 职业名 -> Rect2
	var _tiers: Array = []  # 每层职业名列表（布局 + 列标题用）
	var _chain: Array = []  # 晋升对象走过的链（根 -> 当前）
	var _cur := ""          # 晋升对象当前职业
	var _targets: Array = []    # 可转职业
	var _afford := {}           # 职业 -> 钱料够不够

	func setup(is_labor: bool, cb: Callable, compact := false) -> void:
		labor = is_labor
		_cb = cb
		if compact:
			# e27g: 详情弹窗里的窄版 —— 卡片收窄/列距收紧/字号小一档
			NODE_W = 136.0
			NODE_H = 38.0
			COL_GAP = 18.0
			ROW_GAP = 8.0
			HEAD_H = 18.0
			_name_fs = 12
			_cost_fs = 9
		mouse_filter = Control.MOUSE_FILTER_PASS
		_build_cards()
		refresh()

	func _table() -> Dictionary:
		return Slaves.LABOR_CLASSES if labor else Slaves.CLASSES

	func _root_id() -> String:
		return "帮工" if labor else "新兵"

	func _prev_of(sid: String) -> String:
		return Slaves.labor_prev_of(sid) if labor else Slaves.prev_of(sid)

	# 外部把晋升对象的上下文喂进来（backpack_ui._refresh_class_trees）
	func set_target(chain: Array, cur: String, targets: Array, afford: Dictionary) -> void:
		_chain = chain
		_cur = cur
		_targets = targets
		_afford = afford
		refresh()

	func _build_cards() -> void:
		for c in get_children():
			c.queue_free()
		_cards.clear()
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(5)
			sb.set_border_width_all(2)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			panel.add_theme_stylebox_override("panel", sb)
			panel.gui_input.connect(_on_card_input.bind(sid))
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(v)
			# e52e: 名字行 = 小图标 + 职业名（图标 16x16 像素风, NEAREST 防糊）
			var name_row := HBoxContainer.new()
			name_row.add_theme_constant_override("separation", 4)
			name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(name_row)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(16, 16)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_row.add_child(icon)
			var name_l := _card_label(_name_fs)
			name_row.add_child(name_l)
			var cost_l := _card_label(_cost_fs)
			cost_l.clip_text = true
			v.add_child(cost_l)
			add_child(panel)
			_cards[sid] = panel
			panel.set_meta("name", name_l)
			panel.set_meta("icon", icon)
			panel.set_meta("cost", cost_l)

	func _card_label(sz: int) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", FONT)
		l.add_theme_font_size_override("font_size", sz)
		return l

	func _on_card_input(ev: InputEvent, sid: String) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _cb.is_valid():
				_cb.call(sid, labor)

	func refresh() -> void:
		var table := _table()
		_layout()
		for id in table.keys():
			var sid := String(id)
			if not _cards.has(sid):
				continue
			var panel: PanelContainer = _cards[sid]
			var on_chain: bool = _chain.has(sid)
			var is_cur := sid == _cur
			var is_target: bool = _targets.has(sid)
			# 四档皮肤: 当前金 / 可转(绿=钱够, 暗黄=缺钱) / 走过亮棕 / 无关灰
			var bg := Color(0.15, 0.125, 0.105, 0.98)
			var border := Color(0.34, 0.3, 0.26)
			var bw := 2
			var name_col := Color(0.62, 0.59, 0.54)
			if is_cur:
				bg = Color(0.34, 0.27, 0.12, 0.98)
				border = Color(1, 0.85, 0.4)
				bw = 3
				name_col = Color(1, 0.9, 0.55)
			elif is_target:
				if bool(_afford.get(sid, false)):
					bg = Color(0.13, 0.22, 0.11, 0.98)
					border = Color(0.55, 0.9, 0.45)
					bw = 3
					name_col = Color(0.78, 0.95, 0.62)
				else:
					bg = Color(0.2, 0.17, 0.1, 0.98)
					border = Color(0.72, 0.6, 0.34)
					name_col = Color(0.9, 0.84, 0.68)
			elif on_chain:
				bg = Color(0.22, 0.18, 0.13, 0.98)
				border = Color(0.85, 0.7, 0.35)
				name_col = Color(0.9, 0.84, 0.68)
			var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
			sb.bg_color = bg
			sb.border_color = border
			sb.set_border_width_all(bw)
			var name_l: Label = panel.get_meta("name")
			name_l.text = sid
			name_l.add_theme_color_override("font_color", name_col)
			# e52e: 职业小图 —— 表里没配或素材缺失时隐藏, 只留名字
			var ic: TextureRect = panel.get_meta("icon")
			ic.texture = Slaves.class_icon_for(sid)
			ic.visible = ic.texture != null
			var cost: Dictionary = table[sid]["cost"]
			var cost_l: Label = panel.get_meta("cost")
			var ct := Slaves.cost_text(cost)
			cost_l.text = "  " + (ct if ct != "" else "免费")
			cost_l.add_theme_color_override("font_color",
				name_col.darkened(0.22) if is_cur or is_target or on_chain
				else Color(0.5, 0.46, 0.42))
			panel.tooltip_text = "%s\n点一下 = 给晋升对象转到这份职业\n消耗: %s" \
				% [sid, ct if ct != "" else "免费"]
			panel.position = (_rects[sid] as Rect2).position
		queue_redraw()

	# 布局: 沿 next 推 tier 分列, 子节点往父节点中线靠（同 ResearchTreeView 的收法）
	func _layout() -> void:
		var table := _table()
		var tm := {_root_id(): 0}
		var frontier: Array = [_root_id()]
		var t := 0
		while not frontier.is_empty():
			t += 1
			var nxt: Array = []
			for f in frontier:
				for n in table[String(f)]["next"]:
					if not tm.has(n):
						tm[n] = t
						nxt.append(String(n))
			frontier = nxt
		var maxt := 0
		for id in tm:
			maxt = maxi(maxt, int(tm[id]))
		_tiers.clear()
		for i in maxt + 1:
			_tiers.append([])
		for id in tm:
			_tiers[int(tm[id])].append(String(id))
		for ti in _tiers.size():
			for i in (_tiers[ti] as Array).size():
				_rects[String(_tiers[ti][i])] = Rect2(
					ti * (NODE_W + COL_GAP), HEAD_H + i * (NODE_H + ROW_GAP), NODE_W, NODE_H)
		# 子节点往父节点中线靠, 同列挤了就顺延
		for _i in 3:
			var want := {}
			for id in tm:
				var sid := String(id)
				var req := _prev_of(sid)
				if req == "" or not _rects.has(req):
					continue
				want[sid] = (_rects[req] as Rect2).get_center().y - NODE_H * 0.5
			for ti in _tiers.size():
				var list: Array = _tiers[ti]
				list.sort_custom(func(a, b) -> bool:
					var wa: float = float(want.get(a, (_rects[a] as Rect2).position.y))
					var wb: float = float(want.get(b, (_rects[b] as Rect2).position.y))
					return wa < wb)
				var prev_bottom := -1.0e9
				for id in list:
					var sid := String(id)
					var rc: Rect2 = _rects[sid]
					rc.position.y = maxf(float(want.get(sid, rc.position.y)),
						prev_bottom + ROW_GAP)
					_rects[sid] = rc
					prev_bottom = rc.position.y + NODE_H
		var max_h := 0.0
		for ti in _tiers.size():
			var list: Array = _tiers[ti]
			max_h = maxf(max_h, (_rects[String(list[list.size() - 1])] as Rect2).end.y)
		var cols: int = _tiers.size()
		custom_minimum_size = Vector2(cols * (NODE_W + COL_GAP) - COL_GAP, max_h + 6.0)

	func _draw() -> void:
		var sz := custom_minimum_size
		var dot := Color(1, 1, 1, 0.045)
		var gx := 14.0
		while gx < sz.x:
			var gy := 14.0
			while gy < sz.y:
				draw_rect(Rect2(gx, gy, 1.5, 1.5), dot)
				gy += 26.0
			gx += 26.0
		# 列标题（起步/一线/二线/...）
		for ti in _tiers.size():
			var x := float(ti) * (NODE_W + COL_GAP)
			draw_rect(Rect2(x, 4, NODE_W - 10, 3), Color(0.45, 0.38, 0.26, 0.5))
			draw_string(FONT, Vector2(x, HEAD_H - 4.0),
				String(COL_NAMES[mini(ti, COL_NAMES.size() - 1)]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.62, 0.46))
		# 父 -> 子连线（曼哈顿折线 + 箭头）: 两端都在链上就描金
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var req := _prev_of(sid)
			if req == "" or not _rects.has(req):
				continue
			var ra: Rect2 = _rects[req]
			var rb: Rect2 = _rects[sid]
			var p0 := Vector2(ra.end.x, ra.get_center().y)
			var p3 := Vector2(rb.position.x, rb.get_center().y)
			var mid := (p0.x + p3.x) * 0.5
			var col := Color(0.33, 0.28, 0.21, 0.85)
			var w := 2.0
			var both_on: bool = _chain.has(sid) and (_chain.has(String(req)) or _cur == req)
			var gold: bool = _chain.has(sid) and _chain.has(String(req))
			if gold:
				col = Color(0.98, 0.83, 0.4, 0.95)
				w = 3.0
			elif _targets.has(sid):
				col = Color(0.5, 0.7, 0.38, 0.75) if bool(_afford.get(sid, false)) \
					else Color(0.72, 0.6, 0.34, 0.75)
			elif both_on:
				col = Color(0.85, 0.7, 0.35, 0.8)
			draw_line(p0, Vector2(mid, p0.y), col, w)
			draw_line(Vector2(mid, p0.y), Vector2(mid, p3.y), col, w)
			draw_line(Vector2(mid, p3.y), p3 + Vector2(2, 0), col, w)
			var tri := PackedVector2Array([
				p3 + Vector2(8, 0), p3 + Vector2(-1, -4.5), p3 + Vector2(-1, 4.5)])
			draw_colored_polygon(tri, col)

class ResearchTreeView:
	extends Control

	const FONT := preload("res://resources/font/IPix.ttf")

	const NODE_W := 174.0
	const NODE_H := 66.0
	const COL_GAP := 34.0        # 列间距（留出连线走廊）
	const ROW_GAP := 14.0
	const HEAD_H := 26.0         # 顶部：时代列标题占的高度

	const TIER_NAMES := {
		"tech": ["初启", "革新", "跃迁"],
		"admin": ["奠基", "建制", "扩张", "中枢"],
	}

	var kind := "tech"
	var _cb: Callable
	var _cards := {}             # id -> PanelContainer（节点卡）
	var _rects := {}             # id -> Rect2（当前布局）

	func setup(k: String, cb: Callable) -> void:
		kind = k
		_cb = cb
		mouse_filter = Control.MOUSE_FILTER_PASS
		_build_cards()
		refresh()

	func card_of(id: String) -> PanelContainer:
		return _cards.get(id)

	func _table() -> Dictionary:
		return Research.TECHS if kind == "tech" else Research.ADMINS

	func _done(id: String) -> bool:
		return Research.has_tech(id) if kind == "tech" else Research.has_admin(id)

	func _ready_ok(id: String) -> bool:
		return Research.tech_ready(id) if kind == "tech" else Research.admin_ready(id)

	func _can(id: String) -> bool:
		return Research.can_research_tech(id) if kind == "tech" \
			else Research.can_research_admin(id)

	func _summary(id: String) -> String:
		return Research.tech_summary(id) if kind == "tech" else Research.admin_summary(id)

	# ---------------- 建节点卡 ----------------
	func _build_cards() -> void:
		for c in get_children():
			c.queue_free()
		_cards.clear()
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(NODE_W, NODE_H)
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(5)
			sb.set_border_width_all(2)
			sb.content_margin_left = 9
			sb.content_margin_right = 9
			sb.content_margin_top = 5
			sb.content_margin_bottom = 5
			panel.add_theme_stylebox_override("panel", sb)
			panel.gui_input.connect(_on_card_input.bind(sid))
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			panel.mouse_entered.connect(_on_card_hover.bind(panel, true))
			panel.mouse_exited.connect(_on_card_hover.bind(panel, false))

			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(v)
			var nh := HBoxContainer.new()
			nh.add_theme_constant_override("separation", 5)
			nh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(nh)
			var icon := TextureRect.new()
			icon.texture = Research.icon_for(sid)
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(16, 16)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nh.add_child(icon)
			var name_l := _card_label(13)
			nh.add_child(name_l)
			var desc_l := _card_label(10)
			desc_l.clip_text = true
			v.add_child(desc_l)
			var st_l := _card_label(10)
			v.add_child(st_l)
			add_child(panel)
			_cards[sid] = panel
			panel.set_meta("name", name_l)
			panel.set_meta("desc", desc_l)
			panel.set_meta("state", st_l)

	func _card_label(sz: int) -> Label:
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", FONT)
		l.add_theme_font_size_override("font_size", sz)
		return l

	func _on_card_hover(panel: Control, over: bool) -> void:
		panel.modulate = Color(1.14, 1.12, 1.04) if over else Color(1, 1, 1)

	func _on_card_input(ev: InputEvent, id: String) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _cb.is_valid():
				_cb.call(id, kind)

	# ---------------- 刷新：重摆位置 + 换状态皮肤 ----------------
	func refresh() -> void:
		var table := _table()
		_layout()
		for id in table.keys():
			var sid := String(id)
			if not _cards.has(sid):
				continue
			var panel: PanelContainer = _cards[sid]
			var info: Dictionary = table[sid]
			var done := _done(sid)
			var ready := _ready_ok(sid)
			var can := _can(sid)
			# 四档配色
			var bg := Color(0.15, 0.125, 0.105, 0.98)
			var border := Color(0.34, 0.3, 0.26)
			var bw := 2
			var name_col := Color(0.62, 0.59, 0.54)
			var st_col := Color(0.5, 0.46, 0.42)
			if done:
				bg = Color(0.34, 0.27, 0.12, 0.98)
				border = Color(1, 0.85, 0.4)
				bw = 3
				name_col = Color(1, 0.9, 0.55)
				st_col = Color(0.95, 0.82, 0.45)
			elif can:
				bg = Color(0.13, 0.22, 0.11, 0.98)
				border = Color(0.55, 0.9, 0.45)
				bw = 3
				name_col = Color(0.78, 0.95, 0.62)
				st_col = Color(0.6, 0.9, 0.48)
			elif ready:
				bg = Color(0.19, 0.155, 0.11, 0.98)
				border = Color(0.72, 0.6, 0.34)
				name_col = Color(0.9, 0.84, 0.68)
				st_col = Color(0.8, 0.72, 0.55)
			var sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
			sb.bg_color = bg
			sb.border_color = border
			sb.set_border_width_all(bw)
			var name_l: Label = panel.get_meta("name")
			name_l.text = "%s  %d 点" % [info["name"], int(info["cost"])]
			name_l.add_theme_color_override("font_color", name_col)
			var desc_l: Label = panel.get_meta("desc")
			desc_l.text = "  " + str(info["desc"])
			desc_l.add_theme_color_override("font_color",
				Color(0.85, 0.76, 0.5) if done else name_col.darkened(0.22))
			var st_l: Label = panel.get_meta("state")
			st_l.text = "  " + _summary(sid)
			st_l.add_theme_color_override("font_color", st_col)
			panel.tooltip_text = "%s\n%s\n%s" % [info["name"], info["desc"], _summary(sid)]
			panel.position = (_rects[sid] as Rect2).position
		queue_redraw()

	# ---------------- 布局：tier 分列 + 朝父节点中线收敛 ----------------
	func _layout() -> void:
		var table := _table()
		var tiers := {}
		for id in table.keys():
			var t := int(table[id]["tier"])
			if not tiers.has(t):
				tiers[t] = []
			tiers[t].append(String(id))
		# 第一遍：每列自上而下堆
		for t in tiers.keys():
			var list: Array = tiers[t]
			for i in list.size():
				_rects[String(list[i])] = Rect2(
					(int(t) - 1) * (NODE_W + COL_GAP), HEAD_H + i * (NODE_H + ROW_GAP),
					NODE_W, NODE_H)
		# 迭代对齐：子节点往「各前置节点中线均值」靠，同列挤了就顺延
		for _i in 3:
			var want := {}
			for id in table.keys():
				var sid := String(id)
				var reqs: Array = table[sid]["req"]
				if reqs.is_empty():
					continue
				var sum := 0.0
				for r in reqs:
					sum += (_rects[String(r)] as Rect2).get_center().y
				want[sid] = sum / float(reqs.size()) - NODE_H * 0.5
			for t in tiers.keys():
				var list: Array = tiers[t]
				list.sort_custom(func(a, b) -> bool:
					var wa: float = float(want.get(a, (_rects[a] as Rect2).position.y))
					var wb: float = float(want.get(b, (_rects[b] as Rect2).position.y))
					return wa < wb)
				var prev_bottom := -1.0e9
				for id in list:
					var sid := String(id)
					var rc: Rect2 = _rects[sid]
					rc.position.y = maxf(float(want.get(sid, rc.position.y)),
						prev_bottom + ROW_GAP)
					_rects[sid] = rc
					prev_bottom = rc.position.y + NODE_H
		# 每列整体垂直居中（相对最高的那列）
		var max_h := 0.0
		for t in tiers.keys():
			var list: Array = tiers[t]
			max_h = maxf(max_h, (_rects[String(list[list.size() - 1])] as Rect2).end.y)
		for t in tiers.keys():
			var list: Array = tiers[t]
			var top := (_rects[String(list[0])] as Rect2).position.y
			var bottom := (_rects[String(list[list.size() - 1])] as Rect2).end.y
			var off := (max_h - (bottom - top)) * 0.5 - top
			for id in list:
				var sid := String(id)
				var rc: Rect2 = _rects[sid]
				rc.position.y += off
				_rects[sid] = rc
		var cols := tiers.keys().size()
		custom_minimum_size = Vector2(cols * (NODE_W + COL_GAP) - COL_GAP, max_h + 6.0)

	# ---------------- 画：点阵底 + 列标题 + 前置连线 + 箭头 ----------------
	func _draw() -> void:
		var sz := custom_minimum_size
		var dot := Color(1, 1, 1, 0.045)
		var gx := 14.0
		while gx < sz.x:
			var gy := 14.0
			while gy < sz.y:
				draw_rect(Rect2(gx, gy, 1.5, 1.5), dot)
				gy += 26.0
			gx += 26.0
		# 时代列标题（短横线 + 字）
		var names: Array = TIER_NAMES.get(kind, [])
		for t in names.size():
			var x := float(t) * (NODE_W + COL_GAP)
			draw_rect(Rect2(x, 4, NODE_W - 10, 3), Color(0.45, 0.38, 0.26, 0.5))
			draw_string(FONT, Vector2(x, 23), str(names[t]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.62, 0.46))
		# 前置连线：曼哈顿折线（右出 -> 中途拐 -> 左进）+ 箭头
		var table := _table()
		for id in table.keys():
			var sid := String(id)
			var done_id := _done(sid)
			for r in table[sid]["req"]:
				var rid := String(r)
				if not _rects.has(rid):
					continue
				var ra: Rect2 = _rects[rid]
				var rb: Rect2 = _rects[sid]
				var p0 := Vector2(ra.end.x, ra.get_center().y)
				var p3 := Vector2(rb.position.x, rb.get_center().y)
				var mid := (p0.x + p3.x) * 0.5
				var col := Color(0.33, 0.28, 0.21, 0.85)
				var w := 2.0
				if done_id and _done(rid):
					col = Color(0.98, 0.83, 0.4, 0.95)
					w = 3.0
				elif done_id or _done(rid):
					col = Color(0.85, 0.7, 0.35, 0.8)
				elif _ready_ok(sid):
					col = Color(0.5, 0.7, 0.38, 0.75)
				draw_line(p0, Vector2(mid, p0.y), col, w)
				draw_line(Vector2(mid, p0.y), Vector2(mid, p3.y), col, w)
				draw_line(Vector2(mid, p3.y), p3 + Vector2(2, 0), col, w)
				var tri := PackedVector2Array([
					p3 + Vector2(8, 0), p3 + Vector2(-1, -4.5), p3 + Vector2(-1, 4.5)])
				draw_colored_polygon(tri, col)
