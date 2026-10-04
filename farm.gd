# farm.gd —— Autoload，名字：Farm
# 管理所有农田状态：耕地、浇水、作物、生长
extends Node

signal tilled_added(pos: Vector2i)      # 新开了一块耕地
signal tilled_removed(pos: Vector2i)    # 耕地不再存在（目前只有 clear_all / 重开存档会发）
signal soil_changed(pos: Vector2i)      # 这块地的「外观」要重画（比如浇水了）
signal crop_changed(pos: Vector2i)      # 这块地上的作物状态变了

const TILE_SIZE := 16

# 农田网格在世界坐标里的原点（= 地面瓦片图层的 global_position），由 game.gd 开场赋值
var grid_origin := Vector2.ZERO

var tilled: Dictionary = {}    # {Vector2i: true}  已耕地
var watered: Dictionary = {}   # {Vector2i: true}  今天已浇水
var crops: Dictionary = {}     # {Vector2i: {seed: ItemData, stage: int, days: int, dead: bool}}

func _ready() -> void:
	TimeManager.new_day.connect(_on_new_day)

# ---------------- 查询 ----------------
func is_tilled(pos: Vector2i) -> bool:
	return tilled.has(pos)

func is_watered(pos: Vector2i) -> bool:
	return watered.has(pos)

func has_crop(pos: Vector2i) -> bool:
	return crops.has(pos)

func get_stage(pos: Vector2i) -> int:
	if not crops.has(pos):
		return -1
	return crops[pos].stage

func is_ready(pos: Vector2i) -> bool:
	if not crops.has(pos):
		return false
	if crops[pos].get("dead", false):
		return false            # 枯掉的不能「收获」
	return crops[pos].stage >= crops[pos].seed.grow_days

# ---------------- 季节 ----------------
# 这包种子现在能不能下种：seasons 空 = 全季都能种（老资源兼容）
# e49 温室：pos 落在温室棚前那块地里就不看季节 —— 什么种子都能种。
# ❗pos 有默认值（-99999 的哨兵格），所以 player.gd / 自检那些老调用不传 pos 照样按老规矩走；
#   想让温室真的生效, player.gd 播种那处要把目标格传进来（见下面的注释）。
func season_ok_for(seed_item: ItemData, pos := Vector2i(-99999, -99999)) -> bool:
	if seed_item == null:
		return true
	# 温室地块豁免（structures.gd 的 is_greenhouse_cell 认这块地）
	if pos.x != -99999 and Structures.is_greenhouse_cell(pos):
		return true
	if seed_item.seasons.is_empty():
		return true
	return seed_item.seasons.has(TimeManager.season)

# 把种子能种的季节转成文字（"春/夏"），给播种失败提示用
func seasons_text_for(seed_item: ItemData) -> String:
	if seed_item == null or seed_item.seasons.is_empty():
		return "四季"
	var snames: Array[String] = []
	for si in seed_item.seasons:
		snames.append(TimeManager.SEASONS[int(si)])
	return "/".join(snames)

# ---------------- 耕地 ----------------
func till(pos: Vector2i) -> bool:
	if tilled.has(pos):
		return false
	if crops.has(pos):
		return false
	tilled[pos] = true
	tilled_added.emit(pos)
	return true

# 把耕地翻回草地（锄头再点一次已耕地）。有作物时不许翻（先收割）。
# 返回 true 表示真的翻掉了。
func untill(pos: Vector2i) -> bool:
	if not tilled.has(pos):
		return false
	if crops.has(pos):
		return false
	tilled.erase(pos)
	watered.erase(pos)
	tilled_removed.emit(pos)
	return true

# ---------------- 播种 ----------------
func plant(pos: Vector2i, seed: ItemData) -> bool:
	if seed == null or seed.type != "种子":
		return false
	if not tilled.has(pos) or crops.has(pos):
		return false
	if not season_ok_for(seed, pos):
		return false            # 不是它能种的季节（玩家侧提前拦并给提示，这里是兜底）
	crops[pos] = {"seed": seed, "stage": 0, "days": 0, "dead": false}
	crop_changed.emit(pos)
	return true

# ---------------- 浇水（空耕地也能浇） ----------------
func water(pos: Vector2i) -> bool:
	if not tilled.has(pos):
		return false
	if watered.has(pos):
		return false
	watered[pos] = true
	soil_changed.emit(pos)          # 干土 -> 湿土贴图
	if crops.has(pos):
		crop_changed.emit(pos)
	return true

# ---------------- 收获 ----------------
# 收获只把作物拿走，耕地本身保留（不用再锄一遍），只是回到「干土」外观。
# 想让它变回草地，用 till() 的反操作 —— 目前只由 clear_all() 统一处理。
func harvest(pos: Vector2i) -> ItemData:
	if not crops.has(pos):
		return null
	var c = crops[pos]
	if c.get("dead", false):
		return null             # 枯掉的不出货（玩家走 clear_dead 清地）
	if c.stage < c.seed.grow_days:
		return null
	var crop_item: ItemData = c.seed.grow_to
	crops.erase(pos)
	watered.erase(pos)
	crop_changed.emit(pos)      # 作物贴图移除
	soil_changed.emit(pos)      # 湿土 -> 干土（耕地留在原地）
	Legion.gain_exp(2)          # e13h: 收成也长主角经验 (玩法全覆盖)
	return crop_item

# ---------------- 每日结算 ----------------
# 浇过水的作物长一阶段；没浇水的停长（不会枯死，适合慢慢经营）
# 换季结算：新季种不了的老作物当天早上集体枯掉（dead=true，灰褐贴图），收割只是清地不出货
func _on_new_day(_day: int) -> void:
	var just_watered: Array = watered.keys()
	watered.clear()
	for pos in just_watered:
		soil_changed.emit(pos)      # 湿土 -> 干土贴图

	# 雨天/风暴/雪：天亮时所有耕地自动淋湿 —— 湿土贴图 + 算「今天已浇水」，
	# 晚上结算照常长一阶段，白天不用再人工浇水（Weather 比 Farm 先连 new_day，见 autoload 顺序）
	if Weather.is_rain():
		for pos in tilled:
			if not watered.has(pos):
				watered[pos] = true
				just_watered.append(pos)    # e28a: 补进今日浇水快照, 淋湿的地当晚照常长
				soil_changed.emit(pos)      # 干土 -> 湿土贴图

	for pos in crops:
		var c = crops[pos]
		# 过季枯萎：seed.seasons 不含当前季节就枯（只枯一次，别天天重发信号）
		# e49 温室地块上的作物不过季（season_ok_for 带 pos 进去判）
		if not c.get("dead", false) and not season_ok_for(c.seed, Vector2i(pos)):
			c.dead = true
			watered.erase(pos)      # 枯了也不用浇水
			crop_changed.emit(pos)
			continue
		if c.get("dead", false):
			continue                # 枯掉的不再生长
		if not just_watered.has(pos):
			continue                 # 没浇水，今天不长
		c.days += 1
		c.stage = mini(c.days, c.seed.grow_days)
		crop_changed.emit(pos)

# ---------------- 枯萎作物 ----------------
func is_dead(pos: Vector2i) -> bool:
	return crops.has(pos) and crops[pos].get("dead", false)

# 把枯掉的作物清掉（收割键触发），耕地和干土外观保留。返回 true 表示真的清了。
func clear_dead(pos: Vector2i) -> bool:
	if not is_dead(pos):
		return false
	crops.erase(pos)
	watered.erase(pos)
	crop_changed.emit(pos)
	return true

# ---------------- 批量操作（存档/重开用） ----------------
func clear_all() -> void:
	var old_tilled: Array = tilled.keys()
	tilled.clear()
	watered.clear()
	crops.clear()
	for pos in old_tilled:
		tilled_removed.emit(pos)
