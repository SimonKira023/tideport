# -*- coding: utf-8 -*-
"""从 resources/character 导入头像到 resources/texture/portraits/"""
from __future__ import annotations

import os
import shutil
from datetime import datetime
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("需要 Pillow: pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
CHR = ROOT / "resources" / "character"
OUT = ROOT / "resources" / "texture" / "portraits"
STAGE = ROOT / "tools" / "_portrait_stage"
BAK = ROOT / "outputs" / "_portrait_bak"
OUT_SIZE = 128
BG = (0xF4, 0xEF, 0xE4, 255)

RULES: list[tuple[str, str]] = [
    ("player", "player"),
    ("哥布林", "goblin"),
    ("咪露", "slave_00"),
    ("布恩", "slave_01"),
    ("珞琳", "slave_02"),
    ("娜雅", "slave_03"),
    ("塔洛", "slave_04"),
    ("汐月", "slave_05"),
    ("珂丹", "slave_06"),
    ("雪莱", "slave_07"),
    ("奥朗", "lord_chenxi_cap"),
    ("温楼", "lord_chenxi_port"),
    ("柳原", "lord_chenxi_bridge"),
    ("希尔达", "lord_beiling_cap"),
    ("洛恩", "lord_beiling_valley"),
    ("卡佳", "lord_beiling_pine"),
    ("苏禾", "lord_xichuan_cap"),
    ("麦冬", "lord_xichuan_gold"),
    ("苇青", "lord_xichuan_reed"),
    ("赫连烈", "lord_tieyan_cap"),
    ("巴图", "lord_tieyan_stone"),
    ("苏赫", "lord_tieyan_cliff"),
    ("孛罗", "lord_canglang_cap"),
    ("哈剌", "lord_canglang_pasture"),
    ("脱欢", "lord_canglang_camp"),
    ("秦戈", "captain_chenxi"),
    ("白山", "captain_beiling"),
    ("田石", "captain_xichuan"),
    ("那颜", "captain_tieyan"),
    ("哈丹", "captain_canglang"),
]


def match_key(name: str) -> str:
    if "9273" in name:
        return ""
    for token, out in RULES:
        if token in name:
            return out
    return ""


def to_portrait(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    side = min(w, h)
    y0 = int(round((h - side) * 0.42))
    y0 = max(0, min(y0, h - side))
    x0 = (w - side) // 2
    cut = im.crop((x0, y0, x0 + side, y0 + side))
    if side != OUT_SIZE:
        cut = cut.resize((OUT_SIZE, OUT_SIZE), Image.NEAREST)
    out = Image.new("RGBA", (OUT_SIZE, OUT_SIZE), BG)
    out.paste(cut, (0, 0), cut)
    return out.convert("RGB")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak_sub = BAK / stamp
    assigned: dict[str, str] = {}
    skipped: list[str] = []

    for fn in sorted(os.listdir(CHR)):
        if not fn.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        key = match_key(fn)
        if not key:
            skipped.append(fn)
            continue
        if key in assigned:
            print(f"重复: {key} <- {assigned[key]} 和 {fn}")
            return 1
        assigned[key] = fn

    bak_sub.mkdir(parents=True, exist_ok=True)
    for key in assigned:
        dst = OUT / f"{key}.png"
        if dst.is_file():
            shutil.copy2(dst, bak_sub / dst.name)

    ok = 0
    for key, fn in assigned.items():
        src = CHR / fn
        im = Image.open(src)
        out = to_portrait(im)
        buf = BytesIO()
        out.save(buf, format="PNG")
        staged = STAGE / f"{key}.png"
        staged.write_bytes(buf.getvalue())
        final = OUT / f"{key}.png"
        if final.is_file():
            final.unlink()
        shutil.copy2(staged, final)
        print(f"[头像导入] {key} <- {fn}")
        ok += 1

    miss = [out for _, out in RULES if out not in assigned]
    print(f"[头像导入] 成功 {ok} 张, 跳过 {len(skipped)}, 缺 {len(miss)}: {miss}")
    return 0 if ok >= 25 else 1


if __name__ == "__main__":
    raise SystemExit(main())
