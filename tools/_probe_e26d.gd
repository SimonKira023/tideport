extends Node
# tools/_probe_e26d.gd —— e26d AI事件系统实机探针: 商队 / 漂流瓶 / 奇遇抽签
# 跑法（带窗口跑, 要截图）:
#   & $exe --path . --log-file w32_e26d.log res://tools/_probe_e26d.tscn
#
# 站点:
#   [1] 商队生成 —— _spawn_caravans 刷队 -> goods/price 注入 -> 国色掺金贴图 + 商队名牌
#   [2] 商队行进 —— 直奔目标城 -> 进城散伙（不换旗, 跟远征的 conquer 区分开）
#   [3] 商队不设防 —— 头像贴脸不开战 + 靠近提示「做买卖」
#   [4] 商队面板 —— 买特产扣钱入包升好感 / 打劫抢钱抢货结梁子 / 放行 +1 好感
#   [5] 漂流瓶 —— 海上刷瓶 -> 程序化贴图 -> 靠近提示 -> F 捞起（金币或物品入账）
#   [6] 奇遇抽签 —— 60 连抽至少两路副作用生效（风暴海寇/丰收好感/贸易税金/漂流瓶）
#   [7] 每日链 —— 连过 12 天, 商队/漂流瓶自动上地图

const OUT := "res://outputs"
var fails := 0

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_fresh()
	await _caravan_spawn()
	await _caravan_march()
	await _caravan_bypass()
	await _caravan_panel()
	await _bottles()
	await _random_events()
	await _daily_chain()
	print("\n[e26d] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

# e26c 教训: Wallet.add_money 会连锁 check_milestones —— 先预达成 ms_gold 再清零
func _fresh() -> void:
	Wallet.add_money(99999)
	Wallet.money = 0
	Inventory.reset_for_new_game()
	Nations.reset_for_new_game()

func _fire_day() -> void:
	TimeManager.day += 1
	TimeManager.new_day.emit(TimeManager.day)

# 循环刷商队直到出一支（生成函数带 65% 概率闸）
func _force_caravan(wm: Node) -> Dictionary:
	for t in 40:
		wm._spawn_caravans()
		for p in wm.parties:
			if String(p.get("type", "")) == "商队" and not bool(p.get("gone", false)):
				return p
	return {}

# ---------------- 1. 商队生成 ----------------
func _caravan_spawn() -> void:
	print("\n========== [1] 商队生成 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var n0: int = wm.parties.size()
	var cd := _force_caravan(wm)
	_ck(not cd.is_empty(), "商队上地图 (队伍 %d -> %d)" % [n0, wm.parties.size()])
	if cd.is_empty():
		wm.free()
		return
	var nid := String(cd["nation"])
	_ck(Nations.nation_ids().has(nid), "商队挂靠国家 %s" % nid)
	_ck(cd.has("goods") and String(cd["goods"]) != "", "带一车货: %s" % String(cd["goods"]))
	var price := int(cd.get("price", -1))
	_ck(price >= 25 and price <= 45, "报价 %d 金币 (25~45)" % price)
	var goal := String(cd.get("target", ""))
	_ck(goal != "" and Nations.TOWNS.has(goal), "目的地 %s (%s)" % [goal,
			String(Nations.TOWNS.get(goal, {}).get("name", ""))])
	_ck(String(goal) != nid, "不去自家城")
	_ck(String((cd["lbl"] as Label).text).contains("商队"), "名牌: %s" % String((cd["lbl"] as Label).text))
	var spr := cd["spr"] as AnimatedSprite2D
	_ck(spr.modulate.b > 0.5, "国色掺金 (b=%.2f 偏亮示好, 不示警)" % spr.modulate.b)
	var goods_it: ItemData = load("res://item/%s.tres" % String(cd["goods"]))
	_ck(goods_it != null and goods_it.display_name != "", "货单找得到实物: %s" % goods_it.display_name)
	await _shot("caravan_spawn")
	wm.free()
	await get_tree().process_frame

# ---------------- 2. 商队行进 ----------------
func _caravan_march() -> void:
	print("\n========== [2] 商队行进 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var cd := _force_caravan(wm)
	_ck(not cd.is_empty(), "商队上地图")
	if cd.is_empty():
		wm.free()
		return
	var tid := String(cd["target"])
	var tcell: Vector2i = Nations.TOWNS[tid]["cell"]
	var owner0 := Nations.owner_nation_of(tid)
	var cap_pos: Vector2 = wm._cell_center(tcell)
	# 挪到城边 10 像素, 等它进城
	cd["pos"] = cap_pos + Vector2(10, 0)
	(cd["node"] as Node2D).position = cd["pos"]
	await _wait(0.4)
	var gone := true
	for p in wm.parties:
		if p == cd:
			gone = false
	_ck(gone, "商队进城就地散伙, 队伍散了")
	_ck(Nations.owner_nation_of(tid) == owner0, "城头旗色没变 (商队不是远征, 不夺城)")
	wm.free()
	await get_tree().process_frame

# ---------------- 3. 商队不设防 ----------------
func _caravan_bypass() -> void:
	print("\n========== [3] 商队不设防 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var cd := _force_caravan(wm)
	_ck(not cd.is_empty(), "商队上地图")
	if cd.is_empty():
		wm.free()
		return
	# 别的队伍全挪到远海角落, 免得乱入开战搅局
	for p in wm.parties:
		if p != cd:
			p["pos"] = Vector2(3000.0 + randf() * 500.0, 3000.0 + randf() * 500.0)
			(p["node"] as Node2D).position = p["pos"]
	# 头像贴脸: 遭遇距离 15, 放 10 像素外
	wm.avatar.position = (cd["pos"] as Vector2) + Vector2(10, 0)
	await _wait(0.6)
	var bm: Node = get_tree().get_first_node_in_group("battle")
	_ck(bm == null, "贴脸商队不开战 (做买卖的, 不动武)")
	_ck(wm._near_caravan == int(cd["id"]), "靠近判定生效 (_near_caravan = %d)" % wm._near_caravan)
	_ck(String(wm._hint_text()).contains("做买卖"), "靠近提示: %s" % String(wm._hint_text()).replace("\n", " / "))
	await _shot("caravan_near")
	wm.free()
	await get_tree().process_frame

# ---------------- 4. 商队面板 ----------------
func _hud_buttons(wm: Node) -> Array:
	var out: Array = []
	var stack: Array = [wm._hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

# 遍历顺序不可靠, 按钮一律按文字找
func _btn_by_text(wm: Node, kw: String) -> Button:
	for b in _hud_buttons(wm):
		if String((b as Button).text).contains(kw):
			return b
	return null

func _caravan_panel() -> void:
	print("\n========== [4] 商队面板 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	var cd := _force_caravan(wm)
	_ck(not cd.is_empty(), "商队上地图")
	if cd.is_empty():
		wm.free()
		return
	var nid := String(cd["nation"])
	var goods_it: ItemData = load("res://item/%s.tres" % String(cd["goods"]))

	# --- 买特产 ---
	wm._open_caravan_panel(cd)
	await get_tree().process_frame
	_ck(wm._ui_lock, "面板打开, 走动锁住")
	var b_buy := _btn_by_text(wm, "买特产")
	var b_rob := _btn_by_text(wm, "打劫")
	var b_pass := _btn_by_text(wm, "放行")
	_ck(b_buy != null and b_rob != null and b_pass != null, "面板三个按钮齐全 (买 / 劫 / 放行)")
	await _shot("caravan_panel")      # 先拍面板全貌, 再点按钮
	if b_buy != null:
		var price := int(cd["price"])
		var fav0 := Nations.favor_of(nid)
		Wallet.money = 200
		var have0 := Inventory.count_item(goods_it)
		b_buy.pressed.emit()
		await get_tree().process_frame
		_ck(Wallet.money == 200 - price, "买特产: 扣款 %d 金 (余额 %d)" % [price, Wallet.money])
		_ck(Inventory.count_item(goods_it) == have0 + 1, "货进背包: %s x%d" % [goods_it.display_name, Inventory.count_item(goods_it)])
		_ck(Nations.favor_of(nid) == fav0 + 1, "做买卖升好感: %d -> %d" % [fav0, Nations.favor_of(nid)])
		_ck(not wm._ui_lock, "面板关了, 走动解锁")
	await _shot("caravan_buy")

	# --- 打劫 ---
	Wallet.money = 0
	var fav1 := Nations.favor_of(nid)
	var items0 := _inv_total(wm)
	wm._open_caravan_panel(cd)
	await get_tree().process_frame
	var b_rob2 := _btn_by_text(wm, "打劫")
	if b_rob2 != null:
		b_rob2.pressed.emit()
		await get_tree().process_frame
		var loot_got: int = Wallet.money
		_ck(loot_got >= 15 and loot_got <= 45, "打劫抢到 %d 金币 (15~45)" % loot_got)
		_ck(Inventory.count_item(goods_it) > 0 or _inv_total(wm) > items0, "货也抢到了一车")
		_ck(Nations.favor_of(nid) == maxi(Nations.FAVOR_MIN, fav1 - 3), "结梁子掉好感 (下限 %d): %d -> %d" % [Nations.FAVOR_MIN, fav1, Nations.favor_of(nid)])
		var gone := true
		for p in wm.parties:
			if p == cd:
				gone = false
		_ck(gone, "商队被打散, 从海图消失")
		_ck(Nations.notices.size() >= 1, "记账入册: %s" % String(Nations.notices[Nations.notices.size() - 1]))

	# --- 放行: 再刷一支干净的 ---
	var cd2 := _force_caravan(wm)
	_ck(not cd2.is_empty(), "再刷一支商队测放行")
	if not cd2.is_empty():
		var nid2 := String(cd2["nation"])
		var fav2 := Nations.favor_of(nid2)
		wm._open_caravan_panel(cd2)
		await get_tree().process_frame
		var b_pass2 := _btn_by_text(wm, "放行")
		if b_pass2 != null:
			b_pass2.pressed.emit()
			await get_tree().process_frame
			_ck(Nations.favor_of(nid2) == fav2 + 1, "放行升好感: %d -> %d" % [fav2, Nations.favor_of(nid2)])
			var alive := false
			for p in wm.parties:
				if p == cd2:
					alive = true
			_ck(alive, "放行后商队继续赶路")
	wm.free()
	await get_tree().process_frame

func _inv_total(wm: Node) -> int:
	var n := 0
	for key in ["perch", "crayfish", "pufferfish", "starfish", "wheat", "pumpkin",
			"egg", "pumpkin_pie", "cabbage_soup", "carrot_salad", "baked_potato"]:
		var it: ItemData = load("res://item/%s.tres" % key)
		if it != null:
			n += Inventory.count_item(it)
	return n

# ---------------- 5. 漂流瓶 ----------------
func _bottles() -> void:
	print("\n========== [5] 漂流瓶 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	_fresh()
	for t in 20:
		wm._spawn_bottles()
		if wm._bottles.size() >= 1:
			break
	_ck(wm._bottles.size() >= 1, "海上漂着 %d 只漂流瓶" % wm._bottles.size())
	if wm._bottles.is_empty():
		wm.free()
		return
	var b: Dictionary = wm._bottles[0]
	_ck(is_instance_valid(b["node"]), "瓶子有实体节点")
	_ck(wm._bottle_tex() != null, "程序化瓶贴图生成 OK")
	await _shot("bottle_float")
	# 头像贴过去
	wm.avatar.position = (b["pos"] as Vector2) + Vector2(8, 0)
	await _wait(0.3)
	_ck(wm._near_bottle == 0, "靠近判定生效 (_near_bottle = %d)" % wm._near_bottle)
	_ck(String(wm._hint_text()).contains("漂流瓶"), "靠近提示: %s" % String(wm._hint_text()).replace("\n", " / "))
	var money0 := Wallet.money
	var items0 := _inv_total(wm)
	var n_bottles: int = wm._bottles.size()
	wm._pick_bottle(0)
	await get_tree().process_frame
	_ck(wm._bottles.size() == n_bottles - 1, "瓶子捞起后少一只 (%d -> %d)" % [n_bottles, wm._bottles.size()])
	_ck(wm._near_bottle == -1, "靠近判定复位")
	_ck(Wallet.money > money0 or _inv_total(wm) > items0,
			"开瓶有奖 (金币 +%d 或 货物 +%d 件)" % [Wallet.money - money0, _inv_total(wm) - items0])
	wm.free()
	await get_tree().process_frame

# ---------------- 6. 奇遇抽签 ----------------
func _random_events() -> void:
	print("\n========== [6] 奇遇抽签 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	_fresh()
	var money0 := Wallet.money
	var pirates0 := _count(wm, "海寇")
	var favor0 := _favor_sum()
	var notices0: int = Nations.notices.size()
	var draws := 60
	for i in draws:
		wm._random_event()
	var dm := Wallet.money - money0
	var dp := _count(wm, "海寇") - pirates0
	var dv := _favor_sum() - favor0
	var dn: int = Nations.notices.size() - notices0
	var hits := (1 if dm > 0 else 0) + (1 if dp > 0 else 0) \
			+ (1 if dv > 0 else 0) + (1 if dn > 0 else 0)
	print("    [info] %d 连抽副作用: 金币+%d 海寇+%d 好感+%d 通告+%d" % [draws, dm, dp, dv, dn])
	_ck(hits >= 2, "%d 连抽至少两路奇遇真的生效 (hits=%d)" % [draws, hits])
	wm.free()
	await get_tree().process_frame

func _favor_sum() -> int:
	var s := 0
	for nid in Nations.nation_ids():
		s += Nations.favor_of(String(nid))
	return s

# ---------------- 7. 每日链 ----------------
func _daily_chain() -> void:
	print("\n========== [7] 每日链 ==========")
	var wm: Node = load("res://scene/world_map.gd").new()
	add_child(wm)
	await _wait(0.8)
	_fresh()
	var c0 := _count(wm, "商队")
	var b0: int = wm._bottles.size()
	var got_c := false
	var got_b := false
	for d in 12:
		_fire_day()
		await get_tree().process_frame
		if _count(wm, "商队") > c0:
			got_c = true
		if wm._bottles.size() > b0:
			got_b = true
	_ck(got_c, "连过 12 天, 商队自动上地图")
	_ck(got_b, "连过 12 天, 漂流瓶自动漂来")
	await _shot("daily_chain")
	wm.free()
	await get_tree().process_frame

# ---------------- 工具 ----------------
func _count(wm: Node, type: String) -> int:
	var n := 0
	for p in wm.parties:
		if String(p.get("type", "")) == type and not bool(p.get("gone", false)):
			n += 1
	return n

func _shot(nm: String) -> void:
	await _wait(0.7)      # 等淡入结束再拍, 别截到中间帧
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		img.save_png(ProjectSettings.globalize_path("%s/e26_%s.png" % [OUT, nm]))
		print("  [shot] e26_%s.png" % nm)
	else:
		print("  [!!] 截图失败: viewport 纹理为空")

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame
