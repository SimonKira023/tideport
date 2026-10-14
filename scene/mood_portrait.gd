# 统一角色头像入口: 正式卡通立绘保留 128px, 最近邻显示.
# 角色各自保留不同的基础神态和头部方向. 对话情绪用角标表达, 不覆盖五官.
# 下方旧标定表与绘图函数暂留兼容历史调用, 正式路径只使用 _paint_marker.
extends Object

const SRC_DIR := "res://resources/texture/portraits/"
const S := 128                      # 保留立绘细节, 显示端使用最近邻采样。

const MOODS := ["normal", "happy", "surprised", "angry", "shy"]

# 手工标定表（44px 坐标）：eyes 左右眼中心，mid 脸中心 x，cheek 腮红行。
# flags: glasses=眼镜角色（happy/shy 不碰眼，避免跟镜框打架）；
#        calm=底图本来就眯着眼（happy 不叠弧线、shy 不叠线, 惊讶反而「睁眼」）。
const CALIB := {
	"player": {"eyes": [Vector2i(14, 17), Vector2i(26, 17)], "mid": 20, "cheek": 22},
	"slave_00": {"eyes": [Vector2i(17, 20), Vector2i(24, 20)], "mid": 21, "cheek": 22},
	"slave_01": {"eyes": [Vector2i(16, 17), Vector2i(25, 17)], "mid": 20, "cheek": 22},
	"slave_02": {"eyes": [Vector2i(15, 16), Vector2i(25, 16)], "mid": 20, "cheek": 21},
	"slave_03": {"eyes": [Vector2i(14, 17), Vector2i(24, 17)], "mid": 19, "cheek": 22},
	"slave_04": {"eyes": [Vector2i(16, 16), Vector2i(26, 16)], "mid": 21, "cheek": 21},
	"slave_05": {"eyes": [Vector2i(15, 18), Vector2i(27, 18)], "mid": 21, "cheek": 23},
	"slave_06": {"eyes": [Vector2i(18, 16), Vector2i(28, 16)], "mid": 23, "cheek": 21},
	"slave_07": {"eyes": [Vector2i(16, 18), Vector2i(24, 18)], "mid": 20, "cheek": 23, "calm": true},
}

static var _cache: Dictionary = {}      # key -> 128px 基底 ImageTexture
static var _mood_cache: Dictionary = {} # key|mood -> 差分 ImageTexture

static func has_calib(key: String) -> bool:
	return CALIB.has(key)

# 主入口: 取某角色某表情的纹理。文件不存在返回 null（调用方自行兜底）。
static func tex_of(key: String, mood := "normal") -> Texture2D:
	if not MOODS.has(mood):
		mood = "normal"
	var ck := key + "|" + mood
	if _mood_cache.has(ck):
		return _mood_cache[ck] as Texture2D
	var base := _base_of(key)
	if base == null:
		return null
	if mood == "normal":
		_mood_cache[ck] = base
		return base
	var img: Image = (base.get_image() as Image).duplicate()
	if img == null:
		return null
	_paint_marker(img, mood)
	var tex := ImageTexture.create_from_image(img)
	_mood_cache[ck] = tex
	return tex

# 128px 正式头像基底, 每种立绘只做一次
static func _base_of(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key] as Texture2D
	var tex: Texture2D = portrait_texture(key)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_width() != S or img.get_height() != S:
		img.resize(S, S, Image.INTERPOLATE_NEAREST)
	var out := ImageTexture.create_from_image(img)
	_cache[key] = out
	return out

# 所有对话共用正式立绘, 不再让剧情面板绕开统一的角色身份。
static func portrait_texture(key: String) -> Texture2D:
	if key.is_empty():
		return null
	var path := "res://resources/texture/portraits_v2/" + key + ".png"
	if not ResourceLoader.exists(path):
		path = SRC_DIR + key + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

# 花名册与国家数据是名单的唯一来源, 新增具名角色会自动进入覆盖检查。
static func required_keys() -> Array[String]:
	var keys: Array[String] = ["player", "goblin"]
	for i in Slaves.ROSTER.size():
		keys.append("slave_%02d" % i)
	for town_id in Nations.LORD_NAMES:
		keys.append("lord_" + String(town_id))
	for nation_id in Nations.CAPTAIN_NAMES:
		keys.append("captain_" + String(nation_id))
	return keys

# 新头像姿态各不相同, 不能再按旧的统一眼坐标涂改五官。
# 剧情情绪用小像素角标表达, 保留作者为每个人画的神态。
static func _paint_marker(img: Image, mood: String) -> void:
	var colors := {"happy": Color("e4bd69"), "surprised": Color("8bc4d5"), "angry": Color("d78070"), "shy": Color("d89fba")}
	var glyphs := {
		"happy": ["00000", "10101", "00000", "10001", "01110"],
		"surprised": ["00100", "00100", "00100", "00000", "00100"],
		"angry": ["10101", "01110", "11011", "01110", "10101"],
		"shy": ["01010", "11111", "11111", "01110", "00100"],
	}
	img.fill_rect(Rect2i(106, 6, 16, 16), Color("29383c"))
	img.fill_rect(Rect2i(108, 8, 12, 12), colors.get(mood, Color.WHITE))
	var glyph: Array = glyphs.get(mood, glyphs["happy"])
	for y in 5:
		for x in 5:
			if String(glyph[y])[x] == "1":
				img.fill_rect(Rect2i(109 + x * 2, 9 + y * 2, 2, 2), Color("29383c"))

# ---------------- 表情绘制 ----------------

static func _paint(img: Image, key: String, mood: String) -> void:
	var cal: Dictionary = CALIB.get(key, {})
	var eyes: Array = cal.get("eyes", [])
	var has_face: bool = eyes.size() == 2
	var mid: int = int(cal.get("mid", 22))
	var chy: int = int(cal.get("cheek", 22))
	var glasses: bool = bool(cal.get("glasses", false))
	var calm: bool = bool(cal.get("calm", false))
	match mood:
		"happy":
			if has_face and not glasses and not calm:
				for e in eyes:
					_patch(img, Vector2i(e.x, e.y), 2, 1)
					_arc(img, e.x, e.y + 1, 2, 2, 190.0, 350.0, Color8(70, 45, 35))
			if has_face:
				_blush(img, mid, chy, false)
			_dot(img, S - 6, 3, Color8(255, 226, 110))
			_dot(img, S - 8, 3, Color8(255, 226, 110))
			_dot(img, S - 7, 2, Color8(255, 226, 110))
			_dot(img, S - 7, 4, Color8(255, 226, 110))
			_dot(img, S - 7, 3, Color8(255, 240, 170))
			if glasses or calm:
				# 眼镜/眯眼角色不重画眼 —— 用一层淡暖罩读作「开心发光」
				_tint(img, Color8(255, 214, 140), 0.085)
		"surprised":
			if has_face:
				for e in eyes:
					_patch(img, Vector2i(e.x, e.y), 2, 2)
					_ellipse(img, e.x, e.y, 2, 2, Color8(252, 252, 255), Color8(60, 50, 55))
					_dot(img, e.x, e.y, Color8(45, 42, 55))
					_dot(img, e.x, e.y + 1, Color8(45, 42, 55))
			# 汗滴（右上角, 兜底也有）
			_drop(img, S - 6, 2, Color8(120, 190, 255))
		"angry":
			if has_face and not calm:
				for e in eyes:
					var s: int = 1 if e.x < mid else -1
					_line(img, Vector2i(e.x - s * 3, e.y - 4), Vector2i(e.x + s * 1, e.y - 2), Color8(55, 32, 28))
			_vein(img, mini(S - 5, mid + 12), 3)
		"shy":
			if has_face and not glasses and not calm:
				for e in eyes:
					_patch(img, Vector2i(e.x, e.y), 2, 1)
					_dot(img, e.x - 2, e.y - 1, Color8(70, 45, 35))
					_dot(img, e.x + 2, e.y - 1, Color8(70, 45, 35))
					for dx in range(-2, 3):
						_dot(img, e.x + dx, e.y, Color8(70, 45, 35))
			if has_face:
				_blush(img, mid, chy, true)
			_heart(img, S - 6, 2, Color8(250, 92, 112))
			if glasses or calm:
				_tint(img, Color8(255, 170, 190), 0.07)   # 害羞粉罩

# 兜底角标（没进标定表的角色: 不碰脸, 只在右上角放情绪符号）
	_calib_missing_fallback(img, cal, mood)

static func _calib_missing_fallback(img: Image, cal: Dictionary, mood: String) -> void:
	if not cal.is_empty():
		return
	match mood:
		"surprised":
			_drop(img, S - 6, 2, Color8(120, 190, 255))
			_drop(img, S - 10, 4, Color8(150, 205, 255))
		"angry":
			_vein(img, S - 6, 3)
		"shy":
			_heart(img, S - 6, 2, Color8(250, 92, 112))
			_heart(img, S - 11, 4, Color8(252, 130, 145))
		"happy":
			_dot(img, S - 6, 3, Color8(255, 226, 110))
			_dot(img, S - 8, 4, Color8(255, 226, 110))
			_dot(img, S - 7, 2, Color8(255, 240, 170))
			_dot(img, S - 7, 5, Color8(255, 240, 170))

# 用周边肤色中位数抹掉一个眼周矩形（重画前的"打底"）
static func _patch(img: Image, c: Vector2i, rx: int, ry: int) -> void:
	var ring: Array = []
	for x in range(maxi(0, c.x - rx - 2), mini(S, c.x + rx + 3)):
		for y in [maxi(0, c.y - ry - 2), mini(S - 1, c.y + ry + 2)]:
			var p := img.get_pixel(x, y)
			if _is_skin(p):
				ring.append(p)
	for y in range(maxi(0, c.y - ry - 2), mini(S, c.y + ry + 3)):
		for x in [maxi(0, c.x - rx - 2), mini(S - 1, c.x + rx + 2)]:
			var p2 := img.get_pixel(x, y)
			if _is_skin(p2):
				ring.append(p2)
	var col := Color(0.91, 0.74, 0.6)
	if not ring.is_empty():
		ring.sort_custom(func(a, b): return a.r + a.g + a.b < b.r + b.g + b.b)
		col = ring[ring.size() / 2]
	for y in range(maxi(0, c.y - ry), mini(S, c.y + ry + 1)):
		for x in range(maxi(0, c.x - rx), mini(S, c.x + rx + 1)):
			img.set_pixel(x, y, col)

static func _is_skin(p: Color) -> bool:
	var r: float = p.r * 255.0
	var g: float = p.g * 255.0
	var b: float = p.b * 255.0
	return r > 110.0 and r >= g and g > b - 10.0 and (r - b) > 12.0 and p.get_luminance() > 0.35

# 全图淡色罩（眼镜/眯眼角色的开心/害羞读法：色温即情绪）。col 用 Color8 传入。
static func _tint(img: Image, col: Color, k: float) -> void:
	for y in range(S):
		for x in range(S):
			var p := img.get_pixel(x, y)
			if p.a > 0.01:
				img.set_pixel(x, y, p.lerp(col, k))

static func _dot(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and x < S and y >= 0 and y < S:
		img.set_pixel(x, y, col)

static func _line(img: Image, a: Vector2i, b: Vector2i, col: Color) -> void:
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var cur := a
	for _i in 64:
		_dot(img, cur.x, cur.y, col)
		if cur.x == b.x and cur.y == b.y:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			cur.x += sx
		if e2 <= dx:
			err += dx
			cur.y += sy

# 弧线（弯月笑眼）：参数方程采样
static func _arc(img: Image, cx: int, cy: int, rx: int, ry: int, a0: float, a1: float, col: Color) -> void:
	var steps := 24
	for i in steps + 1:
		var t: float = deg_to_rad(lerpf(a0, a1, float(i) / steps))
		_dot(img, cx + int(round(cos(t) * rx)), cy + int(round(sin(t) * ry)), col)

# 实心椭圆 + 描边（惊讶瞪眼）
static func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, fill: Color, edge: Color) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx: float = float(x - cx) / float(rx)
			var dy: float = float(y - cy) / float(ry)
			var d2 := dx * dx + dy * dy
			if d2 <= 1.0:
				# 距离 0.55 以内算芯, 外圈描边
				_dot(img, x, y, edge if d2 > 0.55 else fill)

# 腮红（开心小块 / 害羞大块）
static func _blush(img: Image, mid: int, chy: int, big: bool) -> void:
	var col := Color8(248, 108, 122) if big else Color8(243, 128, 120)
	var soft := Color8(240, 146, 140)
	for sx in [-1, 1]:
		var bx: int = mid + sx * 7
		if big:
			for ddx in range(-2, 4):
				for ddy in range(0, 3):
					_dot(img, bx + ddx, chy + ddy, col if absf(ddx - 0.5) <= 1.5 else soft)
		else:
			for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(2, 0)]:
				_dot(img, bx + off.x, chy + off.y, col)

# 汗滴（上尖下圆）
static func _drop(img: Image, x: int, y: int, col: Color) -> void:
	var pts := [Vector2i(0, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(-1, 3), Vector2i(0, 3), Vector2i(1, 3), Vector2i(0, 4)]
	for p in pts:
		_dot(img, x + p.x, y + p.y, col)

# 怒纹（漫画青筋十字星）
static func _vein(img: Image, x: int, y: int, col := Color8(232, 62, 52)) -> void:
	for p in [Vector2i(-2, -2), Vector2i(-1, -1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2),
			Vector2i(2, -2), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-2, 2),
			Vector2i(0, -3), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(3, 0)]:
		_dot(img, x + p.x, y + p.y, col)

# 小心心
static func _heart(img: Image, x: int, y: int, col: Color) -> void:
	for p in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(2, 1),
			Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3)]:
		_dot(img, x + p.x, y + p.y, col)
