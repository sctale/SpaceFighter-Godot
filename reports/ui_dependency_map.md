# Phase 0 报告 3/6：UI 依赖地图（ui_dependency_map）

> 基线：`3371cfc`（v1.4.3）。本图是重构时的「可动/不可动」边界依据。

## 1. 节点与调用拓扑

```
scenes/Main.tscn
└─ Main (main.gd)
   ├─ SpaceBackdrop (backdrop.gd, z=-1000)      ← 读 main.zone / view_size
   ├─ FXLayer (fx_layer.gd)                     ← 世界层飘字，main.fx 引用
   ├─ Sfx / MusicPlayer                         ← main.opt_sfx / opt_music 控制
   ├─ WaveDirector / CollisionSystem / UpgradeSystem（纯逻辑，RefCounted 风格挂 main）
   └─ CanvasLayer (layer=2, main.gd:340-342)
      └─ UIOverlay (ui_overlay.gd)
         ├─ skin = UISkin.new(font)             (ui_overlay.gd:31-32)
         ├─ _draw() 分发：
         │   ├─ menu    → UIMenu.draw(...)      (ui_overlay.gd:101)
         │   ├─ game    → UIHud.draw(...)       (ui_overlay.gd:104)
         │   ├─ upgrade → _draw_upgrade(...)    (ui_overlay.gd:106)
         │   ├─ paused  → _draw_pause(...)      (ui_overlay.gd:108)
         │   └─ over    → _draw_results(...)    (ui_overlay.gd:110)
         └─ press(p) → 动作字符串 → main._handle_ui_action()
```

字体链：`_load_font()`（main.gd:349-358）加载 assets/fonts/AuroraCJK.ttf → `ui.font` → `UISkin.font`；FXLayer 也共用（main.gd:338）。

## 2. UI 对 main 的只读依赖（重构必须保持可读）

| UI 模块 | 读取的 main 字段 | 证据 |
|---|---|---|
| UIMenu | in_menu, best_score, difficulty, is_mobile, _keyart_tex(), _ship_tex() | ui_menu.gd 全篇 |
| UIHud | display_score, score, graze, best_score, multiplier, combo_timer, player_lives, player_shields, upgrades["max_hull"], difficulty, boss(title_zh/name_zh/phase/stun/cast_label/telegraph/desperate/hp_frac), display_boss_hp, zone, zone_progress(), rift, weapons(active_id/active()/resonance/unlocked_count()), overdrive, nova, dash_cd | ui_hud.gd:17-163 |
| _draw_upgrade | upgrade_options（id/name/desc/tint/icon/stacks） | ui_overlay.gd:170-211 |
| _draw_pause | score, zone, total_kills, graze, confirm_action, opt_music/sfx/shake, is_mobile | ui_overlay.gd:232-271 |
| _draw_results | _grade(), won, score, best_score, zone, total_kills, graze, rift | ui_overlay.gd:283-321 |
| _draw_banners | zone, boss_warn, boss_pending（经 _process） | ui_overlay.gd:50-61, 330-347 |
| _process 缓动 | **写** main.display_score / main.display_boss_hp（UI 动画状态寄存在 main 上） | ui_overlay.gd:49-55 |

⚠️ 唯一「UI 写 main」的通道就是 display_score / display_boss_hp 两个缓动值（ui_overlay.gd:49-55）。重构若搬动缓动逻辑，必须保证这两个字段仍被正确驱动（HUD 与结算都读它们）。

## 3. 动作字符串全目录（press → _handle_ui_action）

| 动作 | 来源屏 | 处理（main.gd） | 效果 |
|---|---|---|---|
| `diff_cruise/standard/abyss` | 菜单 | 1622-1627 | 设 difficulty |
| `start` | 菜单 | 1628-1629 | _start_run → _reset_game |
| `pause` | HUD | 1630-1633 | paused=true + music.set_paused(true) |
| `nova` | HUD | 1634-1635 | _trigger_nova（main.gd:870） |
| `dash` | HUD | 1636-1637 | _trigger_dash（main.gd:843） |
| `weapon` | HUD | 1638-1643 | weapons.cycle_weapon()；未解锁时飘字提示 |
| `resume` | 暂停 | 1644-1648 | paused=false + 清 confirm + 音乐恢复 |
| `restart` | 暂停 | 1649-1656 | 暂停中需二次确认（confirm_t=2.5s），否则 _start_run |
| `retry` | 结算 | 1649-1656 | 直接 _start_run（无损失） |
| `menu` | 暂停/结算 | 1657-1663 | 暂停中需二次确认，否则 _to_menu |
| `opt_music` | 暂停 | 1664-1669 | 翻转+应用+（开时）play_zone+存档 |
| `opt_sfx` | 暂停 | 1670-1673 | 翻转+应用+存档 |
| `opt_shake` | 暂停 | 1674-1676 | 翻转+存档 |
| `upgrade_0/1/2` | 三选一 | 1616-1618 | _choose_upgrade → UpgradeSystem.choose |

`press()` 命中优先级（ui_overlay.gd:118-146）：upgrade → menu → over（按钮优先，0.6s 后全屏兜底 retry）→ paused → game。
`_flash_action`（ui_overlay.gd:149-155）：按下高亮 0.2s（pressed/pressed_t）。

## 4. 键盘映射全表（main.gd:_unhandled_input 1511-1573）

| 状态 | 键 | 行为 | 行号 |
|---|---|---|---|
| upgrade | 1/2/3 | 选卡 | 1513-1519 |
| menu | Enter/Space | 开始 | 1529-1530 |
| menu | 1/2/3 | 切难度 | 1531-1536 |
| paused | Esc/P | 继续 | 1538-1543 |
| over | R/Enter | 重开 | 1544-1547 |
| game | R | _reset_game | 1549-1550 |
| game | Esc/P | 暂停+音乐冻结 | 1551-1554 |
| game | 1/2/3 | 切难度（局内也生效） | 1555-1560 |
| game | Space | 冲刺 | 1561-1562 |
| game | X | 星爆 | 1563-1564 |
| game | Tab/E | 换线 | 1565-1567 |
| game | F11 | 全屏切换 | 1568-1572 |

## 5. 触屏/鼠标路由（重构最易回归处）

- 模态屏（menu/paused/over/upgrade）：按下 → `ui.press` → `_handle_ui_action`，**不进入拖拽**（main.gd:1580-1583, 1598-1601, 1512-1526）。
- 战斗屏：先打热区（pause/nova/dash/weapon），命中即消费；**未命中才落到拖拽驾驶**（main.gd:1584-1592, 1602-1610）。
- 拖拽：`_start_drag` 抓取偏移钳制（main.gd:1682-1684），ScreenDrag/MouseMotion 更新 pointer_pos（1593-1594, 1611-1612）。
- 自动开火：无开火键，_update_player_fire 持续射击（main.gd:727+）——**不要按文档惯性加「开火按钮」**。

## 6. 持久化依赖

```
_load_best (main.gd:361-368)  ← user://save.cfg  [score]best [opt]music/sfx/shake
_save_opts (371-378)          → load-merge-save（正确）
_save_best (390-396)          → 新建 ConfigFile 只写 best（缺陷：抹掉 [opt]，报告5 A1）
_apply_opts (381-387)         → sfx.enabled / music.enabled(+stop)
```

调用点：_ready→_load_best；opt_* 动作→_save_opts；_to_menu→_save_best（1692）；game_over 结算链→_save_best；-shot victory 也调（255）。

## 7. UISkin 原语 × 调用方（Phase 1 组件化的现成清单）

| 原语（ui_skin.gd） | 行号 | 调用方 |
|---|---|---|
| panel_style/panel（StyleBox 缓存） | 33-53 | 全部 UI 模块 |
| text / text_center / text_right（8 向描边） | 56-79 | 全部 |
| button（按下位移+高光条） | 82-94 | menu start、pause 三键、results 两键 |
| keycap | 97-100 | menu 提示、upgrade 数字键 |
| icon_star/burst/ship/shield/heart/pause/play/chevron/crossed | 103-160 | HUD/菜单/模态/技能键 |
| sparkle / glow / halftone | 163-189 | 菜单装饰、模态装饰、技能键就绪光晕 |

调色板常量（ui_skin.gd:7-21）：INK/INK_SOFT/PAPER/CREAM/WHITE/PINK/PINK_DEEP/CYAN/CYAN_DEEP/GOLD/GOLD_DEEP/VIOLET/VIOLET_DEEP/RED/BLUE。**改视觉方向=改这 15 个常量+各模块填色引用**（部分模块还内嵌 Color.html 硬编码，如 ui_overlay.gd:184 tint 缺省 "#FF8FB1"、暗化色 Color(0.10,0.07,0.16,…)）。

## 8. 安全区 / 视口依赖

- `_update_viewport_layout`（main.gd:304-328）：viewport size_changed 触发；移动端把 DisplayServer 安全区按缩放换算成 safe_top/bottom/left/right → `CFG.set_safe`（game_config.gd:19-23）。
- UI 全部经参数接收安全区（UIMenu 收 st/sb；UIHud 收 st/sb/sl/sr；模态收 st/sb），**不直接读 DisplayServer**。重构必须沿用这条链。
- 玩家活动边界也扣安全区（main.gd:326-328）——UI 改布局不得反向影响它。

## 9. 冻结边界（UI 重构不得触碰）

game_config.gd 全部数值、collision.gd、wave_director.gd、boss.gd 状态机、weapon_system.gd 经济、upgrade_system.gd 效果逻辑、enemy.gd、crate.gd、sfx.gd、music_player.gd 播放逻辑、main.gd 世界更新函数（_update_* 系列）、拖拽驾驶手感（_start_drag/pointer 链）。
UI 可动范围：ui_skin.gd / ui_menu.gd / ui_hud.gd / ui_overlay.gd 的绘制与热区，main.gd 的 _handle_ui_action 路由（保持动作语义）、_spawn_visuals 的 UI 挂载、存档读写函数（修缺陷时）。