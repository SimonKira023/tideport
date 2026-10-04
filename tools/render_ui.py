# tools/render_ui.py —— 把 tools/ui_dump.gd 导出的排版指令用 PIL 画成 PNG。
#
# 用法（项目根目录，先跑一次 tools/ui_dump.tscn）：
#   python tools/render_ui.py outputs/UI预览.png [--show settlement] [--bg 24,22,20]
#
# 只画「矩形 + 边框 + 文字 + 贴图」这四样 —— 够覆盖本项目所有面板的样式。
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.path.join(ROOT, "_ui_dump.json")
FONT = os.path.join(ROOT, "resources", "font", "IPix.ttf")

_font_cache = {}


def font(size):
    size = max(int(round(size)), 6)
    if size not in _font_cache:
        try:
            _font_cache[size] = ImageFont.truetype(FONT, size)
        except Exception:                                    # noqa: BLE001
            _font_cache[size] = ImageFont.load_default()
    return _font_cache[size]


def tex_path(p):
    if p.startswith("res://"):
        p = p[len("res://"):]
    return os.path.join(ROOT, p.replace("/", os.sep))


def rgba(c, alpha=1.0):
    r, g, b, a = c
    return (int(r * 255), int(g * 255), int(b * 255), int(max(0.0, min(1.0, a * alpha)) * 255))


def draw_text(d, rect, txt, size, color, align, valign, outline=0, outline_color=None):
    if not txt:
        return
    x, y, w, h = rect
    f = font(size)
    if align == "center":
        ax = "m"
    elif align == "right":
        ax = "r"
    else:
        ax = "l"
    if valign == "center":
        ay = "m"
    elif valign == "bottom":
        ay = "d"
    else:
        ay = "a"
    anchor = ax + ay
    px = x + w / 2 if ax == "m" else (x + w - 2 if ax == "r" else x + 3)
    py = y + h / 2 if ay == "m" else (y + h - 2 if ay == "d" else y + 1)

    # 多行：Godot 的 Label 支持 \n，PIL 要自己拆
    lines = str(txt).split("\n")
    lh = size + 2
    total = lh * len(lines)
    start = py - (total - lh) / 2 if ay == "m" else py
    for i, line in enumerate(lines):
        ly = start + i * lh
        if outline and outline > 0 and outline_color:
            oc = rgba(outline_color)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx or dy:
                        d.text((px + dx, ly + dy), line, font=f, fill=oc, anchor=anchor)
        d.text((px, ly), line, font=f, fill=rgba(color), anchor=anchor)


def draw_scene(data, tag, bg, out):
    items = data["items"] if tag is None else [it for it in data["items"] if it["tag"] == tag]
    vw, vh = data["view"]
    canvas = Image.new("RGBA", (int(vw), int(vh)), bg)
    cache = {}

    def tex(p):
        if p not in cache:
            cache[p] = Image.open(tex_path(p)).convert("RGBA")
        return cache[p]

    for it in items:
        x, y, w, h = [int(round(v)) for v in it["rect"]]
        if w <= 0 or h <= 0:
            continue
        if it["kind"] == "box":
            fill = rgba(it["fill"])
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            d.rounded_rectangle([0, 0, w - 1, h - 1], radius=max(0, int(it["radius"])), fill=fill)
            bw = it["border_w"]
            if any(bw) and rgba(it["border"])[3] > 0:
                d.rounded_rectangle([0, 0, w - 1, h - 1], radius=max(0, int(it["radius"])),
                                    outline=rgba(it["border"]),
                                    width=max(int(max(bw)), 1))
            canvas.alpha_composite(layer, (x, y))
        elif it["kind"] == "texture":
            p = it.get("tex", "")
            if not p:
                continue
            try:
                t = tex(p)
            except Exception as e:                           # noqa: BLE001
                print("  跳过贴图 %s: %s" % (p, e))
                continue
            # AtlasTexture：ui_dump 给的是「图集路径 + region」，在这裁出那一帧
            rg = it.get("region")
            if rg:
                rx, ry, rw, rh = [int(v) for v in rg]
                t = t.crop((rx, ry, rx + rw, ry + rh))
            if it.get("keep_aspect"):
                k = min(w / t.width, h / t.height)
                tw, th = max(1, int(t.width * k)), max(1, int(t.height * k))
                t = t.resize((tw, th), Image.NEAREST)
            else:
                t = t.resize((w, h), Image.NEAREST)
            canvas.alpha_composite(t, (x + (w - t.width) // 2, y + (h - t.height) // 2))
        elif it["kind"] == "text":
            draw_text(ImageDraw.Draw(canvas), (x, y, w, h), it["text"], it["size"], it["color"],
                      it["align"], it["valign"], it.get("outline", 0), it.get("outline_color"))
        elif it["kind"] == "button":
            draw_text(ImageDraw.Draw(canvas), (x, y, w, h), it["text"], it["size"], it["color"],
                      "center", "center")

    d = os.path.dirname(os.path.abspath(out))
    if d:
        os.makedirs(d, exist_ok=True)
    canvas.convert("RGB").save(out)
    print("已写出", out, canvas.size, "（%s：%d 条指令）" % (tag or "全部", len(items)))
    # 顺手体检：IPix.ttf 缺字形时会画出 .notdef 小方块（5x11 空心方框）。
    # 这类问题肉眼在缩略图上看不出来，这里逐像素认一遍，报了就去换字符。
    bad = find_notdef_boxes(canvas)
    if bad:
        print("  [!!] 发现 %d 处「缺字形方块」（IPix.ttf 里没这个字），位置: %s"
              % (len(bad), bad[:8]))


def find_notdef_boxes(img, thr=200):
    """找出 IPix.ttf 的 .notdef 字形：5 宽 11 高的空心小方框。返回 [(x, y), ...]"""
    px = img.load()
    w, h = img.size

    def ink(x, y):
        c = px[x, y]
        return (c[0] + c[1] + c[2]) > thr

    hits = []
    for y in range(h - 11):
        for x in range(w - 5):
            if not (all(ink(x + i, y) for i in range(5))
                    and all(ink(x + i, y + 10) for i in range(5))
                    and all(ink(x, y + j) and ink(x + 4, y + j) for j in range(11))):
                continue
            if any(ink(x + i, y + j) for j in range(1, 10) for i in range(1, 4)):
                continue
            hits.append((x, y))
    return hits


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    out = sys.argv[1]
    only = None
    if "--show" in sys.argv:
        only = sys.argv[sys.argv.index("--show") + 1]
    bg = (24, 22, 20, 255)
    if "--bg" in sys.argv:
        bg = tuple(int(v) for v in sys.argv[sys.argv.index("--bg") + 1].split(",")) + (255,)

    with open(DUMP, encoding="utf-8") as f:
        data = json.load(f)

    tags = []
    for it in data["items"]:
        if it["tag"] not in tags:
            tags.append(it["tag"])

    if only is not None:
        draw_scene(data, only, bg, out)
        return
    if not tags:
        print("dump 里没有任何排版指令")
        return
    # 没指定 --show 就把每套界面各出一张：xxx_settlement.png / xxx_shop.png
    base, ext = os.path.splitext(out)
    for t in tags:
        draw_scene(data, t, bg, "%s_%s%s" % (base, t, ext))


if __name__ == "__main__":
    main()
