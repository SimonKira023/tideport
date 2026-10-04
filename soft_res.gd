class_name SoftRes
## 第三方素材软加载: 素材包不入 git 仓库(见 README 素材放置说明),
## 机器上没放素材包时返回 null, 界面留空但游戏照常跑, 不会崩。

static func tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## 扫描图集 region 里非透明像素底边离帧底还差几像素。
## 这套素材很多帧内容不贴帧底（工作台/箱/路灯实测都偏上），节点原点约定在
## 「内容底边」, 摆出来就悬空 —— 拿这里返回的留白数把贴图往下挪同样像素就贴地了。
## tex 为 null（素材缺失）或整块全透明时返回 0, 维持原状不崩。
static func bottom_gap(tex: Texture2D, region: Rect2) -> int:
	if tex == null:
		return 0
	var img := tex.get_image()
	if img == null:
		return 0
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var x0 := maxi(int(region.position.x), 0)
	var y0 := maxi(int(region.position.y), 0)
	var x1 := mini(int(region.end.x), img.get_width())
	var y1 := mini(int(region.end.y), img.get_height())
	if x1 <= x0 or y1 <= y0:
		return 0
	var gap := 0
	for y in range(y1 - 1, y0 - 1, -1):
		var row_has := false
		for x in range(x0, x1):
			if img.get_pixel(x, y).a > 0.01:
				row_has = true
				break
		if row_has:
			break
		gap += 1
	if gap >= y1 - y0:      # 整块全透明: 素材多半错位了, 不动偏移更安全
		return 0
	return gap
