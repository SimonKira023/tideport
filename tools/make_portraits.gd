# tools/make_portraits.gd —— 剧情对话框头像（e22 版: 二次元像素 sheet 裁剪 + 改造）
#
# 跑一次就够:
#   Godot_console.exe --headless --path . --script res://tools/make_portraits.gd
#
# 输出 res://resources/texture/portraits/ 下 42 张 128x128 PNG:
#   player.png  主角（草帽 + 红领巾）
#   goblin.png  哥布林商贩（保留旧程序化画法, 2x 放大）
#   slave_00..19.png 伙伴头像 —— 按**像素模型**分组(slave_npc.gd MODELS: Alex男/Lyria女/
#   Manu女·深肤/Tori女), 发色带对齐 slave_npc.gd RECIPES 的目标色; 名字池已按模型性别分池
#   lord_<镇id>.png  十五镇领主, captain_<国id>.png  五国巡逻百夫长
#
# e22 画法: 从 resources/character 的 7 张参考 sheet 裁格子 ->
#   抠底(flood fill) -> 镜像/发色偏移 -> 贴上渐变底 ->
#   程序化配件(王冠/草帽/头盔/头巾/眼罩/胡子/疤/耳环/毛领) ->
#   同底多人时靠 表情格不同 + 配件 + 镜像 + 底色 拉开差距。
#   性别红线: 女名配女脸, 男名配男脸, 绝不串。
extends SceneTree

const OUT_DIR := "res://resources/texture/portraits"
const CHR_DIR := "res://resources/character"
const SIZE := 128

# 五国领主: 每镇一位, 文件名 lord_<镇id>.png
const LORD_IDS := [
	"chenxi_cap", "chenxi_port", "chenxi_bridge",
	"beiling_cap", "beiling_valley", "beiling_pine",
	"xichuan_cap", "xichuan_gold", "xichuan_reed",
	"tieyan_cap", "tieyan_stone", "tieyan_cliff",
	"canglang_cap", "canglang_pasture", "canglang_camp",
]
# 每国一位巡逻百夫长, 文件名 captain_<国id>.png
const CAPTAIN_IDS := ["chenxi", "beiling", "xichuan", "tieyan", "canglang"]

# ---------------- 参考 sheet 登记 ----------------
# cell = 每格边长(px); 384x385 那张按 192 分(末行 1px 余量裁掉)
const SHEETS := {
	"s1": {"file": "1839-1517727454-2038049968.webp", "cell": 128},   # 红发少女 2x2
	"s2": {"file": "1839-1527975814-179663914.webp", "cell": 128},    # 眼镜女 2x2
	"s3": {"file": "1839-1546603454-1056271322.webp", "cell": 128},   # 橙发白花 2x2
	"s4": {"file": "1839-1551714479-1499681361.webp", "cell": 192},   # 橙红侧辫 2x2
	"s5": {"file": "1839-1772495223-2145691403.webp", "cell": 128},   # 六女 3x2
	"s6": {"file": "1839-1779261226-1953943102.webp", "cell": 128},   # 军装男/托腮女/橙发女/眼镜男 2x2
	"s7": {"file": "1839-1781627148-492089847.webp", "cell": 128},    # 六人 3x2
}

# ---------------- 角色映射表 ----------------
# cell: [sheet, 列, 行];  锚点(格内比例): ht 发顶 / ey 眼 / ch 下巴 / fx 脸心x / rx 半脸宽
# opts: flip 镜像 / hue 发色带改色{band,to,vmul,smin,smax,vmin,smul,sset} / skin 肤色调整 / acc 配件
# 配件(e24b): 头上只许王冠 —— 草帽/头盔已按用户要求全部移除;
# e56: 花名册缩编 8 人后原始格天然全不同, 精修给 8 人各配**专属**配件拉开个性
#   (布恩疤/娜雅左耳环/珞琳额巾/咪露眼罩/塔洛胡茬/海莉右耳环/珂丹额饰/雪莱毛领);
# 通用保留 王冠/耳环/疤/胡茬/领巾/毛领。
# e28h: 背景**全角色统一** BG_UNI —— 用户反馈有的头像底色发绿, 全部拉齐一个底;
# e29d: 伙伴头像**一格一人摊匀**(仅 Alex 男脸 4 张不够, s6(0,0) 复用一次靠 flip+发色差),
# 发色带对齐 slave_npc.gd RECIPES 的目标色(整层 tint 染色已按用户要求废除)。
const BG_UNI := ["28303a", "e8c060"]
const SPECS := {
	# ============================================================
	# 伙伴头像按**像素模型**分组（唯一真相源 = slave_npc.gd 的 MODELS/MODEL_MALE）:
	#   i%4=0 Alex  男·橙金短发 -> 男脸仅 4 张: s6(0,0)/s7(1,0)/s6(1,1)/s7(2,0)
	#   i%4=1 Lyria 女·棕红卷发 -> s3 橙发白毛领四表情 / s1 红发少女
	#   i%4=2 Manu  女·黑发白帽粉肤 -> s5 五格(紫发压黑/深肤/兔耳/金发/红发)
	#   i%4=3 Tori  女·橙红长发 -> s4 侧辫四格 / s7(1,1) 橙金长发
	# hue 的 to/vmul/sset 对齐 slave_npc.gd RECIPES 各人目标发色。
	# 名字不再参与头像性别 —— 招募名字池已按模型性别分池（slaves.gd NAMES_M/NAMES_F）。
	# ---- 主角(=Josh: 黑短发男孩, D 底紫发压黑; e24b 去掉草帽) ----
	"player": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.68, 0.88], "to": 0.05, "vmul": 0.30},
		"acc": ["neck"]},
	# ---- Alex 组(男·橙金短发): 发色对齐 RECIPES 00/04/08/12/16 ----
	# e56: 布恩(刀客队长)—— 右颊疤, 唯一带 scar 的伙伴
	"slave_00": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"acc": ["scar"]},
	"slave_04": {"cell": ["s7", 1, 0], "ht": 0.03, "ey": 0.32, "ch": 0.58, "rx": 0.22,
		"hue": {"band": [0.03, 0.14], "to": 0.07, "vmul": 0.55},
		"acc": ["stub_2a2228"]},
	"slave_08": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"flip": true, "hue": {"band": [0.03, 0.14], "to": 0.22, "vmul": 0.75}},
	"slave_12": {"cell": ["s6", 1, 1], "ht": 0.05, "ey": 0.32, "ch": 0.57, "rx": 0.23,
		"hue": {"band": [0.45, 0.75], "to": 0.55, "vmul": 1.30, "smin": 0.10}},
	"slave_16": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.55, 0.90], "to": 0.80, "vmul": 0.90, "smul": 0.75}},
	# ---- Lyria 组(女·棕红卷发): 01 本色 / 05 金 / 09 青 / 13 紫 / 17 暗红褐 ----
	# e56: 娜雅(农妇)左耳金环 / 海莉(水手)右耳金环 —— 一对耳环分挂两边
	"slave_01": {"cell": ["s3", 0, 0], "ht": 0.06, "ey": 0.33, "ch": 0.58, "rx": 0.24,
		"acc": ["ear_l"]},
	"slave_05": {"cell": ["s3", 1, 0], "ht": 0.06, "ey": 0.33, "ch": 0.58, "rx": 0.24,
		"hue": {"band": [0.02, 0.14], "to": 0.11, "vmul": 1.05},
		"acc": ["ear_r"]},
	"slave_09": {"cell": ["s3", 0, 1], "ht": 0.06, "ey": 0.33, "ch": 0.58, "rx": 0.24,
		"hue": {"band": [0.02, 0.14], "to": 0.52, "vmul": 0.80}},
	"slave_13": {"cell": ["s3", 1, 1], "ht": 0.06, "ey": 0.33, "ch": 0.58, "rx": 0.24,
		"hue": {"band": [0.02, 0.14], "to": 0.72, "vmul": 0.80}},
	"slave_17": {"cell": ["s1", 1, 0], "ht": 0.10, "ey": 0.34, "ch": 0.60, "rx": 0.24,
		"hue": {"band": [0.88, 0.12], "to": 0.00, "vmul": 0.60}},
	# ---- Manu 组(女·黑发白帽·粉肤): 02 黑 / 06 玫红 / 10 青 / 14 草绿 / 18 金橙 ----
	# e56: 珞琳(木匠)木色额巾 / 珂丹(园丁)藤绿额饰
	"slave_02": {"cell": ["s5", 0, 0], "ht": 0.06, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.6, 0.93], "to": 0.75, "vmul": 0.16, "smin": 0.36},
		"skin": [0.62, 0.92, 1.0, 0.98, 2.0],
		"acc": ["band_8a6a42"]},
	"slave_06": {"cell": ["s5", 0, 1], "ht": 0.06, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.0, 0.15], "to": 0.93, "vmul": 1.25, "sset": 0.55},
		"acc": ["circlet_5a7a42"]},
	"slave_10": {"cell": ["s5", 1, 0], "ht": 0.06, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.45, 0.75], "to": 0.52, "vmul": 1.0, "sset": 0.50},
		"skin": [0.62, 0.92, 1.0, 0.98, 2.0]},
	"slave_14": {"cell": ["s5", 1, 1], "ht": 0.06, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.04, 0.20], "to": 0.30, "vmul": 1.0, "sset": 0.50},
		"skin": [0.62, 0.92, 1.0, 0.98, 2.0]},
	"slave_18": {"cell": ["s5", 2, 1], "ht": 0.06, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.88, 0.12], "to": 0.09, "vmul": 1.0, "sset": 0.60},
		"skin": [0.62, 0.92, 1.0, 0.98, 2.0], "flip": true, "acc": ["ear_l"]},
	# ---- Tori 组(女·橙红长发): 03 本色 / 07 金 / 11 青绿 / 15 蓝紫 / 19 玫红 ----
	# e56: 咪露(猎手)左眼眼罩 / 雪莱(学者)银白毛领
	"slave_03": {"cell": ["s4", 0, 0], "ht": 0.10, "ey": 0.32, "ch": 0.56, "rx": 0.22,
		"acc": ["patch"]},
	"slave_07": {"cell": ["s4", 1, 0], "ht": 0.10, "ey": 0.32, "ch": 0.56, "rx": 0.22,
		"hue": {"band": [0.02, 0.15], "to": 0.11, "vmul": 1.00},
		"acc": ["furtrim"]},
	"slave_11": {"cell": ["s4", 0, 1], "ht": 0.10, "ey": 0.32, "ch": 0.56, "rx": 0.22,
		"hue": {"band": [0.02, 0.15], "to": 0.45, "vmul": 0.80}},
	"slave_15": {"cell": ["s4", 1, 1], "ht": 0.10, "ey": 0.32, "ch": 0.56, "rx": 0.22,
		"hue": {"band": [0.02, 0.15], "to": 0.66, "vmul": 0.85}},
	"slave_19": {"cell": ["s7", 1, 1], "ht": 0.03, "ey": 0.32, "ch": 0.58, "rx": 0.22,
		"hue": {"band": [0.02, 0.16], "to": 0.90, "vmul": 0.90},
		"flip": true, "acc": ["ear_r"]},
	# ---- 十五镇领主(e24b: 头上只留王冠; e30m: 五国主城的王/女王各用一张**原始**脸,
	# 互不重复 —— 晨曦 s6(0,0) / 西川 s6(1,1) / 铁岩 s7(1,0) / 苍狼 s7(2,0),
	# 北岭改女王(女脸 s3), 属镇领主维持旧搭配) ----
	"lord_chenxi_cap": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"acc": ["crown_f0c040", "stub_8a4a2a"]},
	"lord_chenxi_port": {"cell": ["s6", 1, 1], "ht": 0.05, "ey": 0.32, "ch": 0.57, "rx": 0.23,
		"acc": ["ear_r"]},
	"lord_chenxi_bridge": {"cell": ["s6", 1, 1], "ht": 0.05, "ey": 0.32, "ch": 0.57, "rx": 0.23,
		"acc": ["stub_9a9a9a"]},
	"lord_beiling_cap": {"cell": ["s3", 0, 0], "ht": 0.06, "ey": 0.33, "ch": 0.58, "rx": 0.24,
		"hue": {"band": [0.02, 0.14], "to": 0.55, "vmul": 1.05, "sset": 0.20},
		"acc": ["crown_c0c4d0", "furtrim"]},
	"lord_beiling_valley": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"hue": {"band": [0.03, 0.14], "to": 0.0, "vmul": 0.5},
		"acc": ["stub_6b4226"]},
	"lord_beiling_pine": {"cell": ["s7", 1, 0], "ht": 0.03, "ey": 0.32, "ch": 0.58, "rx": 0.22,
		"acc": ["scar"]},
	"lord_xichuan_cap": {"cell": ["s6", 1, 1], "ht": 0.05, "ey": 0.32, "ch": 0.57, "rx": 0.23,
		"acc": ["stub_d8d8d4"]},
	"lord_xichuan_gold": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"acc": ["stub_6b4226"]},
	"lord_xichuan_reed": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"flip": true, "acc": ["ear_l"]},
	"lord_tieyan_cap": {"cell": ["s7", 1, 0], "ht": 0.03, "ey": 0.32, "ch": 0.58, "rx": 0.22,
		"acc": ["crown_4a4450", "stub_2a2228", "scar"]},
	"lord_tieyan_stone": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.03, 0.14], "to": 0.72, "vmul": 0.7}},
	"lord_tieyan_cliff": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"acc": ["ear_r", "scar"]},
	"lord_canglang_cap": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"flip": true, "acc": ["crown_c8a24b", "stub_2a2420"]},
	"lord_canglang_pasture": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"acc": ["ear_l"]},
	"lord_canglang_camp": {"cell": ["s7", 1, 0], "ht": 0.03, "ey": 0.32, "ch": 0.58, "rx": 0.22,
		"hue": {"band": [0.03, 0.14], "to": 0.0, "vmul": 0.5},
		"acc": ["stub_3a2a1e"]},
	# ---- 五国百夫长(e24b: 头盔全撤, 改发色) ----
	"captain_chenxi": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"hue": {"band": [0.03, 0.14], "to": 0.0, "vmul": 0.6},
		"acc": ["scar"]},
	"captain_beiling": {"cell": ["s7", 1, 0], "ht": 0.03, "ey": 0.32, "ch": 0.58, "rx": 0.22,
		"hue": {"band": [0.03, 0.14], "to": 0.72, "vmul": 0.8}},
	"captain_xichuan": {"cell": ["s6", 1, 1], "ht": 0.05, "ey": 0.32, "ch": 0.57, "rx": 0.23},
	"captain_tieyan": {"cell": ["s7", 2, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.22,
		"hue": {"band": [0.03, 0.14], "to": 0.0, "vmul": 0.5},
		"acc": ["scar"]},
	"captain_canglang": {"cell": ["s6", 0, 0], "ht": 0.05, "ey": 0.30, "ch": 0.55, "rx": 0.23,
		"flip": true, "hue": {"band": [0.03, 0.14], "to": 0.06, "vmul": 0.55}},
}

var _sheet_cache: Dictionary = {}

# 男底四格的画布直坐标锚点(128 系, 实测后按 e29d 缩放 118->126 换算):
# ht 发顶 / ey 眼 / ch 下巴 / rx 半脸宽
# e30m: 贴底改 oy = SIZE - th 后整幅下移 2px, ht/ey/ch 同步 +2(原实测值 -2)。
# 女底不挂重配件, 仍走格内分数锚点。
const CANCHOR := {
	"s6-0-0": {"ht": 6, "ey": 51, "ch": 81, "rx": 28},
	"s6-1-1": {"ht": 6, "ey": 53, "ch": 81, "rx": 26},
	"s7-1-0": {"ht": 11, "ey": 60, "ch": 87, "rx": 26},
	"s7-2-0": {"ht": 2, "ey": 54, "ch": 79, "rx": 27},
}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for nm in SPECS:
		_make(nm, SPECS[nm])
	_save("goblin", _goblin())
	print("[头像] 画完 %d 张 -> " % (SPECS.size() + 1), OUT_DIR)
	quit(0)

func _save(nm: String, img: Image) -> void:
	var err := img.save_png("%s/%s.png" % [OUT_DIR, nm])
	if err != OK:
		push_error("存图失败 %s: %d" % [nm, err])

# ================= sheet 载入 =================
func _sheet(key: String) -> Image:
	if _sheet_cache.has(key):
		return _sheet_cache[key]
	var fa := FileAccess.open(CHR_DIR + "/" + String(SHEETS[key]["file"]), FileAccess.READ)
	if fa == null:
		push_error("参考图读不了: " + key)
		quit(1)
		return Image.new()
	var img := Image.new()
	var err := img.load_webp_from_buffer(fa.get_buffer(fa.get_length()))
	if err != OK:
		push_error("webp 解码失败: " + key)
		quit(1)
		return Image.new()
	img.convert(Image.FORMAT_RGBA8)
	_sheet_cache[key] = img
	return img

# ================= 单人管线 =================
func _make(nm: String, sp: Dictionary) -> void:
	var sheet := _sheet(String(sp["cell"][0]))
	var cs := int(SHEETS[String(sp["cell"][0])]["cell"])
	var src := sheet.get_region(Rect2i(int(sp["cell"][1]) * cs, int(sp["cell"][2]) * cs, cs, cs))
	_key_bg(src)
	if bool(sp.get("flip", false)):
		src.flip_x()
	if sp.has("hue"):
		_hue_band(src, sp["hue"])
	# skin: 肤色调色 —— 只动「色相带内 + 低饱和 + 偏亮」的像素(=皮肤高光/底色),
	# 饱和的头发和暗部衣服都不碰。格式 [h_min, h_max, v_mul, s_cap, s_mul]:
	# Manu 素材粉肤 —— v 不压暗(1.0), 饱和度翻倍提粉, 上限 0.98 防过艳。
	if sp.has("skin"):
		var sk: Array = sp["skin"]
		for yy0 in src.get_height():
			for xx0 in src.get_width():
				var sc0 := src.get_pixel(xx0, yy0)
				if sc0.a >= 0.1 and sc0.s <= 0.34 and sc0.v >= 0.6 \
						and sc0.h >= float(sk[0]) and sc0.h <= float(sk[1]):
					sc0.v *= float(sk[2])
					sc0.s = minf(sc0.s * float(sk[4]), float(sk[3]))
					src.set_pixel(xx0, yy0, sc0)
	var bb := _bbox(src)
	if bb.size.x <= 0 or bb.size.y <= 0:
		push_error(nm + " 抠完是空的")
		return
	# 等比缩放到高 126 贴满画框(e29d: 头像要贴边框; 超宽再压到 126), 最近邻保像素感
	var th := 126
	var tw := int(round(float(bb.size.x) * th / float(bb.size.y)))
	var s := float(th) / float(bb.size.y)
	if tw > 126:
		tw = 126
		th = int(round(float(bb.size.y) * 126.0 / float(bb.size.x)))
		s = float(th) / float(bb.size.y)
	var cut := src.get_region(bb)
	cut.resize(tw, th, Image.INTERPOLATE_NEAREST)
	# 画布: 渐变底 + 径向柔光 + 角落光斑
	var canvas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# e28h: SPECS 全部删 bg 键, 统一走 BG_UNI(深蓝灰+金), 与主角头像同底
	var bgarr: Array = sp.get("bg", BG_UNI)
	var lo := Color(String(bgarr[0]))
	var accent := Color(String(bgarr[1]))
	_paint_bg(canvas, lo, accent)
	var ox := (SIZE - tw) / 2
	# e30m: 贴到画布最底(oy+th == SIZE), 下巴/胸口顶到框底, 不再留 2px 空带
	var oy := SIZE - th
	for y in th:
		for x in tw:
			var c := cut.get_pixel(x, y)
			if c.a > 0.99:
				canvas.set_pixel(ox + x, oy + y, c)
			elif c.a > 0.01:
				canvas.set_pixel(ox + x, oy + y, canvas.get_pixel(ox + x, oy + y).lerp(c, c.a))
	# 锚点: 男底四格用画布直坐标(实测), 其余用格内分数换算
	var ckey := "%s-%d-%d" % [sp["cell"][0], sp["cell"][1], sp["cell"][2]]
	var fx: float
	var ey: float
	var ht: float
	var ch: float
	var rx: float
	if CANCHOR.has(ckey):
		var ca: Dictionary = CANCHOR[ckey]
		fx = 64.0
		ey = float(ca["ey"])
		ht = float(ca["ht"])
		ch = float(ca["ch"])
		rx = float(ca["rx"])
	else:
		var off := Vector2(float(ox) - float(bb.position.x) * s, float(oy) - float(bb.position.y) * s)
		fx = float(cs) * 0.5 * s + off.x
		ey = float(sp["ey"]) * float(cs) * s + off.y
		ht = float(sp["ht"]) * float(cs) * s + off.y
		ch = float(sp["ch"]) * float(cs) * s + off.y
		rx = float(sp["rx"]) * float(cs) * s
	var cv := CV.new(canvas)
	for a in sp.get("acc", []):
		_accessory(cv, String(a), fx, ey, ht, ch, rx)
	_save(nm, canvas)

# ---------------- 抠底: 四角种子各自独立 flood fill ----------------
# e28h: s3/s4 素材头发顶到格边, 旧的「8 点平均色 + 四边全入栈」参考色被头发拉偏,
# 格内背景抠不净 -> 头像残留大片绿底。改为每个角点用自己的颜色独立泛洪。
func _key_bg(img: Image, tol := 44.0) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var lim := tol / 255.0
	for seed in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		var bg := img.get_pixel(seed.x, seed.y)
		if bg.a < 0.1:
			continue
		var stack: Array[Vector2i] = [seed]
		while stack.size() > 0:
			var p: Vector2i = stack.pop_back()
			if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
				continue
			var idx := p.y * w + p.x
			if visited[idx] != 0:
				continue
			visited[idx] = 1
			var c := img.get_pixel(p.x, p.y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > lim:
				continue
			img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
			stack.append(Vector2i(p.x + 1, p.y))
			stack.append(Vector2i(p.x - 1, p.y))
			stack.append(Vector2i(p.x, p.y + 1))
			stack.append(Vector2i(p.x, p.y - 1))

func _bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.1:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if x1 < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

# ---------------- 发色偏移: 色相带内局部改色(对齐 slave_npc.gd _band_hit) ----------------
# band [h0,h1]: h0>h1 = 跨 0/1 环绕带; to 目标色相; vmul 明度倍率; smul/sset 饱和倍率/定值;
# smin/smax 饱和门槛(挡住低饱和的皮肤/布料), vmin/vmax 明度门槛。
func _hue_band(img: Image, opt: Dictionary) -> void:
	var h0 := float(opt["band"][0])
	var h1 := float(opt["band"][1])
	var wrap := h0 > h1
	var to := float(opt["to"])
	var vmul := float(opt.get("vmul", 1.0))
	var smul := float(opt.get("smul", 1.0))
	var smin := float(opt.get("smin", 0.15))
	var smax := float(opt.get("smax", 1.0))
	var vmin := float(opt.get("vmin", 0.08))
	var vmax := float(opt.get("vmax", 1.0))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.1 or c.s < smin or c.s > smax or c.v < vmin or c.v > vmax:
				continue
			var hit := (c.h >= h0 and c.h <= h1) if not wrap else (c.h >= h0 or c.h <= h1)
			if not hit:
				continue
			c.h = to
			c.v = clampf(c.v * vmul, 0.0, 1.0)
			c.s = clampf(c.s * smul, 0.0, 1.0)
			if opt.has("sset"):
				c.s = clampf(float(opt["sset"]), 0.0, 1.0)
			img.set_pixel(x, y, c)

# ================= 画布 + 配件 =================
class CV:
	var img: Image

	func _init(i: Image) -> void:
		img = i

	func px(x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
			return
		img.set_pixel(x, y, c)

	func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
		for yy in range(y, y + h):
			for xx in range(x, x + w):
				px(xx, yy, c)

	func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
		for yy in range(int(cy - ry), int(cy + ry) + 1):
			var t := (yy - cy) / ry
			var dx := rx * sqrt(maxf(0.0, 1.0 - t * t))
			for xx in range(int(cx - dx), int(cx + dx) + 1):
				px(xx, yy, c)

func darker(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

func _paint_bg(canvas: Image, lo: Color, accent: Color) -> void:
	var hi := lo.lerp(accent, 0.35).lightened(0.14)
	for y in SIZE:
		var c := lo.lerp(hi, float(y) / float(SIZE - 1))
		for x in SIZE:
			canvas.set_pixel(x, y, c)
	for y in range(3, 104):
		for x in range(8, 120):
			var d := Vector2(x - 64, y - 54).length()
			if d < 54.0:
				var p := canvas.get_pixel(x, y)
				canvas.set_pixel(x, y, p.lerp(Color(1.0, 0.97, 0.9), 0.13 * (1.0 - d / 54.0)))
	for y in range(10, 60):
		for x in range(76, 124):
			var d2 := Vector2(x - 108, y - 24).length()
			if d2 < 32.0:
				var p2 := canvas.get_pixel(x, y)
				canvas.set_pixel(x, y, p2.lerp(accent, 0.22 * (1.0 - d2 / 32.0)))

func _accessory(cv: CV, kind: String, fx: float, ey: float, ht: float, ch: float, rx: float) -> void:
	var parts := kind.split("_")
	match parts[0]:
		"crown":                                   # crown_<metal>: 王冠(五尖+宝石)
			var m := Color(parts[1])
			var bw := int(rx * 1.5)
			var by := maxi(int(ht) - 4, 8)   # e29d 贴边框后发顶到 0, 王冠压在头发上沿防全裁
			cv.rect(int(fx) - bw / 2, by, bw, 6, m)
			cv.rect(int(fx) - bw / 2, by, bw, 1, m.lightened(0.35))
			cv.rect(int(fx) - bw / 2, by + 5, bw, 1, darker(m, 0.7))
			for i in 5:
				var hx := int(fx) - bw / 2 + 2 + i * (bw - 5) / 4
				var hh := 13 if i == 2 else (9 if i % 2 == 1 else 6)
				cv.rect(hx - 1, by - hh, 3, hh, m)
				cv.px(hx, by - hh, m.lightened(0.4))
			cv.rect(int(fx) - 2, by + 1, 4, 4, Color("c03040"))
		"circlet":                                 # circlet_<c>: 细箍+中石(额头)
			var cm := Color(parts[1])
			var cw := int(rx * 1.6)
			cv.rect(int(fx) - cw / 2, int(ht) + 10, cw, 4, cm)
			cv.rect(int(fx) - cw / 2, int(ht) + 13, cw, 1, darker(cm, 0.7))
			cv.rect(int(fx) - 2, int(ht) + 9, 4, 5, Color("3a7a4a"))
		"straw":                                   # 草帽: 圆顶+宽檐+红带
			var brim := int(ht + (ey - ht) * 0.52)
			for yy in range(brim - 21, brim + 3):   # 圆顶(檐上方才画)
				var t := float(yy - (brim - 10)) / 17.0
				var hw := 27.0 * sqrt(maxf(0.0, 1.0 - t * t))
				cv.rect(int(fx - hw), yy, int(hw * 2), 1, Color("d8b25a"))
			cv.rect(int(fx) - 26, brim - 8, 52, 3, Color("a5803a"))   # 帽带
			cv.rect(int(fx) - 26, brim - 5, 52, 1, Color("8f6c30"))
			cv.ellipse(fx, float(brim), 46.0, 7.5, Color("d8b25a"))   # 宽檐
			cv.ellipse(fx, float(brim) + 3.0, 44.0, 5.5, Color("c09a48"))
			cv.rect(int(fx) - 5, brim - 22, 10, 2, Color("e8c878"))   # 顶高光
		"helm":                                    # helm_<metal>[_fur|_weave|_plume]
			var hm := Color(parts[1])
			var hb := int(ey) - 10                 # 盔檐(眉上方)
			var top := int(ht) - 6
			for yy in range(top, hb):
				var t2 := float(hb - yy) / float(hb - top)
				var hw2 := rx * 1.38 * sqrt(minf(1.0, t2 * 2.1))
				cv.rect(int(fx - hw2), yy, int(hw2 * 2), 1, hm)
				cv.px(int(fx - hw2), yy, darker(hm, 0.7))
				cv.px(int(fx + hw2) - 1, yy, darker(hm, 0.7))
			cv.rect(int(fx) - int(rx * 1.38), hb - 2, int(rx * 2.76), 4, darker(hm, 0.72))
			cv.rect(int(fx) - 8, top + 1, 16, 2, hm.lightened(0.3))
			if parts.size() > 2 and parts[2] == "fur":     # 白毛边
				cv.rect(int(fx) - int(rx * 1.32), hb + 2, int(rx * 2.64), 7, Color("dcdce4"))
				for i in 10:
					cv.rect(int(fx) - int(rx * 1.26) + i * int(rx * 0.26), hb + 7, 2, 3, Color("b8b8c4"))
			elif parts.size() > 2 and parts[2] == "weave": # 藤编纹
				for yy2 in [top + 6, top + 12, top + 18]:
					cv.rect(int(fx) - int(rx * 1.25), yy2, int(rx * 2.5), 1, darker(hm, 0.6))
			elif parts.size() > 2 and parts[2] == "plume": # 盔缨(盔顶红嵴, 画布内)
				cv.ellipse(fx, float(top) + 3.0, 13.0, 6.0, Color("8a3a5a"))
				cv.ellipse(fx - 3.0, float(top) + 2.0, 7.0, 3.0, Color("a34a6e"))
				for i in 5:
					cv.rect(int(fx) - 8 + i * 4, top - 2 + (i % 2), 2, 4, Color("8a3a5a"))
		"band":                                    # band_<c>: 额巾+右侧结带
			var bc := Color(parts[1])
			var b0 := int(ht + (ey - ht) * 0.30)
			var b1 := int(ht + (ey - ht) * 0.62)
			cv.rect(int(fx - rx * 1.15), b0, int(rx * 2.3), b1 - b0, bc)
			cv.rect(int(fx - rx * 1.15), b1 - 2, int(rx * 2.3), 2, darker(bc, 0.7))
			cv.rect(int(fx + rx * 1.15), b0, 8, 4, bc)                # 结
			cv.rect(int(fx + rx * 1.15) + 6, b0 + 3, 10, 3, darker(bc, 0.85))
			cv.rect(int(fx + rx * 1.15) + 5, b0 - 4, 8, 3, bc.darkened(0.1))
		"patch":                                   # 眼罩: 左眼+斜带
			var ex := int(fx - rx * 0.55)
			cv.rect(ex - 8, int(ey) - 5, 16, 11, Color("181418"))
			cv.rect(ex - 8, int(ey) - 5, 16, 1, Color("2a242a"))
			for i in 16:
				cv.px(int(fx - rx * 1.1) + i, int(ey) - 11 + i / 2, Color("181418"))
		"scar":                                    # 疤: 右颊斜四点
			var sx := int(fx + rx * 0.42)
			var sy := int(ey) + 9
			cv.px(sx, sy, darker(Color(0.9, 0.7, 0.6), 0.72))
			cv.px(sx + 1, sy + 1, darker(Color(0.9, 0.7, 0.6), 0.78))
			cv.px(sx + 2, sy + 2, darker(Color(0.9, 0.7, 0.6), 0.72))
			cv.px(sx + 1, sy - 1, darker(Color(0.9, 0.7, 0.6), 0.78))
		"ear_l":                                   # 左耳金环
			cv.rect(int(fx - rx * 1.05), int(ey + (ch - ey) * 0.30), 3, 4, Color("f0c040"))
		"ear_r":
			cv.rect(int(fx + rx * 1.05) - 3, int(ey + (ch - ey) * 0.30), 3, 4, Color("f0c040"))
		"stub":                                    # stub_<c>: 胡茬(颌区撒点, 避开嘴部)
			var sc := Color(parts[1])
			var m0 := int(ey + (ch - ey) * 0.66)
			var m1 := int(ey + (ch - ey) * 0.98)
			for yy4 in range(int(ey + (ch - ey) * 0.62), mini(int(ch) + 6, 127)):
				for xx2 in range(int(fx - rx * 0.88), int(fx + rx * 0.88)):
					if (xx2 + yy4) % 2 == 0:
						if yy4 >= m0 and yy4 <= m1 and absf(xx2 - fx) < rx * 0.36:
							continue               # 嘴部留空(咧嘴的白牙别撒点)
						var under := cv.img.get_pixel(xx2, yy4)
						cv.px(xx2, yy4, under.lerp(sc, 0.34))
		"neck":                                    # 红领巾(e30m: 随贴底下移 2px)
			cv.rect(int(fx) - 12, 114, 24, 5, Color("b03a3a"))
			cv.rect(int(fx) - 12, 118, 24, 1, Color("8a2a2a"))
			cv.rect(int(fx) - 3, 118, 7, 7, Color("b03a3a"))
			cv.rect(int(fx) - 3, 124, 7, 2, Color("8a2a2a"))
			cv.px(int(fx) + 2, 119, Color("d86a6a"))
		"furtrim":                                 # 银白毛领(e30m: 随贴底下移 2px)
			cv.rect(int(fx) - 26, 108, 52, 9, Color("dcdce4"))
			cv.rect(int(fx) - 26, 108, 52, 2, Color("eeeef4"))
			for i in 11:
				cv.rect(int(fx) - 26 + i * 5, 115, 2, 4, Color("b8b8c4"))

# ================= 哥布林(保留旧程序化画法, 2x 放大到 128) =================
func _goblin() -> Image:
	var cv := CV.new(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	cv.img.fill(Color(0, 0, 0, 0))
	# e28h: 背景统一 BG_UNI, 与其余头像同底(去绿)
	var glo := Color(String(BG_UNI[0]))
	var ghi := glo.lerp(Color(String(BG_UNI[1])), 0.35).lightened(0.14)
	for y in 64:
		var bgc := glo.lerp(ghi, float(y) / 63.0)
		for x in 64:
			cv.px(x, y, bgc)
	var skin := Color("6da34d")
	var skin_hi := Color("7fb95c")
	var cxi := 30
	for y in range(14, 46):
		var t := float(y - 30) / 16.0
		var hw := int(19.0 * sqrt(maxf(0.0, 1.0 - t * t)))
		for x in range(cxi - hw, cxi + hw + 1):
			cv.px(x, y, skin)
		cv.px(cxi + hw, y, darker(skin, 0.78))
		cv.px(cxi - hw + 1, y, skin_hi)
	for side in [-1, 1]:
		var bx: int = cxi + side * 17
		for i in 8:
			var ww := maxi(1, 6 - i / 2)
			cv.rect(bx + side * i, 20 + i * 2, ww, 2, skin)
	cv.ellipse(float(cxi), 15.0, 19.0, 8.0, Color("a03030"))   # 红头巾
	cv.rect(cxi - 19, 13, 38, 3, Color("a03030"))
	cv.rect(cxi - 19, 15, 38, 1, Color("702020"))
	for i in 5:
		cv.px(cxi + 18 + i, 17 + i * 2, Color("a03030"))
	for side in [-1, 1]:
		var ex: int = cxi + side * 8 + (2 if side == 1 else 0)
		for dx in range(-3, 4):
			cv.px(ex + dx, 23, darker(Color("3a2a1e"), 0.8))
			cv.px(ex + dx, 24, darker(Color("3a2a1e"), 0.8))
		for dy in range(25, 32):
			for dx in range(-3, 4):
				cv.px(ex + dx, dy, Color(0.97, 0.96, 0.9))
		for dy in range(25, 32):
			for dx in range(-2, 3):
				var t2 := float(dy - 25) / 6.0
				cv.px(ex + dx, dy, darker(Color("c8a020"), 1.0 - t2).lerp(Color("c8a020").lightened(0.3), t2))
		for dy in range(26, 29):
			for dx in range(-1, 2):
				cv.px(ex + dx, dy, Color("503c08"))
		cv.rect(ex - 2, 25, 2, 2, Color(1, 1, 1))
	cv.ellipse(float(cxi + 2), 35.0, 3.0, 2.0, darker(skin, 0.82))
	cv.rect(cxi - 1, 39, 10, 3, darker(skin, 0.5))
	cv.rect(cxi, 39, 8, 1, Color(0.95, 0.93, 0.85))
	cv.px(cxi + 5, 41, Color("f0c040"))
	cv.px(11, 36, Color("f0c040"))
	cv.rect(cxi + 24, 44, 6, 5, darker(skin, 0.85))
	cv.ellipse(float(cxi + 27), 40.0, 5.0, 5.0, Color("f0c040"))
	cv.ellipse(float(cxi + 26), 39.0, 2.0, 2.0, Color("fff0a0"))
	cv.rect(cxi + 24, 39, 6, 1, Color("a08020"))
	var out := cv.img
	out.resize(128, 128, Image.INTERPOLATE_NEAREST)
	return out
