# scene/campfire.gd —— 篝火：某些天傍晚在远离建筑的草地上出现
# 走近按 F 打开「篝火 - 招募伙伴」面板（campfire_ui.gd）。
# 整棵都是程序化画的：石圈 + 交叉木柴是一张生成贴图，火苗/烟用粒子，光用 PointLight2D。
# ❗原点在火堆底部中心（y_sort 排序点），跟房子/树一个道理。
extends Node2D

const PIXEL_FONT := preload("res://resources/font/IPix.ttf")
const NPC_SCRIPT := preload("res://scene/slave_npc.gd")
const LIGHT_UTIL := preload("res://scene/light_util.gd")   # e31 光晕贴图/光源公用件

var player_in_range := false
var _key_hint: Node2D = null
var _flame: CPUParticles2D = null
var _light: PointLight2D = null
var _glow: Sprite2D = null
var _tw: Tween = null

# 一堆火只能招一个人 —— 招完这人就坐到火边（recruited 用来挡第二次）
var recruited := false
var _sitter: Node2D = null
# 招募**之前**就站在火边的那个陌生人（= 面板里那张信息卡写的人）。
# 招下之后他原地坐下，变成 _sitter —— 不换脸、不换人。
var _visitor: Node2D = null

func _ready() -> void:
	add_to_group("campfire")     # 面板靠这个找到「当前这堆火」
	_build_art()
	_build_light()
	_build_visitor()

	var area := Area2D.new()
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 26.0
	cs.shape = sh
	area.add_child(cs)
	area.body_entered.connect(func(b: Node2D):
		if b.is_in_group("player"):
			player_in_range = true
			_key_hint.show_hint())
	area.body_exited.connect(func(b: Node2D):
		if b.is_in_group("player"):
			player_in_range = false
			_key_hint.hide_hint())
	add_child(area)

	_key_hint = preload("res://scene/key_hint.gd").new()
	# 火边站着人的时候，走近提示「看看他」—— 不是为了看火，是为了看清这个人
	_key_hint.setup("F", "看看他" if _visitor != null else "篝火", -46.0)
	_key_hint.connect("clicked", _do_interact)   # e36i: 左键点这个框 = 按 F（字符串写法, _key_hint 是 Node2D）
	add_child(_key_hint)

# ---------------- 外观 ----------------
func _build_art() -> void:
	# e33 火堆脚下的影子
	add_child(preload("res://scene/shadow_util.gd").make_shadow(22, 8, 0.30))
	var spr := Sprite2D.new()
	spr.texture = _make_base_texture()
	spr.centered = true
	spr.position = Vector2(0, -7)     # 贴图 24x14，底边贴着原点
	add_child(spr)

	# 火苗：橙黄色小方块往上窜
	_flame = CPUParticles2D.new()
	_flame.amount = 14
	_flame.lifetime = 0.7
	_flame.spread = 16.0
	_flame.direction = Vector2(0, -1)
	_flame.gravity = Vector2(0, -46)
	_flame.initial_velocity_min = 8.0
	_flame.initial_velocity_max = 22.0
	_flame.scale_amount_min = 1.0
	_flame.scale_amount_max = 2.5
	_flame.color_ramp = _flame_ramp()
	_flame.position = Vector2(0, -4)
	add_child(_flame)

	# 烟：灰白半透明，飘得慢（补软圆纹理 —— CPUParticles2D 没纹理会渲染成白色方块）
	var smoke := CPUParticles2D.new()
	smoke.name = "Smoke"
	smoke.texture = _make_dot()
	smoke.amount = 6
	smoke.lifetime = 1.6
	smoke.spread = 20.0
	smoke.direction = Vector2(0, -1)
	smoke.gravity = Vector2(0, -14)
	smoke.initial_velocity_min = 5.0
	smoke.initial_velocity_max = 10.0
	smoke.scale_amount_min = 1.5
	smoke.scale_amount_max = 3.0
	smoke.color = Color(0.82, 0.8, 0.78, 0.30)
	smoke.position = Vector2(0, -12)
	add_child(smoke)

# 径向渐变小圆点（跟 fx_dust 一个做法，纯运行时生成不依赖图集）
func _make_dot() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)

# 石圈 + 交叉木柴，一次性画在一张小图上（固定随机种子，每次长得一样）
func _make_base_texture() -> ImageTexture:
	var w := 24
	var h := 14
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	# 交叉的两根木柴（深棕 + 浅棕高光）
	for i in 5:
		img.set_pixel(8 + i, 10 - i, Color8(96, 62, 38))
		img.set_pixel(9 + i, 10 - i, Color8(122, 82, 50))
		img.set_pixel(15 - i, 10 - i, Color8(96, 62, 38))
		img.set_pixel(14 - i, 10 - i, Color8(122, 82, 50))
	# 中间的炭火（暗红）
	for x in range(9, 15):
		img.set_pixel(x, 9, Color8(140, 56, 28))
	# 石圈：一圈灰石头围起来
	var stones := [Vector2i(3, 10), Vector2i(6, 12), Vector2i(11, 13), Vector2i(17, 12),
		Vector2i(20, 10), Vector2i(19, 7), Vector2i(4, 7)]
	for s in stones:
		var c := 150 + rng.randi() % 40
		img.set_pixel(s.x, s.y, Color8(c, c, c + 6))
		img.set_pixel(s.x + 1, s.y, Color8(c - 30, c - 30, c - 24))
	return ImageTexture.create_from_image(img)

# 火苗颜色渐变：白黄 -> 橙 -> 红 -> 透明
func _flame_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	g.set_color(1, Color(0.9, 0.25, 0.1, 0.0))
	g.add_point(0.35, Color(1.0, 0.62, 0.16, 0.95))
	g.add_point(0.7, Color(0.85, 0.3, 0.08, 0.5))
	return g

func _build_light() -> void:
	# 暖橙色的光晕：傍晚在野地里远远就能看见，走近了周围一圈都被烘成暖色。
	# texture_scale 决定光晕大小（2.4 -> 直径约 300 像素，差不多 19 格的草地都亮起来），
	# energy 轻微抖动 = 火在跳，不是死灯。
	_light = LIGHT_UTIL.make_light(Color(1.0, 0.68, 0.36), 1.5, 2.4)
	_light.position = Vector2(0, -6)
	add_child(_light)
	# e31 火堆本体的可见柔光（加法混合）：PointLight2D 只把周围"染色"、自己不发光，
	#   夜里远看根本找不到光源在哪。叠这层加法柔光才像"这儿有一团火"。
	_glow = LIGHT_UTIL.make_glow(Color(1.0, 0.62, 0.30, 0.24), 2.9)
	_glow.position = Vector2(0, -6)
	add_child(_glow)
	# 亮度和柔光一起抖：同一条 tween 上并排跑，火苗的明暗才对得上
	_tw = create_tween().set_loops()
	_tw.tween_property(_light, "energy", 1.15, 0.24).set_trans(Tween.TRANS_SINE)
	_tw.parallel().tween_property(_glow, "modulate:a", 0.17, 0.24).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(_light, "energy", 1.6, 0.31).set_trans(Tween.TRANS_SINE)
	_tw.parallel().tween_property(_glow, "modulate:a", 0.30, 0.31).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(_light, "energy", 1.32, 0.19).set_trans(Tween.TRANS_SINE)
	_tw.parallel().tween_property(_glow, "modulate:a", 0.22, 0.19).set_trans(Tween.TRANS_SINE)

# ---------------- 招募之前：火边先站着一个等你的人 ----------------
# ❗「招之前就能看清他」是这一版的重点之一：火边站着的这位、面板信息卡里的数据
#   （名字/兵种/血量/口味），跟招进来之后**是同一个人** ——
#   用的号码都是 Slaves.count（下一个名额），脸走 slave_npc.model_for / build_frames。
func _build_visitor() -> void:
	_visitor = _make_person(Slaves.count)
	if _visitor == null:
		return
	_visitor.name = "Visitor"
	_visitor.position = Vector2(-17, 2)          # 火堆左手边
	var spr := _visitor.get_node_or_null("Body")
	if spr != null:
		spr.play(&"idle_side")                   # 面朝右边的火堆
	add_child(_visitor)

# 按伙伴序号拼一个静止的人（跟白天在农场跑的那个伙伴同一套模型/配色）。
# e29c: 个人配色（发色/服装）已烘进贴图层 —— 静态 build_frames(model, idx) 直调，
# 有了改色贴图就不再需要 tint modulate 那一层。
# 返回的 Node2D 下挂一个叫 "Body" 的 AnimatedSprite2D；贴图造不出来时返回 null。
func _make_person(idx: int) -> Node2D:
	var frames: SpriteFrames = NPC_SCRIPT.build_frames(NPC_SCRIPT.model_for(idx), idx)
	if frames == null:
		return null
	var holder := Node2D.new()
	var spr := AnimatedSprite2D.new()
	spr.name = "Body"
	spr.position = Vector2(0, -16)               # 原点在脚下，跟主角/伙伴一个约定
	spr.sprite_frames = frames
	holder.add_child(spr)
	return holder

# ---------------- 招募之后：把这人安顿在火边 ----------------
# ❗不能直接用 scene/slave_npc.gd 的实体：伙伴一到晚上就 visible=false（夜里隐形），
#   而篝火偏偏是傍晚才出现 —— 用它的火边根本没人。
#   这里只借它的「贴图拼法」画一个围火坐着的人，跟这堆火同生同灭。
func seat_someone() -> void:
	if recruited:
		return
	recruited = true
	if _sitter != null:
		return
	# 首选：火边等着的那个陌生人原地坐下（不换脸 —— 你看到的就是招到的那位）
	if _visitor != null:
		_sitter = _visitor
		_visitor = null
		_sitter.name = "Sitter"
		_sitter.position = Vector2(15, 3)        # 火堆右手边
		var spr := _sitter.get_node_or_null("Body")
		if spr != null:
			spr.position = Vector2(0, -13)       # 坐着，重心比站着低一点
			spr.flip_h = true                    # 面朝左边的火堆
			spr.play(&"idle_side")
		return
	# 兜底（小像没造出来时走老路）：现场拼一个新的人
	var idx: int = maxi(0, Slaves.count - 1)      # 刚招进来那位
	var person := _make_person(idx)
	if person == null:
		return
	_sitter = person
	_sitter.name = "Sitter"
	_sitter.position = Vector2(15, 3)
	var pspr := _sitter.get_node_or_null("Body")
	if pspr != null:
		pspr.position = Vector2(0, -13)
		pspr.flip_h = true
		pspr.play(&"idle_side")
	add_child(_sitter)

# ---------------- 交互 ----------------
func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		_do_interact()

# 按 F / 左键点「F 篝火」框共用这一段（e36i）
func _do_interact() -> void:
	if not player_in_range:
		return
	var panel := get_tree().get_first_node_in_group("campfire_panel")
	if panel != null:
		panel.open_panel()
