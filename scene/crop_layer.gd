# crop_layer.gd —— 挂在主场景，负责在耕地上显示作物
extends Node2D

const CROPS_DIR := "res://resources/Sunnyside_World_Assets/Elements/Crops/"

# 「作物名 -> 它的 00~04 五张生长贴图」。作物名 = 种子 grow_to 的 display_name。
# 用「名字对 base 文件名」的表来建，新增作物只要在这里加一行。
# 注意: 资产包里每样作物其实有 00~05 六张, 但 05 是收获物物品图标（一颗土豆/一根
# 胡萝卜/整颗菜）, 不是植株 —— 田里长到最后一阶显示物品图标很怪, 所以只取 00~04,
# 04 就是成熟苗该有的样子（块茎露头/结球/挂果）。
const GROW_FRAMES := 5

const CROP_BASES := {
	"土豆": "potato",
	"胡萝卜": "carrot",
	"卷心菜": "cabbage",
	"南瓜": "pumpkin",
	# e49 季节限定作物：贴图一样是这个目录里的 beetroot_00..04 / cauliflower_00..04
	"甜菜": "beetroot",
	"花椰菜": "cauliflower",
}

var _crop_textures: Dictionary = {}   # {作物名: Array[Texture2D x5]}
var _sprites: Dictionary = {}         # {Vector2i: Sprite2D}
var _base_x: Dictionary = {}          # d5: 摆动基准 x（摆动只拨 x，别把定位冲掉）
var _phase: Dictionary = {}           # d5: 每株相位（按格子错开，别齐刷刷摇头）
var _stage: Dictionary = {}           # 每株当前贴图档（0=种子: 种子埋在土里不参与风摆）
var _sway_t := 0.0

func _ready() -> void:
	for name in CROP_BASES:
		var frames: Array = []
		for i in GROW_FRAMES:
			# 第三方素材不入库(见 README), 缺失时留空不崩
			var tex := SoftRes.tex("%s%s_%02d.png" % [CROPS_DIR, CROP_BASES[name], i])
			if tex == null:
				# 只在首帧缺失时报一次, 免得同一种作物刷一串警告
				if i == 0:
					push_warning("[素材] 缺少作物贴图 %s%s_00.png, 该作物不显示" % [CROPS_DIR, CROP_BASES[name]])
				continue
			frames.append(tex)
		if frames.is_empty():
			continue
		_crop_textures[name] = frames
	Farm.crop_changed.connect(_on_crop_changed)
	Farm.tilled_removed.connect(_on_crop_removed)

func _on_crop_changed(pos: Vector2i) -> void:
	var stage := Farm.get_stage(pos)
	if stage < 0:
		_on_crop_removed(pos)
		return
	var seed: ItemData = Farm.crops[pos].seed
	# 用种子的 grow_to（作物）名字作为贴图 key
	var crop_name := seed.display_name
	if seed.grow_to != null:
		crop_name = seed.grow_to.display_name
	_update_sprite(pos, crop_name, stage, seed.grow_days, Farm.is_dead(pos))

func _on_crop_removed(pos: Vector2i) -> void:
	if _sprites.has(pos):
		var spr: Sprite2D = _sprites[pos]
		_leaf_burst(spr.position)   # d5: 作物离田那一刻崩几片叶屑
		_sprites[pos].queue_free()
		_sprites.erase(pos)
		_base_x.erase(pos)
		_phase.erase(pos)
		_stage.erase(pos)

func _update_sprite(pos: Vector2i, crop_name: String, stage: int, grow_days: int, dead: bool = false) -> void:
	if not _crop_textures.has(crop_name):
		return
	var frames: Array = _crop_textures[crop_name]
	# 把 0..grow_days 摊到 0..frames-1 —— 这样成熟那张（05）真的会用上，
	# 而不是像以前那样 stage 上限比贴图数小、永远差最后一档。
	var idx := 0
	if grow_days > 0:
		idx = clampi(int(round(float(stage) / float(grow_days) * (frames.size() - 1))),
			0, frames.size() - 1)
	var tex = frames[idx]
	if not _sprites.has(pos):
		var spr := Sprite2D.new()
		spr.centered = true
		add_child(spr)
		_sprites[pos] = spr
	var spr: Sprite2D = _sprites[pos]
	spr.texture = tex
	# 枯萎：灰褐色调（贴图还是那张，压暗+去饱和的假枯），恢复季节前都保持这副样子
	spr.modulate = Color(0.62, 0.55, 0.45) if dead else Color.WHITE
	var origin_local := Farm.grid_origin - global_position
	spr.position = origin_local + Vector2(
		pos.x * Farm.TILE_SIZE + Farm.TILE_SIZE / 2.0,
		pos.y * Farm.TILE_SIZE + Farm.TILE_SIZE / 2.0)
	# d5: 记下摆动基准与相位（跟树一样按格子错开）
	_base_x[pos] = spr.position.x
	_phase[pos] = float(absi(pos.x * 73 + pos.y * 151) % 628) * 0.01
	_stage[pos] = idx

# ---------------- d5: 风摆 + 收割叶屑 ----------------
# 田里的作物也跟树梢一起晃（雨天/风暴摆得更凶）；种子那一档(贴图 00)还埋在土里, 不晃；
# 收割/清枯那一刻原地崩几片绿叶。
func _process(delta: float) -> void:
	if _sprites.is_empty():
		return
	_sway_t += delta
	var amp := 1.8 if (Weather.is_storm() or Weather.is_rain()) else 0.8
	for pos in _sprites:
		var spr: Sprite2D = _sprites[pos]
		if not is_instance_valid(spr):
			continue
		if int(_stage.get(pos, 0)) == 0:   # 种子阶段: 静止
			continue
		spr.position.x = float(_base_x.get(pos, spr.position.x)) \
			+ sin(_sway_t * 1.7 + float(_phase.get(pos, 0.0))) * amp

func _leaf_burst(at: Vector2) -> void:
	if not is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.amount = 8
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.5
	p.spread = 65.0
	p.gravity = Vector2(0, 110)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 36.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.8
	p.color = Color(0.45, 0.66, 0.33)
	p.position = at + Vector2(0, -6)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.1).timeout.connect(p.queue_free)
