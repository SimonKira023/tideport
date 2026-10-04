extends PanelContainer

@onready var season_label: Label = $VBoxContainer/SeasonLabel
@onready var time_label: Label = $VBoxContainer/TimeLabel
@onready var money_label: Label = $VBoxContainer/MoneyLabel

var water_label: Label
var weather_icon: Control        # scene/weather_icon.gd 实例（自绘天气小图标）
var _last_time := ""             # C3: 上次刷新的时间/季节文字, 变了才播微动画
var _last_season := ""

func _ready() -> void:
	# 时钟面板只是显示用，不接收鼠标事件，否则会挡住鼠标左键的耕地操作
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 天气图标：摆在框内右上角的空白处。原来排在文字流末尾会溢出框外。
	# PanelContainer 会把 Control 子节点拉满内容区 —— 垫一层全矩形 holder 再定位。
	var holder := Control.new()
	holder.name = "WeatherSlot"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	weather_icon = preload("res://scene/weather_icon.gd").new()
	weather_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(weather_icon)
	# 锚在右上角，离框边留 6px；图标自身 16x16
	weather_icon.anchor_left = 1.0
	weather_icon.anchor_right = 1.0
	weather_icon.offset_left = -22.0
	weather_icon.offset_right = -6.0
	weather_icon.offset_top = 6.0
	weather_icon.offset_bottom = 22.0
	# 天气图标：翻牌（weather_changed）和换日时都重画一次
	weather_icon.set_kind(Weather.current)
	Weather.weather_changed.connect(func(k: int) -> void: weather_icon.set_kind(k))

	# 水量标签：跟时间标签用同一个像素字体；只有快捷栏选中洒水壶才显示
	water_label = Label.new()
	water_label.name = "WaterLabel"
	water_label.add_theme_font_override("font", time_label.get_theme_font("font"))
	water_label.text = ""
	water_label.visible = false
	$VBoxContainer.add_child(water_label)

	TimeManager.time_tick.connect(_refresh)
	TimeManager.new_day.connect(func(_d): _refresh())
	Wallet.money_changed.connect(func(_m): _refresh())
	Inventory.water_changed.connect(_refresh)
	# 快捷栏比本面板晚就绪：下一帧再找它挂「选中变化」信号
	_hook_hotbar.call_deferred()
	_refresh()

func _hook_hotbar() -> void:
	var hb := get_tree().get_first_node_in_group("hotbar")
	if hb != null and hb.has_signal("selection_changed"):
		hb.selection_changed.connect(_refresh)
	_refresh()

# 只有快捷栏当前格攥着洒水壶才显示水量（平时挂着分散注意力）
func _water_can_selected() -> bool:
	var hb := get_tree().get_first_node_in_group("hotbar")
	if hb == null:
		return false
	var item: ItemData = Inventory.hotbar_item(hb.selected_index)
	return item != null and item.display_name == "洒水壶"

func _refresh() -> void:
	season_label.text = TimeManager.date_text()
	# e13a: 出海时间不走, 时钟显示「航行中」；回岛固定拨到晚上十点才恢复数字
	time_label.text = "航行中" if Voyage.traveling else TimeManager.time_text()
	money_label.text = "%d 金" % Wallet.money
	water_label.visible = _water_can_selected()
	var w := Inventory.watering_can_water
	var wmax := Inventory.water_max()
	if w <= 0:
		water_label.text = "水壶: 空"
	elif w >= wmax:
		water_label.text = "水壶: 满"
	else:
		water_label.text = "水壶: %d/%d" % [w, wmax]
	# C3 只在时间/季节文字真的变了才播微动画（首帧和钱数刷新不播, 免得常驻闪烁）
	var t := String(time_label.text)
	var s := String(season_label.text)
	if _last_time != "":
		if t != _last_time:
			_pop_label(time_label)
		if s != _last_season:
			_pop_label(season_label)
	_last_time = t
	_last_season = s

# C3 文字跳动微动画: 淡入 + 轻微纵向弹起（scale/modulate 不受容器布局管理, 不会被打断）
func _pop_label(l: Label) -> void:
	if l.has_meta("tw"):
		var old: Tween = l.get_meta("tw")
		if old != null and old.is_valid():
			old.kill()
			l.modulate.a = 1.0
			l.scale = Vector2.ONE
	var tw := create_tween()
	l.set_meta("tw", tw)
	l.pivot_offset = Vector2(0.0, l.size.y * 0.5)
	l.modulate.a = 0.25
	l.scale = Vector2(1.0, 0.9)
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
