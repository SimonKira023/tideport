extends CanvasModulate

const COLOR_NIGHT := Color(0.2, 0.22, 0.42)    # 深蓝夜色
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
	if h >= 6.0 and h < 8.0:            # 6~8点 黎明：夜→亮
		c = COLOR_NOON
	elif h >= 8.0 and h < 18.0:         # 8~18点 白天：全亮
		c = COLOR_NOON
	elif h >= 18.0 and h < 20.0:        # 18~20点 黄昏：偏橙
		c = COLOR_NOON.lerp(COLOR_DUSK, (h - 18.0) / 2.0)
	elif h >= 20.0 and h < 22.0:        # 20~22点 入夜：橙→深蓝
		c = COLOR_DUSK.lerp(COLOR_NIGHT, (h - 20.0) / 2.0)
	else:                               # 22~6点 夜晚：深蓝
		c = COLOR_NIGHT
	# 白天到黄昏段遇雨/雪压暗偏灰（风暴更暗）；夜里本来就深蓝，不再叠加免得过黑
	if Weather.is_rain() and h >= 6.0 and h < 20.0:
		c = c.darkened(0.35 if Weather.is_storm() else 0.18)
	return c
