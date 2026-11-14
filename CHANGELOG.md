# Changelog

## 1.6.0 — 2026-11-14

**art / 像素霓虹全面重制（豆包 Seedream 出图）**

- 21 张主力精灵（3 条玩家武器线 / 12 种敌机 / 6 台 Boss）改用豆包系列
  文生图模型出图，再由 `tools/pixel_neon.py` 转成游戏精灵：边缘泛洪去底 →
  裁边 → 按 0.46 外接半径方化 → 最近邻降采样到像素网格 → 量化到 20 色霓虹
  色板 → 最近邻放大到 512/384/640 画布；`_mask` 由 alpha 重建，闪白与护盾
  叠加仍对齐。
- 补给箱与僚机沿用旧美术，用同一脚本的 `--alpha` 模式重新像素化，配色统一。
- 背景换成像素霓虹 shader：168 格 UV 吸附 + 拜尔 4×4 抖动到 11 阶 +
  CRT 扫描线 + 霓虹地平线；五套星球调色板改为洋红/青/紫/橙。
- 星球与月面 shader 增加 72 格像素化与 8 阶抖动。
- UI 改为霓虹 token：洋红 `#FF2E88` / 青 `#22F0E0` 配 `#05030C` 深底，
  圆角 22/14/8 收到 7/5/3；标题由 3D Logo 改为实时霓虹文字；Boss 光环改
  程序化弧线，不再使用旧赛璐璐环贴图。
- 纹理统一最近邻采样；内置中文字体关闭抗锯齿/次像素/微调，字形边缘变硬。
- 玩法未改：`VERIFY_OK checks=180`、`SELFTEST_OK n=8`。
- Android versionName `1.6.0` / code `24`；Windows FileVersion `1.6.0.0`。

## 1.5.0 — 2026-11-12

**refactor / UI 全面重构：暗色科幻换肤 + 独立设置屏 + Android 触屏修复**

- **视觉**：UISkin Token 化暗色科幻皮肤覆盖全部界面（菜单/HUD/三选一/暂停/结算/设置）；
  每星区独立 pastel 天空保留，战斗画面不受换肤影响。
- **主菜单**：重排标题/难度/开始布局，右上角齿轮进入**独立设置屏**；设置复用
  音乐/音效/震屏三开关，切换后立即保存，含版本号与「免费游戏 · 无内购」声明。
- **HUD**：分数块与船体面板分离消除遮挡；Boss 血条展开动画、武器升级脉冲、
  WARNING 横幅收编 Token；长屏/小窗按安全区锚定四角。
- **结算**：重开/回菜单改显式按钮，移除全屏点按重开兜底（防误触丢结算数据）；
  桌面端保留 R / Enter 快速重开提示。
- **修复 A1**：最高分写档先 load 再合并写回，不再抹掉 [opt] 偏好。
- **修复 A2**：暂停中切音乐开关只记状态，恢复后正确续播。
- **修复 A3**：Android 一次点按被 mouse+touch 双分支处理导致开关"点了没反应"；
  `emulate_mouse_from_touch=false` 后单击即切换（桌面鼠标不受影响）。
- **治理**：UIOverlay 对 main 零写入（缓动/衰减归 main._process）；新增 UI 点击音
  （nova/三选一不叠音）；飘字/粒子维持硬上限不新增对象池。
- **验证**：门禁 checks=180、SELFTEST_OK n=8；桌面多比例截图复核；模拟器 E2E 全绿
  （开关切换/强杀持久化/开局/暂停/恢复），logcat 0 SCRIPT ERROR。
- Android versionName **1.5.0** / code **23**。免费游戏，无内购。


## 1.4.1 — 2026-11-10

**fix / 道具掉落与 BGM 反馈修复**

- **道具拿不到**：补给箱此前从屏幕顶端 -30 以 46px/s 下落、寿命仅 10s——
  根本到不了玩家所在的下半屏。现在改为在中上屏（28%~42% 高度）生成，
  下落 58px/s、寿命 14s、磁吸半径 120→170、吸力 520→620、拾取半径 28→32。
- **掉落频率**：间隔 19~20s → **11~13s**，首箱 16s → 8s。
- **武器/换线几乎不出现**：10 种等概率 → 加权（武器 26 / 棱镜 12 / 僚机 16 / 护盾 11 /
  修复 9 / 充能 8 / 星爆 6 / 裂隙 6 / 反射 3 / 换线 3），并保留棱镜首箱保底与
  连续 3 箱无成长类强制武器强化。换线箱现在**直接切换到下一条武器线**（只有一条时先解锁再切）。
- **音乐难听**：重写 `tools/gen_music.py`——去掉锯齿/方波主旋律和鼓点，改为
  52-64 BPM 的正弦长音 pad + 轻低音 + 稀疏钟琴 + 极轻噪声雾，峰值归一 0.55，
  并重新生成 10 段 30-37s 循环 BGM；播放音量 -12dB → **-15dB**。
- 门禁 checks=93、SELFTEST_OK n=5；真机 v1.4.1 / code 20。


## 1.4.0 — 2026-11-10

**balance / 关卡内容与节奏评审后的优化**

评审覆盖：单区长度、Boss 强度/招式/形态/种类、小兵变化、子弹类型、飞船类型、僚机类型。

- **单区长度曲线**：最短停留从固定 40s 改为 `30s + (区-1)×1.2s`（30→40.8s），
  配额 28+区×4 改为 **26+区×4**（第 1 区 30 杀 → 第 10 区 66 杀）。前段更快进 Boss，后段更耐打。
- **终局胜利**：第 10 区改为终局，击破最终 Boss 后进入「巡航完成」结算（S 评级/终焉之门），
  不再无限循环；最终 Boss 固定为「裁决者·塞拉弗」并额外 +20% 血量。
- **后段小兵变化**：第 6 区起每波混编两种机体，精英小队从每 4 波改为每 3 波。
- **Boss 弹种分化**：光束类招式（十字光牢/双生扫射/双子光矛/星网绞杀/光牢旋扫）改用 needle，
  重弹压制改 heavy，陨星暴雨改 shard，波动弹幕保持 wave——不再清一色 orb。
- 飞船 3 种（随武器线切换）与僚机 4 种经复核无需改动。
- 门禁 checks **93**；SELFTEST_OK n=5；真机 v1.4.0 / code 19。


## 1.3.4 — 2026-11-10

**ux / 产品设计 Audit 落地（Nielsen 走查 → 机会点 1）**

- 防误触：暂停页『重新出击』『返回主菜单』改为两 tap 二次确认（2.5s 窗口），避免误触丢本局进度。
- 设置入口：暂停页新增 音乐/音效/震屏 三开关，持久化到 user://save.cfg；Sfx/MusicPlayer 增加 enabled 门控。
- 走查报告：spark-output/audit/aurora-rift.md + context/audit.json（10 findings：2 major 已修 / 8 minor 待排期；4 机会点）。
- 门禁 checks=85、SELFTEST_OK n=5 保持通过。
- Android versionName 1.3.4 / code 18。


## 1.3.3 — 2026-11-10

**fix / 评审修复 + 手感层接回**

- 修俯冲敌机渲染颠倒：`enemy.gd` 朝向改为 `v.angle()−π/2`（机头朝下精灵对准速度方向）。
- 接回原版手感层：打击停顿（Freeze*）与慢镜（Slow*） now 生效——精英击破/Boss 破防/护盾破/星爆/Boss 崩解触发冻结，受创/星爆/Boss 死触发慢镜。
- 相位机制：冲刺期间擦身敌弹被消除，换分与星爆（Phase* 常量接回）。
- 过关结算：Boss 击破追加 基础+星区+无伤+星区补偿 奖励（Clear* 常量接回）。
- 补给保底：连续 PITY_THRESHOLD 箱无成长类强制掉落；长时间未换线概率掉换线箱。
- 清理死代码：main.gd 的 fire_timer / PLAYER_FIRE_LEVEL。
- 门禁 `checks=85`、headless `SELFTEST_OK n=5` 保持通过。
- Android versionName `1.3.3` / code `17`。


## 1.3.2 — 2026-11-07

**refactor / main.gd module split**

- 按 GS 评审建议拆分 `main.gd`（1614 → 1306 行）：
  - `WaveDirector`：星区配额、40 秒最短停留、队形生成、敌机工厂、Boss 触发。
  - `CollisionSystem`：玩家弹 vs 敌机/Boss、每帧受击/擦弹、击杀奖励、玩家死亡。
  - `UpgradeSystem`：卡池过滤、×N 层数、三选一抽卡与应用。
- 行为保持不变：`VERIFY_OK checks=85`、`SELFTEST_OK n=5`、桌面/Android 截图、
  Boss → 突破 → 下一星区流程复验通过。
- Android versionName `1.3.2` / code `16`；Windows FileVersion `1.3.2.0`。

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
