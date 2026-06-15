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

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    setupVoipPushRegistryIfEntitled()
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "dev.flutter.background.refresh"
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// PushKit requires `aps-environment` (paid Apple Developer + Push capability).
  /// Free Personal Team builds have no push entitlement — skip VoIP registration.
  private func hasPushEntitlement() -> Bool {
    guard let provisionURL = Bundle.main.url(
      forResource: "embedded",
      withExtension: "mobileprovision",
    ),
      let data = try? Data(contentsOf: provisionURL),
      let raw = String(data: data, encoding: .isoLatin1)
    else {
      return false
    }
    return raw.contains("<key>aps-environment</key>")
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
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    CallKitAudioChannelHandler.notifyCallDeclined(call: call, noAnswer: false)
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    CallKitAudioChannelHandler.notifyCallDeclined(call: call, noAnswer: true)
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

    let callId = (callRecordId?.isEmpty == false) ? callRecordId! : UUID().uuidString
    let nativeCallerLine = (displayName?.isEmpty == false) ? displayName! : callerName

    let data = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: nativeCallerLine,
      handle: callerRole,
      type: 0,
    )
    data.appName = "Munawwara Care"
    data.duration = 35000
    data.supportsVideo = false
    data.iconName = "AppIcon"
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
