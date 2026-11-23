import Flutter
import Foundation
import StoreKit

private let lockedStorefrontDefaultsKey = "peipal.compliance.lockedStorefrontCountryCode.v1"

func registerStorefrontPlugin(with registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(
    name: "com.xinggue.docmasterPei/storefront",
    binaryMessenger: registrar.messenger()
  )
  channel.setMethodCallHandler { call, result in
    handleStorefrontCall(call: call, result: result)
  }
}

private func currentDeviceRegion() -> String? {
  if #available(iOS 16.0, *) {
    return Locale.current.region?.identifier
  } else {
    return Locale.current.regionCode
  }
}

private func readLockedStorefront() -> String? {
  guard let stored = UserDefaults.standard.string(forKey: lockedStorefrontDefaultsKey)?
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .uppercased(),
    !stored.isEmpty
  else {
    return nil
  }
  return stored
}

private func handleStorefrontCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
  guard call.method == "getRegionInfo" else {
    result(FlutterMethodNotImplemented)
    return
  }

  let deviceRegion = currentDeviceRegion()

  // Lock on first valid App Store storefront so switching Apple IDs later
  // does not flip app behavior for the remainder of this installation.
  if let locked = readLockedStorefront() {
    var payload: [String: Any] = [
      "storefrontCountryCode": locked,
      "isLocked": true,
    ]
    if let deviceRegion, !deviceRegion.isEmpty {
      payload["deviceRegionCode"] = deviceRegion
    }
    result(payload)
    return
  }

  Task {
    let storefront = await StoreKit.Storefront.current
    var payload: [String: Any] = [:]
    if let lockedNow = readLockedStorefront() {
      payload["storefrontCountryCode"] = lockedNow
      payload["isLocked"] = true
    } else if let rawCode = storefront?.countryCode
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased(),
      !rawCode.isEmpty {
      UserDefaults.standard.set(rawCode, forKey: lockedStorefrontDefaultsKey)
      payload["storefrontCountryCode"] = rawCode
      payload["isLocked"] = true
    } else {
      payload["isLocked"] = false
    }
    if let deviceRegion, !deviceRegion.isEmpty {
      payload["deviceRegionCode"] = deviceRegion
    }
    DispatchQueue.main.async {
      result(payload)
    }
  }
}
