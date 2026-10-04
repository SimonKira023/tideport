# tools/make_ambience.gd —— 程序合成氛围音频：海浪/风/鸟鸣三层环境音 + 三种材质脚步。
# 跟 make_weather_audio.gd 一个道理：本机没有可用的 Python，用 AudioStreamWAV.save_to_wav 直写。
#
# 跑法（headless 即可）：
#   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> --script res://tools/make_ambience.gd
# 跑完记得 --import 重新导入资源，游戏里才会读到新 WAV。
extends SceneTree

const SR := 22050

var buf := PackedFloat32Array()
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	print("合成氛围音频...")
	make_wave()
	save_wav("res://resources/audio/sfx/amb_wave.wav")
	make_wind()
	save_wav("res://resources/audio/sfx/amb_wind.wav")
	make_bird()
	save_wav("res://resources/audio/sfx/amb_bird.wav")
	make_step_wood()
	save_wav("res://resources/audio/sfx/step_wood.wav")
	make_step_stone()
	save_wav("res://resources/audio/sfx/step_stone.wav")
	make_step_sand()
	save_wav("res://resources/audio/sfx/step_sand.wav")
	quit()

# 海浪：重低通噪声做「轰」的底，8 秒里两个浪涌（快起慢落），浪峰处叠一层浅低通的泡沫沙沙。
func make_wave() -> void:
	var dur := 8.0
	var xf := int(0.4 * SR)
	var n := int(dur * SR)
	var total := n + xf
	buf.resize(total)
	buf.fill(0.0)
	rng.seed = 20260930
	var lp_a := 0.0
	var lp_b := 0.0
	var lp_f := 0.0
	for i in total:
		var x := rng.randf_range(-1.0, 1.0)
		lp_a += 0.045 * (x - lp_a)     # 深低通: 远处海面的隆隆
		lp_b += 0.012 * (lp_a - lp_b)  # 更深一层: 掉掉全部毛刺
		lp_f += 0.16 * (x - lp_f)      # 浅低通: 泡沫的高频沙沙
		var t := i / float(SR)
		# 浪涌包络: 两个整周期, 每个涌是快起(前 35%)慢退 —— sin 取 2 次幂再前移出不对称
		var ph := fposmod(t * 2.0, 1.0)
		var surge := pow(maxf(sin(PI * ph), 0.0), 1.6)
		surge = surge * surge          # 更尖的峰
		buf[i] = (lp_b * 3.0 + lp_a * 0.8 * surge) + lp_f * 0.9 * surge * surge
	# 极慢的整体起伏(整周期, 循环同相位)
	for i in total:
		var t2 := i / float(SR)
		buf[i] *= 0.82 + 0.18 * sin(TAU * t2 / dur)
	_cross_tail(xf, n)

# 风：中低通噪声「呼——」, 三层整周期正弦包络叠出风向摆动, 再混一层更闷的远处层。
func make_wind() -> void:
	var dur := 9.0
	var xf := int(0.4 * SR)
	var n := int(dur * SR)
	var total := n + xf
	buf.resize(total)
	buf.fill(0.0)
	rng.seed = 20260931
	var lp1 := 0.0
	var lp2 := 0.0
	var lp_deep := 0.0
	for i in total:
		var x := rng.randf_range(-1.0, 1.0)
		lp1 += 0.09 * (x - lp1)        # 主体: 呼声的躯干
		lp2 += 0.035 * (lp1 - lp2)     # 再滤: 掉高音毛刺
		lp_deep += 0.014 * (x - lp_deep)
		buf[i] = lp2 * 3.2 + lp_deep * 1.4
	for i in total:
		var t := i / float(SR)
		var env := 0.55 \
			+ 0.22 * sin(TAU * 3.0 * t / dur) \
			+ 0.15 * sin(TAU * 7.0 * t / dur + 1.1) \
			+ 0.08 * sin(TAU * 13.0 * t / dur + 2.4)
		buf[i] *= maxf(env, 0.12)
	_cross_tail(xf, n)

# 鸟鸣: 干净底 + 数声短促下滑 chirp(3800→2600Hz 正弦扫频), 固定 seed, 循环头尾留白防切断。
func make_bird() -> void:
	var dur := 6.0
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	rng.seed = 20260932
	var t := 0.35
	while t < dur - 0.45:
		var syll := 1 if rng.randf() < 0.62 else 2     # 单音节 / 双音节
		for s in syll:
			var len := rng.randf_range(0.09, 0.16)
			var i0 := int(t * SR)
			var ni := int(len * SR)
			var f0 := rng.randf_range(3300.0, 4100.0)
			var f1 := f0 * rng.randf_range(0.55, 0.72)
			for k in ni:
				var u := k / float(ni)
				var f := lerpf(f0, f1, u)
				var env := sin(PI * u) * sin(PI * u)   # 纺锤包络
				buf[i0 + k] += sin(TAU * f * u * len) * 0.5 * env
			t += len + 0.07
		t += rng.randf_range(0.45, 1.15)
	# 头尾各留 0.35s 静音, 循环接缝天然无痕, 不做折回淡化

# 木板脚步: 120Hz 短敲(音高微降) + 噪声瞬态, 闷「笃」。
func make_step_wood() -> void:
	var dur := 0.13
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	rng.seed = 3301
	for i in n:
		var t := i / float(SR)
		var f := 130.0 - 40.0 * (t / dur)
		var env := exp(-26.0 * t)
		buf[i] = sin(TAU * f * t) * 0.8 * env \
			+ rng.randf_range(-1.0, 1.0) * 0.35 * exp(-60.0 * t)
	_attack(n)

# 石径脚步: 中高频噪声瞬态, 干脆「嗒」。
func make_step_stone() -> void:
	var dur := 0.09
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	rng.seed = 3302
	var lp := 0.0
	for i in n:
		var t := i / float(SR)
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.3 * (x - lp)                 # 半开低通: 脆而不刺
		var env := exp(-38.0 * t)
		buf[i] = lp * 1.6 * env + x * 0.25 * exp(-90.0 * t)
	_attack(n)

# 沙地脚步: 低通噪声的沙沙, 稍长稍软「沙」。
func make_step_sand() -> void:
	var dur := 0.15
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	rng.seed = 3303
	var lp := 0.0
	for i in n:
		var t := i / float(SR)
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.11 * (x - lp)
		var env := exp(-20.0 * t) * (1.0 + 0.4 * sin(TAU * 9.0 * t))
		buf[i] = lp * 2.2 * env
	_attack(n)

# 循环素材共用: 尾巴 xf 长度折回头部交叉淡化(跟 make_weather_audio 一个做法)
func _cross_tail(xf: int, n: int) -> void:
	for i in xf:
		var k := i / float(xf)
		buf[i] = buf[i] * k + buf[n + i] * (1.0 - k)
	buf.resize(n)

# 一次性音效共用: 起音 3ms 快速淡入防爆音
func _attack(n: int) -> void:
	var atk := int(0.003 * SR)
	for i in mini(atk, n):
		buf[i] *= i / float(atk)

func save_wav(path: String, gain := 0.9) -> void:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var k := 0.0
	if peak > 1e-6:
		k = 0.84 / peak * gain
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i] * k, -1.0, 1.0) * 32767.0))
	wav.data = bytes
	var err := wav.save_to_wav(path)
	print("  %s  %.2f 秒  err=%d" % [path.get_file(), buf.size() / float(SR), err])
