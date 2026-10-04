from PIL import Image
import os, sys
base = "resources/Farm RPG - Tiny Asset Pack - (All in One)/"
items = sys.argv[1:]
S = 3
outs = []
for rel in items:
    p = base + rel
    im = Image.open(p).convert("RGBA")
    outs.append((rel, im))
W = max(i.width for _, i in outs)
H = sum(i.height + 12 for _, i in outs)
canvas = Image.new("RGBA", (W + 170, H), (30, 30, 40, 255))
y = 0
for rel, im in outs:
    # checkerboard背景
    bg = Image.new("RGBA", im.size, (60, 60, 70, 255))
    for x in range(0, im.size[0], 8):
        for yy in range(0, im.size[1], 8):
            if (x // 8 + yy // 8) % 2 == 0:
                bg.paste((90, 90, 100, 255), (x, yy, min(x+8, im.size[0]), min(yy+8, im.size[1])))
    bg.alpha_composite(im)
    canvas.alpha_composite(bg, (170, y))
    # 16px 网格线
    canvas.paste((255, 0, 0, 255), (0, y + 0, 170, y + 1))
    y += im.height + 12
canvas = canvas.resize((canvas.width * S, canvas.height * S), Image.NEAREST)
canvas.save("outputs/_probe_sheet.png")
print("saved", canvas.size)
for rel, im in outs:
    print(rel, im.size)
