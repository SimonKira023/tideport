# backpack_ui.gd —— Esc（或 B）打开的「模块面板」
#
# 上方是一排**模块选择**：背包 / 角色 / 团队 / 发展 / 地图 / 日历 / 制作 / 建造 / 外交 / 任务 / 设置。
# 「发展」里再分 战斗 / 科技 / 行政 三个子页。未解锁的模块灰掉 (见 Quests.MODULE_UNLOCK)。
#
# 目前真正有内容的：
#   · 背包   —— 快捷栏 + 背包 30 格，点两格交换/合并
#   · 团队管理 —— 看伙伴人数、派了多少活（**招募已从这一页去掉**：傍晚野外的篝火边按 F）
#   · 地图   —— 按真实地形实时画出来的岛（滚轮放缩 / 拖拽移动 / 黄点是自己、蓝点是伙伴）
#   · 日历   —— 四季 28 天一格, 粉色格子是伙伴生日（生日当天送东西好感增量翻倍）
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
const GIFT_PICKER := preload("res://gift_picker.gd")      # 赠送选物弹窗（团队详情页 / 对话窗共用）
const ROMANCE_UI := preload("res://romance_ui.gd")        # 恋爱界面弹窗（恋爱线互动）

# A3-1: 三个「树状图」视图拆到 scene/backpack/tree_views.gd（自包含 Control 子类）
const SkillTreeView = preload("res://scene/backpack/tree_views.gd").SkillTreeView
const ClassTreeView = preload("res://scene/backpack/tree_views.gd").ClassTreeView
const ResearchTreeView = preload("res://scene/backpack/tree_views.gd").ResearchTreeView

# 模块表：key / 名字 / 下面那行灰字说明
const MODULES := [
	{"key": "bag",   "name": "背包",     "hint": "点击两格交换物品 / 右键盔甲穿戴或脱下  -  B / Esc 关闭"},
	{"key": "hero",  "name": "角色",     "hint": "属性 / 技能树 (首次收获后开放)"},
	{"key": "team",  "name": "团队",     "hint": "查看伙伴人数与今天的派活进度"},
	{"key": "grow",  "name": "发展",     "hint": "科技先开放, 修好码头后再准备战斗"},
	{"key": "map",   "name": "地图",     "hint": "滚轮放缩  /  按住左键或中键拖拽移动视角"},
	{"key": "calendar", "name": "日历",  "hint": "四季 28 天 - 粉色格子是伙伴的生日, 金边是今天 (安顿住处后开放)"},
	{"key": "craft", "name": "制作",     "hint": "消耗材料做食物 / 地板 (首次浇水后开放)"},
	{"key": "build", "name": "建造",     "hint": "选建筑 -> 回地图摆放 (首次售卖后开放)"},
	{"key": "diplomacy", "name": "外交", "hint": "五国关系 / 送礼 / 签约 (第一次出海后开放)"},
	{"key": "quests", "name": "任务",    "hint": "点击任务切换追踪 / 查看操作和解锁条件"},
	{"key": "set",   "name": "设置",     "hint": "音乐 / 画面 / 返回主页面"},
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
	"grow": Vector2(1080, 620),
	"tech": Vector2(1080, 588),
	"admin": Vector2(1080, 610),
	"team": Vector2(1080, 620),
	"hero": Vector2(1080, 620),
	"battle": Vector2(1080, 600),
	"build": Vector2(760, 420),
	#"craft" 也定死高度：制作页三档配方叠起来比屏幕还高，靠下面的滚动兜底（不然面板顶穿屏幕下沿）
	"craft": Vector2(760, 430),
	"calendar": Vector2(820, 400),
	"diplomacy": Vector2(560, 560),
}
var _future_btn: Button
var _future_label: Label
var _growth_box: VBoxContainer
var _build_names := {}
var _tab_btns := {}             # key -> Button
var _pages := {}                # key -> Control (含 grow + battle/tech/admin 子页)
var _grow_sub := "tech"         # 发展页当前子页: battle / tech / admin
var _grow_sub_btns := {}        # 子页签按钮
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
var _detail_give_btn: Button = null
var _detail_like_label: Label = null          # 生日 + 爱好提示行
var _romance_btn: Button = null               # 恋爱线: 打开恋爱界面的按钮
var _rom_love_label: Label = null             # 恋爱线: 心动条
var _rom_status_label: Label = null           # 恋爱线: 状态行（未婚进度 / 已婚纪念）
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
	add_to_group("backpack_panel")
	# 见 shop_ui.gd 的注释：挂在 HUD(CanvasLayer) 下的 Control 默认是 0 尺寸，
	# 不自己声明全屏的话遮罩和居中都会失效（面板会挤在左上角）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_panel()
	Inventory.inventory_changed.connect(_refresh)
	Inventory.inventory_changed.connect(_refresh_craft)
	Quests.changed.connect(_refresh_module_tabs)

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
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_override("font", PIXEL_FONT)
		b.add_theme_font_size_override("font_size", 15)     # 2026-10-06: 页签字号 13 -> 15
		b.pressed.connect(_select_module.bind(m["key"]))
		tabs.add_child(b)
		_tab_btns[m["key"]] = b

	_future_btn = Button.new()
	_future_btn.text = "未来发展 (展开查看条件)"
	_future_btn.add_theme_font_override("font", PIXEL_FONT)
	_future_btn.add_theme_font_size_override("font_size", 12)
	outer.add_child(_future_btn)
	_future_label = _mk_label("", 12, Color(0.8, 0.75, 0.66), HORIZONTAL_ALIGNMENT_CENTER)
	_future_label.visible = false
	outer.add_child(_future_label)
	_future_btn.pressed.connect(func(): _future_label.visible = not _future_label.visible)
	# ---------- 下面：内容盒 ----------
	var box := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = UiStyle.INK
	box_style.border_color = UiStyle.EDGE
	box_style.set_border_width_all(1)
	box_style.border_width_top = 2
	box_style.set_corner_radius_all(2)
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
	_refresh_module_tabs()

# 每个模块一页；现在只做「背包 / 团队管理 / 地图 / 物品制作」四页有内容
func _build_page(key: String) -> Control:
	match key:
		"bag":
			return _build_bag_page()
		"team":
			return _build_team_page()
		"grow":
			return _build_grow_page()
		"map":
			return _build_map_page()
		"calendar":
			return _build_calendar_page()
		"craft":
			return _build_craft_page()
		"build":
			return _build_build_page()
		"hero":
			return _build_hero_page()
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
# 点树上条目弹出: 详细信息 + 效果明细 + 随研究解锁的战斗法术卡和部队牌（行政还列政策卡）
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
	sb.bg_color = Color(0.09, 0.07, 0.06, 1.0)   # b4: 全不透明, 杜绝背后页签文字透出成暗字
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
	# 随研究解锁的部队牌（一张研究可能解锁多张, 如枢密院同时给神机弩手和甲骑）
	var unit_ids: Array = []
	for uid in CardsData.UNLOCK.keys():
		if String(CardsData.UNLOCK[uid]["req"]) == _rsch_id:
			unit_ids.append(String(uid))
	if unit_ids.size() > 0:
		_rsch_box.add_child(_mk_label("--- 随研究的部队牌 ---", 12, Color(0.72, 0.64, 0.52),
			HORIZONTAL_ALIGNMENT_CENTER))
		for uid in unit_ids:
			var uc: Dictionary = CardsData.UNLOCK[uid]
			var kwt_u := _kw_text(String(uc["kw"]))
			var u_txt := "「%s」  %d费 %d/%d" % [uc["name"], int(uc["cost"]),
				int(uc["atk"]), int(uc["hp"])]
			if kwt_u != "":
				u_txt += " " + kwt_u
			u_txt += "  " + ("强力卡" if String(uc["rarity"]) == "strong" else "精英卡")
			_rsch_box.add_child(_mk_label(u_txt, 14, Color(0.98, 0.85, 0.45),
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
	# 未解锁的部队牌在描述里标出来源（随哪项科技/行政解锁）
	if not unlocked and String(id).begins_with("u_"):
		var req := String(CardsData.UNLOCK[String(id)]["req"])
		if Research.ADMINS.has(req) or Research.TECHS.has(req):
			var rname := String(Research.ADMINS[req]["name"]) if Research.ADMINS.has(req) else String(Research.TECHS[req]["name"])
			texts[1] = "%s (随%s解锁)" % [texts[1], rname]
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

	left.add_child(_mk_label("法术卡 -- 研究解锁 + 书院已建成才能编入 (书院是法术的来源)",
		12, Color(0.85, 0.78, 0.6)))
	var spell_grid := _mk_battle_grid()
	left.add_child(spell_grid)
	for id in CardsData.SPELLS.keys():
		_btl_rows[String(id)] = _add_deck_card(spell_grid, String(id))

	left.add_child(_mk_label("部队牌 -- 研究解锁 + 军营已建成才能编入 (强力卡限 4 张 / 精英卡限 2 张)",
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

	wrap.add_child(_mk_label("走近伙伴按 F 可以对话 (聊天不加好感, 赠送才加); 点伙伴卡看详情",
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
	var tex: Texture2D = preload("res://scene/mood_portrait.gd").tex_of("slave_%02d" % i)
	if tex != null:
		_portrait_cache[i] = tex
		return tex
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
	card.tooltip_text = "点开 %s 的详情 (赠送 / 改名 / 晋升)" % str(s["name"])

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
	sb.bg_color = Color(0.09, 0.07, 0.06, 1.0)   # b4: 全不透明, 杜绝背后页签文字透出成暗字
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

	# e30s: 详情页内容很高（两棵树 + 改名 + 赠送），直接塞进卡片会顶出屏幕底。
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

	var advanced := Button.new()
	advanced.text = "展开职业成长 (劳动 / 战斗)"
	advanced.add_theme_font_override("font", PIXEL_FONT)
	advanced.add_theme_font_size_override("font_size", 12)
	box.add_child(advanced)
	_growth_box = VBoxContainer.new()
	_growth_box.visible = false
	box.add_child(_growth_box)
	advanced.pressed.connect(func(): _growth_box.visible = not _growth_box.visible)
	var summary_box := box
	box = _growth_box
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

	box = summary_box
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

	# 生日 + 爱好一行（_refresh_slave_detail 里按当前伙伴填）
	_detail_like_label = _mk_label("", 12, Color(0.98, 0.78, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_detail_like_label)
	box.add_child(_mk_label("(好感线: 每天送一次礼, 挑背包里的作物/食物/材料送 Ta; 好感每 4 点换伙伴 1 点攻击)",
		11, Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_CENTER))

	# 赠送（打开选物弹窗 gift_picker, 从背包挑一份作物/食物/材料）
	var give_row := HBoxContainer.new()
	give_row.alignment = BoxContainer.ALIGNMENT_CENTER
	give_row.add_theme_constant_override("separation", 8)
	box.add_child(give_row)
	_detail_give_btn = Button.new()
	_detail_give_btn.text = "赠送 (从背包挑一份送 Ta)"
	_detail_give_btn.custom_minimum_size = Vector2(280, 30)
	_detail_give_btn.add_theme_font_override("font", PIXEL_FONT)
	_detail_give_btn.add_theme_font_size_override("font_size", 13)
	_detail_give_btn.pressed.connect(_on_give_pressed_detail)
	give_row.add_child(_detail_give_btn)

	# 恋爱线（只有六位可婚姑娘开放; 心里话开线后可做恋爱互动攒心动值）
	box.add_child(_mk_label("--- 恋爱线 ---", 12, Color(0.95, 0.66, 0.76),
		HORIZONTAL_ALIGNMENT_CENTER))
	_rom_love_label = _mk_label("", 13, Color(0.98, 0.75, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_rom_love_label)
	_rom_status_label = _mk_label("", 11, Color(0.80, 0.72, 0.68), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_rom_status_label)
	var rom_row := HBoxContainer.new()
	rom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rom_row.add_theme_constant_override("separation", 8)
	box.add_child(rom_row)
	_romance_btn = Button.new()
	_romance_btn.text = "恋爱互动 (牵手散步 / 月下相拥 ...)"
	_romance_btn.custom_minimum_size = Vector2(280, 30)
	_romance_btn.add_theme_font_override("font", PIXEL_FONT)
	_romance_btn.add_theme_font_size_override("font_size", 13)
	_romance_btn.pressed.connect(_on_romance_pressed_detail)
	rom_row.add_child(_romance_btn)

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
	if _growth_box != null:
		_growth_box.visible = false
	_detail_info_label.text = "好感 %s  %d/%d\n今天%s送过东西" % [
		hearts, aff, Slaves.AFFECTION_MAX,
		"" if bool(s.get("gift_today", false)) else "没",
	]
	# 生日 + 爱好一行（跟选物弹窗顶部提示同一口径）
	if _detail_like_label != null:
		var like := Slaves.like_of(_detail_index)
		_detail_like_label.text = "生日: %s    最喜欢: %s (送中好感 x2)" % [
			Slaves.birthday_text(_detail_index), like if like != "" else "(无)"]
	# 输入框默认填当前名（玩家可以编辑再点改名）
	if _detail_rename != null:
		_detail_rename.text = s["name"]
	# 赠送按钮：今天送过就灰掉
	if _detail_give_btn != null:
		_detail_give_btn.disabled = bool(s.get("gift_today", false))
		_detail_give_btn.modulate = Color(0.7, 0.7, 0.7) if bool(s.get("gift_today", false)) else Color(1, 1, 1)
	# 恋爱线区：按这位伙伴的身份填（已婚 / 恋爱线开放 / 只是并肩伙伴）
	var sid := Slaves.roster_id(_detail_index)
	if _romance_btn != null and _rom_love_label != null and _rom_status_label != null:
		if Marriage.is_married_to(sid):
			var pk: Dictionary = Marriage.perk()
			_rom_love_label.text = "心动 %d/%d" % [Marriage.love_of(sid), Marriage.LOVE_MAX]
			_rom_status_label.text = "已婚 第 %d 天  专属: %s" % [Marriage.married_day,
				String(pk.get("desc", "")) if not pk.is_empty() else ""]
			_romance_btn.visible = true
		elif Marriage.romance_open(sid):
			_rom_love_label.text = "心动 %d/%d" % [Marriage.love_of(sid), Marriage.LOVE_MAX]
			_rom_status_label.text = "心里话 %d/5 段  (篝火聊天解锁更多互动)" % Marriage.stage(sid)
			_romance_btn.visible = true
		elif Marriage.is_bride(sid):
			_rom_love_label.text = "心动 --"
			_rom_status_label.text = "(先在篝火讲第 1 段心里话, 恋爱线才开启)"
			_romance_btn.visible = true
		else:
			_rom_love_label.text = "心动 --"
			_rom_status_label.text = "(并肩伙伴: 恋爱线只对六位姑娘开放)"
			_romance_btn.visible = false
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

# 赠送：打开选物弹窗（gift_picker）, 挑一份背包里的作物/食物/材料送出去
func _on_give_pressed_detail() -> void:
	if _detail_index < 0:
		return
	var gp: Control = GIFT_PICKER.new()
	add_child(gp)
	gp.picked.connect(_on_gift_picked_detail)
	gp.open_for(_detail_index)

# 恋爱互动：打开恋爱界面（romance_ui）, 挑一件小事做攒心动值
func _on_romance_pressed_detail() -> void:
	if _detail_index < 0:
		return
	var rui: Control = ROMANCE_UI.new()
	add_child(rui)
	rui.closed.connect(_refresh_slave_detail)
	rui.open_for(_detail_index)

# 选物弹窗点了某件物品 → 落账（give 记好感 + 扣背包一份, 跟弹窗约定配对）
func _on_gift_picked_detail(item: ItemData) -> void:
	if _detail_index < 0 or item == null:
		return
	var gain: int = Slaves.give(_detail_index, item)
	if gain <= 0:
		_flash_detail_info("今天已经送过东西了")
		return
	Inventory.remove_item(item, 1)
	Audio.play_sfx("buy")
	var sname := str(Slaves.slave_at(_detail_index)["name"])
	var bonus := " (Ta 最喜欢这个!)" if item.display_name == Slaves.like_of(_detail_index) else ""
	_flash_detail_info("送给 %s 1 份 %s, 好感 +%d%s" % [sname, item.display_name, gain, bonus])
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

# ---------------- 日历页 ----------------
# 一年 4 季 x 28 天, 每季一行铺开 28 个格子:
#   · 粉色格子 = 有伙伴在这天过生日（格子里写名字, 悬停看全名）
#   · 金边格子 = 今天
var _calendar_cells: Array = []      # 日期格子 PanelContainer（meta: season/day/sb/name）
var _calendar_today: Label = null

func _build_calendar_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)

	_calendar_today = _mk_label("", 13, Color(1, 0.92, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(_calendar_today)

	for season in TimeManager.SEASONS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		wrap.add_child(row)
		# 行首季节标签
		var sl := _mk_label(str(TimeManager.SEASONS[season]), 14, Color(0.95, 0.86, 0.62))
		sl.custom_minimum_size = Vector2(34, 0)
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(sl)
		var grid := GridContainer.new()
		grid.columns = 28
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 4)
		row.add_child(grid)
		for day in 28:
			grid.add_child(_make_calendar_cell(season, day + 1))
	return wrap

func _make_calendar_cell(season: int, day: int) -> PanelContainer:
	var panel := PanelContainer.new()
	# 今天与生日是状态提示, 不能被通用面板底色覆盖。
	panel.set_meta("keep_ui_palette", true)
	panel.custom_minimum_size = Vector2(24, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiStyle.SURFACE
	sb.border_color = UiStyle.EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var dl := _mk_label(str(day), 10, UiStyle.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	var nl := _mk_label("", 9, Color("944d62"), HORIZONTAL_ALIGNMENT_CENTER)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.clip_text = true          # 改过 8 字名的也塞得下（截断, 全名在 tooltip）
	nl.custom_minimum_size = Vector2(0, 12)
	v.add_child(nl)
	panel.set_meta("sb", sb)
	panel.set_meta("season", season)
	panel.set_meta("day", day)
	panel.set_meta("name", nl)
	_calendar_cells.append(panel)
	return panel

# 切到日历页时重刷一遍：今天描金, 生日格按当前名单重新标（改过名也能跟上）
func _refresh_calendar() -> void:
	if _calendar_cells.is_empty():
		return
	# 谁的生日落在哪天: [season, day, 名字]
	var bds: Array = []
	for i in Slaves.slaves.size():
		var bd := Slaves.birthday_of(i)
		if bd.x >= 0:
			bds.append([int(bd.x), int(bd.y), str(Slaves.slaves[i]["name"])])
	for c in _calendar_cells:
		var panel: PanelContainer = c
		var season := int(panel.get_meta("season"))
		var day := int(panel.get_meta("day"))
		var sb: StyleBoxFlat = panel.get_meta("sb")
		var nl: Label = panel.get_meta("name")
		var names: Array = []
		for bd in bds:
			if int(bd[0]) == season and int(bd[1]) == day:
				names.append(str(bd[2]))
		var is_today: bool = TimeManager.season == season and TimeManager.day == day
		var is_bd := not names.is_empty()
		sb.bg_color = Color("f1cbd0") if is_bd else UiStyle.SURFACE
		sb.border_color = Color("b68a2e") if is_today \
			else (Color("ba7789") if is_bd else UiStyle.EDGE)
		sb.set_border_width_all(2 if is_today else 1)
		nl.text = ", ".join(names)
		panel.tooltip_text = ("%s的生日" % ", ".join(names)) if is_bd \
			else "%s季 第 %d 天" % [TimeManager.SEASONS[season], day]
	_calendar_today.text = "今天: %s季 第 %d 天    粉色格子 = 伙伴生日 (当天送东西好感增量翻倍)" % [
		TimeManager.SEASONS[TimeManager.season], TimeManager.day]

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
var _smith_points: Label = null      # 2026-10-06: 锻造点池（伙伴打铁产出）
var _smith_invest: Button = null     # 2026-10-06: 投入锻造点 -> 当场出件

func _build_craft_page() -> Control:
	# 2026-10-06: 整页套滚动兜底 —— 三档配方（个人 10 + 工作台 + 铁匠铺整套盔甲）叠起来
	# 远超内容盒的高, 矮窗口下底部配方会被面板下沿裁掉。跟建造页(_build_build_page)同款。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wrap)

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
		tb.custom_minimum_size = Vector2(170, 30)
		tb.add_theme_font_override("font", PIXEL_FONT)
		tb.add_theme_font_size_override("font_size", 15)   # 2026-10-06: 跟顶层页签同号
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
		_apply_craft_facility_tooltip(row, r["result"])
		base_page.add_child(row)
		_craft_rows.append({"btn": row, "idx": i, "result": r["result"], "wb": false})
	base_page.add_child(_mk_label("(手持木板时点到草地/耕地上即可铺设)",
		11, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))

	# 工作台: 要站在工作台旁边才能做（更复杂的工具和器械）
	var wb_page := _craft_sub_page("wb", wrap)
	wb_page.add_child(_mk_label("-- 要站在工作台旁边才能做 --", 12,
		Color(0.8, 0.7, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	for i in Crafting.WORKBENCH_RECIPES.size():
		var wb_r: Dictionary = Crafting.WORKBENCH_RECIPES[i]
		var wb_row := _craft_row_btn()
		wb_row.pressed.connect(_on_craft_pressed.bind(i, true))
		_apply_craft_facility_tooltip(wb_row, wb_r["result"])
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
	# 2026-10-06 锻造点：跟建造点同一套 —— 伙伴打铁攒点, 在这里当场出件
	_smith_points = _mk_label("", 12, Color(1.0, 0.92, 0.68), HORIZONTAL_ALIGNMENT_CENTER)
	sm_page.add_child(_smith_points)
	_smith_invest = Button.new()
	_smith_invest.text = "投入锻造点 -- 立刻打出队首那件"
	_smith_invest.custom_minimum_size = Vector2(620, 34)
	_smith_invest.add_theme_font_override("font", PIXEL_FONT)
	_smith_invest.add_theme_font_size_override("font_size", 13)
	_smith_invest.pressed.connect(_on_smith_invest)
	sm_page.add_child(_smith_invest)
	for i in Crafting.SMITH_RECIPES.size():
		var sm_r: Dictionary = Crafting.SMITH_RECIPES[i]
		var sm_row := _craft_row_btn()
		sm_row.pressed.connect(_on_craft_pressed.bind(i, false, true))
		sm_page.add_child(sm_row)
		_craft_rows.append({"btn": sm_row, "idx": i, "result": sm_r["result"], "smith": true})

	_select_craft_sub("base")
	return scroll

func _craft_sub_page(key: String, wrap: VBoxContainer) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 6)
	wrap.add_child(p)
	_craft_sub_pages[key] = p
	return p

func _craft_row_btn() -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(560, 44)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_font_override("font", PIXEL_FONT)
	row.add_theme_font_size_override("font_size", 14)   # 2026-10-06: 13 -> 14, 跟建造页一致
	return row

func _apply_craft_facility_tooltip(row: Button, result: ItemData) -> void:
	if result == null:
		return
	var path := result.resource_path
	if path.ends_with("workbench.tres"):
		row.tooltip_text = Structures.facility_tip(Structures.KIND_WORKBENCH)
	elif path.ends_with("furnace.tres"):
		row.tooltip_text = Structures.facility_tip(Structures.KIND_FURNACE)

# e28f: 切制作子页签 —— 只显当前那段, 选中的页签字点亮
func _select_craft_sub(key: String) -> void:
	for k in _craft_sub_pages.keys():
		(_craft_sub_pages[k] as Control).visible = (k == key)
	for k in _craft_sub_btns.keys():
		var b: Button = _craft_sub_btns[k]
		if k == key:
			b.add_theme_color_override("font_color", UiStyle.PAPER)
		else:
			b.add_theme_color_override("font_color", UiStyle.MUTED)
	_refresh_craft()

# 2026-10-06: 投入锻造点 —— 把池子里的点灌进打铁队列, 够一件当场出一件。
func _on_smith_invest() -> void:
	if not Crafting.smith_busy():
		return
	var made: Array = Crafting.invest_smith_points()
	Audio.play_sfx("plant", -8.0)      # 借放置的锤子音
	if not made.is_empty():
		Audio.play_sfx("bin")
		if _craft_info != null:
			_craft_info.text = "打出来了: %s" % ", ".join(made)
	_refresh_craft()

func _refresh_craft() -> void:
	# e41c: 铁匠铺页顶上的队列一览（"打铁队列: 皮甲 1/2, 锁链甲 0/2"）
	if _smith_queue_label != null:
		if Crafting.smith_busy():
			_smith_queue_label.text = "打铁队列 (%d 件): %s" % [
				Crafting.smith_queued(), Crafting.smith_queue_text()]
		else:
			_smith_queue_label.text = "打铁队列: 空 (点了配方就排进来)"
	# 2026-10-06: 锻造点池 —— 伙伴打铁每晚攒点, 在这里当场出件
	if _smith_points != null:
		_smith_points.text = "锻造点: %d  (派伙伴去铁匠铺打铁, 每晚攒点进池)" % Crafting.smith_points
	if _smith_invest != null:
		var busy: bool = Crafting.smith_busy()
		_smith_invest.visible = busy
		_smith_invest.disabled = (not busy) or Crafting.smith_points <= 0
		if busy:
			var job: Dictionary = Crafting.smith_top()
			var left := maxi(0, int(job["need"]) - int(job["work"]))
			if Crafting.smith_points >= left:
				_smith_invest.text = "投入锻造点 -- 立刻打出 %s" % Crafting.smith_name()
			else:
				_smith_invest.text = "投入锻造点 -- 投入 %d 点 (还差 %d 点)" % [
					Crafting.smith_points, left]
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
var _site_points: Label = null      # 2026-10-06: 建造点总池（伙伴施工产出的点数）
var _site_box: VBoxContainer = null # 2026-10-06: 每座工地一行（进度 + 投入 + 取消），刷新时整段重建
var _move_btn: Button = null        # e44: 建筑模式（搬已建好的建筑）入口
# 2026-10-06: 建造页分四类（建筑一多, 平铺长列表就找不到东西了）。
# 分类表在 _build_build_page 里按 Structures.KIND_* 现搭（const 里不能用 autoload）。
var _build_sub_pages := {}         # 分类 key -> VBoxContainer
var _build_sub_btns := {}          # 分类 key -> Button

# 2026-10-06: 建造页分类 —— 顺序就是页签顺序。没被任何一类收走的 kind
# 会自动落进最后的"其它"页（加新建筑忘了归类也不会凭空消失）。
const BUILD_TAB_DEFS := [
	{"key": "town", "name": "城镇", "kinds": ["barracks", "academy", "market", "lighthouse", "bakery", "weaver"]},
	{"key": "life", "name": "生计", "kinds": ["well", "coop", "lamp", "hut", "hive", "chest"]},
	{"key": "farm", "name": "农牧", "kinds": ["barn", "stable", "silo", "greenhouse", "mill"]},
	{"key": "misc", "name": "材料与路桥", "kinds": ["blacksmith", "fence", "bridge"]},
]
const BUILD_SUB_FONT := 15
const BUILD_ROW_FONT := 14

func _build_build_page() -> Control:
	# e55: 整页套滚动兜底 —— 工地一览 + 建筑升级区 + 每个建筑两行（名字/选位置）
	# 叠起来远超内容盒的高, 底部几个建筑会被面板下沿裁掉。
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wrap)

	# 2026-10-06 建造点：伙伴在工地干活 -> 每晚攒点进**总池** -> 在这里对任意一座工地当场兑现。
	# 工地可多座并行（上限 Structures.SITE_MAX），所以这里是「一个总点数 + 每座一行」。
	_site_points = _mk_label("", 15, Color(1.0, 0.92, 0.68), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(_site_points)
	_site_box = VBoxContainer.new()
	_site_box.add_theme_constant_override("separation", 6)
	wrap.add_child(_site_box)

	_build_info = _mk_label("", 14, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	wrap.add_child(_build_info)

	# e44 建筑模式：已盖好的建筑可以随便挪地方（不花钱不扣料, 等级/鸡/蜂蜜都跟着走）
	_move_btn = Button.new()
	_move_btn.text = "建筑模式 -- 随意搬动已盖好的建筑 (不花钱)"
	_move_btn.custom_minimum_size = Vector2(640, 34)
	_move_btn.add_theme_font_override("font", PIXEL_FONT)
	_move_btn.add_theme_font_size_override("font_size", 14)
	_move_btn.pressed.connect(_on_move_mode)
	wrap.add_child(_move_btn)

	# e28f: 建筑升级区 —— 铁匠铺升级从「站旁边按 F」搬进背包, 建造页也能花钱提级
	wrap.add_child(_mk_label("-- 建筑升级 --", 15, Color(1, 0.92, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER))
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 4)
	wrap.add_child(_upgrade_box)

	# ---------- 分类页签（建筑多了, 一页只看一类） ----------
	wrap.add_child(_mk_label("选建筑 -> 回地图摆放: 左键放置 / 右键取消", 13,
		Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(tabs)
	var defs: Array = _build_tab_defs()
	for d in defs:
		var tb := Button.new()
		tb.text = str(d["name"])
		tb.custom_minimum_size = Vector2(150, 32)
		tb.add_theme_font_override("font", PIXEL_FONT)
		tb.add_theme_font_size_override("font_size", BUILD_SUB_FONT)
		tb.pressed.connect(_select_build_sub.bind(str(d["key"])))
		tabs.add_child(tb)
		_build_sub_btns[str(d["key"])] = tb

	for d in defs:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		wrap.add_child(page)
		_build_sub_pages[str(d["key"])] = page
		for kind in d["kinds"]:
			var k := String(kind)
			if not Structures.BUILDINGS.has(k):
				continue
			var info: Dictionary = Structures.BUILDINGS[k]
			var btip: String = Structures.building_tip(k)
			var name_lab := _mk_label("%s  --  %s" % [info["name"], info["desc"]],
				BUILD_ROW_FONT, Color(0.95, 0.9, 0.8))
			name_lab.tooltip_text = btip
			name_lab.mouse_filter = Control.MOUSE_FILTER_STOP
			page.add_child(name_lab)
			var cost_text := "金币 %d   木头 %d   石头 %d   铁 %d   劳动力 %d" \
				% [int(info["coin"]), int(info["wood"]), int(info["stone"]),
				int(info["iron"]), int(info["labor"])]
			var row := Button.new()
			row.text = "选位置   " + cost_text
			row.custom_minimum_size = Vector2(640, 36)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_theme_font_override("font", PIXEL_FONT)
			row.add_theme_font_size_override("font_size", BUILD_ROW_FONT)
			row.tooltip_text = btip
			row.pressed.connect(_on_build_pick.bind(k))
			page.add_child(row)
			_build_rows[k] = row
			_build_names[k] = name_lab

	_select_build_sub("life")
	wrap.add_child(_mk_label("建造点: 每晚派伙伴去工地干活来攒, 攒够在这里当场把楼盖完",
		12, Color(0.6, 0.57, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	return scroll

# 分类表：BUILD_TAB_DEFS 里登记的 + 一个"其它"兜底页（把 BUILDINGS 里漏归类的收进来）
func _build_tab_defs() -> Array:
	var defs: Array = []
	var claimed := {}
	for d in BUILD_TAB_DEFS:
		defs.append({"key": str(d["key"]), "name": str(d["name"]), "kinds": d["kinds"]})
		for k in d["kinds"]:
			claimed[String(k)] = true
	var rest: Array = []
	for kind in Structures.BUILDINGS:
		if not claimed.has(String(kind)):
			rest.append(String(kind))
	if not rest.is_empty():
		defs.append({"key": "other", "name": "其它", "kinds": rest})
	return defs

# 切建造子页签 —— 只显当前那一类, 选中的页签字点亮
func _select_build_sub(key: String) -> void:
	for k in _build_sub_pages.keys():
		(_build_sub_pages[k] as Control).visible = (k == key)
	for k in _build_sub_btns.keys():
		var b: Button = _build_sub_btns[k]
		if k == key:
			b.add_theme_color_override("font_color", UiStyle.PAPER)
		else:
			b.add_theme_color_override("font_color", UiStyle.MUTED)

func _refresh_build() -> void:
	var g: Node = get_tree().get_first_node_in_group("game")
	for kind in _build_rows:
		var btn: Button = _build_rows[kind]
		var ok: bool = g != null and g.has_method("_can_pay_build") \
			and g._can_pay_build(kind)
		var lock: String = Quests.building_lock_hint(String(kind))
		btn.disabled = not ok or not lock.is_empty()
		btn.tooltip_text = lock if not lock.is_empty() else Structures.building_tip(String(kind))
		btn.visible = lock.is_empty()
		(_build_names[kind] as Control).visible = lock.is_empty()
		btn.modulate = Color(1, 1, 1) if ok else Color(0.75, 0.72, 0.7)
	if _build_info != null:
		var locks: Array[String] = []
		for kind in _build_rows:
			var lock: String = Quests.building_lock_hint(String(kind))
			if not lock.is_empty():
				locks.append(String(Structures.BUILDINGS[kind]["name"]) + ": " + lock)
		_build_info.text = "还有 %d 种设施待开放, 悬停这里查看条件" % locks.size() if not locks.is_empty() else "按自己的节奏建设家园"
		_build_info.tooltip_text = "\n".join(locks)
		_build_info.mouse_filter = Control.MOUSE_FILTER_STOP
	# 2026-10-06: 建造点总池 —— 伙伴在工地干活每晚攒点, 在这里对任意一座工地当场兑现
	if _site_points != null:
		_site_points.text = "建造点: %d  (派伙伴去工地干活, 每晚攒点进池)" % Structures.build_points
	_rebuild_site_rows()
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

# e24c: 取消第 idx 座工地 —— 材料全额退回背包（金币和已花的人工不退, 跟拆房同一套规矩）
func _on_site_cancel(idx: int) -> void:
	var cost: Dictionary = Structures.cancel_site(idx)
	if cost.is_empty():
		return
	for key in ["wood", "stone", "iron"]:
		var n := int(cost.get(key, 0))
		if n > 0:
			Inventory.add_item(load("res://item/%s.tres" % key), n)
	Audio.play_sfx("bin")
	_refresh_build()

# 2026-10-06: 投入建造点 —— 把总池里的点灌进第 idx 座工地, 投满当场落成。
# 这是"建造点"体系的兑现入口：伙伴每晚施工攒点, 玩家在这里主动花掉（可跨天攒、可挑工地）。
func _on_site_invest(idx: int) -> void:
	var list: Array = Structures.site_list()
	if idx < 0 or idx >= list.size():
		return
	var nm := String(list[idx]["name"])
	var done: bool = Structures.invest_build_points(idx)
	Audio.play_sfx("plant", -8.0)      # 借放置的锤子音
	if done:
		Audio.play_sfx("bin")
		_build_info.text = "%s 盖好了!" % nm
	_refresh_build()

# 2026-10-06: 工地行 —— 每座工地一行（进度字 + 投入按钮 + 取消按钮），刷新时整段重建。
# 仿 _refresh_upgrades 的做法；工地可多座并行, 行数跟着变, 所以不缓存按钮。
func _rebuild_site_rows() -> void:
	if _site_box == null:
		return
	for c in _site_box.get_children():
		_site_box.remove_child(c)
		c.queue_free()
	var list: Array = Structures.site_list()
	if list.is_empty():
		_site_box.add_child(_mk_label("当前没有工地 -- 选一座建筑回地图摆放, 付清钱料就开工",
			13, Color(0.62, 0.6, 0.56), HORIZONTAL_ALIGNMENT_CENTER))
		return
	for i in list.size():
		var s: Dictionary = list[i]
		var work := int(s["work"])
		var need := int(s["need"])
		var left := maxi(0, need - work)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.add_child(_mk_label("工地 %d/%d: %s  进度 %d/%d 点" % [
			i + 1, list.size(), String(s["name"]), work, need],
			14, Color(0.85, 0.92, 1.0)))
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		var invest := Button.new()
		invest.custom_minimum_size = Vector2(380, 36)
		invest.add_theme_font_override("font", PIXEL_FONT)
		invest.add_theme_font_size_override("font_size", 14)
		# 点数为 0 才灰掉；点不够也允许投（进度条照样往前走, 攒够那一下才落成）
		invest.disabled = Structures.build_points <= 0
		if Structures.build_points >= left:
			invest.text = "投入建造点 -- 立刻完工"
		else:
			invest.text = "投入建造点 -- 投 %d 点 (还差 %d)" % [Structures.build_points, left]
		invest.pressed.connect(_on_site_invest.bind(i))
		btns.add_child(invest)
		var cancel := Button.new()
		cancel.text = "取消 (返还材料)"
		cancel.custom_minimum_size = Vector2(210, 36)
		cancel.add_theme_font_override("font", PIXEL_FONT)
		cancel.add_theme_font_size_override("font_size", 13)
		cancel.pressed.connect(_on_site_cancel.bind(i))
		btns.add_child(cancel)
		row.add_child(btns)
		_site_box.add_child(row)

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
		var btip: String = Structures.building_tip(Structures.KIND_BLACKSMITH)
		lab.tooltip_text = btip
		lab.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lab)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(230, 30)
		btn.add_theme_font_override("font", PIXEL_FONT)
		btn.add_theme_font_size_override("font_size", 13)
		btn.tooltip_text = btip
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
	# d9: iris 收黑后再回主页面（P4: 回菜单 = 合上这本手册, 翻页转场）
	IRIS.play("out", func() -> void:
		get_tree().change_scene_to_file("res://scene/main_menu.tscn"), "page")

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

# ---------------- 发展页 (战斗 / 科技 / 行政) ----------------
func _build_grow_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	var sub_tabs := HBoxContainer.new()
	sub_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_tabs.add_theme_constant_override("separation", 6)
	var subs: Array = [
		{"key": "battle", "name": "战斗"},
		{"key": "tech", "name": "科技"},
		{"key": "admin", "name": "行政"},
	]
	for sd in subs:
		var sk := String(sd["key"])
		var tb := Button.new()
		tb.text = String(sd["name"])
		tb.add_theme_font_override("font", PIXEL_FONT)
		tb.add_theme_font_size_override("font_size", 14)
		tb.pressed.connect(_select_grow_sub.bind(sk))
		sub_tabs.add_child(tb)
		_grow_sub_btns[sk] = tb
	wrap.add_child(sub_tabs)
	var stack := VBoxContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var battle_p: Control = _build_battle_page()
	var tech_p: Control = _build_tech_page()
	var admin_p: Control = _build_admin_page()
	_pages["battle"] = battle_p
	_pages["tech"] = tech_p
	_pages["admin"] = admin_p
	for p in [battle_p, tech_p, admin_p]:
		p.visible = false
		stack.add_child(p)
	wrap.add_child(stack)
	_select_grow_sub("tech")
	return wrap

func _select_grow_sub(sub: String) -> void:
	if sub != "battle" and sub != "tech" and sub != "admin":
		return
	if not Quests.grow_sub_unlocked(sub):
		return
	_grow_sub = sub
	for k in ["battle", "tech", "admin"]:
		if _pages.has(k):
			(_pages[k] as Control).visible = (_current == "grow" and k == sub)
	_update_grow_sub_tab_colors()
	if _current == "grow":
		if _box != null:
			var sz: Vector2 = PAGE_SIZES.get(sub, PAGE_SIZES["grow"])
			sz.y = minf(sz.y, get_viewport_rect().size.y - 60.0)
			_box.custom_minimum_size = sz
		_refresh_page(sub)

func _update_grow_sub_tab_colors() -> void:
	for k in _grow_sub_btns.keys():
		var b: Button = _grow_sub_btns[k]
		b.visible = Quests.grow_sub_unlocked(String(k))
		if k == _grow_sub:
			b.add_theme_color_override("font_color", UiStyle.PAPER)
		else:
			b.add_theme_color_override("font_color", UiStyle.MUTED)

func _refresh_module_tabs() -> void:
	for m in MODULES:
		var k := String(m["key"])
		if not _tab_btns.has(k):
			continue
		var b: Button = _tab_btns[k]
		var ok: bool = Quests.module_unlocked(k)
		b.visible = ok
		b.disabled = not ok
		b.modulate = Color(1, 1, 1) if ok else Color(0.55, 0.52, 0.48)
		b.tooltip_text = "" if ok else Quests.module_lock_hint(k)
	if _future_label != null:
		var hints: Array[String] = []
		for m in MODULES:
			if not Quests.module_unlocked(String(m["key"])):
				hints.append(String(m["name"]) + ": " + Quests.module_lock_hint(String(m["key"])))
		_future_label.text = "\n".join(hints)
		_future_btn.visible = not hints.is_empty()
	_update_grow_sub_tab_colors()

func _unlocked_module_list() -> Array:
	var out: Array = []
	for m in MODULES:
		if Quests.module_unlocked(String(m["key"])):
			out.append(m)
	return out

# ---------------- 模块切换 ----------------
func _select_module(key: String) -> void:
	if not Quests.module_unlocked(key):
		Audio.play_sfx("cancel", -8.0)
		_hint.text = Quests.module_lock_hint(key)
		return
	if key == _current:
		return
	Audio.play_sfx("ui_click", -10.0)
	_switch_to(key)

func _switch_to(key: String) -> void:
	_current = key
	if _box != null:
		var sz_key: String = _grow_sub if key == "grow" else key
		var sz: Vector2 = PAGE_SIZES.get(sz_key, Vector2.ZERO)
		sz.y = minf(sz.y, get_viewport_rect().size.y - 60.0)
		_box.custom_minimum_size = sz
	for k in _pages.keys():
		var p: Control = _pages[k]
		if k == "battle" or k == "tech" or k == "admin":
			p.visible = (key == "grow" and k == _grow_sub)
		else:
			p.visible = (k == key)
	for k in _tab_btns.keys():
		var b: Button = _tab_btns[k]
		b.modulate = Color(1, 1, 1) if k == key else Color(0.68, 0.65, 0.6)
		if k == key:
			b.add_theme_color_override("font_color", UiStyle.PAPER)
		else:
			b.add_theme_color_override("font_color", UiStyle.MUTED)
	for m in MODULES:
		if m["key"] == key:
			_title.text = str(m["name"])
			_hint.text = str(m["hint"])
	if key == "grow":
		_update_grow_sub_tab_colors()
	_refresh_page(key if key != "grow" else _grow_sub)
	page_changed.emit(key)

func _refresh_page(key: String) -> void:
	match key:
		"bag":
			_refresh()
		"hero":
			_refresh_hero()
		"team":
			_refresh_team()
		"grow":
			_refresh_page(_grow_sub)
		"battle":
			_refresh_battle()
		"map":
			_refresh_map_page()
		"calendar":
			_refresh_calendar()
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
			pass

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
	# 详情面板开着时也同步刷一下（赠送/改名/加好感后回到列表能看到新值）
	if _detail_panel != null and _detail_panel.visible:
		_refresh_slave_detail()


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
		cur_l = String(s.get("labor", "帮工"))   # 缺 labor 的存档/测试数据兜底, 不炸团队页
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
				% [s2["name"], s2["troop"], s2.get("labor", "帮工")]
		else:
			_tree_target.text = "先在下面点开一个伙伴, 这两棵树才会挂到他身上"

# 点树上的职业节点：给晋升对象转职（战斗/劳动两树共用）
func _on_class_node_clicked(cname: String, labor: bool) -> void:
	if _last_slave < 0 or _last_slave >= Slaves.slaves.size():
		_tree_prompt("先点伙伴卡打开详情, 再点树上的职业转职")
		return
	var s: Dictionary = Slaves.slave_at(_last_slave)
	var now := String(s.get("labor", "帮工")) if labor else String(s["troop"])
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
	var mods: Array = _unlocked_module_list()
	if mods.is_empty():
		return
	var idx := 0
	for i in mods.size():
		if String(mods[i]["key"]) == _current:
			idx = i
			break
	var nxt: String = String(mods[(idx + dir + mods.size()) % mods.size()]["key"])
	_switch_to(nxt)
	Audio.play_sfx("ui_click", -10.0)

func toggle() -> void:
	if _visible:
		close()
	else:
		open()

# e30p: 对工作台/铁匠铺按 F 直达对应制造子页（"wb"/"smith"，缺省开在个人页）
func open_craft(sub: String = "base") -> void:
	# 工作台/铁匠铺按 F: 制作页可能尚未任务解锁, 仍允许打开
	var was := _visible
	_visible = true
	_drag_from = -1
	_refresh_module_tabs()
	_switch_to("craft")
	_select_craft_sub(sub)
	_refresh()
	if not was:
		show()
		preload("res://scene/ui_anim.gd").pop_in(self)
		TimeManager.push_ui_pause()
		Audio.play_sfx("ui_open")
		opened.emit()

func open_to(page: String, grow_sub: String = "") -> void:
	var was := _visible
	_visible = true
	_drag_from = -1
	_refresh_module_tabs()
	if Quests.module_unlocked(page):
		_switch_to(page)
	else:
		_switch_to("bag")
	if page == "grow" and grow_sub != "":
		_select_grow_sub(grow_sub)
	elif _current == "grow":
		_select_grow_sub(_grow_sub)
	_refresh()
	if not was:
		show()
		preload("res://scene/ui_anim.gd").pop_in(self)
		TimeManager.push_ui_pause()
		Audio.play_sfx("ui_open")
		opened.emit()

func open() -> void:
	open_to("bag", "")

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
