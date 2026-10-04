# opening.gd —— 序章过场: 五国瓜分, 国破, 流落荒岛 (e42 美化版)
#
# 只在真·新档开播: game.gd 的 reset 分支里 await _play_opening()。
# 读档 / 续档 / 自检 / 探针都不播（自检把 SaveManager.enabled 关了, 双保险）。
# 壳（幕驱动 / 字幕 / 跳过 / 震屏 / 收黑）全在 cutscene_base.gd, 这里只有:
#   · STEPS 八幕文案（跟 w5 版一字不改, 自检 50 节盯着「伙伴」「失踪」两个词）
#   · 自己的布景件（五国旗 / 孤舟 / 荒岛 / 哥布林 / 日出暖光）
#   · 八幕各自的 _scene_* 布景（e42: 加天幕 / 星野 / 云 / 海面 / 光晕 / 雨 / 火星 / 暗角）
#
# ❗成员名别乱改: selftest 46/50 节直接读 _root / _caption / _cloths / _boat / _isle /
#   STEPS / _skip_all / finished, 并要求孤舟荒岛挂在 _root 下、排在字幕之前。
extends "res://scene/cutscene_base.gd"

# 每幕 = [文案, 布景方法名]。提成常量是给 selftest 第 50 节断言文案用的。
# 序章口径: 主角来自旧晨曦国, 国家被五国瓜分 —— 北岭/西川/铁岩/苍狼各占一块,
# 占了故都的新王庭沿用「晨曦」旧国号(就是外交页那位晨曦王 奥朗)。
# 所以五面旗 = 瓜分继承国的旗, 与外交页五国完全对得上。
const STEPS := [
	["大陆历 347 年, 五国瓜分了你的祖国晨曦国.", "_scene_banners_in"],
	["北岭得了北境, 西川吞了粮仓, 铁岩夺了矿脉, 苍狼赶走了西北的马群, 占了故都的新王庭沿用了晨曦的旧国号.", "_scene_war"],
	["晨曦城破. 旧王室的王旗坠海, 宫门在火光里塌了下去.", "_scene_fall"],
	["你是旧王室的血脉. 带着身边的伙伴夺了一条小船, 趁夜逃出火海.", "_scene_sea"],
	["风暴追了你七天七夜. 桅杆断了, 伙伴失踪在巨浪里.", "_scene_storm"],
	["醒来时身边空无一人, 只有海鸟的声音, 和一座没有名字的荒岛.", "_scene_isle"],
	["岛上并非只有你. 东边小岛的桥头, 还住着一个哥布林商贩.", "_scene_goblin"],
	["你一无所有, 可土地还在. 找哥布林帮衬一把, 从一把锄头重新开始吧.", "_scene_dawn"],
]

# 天幕配色（e42）: 每一幕的开场先换天, 画面立刻有「时间在走」的感觉
const SKY_WAR_TOP := Color(0.09, 0.03, 0.04)
const SKY_WAR_BOT := Color(0.38, 0.13, 0.07)
const SKY_SEA_TOP := Color(0.03, 0.05, 0.12)
const SKY_SEA_BOT := Color(0.11, 0.17, 0.27)
const SKY_DAWN_TOP := Color(0.28, 0.29, 0.42)
const SKY_DAWN_BOT := Color(0.90, 0.68, 0.47)

var _cloths: Array = []         # 五面旗面 ColorRect, 按 Nations.NATIONS 顺序
var _flag_names: Array = []
var _banners: Control
var _boat: Node2D
var _isle: Node2D
var _goblin: Node2D             # 哥布林商贩剪影 + 小摊（讲东岛桥头那一幕登场）
var _dawn: ColorRect            # 结尾日出的暖光

func steps() -> Array:
	return STEPS

# ---------------- 搭景 ----------------
func _build() -> void:
	super._build()
	_build_banners()
	_build_boat()
	_build_isle()
	_build_goblin()

	# 结尾暖光（荒岛日出）: 加在布景最后 -> 盖在岛和哥布林之上, 字幕之下
	_dawn = ColorRect.new()
	_dawn.color = Color(1.0, 0.78, 0.45, 0.0)
	_dawn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_prop(_dawn)

func _build_banners() -> void:
	_banners = HBoxContainer.new()
	_banners.add_theme_constant_override("separation", 34)
	_banners.anchor_left = 0.5
	_banners.anchor_right = 0.5
	_banners.anchor_top = 0.0
	_banners.anchor_bottom = 0.0
	_banners.offset_top = 120.0
	_banners.offset_left = -210.0
	_banners.offset_right = 210.0
	_banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_prop(_banners)
	for n in Nations.NATIONS:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pole := ColorRect.new()
		pole.color = Color(0.32, 0.26, 0.20)
		pole.custom_minimum_size = Vector2(3, 66)
		pole.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pole.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pole)
		var cloth := ColorRect.new()
		cloth.color = Color(n.get("color", Color.WHITE))
		cloth.custom_minimum_size = Vector2(38, 24)
		cloth.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cloth.modulate = Color(1, 1, 1, 0)          # 入场时逐面点亮
		cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cloth)
		_cloths.append(cloth)
		var nm := _mk_label(String(n.get("name", "")), 11, Color(0.60, 0.56, 0.50))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nm)
		_flag_names.append(nm)

# 夜海孤舟: 船体 + 桅杆 + 主帆 + 前帆 + 三角旗, 全 Polygon2D
# ❗必须挂在 _root 下、且排在字幕之前 —— 用 _add_prop 插到字幕衬条前就自动满足。
func _build_boat() -> void:
	_boat = Node2D.new()
	_boat.visible = false
	_boat.scale = Vector2(2, 2)
	var hull := Polygon2D.new()
	hull.polygon = PackedVector2Array([
		Vector2(-30, 0), Vector2(30, 0), Vector2(20, 12), Vector2(-20, 12)])
	hull.color = Color(0.40, 0.28, 0.18)
	_boat.add_child(hull)
	# 船体吃水线 + 舷边高光: 两条深/浅线, 一条船就有体积了
	var keel := Polygon2D.new()
	keel.polygon = PackedVector2Array([
		Vector2(-22, 9), Vector2(22, 9), Vector2(20, 12), Vector2(-20, 12)])
	keel.color = Color(0.26, 0.17, 0.10)
	_boat.add_child(keel)
	var rail := Polygon2D.new()
	rail.polygon = PackedVector2Array([
		Vector2(-30, 0), Vector2(30, 0), Vector2(30, 2), Vector2(-30, 2)])
	rail.color = Color(0.52, 0.38, 0.25)
	_boat.add_child(rail)
	var mast := Polygon2D.new()
	mast.polygon = PackedVector2Array([
		Vector2(-2, -30), Vector2(2, -30), Vector2(2, 0), Vector2(-2, 0)])
	mast.color = Color(0.30, 0.21, 0.13)
	_boat.add_child(mast)
	var sail := Polygon2D.new()
	sail.polygon = PackedVector2Array([
		Vector2(3, -28), Vector2(3, -3), Vector2(24, -6)])
	sail.color = Color(0.90, 0.86, 0.76)
	_boat.add_child(sail)
	var sail_dk := Polygon2D.new()
	sail_dk.polygon = PackedVector2Array([
		Vector2(3, -28), Vector2(3, -3), Vector2(11, -4.6)])
	sail_dk.color = Color(0.78, 0.74, 0.65)
	_boat.add_child(sail_dk)
	var jib := Polygon2D.new()
	jib.polygon = PackedVector2Array([
		Vector2(-2, -22), Vector2(-2, -4), Vector2(-16, -6)])
	jib.color = Color(0.84, 0.80, 0.71)
	_boat.add_child(jib)
	var pennant := Polygon2D.new()
	pennant.polygon = PackedVector2Array([
		Vector2(2, -30), Vector2(13, -26), Vector2(2, -22)])
	pennant.color = Color(0.78, 0.28, 0.24)
	_boat.add_child(pennant)
	_add_prop(_boat)

# 荒岛: 礁石 + 沙滩 + 草丘 + 两棵椰树, 结尾幕登场
func _build_isle() -> void:
	_isle = Node2D.new()
	_isle.visible = false
	_isle.scale = Vector2(2, 2)
	var reef := Polygon2D.new()
	reef.polygon = PackedVector2Array([
		Vector2(-92, 20), Vector2(94, 18), Vector2(88, 28), Vector2(-86, 30)])
	reef.color = Color(0.30, 0.40, 0.42)
	_isle.add_child(reef)
	var sand := Polygon2D.new()
	sand.polygon = PackedVector2Array([
		Vector2(-78, 10), Vector2(82, 8), Vector2(72, 26), Vector2(-66, 26)])
	sand.color = Color(0.80, 0.72, 0.52)
	_isle.add_child(sand)
	var foam := Polygon2D.new()
	foam.polygon = PackedVector2Array([
		Vector2(-78, 10), Vector2(82, 8), Vector2(80, 12), Vector2(-76, 14)])
	foam.color = Color(0.92, 0.94, 0.88)
	_isle.add_child(foam)
	var hill := Polygon2D.new()
	hill.polygon = PackedVector2Array([
		Vector2(-62, 12), Vector2(-34, -8), Vector2(6, -18),
		Vector2(48, -6), Vector2(70, 12)])
	hill.color = Color(0.40, 0.58, 0.33)
	_isle.add_child(hill)
	var hill_dk := Polygon2D.new()
	hill_dk.polygon = PackedVector2Array([
		Vector2(6, -18), Vector2(48, -6), Vector2(70, 12), Vector2(6, 12)])
	hill_dk.color = Color(0.32, 0.48, 0.28)
	_isle.add_child(hill_dk)
	_isle.add_child(_palm(-44.0, 11.0, 34.0))
	_isle.add_child(_palm(52.0, 9.0, 27.0))
	_add_prop(_isle)

# 一棵椰树剪影: 树干 + 四片叶 + 两个椰子
func _palm(x: float, y: float, h: float) -> Node2D:
	var tr := Node2D.new()
	tr.position = Vector2(x, y)
	var trunk := Polygon2D.new()
	trunk.polygon = PackedVector2Array([
		Vector2(-1.6, 0.0), Vector2(1.6, 0.0),
		Vector2(2.6, -h), Vector2(-0.6, -h - 1.0)])
	trunk.color = Color(0.38, 0.29, 0.19)
	tr.add_child(trunk)
	var leaf := Color(0.26, 0.46, 0.25)
	for i in 4:
		var dir := -1.0 if i % 2 == 0 else 1.0
		var frond := Polygon2D.new()
		var ty := -h - 1.0
		frond.polygon = PackedVector2Array([
			Vector2(1.0, ty), Vector2(dir * (h * 0.55), ty - h * 0.16),
			Vector2(dir * (h * 0.42), ty + h * 0.10)])
		frond.color = leaf
		tr.add_child(frond)
	for i in 2:
		var nut := Polygon2D.new()
		nut.polygon = PackedVector2Array([
			Vector2(-2.0 + float(i) * 4.0, -h + 1.0),
			Vector2(1.0 + float(i) * 4.0, -h + 1.0),
			Vector2(0.0 + float(i) * 4.0, -h + 4.0)])
		nut.color = Color(0.44, 0.33, 0.20)
		tr.add_child(nut)
	return tr

# 哥布林商贩: 绿皮剪影 + 尖耳 + 小摊, 全 Polygon2D（保持不依赖贴图的原则）
func _build_goblin() -> void:
	_goblin = Node2D.new()
	_goblin.visible = false
	_goblin.scale = Vector2(2, 2)
	var stall_top := Polygon2D.new()
	stall_top.polygon = PackedVector2Array([
		Vector2(-26, -12), Vector2(26, -12), Vector2(22, -6), Vector2(-22, -6)])
	stall_top.color = Color(0.52, 0.38, 0.22)
	_goblin.add_child(stall_top)
	var stall_dk := Polygon2D.new()
	stall_dk.polygon = PackedVector2Array([
		Vector2(-26, -12), Vector2(26, -12), Vector2(25, -9.5), Vector2(-25, -9.5)])
	stall_dk.color = Color(0.38, 0.27, 0.16)
	_goblin.add_child(stall_dk)
	for sx in [-20.0, 20.0]:
		var leg := Polygon2D.new()
		leg.polygon = PackedVector2Array([
			Vector2(sx - 2, -6), Vector2(sx + 2, -6), Vector2(sx + 2, 8), Vector2(sx - 2, 8)])
		leg.color = Color(0.38, 0.27, 0.16)
		_goblin.add_child(leg)
	var g_body := Polygon2D.new()
	g_body.polygon = PackedVector2Array([
		Vector2(-8, -12), Vector2(8, -12), Vector2(6, -30), Vector2(-6, -30)])
	g_body.color = Color(0.36, 0.52, 0.28)
	_goblin.add_child(g_body)
	var g_head := Polygon2D.new()
	g_head.polygon = PackedVector2Array([
		Vector2(-7, -30), Vector2(7, -30), Vector2(8, -40), Vector2(3, -45),
		Vector2(-3, -45), Vector2(-8, -40)])
	g_head.color = Color(0.42, 0.60, 0.32)
	_goblin.add_child(g_head)
	for ear_x in [-8.0, 8.0]:
		var ear := Polygon2D.new()
		ear.polygon = PackedVector2Array([
			Vector2(ear_x, -44), Vector2(ear_x + signf(ear_x) * 7.0, -48), Vector2(ear_x, -38)])
		ear.color = Color(0.42, 0.60, 0.32)
		_goblin.add_child(ear)
	# 摊上一盏小灯: 暖光点, 就知道这儿能做生意
	var lamp := Polygon2D.new()
	lamp.polygon = PackedVector2Array([
		Vector2(-30, -16), Vector2(-24, -16), Vector2(-25.5, -20), Vector2(-28.5, -20)])
	lamp.color = Color(1.0, 0.84, 0.45)
	_goblin.add_child(lamp)
	_add_prop(_goblin)

# ---------------- 各幕布景 ----------------
# 一: 五国旗在燃烧的天边一面面亮起来 (国被瓜分)
func _scene_banners_in() -> void:
	sky_to(SKY_WAR_TOP, SKY_WAR_BOT.darkened(0.45), 0.02)
	stars_on(0.45, 1.6)
	vignette_on(0.52, 1.2)
	glow_at(Vector2(0.5, 0.90), Color(0.95, 0.44, 0.22), 460.0, 0.55, 2.2)
	_banners.modulate.a = 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	for i in _cloths.size():
		var c: ColorRect = _cloths[i]
		tw.tween_property(c, "modulate:a", 1.0, 0.7).set_delay(i * 0.4)

# 二: 战火——地表烧起来, 火星往上飘, 天更红
func _scene_war() -> void:
	sky_to(Color(0.13, 0.03, 0.03), Color(0.50, 0.16, 0.07), 1.6)
	# 远处一排烧着的城郭剪影
	_ridge([[0.0, 0.03], [0.08, 0.07], [0.16, 0.02], [0.26, 0.09], [0.36, 0.04],
		[0.48, 0.10], [0.58, 0.03], [0.70, 0.08], [0.82, 0.04], [0.92, 0.09], [1.0, 0.05]],
		0.86, Color(0.10, 0.03, 0.03, 0.9))
	fx_on("embers", 120)
	glow_at(Vector2(0.5, 0.86), Color(1.0, 0.42, 0.16), 520.0, 0.75, 1.6)
	vignette_on(0.62, 1.2)
	shake(3.5, 1.2)
	var tw := create_tween()
	tw.set_parallel(true)
	for c in _cloths:
		tw.tween_property(c, "modulate", Color(1.35, 0.5, 0.4, 1.0), 0.8)

# 三: 城破——宫门塌下去, 王旗坠海, 满天落灰
func _scene_fall() -> void:
	sky_to(Color(0.06, 0.02, 0.03), Color(0.30, 0.10, 0.06), 1.8)
	# 城墙 + 塌了一角的宫门
	_wall_tower(0.06, 0.36, 0.80, Color(0.09, 0.05, 0.06, 0.95))
	_wall_tower(0.62, 0.32, 0.83, Color(0.09, 0.05, 0.06, 0.95))
	var arch := Polygon2D.new()
	var v := _vw()
	arch.polygon = PackedVector2Array([
		Vector2(0.42 * v.x, 0.86 * v.y), Vector2(0.58 * v.x, 0.86 * v.y),
		Vector2(0.56 * v.x, 0.74 * v.y), Vector2(0.44 * v.x, 0.74 * v.y)])
	arch.color = Color(0.16, 0.07, 0.05, 0.9)
	_add_prop(arch)
	fx_on("embers", 150)
	glow_at(Vector2(0.5, 0.80), Color(1.0, 0.36, 0.12), 560.0, 0.85, 1.4)
	vignette_on(0.72, 1.0)
	shake(6.0, 0.9)
	flash(Color(1.0, 0.55, 0.30), 0.35, 0.7)
	var tw := create_tween()
	tw.set_parallel(true)
	for c in _cloths:
		tw.tween_property(c, "modulate", Color(0.28, 0.26, 0.26, 1.0), 1.4)
	# 晨曦旗（第一面）在风里折下去
	var first: ColorRect = _cloths[0]
	tw.tween_property(first, "rotation_degrees", 24.0, 1.2).set_delay(0.5)
	tw.tween_property(first, "modulate:a", 0.35, 1.2).set_delay(0.5)

# 四: 夜海孤舟——旗帜褪去, 星空和海面亮起来, 小船从画外驶入
func _scene_sea() -> void:
	sky_to(SKY_SEA_TOP, SKY_SEA_BOT, 1.4)
	stars_on(1.0, 1.8)
	clouds_on(0.35, 2.0)
	sea_on(0.56, 1.0, 1.8)
	glow_at(Vector2(0.78, 0.30), Color(0.92, 0.94, 1.0), 300.0, 0.55, 1.6)
	vignette_on(0.48, 1.2)
	fx_off(0.8)
	var v := _vw()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_banners, "modulate:a", 0.0, 0.8)
	_boat.visible = true
	_boat.modulate.a = 0.0
	_boat.position = Vector2(-0.08 * v.x, 0.51 * v.y)
	_boat.rotation_degrees = 0.0
	tw.tween_property(_boat, "modulate:a", 1.0, 1.0).set_delay(0.6)
	tw.tween_property(_boat, "position:x", 0.52 * v.x, 4.0).set_delay(0.6)

# 五: 风暴——暴雨斜打, 闪电撕开天, 船被浪抛起来
func _scene_storm() -> void:
	sky_to(Color(0.05, 0.05, 0.09), Color(0.16, 0.17, 0.22), 0.8)
	stars_on(0.0, 0.6)
	clouds_on(0.9, 0.8)
	fx_on("rain", 170)
	glow_at(Vector2(0.30, 0.24), Color(0.78, 0.84, 1.0), 420.0, 0.40, 0.6)
	vignette_on(0.80, 0.8)
	flash(Color(0.86, 0.90, 1.0), 0.55, 0.5)
	shake(9.0, 0.8)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_boat, "rotation_degrees", 9.0, 0.9)
	tw.tween_property(_boat, "position:y", 0.53 * _vw().y, 0.9)
	tw.chain().tween_property(_boat, "rotation_degrees", -9.0, 0.9)
	tw.parallel().tween_property(_boat, "position:y", 0.48 * _vw().y, 0.9)
	tw.chain().tween_property(_boat, "rotation_degrees", 4.0, 0.9)
	tw.parallel().tween_property(_boat, "position:x", 0.45 * _vw().x, 0.9)

# 六: 荒岛——雨停了, 云缝里漏下月光, 岛从远处推近
func _scene_isle() -> void:
	sky_to(Color(0.10, 0.13, 0.20), Color(0.26, 0.30, 0.36), 1.6)
	fx_off(1.2)
	clouds_on(0.55, 1.4)
	sea_on(0.70, 1.0, 1.6)
	glow_at(Vector2(0.30, 0.26), Color(0.94, 0.95, 1.0), 380.0, 0.50, 1.4)
	vignette_on(0.42, 1.2)
	var v := _vw()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_boat, "modulate:a", 0.0, 1.0)
	_isle.visible = true
	_isle.modulate.a = 0.0
	_isle.position = Vector2(0.50 * v.x, 0.62 * v.y)
	_isle.scale = Vector2(0.6, 0.6)
	tw.tween_property(_isle, "modulate:a", 1.0, 1.4).set_delay(0.4)
	tw.tween_property(_isle, "scale", Vector2(2, 2), 1.4).set_delay(0.4)

# 七: 哥布林商贩——晨雾里的东岛桥头, 摊上一点暖灯
func _scene_goblin() -> void:
	sky_to(Color(0.24, 0.26, 0.30), Color(0.52, 0.50, 0.46), 1.6)
	clouds_on(0.75, 1.4)
	glow_at(Vector2(0.88, 0.20), Color(1.0, 0.88, 0.62), 320.0, 0.40, 1.4)
	vignette_on(0.38, 1.2)
	fx_on("fireflies", 26)
	var v := _vw()
	_goblin.visible = true
	_goblin.modulate.a = 0.0
	_goblin.position = Vector2(0.86 * v.x, 0.55 * v.y)   # 荒岛右侧: 哥布林守着他的小摊
	var tw := create_tween()
	tw.tween_property(_goblin, "modulate:a", 1.0, 0.9).set_delay(0.3)

# 八: 日出——暖光铺满, 尘埃在光里打转, 故事交给游戏第一帧
func _scene_dawn() -> void:
	sky_to(SKY_DAWN_TOP, SKY_DAWN_BOT, 2.2)
	stars_on(0.0, 1.2)
	clouds_on(0.45, 1.6)
	sea_on(0.70, 1.0, 1.0)
	glow_at(Vector2(0.50, 0.66), Color(1.0, 0.82, 0.48), 560.0, 0.90, 2.0)
	vignette_on(0.34, 1.6)
	fx_on("fireflies", 40)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dawn, "color:a", 0.28, 2.2)
	_isle.position.y = _vw().y * 0.58
	_goblin.modulate.a = 1.0