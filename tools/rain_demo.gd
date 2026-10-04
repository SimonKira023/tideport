extends Node
## rain_demo —— 雨夜氛围录制 demo（Movie Maker 专用，不影响正常游戏）。
##
## 录制命令（项目根目录）：
##   "D:\平台\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . ^
##     res://tools/rain_demo.tscn --write-movie "_demo/rain_demo.avi" --fixed-fps 30 ^
##     --windowed --resolution 1280x720
##
## 流程：裸跑（不读档/不写档/不播开局动画）→ 18:20 傍晚 + 强制下雨
##       → 48 秒慢推长镜（黄昏渐渐入夜）→ 首尾黑幕 + 电影黑边 → 自动退出。

const DURATION := 48.0    # 成片长度（秒）：5 现实秒 = 10 游戏分钟，48s ≈ 18:20 → 19:56
const FADE_IN := 1.5      # 开场黑幕淡入用时
const FADE_OUT := 1.4     # 结尾黑幕淡出用时

var _t := 0.0
var _cam: Camera2D = null
var _fader: ColorRect
var _fading_out := false

func _ready() -> void:
	SaveManager.enabled = false            # 裸跑：game._ready 走 else 分支
	var game: Node = load("res://scene/game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame         # 等 game._ready 跑完（相机/后处理都就位）
	await get_tree().process_frame
	TimeManager.time_running = true
	TimeManager.hour = 18
	TimeManager.minute = 20
	TimeManager.snap()
	Weather.current = Weather.RAIN         # 强制雨天（_refresh 按日期指纹，同日不会回滚）
	Weather.weather_changed.emit(Weather.RAIN)
	var hud_node := game.get_node_or_null("HUD")
	if hud_node != null:
		hud_node.visible = false           # 纯观影模式：时钟/金币/快捷栏不入镜
	_build_cinema()
	_fader.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fader, "color:a", 0.0, FADE_IN)

func _process(delta: float) -> void:
	_t += delta
	if _cam == null:
		_cam = get_viewport().get_camera_2d()
	elif _t > FADE_IN and _t < DURATION - FADE_OUT:
		_cam.zoom *= 1.0 + delta * 0.003   # 慢推：全程约推近 14%
	if _t >= DURATION - FADE_OUT and not _fading_out:
		_fading_out = true
		var tw := create_tween()
		tw.tween_property(_fader, "color:a", 1.0, FADE_OUT - 0.1)
	if _t >= DURATION:
		get_tree().quit()

# 电影黑边（上下各挡 5.5%）+ 首尾黑幕
func _build_cinema() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.945
		bar.anchor_bottom = 0.055 if top else 1.0
		layer.add_child(bar)
	_fader = ColorRect.new()
	_fader.color = Color(0, 0, 0, 0)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fader)
