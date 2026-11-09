import Flutter
import UIKit
import Vision

func registerAppleVisionOcr(with registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/apple_vision_ocr",
    binaryMessenger: registrar.messenger()
  )
  channel.setMethodCallHandler { call, result in
    handleAppleVisionOcr(call: call, result: result)
  }
}

private func handleAppleVisionOcr(call: FlutterMethodCall, result: @escaping FlutterResult) {
  switch call.method {
  case "isAvailable":
    result(true)
  case "recognize":
    guard let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String] else {
      result(FlutterError(code: "bad_args", message: "缺少图片路径", details: nil))
      return
    }
    let languages = args["languages"] as? [String] ?? ["zh-Hans", "en-US"]
    DispatchQueue.global(qos: .userInitiated).async {
      let text = recognizeImages(paths: paths, languages: languages)
      DispatchQueue.main.async {
        result(text)
      }
    }
  default:
    result(FlutterMethodNotImplemented)
  }
}

private func recognizeImages(paths: [String], languages: [String]) -> String {
  var pages: [String] = []
  for path in paths {
    let page = recognizeImage(path: path, languages: languages).trimmingCharacters(in: .whitespacesAndNewlines)
    if !page.isEmpty {
      pages.append(page)
    }
  }
  return pages.joined(separator: "\n\n")
}

private func recognizeImage(path: String, languages: [String]) -> String {
  let url = URL(fileURLWithPath: path)
  guard let image = UIImage(contentsOfFile: url.path),
        let cgImage = image.cgImage else {
    return "[无法读取图片]"
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true
  request.recognitionLanguages = languages

  let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
  do {
    try handler.perform([request])
  } catch {
    return "[识别失败 \(error.localizedDescription)]"
  }

  let observations = request.results ?? []
  let sorted = observations.sorted { a, b in
    let ay = a.boundingBox.midY
    let by = b.boundingBox.midY
    if abs(ay - by) > 0.012 {
      return ay > by
    }
    return a.boundingBox.minX < b.boundingBox.minX
  }

  return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}
