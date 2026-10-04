# soil_layer.gd —— 耕地显示层：16 格自动拼接（blob autotile）
#
# 为什么不再直接切图集？
#   素材 Tilled Soil and wet soil.png 里那套「干土自动拼接」图块，
#   每一格的四角都画了 2x2 的深色像素点（连内部填充格也有）。
#   一整片田铺出来，格与格的角点会两两相接，变成一张规律的深色网点 ——
#   就是你说的「耕地中间有小点」。
#
#   所以这里改成：用素材里的**原色**自己生成 16 张拼接图块 ——
#     · 内部：纯色填充，相邻的格子严丝合缝，一点缝都没有
#     · 只有真正「敞开」的那一边，才画 2 像素的深色描边（外深内浅）
#   颜色全部取自素材（见下面的 FILL / RIM_*），所以画风不变，但连成一片。
#
#   注：图集下半张（行 4-7）其实是蓝色水面，不是深色湿土，
#   所以「浇过水」是把干土整体压暗偏冷（WET_TINT），免得湿地看起来像水塘。
extends Node2D

const TS := 16

# —— 取自素材 Tilled Soil and wet soil.png 图块 (2,1) / (2,0) 的实际像素色 ——
const FILL := Color8(190, 109, 71)      # 土的底色
const RIM_OUT := Color8(110, 53, 57)    # 描边外层（深）
const RIM_IN := Color8(157, 76, 70)     # 描边内层（稍浅）
const RIM_W := 2                        # 描边层数（外深 1 层 + 内浅 1 层）

const DRY_TINT := Color(1, 1, 1)                 # 干土：原色
const WET_TINT := Color(0.60, 0.66, 0.86)        # 湿土：压暗 + 偏冷

var _tiles: Dictionary = {}     # {mask(String): ImageTexture}
var _sprites: Dictionary = {}   # {Vector2i: Sprite2D}

func _ready() -> void:
	Farm.tilled_added.connect(_on_added)
	Farm.tilled_removed.connect(_on_removed)
	Farm.soil_changed.connect(_refresh)
	# 开场同步已有耕地（读档 / 场景里预设的田）
	for pos in Farm.tilled.keys():
		_on_added(pos)

# ---------------- 增删 ----------------
func _on_added(pos: Vector2i) -> void:
	if _sprites.has(pos):
		return
	var spr := Sprite2D.new()
	spr.centered = false                       # 以格子左上角定位，省一次半格换算
	add_child(spr)
	_sprites[pos] = spr
	_refresh(pos)
	for n in _neighbors(pos):
		_refresh(n)                            # 新邻居会改变旁边那格的敞口方向

func _on_removed(pos: Vector2i) -> void:
	if _sprites.has(pos):
		_sprites[pos].queue_free()
		_sprites.erase(pos)
	for n in _neighbors(pos):
		_refresh(n)                            # 邻居少了一个伴，边缘要重画

func _neighbors(pos: Vector2i) -> Array:
	return [
		pos + Vector2i.UP, pos + Vector2i.DOWN,
		pos + Vector2i.LEFT, pos + Vector2i.RIGHT,
	]

# ---------------- 重画单格 ----------------
func _refresh(pos: Vector2i) -> void:
	if not _sprites.has(pos):
		return
	var spr: Sprite2D = _sprites[pos]
	spr.texture = tile_for(_mask(pos))
	spr.position = _grid_to_local(pos)
	spr.modulate = WET_TINT if Farm.is_watered(pos) else DRY_TINT

# 四方向是否"敞开"（没有相邻耕地）
func _mask(pos: Vector2i) -> String:
	var m := ""
	m += "N" if not Farm.is_tilled(pos + Vector2i.UP) else "-"
	m += "S" if not Farm.is_tilled(pos + Vector2i.DOWN) else "-"
	m += "W" if not Farm.is_tilled(pos + Vector2i.LEFT) else "-"
	m += "E" if not Farm.is_tilled(pos + Vector2i.RIGHT) else "-"
	return m

func mask_at(pos: Vector2i) -> String:
	return _mask(pos)

# 格子号 -> 本节点局部坐标。
# Farm.grid_origin 是世界坐标下的网格原点；减去本节点 global_position 得到局部偏移，
# 这样主场景根节点被拖动、或本节点不在网格原点上，位置依然正确。
func _grid_to_local(pos: Vector2i) -> Vector2:
	var origin_local := Farm.grid_origin - global_position
	return origin_local + Vector2(pos.x * TS, pos.y * TS)

# ---------------- 生成拼接图块 ----------------
# mask = 四方向敞开标记（N/S/W/E），敞开的那一边才画描边，闭合边保持纯色。
# 这样相邻两格在「接壤的那条边」上都是纯色，拼起来完全看不出接缝。
func tile_for(mask: String) -> ImageTexture:
	if _tiles.has(mask):
		return _tiles[mask]
	var img := Image.create_empty(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(FILL)
	if mask[0] == "N":
		_hline(img, 0)
	if mask[1] == "S":
		_hline(img, TS - 1)
	if mask[2] == "W":
		_vline(img, 0)
	if mask[3] == "E":
		_vline(img, TS - 1)
	var tex := ImageTexture.create_from_image(img)
	_tiles[mask] = tex
	return tex

# 在 y 处画一条「外深内浅」的描边；y 是 0 就往下叠，是 TS-1 就往上叠
func _hline(img: Image, y: int) -> void:
	var step := 1 if y == 0 else -1
	for x in TS:
		img.set_pixel(x, y, RIM_OUT)
		if RIM_W > 1:
			img.set_pixel(x, y + step, RIM_IN)

func _vline(img: Image, x: int) -> void:
	var step := 1 if x == 0 else -1
	for y in TS:
		img.set_pixel(x, y, RIM_OUT)
		if RIM_W > 1:
			img.set_pixel(x + step, y, RIM_IN)
