extends Node
# e30 一次性探针：扫描全场景碰撞体 + 贴图裁剪审计，定位「屋子前走不了」的隐形墙
#   (1) 所有与屋前区域相交的碰撞矩形
#   (2) 所有非水碰撞的 StaticBody2D 形状（逐个对照贴图查碰撞是否过大）
#   (3) 物理点采样 + ASCII 可走性地图（抓 TileMap 物理 / 运行时水矩形等非常规碰撞）
#   (4) 全场景贴图裁剪审计（region_rect 越界 / 明显非整数）
#   (5) 贴图不透明边界 vs 碰撞矩形 像素级对比（房子墙带逐行 / 售卖箱 / 商人 / 床）
# 只读不写档：SaveManager.enabled = false，跑完即退。

var _space: PhysicsDirectSpaceState2D
var _do_points := false
var _big_zone := Rect2()
var _step := 4
var _g: Node2D

func _ready() -> void:
	SaveManager.enabled = false
	var g: Node2D = load("res://scene/game.tscn").instantiate()
	_g = g
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var house: Node2D = g.get_node("House")
	var hp: Vector2 = house.global_position
	print("[House] global_position=", hp)
	var ext: Sprite2D = house.get_node("Exterior")
	print("[House.Exterior] 贴图全局矩形=", Rect2(ext.global_position, ext.texture.get_size()))
	for other in ["Merchant", "ShippingBin"]:
		var n: Node2D = g.get_node_or_null(other)
		if n != null:
			var spr := _first_sprite(n)
			if spr != null and spr.texture != null:
				print("[%s] global_position=%s 贴图矩形=%s" % [other, n.global_position, Rect2(spr.global_position, spr.texture.get_size())])

	# 屋前重点区域：门前 y 0~48、左右各多扫 40px
	var front_zone := Rect2(hp + Vector2(-40, -16), Vector2(160, 96))
	print("\n=== (1) 与屋前区域相交的碰撞形状 ===")
	_scan(g, front_zone, hp, true)

	print("\n=== (2) 全部非水碰撞形状 ===")
	_scan(g, Rect2(), hp, false)

	# (3) 物理点采样：覆盖屋子前后左右 (屋后能走 / 屋前别有隐形墙)
	_big_zone = Rect2(hp + Vector2(-80, -140), Vector2(240, 250))
	_space = g.get_world_2d().direct_space_state
	_do_points = true   # 交给 _physics_process 执行(空间状态只在物理步内可查)

func _physics_process(_d: float) -> void:
	if not _do_points:
		return
	_do_points = false
	print("\n=== (3) 物理点采样 ASCII 可走性图 (遮罩=1|4, 步长 %dpx, 区=%s) ===" % [_step, _big_zone])
	print("  ('#'=挡人 ' '=可走; 左上角=区左上角; 每字符横向 %dpx)" % _step)
	var owner_hits := {}
	var cols := int(_big_zone.size.x) / _step
	var rows := int(_big_zone.size.y) / _step
	for row in rows:
		var line := ""
		for col in cols:
			var pt := _big_zone.position + Vector2(col * _step + 1, row * _step + 1)
			var q := PhysicsPointQueryParameters2D.new()
			q.position = pt
			q.collision_mask = 1 | 8   # layer1 世界碰撞 + layer4 树/岩石
			q.collide_with_areas = false
			q.collide_with_bodies = true
			var hits := _space.intersect_point(q, 8)
			if hits.is_empty():
				line += " "
			else:
				line += "#"
				for h in hits:
					var col_obj: Object = h["collider"]
					var key: String = str((col_obj as Node).get_path()) if col_obj is Node else str(col_obj)
					if not owner_hits.has(key):
						owner_hits[key] = {"n": 0, "min": pt, "max": pt}
					var rec: Dictionary = owner_hits[key]
					rec["n"] = int(rec["n"]) + 1
					var mn: Vector2 = rec["min"]
					var mx: Vector2 = rec["max"]
					rec["min"] = Vector2(minf(mn.x, pt.x), minf(mn.y, pt.y))
					rec["max"] = Vector2(maxf(mx.x, pt.x), maxf(mx.y, pt.y))
		print(line)
	print("  -- 各挡人 owner 汇总 --")
	for k in owner_hits.keys():
		var rec: Dictionary = owner_hits[k]
		print("  [挡点] %s n=%d 范围=%s ~ %s" % [k, rec["n"], rec["min"], rec["max"]])

	# (5) 贴图不透明边界 vs 碰撞矩形
	print("\n=== (5) 贴图不透明边界 vs 碰撞矩形 ===")
	_cmp_all()

	# (4) 贴图裁剪审计
	print("\n=== (4) 贴图裁剪审计 ===")
	_audit_crops(get_tree().root)
	get_tree().quit()

# ---------------- (5) 像素级对比 ----------------
func _img_of(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img

# 区域内不透明包围盒（图像像素坐标）
func _bbox(img: Image, r: Rect2i) -> Rect2i:
	var mn := Vector2i(1 << 30, 1 << 30)
	var mx := Vector2i(-1, -1)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if img.get_pixel(x, y).a > 0.05:
				mn.x = mini(mn.x, x)
				mn.y = mini(mn.y, y)
				mx.x = maxi(mx.x, x)
				mx.y = maxi(mx.y, y)
	if mx.x < 0:
		return Rect2i()
	return Rect2i(mn, mx - mn + Vector2i(1, 1))

# 横向条带里不透明像素的 x 范围 [min,max]；全空返回 (-1,-1)
func _band_x(img: Image, y0: int, y1: int, x0: int, x1: int) -> Vector2i:
	var mnx := 1 << 30
	var mxx := -1
	for y in range(maxi(y0, 0), mini(y1, img.get_height())):
		for x in range(maxi(x0, 0), mini(x1, img.get_width())):
			if img.get_pixel(x, y).a > 0.05:
				mnx = mini(mnx, x)
				mxx = maxi(mxx, x)
	return Vector2i(mnx, mxx)

func _edges(tag: String, coll: Rect2, opq: Rect2) -> void:
	print("  [%s]\n        碰撞=%s\n        不透明=%s\n        差值: 左%+.1f 右%+.1f 上%+.1f 下%+.1f (正=贴图超出碰撞/碰撞偏小; 负=碰撞超出贴图/碰撞偏大)" % [
		tag, coll, opq,
		opq.position.x - coll.position.x, opq.end.x - coll.end.x,
		opq.position.y - coll.position.y, opq.end.y - coll.end.y])

func _cmp_all() -> void:
	var house: Node2D = _g.get_node("House")
	# --- 房子：10.png 逐行轮廓 ---
	var ext := house.get_node("Exterior") as Sprite2D
	var img := _img_of(ext.texture)
	var ts := Vector2i(img.get_width(), img.get_height())
	var full := _bbox(img, Rect2i(0, 0, ts.x, ts.y))
	print("  [House] 10.png 尺寸=%s 全图不透明bbox=%s (贴图底行=%d, 不透明底行=%d)" % [str(ts), str(full), ts.y, full.end.y])
	print("  -- 底部 34 行逐行不透明 x (墙体/门轮廓; HouseBody 碰撞在图内 x 15..65, 行 %d..%d) --" % [ts.y - 30, ts.y])
	for y in range(ts.y - 34, ts.y):
		var xr := _band_x(img, y, y + 1, 0, ts.x)
		var gy := house.global_position.y + ext.position.y + float(y)
		print("    行%3d (全局y=%.0f): %s" % [y, gy, "空" if xr.y < 0 else "x %d..%d" % [xr.x, xr.y]])
	# --- 售卖箱：动态 Art 13x19 ---
	var bin: Node2D = _g.get_node("ShippingBin")
	var art := bin.get_node_or_null("Art") as Sprite2D
	if art != null and art.texture != null:
		var bimg := _img_of(art.texture)
		var bts := Vector2i(bimg.get_width(), bimg.get_height())
		var bb := _bbox(bimg, Rect2i(0, 0, bts.x, bts.y))
		var opq := Rect2(art.global_position + Vector2(bb.position), Vector2(bb.size))
		var body := Rect2(bin.global_position + Vector2(-7, -8), Vector2(14, 8))
		_edges("Bin(箱图%s)" % str(bts), body, opq)
	# --- 商人：当前帧的不透明包围盒 ---
	var m: Node2D = _g.get_node("Merchant")
	var ms := m.get_node("Sprite2D") as Sprite2D
	var mimg := _img_of(ms.texture)
	var fw := int(mimg.get_width()) / ms.hframes
	var fh := mimg.get_height()
	var fr := Rect2i(ms.frame * fw, 0, fw, fh)
	var mb := _bbox(mimg, fr)
	var ftl: Vector2 = ms.global_position - Vector2(fw, fh) * 0.5
	# bbox 是图像像素坐标，转帧局部要减掉帧起点（帧非 0 时 fr.position != 0）
	var mopq := Rect2(ftl + Vector2(mb.position) - Vector2(fr.position), Vector2(mb.size))
	var mbody := Rect2(m.global_position + Vector2(-25, -10), Vector2(50, 10))
	_edges("Merchant(帧%d %dx%d)" % [ms.frame, fw, fh], mbody, mopq)
	# --- 床：Beds.png 区域 vs BedBody ---
	var spr := house.get_node("Interior/Bed/Sprite2D") as Sprite2D
	var bedimg := _img_of(spr.texture)
	var kb := _bbox(bedimg, Rect2i(spr.region_rect))
	# bbox 是图像像素坐标，转 sprite 局部要减掉 region 起点
	var kopq := Rect2(spr.global_position + Vector2(kb.position) - spr.region_rect.position, Vector2(kb.size))
	var bbcs := house.get_node("Interior/BedBody/CollisionShape2D") as CollisionShape2D
	var bsz: Vector2 = (bbcs.shape as RectangleShape2D).size
	var kbody := Rect2(bbcs.global_position - bsz * 0.5, bsz)
	_edges("Bed", kbody, kopq)

# ---------------- 工具 ----------------
func _audit_crops(n: Node) -> void:
	if n is Sprite2D:
		var s := n as Sprite2D
		if s.texture != null and s.region_enabled:
			var ts: Vector2 = s.texture.get_size()
			var rr: Rect2 = s.region_rect
			if rr.position.x < -0.01 or rr.position.y < -0.01 \
					or rr.end.x > ts.x + 0.01 or rr.end.y > ts.y + 0.01:
				print("  [越界] %s region=%s 超出贴图 %s" % [s.get_path(), rr, ts])
			var fx := absf(rr.position.x - roundf(rr.position.x)) + absf(rr.size.x - roundf(rr.size.x))
			var fy := absf(rr.position.y - roundf(rr.position.y)) + absf(rr.size.y - roundf(rr.size.y))
			if fx > 0.05 or fy > 0.05:
				print("  [非整数] %s region=%s (贴图 %s)" % [s.get_path(), rr, ts])
	for c in n.get_children():
		_audit_crops(c)

func _first_sprite(n: Node) -> Sprite2D:
	if n is Sprite2D:
		return n
	for c in n.get_children():
		var s := _first_sprite(c)
		if s != null:
			return s
	return null

func _scan(n: Node, zone: Rect2, house_pos: Vector2, only_zone: bool) -> void:
	if n is CollisionShape2D and n.get_parent() is CollisionObject2D:
		var cs := n as CollisionShape2D
		var co := cs.get_parent() as CollisionObject2D
		var is_water := false
		var p: Node = co
		while p != null:
			if p.name == "WaterBodies":
				is_water = true
				break
			p = p.get_parent()
		var desc := ""
		var aabb := Rect2()
		if cs.shape is RectangleShape2D:
			var sz: Vector2 = (cs.shape as RectangleShape2D).size
			aabb = Rect2(cs.global_position - sz * 0.5, sz)
			desc = "rect=%s" % aabb
		elif cs.shape is CircleShape2D:
			var r: float = (cs.shape as CircleShape2D).radius
			aabb = Rect2(cs.global_position - Vector2(r, r), Vector2(r * 2, r * 2))
			desc = "circle c=%s r=%.1f" % [cs.global_position, r]
		elif cs.shape is CapsuleShape2D:
			var cap := cs.shape as CapsuleShape2D
			aabb = Rect2(cs.global_position - Vector2(cap.radius, cap.height * 0.5), Vector2(cap.radius * 2, cap.height))
			desc = "capsule c=%s r=%.1f h=%.1f" % [cs.global_position, cap.radius, cap.height]
		else:
			desc = "other shape"
		if is_water:
			if only_zone and aabb.intersects(zone):
				print("  [水] %s layer=%d %s" % [co.get_path(), co.collision_layer, desc])
		else:
			if not only_zone:
				print("  %s layer=%d %s" % [co.get_path(), co.collision_layer, desc])
			elif aabb.intersects(zone):
				print("  [屋前] %s layer=%d %s" % [co.get_path(), co.collision_layer, desc])
	for c in n.get_children():
		_scan(c, zone, house_pos, only_zone)
