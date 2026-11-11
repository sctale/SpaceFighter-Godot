# Phase 0 报告 2/6：UI 场景清单（ui_scene_inventory）

> 基线：`3371cfc`（v1.4.3）。所有行号以当前工作树为准。

## 0. 场景文件盘点（重要事实）

- 全项目**唯一** .tscn：`scenes/Main.tscn`（project.godot `run/main_scene`），只是挂载 main.gd 的壳。
- **没有**任何 UI 场景、Control 节点、Theme 资源、StyleBox 资源文件（StyleBoxFlat 在 ui_skin.gd:33-49 运行时生成并缓存）。
- 全部 UI 由 4 个脚本以 `CanvasItem._draw()` 立即模式绘制：

| 脚本 | 类型 | 角色 |
|---|---|---|
| ui_overlay.gd | `UIOverlay extends Node2D`（实例，挂 CanvasLayer layer=2） | 状态分发 + 模态屏 + 横幅 + 热区命中 |
| ui_menu.gd | `UIMenu extends RefCounted`（静态函数） | 主菜单 |
| ui_hud.gd | `UIHud extends RefCounted`（静态函数） | 战斗 HUD |
| ui_skin.gd | `UISkin extends RefCounted`（实例，绘制原语库） | 调色板/面板/文字/按钮/图标 |

## 1. 屏幕清单（6 屏 + 2 覆盖层）

状态判定集中在 `UIOverlay._state()`（ui_overlay.gd:69-79）：
`in_menu → "menu"`；`game_over → "over"`；`upgrade_pending → "upgrade"`；`paused → "paused"`；否则 `"game"`。
绘制分发在 `_draw()`（ui_overlay.gd:91-116）；点击分发在 `press()`（ui_overlay.gd:118-146），优先级 upgrade → menu → over → paused → game。

### 1.1 主菜单（menu）

- 入口：`UIMenu.draw(ci, skin, main, vw, vh, safe_top, safe_bottom, t)`（ui_menu.gd:8-161），由 ui_overlay.gd:101 调用。
- 热区（返回字典）：`cruise` / `standard` / `abyss`（难度胶囊）、`start`（开始巡航）。press 命中后返回 `diff_<key>` 或 `start`（ui_overlay.gd:127-131）。
- 元素清单：
  - Hero 机体大图：keyart `hero`，缺图回退 `player_pulse` 精灵；浮动+光晕+双轨道环+6 个 sparkle（ui_menu.gd:24-44）。
  - 标题贴纸：keyart `logo`，缺图回退文字「裂隙巡航 / AURORA RIFT」；-0.018rad 倾斜+投影底板（ui_menu.gd:47-62）。
  - 最高分面板（star 图标 + 数值，ui_menu.gd:65-71）。
  - 三档难度胶囊：图标+中文名+EASY/NORMAL/ABYSS 副标，选中填糖果色（ui_menu.gd:74-99）。
  - 开始按钮：呼吸外圈+斜向扫光+chevron 动画（ui_menu.gd:102-117）。
  - 操作提示卡：移动端/键鼠两套文案（ui_menu.gd:120-152）。
  - 页脚版本号（ProjectSettings 读取，ui_menu.gd:155-158）。
- 布局策略：全部按 `vh` 比例锚点（hero 0.140 / title 0.345 / best 0.525 / diff 0.610 / start 0.705 / hint 0.850），宽度 `min(vw-64, 460)`。
- 键盘：Enter/Space 开始，1/2/3 切难度（main.gd:1528-1537）。
- 真实截图：菜单即默认启动画面，`godot --path .` 直接截；无专属 -shot 模式。

### 1.2 战斗 HUD（game）

- 入口：`UIHud.draw(ci, skin, main, vw, vh, st, sb, sl, sr, t, pressed)`（ui_hud.gd:8-148），由 ui_overlay.gd:104 调用。
- 热区：`pause`（48×48）、`nova`（r42 圆）、`dash`（r32 圆）、`weapon`（r30 圆）。
- 元素清单：
  - 分数板 204×84：得分（display_score 缓动数字 30px）、擦弹、最高分、×N 连击芯片+2.8s 窗口条（ui_hud.gd:17-38）。
  - 船体板 158×84：船体图标阵列（上限 UPGRADE_MAX_HULL）、3 格护盾、难度名（ui_hud.gd:41-55）。
  - 暂停键（ui_hud.gd:58-62）。
  - Boss 血条（boss 存在时）：名条「称号·名·P阶段」+ 470px 封顶血条（display_boss_hp 缓动）+ 状态芯片（破防/招式预告/临界）（ui_hud.gd:65-95）。
  - 星区胶囊（无 Boss 时）：星区号+进度条 zone_progress() + 裂隙计数胶囊（ui_hud.gd:96-108）。
  - 武器板 216×86：武器图标（三线各不同）、名称+LV、充能条（失谐变红）、失谐排气/充能百分比文案（ui_hud.gd:111-135）。
  - 状态芯片：共鸣 ×N、超频倒计时（ui_hud.gd:136-141）。
  - 右下技能键组：星爆（充能环+百分比）、冲刺（CD 环+秒数）、换线（锁定态）（ui_hud.gd:144-163 + action_button 190-221）。
- 布局策略：左上/右上/左下/右下四角锚定安全区；Boss 条顶部居中。
- 键盘：Space 冲刺、X 星爆、Tab/E 换线、P/Esc 暂停、R 重开、F11 全屏（main.gd:1548-1572）。
- 真实截图：`-shot play` / `-shot boss`（main.gd:221-232）。

### 1.3 暂停模态（paused）

- 入口：`UIOverlay._draw_pause`（ui_overlay.gd:219-273）。
- 热区：`resume` / `restart` / `menu` / `opt_music` / `opt_sfx` / `opt_shake`。
- 元素：全屏暗化 0.55k、卡片 440×≤520（ease-out 入场 0.32s）、标题「暂停/巡航已冻结」、2×2 战况统计（分数/星区/击坠/擦弹）、三按钮（restart/menu 带二次确认文案「确认…？」）、三设置开关胶囊、底部操作提示。
- 二次确认：`confirm_action` + `confirm_t=2.5s` 真实时间倒计时（main.gd:614-618, 1649-1663）。
- 键盘：P/Esc 继续（main.gd:1538-1543）。
- 真实截图：`-shot pause`（main.gd:298-300, 593-594）。

### 1.4 结算模态（over）

- 入口：`UIOverlay._draw_results`（ui_overlay.gd:275-328）。
- 热区：`retry` / `menu`；**另有全屏兜底**：game_over_time>0.6s 后点任意处=retry（ui_overlay.gd:136-141）。
- 元素：暗化 0.62k、卡片 470×≤640、标题（巡航完成/巡航终止 + won 文案）、评级星章 S/A/B/C（_grade() main.gd:2119-2126，阈值 120000/60000/22000 game_config.gd:463-465）、大号得分、新纪录芯片、4 行统计（最远星区+区名/击坠/擦弹·裂隙/最高分）、再来一次+返回主菜单。
- 键盘：R/Enter 重开（main.gd:1544-1547）。
- 真实截图：`-shot gameover`（失败，main.gd:595-603）/ `-shot victory`（胜利，main.gd:243-255）。

### 1.5 突破三选一模态（upgrade）

- 入口：`UIOverlay._draw_upgrade`（ui_overlay.gd:157-217）。
- 热区：`upgrade_0/1/2`（press 返回 `upgrade_<i>`，ui_overlay.gd:120-124）。
- 元素：暗化 0.62k、卡片 470×≤500、「星区突破 / BOSS 已击破」、3 张 108px 选项卡（图标圆底+名称×N 层数+描述+数字键帽 1-3+chevron）、底部提示。
- 数据源：`main.upgrade_options`（UpgradeSystem.roll 从 CFG.UPGRADE_POOL 10 项过滤抽取，upgrade_system.gd:65-78）。
- 键盘：1/2/3 直选（main.gd:1512-1519）。
- 真实截图：`-shot upgrade`（预置层数展示 ×N，main.gd:267-280）/ `-shot upgrade_apply`（自动选第 1 张，main.gd:281-284, 591-592）。

### 1.6 设置（半屏，寄生在暂停页）

- 无独立屏。3 个开关 `opt_music/opt_sfx/opt_shake` 在暂停卡片底部（ui_overlay.gd:258-269），动作处理 main.gd:1664-1676，持久化 _save_opts。
- **主菜单无法改设置**（必须先开一局再暂停）——体验缺口，见报告 5 C1。

### 1.7 覆盖层：星区横幅 + WARNING（非模态）

- `UIOverlay._draw_banners`（ui_overlay.gd:330-347）：星区突破横幅 2.4s（区号+区名，ZONE_NAMES ui_menu.gd:5-6）；WARNING 横幅（boss_warn>0 或 boss_pending 期间持续刷新 0.55s，ui_overlay.gd:57-59）。
- 计时器在 UIOverlay._process（ui_overlay.gd:50-61），只在非菜单状态推进。

### 1.8 覆盖层：状态转场淡入

- `_fade`（ui_overlay.gd:86-89）：菜单⇄游戏切换时 1.0→0 淡出（3.4/s），深梅色 0.82 alpha 全屏。
- `_modal_t`：模态入场动画时钟（ui_overlay.gd:44-48）。

## 2. 辅助 UI（世界层，不在 CanvasLayer）

- FXLayer 飘字：拾取/突破/换线提示等（fx_layer.gd；调用例 main.gd:1642-1643, upgrade_system.gd:131-133）。跟随世界震屏，属战斗反馈而非界面，重构时保持不动。

## 3. 不存在的屏（文档提到但项目没有）

机库 Hangar、商店 Shop、任务 Missions、玩家档案/等级、成就、登录/账号、内购付费点、独立设置屏、教程关。
处置建议见报告 6 R3（免费游戏，不虚构机制）。

## 4. 屏幕 × 截图模式速查（Phase 8 证据链用）

| 屏 | 命令（窗口模式运行，自动存 build/shots/ 后退出） |
|---|---|
| 主菜单 | 默认启动即菜单（capture.ps1 定时截） |
| 战斗 HUD | `godot --path . -- -shot play` |
| Boss HUD | `godot --path . -- -shot boss`（boss2..boss6 换 Boss） |
| 暂停 | `godot --path . -- -shot pause` |
| 结算（败） | `godot --path . -- -shot gameover` |
| 结算（胜） | `godot --path . -- -shot victory` |
| 三选一 | `godot --path . -- -shot upgrade` |
| 补给箱陈列 | `godot --path . -- -shot crates` |