extends Node2D
# 天上的半透明白云层（主岛 + 海图共用）：
# - 一朵云由几块半透明白色长方形拼成（底宽顶窄，错位叠出蓬松劲儿）
# - 整层朝一个方向（往左）慢速飘，全场统一风向
# - 挂在世界坐标下（不进 CanvasLayer），相机缩放时云跟着一起放大缩小：
#   视野拉大（zoom 值大）能看到一小片云层；拉太近云块巨大又稀，常常看不见，属正常
# - 同屏最多 MAX_CLOUDS 朵，防止把地图糊住
# - 飘出视野的云自动回收，隔一会儿再从上风处补一朵新的飘进来

const MAX_CLOUDS := 3                 # 同屏上限
const MIN_SPEED := 9.0                # 飘速下限（世界像素/秒）：慢悠悠
const MAX_SPEED := 22.0
const SPAWN_GAP := Vector2(2.0, 5.0)  # 补一朵新云的间隔（秒，随机）
const MARGIN := 96.0                  # 视野外余量：离开视野这么远才算真走了
const LOITER := 45.0                  # 一直没飘进视野的云，超过这个秒数兜底回收

var _rng := RandomNumberGenerator.new()
var _spawn_cd := 0.0

func _ready() -> void:
	z_index = 20                  # 云在天上：盖过树/屋顶/城镇（HUD 在 CanvasLayer，不受影响）
	_rng.randomize()
	_spawn_cd = _rng.randf_range(2.0, 4.0)
	# 开场先放 1~2 朵在视野里，别让玩家干等。
	# 推迟到本帧末尾：等相机组好、视野矩形可用（不然拿到的视野是空的）
	for i in _rng.randi_range(1, 2):
		_spawn_cloud.call_deferred(true)

func _process(delta: float) -> void:
	var view := _view_rect()
	if view.size == Vector2.ZERO:
		return
	# 1) 整层往一个方向飘 + 回收飘走的云
	for c in get_children():
		c.position.x -= float(c.get_meta("speed")) * delta
		var box: Rect2 = c.get_meta("box")
		box.position = c.position
		# e30f: Rect2 是值类型 —— 上面的修改不写回 meta，盒子永远停在出生点，
		# 回收判定全按旧盒子算：玩家往右走时，屏幕上还看得见的云会被提前回收。
		c.set_meta("box", box)
		c.set_meta("age", float(c.get_meta("age")) + delta)
		# e28a: 「飘出屏幕才删」—— 进视野判定不带余量(真进过屏幕才算 entered),
		# 且只有从左边界完全飘出屏幕才回收; 玩家走动把云甩出视野不再凭空消失
		if box.intersects(view):
			c.set_meta("entered", true)          # 真的进过屏幕
		elif bool(c.get_meta("entered")) and box.end.x < view.position.x - MARGIN:
			c.queue_free()                       # 从左边界完全飘出去 -> 回收
		elif not bool(c.get_meta("entered")) and float(c.get_meta("age")) > LOITER:
			c.queue_free()                       # 一直没飘进屏幕的云，兜底回收
	# 2) 按间隔补新云（从上风侧视野外飘进来）
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and get_child_count() < MAX_CLOUDS:
		_spawn_cloud(false)
		_spawn_cd = _rng.randf_range(SPAWN_GAP.x, SPAWN_GAP.y)

# 造一朵云：3 块长方形（宽云加第 4 块小顶盖），底块整宽、往上渐窄
func _spawn_cloud(inside: bool) -> void:
	var view := _view_rect()
	if view.size == Vector2.ZERO:
		return                                  # 相机还没就位，等下一轮补货
	var cloud := Node2D.new()
	var w := _rng.randf_range(44.0, 96.0)       # 一朵云的世界宽
	var alpha := _rng.randf_range(0.20, 0.34)   # 半透明：云是氛围，不能糊住地图
	var pieces := [[1.0, 14.0], [0.62, 7.0], [0.36, 0.0]]
	if w > 72.0:
		pieces.append([0.20, -6.0])
	for pc in pieces:
		var pw := w * float(pc[0])
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(pw, 0), Vector2(pw, 9), Vector2(0, 9)])
		poly.color = Color(1, 1, 1, alpha * _rng.randf_range(0.8, 1.0))
		poly.position = Vector2(
			(w - pw) * 0.5 + _rng.randf_range(-4.0, 4.0),
			float(pc[1]) + _rng.randf_range(-1.5, 1.5))
		cloud.add_child(poly)
	cloud.set_meta("speed", _rng.randf_range(MIN_SPEED, MAX_SPEED))
	cloud.set_meta("age", 0.0)
	cloud.set_meta("entered", false)
	cloud.set_meta("box", Rect2(Vector2(-6, -8), Vector2(w + 12, 31)))
	# 出生点：开场那几朵直接撒在视野里；平时从上风侧视野外飘进来
	var vy := view.position.y + view.size.y * _rng.randf_range(0.05, 0.8)
	if inside:
		cloud.position = Vector2(
			_rng.randf_range(view.position.x, view.end.x - w), vy)
		cloud.set_meta("entered", true)          # 出生即在视野里
	else:
		cloud.position = Vector2(view.end.x + _rng.randf_range(20.0, 90.0), vy)
	add_child(cloud)

# 当前相机视野的世界矩形（云的生成/回收全按它算，缩放拖动都自动适配）
func _view_rect() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Rect2()
	var half := get_viewport_rect().size * 0.5 / cam.zoom
	return Rect2(cam.get_screen_center_position() - half, half * 2.0)
