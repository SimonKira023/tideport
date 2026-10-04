# tools/_probe_walk.py —— 量走路动画的「支撑脚」每帧在贴图里退了多少像素
#
# 原理：走路时支撑脚相对地面是不动的（脚踩住、身子往前挪）。
# 所以「支撑脚在贴图坐标系里的位移 / 每帧时间」就是身子该有的速度。
# 速度对了脚就踩得住地；太快是滑步、太慢是原地蹬腿。
import os
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK = os.path.join(ROOT, "resources",
                    "Farm RPG - Tiny Asset Pack - (All in One)",
                    "Character", "Character", "Pre-made")
CELL = 32

def feet_profile(path, row, frames):
    """每帧：返回脚部（最底下 2 行）的像素列分布 + 连通块（连通块 = 一只脚）"""
    img = Image.open(path).convert("RGBA")
    out = []
    for i in range(frames):
        f = img.crop((i * CELL, row * CELL, (i + 1) * CELL, (row + 1) * CELL))
        px = f.load()
        bottom = -1
        for y in range(CELL - 1, -1, -1):
            if any(px[x, y][3] > 40 for x in range(CELL)):
                bottom = y
                break
        cols = []
        for x in range(CELL):
            if any(px[x, y][3] > 40 for y in range(max(0, bottom - 1), bottom + 1)):
                cols.append(x)
        # 按 x 找出所有连续段（段与段之间隔着空白 = 两只脚）
        groups = []
        for x in cols:
            if groups and x == groups[-1][-1] + 1:
                groups[-1].append(x)
            else:
                groups.append([x])
        feet = [((g[0] + g[-1]) / 2.0, g[0], g[-1]) for g in groups]
        out.append({"bottom": bottom, "cols": cols, "feet": feet})
    return out

def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "Alex"
    fps = 10.0
    p = os.path.join(PACK, model, "Walk.png")
    print("==", model, "Walk.png   (6 帧 @ %g fps -> 一个循环 %.2f 秒)" % (fps, 6 / fps))
    for row, dn in ((2, "side"), (0, "down")):
        prof = feet_profile(p, row, 6)
        print("\n  -- 朝向 %s --" % dn)
        centers = []
        for i, pr in enumerate(prof):
            fs = "  ".join("[%d~%d 中%.1f]" % (a, b, c) for (c, a, b) in pr["feet"])
            print("    帧%d 底y=%d  脚=%s" % (i, pr["bottom"], fs if fs else "无"))
            for (c, a, b) in pr["feet"]:
                centers.append(c)
        if centers:
            print("    所有脚中心范围: %.1f ~ %.1f  (跨度 %.1f px)" % (
                min(centers), max(centers), max(centers) - min(centers)))
        # 一只脚从最前走到最后 = 一个「步」；一个循环两步
        span = (max(centers) - min(centers)) if centers else 0
        print("    => 一个循环位移 ≈ %.1f px, 配 %.1f fps 的话速度 ≈ %.1f px/s"
              % (span * 2, fps, span * 2 / (6 / fps)))

if __name__ == "__main__":
    main()
