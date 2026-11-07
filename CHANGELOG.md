# Changelog

## 1.3.1 — 2026-11-07

**perf / GS review pass**

- 用 Claude-Code-Game-Studios（GS）套件完成脚手架安装、引擎配置与全项目
  代码评审。
- 热路径优化：敌机 base/accent 颜色与玩家武器色改为缓存，移除每帧最多 84 次
  `Color.html()` 字符串解析。
- 敌机开火色在 `setup()` 时缓存，不再每次射击重新解析。
- 特效层加上限：420 个粒子 / 40 条浮字，超出丢弃最旧项，避免连续星爆/爆炸
  让单帧绘制量无上限增长。
- 数值 gate `checks=85`；headless selftest `n=5` 保持通过。
- Android versionName `1.3.1` / code `15`；Windows FileVersion `1.3.1.0`。

## 1.3.0 — 2026-11-07

**feat / boss roster, per-zone music, longer zones**

- 新增 3 台 Boss（共 6 台）：塔罗斯 / 铁壁（宽体无畏舰）、许德拉 / 噬星者
  （纵向蛇形）、塞拉弗 / 裁决者（四翼 X 形）；沿用 Blender 赛璐璐管线，
  剪影与现有 3 台完全不同，星区按 `(zone-1)%6` 轮换。
- 每台新 Boss 拥有独立的三阶段招式序列与弹幕色。
- 新增每星区 BGM：`tools/gen_music.py` 合成 10 段 29–53 秒循环 OGG
  （约 3.4 MB），`MusicPlayer` 切区淡入，暂停菜单同步暂停音乐。
- 星区时长：击杀配额 `12+4z` → `28+4z`，并增加 40 秒最短停留；
  单区从约 20 秒拉长到约 45 秒。
- 换线体验：机体贴图本来就会随武器线切换，问题在于第二条线解锁太晚。
  首个补给箱现在必掉棱镜；未解锁时换线键显示“锁定”，点按给出提示。
- `星区` 进度条同时反映击杀与最短时长（取较小值）。
- 数值 gate `checks=85`；headless selftest `n=5`（新增 BGM 与节奏断言）。
- Android versionName `1.3.0` / code `14`；Windows FileVersion `1.3.0.0`。

## 1.2.1 — 2026-11-07

**fix / gameplay integrity + two-round polish**

- 修复核心判定：敌弹命中、机体接触与擦弹原本写在 `_kill_enemy()` 内，只有敌机
  死亡帧才结算，导致玩家对弹幕几乎无敌、擦弹成批误计。现拆为
  `_resolve_player_hazards()` 每帧结算，与 web 版 `collide()` 对齐。
- 最后一格船体被击穿时立即关闭“星区突破”草稿，避免结算被卡片遮挡。
- 三选一卡池过滤已满级项（船体 4 / 护盾 3 / 移速 1.30），卡片显示当前 `×N` 层数。
- `星区` chip 增加击杀进度条；结算新增 `擦弹 / 裂隙`。
- 新增 headless 行为自检 `-selftest`（3 项断言）；数值 gate `checks=81`。
- 性能：碎片绘制复用顶点并减少光晕层；子弹推进去掉每帧数组分配。
- 打包优化：导出排除 `build/*`、`.trae/*`，APK 45 MB → 31 MB，
  Windows 128 MB → 113 MB。
- Android versionName `1.2.1` / code `13`；Windows FileVersion `1.2.1.0`。

## 1.2.0 — 2026-11-07

**feat / gameplay innovation**

- 对标 Touhou / DoDonPachi / 雷电 / Sky Force / Archero / Vampire Survivors /
  Hades，补上两个玩法缺口：擦弹没有机械回报，星区之间没有 build 选择。
- 新增**裂隙碎片**：每次擦弹在子弹位置掉落磁吸碎片，拾取后加得分、延长连击、
  充能星爆并累计 HUD `裂隙` 计数；擦弹从隐藏统计变成风险回报循环。
- 新增**星区突破**：每次击破 Boss 后冻结战斗，从 10 项强化中随机三选一：
  伤害、僚机射速、最大船体、护盾、星爆充能、超频时长、移速、补给率、
  Boss 伤害、裂隙共振。强化可跨 10 个星区叠加，改变整局 build。
- 新增模态卡片 UI（三选一，支持触屏点按与键盘 1/2/3），不增加常驻触屏按钮。
- 新 HUD：`裂隙` 计数 chip；船体图标随最大船体升级扩展；Boss 死亡清屏后进入
  突破选择，避免残留弹幕偷袭。
- Android：versionName `1.2.0` / versionCode `12`；Windows FileVersion `1.2.0.0`；
  数值 gate `VERIFY_OK checks=80`。
- 字体子集重新生成（280 KB，971 mapped glyphs）。

## 1.1.1 — 2026-11-07

**polish / two visual optimization rounds**

- 新增赛璐璐星球/月面 shader（三色阶、纬向云带、墨色描边、行星环），替换原来
  的平面半圆背景球。
- HUD 中文化：得分 / 最高 / 擦弹 / 星区；结算页得分、评级、新纪录同步中文化。
- 移动端菜单改为触屏提示卡（拖动屏幕 / 右下角技能 / 右上角暂停 / 换线键），
  桌面端保留键盘提示。
- 右下角技能键改为三键（星爆 / 冲刺 / 换线）；**移除精准慢速瞄准按键与
  Shift 精准模式**，相关数值常量、武器压缩参数与 gate 检查一并删除。
- 动效：菜单↔战斗淡入淡出、暂停/结算卡片滑入、得分滚动、Boss 血条平滑、
  开始按钮扫光与箭头浮动；连击 chip 增加计时条。
- Android：versionName `1.1.1` / versionCode `11`；Windows FileVersion `1.1.1.0`；
  数值 gate `VERIFY_OK checks=75`。
- 字体子集重新生成（274 KB，957 mapped glyphs），覆盖新文案。
- 验证：桌面 540x960 / 720x960 / 540x1061，Android 硬件 GPU 模拟器
  1080x1920 / 1080x2400，无黑边、三键触控正常。

## 1.1.0 — 2026-11-07

**feat / visual reset**

### 视觉与美术
- 全部玩家机、12 种敌机、3 个 Boss、4 种僚机、9 种补给箱在 Blender 中重渲为日系赛璐璐风格：
  双色阶硬阴影、深梅色双层描边、斜向高光、2 倍超采样。
- 新增主菜单 3/4 Hero 机体（`assets/keyart/hero.png`）与 3D 标题 Logo
  （`assets/keyart/logo.png`）。
- 新增应用图标：3/4 赛璐璐机体 + 粉彩星云，含 Android adaptive 前景/背景。
- 字体子集重新生成（938 glyphs），覆盖全部新 UI 文案。

### 界面
- 重做主菜单 / HUD / 暂停 / 结算 / 触屏控件：奶油贴纸面板、糖果色胶囊、
  深梅描边、动态 Boss 血条、连击数字、星区横幅与 WARNING 横幅。
- 新增暂停与结算卡片，支持继续 / 重新出击 / 返回主菜单 / 再来一次。

### 自适应分辨率
- `stretch/aspect="expand"`，运行时 `CFG.VIEW` 跟随真实屏幕；
  刘海/导航栏安全区参与 HUD 与底栏布局。
- 已在 540x960、540x1061、720x960 以及 Android 1080x1920 / 1080x2400
  上验证无黑边、无重叠。

### 背景与特效
- 新增 FBM 星云 shader、三层视差星、赛璐璐星球/月面；战斗模式底部平滑压暗。
- 新增爆炸碎片、冲击环、火花、拾取浮字、震屏、引擎火焰、冲刺残影，
  并按弹种重绘敌我弹体。

### 构建
- Android：versionName `1.1.0` / versionCode `10`，target SDK 36，
  签名 APK `SpaceFighter-Godot-v1.1.0.apk`（v2/v3 已验签）。
- Windows：`build/windows/SpaceFighter.exe`，FileVersion `1.1.0.0`。
- 数值 gate：`VERIFY_OK checks=76`。
- 注意：纯软件渲染的 Android 模拟器（SwiftShader）受 GLES3 uniform
  上限限制可能无法启动渲染；请使用硬件 GPU 模拟器或真机。
