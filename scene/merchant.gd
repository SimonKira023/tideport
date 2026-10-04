# merchant.gd —— 商人 NPC（哥布林摊位）
# 走近按 F 打开「交易面板」（shop_ui.gd）：买种子 / 把作物卖掉。
# 开局开场白不在摊位触发 —— 改在玩家第一次进屋时播（house.gd _try_intro）。
extends Area2D

@onready var sprite: Sprite2D = $Sprite2D

const FRAME_TIME := 0.35      # 待机动画每帧停留时间（秒）

var player_in_range := false
var _frame_count := 1
var _timer := 0.0
var _gaze_t := 2.0      # e54: 下一次张望（镜像翻转）还有多久
var _hop_t := 5.0       # e54: 下一次原地小跳还有多久
var _key_hint: Node2D = null         # 走近时浮在半空的「F 交易」提示

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_frame_count = maxi(sprite.hframes, 1)
	# e33 摊位脚下的影子
	var sh := preload("res://scene/shadow_util.gd").make_shadow(26, 8, 0.25)
	sh.position = Vector2(0, 2)
	add_child(sh)
	_build_key_hint()

# 提示挂在摊位上方一点，别压住哥布林的头
func _build_key_hint() -> void:
	_key_hint = preload("res://scene/key_hint.gd").new()
	_key_hint.setup("F", "交易", -62.0)
	_key_hint.connect("clicked", _do_interact)   # e36i: 左键点这个框 = 按 F（字符串写法, _key_hint 是 Node2D）
	add_child(_key_hint)

# 摊位待机动画（素材是 4 帧，只有哥布林头部有细微变化）
func _process(delta: float) -> void:
	if _frame_count <= 1:
		return
	_timer += delta
	if _timer >= FRAME_TIME:
		_timer = 0.0
		sprite.frame = (sprite.frame + 1) % _frame_count
	# e54 生命感：偶尔左右张望（镜像翻转），偶尔原地小跳一下 —— 摊位后有活物
	_gaze_t -= delta
	if _gaze_t <= 0.0:
		_gaze_t = randf_range(2.5, 5.5)
		if randf() < 0.45:
			sprite.flip_h = not sprite.flip_h
	_hop_t -= delta
	if _hop_t <= 0.0:
		_hop_t = randf_range(4.0, 9.0)
		var base_y := sprite.position.y
		var tw := create_tween()
		tw.tween_property(sprite, "position:y", base_y - 3.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(sprite, "position:y", base_y, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true
		_key_hint.show_hint()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
		_key_hint.hide_hint()

# 按 F：开场白已播过（靠近时自动触发）就先来一句招呼，说完才开面板。
# 关面板由 shop_ui 自己在 _input 里处理（它会把事件吃掉，
# 所以这里不会再收到「同一按 F」，不会出现关了又开）。
func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		_do_interact()

# 按 F / 左键点「F 交易」框共用这一段（e36i）
func _do_interact() -> void:
	if not player_in_range:
		return
	var dlg := get_tree().get_first_node_in_group("story_dialogue")
	if dlg != null and dlg.is_open():
		return                     # 开场白还在放，按键让对话框处理
	if dlg != null:
		dlg.play(_shop_lines(), _open_shop)
	else:
		_open_shop()

# 进店招呼：随机一句（首次的完整开场白在 house.gd 的 _try_intro 里已播过）
func _shop_lines() -> Array:
	var idle := [
		"嘿嘿, 又来送钱啦? 快看看今天的货!",
		"招呼生意要紧, 您里边请!",
		"金银财宝的味道, 就是这个味儿!",
		"想要什么? 我这儿的种子可新鲜了!",
	]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return [{"name": "哥布林", "portrait": "goblin",
		"text": idle[rng.randi_range(0, idle.size() - 1)]}]

func _open_shop() -> void:
	var shop := get_tree().get_first_node_in_group("shop")
	if shop != null:
		shop.open_panel()
	else:
		_show_feedback("交易面板不见了...")

# 出错/兜底时的一次性飘字（跟常驻提示分开：这种说完就该走）
func _show_feedback(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(-60, -40)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", -70.0, 1.2)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.2)
	tween.tween_callback(label.queue_free)
