# PinSnip 项目约定

## 按钮图标与文字必须整体居中

用户明确要求（2026-10-17）：以后新增或修改带图标和文字的操作按钮，必须把图标与文字作为一个整体居中，不能图标贴左边、文字单独居中。

- AppKit 的图文按钮统一设置 `imagePosition = .imageLeading`、`imageHugsTitle = true`、`alignment = .center`，不要仅设置 `imageLeading`。
- SwiftUI 的图文按钮将图标与文字放在同一 `Label` 或 `HStack` 内，让整个组合居中；不要在图标和文字之间放伸缩空白。
- 纯图标按钮居中显示图标，纯文字按钮居中显示文字。菜单项沿用系统菜单对齐方式。
- 检查实际渲染中的左右留白、图文间距和截断，覆盖浅色、深色及禁用状态；不能只从代码判断已经居中。

## 本机升级必须保持正式签名身份

用户明确要求（2026-10-16）：以后替换已安装的新版，必须使用原来的正式签名，避免因签名身份变化让用户重新设置屏幕录制、辅助功能等权限。

- 安装到 `/Applications/PinSnip.app` 或替换其他位置的已安装版本时，必须使用 Developer ID 签名的 Release 构建。
- 当前正式签名：`Developer ID Application: hai long (5RFJK73RSL)`；Team ID：`5RFJK73RSL`；Bundle ID：`com.longhai.pinsnip`。保持这些身份信息稳定。
- 禁止用 Debug、未签名、ad-hoc（`codesign --sign -`）或 Apple Development 签名版本覆盖用户已安装的正式版本。临时开发构建只可留在独立构建目录。
- `scripts/build-release.sh` 未传签名环境变量时仍可生成未签名产物，不能把脚本成功退出当成可安装的依据。用于替换的构建必须显式传入 `PINSNIP_CODE_SIGN_IDENTITY` 和 `PINSNIP_DEVELOPMENT_TEAM`，见 [发布与本机替换流程](docs/releasing.md)。
- 替换前读取旧应用的 designated requirement，验证新应用及嵌套组件的完整签名，并确认新应用满足旧应用的身份规则。`codesign --verify --deep --strict` 和主应用的 `codesign --verify --strict -R "=<旧身份规则>"` 分开执行；不要把主应用的身份规则套到标识符不同的嵌套组件上。
- 如果正式证书不可用或身份验证失败，保留已安装版本并说明阻塞原因，不能降级为临时签名继续覆盖。
- 校验通过后再退出旧版、备份、替换、启动，并确认运行的是安装目录中的新版。
- 本机替换统一运行 `./scripts/install-release.sh`，禁止绕过脚本直接复制或手工重签后覆盖。脚本强制验证正式签名及新旧身份的双向兼容性，失败立即停止；可先运行 `./scripts/install-release.sh --check` 做只读预检。
- 不运行 `tccutil reset`，不删除或修改 TCC 数据库，不把重新授权作为日常升级步骤。若相同签名下仍出现权限提示，应先调查原因，不能宣称签名验证通过就等于权限已恢复。

本约定同时适用于人工操作和代理执行；用户要求“替换并启动新版”时也必须遵守。
