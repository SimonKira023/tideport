# item_data.gd —— 道具的数据模板
class_name ItemData
extends Resource

@export var display_name: String = ""
@export var icon: Texture2D
@export_enum("材料", "种子", "作物", "工具", "食物", "地板", "船", "装备") var type: String = "材料"
@export var max_stack: int = 99          # 最大堆叠数
@export_multiline var description: String = ""
# 装备专用：整套盔甲的档位（1-3，越高越高级）。0 = 不是装备。
# 同伴晋升二线/三线兵种时要背包里有达标的整套甲（见 slaves.gd can_afford）。
@export var armor_tier: int = 0
# 装备专用：穿上后主角的生命上限加成（盔甲只管保命, 不存在防御减伤）。
@export var armor_hp: int = 0
# 种子专用：种下后长成的作物，以及卖价
@export var grow_to: ItemData = null     # 种子 -> 作物 的映射
@export var grow_days: int = 4           # 成熟所需天数
@export var sell_price: int = 0          # 卖价（作物有，种子也有）
# 种子种在哪儿：作物种子下田，树种子下草地（玩家代码按这个分流）
@export_enum("耕地", "草地") var plant_on: String = "耕地"
# 种子专用：能播种的季节（0春/1夏/2秋/3冬）。空数组 = 全季都能种（老种子资源不用改）。
# 过了季节还没收的作物会在换季早上枯掉（见 farm.gd _on_new_day）。
@export var seasons: Array = []

# e46「一键整理」排的道具先后：工具放最前面（常用的顺手），后面按类型分组，
# 同组的按名字排。表里没有的类型统一排到最后（权重 99）。
# ❗「放置」（工作台/熔炉这种拿在手里摆的件）不在 @export_enum 那串里, 但实际有,
#   得单列一项, 否则它们全漂到最末尾去。
const SORT_ORDER := ["工具", "装备", "种子", "作物", "食物", "材料", "地板", "放置", "船"]

func sort_rank() -> int:
	var i := SORT_ORDER.find(type)
	return i if i >= 0 else 99

# 给 UI 悬浮提示用的一段说明：名称 / 类型 / 卖价 / 种子长成什么 / 描述。
# ❗界面只用 ASCII 标点（IPix 字体没有全角标点字形）。
func info_text() -> String:
	var lines: Array[String] = [display_name]
	lines.append("[%s]" % type)
	if type == "装备":
		lines.append("装备等级: %d" % armor_tier)
		if armor_hp > 0:
			lines.append("穿上: 生命上限 +%d" % armor_hp)
		lines.append("晋升高级兵种时要背包里有达标的一套")
	if sell_price > 0:
		lines.append("卖价: %d金/个" % sell_price)
	if type == "种子":
		if plant_on == "草地":
			lines.append("种在草地上, 长成一棵树")
			lines.append("砍掉掉木头和树种子")
		elif grow_to != null:
			lines.append("种在田里, %d天成熟, 长成 %s" % [grow_days, grow_to.display_name])
			if grow_to.sell_price > 0:
				lines.append("收成卖价: %d金/个" % grow_to.sell_price)
			# 季节限制：只列能种的季节，过了季没收的会枯
			if not seasons.is_empty():
				var snames: Array[String] = []
				for si in seasons:
					snames.append(TimeManager.SEASONS[int(si)])
				lines.append("%s季能种, 过季会枯" % "/".join(snames))
	# 钓鱼图鉴：钓到过的鱼（按名字对上号）在悬浮提示里报个累计条数
	var fished: int = FishJournal.count_of(display_name)
	if fished > 0:
		lines.append("图鉴: 钓到过 %d 条" % fished)
	if description != "":
		lines.append(description)
	return "\n".join(lines)
