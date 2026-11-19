import Flutter
import UIKit

func registerConfigFileExport(with registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/config_file",
    binaryMessenger: registrar.messenger()
  )
  let handler = ConfigFileExportHandler(registrar: registrar)
  channel.setMethodCallHandler { call, result in
    handler.handle(call: call, result: result)
  }
}

private final class ConfigFileExportHandler: NSObject {
  private let registrar: FlutterPluginRegistrar
  private var activeBridge: DocumentExportBridge?

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let isTextExport = call.method == "saveWithDocumentPicker"
    let isFileExport = call.method == "saveFileWithDocumentPicker"
    let isTextShare = call.method == "shareTextFile"
    let isFileShare = call.method == "shareBinaryFile"
    guard isTextExport || isFileExport || isTextShare || isFileShare else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "BAD_ARGS", message: "缺少导出参数", details: nil))
      return
    }

    let rawName = (args["fileName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let lastComponent = (rawName as NSString).lastPathComponent
    let fileName = lastComponent.isEmpty
      ? ((isFileExport || isFileShare) ? "peipal_backup.zip" : "docmaster_config.txt")
      : lastComponent

    guard let presenter = resolveTopViewController() else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "无法获取当前界面控制器", details: nil))
      return
    }

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("peipal_export_\(UUID().uuidString)", isDirectory: true)
    let tempFile = tempDir.appendingPathComponent(fileName)

    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      if isFileExport || isFileShare {
        guard let sourcePath = args["sourcePath"] as? String, !sourcePath.isEmpty else {
          try? FileManager.default.removeItem(at: tempDir)
          result(FlutterError(code: "BAD_ARGS", message: "缺少导出源文件路径", details: nil))
          return
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: tempFile)
      } else {
        guard let content = args["content"] as? String else {
          try? FileManager.default.removeItem(at: tempDir)
          result(FlutterError(code: "BAD_ARGS", message: "缺少导出内容", details: nil))
          return
        }
        guard let data = content.data(using: .utf8) else {
          try? FileManager.default.removeItem(at: tempDir)
          result(FlutterError(code: "ENCODE_FAILED", message: "无法编码导出文本", details: nil))
          return
        }
        try data.write(to: tempFile, options: .atomic)
      }
    } catch {
      try? FileManager.default.removeItem(at: tempDir)
      result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
      return
    }

    if isTextShare || isFileShare {
      let activityVC = UIActivityViewController(activityItems: [tempFile], applicationActivities: nil)
      if let subject = args["subject"] as? String, !subject.isEmpty {
        activityVC.setValue(subject, forKey: "subject")
      }
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 0,
          height: 0
        )
        popover.permittedArrowDirections = []
      }
      var completedOnce = false
      activityVC.completionWithItemsHandler = { _, completed, _, _ in
        if completedOnce { return }
        completedOnce = true
        try? FileManager.default.removeItem(at: tempDir)
        result(completed)
      }
      presenter.present(activityVC, animated: true)
      return
    }

    // Cancel any stale pending export before presenting a new picker.
    activeBridge?.cancelIfPending()

    let bridge = DocumentExportBridge(
      tempDir: tempDir,
      fallbackName: fileName,
      onComplete: { [weak self] outcome in
        self?.activeBridge = nil
        result(outcome)
      }
    )
    activeBridge = bridge

    let picker = UIDocumentPickerViewController(forExporting: [tempFile], asCopy: true)
    picker.delegate = bridge
    picker.presentationController?.delegate = bridge
    presenter.present(picker, animated: true)
  }

  private func resolveTopViewController() -> UIViewController? {
    var root = registrar.viewController
    if root == nil {
      let window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }
      root = window?.rootViewController
    }
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }
}

private final class DocumentExportBridge: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private let tempDir: URL
  private let fallbackName: String
  private var onComplete: ((String?) -> Void)?

  init(tempDir: URL, fallbackName: String, onComplete: @escaping (String?) -> Void) {
    self.tempDir = tempDir
    self.fallbackName = fallbackName
    self.onComplete = onComplete
  }

  func cancelIfPending() {
    finish(with: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let savedName = urls.first?.lastPathComponent
    finish(with: (savedName?.isEmpty == false) ? savedName : fallbackName)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(with: nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(with: nil)
  }

  private func finish(with value: String?) {
    guard let callback = onComplete else { return }
    onComplete = nil
    try? FileManager.default.removeItem(at: tempDir)
    callback(value)
  }
}
