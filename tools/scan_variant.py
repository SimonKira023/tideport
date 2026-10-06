# -*- coding: utf-8 -*-
# A7：全项目扫 `:=` 类型推断隐患（AGENTS.md 红线坑 1）。
# 思路：GDScript 的 `:=` 是静态推断，推断不出具体类型时会退化成 Variant，
#       之后拿它当具体类型用（点属性 / 调方法）就可能在运行时炸。
# 模式：
#   R1 := x.get(...)      （Dictionary/Object.get 返回 Variant）
#   R2 := x["key"]        （字符串下标 -> 字典取值 Variant）
#   R3 := x.call(...)     （内建 call 返回 Variant）
#   R4 for v in [字面量数组] 后，块内 `var y := ...v...`（坑 1 原型：v 是 Variant）
import os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"C:\Users\蔡璟熙\Documents\新建游戏项目"
SKIP_PARTS = ("\\.godot", "_archive", "_demo", "_build", "__pycache__", "\\resources\\", "\\item\\")

files = []
for dp, dn, fn in os.walk(ROOT):
    if any(s in dp for s in SKIP_PARTS):
        dn[:] = []
        continue
    for f in fn:
        if f.endswith(".gd"):
            files.append(os.path.join(dp, f))

pat_get  = re.compile(r":=\s*[\w\.\[\]]+\.get\(")
pat_ksub = re.compile(r":=\s*[\w\.\[\]]+\[\s*[\"']")
pat_call = re.compile(r":=\s*[\w\.\[\]]+\.call\(")
pat_for  = re.compile(r"^(\s*)for\s+(\w+)\s+in\s+\[")
pat_decl = re.compile(r"var\s+\w+\s*:=\s*(.+)$")

hits = {"get": [], "ksub": [], "call": [], "forvar": []}
for p in files:
    try:
        txt = open(p, encoding="utf-8").read()
    except Exception as e:
        print("READ FAIL", p, e)
        continue
    rel = os.path.relpath(p, ROOT)
    lines = txt.split("\n")
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("#"):
            continue
        if pat_get.search(ln):
            hits["get"].append((rel, i + 1, s))
        if pat_ksub.search(ln):
            hits["ksub"].append((rel, i + 1, s))
        if pat_call.search(ln):
            hits["call"].append((rel, i + 1, s))
        m = pat_for.match(ln)
        if not m:
            continue
        indent = len(m.group(1)); var = m.group(2)
        for j in range(i + 1, min(i + 40, len(lines))):
            l2 = lines[j]
            if l2.strip() == "":
                continue
            ind2 = len(l2) - len(l2.lstrip())
            if ind2 <= indent:
                break
            vm = pat_decl.search(l2)
            if vm and re.search(r"\b%s\b" % re.escape(var), vm.group(1)):
                hits["forvar"].append((rel, j + 1, l2.strip()))

print("扫描 .gd 文件数:", len(files))
titles = (
    ("get", "R1 := x.get(...)      (Dictionary/Object.get -> Variant)"),
    ("ksub", 'R2 := x["key"]        (字符串下标 -> 字典取值 Variant)'),
    ("call", "R3 := x.call(...)     (内建 call -> Variant)"),
    ("forvar", "R4 for v in [..] 后用 := 接 v  (坑 1 原型)"),
)
for k, title in titles:
    print("\n=== %s  共 %d 处 ===" % (title, len(hits[k])))
    byfile = {}
    for rel, n, s in hits[k]:
        byfile.setdefault(rel, []).append((n, s))
    for rel in sorted(byfile, key=lambda r: -len(byfile[r])):
        arr = byfile[rel]
        print("  %s  (%d)" % (rel, len(arr)))
        for n, s in arr[:4]:
            print("     L%d: %s" % (n, s[:120]))
        if len(arr) > 4:
            print("     ... 另 %d 处" % (len(arr) - 4))
