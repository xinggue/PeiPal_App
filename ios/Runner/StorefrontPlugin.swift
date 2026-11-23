import Flutter
import Foundation
import StoreKit

func registerStorefrontPlugin(with registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/storefront",
    binaryMessenger: registrar.messenger()
  )
  channel.setMethodCallHandler { call, result in
    handleStorefrontCall(call: call, result: result)
  }
}

private func handleStorefrontCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
  guard call.method == "getRegionInfo" else {
    result(FlutterMethodNotImplemented)
    return
  }

  let deviceRegion: String?
  if #available(iOS 16.0, *) {
    deviceRegion = Locale.current.region?.identifier
  } else {
    deviceRegion = Locale.current.regionCode
  }

  Task {
    let storefront = await StoreKit.Storefront.current
    var payload: [String: Any] = [:]
    if let countryCode = storefront?.countryCode, !countryCode.isEmpty {
      payload["storefrontCountryCode"] = countryCode
    }
    if let deviceRegion, !deviceRegion.isEmpty {
      payload["deviceRegionCode"] = deviceRegion
    }
    DispatchQueue.main.async {
      result(payload)
    }
  }
}
