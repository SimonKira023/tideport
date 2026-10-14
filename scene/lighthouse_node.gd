# scene/lighthouse_node.gd —— 2026-10-06 港口地标「灯塔」（程序化绘制, 不依赖第三方素材）
#
# 为什么程序化画：素材包里没有塔形房子（只有农舍/商铺），而灯塔是港口题材的**截图担当**,
# 不能拿农舍凑数。整座塔一次画成一张图（塔身石带 + 灯室 + 红顶 + 门），
# 再叠一盏夜间点亮的 PointLight2D + 一道旋转的加法光束。
#
# 玩法：不用 F（它是地标/被动建筑）—— 站旁边按 F 只飘一句说明。
#   功能在 game._on_day_ended 里：有灯塔 -> 每天早上 +1 声望（见 Structures.has_built_kind）。
# 原点在**塔基底部中间**（父节点开了 y_sort, 排序点落在底边）。
extends Node2D

const IMG_W := 32
const IMG_H := 120

# 石色（塔身暖灰, 跟海图/村子的暖调不打架）
const STONE := Color8(150, 146, 138)
const STONE_HI := Color8(186, 182, 172)
const STONE_DK := Color8(104, 100, 94)
const GLASS := Color8(255, 214, 138)     # 灯室玻璃（暖黄）
const GLASS_DK := Color8(196, 150, 84)
const ROOF := Color8(150, 62, 54)        # 红顶
const ROOF_DK := Color8(108, 40, 36)
const DOOR := Color8(86, 60, 42)

# 灯塔的亮/灭时辰见 _sync —— 全岛夜灯统一走 light_util.glow_hour_now() 一个总闸。
const BEAM_SPEED := 0.55                 # 光束转速（弧度/秒）
# 灯室那盏灯的亮度。2026-10-06 从 1.5 收到 1.35：泛光推强后 1.5 会把整座塔顶糊成一团白,
# 海上灯塔要"看得出是一盏灯在转"，不是一团光。呼吸就围绕这个值走。
const LIGHT_ENERGY := 1.35

var cell := Vector2i.ZERO
var kind := "lighthouse"                 # Structures.KIND_LIGHTHOUSE
var is_ghost := false

var _art: Sprite2D = null
var _light: PointLight2D = null
var _glow: Sprite2D = null
var _beam: Sprite2D = null
var _beam2: Sprite2D = null
var _lit := false
var _t := 0.0

func _ready() -> void:
	_art = Sprite2D.new()
	_art.centered = false
	_art.position = Vector2(-IMG_W / 2.0, -float(IMG_H))
	_art.texture = _make_tower_tex()
	add_child(_art)

	if is_ghost:
		return                              # 预览只有塔身一张图：不亮、不挡路

	add_to_group("farm_station")             # Structures.interact_farm 按这个组找节点
	add_child(preload("res://scene/shadow_util.gd").make_shadow(26, 9, 0.22))
	# 塔身当遮挡体：光心在灯室(y≈-100)之上, 遮挡体只画灯室以下的塔身 ——
	# 包住光心会把整盏灯罩黑（铁律见 light_util.gd）。
	add_child(preload("res://scene/light_util.gd").occluder_rect(
		Rect2(-11, -98, 22, 98)))

	# 灯室那盏灯（夜里点亮, 照亮塔下和近岸）
	var lantern := Vector2(0, -100)
	_light = preload("res://scene/light_util.gd").make_light(Color(1.0, 0.86, 0.6), LIGHT_ENERGY, 2.2, 1.9)
	_light.position = lantern
	_light.enabled = false
	add_child(_light)
	_glow = preload("res://scene/light_util.gd").make_glow(Color(1.0, 0.86, 0.56, 0.15), 2.6, 1.7)   # e90: HDR 后 0.24->0.15
	_glow.position = lantern
	_glow.visible = false
	add_child(_glow)

	# 旋转光束：两道光（相差 180 度）更像真灯塔扫海
	_beam = _make_beam(lantern)
	_beam2 = _make_beam(lantern)
	_beam2.rotation = PI

	# 走近浮出「F 灯塔」提示（左键点它 = 按 F）
	var hint: Node2D = preload("res://scene/key_hint.gd").new()
	hint.setup("F", "灯塔", -float(IMG_H) - 10.0)
	hint.connect("clicked", _on_hint_clicked)
	add_child(hint)

	# 塔基碰撞：贴底一条矮矩形，layer 4 只有玩家的 mask 里有
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(18, 10)
	cs.shape = sh
	cs.position = Vector2(0, -5)
	body.add_child(cs)
	add_child(body)

	_sync(true)

func _make_beam(lantern: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _make_beam_tex()
	s.centered = false
	s.offset = Vector2(0, -24)              # 贴图纵向居中于光心
	s.position = lantern
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = mat
	s.modulate = Color(1, 1, 1, 0.0)        # 白天透明（_sync 里改 alpha）
	add_child(s)
	return s

# 光束贴图：从光心向右发散的楔形, 越远越淡
func _make_beam_tex() -> ImageTexture:
	var w := 208
	var h := 48
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in w:
		var tx := float(x) / float(w - 1)
		var half := float(h) * 0.5 * (0.10 + 0.90 * tx)     # 近灯窄、远处散开
		for y in h:
			var dy := absf(float(y) - float(h) * 0.5) / maxf(half, 0.6)
			if dy <= 1.0:
				var a := (1.0 - dy) * (1.0 - tx) * 0.5
				img.set_pixel(x, y, Color(1.0, 0.92, 0.7, a))
	return ImageTexture.create_from_image(img)

# 整座塔一次画成一张图
func _make_tower_tex() -> ImageTexture:
	var img := Image.create_empty(IMG_W, IMG_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1EA5
	var roof_h := 12
	var lantern_h := 14
	var tower_top := roof_h + lantern_h       # 塔身顶端（img 行）
	var bottom := IMG_H - 1
	var base_w := 26.0
	var top_w := 15.0
	var cx := IMG_W * 0.5
	# —— 塔身：上窄下宽的梯形, 石带 + 左亮右暗 ——
	for y in range(tower_top, bottom + 1):
		var t := float(y - tower_top) / float(maxi(1, bottom - tower_top))
		var half := lerpf(top_w, base_w, t) * 0.5
		for x in range(int(cx - half), int(cx + half) + 1):
			if x < 0 or x >= IMG_W:
				continue
			var col := STONE
			var dxn := (float(x) - cx) / maxf(half, 1.0)
			if dxn < -0.35:
				col = STONE.lerp(STONE_HI, 0.42)
			elif dxn > 0.40:
				col = STONE.lerp(STONE_DK, 0.45)
			if (y - tower_top) % 7 == 0:
				col = col.lerp(STONE_DK, 0.5)          # 每 7 行一道砌石横带
			if rng.randi_range(0, 13) == 0:
				col = col.lerp(STONE_DK, 0.35)         # 风化点
			img.set_pixel(x, y, col)
	# —— 门：贴在塔基中间 ——
	var door_w := 8
	var door_h := 13
	for y in range(bottom - door_h + 1, bottom + 1):
		for x in range(IMG_W / 2 - door_w / 2, IMG_W / 2 + door_w / 2):
			img.set_pixel(x, y, DOOR)
	# —— 灯室下的环形挑台 ——
	var gal_y := tower_top
	for x in range(IMG_W / 2 - 11, IMG_W / 2 + 11):
		img.set_pixel(x, gal_y, STONE_DK)
		img.set_pixel(x, gal_y - 1, STONE_HI)
	# —— 灯室：玻璃 + 竖窗棂 ——
	for y in range(roof_h, roof_h + lantern_h):
		for x in range(IMG_W / 2 - 7, IMG_W / 2 + 7):
			var glass := GLASS
			if (x - IMG_W / 2 + 7) % 4 == 0:
				glass = GLASS_DK                        # 窗棂
			img.set_pixel(x, y, glass)
	for x in range(IMG_W / 2 - 7, IMG_W / 2 + 7):
		img.set_pixel(x, roof_h, GLASS_DK)
		img.set_pixel(x, roof_h + lantern_h - 1, GLASS_DK)
	# —— 红顶：小三角 ——
	for y in range(0, roof_h):
		var half := int(lerpf(1.0, 9.0, float(y) / float(maxi(1, roof_h - 1))))
		for x in range(IMG_W / 2 - half, IMG_W / 2 + half + 1):
			var col := ROOF
			if x < IMG_W / 2:
				col = ROOF.lerp(Color8(190, 92, 80), 0.4)
			elif x > IMG_W / 2:
				col = ROOF.lerp(ROOF_DK, 0.5)
			img.set_pixel(x, y, col)
	# 顶上的尖
	img.set_pixel(IMG_W / 2, 0, ROOF_DK)
	return ImageTexture.create_from_image(img)

# 天亮熄 / 天黑亮（统一走 light_util 那个总闸 —— 跟路灯/窗火/栈桥灯同一刻亮）
func _sync(force: bool) -> void:
	var want := preload("res://scene/light_util.gd").glow_hour_now()
	if want == _lit and not force:
		return
	_lit = want
	if _light != null:
		_light.enabled = want
	if _glow != null:
		_glow.visible = want
	if _beam != null:
		_beam.modulate.a = 1.0 if want else 0.0
	if _beam2 != null:
		_beam2.modulate.a = 1.0 if want else 0.0

func _process(delta: float) -> void:
	if is_ghost:
		return
	_sync(false)
	if _lit:
		_t += delta * BEAM_SPEED
		if _beam != null:
			_beam.rotation = _t
		if _beam2 != null:
			_beam2.rotation = _t + PI
		# 灯焰微呼吸, 让"亮着"有生命感
		if _light != null:
			_light.energy = LIGHT_ENERGY * (1.0 + 0.04 * sin(_t * 6.0))

# —— 与其它建筑节点同一套接口（game.pick_station_cell / _try_station_interact / 建筑模式用）——
func hit_rect() -> Rect2:
	return Rect2(global_position + Vector2(-IMG_W / 2.0, -float(IMG_H) - 2.0),
		Vector2(IMG_W, float(IMG_H) + 4.0))

func interact_rect() -> Rect2:
	return Rect2(global_position + Vector2(-40, -60), Vector2(80, 80))

func activate() -> void:
	_flash("灯塔亮着 - 每天早上 +1 声望, 海外商船也认这座港")

func _on_hint_clicked() -> void:
	activate()

func _flash(text: String, bad := false) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g == null:
		return
	var p: Variant = g.get("player")
	if p != null and (p as Node).has_method("_flash"):
		(p as Node).call("_flash", text, "error" if bad else "")

func play_removed() -> void:
	var y0 := position.y
	var tw := create_tween()
	tw.tween_property(self, "position:y", y0 - 3.0, 0.08)
	tw.tween_property(self, "position:y", y0, 0.1)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)
