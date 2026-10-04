extends Node
# tools/_probe_e26c.gd —— e26c 终局目标沙盒版实机探针: 终局三连里程碑 / 大庆祝横幅 / 不锁档
# 跑法（带窗口跑, 要截图）:
#   & $exe --path . --log-file w32_e26c.log res://tools/_probe_e26c.tscn
#
# 站点:
#   [1] 威震四海 —— 声望 100 触发 grand 里程碑, 走 celebrated 不走 rewarded, 奖金 +3000
#   [2] 裂土封王 —— 签封臣契约拿封地触发, 契约状态真实落账
#   [3] 四海归一 —— 全部王都插旗触发; 重复 check 不重复发奖
#   [4] 普通里程碑 —— 建交五方走老 rewarded 通道（两条通道分流）
#   [5] 大庆祝横幅 —— 真机 game.tscn 里 _celebrate 弹金字横幅 + 副标题
#   [6] 沙盒不锁档 —— 全部达成后任务栏还有下一站, 存档往返 grand 进度不丢

const OUT := "res://outputs"
var fails := 0
var cel_texts: Array[String] = []   # celebrated 通道
var rew_texts: Array[String] = []   # rewarded 通道

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Quests.celebrated.connect(func(t: String): cel_texts.append(t))
	Quests.rewarded.connect(func(t: String): rew_texts.append(t))
	_prestige_end()
	_lord_end()
	_unify_end()
	_normal_path()
	await _banner_ui()
	_sandbox_alive()
	print("\n[e26c] %s (fails=%d)" % ["全过" if fails == 0 else "有失败", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  [ok] " + msg)
	else:
		fails += 1
		print("  [!!] " + msg)

func _cel_n(title: String) -> int:
	var n := 0
	for t in cel_texts:
		if t.contains(title):
			n += 1
	return n

func _rew_n(title: String) -> int:
	var n := 0
	for t in rew_texts:
		if t.contains(title):
			n += 1
	return n

# 每站开跑前把现场擦干净（不走指链, 直接开闸里程碑）
func _fresh() -> void:
	Nations.reset_for_new_game()
	Quests.reset_all()
	Wallet.money = 0
	cel_texts.clear()
	rew_texts.clear()
	Quests.start_milestones()
	# 首桶金提前收官: 否则任何一笔进账都会经 money_changed 连锁触发它, 断言没法对账
	Wallet.add_money(99999)             # money_changed -> check -> ms_gold 达成 +500
	Wallet.money = 0                    # 直接赋值不发信号, 现场归零
	_ck(Quests.milestone_done("ms_gold"), "首桶金预达成, 后续奖金不会再连锁")

func _capital_of(nid: String) -> String:
	for tid in Nations.TOWNS.keys():
		var t: Dictionary = Nations.TOWNS[tid]
		if String(t.get("nation", "")) == nid and String(t.get("kind", "")) == "capital":
			return String(tid)
	return ""

func _capitals() -> Array:
	var out: Array = []
	for tid in Nations.TOWNS.keys():
		if String(Nations.TOWNS[tid].get("kind", "")) == "capital":
			out.append(String(tid))
	return out

# ---------------- 1. 威震四海 ----------------
func _prestige_end() -> void:
	print("\n========== [1] 威震四海（声望 100）==========")
	_fresh()
	_ck(not Quests.milestone_done("ms_prestige"), "开局: 威震四海未达成")
	var m0: int = Wallet.money
	Nations.add_prestige(100)   # prestige_changed -> check_milestones
	_ck(Quests.milestone_done("ms_prestige"), "声望 100 -> 威震四海达成")
	_ck(_cel_n("威震四海") == 1, "走大庆祝通道 celebrated (1 次)")
	_ck(_rew_n("威震四海") == 0, "不走普通公告通道 rewarded")
	_ck(Wallet.money == m0 + 3000, "奖励 +3000 金 (钱包 %d -> %d)" % [m0, Wallet.money])
	_ck(not Quests.milestone_done("ms_lord") and not Quests.milestone_done("ms_unify"),
		"另外两个终局目标还挂着, 长线继续")

# ---------------- 2. 裂土封王 ----------------
func _lord_end() -> void:
	print("\n========== [2] 裂土封王（封臣契约）==========")
	var nid := String(Nations.nation_ids()[0])
	var cap := _capital_of(nid)
	_ck(cap != "", "%s 的王都 %s 可当封地" % [nid, cap])
	var ok := Nations.sign_contract(nid, "封臣", cap)
	_ck(ok, "签约成功 (声望 %d 够 VASSAL_NEED %d)" % [Nations.prestige, Nations.VASSAL_NEED])
	_ck(Nations.contract == "封臣" and Nations.fief == cap, "契约真实落账: 封臣 + 封地 %s" % cap)
	_ck(Quests.milestone_done("ms_lord"), "裂土封王达成")
	_ck(_cel_n("裂土封王") == 1, "走大庆祝通道 (1 次)")
	Wallet.money = 0   # 擦掉奖金防下一站串门

# ---------------- 3. 四海归一 ----------------
func _unify_end() -> void:
	print("\n========== [3] 四海归一（王都插旗）==========")
	var caps := _capitals()
	_ck(caps.size() >= 2, "共 %d 座王都要插旗" % caps.size())
	for tid in caps:
		Nations.occupied[String(tid)] = true
	Quests.check_milestones()   # occupied 不发信号, 直接催一遍
	_ck(Quests.milestone_done("ms_unify"), "全部王都插旗 -> 四海归一达成")
	_ck(_cel_n("四海归一") == 1, "走大庆祝通道 (1 次)")
	Quests.check_milestones()
	_ck(_cel_n("四海归一") == 1, "重复 check 不重复发奖 (还是 1 次)")
	Wallet.money = 0

# ---------------- 4. 普通里程碑走老通道 ----------------
func _normal_path() -> void:
	print("\n========== [4] 建交五方走 rewarded 通道 ==========")
	for nid in Nations.nation_ids():
		Nations.add_favor(String(nid), 20)
	_ck(Quests.milestone_done("ms_friends"), "建交五方达成")
	_ck(_rew_n("建交五方") == 1, "普通目标走 rewarded 公告 (1 次)")
	_ck(_cel_n("建交五方") == 0, "不误走大庆祝通道")
	Wallet.money = 0

# ---------------- 5. 大庆祝横幅（真机 game.tscn）----------------
func _banner_ui() -> void:
	print("\n========== [5] 大庆祝横幅 ==========")
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Node = g.get("hud")
	_ck(hud != null, "game 场景就位, hud 挂好了")
	Quests.celebrated.emit("四海归一达成! 奖励 +5000 金")
	await get_tree().process_frame
	# GDScript lambda 按值捕获局部变量, 计数要用引用类型（数组）收
	var hits: Array[String] = []
	_scan_labels(hud, func(l: Label):
		if l.text.contains("结局没有终点"):
			hits.append("sub")
		if l.text.contains("四海归一"):
			hits.append("gold"))
	_ck(hits.has("gold"), "横幅金字标题上屏")
	_ck(hits.has("sub"), "副标题点明沙盒: 结局没有终点, 这片海随你继续闯")
	await _wait(0.7)   # 等淡入+回弹动画播完再截, 别把半透明中间帧当证据
	await _shot("celebrate_banner")
	g.free()
	await get_tree().process_frame

func _scan_labels(node: Node, fn: Callable) -> void:
	if node is Label:
		fn.call(node)
	for c in node.get_children():
		_scan_labels(c, fn)

# ---------------- 6. 沙盒不锁档 ----------------
func _sandbox_alive() -> void:
	print("\n========== [6] 沙盒不锁档 ==========")
	# 任务栏常驻位还在: 长线没收官（首桶金已预达成, 最靠前未达成的是满仓丰收）
	var has_next := false
	for t in Quests.active():
		if String(t["id"]) == "milestone" and not String(t["title"]).is_empty():
			has_next = true
		print("    [info] 任务栏: %s / %s" % [String(t["title"]), String(t["desc"])])
	_ck(has_next, "终局达成后任务栏仍指着下一站, 长线继续")
	# 存档往返: grand 里程碑进度进档不丢
	var d := Quests.to_dict()
	Quests.reset_all()
	Quests.from_dict(d)
	_ck(Quests.milestone_done("ms_prestige") and Quests.milestone_done("ms_lord")
		and Quests.milestone_done("ms_unify"), "存档往返: 终局三连进度还原")
	_ck(Nations.contract == "封臣" and Nations.fief != "", "契约还在, 想怎么玩还怎么玩")

# ---------------- 工具 ----------------
func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().process_frame

func _shot(nm: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		img.save_png(ProjectSettings.globalize_path("%s/e26_%s.png" % [OUT, nm]))
		print("  [shot] e26_%s.png" % nm)
	else:
		print("  [!!] 截图失败: viewport 纹理为空")
