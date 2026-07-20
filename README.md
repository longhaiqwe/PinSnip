# PinSnip for macOS

PinSnip 是一个原生 macOS 截图与贴图工具，目标是逐阶段覆盖 Snipaste Desktop Pro 的工作流，但采用独立的 Swift/AppKit 实现。项目不包含 Snipaste 的源代码、商标、图标或其他专有素材。

## 当前可用功能

- 菜单栏常驻应用
- `⌃⇧1` 全局截图快捷键
- 当前鼠标所在显示器截图与 Retina 像素映射
- 自由矩形拖选、尺寸提示、取消
- 矩形、箭头、画笔标注
- 标注撤销与重做
- 截图复制为 PNG/TIFF、保存为 PNG、直接贴到屏幕
- `⌃⇧2` 将剪贴板图像、图片文件、文字或 HEX 颜色贴到屏幕
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
2. 按 `⌃⇧1` 或从菜单选择“截图”。
3. macOS 首次会请求“屏幕与系统音频录制”权限。授权后如果仍无法截图，退出并重新打开 PinSnip。
4. 拖出选区后选择标注工具，最后复制、保存或贴图。
5. 剪贴板中已有内容时，按 `⌃⇧2` 可直接创建贴图。

鼠标穿透后无法直接右键该贴图；从菜单栏选择“恢复鼠标操作”即可恢复所有贴图交互。

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

截图、文字卡片和贴图均在本机处理。当前版本没有网络请求、遥测或用户账户。

