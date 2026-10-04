extends Control
# cg_view.gd — 剧情演出场景层：多层视差 + 时段光照 + 色调 + fx 指令驱动
# 由 story_dialogue 导演模式调用：fx(cmd) 同步执行并返回等待秒数

const EDGE := 150.0          # 摄像机视差余量
const SKY_PAD := 300.0       # 天空纹理出血
const M := 240.0             # 自绘层出血
const GROUND_FAR := 0.93     # 近景地平
const GROUND_ACT := 0.86     # 站位地平

const INK := Color(0.035, 0.040, 0.055)

const TODS := {
	"dawn": {"top": Color(0.55, 0.42, 0.50), "bot": Color(0.94, 0.70, 0.55), "sun": Color(0.78, 0.42, 0.40), "sun_p": Vector2(0.24, 0.52), "stars": 0.0, "moon_p": Vector2(0.86, 0.10), "ink_far": Color(0.34, 0.26, 0.36), "ink_near": Color(0.22, 0.16, 0.26)},
	"day": {"top": Color(0.48, 0.72, 0.88), "bot": Color(0.80, 0.88, 0.90), "sun": Color(0.92, 0.80, 0.42), "sun_p": Vector2(0.78, 0.14), "stars": 0.0, "moon_p": Vector2(0.86, 0.10), "ink_far": Color(0.34, 0.42, 0.50), "ink_near": Color(0.20, 0.28, 0.30)},
	"dusk": {"top": Color(0.30, 0.22, 0.38), "bot": Color(0.92, 0.52, 0.36), "sun": Color(0.80, 0.38, 0.30), "sun_p": Vector2(0.72, 0.60), "stars": 0.35, "moon_p": Vector2(0.86, 0.10), "ink_far": Color(0.20, 0.14, 0.30), "ink_near": Color(0.12, 0.09, 0.22)},
	"night": {"top": Color(0.04, 0.05, 0.12), "bot": Color(0.10, 0.14, 0.24), "sun": Color(0.76, 0.78, 0.85), "sun_p": Vector2(0.82, 0.18), "stars": 0.9, "moon_p": Vector2(0.82, 0.18), "ink_far": Color(0.10, 0.12, 0.22), "ink_near": Color(0.06, 0.07, 0.14)},
}

# 场景定义：h=海平线（-1 无海用地面带）
const SCENES := {
	"beach": {"h": 0.60, "props": "beach"},
	"field": {"h": 0.55, "props": "field"},
	"homestead": {"h": -1.0, "props": "homestead"},
	"camp": {"h": -1.0, "props": "camp"},
	"cliff": {"h": 0.78, "props": "cliff"},
	"docks": {"h": 0.52, "props": "docks"},
	"mine": {"h": -1.0, "props": "mine"},
	"workshop": {"h": -1.0, "props": "workshop"},
}

const AT_X := {"l": 0.24, "ml": 0.38, "m": 0.5, "mr": 0.62, "r": 0.76}

# 小人调色板：主色 + 发色
const FIGS := {
	"you": {"c": Color(0.30, 0.28, 0.32), "trim": Color(0.90, 0.72, 0.25), "hair": Color(0.24, 0.18, 0.14), "female": false},
	"s0": {"c": Color(0.62, 0.28, 0.20), "trim": Color(0.40, 0.18, 0.14), "hair": Color(0.20, 0.12, 0.10), "female": false},
	"s1": {"c": Color(0.82, 0.48, 0.20), "trim": Color(0.60, 0.32, 0.14), "hair": Color(0.30, 0.16, 0.10), "female": true},
	"s2": {"c": Color(0.30, 0.55, 0.32), "trim": Color(0.20, 0.38, 0.22), "hair": Color(0.16, 0.28, 0.16), "female": true},
	"s3": {"c": Color(0.55, 0.38, 0.68), "trim": Color(0.38, 0.24, 0.48), "hair": Color(0.22, 0.14, 0.28), "female": true},
	"s4": {"c": Color(0.22, 0.34, 0.26), "trim": Color(0.14, 0.22, 0.18), "hair": Color(0.14, 0.16, 0.12), "female": false},
	"s5": {"c": Color(0.26, 0.48, 0.68), "trim": Color(0.16, 0.32, 0.46), "hair": Color(0.16, 0.30, 0.42), "female": true},
	"s6": {"c": Color(0.66, 0.52, 0.28), "trim": Color(0.44, 0.34, 0.18), "hair": Color(0.36, 0.28, 0.16), "female": true},
	"s7": {"c": Color(0.80, 0.80, 0.78), "trim": Color(0.58, 0.58, 0.56), "hair": Color(0.72, 0.72, 0.70), "female": true},
}

var _pad: ColorRect
var _camera: Control
var _far_g: Control
var _near_g: Control
var _near: Control
var _actors: Control
var _weather: Control
var _pf: ParticleField
var _leaf: LeafField
var _dust: DustField
var _sky_a: TextureRect
var _sky_b: TextureRect
var _stars: StarField
var _clouds: CloudLayer
var _sun_moon: SunMoon
var _sea: SeaField
var _glow: GlowOrb
var _mid: Control
var _tint: ColorRect
var _vig: Vignette
var _flash: ColorRect
var _fade: ColorRect

var _t := 0.0
var _pan_base := Vector2.ZERO
var _shake_k := 0.0
var _flash_a := 0.0
var _cur_tod := "day"
var _cur_scene := ""
var _cur_horizon := 0.6
var _bgm_pushed := false
var _cast := {}          # who -> Fig
var _props: Array = []   # [node, x_frac] 用于时段换色
var _sky_tween: Tween
var _props_fading := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_tree()
	_fade.color = Color(0, 0, 0, 1)
	resized.connect(func(): _camera.pivot_offset = size * 0.5)
	_camera.pivot_offset = size * 0.5

func _vw() -> Vector2:
	return size if size.x > 1.0 else Vector2(1152, 648)

func _build_tree() -> void:
	_pad = ColorRect.new()
	_pad.color = INK
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pad)

	_camera = Control.new()
	_camera.set_anchors_preset(Control.PRESET_FULL_RECT)
	_camera.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_camera)

	_far_g = Control.new()
	_near_g = Control.new()
	for g in [_far_g, _near_g]:
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_camera.add_child(g)

	_sky_a = _mk_sky_rect()
	_sky_b = _mk_sky_rect()
	_sky_b.modulate.a = 0.0
	_stars = StarField.new()
	_clouds = CloudLayer.new()
	_sun_moon = SunMoon.new()
	_sea = SeaField.new()
	_glow = GlowOrb.new()
	_mid = Control.new()
	_mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in [_sky_a, _sky_b, _stars, _clouds, _sun_moon, _sea, _glow, _mid]:
		n.set_anchors_preset(Control.PRESET_FULL_RECT)
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_far_g.add_child(n)

	_near = Control.new()
	_near.set_anchors_preset(Control.PRESET_FULL_RECT)
	_near.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_near_g.add_child(_near)

	_actors = Control.new()
	_actors.set_anchors_preset(Control.PRESET_FULL_RECT)
	_actors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera.add_child(_actors)

	_weather = Control.new()
	_weather.set_anchors_preset(Control.PRESET_FULL_RECT)
	_weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_camera.add_child(_weather)
	_pf = ParticleField.new()
	_leaf = LeafField.new()
	_dust = DustField.new()
	for n in [_pf, _leaf, _dust]:
		n.set_anchors_preset(Control.PRESET_FULL_RECT)
		_weather.add_child(n)

	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(1, 1, 1, 0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig = Vignette.new()
	_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in [_tint, _vig, _flash, _fade]:
		add_child(n)

func _mk_sky_rect() -> TextureRect:
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	return r

func _process(delta: float) -> void:
	_t += delta
	# 视差：far 净速 0.45x，near 净速 1.35x
	_far_g.position = Vector2(-EDGE, -EDGE) - _pan_base * 0.55
	_near_g.position = Vector2(-EDGE, -EDGE) + _pan_base * 0.35
	# 震屏
	var sh := Vector2.ZERO
	if _shake_k > 0.001:
		_shake_k = maxf(0.0, _shake_k - delta * 2.6)
		var k2 := _shake_k * _shake_k
		sh = Vector2(sin(_t * 61.0), cos(_t * 53.0)) * 9.0 * k2
	_camera.position = _pan_base + sh
	# flash 衰减
	if _flash_a > 0.001:
		_flash_a = maxf(0.0, _flash_a - delta * 2.4)
		_flash.color.a = _flash_a

# ============ fx 指令 ============

func fx(cmd: Dictionary) -> float:
	var kind := str(cmd.get("fx", cmd.get("cmd", "")))
	match kind:
		"bg":
			var dur := float(cmd.get("dur", 1.4))
			_set_scene(str(cmd.get("scene", "beach")), str(cmd.get("tod", "day")), dur)
			return dur
		"weather":
			_set_weather(str(cmd.get("mode", "off")), int(cmd.get("amount", 60)))
			return 0.8
		"show":
			_show_fig(str(cmd.get("who")), str(cmd.get("at", "m")))
			return 0.8
		"hide":
			_hide_fig(cmd)
			return 0.5
		"move":
			return _move_fig(str(cmd.get("who")), str(cmd.get("to", "m")), float(cmd.get("dur", 1.0)))
		"act":
			var f: Fig = _cast.get(str(cmd.get("who")))
			if f:
				f.act(str(cmd.get("pose", "bob")))
			return 0.6
		"focus":
			var f2: Fig = _cast.get(str(cmd.get("who")))
			if f2:
				_pan_to(clampf(f2.position.x / _vw().x * 0.5 - 0.25, -1.0, 1.0), 0.0, 0.9)
			return 0.9
		"cam":
			var dur2 := float(cmd.get("dur", 1.0))
			var pan: Array = cmd.get("pan", [0, 0])
			_pan_to(float(pan[0]), float(pan[1]), dur2)
			var z := float(cmd.get("zoom", -1.0))
			if z > 0.0:
				var tw := create_tween()
				tw.tween_property(_camera, "scale", Vector2.ONE * z, dur2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			return dur2
		"flash":
			_flash_a = 1.0
			_flash.color.a = 1.0
			return 0.45
		"shake":
			_shake_k = 1.0
			return 0.0
		"fade":
			var dur3 := float(cmd.get("dur", 0.8))
			var a := float(cmd.get("a", 0.0))
			var tw3 := create_tween()
			tw3.tween_property(_fade, "color:a", a, dur3)
			return dur3
		"sfx":
			Audio.play_sfx(str(cmd.get("name", "")))
			return 0.0
		"bgm":
			Audio.push_bgm(str(cmd.get("key", "")))
			_bgm_pushed = true
			return 1.6
		"bgm_off":
			if _bgm_pushed:
				Audio.pop_bgm()
				_bgm_pushed = false
			return 1.0
		"duck":
			Audio.duck()
			return 0.0
		"unduck":
			Audio.unduck()
			return 0.0
		"tint":
			var c: Color = cmd.get("color", Color(1, 1, 1, 0))
			var tw4 := create_tween()
			tw4.tween_property(_tint, "color", c, float(cmd.get("dur", 0.8)))
			return float(cmd.get("dur", 0.8))
		"wait":
			return float(cmd.get("t", 0.5))
	return 0.0

func _pan_to(nx: float, ny: float, dur: float) -> void:
	var target := Vector2(clampf(nx, -1.0, 1.0) * 120.0, clampf(ny, -1.0, 1.0) * 48.0)
	var tw := create_tween()
	tw.tween_property(self, "_pan_base", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _show_fig(who: String, at: String) -> void:
	var f: Fig = _cast.get(who)
	if f == null:
		f = Fig.new()
		f.who = who
		var pal: Dictionary = FIGS.get(who, FIGS["s0"])
		f.col = pal["c"]
		f.trim = pal["trim"]
		f.hair_col = pal["hair"]
		f.female = pal["female"]
		f.ww = _vw().x
		_actors.add_child(f)
		_cast[who] = f
	var xf: float = AT_X.get(at, 0.5)
	f.position = Vector2(xf * _vw().x, _vw().y * GROUND_ACT)
	f.modulate.a = 0.0
	f.scale = Vector2(1.15, 1.15)
	# 自动朝向中心
	f.scale.x = 1.15 if xf < 0.5 else -1.15
	var tw := create_tween()
	tw.tween_property(f, "modulate:a", 1.0, 0.45)

func _hide_fig(cmd: Dictionary) -> void:
	var who := str(cmd.get("who", ""))
	if who == "all":
		for k in _cast.keys():
			_fade_out_fig(_cast[k])
			_cast.erase(k)
		return
	var f: Fig = _cast.get(who)
	if f:
		_fade_out_fig(f)
		_cast.erase(who)

func _fade_out_fig(f: Fig) -> void:
	var tw := create_tween()
	tw.tween_property(f, "modulate:a", 0.0, 0.4)
	tw.tween_callback(f.queue_free)

func _move_fig(who: String, to: String, dur: float) -> float:
	var f: Fig = _cast.get(who)
	if f == null:
		return 0.0
	var xf: float = AT_X.get(to, 0.5)
	f.scale.x = 1.15 if xf < 0.5 else -1.15
	var tw := create_tween()
	tw.tween_property(f, "position:x", xf * _vw().x, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return dur

func _set_weather(mode: String, amount: int) -> void:
	_pf.visible = false
	_leaf.visible = false
	_dust.visible = false
	match mode:
		"rain":
			_pf.setup("rain", amount)
			_pf.visible = true
		"snow":
			_pf.setup("snow", amount)
			_pf.visible = true
		"embers":
			_pf.setup("embers", amount)
			_pf.visible = true
		"fireflies":
			_pf.setup("fireflies", amount)
			_pf.visible = true
		"leaf":
			_leaf.setup(amount)
			_leaf.visible = true
		"dust":
			_dust.setup(amount)
			_dust.visible = true
		_:
			pass

# ============ 场景构建 ============

func _set_scene(scene: String, tod: String, dur: float) -> void:
	var sc: Dictionary = SCENES.get(scene, SCENES["beach"])
	var td: Dictionary = TODS.get(tod, TODS["day"])
	var scene_changed := scene != _cur_scene
	var tod_changed := tod != _cur_tod
	_cur_scene = scene
	_cur_tod = tod
	_cur_horizon = float(sc["h"])
	# 天空
	_sky_to(td["top"], td["bot"], dur if tod_changed else minf(dur, 0.6))
	_stars.alpha = float(td["stars"])
	_sun_moon.setup(tod, td["sun"], td["sun_p"], td["moon_p"])
	_glow.visible = scene == "camp"
	if scene == "camp":
		_glow.position = Vector2(_vw().x * 0.5, _vw().y * 0.80)
		_glow.base_col = Color(1.0, 0.62, 0.24)
	# 海
	_sea.visible = _cur_horizon > 0.0
	if _sea.visible:
		_sea.horizon = _cur_horizon
		_sea.deep = td["bot"].darkened(0.35)
	# props 重建
	if scene_changed or tod_changed:
		_rebuild_props(scene, td)
	# 场景 BGM 语义由剧本层决定，此处不动 BGM

func _sky_to(top: Color, bot: Color, dur: float) -> void:
	if _sky_tween and _sky_tween.is_valid():
		_sky_tween.kill()
	# 旧 sky_b 若还在淡入则晋升
	if _sky_b.modulate.a > 0.5:
		var tmp := _sky_a.texture
		_sky_a.texture = _sky_b.texture
		_sky_b.texture = tmp
	_sky_b.texture = _grad_tex(top, bot)
	_sky_b.modulate.a = 0.0
	_sky_tween = create_tween()
	_sky_tween.tween_property(_sky_b, "modulate:a", 1.0, dur)
	_sky_tween.tween_callback(func():
		_sky_a.texture = _sky_b.texture
		_sky_b.modulate.a = 0.0)

func _grad_tex(top: Color, bot: Color, steps := 96) -> ImageTexture:
	var img := Image.create_empty(1, steps, false, Image.FORMAT_RGBA8)
	for i in steps:
		img.set_pixel(0, i, top.lerp(bot, float(i) / float(steps - 1)))
	return ImageTexture.create_from_image(img)

func _rebuild_props(scene: String, td: Dictionary) -> void:
	# 已可见的旧 props 淡出
	if not _props.is_empty():
		_props_fading = true
		var old_nodes: Array = []
		for e in _props:
			old_nodes.append(e[0])
		_props.clear()
		var tw := create_tween()
		tw.tween_interval(0.3)
		tw.tween_callback(func():
			for n in old_nodes:
				if is_instance_valid(n):
					n.queue_free())
	var ink_far: Color = td["ink_far"]
	var ink_near: Color = td["ink_near"]
	# 地面/海平色带
	_add_ground_bands(td)
	match scene:
		"beach":
			_scn_beach(ink_far, ink_near)
		"field":
			_scn_field(ink_far, ink_near)
		"homestead":
			_scn_homestead(ink_far, ink_near)
		"camp":
			_scn_camp(ink_far, ink_near)
		"cliff":
			_scn_cliff(ink_far, ink_near)
		"docks":
			_scn_docks(ink_far, ink_near)
		"mine":
			_scn_mine(ink_far, ink_near)
		"workshop":
			_scn_workshop(ink_far, ink_near)

func _add_prop(node: Node2D, x_frac: float, y_px: float, near: bool) -> void:
	var vw := _vw()
	node.position = Vector2(x_frac * vw.x, y_px)
	if near:
		_near.add_child(node)
	else:
		_mid.add_child(node)
	_props.append([node, x_frac])

func _add_ground_bands(td: Dictionary) -> void:
	var vw := _vw()
	var bot: Color = td["bot"]
	if _cur_horizon > 0.0:
		# 海下地面带（远岸）
		var g := Polygon2D.new()
		var hy := _cur_horizon * vw.y + M
		var gy := vw.y + 2.0 * M
		g.polygon = PackedVector2Array([Vector2(-M, hy), Vector2(vw.x + M, hy), Vector2(vw.x + M, gy), Vector2(-M, gy)])
		g.color = td["ink_far"].lightened(0.25)
		_mid.add_child(g)
		_props.append([g, 0.5])
	else:
		# 无海：地面色带从 0.78h 起
		var g2 := Polygon2D.new()
		var hy2 := vw.y * 0.78 + M
		var gy2 := vw.y + 2.0 * M
		g2.polygon = PackedVector2Array([Vector2(-M, hy2), Vector2(vw.x + M, hy2), Vector2(vw.x + M, gy2), Vector2(-M, gy2)])
		g2.color = bot.darkened(0.45)
		_mid.add_child(g2)
		_props.append([g2, 0.5])

# ---- 8 场景 props 分发 ----

func _scn_beach(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var hy := _cur_horizon * vw.y
	_add_prop(_p_palm(far_c), 0.14, hy + 6.0, false)
	_add_prop(_p_boat(far_c), 0.68, hy - 4.0, false)
	_add_prop(_p_rock(far_c), 0.86, hy + 10.0, false)
	_add_prop(_p_tree(near_c), 0.10, vw.y * GROUND_FAR, true)
	_add_prop(_p_rock(near_c), 0.90, vw.y * GROUND_FAR, true)

func _scn_field(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var hy := _cur_horizon * vw.y
	_add_prop(_p_crops(far_c), 0.30, hy + 14.0, false)
	_add_prop(_p_crops(far_c), 0.62, hy + 18.0, false)
	_add_prop(_p_scarecrow(far_c), 0.48, hy + 8.0, false)
	_add_prop(_p_fence(near_c), 0.50, vw.y * GROUND_FAR, true)
	_add_prop(_p_tree(near_c), 0.86, vw.y * GROUND_FAR, true)

func _scn_homestead(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var gy := vw.y * 0.80
	_add_prop(_p_house(far_c), 0.32, gy, false)
	_add_prop(_p_tree(far_c), 0.66, gy + 4.0, false)
	_add_prop(_p_fence(near_c), 0.62, vw.y * GROUND_FAR, true)
	_add_prop(_p_well(near_c), 0.20, vw.y * GROUND_FAR, true)

func _scn_camp(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var gy := vw.y * 0.80
	_add_prop(_p_tent(far_c), 0.28, gy + 6.0, false)
	_add_prop(_p_tree(far_c), 0.84, gy, false)
	_add_prop(_p_fire(near_c), 0.50, vw.y * GROUND_ACT + 8.0, true)
	_add_prop(_p_rock(near_c), 0.12, vw.y * GROUND_FAR, true)

func _scn_cliff(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var hy := _cur_horizon * vw.y
	_add_prop(_p_tower(far_c), 0.74, hy - 6.0, false)
	_add_prop(_p_rock(far_c), 0.16, hy + 4.0, false)
	_add_prop(_p_rock(near_c), 0.32, vw.y * GROUND_FAR, true)

func _scn_docks(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var hy := _cur_horizon * vw.y
	_add_prop(_p_boat(far_c), 0.22, hy - 6.0, false)
	_add_prop(_p_dock(near_c), 0.56, vw.y * 0.84, true)
	_add_prop(_p_crate(near_c), 0.80, vw.y * 0.84, true)

func _scn_mine(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var gy := vw.y * 0.80
	_add_prop(_p_mine_arch(far_c), 0.42, gy, false)
	_add_prop(_p_cart(near_c), 0.64, vw.y * GROUND_FAR, true)
	_add_prop(_p_lantern(near_c), 0.22, vw.y * GROUND_FAR, true)

func _scn_workshop(far_c: Color, near_c: Color) -> void:
	var vw := _vw()
	var gy := vw.y * 0.80
	_add_prop(_p_shed(far_c), 0.30, gy, false)
	_add_prop(_p_mill(far_c), 0.72, gy + 2.0, false)
	_add_prop(_p_crate(near_c), 0.18, vw.y * GROUND_FAR, true)

# ---- props 生成器（Polygon2D 拼） ----

func _poly(pts: Array, col: Color) -> Polygon2D:
	var p := Polygon2D.new()
	var arr := PackedVector2Array()
	for v in pts:
		arr.append(v)
	p.polygon = arr
	p.color = col
	return p

func _p_tree(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-6, 0), Vector2(6, 0), Vector2(3, -46), Vector2(-3, -46)], col))
	for off in [Vector2(-20, -52), Vector2(18, -56), Vector2(0, -72)]:
		var c := _circle_poly(off, 26.0, col)
		n.add_child(c)
	return n

func _p_palm(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-5, 0), Vector2(5, 0), Vector2(9, -62), Vector2(1, -64)], col))
	for ang in [-2.4, -1.9, -1.2, -0.5, 0.1]:
		var leaf := _poly([Vector2(6, -62), Vector2(6 + 40 * cos(ang), -62 + 26 * sin(ang)), Vector2(6 + 46 * cos(ang), -62 + 34 * sin(ang)), Vector2(4, -56)], col)
		n.add_child(leaf)
	return n

func _p_house(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-42, 0), Vector2(42, 0), Vector2(42, -48), Vector2(-42, -48)], col))
	n.add_child(_poly([Vector2(-50, -48), Vector2(50, -48), Vector2(0, -78)], col.darkened(0.2)))
	n.add_child(_poly([Vector2(-9, 0), Vector2(9, 0), Vector2(9, -26), Vector2(-9, -26)], col.darkened(0.45)))
	return n

func _p_tent(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-36, 0), Vector2(36, 0), Vector2(0, -54)], col))
	n.add_child(_poly([Vector2(-8, 0), Vector2(8, 0), Vector2(0, -22)], col.darkened(0.5)))
	return n

func _p_rock(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-24, 0), Vector2(-14, -20), Vector2(4, -26), Vector2(20, -12), Vector2(24, 0)], col))
	return n

func _p_boat(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-30, 0), Vector2(30, 0), Vector2(20, -12), Vector2(-20, -12)], col))
	n.add_child(_poly([Vector2(-2, -12), Vector2(2, -12), Vector2(2, -44), Vector2(-2, -44)], col.darkened(0.2)))
	return n

func _p_fence(col: Color) -> Node2D:
	var n := Node2D.new()
	for i in 5:
		var x := -40.0 + i * 20.0
		n.add_child(_poly([Vector2(x - 2, 0), Vector2(x + 2, 0), Vector2(x + 2, -26), Vector2(x - 2, -26)], col))
	n.add_child(_poly([Vector2(-44, -20), Vector2(44, -20), Vector2(44, -24), Vector2(-44, -24)], col.darkened(0.15)))
	return n

func _p_crate(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-14, 0), Vector2(14, 0), Vector2(14, -24), Vector2(-14, -24)], col))
	n.add_child(_poly([Vector2(-14, -10), Vector2(14, -10), Vector2(14, -14), Vector2(-14, -14)], col.darkened(0.3)))
	return n

func _p_dock(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-80, -10), Vector2(20, -10), Vector2(20, -4), Vector2(-80, -4)], col))
	for i in 3:
		var x := -70.0 + i * 36.0
		n.add_child(_poly([Vector2(x - 3, -4), Vector2(x + 3, -4), Vector2(x + 3, 14), Vector2(x - 3, 14)], col.darkened(0.25)))
	return n

func _p_mill(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-16, 0), Vector2(16, 0), Vector2(12, -60), Vector2(-12, -60)], col))
	n.add_child(_poly([Vector2(-20, -60), Vector2(20, -60), Vector2(0, -76)], col.darkened(0.2)))
	return n

func _p_mine_arch(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-44, 0), Vector2(-34, 0), Vector2(-34, -48), Vector2(-20, -62), Vector2(20, -62), Vector2(34, -48), Vector2(34, 0), Vector2(44, 0), Vector2(44, 4), Vector2(-44, 4)], col))
	n.add_child(_poly([Vector2(-22, 0), Vector2(22, 0), Vector2(22, -30), Vector2(0, -46), Vector2(-22, -30)], col.darkened(0.55)))
	return n

func _p_cart(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-22, -12), Vector2(22, -12), Vector2(18, -30), Vector2(-18, -30)], col))
	for x in [-12.0, 12.0]:
		n.add_child(_circle_poly(Vector2(x, -6), 8.0, col.darkened(0.3)))
	return n

func _p_scarecrow(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-2, 0), Vector2(2, 0), Vector2(2, -40), Vector2(-2, -40)], col))
	n.add_child(_poly([Vector2(-18, -34), Vector2(18, -34), Vector2(18, -30), Vector2(-18, -30)], col))
	n.add_child(_circle_poly(Vector2(0, -44), 8.0, col))
	return n

func _p_fire(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-14, 0), Vector2(-4, -18), Vector2(2, -8), Vector2(12, -22), Vector2(16, 0)], Color(0.85, 0.42, 0.16)))
	n.add_child(_poly([Vector2(-20, 2), Vector2(20, 2), Vector2(16, 8), Vector2(-16, 8)], col.darkened(0.4)))
	return n

func _p_well(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-16, 0), Vector2(16, 0), Vector2(14, -20), Vector2(-14, -20)], col))
	n.add_child(_poly([Vector2(-20, -20), Vector2(20, -20), Vector2(0, -34)], col.darkened(0.2)))
	return n

func _p_crops(col: Color) -> Node2D:
	var n := Node2D.new()
	for i in 7:
		var x := -36.0 + i * 12.0
		n.add_child(_poly([Vector2(x - 1.5, 0), Vector2(x + 1.5, 0), Vector2(x + 2.5, -16), Vector2(x - 2.5, -16)], col))
	return n

func _p_lantern(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-2, 0), Vector2(2, 0), Vector2(2, -34), Vector2(-2, -34)], col))
	n.add_child(_circle_poly(Vector2(0, -40), 7.0, Color(0.95, 0.72, 0.30)))
	return n

func _p_shed(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-34, 0), Vector2(34, 0), Vector2(34, -36), Vector2(-34, -36)], col))
	n.add_child(_poly([Vector2(-40, -36), Vector2(40, -36), Vector2(-6, -52)], col.darkened(0.2)))
	return n

func _p_tower(col: Color) -> Node2D:
	var n := Node2D.new()
	n.add_child(_poly([Vector2(-16, 0), Vector2(16, 0), Vector2(12, -80), Vector2(-12, -80)], col))
	n.add_child(_poly([Vector2(-18, -80), Vector2(18, -80), Vector2(18, -92), Vector2(-18, -92)], col.darkened(0.2)))
	return n

func _circle_poly(center: Vector2, r: float, col: Color) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	return p

# ============ 内件（复刻 cutscene_base） ============

class StarField extends Control:
	var alpha := 0.0
	var _pts: Array = []
	var _t := 0.0
	const MM := 240.0
	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260925
		for i in 110:
			_pts.append({"x": rng.randf(), "y": rng.randf() * 0.62, "sp": rng.randf_range(0.5, 1.6), "p": rng.randf() * TAU, "r": rng.randf_range(0.8, 1.8)})
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		if alpha <= 0.01:
			return
		var w := _ww()
		var h := _hh()
		for s in _pts:
			var x := fposmod(s["x"] * w - _t * 3.0, w)
			var y: float = s["y"] * h
			var a: float = alpha * (0.30 + 0.70 * (0.5 + 0.5 * sin(_t * s["sp"] + s["p"])))
			draw_circle(Vector2(x, y), s["r"], Color(1.0, 0.98, 0.90, a))
	func _ww() -> float:
		return size.x if size.x > 1.0 else 1152.0
	func _hh() -> float:
		return size.y if size.y > 1.0 else 648.0

class CloudLayer extends Control:
	var _t := 0.0
	var _clouds: Array = []
	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 9911
		for i in 14:
			_clouds.append({"x": rng.randf(), "y": rng.randf_range(0.06, 0.42), "r": rng.randf_range(44, 96), "sp": rng.randf_range(4.0, 11.0), "a": rng.randf_range(0.35, 0.75)})
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		for c in _clouds:
			var x := fposmod(c["x"] * w + _t * c["sp"], w + 360.0) - 180.0
			var y: float = c["y"] * h
			var r: float = c["r"]
			for k in 5:
				var ang := TAU * float(k) / 5.0
				draw_circle(Vector2(x, y) + Vector2(cos(ang), sin(ang) * 0.4) * r * 0.5, r * 0.42, Color(1, 1, 1, 0.10 * c["a"]))
			draw_circle(Vector2(x, y), r * 0.5, Color(1, 1, 1, 0.12 * c["a"]))

class SunMoon extends Control:
	var mode := "sun"
	var col := Color(0.92, 0.80, 0.42)
	var pos := Vector2(0.78, 0.14)
	var moon_pos := Vector2(0.86, 0.10)
	func setup(m: String, c: Color, sp: Vector2, mp: Vector2) -> void:
		mode = m
		col = c
		pos = sp
		moon_pos = mp
		queue_redraw()
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		var p := pos if mode != "night" else moon_pos
		var c := col if mode != "night" else Color(0.82, 0.84, 0.90)
		var r := 26.0 if mode != "night" else 20.0
		var center := Vector2(p.x * w, p.y * h)
		for i in 8:
			var u := float(i) / 8.0
			draw_circle(center, r * (1.0 + u * 0.9), Color(c.r, c.g, c.b, 0.035 * (1.0 - u)))
		draw_circle(center, r, c)

class SeaField extends Control:
	const MM := 240.0
	var horizon := 0.60
	var deep := Color(0.16, 0.26, 0.34)
	var _t := 0.0
	var _waves := [
		{"dy": 0.010, "amp": 0.016, "len": 0.30, "sp": 0.9},
		{"dy": 0.075, "amp": 0.022, "len": 0.24, "sp": 1.5},
		{"dy": 0.170, "amp": 0.028, "len": 0.20, "sp": 2.2},
	]
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		var hy := horizon * h
		for wi in _waves.size():
			var wv: Dictionary = _waves[wi]
			var base_y: float = hy + wv["dy"] * h
			var amp: float = wv["amp"] * h
			var lw: float = wv["len"] * w
			var pts := PackedVector2Array()
			var steps := 44
			for i in steps + 1:
				var x: float = -MM + (w + 2.0 * MM) * float(i) / float(steps)
				var ph: float = x / (lw * 0.37)
				var yy := base_y + sin(ph + _t * wv["sp"]) * amp + sin(ph * 0.37 + _t * wv["sp"] * 1.7) * amp * 0.4
				pts.append(Vector2(x, yy))
			var col := deep.lightened(0.10 * float(wi + 1))
			col.a = 0.85
			draw_polyline(pts, col, 2.0)
		# 反光
		for i in 10:
			var gx := w * 0.5
			var rx := gx + sin(_t * 0.7 + float(i) * 2.1) * w * 0.06
			var ry := hy + 8.0 + float(i) * 6.0
			var rl := 14.0 + 10.0 * sin(_t * 1.3 + float(i))
			draw_line(Vector2(rx - rl, ry), Vector2(rx + rl, ry), Color(1, 1, 1, 0.06), 2.0)

class GlowOrb extends Control:
	var base_col := Color(1.0, 0.62, 0.24)
	var _t := 0.0
	func _process(d: float) -> void:
		_t += d
		queue_redraw()
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		var center := Vector2(w * 0.5, h * 0.80)
		var breathe := 1.0 + 0.035 * sin(_t * 1.3)
		var r := 90.0 * breathe
		for i in 18:
			var u := float(i) / 18.0
			draw_circle(center, r * (1.0 - u * 0.92), Color(base_col.r, base_col.g, base_col.b, 0.030))

class Vignette extends Control:
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		var depth := minf(w, h) * 0.24
		var steps := 26
		for i in steps:
			var u := float(i) / float(steps)
			draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.020 * (1.0 - u * 0.7)), false, depth * (1.0 - u))

class ParticleField extends Control:
	var mode := ""
	var _parts: Array = []
	var _t := 0.0
	func setup(m: String, amount: int) -> void:
		mode = m
		_parts.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711 + amount
		for i in amount:
			_parts.append({
				"x": rng.randf(), "y": rng.randf(),
				"vx": rng.randf_range(-0.02, 0.02), "vy": rng.randf_range(0.05, 0.16),
				"p": rng.randf() * TAU, "sp": rng.randf_range(1.0, 3.0),
			})
		_t = 0.0
		queue_redraw()
	func _process(d: float) -> void:
		if mode == "":
			return
		_t += d
		var h := size.y if size.y > 1.0 else 648.0
		for p in _parts:
			match mode:
				"rain":
					p["y"] += 1.4 * d * p["sp"]
					p["x"] += 0.10 * d
				"snow":
					p["y"] += 0.10 * d * p["sp"]
					p["x"] += sin(_t * 0.8 + p["p"]) * 0.02 * d
				"embers":
					p["y"] -= 0.12 * d * p["sp"]
					p["x"] += sin(_t * 1.4 + p["p"]) * 0.03 * d
				"fireflies":
					p["x"] += sin(_t * 0.6 + p["p"]) * 0.03 * d
					p["y"] += cos(_t * 0.5 + p["p"] * 1.3) * 0.02 * d
			if p["y"] > 1.05:
				p["y"] = -0.05
			if p["y"] < -0.05:
				p["y"] = 1.05
		queue_redraw()
	func _draw() -> void:
		if mode == "":
			return
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		for p in _parts:
			var x: float = p["x"] * w
			var y: float = p["y"] * h
			match mode:
				"rain":
					draw_line(Vector2(x, y), Vector2(x - 2.0, y + 9.0), Color(0.70, 0.78, 0.88, 0.40), 1.5)
				"snow":
					draw_circle(Vector2(x, y), 2.0, Color(1, 1, 1, 0.70))
				"embers":
					var fl := 0.5 + 0.5 * sin(_t * 3.1 + p["p"])
					draw_circle(Vector2(x, y), 1.8, Color(1.0, 0.55, 0.20, 0.65 * fl))
				"fireflies":
					var fl2 := 0.5 + 0.5 * sin(_t * 2.2 + p["p"])
					draw_circle(Vector2(x, y), 2.2, Color(0.85, 0.95, 0.45, 0.60 * fl2))

class LeafField extends Control:
	var _leaves: Array = []
	var _t := 0.0
	func setup(amount: int) -> void:
		_leaves.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 8821
		for i in clampi(amount, 1, 60):
			_leaves.append({"x": rng.randf(), "y": rng.randf(), "vy": rng.randf_range(0.04, 0.10), "sw": rng.randf_range(0.02, 0.06), "p": rng.randf() * TAU, "s": rng.randf_range(3.0, 6.0), "col": Color(0.55, 0.62, 0.28).lerp(Color(0.72, 0.50, 0.22), rng.randf())})
	func _process(d: float) -> void:
		_t += d
		for l in _leaves:
			l["y"] += l["vy"] * d
			l["x"] += sin(_t * 1.1 + l["p"]) * l["sw"] * d
			if l["y"] > 1.05:
				l["y"] = -0.05
				l["x"] = randf()
		queue_redraw()
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		for l in _leaves:
			var x: float = l["x"] * w
			var y: float = l["y"] * h
			var s: float = l["s"]
			draw_polygon(PackedVector2Array([Vector2(x - s, y), Vector2(x, y - s * 0.5), Vector2(x + s, y), Vector2(x, y + s * 0.5)]), PackedColorArray([l["col"]]))

class DustField extends Control:
	var _parts: Array = []
	var _t := 0.0
	func setup(amount: int) -> void:
		_parts.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 3313 + amount
		for i in clampi(amount, 1, 80):
			_parts.append({"x": rng.randf(), "y": rng.randf_range(0.3, 1.0), "vx": rng.randf_range(-0.008, 0.008), "vy": rng.randf_range(-0.006, 0.004), "p": rng.randf() * TAU})
	func _process(d: float) -> void:
		_t += d
		for p in _parts:
			p["x"] += p["vx"] * d
			p["y"] += p["vy"] * d
			if p["x"] > 1.02:
				p["x"] = -0.02
			if p["x"] < -0.02:
				p["x"] = 1.02
		queue_redraw()
	func _draw() -> void:
		var w := size.x if size.x > 1.0 else 1152.0
		var h := size.y if size.y > 1.0 else 648.0
		for p in _parts:
			var fl := 0.5 + 0.5 * sin(_t * 1.7 + p["p"])
			draw_circle(Vector2(p["x"] * w, p["y"] * h), 1.6, Color(0.90, 0.85, 0.70, 0.22 * fl))

# ============ 站位小人 ============

class Fig extends Node2D:
	var who := "s0"
	var col := Color(0.6, 0.3, 0.2)
	var trim := Color(0.4, 0.2, 0.1)
	var hair_col := Color(0.2, 0.1, 0.1)
	var female := false
	var pose := "idle"
	var _t := 0.0
	var _act_t := -1.0
	var _act := ""
	var _bob_amp := 0.0
	var ww := 1152.0

	func act(p: String) -> void:
		match p:
			"bob":
				_bob_amp = 1.0
			"jump":
				var tw := create_tween()
				tw.tween_property(self, "position:y", position.y - 16.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(self, "position:y", position.y, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			"wave", "nod":
				_act = p
				_act_t = 0.0
			_:
				pass

	func _process(d: float) -> void:
		_t += d
		if _act_t >= 0.0:
			_act_t += d
			if _act_t > 0.6:
				_act = ""
				_act_t = -1.0
		queue_redraw()

	func _draw() -> void:
		var bob := sin(_t * 2.4) * 2.0 * _bob_amp
		var yb := bob
		# 阴影
		draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2(0, 0), 14.0, Color(0, 0, 0, 0.20))
		draw_set_transform(Vector2(0, yb), 0.0, Vector2(1.0, 1.0))
		var H := 86.0
		# 腿/裙
		if female:
			draw_polygon(PackedVector2Array([Vector2(-9, 0), Vector2(9, 0), Vector2(6, -H * 0.42), Vector2(-6, -H * 0.42)]), PackedColorArray([col]))
		else:
			draw_rect(Rect2(-7, -H * 0.42, 5, H * 0.42), col.darkened(0.25))
			draw_rect(Rect2(2, -H * 0.42, 5, H * 0.42), col.darkened(0.25))
		# 躯干
		var torso_top := -H * 0.80
		draw_polygon(PackedVector2Array([Vector2(-8, -H * 0.40), Vector2(8, -H * 0.40), Vector2(7, torso_top), Vector2(-7, torso_top)]), PackedColorArray([col]))
		# you 金 trim
		if who == "you":
			draw_rect(Rect2(-8, -H * 0.52, 16, 3), trim)
		# 臂
		var arm_y := -H * 0.68
		var wave_lift := 0.0
		if _act == "wave":
			wave_lift = -10.0 + sin(_act_t * 12.0) * 4.0
		draw_line(Vector2(7, arm_y), Vector2(12, arm_y + 14 + wave_lift), col, 3.5)
		draw_line(Vector2(-7, arm_y), Vector2(-12, arm_y + 14), col, 3.5)
		# 头
		var head_y := torso_top - 9.0
		var nod_off := 0.0
		if _act == "nod":
			nod_off = sin(_act_t * 9.0) * 2.0
		draw_circle(Vector2(0, head_y + nod_off), 9.0, Color(0.92, 0.80, 0.68))
		# 发
		if female:
			draw_circle(Vector2(0, head_y - 3.0 + nod_off), 10.0, hair_col)
			draw_rect(Rect2(-11, head_y - 4.0, 4, 22), hair_col)
			draw_rect(Rect2(7, head_y - 4.0, 4, 22), hair_col)
		else:
			draw_arc(Vector2(0, head_y + nod_off), 9.5, PI, TAU, 12, hair_col, 4.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ============ 收尾 ============

func close_stage() -> float:
	if _bgm_pushed:
		Audio.pop_bgm()
		_bgm_pushed = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	tw.tween_callback(_reset_stage)
	return 0.7

func _reset_stage() -> void:
	for k in _cast.keys():
		var f: Fig = _cast[k]
		if is_instance_valid(f):
			f.queue_free()
	_cast.clear()
	for e in _props:
		if is_instance_valid(e[0]):
			e[0].queue_free()
	_props.clear()
	_pan_base = Vector2.ZERO
	_shake_k = 0.0
	_camera.scale = Vector2.ONE
	_sky_a.texture = null
	_sky_b.texture = null
	_sky_b.modulate.a = 0.0
	_stars.alpha = 0.0
	_sea.visible = false
	_glow.visible = false
	_sun_moon.setup("day", TODS["day"]["sun"], TODS["day"]["sun_p"], TODS["day"]["moon_p"])
	_set_weather("off", 0)
	_tint.color = Color(1, 1, 1, 0)
	_flash_a = 0.0
	_flash.color.a = 0.0
	_cur_scene = ""
	_cur_tod = "day"
