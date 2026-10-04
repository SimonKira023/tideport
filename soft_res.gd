class_name SoftRes
## 第三方素材软加载: 素材包不入 git 仓库(见 README 素材放置说明),
## 机器上没放素材包时返回 null, 界面留空但游戏照常跑, 不会崩。

static func tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
