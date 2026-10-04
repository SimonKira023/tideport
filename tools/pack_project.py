#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
把《潮汐港》项目打包成一个 zip，方便拷贝到另一台电脑继续开发。

用法（在项目目录里）：
    python tools/pack_project.py

产物：桌面上的  潮汐港_项目_YYYYMMDD.zip  （约 80~120MB）

会排除：.git / .godot 缓存 / Godot 编辑器副本(200MB) /
        tools/export 里的 1.2GB 导出模板包 / outputs 预览图 / 临时文件
这些换电脑后都能自动重建或重新下载，不需要搬。
"""

import os
import sys
import time
import zipfile
from datetime import datetime

# ---------- 路径 ----------
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)

DESKTOP = os.path.join(os.environ.get("USERPROFILE", "."), "Desktop")
if not os.path.isdir(DESKTOP):
    DESKTOP = os.path.join(os.path.expanduser("~"), "OneDrive", "Desktop")
if not os.path.isdir(DESKTOP):
    DESKTOP = os.path.expanduser("~")

OUT_NAME = "潮汐港_项目_%s.zip" % datetime.now().strftime("%Y%m%d")
OUT_PATH = os.path.join(DESKTOP, OUT_NAME)

# ---------- 排除规则（目录名或文件名前缀匹配） ----------
SKIP_DIRS = {
    ".git", ".godot", "Godot", "output", "outputs",
    "_preview_tex", "_ui_tex", "__pycache__", ".workbuddy",
    "export",           # tools/export（1.2GB 模板包）
}
SKIP_FILES = {
    "_preview_dump.json", "_ui_dump.json", ".DS_Store",
}
SKIP_EXT = {".exe", ".pck", ".zip", ".tmp", ".pyc", ".log"}


def should_skip_dir(name, full):
    # 只排除 tools/ 下的 export，其它目录里的 export 正常保留
    if name in SKIP_DIRS:
        return True
    return False


def main():
    if not os.path.isfile(os.path.join(PROJECT, "project.godot")):
        print("[X] 没找到 project.godot，脚本要放在项目 tools/ 目录下")
        return 1

    total = 0
    kept = []
    for root, dirs, files in os.walk(PROJECT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f in SKIP_FILES:
                continue
            if os.path.splitext(f)[1].lower() in SKIP_EXT:
                continue
            p = os.path.join(root, f)
            try:
                sz = os.path.getsize(p)
            except OSError:
                continue
            total += sz
            kept.append((p, sz))

    kept.sort()
    print("项目目录: %s" % PROJECT)
    print("待打包文件: %d 个，共 %.1f MB（未压缩）" % (len(kept), total / 1024 / 1024))
    print("输出: %s" % OUT_PATH)
    print("打包中...")

    t0 = time.time()
    n = 0
    with zipfile.ZipFile(OUT_PATH, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for p, sz in kept:
            arc = os.path.relpath(p, os.path.dirname(PROJECT))
            arc = arc.replace("\\", "/")
            z.write(p, arc)
            n += 1
            if n % 500 == 0:
                print("  %d / %d" % (n, len(kept)))

    size = os.path.getsize(OUT_PATH) / 1024 / 1024
    print("")
    print("[OK] 完成：%d 个文件，%.1f MB，用时 %.0f 秒" % (n, size, time.time() - t0))
    print("     文件在桌面：%s" % OUT_NAME)
    print("")
    print("换电脑后：解压 → 装 Godot 4.7.2 → 导入 project.godot")
    print("详细步骤见项目里的 MIGRATE.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
