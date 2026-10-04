extends SceneTree
# 体检脚本：解析 _ui_dump.json，检查每个界面是否越出 1152x648 屏幕。
# ❗滚动容器里被裁掉的子控件 rect 会超出屏幕（这是滚动该干的事），
#   所以路径里带 ScrollContainer 的条目跳过不计。
# 用法: Godot --headless --path . --script res://tools/check_dump.gd

const W := 1152.0
const H := 648.0

func _init() -> void:
	var f := FileAccess.open("res://_ui_dump.json", FileAccess.READ)
	if f == null:
		print("NO DUMP FILE")
		quit()
		return
	var j: Variant = JSON.parse_string(f.get_as_text())
	var items: Array = j["items"]

	# 每个 tag 记录最大 right / bottom（排除滚动容器内部）
	var maxr := {}
	var maxb := {}
	var bad: Array = []
	for it in items:
		var p := str(it.get("node", ""))
		if p.contains("ScrollContainer"):
			continue
		var r: Array = it["rect"]
		var tag := str(it.get("tag", "?"))
		var right: float = r[0] + r[2]
		var bottom: float = r[1] + r[3]
		if not maxr.has(tag) or right > float(maxr[tag]):
			maxr[tag] = right
		if not maxb.has(tag) or bottom > float(maxb[tag]):
			maxb[tag] = bottom
		if right > W + 0.5 or bottom > H + 0.5:
			bad.append("%s  %s  rect=%s right=%.0f bottom=%.0f" % [
				tag, it.get("type"), str(r), right, bottom])

	print("=== PER-TAG MAX (right<=1152 / bottom<=648) ===")
	var keys := maxr.keys()
	keys.sort()
	for k in keys:
		print("  %-10s right=%6.1f  bottom=%6.1f  %s" % [
			k, float(maxr[k]), float(maxb[k]),
			("OK" if float(maxr[k]) <= W + 0.5 and float(maxb[k]) <= H + 0.5 else "OVER")])

	print("=== OVERFLOW ITEMS (%d) ===" % bad.size())
	for b in bad:
		print("  ", b)
	quit()
