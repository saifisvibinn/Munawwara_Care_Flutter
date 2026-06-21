import AVFAudio
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_background_service_ios
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?
  /// CallKit can emit a spurious end/decline a few ms before accept on the same
  /// call. Defer BOTH the HTTP decline POST and the Dart notification so a
  /// near-simultaneous accept cancels them before they reach the server.
  private var pendingDeclineNotify: DispatchWorkItem?
  /// Timestamp of the last onAccept call — used to suppress a racing onDecline
  /// that arrives within 1 s of an accept (belt-and-suspenders guard).
  private var lastAcceptAt: Date?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    setupVoipPushRegistryIfEntitled()
    registerForStandardPushIfEntitled()
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.flutter.background.refresh"
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// PushKit requires `aps-environment` (paid Apple Developer + Push capability).
  ///
  /// Release/TestFlight/App Store builds do not ship `embedded.mobileprovision`
  /// on device, so we always register push there — entitlements are in the signed
  /// binary (`Runner-Release.entitlements`). Debug USB builds still gate on the
  /// embedded profile so free Personal Team installs fail gracefully.
  private func hasPushEntitlement() -> Bool {
    #if !DEBUG
    return true
    #else
    guard let provisionURL = Bundle.main.url(
      forResource: "embedded",
      withExtension: "mobileprovision",
    ),
      let data = try? Data(contentsOf: provisionURL),
      let raw = String(data: data, encoding: .isoLatin1),
      raw.contains("<key>aps-environment</key>")
    else {
      NSLog(
        "[Runner] No aps-environment entitlement — push registration skipped "
          + "(expected on free Apple ID until Push Notifications is enabled)"
      )
      return false
    }
    return true
    #endif
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "LocationChannelHandler",
    ) {
      LocationChannelHandler.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "MapKitBridge",
    ) {
      MapKitBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ScrollEdgeBlurBridge",
    ) {
      ScrollEdgeBlurBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "CallKitAudioChannelHandler",
    ) {
      CallKitAudioChannelHandler.register(with: registrar)
    }
  }

  /// FCM on iOS requires a standard APNS device token (separate from PushKit VoIP).
  private func registerForStandardPushIfEntitled() {
    guard hasPushEntitlement() else {
      NSLog(
        "[Runner] Skipping registerForRemoteNotifications — no aps-environment entitlement"
      )
      return
    }
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  private func setupVoipPushRegistryIfEntitled() {
    guard hasPushEntitlement() else {
      NSLog(
        "[Runner] Skipping VoIP PushKit — no aps-environment entitlement "
          + "(expected on free Apple ID until Push Notifications is enabled)"
      )
      return
    }
    let mainQueue = DispatchQueue.main
    let registry = PKPushRegistry(queue: mainQueue)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  // MARK: - PushKit

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate credentials: PKPushCredentials,
    for type: PKPushType,
  ) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType,
  ) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void,
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let data = MunawwaraVoipPayloadMapper.callData(from: payload.dictionaryPayload)
    CallSignalingBridge.persistPendingCall(from: payload.dictionaryPayload)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data,
      fromPushKit: true,
    ) {
      completion()
    }
  }

  // MARK: - Missed call notifications

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void,
  ) {
    CallkitNotificationManager.shared.userNotificationCenter(
      center,
      willPresent: notification,
      withCompletionHandler: completionHandler,
    )
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void,
  ) {
    if response.actionIdentifier == CallkitNotificationManager.CALLBACK_ACTION {
      let data = response.notification.request.content.userInfo as? [String: Any]
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.sendCallbackEvent(data)
    }
    completionHandler()
  }

  // MARK: - Call history / Recents

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void,
  ) -> Bool {
    guard let handleObj = userActivity.handle,
      let isVideo = userActivity.isVideo else {
      return false
    }

    let objData = handleObj.getDecryptHandle()
    let nameCaller = objData["nameCaller"] as? String ?? ""
    let handle = objData["handle"] as? String ?? ""
    let data = flutter_callkit_incoming.Data(
      id: UUID().uuidString,
      nameCaller: nameCaller,
      handle: handle,
      type: isVideo ? 1 : 0,
    )
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.startCall(data, fromPushKit: true)
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler,
    )
  }

  // MARK: - CallkitIncomingAppDelegate (Dart handles signaling)

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    pendingDeclineNotify?.cancel()
    pendingDeclineNotify = nil
    lastAcceptAt = Date()
    CallSignalingBridge.postAnswer(for: call)
    CallKitAudioChannelHandler.notifyCallAccepted(call: call)
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    pendingDeclineNotify?.cancel()
    // Guard: if onAccept fired within the last second, this is a race-condition
    // decline from the banner dismissal — skip it entirely.
    if let accepted = lastAcceptAt, Date().timeIntervalSince(accepted) < 1.0 {
      NSLog("[AppDelegate] onDecline ignored — onAccept fired \(Date().timeIntervalSince(accepted))s ago")
      action.fulfill()
      return
    }
    // Defer BOTH the HTTP POST and the Dart notification inside the work item.
    // onAccept cancels pendingDeclineNotify, which now also cancels the HTTP call,
    // preventing a spurious decline from reaching the server on a banner-tap race.
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      // Re-check in case onAccept fired while we were waiting.
      if let accepted = self.lastAcceptAt, Date().timeIntervalSince(accepted) < 1.0 {
        NSLog("[AppDelegate] Deferred decline cancelled — onAccept fired during grace")
        return
      }
      CallSignalingBridge.postDecline(for: call, noAnswer: false)
      CallKitAudioChannelHandler.notifyCallDeclined(call: call, noAnswer: false)
    }
    pendingDeclineNotify = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    CallSignalingBridge.postEnd(for: call)
    CallKitAudioChannelHandler.notifyCallEnded(call: call)
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    CallSignalingBridge.postDecline(for: call, noAnswer: true)
    CallKitAudioChannelHandler.notifyCallDeclined(call: call, noAnswer: true)
  }

  func onDeclineIncomingWithoutManagedCall(extra: [String: Any]?) {
    CallSignalingBridge.postDecline(extra: extra, noAnswer: false)
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    CallKitAudioChannelHandler.notifyAudioSessionActivated()
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    CallKitAudioChannelHandler.notifyAudioSessionDeactivated()
  }
}

/// Maps Munawwara backend / FCM call fields to flutter_callkit_incoming.Data.
enum MunawwaraVoipPayloadMapper {
  static func callData(from payload: [AnyHashable: Any]) -> flutter_callkit_incoming.Data {
    let dict = payload as? [String: Any] ?? [:]

    let callerId = stringValue(dict, keys: ["callerId", "caller_id"]) ?? ""
    let callerName = stringValue(dict, keys: ["callerName", "caller_name", "nameCaller"])
      ?? "Unknown"
    let displayName = stringValue(dict, keys: ["displayName", "callerDisplayName"])
    let callerRole = stringValue(dict, keys: ["callerRole", "caller_role"]) ?? "Voice Call"
    let channelName = stringValue(dict, keys: ["channelName", "channel_name"]) ?? ""
    let callRecordId = stringValue(dict, keys: ["callRecordId", "call_record_id", "id"])
    let callerGender = stringValue(dict, keys: ["callerGender", "caller_gender"])
    let callerProfilePicture = stringValue(
      dict,
      keys: ["callerProfilePicture", "caller_profile_picture"],
    )

    // CallKit requires a RFC-4122 UUID for `id`. MongoDB ObjectIds and test ids
    // like "test_123" are not valid — always generate a UUID and keep the server
    // record id in `extra.callRecordId` (same as the Flutter CallKitService path).
    let callKitId: String
    if let callRecordId, !callRecordId.isEmpty, UUID(uuidString: callRecordId) != nil {
      callKitId = callRecordId
    } else {
      callKitId = UUID().uuidString
    }
    let nativeCallerLine = (displayName?.isEmpty == false) ? displayName! : callerName

    let data = flutter_callkit_incoming.Data(
      id: callKitId,
      nameCaller: nativeCallerLine,
      handle: callerRole,
      type: 0,
    )
    data.appName = "Munawwara Care"
    data.duration = 35000
    data.supportsVideo = false
    data.iconName = "CallKitIcon"
    data.maximumCallsPerCallGroup = 1
    data.configureAudioSession = false
    data.audioSessionMode = "voiceChat"
    data.audioSessionActive = false
    data.isShowMissedCallNotification = false

    var extra: [String: Any] = [
      "callerId": callerId,
      "callerName": nativeCallerLine,
      "peerCallerName": callerName,
      "callerRole": callerRole,
      "channelName": channelName,
      "platform": "ios",
    ]
    if let callRecordId, !callRecordId.isEmpty {
      extra["callRecordId"] = callRecordId
    }
    if let callerGender, !callerGender.isEmpty {
      extra["callerGender"] = callerGender
    }
    if let callerProfilePicture, !callerProfilePicture.isEmpty {
      extra["callerProfilePicture"] = callerProfilePicture
    }
    data.extra = extra as NSDictionary

    return data
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
}
