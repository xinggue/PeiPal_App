# macOS 发布签名

GitHub Actions 的 macOS 产物必须使用 Developer ID Application 证书签名，并通过 Apple 公证。缺少凭据时构建会停止，避免将临时签名的包作为正式安装包发布。

在 `xinggue/PeiPal_App` 仓库配置以下 Actions secrets：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Developer ID Application 证书及私钥导出的 `.p12`，Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `MACOS_TEAM_ID` | 证书所属 Apple Developer Team ID |
| `MACOS_NOTARY_KEY_BASE64` | 有公证权限的 App Store Connect 团队 API 密钥 `.p8`，Base64 编码 |
| `MACOS_NOTARY_KEY_ID` | API Key ID |
| `MACOS_NOTARY_ISSUER_ID` | API Issuer ID |

Apple Development 证书无法替代 Developer ID Application 证书。证书需要付费 Apple Developer 账户，由「钥匙串访问」导出证书及其私钥；只有证书文件而没有私钥无法签名。凭据仅存放在 Actions secrets 中。

`.github/scripts/package_macos.sh` 会在临时钥匙串中导入证书，逐层签名应用并启用 Hardened Runtime，然后分别公证应用和 DMG、附加公证票据，最后执行 Gatekeeper 校验。临时钥匙串和凭据文件在退出时删除。DMG 内包含 Applications 快捷方式，用户拖入后即可正常打开。

应用继续使用原有登录钥匙串保存 API 密钥，保持现有配置可读。发布版本使用相同 Team ID、Bundle ID 和正式签名身份，使钥匙串能在升级后识别应用。临时签名的旧版本升级到正式签名时，已有钥匙串项目仍可能需要一次授权；修改签名无法追溯更改旧项目的访问控制。不要通过清空钥匙串或将密钥转存明文来消除弹窗。

本地验证打包流程需要先执行 `flutter build macos --release`，设置以上环境变量，再运行 `bash .github/scripts/package_macos.sh`。开发构建本身仍使用项目现有的本地签名设置。
