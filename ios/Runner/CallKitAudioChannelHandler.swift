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

  /// Fires when the user taps Accept (CallKit → AppDelegate). Mirrors the
  /// decline bridge so accept is delivered reliably even when the plugin's
  /// Flutter event channel drops `ACTION_CALL_ACCEPT` (implicit engine race).
  static func notifyCallAccepted(call: Call) {
    var args: [String: Any] = [:]
    if let extra = call.data.extra as? [String: Any] {
      for key in ["callerId", "callerName", "callerRole", "channelName", "callRecordId"] {
        if let value = extra[key] as? String, !value.isEmpty {
          args[key] = value
        }
      }
    }
    DispatchQueue.main.async {
      channel?.invokeMethod("callAccepted", arguments: args)
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

  /// Fires when the user taps End on the native CallKit UI (lock screen / banner).
  static func notifyCallEnded(call: Call) {
    var args: [String: Any] = [:]
    if let extra = call.data.extra as? [String: Any] {
      if let callerId = extra["callerId"] as? String, !callerId.isEmpty {
        args["callerId"] = callerId
      }
      if let recordId = extra["callRecordId"] as? String, !recordId.isEmpty {
        args["callRecordId"] = recordId
      }
    }
    DispatchQueue.main.async {
      channel?.invokeMethod("callEnded", arguments: args)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
