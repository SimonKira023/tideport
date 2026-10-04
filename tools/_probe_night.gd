# tools/_probe_night.gd —— 临时探针: 查海图天色/夜罩为什么不渲染
# --world: 22 点拨钟 -> enter_travel -> 五等分测试带(全按相机视野定位) + 深挖 Sky 子树
# 默认:   22 点 -> enter_battle -> 战场测试带
extends Node

var game: Node = null
var _frames := 0

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--world"):
		_stripes_on = "world"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hour="):
			_hour = float(a.substr(7))
		if a == "--clean":
			_stripes_on = "clean"
		if a == "--segf":
			_stripes_on = "segf"
	SaveManager.enabled = false
	var scene: PackedScene = load("res://scene/game.tscn")
	game = scene.instantiate()
	add_child(game)

var _hour := 22.0

func _physics_process(_d: float) -> void:
	_frames += 1
	if _frames == 6:
		TimeManager.hour = int(_hour)
		TimeManager.minute = int(roundf((_hour - float(int(_hour))) * 60.0))
		TimeManager.time_tick.emit()
		if _stripes_on != "segf":
			Voyage.enter_travel(game)   # segf 在 30 帧自己出(先在岛上跑一会儿, 同 F 段)
	elif _frames == 16 and _stripes_on == "battle":
		print("[probe] before enter_battle hour=", TimeManager.hour, " minute=", TimeManager.minute)
		Voyage.enter_battle({"id": 99, "type": "巡逻", "size": 4,
			"nation": "tieyan", "army": "铁岩亲军", "pos": Vector2.ZERO})
	# --segf: 复刻宣传片 F 段(30 帧后出海, 60~190 左走, 220~255 下走)
	if _stripes_on == "segf":
		if _frames == 30:
			Voyage.enter_travel(game)
		elif _frames == 60:
			Input.action_press("move_left")
		elif _frames == 190:
			Input.action_release("move_left")
		elif _frames == 220:
			Input.action_press("move_down")
		elif _frames == 255:
			Input.action_release("move_down")
		elif _frames == 40 or _frames == 120 or _frames == 250:
			_dump_sky("frame=%d" % _frames)
		elif _frames == 290:
			var img2 := get_viewport().get_texture().get_image()
			img2.save_png(OS.get_user_data_dir() + "/../probe_segf.png")
			print("[probe] saved segf shot")
			get_tree().quit()
	elif _frames == 30:
		var bm: Node = null
		if _stripes_on == "battle":
			bm = get_tree().get_first_node_in_group("battle")
		else:
			bm = get_tree().get_first_node_in_group("world_map")
		if bm == null:
			print("[probe] !! no target node (stripes_on=%s)" % _stripes_on)
		elif _stripes_on != "clean":
			print("[probe] target=", bm.name, " hour=", TimeManager.hour)
			_add_stripes(bm)
		else:
			print("[probe] clean run, hour=", TimeManager.hour)
	elif _frames == 120:
		_dump_and_shoot()

func _dump_sky(tag: String) -> void:
	var wm: Node = get_tree().get_first_node_in_group("world_map")
	if wm == null:
		print("[probe] ", tag, " !! no world_map")
		return
	var sky: Node = wm.get("_sky_root")
	var cam := get_viewport().get_camera_2d()
	var dn: Node2D = wm.get("_dn_rect")
	print("[probe] ", tag, " hour=", TimeManager.hour, ":", "%02d" % TimeManager.minute,
		" phys=", wm.is_physics_processing(),
		" cam.center=", (cam.get_screen_center_position() if cam else Vector2.INF),
		" cam.zoom=", (cam.zoom if cam else Vector2.INF))
	if sky != null:
		print("[probe]   sky gp=", sky.global_position, " scale=", sky.scale,
			" vis=", sky.visible, " dn.mod=", (dn.modulate if dn else Color()),
			" dn.vis=", (dn.visible if dn else false))
	var img := get_viewport().get_texture().get_image()
	var tot := Color(0, 0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 48):
		for x in range(0, img.get_width(), 48):
			tot += img.get_pixel(x, y)
			n += 1
	print("[probe]   shot avg=", tot / float(n))

func _dump_and_shoot() -> void:
	var wms := get_tree().get_nodes_in_group("world_map")
	print("[probe] wm_count=", wms.size())
	if not wms.is_empty():
		var wm: Node = wms[0]
		print("[probe] wm=", wm, " processing=", wm.is_processing(),
			" visible=", (wm as CanvasItem).visible)
		var sky: Node = wm.get("_sky_root")
		if sky != null:
			print("[probe] sky gp=", sky.global_position, " scale=", sky.scale,
				" vis=", sky.visible, " mod=", sky.modulate, " children=", sky.get_child_count())
			for ch in sky.get_children():
				var info := "[probe]  - %s gp=%s scale=%s vis=%s mod=%s" % [
					ch.get_class(), ch.global_position, ch.scale, ch.visible, ch.modulate]
				if ch is Sprite2D and (ch as Sprite2D).texture != null:
					info += " tex=%s" % [(ch as Sprite2D).texture.get_size()]
				print(info)
		else:
			print("[probe] !! wm has no _sky_root")
	var img := get_viewport().get_texture().get_image()
	var tot := Color(0, 0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 64):
		for x in range(0, img.get_width(), 64):
			tot += img.get_pixel(x, y)
			n += 1
	print("[probe] shot avg=", tot / float(n))
	img.save_png(OS.get_user_data_dir() + "/../probe_stripes.png")
	print("[probe] saved stripes shot")
	get_tree().quit()

var _stripes_on := "battle"

func _add_stripes(bm: Node) -> void:
	# 五等分测试带, 全按相机视野定位(旧版 y=0 在海图视野外, 全部误判"不渲染")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	var top := Vector2.ZERO
	var vw := vp.x
	var vh := vp.y
	if cam != null:
		vw = vp.x / cam.zoom.x
		vh = vp.y / cam.zoom.y
		top = cam.get_screen_center_position() - Vector2(vw, vh) * 0.5
	print("[probe] vp=", vp, " zoom=", (cam.zoom if cam else Vector2.INF),
		" top=", top, " vw=", vw, " vh=", vh,
		" center=", (cam.get_screen_center_position() if cam else Vector2.INF))
	var w := vw / 5.0
	# A 红 = Polygon2D 直挂
	var pa := Polygon2D.new()
	pa.polygon = PackedVector2Array([top, top + Vector2(w, 0),
		top + Vector2(w, vh), top + Vector2(0, vh)])
	pa.color = Color(1, 0, 0, 0.5)
	pa.z_index = 55
	bm.add_child(pa)
	# B 绿 = Polygon2D 挂 z=60 的 Node2D 父层
	var mid := Node2D.new()
	mid.z_index = 60
	bm.add_child(mid)
	var pb := Polygon2D.new()
	pb.polygon = PackedVector2Array([top + Vector2(w, 0), top + Vector2(w * 2, 0),
		top + Vector2(w * 2, vh), top + Vector2(w, vh)])
	pb.color = Color(0, 1, 0, 0.5)
	mid.add_child(pb)
	# C 蓝 = Sprite2D + 1x1 白纹理拉伸 + modulate
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1, 1, 1))
	var pc := Sprite2D.new()
	pc.texture = ImageTexture.create_from_image(img)
	pc.centered = false
	pc.position = top + Vector2(w * 2, 0)
	pc.scale = Vector2(w, vh)
	pc.modulate = Color(0, 0, 1, 0.5)
	pc.z_index = 55
	bm.add_child(pc)
	# D 紫 = 原生尺寸 ImageTexture + z60 父层
	var sky := Node2D.new()
	sky.z_index = 60
	bm.add_child(sky)
	var big := Image.create_empty(int(w), int(vh), false, Image.FORMAT_RGBA8)
	big.fill(Color(0.6, 0.0, 0.6, 0.5))
	var pd := Sprite2D.new()
	pd.texture = ImageTexture.create_from_image(big)
	pd.centered = false
	pd.position = top + Vector2(w * 3, 0)
	sky.add_child(pd)
	# E 黄 = 直接挂进 _sky_root(海图才有; 本地坐标=屏幕像素, sky 自带缩放补偿)
	var skyr: Node = bm.get("_sky_root")
	if skyr != null:
		var pe := Polygon2D.new()
		pe.polygon = PackedVector2Array([Vector2(vp.x * 0.8, 0), Vector2(vp.x, 0),
			Vector2(vp.x, vp.y), Vector2(vp.x * 0.8, vp.y)])
		pe.color = Color(1, 1, 0, 0.5)
		skyr.add_child(pe)
	print("[probe] five test stripes added to ", bm.name)
