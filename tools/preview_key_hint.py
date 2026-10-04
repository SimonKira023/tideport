# tools/preview_key_hint.py —— 把「按键提示」的样式按 key_hint.gd 的布局画出来放大看
#
# 为什么要这个：Godot headless 截不了图，而 scene_dump 只认 Sprite2D / TileMapLayer，
#   抓不到 KeyHint 自己 _draw() 出来的东西。这里用 PIL 按**同一套尺寸和配色**复刻一遍，
#   放大 8 倍输出，改样式的时候能立刻看到长什么样。
#
# 坐标约定：**布局全程用「放大后的像素」算**（字体也直接用放大号），
#   中途不二次乘 SCALE —— 否则徽章会被拉宽、字会跑出框。
#
# 跑法：python tools/preview_key_hint.py outputs/按键提示.png
from PIL import Image, ImageDraw, ImageFont
import sys, os

FONT = os.path.join(os.path.dirname(__file__), "..", "resources", "font", "IPix.ttf")

KEY_SIZE = 9
WORD_SIZE = 10
PAD = (5, 3)
GAP = 5
BADGE_PAD = 4
SCALE = 8

BG = (26, 18, 15, 209)
BORDER = (184, 148, 87)
BADGE_BG = (242, 230, 194)
BADGE_BORDER = (107, 77, 46)
KEY_COLOR = (51, 36, 20)
WORD_COLOR = (255, 255, 255)
OUTLINE = (0, 0, 0)

# 场景里实际用到的六条提示
HINTS = [
    ("F", "交易"), ("F", "打水"), ("F", "存入作物"),
    ("F", "进屋"), ("F", "睡觉"), ("F", "出门"),
]


def render_hint(key, word, f_key, f_word):
    """按 key_hint.gd 的布局画一个提示框，返回放大后的 RGBA 图。"""
    meas = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    kw = meas.textlength(key, font=f_key)
    ww = meas.textlength(word, font=f_word)
    pad_x, pad_y = PAD[0] * SCALE, PAD[1] * SCALE
    gap, badge_pad = GAP * SCALE, BADGE_PAD * SCALE
    line_h = max(KEY_SIZE, WORD_SIZE) * SCALE + 4 * SCALE

    badge_w = int(kw) + badge_pad * 2
    bw = int(pad_x * 2 + badge_w + gap + ww)
    bh = int(pad_y * 2 + line_h)

    img = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, bw - 1, bh - 1], fill=BG)
    d.rectangle([0, 0, bw - 1, bh - 1], outline=BORDER, width=SCALE)
    d.rectangle([pad_x, pad_y, pad_x + badge_w - 1, pad_y + line_h - 1], fill=BADGE_BG)
    d.rectangle([pad_x, pad_y, pad_x + badge_w - 1, pad_y + line_h - 1],
                outline=BADGE_BORDER, width=SCALE)

    kx = pad_x + (badge_w - kw) / 2
    ky = pad_y + (line_h - KEY_SIZE * SCALE) / 2 - SCALE
    d.text((kx, ky), key, font=f_key, fill=KEY_COLOR)

    wx = pad_x + badge_w + gap
    wy = pad_y + (line_h - WORD_SIZE * SCALE) / 2 - SCALE
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        d.text((wx + dx * SCALE, wy + dy * SCALE), word, font=f_word, fill=OUTLINE)
    d.text((wx, wy), word, font=f_word, fill=WORD_COLOR)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "outputs/按键提示.png"
    f_key = ImageFont.truetype(FONT, KEY_SIZE * SCALE)
    f_word = ImageFont.truetype(FONT, WORD_SIZE * SCALE)
    imgs = [render_hint(k, w, f_key, f_word) for k, w in HINTS]

    margin, cols = 24, 3
    col_w = max(i.width for i in imgs)
    row_h = max(i.height for i in imgs)
    rows = (len(imgs) + cols - 1) // cols
    W = cols * (col_w + margin) + margin
    H = margin + 28 + rows * (row_h + margin)
    canvas = Image.new("RGBA", (W, H), (36, 52, 40, 255))   # 草地绿底，还原实际观感
    d = ImageDraw.Draw(canvas)
    d.text((margin, margin - 4), "走近 -> 飞入并悬浮（放大 8 倍）",
           font=f_word, fill=(232, 232, 220))
    for i, im in enumerate(imgs):
        x = margin + (i % cols) * (col_w + margin)
        y = margin + 28 + (i // cols) * (row_h + margin)
        canvas.alpha_composite(im, (x, y))
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    canvas.save(out)
    print("saved", out, canvas.size)


main()
