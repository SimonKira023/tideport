extends CanvasModulate

const COLOR_NIGHT := Color(0.2, 0.22, 0.42)    # 深蓝夜色
const COLOR_PREDAWN := Color(0.45, 0.50, 0.62) # 破晓前的青灰
const COLOR_DAWN  := Color(0.93, 0.70, 0.60)   # 晨光粉金
const COLOR_DUSK  := Color(0.95, 0.6, 0.45)    # 橙红黄昏
const COLOR_NOON  := Color(1, 1, 1)            # 正午纯白（原色）

var _target := COLOR_NOON

func _ready() -> void:
	TimeManager.time_tick.connect(_update_target)
	TimeManager.new_day.connect(func(_d): _update_target())
	Weather.weather_changed.connect(func(_k: int) -> void: _update_target())
	_update_target()

func _update_target() -> void:
	var h := TimeManager.hour + TimeManager.minute / 60.0
	_target = _color_at(h)

# 每帧平滑过渡到目标颜色，避免突变
func _process(delta: float) -> void:
	color = color.lerp(_target, delta * 3.0)

func _color_at(h: float) -> Color:
	var c: Color
	if h >= 4.5 and h < 6.0:            # 4.5~6点 破晓前：夜→青灰
		c = COLOR_NIGHT.lerp(COLOR_PREDAWN, (h - 4.5) / 1.5)
	elif h >= 6.0 and h < 7.5:          # 6~7.5点 晨光：青灰→粉金
		c = COLOR_PREDAWN.lerp(COLOR_DAWN, (h - 6.0) / 1.5)
	elif h >= 7.5 and h < 9.0:          # 7.5~9点 日升：粉金→正午
		c = COLOR_DAWN.lerp(COLOR_NOON, (h - 7.5) / 1.5)
	elif h >= 9.0 and h < 18.0:         # 9~18点 白天：全亮
		c = COLOR_NOON
	elif h >= 18.0 and h < 20.0:        # 18~20点 黄昏：偏橙
		c = COLOR_NOON.lerp(COLOR_DUSK, (h - 18.0) / 2.0)
	elif h >= 20.0 and h < 22.0:        # 20~22点 入夜：橙→深蓝
		c = COLOR_DUSK.lerp(COLOR_NIGHT, (h - 20.0) / 2.0)
	else:                               # 22~4.5点 夜晚：深蓝
		c = COLOR_NIGHT
	# 白天到黄昏段遇雨/雪压暗偏灰（风暴更暗）；夜里本来就深蓝，不再叠加免得过黑
	if Weather.is_rain() and h >= 4.5 and h < 20.0:
		c = c.darkened(0.35 if Weather.is_storm() else 0.18)
	return c
