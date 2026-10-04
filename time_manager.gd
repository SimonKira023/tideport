extends Node

signal time_tick            # 每游戏10分钟触发一次
signal day_ended            # 玩家睡觉/昏迷，当天结束
signal new_day(day: int)    # 新的一天开始了
signal season_changed(new_season: int)   # 换季瞬间（advance_day 进位时发，game.gd 接住飘提示）

const SEASONS := ["春", "夏", "秋", "冬"]
const DAYS_PER_SEASON := 28
const START_HOUR := 6
const REAL_SECONDS_PER_10MIN := 5.0   # e29g: 现实5秒 = 游戏10分钟(原7秒) —— 一天14分钟压到10分钟, 更紧凑; 出海时间已完全停止(e13a), 此常量只管岛上

var year := 1
var season := 0        # 0春 1夏 2秋 3冬
var day := 1           # 当季第几天
var hour := START_HOUR
var minute := 0
var time_running := false
var speed_scale := 1.0        # 时间流速倍率（战场慢放走 Engine.time_scale, 此倍率目前只被 selftest 用作测试旋钮）

var _acc := 0.0
var _ui_pause_stack := []     # 见 push_ui_pause：面板一层层开也不会乱

func _ready() -> void:
	start_new_day()

# 开新档：回到第 1 年第 1 天早上 6 点，时间开始流动（由 save_manager.reset_all 调用）。
# 面板暂停栈也要清空 —— 上一把要是死在某个面板开着的时候，栈里会留着脏记录，
# 新档的时间就再也走不起来了（push/pop 不成对）。
func reset_for_new_game() -> void:
	year = 1
	season = 0
	day = 1
	_ui_pause_stack.clear()
	start_new_day()

# ---------------- 界面暂停 ----------------
# 背包(Esc) / 商店 / 码头这类面板开着时把时间停住 —— 翻着背包天就黑了很出戏。
# 用栈而不是一个布尔：面板套着开（商店里又开背包）时，得等最外层关了才恢复。
# 栈里存的是「开面板那一刻时间是走着的吗」，所以睡觉/出海时开面板也不会误放行。
func push_ui_pause() -> void:
	_ui_pause_stack.append(time_running)
	time_running = false

func pop_ui_pause() -> void:
	if _ui_pause_stack.is_empty():
		return
	var prev: bool = _ui_pause_stack.pop_back()
	if _ui_pause_stack.is_empty():
		time_running = prev


func start_new_day() -> void:
	hour = START_HOUR
	minute = 0
	_acc = 0.0
	time_running = true
	new_day.emit(day)

# e27a: 直接改 hour 的地方（回岛拨 22 点）调一下 —— 立刻广播一次 tick,
# 昼夜色和时钟文字马上跟上。不然要等下一个 7 秒 tick 才刷新,
# 回岛头几秒全岛还停在出海前的颜色（看着像闪了段白天）。
func snap() -> void:
	time_tick.emit()

func _process(delta: float) -> void:
	if not time_running:
		return
	_acc += delta * speed_scale
	if _acc < REAL_SECONDS_PER_10MIN:
		return
	_acc = 0.0
	minute += 10
	if minute >= 60:
		minute = 0
		hour += 1
		if hour >= 26:      # 凌晨2点强制收尾
			if Voyage.traveling:
				advance_day()   # 出海没床可躺：静默翻日，别弹睡觉结算（人在海图上）
			else:
				pass_out()
	time_tick.emit()

func pass_out() -> void:
	time_running = false
	day_ended.emit()

func go_to_bed() -> void:
	time_running = false
	day_ended.emit()

func advance_day() -> void:
	day += 1
	if day > DAYS_PER_SEASON:
		day = 1
		season += 1
		if season > 3:
			season = 0
			year += 1
		season_changed.emit(season)   # 换季了（new_day 会紧跟着发, Farm 在那一步枯作物）
	start_new_day()

func time_text() -> String:
	var h := hour % 24
	var ampm := "上午" if h < 12 else "下午"
	return "%s %d:%02d" % [ampm, h, minute]

func date_text() -> String:
	return "%s季 第 %d 天" % [SEASONS[season], day]
