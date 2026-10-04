extends Node
# tools/_probe_e25_live.gd —— e25 实机巡检: 真开窗口把玩法跑一遍, 每站截图 outputs/e25_*.png
# 跑法（必须带窗口跑, headless 截不出画面）:
#   & $exe --path . --log-file w32_live.log res://tools/_probe_e25_live.tscn
#
# 站点: 主菜单 -> 岛上(全景/砍树/背包/夜晚结算) -> 出海动画 -> 海图 ->
#       遭遇战(布阵/开打/胜利结算页) -> 关闭回海图 -> 败北结算页 -> 关闭回岛 -> 攻城结算页
# ❗_wait 用真实时钟: 布阵阶段 Engine.time_scale=0, 按帧 delta 累加会冻死。

const OUT := "res://outputs"
const TS := 16

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _menu()
	await _island()
	await _battle_victory()
	await _battle_defeat()
	await _siege()
	print("\n[e25] 巡检完毕")
	get_tree().quit()

# ---------------- 1. 主菜单 ----------------
func _menu() -> void:
	print("\n========== [1] 主菜单 ==========")
	var mm: Node = load("res://scene/main_menu.tscn").instantiate()
	add_child(mm)
	await _wait(5.0)
	await _shot("01_menu")
	mm.free()
	await get_tree().process_frame

# ---------------- 2. 岛上 ----------------
func _island() -> void:
	print("\n========== [2] 岛上 ==========")
	Slaves.slaves = [
		{"name": "甲", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 1},
		{"name": "乙", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "弓手", "squad": 1},
		{"name": "丙", "affection": 0, "pref": 0, "fed_today": true, "talked_today": true,
			"max_hp": 30, "hp": 30, "troop": "刀客", "squad": 2},
	]
	Slaves.count = Slaves.slaves.size()
	Slaves.expedition = [0, 1, 2]
	TimeManager.hour = 8
	TimeManager.time_running = true
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await _wait(1.2)
	await _shot("02_island")

	# 砍树一斧
	var player: Node2D = g.get_node("Player")
	player.current_item = load("res://item/axe.tres")
	var tc := Vector2i(-999, -999)
	for k in Trees.trees.keys():
		var kk: Vector2i = k
		if int(Trees.trees[kk].stage) != Trees.ST_MATURE:
			continue
		if not g.tree_nodes.has(kk):
			continue
		if g.is_water(kk + Vector2i(0, 1)) or Trees.has_tree(kk + Vector2i(0, 1)):
			continue
		tc = kk
		break
	if tc.x != -999:
		_place(g, tc + Vector2i(0, 1))
		var pc: Vector2i = g._world_to_cell(player.global_position)
		player._swing_axe(pc, player.global_position)
		await _wait(0.3)
		await _shot("03_chop")
		print("  砍树: 树格 %s" % tc)
	else:
		print("  [skip] 岛上没找到能砍的成树")

	# 背包
	var bp: Control = g.get("backpack_panel")
	if bp != null:
		bp.call("open")
		await _wait(0.4)
		await _shot("04_bag")
		bp.call("close")
		await _wait(0.2)
	else:
		print("  [skip] 背包面板没找到")

	# 夜晚结算画面
	var settle: Control = g.get("settlement_panel")
	if settle != null:
		var carrot: ItemData = load("res://item/carrot.tres")
		var income: int = carrot.sell_price * 3
		settle.call("show_summary", "春季 第 3 天", 3,
			[{"item": carrot, "count": 3, "price": income}], income, 1234)
		await _wait(0.6)
		await _shot("05_night_settle")
		settle.hide()
		TimeManager.time_running = true
	else:
		print("  [skip] 夜晚结算面板没找到")

	# 出海: 码头建成 + 两条船 + 白天
	Voyage.dock_state = Voyage.DOCK_BUILT
	Voyage.boat_count = 2
	Voyage.dock_changed.emit()
	TimeManager.hour = 10
	Slaves.expedition = [0, 1]
	print("  depart_block = '%s'" % Voyage.depart_block_reason(g))
	g.call("_depart")
	await _wait(1.6)
	await _shot("06_sail")
	var wm: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		wm = get_tree().get_first_node_in_group("world_map")
		if wm != null:
			break
	if wm != null:
		await _wait(1.5)
		await _shot("07_worldmap")
		print("  海图出现了, 队伍 %d 支" % wm.parties.size())
	else:
		print("  [skip] 出海 12s 海图没出现")

# ---------------- 3. 遭遇战 - 胜利 ----------------
func _battle_victory() -> void:
	print("\n========== [3] 遭遇战 - 胜利 ==========")
	var wm: Node = get_tree().get_first_node_in_group("world_map")
	if wm == null:
		print("  [skip] 没有海图（出海段没走通）")
		return
	var pid := -1
	for p in wm.parties:
		if String(p.get("type", "")) == "海寇":
			pid = int(p.get("id"))
			break
	if pid < 0:
		print("  [skip] 海图上没有海寇队")
		return
	wm.call("_start_battle", pid)
	await get_tree().process_frame
	await get_tree().process_frame
	var bm: Node = get_tree().get_first_node_in_group("battle")
	if bm == null:
		print("  [!!] 没进战场")
		return
	print("  进战场: 地形=%s 敌=%d 主角hp=%d" % [bm.template, bm._count_foes(), Legion.player_hp])
	await _wait(2.0)
	await _shot("08_battle_deploy")
	if bool(bm.get("_deploying")):
		bm.call("_begin_battle")
	await _wait(2.5)
	await _shot("09_battle_fight")
	for u in bm.units.duplicate():
		if is_instance_valid(u) and u.side == "enemy":
			u.call("take_damage", 9999)
	await _wait(3.5)
	print("  结算页: hud在=%s result='%s' 曲池='%s' 金币=%d 声望=%d" % [
		str(bm.get("_settle_hud") != null), str(bm.get("_settle_result")),
		Audio.scene_track(), int(bm.get("_last_coin")), int(bm.get("_last_prest"))])
	await _shot("10_settle_victory")
	if bm.get("_settle_hud") != null:
		bm.call("_close_settlement")
	await _wait(2.0)
	await _shot("11_back_map")
	var bm2: Node = get_tree().get_first_node_in_group("battle")
	print("  关闭后: 战场在=%s 海图在=%s" % [str(bm2 != null),
		str(get_tree().get_first_node_in_group("world_map") != null)])

# ---------------- 4. 遭遇战 - 败北 ----------------
func _battle_defeat() -> void:
	print("\n========== [4] 遭遇战 - 败北 ==========")
	var old_wm: Node = get_tree().get_first_node_in_group("world_map")
	if old_wm != null:
		old_wm.queue_free()
	await get_tree().process_frame
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.5)
	var party := {"id": 0, "pos": Vector2(60, 50) * 16.0, "dir": Vector2.ZERO,
		"t": 0.0, "type": "海寇", "size": 3, "node": null}
	wm.parties = [party]
	wm._active_party = 0
	Voyage.enter_battle(party)
	await get_tree().process_frame
	await get_tree().process_frame
	var bm: Node = get_tree().get_first_node_in_group("battle")
	if bm == null:
		print("  [!!] 没进战场")
		return
	if bool(bm.get("_deploying")):
		bm.call("_begin_battle")
	await _wait(1.5)
	Legion.player_hp = 0
	await _wait(3.5)
	print("  结算页: hud在=%s result='%s' 曲池='%s'" % [
		str(bm.get("_settle_hud") != null), str(bm.get("_settle_result")), Audio.scene_track()])
	await _shot("12_settle_defeat")
	if bm.get("_settle_hud") != null:
		bm.call("_close_settlement")
	await _wait(2.5)
	await _shot("13_back_island")
	print("  关闭后: 战场在=%s 岛上game组=%s" % [
		str(get_tree().get_first_node_in_group("battle") != null),
		str(get_tree().get_first_node_in_group("game") != null)])
	Legion.player_hp = Legion.player_max_hp()
	Engine.time_scale = 1.0

# ---------------- 5. 攻城战 ----------------
func _siege() -> void:
	print("\n========== [5] 攻城战 ==========")
	var old_b: Node = get_tree().get_first_node_in_group("battle")
	if old_b != null:
		old_b.remove_from_group("battle")
	var bm: Variant = load("res://scene/battle_map.gd").new()
	bm.party = {"id": 0, "type": "攻城", "size": 3, "siege": "chenxi_cap"}
	add_child(bm)
	await _wait(2.0)
	await _shot("14_siege_deploy")
	if bool(bm.get("_deploying")):
		bm.call("_begin_battle")
	await _wait(2.0)
	await _shot("15_siege_fight")
	for u in bm.units.duplicate():
		if is_instance_valid(u) and u.side == "enemy":
			u.call("take_damage", 9999)
	await _wait(3.5)
	print("  攻城结算页: hud在=%s result='%s'" % [
		str(bm.get("_settle_hud") != null), str(bm.get("_settle_result"))])
	await _shot("16_settle_siege")
	bm.free()
	Voyage.set_battle_slow(false)
	Engine.time_scale = 1.0
	await get_tree().process_frame

# ---------------- 工具 ----------------
func _shot(nm: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		img.save_png(ProjectSettings.globalize_path("%s/e25_%s.png" % [OUT, nm]))
		print("  [shot] e25_%s.png" % nm)
	else:
		print("  [!!] 截图失败: viewport 纹理为空")

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame

func _place(g: Node, cell: Vector2i) -> void:
	var player: Node2D = g.get_node("Player")
	var cs: CollisionShape2D = player.get_node("CollisionShape2D")
	player.global_position = Farm.grid_origin \
		+ Vector2(cell.x * TS + TS * 0.5, cell.y * TS + TS * 0.5) - cs.position
