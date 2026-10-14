# 世界里只追踪一个目标. 打开面板/剧情时收起, 不盖住交互。
extends PanelContainer

const FONT := preload("res://resources/font/IPix.ttf")
var _title: Button
var _desc: Label
var _game: Node
var _direction: Label
var _caption: Label
var _action: Label
var _timer := 0.0

func _ready() -> void:
	_game = get_tree().get_first_node_in_group("game")
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(16, 16)
	custom_minimum_size = Vector2(296, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.07, 0.88)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_caption = Label.new()
	_caption.add_theme_font_override("font", FONT)
	_caption.add_theme_font_size_override("font_size", 10)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_caption)
	_title = Button.new()
	_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.add_theme_font_override("font", FONT)
	_title.add_theme_font_size_override("font_size", 13)
	_title.pressed.connect(func():
		var bp: Node = get_tree().get_first_node_in_group("backpack_panel")
		if bp != null:
			bp.open_to("quests"))
	col.add_child(_title)
	_action = Label.new()
	_action.custom_minimum_size.x = 280
	_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action.add_theme_font_override("font", FONT)
	_action.add_theme_font_size_override("font_size", 13)
	_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_action)
	_desc = Label.new()
	_desc.custom_minimum_size.x = 280
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_override("font", FONT)
	_desc.add_theme_font_size_override("font_size", 12)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_desc)
	_direction = Label.new()
	_direction.custom_minimum_size.x = 280
	_direction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_direction.add_theme_font_override("font", FONT)
	_direction.add_theme_font_size_override("font_size", 11)
	_direction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_direction)
	Quests.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var guide: Dictionary = Quests.guidance()
	_caption.text = String(guide["caption"])
	_title.text = String(guide["title"]) + " (任务)"
	_action.text = String(guide["action"])
	_action.visible = not _action.text.is_empty()
	_desc.text = String(guide["detail"])
	# 内容变短时允许面板收回, 不残留上一段多行提示的高度。
	size.y = 0

func _process(delta: float) -> void:
	if _game == null:
		return
	var blocked := Voyage.traveling or bool(_game.get("_sleeping"))
	var player: Node = _game.get("player")
	if player != null:
		blocked = blocked or bool(player.get("frozen"))
	var bp: Node = _game.get("backpack_panel")
	if bp != null:
		blocked = blocked or bp.is_open()
	visible = not blocked
	_timer += delta
	if _timer >= 0.3 and visible:
		_timer = 0.0
		_refresh()
		_update_direction()

func _update_direction() -> void:
	var guide: Dictionary = Quests.guidance()
	var target: Node2D = null
	match String(guide["target"]):
		"house": target = _game.get_node_or_null("House")
		"merchant": target = _game.get_node_or_null("Merchant")
		"shipping": target = _game.get("shipping_bin")
		"campfire": target = _game.get("campfire")
		"dock": target = _game.get("dock")
	var player: Node2D = _game.get("player")
	_direction.text = "点标题查看任务, 按 B 打开背包"
	if player == null:
		return
	if bool(player.get("indoors")):
		_direction.text = "在床边按 F 休息" if String(guide["target"]) == "house" else "先从屋门离开, 再按指引操作"
		return
	var cells: Array = guide["cells"]
	if not cells.is_empty():
		var nearest: Vector2 = Farm.grid_origin + Vector2(cells[0]) * Farm.TILE_SIZE
		for cell: Vector2i in cells:
			var point: Vector2 = Farm.grid_origin + Vector2(cell) * Farm.TILE_SIZE
			if player.global_position.distance_squared_to(point) < player.global_position.distance_squared_to(nearest):
				nearest = point
		var offset: Vector2 = nearest - player.global_position
		_direction.text = "田地: %s, 约 %d 格 (靠近后左键)" % [_game._dir_name(offset), ceili(offset.length() / Farm.TILE_SIZE)]
		return
	if target != null and player != null:
		var offset: Vector2 = target.global_position - player.global_position
		_direction.text = "方位: %s, 约 %d 格 (靠近后按 F)" % [_game._dir_name(offset), ceili(offset.length() / Farm.TILE_SIZE)]
