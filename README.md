# 潮汐港

像素风港口小镇生活模拟游戏，使用 Godot 4.7.2 开发。

种田、钓鱼、养殖、航海贸易、海战、卡牌收集、伙伴养成…… 从一间小木屋开始，把潮汐港经营成自己的家。

## 下载游玩（普通玩家看这里）

**不用装 Godot、不用克隆仓库**，两步开玩：

1. 到 [Releases](https://github.com/SimonKira023/tideport/releases) 页下载最新版本的 `潮汐港demo_win64.zip`
2. 解压后双击里面的 `潮汐港demo5.exe`

> **首次运行提示**：若弹出「Windows 已保护你的电脑」，点 **更多信息 → 仍要运行** 即可。程序没有购买数字签名，属独立游戏正常现象，放心运行。
>
> 存档保存在本机 `%APPDATA%\Godot\app_userdata\潮汐港\`，以后下载新版本直接覆盖解压，进度不会丢。

## 运行

1. 安装 [Godot 4.7.2](https://godotengine.org/download)（标准版即可，导出才需要 .NET 版）
2. 用 Godot 打开本项目根目录的 `project.godot`
3. 按 F5 运行（主场景：`scene/main_menu.tscn`）

命令行运行：

```
Godot_v4.7.2-stable_win64_console.exe --path . 
```

## 自测

项目自带全量回归自测（数百条断言）：

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/selftest.tscn
```

全部 PASS 输出 `SELFTEST PASS`。

## 素材放置说明

仓库里只包含**代码**和**自产/CC0 素材**（生成脚本在 `tools/`，卡牌原图见 `resources/cards_src/SOURCES.txt`）。以下第三方素材包**不随仓库分发**（各自许可，请自行获取后放入对应目录）；**不放也能玩**——代码对它们全部软加载容错，缺失时相关贴图/音乐留空，控制台有警告但不崩。

| 放置目录（resources/ 下） | 内容 | 用途 | 缺失时表现 |
|---|---|---|---|
| `Farm RPG - Tiny Asset Pack - (All in One)/` | 预制角色（Josh/Lyria/Manu 等） | 玩家、伙伴、船员的形象帧 | 角色贴图留空，功能不受影响 |
| `Sunnyside_World_Assets/` | 作物等场景元素 | 农田作物渲染 | 作物不显示 |
| `Towball's Crossing Deluxe!/` | 岛屿瓦片 + 音乐 | 主岛地表/换季贴图、岛屿 BGM | 换季贴图跳过、岛屿无 BGM |
| `Loops Medieval Vol. 2/` | 中世纪风音乐循环 | 部分 BGM 与开场曲 | 对应曲目安静 |
| `FREE Mana Seed Character Base Demo 2.0/` | 角色基础骨骼帧 | 预留（当前代码无引用） | 无影响 |
| `music-loop-bundle-2026-q2/` | 音乐循环包 | 预留（当前代码无引用） | 无影响 |

另外 `resources/audio/` 下旧版曾放过的星露谷 ripping 音频已从仓库剥离，代码亦无引用。

## 自产素材怎么重新生成

所有自产音频/贴图都有生成脚本，改完脚本重跑即可：

| 脚本（tools/） | 产物 |
|---|---|
| `make_audio.py` | `resources/audio/sfx/*.wav` 与 `bgm/bgm_*.wav` |
| `make_card_art.gd` / `make_portraits.gd` / `make_boat.gd` / `make_cover.gd` | `resources/cards_art/`、`resources/texture/` 各贴图 |
| `_make_bald.py` / `_make_boat.py` | 部分贴图源图 |

注: `make_portraits.gd` 生成时参考的撕图 `resources/character/` 未入库（网络图源许可不明），重生成立绘需自备参考图。

## 目录结构

```
scene/          全部游戏场景与逻辑脚本（game.gd 为总控）
resources/      素材（cards_src 为 CC0 卡牌原图 + SOURCES.txt 出处清单）
item/           物品定义 .tres
tools/          自测、素材生成、导出打包等开发脚本
soft_res.gd     第三方素材软加载助手（缺失留空不崩）
```

## 许可证

代码与自产素材以 [MIT](LICENSE) 发布。第三方素材包（见上表）版权归各自作者，不入库、不随本项目分发，使用前请阅读其原始许可。
