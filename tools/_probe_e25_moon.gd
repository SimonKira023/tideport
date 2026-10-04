extends Node
# tools/_probe_e25_moon.gd —— round7: 验证月晕混合修复（晕环应全不透明、无绿环/棕条）
# 跑法: & $exe --path . --log-file w33_moon7.log res://tools/_probe_e25_moon.tscn

# 屏幕上棕色异物的大致区域（月亮右半）
const REGION := Rect2(890, 90, 80, 110)

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	Slaves.slaves = [
		{"name": "甲", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1},
	]
	Slaves.count = 1
	Slaves.expedition = [0]
	TimeManager.hour = 8
	TimeManager.time_running = true
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await _wait(1.2)

	var settle: Control = g.get("settlement_panel")
	var carrot: ItemData = load("res://item/carrot.tres")
	settle.call("show_summary", "春季 第 3 天", 3,
		[{"item": carrot, "count": 3, "price": 66}], 66, 1234)
	await _wait(0.6)

	var bg: TextureRect = settle.get("_bg")
	var stars: TextureRect = settle.get("_stars")
	var holder: Control = settle.get("_holder")
	print("[info] bg.filter=%d stars.filter=%d 默认filter=%s" % [
		bg.texture_filter, stars.texture_filter,
		str(ProjectSettings.get_setting(
			"rendering/textures/canvas_textures/default_texture_filter", "未设"))])

	await _shot("r7_base")
	await _palette("r7_base")

	# 1) 藏世界（晕环修好后应无变化）
	g.visible = false
	await _shot("r7_no_world")
	await _palette("r7_no_world")
	g.visible = true
	await _wait(0.15)

	# 6) 纹理程序化查棕色/半透明像素（月亮邻域 x234-270 y22-58）
	_check_tex(bg, "bg")
	_check_tex(stars, "stars")

	# 7) NightOverlay 全子树 dump
	_dump(settle.get_parent(), 0)
	get_tree().quit()

# ---------- 截图 + 棕色像素统计 ----------
func _shot(nm: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		tex.get_image().save_png(
			ProjectSettings.globalize_path("res://outputs/e25_moon_%s.png" % nm))
		print("[shot] e25_moon_%s.png" % nm)

func _palette(tag: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var brown := 0
	var buckets := {}
	for x in range(int(REGION.position.x), int(REGION.end.x), 3):
		for y in range(int(REGION.position.y), int(REGION.end.y), 3):
			var c := img.get_pixel(x, y)
			if _is_brown(c):
				brown += 1
			var key := "%d,%d,%d" % [int(c.r8 / 48.0), int(c.g8 / 48.0), int(c.b8 / 48.0)]
			buckets[key] = int(buckets.get(key, 0)) + 1
	var top := buckets.keys()
	top.sort_custom(func(a, b): return buckets[a] > buckets[b])
	var desc := ""
	for i in mini(6, top.size()):
		desc += " %s×%d" % [top[i], buckets[top[i]]]
	print("[pal] %s 棕色像素=%d 色桶:%s" % [tag, brown, desc])

func _is_brown(c: Color) -> bool:
	# 木棕/亮橙：红主导、绿中等、蓝低；排除奶油月面/绿环/蓝天/金字
	return c.r8 > 100 and c.g8 > 50 and c.g8 < 165 and c.b8 < 95 \
		and c.r8 > c.g8 + 25 and c.g8 > c.b8 + 10

# ---------- 纹理像素检查 ----------
func _check_tex(tr: TextureRect, tag: String) -> void:
	var img: Image = (tr.texture as Texture2D).get_image()
	var found := 0
	var trans := 0
	var semi := 0
	for y in range(22, 59):
		for x in range(234, 271):
			var c := img.get_pixel(x, y)
			if c.a < 0.05:
				trans += 1
			elif c.a < 0.95:
				semi += 1       # 半透明洞 = 月晕替换 bug 的直接证据
			elif _is_brown(c):
				found += 1
				if found <= 5:
					print("[tex] %s 月区棕色 (%d,%d)=%s" % [tag, x, y, str(c)])
	print("[tex] %s 月邻域 棕色=%d 半透明=%d 全透明=%d" % [tag, found, semi, trans])

# ---------- 子树 dump ----------
func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is TextureRect and (n as TextureRect).texture != null:
		extra = " tex=%s" % [(n as TextureRect).texture.resource_path]
	if n is CanvasItem and (n as CanvasItem).material != null:
		extra += " mat=有"
	var vis := "visible" if not (n is CanvasItem) or (n as CanvasItem).visible else "HIDDEN"
	print("%s%s (%s) %s%s" % [pad, n.name, n.get_class(), vis, extra])
	for ch in n.get_children():
		_dump(ch, depth + 1)

func _find(n: Node, nm: String) -> CanvasItem:
	if n.name == nm and n is CanvasItem:
		return n as CanvasItem
	for ch in n.get_children():
		var r := _find(ch, nm)
		if r != null:
			return r
	return null

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame
