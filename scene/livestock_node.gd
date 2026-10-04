# scene/livestock_node.gd —— e49 畜棚/马厩里那群会走动的牲口
# 由 farm_building_node 挂在它底下当子节点（原点 = 建筑底部中间那一格）。
# 只干一件事：按 Structures 里记的头数把牲口画出来，各自 idle/walk/eat 轮着来。
# 位置摆在哪不用问别人 —— 建筑节点把畜栏宽度（pen_w）喂进来，牲口就在栏里横向铺开。
#
# 帧格是 32x32。每行的含义是**探针逐行比帧差量**出来的，不是猜的：
#   第 0 行 = idle（四帧几乎一模一样，站着原地图呼吸）
#   第 5 行 = walk（帧间差最大，四帧换着迈步）
#   第 3 行 = eat（不透明内容最靠下：脑袋低下去啃地）
# 两个例外：
#   · 鸭 —— 第 5 行有两帧逐像素完全相同（那是「同姿势重复」），真迈步在第 6 行；
#   · 马 —— 不是一张大表，三个动作各一个文件（idle.png / Run.png / Eat.png），
#     而且 Eat.png 第 0 行是「高个子站着」，低头吃草在第 1 行。
extends Node2D

const ANIM_DIR := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Animals/Farm/"
const CELL := 32

const ANIM := {
	"cow": {"tex": ANIM_DIR + "Cow/Common Cow/Female Cow Brown.png",
		"cols": 4, "idle": 0, "walk": 5, "eat": 3},
	"sheep": {"tex": ANIM_DIR + "Sheep/Sheep Female.png",
		"cols": 4, "idle": 0, "walk": 5, "eat": 3},
	"goat": {"tex": ANIM_DIR + "Goat/Goat Female Brown.png",
		"cols": 4, "idle": 0, "walk": 5, "eat": 3},
	"duck": {"tex": ANIM_DIR + "Ducks/Duck White.png",
		"cols": 2, "idle": 0, "walk": 6, "eat": 3},
	"ostrich": {"tex": ANIM_DIR + "Ostrich/Ostrich Brown.png",
		"cols": 4, "idle": 0, "walk": 5, "eat": 3},
}

# 马：三个动作三个文件（row = 取第几行, frames = 这一行有几帧）
const HORSE_ANIM := {
	"idle": {"tex": ANIM_DIR + "Horse/1/idle.png", "row": 0, "frames": 4},
	"walk": {"tex": ANIM_DIR + "Horse/1/Run.png", "row": 0, "frames": 6},
	"eat": {"tex": ANIM_DIR + "Horse/1/Eat.png", "row": 1, "frames": 4},
}

# 畜栏：牲口在建筑**前方**这一条横带里活动（原点上方是房子, 下方才是空地）
const PEN_Y0 := 2.0
const PEN_Y1 := 20.0
const FRAME_STEP := 0.16      # 一帧 0.16 秒（跟鸡舍啄食一个节奏）
const WALK_SPEED := 11.0
const SHOW_CAP := 6           # 栏里最多画 6 头 —— 再多就挤成一团看不清, 头数在面板里报
const SYNC_STEP := 0.25       # 头数变化的兜底轮询（正常变化由 station_changed 立刻推）

var cell := Vector2i.ZERO
var pen_w := 48.0             # 畜栏宽度（建筑节点按它的贴图宽喂进来）

var _animals: Array = []      # [{sp, spr, state, t, vx, row, frames}]
var _frame := 0
var _frame_t := 0.0
var _sync_t := 0.0
var _sig := ""
var _tex: Dictionary = {}     # {贴图路径: Texture2D} —— 一头一张, 别每帧 load

# 由建筑节点调用：告诉它归哪一格、栏有多宽
func setup(owner_cell: Vector2i, width: float) -> void:
	cell = owner_cell
	pen_w = maxf(48.0, width)
	_sync(true)

func _ready() -> void:
	# 买卖牲口会改头数：直接在 station_changed 上刷新（面板开着时 time_scale = 0,
	# _process 的 delta 也是 0, 光靠轮询得等关了面板才看得到新买的那头）。
	Structures.station_changed.connect(_on_station_changed)

func _on_station_changed(c: Vector2i) -> void:
	if c == cell:
		_sync(false)

func _process(delta: float) -> void:
	_sync_t += delta
	if _sync_t >= SYNC_STEP:
		_sync_t = 0.0
		_sync(false)

	# 换帧（所有牲口共用一个帧号, 各自的帧数取模 —— 数量不同也不会跑飞）
	_frame_t += delta
	if _frame_t >= FRAME_STEP:
		_frame_t = 0.0
		_frame += 1
		_paint_frames()

	for a in _animals:
		var spr: Sprite2D = a["spr"]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			_pick_state(a)
		if String(a["state"]) != "walk":
			continue
		var half: float = maxf(4.0, pen_w * 0.5 - CELL * 0.5)
		var x: float = spr.position.x + float(a["vx"]) * delta
		if x > half or x < -half:
			x = clampf(x, -half, half)
			a["vx"] = -float(a["vx"])     # 撞栏就掉头
		spr.position.x = x
		spr.flip_h = float(a["vx"]) < 0.0

# ---------------- 状态机 ----------------
# 站在那儿一会 -> 要么走走, 要么低头吃两口 -> 再站回去。没有繁殖/饥饿, 纯好看。
func _pick_state(a: Dictionary) -> void:
	var st := String(a["state"])
	var r := randf()
	if st == "idle":
		if r < 0.45:
			_set_state(a, "walk")
			a["t"] = randf_range(1.4, 3.2)
		elif r < 0.72:
			_set_state(a, "eat")
			a["t"] = randf_range(1.2, 2.4)
		else:
			a["t"] = randf_range(1.0, 2.4)
	elif st == "walk":
		_set_state(a, "idle")
		a["t"] = randf_range(0.8, 2.0)
	else:
		_set_state(a, "idle")
		a["t"] = randf_range(1.0, 2.2)

func _set_state(a: Dictionary, st: String) -> void:
	a["state"] = st
	if st == "walk":
		a["vx"] = WALK_SPEED if randf() < 0.5 else -WALK_SPEED
	else:
		a["vx"] = 0.0
	_apply_anim(a)

# ---------------- 画 ----------------
# 把「当前状态」翻译成 贴图文件 + 行号 + 帧数, 写回 a 里（换贴图的那几个动作只有马）。
func _apply_anim(a: Dictionary) -> void:
	var sp := String(a["sp"])
	var st := String(a["state"])
	var path := ""
	var row := 0
	var frames := 1
	if sp == "horse":
		var h: Dictionary = HORSE_ANIM.get(st, HORSE_ANIM["idle"])
		path = String(h["tex"])
		row = int(h.get("row", 0))
		frames = int(h["frames"])
	else:
		var d: Dictionary = ANIM.get(sp, ANIM["cow"])
		path = String(d["tex"])
		row = int(d.get(st, 0))
		frames = maxi(1, int(d["cols"]))
	var tex: Texture2D = _tex_for(path)
	if tex == null:
		return      # 第三方素材缺失, 跳过贴图赋值, 下次状态切换再试
	var spr: Sprite2D = a["spr"]
	var at := spr.texture as AtlasTexture
	if at == null or at.atlas != tex:
		at = AtlasTexture.new()
		at.atlas = tex
		spr.texture = at
	a["row"] = row
	a["frames"] = frames
	at.region = Rect2(0, row * CELL, CELL, CELL)

func _paint_frames() -> void:
	for a in _animals:
		var spr: Sprite2D = a["spr"]
		var at := spr.texture as AtlasTexture
		if at == null:
			continue
		var f: int = _frame % maxi(1, int(a["frames"]))
		at.region = Rect2(f * CELL, int(a["row"]) * CELL, CELL, CELL)

func _tex_for(path: String) -> Texture2D:
	if not _tex.has(path):
		# 第三方素材不入库(见 README), 缺失时返回 null 且不写入缓存, 下次再试
		var t := SoftRes.tex(path)
		if t == null:
			return null
		_tex[path] = t
	return _tex[path]

# ---------------- 按头数重建 ----------------
# 头数一变就整批拆了重来 —— 一天才变一次, 没必要做增量。
func _sync(force: bool) -> void:
	var counts := {}
	var total := 0
	for sp in ANIM.keys():
		var n: int = Structures.count_of_species(cell, String(sp))
		if n > 0:
			counts[sp] = n
			total += n
	var horse: int = Structures.count_of_species(cell, "horse")
	if horse > 0:
		counts["horse"] = horse
		total += horse
	var sig := "%s|%d" % [str(counts), total]
	if not force and sig == _sig:
		return
	_sig = sig
	for a in _animals:
		(a["spr"] as Sprite2D).queue_free()     # 不在自己的信号里, 直接 free 干净
	_animals.clear()
	var idx := 0
	for sp in counts.keys():
		for _i in int(counts[sp]):
			if idx >= SHOW_CAP:
				return
			_make_animal(String(sp), idx)
			idx += 1

func _make_animal(sp: String, idx: int) -> void:
	var spr := Sprite2D.new()
	# 影子跟着走（跟鸡舍/树一个套路, 不然像贴纸）
	var sh := preload("res://scene/shadow_util.gd").make_shadow(17, 6, 0.16)
	sh.position = Vector2(0, 9)
	spr.add_child(sh)
	var half: float = maxf(4.0, pen_w * 0.5 - CELL * 0.5)
	var step: float = (half * 2.0) / float(maxi(1, SHOW_CAP - 1))
	var x: float = -half + step * float(idx) + randf_range(-3.0, 3.0)
	spr.position = Vector2(x, randf_range(PEN_Y0, PEN_Y1))
	add_child(spr)
	var a := {"sp": sp, "spr": spr, "state": "idle", "t": randf_range(0.1, 2.5),
		"vx": 0.0, "row": 0, "frames": 1}
	_animals.append(a)
	_apply_anim(a)
	spr.flip_h = randf() < 0.5