import Flutter
import Foundation
import flutter_callkit_incoming

/// Notifies Dart when CallKit activates/deactivates AVAudioSession (CXProviderDelegate).
/// Channel: com.munawwaracare/callkit_audio
final class CallKitAudioChannelHandler: NSObject, FlutterPlugin {
  private static let channelName = "com.munawwaracare/callkit_audio"
  private static var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger(),
    )
    self.channel = channel
    registrar.addMethodCallDelegate(CallKitAudioChannelHandler(), channel: channel)
  }

  static func notifyAudioSessionActivated() {
    DispatchQueue.main.async {
      channel?.invokeMethod("audioSessionActivated", arguments: nil)
    }
  }

  static func notifyAudioSessionDeactivated() {
    DispatchQueue.main.async {
      channel?.invokeMethod("audioSessionDeactivated", arguments: nil)
    }
  }

  /// Fires when the user taps Decline or the ring times out (CallKit → AppDelegate).
  static func notifyCallDeclined(call: Call, noAnswer: Bool) {
    var args: [String: Any] = ["noAnswer": noAnswer]
    if let extra = call.data.extra as? [String: Any] {
      if let callerId = extra["callerId"] as? String, !callerId.isEmpty {
        args["callerId"] = callerId
      }
      if let recordId = extra["callRecordId"] as? String, !recordId.isEmpty {
        args["callRecordId"] = recordId
      }
    }
    DispatchQueue.main.async {
      channel?.invokeMethod("callDeclined", arguments: args)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
