# Phase 0 报告 4/6：现有玩法流程（existing_gameplay_flow）

> 基线：`3371cfc`（v1.4.3）。本文件描述「UI 必须如实呈现」的既有流程；重构不得改变其中任何机制与数值（文档红线 + 180 项门禁）。

## 1. 顶层状态机

状态由 main.gd 的 4 个布尔旗标决定（无枚举、无场景切换）：

```
in_menu=true ──start──▶ 战斗中 (全 false)
战斗中 ──P/Esc/pause键──▶ paused=true ──resume──▶ 战斗中
战斗中 ──Boss击破+4.4s──▶ upgrade_pending=true ──选卡──▶ 战斗中(zone+1)
战斗中 ──船体归零──▶ game_over=true (won=false)
zone10 Boss击破 ──▶ game_over=true (won=true)
paused ──二次确认menu──▶ in_menu=true
over ──retry──▶ 战斗中（重开） / ──menu──▶ in_menu=true
```

| 转移 | 函数 | 行号 |
|---|---|---|
| 开始/重开 | _start_run → _reset_game | main.gd:1687-1689, 1720-1776 |
| 回菜单 | _to_menu（存档+清场+重置显示值） | main.gd:1691-1717 |
| 开三选一 | _open_upgrade_draft → UpgradeSystem.open_draft | main.gd:829-830；upgrade_system.gd:81-85 |
| 选卡 | _choose_upgrade → UpgradeSystem.choose（应用+zone+1+清残敌+换 BGM） | main.gd:833-834；upgrade_system.gd:88-133 |
| 暂停/继续 | _handle_ui_action "pause"/"resume" + 键盘 | main.gd:1630-1633, 1644-1648, 1538-1543, 1551-1554 |

状态优先级（UI 与输入一致）：upgrade > menu > over > paused > game（ui_overlay.gd:69-79, 118-146）。
暂停/结算/三选一期间世界冻结，但 `_process` 仍走真实时间处理 confirm 倒计时与 UI 动画（main.gd:614-630）。
手感层 hitstop/slowmo 只冻结世界 dt，不影响 UI（main.gd:636-645）。

## 2. 单局生命周期（星区循环）

1. **开局**：_reset_game —— 3 船体（START_LIVES=3，game_config.gd:171）、1 护盾（START_SHIELDS=1，:172）、脉冲炮 LV2（START_PULSE_LEVEL=2，:174）、nova=0、zone=1、补给首箱 20s（SUPPLY_INTERVAL=20，:482）。
2. **清剿配额**：每星区击杀配额 `ZONE_QUOTA_BASE 26 + ZONE_QUOTA_STEP 4 ×(zone-1)`（game_config.gd:305-306；wave_director.gd 执行）。
3. **Boss 预警**：配额达成 → boss_warn=3.0s（BOSS_WARN_SECONDS，game_config.gd:433）+ 清场 4.4s（SECTOR_CLEAR_SECONDS，:434）→ WARNING 横幅（ui_overlay.gd:57-59, 341-347）。
4. **Boss 入场**：从 y=-81 以 118.8px/s 入场（game_config.gd:436-437）；3 台 Boss 轮换（boss.gd，22 招状态机），HUD 显示名条+血条+招式预告（ui_hud.gd:65-95）。
5. **击破结算**：Boss 死亡 → clear_hold=4.4s 缓冲（打捞箱落地/残弹飞完，main.gd:658-662）→ 自动开三选一。
6. **突破选卡**：3 张（UPGRADE_CARD_COUNT=3，game_config.gd:243），从 10 项池过滤已满级项（upgrade_system.gd:30-38, 65-78）；选中立即生效并 zone+1（上限 10，upgrade_system.gd:119）。
7. **终局**：zone10 Boss 击破 → won=true 结算；船体归零 → won=false 结算。评级 S≥120000 / A≥60000 / B≥22000 / C（game_config.gd:463-465；main.gd:2119-2126）。

## 3. 局内经济（UI 呈现对象，全部只读）

| 系统 | 关键数值 | 证据 |
|---|---|---|
| 连击 | 窗口 2.8s，每 5 连 +1 倍率，封顶 ×8 | game_config.gd:375-377；main.gd:837-840 |
| 擦弹 graze | 擦弹计数 + nova 充能 0.9/次 | game_config.gd:211 |
| 星爆 nova | 满 100 释放；击杀 2.5/精英 7/受创 25 等充能；清弹计分 10/发 | game_config.gd:208-230 |
| 武器蓄能 | 每枪扣充能、命中回充；失谐（detuned）伤害 ×0.55；换线共鸣 ×N 增伤 | weapon_system.gd；game_config.gd:279-285 |
| 冲刺 dash | CD 1.7s，冲刺中无敌 | game_config.gd:190；main.gd:843-848 |
| 裂隙 rift | 裂隙碎片充能/得分（rift 强化影响） | upgrade_system.gd:114-116 |
| 补给箱 | 首箱 20s 后每 19s，9 种掉落，直落 75.6px/s | game_config.gd:480-482；crate.gd |
| 超频 overdrive | 星爆后限时增伤窗口 | main.gd（overdrive 字段）；ui_hud.gd:139-141 |

## 4. 突破强化池（10 项，UI 卡面数据源）

| id | 名称 | 效果 | 上限/过滤 |
|---|---|---|---|
| damage | 火力校准 | 全武器伤害 +12%/层 | 无 |
| drone | 僚机扩编 | 僚机射速 +25%/层 | 无 |
| hull | 船体强化 | 最大船体 +1 并修复 1 | max_hull<4（UPGRADE_MAX_HULL） |
| shield | 护盾矩阵 | 立即 +1 护盾 | shields<3（MAX_SHIELDS） |
| nova | 星爆核心 | 星爆充能 +25%/层 | 无 |
| overdrive | 超频延长 | 超频 +1.5s/层 | 无 |
| speed | 流星推进 | 移速 +8%/层 | speed<1.30 |
| crate | 战利品雷达 | 补给箱 +25%/层 | 无 |
| break | 破防弹头 | Boss 伤害 +25%/层 | 无 |
| rift | 裂隙共振 | 裂隙充能 +50%、得分 +30%/层 | 无 |

证据：game_config.gd:255-276（池）；upgrade_system.gd:88-116（应用）。卡面含 ×N 层数（stacks，upgrade_system.gd:42-62）。
**这是单局临时强化，局末清零（_reset_upgrades），不是永久成长**——文档若假设「升级养成」需按此裁剪。

## 5. 武器三线（换线 UI 的数据源）

pulse 脉冲 / prism 棱镜 / swarm 蜂群（CFG.WEAPON_LINES；weapon_system.gd）。
初始仅 pulse LV2；拾取棱镜补给解锁换线（main.gd:1641-1643 提示文案）；蓄能满 100 换线触发共鸣；HUD 武器板+换线键呈现（ui_hud.gd:111-163）。

## 6. 三档难度（菜单胶囊数据源）

| key | 名 | 特征 |
|---|---|---|
| cruise | 巡航 | 敌率 ×1.22、弹速 ×0.9、Boss 血 ×0.9、得分 ×0.8 |
| standard | 标准 | 全 ×1.0 |
| abyss | 深渊 | 敌率 ×0.8、弹速 ×1.1、Boss 血 ×1.18、得分 ×1.35 |

证据：game_config.gd:60-73。局内按 1/2/3 也可切（main.gd:1555-1560）。

## 7. 设置与存档流

- 3 开关：音乐/音效/震屏（opt_music/sfx/shake），暂停页切换（ui_overlay.gd:258-269）→ _apply_opts + _save_opts（main.gd:1664-1676）。
- 最高分：结算/回菜单时 _save_best（main.gd:390-396，有覆写缺陷见报告 5）。
- 存档仅 user://save.cfg，无账号/云存档。

## 8. 输入总览

见报告 3 §4-5（键盘全表 + 触屏热区优先于拖拽 + 自动开火无开火键）。

## 9. 调试/截图入口（验收用，release 包无此桥）

`-selftest`（8 项行为自检）、`-boss`（直入 Boss 战）、`-play`（直入开局）、`-shot <mode>`（12 种陈列/自动截图模式，main.gd:217-300, 582-613）。
Android release 无调试参数桥（OS.get_cmdline_user_args 在打包环境为空），真机验收走正常流程 + adb screencap。