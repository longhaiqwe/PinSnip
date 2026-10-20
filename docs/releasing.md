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
   的 `appcast.xml`。更新说明会直接嵌入清单，并将完整说明链接指向对应的
   GitHub Release 页面，避免依赖仓库中不存在的构建期 Markdown 文件。
6. 先把 ZIP 上传并发布到对应的 GitHub Release，确认下载 URL 可访问。
7. 最后提交并推送 `appcast.xml`。不要在安装包可下载前发布清单，避免客户端
   读到暂时不可用的更新。

## 本机替换：保持原有权限对应的签名身份

用户要求：以后替换已安装版本，必须沿用原来的正式签名，避免因更换签名身份而重新授权。
此要求也适用于未公开发布的本机功能更新，详见项目根目录 [AGENTS.md](../AGENTS.md)。

用于替换安装的构建命令：

```bash
PINSNIP_CODE_SIGN_IDENTITY='Developer ID Application: hai long (5RFJK73RSL)' \
PINSNIP_DEVELOPMENT_TEAM='5RFJK73RSL' \
./scripts/build-release.sh
```

注意：脚本不传上述变量时允许生成未签名构建，这种产物仅用于开发，禁止覆盖已安装的正式版本。
保持 Bundle ID `com.longhai.pinsnip`、Team ID `5RFJK73RSL` 和 Developer ID 签名身份不变；
不得用 ad-hoc、Apple Development 或 Debug 构建代替。

构建完成后，统一使用安装脚本（需要 Python 3.9 或更高版本）：

```bash
./scripts/install-release.sh --check  # 只读检查，不退出或修改已安装应用
./scripts/install-release.sh          # 校验、备份、替换并启动
```

默认来源为 `build/Release/PinSnip.app`，目标为 `/Applications/PinSnip.app`；
可以通过 `--app <来源.app>` 和 `--destination <已安装.app>` 指定路径。
脚本专用于替换已有正式版本，不接受缺失的旧版，不提供跳过签名检查的选项。

脚本强制检查完整签名、Developer ID、Team ID、Bundle ID、时间戳、Hardened Runtime、
主程序及嵌套程序的调试权限，并验证新版满足旧版身份规则、旧版也满足新版身份规则。
只有来源和目标均通过检查，才会准备安装；暂存副本会再次校验，然后才退出旧版并替换。
替换后验证失败会恢复旧版。旧版备份保存在目标目录下的 `.PinSnip-upgrade-*/Previous.app`，
脚本会输出准确路径。安装前校验失败不会退出旧版或覆盖安装目录。

维护脚本时需保持以下核验逻辑（不要绕过脚本手动覆盖）：

1. 用 `codesign -d -r- /Applications/PinSnip.app` 读取旧版的 designated requirement，
   保存 `designated =>` 后的完整规则。
2. 用 `codesign --verify --deep --strict build/Release/PinSnip.app` 核验新版及全部嵌套组件。
3. 用 `codesign --verify --strict -R "=<旧版完整规则>" build/Release/PinSnip.app`
   验证主应用满足旧版身份规则。`=` 表示传入规则文本，不能省略；此步骤不要加 `--deep`。
4. 检查签名仍为正式 Developer ID、Team ID 一致，且不包含调试用的 `get-task-allow` 权限。
5. 以上验证全部通过后，再退出旧版、备份、替换到原安装路径并启动；确认运行路径及安装后签名。

安装保护测试：`python3 -B scripts/tests/install-release-tests.py`。

证书不可用或验证失败时停止替换，保留旧版，禁止改用临时签名。不要重置 TCC 或删除权限记录。
签名兼容性验证不等于实际权限验证；如果系统仍提示授权，先排查原因。

## 安全边界

- App 只内置 `SUPublicEDKey`；EdDSA 私钥保存在发布 Mac 的钥匙串中，不能提交
  到仓库。
- 自动更新包仍须使用稳定的 Developer ID 身份签名、通过 Apple 公证并 stapling。
- `CFBundleVersion` 必须严格递增；Sparkle 用它判断版本先后。
- App 内的“自动下载并安装更新”可以关闭；“自动检查更新”关闭时，该选项会禁用。
