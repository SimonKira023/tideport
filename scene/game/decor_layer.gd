extends RefCounted
# ==========================================================================
# 花草点缀模块 —— 阶段 1-1「拆 scene/game.gd」的第三块（2026-10-06）
#
# 原先这段长在 game.gd 的 _build_decor（约 84 行）。现在整体搬到这里，
# game.gd 只留 `_build_decor()` 门面 + `decor_layer` 的只读属性转发。
#
# 职责：遍历每一格草地，用「低频噪声 + 花圃噪声」按概率撒草丛 / 小花 / 蘑菇，
#       跳过水面与耕地（田里长草会很怪）；并把 DecorTileMapLayer 挂到 Game 下。
#
# ❗为什么 decor_layer 仍挂在 Game 下、本模块只持引用：
#     - `_build_critters`（蝴蝶）要拿 decor 层里的花格当锚点；
#     - `_build_border` 要按 `decor_layer.get_index() + 1` 排层。
#   两处都从 game 读 `decor_layer`，所以 game.gd 用只读属性转发。
#
# ❗DECOR_* 常量留在 game.gd：自检直接读 `g.DECOR_TUFT` / `g.DECOR_FLOWER` /
#   `g.DECOR_MUSHROOM`，不能搬。模块通过 `_game.DECOR_*` 回问。
#
# ❗与 Game 的耦合（grid_layer / water_layer / beach_layer / PROP_SHEET /
#   DECOR_*）统一走 _game 动态派发 —— 这些成员不在 RefCounted 的静态基类里。
# ==========================================================================

var decor_layer: TileMapLayer = null   # 草地上的花草点缀层（草地之上、耕地之下）
var _game = null

func setup(game) -> void:
	_game = game

# 遍历每一格草地，按概率撒草丛 / 小花 / 蘑菇。跳过水面（池塘）和耕地。
func build() -> void:
	var tex: Texture2D = SoftRes.tex(_game.PROP_SHEET)
	if tex == null or _game.grid_layer.tile_set == null:
		return
	var grass_cells: Array = _game.grid_layer.get_used_cells()
	if grass_cells.is_empty():
		return

	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	var palette: Array = []
	palette.append_array(_game.DECOR_MUSHROOM)
	palette.append_array(_game.DECOR_FLOWER)
	palette.append_array(_game.DECOR_TUFT)
	for t in palette:
		if not atlas.has_tile(t):
			atlas.create_tile(t)
	var ts := TileSet.new()
	ts.tile_size = _game.grid_layer.tile_set.tile_size
	ts.add_source(atlas, _game.DECOR_SRC)

	decor_layer = TileMapLayer.new()
	decor_layer.name = "DecorTileMapLayer"
	decor_layer.tile_set = ts
	decor_layer.position = _game.grid_layer.position
	_game.add_child(decor_layer)
	_game.move_child(decor_layer, _game.grid_layer.get_index() + 1)   # 草地之上、耕地之下

	var rng := RandomNumberGenerator.new()
	rng.seed = _game.DECOR_SEED
	# 低频噪声：这一步是「好看」的关键 —— 均匀撒出来像花毯，有了疏密才像野地
	var noise := FastNoiseLite.new()
	noise.seed = _game.DECOR_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = _game.DECOR_NOISE_FREQ
	# 花圃噪声：更低频的一层, 高值区整片是花（花海）, 低值区几乎只有草丛
	var field_noise := FastNoiseLite.new()
	field_noise.seed = _game.DECOR_SEED + 7
	field_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	field_noise.frequency = _game.DECOR_FIELD_FREQ
	var placed := 0
	var n_mushroom := 0
	var n_flower := 0
	var n_tuft := 0
	for c in grass_cells:
		if _game.water_layer.get_cell_source_id(c) != -1:
			continue
		if _game.beach_layer != null and _game.beach_layer.get_cell_source_id(c) != -1:
			continue       # 沙滩是过渡带，上面不长花
		if Farm.tilled.has(c):
			continue
		var n := (noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5      # 0~1
		# 基础密度收紧（留白更多）; 花圃区里用花圃强度兜底, 疏密对比更强
		var density: float = smoothstep(0.34, 0.92, n) * _game.DECOR_MAX_DENSITY
		var field: float = smoothstep(0.66, 0.90,
			(field_noise.get_noise_2d(float(c.x), float(c.y)) + 1.0) * 0.5)
		if field > 0.0:
			density = maxf(density, field * _game.DECOR_FIELD_DENSITY)
		if rng.randf() >= density:
			continue
		# 花圃里花的占比被拉高、蘑菇近乎绝迹; 区外回归「草丛为主, 花是点缀」
		var flower_share: float = lerpf(_game.DECOR_FLOWER_SHARE, 0.72, field)
		var mush_share: float = lerpf(_game.DECOR_MUSHROOM_SHARE, 0.015, field)
		var tuft_band: float = 1.0 - (mush_share + flower_share)
		var r := rng.randf()
		var pick := Vector2i(-1, -1)
		var kind := ""
		if r < tuft_band:
			pick = _game.DECOR_TUFT[rng.randi() % _game.DECOR_TUFT.size()]
			kind = "草丛"
		elif r < tuft_band + flower_share:
			pick = _game.DECOR_FLOWER[rng.randi() % _game.DECOR_FLOWER.size()]
			kind = "花"
		else:
			pick = _game.DECOR_MUSHROOM[rng.randi() % _game.DECOR_MUSHROOM.size()]
			kind = "蘑菇"
		decor_layer.set_cell(c, _game.DECOR_SRC, pick)
		placed += 1
		match kind:
			"蘑菇": n_mushroom += 1
			"花": n_flower += 1
			"草丛": n_tuft += 1
	print("[点缀] 草地 %d 格里撒了 %d 处(约 %.0f%%):草丛 %d / 花 %d / 蘑菇 %d"
		% [grass_cells.size(), placed, 100.0 * placed / grass_cells.size(), n_tuft, n_flower, n_mushroom])
