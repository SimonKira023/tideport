# tools/make_audio.py —— 程序化合成游戏的 BGM 与音效（纯 Python，不用 numpy）
#
# 为什么要自己生成：项目里只有星露谷 Prairie King 的原曲和一堆「牛仔枪战」音效，
# 没有耕地/浇水/收获这类田园音效。自己合成还有一个好处 —— 100% 原创，能安全发布。
#
# 输出：
#   resources/audio/bgm/bgm_day.wav     白天 BGM（明亮、跳跃的 8-bit 田园曲，16 小节无缝循环）
#   resources/audio/bgm/bgm_night.wav   夜晚 BGM（同一段旋律放慢、变柔和）
#   resources/audio/bgm/bgm_ocean.wav   大地图（海图）BGM（6/8 摇摆的悠远行船调）
#   resources/audio/bgm/bgm_battle.wav  战斗 BGM（150 BPM 的急促军鼓 + 紧张小调）
#   resources/audio/sfx/*.wav           各种交互音效
#
# 用法：python tools/make_audio.py
import math
import os
import random
import struct
import wave

SR = 22050          # 采样率（8-bit 风格够用，文件还小）
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "resources", "audio")


# ---------------------------------------------------------------- 基础波形
def sq(ph, duty=0.5):
    return 1.0 if (ph % 1.0) < duty else -1.0


def tri(ph):
    p = ph % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def sine(ph):
    return math.sin(2.0 * math.pi * (ph % 1.0))


def mix_wave(ph, kind):
    if kind == "sq":
        return sq(ph, 0.5)
    if kind == "sq25":
        return sq(ph, 0.25)
    if kind == "sq12":
        return sq(ph, 0.125)
    if kind == "tri":
        return tri(ph)
    return sine(ph)


def new_buf(seconds):
    return [0.0] * int(seconds * SR)


def wrap_tail(buf, loop_len):
    """把「越过循环点」的那一段绕回来叠到开头，循环就没接缝了。

    ❗为什么要这么干：最后一小节的长音/尾音会一直响到循环点之后，
    如果缓冲区正好截在循环点上，这些音就被切掉了 —— 听起来就是
    「每一圈末尾都掉一下音量」。多留一小节的空位给尾音，
    再把溢出部分按取模叠回开头，接缝处才是连续的。
    """
    n = int(loop_len * SR)
    out = buf[:n]
    for i in range(n, len(buf)):
        out[i % n] += buf[i]
    return out


def add_tone(buf, start, dur, freq, kind="sq", amp=0.25,
             attack=0.006, release=0.06, decay=0.0):
    """往 buffer 上叠一个音。freq=0 时跳过（当休止符用）。"""
    if freq <= 0 or dur <= 0:
        return
    n0 = int(start * SR)
    n1 = min(int((start + dur) * SR), len(buf))
    if n0 >= n1:
        return
    step = freq / SR
    ph = 0.0
    atk = max(attack, 1e-4)
    rel = max(release, 1e-4)
    wf = kind
    for i in range(n0, n1):
        t = (i - n0) / SR
        e = 1.0
        if t < atk:
            e = t / atk
        elif t > dur - rel:
            e = max(0.0, (dur - t) / rel)
        if decay > 0.0:
            e *= math.exp(-decay * t)
        buf[i] += mix_wave(ph, wf) * amp * e
        ph += step
        if ph >= 1.0:
            ph -= 1.0


def add_noise(buf, start, dur, amp, decay=10.0, lp=0.0, hp=0.0, seed=1):
    """噪声（锄地/脚步/水花都用它）。lp/hp 是简单的单极点滤波系数 0~1。"""
    rng = random.Random(seed)
    n0 = int(start * SR)
    n1 = min(int((start + dur) * SR), len(buf))
    if n0 >= n1:
        return
    prev = 0.0
    prev_out = 0.0
    for i in range(n0, n1):
        t = (i - n0) / SR
        n = rng.uniform(-1.0, 1.0)
        if lp > 0.0:
            prev = prev + lp * (n - prev)
            n = prev
        if hp > 0.0:
            prev_out = prev_out + hp * (n - prev_out)
            n = n - prev_out
        buf[i] += n * amp * math.exp(-decay * t)


def add_sweep(buf, start, dur, f0, f1, kind="sine", amp=0.3, decay=6.0):
    """频率扫掠（金币的 ding、打水的咕嘟都用它）"""
    n0 = int(start * SR)
    n1 = min(int((start + dur) * SR), len(buf))
    if n0 >= n1:
        return
    ph = 0.0
    for i in range(n0, n1):
        t = (i - n0) / dur
        f = f0 + (f1 - f0) * t
        buf[i] += mix_wave(ph, kind) * amp * math.exp(-decay * (i - n0) / SR)
        ph += f / SR
        if ph >= 1.0:
            ph -= 1.0


def save_wav(path, buf, gain=1.0):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 归一到 -1.5dB，避免削波
    peak = max((abs(v) for v in buf), default=0.0)
    k = (0.84 / peak * gain) if peak > 1e-6 else 0.0
    frames = bytearray()
    for v in buf:
        s = int(max(-1.0, min(1.0, v * k)) * 32767)
        frames += struct.pack("<h", s)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("  %-28s %5.2fs" % (os.path.basename(path), len(buf) / SR))


# ---------------------------------------------------------------- 音效
def sfx_hoe():
    """锄地：一下闷闷的土声"""
    b = new_buf(0.30)
    add_noise(b, 0.0, 0.16, 0.5, decay=26.0, lp=0.10, seed=11)
    add_tone(b, 0.0, 0.13, 110, "tri", 0.35, decay=26.0)
    add_tone(b, 0.01, 0.10, 74, "sine", 0.25, decay=30.0)
    return b


def sfx_water():
    """浇水：水洒下来的沙沙声"""
    b = new_buf(0.55)
    add_noise(b, 0.0, 0.50, 0.32, decay=5.0, lp=0.30, hp=0.55, seed=23)
    add_noise(b, 0.05, 0.45, 0.20, decay=4.0, lp=0.45, seed=31)
    add_tone(b, 0.0, 0.12, 520, "sine", 0.10, decay=20.0)
    return b


def sfx_fill():
    """打水：咕嘟咕嘟往上冒泡"""
    b = new_buf(0.75)
    for i, t in enumerate((0.00, 0.13, 0.26, 0.39, 0.52)):
        f = 300.0 + i * 130.0
        add_tone(b, t, 0.14, f, "sine", 0.30, decay=14.0)
        add_noise(b, t, 0.07, 0.10, decay=30.0, lp=0.5, seed=40 + i)
    return b


def sfx_plant():
    """播种：轻柔的噗"""
    b = new_buf(0.20)
    add_noise(b, 0.0, 0.10, 0.30, decay=34.0, lp=0.22, seed=51)
    add_tone(b, 0.0, 0.12, 420, "tri", 0.22, decay=22.0)
    return b


def sfx_harvest():
    """收获：两声上扬的清脆音"""
    b = new_buf(0.55)
    add_tone(b, 0.00, 0.16, 784.0, "sq25", 0.26, decay=9.0)     # G5
    add_tone(b, 0.11, 0.22, 1046.5, "sq25", 0.24, decay=8.0)    # C6
    add_tone(b, 0.11, 0.22, 1568.0, "sq12", 0.10, decay=10.0)   # G6 泛音
    return b


def sfx_coin():
    """金币：经典双音"""
    b = new_buf(0.45)
    add_tone(b, 0.00, 0.09, 987.8, "sq12", 0.30)                # B5
    add_tone(b, 0.07, 0.28, 1318.5, "sq12", 0.28, decay=4.0)    # E6
    return b


def sfx_pickup():
    """捡拾：比 coin 柔、比 harvest 短的两声上扬"""
    b = new_buf(0.18)
    add_tone(b, 0.00, 0.07, 660.0, "tri", 0.24, decay=18.0)     # E5
    add_tone(b, 0.05, 0.11, 990.0, "tri", 0.20, decay=12.0)     # B5
    return b


def sfx_buy():
    """买东西：收银机式的三连音"""
    b = new_buf(0.6)
    for i, f in enumerate((659.3, 784.0, 1046.5)):
        add_tone(b, i * 0.08, 0.2, f, "sq25", 0.24, decay=7.0)
    return b


def sfx_error():
    """做不了（水壶空、金币不够）"""
    b = new_buf(0.34)
    add_tone(b, 0.0, 0.14, 180.0, "sq25", 0.30, decay=8.0)
    add_tone(b, 0.13, 0.18, 140.0, "sq25", 0.28, decay=8.0)
    return b


def sfx_ui_click():
    b = new_buf(0.10)
    add_tone(b, 0.0, 0.06, 900.0, "sq12", 0.20, decay=30.0)
    return b


def sfx_ui_open():
    b = new_buf(0.26)
    for i, f in enumerate((523.3, 659.3, 784.0)):
        add_tone(b, i * 0.05, 0.14, f, "sq25", 0.20, decay=12.0)
    return b


def sfx_ui_close():
    b = new_buf(0.26)
    for i, f in enumerate((784.0, 659.3, 523.3)):
        add_tone(b, i * 0.05, 0.14, f, "sq25", 0.20, decay=12.0)
    return b


def sfx_step():
    """脚步：很短的闷响"""
    b = new_buf(0.12)
    add_noise(b, 0.0, 0.07, 0.22, decay=42.0, lp=0.16, seed=77)
    return b


def sfx_sleep():
    """睡觉：柔和下行"""
    b = new_buf(1.1)
    for i, f in enumerate((659.3, 587.3, 523.3, 392.0)):
        add_tone(b, i * 0.16, 0.42, f, "tri", 0.22, decay=4.0)
    return b


def sfx_bin():
    """往售卖箱里丢东西：木头砰一声"""
    b = new_buf(0.34)
    add_noise(b, 0.0, 0.12, 0.34, decay=30.0, lp=0.14, seed=91)
    add_tone(b, 0.0, 0.18, 150.0, "tri", 0.30, decay=18.0)
    add_tone(b, 0.06, 0.24, 240.0, "sine", 0.16, decay=14.0)
    return b


def sfx_chop():
    """砍树：斧头劈进木头的脆响（高频噪声 + 一记闷敲）"""
    b = new_buf(0.28)
    add_noise(b, 0.0, 0.10, 0.45, decay=34.0, hp=0.35, seed=97)
    add_tone(b, 0.0, 0.12, 220.0, "sq25", 0.28, decay=24.0)
    add_tone(b, 0.005, 0.09, 480.0, "tri", 0.16, decay=30.0)
    return b


def sfx_fell():
    """树倒下：低沉的轰 + 枝叶落地的沙沙"""
    b = new_buf(0.9)
    add_tone(b, 0.0, 0.5, 90.0, "tri", 0.32, decay=5.0)
    add_tone(b, 0.02, 0.4, 60.0, "sine", 0.28, decay=4.0)
    add_noise(b, 0.35, 0.45, 0.28, decay=7.0, lp=0.25, seed=103)
    return b


def sfx_campfire():
    """篝火出现：噼啪两声 + 火苗窜起的沙沙"""
    b = new_buf(0.6)
    add_noise(b, 0.0, 0.4, 0.26, decay=6.0, lp=0.3, hp=0.2, seed=113)
    add_noise(b, 0.05, 0.06, 0.4, decay=40.0, hp=0.4, seed=117)
    add_noise(b, 0.28, 0.05, 0.35, decay=42.0, hp=0.4, seed=119)
    add_tone(b, 0.0, 0.3, 180.0, "tri", 0.14, decay=8.0)
    return b


def sfx_deploy():
    """下场：桌面落子闷响 + 一记低鼓"""
    b = new_buf(0.32)
    add_noise(b, 0.0, 0.08, 0.30, decay=40.0, lp=0.18, seed=131)
    add_tone(b, 0.0, 0.16, 150.0, "tri", 0.34, decay=20.0)
    add_tone(b, 0.02, 0.20, 96.0, "sine", 0.26, decay=16.0)
    return b


def sfx_move():
    """行军前进：两小声踏步 + 上扬短音"""
    b = new_buf(0.4)
    add_noise(b, 0.0, 0.06, 0.22, decay=45.0, lp=0.15, seed=137)
    add_noise(b, 0.11, 0.06, 0.26, decay=45.0, lp=0.15, seed=139)
    add_sweep(b, 0.18, 0.22, 300.0, 620.0, "tri", 0.16, decay=8.0)
    return b


def sfx_attack():
    """出手攻击：挥砍呼啸（向下扫频）+ 一记重击"""
    b = new_buf(0.34)
    add_sweep(b, 0.0, 0.10, 900.0, 220.0, "sq25", 0.14, decay=14.0)
    add_noise(b, 0.09, 0.12, 0.42, decay=26.0, hp=0.30, seed=149)
    add_tone(b, 0.09, 0.16, 130.0, "tri", 0.30, decay=18.0)
    return b


# ---------------------------------------------------------------- BGM
# 16 小节循环：C - G - Am - F - C - G - F - G（每个和弦 2 小节），132 BPM。
# 4 个声部：贝斯(triangle) / 和弦垫(square) / 主旋律(square) / 轻打击。
# ❗原来是 8 小节（才 14 秒），循环两遍就听腻了。现在扩成 16 小节：
#   和弦加到 8 块，后 4 块的旋律是前 4 块的**变奏**（换了走向，不是原样重复），
#   另外在 4 个小节末尾加了个小鼓花。最后落在属和弦 G 上 —— 绕回开头的 C 有推进感。
NOTE = {
    "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.00,
    "A3": 220.00, "B3": 246.94,
    "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
    "A4": 440.00, "B4": 493.88,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99,
    "A5": 880.00, "B5": 987.77, "C6": 1046.50,
}

# 每 2 小节一个和弦，共 8 块 = 16 小节
PROG = [
    {"bass": "C3", "chord": ["C4", "E4", "G4"], "scale": ["C4", "D4", "E4", "G4", "A4", "C5", "E5", "G5"]},
    {"bass": "G3", "chord": ["B3", "D4", "G4"], "scale": ["B3", "D4", "E4", "G4", "A4", "B4", "D5", "G5"]},
    {"bass": "A3", "chord": ["C4", "E4", "A4"], "scale": ["A3", "C4", "E4", "G4", "A4", "C5", "E5", "A5"]},
    {"bass": "F3", "chord": ["C4", "F4", "A4"], "scale": ["A3", "C4", "F4", "G4", "A4", "C5", "F5", "A5"]},
    {"bass": "C3", "chord": ["C4", "E4", "G4"], "scale": ["C4", "D4", "E4", "G4", "A4", "C5", "E5", "G5"]},
    {"bass": "G3", "chord": ["B3", "D4", "G4"], "scale": ["B3", "D4", "E4", "G4", "A4", "B4", "D5", "G5"]},
    {"bass": "F3", "chord": ["C4", "F4", "A4"], "scale": ["A3", "C4", "F4", "G4", "A4", "C5", "F5", "A5"]},
    {"bass": "G3", "chord": ["B3", "D4", "G4"], "scale": ["B3", "D4", "E4", "G4", "A4", "B4", "D5", "G5"]},
]

# 主旋律：每个和弦块 16 个八分音符（每小节用其中 8 个），-1 = 休止。用音阶下标（0~7）。
# 前 4 块是主题，后 4 块是变奏 —— 走向换过，所以听两遍不觉得是同一段。
MELODY = [
    [5, -1, 4, 3, 5, -1, 6, -1, 7, -1, 6, 5, 4, 3, 2, -1],
    [4, -1, 3, 2, 3, 4, 5, -1, 4, 3, 2, -1, 3, -1, -1, -1],
    [5, 6, 7, -1, 6, 5, 4, -1, 3, 4, 5, -1, 6, 5, 4, 3],
    [2, -1, 3, 4, 5, -1, 6, 5, 4, -1, 5, 4, 3, 2, 1, -1],
    # ↓ 变奏：第 2 遍从高音往下走，再爬回去
    [7, -1, 6, 5, 4, -1, 3, -1, 4, 5, 6, -1, 7, 6, 5, -1],
    [5, -1, 4, 3, 4, 5, 6, -1, 5, 4, 3, -1, 2, -1, 3, -1],
    [3, 4, 5, 6, 7, -1, 6, 5, 4, 3, 2, -1, 3, 4, 5, -1],
    [6, -1, 5, 4, 3, -1, 2, 3, 4, 5, 4, 3, 2, -1, -1, -1],
]

# 这 4 个小节的末尾加一小段鼓花，把 16 小节的循环分成四句
FILL_BARS = {3, 7, 11, 15}


def make_bgm(bpm=132.0, night=False):
    beat = 60.0 / bpm
    eighth = beat / 2.0
    bars = 16
    total = bars * 4 * beat
    b = new_buf(total + 0.5)

    mel_amp = 0.20 if night else 0.26
    bass_amp = 0.26 if night else 0.30
    chord_amp = 0.10 if night else 0.15
    mel_kind = "tri" if night else "sq25"
    drum = 0.0 if night else 1.0

    for bar in range(bars):
        block = bar // 2               # 0..7 对应 8 个和弦
        ch = PROG[block]
        bar_t = bar * 4 * beat
        # 贝斯：1、3 拍根音，2、4 拍五度。后半段改成跳八度，低音不至于一条线
        for k, off in enumerate((0.0, 1.0, 2.0, 3.0)):
            if k % 2 == 0:
                note = ch["bass"]
            elif bar >= 8:
                note = ch["bass"]           # 变奏段用同音重复，更稳
            else:
                note = _fifth(ch["bass"])
            add_tone(b, bar_t + off * beat, beat * 0.9, NOTE[note], "tri",
                     bass_amp, decay=1.2)
        # 和弦垫：2、4 拍短促一下
        for off in (1.0, 3.0):
            for n in ch["chord"]:
                add_tone(b, bar_t + off * beat, beat * 0.42, NOTE[n], "sq12",
                         chord_amp, attack=0.004, release=0.10, decay=6.0)
        # 主旋律：每小节 8 个八分音符
        pat = MELODY[block]
        for i in range(8):
            deg = pat[(i + (4 if bar % 2 == 1 else 0)) % 16]
            if deg < 0:
                continue
            add_tone(b, bar_t + i * eighth, eighth * 0.86,
                     NOTE[ch["scale"][deg]], mel_kind, mel_amp,
                     attack=0.005, release=0.05, decay=2.0)
        # 轻打击：底鼓 + 踩镲
        if drum > 0.0:
            for off in (0.0, 2.0):
                add_tone(b, bar_t + off * beat, 0.12, 90.0, "sine", 0.22, decay=22.0)
            for i in range(8):
                add_noise(b, bar_t + i * eighth, 0.05, 0.045,
                          decay=55.0, hp=0.85, seed=1000 + bar * 16 + i)
            # 乐句末尾的小鼓花：16 分音符三连滚 + 一个军鼓
            if bar in FILL_BARS:
                for j in range(4):
                    add_noise(b, bar_t + 3 * beat + j * (beat / 4.0), 0.04,
                              0.05 + 0.015 * j, decay=70.0, hp=0.6,
                              seed=7000 + bar * 8 + j)
                add_noise(b, bar_t + 3.9 * beat, 0.12, 0.075,
                          decay=26.0, lp=0.55, seed=8000 + bar)
    return b


def _fifth(note):
    """取一个根音的上方五度（用于贝斯的 2、4 拍）"""
    table = {"C3": "G3", "G3": "D3", "A3": "E3", "F3": "C4"}
    return table.get(note, note)


# ---------------------------------------------------------------- 海图 BGM（行船）
# 6/8 摇摆、慢速、留白多 —— 要的是「辽阔 + 晃」：海面一望无际，船在浪上一起一伏。
# 12 小节一循环，A 小调五声，主旋律用三角波（柔和，不抢戏），
# 每两小节涌一道低频"浪"，反拍上加两颗轻摇铃。最后落在 Em 上（半终止），
# 绕回开头的 Am 有推进感，循环听不出接缝。
def midi(m):
    """MIDI 音高号 -> 频率（69 = A4 = 440Hz）"""
    return 440.0 * (2.0 ** ((m - 69) / 12.0))


OCEAN_BPM = 100.0
OCEAN_BARS = 12
# (贝斯根音, 和弦音们) 的 MIDI 号：Am Em F C Am Em G G F C Dm Em
OCEAN_PROG = [
    (45, [57, 60, 64]),
    (40, [52, 56, 59]),
    (41, [53, 57, 60]),
    (48, [55, 60, 64]),
    (45, [57, 60, 64]),
    (40, [52, 56, 59]),
    (43, [55, 59, 62]),
    (43, [55, 59, 62]),
    (41, [53, 57, 60]),
    (48, [55, 60, 64]),
    (38, [50, 53, 57]),
    (40, [52, 56, 59]),
]
# 每小节 6 个八分音符，-1 = 休止。A 小调五声：A(69) C(72) D(74) E(76) G(79)
OCEAN_MELODY = [
    [76, -1, -1, 72, -1, -1],
    [74, -1, 76, -1, -1, -1],
    [72, -1, -1, 69, -1, -1],
    [67, -1, 69, -1, -1, -1],
    [76, -1, 79, -1, 76, -1],
    [74, -1, 72, 74, -1, -1],
    [71, -1, 74, -1, 71, -1],
    [72, -1, -1, -1, -1, -1],
    [69, -1, 72, -1, 74, -1],
    [76, -1, -1, 74, 72, -1],
    [74, -1, 72, -1, 69, -1],
    [71, -1, 76, -1, -1, -1],
]


def make_bgm_ocean():
    beat = 60.0 / OCEAN_BPM
    eighth = beat / 2.0
    bar = 6 * eighth                       # 6/8：一小节 = 6 个八分
    loop = OCEAN_BARS * bar
    buf = new_buf(loop + bar)              # 多留一小节给尾音绕回来（见 wrap_tail）
    for i, (root, chord) in enumerate(OCEAN_PROG):
        t0 = i * bar
        last = (i == OCEAN_BARS - 1)
        # 最后一小节的长音故意**拖过循环点**（多出来的那截由 wrap_tail 绕回开头），
        # 不然这一小节的音在循环点前就衰完了，每转一圈末尾都有半秒空档，接缝很明显。
        tail_dur = (loop - t0) + eighth * 3 if last else 0.0
        # 贝斯：第 1、4 个八分各一下，用长音铺底（三角波最柔）
        add_tone(buf, t0,
                 tail_dur if last else eighth * 2.6, midi(root), "tri", 0.30,
                 decay=0.62 if last else 1.1)
        add_tone(buf, t0 + 3 * eighth,
                 tail_dur if last else eighth * 2.4, midi(root + 7), "tri", 0.20,
                 decay=0.78 if last else 1.3)
        # 和弦垫：同两个点轻点一下，音量压得很低，只做"和声背景"
        for off in (0.0, 3 * eighth):
            for n in chord:
                var_dur = (loop - (t0 + off)) + eighth * 3 if last else eighth * 1.5
                add_tone(buf, t0 + off, var_dur, midi(n), "sq12", 0.070,
                         attack=0.02, release=0.30, decay=1.9 if last else 2.6)
        # 主旋律
        for k, deg in enumerate(OCEAN_MELODY[i]):
            if deg < 0:
                continue
            add_tone(buf, t0 + k * eighth, eighth * 1.7, midi(deg), "tri", 0.20,
                     attack=0.02, release=0.25, decay=1.4)
        # 浪：每两小节一道低频噪声"涌上来再退下去"
        if i % 2 == 0:
            add_noise(buf, t0, bar * 1.7, 0.055, decay=1.5, lp=0.055, seed=200 + i)
        # 轻摇铃：每小节第 3、6 个八分（反拍）上各一颗
        for off in (2 * eighth, 5 * eighth):
            add_noise(buf, t0 + off, 0.07, 0.028, decay=48.0, hp=0.88,
                      seed=300 + i * 4 + int(off * 100))
    return wrap_tail(buf, loop)


# ---------------------------------------------------------------- 战斗 BGM（开打）
# 150 BPM、4/4、D 小调，鼓组是主角：底鼓踩 1、3，军鼓踩 2、4（反拍），
# 16 分踩镲垫底，每 8 小节来一次军鼓滚奏；贝斯走连续八分（推着往前跑），
# 旋律用方波（有金属味），刻意多用小二度/减五度制造紧张感。
# 16 小节一循环，最后落在 A 和弦上（属和弦），绕回开头的 Dm 有"再来一轮"的冲劲。
BATTLE_BPM = 150.0
BATTLE_BARS = 16
# Dm Dm Bb C | Dm Dm Gm A  —— 16 小节，每块 2 小节
BATTLE_PROG = [
    (50, [62, 65, 69]),
    (50, [62, 65, 69]),
    (46, [58, 62, 65]),
    (48, [60, 64, 67]),
    (50, [62, 65, 69]),
    (50, [62, 65, 69]),
    (43, [58, 62, 67]),
    (45, [57, 61, 64]),
]
# D 自然小调音阶（D E F G A Bb C D E），用下标写旋律，-1 = 休止
BATTLE_SCALE = [50, 52, 53, 55, 57, 58, 60, 62, 64]
# 每块 16 个八分音符（2 小节 x 8）
BATTLE_MELODY = [
    [7, -1, 6, 5, 4, -1, 3, 2, 4, -1, 5, -1, 6, 5, 4, -1],
    [5, -1, 4, 3, 2, -1, 3, 4, 5, -1, 6, -1, 7, -1, -1, -1],
    [4, -1, 5, 6, 7, -1, 6, 5, 4, 3, 2, -1, 3, -1, -1, -1],
    [7, 6, 5, 4, 5, -1, 6, 7, 8, -1, 7, 6, 5, -1, 4, -1],
    [2, 3, 4, 5, 6, -1, 7, 8, 7, -1, 6, 5, 4, -1, 3, -1],
    [5, -1, 4, -1, 3, -1, 2, -1, 4, 5, 6, 7, 8, -1, 7, -1],
    [6, -1, 5, 4, 3, -1, 4, 5, 6, -1, 7, -1, 6, 5, 4, 3],
    [2, -1, 3, 4, 5, 6, 7, -1, 8, -1, 7, -1, 6, -1, -1, -1],
]


def make_bgm_battle():
    beat = 60.0 / BATTLE_BPM
    eighth = beat / 2.0
    bar = 4 * beat
    loop = BATTLE_BARS * bar
    buf = new_buf(loop + bar)              # 多留一小节给尾音绕回来（见 wrap_tail）
    # —— 鼓组：底鼓走 1、3 拍，军鼓走 2、4 拍（军乐味的进行感）——
    for i in range(BATTLE_BARS):
        t0 = i * bar
        for off in (0.0, 2.0):
            add_tone(buf, t0 + off * beat, 0.13, 72.0, "sine", 0.30, decay=24.0)
        for off in (1.0, 3.0):
            add_noise(buf, t0 + off * beat, 0.14, 0.10, decay=24.0, lp=0.55,
                      seed=4000 + i * 8 + int(off))
        # 16 分踩镲：第 3 个八分位置稍微重一点，做出摇摆感
        for k in range(8):
            hit = 0.026 if k % 2 else 0.014
            add_noise(buf, t0 + k * eighth, 0.045, hit, decay=60.0, hp=0.9,
                      seed=5000 + i * 16 + k)
        # 每 8 小节收尾来一串军鼓滚奏，把整段分成两句
        if i % 8 == 7:
            for j in range(6):
                add_noise(buf, t0 + 3 * beat + j * (beat / 6.0), 0.05,
                          0.05 + 0.012 * j, decay=70.0, hp=0.6, seed=6000 + i * 8 + j)
    for block, (root, chord) in enumerate(BATTLE_PROG):
        for half in range(2):
            i = block * 2 + half
            t0 = i * bar
            # 贝斯：连续八分，根音与八度交替 -> 一直往前推
            for k in range(8):
                n = root if k % 2 == 0 else root + 12
                add_tone(buf, t0 + k * eighth, eighth * 0.9, midi(n), "tri", 0.24, decay=6.0)
            # 和弦刺：1、3 拍各一下短促的（sq12 有木质感，不刺耳）
            for off in (0.0, 2.0):
                for n in chord:
                    add_tone(buf, t0 + off * beat, beat * 0.30, midi(n), "sq12", 0.075,
                             attack=0.004, release=0.09, decay=9.0)
            # 主旋律
            for k, deg in enumerate(BATTLE_MELODY[block]):
                if deg < 0:
                    continue
                add_tone(buf, t0 + k * eighth, eighth * 0.85,
                         midi(BATTLE_SCALE[deg]), "sq25", 0.21,
                         attack=0.004, release=0.05, decay=3.0)
    return wrap_tail(buf, loop)


# ---------------------------------------------------------------- 主流程
def main():
    print("合成音效……")
    sfx = {
        "hoe": sfx_hoe(), "water": sfx_water(), "fill": sfx_fill(),
        "plant": sfx_plant(), "harvest": sfx_harvest(), "pickup": sfx_pickup(),
        "coin": sfx_coin(),
        "buy": sfx_buy(), "error": sfx_error(), "ui_click": sfx_ui_click(),
        "ui_open": sfx_ui_open(), "ui_close": sfx_ui_close(),
        "step": sfx_step(), "sleep": sfx_sleep(), "bin": sfx_bin(),
        "chop": sfx_chop(), "fell": sfx_fell(), "campfire": sfx_campfire(),
        "deploy": sfx_deploy(), "move": sfx_move(), "attack": sfx_attack(),
    }
    for name, buf in sfx.items():
        save_wav(os.path.join(OUT, "sfx", name + ".wav"), buf, gain=0.9)

    print("合成 BGM……")
    save_wav(os.path.join(OUT, "bgm", "bgm_day.wav"), make_bgm(132.0, False), gain=0.85)
    save_wav(os.path.join(OUT, "bgm", "bgm_night.wav"), make_bgm(88.0, True), gain=0.8)
    save_wav(os.path.join(OUT, "bgm", "bgm_ocean.wav"), make_bgm_ocean(), gain=0.85)
    save_wav(os.path.join(OUT, "bgm", "bgm_battle.wav"), make_bgm_battle(), gain=0.8)
    print("完成 →", OUT)


if __name__ == "__main__":
    main()
