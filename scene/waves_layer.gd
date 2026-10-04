extends Node2D
# 岸边白浪：沿「贴陆的水格」的贴陆边画一条会呼吸的白浪线，
# 相位按格子错开；浪线随呼吸往海里推进/退回，再补几个闪烁的泡沫点。
# 纯 _draw 实现，不依赖任何图集；贴着浅滩层（Z_SHORE）画在其上面。

var _game: Node2D = null
var _segs: Array = []       # [{c: Vector2i, n: Vector2i, phase: float}]
var _t := 0.0
var _acc := 0.0             # 重绘限帧累加器

const REDRAW_DT := 0.066    # 浪线 ~15fps 足够顺：慢呼吸动画不必每帧全量重画数千段

func setup(g: Node2D) -> void:
	_game = g
	z_index = g.Z_SHORE      # 与浅滩同层；节点排在 shore_layer 之后，同层后画 -> 盖在浅滩上
	_build()

# ❗段列表要在 setup 里建：_build_waves 是先 add_child 再 setup，
#   _ready 执行时 _game 还是 null，放 _ready 里一段都收不到。
func _build() -> void:
	var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	var bits := [1, 2, 4, 8]
	_segs.clear()
	# 主岛叫 _water_set, 海图(world_map)叫 _water —— 哪个在用取哪个
	var wset: Dictionary = _game._water_set if "_water_set" in _game else _game._water
	for c in wset.keys():
		var mask: int = _game._edge_mask(c, true)    # 哪几边贴着陆地
		if mask == 0:
			continue
		for i in 4:
			if mask & bits[i]:
				# 泡沫星点：每段预生成 3 个（沿切向位置/法向偏移/闪烁相位），_draw 里零哈希
				var dots: Array = []
				for k in 3:
					var hx: int = _game._hash2(c * 41 + Vector2i(i * 7 + k * 13, k * 31 + i * 5))
					var hy: int = _game._hash2(c * 57 + Vector2i(k * 23 + i * 3, i * 11 + k * 7))
					dots.append({
						"u": float(hx % 100) / 100.0,
						"v": float(hy % 100) / 100.0,
						"ph": float((hx + hy) % 628) / 100.0,
					})
				_segs.append({
					"c": c,
					"n": dirs[i],
					"phase": float(_game._hash2(c * 3 + Vector2i(i * 17, i * 29)) % 628) / 100.0,
					"dots": dots,
				})
	set_process(not _segs.is_empty())

func _process(delta: float) -> void:
	_t += delta
	_acc += delta
	if _acc < REDRAW_DT:
		return
	_acc = 0.0
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	if _game == null:
		return
	var origin: Vector2 = _game.grid_layer.position
	# 视口裁剪：只画相机视野内（外扩一格余量）的浪段，视野外的几千段直接跳过
	var cam := get_viewport().get_camera_2d()
	var vis := Rect2()
	if cam != null:
		var half: Vector2 = get_viewport_rect().size * 0.5 / cam.zoom + Vector2(32, 32)
		vis = Rect2(cam.get_screen_center_position() - half, half * 2.0)
	for s in _segs:
		var c: Vector2i = s["c"]
		var n: Vector2i = s["n"]
		var phase: float = s["phase"]
		var w := 0.5 + 0.5 * sin(_t * 1.6 + phase)
		var a := 0.08 + 0.55 * w * w
		var push := 1.0 + 2.6 * w          # 浪线离陆边的距离（往海里退）
		var center := origin + Vector2(c.x * 16 + 8, c.y * 16 + 8)
		if cam != null and not vis.has_point(center):
			continue
		var mid := center + Vector2(n) * (8.0 - push)
		var tang := Vector2(-n.y, n.x) * 6.0
		draw_line(mid + tang, mid - tang, Color(0.95, 0.99, 1.0, a), 2.0)
		# 碎沫带：主浪线外侧一条更短更淡的平行线，错相呼吸 —— 浪花的第二层
		var w2 := 0.5 + 0.5 * sin(_t * 1.6 + phase + 0.9)
		var mid2 := center + Vector2(n) * (8.0 - push - 2.6)
		var tang2 := Vector2(-n.y, n.x) * 3.6
		draw_line(mid2 + tang2, mid2 - tang2, Color(0.95, 0.99, 1.0, a * 0.4 * w2), 1.2)
		# 泡沫星点：预生成的 3 个小圆点沿碎沫带散开，错相闪烁，随浪推进微移
		var tn := Vector2(-n.y, n.x)
		for d in s["dots"]:
			var fa := 0.10 + 0.45 * maxf(0.0, sin(_t * 2.1 + d["ph"]))
			if fa <= 0.12:
				continue
			var along := (float(d["u"]) - 0.5) * 9.0
			var across := 10.5 + float(d["v"]) * 3.0 + push * 0.4
			var p := center + Vector2(n) * across + tn * along
			draw_circle(p, 0.9 + 0.5 * float(d["v"]), Color(1, 1, 1, fa))
