# Windows 性能排查

## 已确认（2026-11-19）

- v0.1.7 的 CI 使用 Flutter 3.50.0，执行 `flutter build windows --release`，不是 Debug。
- 下载检查了公开便携包：56 个条目，解压后约 72.3 MiB。包含
  `peipal.exe`、`flutter_windows.dll`、AOT `data/app.so`、ICU、
  ICD 数据库、插件 DLL 和模型资源。
- 下载体积：Windows Setup 38.5 MB、ZIP 43.7 MB；Android APK 56.6 MB、
  macOS DMG 58.2 MB（十进制）。安装器采用 LZMA 固实压缩；
  Windows 仅 x64，默认 Android APK 包含多个 ABI，原生插件也随平台不同。
  不应以压缩包大小判断渲染性能或功能完整性。
- 根 Overlay 原来在 `didUpdateWidget` 中延迟到帧结束才更新 entry。
  尺寸变化会再次排队一帧；改用 Flutter 的 `Overlay.wrap` 同帧更新，
  保留悬浮输入框编辑菜单所需的 Overlay。
- 悬浮面板原来在窗口尺寸连续变化时反复重设 300ms 位置动画；
  尺寸变化时改为立即跟随，主动展开/最大化动画保留。
- 页面增加绘制隔离，避免悬浮控件独立动画或拖动时连带重绘底下页面。
  这不免除窗口缩放本来就需要的重新布局。

以上是代码路径分析和包检查，不是 Windows 实机性能测量。
不能据此断言这些改动消除了所有卡顿。

## Windows 实机复测

先使用本地安装的正式包和便携包，在相同数据、相同显示器下对照。
记录 Windows 版本、显卡型号/驱动版本、分辨率、缩放比例、刷新率，
是否通过远程桌面或虚拟机运行。普通页面也卡时尤其需要确认 GPU 环境。

在 Windows 开发机、`app/` 目录下，使用与 CI 相同的 Flutter 版本：

```powershell
flutter --version
flutter pub get
flutter run -d windows --profile
```

打开终端给出的 DevTools 地址，在 Performance 里分别录制：

1. 会话列表静置 5 秒。
2. 连续拖动窗口右边缘、下边缘和右下角各 10 秒。
3. 滚动长会话，再进入设置页滚动。
4. 悬浮面板关闭和展开各重复一次。

先滚动一次预热，再录第二次，区分首次字体/图片/着色器加载与持续卡顿。
导出录制结果；只用测试数据，避免截图或 trace 暴露真实会话。

- UI 帧耗时高：继续查布局、重建、文本排版或主 isolate 的同步计算。
- Raster 帧耗时高：继续查大图、阴影、裁剪与 GPU 绘制。
- 两者都不高但窗口拖动停顿：继续查 Win32 消息循环、引擎呈现与驱动，
  不能只靠 Flutter 帧耗时下结论。
- 60 Hz 的单阶段帧预算约 16.7ms，120 Hz 约 8.3ms。

不要直接用 Debug 帧耗时判断正式包性能，也不要先关闭硬件加速作为“优化”。
当前 Windows runner 没有主动启用软件渲染，是否存在驱动回退仍需实机检查。

## 打包检查

CI 在压缩前检查核心运行文件、AOT 和数据库非空，拒绝混入 Debug kernel，
并在 Actions Summary 输出未压缩体积及最大的文件：

```powershell
python .github/scripts/verify_windows_bundle.py build/windows/x64/runner/Release
```

这是核心文件检查，不替代干净 Windows 机器上的启动、插件和 VC++ 运行库测试。
