# world_director.gd —— P2 世界演出导演（PLAN_CUTE_STYLE.md 第 2 期）
#
# 跟 Cutscenes 的分工（红线，别合并）:
#   · Cutscenes = 世界外的舞台剧: 全黑幕 + 天幕海面 + 剪影, 播的时候世界整个被盖住。
#   · 本导演    = 世界内的实机演出: 像素小人就在岛上走位、说话、冒气泡, 镜头摇过去拍。
#
# 剧本 = 一排步骤 (JSON 数组), 每步一个 {"do": ...} 指令, 顺序执行、可 Esc 整段跳过:
#   {"do":"enter","who":"阿鲤","model":0,"at":[24,26],"speed":34}   # 造一个提线小人进场
#   {"do":"walk", "who":"阿鲤","to":[30,28]}                        # 走到格子
#   {"do":"walk", "who":"阿鲤","to_who":"player"}                   # 走到玩家面前 1 格
#   {"do":"face", "who":"阿鲤","dir":"down"}                        # down/up/left/right
#   {"do":"emote","who":"阿鲤","kind":"heart","dur":1.2}            # P1 情绪气泡
#   {"do":"say",  "who":"阿鲤","portrait":0,"lines":["...","..."]}  # 对话框(玩家点着推进)
#                 "auto":1.6                                        # 或自动关(演出旁白/探针)
#   {"do":"cam",  "to":"阿鲤","dur":0.7}                            # 镜头摇过去("player"摇回)
#   {"do":"shake","amp":5.0,"dur":0.5}
#   {"do":"sfx",  "name":"blip"}
#   {"do":"wait", "sec":1.0}
#   {"do":"exit", "who":"阿鲤"}                                     # 淡出收人(省略则收尾清场)
#
# 演出期间: 时间暂停(push_ui_pause) + 玩家冻结 + letterbox + 相机归导演管；
# 收尾全部原样还回去。提线小人(puppet)不是真伙伴 —— 纯演出道具, 不进存档不干
# 活不跑 AI, 用 slave_npc 的帧工厂画出来, 走位自带水检(不下水)。
#
# 用法:
#   game.world_director.play_id("demo_arrival")     # 播 data/world_scenes/<id>.json
#   await game.world_director.finished
#   game.world_director.cmd({"do":"emote", ...})    # 单步也行(P2.5 别的模块来凑戏)
extends Node

signal finished
signal step_started(index: int, st: Dictionary)

const NPC := preload("res://scene/slave_npc.gd")
const EMOTE := preload("res://scene/emote_bubble.gd")
const PORTRAIT_DIR := "res://resources/texture/portraits/"   # P3 起头像统一走 mood_portrait.gd（key = 文件名）
const FACES: Array[String] = ["down", "up", "left", "right"]
const STAND_DIST := 14.0        # walk to_who 时停在目标面前多远
const CAM_LIMIT := Vector2(430, 270)   # 镜头别摇出屏幕太远（照抄 _cinematic_pan 的口径）

var _game = null                # Game（故意不标类型, 走动态派发拿私有工具, 项目惯例）
var _busy := false
var _skip := false
var _actors := {}               # who -> {"node":Node2D, "spr":AnimatedSprite2D, "facing":String, "speed":float}
var _box = null                 # say 打开的对话框（dialog_box.gd）
var _box_layer: CanvasLayer = null   # 对话框专属层 —— ❗不能直接挂 game 下:
                                      # game 开着 y_sort, 全屏 Control 会被按 y 排到实体后面

func busy() -> bool:
	return _busy

func setup(game) -> void:
	_game = game

# ---------------- 剧本校验（纯函数, 自检直接调） ----------------
# 返回错误清单；空 = 可播。who 的坑: "player" 是保留名（玩家本尊, 不用 enter）。
static func validate(steps: Array) -> Array:
	var errs: Array = []
	var cast := {}
	for i in steps.size():
		var st_v: Variant = steps[i]
		if st_v is Dictionary:
			var st: Dictionary = st_v
			var d := String(st.get("do", ""))
			match d:
				"enter":
					if not st.has("who") or not st.has("at"):
						errs.append("第%d步 enter 缺 who/at" % i)
					cast[String(st.get("who", ""))] = true
				"walk":
					if not cast.has(String(st.get("who", ""))):
						errs.append("第%d步 walk 的 who(%s) 还没进场" % [i, st.get("who", "?")])
					if not st.has("to") and not st.has("to_who"):
						errs.append("第%d步 walk 缺 to/to_who" % i)
					elif st.has("to_who"):
						var t := String(st["to_who"])
						if t != "player" and not cast.has(t):
							errs.append("第%d步 walk 的 to_who(%s) 还没进场" % [i, t])
				"face":
					if not cast.has(String(st.get("who", ""))):
						errs.append("第%d步 face 的 who 还没进场" % i)
					if not FACES.has(String(st.get("dir", ""))):
						errs.append("第%d步 face 的 dir 必须是 down/up/left/right" % i)
				"emote":
					if not cast.has(String(st.get("who", ""))) and String(st.get("who", "")) != "player":
						errs.append("第%d步 emote 的 who 还没进场" % i)
					if not EMOTE.ICON_MAP.has(String(st.get("kind", ""))):
						errs.append("第%d步 emote 的 kind(%s) 不在 ICON_MAP 里" % [i, st.get("kind", "?")])
				"say":
					if String(st.get("who", "")) == "":
						errs.append("第%d步 say 缺 who" % i)
					var lines: Variant = st.get("lines", null)
					if lines is Array and (lines as Array).is_empty():
						errs.append("第%d步 say 的 lines 是空的" % i)
				"cam":
					if not st.has("to"):
						errs.append("第%d步 cam 缺 to" % i)
				"shake":
					pass
				"sfx":
					if String(st.get("name", "")) == "":
						errs.append("第%d步 sfx 缺 name" % i)
				"wait":
					if not st.has("sec"):
						errs.append("第%d步 wait 缺 sec" % i)
				"exit":
					if not cast.has(String(st.get("who", ""))):
						errs.append("第%d步 exit 的 who 还没进场" % i)
				_:
					errs.append("第%d步未知指令 %s" % [i, d])
		else:
			errs.append("第%d步不是字典" % i)
	return errs

static func load_id(id: String) -> Array:
	var txt := FileAccess.get_file_as_string("res://data/world_scenes/%s.json" % id)
	if txt.is_empty():
		push_error("world_director: 剧本 %s 读不到" % id)
		return []
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Array:
		return parsed
	push_error("world_director: 剧本 %s 不是 JSON 数组" % id)
	return []

# ---------------- 播放 ----------------
func play_id(id: String) -> void:
	play_script(load_id(id))

func play_script(steps: Array) -> void:
	if _busy:
		push_warning("world_director: 已经在演了, 这份剧本被丢掉")
		return
	var errs := validate(steps)
	if not errs.is_empty():
		push_error("world_director: 剧本校验失败 %s" % [errs])
		return
	_busy = true
	_skip = false
	_begin_stage()
	for i in steps.size():
		if _skip:
			break
		step_started.emit(i, steps[i])
		await cmd(steps[i])
	_end_stage()
	finished.emit()
	_busy = false

# 单步执行（play_script 内部走这里; 外部凑戏也可以直接 await cmd(...)）
func cmd(st: Dictionary) -> void:
	match String(st.get("do", "")):
		"enter":
			_i_enter(st)
		"walk":
			await _i_walk(st)
		"face":
			_i_face(st)
		"emote":
			_i_emote(st)
		"say":
			await _i_say(st)
		"cam":
			await _i_cam(st)
		"shake":
			if _game != null:
				_game.shake_screen(float(st.get("amp", 5.0)), float(st.get("dur", 0.5)))
			await _wait(0.2)
		"sfx":
			Audio.play_sfx(String(st.get("name", "blip")), -6.0)
		"wait":
			await _wait(float(st.get("sec", 1.0)))
		"exit":
			await _i_exit(st)

# ---------------- 开场 / 收尾（时间、玩家、镜头的接管与归还） ----------------
func _begin_stage() -> void:
	if _game == null:
		return
	TimeManager.push_ui_pause()
	_game.call("_set_player_frozen", true)
	_game.set("_cine_busy", true)     # 前视偏移让位, 相机 offset 归导演
	_game.call("_letterbox", true)

func _end_stage() -> void:
	if _box != null and is_instance_valid(_box):
		_box.close()
	_box = null
	if _box_layer != null and is_instance_valid(_box_layer):
		_box_layer.queue_free()
	_box_layer = null
	# 提线小人统一淡出收场（exit 过的已经不在表里）
	for who in _actors.keys():
		var a: Dictionary = _actors[who]
		var n: Node2D = a["node"]
		if is_instance_valid(n):
			var tw := create_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.35)
			tw.tween_callback(n.queue_free)
	_actors.clear()
	if _game == null:
		return
	# 相机还回去（不 await, 收尾本来就是快速连续的一串）
	var pl: Node2D = _game.get("player")
	if pl != null and is_instance_valid(pl):
		var cam := pl.get_node_or_null("Camera2D") as Camera2D
		if cam != null:
			var tw := create_tween()
			tw.tween_property(cam, "offset", Vector2.ZERO, 0.4) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_game.call("_letterbox", false)
	_game.set("_cine_busy", false)
	_game.call("_set_player_frozen", false)
	TimeManager.pop_ui_pause()

# ---------------- 各指令 ----------------
func _i_enter(st: Dictionary) -> void:
	var who := String(st["who"])
	var at: Array = st["at"]
	var model := int(st.get("model", 0))
	var root := Node2D.new()
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = NPC.build_frames(NPC.model_for(model), model)
	spr.position = NPC.BODY_OFFSET
	spr.scale = NPC.body_scale_for(model)
	root.add_child(spr)
	_game.add_child(root)
	root.global_position = _cell_center(Vector2i(int(at[0]), int(at[1])))
	spr.play(&"idle_down")
	_actors[who] = {
		"node": root, "spr": spr, "facing": "down",
		"speed": float(st.get("speed", 30.0)),
	}

func _i_walk(st: Dictionary) -> void:
	var who := String(st["who"])
	if not _actors.has(who):
		return
	var a: Dictionary = _actors[who]
	var node: Node2D = a["node"]
	var dest := Vector2.ZERO
	if st.has("to"):
		var to: Array = st["to"]
		dest = _cell_center(Vector2i(int(to[0]), int(to[1])))
	else:
		var target := _pos_of(String(st["to_who"]))
		if target == Vector2.INF:
			return
		var dir := (target - node.global_position).normalized()
		dest = target - dir * STAND_DIST
	a["speed"] = float(st.get("speed", a["speed"]))
	var guard := 0          # 兜底: 被水堵死 4 秒就放弃, 绝不把演出卡死
	while not _skip:
		var step := _step_actor(a, dest, get_process_delta_time())
		if step != 0:
			break
		guard += 1
		if guard > 240:
			break
		await get_tree().process_frame
	_play_facing(a, "idle")

func _i_face(st: Dictionary) -> void:
	if not _actors.has(String(st["who"])):
		return
	var a: Dictionary = _actors[String(st["who"])]
	a["facing"] = String(st["dir"])
	_play_facing(a, "idle")

func _i_emote(st: Dictionary) -> void:
	var who := String(st["who"])
	var host: Node2D = null
	if who == "player":
		host = _pos_node("player")
	elif _actors.has(who):
		host = _actors[who]["node"]
	if host != null and host.is_inside_tree():
		EMOTE.pop_over(host, String(st.get("kind", "!")), float(st.get("dur", 1.4)), 26.0)
	await _wait(minf(float(st.get("dur", 1.4)) * 0.6, 1.0))

func _i_say(st: Dictionary) -> void:
	var who := String(st["who"])
	var lines: Array = st.get("lines", ["..."])
	# 头像: portrait 是伙伴序号(0..) -> slave_XX key, 没有就退玩家（跟 dialogue_ui 同口径）
	# P3: 走像素 Q 版差分管线; 剧本可带 "moods": ["happy","shy"] 逐段换表情
	var key := "player"
	if st.has("portrait"):
		var k := "slave_%02d" % int(st["portrait"])
		if preload("res://scene/mood_portrait.gd").portrait_texture(k) != null:
			key = k
	var moods: Array = st.get("moods", [])
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	if _box_layer == null or not is_instance_valid(_box_layer):
		_box_layer = CanvasLayer.new()
		_box_layer.layer = 90          # 游戏画面之上、letterbox(99)之下
		_game.add_child(_box_layer)
	_box = preload("res://dialog_box.gd").new()
	_box_layer.add_child(_box)
	_box.open_key(key, who, lines.duplicate(), moods)
	if st.has("auto"):
		# 自动关（探针/旁白用）: 到点自己点掉, 每段都点
		var rep := float(st["auto"])
		for i in lines.size():
			if _skip:
				break
			await _wait(rep)
			if _skip:
				break
			if _box != null and is_instance_valid(_box) and _box.visible:
				_box._advance_or_close()
		# 最后一段 advance 可能已关; 没关(比如玩家手快抢先点了)就直接收
		if _box != null and is_instance_valid(_box) and _box.visible:
			_box.close()
	else:
		# 玩家点着推进。框可能已被 Esc 关掉（_unhandled_input 先把 _skip 置了）,
		# 那就别 await —— 不然这个信号永远不来, 演出卡死在这。
		if _box != null and is_instance_valid(_box) and _box.visible:
			await _box.closed
	if _skip and _box != null and is_instance_valid(_box):
		_box.close()
	_box = null

func _i_cam(st: Dictionary) -> void:
	var pl: Node2D = _pos_node("player")
	if pl == null:
		return
	var cam := pl.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	var dur := float(st.get("dur", 0.7))
	var target := Vector2.INF
	var to: Variant = st["to"]
	if to is Array:
		target = _cell_center(Vector2i(int(to[0]), int(to[1])))
	else:
		target = _pos_of(String(to))
	if target == Vector2.INF:
		return
	var off: Vector2 = (target - pl.global_position).clamp(-CAM_LIMIT, CAM_LIMIT)
	if String(to) == "player" or off.length() < 2.0:
		off = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(cam, "offset", off, maxf(0.05, dur)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished

func _i_exit(st: Dictionary) -> void:
	var who := String(st["who"])
	if not _actors.has(who):
		return
	var a: Dictionary = _actors[who]
	_actors.erase(who)
	var n: Node2D = a["node"]
	if is_instance_valid(n):
		var tw := create_tween()
		tw.tween_property(n, "modulate:a", 0.0, float(st.get("fade", 0.4)))
		tw.tween_callback(n.queue_free)
		await tw.finished

# ---------------- 提线小人走位（照 slave_npc._step_toward 的口径抄的简化版） ----------------
# 返回 0=还在走 1=到了 2=被水堵死
func _step_actor(a: Dictionary, dest: Vector2, delta: float) -> int:
	var node: Node2D = a["node"]
	var to := dest - node.global_position
	if to.length() < 2.5:
		return 1
	var dir := to.normalized()
	var facing := _dir_name(dir)
	if facing != String(a["facing"]):
		a["facing"] = facing
	_play_facing(a, "walk")
	var next := node.global_position + dir * float(a["speed"]) * delta
	if _is_water(next):
		_play_facing(a, "idle")
		return 2
	node.global_position = next
	return 0

# 播朝向动画。❗素材只有 下/上/侧 三行 —— 左右共用 _side, 真左右靠 flip_h,
# 直接拼 walk_left 会撞上「动画不存在」（slave_npc 里踩过的同一个坑）。
func _play_facing(a: Dictionary, prefix: String) -> void:
	var facing := String(a["facing"])
	var an := prefix + ("_side" if facing == "left" or facing == "right" else "_" + facing)
	var spr: AnimatedSprite2D = a["spr"]
	if spr.sprite_frames.has_animation(StringName(an)):
		spr.play(StringName(an))
	spr.flip_h = facing == "left"

func _is_water(pos: Vector2) -> bool:
	if _game == null or not _game.has_method("is_water"):
		return false
	var local: Vector2 = pos - Farm.grid_origin
	return _game.is_water(Vector2i(floori(local.x / 16.0), floori(local.y / 16.0)))

func _cell_center(cell: Vector2i) -> Vector2:
	return Farm.grid_origin + Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)

func _dir_name(dir: Vector2) -> String:
	if absf(dir.x) >= absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"

# "player" -> 玩家节点; 其余查提线小人表
func _pos_node(who: String) -> Node2D:
	if _game == null:
		return null
	if who == "player":
		return _game.get("player")
	if _actors.has(who):
		return _actors[who]["node"]
	return null

func _pos_of(who: String) -> Vector2:
	var n := _pos_node(who)
	return n.global_position if n != null else Vector2.INF

# 等待: 0.1s 一片一片等, Esc 跳过能立刻接上
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec and not _skip:
		await get_tree().create_timer(0.1).timeout
		t += 0.1

# Esc = 整段跳过。对话框自己的 Esc 只关框（closed 信号把 say 步放行）,
# 这里再补一刀把后面所有步全部放完。
func _unhandled_input(event: InputEvent) -> void:
	if not _busy:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_skip = true
