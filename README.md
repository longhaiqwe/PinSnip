# PinSnip

PinSnip 是一款原生 macOS 截图、滚动截屏、录制动图与贴图工具。

- `F1`：截图
- 菜单栏「滚动截屏…」：框选页面视口并生成长截图
- `F3`：框选区域并录制 GIF
- `F4`：把剪贴板内容贴在屏幕上

快捷键可以在菜单栏中修改。截图、滚动拼接、动图和贴图均在本机处理，没有网络请求、遥测或用户账户。

## 滚动截屏

滚动截屏适合网页、文档、聊天记录等纵向内容：

1. 从菜单栏选择「滚动截屏…」，或按 `F1` 框选后点击工具栏中的叠层矩形按钮。
2. 框选真正发生滚动的内容区域，尽量不要包含浏览器地址栏和窗口边框。
3. 有「辅助功能」权限时，PinSnip 会自动滚动并在页面到底后结束；没有权限时会进入手动模式，请在蓝框内滚动内容。
4. 选择「完成并复制」「保存…」或「贴图」输出长图。

PinSnip 会尝试识别并忽略固定页头、固定侧栏和空白边距，只拼接新出现的页面内容。长图按原始 PNG 输出，不添加普通截图使用的分享背景；达到 2,400 万像素安全上限时会自动结束。

完整说明、权限配置、工作原理和排障方法见[《滚动截屏使用指南》](docs/features/scrolling-capture.md)。

## 下载

从 [Releases](https://github.com/longhaiqwe/PinSnip/releases) 下载最新版本。支持 macOS 14 及以上系统，兼容 Apple 芯片和 Intel 芯片。

首次使用时可能需要以下权限：

- **屏幕与系统音频录制**：截图、滚动截屏和 GIF 录制所必需。
- **辅助功能**：仅用于自动滚动；未授权时滚动截屏仍可使用，但会切换为手动模式。

## 构建

需要 Xcode 26 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
./scripts/build-release.sh
```

脚本会运行测试，并在 `build/Release` 中生成同时支持 `arm64` 与 `x86_64` 的 `PinSnip.app`。

## 致谢

PinSnip 的灵感来源于 [Snipaste](https://www.snipaste.com/)，并向它致敬。本项目使用 Swift 与 AppKit 独立实现，不包含 Snipaste 的源代码或专有素材，与 Snipaste 官方无隶属关系。

## License

[MIT](LICENSE)
