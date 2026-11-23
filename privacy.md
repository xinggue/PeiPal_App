# 隐私政策 / Privacy Policy — 小培同学 (PeiPal)

**更新日期 / Last Updated:** 2026-11-23

感谢使用**小培同学（PeiPal）**。我们非常重视您的隐私与数据安全。本隐私政策说明本应用如何处理、存储与保护您的信息。

Thank you for using **PeiPal (小培同学)**. This Privacy Policy explains how the app handles, stores, and protects your information.

---

## 1. 本地优先存储 / Local-First Data Storage

- **会话与文书数据：** 您在应用内输入的文字、语音备忘、文档图片、导入文件、自定义文书模板、词库以及生成的结构化记录，均**仅保存在您的设备本地**。开发者不运营任何用于存储用户业务内容、影像或病历/文书资料的云端账号服务器。
- **密钥安全存储：** 您自行填写的第三方接口密钥（API Key）仅加密保存在设备本地安全存储区（如 iOS Keychain）中，不会上传至开发者。
- **备份与导出：** 应用提供本地加密导出与备份恢复功能，相关备份文件完全由您自行保管与支配。

* **Session & Document Data:** Text notes, voice memos, document photos, imported files, custom templates, catalogs, and structured records created in PeiPal are **stored locally on your device**. The developer does not operate servers that store your personal documents, recordings, or images.
* **API Keys:** Any third-party API keys you optionally enter are stored locally using system secure storage (e.g., iOS Keychain) and are never sent to the developer.
* **Backup & Export:** Encrypted backup export and restore files remain strictly under your control.

---

## 2. 系统权限用途 / Device Permissions

本应用仅在您触发对应功能时请求以下系统权限：

| 权限 / Permission | 用途 / Purpose |
|---|---|
| **相机 / Camera** | 拍摄单据、化验单或文书照片以便本地整理与文字识别 |
| **相册 / Photo Library** | 从系统相册选取照片或将导出的二维码/图片保存到相册 |
| **麦克风 / Microphone** | 录制语音备忘以便会话归档、回放与语音转文字 |
| **语音识别 / Speech Recognition (iOS)** | 调用 iOS 系统 Speech 框架将已录制的语音转写为文字 |
| **蓝牙 / Bluetooth** | 连接配套蓝牙模拟键盘（BLE HID）硬件以录入整理后的文本 |

上述权限采集的音频、图像与文本仅用于当前设备上的功能执行，不会回传给开发者。

---

## 3. 设备端识别、系统识别与第三方接口 / On-Device Processing & Third-Party Services

1. **本机离线与系统级处理：**
   - 在支持的 Apple 设备上，应用默认使用本机 **Apple Vision** 进行离线图片文字识别，以及使用 **Apple 系统语音识别（Speech Framework）** 进行语音转写。
2. **用户自配的第三方识别/解析/模型接口（BYOK）：**
   - 应用不内置或预填任何第三方云端服务商密钥。
   - 若您在设置中自主填入第三方服务商的接口地址与 API Key（包括图像识别、语音转文字、文档解析，或所在受支持地区/平台上的大语言模型接口），当您主动触发对应识别、解析或生成操作时，设备会将该次操作所选的文本、音频、图片或文件**直接发送至您指定的第三方服务商**。
   - 第三方服务商对数据的接收与处理受其各自的隐私政策及服务条款约束。
3. **模板社区（可选）：**
   - 仅当您主动访问公共模板社区下载模板，或主动点击上传公开模板时，应用才会与模板中心通信。社区模板仅包含字段结构与示例说明，不应包含任何个人隐私资料。

* **On-Device & OS Frameworks:** On supported Apple devices, the app defaults to on-device Apple Vision OCR and iOS Speech Recognition.
* **User-Configured Third-Party APIs (BYOK):** The app bundles no pre-filled third-party API keys. Only if you manually configure a third-party endpoint and API key and invoke a corresponding action will the selected content be transmitted directly from your device to that provider under that provider's own privacy policy.
* **Template Hub (Optional):** Accessed only when you explicitly browse, download, or publish non-personal template schemas.

---

## 4. 匿名基础统计与本地日志 / Anonymous Telemetry & Local Logs

- **匿名使用统计（可随时关闭）：** 应用默认在「设置 → 关于与帮助」中提供可随时关闭的匿名基础统计开关。开启时仅发送 **5 项基础技术字段**：随机匿名安装标识、应用版本号、构建号、操作系统类型、操作系统版本。**不包含**任何会话文本、图片、录音、识别结果、模板内容、IP 关联身份或 API 密钥。
- **本地运行日志：** 运行与崩溃日志仅保存在您的设备本地（敏感密钥会自动脱敏），仅在您主动点击「导出诊断日志」并自行分享时才会离开设备。

* **Anonymous Telemetry (Opt-out anytime in About & Help):** Sends only 5 non-personal technical fields (random installation ID, app version, build number, OS name, OS version). No user content, media, personal identifiers, or API keys are ever collected.
* **Runtime Logs:** Stored locally with automatic credential redaction and shared only when manually exported by you.

---

## 5. 数据控制与删除 / Data Retention & Deletion

- 您可以随时在应用内删除单条消息、单个会话、模板或词条。
- 卸载本应用将移除应用沙盒内的全部本地数据（包括首次启动区域配置记录）；如您曾在设备系统安全存储中保存过第三方 API Key，建议卸载前先在应用内清空或通过系统清理重置。

You can delete individual records, sessions, or templates at any time inside the app. Uninstalling the app removes all sandboxed local data on your device.

---

## 6. 儿童隐私 / Children's Privacy

本应用面向具备独立民事行为能力的效率办公及专业文档整理用户，不针对未满 13 周岁（或当地适用法定最低年龄）的儿童设计，亦不会有意收集儿童个人信息。

---

## 7. 隐私政策更新与联系方式 / Changes & Contact

随着功能迭代，我们可能会适时更新本隐私政策，更新后的版本将直接发布于本页面并更新顶部日期。

如对本隐私政策或数据安全有任何疑问、建议或反馈，请通过以下公开支持渠道联系开发者：

- **项目主页与问题反馈 / Support & Issues:** <https://github.com/xinggue/PeiPal_App/issues>
- **代码仓库 / Repository:** <https://github.com/xinggue/PeiPal_App>
