import AppKit
import FlutterMacOS
import ImageIO
import Vision

func registerAppleVisionOcr(with registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/apple_vision_ocr",
    binaryMessenger: registrar.messenger
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
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        CGImageSourceGetCount(source) > 0 else {
    return "[无法读取图片]"
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true
  request.recognitionLanguages = languages

  // 传文件 URL 让 Vision 自动读取并应用 EXIF 方向，避免竖拍/旋转图识别错乱
  let handler = VNImageRequestHandler(url: url, options: [:])
  do {
    try handler.perform([request])
  } catch {
    return "[识别失败 \(error.localizedDescription)]"
  }

  return formatObservations(request.results ?? [])
}

/// 先严格按 Y 降序排列并聚类成行，再在行内严格按 X 升序排列，避免单次比较器不满足严格弱序导致崩溃。
private func formatObservations(_ observations: [VNRecognizedTextObservation]) -> String {
  let verticalSorted = observations.sorted { a, b in
    if a.boundingBox.midY != b.boundingBox.midY {
      return a.boundingBox.midY > b.boundingBox.midY
    }
    return a.boundingBox.minX < b.boundingBox.minX
  }

  var lines: [[VNRecognizedTextObservation]] = []
  var anchorMidY: CGFloat = 0
  var anchorHeight: CGFloat = 0

  for obs in verticalSorted {
    let box = obs.boundingBox
    if lines.isEmpty {
      lines.append([obs])
      anchorMidY = box.midY
      anchorHeight = box.height
      continue
    }
    let tolerance = max(0.012, min(anchorHeight, box.height) * 0.45)
    if abs(box.midY - anchorMidY) <= tolerance {
      lines[lines.count - 1].append(obs)
    } else {
      lines.append([obs])
      anchorMidY = box.midY
      anchorHeight = box.height
    }
  }

  return lines.compactMap { line in
    let horizontal = line.sorted { a, b in
      if a.boundingBox.minX != b.boundingBox.minX {
        return a.boundingBox.minX < b.boundingBox.minX
      }
      return a.boundingBox.midY > b.boundingBox.midY
    }
    let joined = horizontal
      .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return joined.isEmpty ? nil : joined
  }.joined(separator: "\n")
}
