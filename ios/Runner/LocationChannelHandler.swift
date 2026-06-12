import CoreLocation
import Flutter
import Foundation

/// Native bridge for Tameny location tracking on iOS.
/// Channel: com.munawwaracare/location
final class LocationChannelHandler: NSObject, FlutterPlugin, CLLocationManagerDelegate {
  private static let channelName = "com.munawwaracare/location"
  private static let tokenKey = "pilgrim_auth_token"
  private static let serverUrlKey = "server_url"

  private var channel: FlutterMethodChannel?
  private let locationManager = CLLocationManager()

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LocationChannelHandler()
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger(),
    )
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.pausesLocationUpdatesAutomatically = false
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "saveCredentials":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Expected map", details: nil))
        return
      }
      let token = args["token"] as? String ?? ""
      let serverUrl = args["serverUrl"] as? String ?? ""
      UserDefaults.standard.set(token, forKey: Self.tokenKey)
      UserDefaults.standard.set(serverUrl, forKey: Self.serverUrlKey)
      result(true)
    case "startSignificantLocationChanges":
      let status = locationManager.authorizationStatus
      if status == .notDetermined {
        locationManager.requestAlwaysAuthorization()
      }
      locationManager.startMonitoringSignificantLocationChanges()
      result(true)
    case "stopSignificantLocationChanges":
      locationManager.stopMonitoringSignificantLocationChanges()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    sendHeartbeat(location: location)
  }

  func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error,
  ) {
    NSLog("[TamenyLocation] CLLocationManager error: \(error.localizedDescription)")
  }

  private func sendHeartbeat(location: CLLocation) {
    let token = UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
    let serverUrl = UserDefaults.standard.string(forKey: Self.serverUrlKey) ?? ""
    if token.isEmpty || serverUrl.isEmpty {
      return
    }

    let baseUrl = Self.resolveApiBaseUrl(serverUrl)
    guard let url = URL(string: "\(baseUrl)/location/heartbeat") else {
      return
    }

    let payload: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "source": "ios_significant_change",
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ]

    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let task = URLSession.shared.dataTask(with: request) { _, response, error in
      if let error = error {
        NSLog("[TamenyLocation] heartbeat failed: \(error.localizedDescription)")
        return
      }
      if let http = response as? HTTPURLResponse {
        NSLog("[TamenyLocation] heartbeat status: \(http.statusCode)")
      }
    }
    task.resume()
  }

  private static func resolveApiBaseUrl(_ serverUrl: String) -> String {
    var clean = serverUrl
    if clean.hasSuffix("/") {
      clean.removeLast()
    }
    if clean.hasSuffix("/api") {
      return clean
    }
    return "\(clean)/api"
  }
}
