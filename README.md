# PinSnip for macOS

PinSnip 是一个原生 macOS 截图、动图录制与贴图工具，目标是逐阶段覆盖 Snipaste Desktop Pro 的工作流，但采用独立的 Swift/AppKit 实现。项目不包含 Snipaste 的源代码、商标、图标或其他专有素材。

## 当前可用功能

- 菜单栏常驻应用
- `F1` 全局截图快捷键（可配置）
- 当前鼠标所在显示器截图与 Retina 像素映射
- 应用窗口智能识别、悬停自动框选、单击确认与自由矩形拖选
- 自由拖选支持自由、1:1、4:3、16:9 比例，菜单栏可重复上次截图区域
- 矩形、箭头、画笔、自动递增序号标注
- 标注撤销与重做
- 截图复制或保存时自动生成带柔化背景、留白、圆角和阴影的分享图；贴图保留原图
- 从菜单栏框选屏幕区域录制 GIF；包含鼠标，最长 30 秒，停止后复制、保存并预览
- `F3` 将剪贴板图像、图片文件、文字或 HEX 颜色贴到屏幕（可配置）
- 菜单栏可录制并持久化截图、贴图快捷键
- 贴图拖动、滚轮缩放、`Control + 滚轮` 调透明度
- 贴图旋转、水平/垂直镜像、鼠标穿透、置顶开关
- 贴图复制、保存、双击隐藏、批量显示/隐藏与恢复鼠标操作

完整对标范围与进度见 [功能矩阵](docs/product/parity-matrix.md)。

## 构建

需要 macOS 14 或更高版本、Xcode 26 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
./scripts/build-release.sh
```

产物位于 `build/Release/PinSnip.app`。开发时可运行：

```bash
xcodegen generate
xcodebuild test -project PinSnip.xcodeproj -scheme PinSnip -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
open build/Release/PinSnip.app
```

## 首次使用

1. 启动 `PinSnip.app`，菜单栏会出现叠放矩形图标。
2. 按 `F1` 或从菜单选择“截图”。
3. 首次截图时，PinSnip 会提示你打开“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”。允许 PinSnip 后，退出并重新打开应用。
4. 拖出选区后选择标注工具，最后复制、保存或贴图。
5. 剪贴板中已有内容时，按 `F3` 可直接创建贴图。
6. 需要录制屏幕操作时，从菜单栏选择“录制动图…”，框选区域后点击红色录制按钮；完成后在浮动控制条点击“停止并生成 GIF”。

从菜单栏选择“快捷键设置…”可以录入其他组合；F1–F20 可单独使用，普通按键至少需要搭配 `Command`、`Option` 或 `Control`，也可再加 `Shift`。鼠标穿透后无法直接右键该贴图；从菜单栏选择“恢复鼠标操作”即可恢复所有贴图交互。

## 工程结构

```text
PinSnip/Core          可测试的几何、命令、颜色和贴图变换模型
PinSnip/Capture       ScreenCaptureKit 截图与选区覆盖层
PinSnip/Annotations   矢量标注文档和 Core Graphics 渲染
PinSnip/Clipboard     剪贴板内容识别
PinSnip/Pins          无边框置顶贴图窗口
PinSnip/Hotkeys       Carbon 全局快捷键
PinSnip/Output        复制与文件输出
PinSnipTests          XCTest 行为测试
```

## 隐私

截图、动图、文字卡片和贴图均在本机处理。当前版本没有网络请求、遥测或用户账户。
