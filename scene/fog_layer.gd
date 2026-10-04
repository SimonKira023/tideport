extends Node2D
# fog_layer.gd —— 天气雾气层（世界坐标，跟相机走，仿 rain_fx 的跟随方式）。
#
# 雨/风暴天在画面上蒙一层缓慢流动的半透明雾，压出「雨雾蒙蒙」的空气感；
# 晴/阴天目标强度为 0，雾自然淡出。挂在世界画布内 —— CanvasModulate 会
# 顺带给雾上色，夜里雾跟着变深蓝，不用自己管昼夜。
#
# 强度档位：雨 0.55，风暴 0.85（storm 常数凑个整，别太糊地图）。

const FADE_SPEED := 0.12           # 强度过渡速度（每秒）：雾要慢慢蒙上来/散掉
const SPRITE_SIZE := Vector2(1400.0, 900.0)   # 盖住 zoom 最低时的视野还有富余

var _amt := 0.0                    # 当前雾强度 0~1（平滑追目标）
var _sprite: Sprite2D

func _ready() -> void:
	z_index = 50            # 云(20)之上、雨丝(60)之下：雾飘在雨幕后面
	_sprite = Sprite2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scene/fog.gdshader")
	_sprite.material = mat
	_sprite.texture = _make_noise()
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sprite.scale = SPRITE_SIZE / Vector2(256.0, 256.0)
	add_child(_sprite)

# 无缝噪声：两层错速流动的原料，seamless 避免接缝在雾里露馅
func _make_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = 0.012
	n.fractal_octaves = 3
	n.seed = 20260
	var t := NoiseTexture2D.new()
	t.noise = n
	t.seamless = true
	t.width = 256
	t.height = 256
	return t

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		global_position = cam.get_screen_center_position()
	var want := 0.0
	if Weather.is_rain():
		want = 0.85 if Weather.is_storm() else 0.55
	_amt = move_toward(_amt, want, delta * FADE_SPEED)
	(_sprite.material as ShaderMaterial).set_shader_parameter("intensity", _amt)
