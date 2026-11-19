import AppKit
import FlutterMacOS

func registerConfigFileShare(with registrar: FlutterPluginRegistrar, window: NSWindow) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/config_file",
    binaryMessenger: registrar.messenger
  )
  let handler = ConfigFileShareHandler(window: window)
  channel.setMethodCallHandler { call, result in
    handler.handle(call: call, result: result)
  }
}

private final class ConfigFileShareHandler: NSObject, NSSharingServicePickerDelegate {
  private weak var window: NSWindow?
  private var activePicker: NSSharingServicePicker?
  private var pendingResult: FlutterResult?
  private var pendingTempDir: URL?

  init(window: NSWindow) {
    self.window = window
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "revealInFinder" {
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            !path.isEmpty else {
        result(FlutterError(code: "BAD_ARGS", message: "缺少文件路径", details: nil))
        return
      }
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      result(true)
      return
    }

    let isTextShare = call.method == "shareTextFile"
    let isFileShare = call.method == "shareBinaryFile"
    guard isTextShare || isFileShare else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "BAD_ARGS", message: "缺少分享参数", details: nil))
      return
    }

    let rawName = (args["fileName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lastComponent = (rawName as NSString).lastPathComponent
    let fileName = lastComponent.isEmpty
      ? (isFileShare ? "peipal_backup.zip" : "peipal_export.txt")
      : lastComponent

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("peipal_share_\(UUID().uuidString)", isDirectory: true)
    let tempFile = tempDir.appendingPathComponent(fileName)

    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      if isFileShare {
        guard let sourcePath = args["sourcePath"] as? String, !sourcePath.isEmpty else {
          try? FileManager.default.removeItem(at: tempDir)
          result(FlutterError(code: "BAD_ARGS", message: "缺少分享源文件路径", details: nil))
          return
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: tempFile)
      } else {
        guard let content = args["content"] as? String else {
          try? FileManager.default.removeItem(at: tempDir)
          result(FlutterError(code: "BAD_ARGS", message: "缺少分享内容", details: nil))
          return
        }
        guard let data = content.data(using: .utf8) else {
          try? FileManager.default.removeItem(at: tempDir)
          result(FlutterError(code: "ENCODE_FAILED", message: "无法编码分享文本", details: nil))
          return
        }
        try data.write(to: tempFile, options: .atomic)
      }
    } catch {
      try? FileManager.default.removeItem(at: tempDir)
      result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
      return
    }

    guard let contentView = window?.contentView else {
      try? FileManager.default.removeItem(at: tempDir)
      result(FlutterError(code: "NO_VIEW", message: "无法获取当前窗口视图", details: nil))
      return
    }

    if let oldResult = pendingResult {
      oldResult(false)
      pendingResult = nil
    }
    if let oldDir = pendingTempDir {
      try? FileManager.default.removeItem(at: oldDir)
      pendingTempDir = nil
    }

    let picker = NSSharingServicePicker(items: [tempFile])
    picker.delegate = self
    activePicker = picker
    pendingResult = result
    pendingTempDir = tempDir

    let anchorRect = NSRect(
      x: contentView.bounds.midX,
      y: contentView.bounds.midY,
      width: 1,
      height: 1
    )
    picker.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
  }

  func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
    let chosen = service != nil
    let res = pendingResult
    let dir = pendingTempDir
    pendingResult = nil
    pendingTempDir = nil
    activePicker = nil

    res?(chosen)

    if let dir {
      let delay: TimeInterval = chosen ? 30.0 : 0.0
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
        try? FileManager.default.removeItem(at: dir)
      }
    }
  }
}
