# season_fx.gd —— 季节氛围粒子，跟着相机走（仿 rain_fx.gd 的跟随方式）。
#
#   · 春：淡粉飞絮，几乎无重力地慢速漂浮。
#   · 夏：萤火虫，只在夜里亮起（黄绿光点加法混合，随生命周期呼吸明灭），雨天不出。
#   · 秋：橙红落叶，带旋转慢慢斜飘下落。
#   · 冬：晴日细雪，密度很低的一层薄雪感；真下雪天仍由 rain_fx.gd 播雪。
#
# 曾经的「冬晴轻雪」与光尘层因「凭空飘白点看不懂」被砍；这版给足语义——
# 萤火只在夜里发光、细雪只在入冬后飘、飞絮淡粉可辨，且密度都压得很低。
#
# _process 里把各层 alpha 往目标值缓动 —— 换季那天天一亮粒子自然切换，不用发信号。
extends CPUParticles2D

const LEAF_COLOR := Color(0.87, 0.47, 0.22, 1.0)
const LEAF_ALPHA := 0.45
const PETAL_ALPHA := 0.30
const FIRE_ALPHA := 0.55
const SNOW_ALPHA := 0.22

var _leaf: CPUParticles2D = null
var _petal: CPUParticles2D = null
var _fire: CPUParticles2D = null
var _snow: CPUParticles2D = null

func _ready() -> void:
	z_index = 60            # 盖在角色之上（跟雨效同层）；被 NightOverlay 和面板压住
	# ❗本节点自己也是 CPUParticles2D：没配纹理/参数时按默认白色无纹理方块往下掉。
	#   父节点只当跟随相机的容器用，自己的发射必须关掉（amount 不能设 0，
	#   引擎要求 >= 1）。
	emitting = false
	_build_leaves()
	_build_petals()
	_build_fireflies()
	_build_snowdrift()

# 径向渐变小圆点（纯运行时生成不依赖图集）
func _make_dot() -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			var d := Vector2(x - 5.5, y - 5.5).length() / 5.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	# 各层的季节目标浓度：只有对应季节出现，其余季节淡出
	if _leaf != null:
		var leaf_target := LEAF_ALPHA if TimeManager.season == 2 else 0.0
		_leaf.color.a = lerpf(_leaf.color.a, leaf_target, 0.05)
	if _petal != null:
		var petal_target := PETAL_ALPHA if TimeManager.season == 0 else 0.0
		_petal.color.a = lerpf(_petal.color.a, petal_target, 0.05)
	if _snow != null:
		var snow_target := SNOW_ALPHA if TimeManager.season == 3 else 0.0
		_snow.color.a = lerpf(_snow.color.a, snow_target, 0.05)
	if _fire != null:
		var fire_target := 0.0
		if TimeManager.season == 1 and _is_night() and not Weather.is_rain():
			fire_target = FIRE_ALPHA
		_fire.color.a = lerpf(_fire.color.a, fire_target, 0.05)

func _is_night() -> bool:
	var h := float(TimeManager.hour)
	return h >= 19.0 or h < 5.0

# ---- 秋落叶：橙红小叶，慢速斜落 + 自旋摇摆（普通混合，别发亮） ----
func _build_leaves() -> void:
	_leaf = CPUParticles2D.new()
	_leaf.name = "Leaves"
	_leaf.texture = _make_dot()
	_leaf.amount = 14
	_leaf.lifetime = 9.0
	_leaf.preprocess = 9.0
	_leaf.emission_shape = EMISSION_SHAPE_RECTANGLE
	_leaf.emission_rect_extents = Vector2(330, 200)
	_leaf.direction = Vector2(0.3, 1.0)
	_leaf.spread = 24.0
	_leaf.gravity = Vector2(6, 14)
	_leaf.initial_velocity_min = 10.0
	_leaf.initial_velocity_max = 22.0
	_leaf.angular_velocity_min = -110.0
	_leaf.angular_velocity_max = 110.0
	_leaf.scale_amount_min = 1.1
	_leaf.scale_amount_max = 2.0
	_leaf.color = Color(LEAF_COLOR.r, LEAF_COLOR.g, LEAF_COLOR.b, 0.0)
	add_child(_leaf)

# ---- 春飞絮：淡粉白小瓣，几乎无重力，随风慢漂 ----
func _build_petals() -> void:
	_petal = CPUParticles2D.new()
	_petal.name = "Petals"
	_petal.texture = _make_dot()
	_petal.amount = 10
	_petal.lifetime = 11.0
	_petal.preprocess = 11.0
	_petal.emission_shape = EMISSION_SHAPE_RECTANGLE
	_petal.emission_rect_extents = Vector2(330, 200)
	_petal.direction = Vector2(0.5, 0.35)
	_petal.spread = 40.0
	_petal.gravity = Vector2(0, 2)
	_petal.initial_velocity_min = 4.0
	_petal.initial_velocity_max = 10.0
	_petal.angular_velocity_min = -40.0
	_petal.angular_velocity_max = 40.0
	_petal.scale_amount_min = 0.7
	_petal.scale_amount_max = 1.3
	_petal.color = Color(1.0, 0.90, 0.94, 0.0)
	add_child(_petal)

# ---- 夏萤火：黄绿光点加法混合，随生命周期呼吸式明灭；整层只在夜里亮起 ----
func _build_fireflies() -> void:
	_fire = CPUParticles2D.new()
	_fire.name = "Fireflies"
	_fire.texture = _make_dot()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fire.material = mat
	_fire.amount = 12
	_fire.lifetime = 7.0
	_fire.preprocess = 7.0
	_fire.emission_shape = EMISSION_SHAPE_RECTANGLE
	_fire.emission_rect_extents = Vector2(320, 180)
	_fire.direction = Vector2(0, -1)
	_fire.spread = 180.0
	_fire.gravity = Vector2.ZERO
	_fire.initial_velocity_min = 2.0
	_fire.initial_velocity_max = 8.0
	_fire.scale_amount_min = 0.8
	_fire.scale_amount_max = 1.6
	# 呼吸明灭：生命周期里 alpha 淡入-保持-淡出，每只萤火虫自然错开
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 1.0, 0.55, 0.0))
	ramp.set_color(1, Color(0.85, 1.0, 0.55, 0.0))
	ramp.add_point(0.3, Color(0.85, 1.0, 0.55, 1.0))
	ramp.add_point(0.7, Color(0.85, 1.0, 0.55, 1.0))
	_fire.color_ramp = ramp
	_fire.color = Color(0.85, 1.0, 0.55, 0.0)
	add_child(_fire)

# ---- 冬细雪：晴日里密度很低的薄雪感（真下雪天由 rain_fx 负责） ----
func _build_snowdrift() -> void:
	_snow = CPUParticles2D.new()
	_snow.name = "Snowdrift"
	_snow.texture = _make_dot()
	_snow.amount = 12
	_snow.lifetime = 10.0
	_snow.preprocess = 10.0
	_snow.emission_shape = EMISSION_SHAPE_RECTANGLE
	_snow.emission_rect_extents = Vector2(330, 200)
	_snow.direction = Vector2(0.2, 1.0)
	_snow.spread = 14.0
	_snow.gravity = Vector2(3, 10)
	_snow.initial_velocity_min = 8.0
	_snow.initial_velocity_max = 16.0
	_snow.scale_amount_min = 0.6
	_snow.scale_amount_max = 1.2
	_snow.color = Color(1, 1, 1, 0.0)
	add_child(_snow)
