# Changelog

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
