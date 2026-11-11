# Phase 0 报告 1/6：项目审计（project_audit）

> 审计日期：2026-11-11 · 审计基线：`3371cfc`（v1.4.3 / code 22）
> 依据文档：《Godot_飞机游戏_UI全面重构实施方案》§9 —— 本阶段只读审计，未修改任何原有项目文件。
> 所有结论均附 `文件:行号` 证据；标注「推断」的条目未经运行时验证。

## 1. 项目基本信息

| 项 | 值 | 证据 |
|---|---|---|
| 游戏名 | 裂隙巡航 / Aurora Rift（Space Fighter Godot） | project.godot `[application]`；ui_menu.gd:52 |
| 引擎 | Godot 4.7.2 stable（本机 `~/bin/godot`） | project.godot `config/features` |
| 渲染 | GL Compatibility（桌面 + 移动均是） | project.godot `[rendering]` |
| 设计视口 | 540×960 竖屏 | project.godot `[display]`；game_config.gd:5-6 |
| 拉伸策略 | mode=`canvas_items`，aspect=`expand`，scale_mode=`fractional` | project.godot `[display]` |
| 方向 | 竖屏（orientation=1），移动端强制全屏 | project.godot；main.gd:190-191 |
| 当前版本 | 1.4.3 / Android versionCode 22 | project.godot；export_presets.cfg |
| 包名 | com.sctale.spacefightergodot | export_presets.cfg |
| 商业模式 | **免费游戏，无内购**（用户明确指示；代码中无任何货币/商店/IAP 痕迹） | 全库检索无 currency/shop/iap 相关系统 |

## 2. 代码结构与规模

唯一场景文件：`scenes/Main.tscn`（壳，挂载 main.gd）。**没有任何 UI 场景、没有 Control 节点、没有 Theme 资源**（详见报告 2）。

脚本（scripts/，共 17 个 .gd，约 6240 行）：

| 文件 | 行数 | 职责 | 与 UI 重构的关系 |
|---|---|---|---|
| main.gd | 2133 | 总控：状态机/输入路由/世界更新/持久化 | **高危**：输入与状态耦合，UI 只可改读取侧 |
| boss.gd | 757 | 3 台 Boss × 阶段 × 22 招状态机 | 冻结（UI 只读 title/name/phase/cast_label 等） |
| game_config.gd | 621 | 全部数值常量（对齐 Unity/网页版） | **冻结**：180 项门禁守着 |
| ui_overlay.gd | 347 | UI 总控：状态分发/模态/横幅/点击热区 | 重构主战场 |
| weapon_system.gd | 303 | 三线武器/蓄能/共鸣/换线 | 冻结（UI 只读） |
| enemy.gd | 303 | 敌机 roster | 冻结 |
| backdrop.gd | 274 | 每星区天空/星野 | 低危（菜单背景可复用） |
| ui_hud.gd | 221 | 战斗 HUD 静态绘制 | 重构主战场 |
| collision.gd | 207 | 判定 | 冻结 |
| wave_director.gd | 193 | 波次/配额/Boss 触发 | 冻结 |
| ui_skin.gd | 189 | 调色板 + 绘制原语（事实上的设计系统） | **Phase 1 扩展基座** |
| fx_layer.gd | 175 | 飘字/爆炸等战斗特效 | 低危 |
| ui_menu.gd | 161 | 主菜单静态绘制 | 重构主战场 |
| upgrade_system.gd | 133 | 突破三选一卡池/应用 | 冻结逻辑，卡面视觉可改 |
| sfx.gd | 111 | 音效 | 冻结 |
| music_player.gd | 81 | 每星区 BGM | 冻结（有一处暂停交互缺陷，见报告 5） |
| crate.gd | 31 | 补给箱实体 | 冻结 |

资产：`assets/fonts/AuroraCJK.ttf`（Noto Sans CJK 子集，约 300KB）、`assets/keyart/hero.png + logo.png`（Blender 3D 渲染）、`assets/ships/`（212 个精灵）、`assets/music/zone_01..10.ogg`、`assets/icons/`。

参照系：`reference/web/www/js/*.js`（数值真源）、`build/_unity_ref/`（Unity v0.21.14 行为参照，已归档）。两者均被 export_presets.cfg 排除出包。

## 3. 运行时架构（关键审计结论）

**本项目 UI 是立即模式（immediate-mode）绘制，不是 Godot 控件树。**

节点树（main.gd:331-346 `_spawn_visuals`）：

```
Main (main.gd, Node2D)
├─ SpaceBackdrop   z=-1000（每星区天空）
├─ FXLayer         （战斗飘字/特效，世界坐标）
├─ Sfx / MusicPlayer / WaveDirector / CollisionSystem / UpgradeSystem（逻辑节点）
└─ CanvasLayer layer=2
   └─ UIOverlay (Node2D)  ← 全部 UI 在这里用 _draw() 画出来
```

- 每帧 `UIOverlay._process` → `queue_redraw()`（ui_overlay.gd:66），`_draw()` 按状态分发到静态绘制函数（ui_overlay.gd:91-116）。
- 绘制函数**返回热区矩形字典**（如 ui_menu.gd:8 `draw(...) -> Dictionary`），`UIOverlay.press(p)` 做命中检测返回动作字符串（ui_overlay.gd:118-146），main.gd `_unhandled_input`（1511）→ `_handle_ui_action`（1615）消费。
- UI 放在独立 CanvasLayer，不受世界震屏影响（main.gd:340-346；震屏只作用于世界绘制）。
- `UISkin`（RefCounted，ui_skin.gd）已集中管理调色板 + StyleBoxFlat 缓存 + 文字/按钮/图标原语——**这是现成的设计系统种子**，文档 Phase 1 的 Design Token 化应在此扩展，而不是另起炉灶。

## 4. 持久化

`user://save.cfg`（ConfigFile）：

| 键 | 读写位置 |
|---|---|
| [score] best | 读 main.gd:364；写 _save_best main.gd:390-396 |
| [opt] music / sfx / shake | 读 main.gd:365-367；写 _save_opts main.gd:371-378 |

**没有**货币、玩家等级、永久强化、机库、商店、任务、成就等任何持久化成长数据。强化是单局三选一（upgrade_system.gd），局末即弃。
已发现 `_save_best` 会覆写丢设置的缺陷，见报告 5 条目 A1。

## 5. 验证与交付基础设施（现成、可复用）

| 设施 | 命令/位置 | 现状 |
|---|---|---|
| 数值门禁 | `godot --headless --path . --script res://tools/verify_numbers.gd` | **VERIFY_OK checks=180**；不加载 main.gd |
| 行为自检 | `godot --headless --path . -- -selftest` | **SELFTEST_OK n=8**；main.gd 解析错误会挂起 |
| 调试入口 | `-boss` / `-play` / `-shot <mode>`（main.gd:203-300） | shot 模式含 play/boss..boss6/crates/victory/demo/action/upgrade/upgrade_apply/motes/switch/**pause/gameover**，自动存 `build/shots/ui_<mode>_<w>x<h>.png` 后退出（main.gd:582-613）——**UI 各屏真实运行截图可一键产出** |
| 桌面截屏 | build/capture.ps1（System.Drawing 全屏捕获） | 上一版验收用过 |
| Android 构建 | JAVA_HOME=jdk-17.0.19+10，ANDROID_HOME=本机 Sdk；`godot --headless --export-release "Android"` | v1.4.3 已验证 |
| 真机/模拟器 | adb 需 `TEMP/TMP=build/`；模拟器 test-android-36（-gpu angle_indirect）；apksigner/aapt2 在 build-tools/35.0.0 | 上一版 0 SCRIPT ERROR |
| 字体子集管线 | `python tools/gen_font_subset.py`（扫 scripts/**.gd 全部字符） | 源字体 reference/artgen/fontwork/NotoSansCJK-Regular.ttc 与 pyftsubset 本机均在（已验证） |
| 提交纪律 | `git -c user.name=sctale -c user.email=...`；多会话并发，提交前查 HEAD/origin | 工作区硬规则 |

## 6. 与方案文档假设的对照（范围裁剪依据）

| 文档假设存在的系统 | 项目实际 | 处置建议 |
|---|---|---|
| 主菜单 | ✅ 有（ui_menu.gd） | 按 Phase 2 优化 |
| 战斗 HUD | ✅ 有（ui_hud.gd） | 按 Phase 3 优化（最高优先） |
| 机库 Hangar | ❌ 不存在（机体=武器线皮肤，无选择/养成） | 跳过，或改只读「武器图鉴」（待用户确认） |
| 局内升级 | ✅ 有（突破三选一，upgrade_system.gd） | 按 Phase 4 只做卡面视觉 |
| 商店 Shop / 货币 | ❌ 不存在 | **跳过**（免费游戏，不做内购；文档红线也不许虚构机制） |
| 任务 Missions | ❌ 不存在 | **跳过**（同上） |
| 玩家等级 / 永久成长 | ❌ 不存在 | 跳过 |
| 结算 Results | ✅ 有（ui_overlay.gd:275） | 按 Phase 5 优化 |
| 暂停 Pause | ✅ 有（ui_overlay.gd:219，含二次确认+设置开关） | 按 Phase 5 优化 |
| 独立设置 Settings | ⚠️ 半有：3 个开关藏在暂停页（main.gd:1664-1676） | 建议提为独立屏+主菜单入口（复用现有开关，不新增机制） |
| UIManager 生命周期 | ⚠️ 对应物是 UIOverlay 状态分发 | Phase 6 治理现有分发，不新造平行系统 |
| Android 适配 | ✅ 已有安全区+stretch（main.gd:304-328） | Phase 7 复核+补性能测量 |

## 7. 审计结论摘要

1. 项目健康：门禁 180 + 自检 8 全绿，v1.4.3 已真机验收；UI 重构可以在不动玩法数值的前提下进行。
2. **文档的 Control/Theme 技术假设与项目立即模式现实不符**——这是最大的路线决策点（报告 6 R1）。
3. **文档的暗色科幻 Token 与现有奶油贴纸视觉方向冲突**——现有视觉是此前多轮 deliberate 决策（含 3D keyart 配套），需要用户拍板（报告 6 R2）。
4. 文档 Phase 4/5 的机库/商店/任务/货币在本项目不存在，按「不做内购 + 不虚构机制」原则裁剪（报告 6 R3）。
5. 发现 2 个与 UI/设置相关的现存缺陷（存档覆写、暂停中开音乐），可在重构中顺手修复（报告 5）。
6. 各屏真实运行截图有现成 `-shot` 管线，Phase 8 证据链成本低。