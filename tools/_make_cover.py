# -*- coding: utf-8 -*-
"""生成《潮汐港》游戏封面图标（.ico 多尺寸 + 预览 png）

画面：像素海面 + 落日 + 一艘挂着帆的木船（船体直接复用游戏里的
resources/texture/boat.png，风格跟游戏内一致），配上「潮汐港」标题。
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "outputs")
os.makedirs(OUT, exist_ok=True)

S = 512
CELL = 8                    # 一个「像素格」= 8 屏幕像素，保证颗粒感统一
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def block(x, y, w=1, h=1, col=(0, 0, 0, 255)):
    """按像素格画一个方块（x/y/w/h 单位都是格子）"""
    d.rectangle([x * CELL, y * CELL, (x + w) * CELL - 1, (y + h) * CELL - 1], fill=col)


N = S // CELL               # 64 格
HORIZON = 34                # 海平线在从上数第 34 格

# ---------- 1. 天空：深夜蓝 -> 暖橙（黄昏），逐格渐变 ----------
SKY_TOP = (26, 34, 52)
SKY_MID = (74, 78, 104)
SKY_LOW = (196, 128, 96)
SKY_HOT = (238, 176, 118)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


for y in range(HORIZON):
    t = y / float(HORIZON - 1)
    if t < 0.55:
        col = lerp(SKY_TOP, SKY_MID, t / 0.55)
    elif t < 0.85:
        col = lerp(SKY_MID, SKY_LOW, (t - 0.55) / 0.30)
    else:
        col = lerp(SKY_LOW, SKY_HOT, (t - 0.85) / 0.15)
    block(0, y, N, 1, col + (255,))

# 星星（天上一点点，别太多）
for sx, sy in [(4, 3), (9, 7), (14, 2), (20, 6), (27, 4), (33, 8), (44, 3),
               (50, 6), (55, 2), (59, 7), (38, 12), (12, 13), (48, 14)]:
    block(sx, sy, 1, 1, (222, 226, 240, 255))

# 落日：暖色圆盘 + 一圈淡淡光环（放左上，右边留给船帆）
SUN_X, SUN_Y, SUN_R = 11, 22, 5
for y in range(SUN_Y - SUN_R - 3, SUN_Y + SUN_R + 4):
    for x in range(SUN_X - SUN_R - 3, SUN_X + SUN_R + 4):
        dd = ((x - SUN_X) ** 2 + (y - SUN_Y) ** 2) ** 0.5
        if dd <= SUN_R - 1:
            block(x, y, 1, 1, (252, 226, 168, 255))
        elif dd <= SUN_R + 0.5:
            block(x, y, 1, 1, (244, 190, 132, 255))
        elif dd <= SUN_R + 2.5:
            block(x, y, 1, 1, (206, 146, 116, 120))

# 远处的云：几条暖色横带（避开左上角的落日）
for cy, cx0, cw in [(26, 22, 14), (26, 42, 10), (30, 30, 18), (33, 6, 5), (33, 46, 12)]:
    block(cx0, cy, cw, 1, (214, 166, 140, 190))
    block(cx0 + 3, cy - 1, max(2, cw - 6), 1, (232, 188, 152, 160))

# ---------- 2. 海：从上到下由暖橙反光过渡到深青蓝 ----------
SEA_TOP = (150, 122, 128)
SEA_MID = (44, 88, 116)
SEA_DEEP = (18, 40, 62)
for y in range(HORIZON, N):
    t = (y - HORIZON) / float(N - HORIZON - 1)
    col = lerp(SEA_TOP, SEA_MID, min(1.0, t / 0.45)) if t < 0.45 \
        else lerp(SEA_MID, SEA_DEEP, (t - 0.45) / 0.55)
    block(0, y, N, 1, col + (255,))

# 海平线上的一道反光带（太阳正下方，细细一条）
for y in range(HORIZON, HORIZON + 5):
    w = max(1, 5 - (y - HORIZON))
    block(SUN_X - w, y, w * 2 + 1, 1, (236, 198, 158, 90))

# 波浪：一排排小横向高光（近处更宽更亮）
WAVE_ROWS = [
    (37, 214, 176, 150, 90), (40, 150, 132, 116, 70), (44, 236, 200, 172, 100),
    (48, 170, 152, 138, 80), (52, 226, 196, 170, 95), (56, 160, 150, 140, 75),
    (60, 240, 214, 190, 105),
]
for wy, r, g, b, a in WAVE_ROWS:
    step = 11 if wy < 46 else 9
    for wx in range((wy * 5) % step, N, step):
        block(wx, wy, 3 if wy > 50 else 2, 1, (r, g, b, a))

# ---------- 3. 船：船体用游戏里的 boat.png，帆和桅杆现画 ----------
boat_src = Image.open(os.path.join(ROOT, "resources", "texture", "boat.png")).convert("RGBA")
SCALE = 6
hull = boat_src.resize((boat_src.width * SCALE, boat_src.height * SCALE), Image.NEAREST)
hx = (S - hull.width) // 2
hy = 512 - hull.height - 62

MAST = (78, 54, 36, 255)
SAIL_LIGHT = (238, 226, 202, 255)
SAIL_DARK = (196, 180, 156, 255)
SAIL_EDGE = (150, 132, 110, 255)
FLAG = (176, 52, 44, 255)

# 桅杆（船体中线往上一根），另加一根横杆挂帆
mast_x = S // 2 + 4
mast_top = hy - 176
d.rectangle([mast_x, mast_top, mast_x + 7, hy + 24], fill=MAST)
d.rectangle([mast_x - 4, mast_top - 8, mast_x + 11, mast_top - 1], fill=MAST)

# 帆：右侧的三角主帆（像素阶梯边缘，避免斜线糊成一团）
sail_x0 = mast_x + 8
sail_top = mast_top + 10
sail_bot = hy - 4
SAIL_W = 150
steps = sail_bot - sail_top
for i in range(steps):
    t = i / float(max(1, steps - 1))
    w = int(SAIL_W * (0.10 + 0.90 * t))
    y = sail_top + i
    shade = SAIL_LIGHT if i % 7 < 5 else SAIL_DARK
    d.rectangle([sail_x0, y, sail_x0 + w, y + 1], fill=shade)
d.rectangle([sail_x0, sail_top, sail_x0 + 2, sail_bot], fill=SAIL_EDGE)
d.rectangle([sail_x0, sail_bot - 2, sail_x0 + SAIL_W, sail_bot], fill=SAIL_EDGE)

# 桅顶小旗
d.rectangle([mast_x + 12, mast_top - 8, mast_x + 30, mast_top - 4], fill=FLAG)
d.rectangle([mast_x + 34, mast_top - 7, mast_x + 44, mast_top - 5], fill=FLAG)

# 船体 + 水面倒影：船底下几道横向暗影，看着是浮在水上
img.alpha_composite(hull, (hx, hy))
for i, (dy, a) in enumerate([(6, 110), (14, 80), (22, 55), (30, 32)]):
    y = hy + hull.height - 10 + dy
    if y >= S:
        break
    d.rectangle([hx + 30 + i * 6, y, hx + hull.width - 30 - i * 6, y + 2],
                fill=(14, 30, 46, a))

# ---------- 4. 复古双线外框 ----------
FRAME = (235, 210, 160, 255)
FRAME_DIM = (120, 110, 90, 255)
d.rectangle([6, 6, S - 7, S - 7], outline=FRAME, width=6)
d.rectangle([20, 20, S - 21, S - 21], outline=FRAME_DIM, width=2)

# ---------- 5. 标题「潮汐港」+ 小字副标 ----------
FONT_PATH = os.path.join(ROOT, "resources", "font", "IPix.ttf")
font = ImageFont.truetype(FONT_PATH, 84)
TEXT = "潮汐港"
TEXT_COLOR = (240, 222, 174, 255)
SHADOW = (16, 24, 36, 255)

bbox = d.textbbox((0, 0), TEXT, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
tx = (S - tw) // 2 - bbox[0]
ty = 74
d.text((tx + 5, ty + 5), TEXT, font=font, fill=SHADOW)
d.text((tx, ty), TEXT, font=font, fill=TEXT_COLOR)

font_s = ImageFont.truetype(FONT_PATH, 26)
TAG = "TIDEPORT"
bbox2 = d.textbbox((0, 0), TAG, font=font_s)
tag_w = bbox2[2] - bbox2[0]
tx2 = (S - tag_w) // 2 - bbox2[0]
ty2 = 178
d.text((tx2 + 3, ty2 + 3), TAG, font=font_s, fill=SHADOW)
d.text((tx2, ty2), TAG, font=font_s, fill=(226, 238, 248, 255))

preview = img.copy()
preview.save(os.path.join(OUT, "cover_preview.png"))

# ---------- 6. 生成 .ico（多尺寸）+ 窗口图标 ----------
sizes = [16, 24, 32, 48, 64, 128, 256]
ico_path = os.path.join(ROOT, "icon.ico")
img.save(ico_path, format="ICO", sizes=[(s, s) for s in sizes])
img.resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "icon_256.png"))
print("已生成:")
print("  预览:", os.path.join(OUT, "cover_preview.png"))
print("  图标:", ico_path)
