# tools/render_preview.py —— 把 Godot 导出的绘制指令合成一张 PNG，用来「看」headless 跑不出来的画面。
#
# 用法（在项目根目录，先跑一次 tools/scene_dump.tscn 生成 _preview_dump.json）：
#   python tools/render_preview.py outputs/俯视图.png
#   python tools/render_preview.py outputs/室内.png --crop 232 890 312 195 --scale 2
#   python tools/render_preview.py outputs/全图.png --scale 0.78
#
# --crop x y w h 用的是**世界坐标**（跟 Godot 里节点坐标同一套），不是输出图上的像素。
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.path.join(ROOT, "_preview_dump.json")


def tex_path(p):
    if p.startswith("res://"):
        p = p[len("res://"):]
    return os.path.join(ROOT, p.replace("/", os.sep))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    out = sys.argv[1]
    crop = None
    scale = 1.0
    if "--crop" in sys.argv:
        i = sys.argv.index("--crop")
        crop = [int(v) for v in sys.argv[i + 1:i + 5]]
    if "--scale" in sys.argv:
        scale = float(sys.argv[sys.argv.index("--scale") + 1])

    with open(DUMP, encoding="utf-8") as f:
        items = json.load(f)["items"]

    cache = {}

    def tex(p):
        if p not in cache:
            cache[p] = Image.open(tex_path(p)).convert("RGBA")
        return cache[p]

    # 1) 先算所有绘制指令的包围盒
    minx = miny = 1 << 30
    maxx = maxy = -(1 << 30)
    for it in items:
        _, _, sw, sh = it["src_rect"]
        w = max(1, int(round(sw * it["scale"][0])))
        h = max(1, int(round(sh * it["scale"][1])))
        x, y = int(round(it["pos"][0])), int(round(it["pos"][1]))
        minx = min(minx, x); miny = min(miny, y)
        maxx = max(maxx, x + w); maxy = max(maxy, y + h)

    cw, ch = maxx - minx, maxy - miny
    print("画布范围 %d x %d（原点 %d,%d），共 %d 条指令" % (cw, ch, minx, miny, len(items)))

    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 255))

    # 2) 按节点顺序贴上去（后面的盖前面的，跟 Godot 的绘制顺序一致）
    for it in items:
        sx, sy, sw, sh = [int(round(v)) for v in it["src_rect"]]
        if sw <= 0 or sh <= 0:
            continue
        try:
            t = tex(it["tex"]).crop((sx, sy, sx + sw, sy + sh))
        except Exception as e:                                  # noqa: BLE001
            print("  跳过 %s: %s" % (it["tex"], e))
            continue
        sc = it["scale"]
        if abs(sc[0] - 1) > 1e-3 or abs(sc[1] - 1) > 1e-3:
            t = t.resize((max(1, int(round(sw * sc[0]))), max(1, int(round(sh * sc[1])))),
                         Image.NEAREST)
        if it.get("flip_h"):
            t = t.transpose(Image.FLIP_LEFT_RIGHT)
        m = it.get("modulate", [1, 1, 1, 1])
        if abs(m[0] - 1) > 1e-3 or abs(m[1] - 1) > 1e-3 or abs(m[2] - 1) > 1e-3 or abs(m[3] - 1) > 1e-3:
            r, g, b, a = t.split()
            r = r.point(lambda v: int(v * m[0]))
            g = g.point(lambda v: int(v * m[1]))
            b = b.point(lambda v: int(v * m[2]))
            a = a.point(lambda v: int(v * m[3]))
            t = Image.merge("RGBA", (r, g, b, a))
        x, y = int(round(it["pos"][0])) - minx, int(round(it["pos"][1])) - miny
        canvas.alpha_composite(t, (x, y))

    if crop:
        x, y, w, h = crop
        canvas = canvas.crop((x - minx, y - miny, x - minx + w, y - miny + h))

    if abs(scale - 1.0) > 1e-3:
        canvas = canvas.resize((int(canvas.width * scale), int(canvas.height * scale)),
                               Image.LANCZOS)

    d = os.path.dirname(os.path.abspath(out))
    if d:
        os.makedirs(d, exist_ok=True)
    canvas.convert("RGB").save(out)
    print("已写出", out, canvas.size)


if __name__ == "__main__":
    main()
