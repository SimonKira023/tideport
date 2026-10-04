# tools/make_audio_gd.gd —— 用 GDScript 重新合成 4 首 BGM（连贯音色复调器乐版 v4）
#
# 为什么不用 tools/make_audio.py：本机没有可用的 Python（商店占位符），
# 所以把合成逻辑搬进 Godot 自己跑 —— AudioStreamWAV.save_to_wav 直写 WAV 文件。
#
# v3 相对 v2（中世纪乐队版）的变化 ——「天国拯救 2 圣女芭芭拉风格，但不要吟唱」：
#   · 全程 **器乐**，不设任何人声/合唱垫 —— 「不要吟唱」硬约束；
#   · 织体改成文艺复兴教堂复调：便携管风琴奏 **固定旋律**（cantus firmus），
#     横笛在调式内平行三度跟走（fauxbourdon 六和弦），维奥尔低音走根音-五度 bordun；
#   · 日曲换 **F 利底亚**（还原 B 是利底亚的神性亮色），「圣芭芭拉颂」固定旋律，
#     高声部句尾加邻音花唱，84 BPM 庄重行进，鼓全部收掉；
#   · 夜曲同一条固定旋律落在 **D 多利亚**，64 BPM 慢板，笛声退远、鲁特改稀疏双音；
#   · 海曲保留 6/8 行船骨架，主旋律加一条 **低八度延迟一拍的卡农模仿**（复调感），
#     和弦垫从方波刺换成便携管风琴五度长音；
#   · 战曲去掉现代踩镲，旋律改 **肖姆双簧**（方波+正弦双层簧片感）并加 **下方三度对位**，
#     和弦刺换成管风琴长和弦，军鼓/底鼓/战号保留。
#
# v4 相对 v3 的变化 ——「连贯非 8bit 曲风」：
#   · 全曲禁用方波（sq/sq25/sq12 查表项删除）—— 8bit 感的元凶就是它们；
#   · 新增 organ 音色：基频 + 2/3/4 次谐波薄混（风管叠加音栓），替换原 sq25 管风琴；
#   · 新增 shawm 音色：奇次谐波递减（簧片的锯齿感但圆润连贯），替换原 sq12 肖姆；
#   · 军号扫掠同步改泛音叠加；横笛去掉方波芯改纯音加幅；
#   · 旋律 / 曲式 / BPM / 小节数全部沿用 v3，WAV 时长不变。
#
# v5 相对 v4 的变化 ——「连贯一点，使用连贯乐器」：
#   · 新增 pad 音色：全谐波缓降的弦乐合奏垫，慢起慢收长弓 —— 接管低音提琴与海曲根音；
#   · 连奏（legato）：旋律/长音的 dur 拉过下一音起点，前音 release 与后音 attack
#     交叉淡化，消掉「每音一个包子」的步进离散感；
#   · 包络整体放缓：attack 2~6 倍、release 2~3 倍，揉弦 vib 全面加深（弦乐呼吸感）；
#   · 新增 add_reverb()：四路反馈梳状混响（教堂空间感），在 wrap_tail 之前送入，
#     混响尾随尾音一起绕回循环点，循环接缝处空间感连续无痕；
#   · 鲁特拨弦衰减放缓但保留点状触感；战曲军鼓送混响减半不糊；
#   · 旋律 / 曲式 / BPM / 小节数仍全部不动，WAV 时长与 v4 完全一致。
#
# 跑法（headless 即可，不用开窗口）：
#   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> \
#       --script res://tools/make_audio_gd.gd
# 跑完记得 --import 重新导入资源，游戏里才会读到新 WAV。
extends SceneTree

const SR := 22050

const NOTE := {
	"C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00,
	"A3": 220.00, "B3": 246.94,
	"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
	"A4": 440.00, "B4": 493.88,
	"C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99,
	"A5": 880.00, "B5": 987.77, "C6": 1046.50,
}

# 调式音级走行：在自然音集 CDEFGAB 里走 steps 级，自动翻八度（fauxbourdon 用）
const MODE := ["C", "D", "E", "F", "G", "A", "B"]

# ------------------------------------------------ 「圣芭芭拉颂」固定旋律
# F 利底亚，每小节两个二分音符，16 小节 32 音；级进为主、拱形乐句、结束回到主音。
const CF := [
	"F4", "G4", "A4", "F4", "C5", "B4", "A4", "G4",
	"A4", "C5", "D5", "C5", "C5", "B4", "A4", "F4",
	"D5", "C5", "B4", "A4", "G4", "A4", "B4", "C5",
	"A4", "G4", "F4", "E4", "G4", "F4", "F4", "F4",
]
# 日曲低音根音（F 利底亚；bordun：1、3 拍根音，2、4 拍纯五度）
const DAY_BASS := [
	"F3", "C3", "G3", "C3", "F3", "C3", "G3", "F3",
	"D3", "G3", "C3", "G3", "F3", "C3", "C3", "F3",
]
# 夜曲低音根音（同一旋律落在 D 多利亚上听感更沉）
const NIGHT_BASS := [
	"D3", "C3", "G3", "D3", "F3", "C3", "G3", "D3",
	"D3", "C3", "G3", "G3", "F3", "C3", "D3", "D3",
]

# ------------------------------------------------ 海图（6/8 行船调，A 小调五声，节奏结构不变）
const OCEAN_BPM := 100.0
const OCEAN_BARS := 12
const OCEAN_PROG := [
	[45, [57, 60, 64]], [40, [52, 56, 59]], [41, [53, 57, 60]],
	[48, [55, 60, 64]], [45, [57, 60, 64]], [40, [52, 56, 59]],
	[43, [55, 59, 62]], [43, [55, 59, 62]], [41, [53, 57, 60]],
	[48, [55, 60, 64]], [38, [50, 53, 57]], [40, [52, 56, 59]],
]
const OCEAN_MELODY := [
	[76, -1, -1, 72, -1, -1], [74, -1, 76, -1, -1, -1], [72, -1, -1, 69, -1, -1],
	[67, -1, 69, -1, -1, -1], [76, -1, 79, -1, 76, -1], [74, -1, 72, 74, -1, -1],
	[71, -1, 74, -1, 71, -1], [72, -1, -1, -1, -1, -1], [69, -1, 72, -1, 74, -1],
	[76, -1, -1, 74, 72, -1], [74, -1, 72, -1, 69, -1], [71, -1, 76, -1, -1, -1],
]

# ------------------------------------------------ 战曲（150 BPM，D 小调，节奏结构不变）
const BATTLE_BPM := 150.0
const BATTLE_BARS := 16
const BATTLE_PROG := [
	[50, [62, 65, 69]], [50, [62, 65, 69]], [46, [58, 62, 65]], [48, [60, 64, 67]],
	[50, [62, 65, 69]], [50, [62, 65, 69]], [43, [58, 62, 67]], [45, [57, 61, 64]],
]
const BATTLE_SCALE := [50, 52, 53, 55, 57, 58, 60, 62, 64]
const BATTLE_MELODY := [
	[7, -1, 6, 5, 4, -1, 3, 2, 4, -1, 5, -1, 6, 5, 4, -1],
	[5, -1, 4, 3, 2, -1, 3, 4, 5, -1, 6, -1, 7, -1, -1, -1],
	[4, -1, 5, 6, 7, -1, 6, 5, 4, 3, 2, -1, 3, -1, -1, -1],
	[7, 6, 5, 4, 5, -1, 6, 7, 8, -1, 7, 6, 5, -1, 4, -1],
	[2, 3, 4, 5, 6, -1, 7, 8, 7, -1, 6, 5, 4, -1, 3, -1],
	[5, -1, 4, -1, 3, -1, 2, -1, 4, 5, 6, 7, 8, -1, 7, -1],
	[6, -1, 5, 4, 3, -1, 4, 5, 6, -1, 7, -1, 6, 5, 4, 3],
	[2, -1, 3, 4, 5, 6, 7, -1, 8, -1, 7, -1, 6, -1, -1, -1],
]

var buf := PackedFloat32Array()
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	print("GDScript 合成圣芭芭拉复调器乐 BGM v5（连贯弦乐+混响）...")
	make_bgm_day()
	save_wav("res://resources/audio/bgm/bgm_day.wav", 0.85)
	make_bgm_night()
	save_wav("res://resources/audio/bgm/bgm_night.wav", 0.80)
	make_bgm_ocean()
	save_wav("res://resources/audio/bgm/bgm_ocean.wav", 0.85)
	make_bgm_battle()
	save_wav("res://resources/audio/bgm/bgm_battle.wav", 0.80)
	print("完成")
	quit(0)


# 自然音集里走 n 级："F4" +2 -> "A4"，"B4" +2 -> "D5"（利底亚特征音自动保留）
func _deg(name: String, steps: int) -> String:
	var letter := name.substr(0, 1)
	var octv := int(name.substr(1))
	var idx := MODE.find(letter) + steps
	while idx >= 7:
		idx -= 7
		octv += 1
	while idx < 0:
		idx += 7
		octv -= 1
	return "%s%d" % [MODE[idx], octv]


# ------------------------------------------------ 波形与叠加
func new_buf(seconds: float) -> void:
	buf.resize(int(seconds * SR))
	buf.fill(0.0)


# 把越过循环点的尾音绕回开头叠上，循环才不会在接缝处掉音量
func wrap_tail(loop_frames: int) -> void:
	var n := mini(loop_frames, buf.size())
	for i in range(n, buf.size()):
		buf[i % n] += buf[i]
	buf.resize(n)


func _midi(m: int) -> float:
	return 440.0 * pow(2.0, (m - 69) / 12.0)


# start/dur 单位秒；kind: sine/tri/organ/shawm/pad；vib = 颤音深度（0 关闭）
func add_tone(start: float, dur: float, freq: float, kind: String, amp: float,
		attack := 0.018, release := 0.14, decay := 0.0, vib := 0.0) -> void:
	if freq <= 0.0 or dur <= 0.0:
		return
	var n0 := int(start * SR)
	var n1 := mini(int((start + dur) * SR), buf.size())
	if n0 >= n1:
		return
	var wid := 0                     # 音色：0 正弦 1 三角 2 管风琴 3 肖姆 4 弦乐垫
	match kind:
		"tri": wid = 1
		"organ": wid = 2
		"shawm": wid = 3
		"pad": wid = 4
	var atk := maxf(attack, 0.0001)
	var rel := maxf(release, 0.0001)
	var ph := 0.0
	for i in range(n0, n1):
		var t := (i - n0) / float(SR)
		var e := 1.0
		if t < atk:
			e = t / atk
		elif t > dur - rel:
			e = maxf(0.0, (dur - t) / rel)
		if decay > 0.0:
			e *= exp(-decay * t)
		var s := 0.0
		match wid:               # ph 每步都绕回 [0,1)，不用再 fposmod
			1: s = 4.0 * absf(ph - 0.5) - 1.0
			2:                # 管风琴：基频 + 2/3/4 次谐波薄混（风管叠加音栓）
				s = (sin(TAU * ph) + 0.32 * sin(2.0 * TAU * ph)
						+ 0.16 * sin(3.0 * TAU * ph) + 0.07 * sin(4.0 * TAU * ph)) / 1.55
			3:                # 肖姆双簧：奇次谐波递减（簧片锯齿感，圆润不生硬）
				s = (sin(TAU * ph) + 0.30 * sin(3.0 * TAU * ph)
						+ 0.15 * sin(5.0 * TAU * ph) + 0.08 * sin(7.0 * TAU * ph)) / 1.53
			4:                # 弦乐合奏垫：全谐波缓降（合奏锯齿感+厚基频），慢包络长弓
				s = (sin(TAU * ph) + 0.55 * sin(2.0 * TAU * ph)
						+ 0.34 * sin(3.0 * TAU * ph) + 0.22 * sin(4.0 * TAU * ph)
						+ 0.12 * sin(5.0 * TAU * ph) + 0.06 * sin(6.0 * TAU * ph)) / 2.29
			0: s = sin(TAU * ph)
		buf[i] += s * amp * e
		var f := freq
		if vib > 0.0:                # 揉弦：5.2Hz 的弦乐式微颤
			f = freq * (1.0 + vib * sin(TAU * 5.2 * t))
		ph += f / SR
		if ph >= 1.0:
			ph -= 1.0


# 噪声（鼓皮/军鼓），lp/hp 是单极点滤波系数 0~1
func add_noise(start: float, dur: float, amp: float, decay := 10.0,
		lp := 0.0, hp := 0.0, seed_v := 1) -> void:
	rng.seed = seed_v
	var n0 := int(start * SR)
	var n1 := mini(int((start + dur) * SR), buf.size())
	if n0 >= n1:
		return
	var prev := 0.0
	var prev_out := 0.0
	for i in range(n0, n1):
		var t := (i - n0) / float(SR)
		var n := rng.randf_range(-1.0, 1.0)
		if lp > 0.0:
			prev = prev + lp * (n - prev)
			n = prev
		if hp > 0.0:
			prev_out = prev_out + hp * (n - prev_out)
			n = n - prev_out
		buf[i] += n * amp * exp(-decay * t)


# 频率扫掠（军号的上扬，基频 + 2/3 次泛音的铜管感）
func add_sweep(start: float, dur: float, f0: float, f1: float,
		amp: float, decay := 6.0) -> void:
	var n0 := int(start * SR)
	var n1 := mini(int((start + dur) * SR), buf.size())
	if n0 >= n1:
		return
	var ph := 0.0
	for i in range(n0, n1):
		var t := (i - n0) / float(dur)
		var f := f0 + (f1 - f0) * t
		var p := fposmod(ph, 1.0)
		var s := (sin(TAU * p) + 0.30 * sin(2.0 * TAU * p)
				+ 0.15 * sin(3.0 * TAU * p)) / 1.45
		buf[i] += s * amp * exp(-decay * (i - n0) / float(SR))
		ph += f / SR


# 教堂混响：四路反馈梳状并联（延迟 29~73ms，反馈递减），wrap_tail 之前调用 ——
# 混响尾会跟尾音一起绕回循环点，BGM 循环接缝处空间感连续无痕
func add_reverb(wet := 0.2) -> void:
	var x := buf.duplicate()
	for c in [[0.029, 0.34], [0.041, 0.30], [0.057, 0.26], [0.073, 0.21]]:
		var d := int(c[0] * SR)
		var g: float = c[1]
		var y := PackedFloat32Array()
		y.resize(buf.size())
		for i in range(d, buf.size()):
			y[i] = x[i - d] + y[i - d] * g
		for i in buf.size():
			buf[i] += y[i] * wet


func save_wav(path: String, gain: float) -> void:
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


# ------------------------------------------------ 日曲（圣芭芭拉颂，F 利底亚，84 BPM，无鼓）
func make_bgm_day() -> void:
	var beat := 60.0 / 84.0
	var half := beat * 2.0           # 二分音符 = 一个固定旋律音
	var bars := 16
	var total := bars * 4.0 * beat
	new_buf(total + beat * 2.0)      # 多留 2 小节给尾音绕回
	for bar in bars:
		var t0 := bar * 4.0 * beat
		var bass: String = DAY_BASS[bar]
		# 低音维奥尔：1、3 拍根音，2、4 拍纯五度（bordun）—— pad 弦乐长弓，
		# dur 拉过下一弓起点，弓与弓交叉淡化连成一条低音线
		for k in 4:
			var nm: String = bass if k % 2 == 0 else _deg(bass, 4)
			add_tone(t0 + k * beat, beat * 1.9, NOTE[nm], "pad", 0.15, 0.09, 0.22, 0.55, 0.004)
		# 便携管风琴奏固定旋律（二分长音 + 高八度 mixtur 音栓薄薄一层）
		for j in 2:
			var cn: String = CF[bar * 2 + j]
			var ct := t0 + j * half
			add_tone(ct, half * 1.06, NOTE[cn], "organ", 0.065, 0.06, 0.24, 0.5, 0.006)
			add_tone(ct, half * 1.06, NOTE[cn] * 2.0, "sine", 0.025, 0.06, 0.24, 0.5)
		# 横笛：调式内平行三度（fauxbourdon），每个长音拆 4 个四分、
		# 第 3 个换成上邻音 —— 圣咏花唱的小尾巴
		for j2 in 2:
			var cn2: String = CF[bar * 2 + j2]
			var top := _deg(cn2, 2)
			var nb := _deg(top, 1)
			var ft := t0 + j2 * half
			var q := half / 2.0
			for k2 in 4:
				var nm2: String = top if k2 != 2 else nb
				add_tone(ft + k2 * q, q * 1.12, NOTE[nm2], "sine",
				0.16, 0.035, 0.13, 1.1, 0.007)
		# 鲁特琴：八分琶音铺底流动（根 三 五 八 五 三 五 三）
		var d2 := _deg(bass, 2)
		var d4 := _deg(bass, 4)
		var d8 := _deg(bass, 7)
		var arp := [bass, d2, d4, d8, d4, d2, d4, d2]
		for i3 in 8:
			add_tone(t0 + i3 * (beat / 2.0), beat * 0.56, NOTE[arp[i3]], "tri",
				0.08, 0.004, 0.09, 5.0)
	add_reverb(0.20)
	wrap_tail(int(total * SR))


# ------------------------------------------------ 夜曲（同旋律落 D 多利亚，64 BPM，无鼓）
func make_bgm_night() -> void:
	var beat := 60.0 / 64.0
	var half := beat * 2.0
	var bars := 16
	var total := bars * 4.0 * beat
	new_buf(total + beat * 2.0)
	for bar in bars:
		var t0 := bar * 4.0 * beat
		var bass: String = NIGHT_BASS[bar]
		# 低音：慢弓长音连成整条 bassline，五度只在第 3 拍点一次
		add_tone(t0, beat * 2.3, NOTE[bass], "pad", 0.14, 0.12, 0.3, 0.5, 0.004)
		add_tone(t0 + 2.0 * beat, beat * 2.3, NOTE[_deg(bass, 4)], "pad",
			0.11, 0.12, 0.3, 0.5, 0.004)
		# 管风琴：固定旋律放低八度，夜里唱得更沉
		for j in 2:
			var cn: String = CF[bar * 2 + j]
			var ct := t0 + j * half
			add_tone(ct, half * 1.05, NOTE[cn] / 2.0, "organ", 0.06, 0.08, 0.26, 0.4, 0.005)
			add_tone(ct, half * 1.05, NOTE[cn], "sine", 0.035, 0.08, 0.26, 0.4)
		# 横笛退到远处：平行三度长音直给，不加花
		for j2 in 2:
			var cn2: String = CF[bar * 2 + j2]
			add_tone(t0 + j2 * half, half * 1.04, NOTE[_deg(cn2, 2)], "sine",
				0.075, 0.1, 0.3, 1.0, 0.006)
		# 鲁特：稀疏双音拨弦（每半小节一声，根+五）
		for k3 in [0.0, 2.0]:
			add_tone(t0 + k3 * beat, beat * 0.85, NOTE[bass], "tri", 0.05, 0.004, 0.1, 4.5)
			add_tone(t0 + k3 * beat, beat * 0.85, NOTE[_deg(bass, 4)], "tri",
				0.04, 0.004, 0.1, 4.5)
	add_reverb(0.24)
	wrap_tail(int(total * SR))


# ------------------------------------------------ 海曲（6/8 行船调 + 低八度卡农模仿）
func make_bgm_ocean() -> void:
	var beat := 60.0 / OCEAN_BPM
	var eighth := beat / 2.0
	var bar_len := 6.0 * eighth
	var loop := OCEAN_BARS * bar_len
	new_buf(loop + bar_len)          # 多留一小节给尾音绕回
	for i in OCEAN_BARS:
		var t0 := i * bar_len
		var last := i == OCEAN_BARS - 1
		var entry: Array = OCEAN_PROG[i]
		var root: int = entry[0]
		var chord: Array = entry[1]
		# 最后一小节的长音故意拖过循环点，由 wrap_tail 绕回开头
		var tail_dur := 0.0
		if last:
			tail_dur = (loop - t0) + eighth * 3.0
		if last:
			add_tone(t0, tail_dur, _midi(root), "pad", 0.24, 0.1, 0.22, 0.62)
			add_tone(t0 + 3.0 * eighth, tail_dur, _midi(root + 7), "pad", 0.16, 0.1, 0.22, 0.78)
		else:
			add_tone(t0, eighth * 3.2, _midi(root), "pad", 0.24, 0.1, 0.22, 1.1)
			add_tone(t0 + 3.0 * eighth, eighth * 3.0, _midi(root + 7), "pad", 0.16, 0.1, 0.22, 1.3)
		# 便携管风琴：五度上方持续长音垫底（替换原来的方波和弦刺）
		var pad_dur := eighth * 5.0
		var pad_decay := 0.5
		if last:
			pad_dur = (loop - t0) + eighth * 3.0
			pad_decay = 0.35
		add_tone(t0, pad_dur, _midi(root + 7), "organ", 0.045, 0.14, 0.5, pad_decay)
		# 鲁特琴：每小节 6 个八分爬一遍和弦（行船的拨弦感）
		for k in 6:
			add_tone(t0 + k * eighth, eighth * 0.95, _midi(chord[k % 3]), "tri",
				0.07, 0.005, 0.11, 5.0)
		# 竖笛主旋律
		for k2 in 6:
			var deg: int = OCEAN_MELODY[i][k2]
			if deg < 0:
				continue
			add_tone(t0 + k2 * eighth, eighth * 2.1, _midi(deg), "sine",
				0.18, 0.05, 0.36, 1.4, 0.007)
		# 卡农：低八度、晚一个八分紧跟模仿上一拍音（复调的问答感）
		if i > 0:
			var pd: int = OCEAN_MELODY[i - 1][5]
			if pd > 0:
				add_tone(t0, eighth * 2.1, _midi(pd - 12), "sine",
					0.095, 0.05, 0.36, 1.6, 0.006)
		for k4 in 5:
			var deg2: int = OCEAN_MELODY[i][k4]
			if deg2 < 0:
				continue
			add_tone(t0 + (k4 + 1) * eighth, eighth * 2.1, _midi(deg2 - 12), "sine",
					0.095, 0.05, 0.36, 1.6, 0.006)
		# 浪：每两小节一道低频噪声涌上来
		if i % 2 == 0:
			add_noise(t0, bar_len * 1.7, 0.055, 1.5, 0.055, 0.0, 200 + i)
		for off2 in [2.0 * eighth, 5.0 * eighth]:
			add_noise(t0 + off2, 0.07, 0.028, 48.0, 0.0, 0.88, 300 + i * 4 + int(off2 * 100.0))
	add_reverb(0.20)
	wrap_tail(int(loop * SR))


# ------------------------------------------------ 战曲（军鼓 + 肖姆双簧 + 下方三度对位）
func make_bgm_battle() -> void:
	var beat := 60.0 / BATTLE_BPM
	var eighth := beat / 2.0
	var bar_len := 4.0 * beat
	var loop := BATTLE_BARS * bar_len
	new_buf(loop + bar_len)
	for i in BATTLE_BARS:
		var t0 := i * bar_len
		for off in [0.0, 2.0]:       # 底鼓踩 1、3
			add_tone(t0 + off * beat, 0.13, 72.0, "sine", 0.30, 0.002, 0.04, 24.0)
		for off in [1.0, 3.0]:       # 军鼓踩 2、4
			add_noise(t0 + off * beat, 0.14, 0.10, 24.0, 0.55, 0.0, 4000 + i * 8 + int(off))
		add_noise(t0 + 3.5 * beat, 0.05, 0.05, 60.0, 0.0, 0.7, 4500 + i)   # 4 拍后半轻点
		if i % 8 == 7:               # 每 8 小节收一串军鼓滚奏
			for j in 6:
				add_noise(t0 + 3.0 * beat + j * (beat / 6.0), 0.05,
					0.05 + 0.012 * j, 70.0, 0.0, 0.6, 6000 + i * 8 + j)
	for block in BATTLE_PROG.size():
		var entry: Array = BATTLE_PROG[block]
		var root: int = entry[0]
		var chord: Array = entry[1]
		for half2 in 2:
			var i2 := block * 2 + half2
			var t1 := i2 * bar_len
			for k in 8:              # 贝斯连续八分交叠成 bordun 长线（根音与八度交替）
				var n := root if k % 2 == 0 else root + 12
				add_tone(t1 + k * eighth, eighth * 1.08, _midi(n), "tri", 0.22, 0.008, 0.1, 6.0)
			# 便携管风琴：半小节一个长和弦垫底，dur 越过下一组和弦起点衔接
			for off3 in [0.0, 2.0]:
				for n2 in chord:
					add_tone(t1 + off3 * beat, beat * 2.15, _midi(n2), "organ",
						0.038, 0.09, 0.3, 1.2)
			for k2 in 16:            # 肖姆双簧主旋律（连奏+揉弦）+ 下方三度对位
				var deg: int = BATTLE_MELODY[block][k2]
				if deg < 0:
					continue
				var f: float = _midi(BATTLE_SCALE[deg])
				add_tone(t1 + k2 * eighth, eighth * 1.05, f, "shawm", 0.14, 0.012, 0.12, 2.6, 0.004)
				var d3: int = deg - 3
				if d3 >= 0:
					add_tone(t1 + k2 * eighth, eighth * 1.02, _midi(BATTLE_SCALE[d3]),
						"organ", 0.085, 0.016, 0.14, 3.5)
	# 军号：第 1、9 小节开头两声上扬号角（泛音号 + 高八度正弦泛音）
	for i3 in [0, 8]:
		var t2: float = i3 * bar_len
		add_sweep(t2, beat * 2.2, 174.6, 233.1, 0.10, 1.6)
		add_sweep(t2, beat * 2.2, 349.2, 466.2, 0.06, 1.6)
	add_reverb(0.12)                 # 战曲送混响减半，军鼓保持干脆
	wrap_tail(int(loop * SR))
