import Flutter
import Foundation
import Speech

public func registerAppleSpeechAsr(with registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/apple_speech_asr",
    binaryMessenger: registrar.messenger()
  )

  channel.setMethodCallHandler { call, result in
    switch call.method {
    case "isAvailable":
      let args = call.arguments as? [String: Any]
      let language = args?["language"] as? String
      let authStatus = SFSpeechRecognizer.authorizationStatus()
      if authStatus == .denied || authStatus == .restricted {
        result(false)
        return
      }
      guard let recognizer = resolveSpeechRecognizer(languageHint: language) else {
        result(false)
        return
      }
      result(recognizer.isAvailable)

    case "transcribe":
      guard let args = call.arguments as? [String: Any],
            let filePath = args["filePath"] as? String,
            !filePath.isEmpty else {
        result(FlutterError(code: "INVALID_ARGS", message: "缺少 filePath 参数", details: nil))
        return
      }
      guard FileManager.default.fileExists(atPath: filePath) else {
        result(FlutterError(code: "FILE_NOT_FOUND", message: "音频文件不存在", details: filePath))
        return
      }

      let language = args["language"] as? String
      transcribeAudioFile(filePath: filePath, languageHint: language, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private func resolveSpeechRecognizer(languageHint: String?) -> SFSpeechRecognizer? {
  let normalized = (languageHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  var candidates: [String] = []
  if !normalized.isEmpty && normalized.lowercased() != "auto" {
    candidates.append(normalized)
    if normalized.lowercased() == "zh" {
      candidates.append("zh-CN")
    } else if normalized.lowercased() == "en" {
      candidates.append("en-US")
    }
  }
  candidates.append(contentsOf: ["zh-CN", "zh-Hans-CN", Locale.current.identifier, "en-US"])

  for identifier in candidates {
    let locale = Locale(identifier: identifier)
    if let recognizer = SFSpeechRecognizer(locale: locale) {
      return recognizer
    }
  }
  return SFSpeechRecognizer()
}

private func isNoSpeechError(_ error: Error) -> Bool {
  let nsError = error as NSError
  // SFSpeechRecognizer / Siri Assistant reports code 1110 when no speech is detected in audio.
  return nsError.code == 1110
}

private func transcribeAudioFile(
  filePath: String,
  languageHint: String?,
  result: @escaping FlutterResult
) {
  let stateQueue = DispatchQueue(label: "com.xinggue.docmasterPei.appleSpeechAsr.state")
  var didFinish = false
  var activeTask: SFSpeechRecognitionTask?
  var timeoutWorkItem: DispatchWorkItem?

  func finishOnce(_ value: Any?) {
    var shouldInvoke = false
    stateQueue.sync {
      if !didFinish {
        didFinish = true
        shouldInvoke = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
      }
    }
    guard shouldInvoke else { return }
    DispatchQueue.main.async {
      result(value)
    }
  }

  SFSpeechRecognizer.requestAuthorization { authStatus in
    switch authStatus {
    case .authorized:
      break
    case .denied:
      finishOnce(FlutterError(
        code: "PERMISSION_DENIED",
        message: "未获得系统语音识别权限，请在系统设置中允许访问“语音识别”",
        details: nil
      ))
      return
    case .restricted:
      finishOnce(FlutterError(
        code: "PERMISSION_RESTRICTED",
        message: "当前设备限制了系统语音识别功能",
        details: nil
      ))
      return
    case .notDetermined:
      finishOnce(FlutterError(
        code: "PERMISSION_NOT_DETERMINED",
        message: "尚未完成系统语音识别授权",
        details: nil
      ))
      return
    @unknown default:
      finishOnce(FlutterError(
        code: "PERMISSION_UNKNOWN",
        message: "系统语音识别授权状态未知",
        details: nil
      ))
      return
    }

    guard let recognizer = resolveSpeechRecognizer(languageHint: languageHint) else {
      finishOnce(FlutterError(
        code: "UNSUPPORTED_LOCALE",
        message: "当前系统不支持所选语言的系统语音识别",
        details: languageHint
      ))
      return
    }

    guard recognizer.isAvailable else {
      finishOnce(FlutterError(
        code: "UNAVAILABLE",
        message: "系统语音识别暂不可用，请检查网络连接或系统听写设置",
        details: nil
      ))
      return
    }

    let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: filePath))
    request.shouldReportPartialResults = false
    request.taskHint = .dictation

    let workItem = DispatchWorkItem {
      var taskToCancel: SFSpeechRecognitionTask?
      stateQueue.sync {
        taskToCancel = activeTask
      }
      taskToCancel?.cancel()
      finishOnce(FlutterError(
        code: "TIMEOUT",
        message: "系统语音识别超时，请重试",
        details: nil
      ))
    }

    stateQueue.sync {
      timeoutWorkItem = workItem
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60, execute: workItem)

    let task = recognizer.recognitionTask(with: request) { recognitionResult, error in
      if let recognitionResult = recognitionResult, recognitionResult.isFinal {
        let text = recognitionResult.bestTranscription.formattedString
          .trimmingCharacters(in: .whitespacesAndNewlines)
        finishOnce(text)
        return
      }

      if let error = error {
        if isNoSpeechError(error) {
          finishOnce("")
        } else {
          finishOnce(FlutterError(
            code: "SPEECH_RECOGNITION_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }

    stateQueue.sync {
      activeTask = task
    }
  }
}
