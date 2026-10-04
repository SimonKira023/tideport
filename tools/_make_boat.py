# -*- coding: utf-8 -*-
# _make_boat.py —— 木船像素贴图：道具图标(16x16) + 大地图船身(32x20)
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "resources", "texture")
os.makedirs(OUT, exist_ok=True)

HULL    = (134, 94, 56, 255)    # 船帮深木
HULL_SH = (102, 70, 42, 255)
DECK    = (176, 134, 84, 255)   # 船板
DECK_SH = (148, 110, 66, 255)
RIM     = (92, 62, 38, 255)     # 船缘描边
MAST    = (110, 78, 46, 255)
SAIL    = (226, 214, 186, 255)  # 米白帆
SAIL_SH = (198, 184, 156, 255)

def P(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((int(x), int(y)), c)

def R(img, x0, y0, x1, y1, c):
    for y in range(int(y0), int(y1) + 1):
        for x in range(int(x0), int(x1) + 1):
            P(img, x, y, c)

# ---------------- 图标 16x16：斜放的 小木船 ----------------
icon = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
# 船体（两端翘起的橢圆剖面）
R(icon, 2, 8, 13, 10, HULL)
R(icon, 3, 10, 12, 11, HULL_SH)
R(icon, 1, 7, 3, 8, HULL)          # 左船头上翘
R(icon, 12, 7, 14, 8, HULL)
P(icon, 0, 6, HULL); P(icon, 15, 6, HULL)
R(icon, 3, 8, 12, 8, DECK)         # 船板
P(icon, 4, 9, DECK_SH); P(icon, 8, 9, DECK_SH)
R(icon, 0, 6, 0, 6, RIM); R(icon, 15, 6, 15, 6, RIM)
R(icon, 1, 7, 1, 8, RIM); R(icon, 14, 7, 14, 8, RIM)
R(icon, 2, 11, 13, 11, RIM)
icon.save(os.path.join(OUT, "boat_icon.png"))
print("boat_icon.png 16x16")

# ---------------- 大地图船身 32x20（顶视角，人在上面） ----------------
boat = Image.new("RGBA", (32, 20), (0, 0, 0, 0))
# 船帮外圈（尖头朝右）
hull_rows = {
    2: (8, 22), 3: (5, 26), 4: (3, 28), 5: (2, 29), 6: (1, 30),
    7: (1, 31), 8: (0, 32), 9: (0, 32), 10: (0, 32), 11: (0, 32),
    12: (1, 31), 13: (1, 30), 14: (2, 29), 15: (3, 28), 16: (5, 26), 17: (8, 22),
}
for y, (x0, x1) in hull_rows.items():
    R(boat, x0, y, x1, y, HULL)
# 船缘描边（上下两条弧）
for y in (2, 3, 16, 17):
    x0, x1 = hull_rows[y]
    R(boat, x0, y, x1, y, RIM)
# 舱内甲板（中间挖空）
deck_rows = {
    4: (7, 24), 5: (5, 27), 6: (4, 28), 7: (3, 29), 8: (2, 30),
    9: (2, 30), 10: (2, 30), 11: (2, 30), 12: (3, 29), 13: (4, 28), 14: (5, 27), 15: (7, 24),
}
for y, (x0, x1) in deck_rows.items():
    R(boat, x0, y, x1, y, DECK)
# 甲板板缝
for x in (9, 14, 19, 24):
    for y, (x0, x1) in deck_rows.items():
        if x0 <= x <= x1:
            P(boat, x, y, DECK_SH)
# 右舷内侧阴影（光源左上）
for y, (x0, x1) in deck_rows.items():
    P(boat, x1, y, DECK_SH)
# 船头尖
P(boat, 31, 9, HULL_SH); P(boat, 31, 10, HULL_SH)
boat.save(os.path.join(OUT, "boat.png"))
print("boat.png 32x20")

# 预览
prev = Image.new("RGBA", (160, 110), (60, 110, 150, 255))
prev.paste(icon.resize((64, 64), Image.NEAREST), (12, 12), icon.resize((64, 64), Image.NEAREST))
prev.paste(boat.resize((96, 60), Image.NEAREST), (56, 40), boat.resize((96, 60), Image.NEAREST))
prev.save(os.path.join(OUT, "boat_preview.png"))
print("boat_preview.png")
