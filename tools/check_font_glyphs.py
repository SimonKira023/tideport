# tools/check_font_glyphs.py —— 找出「会在界面上显示、但 IPix.ttf 里没有字形」的字符。
#
# 为什么需要：IPix.ttf 是个很小的像素字体，**中日韩全角标点一个都没有**
# （、。！？：（）「」【】·—─… 全缺）。缺字形时 Godot 会退回默认字体，
# 显示出来就是另一种字体或者豆腐块 —— 在又小又糊的像素界面里很难看。
# 所以：凡是会被画到界面上的字符串，一律只用 ASCII 标点。
#
# 只看**字符串字面量**（会显示的东西），注释里的符号不算。
# 注意 print/push_warning 是往控制台打的，用的是控制台的字体，不算「界面文字」。
# 跑法：python tools/check_font_glyphs.py [--all]
#   --all  连 tools/ 下的开发脚本和 print 一起查（平时不用）
import glob
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "resources", "font", "IPix.ttf")

STR_RE = re.compile(r'"([^"\n]*)"|\'([^\'\n]*)\'')
SKIP_PREFIX = ("print(", "print_", "push_warning(", "push_error(", "assert(", "printerr(")


def main():
    show_all = "--all" in sys.argv
    if not os.path.exists(FONT):
        print("找不到字体", FONT)
        return 1
    probe = ImageFont.truetype(FONT, 16)
    notdef = _sig(probe, chr(0xE123))            # 私用区：字体里肯定没有 → .notdef 方框

    bad = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.gd"), recursive=True)):
        if ".godot" in path:
            continue
        rel = os.path.relpath(path, ROOT)
        if not show_all and rel.replace("\\", "/").startswith("tools/"):
            continue
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        for n, line in enumerate(lines, 1):
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            if not show_all and stripped.startswith(SKIP_PREFIX):
                continue
            for m in STR_RE.finditer(line):
                text = m.group(1) if m.group(1) is not None else m.group(2)
                for ch in set(text):
                    if ord(ch) < 128 or ch.isspace():
                        continue
                    if _sig(probe, ch) == notdef:
                        bad.setdefault(ch, []).append("%s:%d" % (rel, n))

    if not bad:
        print("✔ 界面上要显示的文字里，没有 IPix.ttf 缺字形的字符")
        return 0

    print("✘ 下面这些字符会显示在界面上，但 IPix.ttf 里没有字形（建议换成 ASCII 标点）：\n")
    for ch, where in sorted(bad.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        print("  %r  U+%04X  出现 %d 处" % (ch, ord(ch), len(where)))
        for w in where[:6]:
            print("      " + w)
        if len(where) > 6:
            print("      ... 还有 %d 处" % (len(where) - 6))
    print("\n合计 %d 种字符。全角标点建议统一换成：· -> -   （） -> ()   ！ -> !   ： -> :" % len(bad))
    return 1


def _sig(font, ch):
    im = Image.new("L", (40, 40), 0)
    ImageDraw.Draw(im).text((4, 4), ch, font=font, fill=255)
    return im.tobytes()


if __name__ == "__main__":
    sys.exit(main())
