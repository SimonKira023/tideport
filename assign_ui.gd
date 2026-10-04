# assign_ui.gd —— 夜晚「给伙伴派活」面板（在结算画面之后弹出）
#
# 睡觉的流程变成：
#   黑幕 → 售卖箱结算画面（今天卖了多少钱）→ **这张派活面板** → 换日 → 天亮
#
# e30r 版面（从上到下）：
#   标题 + 信息行
#   中排：左边一张大地图（涂色派浇水）+ 右边一列功能键（含图例）
#   底部：六大板块条 —— 照料作物 / 采集矿石 / 远航出征 / 工地建造 / 冶炼锻造 / 科研行政
#
# 六大板块怎么用：
#   · 每格瓦片 = 一个伙伴，瓦片上写着「名字 + 劳动职业」
#   · 把瓦片拖到别的板块 = 改派；也可以「点一下拿起，再点目标板块标题放下」
#   · 照料作物 = 默认池：没被别的活占住的人都在这里，白天在地图上浇水
#   · 采集矿石：点瓦片循环 采石 → 采铁 → 收工；劳动力越多采矿效率越高
#   · 远航出征：点瓦片循环换编队 1/2/3（战斗里按数字指挥）
#   · 工地建造 / 冶炼锻造：只有工地或铁匠铺在忙时才亮，点瓦片没反应，拖出去才算撤
#   · 科研行政：全体名单，每人一行 [科]/[行] 两个小键
#
# 地图（scene/assign_map.gd）：
#   · 左键涂色（按住能刷一排）、右键单击擦除、右键或中键拖拽平移、滚轮放缩
#   · 图上的颜色 = 地形：黄绿 = 已播种、棕 = 空耕地、绿 = 草地、深蓝 = 水
#   · 伙伴只能往耕地/已播种的地块上涂；草地涂不上
#   · 能涂多少格由「伙伴人数 × 每人可派格数」决定，涂满了就涂不上新的
#
# ❗地图**尺寸固定**（按视口算一次就不再变）：滚轮放缩/拖拽移动只改画在里面的内容，
#   不会把地图本身撑大撑小 —— 右边那列按钮也就不会跟着左右乱跑。
# ❗鼠标左键在这里是「涂色」，所以**不能用左键关面板** —— 只有 F / 空格 / Esc 能关。
# ❗文案只能用 ASCII 标点：IPix.ttf 没有全角括号/逗号的字形，渲出来是方块。
extends Control

signal closed

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const GUARD := 0.5       # 刚弹出来的这段时间不吃输入
const BTN_W := 178       # 右边功能键那一列多宽
const BOARD_W := 176     # 底部每个板块多宽（6 块正好铺满 1152 的视口）
const BOARD_H := 200     # 板块条高度（标题 + 名单 + 底部小字）
const TILE_W := 74       # 板块里一格瓦片多宽（两列并排）
const TILE_H := 48 # 瓦片高度（三行字：名字 / 劳动职业 / 三项属性 建N 劳N 知N）

# 六个板块的键
const B_CROP := "crop"           # 照料作物（默认池）
const B_MINE := "mine"           # 采集矿石
const B_EXP := "exp"             # 远航出征
const B_DOCK := "dock"           # 工地建造
const B_SMITH := "smith"         # 冶炼锻造
const B_RESEARCH := "research"   # 科研行政
const BOARD_KEYS := [B_CROP, B_MINE, B_EXP, B_DOCK, B_SMITH, B_RESEARCH]
const BOARD_NAMES := {
	B_CROP: "照料作物",
	B_MINE: "采集矿石",
	B_EXP: "远航出征",
	B_DOCK: "工地建造",
	B_SMITH: "冶炼锻造",
	B_RESEARCH: "科研行政",
}
# 只有固定小字的板块写在这里；出征/工地/打铁的底部小字是活的（见 _refresh_notes）
const BOARD_HINTS := {
	B_CROP: "点瓦片拿起, 再点别的板块放下\n涂地图 = 派去浇水",
	B_MINE: "劳动力越多采矿效率越高\n点一下采石 / 采铁 / 收工",
	B_RESEARCH: "科 = 科技, 行 = 行政\n派人钻研当天不下地",
}
# e41d: 每个板块吃的属性写在标题下面（瓦片底下那行 建/劳/知 就是这三个数）
# ❗名字跟 slaves.gd 的 ATTR_NAMES 对齐（const 里引不到 autoload 的常量, 只能手抄一份）
const BOARD_NEEDS := {
	B_CROP: "所需: 劳动 (浇水与派格)",
	B_MINE: "所需: 劳动 (采矿产量)",
	B_EXP: "看战力, 不吃出工属性",
	B_DOCK: "所需: 建造 (施工速度)",
	B_SMITH: "所需: 建造 (打铁速度)",
	B_RESEARCH: "所需: 知识 (研究速度)",
}

# ---- 拖放用的小部件（内类：把拖拽/接住都转发给面板本体） ----
# 板块里的一格瓦片：能拖出去，也能接住别人拖进来的伙伴
class Tile extends Button:
	var idx := -1
	var board := ""
	var host = null

	func _get_drag_data(_p: Vector2):
		return host._drag_from(idx)

	func _can_drop_data(_p: Vector2, data) -> bool:
		return host._can_drop_board(board, data)

	func _drop_data(_p: Vector2, data) -> void:
		host._drop_board(board, data)

# 板块底板：拖到板块的空白处也算数
class BoardPanel extends PanelContainer:
	var board := ""
	var host = null

	func _can_drop_data(_p: Vector2, data) -> bool:
		return host._can_drop_board(board, data)

	func _drop_data(_p: Vector2, data) -> void:
		host._drop_board(board, data)

# 板块里那张名单的滚动框：拖到名单空隙里也算数
class BoardScroll extends ScrollContainer:
	var board := ""
	var host = null

	func _can_drop_data(_p: Vector2, data) -> bool:
		return host._can_drop_board(board, data)

	func _drop_data(_p: Vector2, data) -> void:
		host._drop_board(board, data)

# 科研行政板块里的「名字(劳动职业) + 科/行」一行，整行也能拖出去
class DragRow extends HBoxContainer:
	var idx := -1
	var board := ""
	var host = null

	func _get_drag_data(_p: Vector2):
		return host._drag_from(idx)

	func _can_drop_data(_p: Vector2, data) -> bool:
		return host._can_drop_board(board, data)

	func _drop_data(_p: Vector2, data) -> void:
		host._drop_board(board, data)

var _open := false
var _guard := 0.0
var _title: Label
var _info: Label
var _map_slot: HBoxContainer = null
var _map: Control = null
var _side_scroll: ScrollContainer = null
var _tool_btns := {}
var _selected := Slaves.TASK_WATER
var _held := -1                          # 点选-点放：手里拿着的伙伴序号（-1 = 空手）

# 六个板块
var _boards := {}                        # key -> PanelContainer
var _board_title := {}                   # key -> Label（标题 + 人数，兼「放下」目标）
var _board_body := {}                    # key -> Control（瓦片网格 / 科研名单容器）
var _board_note := {}                    # key -> Label（底部小字）
var _tiles := {}                         # key -> GridContainer（五个瓦片板块）
var _tile_indexes := {}                  # key -> Array[int]（网格里第 n 格是谁）
var _board_sig := ""                     # 板块归属的指纹，变了才重建瓦片

# 科研行政板块的名单：每行 = 名字(劳动职业) + 科/行 两个小键（selftest 按行数校验）
var _research_box: VBoxContainer = null
var _research_btns: Array = []           # 上面那些 科/行 小键（刷新时只改状态，不重建）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	hide()

func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard -= delta

# ---------------- 搭界面 ----------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_bottom", 14)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vbox)

	_title = _label("派活", 20, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(_title)
	_info = _label("", 12, Color(0.98, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info)

	# 中排：左边大地图 + 右边功能键列
	_map_slot = HBoxContainer.new()
	_map_slot.add_theme_constant_override("separation", 10)
	_map_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	_map_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_map_slot)
	_build_side_buttons()

	# 底部：六大板块条
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(strip)
	for key in BOARD_KEYS:
		_build_board(strip, key)

# ---------------- 一个板块 ----------------
func _build_board(strip: Control, key: String) -> void:
	var panel := BoardPanel.new()
	panel.board = key
	panel.host = self
	panel.custom_minimum_size = Vector2(BOARD_W, BOARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.075, 0.07, 0.92)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	strip.add_child(panel)
	_boards[key] = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	# 标题兼「放下」目标：手里拿起伙伴之后，点板块标题就把他放进这个板块
	var title := _label("", 13, Color(1, 0.93, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drop_click(key))
	col.add_child(title)
	_board_title[key] = title

	# e41d: 这个板块吃哪项属性（不挡点击，纯说明）
	if BOARD_NEEDS.has(key):
		var need := _label(BOARD_NEEDS[key], 10, Color(0.62, 0.72, 0.6),
			HORIZONTAL_ALIGNMENT_CENTER)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		need.custom_minimum_size = Vector2(BOARD_W - 14, 0)
		need.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(need)

	var sc := BoardScroll.new()
	sc.board = key
	sc.host = self
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sc)

	var body: Control
	if key == B_RESEARCH:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_research_box = box
		body = box
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tiles[key] = grid
		body = grid
	sc.add_child(body)
	_board_body[key] = body

	# 底部小字（也是「放下」目标）
	var note := _label("", 10, Color(0.62, 0.58, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(BOARD_W - 14, 0)
	note.mouse_filter = Control.MOUSE_FILTER_STOP
	note.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drop_click(key))
	col.add_child(note)
	_board_note[key] = note
	if BOARD_HINTS.has(key):
		note.text = BOARD_HINTS[key]

# ---------------- 地图右侧那列功能键 ----------------
func _build_side_buttons() -> void:
	# ❗整列装进限高的滚动框：最高和地图齐平，超出部分滚动看。
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(BTN_W + 14, _map_fixed_size().y)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_map_slot.add_child(sc)
	_side_scroll = sc
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	sc.add_child(col)

	# 画笔：伙伴只干「浇水」这一样活，所以就两个（浇水 + 橡皮）
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tools)
	for task in [Slaves.TASK_WATER]:
		var tb := _button(Slaves.TASK_NAMES[task], 84)
		tb.pressed.connect(_select_tool.bind(task))
		tools.add_child(tb)
		_tool_btns[task] = tb
	var er := _button("橡皮", 72)
	er.pressed.connect(_select_tool.bind(0))
	tools.add_child(er)
	_tool_btns[0] = er

	for s in [
		["重新绘制", Callable(self, "_redraw_map")],
		["清除全部", Callable(self, "_clear")],
		["全部选择", Callable(self, "_select_all")],
		["只取消浇水", Callable(self, "_cancel_water")],
		["确定 (F)", Callable(self, "_dismiss")],
	]:
		var b := _button(str(s[0]), BTN_W)
		b.pressed.connect(s[1] as Callable)
		col.add_child(b)

	# 图例：底图上那几种颜色分别是什么
	col.add_child(_divider())
	col.add_child(_label("图例", 12, Color(1, 0.93, 0.76)))
	for entry in [
		# ❗色块前缀只能用字体里真有的字符：■ ● ♥ 在 IPix.ttf 里都没有字形（会显示成一个小方块）。
		#   '#' 是有的，当色块用刚好。
		["# 已播种", Color(0.66, 0.82, 0.24)],
		["# 空耕地", Color(0.55, 0.34, 0.24)],
		["# 草地(不能派)", Color(0.34, 0.52, 0.28)],
		["# 水面", Color(0.13, 0.28, 0.42)],
		["# 已派活", Slaves.TASK_COLORS[Slaves.TASK_WATER]],
	]:
		col.add_child(_label(str(entry[0]), 11, entry[1] as Color))

	col.add_child(_divider())
	col.add_child(_hint("拖瓦片到别的板块 = 改派\n点瓦片拿起, 再点板块标题放下\n左键涂色 / 右键擦除 / 滚轮放缩\n重新绘制 = 按当下地形重画并回整座岛"))

# ---------------- 六大板块：谁归哪块 ----------------
# 一个人同时只占一个岗位（数据层 toggle 之间互斥），所以归属是唯一的。
func _board_of(i: int) -> String:
	if Slaves.is_expedition(i):
		return B_EXP
	if Slaves.is_research(i, "tech") or Slaves.is_research(i, "admin"):
		return B_RESEARCH
	if Slaves.is_dock(i):
		return B_DOCK
	if Slaves.is_craft(i):
		return B_SMITH
	if Slaves.is_mine(i):
		return B_MINE
	return B_CROP

# 这块今天能不能派：工地/铁匠铺闲着就灰掉（拖进去也不收）
func _board_live(key: String) -> bool:
	match key:
		B_DOCK:
			return Structures.site_busy() or Voyage.dock_state == Voyage.DOCK_FUNDED
		B_SMITH:
			return Crafting.smith_busy()
		_:
			return true

func _board_count(key: String) -> int:
	if key == B_RESEARCH:
		return Slaves.research_heads("tech") + Slaves.research_heads("admin")
	var n := 0
	for i in Slaves.slaves.size():
		if _board_of(i) == key:
			n += 1
	return n

# 板块归属的指纹：谁在哪个板块 + 瓦片上会写的字（岗位/编队/劳动职业）
# 变了才重建瓦片，免得每次刷个数字都把 40 块瓦片拆了重搭
func _board_signature() -> String:
	var parts: Array = []
	for i in Slaves.slaves.size():
		var s: Dictionary = Slaves.slave_at(i)
		parts.append("%d:%s:%s:%d:%s" % [i, _board_of(i), Slaves.mine_job_of(i),
			Slaves.squad_of(i), str(s.get("labor", "帮工"))])
	return "|".join(parts)

# ---------------- 重建瓦片 ----------------
# ❗只在归属变了/每次打开面板时整段重建；平时只改文字和颜色（见 _refresh_boards）。
func _rebuild_boards() -> void:
	for key in BOARD_KEYS:
		var body: Control = _board_body.get(key)
		if body != null:
			for c in body.get_children():
				body.remove_child(c)      # 立刻摘掉，免得同帧新旧两份一起显示
				c.queue_free()
		_tile_indexes[key] = []
	_research_btns.clear()
	_board_sig = _board_signature()
	for i in Slaves.slaves.size():
		var key := _board_of(i)
		if key != B_RESEARCH:
			_add_tile(key, i)
	# 科研行政 = 全体名单（不是只有正在研究的那些人）
	for i in Slaves.slaves.size():
		_research_row(i)
	_refresh_boards()
	_refresh_notes()

func _add_tile(key: String, i: int) -> void:
	var grid: GridContainer = _tiles.get(key)
	if grid == null:
		return
	var t := Tile.new()
	t.idx = i
	t.board = key
	t.host = self
	t.custom_minimum_size = Vector2(TILE_W, TILE_H)
	t.add_theme_font_override("font", PIXEL_FONT)
	t.add_theme_font_size_override("font_size", 10)
	t.clip_text = true                # 三行字顶满时宁可裁掉, 也不许把板块撑宽
	t.pressed.connect(_on_tile_pressed.bind(i, key))
	grid.add_child(t)
	(_tile_indexes[key] as Array).append(i)

# ---------------- 只刷文字/颜色，不重建 ----------------
func _refresh_boards() -> void:
	for key in BOARD_KEYS:
		var live := _board_live(key)
		var title: Label = _board_title.get(key)
		if title != null:
			title.text = "%s %d人" % [BOARD_NAMES[key], _board_count(key)]
			title.add_theme_color_override("font_color",
				Color(1, 0.93, 0.76) if live else Color(0.46, 0.43, 0.4))
		var body: Control = _board_body.get(key)
		if body != null:
			body.modulate = Color(1, 1, 1) if live else Color(0.55, 0.53, 0.5)
	for key in [B_CROP, B_MINE, B_EXP, B_DOCK, B_SMITH]:
		var grid: GridContainer = _tiles.get(key)
		if grid == null:
			continue
		var idxs: Array = _tile_indexes.get(key, [])
		for n in grid.get_child_count():
			var t: Button = grid.get_child(n)
			_fill_tile(t, key, int(idxs[n]) if n < idxs.size() else -1)
	_refresh_research_states()

func _fill_tile(t: Button, key: String, i: int) -> void:
	if i < 0:
		t.text = ""
		t.modulate = Color(1, 1, 1, 0)
		return
	var s: Dictionary = Slaves.slave_at(i)
	var who := str(s.get("name", "?"))
	var labor := str(s.get("labor", "帮工"))
	# e41d: 每块瓦片底下都写着这个人的三项属性（建N 劳N 知N）, 跟板块标题的「所需」对上
	var attrs := Slaves.attrs_short_text(s)
	match key:
		B_MINE:
			var job := Slaves.mine_job_of(i)
			t.text = "%s\n%s\n%s" % [who, "采石" if job == "stone" else "采铁", attrs]
			t.modulate = Color(0.82, 0.88, 1.0) if job == "stone" else Color(1.0, 0.82, 0.62)
		B_EXP:
			# 出征板块的瓦片仍是三行（瓦片只有 48 高, 四行会被裁掉）:
			# 第一行 名字 + 编队名, 第二行 劳动职业, 第三行 三项属性
			t.text = "%s %s\n%s\n%s" % [who, Voyage.squad_name(Slaves.squad_of(i)), labor, attrs]
			t.modulate = Voyage.squad_color(Slaves.squad_of(i))
		_:
			t.text = "%s\n%s\n%s" % [who, labor, attrs]
			t.modulate = Color(1, 1, 1)

func _refresh_notes() -> void:
	# 远航出征：船够不够（四态文案原样保留）
	var t := ""
	var c := Color(0.62, 0.58, 0.5)
	if not Voyage.dock_ready():
		t = "码头还是废墟, 出不了海"
	elif Voyage.boat_count <= 0:
		t = "码头还没船 (去码头按 F 造)"
	elif Voyage.boats_enough():
		t = "船 %d 艘 - 能载 %d 人 - 出海 %d 人" % [
			Voyage.boat_count, Voyage.seats(), Voyage.party_size()]
		c = Color(0.62, 0.80, 0.55)
	else:
		t = "船不足, 无法派遣! %d 人要 %d 艘, 只有 %d 艘" % [
			Voyage.party_size(), Voyage.boats_needed(), Voyage.boat_count]
		c = Color(1, 0.55, 0.5)
	_set_note(B_EXP, t, c)

	# 工地建造：有工地就先盖房，没有工地但码头在施工就修码头（夜里也是这个顺序结算）
	if Structures.site_busy():
		_set_note(B_DOCK, "工地: %s (%d/%d 人天)" % [
			Structures.site_name(),
			int(Structures.site.get("work", 0)), int(Structures.site.get("need", 0))],
			Color(0.85, 0.88, 0.7))
	elif Voyage.dock_state == Voyage.DOCK_FUNDED:
		_set_note(B_DOCK, "修码头 (施工中)", Color(0.85, 0.88, 0.7))
	else:
		_set_note(B_DOCK, "眼下没有工地\n盖房 / 修码头时才能派人", Color(0.55, 0.52, 0.48))

	# 冶炼锻造：铁匠铺有东西正在打才亮（e41c: 队列 —— 显示队首进度 + 还排着几件）
	if Crafting.smith_busy():
		var top := Crafting.smith_top()
		var t2 := "打铁: %s (%d/%d 人天)" % [
			Crafting.smith_name(),
			int(top.get("work", 0)), int(top.get("need", 0))]
		if Crafting.smith_queued() > 1:
			t2 += "\n排队 %d 件 - 人工顺延" % Crafting.smith_queued()
		_set_note(B_SMITH, t2, Color(0.9, 0.82, 0.7))
	else:
		_set_note(B_SMITH, "铁匠铺闲着\n有东西在打时才能派人", Color(0.55, 0.52, 0.48))

func _set_note(key: String, text: String, color: Color) -> void:
	var l: Label = _board_note.get(key)
	if l == null:
		return
	l.text = text
	l.add_theme_color_override("font_color", color)

# ---------------- 科研行政名单（全体，一人一行） ----------------
func _research_row(index: int) -> void:
	if _research_box == null:
		return
	var s: Dictionary = Slaves.slave_at(index)
	var row := DragRow.new()
	row.idx = index
	row.board = B_RESEARCH
	row.host = self
	row.add_theme_constant_override("separation", 3)
	# e41d: 名字那列写两行 —— 上「名字(劳动职业)」, 下「建N 劳N 知N」（研究板块没有瓦片, 属性写这儿）
	var lb := _label("%s(%s)\n%s" % [str(s.get("name", "?")), str(s.get("labor", "帮工")),
		Slaves.attrs_short_text(s)], 10, Color(0.78, 0.74, 0.66))
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.clip_text = true                      # 名字再长也不许把这列撑宽
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.custom_minimum_size = Vector2(0, 30)
	row.add_child(lb)
	for tree in ["tech", "admin"]:
		var b := _button("科" if tree == "tech" else "行", 28)
		b.custom_minimum_size = Vector2(28, 22)
		b.add_theme_font_size_override("font_size", 11)
		b.toggle_mode = true
		b.set_meta("idx", index)
		b.set_meta("tree", tree)
		b.pressed.connect(func():
			var idx: int = int(b.get_meta("idx"))
			var tr := str(b.get_meta("tree"))
			var ok := Slaves.set_research(idx, tr)
			Audio.play_sfx("ui_click" if ok else "error", -10.0)
			_refresh())
		_research_btns.append(b)
		row.add_child(b)
	_research_box.add_child(row)

# 只刷状态，不重建
func _refresh_research_states() -> void:
	for b in _research_btns:
		var idx: int = int(b.get_meta("idx"))
		var tr := str(b.get_meta("tree"))
		var on := Slaves.is_research(idx, tr)
		var busy := Slaves.is_expedition(idx)   # 出海的人不能同时搞研究
		b.button_pressed = on
		b.disabled = busy
		if busy:
			b.modulate = Color(0.5, 0.47, 0.44)
		else:
			b.modulate = Color(1, 1, 1) if on else Color(0.72, 0.7, 0.66)

# ---------------- 拖放 ----------------
func _drag_from(i: int) -> Variant:
	if i < 0 or i >= Slaves.slaves.size():
		return null
	var s: Dictionary = Slaves.slave_at(i)
	var lb := _label("%s (%s)" % [str(s.get("name", "?")), str(s.get("labor", "帮工"))],
		12, Color(1, 0.96, 0.84))
	lb.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	lb.add_theme_constant_override("shadow_offset_x", 1)
	lb.add_theme_constant_override("shadow_offset_y", 1)
	set_drag_preview(lb)
	return {"idx": i}

func _can_drop_board(key: String, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	if not d.has("idx"):
		return false
	var i := int(d["idx"])
	if i < 0 or i >= Slaves.slaves.size():
		return false
	if key == _board_of(i):
		return false                        # 拖回原板块 = 白拖
	return _board_live(key)

func _drop_board(key: String, data: Variant) -> void:
	if not _can_drop_board(key, data):
		return
	var d: Dictionary = data
	var i := int(d["idx"])
	_held = -1
	_move_to(i, key)
	Audio.play_sfx("ui_click", -10.0)
	_refresh()

# 点选-点放：手里拿着人时点板块标题 = 放下
func _drop_click(key: String) -> void:
	if _held < 0:
		return
	var i := _held
	_held = -1
	if _can_drop_board(key, {"idx": i}):
		_move_to(i, key)
		Audio.play_sfx("ui_click", -10.0)
	else:
		Audio.play_sfx("error", -8.0)
	_refresh()

# 把人改派到某个板块：数据层的一次 toggle 就够（toggle 之间自带互斥，会把别的岗位撤掉）
func _move_to(i: int, key: String) -> void:
	match key:
		B_CROP:
			_unassign(i)
		B_MINE:
			Slaves.toggle_mine(i, "stone")
		B_EXP:
			# 一船两人：坐不下就不许派（跟以前勾选时的判断一致）
			if not _expedition_has_room():
				Audio.play_sfx("error", -8.0)
				return
			Slaves.toggle_expedition(i)
		B_DOCK:
			Slaves.toggle_dock(i)
		B_SMITH:
			Slaves.toggle_craft(i)
		B_RESEARCH:
			Slaves.set_research(i, "tech")   # 拖进来默认先钻研科技，要行政就点[行]

# 收工回「照料作物」默认池：看他现在占的是哪个岗位，撤掉那一个
func _unassign(i: int) -> void:
	if Slaves.is_expedition(i):
		Slaves.toggle_expedition(i)
	elif Slaves.is_research(i, "tech"):
		Slaves.set_research(i, "tech")
	elif Slaves.is_research(i, "admin"):
		Slaves.set_research(i, "admin")
	elif Slaves.is_dock(i):
		Slaves.toggle_dock(i)
	elif Slaves.is_craft(i):
		Slaves.toggle_craft(i)
	elif Slaves.is_mine(i):
		Slaves.toggle_mine(i, Slaves.mine_job_of(i))

# ---------------- 瓦片点击 ----------------
func _on_tile_pressed(i: int, key: String) -> void:
	match key:
		B_MINE:
			# 循环切换岗位：采石 -> 采铁 -> 收工（收工时按「同岗位」再 toggle 一次就出井）
			var job := Slaves.mine_job_of(i)
			var next := "stone"
			if job == "stone":
				next = "iron"
			elif job == "iron":
				next = ""
			if next == "":
				Slaves.toggle_mine(i, "iron")
			else:
				Slaves.toggle_mine(i, next)
			Audio.play_sfx("ui_click", -10.0)
		B_EXP:
			Slaves.set_squad(i, Slaves.squad_of(i) % Slaves.SQUAD_MAX + 1)
			Audio.play_sfx("ui_click", -10.0)
		B_CROP:
			_held = i                        # 拿起，再点目标板块标题放下
			Audio.play_sfx("ui_click", -10.0)
		_:
			# 工地建造 / 冶炼锻造：点瓦片没反应，要撤只能拖回照料作物
			return
	_refresh()

# ---------------- 船位（一船两人） ----------------
# 再派一个人还坐不坐得下？坐不下就不许派 —— 派出去也上不了船。
func _expedition_has_room() -> bool:
	if not Voyage.dock_ready():
		return false
	return Voyage.party_size() + 1 <= Voyage.seats()

# ---------------- 地图固定尺寸 ----------------
# 按视口算一次，减去右边功能键那一列（含纵向滚动条的位置）和上下那些文字占的地方。
# ❗算完就写死 —— 之后放缩/拖拽都不会再改它。
func _map_fixed_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1152, 648)
	# ❗纵向预算 320：除地图外还有标题/信息行/底部六大板块条要占位，
	#   预算给少了这堆东西会被挤到屏幕外；给多了地图框变矮，
	#   而底图是「格子边长取整」画的（terrain_map._fit_tile），会比框高出小半格压到板块条上。
	#   （右侧功能键列超高是滚动看的，不算被挤出去 —— ui_dump 里已按滚动裁剪处理）
	return Vector2(clampf(vp.x - 76.0 - float(BTN_W), 320.0, 1000.0),
		clampf(vp.y - 320.0, 240.0, 560.0))

# ---------------- 接上游戏数据 ----------------
# game 用来读地形（哪格是水），from/to 是可涂色的格子范围（= 整座岛的外接矩形）
func setup(game: Node, from: Vector2i, to: Vector2i) -> void:
	_map = preload("res://scene/assign_map.gd").new()
	# ❗不要 expand：一旦让它跟着容器伸缩，放缩地图时按钮列就会被挤得左右乱跑
	_map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map.custom_minimum_size = _map_fixed_size()
	_map_slot.add_child(_map)
	_map_slot.move_child(_map, 0)          # 地图在左，功能键在右
	_map.setup(game, from, to, _map_fixed_size())
	_map.tool = _selected
	Slaves.changed.connect(_refresh)
	_rebuild_boards()
	_refresh()

# ---------------- 功能键 ----------------
func _select_tool(task: int) -> void:
	_selected = task
	if _map != null:
		_map.tool = task
	Audio.play_sfx("ui_click", -8.0)
	_refresh()

# 重新绘制：按**当下**的地形重画底图（白天新锄的地、刚播的种都会出现），视角拉回整座岛
func _redraw_map() -> void:
	if _map == null:
		return
	_map.reset_view()
	_map.refresh(_map_fixed_size())
	Audio.play_sfx("ui_click", -8.0)
	_refresh()

func _clear() -> void:
	Slaves.clear_all()
	if _map != null:
		_map.queue_redraw()
	Audio.play_sfx("ui_close", -10.0)

# 全部选择：把所有能派活的地块（耕地 / 已播种）都涂上当前工种，涂到额度用完为止
func _select_all() -> void:
	if _map == null or _selected == 0:
		return
	var n := 0
	for y in range(Slaves.map_from.y, Slaves.map_to.y + 1):
		if not Slaves.has_room():
			break
		for x in range(Slaves.map_from.x, Slaves.map_to.x + 1):
			if not Slaves.has_room():
				break
			var c := Vector2i(x, y)
			if not _map.can_paint(c):
				continue
			if Slaves.assign(c, _selected):
				n += 1
	Audio.play_sfx("ui_click", -8.0)
	_refresh()

# 只取消浇水：把所有「浇水」的派活撤掉，别的工种留着
func _cancel_water() -> void:
	Slaves.erase_task(Slaves.TASK_WATER)
	if _map != null:
		_map.queue_redraw()
	Audio.play_sfx("ui_close", -10.0)
	_refresh()

# ---------------- 刷新 ----------------
func _refresh() -> void:
	if _info == null:
		return
	if _board_signature() != _board_sig:
		# 归属变了要重搭瓦片：延迟一帧做，免得在按钮自己的回调里把它拆掉
		_rebuild_boards.call_deferred()
	else:
		_refresh_boards()
		_refresh_notes()
	_update_info()
	# 选中的工种按钮提亮
	for task in _tool_btns.keys():
		var b: Button = _tool_btns[task]
		b.modulate = Color(1, 1, 1) if task == _selected else Color(0.72, 0.7, 0.66)
	if _map != null:
		_map.queue_redraw()

func _update_info() -> void:
	var parts: Array = []
	parts.append("伙伴 %d 人" % Slaves.count)
	parts.append("干活 %d 人 - 可派 %d 格 (每人 %d 格)"
		% [Slaves.working_count(), Slaves.budget(), Slaves.cells_per_slave()])
	if not Slaves.expedition.is_empty():
		parts.append("出海 %d 人" % Slaves.expedition.size())
	if Slaves.mine_heads() > 0:
		parts.append("下井 %d 人" % Slaves.mine_heads())
	var rn := Slaves.research_heads("tech") + Slaves.research_heads("admin")
	if rn > 0:
		parts.append("研究 %d 人" % rn)
	if Structures.site_busy() or Voyage.dock_state == Voyage.DOCK_FUNDED:
		parts.append("施工 %d 人" % Slaves.dock_heads())
	if Crafting.smith_busy():
		parts.append("打铁 %d 人" % Slaves.craft_heads())
	parts.append("浇水 %d 格" % Slaves.count_of(Slaves.TASK_WATER))
	parts.append("还剩 %d 格" % Slaves.remaining())
	parts.append("今天已干完 %d" % Slaves.done_today.size())
	if Slaves.remaining() <= 0:            # e28e: 额度顶满了要明说，别让玩家瞎涂
		parts.append("额度已满: 升丰饶线或管理研究能加格")
	if _held >= 0:
		var hs: Dictionary = Slaves.slave_at(_held)
		parts.append("已拿起 %s - 点目标板块放下" % str(hs.get("name", "?")))
	_info.text = "   ".join(parts)

# ---------------- 小部件 ----------------
# 各功能块之间的一条细分割线
func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(1, 1, 1, 0.10)
	d.custom_minimum_size = Vector2(BTN_W, 1)
	return d

func _button(text: String, w: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 30)
	b.add_theme_font_override("font", PIXEL_FONT)
	b.add_theme_font_size_override("font_size", 13)
	return b

func _label(text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PIXEL_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

# 右列里的灰色小字说明：必须自动换行，不许把这列撑宽
func _hint(text: String) -> Label:
	var l := _label(text, 11, Color(0.62, 0.58, 0.5))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ---------------- 开关 ----------------
func open() -> void:
	_title.text = "第 %d 天 - 给伙伴派活" % TimeManager.day
	# ❗每次打开都要重画底图：白天可能又锄了新地、播了新种，
	#   图上「哪些是耕地 / 哪些已经播种」得是当下这一刻的样子。
	if _map != null:
		_map.custom_minimum_size = _map_fixed_size()
		_map.refresh(_map_fixed_size())
	if _side_scroll != null:
		_side_scroll.custom_minimum_size = Vector2(BTN_W + 14, _map_fixed_size().y)
	_held = -1
	_rebuild_boards()
	_refresh()
	_guard = GUARD
	_open = true
	Slaves.paused = true          # 玩家开始绘制：伙伴全体停工
	TimeManager.push_ui_pause()   # 派活的时候时间也停住（不然一边划格子一边天黑）
	show()

func _input(event: InputEvent) -> void:
	if not _open or _guard > 0.0:
		return
	# ❗左键要留给涂色/拖人，所以这里只认键盘
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("interact"):
		_dismiss()
		get_viewport().set_input_as_handled()

func _dismiss() -> void:
	if not _open:
		return
	_open = false
	_held = -1
	Slaves.paused = false         # 收起面板：伙伴继续干活
	TimeManager.pop_ui_pause()
	hide()
	closed.emit()

func is_open() -> bool:
	return _open
