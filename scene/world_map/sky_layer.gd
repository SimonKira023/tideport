extends RefCounted
# scene/world_map/sky_layer.gd —— 海图「天色系统」（e15c）实现模块。
#
# 原先长在 scene/world_map.gd 的 `# ---------------- 天色系统（e15c）----------------` 一节，
# 整块搬到这里：全天色键插值（SKY_KEYS）+ 建天色节点 + 每帧刷新 + 远帆剪影。
#
# 【为什么是 RefCounted 而不是 Node2D 子节点】
#   天色节点（Sky / Grade / Haze / DayNight / SunMoon / LightBand / FarBoats）必须
#   直接挂在海图根节点下参与树序与 z_index 收口（_sky_root.z_index=60 压在地图装饰上、
#   HUD 仍在更上层）；套一层容器会打乱整棵树的排序与 z 累加。
#   所以模块只负责「创建 / 刷新」，节点一律 g.add_child() 挂回海图。
#
# 【字段为什么全留在 world_map.gd】
#   1) 自检直接读它们：`wm70._dn_rect` / `_glow` / `_band` / `wm75._grade_spr`；
#   2) 自检直接 set 它们：`wm81.set("_voy_clock", 18.5)` —— 必须是宿主真字段才能被 set 命中；
#   3) `_spark_holder` 由宿主 `_build_fx` 建（粼光层不算天色，但夜里要转冷白），
#      方向是「宿主写、模块读」；
#   4) `_sync_post` 调 `_sky_hours()`、`_physics_process` 调 `_refresh_sky()`。
#   于是模块对宿主声明过的字段一律走 `g.xxx` 读写（Sprite2D / Node2D / Dictionary /
#   Array 都是引用类型，两边看到同一份；_sky_t/_voy_clock 是 float，读回时显式 float() 包一层）。
#
# 【耦合面（模块回问宿主的接口）】
#   g._sky_root g._grade_spr g._dn_rect g._glow g._band g._spark_holder
#   g._farboats g._farboat_info g._sky_t g._voy_clock
#   g.SEED g.MAP_W g.MAP_H g.VOY_DAY_SEC            （常量）
#   g._water g._sea_d                               （地形产出，宿主保有）
#   g._cell_center() g.is_water() g.add_child() g.get_viewport() g.get_viewport_rect()
#   g._grade_tex()                                  （全屏滤镜贴图留在宿主 fx 节）
#   g.visible
#   注意：`_game` 故意不标类型（动态派发），所以从 `g.` 取回来的一切都是 Variant，
#   凡是出现在 `:=` 右边的都要显式标类型，否则会撞 Parse Error（项目已知坑）。

var _game = null          # world_map 节点（动态派发，故意不标类型）

# 幂等。宿主的每个门面（含 _sky_hours/_sky_sample 这种只读 getter）都会先调一次 ——
# 因为自检 §81 会裸 `load("res://scene/world_map.gd").new()` 建海图**不进树**（_ready 不跑），
# 直接 call("_sky_hours")；只靠 _build_sky 那一处 setup 的话 _game 会是 null。
func setup(game) -> void:
	_game = game

# ---------------- 全天色键 ----------------
# [小时, 覆盖色, 覆盖强度, 光盘色, 光盘强度, 光带强度]。
# 出海时时间停摆(e13a) -> 海图定格在出发那一刻的天色: 早上出海是晨光海,
# 晚十点回岛前是暮色海 —— 宣传片里直接拨 TimeManager.hour 就能拍黄昏。
const SKY_KEYS := [
	[0.0,  Color(0.05, 0.09, 0.24), 0.50, Color(0.72, 0.82, 1.00), 0.30, 0.07],
	[4.5,  Color(0.08, 0.12, 0.28), 0.46, Color(0.72, 0.82, 1.00), 0.26, 0.07],
	[6.0,  Color(1.00, 0.82, 0.64), 0.14, Color(1.00, 0.80, 0.55), 0.42, 0.12],
	[8.0,  Color(1.00, 0.96, 0.88), 0.05, Color(1.00, 0.92, 0.72), 0.32, 0.09],
	[16.0, Color(1.00, 0.94, 0.84), 0.10, Color(1.00, 0.88, 0.62), 0.34, 0.09],
	[18.5, Color(1.00, 0.55, 0.28), 0.42, Color(1.00, 0.60, 0.34), 0.46, 0.14],
	[20.0, Color(0.13, 0.16, 0.34), 0.46, Color(0.80, 0.86, 1.00), 0.22, 0.08],
	[24.0, Color(0.05, 0.09, 0.24), 0.50, Color(0.72, 0.82, 1.00), 0.30, 0.07],
]

# ---------------- 建天色 ----------------
func build_sky(root: Node2D) -> void:
	var g = _game
	# [牺牲品] 保险丝(同 battle_map._build_night 的配方): 战场实测 Movie 模式进场帧
	#   「最先建的那批含纹理节点」可能整批不渲染, 先扔一张图外深蓝块占住名额。
	#   海图天色窗口/Movie 双模式已探针实测正常(2026-09-20), 此块未证实必需, 留作保险。
	var sac := Sprite2D.new()
	var simg := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	simg.fill(Color(0.05, 0.07, 0.20, 0.5))
	sac.texture = ImageTexture.create_from_image(simg)
	sac.position = Vector2(-20000, -20000)   # 图外远海, 不入镜
	root.add_child(sac)
	# 天色根: 世界层 Node2D, 跟随相机铺满屏幕; z 抬到地图装饰之上, HUD(CanvasLayer)永远在其上
	g._sky_root = Node2D.new()
	g._sky_root.name = "Sky"
	g._sky_root.z_index = 60
	root.add_child(g._sky_root)
	var vp: Vector2 = g.get_viewport_rect().size
	# 暖冷渐变+暗角(e12e): 160x90 纹理 LINEAR 拉伸铺屏
	g._grade_spr = Sprite2D.new()
	g._grade_spr.name = "Grade"
	g._grade_spr.texture = g._grade_tex()
	g._grade_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	g._grade_spr.centered = false
	g._grade_spr.scale = vp / Vector2(160, 90)
	g._sky_root.add_child(g._grade_spr)
	# 顶边远海雾：8x64 纹理拉伸铺屏（纹理只有顶部带 alpha, 大气透视的错觉）
	var haze := Sprite2D.new()
	haze.name = "Haze"
	haze.texture = haze_tex()
	haze.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	haze.centered = false
	haze.scale = vp / Vector2(8, 64)
	g._sky_root.add_child(haze)
	# 昼夜覆盖色: 全屏块(load 全屏白 PNG 原生尺寸铺 + modulate 上色;
	# 窗口/Movie 双模式探针实测渲染正常 —— 早先「不渲染」是探针带画到视野外的误判)
	g._dn_rect = Sprite2D.new()
	g._dn_rect.name = "DayNight"
	g._dn_rect.texture = load("res://resources/fx/white_screen.png")
	g._dn_rect.centered = false
	g._dn_rect.modulate = Color(1, 1, 1, 0)
	g._sky_root.add_child(g._dn_rect)
	# 太阳/月亮柔光盘 + 海面光带（都是加法混合; 根节点做缩放补偿, 子节点用屏幕坐标）
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g._glow = Sprite2D.new()
	g._glow.name = "SunMoon"
	g._glow.texture = glow_tex()
	g._glow.material = add_mat
	g._sky_root.add_child(g._glow)
	g._band = Sprite2D.new()
	g._band.name = "LightBand"
	g._band.texture = band_tex()
	g._band.material = add_mat
	g._band.rotation_degrees = -14.0
	g._sky_root.add_child(g._band)

# ---------------- 时刻取数 ----------------
func sky_hours() -> float:
	var g = _game
	# e16d: 航行中天色走演出钟（真实时刻只在落地回岛后接管）
	if Voyage.traveling and float(g._voy_clock) >= 0.0:
		return float(g._voy_clock)
	# 色调钟比真实钟快 2 小时（跟岛上 game.gd 一致: 6 点就是 8 点的亮色）
	return fmod(float(TimeManager.hour) + 2.0 + float(TimeManager.minute) / 60.0, 24.0)

# 按色键插值: 返回 [覆盖色(含alpha), 光盘色, 光盘强度, 光带强度]
func sky_sample(t: float) -> Array:
	var keys: Array = SKY_KEYS
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var u := (t - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
			var col: Color = (a[1] as Color).lerp(b[1], u)
			var al: float = lerpf(float(a[2]), float(b[2]), u)
			var gc: Color = (a[3] as Color).lerp(b[3], u)
			var ga: float = lerpf(float(a[4]), float(b[4]), u)
			var ba: float = lerpf(float(a[5]), float(b[5]), u)
			return [Color(col.r, col.g, col.b, al), gc, ga, ba]
	var last: Array = keys[-1]
	return [Color(last[1].r, last[1].g, last[1].b, float(last[2])), last[3], float(last[4]), float(last[5])]

# ---------------- 每帧刷新 ----------------
func refresh_sky(delta: float) -> void:
	var g = _game
	g._sky_t = float(g._sky_t) + delta
	# e16d: 航行演出钟推进 —— 首次衔接出发时刻, 之后每 VOY_DAY_SEC 秒转一天
	if Voyage.traveling:
		if float(g._voy_clock) < 0.0:
			g._voy_clock = float(TimeManager.hour) + float(TimeManager.minute) / 60.0
		g._voy_clock = fmod(float(g._voy_clock) + delta * (24.0 / float(g.VOY_DAY_SEC)), 24.0)
	# 天色根跟随相机(世界层铺屏): 原点=屏幕左上角, 观景档拉远时 scale 反向补偿, 覆盖始终=全屏
	if g._sky_root != null:
		var cam: Camera2D = g.get_viewport().get_camera_2d()
		if cam != null:
			var vp0: Vector2 = g.get_viewport_rect().size
			g._sky_root.global_position = cam.get_screen_center_position() - vp0 * 0.5 / cam.zoom.x
			g._sky_root.scale = Vector2.ONE / cam.zoom.x
	if g._dn_rect == null:
		return
	var s: Array = sky_sample(sky_hours())
	g._dn_rect.modulate = s[0]
	var vp: Vector2 = g.get_viewport_rect().size
	var t: float = sky_hours()
	# 太阳/月亮沿浅弧扫: 白天 5.5~19.5 从左到右, 夜里走另外一段
	var day: bool = t >= 5.5 and t < 19.5
	var u := 0.0
	if day:
		u = clampf((t - 5.5) / 14.0, 0.0, 1.0)
	else:
		u = clampf(fposmod(t - 19.5, 24.0) / 10.0, 0.0, 1.0)
	var gy: float = vp.y * (0.54 - 0.36 * sin(u * PI)) + sin(float(g._sky_t) * 0.7) * 2.0
	g._glow.position = Vector2(lerpf(vp.x * 0.12, vp.x * 0.88, u), gy)
	g._glow.modulate = Color(s[1].r, s[1].g, s[1].b, s[2])
	# 光带: 斜搭在海面上, 缓慢呼吸
	g._band.modulate = Color(s[1].r * 0.85, s[1].g * 0.85, s[1].b, s[3] * (0.8 + 0.2 * sin(float(g._sky_t) * 0.5)))
	g._band.position = Vector2(vp.x * 0.5, vp.y * (0.34 + 0.05 * sin(float(g._sky_t) * 0.23)))
	var bs := Vector2(vp.x * 1.9 / 256.0, vp.y * 0.42 / 24.0)
	g._band.scale = bs
	# 粼光夜里转冷白 —— 星光落在海上的倒影感
	if g._spark_holder != null:
		var nf := clampf(maxf((5.2 - t) / 1.6, (t - 19.8) / 1.6), 0.0, 1.0)
		g._spark_holder.modulate = Color(1, 1, 1).lerp(Color(0.72, 0.85, 1.15), nf)
	# 远帆剪影慢漂（只在海图可见时动）
	if g.visible and g._farboats != null:
		for info in g._farboat_info:
			var sp: Sprite2D = info["spr"]
			var dir: float = float(info["speed"])
			var nx: float = sp.position.x + dir * delta
			if not g.is_water(Vector2(nx + signf(dir) * 10.0, sp.position.y)):
				info["speed"] = -dir          # 到岸边就掉头, 永远漂在水上
				nx = sp.position.x
			sp.position.x = nx
			sp.position.y = float(info["y0"]) + sin(float(g._sky_t) * 1.1 + float(info["ph"])) * 1.6

# ---------------- 程序化贴图 ----------------
# 顶边雾: 8x64, 从天光色 alpha 0.15 淡到 0
func haze_tex() -> ImageTexture:
	var img := Image.create_empty(8, 64, false, Image.FORMAT_RGBA8)
	var sky := Color(0.66, 0.80, 0.94)
	for y in 64:
		var a := 0.15 * pow(1.0 - float(y) / 63.0, 1.6)
		for x in 8:
			img.set_pixel(x, y, Color(sky.r, sky.g, sky.b, a))
	return ImageTexture.create_from_image(img)

# 日/月光盘: 64x64 径向柔光, (1-r)^2 衰减
func glow_tex() -> ImageTexture:
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var r := Vector2(float(x) - c, float(y) - c).length() / c
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 2.0) * 0.55
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

# 海面光带: 256x24, 横向 sin 包络 + 纵向边缘淡出
func band_tex() -> ImageTexture:
	var w := 256
	var h := 24
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var env := pow(sin(PI * float(x) / float(w - 1)), 1.5)
		for y in h:
			var fy := 1.0 - absf(float(y) - float(h - 1) * 0.5) / (float(h) * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, env * fy * 0.5))
	return ImageTexture.create_from_image(img)

# 远帆剪影: 13x11 黑帆小船（深灰蓝, 半透明更远）
func farboat_tex() -> ImageTexture:
	var img := Image.create_empty(13, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var sil := Color(0.10, 0.13, 0.20, 0.85)
	# 船身: 底部两行微外扩
	for x in range(1, 12):
		img.set_pixel(x, 9, sil)
		img.set_pixel(x, 8, sil)
	img.set_pixel(0, 8, sil)
	img.set_pixel(12, 8, sil)
	# 桅杆 + 三角帆
	for y in range(2, 9):
		img.set_pixel(6, y, sil)
	for y in range(3, 8):
		var ww := int(float(y - 2) * 0.9)
		for x in range(7, 7 + ww):
			img.set_pixel(x, y, Color(0.14, 0.17, 0.25, 0.7))
	return ImageTexture.create_from_image(img)

# ---------------- 远帆剪影 ----------------
func build_farboats() -> void:
	var g = _game
	g._farboats = Node2D.new()
	g._farboats.name = "FarBoats"
	g.add_child(g._farboats)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = int(g.SEED) + 7777
	var tex := farboat_tex()
	var made := 0
	var tries := 0
	while made < 3 and tries < 300:
		tries += 1
		var c := Vector2i(rnd.randi_range(4, int(g.MAP_W) - 5), rnd.randi_range(4, int(g.MAP_H) - 5))
		if not g._water.has(c) or int(g._sea_d.get(c, 0)) < 2:
			continue
		made += 1
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var cpos: Vector2 = g._cell_center(c)
		s.position = cpos
		s.modulate = Color(1, 1, 1, 0.55)
		s.flip_h = rnd.randf() < 0.5
		g._farboats.add_child(s)
		g._farboat_info.append({
			"spr": s,
			"speed": rnd.randf_range(4.5, 8.0) * (-1.0 if s.flip_h else 1.0),
			"y0": s.position.y,
			"ph": rnd.randf_range(0.0, TAU),
		})
