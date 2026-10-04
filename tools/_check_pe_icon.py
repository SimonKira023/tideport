# -*- coding: utf-8 -*-
"""解析 PE 文件资源目录，检查是否包含图标资源 (RT_ICON=3, RT_GROUP_ICON=14)"""
import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else r"C:/Users/蔡璟熙/Documents/潮汐港/潮汐港.exe"

with open(path, "rb") as f:
    data = f.read()

# --- DOS header: e_lfanew at 0x3C ---
e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
assert data[e_lfanew:e_lfanew + 4] == b"PE\0\0", "不是有效的 PE 文件"

# --- COFF header (20 bytes after PE sig) ---
coff = e_lfanew + 4
machine, num_sections, _, _, _, opt_size, _ = struct.unpack_from("<HHIIIHH", data, coff)
opt = coff + 20

# --- Optional header: magic determines data-dir offset ---
magic = struct.unpack_from("<H", data, opt)[0]
if magic == 0x20B:      # PE32+ (x64)
    dd_off = opt + 112
else:                    # PE32
    dd_off = opt + 96
res_rva, res_size = struct.unpack_from("<II", data, dd_off + 2 * 8)  # 目录第 3 项 = 资源
print("资源目录 RVA=0x%X 大小=0x%X" % (res_rva, res_size))
if res_rva == 0:
    print("!! 该 exe 没有任何资源段（图标没打进去）")
    sys.exit(1)

# --- Section table: find section containing res_rva to map RVA -> file offset ---
sec_off = opt + opt_size
res_file_off = None
for i in range(num_sections):
    base = sec_off + i * 40
    name = data[base:base + 8].rstrip(b"\0").decode(errors="replace")
    vsize, vaddr, rsize, roff = struct.unpack_from("<IIII", data, base + 8)
    if vaddr <= res_rva < vaddr + max(vsize, rsize):
        res_file_off = roff + (res_rva - vaddr)
        print("资源段在节 [%s]，文件偏移 0x%X" % (name, res_file_off))
        break
assert res_file_off is not None, "资源 RVA 无法映射到文件偏移"

# --- Walk resource tree: root -> type level ---
def parse_dir(off):
    """返回 [(name_id, data_entry_rva)]"""
    chars, ts, maj, mins, n_named, n_id = struct.unpack_from("<IIHHHH", data, off)
    entries = []
    for i in range(n_named + n_id):
        e = off + 16 + i * 8
        name_or_id, offset_field = struct.unpack_from("<II", data, e)
        is_dir = offset_field & 0x80000000
        sub_off = res_file_off + (offset_field & 0x7FFFFFFF)
        entries.append((name_or_id, is_dir, sub_off))
    return entries

icon_types = {3: "RT_ICON", 14: "RT_GROUP_ICON"}
found = []
for type_id, is_dir, sub_off in parse_dir(res_file_off):
    if type_id in icon_types and is_dir:
        # count leaves under this type
        count = 0
        for _id, d2, lang_off in parse_dir(sub_off):
            for _id2, d3, l_off in parse_dir(lang_off if d2 else sub_off):
                pass
            # second level: id entries -> third level (language)
            for _id2, d3, l3 in parse_dir(lang_off):
                if not d3:
                    count += 1
                else:
                    count += len(parse_dir(l3))
        found.append((icon_types[type_id], count))

print("找到图标资源:")
ok = False
for t, n in found:
    print("  %s x %d" % (t, n))
    ok = True
if not ok:
    print("!! 没有 RT_ICON / RT_GROUP_ICON —— 图标没嵌入")
    sys.exit(1)
print("OK: exe 已包含图标资源 ✔")
