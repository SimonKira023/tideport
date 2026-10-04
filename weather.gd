# weather.gd —— Autoload，名字：Weather
# 每日天气：晴 / 阴 / 雨 / 风暴（冬天雨显示为雪）。
#
# 天气是「日期的纯函数」—— 同一天永远同一种天气（按日期播种的伪随机，
# 跟 game.gd 篝火的播种法一个思路）。好处：
#   · 存档不用存天气字段 —— 读档/开新档按日期重算一遍就是原样；
#   · 明天的天气现在就能预报（睡觉菜单的「明晨有雨」提示）；
#   · 自检可以精确复现任意一天的天气。
#
# 开局第 1 天固定晴天 —— 教学周好办事，玩家不会被第一场雨打蒙。
#
# 信号 weather_changed(kind)：翻牌时发。雨效粒子 / 时钟图标 / 昼夜光照听它翻状态。
extends Node

signal weather_changed(kind: int)

const SUNNY := 0
const CLOUDY := 1
const RAIN := 2
const STORM := 3
const NAMES := ["晴", "阴", "雨", "风暴"]

# 各季节出现风暴/雨/阴的概率（下标 春/夏/秋/冬）。夏天雷雨最多，冬天几乎没风暴。
const STORM_CHANCE := [0.05, 0.13, 0.05, 0.02]
const RAIN_CHANCE := [0.24, 0.15, 0.18, 0.16]
const CLOUDY_CHANCE := [0.24, 0.22, 0.26, 0.30]

var current := SUNNY

var _cached_key := -1      # 上次算天气时的日期指纹（年*10000 + 季*100 + 日）

func _ready() -> void:
	# e30g: new_day 信号里同步刷新 —— 之前只靠 _process 懒刷新，而 Farm 在
	# new_day 信号里就查 is_rain()，那时 current 还是昨天的天气：
	# 雨天当早读到昨天(晴)不浇水，次日(没雨)反而吃到昨天的雨。
	# autoload 序 Weather 在 Farm 之前，这里先连接的先处理，Farm 读到的就是新一天的天气。
	TimeManager.new_day.connect(_refresh)   # 信号带 day 参数, _refresh 用可省默认参接住
	_refresh()

func _process(_delta: float) -> void:
	# 读档 / 开新档不走 new_day 信号（日期是直接写回的），每帧比对日期兜底。
	# 日期没变时一次比较就返回，开销可以忽略。
	_refresh()

func _refresh(_day: int = -1) -> void:
	var key: int = TimeManager.year * 10000 + TimeManager.season * 100 + TimeManager.day
	if key == _cached_key:
		return
	_cached_key = key
	var kind: int = roll_for(TimeManager.year, TimeManager.season, TimeManager.day)
	if kind != current:
		current = kind
		weather_changed.emit(current)

# ---------------- 查询 ----------------
func is_rain() -> bool:
	return current == RAIN or current == STORM

func is_storm() -> bool:
	return current == STORM

# 今天的天气名（冬天的雨显示为「雪」）
func name_text() -> String:
	return name_text_for(current, TimeManager.season)

# 明天的年/季/日（跨季跨年进位）
func tomorrow_ymd() -> Array:
	var d := TimeManager.day + 1
	var s := TimeManager.season
	var y := TimeManager.year
	if d > TimeManager.DAYS_PER_SEASON:
		d = 1
		s += 1
		if s > 3:
			s = 0
			y += 1
	return [y, s, d]

# 明天的天气名 —— 睡觉菜单的「明晨有雨」提示用
func tomorrow_name_text() -> String:
	var t: Array = tomorrow_ymd()
	return name_text_for(roll_for(int(t[0]), int(t[1]), int(t[2])), int(t[1]))

func is_tomorrow_rain() -> bool:
	var t: Array = tomorrow_ymd()
	var k: int = roll_for(int(t[0]), int(t[1]), int(t[2]))
	return k == RAIN or k == STORM

# ---------------- 纯函数（selftest 直接测） ----------------
# 某年某季某天的天气。同一天永远同一个结果。
static func roll_for(y: int, s: int, d: int) -> int:
	if y == 1 and s == 0 and d == 1:
		return SUNNY        # 开局第一天固定晴天
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather") + y * 100000 + s * 1000 + d * 7
	var r := rng.randf()
	if r < STORM_CHANCE[s]:
		return STORM
	if r < STORM_CHANCE[s] + RAIN_CHANCE[s]:
		return RAIN
	if r < STORM_CHANCE[s] + RAIN_CHANCE[s] + CLOUDY_CHANCE[s]:
		return CLOUDY
	return SUNNY

# 天气显示名：冬天的雨叫雪（风暴在冬天也照叫风暴，反正几乎碰不上）
static func name_text_for(kind: int, season: int) -> String:
	if season == 3 and kind == RAIN:
		return "雪"
	return NAMES[kind]
