# AGENTS.md —— 《潮汐港》开发交接（给 Cursor / AI 协作者）

> 这是本项目的**唯一权威交接文档**，Cursor 会自动读取本文件作为长期上下文。
> 项目内 `HANDOFF.md` 是 2026-09-16 的旧版（游戏名还是旧的《潮风港镇》），**已过期，不要以它为准**。
> `README.md` 面向玩家与仓库访客；本文件面向写代码的 AI。

---

## 0. 一句话

**《潮汐港》** —— Godot 4.7.2 + GDScript 的 2D 像素人生模拟游戏（种田 / 钓鱼 / 养殖 / 航海贸易 / 海战 / 卡牌战斗 / 伙伴养成）。
作者是**非专业程序员**（大一新生，零基础，大量依赖 AI 生成代码），**需要你代为验证与修复**。
**全程简体中文交流**，代码注释也用中文。

## 1. 环境（本机）

| 项 | 值 |
|---|---|
| 项目根 | `C:\Users\蔡璟熙\Documents\新建游戏项目` |
| 引擎 | Godot **4.7.2 stable** Win64 |
| 引擎路径 | `D:\平台\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| 主场景 | `res://scene/main_menu.tscn` |
| 游戏名（`project.godot`） | 潮汐港 |
| UI 字体 | `resources/font/IPix.ttf`（像素字体，**没有回退字体**） |
| 版本控制 | git 仓库（`main`）。⚠️ 本机 git 曾损坏过对象，`.gitignore` 里排除了 `.godot/ Godot/ tools/export/ outputs/` 等 |

## 2. 怎么跑、怎么验（每次改完必做）

```powershell
# 全量回归自测 —— 改完代码必须跑，末行出现「全部通过 ✔」才算没坏
& "D:\平台\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://tools/selftest.tscn *> tools\_st.txt
# 然后看 tools\_st.txt 最后一行

# 只查语法（最快）
& "<EXE>" --headless --path . --check-only --script res://scene/xxx.gd

# 正常启动（人工看画面）
& "<EXE>" --path .
```

- 自检脚本 `tools/selftest.gd` 有**上百节、上千条断言**，是本项目唯一的回归底线。
- 断言失败会打印 `[X]` 之类的行，末尾汇总「有 N 项没通过 ✘」；全绿时是「全部通过 ✔」。
- **探针/自检绝不能污染玩家真档**：跑自检前把 `SaveManager.enabled = false`，或把
  `SaveManager.save_path / history_dir / slot_dir` 重定向到 `user://_selftest_slots` 之类的临时目录。
- 要**截图**的探针**不能加 `--headless`**（headless 是 dummy 渲染器，`get_viewport().get_texture()` 返回 null）。
- 新增 `.wav` / 图片等资源后先跑一次 `--headless --path . --import`。

## 3. 代码地图

```
scene/          场景与游戏逻辑（game.gd 是岛上总控；main_menu.tscn 是入口）
  game.gd       岛屿场景总控（地形/碰撞/建筑/派活接线）
  slave_npc.gd  伙伴像素外观唯一真相源（MODELS / MODEL_MALE / model_for / tint_for）
  troop.gd      战役地图通用兵种单位（含哥布林/魔物）
  battle_map.gd 战役地图
  world_map.gd  航海大地图    mainland.gd  大陆据点
resources/      素材（font / texture / audio / cards_art ...）
item/           物品定义 .tres
tools/          自测、素材生成、导出打包、临时探针
soft_res.gd     第三方素材「软加载」助手（缺失留空不崩，别改成硬加载）
```

根目录散落的 `*_ui.gd`（`dialogue_ui.gd` / `backpack_ui.gd` / `troop_ui.gd` …）是各类界面面板。

**autoload 清单**（`project.godot`，跨场景常驻，顺序敏感可参考 `Research` 的位置）：
`TimeManager Weather Inventory Farm Wallet Audio Slaves Floor Crafting FloorIcon Trees OreVein Structures Legion Research Voyage Nations SaveManager Quests Recruits Marriage FishJournal Cutscenes Fullscreen`

## 4. 硬红线（违反 = 直接判错）

1. **UI 文案与所有游戏内文字只能用 ASCII 半角标点**。`IPix.ttf` 没有全角字形，全角标点会渲染成方块。
   - 禁止：`（），。！？；、`、`“”‘’《》【】「」`、`…` `—` `～`、全角空格 `U+3000`、`·` `→` `■ ● ♥ ★ ☆ ✔ ✘` 等。
   - 省略号写六个点 `......`；引号用 `""` 或不用。
   - 改完 UI 文案，务必跑自检里的「字体缺字体检」节。
2. **改完任何代码必须跑全量自检，直到「全部通过 ✔」**。不许说「应该没问题」就收工。
3. **第三方素材不入库**（`Farm RPG` / `Towball's Crossing` / `Loops Medieval` / `Sunnyside` / `Mana Seed` / `resources/character` 参考撕图…）。
   代码对它们**全部软加载容错**，缺失时留空即可。**不要把 `soft_res` 改成硬加载**，也不要把它们加进 git。
4. **坐标一律按格子算，别写像素偏移**：`Farm.TILE_SIZE == 16`，运行时 `Farm.grid_origin` 是**全局坐标**。
   - 给 `Game` 的**子节点**定位：`global_position = Farm.grid_origin + cell * 16` ✅
   - 写成 `position = ...` ❌（Game 自身偏移会被叠第二次，东西会飞出去 10 格）。
5. **实体原点在脚下**（y_sort 约定）。影子要贴脚：`make_shadow` 的 `position = Vector2(0, -7)`。
6. **`.tres` / `.tscn` 文件里不能写 `#` 注释**（`.tscn` 用 `;`）。
7. **新文案必须半角标点**，且自检 `bad_punct` 黑名单包含 `（），。！？；、`。

## 5. 最容易踩的坑（Top 10，改代码前先扫一眼）

1. **`:=` 类型推断会把 Variant 撞成 Parse Error**，而脚本解析失败会连带刷几百条无关报错。
   - 例：`for d in [Vector2i(1,0)]:` 里 `d` 是 Variant，`var c := center + d` 编译不过。
   - 修法：显式标注 `var c: Vector2i = center + d`。
   - **看到「某属性不存在 on a base object of type X」的洪水报错，先翻日志最前面的 `Parse Error`**。
2. **`CanvasLayer` 不是 `CanvasItem`**：把场景根 `visible = false` 藏不住挂在它下面的 HUD。
   藏场景一律走 `Voyage.set_scene_visible(n, on)`（可见性 + 遍历子树设所有 `CanvasLayer.visible`）。
3. **别拿 `ColorRect` 当卡片底板**：它只认 `custom_minimum_size`，子节点撑不大它 → 底板高度 0、字飘在背景上。用 `PanelContainer` + `StyleBoxFlat`。
4. **HBox 里的 `Label` 开了 autowrap 会被压成 1px 宽 → 文字竖排一列**：行内 Label 一律 `autowrap_mode = OFF` + 死宽 `custom_minimum_size.x`。
5. **`DirAccess.open("user://...")` 会返回 null**：一律用 `OS.get_user_data_dir()` 拼绝对路径（`SaveManager._abs()` 已封装）。`FileAccess` 反而没事。
6. **`FileAccess.open(WRITE)` 不会自动建目录**，缺一级就静默返回 null 写盘失败。
7. **移动/滑行的阈值别写绝对像素、位移别按被挡那一轴的分量算**（这是「战斗打完退不出去」的真凶）。
   位移用**整步长**、方向只取 `signf()`。
8. **胜负判定 = 场上敌人一个不剩**，所以敌人 AI 必须有「卡死超时自己退场」兜底（`troop._tick_stuck` / `STUCK_LIMIT`）。
9. **z_index 相对父节点累加**：给容器和子节点都设会双重叠加（桥曾因此沉到水下）。
10. **程序化图集的格子感来自纹样对齐**：每档水只给 1~2 个相位会出现规则方格；要**按格子 hash 挑相位**（别用线性式，会浮出斜条纹），并让深浅档步进不均匀。柔和渐变（云影）要单独把 `texture_filter` 设 `LINEAR`。

## 6. 关键「唯一真相源」（改前先找到它，别改下游）

| 主题 | 真相源 |
|---|---|
| 伙伴外观/性别 | `scene/slave_npc.gd` 的 `MODELS` / `MODEL_MALE` / `model_for(i)` / `tint_for(i)` / `ART_SWAP` |
| 伙伴数据（名字/生日/爱好/招募条件） | `slaves.gd` 的 `ROSTER` / `BIRTHDAYS` / `LIKES`（`ROSTER[i].id` 必须 == `"rq_%02d" % i`） |
| 劳动力分配 | `Slaves` 的 `research_tech` / `research_admin` / `dock_crew`（`Research` 只计数） |
| 游泳/水的判定 | `scene/game.gd` 的 `is_swim_water(c)`（`player.gd` 只调用，别另造一套） |
| 头顶/脚下坐标 | `Farm.TILE_SIZE` / `Farm.grid_origin` |
| 存档写档时机 | **只有每天早上 6 点**（`game.gd` 两处），关窗兜底已按设计删除，**不要加回来** |
| 婚恋 | `marriage.gd`（`BRIDES` / 判定）+ `scripts_marriage.gd`（台词工厂，static） |

## 7. 工作方式约定（作者对 AI 的期待）

- **直接动手实现，不要反复问「要不要我改」**；方案有明显分叉时用最简方案，并在回复里说清你改了什么。
- **回复要短**，别写长篇分析；结尾给出**「你现在要做什么」**的可执行步骤清单（大白话、分步）。
- 改完自动跑的验证命令要写进回复里（至少是「已跑自检，全部通过 ✔」）。
- 新增 UI 组件优先**程序化绘制**（项目风格如此，如 `wood_frame.gd` 画木质画框），少引入新贴图。
- 生成的脚步/探针放 `tools/`，命名 `_probe_xxx.gd`；一次性调试用的用完可删。

## 8. 首次在 Cursor 里开场（把这段整段发给 Cursor 的 Chat）

```
请先读项目根目录的 AGENTS.md（这是本项目的交接文档，Cursor 会自动加载）。
这是一款 Godot 4.7.2 的 GDScript 像素游戏《潮汐港》，我是非专业程序员，需要你直接动手改代码并自己验证。

三条硬规矩：
1. UI/游戏内文字只能用 ASCII 半角标点（字体 IPix.ttf 没有全角字形，会渲染成方块）。
2. 改完代码必须跑全量自检，直到末行出现「全部通过 ✔」：
   & "D:\平台\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://tools/selftest.tscn *> tools\_st.txt
3. 代码注释用中文；回复要短，结尾给我「你现在要做什么」的分步清单。

先做一件事：跑一遍上面的自检，把结果告诉我，然后用三句话总结你从 AGENTS.md 读到的项目结构。
```

---

## 附：文档分工

| 文件 | 作用 | 是否入库 |
|---|---|---|
| `AGENTS.md` | 本文件，AI 协作用交接文档 | ✅ 入库 |
| `.cursor/rules/tideport.mdc` | Cursor 常驻规则（红线精简版） | ✅ 入库 |
| `README.md` | 面向玩家/访客 | ✅ 入库 |
| `MIGRATE.md` | 换电脑/换机器搬迁手册 | ❌ 已在 .gitignore |
| `HANDOFF.md` | 旧交接记录（**已过期**） | ❌ 已在 .gitignore |