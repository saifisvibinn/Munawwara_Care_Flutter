import Foundation
import UIKit
import flutter_callkit_incoming

/// Native HTTP accept/decline for killed/background CallKit actions.
/// Mirrors Android `CallDeclineApplication` so the caller stops ringing even when
/// the Flutter engine has not started yet.
enum CallSignalingBridge {
  private static let prefsPrefix = "flutter."
  private static let productionApiFallback =
    "https://mc-backend-44890250266.europe-west3.run.app/api"

  private struct Payload {
    let callerId: String
    let callRecordId: String
    let currentUserId: String
    let apiBaseUrl: String

    var canSignal: Bool {
      (!callerId.isEmpty || !callRecordId.isEmpty) && !apiBaseUrl.isEmpty
    }
  }

  static func postAnswer(for call: Call) {
    persistPendingAccept(from: call)
    let payload = extractPayload(from: call)
    guard payload.canSignal else {
      NSLog(
        "[CallSignaling] Answer skipped — callerId=\(payload.callerId) "
          + "callRecordId=\(payload.callRecordId) api=\(payload.apiBaseUrl)"
      )
      return
    }

    var body: [String: Any] = ["callerId": payload.callerId]
    if !payload.currentUserId.isEmpty {
      body["answererId"] = payload.currentUserId
    }

    NSLog(
      "[CallSignaling] Native ACCEPT -> \(payload.apiBaseUrl) "
        + "callerId=\(payload.callerId) answererId=\(payload.currentUserId)"
    )
    postJson(
      to: "\(payload.apiBaseUrl)/call-history/answer",
      body: body,
      label: "answer",
    )
  }

  static func postDecline(for call: Call, noAnswer: Bool) {
    postDecline(payload: extractPayload(from: call), noAnswer: noAnswer)
  }

  /// Used when PushKit woke the app but CallKit no longer has the call in memory.
  static func postDeclineFromPersisted(noAnswer: Bool) {
    postDecline(payload: payloadFromPersistedPrefs(), noAnswer: noAnswer)
  }

  static func postDecline(extra: [String: Any]?, noAnswer: Bool) {
    var payload = payloadFromPersistedPrefs()
    if let extra {
      let callerId = stringValue(extra, keys: ["callerId", "caller_id"]) ?? ""
      let callRecordId =
        stringValue(extra, keys: ["callRecordId", "call_record_id", "id"]) ?? ""
      if !callerId.isEmpty {
        payload = Payload(
          callerId: callerId,
          callRecordId: callRecordId.isEmpty ? payload.callRecordId : callRecordId,
          currentUserId: payload.currentUserId,
          apiBaseUrl: payload.apiBaseUrl,
        )
      }
    }
    postDecline(payload: payload, noAnswer: noAnswer)
  }

  private static func postDecline(payload: Payload, noAnswer: Bool) {
    guard payload.canSignal else {
      NSLog(
        "[CallSignaling] Decline skipped — callerId=\(payload.callerId) "
          + "callRecordId=\(payload.callRecordId) api=\(payload.apiBaseUrl)"
      )
      return
    }

    var body: [String: Any] = ["callerId": payload.callerId]
    if !payload.currentUserId.isEmpty {
      body["declinerId"] = payload.currentUserId
    }
    if !payload.callRecordId.isEmpty {
      body["callRecordId"] = payload.callRecordId
    }
    if noAnswer {
      body["noAnswer"] = true
    }

    NSLog(
      "[CallSignaling] Native DECLINE -> \(payload.apiBaseUrl) "
        + "callerId=\(payload.callerId) callRecordId=\(payload.callRecordId) "
        + "noAnswer=\(noAnswer)"
    )
    postJson(
      to: "\(payload.apiBaseUrl)/call-history/decline",
      body: body,
      label: "decline",
      onSuccess: clearPendingCallPrefs,
    )
  }

  static func clearPendingCallPrefs() {
    let defaults = UserDefaults.standard
    for key in [
      "pending_call_caller_id",
      "pending_call_record_id",
      "pending_call_channel_name",
      "pending_call_caller_name",
      "pending_call_caller_role",
      "pending_call_created_at_ms",
      "pending_call_uuid",
    ] {
      defaults.removeObject(forKey: prefsPrefix + key)
    }
    clearPendingAcceptFile()
  }

  /// Writes the same JSON file Dart uses in [NativeCallCoordinator] so a killed
  /// accept can join Agora after Flutter boots (method channel may be too early).
  static func persistPendingAccept(from call: Call) {
    guard let extra = call.data.extra as? [String: Any] else { return }
    let callerId = stringValue(extra, keys: ["callerId", "caller_id"]) ?? ""
    let channelName =
      stringValue(extra, keys: ["channelName", "channel_name"]) ?? ""
    guard !channelName.isEmpty else {
      NSLog("[CallSignaling] Accept persist skipped — missing channelName")
      return
    }

    let callerName =
      stringValue(extra, keys: ["peerCallerName", "callerName", "caller_name"])
      ?? "Unknown"
    let callerRole =
      stringValue(extra, keys: ["callerRole", "caller_role"]) ?? ""

    if !callerId.isEmpty {
      UserDefaults.standard.set(callerId, forKey: prefsPrefix + "pending_call_caller_id")
    }
    UserDefaults.standard.set(channelName, forKey: prefsPrefix + "pending_call_channel_name")
    if !callerName.isEmpty {
      UserDefaults.standard.set(callerName, forKey: prefsPrefix + "pending_call_caller_name")
    }
    if !callerRole.isEmpty {
      UserDefaults.standard.set(callerRole, forKey: prefsPrefix + "pending_call_caller_role")
    }

    let acceptBody: [String: String] = [
      "callerId": callerId,
      "callerName": callerName,
      "channelName": channelName,
      "callerRole": callerRole,
    ]
    guard
      let data = try? JSONSerialization.data(withJSONObject: acceptBody),
      let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      return
    }
    let fileURL = dir.appendingPathComponent("pending_call_accept.json")
    do {
      try data.write(to: fileURL, options: .atomic)
      NSLog("[CallSignaling] Persisted pending accept for channel \(channelName)")
    } catch {
      NSLog("[CallSignaling] Failed to persist pending accept: \(error.localizedDescription)")
    }
  }

  static func clearPendingAcceptFile() {
    guard
      let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      return
    }
    let fileURL = dir.appendingPathComponent("pending_call_accept.json")
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Cache call ids for Dart fallback paths (same keys as `CallKitService` prefs).
  static func persistPendingCall(from payload: [AnyHashable: Any]) {
    let dict = payload as? [String: Any] ?? [:]
    let callerId = stringValue(dict, keys: ["callerId", "caller_id"]) ?? ""
    let callRecordId =
      stringValue(dict, keys: ["callRecordId", "call_record_id", "id"]) ?? ""
    let channelName = stringValue(dict, keys: ["channelName", "channel_name"]) ?? ""

    guard !callerId.isEmpty || !callRecordId.isEmpty || !channelName.isEmpty else {
      return
    }

    let defaults = UserDefaults.standard
    if !callerId.isEmpty {
      defaults.set(callerId, forKey: prefsPrefix + "pending_call_caller_id")
    }
    if !callRecordId.isEmpty {
      defaults.set(callRecordId, forKey: prefsPrefix + "pending_call_record_id")
    }
    if !channelName.isEmpty {
      defaults.set(channelName, forKey: prefsPrefix + "pending_call_channel_name")
    }
    let callerName =
      stringValue(dict, keys: ["callerName", "caller_name", "peerCallerName"]) ?? ""
    let callerRole = stringValue(dict, keys: ["callerRole", "caller_role"]) ?? ""
    if !callerName.isEmpty {
      defaults.set(callerName, forKey: prefsPrefix + "pending_call_caller_name")
    }
    if !callerRole.isEmpty {
      defaults.set(callerRole, forKey: prefsPrefix + "pending_call_caller_role")
    }
    defaults.set(
      Int(Date().timeIntervalSince1970 * 1000),
      forKey: prefsPrefix + "pending_call_created_at_ms",
    )
  }

  private static func extractPayload(from call: Call) -> Payload {
    var payload = payloadFromPersistedPrefs()
    if let extra = call.data.extra as? [String: Any] {
      let callerId = stringValue(extra, keys: ["callerId", "caller_id"]) ?? ""
      let callRecordId =
        stringValue(extra, keys: ["callRecordId", "call_record_id", "id"]) ?? ""
      if !callerId.isEmpty {
        payload = Payload(
          callerId: callerId,
          callRecordId: callRecordId.isEmpty ? payload.callRecordId : callRecordId,
          currentUserId: payload.currentUserId,
          apiBaseUrl: payload.apiBaseUrl,
        )
      }
    }
    return payload
  }

  private static func payloadFromPersistedPrefs() -> Payload {
    let defaults = UserDefaults.standard
    return Payload(
      callerId: defaults.string(forKey: prefsPrefix + "pending_call_caller_id") ?? "",
      callRecordId:
        defaults.string(forKey: prefsPrefix + "pending_call_record_id") ?? "",
      currentUserId: defaults.string(forKey: prefsPrefix + "user_id") ?? "",
      apiBaseUrl:
        defaults.string(forKey: prefsPrefix + "api_base_url")?
        .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        ?? productionApiFallback,
    )
  }

  private static func stringValue(
    _ dict: [String: Any],
    keys: [String],
  ) -> String? {
    for key in keys {
      if let value = dict[key] as? String, !value.isEmpty {
        return value
      }
    }
    return nil
  }

  private static func postJson(
    to urlString: String,
    body: [String: Any],
    label: String,
    onSuccess: (() -> Void)? = nil,
  ) {
    guard let url = URL(string: urlString) else {
      NSLog("[CallSignaling] Invalid URL for \(label): \(urlString)")
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 10
    guard let data = try? JSONSerialization.data(withJSONObject: body) else {
      NSLog("[CallSignaling] Failed to encode \(label) body")
      return
    }
    request.httpBody = data

    var bgTask: UIBackgroundTaskIdentifier = .invalid
    bgTask = UIApplication.shared.beginBackgroundTask {
      if bgTask != .invalid {
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
      }
    }

    URLSession.shared.dataTask(with: request) { _, response, error in
      defer {
        if bgTask != .invalid {
          UIApplication.shared.endBackgroundTask(bgTask)
        }
      }
      if let error = error {
        NSLog("[CallSignaling] Native \(label) POST failed: \(error.localizedDescription)")
        return
      }
      let code = (response as? HTTPURLResponse)?.statusCode ?? -1
      NSLog("[CallSignaling] Native \(label) POST response: \(code)")
      if (200...299).contains(code) {
        onSuccess?()
      }
    }.resume()
  }
}

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}
