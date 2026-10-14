extends Control
# 实景事件舞台. 演员用真相源帧工厂, 玩家/伙伴原地冻结, 不改存档数据.
const NPC := preload("res://scene/slave_npc.gd")
const EMOTE := preload("res://scene/emote_bubble.gd")
const PROP := preload("res://scene/event_prop.gd")
const MARKS := {"l": Vector2(-3, 0), "ml": Vector2(-1, 0), "m": Vector2.ZERO,
	"mr": Vector2(1, 0), "r": Vector2(3, 0), "back_l": Vector2(-3, -2),
	"back_r": Vector2(3, -2), "entry_l": Vector2(-4, 2), "entry_r": Vector2(4, 2), "front": Vector2(0, 2)}
var _game: Node
var _player: Node2D
var _cam: Camera2D
var _event_cam: Camera2D
var _anchor := Vector2.ZERO
var _actors := {}
var _props := {}
var _restore_vis: Array = []
var _blackout: ColorRect
var _isolated := false
var _fast := false
var _skip := false
var _closed := false
var _bgm_pushed := false
var _ducked := false
var _cine_before := false
var _script: Array = []
var _step := 0
var _reserved := {}
var _camera_tween: Tween
var _clear_cache := {}
var _transition: Tween
var _title: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cs := get_tree().current_scene
	if cs != null and cs.is_in_group("game"):
		_game = cs
	elif Engine.has_meta("live_probe"):
		_game = get_tree().get_first_node_in_group("game")
	if _game != null:
		_player = _game.get("player")
		_cam = _player.get_node_or_null("Camera2D") if _player != null else null
	_fast = not SaveManager.enabled and not Engine.has_meta("event_rehearsal")
	_blackout = ColorRect.new()
	_blackout.color = Color(0.02, 0.02, 0.03, 0)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_blackout)
	_title = Label.new()
	_title.add_theme_font_override("font", preload("res://resources/font/IPix.ttf"))
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color("f5e6bb"))
	_title.add_theme_color_override("font_outline_color", Color("302b29"))
	_title.add_theme_constant_override("outline_size", 5)
	_title.position = Vector2(28, 24)
	add_child(_title)

func prepare(script: Array) -> void:
	_script = script

func _k() -> float:
	return 0.06 if _fast else 1.0

func request_skip() -> void:
	_skip = true

# 等待实际走完, 对话不会抢在演员到位之前弹出.
func execute(cmd: Dictionary, index: int = -1) -> void:
	_step = index
	var duration := fx(cmd)
	var kind := str(cmd.get("fx", cmd.get("cmd", "")))
	if kind == "bg":
		while not _skip and _transition != null and _transition.is_running():
			await get_tree().process_frame
	else:
		await _wait(duration)
	if kind in ["bg", "focus", "cam"]:
		while not _skip and _camera_tween != null and _camera_tween.is_running():
			await get_tree().process_frame
	while not _skip and _has_walkers():
		await get_tree().process_frame
	if _event_cam != null:
		_event_cam.force_update_scroll()

func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and not _skip:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _has_walkers() -> bool:
	for a: Dictionary in _actors.values():
		if not (a["path"] as Array).is_empty():
			return true
	return false

func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - Farm.grid_origin) / Farm.TILE_SIZE).floor())

func _world(c: Vector2i) -> Vector2:
	return Farm.grid_origin + (Vector2(c) + Vector2(0.5, 0.5)) * Farm.TILE_SIZE

func _clear_cell(c: Vector2i) -> bool:
	if _clear_cache.has(c):
		return _clear_cache[c]
	var clear: bool = not (_game.is_water(c) and not _game.is_bridge_cell(c) and not _game.is_deck_cell(c))
	clear = clear and not Trees.is_blocked(c) and not OreVein.is_blocked(c) and not Structures.is_blocked(c)
	if clear:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = _world(c)
		query.collision_mask = 1
		query.collide_with_areas = false
		if _player is CollisionObject2D:
			query.exclude = [_player.get_rid()]
		clear = _player.get_world_2d().direct_space_state.intersect_point(query).is_empty()
	_clear_cache[c] = clear
	return clear

func _pick_anchor(key: String) -> Vector2:
	var base: Vector2 = _player.global_position
	var node: Node2D
	match key.trim_prefix("_").get_slice("_", 0):
		"harbor", "beach", "docks", "navy", "pact", "coast":
			node = _game.get("dock")
			if node != null:
				base = node.global_position + Vector2(-4, 1) * Farm.TILE_SIZE
		"camp", "ally", "lord", "war", "lost", "unify", "cliff":
			node = _game.get("campfire")
			if node == null:
				node = _game.get_node_or_null("House")
			if node != null:
				base = node.global_position + Vector2(0, 3) * Farm.TILE_SIZE
		"goblin", "river":
			node = _game.get_node_or_null("Merchant")
			if node != null:
				base = node.global_position + Vector2(-3, 3) * Farm.TILE_SIZE
		"house", "homestead", "workshop", "village", "siege":
			node = _game.get_node_or_null("House")
			if node != null:
				base = node.global_position + Vector2(0, 4) * Farm.TILE_SIZE
		"field", "garden", "mine":
			base = _game._field_center()
	# 找连续空地, 站位和进场路线必须属于同一片地面.
	var origin := _cell(base)
	for radius in range(0, 22):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := origin + Vector2i(dx, dy)
				var clear := true
				for x in range(-4, 5):
					for y in range(-2, 3):
						if not _clear_cell(c + Vector2i(x, y)):
							clear = false
							break
					if not clear:
						break
				if clear:
					return _world(c)
	return _world(origin)

func _mark(at: Variant) -> Vector2:
	var offset: Vector2 = Vector2.ZERO
	if at is Array:
		offset = Vector2(float(at[0]), float(at[1]))
	else:
		offset = MARKS.get(str(at), Vector2.ZERO)
	return _anchor + offset * Farm.TILE_SIZE

func _safe_mark(at: Variant, who: String) -> Vector2:
	var c := _cell(_mark(at))
	for r in range(0, 12):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t := c + Vector2i(dx, dy)
				if _clear_cell(t) and (not _reserved.has(t) or _reserved[t] == who):
					_reserved[t] = who
					return _world(t)
	return _mark(at)

func _actor(who: String) -> Node2D:
	return _actors[who]["node"] if _actors.has(who) else null

func _make_actor(who: String) -> Node2D:
	if _actors.has(who):
		return _actor(who)
	if _game == null:
		return null
	var root := Node2D.new()
	root.name = "EventActor_" + who
	var visual: Node2D
	if who == "you":
		var body: AnimatedSprite2D = _player.get("body_sprite")
		visual = body.duplicate() as AnimatedSprite2D
	elif who == "goblin":
		var merchant := _game.get_node_or_null("Merchant/Sprite2D") as Sprite2D
		if merchant == null:
			root.free()
			return null
		visual = merchant.duplicate() as Sprite2D
		visual.position = Vector2(0, -1) * Farm.TILE_SIZE
	else:
		var idx := int(who.trim_prefix("s"))
		if not who.begins_with("s") or idx < 0 or idx >= Slaves.ROSTER.size():
			root.free()
			return null
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = NPC.build_frames(NPC.model_for(idx), idx)
		spr.position = NPC.BODY_OFFSET
		spr.scale = NPC.body_scale_for(idx)
		visual = spr
	root.add_child(visual)
	var shadow := preload("res://scene/shadow_util.gd").make_shadow(18, 7, 0.28)
	shadow.position = Vector2(0, -7)
	root.add_child(shadow)
	root.move_child(shadow, 0)
	_game.add_child(root) # 直接挂 Game, 脚底原点参与 y_sort.
	_actors[who] = {"node": root, "visual": visual, "facing": "down", "path": []}
	visual.visible = true
	_pose(who, false)
	return root

func _pose(who: String, walking: bool) -> void:
	var a: Dictionary = _actors[who]
	var visual: Node2D = a["visual"]
	var dir := str(a["facing"])
	if visual is AnimatedSprite2D:
		var prefix := ("run" if walking else "normal") if who == "you" else ("walk" if walking else "idle")
		var suffix := "side" if dir in ["left", "right"] else dir
		var animation := StringName(prefix + "_" + suffix)
		if visual.sprite_frames.has_animation(animation):
			visual.play(animation)
		visual.flip_h = dir == "left"
	elif visual is Sprite2D:
		visual.flip_h = dir == "left"

func _face(who: String, direction: Vector2) -> void:
	if not _actors.has(who) or direction == Vector2.ZERO:
		return
	_actors[who]["facing"] = ("right" if direction.x > 0 else "left") if absf(direction.x) > absf(direction.y) else ("down" if direction.y > 0 else "up")
	_pose(who, false)

# 四向路线不斜穿树木/水面. 无路时报告并停住, 不瞬移穿帮.
func _route(start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return []
	var todo: Array[Vector2i] = [start]
	var came := {start: start}
	var head := 0
	while head < todo.size() and head < 1800:
		var c: Vector2i = todo[head]
		head += 1
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var t: Vector2i = c + d
			if came.has(t) or not _clear_cell(t) or (Vector2(t - start).length() > 24):
				continue
			came[t] = c
			if t == goal:
				var path: Array = []
				while t != start:
					path.push_front(_world(t))
					t = came[t]
				return path
			todo.append(t)
	push_warning("事件走位无路: %s -> %s" % [start, goal])
	return []

func _process(delta: float) -> void:
	if _closed:
		return
	for who: String in _actors:
		var a: Dictionary = _actors[who]
		var path: Array = a["path"]
		var budget := delta * 38.0 / _k()
		while not path.is_empty() and budget > 0:
			var n: Node2D = a["node"]
			var diff: Vector2 = path[0] - n.global_position
			_face(who, diff)
			_pose(who, true)
			var distance := diff.length()
			n.global_position = n.global_position.move_toward(path[0], budget)
			budget -= distance
			if n.global_position.distance_to(path[0]) < 0.01:
				path.pop_front()
		if path.is_empty():
			_pose(who, false)

func fx(cmd: Dictionary) -> float:
	var kind := str(cmd.get("fx", cmd.get("cmd", "")))
	if _game == null:
		return 0.0
	match kind:
		"bg":
			var tb := create_tween()
			_transition = tb
			tb.tween_property(_blackout, "color:a", 1.0, 0.28 * _k())
			tb.tween_callback(func(): _title.text = str(cmd.get("title", "")))
			tb.tween_callback(func(): _enter_stage(str(cmd.get("scene", "camp"))))
			tb.tween_interval(0.12 * _k())
			tb.tween_property(_blackout, "color:a", 0.0, 0.4 * _k())
			return 0.82 * _k()
		"show":
			var who := str(cmd.get("who", "you"))
			var n := _make_actor(who)
			if n != null:
				n.visible = true
				if cmd.has("from"):
					_actors[who]["path"] = _route(_cell(n.global_position), _cell(_safe_mark(cmd.get("at", "m"), who)))
			return 0.0
		"move":
			var who := str(cmd.get("who", "you"))
			var n := _actor(who)
			if n != null:
				_reserved.erase(_cell(n.global_position))
				_actors[who]["path"] = _route(_cell(n.global_position), _cell(_safe_mark(cmd.get("to", cmd.get("at", "m")), who)))
		"hide":
			var who := str(cmd.get("who", "all"))
			for k: String in _actors:
				if who == "all" or who == k:
					_actor(k).visible = false
		"face":
			var who := str(cmd.get("who", "you"))
			var n := _actor(who)
			var target := _actor(str(cmd.get("target", "")))
			if n != null:
				if target != null:
					_face(who, target.global_position - n.global_position)
				else:
					_actors[who]["facing"] = str(cmd.get("dir", "down"))
					_pose(who, false)
		"act", "emote":
			var who := str(cmd.get("who", "you"))
			var n := _actor(who)
			var pose := str(cmd.get("pose", "bob"))
			if n != null:
				var emotion := str(cmd.get("kind", {"bob": "...", "nod": "note", "jump": "!", "wave": "note"}.get(pose, "...")))
				EMOTE.pop_over(n, emotion, 1.2 * _k(), 26.0)
				if pose in ["nod", "jump"]:
					var visual: Node2D = _actors[who]["visual"]
					var start_y := visual.position.y
					var tw := create_tween()
					tw.tween_property(visual, "position:y", start_y - (3.0 if pose == "jump" else -1.0), 0.15 * _k())
					tw.tween_property(visual, "position:y", start_y, 0.2 * _k())
			return 0.5 * _k()
		"focus", "cam":
			var target: Vector2 = _anchor
			var n := _actor(str(cmd.get("who", "")))
			if n != null:
				target = _anchor.lerp(n.global_position, 0.25)
			_pan_to(target, float(cmd.get("dur", 0.6)))
			return float(cmd.get("dur", 0.6)) * _k()
		"wait":
			return float(cmd.get("t", 0.5)) * _k()
		"prop":
			var key := str(cmd.get("id", "object"))
			if _props.has(key):
				_props[key].queue_free()
			var p := PROP.new()
			p.kind = str(cmd.get("kind", "letter"))
			_game.add_child(p)
			p.global_position = _mark(cmd.get("at", "m"))
			_props[key] = p
		"give":
			var key := str(cmd.get("id", "object"))
			var n := _actor(str(cmd.get("to", "you")))
			if _props.has(key) and n != null:
				var tw := create_tween()
				tw.tween_property(_props[key], "global_position", n.global_position + Vector2(0, -0.6) * Farm.TILE_SIZE, 0.45 * _k())
			return 0.6 * _k()
		"sfx":
			Audio.play_sfx(str(cmd.get("name", "ui_click")))
		"bgm":
			if _bgm_pushed:
				Audio.pop_bgm()
			Audio.push_bgm(str(cmd.get("key", "")))
			_bgm_pushed = true
		"bgm_off":
			if _bgm_pushed:
				Audio.pop_bgm()
				_bgm_pushed = false
		"duck":
			if not _ducked:
				Audio.duck()
				_ducked = true
		"unduck":
			if _ducked:
				Audio.unduck()
				_ducked = false
	return 0.0

func _pan_to(target: Vector2, duration: float) -> void:
	if _event_cam == null:
		return
	if _camera_tween != null and _camera_tween.is_running():
		_camera_tween.kill()
	# 正文占下方 32%, 演员摆在上方可见区域中央.
	var min_y := 0.0
	var max_y := 0.0
	for a: Dictionary in _actors.values():
		var relative: Vector2 = a["node"].global_position - _anchor
		min_y = minf(min_y, relative.y)
		max_y = maxf(max_y, relative.y)
	var group_shift := (min_y + max_y) * 0.5 - Farm.TILE_SIZE
	var center := target + Vector2(0, group_shift + get_viewport_rect().size.y * 0.16 / _event_cam.zoom.y)
	_camera_tween = create_tween()
	_camera_tween.tween_property(_event_cam, "global_position", center, maxf(0.01, duration * _k()))

func _enter_stage(scene_key: String) -> void:
	_isolate()
	for a: Dictionary in _actors.values():
		a["node"].queue_free()
	_actors.clear()
	for p: Node2D in _props.values():
		p.queue_free()
	_props.clear()
	_reserved.clear()
	_clear_cache.clear()
	_anchor = _pick_anchor(scene_key)
	var dressing := {"camp": "fire", "workshop": "bench", "field": "garden", "garden": "garden"}
	if dressing.has(scene_key):
		var p := PROP.new()
		p.kind = dressing[scene_key]
		_game.add_child(p)
		p.global_position = _mark([0, -1.5])
		_props["setting"] = p
	# 每幕首次 show 在黑幕后摆好, 只让明确指定 from 的演员走进场.
	var end := _script.size()
	for i in range(_step + 1, _script.size()):
		if str(_script[i].get("fx", "")) == "bg":
			end = i
			break
	for i in range(_step + 1, end):
		var st: Dictionary = _script[i]
		if str(st.get("fx", "")) != "show":
			continue
		var who := str(st.get("who", "you"))
		if _actors.has(who):
			continue
		var n := _make_actor(who)
		if n != null:
			n.global_position = _safe_mark(st.get("from", st.get("at", "m")), who)
			_face(who, _anchor - n.global_position)
	# 清掉遮住演员上半身的近景树冠, 只动显示, 收台恢复.
	var cast_rect := Rect2(_anchor - Vector2(5, 5) * Farm.TILE_SIZE, Vector2(10, 7) * Farm.TILE_SIZE)
	for tree: Node2D in _game.get("tree_nodes").values():
		if is_instance_valid(tree) and cast_rect.has_point(tree.global_position):
			_remember(tree)
			tree.hide()
	_pan_to(_anchor, 0.01)

func _remember(n: Node) -> void:
	for r: Dictionary in _restore_vis:
		if r["node"] == n:
			return
	_restore_vis.append({"node": n, "vis": n.visible if n is CanvasItem else true, "mode": n.process_mode})

func _isolate() -> void:
	if _isolated or _game == null:
		return
	_isolated = true
	_cine_before = bool(_game.get("_cine_busy"))
	_game.set("_cine_busy", true)
	_game._set_player_frozen(true)
	var nodes: Array = [_player]
	nodes.append_array(_game.get("slave_nodes"))
	for key in ["Merchant", "Critters", "PortLife"]:
		var n := _game.get_node_or_null(key)
		if n != null:
			nodes.append(n)
	var fire: Node = _game.get("campfire")
	if fire != null:
		for key in ["_visitor", "_sitter"]:
			var visitor: Node = fire.get(key)
			if visitor != null:
				nodes.append(visitor)
	# 保留故事面板, 隐藏时钟/钱包/任务卡和公告, 不让 UI 混进镜头.
	var hud: Node = _game.get("hud")
	if hud != null:
		for n: Node in hud.get_children():
			if n != get_parent() and n is CanvasItem:
				nodes.append(n)
	for label: Node in _game.find_children("*", "Label", true, false):
		if not get_parent().is_ancestor_of(label):
			nodes.append(label)
	for n: Node in nodes:
		if n == null or not is_instance_valid(n):
			continue
		_remember(n)
		n.process_mode = Node.PROCESS_MODE_DISABLED
		if n is CanvasItem:
			n.visible = false
	_event_cam = Camera2D.new()
	_event_cam.zoom = Vector2(3, 3)
	_game.add_child(_event_cam)
	_event_cam.make_current()

func _restore_all() -> void:
	if not _isolated:
		return
	for a: Dictionary in _actors.values():
		if is_instance_valid(a["node"]):
			a["node"].queue_free()
	_actors.clear()
	for p: Node2D in _props.values():
		if is_instance_valid(p):
			p.queue_free()
	_props.clear()
	for r: Dictionary in _restore_vis:
		if is_instance_valid(r["node"]):
			r["node"].process_mode = r["mode"]
			if r["node"] is CanvasItem:
				r["node"].visible = r["vis"]
	_restore_vis.clear()
	if is_instance_valid(_cam) and _cam.is_inside_tree() and _cam.enabled:
		_cam.make_current()
		_cam.reset_smoothing()
	if is_instance_valid(_event_cam):
		_event_cam.queue_free()
	_event_cam = null
	_game.set("_cine_busy", _cine_before)
	_isolated = false

func close_stage() -> float:
	if _closed:
		return 0.0
	_closed = true
	if _transition != null and _transition.is_running():
		_transition.kill()
	if _camera_tween != null and _camera_tween.is_running():
		_camera_tween.kill()
	_title.hide()
	if _bgm_pushed:
		Audio.pop_bgm()
		_bgm_pushed = false
	if _ducked:
		Audio.unduck()
		_ducked = false
	if _game == null:
		return 0.0
	var tw := create_tween()
	tw.tween_property(_blackout, "color:a", 1.0, 0.25 * _k())
	tw.tween_callback(_restore_all)
	tw.tween_property(_blackout, "color:a", 0.0, 0.35 * _k())
	return 0.65 * _k()

func _exit_tree() -> void:
	_restore_all()
	if _bgm_pushed:
		Audio.pop_bgm()
	if _ducked:
		Audio.unduck()

