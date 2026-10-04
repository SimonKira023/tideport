# tools/make_weather_audio.gd —— 程序合成天气音效：rain.wav（循环雨声）+ thunder.wav（滚雷）
#
# 为什么用 GDScript：本机没有可用的 Python，跟 tools/make_audio_gd.gd 一个道理，
# 用 AudioStreamWAV.save_to_wav 直写 WAV 文件。
#
# 跑法（headless 即可，不用开窗口）：
#   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> \
#       --script res://tools/make_weather_audio.gd
# 跑完记得 --import 重新导入资源，游戏里才会读到新 WAV。
extends SceneTree

const SR := 22050

var buf := PackedFloat32Array()
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	print("合成天气音效...")
	make_rain()
	save_wav("res://resources/audio/sfx/rain.wav")
	make_thunder()
	save_wav("res://resources/audio/sfx/thunder.wav")
	quit()

# 雨：白噪声过两段低通（细密沙沙）+ 慢起伏包络（风向摆动）。
# 包络周期取整倍数 + 尾巴折回头部交叉淡化，循环接缝无痕。
func make_rain() -> void:
	var dur := 6.0
	var xf := int(0.25 * SR)
	var n := int(dur * SR)
	var total := n + xf
	buf.resize(total)
	buf.fill(0.0)
	rng.seed = 20260918
	var lp1 := 0.0
	var lp2 := 0.0
	for i in total:
		var x := rng.randf_range(-1.0, 1.0)
		lp1 += 0.34 * (x - lp1)      # 第一段低通：保留中高频的沙沙质感
		lp2 += 0.06 * (lp1 - lp2)    # 第二段低通：掉掉刺耳的高频
		buf[i] = lp2 * 2.6
	# 慢起伏：两个整周期正弦（首尾同相位，循环才不掉底）
	for i in total:
		var t := i / float(SR)
		var env := 0.72 + 0.18 * sin(TAU * 2.0 * t / dur) \
			+ 0.10 * sin(TAU * 5.0 * t / dur + 1.3)
		buf[i] *= env
	# 尾巴 xf 长度折回头部交叉淡化：buf[0] ≈ 自然接在 buf[n-1] 后面的那一下
	for i in xf:
		var k := i / float(xf)
		buf[i] = buf[i] * k + buf[n + i] * (1.0 - k)
	buf.resize(n)

# 雷：低频噪声过重低通 + 指数衰减，主雷 + 0.55 秒后一记更远的回声雷，
# 起始 8ms 快速起音防爆音。
func make_thunder() -> void:
	var dur := 2.4
	var n := int(dur * SR)
	buf.resize(n)
	buf.fill(0.0)
	for burst in 2:
		var t0 := 0.0 if burst == 0 else 0.55
		var amp := 1.0 if burst == 0 else 0.55
		rng.seed = 7291 + burst
		var lp := 0.0
		var i0 := int(t0 * SR)
		for i in range(i0, n):
			var t := (i - i0) / float(SR)
			var x := rng.randf_range(-1.0, 1.0)
			lp += 0.035 * (x - lp)                 # 重低通 → 闷雷
			var env := exp(-2.2 * t) * (1.0 + 0.7 * sin(TAU * 3.1 * t))
			buf[i] += lp * 3.2 * amp * env
	var atk := int(0.008 * SR)
	for i in atk:
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
