# Audit — 裂隙巡航 Aurora Rift (Godot)

- **生成时间**：2026-11-10T21:44:03.487062+08:00
- **走查对象**：代码仓库 @ v1.3.3 + 六屏截图（menu/game/boss/pause/upgrade/results）
- **走查模式**：自动（代码 + 截图）
- **框架**：Nielsen 10 + responsive + performance

## 总览

| 严重度 | 数量 |
| --- | --- |
| 🔴 Blocker | 0 |
| 🟠 Major | 2 |
| 🟡 Minor | 8 |

## 改版机会点（按优先级）

### 🥇 high：防误触与玩家可控性（确认+设置）
- 关联 findings：audit-1, audit-2
- 理由：两个 major 集中在 user-control/error-prevention/flexibility，直接关系丢进度与无障碍；已在 v1.3.4 落地。

### 🥈 medium：新手引导与机制释义
- 关联 findings：audit-3, audit-4, audit-6
- 理由：三个 minor 同属 help-docs/recognition/real-world-match，聚类为 onboarding 主题，降低首局流失。

### 🥉 medium：文案与术语一致性规范
- 关联 findings：audit-5, audit-6
- 理由：动词不统一+货币术语无解释，建立文案表一次解决。

### 4️⃣ low：高屏留白与横屏提示打磨
- 关联 findings：audit-7, audit-9
- 理由：responsive/aesthetic 细节包，不影响核心 loop。

## 完整 Findings

### 维度：error-prevention

- **[major]** 暂停页『重新出击』『返回主菜单』一点即执行，误触会直接丢掉本局进度，无二次确认。
  - 位置：scripts/ui_overlay.gd _draw_pause / main.gd _handle_ui_action（v1.3.3 直接 _start_run/_to_menu）
  - 建议：改为两 tap 确认：首按变『确认重新出击？』并 2.5s 窗口，再按才执行。已在 v1.3.4 落地。
  - 成本：quick-win

### 维度：flexibility

- **[major]** 无设置入口：音乐/音效/震屏无法关闭，对噪音敏感/晕动玩家不友好，也不持久化。
  - 位置：暂停页仅 resume/restart/menu 三键（v1.3.3）
  - 建议：暂停页加 音乐/音效/震屏 三个开关并写入 user://save.cfg；已在 v1.3.4 落地。
  - 成本：medium

### 维度：help-docs

- **[minor]** 无首局引导；擦弹/裂隙/失谐等核心机制全靠玩家自悟，菜单只有一张操作卡。
  - 位置：ui_menu.gd 帮助卡仅讲按键，不讲机制
  - 建议：首局进入给 3 步轻量提示（移动/擦弹换星爆/星爆清屏），并在升级卡旁解释裂隙。
  - 成本：medium

### 维度：recognition

- **[minor]** Boss 预告色族（玫红=光束/紫=位移/金=投送）没有图例教学，新玩家无法把颜色与应对方式关联。
  - 位置：boss.gd _tell / ui_overlay 警告横幅仅 WARNING
  - 建议：首次 Boss 战前用一行图例说明三种预告色含义。
  - 成本：quick-win

### 维度：consistency

- **[minor]** 重开动词不统一：暂停用『重新出击』、结算用『再来一次』，同一动作两种叫法。
  - 位置：ui_overlay.gd _draw_pause / _draw_results
  - 建议：统一为『重新出击』或建立文案表。
  - 成本：quick-win

### 维度：real-world-match

- **[minor]** 『裂隙』作为升级货币首次出现时无解释，直到突破卡才隐含说明。
  - 位置：ui_hud.gd 裂隙计数 / upgrade 卡
  - 建议：在 HUD 裂隙计数旁加 inline 提示或者首局浮字解释。
  - 成本：quick-win

### 维度：aesthetic

- **[minor]** 高屏（20:9）菜单开始按钮与帮助卡之间留白偏大，视觉重心偏上。
  - 位置：ui_menu.gd 布局（android_111_tall_menu 截图）
  - 建议：按视口高度弹性分配间距，帮助卡贴底。
  - 成本：medium

### 维度：user-control

- **[minor]** 星区突破三选一不可跳过/放弃，强制选择（类型惯例，但无『暂不强化』出口）。
  - 位置：ui_overlay.gd _draw_upgrade
  - 建议：保留强制（节奏需要）但增加说明『每区必选一项』降低困惑。
  - 成本：quick-win

### 维度：responsive

- **[minor]** 仅竖屏；平板横屏会letterbox，未做横屏布局或提示。
  - 位置：project.godot orientation=1
  - 建议：竖屏锁定可接受；横屏时显示『请旋转设备』提示。
  - 成本：medium

### 维度：visibility

- **[minor]** 慢镜/打击停顿生效时无视觉提示，玩家不感知时间被拖慢，可能误判卡顿。
  - 位置：main.gd hitstop/slowmo（v1.3.3 接回）
  - 建议：慢镜期间加轻微径向模糊/暗角或『子弹时间』浮字。
  - 成本：medium

## 下一步建议

- 机会点 1（防误触+设置）已在 **v1.3.4** 落地；其余进入 Brief/Stories 排期。
- Blocker 为 0；两个 major 已修，建议下轮做 onboarding（机会点 2）。
