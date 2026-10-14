extends Node2D
# q2 太阳/月亮：全场景 DirectionalLight2D —— 光的方向/色温随时刻扫过全场。
#
# 白天是太阳：给全场加一层随时间扫动方向、随时辰变暖变冷的平行光。
#
# ❗这盏灯**不开影子**（shadow_enabled=false）。原因：俯视 2D 里平行光的影子是
#   「半无限长条」——不落在物体身边，而是沿光向一路拖到屏幕外。太阳一低（清晨/傍晚），
#   每个遮挡体都拖出一条横贯全屏的暗带，就是「影子被拉成长条」。
#   调 shadow_color 只能整体调深浅、调不掉形状，实测开影与关影的差异图是一大片
#   屏幕级的斜带（不是物体轮廓）。所以太阳只负责「光」，
#   角色/树木/建筑脚底那种按物体轮廓走的落地影子，由 shadow_util.make_shadow 的椭圆影负责。
#
# 夜里淡成月亮：冷蓝低亮度，角度固定。色温跟着太阳高度走：正午白亮、晨昏偏橙。
#
# rotation 约定：DirectionalLight2D rotation=0 时光线朝屏幕下方走。
# 白天 rotation 从 PI/2（太阳在东、影子指西）扫到 3PI/2（太阳在西、影子指东），
# 正午 PI（太阳在正南）。夜里 lerp 到月亮固定角 PI*1.4。
const DAY_FROM := 6.0            # 日出
const DAY_TO := 19.0             # 日落
const ENERGY_NOON := 0.42        # 正午亮度（CanvasModulate 白天本身已亮, 只是加一层方向感）
const ENERGY_DUSK := 0.20        # 晨昏亮度
const ENERGY_MOON := 0.10        # 月光亮度（夜里还有 CanvasModulate 压底色）

var _light: DirectionalLight2D = null
var _game: Node = null

func setup(g: Node) -> void:
	_game = g

func _ready() -> void:
	_light = DirectionalLight2D.new()
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.shadow_enabled = false
	add_child(_light)
	_apply()

func _process(_delta: float) -> void:
	_apply()

func _apply() -> void:
	# 色调钟 = 真实钟 + TONE_ADVANCE: 太阳东升西落整体提早两小时(跟昼夜色调/后处理同一套基准)
	var h: float = TimeManager.hour + TimeManager.minute / 60.0 + TimeManager.TONE_ADVANCE
	var day_t := clampf((h - DAY_FROM) / (DAY_TO - DAY_FROM), 0.0, 1.0)
	# 夜度优先读 game 里 fx_post 那套平滑夜度（跟画面暗下去的节奏一致）
	var night := 0.0
	if _game != null and "_post_night" in _game:
		night = _game._post_night
	else:
		night = 0.0 if (h >= DAY_FROM and h < DAY_TO) else 1.0
	# 光的方向：清晨从东边来 → 正午在正南 → 傍晚从西边来
	var sun_rot := PI * 0.5 + PI * day_t
	var moon_rot := PI * 1.4
	_light.rotation = lerp_angle(sun_rot, moon_rot, night)
	# 太阳高度（0=地平线 1=头顶）决定亮度与色温
	var elev := sin(PI * day_t)
	var warm := 1.0 - elev
	var sun_col := Color(1.0, 0.97 - warm * 0.25, 0.88 - warm * 0.45)
	var moon_col := Color(0.62, 0.72, 1.0)
	var energy := lerpf(lerpf(ENERGY_DUSK, ENERGY_NOON, elev), ENERGY_MOON, night)
	# k4 冬天雪地反光强, 加法太阳叠上去整屏过曝 —— 雪季白天的太阳压狠一点
	# （白刃雪场 255 底再叠光只会推平成 255 白板, 实测冬天白天 p75 全在裁切）,
	# 夜里月光不动（冬夜亮度已四季对齐）
	if TimeManager.season == 3:
		energy = lerpf(energy * 0.20, energy, night)
	_light.energy = energy
	_light.color = sun_col.lerp(moon_col, night)
	# 影子：不开（见文件头）。太阳只调能量/颜色/方向。
