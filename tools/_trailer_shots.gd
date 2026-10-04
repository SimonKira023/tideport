# k3: 预告片自动截图 —— 跑遍 9 个镜头, 输出 tools/_trailer/*.png (1920x1080)
# 跑法(不能加 --headless): godot --path . --script res://tools/_trailer_shots.gd
# 注意: --script 窗口模式 FPS 无锁(高配机 ~240fps), 一切等待必须按秒, 按帧会严重缩水
extends SceneTree

const OUT := "res://tools/_trailer/"
# --script 模式下主脚本先于 autoload 编译, preload 依赖链会炸 —— 必须运行时 load()
var CARDSB: GDScript
var CARDSD: GDScript
var SEAMAP: GDScript
var MAINLAND: GDScript
# 每季各拍各的当季成熟作物(春土豆/夏花椰菜/秋卷心菜/冬甜菜)
const SEED_BY_SEASON := ["res://item/seed.tres", "res://item/cauliflower_seed.tres", "res://item/cabbage_seed.tres", "res://item/beet_seed.tres"]
var _crop_cells: Array = []

func _init() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_run()

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _run() -> void:
	await _wait(0.2)
	# autoload 已就绪后才能安全 load 依赖它们的场景脚本
	CARDSB = load("res://scene/battle_cards.gd")
	CARDSD = load("res://scene/cards_data.gd")
	SEAMAP = load("res://scene/world_map.gd")
	MAINLAND = load("res://scene/mainland.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# ---- 镜头1: 主菜单标题 ----
	# 清掉历次跑片攒的垃圾存档: 标题输入框显示「第 N 档」, N = 档数+1, 档越多越难看
	var ubase := OS.get_user_data_dir()
	for sub in ["slots", "saves"]:
		var d := DirAccess.open(ubase + "/" + sub)
		if d != null:
			for f in d.get_files():
				d.remove(f)
	DirAccess.remove_absolute(ubase + "/savegame.json")
	change_scene_to_file("res://scene/main_menu.tscn")
	await _wait(0.8)
	if current_scene != null and current_scene.has_method("_skip_intro"):
		current_scene.call("_skip_intro")
	await _wait(0.8)
	await _shot("01_title")

	# ---- 镜头2-6: 岛上四季 + 夜 ----
	# 关 SaveManager 走「裸跑」分支(自检同款): 新档的 reset_all 会把手绘的 272 格
	# 耕地清空(荒岛开局是设计如此), 裸跑既保住整片田也不播序章过场
	root.get_node("SaveManager").enabled = false
	change_scene_to_file("res://scene/game.tscn")
	await _wait(2.0)
	await _skip_opening()
	_teleport_farm()
	_plant_season()
	# 春·上午
	var tm := root.get_node("TimeManager")
	tm.hour = 10
	tm.minute = 0
	tm.snap()
	await _wait(0.8)
	await _shot("02_spring")
	# 夏(换季飘字约 2s, 等淡干净; 换季即换种当季作物)
	_season(1)
	_plant_season()
	await _wait(2.6)
	await _shot("03_summer")
	# 秋
	_season(2)
	_plant_season()
	await _wait(2.6)
	await _shot("04_autumn")
	# 冬
	_season(3)
	_plant_season()
	await _wait(2.6)
	await _shot("05_winter")
	# 夜: 21 点触发的篝火公告挂 5s + 0.8s 淡出, 等它彻底散了再拍
	tm.hour = 21
	tm.snap()
	await _wait(6.5)
	await _shot("06_night")

	# ---- 拆岛, 摆卡牌战场 ----
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	var cb: Node = CARDSB.new()
	cb.set("party", {"type": "海寇", "size": 3, "id": 0})
	root.add_child(cb)
	cb.scale = Vector2(5.0 / 3.0, 5.0 / 3.0)
	await _wait(0.5)
	_stage_battle(cb)
	# 等开局横幅(接舷/甲板狭窄)淡干净
	await _wait(3.0)
	# _flash 的提示字停在 0.35 透明度不会自己消失, 拍前手动清掉
	_clear_hint(cb)
	await _shot("07_battle")
	cb.queue_free()
	await process_frame

	# ---- 海图 ----
	var wm: Node = SEAMAP.new()
	root.add_child(wm)
	await _wait(1.0)
	await _shot("08_seamap")
	wm.queue_free()
	await process_frame

	# ---- 大陆据点 ----
	# 码头公告挂 3.5s + 0.8s 淡出, 等散了再拍干净版
	var ml: Node = MAINLAND.new()
	root.add_child(ml)
	await _wait(5.5)
	await _shot("09_mainland")
	ml.queue_free()
	await process_frame

	print("trailer shots done")
	quit(0)

func _shot(shot_name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT + shot_name + ".png")
	print("shot %s %dx%d err=%d" % [shot_name, img.get_width(), img.get_height(), err])

# 序章兜底: 裸跑(enabled=false)根本不播序章, 只留 2s 轮询防万一
func _skip_opening() -> void:
	var op: Node = null
	for i in 20:
		if current_scene != null:
			for ch in current_scene.get_children():
				var sc: Variant = ch.get_script()
				if sc != null and String(sc.resource_path).ends_with("opening.gd"):
					op = ch
					break
		if op != null:
			break
		await _wait(0.1)
	if op == null:
		print("opening not found, skip failed")
		return
	print("opening found, calling _finish")
	op.call("_finish")
	# 淡出 0.6s, 翻倍兜底
	await _wait(1.5)

# 换季: 直接拨 TimeManager + 手动广播(换季提示飘字等淡出后才拍)
func _season(s: int) -> void:
	var tm := root.get_node("TimeManager")
	tm.season = s
	tm.day = 1
	tm.season_changed.emit(s)
	tm.new_day.emit(tm.day)
	tm.snap()

# 玩家传到岛上自带农田(272 格已开垦)的中心格 —— 镜头跟着玩家, 田就铺满画面
func _teleport_farm() -> void:
	var farm := root.get_node("Farm")
	var players := get_nodes_in_group("player")
	if players.is_empty() or farm.tilled.is_empty():
		print("teleport farm skipped: no player or no tilled")
		return
	# 所有已耕格的质心, 再取离质心最近的已耕格当落点
	var sum := Vector2.ZERO
	for c in farm.tilled.keys():
		sum += Vector2(c)
	var center: Vector2i = Vector2i((sum / float(farm.tilled.size())).floor())
	var best: Vector2i = center
	var bestd := 999999.0
	for c in farm.tilled.keys():
		var d: float = Vector2(c).distance_squared_to(Vector2(center))
		if d < bestd:
			bestd = d
			best = c
	var pl := players[0] as Node2D
	# grid_origin 是世界像素原点, 格子 -> 世界 = origin + cell*16 + 半格
	pl.global_position = Vector2(farm.grid_origin) \
		+ Vector2(best) * float(farm.TILE_SIZE) + Vector2(8, 8)
	print("farm center cell: ", best, " world: ", pl.global_position)

# 对当前季节把全部耕地种满成熟作物; 换季后先清上一季残株再种新的
func _plant_season() -> void:
	var farm := root.get_node("Farm")
	for c in _crop_cells:
		if farm.crops.has(c):
			farm.crops.erase(c)
			farm.crop_changed.emit(c)   # 与 harvest 同套路: erase 后发信号移除贴图
	_crop_cells.clear()
	var tm := root.get_node("TimeManager")
	var seed_item = load(SEED_BY_SEASON[int(tm.season)])
	var grown := 0
	for c in farm.tilled.keys():
		if farm.plant(c, seed_item):
			farm.crops[c].stage = seed_item.grow_days
			farm.crop_changed.emit(c)   # crop_layer 在信号时才读 stage, 设完必须再发一次
			_crop_cells.append(c)
			grown += 1
	print("crops grown: ", grown)

# 摆一个好看的对峙局面: 前线我 1 敌 2 贴脸对峙 + 支援线弓手, 手牌 3 张
# 注意: 接舷战前线只有 3 格, 且部署本身就算行动(_advance 会被「已行动」拒掉),
# 所以全部直接落位, 不走出牌/前进的正规流程
func _stage_battle(cb: Variant) -> void:
	cb._front[0] = cb._new_unit(CARDSD.unit_card("藤牌手", 1, 0, 3, "guard"), "my")
	cb._front[1] = cb._new_unit(CARDSD.unit_card("海寇", 2, 2, 2, ""), "foe")
	cb._front[2] = cb._new_unit(CARDSD.unit_card("浪人", 3, 3, 2, ""), "foe")
	cb._my_support[0] = cb._new_unit(CARDSD.unit_card("游哨弓手", 2, 2, 2, "ranged"), "my")
	cb._my_hand = [
		CARDSD.unit_card("甲骑", 4, 4, 4, "cav"),
		CARDSD.unit_card("持斧客", 2, 3, 1, ""),
		CARDSD.unit_card("艨艟水手", 3, 2, 4, "guard"),
	]
	cb._cost = 2
	cb._refresh_all()

# _flash 的提示字停在 0.35 透明度不会自己消失, 拍前手动清掉
func _clear_hint(cb: Variant) -> void:
	var lbl: Variant = cb.get("_lbl_hint")
	if lbl != null:
		lbl.set("text", "")
		lbl.set("modulate", Color(1, 1, 1, 0))
