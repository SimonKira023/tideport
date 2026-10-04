# rain_fx.gd —— 雨 / 雪 / 风暴的屏幕级天气粒子，跟着相机走（仿 fx_dust.gd 的跟随）。
#
# Weather 翻牌（weather_changed）时重配参数：
#   · 雨：细密斜落的小雨丝；风暴：又急又斜又密；
#   · 冬天（季节 == 3）下雨改播成雪：白点慢飘；
#   · 晴/阴：停发（已落的粒子自然掉完）。
#
# 风暴另带雷电：随机间隔发 thunder 信号（game.gd 接住 → HUD 闪白 + 雷声）。
# 自带循环雨声（rain.wav 程序合成），进雨天淡入、出雨天淡出 —— 两层错开播，见下面注释。
# 音频缺失不报错 —— 静默没声（跟 audio_manager 一个脾气）。
extends CPUParticles2D

signal thunder

const RAIN_COLOR := Color(0.62, 0.72, 0.95, 0.5)
const SNOW_COLOR := Color(1, 1, 1, 0.85)

# ---- 循环雨声（e30w 去重复）----
# 单层循环的毛病：同一条 WAV 每隔几秒原样重来一次，「接缝」听得很清楚（像卡带）。
# 现在两层同时播同一条雨声，但各自抽不同的音高（pitch_scale ±6%）和不同的入点（play 的起点），
# 两条循环的周期不一样 → 永远对不齐，要等两个周期的最小公倍数才重合（几十秒级，听不出来）。
# 再让两层的音量配比慢慢来回漂（0.3~0.7 交叉淡化），谁都不长期当主角，接缝就更没有固定落点。
# 每场雨开播时重抽一次音高/入点 —— 今天和明天的雨声不是同一条。
const RAIN_DB := -19.0          # 单层满音量；两层不相关叠加约 +3dB，合起来 ≈ 原来的 -16
const PITCH_JITTER := 0.06
const FADE_IN := 1.5
const FADE_OUT := 1.2
const MIX_MIN := 0.3            # 配比漂移的下限（再低那层就快听不见了，遮不住接缝）
const MIX_MAX := 0.7

var _audio_a: AudioStreamPlayer
var _audio_b: AudioStreamPlayer
var _rain_len := 0.0            # 一条循环有多长（秒）
var _gain := 0.0                # 总音量包络: 0 = 静音, 1 = 满
var _mix := 0.5                 # A 层的占比（B 层就是 1 - _mix），两层加起来恒为 1
var _mix_to := 0.5              # 配比要漂去的目标
var _mix_t := 6.0               # 下一次换配比的倒计时
var _playing := false

var _bolt_t := 8.0

func _ready() -> void:
	z_index = 60            # 盖在角色之上（跟光尘同层）；被 NightOverlay 和各面板压住
	texture = _make_streak()
	emission_shape = EMISSION_SHAPE_RECTANGLE
	emission_rect_extents = Vector2(330, 200)   # 盖住 zoom 最低时的视野
	Weather.weather_changed.connect(func(_k: int) -> void: _apply())
	_build_audio()
	_apply()

# 2x6 的小竖条纹理 —— 拉上速度就是雨丝
func _make_streak() -> ImageTexture:
	var img := Image.create(2, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 2:
			img.set_pixel(x, y, Color(1, 1, 1, 0.85))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	_tick_audio(delta)
	# 风暴的滚雷计时（只在风暴天走表）
	if Weather.is_storm():
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			_bolt_t = randf_range(9.0, 22.0)
			thunder.emit()

# 按 Weather.current + 当前季节重配整套粒子参数
func _apply() -> void:
	if Weather.is_rain():
		emitting = true
		if TimeManager.season == 3:
			_snow()
		else:
			_rain()
	else:
		emitting = false
	# 雨声的进出场不在这儿切 —— 由 _tick_audio 按 Weather.is_rain() 逐帧推音量包络

func _rain() -> void:
	var storm := Weather.is_storm()
	amount = 330 if storm else 200
	lifetime = 0.9
	preprocess = 1.0        # 开局天上就挂满雨，不用等从零落下
	direction = Vector2(0.35, 1.0) if storm else Vector2(0.12, 1.0)
	spread = 4.0
	gravity = Vector2(40, 380)
	initial_velocity_min = 240.0
	initial_velocity_max = 320.0
	scale_amount_min = 0.8
	scale_amount_max = 1.1
	color = RAIN_COLOR.darkened(0.15) if storm else RAIN_COLOR
	if storm:
		_bolt_t = randf_range(4.0, 10.0)   # 一进风暴先来一记近雷

func _snow() -> void:
	amount = 90
	lifetime = 6.0
	preprocess = 6.0
	direction = Vector2(0.15, 1.0)
	spread = 14.0
	gravity = Vector2.ZERO
	initial_velocity_min = 14.0
	initial_velocity_max = 26.0
	scale_amount_min = 1.0
	scale_amount_max = 1.7
	color = SNOW_COLOR

# ---------------- 循环雨声 ----------------
func _build_audio() -> void:
	var s: AudioStream = load("res://resources/audio/sfx/rain.wav")
	var stream: AudioStream = null
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
		# WAV 导入默认不循环 —— 手动把循环点设成整段（跟 audio_manager 一个做法）
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		var bps := 2
		if w.format == AudioStreamWAV.FORMAT_8_BITS:
			bps = 1
		var ch := 2 if w.stereo else 1
		var frames := maxi(int(w.data.size() / (bps * ch)), 1)
		w.loop_end = frames
		stream = w
		_rain_len = float(frames) / maxf(float(w.mix_rate), 1.0)   # 自己算时长，别指望 get_length()
	_audio_a = _make_voice(stream)
	_audio_b = _make_voice(stream)

func _make_voice(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -60.0
	add_child(p)
	return p

# 逐帧推音量包络（不用 Tween: 交叉淡化会跟进出场抢同一个 volume_db）
func _tick_audio(delta: float) -> void:
	if _audio_a == null or _audio_a.stream == null:
		return
	var want := 1.0 if Weather.is_rain() else 0.0
	_gain = move_toward(_gain, want, delta / (FADE_IN if want > 0.0 else FADE_OUT))
	if _gain <= 0.0:
		if _playing:
			_audio_a.stop()
			_audio_b.stop()
			_playing = false
		return
	if not _playing:
		_start_voices()
	# 配比慢慢漂: 两层加起来恒为 _gain, 总响度不变, 只是"谁在台前"来回换
	_mix_t -= delta
	if _mix_t <= 0.0:
		_mix_t = randf_range(7.0, 13.0)
		_mix_to = randf_range(MIX_MIN, MIX_MAX)
	_mix = move_toward(_mix, _mix_to, delta / 3.0)
	_audio_a.volume_db = _voice_db(_gain * _mix)
	_audio_b.volume_db = _voice_db(_gain * (1.0 - _mix))

# 开播：每场雨重抽音高与入点，两层各走各的
func _start_voices() -> void:
	_audio_a.pitch_scale = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	_audio_b.pitch_scale = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	_audio_a.play(0.0)
	# B 从循环中段随机一处进来 —— 跟 A 错开相位
	_audio_b.play(randf_range(_rain_len * 0.3, _rain_len * 0.7) if _rain_len > 0.0 else 0.0)
	_playing = true

func _voice_db(g: float) -> float:
	return -60.0 if g <= 0.001 else linear_to_db(g) + RAIN_DB
