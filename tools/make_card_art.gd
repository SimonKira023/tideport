# tools/make_card_art.gd —— KARDS 式卡面海报合成（纯程序化, 无网络）
#
# 跑一次就够:
#   Godot_console.exe --headless --path . --script res://tools/make_card_art.gd
# 之后补一次导入:
#   Godot_console.exe --headless --path . --import
#
# 构图（KARDS 海报思路: 战场场面, 不要单人立正站桩）:
#   · 单位卡 —— 戏剧性天空为底（三段渐变 + 日/月 + 云带 + 两层远山 + 地面）,
#     纵深三层: 远景两枚暗剪影踩在山脊上 -> 中景一枚侧影 -> 前景主角大图;
#     越远越暗越糊（LANCZOS）, 主角最清晰（NEAREST）—— 距离感全靠清晰度差。
#   · 法术卡 —— 同一套天空 + 中央大图标 + 背后光晕 + 星屑。
#   · 收尾统一像素海报化: LANCZOS 缩半 -> NEAREST 放大 2 倍 -> 1px 阵营描边。
#   · 全部固定种子（按卡名 hash）, 复跑结果一致。
#
# 输出 res://resources/cards_art/ 下两类图, 每种两个尺寸:
#   u_<阵营>_<兵种>_card.png  76x84  —— 手牌立绘
#   u_<阵营>_<兵种>_icon.png  40x44  —— 战场槽位小图（由卡面缩半再放大导出）
#   s_<法术id>_card.png / s_<法术id>_icon.png
#
# 素材来源与许可证见 resources/cards_src/SOURCES.txt（全部 CC0 / Public Domain）。
extends SceneTree

const SRC := "res://resources/cards_src/"
const OUT := "res://resources/cards_art/"
const CELL := 96                 # townguard_* 的格子边长
const ART_W := 76
const ART_H := 84
const ICON_W := 40
const ICON_H := 44

# ---------------- 素材登记 ----------------
# 带 cell 的 = 从 768x192 大图里裁 96px 格子; 不带 = 整图（裁 alpha 包围盒）
const SRC_UNITS := {
	"spear": {"file": "townguard_spearman.png", "cell": [0, 0]},
	"sword": {"file": "townguard_swordsman.png", "cell": [0, 0]},
	"bow": {"file": "townguard_archer.png", "cell": [0, 0]},
	"heavy": {"file": "townguard_heavy_guard.png", "cell": [0, 0]},
	"cap": {"file": "townguard_captain.png", "cell": [0, 0]},
	"flag": {"file": "townguard_standard_bearer.png", "cell": [0, 0]},
}
const SRC_ICONS := {
	"fire": {"file": "kenney_icon_fire.png"},
	"campfire": {"file": "kenney_icon_campfire.png"},
	"sword": {"file": "kenney_icon_sword.png"},
	"shield": {"file": "kenney_icon_shield.png"},
	"bow": {"file": "kenney_icon_bow.png"},
	"flaskb": {"file": "kenney_icon_flask_blue.png"},
	"flaskh": {"file": "kenney_icon_flask_half.png"},
	"hourglass": {"file": "kenney_icon_hourglass.png"},
	"crown": {"file": "kenney_icon_crown.png"},
	"skull": {"file": "kenney_icon_skull.png"},
	"pouch": {"file": "kenney_icon_pouch.png"},
	"book": {"file": "kenney_icon_book.png"},
	"tower": {"file": "kenney_icon_tower.png"},
	"axe": {"file": "pixel_icon_axe.png"},
	"axes": {"file": "pixel_icon_axes_crossed.png"},
	"hammer": {"file": "pixel_icon_hammer.png"},
	"torch": {"file": "pixel_icon_torch.png"},
	"shields": {"file": "pixel_icon_shield_small.png"},
	# 法术也能借单位图: 增援 = 旗手到场（96px 单位图比 16px 图标清楚得多）
	"flag": {"file": "townguard_standard_bearer.png", "cell": [0, 0]},
}

# hue: [目标色相, 明度倍率, 饱和倍率] —— 只动有饱和的像素（smin 很低, 灰蓝甲也跟着走）
func _h(to: float, v := 1.0, s := 1.0) -> Dictionary:
	return {"to": to, "vmul": v, "smul": s}

# ---------------- 单位配方 ----------------
# 玩家兵种（bg = my）: 兵种 -> {src, bg, hue?, fit?}
const UNITS := {
	# —— 我方: 按 Slaves.CLASSES 十档 + 民兵 ——
	"my_民兵":   {"src": "spear", "bg": "my", "hue": [0.08, 0.92, 0.70]},
	"my_新兵":   {"src": "spear", "bg": "my"},
	"my_刀客":   {"src": "sword", "bg": "my"},
	"my_弓手":   {"src": "bow", "bg": "my"},
	"my_骑兵":   {"src": "cap", "bg": "my"},
	"my_剑士":   {"src": "sword", "bg": "my", "hue": [0.58, 1.05, 1.10]},
	"my_神射手": {"src": "bow", "bg": "my", "hue": [0.30, 1.05, 1.05]},
	"my_枪骑兵": {"src": "spear", "bg": "my", "hue": [0.55, 1.02, 1.05]},
	"my_咏剑士": {"src": "sword", "bg": "gold", "hue": [0.10, 1.15, 1.20]},
	"my_狙击手": {"src": "bow", "bg": "gold", "hue": [0.12, 1.12, 1.15]},
	"my_重骑兵": {"src": "heavy", "bg": "gold", "hue": [0.09, 1.10, 1.15]},
	# —— 敌方: 按 FOE_UNITS 四流派全部模板 ——
	"foe_铁骑":   {"src": "cap", "bg": "foe", "hue": [0.98, 0.95, 1.25]},
	"foe_轻骑":   {"src": "cap", "bg": "foe", "hue": [0.94, 1.05, 1.15]},
	"foe_重骑":   {"src": "heavy", "bg": "foe", "hue": [0.99, 0.90, 1.30]},
	"foe_民夫":   {"src": "spear", "bg": "foe", "hue": [0.07, 0.90, 0.60]},
	"foe_山贼":   {"src": "sword", "bg": "foe", "hue": [0.32, 0.92, 1.05]},
	"foe_悍匪":   {"src": "sword", "bg": "foe", "hue": [0.27, 0.80, 1.10]},
	"foe_匪首":   {"src": "flag", "bg": "foe", "hue": [0.30, 0.85, 1.05]},
	"foe_海寇":   {"src": "sword", "bg": "foe", "hue": [0.52, 0.95, 1.20]},
	"foe_浪人":   {"src": "sword", "bg": "foe", "hue": [0.60, 0.85, 0.95]},
	"foe_刀魁":   {"src": "sword", "bg": "foe", "hue": [0.03, 0.82, 1.35]},
	"foe_刀客":   {"src": "sword", "bg": "foe"},
	"foe_弓手":   {"src": "bow", "bg": "foe"},
	"foe_枪骑兵": {"src": "spear", "bg": "foe"},
	"foe_重装":   {"src": "heavy", "bg": "foe", "hue": [0.58, 0.88, 1.00]},
}

# ---------------- 法术配方 ----------------
# 玩家 SUPPORT 五张 + 敌方 FOE_SPELLS 五张
# Kenney 那批图标本身是**白色剪影**, 所以配 tint 上色（保留 alpha, 加一点上亮下暗）。
# 只有 axe 用了 16px 像素材（本身彩色, 不上 tint）; 交叉双斧的剪影比单斧清楚。
# reinforce 借单位图（旗手）, 配 hue 走"援兵"的草绿。
const SPELLS := {
	"drill":     {"src": "sword", "bg": "my", "tint": [1.0, 0.84, 0.40]},
	"armory":    {"src": "shield", "bg": "my", "tint": [0.78, 0.84, 0.94]},
	"mobilize":  {"src": "pouch", "bg": "my", "tint": [1.0, 0.82, 0.38]},
	"scout":     {"src": "bow", "bg": "my", "tint": [0.56, 0.90, 0.66]},
	"baojia":    {"src": "campfire", "bg": "my", "tint": [1.0, 0.72, 0.42]},
	"fire":      {"src": "fire", "bg": "foe", "tint": [1.0, 0.46, 0.18]},
	"axe":       {"src": "axes", "bg": "foe"},
	"reinforce": {"src": "flag", "bg": "foe", "hue": [0.32, 0.92, 1.05], "fit": 0.78},
	"horns":     {"src": "crown", "bg": "foe", "tint": [1.0, 0.82, 0.34]},
	"rocks":     {"src": "skull", "bg": "foe", "tint": [0.72, 0.70, 0.68]},
}

var _cache := {}

func _initialize() -> void:
	await process_frame      # --script 模式下等一帧再动手
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var n := 0
	for key: String in UNITS.keys():
		var rec: Dictionary = (UNITS[key] as Dictionary).duplicate()
		rec["src"] = SRC_UNITS[String(rec["src"])]
		rec["mode"] = "unit"
		n += _emit("u_" + key, rec)
	for key2: String in SPELLS.keys():
		var rec2: Dictionary = (SPELLS[key2] as Dictionary).duplicate()
		rec2["src"] = SRC_ICONS[String(rec2["src"])]
		rec2["mode"] = "spell"
		rec2["fit"] = float(rec2.get("fit", 0.56))
		n += _emit("s_" + key2, rec2)
	print("[卡面] 程序化海报 %d 张 -> %s" % [n / 2, OUT])
	quit()

func _emit(cname: String, rec: Dictionary) -> int:
	var card := _compose(cname, rec, ART_W, ART_H)
	_posterize(card, String(rec.get("bg", "my")))
	card.save_png(ProjectSettings.globalize_path(OUT) + cname + "_card.png")
	var s: Image = card.duplicate()
	s.resize(ICON_W / 2, ICON_H / 2, Image.INTERPOLATE_LANCZOS)
	s.resize(ICON_W, ICON_H, Image.INTERPOLATE_NEAREST)
	s.save_png(ProjectSettings.globalize_path(OUT) + cname + "_icon.png")
	return 2

# ---------------- 合成 ----------------
func _compose(cname: String, rec: Dictionary, ow: int, oh: int) -> Image:
	var out := Image.create(ow, oh, false, Image.FORMAT_RGBA8)
	_paint_bg(out, String(rec.get("bg", "my")))
	var sp := _sprite(rec.get("src", {}))
	if sp == null:
		return out
	if rec.has("tint"):
		var tc: Array = rec["tint"]
		_tint_flat(sp, Color(float(tc[0]), float(tc[1]), float(tc[2])))
	if rec.has("hue"):
		var h: Array = rec["hue"]
		_hue_band(sp, float(h[0]), float(h[1]), float(h[2]))
	var rng := RandomNumberGenerator.new()
	rng.seed = cname.hash()          # 按卡名固定, 复跑同构图
	if String(rec.get("mode", "unit")) == "spell":
		_compose_spell(out, sp, rec, ow, oh, rng)
	else:
		_compose_unit(out, sp, ow, oh, rng)
	return out

# 单位卡: 远景剪影两枚 -> 中景侧影 -> 前景主角（近处清晰, 远处压暗糊开）
func _compose_unit(out: Image, sp: Image, ow: int, oh: int, rng: RandomNumberGenerator) -> void:
	var dir := 1 if rng.randf() < 0.5 else -1        # 主角偏左还是偏右
	# 远景: 两枚 27% / 24% 高的暗剪影, 踩在远山脊线一带
	var far_y := int(float(oh) * 0.745)
	_layer(out, sp, int(float(ow) * (0.30 if dir > 0 else 0.70)), far_y,
		int(float(oh) * 0.27), 0.46, rng.randf() < 0.5, Image.INTERPOLATE_LANCZOS)
	_layer(out, sp, int(float(ow) * (0.62 if dir > 0 else 0.38)), far_y - 1,
		int(float(oh) * 0.24), 0.52, rng.randf() < 0.5, Image.INTERPOLATE_LANCZOS)
	# 中景: 一枚 45% 高的侧影, 挡在主角斜后方
	_layer(out, sp, int(float(ow) * (0.34 if dir > 0 else 0.66)),
		int(float(oh) * 0.815), int(float(oh) * 0.45), 0.24, dir < 0,
		Image.INTERPOLATE_LANCZOS)
	# 主角: 66% 高, 脚下 0.90 处 + 椭圆脚影
	var th := int(float(oh) * 0.66)
	var fx := int(float(ow) / 2) + dir * int(float(ow) * 0.06)
	var fy := oh - int(round(float(oh) * 0.10))
	_shadow(out, fx, fy - 2, maxi(4, int(float(th) * 0.34)))
	_layer(out, sp, fx, fy, th, 0.0, false, Image.INTERPOLATE_NEAREST)

# 法术卡: 中央大图标 + 背后光晕 + 落影 + 星屑
func _compose_spell(out: Image, sp: Image, rec: Dictionary, ow: int, oh: int,
		rng: RandomNumberGenerator) -> void:
	var cx := float(ow) / 2
	var cy := float(oh) * 0.46
	var glow := Color(0.92, 0.86, 0.66)
	if rec.has("tint"):
		var tc: Array = rec["tint"]
		glow = Color(float(tc[0]), float(tc[1]), float(tc[2])).lightened(0.25)
	var r := float(oh) * 0.62
	for y in oh:
		for x in ow:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var d := sqrt(dx * dx + dy * dy) / r
			if d < 1.0:
				var k := 0.34 * pow(1.0 - d, 2.0)
				var c := out.get_pixel(x, y)
				out.set_pixel(x, y, Color(lerpf(c.r, glow.r, k),
					lerpf(c.g, glow.g, k), lerpf(c.b, glow.b, k), 1.0))
	var th := int(float(oh) * float(rec.get("fit", 0.56)))
	var nw := maxi(1, int(round(float(th) * float(sp.get_width()) / float(maxi(1, sp.get_height())))))
	var im: Image = sp.duplicate()
	# 16px 像素材用 NEAREST 保像素棱角, Kenney 矢量图用 LANCZOS 缩平滑
	var interp := Image.INTERPOLATE_LANCZOS
	if String(rec.get("src", {}).get("file", "")).begins_with("pixel_icon"):
		interp = Image.INTERPOLATE_NEAREST
	im.resize(nw, maxi(1, th), interp)
	_shadow(out, int(cx), int(float(oh) * 0.82), maxi(4, int(float(nw) * 0.42)))
	out.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()),
		Vector2i(int(cx) - im.get_width() / 2, int(cy) - th / 2))
	for i in 5:                        # 星屑
		var x2 := rng.randi_range(2, ow - 3)
		var y2 := rng.randi_range(2, oh - 3)
		out.set_pixel(x2, y2, out.get_pixel(x2, y2).lightened(0.35))

# 一层单位: 以脚底中心 (fx, fy) 落位, 目标高 th; dark = 压暗比例（越远越暗）
func _layer(out: Image, sp: Image, fx: int, fy: int, th: int, dark: float,
		flip: bool, interp: int) -> void:
	var im: Image = sp.duplicate()
	var nw := maxi(1, int(round(float(th) * float(im.get_width()) / float(maxi(1, im.get_height())))))
	im.resize(nw, maxi(1, th), interp)
	if flip:
		im.flip_x()
	if dark > 0.0:
		_darken(im, dark)
	out.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()),
		Vector2i(fx - im.get_width() / 2, fy - im.get_height()))

# ---------------- 底图: 戏剧性天空 ----------------
# 三段渐变天 + 日/月 + 云带 + 两层远山 + 地面 + 星点 + 暗角 + 描边
func _paint_bg(img: Image, kind: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	# 配色: 天顶 / 天中 / 地平线 / 日月 / 远山两层 / 地面两阶 / 描边
	var top := Color(0.10, 0.14, 0.20)
	var midc := Color(0.24, 0.28, 0.30)
	var hor := Color(0.62, 0.50, 0.34)
	var sun := Color(0.98, 0.86, 0.58)
	var sun_x := 0.50
	var sun_y := 0.30
	var sun_r := 0.07
	var r_far := Color(0.30, 0.30, 0.28)
	var r_near := Color(0.18, 0.19, 0.17)
	var g_top := Color(0.26, 0.22, 0.16)
	var g_bot := Color(0.16, 0.14, 0.11)
	var rim := Color(0.55, 0.50, 0.42)
	if kind == "foe":
		top = Color(0.16, 0.07, 0.09)
		midc = Color(0.34, 0.13, 0.11)
		hor = Color(0.66, 0.30, 0.16)
		sun = Color(0.94, 0.36, 0.20)
		sun_x = 0.68
		sun_y = 0.26
		sun_r = 0.06
		r_far = Color(0.26, 0.14, 0.13)
		r_near = Color(0.13, 0.08, 0.08)
		g_top = Color(0.22, 0.13, 0.10)
		g_bot = Color(0.12, 0.08, 0.07)
		rim = Color(0.62, 0.34, 0.30)
	elif kind == "gold":
		top = Color(0.16, 0.17, 0.22)
		midc = Color(0.42, 0.36, 0.24)
		hor = Color(0.78, 0.64, 0.34)
		sun = Color(1.0, 0.92, 0.62)
		sun_r = 0.09
		r_far = Color(0.36, 0.30, 0.20)
		r_near = Color(0.20, 0.17, 0.12)
		g_top = Color(0.30, 0.25, 0.14)
		g_bot = Color(0.18, 0.15, 0.09)
		rim = Color(0.82, 0.68, 0.36)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	var gy := int(float(h) * 0.80)     # 地平线
	# 天空三段渐变（上深 -> 中 -> 地平线亮）
	for y in h:
		var t := float(y) / float(maxi(1, h - 1))
		var c: Color
		if t < 0.55:
			c = top.lerp(midc, clampf(t / 0.55, 0.0, 1.0))
		else:
			c = midc.lerp(hor, clampf((t - 0.55) / 0.45, 0.0, 1.0))
		for x in w:
			img.set_pixel(x, y, c)
	# 日 / 月 + 光晕
	var sx := int(float(w) * sun_x)
	var sy := int(float(h) * sun_y)
	var rr := float(h) * sun_r
	for y in h:
		for x in w:
			var ddx := float(x - sx)
			var ddy := float(y - sy)
			var d := sqrt(ddx * ddx + ddy * ddy)
			if d <= rr:
				img.set_pixel(x, y, sun)
			elif d <= rr * 3.0:
				var k := 0.30 * pow(1.0 - (d - rr) / (rr * 2.0), 2.0)
				var c2 := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(lerpf(c2.r, sun.r, k),
					lerpf(c2.g, sun.g, k), lerpf(c2.b, sun.b, k), 1.0))
	# 云带: 横向细条, 亮暗相间
	for b in 5:
		var by := rng.randi_range(int(float(h) * 0.08), int(float(h) * 0.52))
		var thick := rng.randi_range(1, 2)
		var col := hor.lightened(0.10) if rng.randf() < 0.4 else midc.darkened(0.28)
		var x0 := rng.randi_range(-w / 3, maxi(1, w * 2 / 3))
		var bw := rng.randi_range(int(float(w) * 0.35), w)
		for x in range(maxi(0, x0), mini(w, x0 + bw)):
			var j := rng.randi_range(0, thick - 1)
			for y2 in range(by + j, mini(by + thick + j, gy)):
				img.set_pixel(x, y2, img.get_pixel(x, y2).lerp(col, 0.5))
	# 远山两层（锯齿山脊, 填到地平线）
	_ridge(img, rng, int(float(h) * 0.735), maxi(2, int(float(h) * 0.09)), r_far, gy)
	_ridge(img, rng, int(float(h) * 0.765), maxi(2, int(float(h) * 0.05)), r_near, gy)
	# 地面 + 横向草痕
	for y3 in range(gy, h):
		var t3 := float(y3 - gy) / float(maxi(1, h - gy))
		var c3 := g_top.lerp(g_bot, t3)
		for x3 in w:
			img.set_pixel(x3, y3, c3)
	for i in 6:
		var y4 := rng.randi_range(gy, h - 2)
		var x4 := rng.randi_range(0, maxi(0, w - 2))
		var ln := rng.randi_range(3, maxi(4, w / 3))
		for x5 in range(x4, mini(w, x4 + ln)):
			img.set_pixel(x5, y4, img.get_pixel(x5, y4).lightened(0.07))
	# 星点（血色天幕更明显）
	var n := 7 if kind == "foe" else 3
	for i in n:
		var x6 := rng.randi_range(1, w - 2)
		var y6 := rng.randi_range(1, maxi(1, int(float(h) * 0.40)))
		img.set_pixel(x6, y6, img.get_pixel(x6, y6).lightened(0.30))
	_vignette(img, 0.40)
	# 1px 描边
	for x7 in w:
		img.set_pixel(x7, 0, rim)
		img.set_pixel(x7, h - 1, rim)
	for y7 in h:
		img.set_pixel(0, y7, rim)
		img.set_pixel(w - 1, y7, rim)

# 一层锯齿山脊: 从 base_y 起伏, 往下填到 gy
func _ridge(img: Image, rng: RandomNumberGenerator, base_y: int, amp: int,
		col: Color, gy: int) -> void:
	var w := img.get_width()
	var y := base_y
	for x in w:
		if rng.randf() < 0.3:
			y = clampi(base_y - rng.randi_range(0, amp), 1, base_y)
		for yy in range(y, gy):
			img.set_pixel(x, yy, col)

# 像素海报化: LANCZOS 缩半 -> NEAREST 放大 2 倍 -> 1px 阵营描边
func _posterize(img: Image, kind: String) -> void:
	var ow := img.get_width()
	var oh := img.get_height()
	img.resize(maxi(1, ow / 2), maxi(1, oh / 2), Image.INTERPOLATE_LANCZOS)
	img.resize(ow, oh, Image.INTERPOLATE_NEAREST)
	var rim := Color(0.55, 0.50, 0.42)
	if kind == "foe":
		rim = Color(0.62, 0.34, 0.30)
	elif kind == "gold":
		rim = Color(0.82, 0.68, 0.36)
	for x in ow:
		img.set_pixel(x, 0, rim)
		img.set_pixel(x, oh - 1, rim)
	for y in oh:
		img.set_pixel(0, y, rim)
		img.set_pixel(ow - 1, y, rim)

func _vignette(img: Image, k: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var cx := float(w) * 0.5
	var cy := float(h) * 0.44
	var maxd := maxf(1.0, sqrt(cx * cx + cy * cy))
	for y in h:
		for x in w:
			var d := sqrt(float(x - cx) * float(x - cx) + float(y - cy) * float(y - cy)) / maxd
			var kk := clampf(1.0 - k * pow(d, 2.2), 0.0, 1.0)
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * kk, c.g * kk, c.b * kk, 1.0))

func _shadow(img: Image, cx: int, cy: int, rx: int) -> void:
	var ry := maxi(1, int(float(rx) * 0.24))
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := float(x - cx) / float(maxi(1, rx))
			var dy := float(y - cy) / float(maxi(1, ry))
			if dx * dx + dy * dy > 1.0:
				continue
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * 0.42, c.g * 0.42, c.b * 0.42, 1.0))

func _darken(img: Image, k: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			img.set_pixel(x, y, Color(c.r * (1.0 - k), c.g * (1.0 - k), c.b * (1.0 - k), c.a))

## 取素材: 带 cell 就裁格子, 然后一律裁到 alpha 包围盒（去掉大片空白）
func _sprite(src: Dictionary) -> Image:
	if src.is_empty():
		return null
	var file := String(src.get("file", ""))
	var full: Image = _cache.get(file)
	if full == null:
		full = Image.load_from_file(ProjectSettings.globalize_path(SRC) + file)
		if full == null:
			push_warning("[卡面] 读不到素材 %s" % file)
			return null
		_cache[file] = full
	var sub: Image = full
	if src.has("cell"):
		var c: Array = src["cell"]
		sub = full.get_region(Rect2i(int(c[0]) * CELL, int(c[1]) * CELL, CELL, CELL))
	var bb := _alpha_rect(sub)
	if bb.size.x <= 0:
		var cp: Image = sub.duplicate()
		return cp
	return sub.get_region(bb)

func _alpha_rect(img: Image) -> Rect2i:
	var minx := img.get_width()
	var miny := img.get_height()
	var maxx := -1
	var maxy := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.06:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

## Kenney 白色剪影上色: 保留 alpha, 颜色用 tint 色, 略微上亮下暗做出浮雕感
func _tint_flat(img: Image, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var k := 0.82 + 0.28 * clampf(1.0 - float(y) / float(maxi(1, img.get_height())), 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, c.a))

## 整身改色: smin 很低（0.06）→ 灰蓝甲也一起走色相, 同一张图能拉出好几路兵
func _hue_band(img: Image, to: float, vmul: float, smul: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.1 or c.s < 0.06 or c.v < 0.05:
				continue
			c.h = to
			c.s = clampf(c.s * smul, 0.0, 1.0)
			c.v = clampf(c.v * vmul, 0.0, 1.0)
			img.set_pixel(x, y, c)
