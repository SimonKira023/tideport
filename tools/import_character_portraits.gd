# tools/import_character_portraits.gd
# 把 resources/character/ 里即梦导出的 PNG(文件名含角色名) 裁成 128x128,
# 写入 resources/texture/portraits/ 对应槽位。
#
#   Godot_console.exe --headless --path . --script res://tools/import_character_portraits.gd
extends SceneTree

const CHR_DIR := "res://resources/character"
const OUT_DIR := "res://resources/texture/portraits"
const BAK_DIR := "res://outputs/_portrait_bak"
const STAGE_DIR := "res://tools/_portrait_stage"
const OUT_SIZE := 128
const BG := Color("f4efe4")

# 按「文件名里出现的名字」匹配; 顺序: 更长的/更专的先写, 避免误配
const RULES: Array = [
	["player", "player"],
	["哥布林", "goblin"],
	["咪露", "slave_00"],
	["布恩", "slave_01"],
	["珞琳", "slave_02"],
	["娜雅", "slave_03"],
	["塔洛", "slave_04"],
	["汐月", "slave_05"],
	["珂丹", "slave_06"],
	["雪莱", "slave_07"],
	["奥朗", "lord_chenxi_cap"],
	["温楼", "lord_chenxi_port"],
	["柳原", "lord_chenxi_bridge"],
	["希尔达", "lord_beiling_cap"],
	["洛恩", "lord_beiling_valley"],
	["卡佳", "lord_beiling_pine"],
	["苏禾", "lord_xichuan_cap"],
	["麦冬", "lord_xichuan_gold"],
	["苇青", "lord_xichuan_reed"],
	["赫连烈", "lord_tieyan_cap"],
	["巴图", "lord_tieyan_stone"],
	["苏赫", "lord_tieyan_cliff"],
	["孛罗", "lord_canglang_cap"],
	["哈剌", "lord_canglang_pasture"],
	["脱欢", "lord_canglang_camp"],
	["秦戈", "captain_chenxi"],
	["白山", "captain_beiling"],
	["田石", "captain_xichuan"],
	["那颜", "captain_tieyan"],
	["哈丹", "captain_canglang"],
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var abs_chr := ProjectSettings.globalize_path(CHR_DIR)
	var abs_out := ProjectSettings.globalize_path(OUT_DIR)
	var abs_bak := ProjectSettings.globalize_path(BAK_DIR)
	if not DirAccess.dir_exists_absolute(abs_out):
		DirAccess.make_dir_recursive_absolute(abs_out)
	if not DirAccess.dir_exists_absolute(abs_bak):
		DirAccess.make_dir_recursive_absolute(abs_bak)

	var dir := DirAccess.open(CHR_DIR)
	if dir == null:
		push_error("打不开 character 目录")
		quit(1)
		return

	var assigned: Dictionary = {}   # out_key -> source filename
	var skipped: Array = []
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not fn.ends_with(".png") and not fn.ends_with(".jpg") and not fn.ends_with(".jpeg"):
			fn = dir.get_next()
			continue
		# 9273 是误生成的另一版主角, 不要覆盖 player
		if fn.contains("9273"):
			skipped.append(fn)
			fn = dir.get_next()
			continue
		var out_key := _match_key(fn)
		if out_key == "":
			skipped.append(fn)
			fn = dir.get_next()
			continue
		if assigned.has(out_key):
			push_error("重复映射 %s: 已有 %s, 又来 %s" % [out_key, assigned[out_key], fn])
			quit(1)
			return
		assigned[out_key] = fn
		fn = dir.get_next()
	dir.list_dir_end()

	_backup_existing(abs_out, abs_bak, assigned.keys())

	var ok := 0
	for out_key in assigned.keys():
		var src := CHR_DIR.path_join(String(assigned[out_key]))
		var dst := OUT_DIR.path_join("%s.png" % out_key)
		var staged := STAGE_DIR.path_join("%s.png" % out_key)
		var img := _load_any(src)
		if img == null:
			push_error("读图失败: " + src)
			continue
		var out := _to_portrait(img)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STAGE_DIR))
		var err := out.save_png(staged)
		if err != OK:
			push_error("写暂存失败 %s err=%d" % [staged, err])
			continue
		if FileAccess.file_exists(dst):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
		err = DirAccess.copy_absolute(
			ProjectSettings.globalize_path(staged),
			ProjectSettings.globalize_path(dst))
		if err != OK:
			push_error("复制到 portraits 失败 %s err=%d" % [dst, err])
		else:
			ok += 1
			print("[头像导入] %s <- %s" % [out_key, assigned[out_key]])

	var expect := RULES.size()
	var miss: Array = []
	for r in RULES:
		if not assigned.has(String(r[1])):
			miss.append(String(r[1]))
	print("[头像导入] 成功 %d 张, 跳过源文件 %d, 缺 %d: %s"
		% [ok, skipped.size(), miss.size(), str(miss)])
	if not miss.is_empty():
		print("[头像导入] 缺的槽位仍用 portraits/ 里旧图")
	quit(0 if ok >= 25 else 1)

func _match_key(filename: String) -> String:
	for r in RULES:
		if filename.contains(String(r[0])):
			return String(r[1])
	return ""

func _load_any(path: String) -> Image:
	var img := Image.new()
	var err := img.load(path)
	if err == OK:
		img.convert(Image.FORMAT_RGBA8)
		return img
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	if path.to_lower().ends_with(".png"):
		err = img.load_png_from_buffer(fa.get_buffer(fa.get_length()))
	else:
		err = img.load_jpg_from_buffer(fa.get_buffer(fa.get_length()))
	if err != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

# 居中裁方 + 缩到 128, 像素图用最近邻
func _to_portrait(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var side := mini(w, h)
	# 略往上偏, 胸像别裁掉头顶
	var y0 := int(round((h - side) * 0.42))
	y0 = clampi(y0, 0, h - side)
	var x0 := (w - side) / 2
	var cut := src.get_region(Rect2i(x0, y0, side, side))
	if side != OUT_SIZE:
		cut.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_NEAREST)
	# 铺米白底, 半透明像素合成
	var out := Image.create(OUT_SIZE, OUT_SIZE, false, Image.FORMAT_RGBA8)
	out.fill(BG)
	for y in OUT_SIZE:
		for x in OUT_SIZE:
			var c: Color = cut.get_pixel(x, y)
			if c.a < 0.02:
				continue
			if c.a > 0.98:
				out.set_pixel(x, y, c)
			else:
				out.set_pixel(x, y, BG.lerp(c, c.a))
	return out

func _backup_existing(abs_out: String, abs_bak: String, keys: Array) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var bak_sub := abs_bak.path_join(stamp)
	DirAccess.make_dir_recursive_absolute(bak_sub)
	for k in keys:
		var src_path := abs_out.path_join("%s.png" % String(k))
		if not FileAccess.file_exists(src_path):
			continue
		var dst_path := bak_sub.path_join("%s.png" % String(k))
		DirAccess.copy_absolute(src_path, dst_path)
