# PinSnip 发布与自动更新

PinSnip 使用 Sparkle 2 获取、验证并安装更新。更新清单托管在仓库根目录的
`appcast.xml`，安装包仍由 GitHub Releases 提供。

首次发布带自动更新能力的版本时，必须先让 `appcast.xml` 在 `SUFeedURL` 指向的
地址可访问。引导清单只发布当前版本及其版本页面，不包含旧安装包的 `enclosure`；
这样客户端会得到“已是最新版本”，也不会信任未使用当前 EdDSA 密钥签名的旧包。

## 发布顺序

1. 同时递增 `VERSION`、`MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
2. 运行 `./scripts/build-release.sh`，完成测试、Universal Release 构建和
   Developer ID 签名检查。
3. 对 App 完成 Apple 公证并 stapling，再从该 App 生成
   `PinSnip-v<版本>-macOS-universal.zip`。
4. 如需更新说明，在 ZIP 同目录放置
   `PinSnip-v<版本>-release-notes.md`。
5. 运行 `./scripts/generate-appcast.sh`。脚本从本机钥匙串临时导出 Sparkle
   EdDSA 私钥到权限为 `0600` 的临时目录，签名完成后立即清理，再更新仓库根目录
   的 `appcast.xml`。
6. 先把 ZIP 上传并发布到对应的 GitHub Release，确认下载 URL 可访问。
7. 最后提交并推送 `appcast.xml`。不要在安装包可下载前发布清单，避免客户端
   读到暂时不可用的更新。

## 安全边界

- App 只内置 `SUPublicEDKey`；EdDSA 私钥保存在发布 Mac 的钥匙串中，不能提交
  到仓库。
- 自动更新包仍须使用稳定的 Developer ID 身份签名、通过 Apple 公证并 stapling。
- `CFBundleVersion` 必须严格递增；Sparkle 用它判断版本先后。
- App 内的“自动下载并安装更新”可以关闭；“自动检查更新”关闭时，该选项会禁用。
