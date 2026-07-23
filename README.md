# PinSnip

PinSnip 是一款原生 macOS 截图、录制动图与贴图工具。

- `F1`：截图
- `F3`：框选区域并录制 GIF
- `F4`：把剪贴板内容贴在屏幕上

快捷键可以在菜单栏中修改。截图、动图和贴图均在本机处理，没有网络请求、遥测或用户账户。

## 下载

从 [Releases](https://github.com/longhaiqwe/PinSnip/releases) 下载最新版本。支持 macOS 14 及以上系统，兼容 Apple 芯片和 Intel 芯片。

首次截图或录制时，请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 PinSnip。

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
