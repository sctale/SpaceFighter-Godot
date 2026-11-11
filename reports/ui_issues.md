# Phase 0 报告 5/6：现存 UI 问题清单（ui_issues）

> 基线：`3371cfc`（v1.4.3）。分级：A=确认缺陷（代码证据确凿）；B=结构限制；C=体验缺口；D=易回归点。
> 标注「推断」的条目未经运行时复验，修复前应先截图/实测确认。

## A. 确认缺陷（建议随重构修复）

### A1 新纪录会抹掉全部设置（存档覆写）
- 证据：`_save_best`（main.gd:390-396）`ConfigFile.new()` 后**不 load** 直接只写 `[score]best` 并 save；对比 `_save_opts`（371-378）是正确的 load-merge-save。
- 触发：任何一次刷新最高分（结算/回菜单，main.gd:1692 等）。
- 影响：`[opt] music/sfx/shake` 被抹掉，下次启动回默认（全开）。用户关掉的音效/震屏会"复活"。
- 修复方向：_save_best 改 load-merge-save（与 _save_opts 同构）。**属 UI/设置域，纳入 Phase 5/6。**

### A2 暂停中打开音乐，BGM 立即 resume（推断，代码路径确凿）
- 证据：`opt_music` 动作在 paused 时也可触发（暂停页开关）→ `music.play_zone(zone)`（main.gd:1667-1668）→ `_player.play()`（music_player.gd:37）会清除 `stream_paused`。
- 影响：暂停状态下音乐响起来，与"暂停冻结音乐"语义（main.gd:1632-1633）矛盾。
- 修复方向：play_zone 后按当前 paused 重放 `set_paused(paused)`；或暂停中只记开关不播。**纳入 Phase 5，修前运行时复验。**

## B. 结构限制（决定重构路线，见报告 6）

### B1 立即模式全量重绘，无控件语义
- 证据：UIOverlay 每帧 queue_redraw（ui_overlay.gd:66）；main 在各冻结态也 queue_redraw（main.gd:622/626/629/665）；全 UI 无 Control/Theme/焦点/无障碍语义。
- 影响：无法用 Godot 内建焦点导航/读屏；每帧重画全部面板文字（StyleBox 已缓存缓解，ui_skin.gd:33-49）。低端机帧耗未测量（Phase 7 补）。

### B2 UI 动画状态寄存在 main 上
- 证据：display_score/display_boss_hp 的缓动写在 UIOverlay._process（ui_overlay.gd:49-55），HUD/结算读 main 字段。
- 影响：重构搬动缓动逻辑时若漏掉，分数跳变/Boss 条瞬移。必须保持这两个字段被驱动。

### B3 硬编码颜色散落
- 证据：暗化色 `Color(0.10,0.07,0.16,…)`（ui_overlay.gd:87/159/221/277 等）、缺省 tint `"#FF8FB1"`（ui_overlay.gd:184）、飘字 `"#FFD27A"`（main.gd:1642；upgrade_system.gd:133）、HUD 内联 Color（ui_hud.gd 多处）。
- 影响：Design Token 化（Phase 1）必须全量收编这些散点，否则换肤不彻底。

### B4 字体子集管线依赖
- 证据：AuroraCJK.ttf 是子集，由 tools/gen_font_subset.py 扫描 scripts/**.gd 全部字符生成；main.gd:349-358 加载。
- 影响：**任何新增中文文案后必须重跑子集脚本**，否则豆腐块。源字体与 pyftsubset 本机已验证可用。纳入每阶段收尾清单。

## C. 体验缺口（重构可补，不新增机制）

### C1 主菜单无设置入口
- 证据：设置开关只在暂停页（ui_overlay.gd:258-269）；菜单热区仅 diff×3+start（ui_menu.gd）。
- 影响：改音乐/音效必须先开一局再暂停。建议提独立设置屏+菜单入口（复用现有 3 开关，零新机制）。

### C2 结算页 0.6s 后全屏点按=重开
- 证据：ui_overlay.gd:136-141（game_over_time>0.6 兜底 retry）。
- 影响：想看结算数据时误触重开。暂停页已有二次确认范式（main.gd:1649-1663），结算兜底可考虑去掉或加确认。**待用户确认取舍。**

### C3 UI 按钮无点击音/触感
- 证据：_handle_ui_action（main.gd:1615-1679）无 sfx 调用；对比选卡有 sfx.play_pick（upgrade_system.gd:130）。
- 影响：按钮反馈只有 0.2s 视觉高亮（ui_overlay.gd:149-155）。可选补点击音（复用现有 sfx 资源，不新增机制）。

### C4 模态内容固定高 vs 外框弹性（推断）
- 证据：暂停卡内容需 ≈500px（按钮 by=238 + 3×68 + 开关 40 + 页脚，ui_overlay.gd:238-271），外框 h=min(vh-st-sb-80, 520)；结算内容需 ≈600px（rows 296+160 + 按钮 118，ui_overlay.gd:296-327），外框 min(…,640)；三选一需 ≈474px，外框 min(…,500)。
- 影响：竖屏手机（stretch expand 下设计高度 ≥960）安全；**桌面小窗/横屏**（vh<~650）内容会溢出卡片。Phase 7 需小窗截图复验，必要时内容随 h 缩放。

### C5 HUD 四角固定宽度（推断）
- 证据：分数板 204 + 船体板 158 + 暂停 48 按左右锚定（ui_hud.gd:14-16）；武器板 216（:111）。
- 影响：vw 很窄（桌面小窗 <~460）时左右面板可能重叠；宽屏（平板/expand）中央留白大。Phase 7 复核。

### C6 无教程/无关于页
- 证据：操作说明仅菜单提示卡（ui_menu.gd:120-152）；版本仅页脚（:155-158）。
- 影响：文档未强制；可选在设置屏加"关于/版本"行（零新机制）。

## D. 易回归点（历史已修，重构必须保住）

| # | 既有成果 | 证据/出处 | 重构注意 |
|---|---|---|---|
| D1 | 分数块不被 Boss 面板遮挡、文字不裁剪 | 任务 #29/#34（v0.21.7）；ui_hud.gd 顶部布局 | 改 HUD 顶部必须复截 Boss 战 |
| D2 | 防误触二次确认（重开/回菜单） | v1.3.4；main.gd:614-618, 1649-1663 | 动作语义与 2.5s 倒计时保留 |
| D3 | 安全区底栏不被导航栏挡 | main.gd:314-325；CFG.SAFE_* | 沿用 safe 参数链，不直读 DisplayServer |
| D4 | 中文不豆腐（随包子集字体） | main.gd:349-358（Unity 踩坑注释） | 新文案重跑子集（B4） |
| D5 | 触屏热区优先于拖拽驾驶 | main.gd:1584-1592, 1602-1610 | 技能键移位必须同步 press 热区 |
| D6 | WARNING/突破横幅时序对齐 Unity | ui_overlay.gd:50-61（Announce 2.7s 注释） | 横幅计时器语义保留 |
| D7 | 分数/Boss 血缓动手感 | ui_overlay.gd:49-55（exp -7/-6） | 见 B2 |
| D8 | 自动开火（无开火键） | main.gd:727+ _update_player_fire | 不要按文档惯性加开火按钮 |

## 修复优先级建议

1. A1（存档覆写）——真实损害用户设置，必修，改动极小。
2. C1（独立设置+菜单入口）——文档 Phase 5 核心，复用现有开关。
3. A2（暂停音乐）——随设置屏一起修+复验。
4. B3/B4（Token 收编+字体管线）——Phase 1 基础设施。
5. C2/C3/C4/C5——按用户取舍与 Phase 7 实测结果决定。
------------------------------------------------------------------------

## Phase 6 治理结论（2026-11-11 补记）

- **B2 已解耦**：display_score / display_boss_hp 缓动与 hurt_flash / shield_flash 衰减
  从 UIOverlay._process 搬回 main._process（所有状态走真实时间，早于 in_menu/paused 等提前 return）。
  UIOverlay 现在对 main 字段**零写入**，只读 + 自有局部视觉时钟（_t/_modal_t/_fade/_banner_t/_warning_t/_boss_bar_k/_lv_pulse）。
  未新造平行 UIManager，符合文档数据架构要求。
- **飘字对象池评估：不新增**。fx_layer 飘字/粒子本就是字典数组 + 硬上限
  （MAX_PARTS=420 / MAX_TEXTS=40，溢出 pop_front），无逐条 Node 创建、无无限增长；
  对象池只增复杂度无实测收益。低端机帧耗留 Phase 7 实测。
- **B3 收尾**：WARNING 横幅硬编码色收编为 WARNING_BG / WARNING_TINT / WARNING_TEXT Token；
  三选一默认 tint 改读 skin.ACCENT_BLUE，移除 "#26C6F6" 散点。

## Phase 7 复验结论（2026-11-11 补记，桌面侧）

- **C4/C5 在窗口层结构性不成立**：project.godot stretch=canvas_items + aspect=expand，
  实测视口恒 ≥540×960（360×640 窗→540×960 等比缩放；800×600→1280×960；300×900→540×1620）。
  Phase 0 报告按"视口=窗口尺寸"假设的像素溢出/重叠推算在此 stretch 配置下不成立。
  1280×960 与 540×1620 两极端比例下 play/pause/gameover/upgrade 截图：模态居中、HUD 四角锚定、无溢出。
- 模态高度唯一收缩变量是移动端 safe area（st/sb），竖屏锁定下实测复核（模拟器/真机）。
- **SwiftShader 软渲染黑屏属引擎限制**：Godot 4.7 内建 Scene/CanvasShaderGLES3 在
  GL_MAX_FRAGMENT_UNIFORM_VECTORS=261 下链接失败（非项目自定义 shader；planet_orb 仅 9 uniform）。
  模拟器验收改用 -gpu host；backdrop.gd 对自定义星云 shader 已有 SwiftShader 降级。

## Phase 7 复验结论（2026-11-12 补记，Android 侧 + A3 修复）

- **A3（新发现真 bug，已修）：Android 触屏双触发**。Godot 默认
  `emulate_mouse_from_touch=true`，一次物理点按先后派发 InputEventMouseButton 与
  InputEventScreenTouch，main._unhandled_input 两个分支都处理 → 切换型动作执行两次互相抵消
  （设置开关"点了没反应"）；非切换型（齿轮开设置）因第二次落点不在热区而表现正常，极具迷惑性。
  证据：临时调试日志同一次点按出现两次热区命中（mouse 分支先、touch 分支后）；
  桌面探针 SETTINGS_PROBE_OK 排除布局/逻辑问题。修复：project.godot
  `[input_devices] pointing/emulate_mouse_from_touch=false`（桌面真实鼠标不受影响）。
- **E2E 全绿**（test-android-36 模拟器，-gpu host，1080×1920=2×设计坐标，safe=0）：
  菜单渲染 → 齿轮进设置 → 单击音乐=关、三开关全关（android_settings4/5.png）→
  强杀重启仍全关（持久化，android_settings6.png）→ 恢复全开 → 返回→开始→战斗 HUD
  （android_play.png）→ 暂停（android_pause.png）→ 继续巡航恢复战斗（android_resume.png）。
  全程 logcat `SCRIPT ERROR` = 0。
- **C4/C5 Android 侧 likewise 不成立**：模态居中、HUD 四角锚定，无溢出无遮挡（见上述截图）。
- **性能参考值**：x86_64 模拟器 + arm64 翻译层 + host GPU，gfxinfo 50th=26ms / 90th=40ms /
  99th=73ms（仅翻译层环境参考，非真机数据）；战斗/暂停截图无掉帧撕裂迹象，
  粒子/飘字硬上限（420/40）未触顶。真机帧耗待用户设备反馈。
