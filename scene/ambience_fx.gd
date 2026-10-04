extends Node
# D1 岛上环境音层: 海浪(常驻) / 风(夜·冬·风暴) / 鸟鸣(晴朗白天)
# 屋内压到 1/4(读 Audio.indoor_gain()); 仿 rain_fx 自管模式, 不占 Audio 的 SFX 池
const WAVE_DB := -21.0
const WIND_DB := -20.0
const BIRD_DB := -20.0
const CRICKET_DB := -26.0
const FROG_DB := -27.0
const FADE := 2.5

var _wave: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _bird: AudioStreamPlayer
var _cricket: AudioStreamPlayer
var _frog: AudioStreamPlayer
var _g_wave := 0.0
var _g_wind := 0.0
var _started := false

# 鸟鸣: 到点随机叫一声（从头播 + 音高微随机）, 不再整段循环 --
# 同一段录音 LOOP_FORWARD 循环, 叫声一模一样一遍遍重复, 还会从样本中间接续出半截叫声,
# 停着不动听久了就是「莫名其妙的音效重复播放」。
var _bird_cool := 3.0
# 蟋蟀/蛙声同款「到点叫一声」: 蟋蟀晴天夜里, 蛙雨天(昼夜都叫, 雨夜最活) —— 昼夜声景闭环
var _cricket_cool := 2.0
var _frog_cool := 4.0

func _ready() -> void:
	_wave = _voice("res://resources/audio/sfx/amb_wave.wav")
	_wind = _voice("res://resources/audio/sfx/amb_wind.wav")
	_bird = _voice("res://resources/audio/sfx/amb_bird.wav", false)
	_cricket = _voice("res://resources/audio/sfx/amb_cricket.wav", false)
	_frog = _voice("res://resources/audio/sfx/amb_frog.wav", false)

func _voice(path: String, looped := true) -> AudioStreamPlayer:
	var s: AudioStream = load(path)
	if s == null:
		return null
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
		if looped:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			var ch := 2 if w.stereo else 1
			w.loop_end = maxi(int(w.data.size() / 2 / ch), 1)   # 16bit
		else:
			w.loop_mode = AudioStreamWAV.LOOP_DISABLED
		s = w
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -60.0
	add_child(p)
	return p

func _process(delta: float) -> void:
	if _wave == null and _bird == null and _cricket == null and _frog == null:
		return
	var night := TimeManager.hour >= 19 or TimeManager.hour < 6
	var want_wave := 1.0
	var want_wind := 1.0 if (night or TimeManager.season == 3 or Weather.is_storm()) else 0.25
	var want_bird := 1.0 if (not night and not Weather.is_rain() and TimeManager.season != 3) else 0.0
	# 蟋蟀: 晴朗的夜里(冬天太冷不叫); 蛙: 雨天昼夜都叫(冬天蛰伏)
	var want_cricket := 1.0 if (night and not Weather.is_rain() and TimeManager.season != 3) else 0.0
	var want_frog := 1.0 if (Weather.is_rain() and TimeManager.season != 3) else 0.0
	var muffle := Audio.indoor_gain()
	_g_wave = move_toward(_g_wave, want_wave * muffle, delta / FADE)
	_g_wind = move_toward(_g_wind, want_wind * muffle, delta / FADE)
	# 鸟鸣: 随机隔 5~16 秒叫一声, 白天晴天才有; 屋里按 muffle 压音量
	_bird_cool -= delta
	if _bird_cool <= 0.0:
		_bird_cool = randf_range(5.0, 16.0)
		if want_bird > 0.0 and _bird != null and not _bird.playing:
			_bird.pitch_scale = randf_range(0.92, 1.08)
			_bird.volume_db = linear_to_db(muffle) + BIRD_DB
			_bird.play()
	if _bird != null and _bird.playing:
		_bird.volume_db = linear_to_db(muffle) + BIRD_DB
	# 蟋蟀: 隔 2.5~8 秒唧一声, 晴夜限定
	_cricket_cool -= delta
	if _cricket_cool <= 0.0:
		_cricket_cool = randf_range(2.5, 8.0)
		if want_cricket > 0.0 and _cricket != null and not _cricket.playing:
			_cricket.pitch_scale = randf_range(0.93, 1.07)
			_cricket.volume_db = linear_to_db(muffle) + CRICKET_DB
			_cricket.play()
	# 蛙声: 隔 3~10 秒呱一声, 雨天限定
	_frog_cool -= delta
	if _frog_cool <= 0.0:
		_frog_cool = randf_range(3.0, 10.0)
		if want_frog > 0.0 and _frog != null and not _frog.playing:
			_frog.pitch_scale = randf_range(0.88, 1.12)
			_frog.volume_db = linear_to_db(muffle) + FROG_DB
			_frog.play()
	_set_gain(_wave, _g_wave, WAVE_DB)
	_set_gain(_wind, _g_wind, WIND_DB)
	if _g_wave <= 0.0 and _g_wind <= 0.0:
		if _started:
			for p in [_wave, _wind]:
				if p != null:
					p.stop()
			_started = false
	else:
		if not _started:
			for p in [_wave, _wind]:
				if p != null:
					p.play(randf() * 2.0)   # 各自错开入点
			_started = true

func _set_gain(p: AudioStreamPlayer, g: float, base_db: float) -> void:
	if p == null:
		return
	p.volume_db = -60.0 if g <= 0.001 else linear_to_db(g) + base_db
