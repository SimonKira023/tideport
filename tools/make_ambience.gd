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
	make_cricket()
	save_wav("res://resources/audio/sfx/amb_cricket.wav")
	make_frog()
	save_wav("res://resources/audio/sfx/amb_frog.wav")
	make_step_wood()
	save_wav("res://resources/audio/sfx/step_wood.wav")
	make_step_stone()
	save_wav("res://resources/audio/sfx/step_stone.wav")
	make_step_sand()
	save_wav("res://resources/audio/sfx/step_sand.wav")
	quit()

# 海浪 v2 —— 浪涌事件表根除「摩擦」声。旧版 fposmod(t*2,1) 是固定节拍器: 每 0.5 秒一圈
# 一模一样的浪, 8 秒样本 16 圈等距浪, 循环播起来频谱上就是等距条纹(视频里那阵摩擦声的
# 真凶——上轮只修了雨声, 浪声漏网)。v2 每个浪的时间/峰高/起落速度全随机, 快起慢落像真浪;
# 底噪无限流连续, 接缝交叉淡化无痕; 整体起伏也从整周期正弦换成随机漫步。
func make_wave() -> void:
	var dur := 12.0
	var xf := int(0.5 * SR)
	var n := int(dur * SR)
	var total := n + xf
	buf.resize(total)
	buf.fill(0.0)
	rng.seed = 20260930
	var lp_a := 0.0
	var lp_b := 0.0
	var lp_f := 0.0
	var base := PackedFloat32Array()
	var mid := PackedFloat32Array()
	var foam := PackedFloat32Array()
	base.resize(total)
	mid.resize(total)
	foam.resize(total)
	for i in total:
		var x := rng.randf_range(-1.0, 1.0)
		lp_a += 0.045 * (x - lp_a)     # 深低通: 远处海面的隆隆
		lp_b += 0.012 * (lp_a - lp_b)  # 更深一层: 掉掉全部毛刺
		lp_f += 0.16 * (x - lp_f)      # 浅低通: 泡沫的高频沙沙
		base[i] = lp_b * 3.0           # 常驻底: 浪来浪去都在
		mid[i] = lp_a                  # 浪身: 随浪涌抬
		foam[i] = lp_f                 # 浪花: 峰顶才哗出来
	# 整体起伏: 随机漫步控制点(余弦平滑, 首尾同值) —— 跟 rain.wav 同款手法
	var seg := 2.4
	var kn := int(ceil(dur / seg)) + 1
	var knots := PackedFloat32Array()
	knots.resize(kn)
	for k in kn:
		knots[k] = rng.randf_range(0.8, 1.0)
	knots[0] = 0.92
	knots[kn - 1] = knots[0]
	# 浪涌事件表: [t0, peak, rise, fall] —— 间隔/高度/起落全随机, 快起慢落
	# 间隔刻意加大方差(有时连着来两浪、有时长间歇), 彻底打掉固定节律;
	# 最后一浪保证在 dur-2.4 前起, 让循环接缝落在相对平静的段
	var surges: Array = []
	var st := rng.randf_range(0.6, 1.8)
	while st < dur - 2.4:
		var peak := rng.randf_range(0.45, 1.0)
		var rise := rng.randf_range(0.08, 0.30)
		var fall := rng.randf_range(0.7, 2.1)
		surges.append([st, peak, rise, fall])
		var gap := rng.randf_range(0.15, 1.2)
		if rng.randf() < 0.28:
			gap += rng.randf_range(1.4, 3.2)   # 偶发长间歇
		st += rise + fall + gap
	for i in total:
		var t := i / float(SR)
		var u := fposmod(t, seg) / seg
		var k := mini(int(t / seg), kn - 2)
		var sm := 0.5 - 0.5 * cos(PI * u)
		var slow := lerpf(knots[k], knots[k + 1], sm)
		# 浪涌包络: 多浪重叠取 max 不叠爆; smoothstep 快起、指数慢落
		var surge := 0.0
		for ev in surges:
			var dt: float = t - ev[0]
			if dt < 0.0 or dt > ev[2] + ev[3] * 2.2:
				continue
			var s: float
			if dt < ev[2]:
				s = dt / ev[2]
				s = s * s * (3.0 - 2.0 * s)
			else:
				s = exp(-(dt - ev[2]) * 2.6 / ev[3])
			surge = maxf(surge, s * ev[1])
		buf[i] = (base[i] * 0.75 + mid[i] * 0.9 * surge) * slow \
			+ foam[i] * 1.1 * surge * surge * slow
	_cross_tail(xf, n)

# 风：中低通噪声「呼——」的躯干 + 更闷的远处层。包络 v2: 三层整周期正弦换成随机漫步
# ——旧版 9 秒样本里 3/7/13 圈等分正弦, 周期虽宽听不出摩擦, 但起伏仍可预测、偏机械;
# 漫步控制点 + 余弦平滑, 「呼」的涌动没固定节律, 更像真风。
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
	# 随机漫步包络: 每 ~1.7 秒一个控制点, 首尾同值接缝无痕
	var seg := 1.7
	var kn := int(ceil(dur / seg)) + 1
	var knots := PackedFloat32Array()
	knots.resize(kn)
	for k in kn:
		knots[k] = rng.randf_range(0.58, 1.0)
	knots[0] = 0.8
	knots[kn - 1] = knots[0]
	for i in total:
		var t := i / float(SR)
		var u := fposmod(t, seg) / seg
		var k := mini(int(t / seg), kn - 2)
		var sm := 0.5 - 0.5 * cos(PI * u)
		buf[i] *= maxf(lerpf(knots[k], knots[k + 1], sm), 0.12)
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

# 蟋蟀: 高频载波(~4.1-4.6kHz)乘快颤(每秒 ~24-32 下)出「唧————」的连续颤音, 音头微滑;
# 一次样本含两声, 播放层仿鸟鸣「到点叫一声」随机触发(pitch 微随机), 不整段循环。
func make_cricket() -> void:
	var dur := 2.0
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	rng.seed = 20260933
	var t := 0.06
	while t < dur - 1.0:
		var len := rng.randf_range(0.5, 0.9)
		var i0 := int(t * SR)
		var ni := int(len * SR)
		var f0 := rng.randf_range(4100.0, 4600.0)
		var trill := rng.randf_range(24.0, 32.0)
		var ph := 0.0
		for k in ni:
			var u := k / float(ni)
			ph += TAU * lerpf(f0, f0 * 0.94, u) / SR
			var am := pow(0.5 + 0.5 * sin(TAU * trill * u * len), 2.0)
			var env := sin(PI * minf(u * 1.25, 1.0))
			buf[i0 + k] += sin(ph) * 0.55 * am * env
		t += len + rng.randf_range(0.35, 0.75)
	_attack(n)

# 蛙鸣: 短促下滑「呱」—— 基频 ~340-520Hz 加二次谐波, 音调快降 + 幅度快落;
# 一到两声一组, 组间隔随机。播放层雨天触发(白天夜里都叫, 雨夜尤其活)。
func make_frog() -> void:
	var dur := 2.4
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	rng.seed = 20260934
	var t := 0.08
	while t < dur - 0.9:
		var croaks := 1 if rng.randf() < 0.4 else 2
		for c in croaks:
			var len := rng.randf_range(0.14, 0.26)
			var i0 := int(t * SR)
			var ni := int(len * SR)
			var f0 := rng.randf_range(340.0, 520.0)
			for k in ni:
				var u := k / float(ni)
				var f := lerpf(f0, f0 * 0.72, u)
				var env := exp(-7.0 * u) * minf(u * 12.0, 1.0)
				var ph := TAU * f * u * len
				var v := sin(ph) + 0.45 * sin(2.0 * ph)
				buf[i0 + k] += v * 0.4 * env
			t += len + rng.randf_range(0.10, 0.22)
		t += rng.randf_range(0.5, 1.1)
	_attack(n)

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
