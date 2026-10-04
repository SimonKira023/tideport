extends Node
# 艺术宣传片导演（e15e）: 分段拍摄 —— 每段一次 Movie Maker 渲染出一段 avi,
# 后期用 ffmpeg 剪成片（字幕卡 + 淡入淡出 + 配乐）。比上一版单镜头连续录更有剪辑感。
#
# 跑法（要带窗口跑, headless 渲不出画面）:
#   & $exe --path . --write-movie outputs/trailer_A.avi --fixed-fps 30 --log-file trailer_A.log res://tools/trailer.tscn -- --seg=A
# 段落（--seg=）:
#   A 晨曦岛居 10s —— 清晨的潮汐港: 主角穿过农田, 云影流转
#   B 耕读技艺 10s —— 背包三页: 科技树 / 行政树 / 团队职业树
#   C 暮色启航 12s —— 黄昏出海: 天色染橙, 船队沿岸航行, 镜头缓缓拉远
#   D 全景列国 10s —— 观景档缓推: 涂色晕开, 五国名字浮出
#   E 夜战锋芒 12s —— 深夜遭遇战: 布阵 -> 军鼓开打 -> 胜利
#   F 夜航归潮  9s —— 月光海面, 船队驶向远方的家
#
# ❗SaveManager 在挂 game 之前就关闸 —— 宣传片绝不碰真档（一号事故的铁规矩）。
# ❗帧数驱动（_process 每帧 +1）: 布阵阶段 Engine.time_scale=0 会让 delta 归零,
#   用秒计时的导演会僵死, 帧计数不会。

const FPS := 30
const SEG_FRAMES := {"A": 300, "B": 300, "C": 360, "D": 300, "E": 360, "F": 270}

var game: Node = null
var _frames := 0
var _step := 0
var _seg := "A"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seg="):
			_seg = a.substr(6).to_upper()
	if not SEG_FRAMES.has(_seg):
		_seg = "A"
	SaveManager.enabled = false            # 宣传片不读不存
	var game_scene: PackedScene = load("res://scene/game.tscn")
	game = game_scene.instantiate()
	add_child(game)
	Wallet.money = 3200
	for i in 2:
		Wallet.add_money(200)
		Slaves.recruit_roster()
	print("[trailer] 段 %s 开拍, %d 帧" % [_seg, int(SEG_FRAMES[_seg])])

func _process(_delta: float) -> void:
	_frames += 1
	match _seg:
		"A": _seg_a()
		"B": _seg_b()
		"C": _seg_c()
		"D": _seg_d()
		"E": _seg_e()
		"F": _seg_f()
	if _frames >= int(SEG_FRAMES[_seg]):
		print("[trailer] 段 %s 拍完, 可以关掉窗口" % _seg)
		get_tree().quit()

# —— A 晨曦岛居: 穿过农田的清晨散步 ——
func _seg_a() -> void:
	_set_clock(8, 0)
	match _step:
		0:
			if _frames >= 40:
				_walk("move_right", true); _step = 1
		1:
			if _frames >= 140:
				_walk("move_right", false); _step = 2
		2:
			if _frames >= 180:
				_walk("move_down", true); _step = 3
		3:
			if _frames >= 260:
				_walk("move_down", false); _step = 4

# —— B 耕读技艺: 背包里的两棵树 + 团队 ——
func _seg_b() -> void:
	match _step:
		0:
			if _frames >= 40:
				var bp := _backpack()
				if bp != null:
					bp.open()
				_step = 1
		1:
			if _frames >= 70:
				var bp := _backpack()
				if bp != null:
					bp._switch_to("tech")
				_step = 2
		2:
			if _frames >= 160:
				var bp := _backpack()
				if bp != null:
					bp._switch_to("team")
				_step = 3
		3:
			if _frames >= 285:
				var bp := _backpack()
				if bp != null:
					bp.close()
				_step = 4

# —— C 暮色启航: 黄昏出海, 沿岸航行, 中途拉远一档 ——
func _seg_c() -> void:
	_set_clock(17, 30)
	match _step:
		0:
			if _frames >= 30:
				Voyage.enter_travel(game)
				_step = 1
		1:
			if _frames >= 60:
				_walk("move_right", true)
				_step = 2
		2:
			if _frames >= 220:
				_walk("move_right", false)
				var wm := _world_map()
				if wm != null:
					wm.call("_zoom_camera", -1)    # 3 -> 2: 起航后镜头缓缓拉远
				_step = 3
		3:
			if _frames >= 250:
				_walk("move_up", true)
				_step = 4
		4:
			if _frames >= 330:
				_walk("move_up", false)
				_step = 5

# —— D 全景列国: 直上观景档, 看涂色晕开 + 国名浮出 ——
func _seg_d() -> void:
	_set_clock(10, 0)
	match _step:
		0:
			if _frames >= 30:
				Voyage.enter_travel(game)
				_step = 1
		1:
			if _frames >= 60:
				var wm := _world_map()
				if wm != null:
					wm.call("_zoom_camera", -1)    # 3 -> 2
				_step = 2
		2:
			if _frames >= 66:
				var wm := _world_map()
				if wm != null:
					wm.call("_zoom_camera", -1)    # 2 -> 0.28 进观景档
				_step = 3

# —— E 夜战锋芒: 深夜出海遭遇, 布阵 -> 开打 -> 胜利 ——
func _seg_e() -> void:
	_set_clock(22, 0)
	match _step:
		0:
			# enter_battle 要求海图已存在(里面找 world_map 节点), 所以必须先出海
			if _frames >= 30:
				Voyage.enter_travel(game)
				_step = 1
		1:
			if _frames >= 60:
				Voyage.enter_battle({"id": 99, "type": "巡逻", "size": 4,
					"nation": "tieyan", "army": "铁岩亲军", "pos": Vector2.ZERO})
				_step = 2
		2:
			if _frames >= 120:
				var bm := get_tree().get_first_node_in_group("battle")
				if bm != null:
					bm.call("_begin_battle")
				_step = 3
		3:
			# e15h: 主角左键挥剑展示 —— 打仗不再自己砍, 导演隔一会儿替他点一刀
			if _frames >= 160 and _frames % 45 == 0:
				var bm: Node = get_tree().get_first_node_in_group("battle")
				var h: Node2D = null
				if bm != null:
					h = bm.call("get_hero")
				if h != null:
					var f: Node2D = h.call("_nearest_foe", 9999.0)
					if f != null:
						h.call("swing_sword", f.global_position)
			if _frames >= 330:
				Voyage.end_battle("victory")
				_step = 4

# —— F 夜航归潮: 月光下的最后一程 ——
# (路径同 C 段: 右走到码头才能上船出海; 旧版向左走会留在村里步行, 夜色罩在
#  明亮岛屿美术上不明显 —— 2026-09-20 探针实测, 夜海+月光才是深夜的正确拍法)
func _seg_f() -> void:
	_set_clock(21, 30)
	match _step:
		0:
			if _frames >= 30:
				Voyage.enter_travel(game)
				_step = 1
		1:
			if _frames >= 60:
				_walk("move_right", true)
				_step = 2
		2:
			if _frames >= 190:
				_walk("move_right", false)
				var wm := _world_map()
				if wm != null:
					wm.call("_zoom_camera", -1)    # 缓缓拉远, 收在夜色全景
				_step = 3
		3:
			if _frames >= 220:
				_walk("move_up", true)
				_step = 4
		4:
			if _frames >= 255:
				_walk("move_up", false)
				_step = 5

func _walk(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)

# 拨时刻表 + 发 time_tick —— 时钟面板只听信号刷新, 直接改变量 UI 会停在旧时间
func _set_clock(h: int, m: int) -> void:
	TimeManager.hour = h
	TimeManager.minute = m
	TimeManager.time_tick.emit()

func _backpack() -> Control:
	var bp: Control = null
	if game != null:
		bp = game.get("backpack_panel")
	return bp

func _world_map() -> Node:
	return get_tree().get_first_node_in_group("world_map")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
