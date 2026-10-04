# -*- coding: utf-8 -*-
"""运行时生成木地板和食物的预览图，存到 outputs/ 给用户看效果。"""
from PIL import Image, ImageDraw, ImageFont
import os
OUT = r"C:/Users/蔡璟熙/Documents/新建游戏项目/outputs"
os.makedirs(OUT, exist_ok=True)

# 木地板材质预览（程序化生成 16x16 木板 + 8x 放大）
FILL = (180, 132, 80)
RIM = (102, 64, 32)
HL = (204, 158, 100)
import random

def make_floor_tile(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (16, 16), FILL + (255,))
    # 四边都画描边
    for i in range(16):
        img.putpixel((0, i), RIM + (255,))
        img.putpixel((15, i), RIM + (255,))
        img.putpixel((i, 0), RIM + (255,))
        img.putpixel((i, 15), RIM + (255,))
    # 横竖交叉缝
    for y in range(16):
        img.putpixel((8, y), RIM + (255,))
    for x in range(16):
        img.putpixel((x, 8), RIM + (255,))
    # 木纹亮点
    for x in [4, 12]:
        for y in [4, 12]:
            img.putpixel((x, y), HL + (255,))
    return img

# 4x4 木地板拼接预览
S = 8  # 8 倍缩放
canvas = Image.new("RGBA", (16 * 4 * S, 16 * 4 * S), (104, 132, 74, 255))  # 草绿色背景
for row in range(4):
    for col in range(4):
        tile = make_floor_tile(row * 100 + col)
        tile = tile.resize((16 * S, 16 * S), Image.NEAREST)
        canvas.alpha_composite(tile, (col * 16 * S, row * 16 * S))
canvas.save(os.path.join(OUT, "preview_floor_tiles.png"))
print("preview_floor_tiles.png saved")

# 食物图标网格（用真实素材）
ICON_DIR = r"resources/Farm RPG - Tiny Asset Pack - (All in One)/Icons/Food Icons"
foods = [
    ("烤土豆",     "Baked Potato.png",      "咸"),
    ("胡萝卜沙拉", "Salad.png",             "酸"),
    ("卷心菜汤",   "Soup.png",              "鲜"),
    ("南瓜派",     "Pumpkin Pie.png",       "甜"),
]
SW, SH = 80, 96
canvas = Image.new("RGBA", (SW * len(foods), SH), (40, 30, 24, 255))
try:
    fnt = ImageFont.truetype("resources/font/IPix.ttf", 14)
except Exception:
    fnt = ImageFont.load_default()
for i, (name, fn, taste) in enumerate(foods):
    p = os.path.join(ICON_DIR, fn)
    if not os.path.exists(p):
        continue
    icon = Image.open(p).convert("RGBA")
    icon.thumbnail((64, 64), Image.NEAREST)
    canvas.alpha_composite(icon, ((SW - icon.width) // 2 + i * SW, 4))
    d = ImageDraw.Draw(canvas)
    d.text((i * SW + 10, 70), name, font=fnt, fill=(220, 200, 160))
    d.text((i * SW + 30, 88), taste, font=fnt, fill=(255, 180, 180))
canvas.save(os.path.join(OUT, "preview_foods.png"))
print("preview_foods.png saved")

# 木地板道具 icon
img = Image.new("RGBA", (32, 32), FILL + (255,))
for i in range(32):
    img.putpixel((0, i), RIM + (255,))
    img.putpixel((31, i), RIM + (255,))
    img.putpixel((i, 0), RIM + (255,))
    img.putpixel((i, 31), RIM + (255,))
for y in range(32):
    img.putpixel((16, y), RIM + (255,))
for x in range(32):
    img.putpixel((x, 16), RIM + (255,))
img = img.resize((256, 256), Image.NEAREST)
img.save(os.path.join(OUT, "preview_wood_floor_icon.png"))
print("preview_wood_floor_icon.png saved")