#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
重做光头贴图（v4.3）：真光头 —— 卵形头皮，赤道在眼睛中线。

历史教训：
  v2 把整块灰阶头发染成肤色，连嵌在头发里的**眼睛**（黑色眉毛 000000、
  灰色瞳孔 4e4e4e 也是灰阶）一起染掉了 —— 五官被抹掉，看着像「染色头」。
  v3 顺着原发型轮廓重涂 —— 锯齿边/老描边残留全留下；眉毛上方误涂阴影。
  v4.0~4.2 正椭圆/上下对称收窄 —— 赤道卡在太阳穴高度，最宽处above眼睛，
  看着像蘑菇/肿瘤，两侧一条全宽带。

v4.3 思路（每个 32x32 帧）：
  1. 认头发 = 纯灰阶像素里、跟脸部肤色/衣领相邻的连通块（挨木柄的灰块
     = 金属工具头，不误剃）；包围盒附近的孤立碎灰（鬓角尖）一并收编。
  2. 找**脸窗** = 头发包围盒里的非灰非透明像素；眼白 + 紧挨眼白的灰像素
     （眉毛/瞳孔/眼眶）全部原样保留。脸窗核心 < 4 像素 = 没脸（背面/躺倒）。
  3. **卵形头皮**：赤道压在眼睛中线（有脸帧）或包围盒中部（无脸帧）——
     上半球压扁(TOP_FLATTEN)+收窄(TOP_TAPER)，下半球朝下巴收窄(BOT_TAPER)，
     两侧再各剃 SIDE_SHAVE。椭圆内头发重画成头皮（贴边=描边、其余=肤色），
     椭圆外头发/孤儿老描边清成透明。头顶最宽处=眼睛高度，两侧是连续弧线。
  4. 眼睛保命：收窄后每个 keep 像素必须在头皮里、外留 1px（撑大 rx 兜底）。

用法：
    python tools/_make_bald.py            # 生成全部 6 张
    python tools/_make_bald.py --check    # 只打印统计，不写文件
"""

import os
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "resources", "Farm RPG - Tiny Asset Pack - (All in One)",
                       "Character", "Character", "Pre-made", "Josh")
OUT_DIR = os.path.join(ROOT, "resources", "texture", "bald")

# 每张表都按 32x32 一帧切
FRAME = 32

# 调色（都取自素材里已有的皮肤色，风格不违和）
SKIN = (255, 198, 139, 255)      # ffc68b 主肤色
OUTLINE = (28, 10, 24, 255)      # 1c0a18 身体轮廓的深色勾线
CLEAR = (0, 0, 0, 0)             # 剃掉的头发 = 全透明

GRAY_TOL = 6          # r/g/b 相差 <= 6 算纯灰
GRAY_MAX_V = 160      # 亮度上限（排除眼白 ffffff）
CORE_MIN = 4          # 脸窗核心至少几个像素才算「有脸」（背面/躺倒没有）
TOP_TAPER = 0.30      # 上半球宽度往里收的比例（越大头越尖）
TOP_FLATTEN = 1.45    # 上半球高度压缩比（>1 = 圆顶压扁，防"头上鼓肿瘤"）
BOT_TAPER = 0.35      # 下半球宽度往里收的比例（朝下巴变窄，头成卵形）
SIDE_SHAVE = 1.2      # 两侧各剃几像素（头发往外撑宽，光头要窄一圈）

# 不做脸窗判断的表（背面/躺倒的帧脸窗方向不对，赤道取包围盒中部）
NO_DOME = {"Sleep.png"}


def is_gray(p):
    r, g, b, a = p
    if a < 40:
        return False
    return max(r, g, b) - min(r, g, b) <= GRAY_TOL and max(r, g, b) < GRAY_MAX_V


def is_skin(p):
    r, g, b, a = p
    return a > 40 and r > 200 and 150 < g < 220 and 100 < b < 180 and r > g > b


def is_cloth(p):
    """蓝色系衣物（背面帧的后脑勺头发不挨皮肤、只挨衣领，靠这个认出来）。"""
    r, g, b, a = p
    return a > 40 and b > r and b > 60


def is_wood(p):
    """工具的木头柄（棕、r>g>b、不算亮）—— 挨着它的灰色块是金属工具头，别误剃。"""
    r, g, b, a = p
    return a > 40 and r > g > b and 80 < r < 220 and b < 110


def is_outline_col(p):
    r, g, b, a = p
    return a > 40 and (r, g, b) == OUTLINE[:3]


def neighbors4(x, y):
    return ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))


def neighbors8(x, y):
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx or dy:
                yield (x + dx, y + dy)


def alpha_at(px, ox, oy, x, y):
    """帧内 (x,y) 的 alpha，帧外当全透明。"""
    if 0 <= x < FRAME and 0 <= y < FRAME:
        return px[ox + x, oy + y][3]
    return 0


def find_hair(px, ox, oy):
    """认出本帧的头发像素集合（v2 同款检测）。没有则返回空集。"""
    gray = set()
    for y in range(FRAME):
        for x in range(FRAME):
            if is_gray(px[ox + x, oy + y]):
                gray.add((x, y))
    if not gray:
        return set()

    seen, blocks = set(), []
    for s in gray:
        if s in seen:
            continue
        stack, comp = [s], set()
        while stack:
            c = stack.pop()
            if c in comp:
                continue
            comp.add(c)
            x, y = c
            for n in neighbors4(x, y):
                if n in gray and n not in comp:
                    stack.append(n)
        seen |= comp
        blocks.append(comp)

    def touches(comp, pred):
        for (x, y) in comp:
            for nb in neighbors4(x, y):
                if 0 <= nb[0] < FRAME and 0 <= nb[1] < FRAME \
                        and pred(px[ox + nb[0], oy + nb[1]]):
                    return True
        return False

    hair = set()
    for comp in blocks:
        top = min(y for (_, y) in comp)          # 头发都长在帧的上半部
        if top > 12:
            continue
        if touches(comp, is_wood):
            continue                             # 挨着木柄的灰块 = 金属工具头
        # 背面后脑勺是一大块灰、隔着轮廓线谁都不挨 —— 用「够大」认出它；
        # 正面/侧面的头发挨着脸或衣领 —— 用相邻认出。
        if len(comp) >= 25 or touches(comp, is_skin) or touches(comp, is_cloth):
            hair |= comp
    return hair


def egg_inside(x, y, cx, cy, rx, ry_up, ry_dn):
    """卵形头皮判定（v4.3）：赤道（cy）= 最宽处。
    上半球（y < cy）：高度压 TOP_FLATTEN、宽度按 t^2 收 TOP_TAPER；
    下半球（y > cy）：宽度按 t^2 收 BOT_TAPER（朝下巴变窄）。"""
    dx = (x - cx) / rx
    if y < cy:
        dy = (cy - y) / ry_up * TOP_FLATTEN
        dx /= (1.0 - TOP_TAPER * dy * dy)
    else:
        dy = (y - cy) / ry_dn
        dx /= (1.0 - BOT_TAPER * dy * dy)
    return dx * dx + dy * dy <= 1.0


def repaint_scalp(px, ox, oy, scalp, keep, ell):
    """把 scalp（头皮像素集）画成肤色：贴透明边/贴椭圆外 -> 描边，其余 -> 主肤色。
    keep 里的像素（五官）一个不碰。返回改掉的像素数。
    （v4 起去掉了发际线阴影 —— 这套素材脸窗很高，阴影涂上去像头顶沾了泥）"""
    cx, cy, rx, ry_up, ry_dn = ell
    n = 0
    for (x, y) in scalp:
        edge = False
        for nb in neighbors4(x, y):
            if alpha_at(px, ox, oy, nb[0], nb[1]) < 40 and nb not in scalp:
                edge = True                      # 贴透明 = 轮廓
            elif not egg_inside(nb[0], nb[1], cx, cy, rx, ry_up, ry_dn):
                edge = True                      # 贴椭圆外 = 轮廓（平滑弧线）
        if edge:
            px[ox + x, oy + y] = OUTLINE          # 外轮廓勾线
        else:
            px[ox + x, oy + y] = SKIN             # 头皮
        n += 1
    return n


def cleanup_orphan_outline(px, ox, oy, x0, y0, x1, y1, ell, keep):
    """清掉椭圆外的「孤儿描边」——原头发轮廓线，头发剃掉后悬空的那种。
    判据：描边色、在椭圆外、8 邻居里没有任何活着的东西。
    活着 = 椭圆外的不透明非描边像素（脸皮肤/衣物/木柄/keep）。
    ❗椭圆内的新头皮/新描边不算活着 —— 否则贴着新头皮的老描边斜向沾活，
    清不掉，形成双描边。脸的下巴描边贴着椭圆外的脸皮肤，不会被误删。"""
    cx, cy, rx, ry_up, ry_dn = ell
    n = 0
    for y in range(max(0, y0), min(FRAME, y1 + 2)):
        for x in range(max(0, x0), min(FRAME, x1 + 2)):
            if not is_outline_col(px[ox + x, oy + y]) \
                    or egg_inside(x, y, cx, cy, rx, ry_up, ry_dn):
                continue
            alive = False
            for nb in neighbors8(x, y):
                nx, ny = nb
                if not (0 <= nx < FRAME and 0 <= ny < FRAME):
                    continue
                p = px[ox + nx, oy + ny]
                if p[3] < 40 or is_outline_col(p):
                    continue
                if egg_inside(nx, ny, cx, cy, rx, ry_up, ry_dn):
                    continue                      # 椭圆内的新头皮不算活
                if is_gray(p) or is_skin(p) or is_cloth(p) or is_wood(p) \
                        or (nx, ny) in keep:
                    alive = True
                    break
            if not alive:
                px[ox + x, oy + y] = CLEAR
                n += 1
    return n


def process_frame(img, fx, fy, sheet):
    """处理一帧，返回改了多少像素。img 是整张 RGBA Image。"""
    ox, oy = fx * FRAME, fy * FRAME
    px = img.load()

    hair = find_hair(px, ox, oy)
    if not hair:
        return 0

    # 2) 脸窗：头发包围盒里的非灰非透明像素（皮肤/眼白/瞳孔底），
    #    紧挨眼白的灰像素（眉毛/瞳孔/眼眶）也算特征，全部保留
    x0 = min(x for (x, _) in hair)
    x1 = max(x for (x, _) in hair)
    y0 = min(y for (_, y) in hair)
    y1 = max(y for (_, y) in hair)
    feats = set()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x, y) not in hair and alpha_at(px, ox, oy, x, y) >= 40 \
                    and not is_gray(px[ox + x, oy + y]):
                feats.add((x, y))
    # keep = 眼睛相关的像素：眼白自己 + 紧挨眼白的灰像素（眉毛/瞳孔）。
    # ❗只认「眼白」不认「皮肤」：挨着额头的灰像素是发际线，要重画成头皮。
    keep = set()
    for (x, y) in feats:
        p = px[ox + x, oy + y]
        if is_outline_col(p) or is_skin(p):
            continue                              # 轮廓/皮肤不带keep
        keep.add((x, y))                          # 眼白/眼瞳底
        for n in neighbors8(x, y):
            if n in hair:
                keep.add(n)

    # 脸窗核心（去掉轮廓色 1c0a18，免得把下巴描边算进脸的宽度）
    core = {(x, y) for (x, y) in feats if not is_outline_col(px[ox + x, oy + y])}
    has_face = len(core) >= CORE_MIN and sheet not in NO_DOME

    # 散灰收编：包围盒附近不在主头发块里的小灰块（鬓角尖/碎发），也不挨
    # 木柄 —— 收进头发一起处理，免得脸颊上剩孤立灰点。keep 里的五官除外。
    for y in range(max(0, y0 - 1), min(FRAME, y1 + 2)):
        for x in range(max(0, x0 - 1), min(FRAME, x1 + 2)):
            if (x, y) in hair or (x, y) in keep:
                continue
            if not is_gray(px[ox + x, oy + y]):
                continue
            if any(0 <= nb[0] < FRAME and 0 <= nb[1] < FRAME
                   and is_wood(px[ox + nb[0], oy + nb[1]])
                   for nb in neighbors8(x, y)):
                continue                          # 挨木柄的灰 = 工具头
            hair.add((x, y))

    # 3) 卵形头皮：赤道压在眼睛中线（有脸）或包围盒中部（无脸），
    #    两侧再各剃 SIDE_SHAVE（光头比发型窄）
    if has_face and keep:
        cy = (min(y for (_, y) in keep) + max(y for (_, y) in keep)) / 2.0
    else:
        cy = (y0 + y1) / 2.0
    cx = (x0 + x1) / 2.0
    ry_up = max(2.0, cy - y0 + 0.5)
    ry_dn = max(2.0, y1 - cy + 0.5)
    rx = max(3.0, (x1 - x0) / 2.0 + 0.5 - SIDE_SHAVE)
    ell = (cx, cy, rx, ry_up, ry_dn)
    # ❗眼睛保命：收窄/收扁后每个 keep 像素（眼白/眉/瞳）必须还在头皮里、
    # 外面留 1px 头皮，不满足就撑大 rx —— 否则眼角悬空没描边，看着像破了
    for (kx, ky) in keep:
        if ky < cy:
            dy2 = (cy - ky) / ry_up * TOP_FLATTEN
            m = 1.0 - TOP_TAPER * dy2 * dy2
        else:
            dy2 = (ky - cy) / ry_dn
            m = 1.0 - BOT_TAPER * dy2 * dy2
        denom = m * max(0.0, 1.0 - dy2 * dy2) ** 0.5
        if denom > 1e-6:
            rx = max(rx, (abs(kx - cx) + 1.0) / denom)
    ell = (cx, cy, rx, ry_up, ry_dn)

    # 补皮上限：有脸的帧补到发际线为止（别往脸上糊皮）；
    # 没脸的帧整个上半球都补（圆顶饱满、凹坑填平）
    fill_limit = (min(y for (_, y) in core) if has_face else int(cy) + 1)

    removed = set()
    scalp = set()
    for y in range(y0 - 1, y1 + 2):
        for x in range(x0 - 1, x1 + 2):
            is_h = (x, y) in hair and (x, y) not in keep
            if egg_inside(x, y, cx, cy, rx, ry_up, ry_dn):
                if is_h:
                    scalp.add((x, y))             # 椭圆内的头发 -> 重画头皮
                elif alpha_at(px, ox, oy, x, y) < 40 and y <= fill_limit:
                    scalp.add((x, y))             # 椭圆内的透明 -> 补皮
            elif is_h:
                removed.add((x, y))               # 椭圆外的头发 -> 剃掉
    for (x, y) in removed:
        px[ox + x, oy + y] = CLEAR

    n = repaint_scalp(px, ox, oy, scalp, keep, ell)
    n += cleanup_orphan_outline(px, ox, oy, x0, y0, x1, y1, ell, keep)
    return len(removed) + n


def main():
    write = "--check" not in sys.argv
    names = ["Idle.png", "Run.png", "Hoe.png", "Axe.png", "Watering.png", "Sleep.png"]
    out_names = {"Idle": "idle", "Run": "run", "Hoe": "hoe",
                 "Axe": "axe", "Watering": "watering", "Sleep": "sleep"}
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in names:
        path = os.path.join(SRC_DIR, name)
        if not os.path.isfile(path):
            print("[X] 找不到 %s" % path)
            continue
        img = Image.open(path).convert("RGBA")
        total = 0
        cols, rows = img.width // FRAME, img.height // FRAME
        for fy in range(rows):
            for fx in range(cols):
                total += process_frame(img, fx, fy, name)
        out_path = os.path.join(OUT_DIR, out_names[name.replace(".png", "")] + ".png")
        if write:
            img.save(out_path)
        print("%-14s %d 帧  改了 %5d 像素  -> %s"
              % (name, cols * rows, total, os.path.basename(out_path)))
    print("[OK]" if write else "[check only]")


if __name__ == "__main__":
    main()
