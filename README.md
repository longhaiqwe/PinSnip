# PinSnip

PinSnip 是一款原生 macOS 截图、滚动截屏、录制动图与贴图工具。

- `F1`：截图
- 菜单栏「滚动截屏…」：生成长截图（[使用指南](docs/features/scrolling-capture.md)）
- `F3`：框选区域并录制 GIF
- `F4`：从新到旧逐张贴出最近 10 张截图；没有截图历史时贴出剪贴板内容

快捷键可以在菜单栏中修改。截图、滚动拼接、动图和贴图均在本机处理。

菜单栏支持“检查更新…”，也可以分别关闭自动检查、自动下载并安装更新。PinSnip
仅在检查或下载更新时访问 GitHub 上的更新清单与 Release 安装包；截图、滚动拼接、
动图和贴图仍完全在本机处理，不包含遥测或用户账户。

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

发布新版本及生成签名更新清单的步骤见
[发布与自动更新](docs/releasing.md)。

## 致谢

PinSnip 的灵感来源于 [Snipaste](https://www.snipaste.com/)，并向它致敬。本项目使用 Swift 与 AppKit 独立实现，不包含 Snipaste 的源代码或专有素材，与 Snipaste 官方无隶属关系。

## License

[MIT](LICENSE)
