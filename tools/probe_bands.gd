# e29c 探针: 验证 RECIPES 色带在每张动作图上的命中情况。
# 关注两件事:
#  1. Manu 的「白帽带」(亮低饱和) 和「黑发挑染带」(暗低饱和) 逐行(y%32)分布 ——
#     帽带靠 ybot=9 圈帧顶, 若挥锄/挥剑动作里帽子掉到 y>9 就会漏染。
#  2. 其他模型各色带在每张图的总命中数 —— 某张图命中 0 就会出现「换动作就变色」。
extends SceneTree

const BASE := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/Pre-made/%s/%s"
const SHEETS := ["Idle.png", "Walk.png", "Hoe.png", "Watering.png", "Sickle.png", "Sword.png", "Bow and Arrow.png"]

func _init() -> void:
	var manu_hat := [0.0, 0.25, 0.50, 2.0]   # s<=0.25, v>=0.50
	var manu_hair := [0.0, 0.35, 0.06, 0.28] # s<=0.35, v 0.06~0.28
	for model in ["Alex", "Lyria", "Manu", "Tori"]:
		for file in SHEETS:
			var path := BASE % [model, file]
			if not FileAccess.file_exists(path):
				print("%s/%s : (无此图)" % [model, file])
				continue
			var img: Image = (load(path) as Texture2D).get_image()
			img.convert(Image.FORMAT_RGBA8)
			var w := img.get_width()
			var h := img.get_height()
			if model == "Manu":
				var row_hat := {}
				var row_hair := {}
				for y in h:
					for x in w:
						var c := img.get_pixel(x, y)
						if c.a < 0.1:
							continue
						var ry := y % 32
						if c.s <= manu_hat[1] and c.v >= manu_hat[2]:
							row_hat[ry] = int(row_hat.get(ry, 0)) + 1
						if c.s <= manu_hair[1] and c.v >= manu_hair[2] and c.v <= manu_hair[3]:
							row_hair[ry] = int(row_hair.get(ry, 0)) + 1
				var hs := []
				var hk := row_hat.keys()
				hk.sort()
				for k in hk:
					hs.append("y%d:%d" % [k, row_hat[k]])
				var ds := []
				var dk := row_hair.keys()
				dk.sort()
				for k in dk:
					ds.append("y%d:%d" % [k, row_hair[k]])
				print("Manu/%s 帽带[%s] 发带[%s]" % [file, " ".join(hs), " ".join(ds)])
			else:
				# 其他模型: 只统计「高饱和彩色像素」在各图的分布概况(命中池是否为空)
				var total := 0
				var sat_hi := 0
				for y in h:
					for x in w:
						var c := img.get_pixel(x, y)
						if c.a < 0.1:
							continue
						total += 1
						if c.s >= 0.35:
							sat_hi += 1
				print("%s/%s 不透明=%d 高饱和(>=0.35)=%d" % [model, file, total, sat_hi])
	quit(0)
