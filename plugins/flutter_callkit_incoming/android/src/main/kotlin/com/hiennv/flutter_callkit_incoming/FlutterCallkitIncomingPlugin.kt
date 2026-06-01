package com.hiennv.flutter_callkit_incoming

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.hiennv.flutter_callkit_incoming.Utils.Companion.reapCollection
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.lang.ref.WeakReference


/** FlutterCallkitIncomingPlugin */
class FlutterCallkitIncomingPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {

        const val EXTRA_CALLKIT_CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"

        @SuppressLint("StaticFieldLeak")
        private lateinit var instance: FlutterCallkitIncomingPlugin

        fun getInstance(): FlutterCallkitIncomingPlugin? {
            if (hasInstance()) {
                return instance
            }
            return null
        }

        fun hasInstance(): Boolean {
            return ::instance.isInitialized
        }

        private val methodChannels = mutableMapOf<BinaryMessenger, MethodChannel>()
        private val eventChannels = mutableMapOf<BinaryMessenger, EventChannel>()
        private val eventHandlers = mutableListOf<WeakReference<EventCallbackHandler>>()
        private val eventCallbacks = mutableListOf<WeakReference<CallkitEventCallback>>()

        fun sendEvent(event: String, body: Map<String, Any?>) {
            eventHandlers.reapCollection().forEach {
                it.get()?.send(event, body)
            }
        }

        /**
         * Munawwara: plugin ringtone/tray/FGS only — does not start app telecom service.
         */
        fun dismissPluginIncomingUi(context: Context?) {
            if (context == null) {
                Log.w("FlutterCallkitIncoming", "dismissPlugin skipped — null context")
                return
            }
            try {
                val sound = CallkitSoundPlayerManager(context)
                sound.stop()
                sound.destroy()
            } catch (e: Exception) {
                Log.w("FlutterCallkitIncoming", "dismissPlugin sound stop: ${e.message}")
            }
            try {
                val flutterPrefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE,
                )
                val uuid = flutterPrefs.getString("flutter.pending_call_uuid", null)
                if (!uuid.isNullOrEmpty()) {
                    val bundle = android.os.Bundle().apply {
                        putString(CallkitConstants.EXTRA_CALLKIT_ID, uuid)
                        putString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, "")
                        putString(CallkitConstants.EXTRA_CALLKIT_HANDLE, "")
                    }
                    getInstance()?.getCallkitNotificationManager()
                        ?.clearIncomingNotification(bundle, false)
                        ?: CallkitNotificationManager(context, null)
                            .clearIncomingNotification(bundle, false)
                }
            } catch (e: Exception) {
                Log.w("FlutterCallkitIncoming", "dismissPlugin notification: ${e.message}")
            }
            try {
                CallkitNotificationService.stopService(context)
            } catch (e: Exception) {
                Log.w("FlutterCallkitIncoming", "dismissPlugin FGS stop: ${e.message}")
            }
            removeAllCalls(context)
        }

        /** @deprecated Use [dismissPluginIncomingUi]; kept for older call sites. */
        fun forceDismissAllIncomingCallUi(context: Context?) {
            dismissPluginIncomingUi(context)
        }

        public fun sendEventCustom(event: String, body: Map<String, Any>) {
            eventHandlers.reapCollection().forEach {
                it.get()?.send(event, body)
            }
        }

        /**
         * Register a callback to receive call events (accept/decline) natively.
         * This allows other plugins/services to handle call events
         * even when Flutter engine is terminated.
         */
        fun registerEventCallback(callback: CallkitEventCallback) {
            eventCallbacks.add(WeakReference(callback))
        }

        /**
         * Unregister an event callback.
         */
        fun unregisterEventCallback(callback: CallkitEventCallback) {
            eventCallbacks.removeAll { it.get() == callback || it.get() == null }
        }

        /**
         * Notify all registered event callbacks.
         * Called internally when a call event occurs.
         */
        internal fun notifyEventCallbacks(event: CallkitEventCallback.CallEvent, callData: android.os.Bundle) {
            eventCallbacks.reapCollection().forEach { callbackRef ->
                callbackRef.get()?.onCallEvent(event, callData)
            }
        }


        fun sharePluginWithRegister(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
            initSharedInstance(
                flutterPluginBinding.applicationContext,
                flutterPluginBinding.binaryMessenger
            )
        }

        fun initSharedInstance(context: Context, binaryMessenger: BinaryMessenger) {
            if (!::instance.isInitialized) {
                instance = FlutterCallkitIncomingPlugin()
                instance.callkitSoundPlayerManager = CallkitSoundPlayerManager(context)
                instance.callkitNotificationManager = CallkitNotificationManager(context, instance.callkitSoundPlayerManager)
                instance.context = context
            } else {
                // Re-initialize managers if they were destroyed but instance still exists
                if (instance.callkitNotificationManager == null) {
                    instance.callkitSoundPlayerManager = CallkitSoundPlayerManager(context)
                    instance.callkitNotificationManager = CallkitNotificationManager(context, instance.callkitSoundPlayerManager)
                }
            }

            val channel = MethodChannel(binaryMessenger, "flutter_callkit_incoming")
            methodChannels[binaryMessenger] = channel
            channel.setMethodCallHandler(instance)

            val events = EventChannel(binaryMessenger, "flutter_callkit_incoming_events")
            eventChannels[binaryMessenger] = events
            val handler = EventCallbackHandler()
            eventHandlers.add(WeakReference(handler))
            events.setStreamHandler(handler)

        }

    }

    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private var activity: Activity? = null
    private var context: Context? = null
    private var callkitNotificationManager: CallkitNotificationManager? = null
    private var callkitSoundPlayerManager: CallkitSoundPlayerManager? = null

    fun getCallkitNotificationManager(): CallkitNotificationManager? {
        return callkitNotificationManager
    }

    fun getCallkitSoundPlayerManager(): CallkitSoundPlayerManager? {
        return callkitSoundPlayerManager
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        sharePluginWithRegister(flutterPluginBinding)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            InAppCallManager(flutterPluginBinding.applicationContext).registerPhoneAccount()
        }
    }

    public fun showIncomingNotification(data: Data) {
        data.from = "notification"
        //send BroadcastReceiver
        context?.sendBroadcast(
            CallkitIncomingBroadcastReceiver.getIntentIncoming(
                requireNotNull(context),
                data.toBundle()
            )
        )
    }

    public fun showMissCallNotification(data: Data) {
        callkitNotificationManager?.showMissCallNotification(data.toBundle())
    }

    public fun startCall(data: Data) {
        context?.sendBroadcast(
            CallkitIncomingBroadcastReceiver.getIntentStart(
                requireNotNull(context),
                data.toBundle()
            )
        )
    }

    public fun endCall(data: Data) {
        context?.sendBroadcast(
            CallkitIncomingBroadcastReceiver.getIntentEnded(
                requireNotNull(context),
                data.toBundle()
            )
        )
    }

    public fun endAllCalls() {
        val calls = getDataActiveCalls(context)
        calls.forEach {
            context?.sendBroadcast(
                CallkitIncomingBroadcastReceiver.getIntentEnded(
                    requireNotNull(context),
                    it.toBundle()
                )
            )
        }
        removeAllCalls(context)
        dismissPluginIncomingUi(context)
    }

    public fun sendEventCustom(body: Map<String, Any>) {
        eventHandlers.reapCollection().forEach {
            it.get()?.send(CallkitConstants.ACTION_CALL_CUSTOM, body)
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        try {
            when (call.method) {
                "showCallkitIncoming" -> {
                    val data = Data(call.arguments() ?: HashMap())
                    data.from = "notification"
                    //send BroadcastReceiver
                    context?.sendBroadcast(
                        CallkitIncomingBroadcastReceiver.getIntentIncoming(
                            requireNotNull(context),
                            data.toBundle()
                        )
                    )

                    result.success(true)
                }

                "showCallkitIncomingSilently" -> {
                    val data = Data(call.arguments() ?: HashMap())
                    data.from = "notification"

                    result.success(true)
                }

                "showMissCallNotification" -> {
                    val data = Data(call.arguments() ?: HashMap())
                    data.from = "notification"
                    callkitNotificationManager?.showMissCallNotification(data.toBundle())
                    result.success(true)
                }

                "startCall" -> {
                    val data = Data(call.arguments() ?: HashMap())
                    context?.sendBroadcast(
                        CallkitIncomingBroadcastReceiver.getIntentStart(
                            requireNotNull(context),
                            data.toBundle()
                        )
                    )

                    result.success(true)
                }

                "muteCall" -> {
                    val map = buildMap {
                        val args = call.arguments
                        if (args is Map<*, *>) {
                            putAll(args as Map<String, Any>)
                        }
                    }
                    sendEvent(CallkitConstants.ACTION_CALL_TOGGLE_MUTE, map)

                    result.success(true)
                }

                "holdCall" -> {
                    val map = buildMap {
                        val args = call.arguments
                        if (args is Map<*, *>) {
                            putAll(args as Map<String, Any>)
                        }
                    }
                    sendEvent(CallkitConstants.ACTION_CALL_TOGGLE_HOLD, map)

                    result.success(true)
                }

                "isMuted" -> {
                    result.success(true)
                }

                "endCall" -> {
                    val calls = getDataActiveCalls(context)
                    val data = Data(call.arguments() ?: HashMap())
                    val currentCall = calls.firstOrNull { it.id == data.id }
                    if (currentCall != null && context != null) {
                        if(currentCall.isAccepted) {
                            context?.sendBroadcast(
                                CallkitIncomingBroadcastReceiver.getIntentEnded(
                                    requireNotNull(context),
                                    currentCall.toBundle()
                                )
                            )
                        }else {
                            context?.sendBroadcast(
                                CallkitIncomingBroadcastReceiver.getIntentDecline(
                                    requireNotNull(context),
                                    currentCall.toBundle()
                                )
                            )
                        }
                    } else if (context != null && data.id.isNotEmpty()) {
                        // No ACTIVE_CALLS match (e.g. accepted only from Flutter / prefs cleared).
                        // Still cancel incoming + ongoing notifications and stop foreground service.
                        getCallkitNotificationManager()?.clearIncomingNotification(data.toBundle(), false)
                        CallkitNotificationService.stopService(requireNotNull(context))
                        removeCall(context, data)
                    }
                    result.success(true)
                }

                "callConnected" -> {
                    val calls = getDataActiveCalls(context)
                    val data = Data(call.arguments() ?: HashMap())
                    val currentCall = calls.firstOrNull { it.id == data.id }
                    if (currentCall != null && context != null) {
                        // Flutter accepted in-app: native never got ACTION_CALL_ACCEPT — fix
                        // isAccepted so endCall routes to ENDED and tears down ongoing FGS.
                        addCall(requireNotNull(context), currentCall, true)
                        context?.sendBroadcast(
                            CallkitIncomingBroadcastReceiver.getIntentConnected(
                                requireNotNull(context),
                                currentCall.toBundle()
                            )
                        )
                    }
                    result.success(true)
                }

                "endAllCalls" -> {
                    val calls = getDataActiveCalls(context)
                    if (calls.isEmpty() && context != null) {
                        // Nothing in prefs but foreground / tray may still be visible.
                        CallkitNotificationService.stopService(requireNotNull(context))
                    } else {
                        calls.forEach {
                            if (it.isAccepted) {
                                context?.sendBroadcast(
                                    CallkitIncomingBroadcastReceiver.getIntentEnded(
                                        requireNotNull(context),
                                        it.toBundle()
                                    )
                                )
                            } else {
                                context?.sendBroadcast(
                                    CallkitIncomingBroadcastReceiver.getIntentDecline(
                                        requireNotNull(context),
                                        it.toBundle()
                                    )
                                )
                            }
                        }
                    }
                    removeAllCalls(context)
                    dismissPluginIncomingUi(context)
                    result.success(true)
                }

                "activeCalls" -> {
                    result.success(getDataActiveCallsForFlutter(context))
                }

                "getDevicePushTokenVoIP" -> {
                    result.success("")
                }

                "silenceEvents" -> {
                    val silence = call.arguments as? Boolean ?: false
                    CallkitIncomingBroadcastReceiver.silenceEvents = silence
                    result.success(true)
                }

                "requestNotificationPermission" -> {
                    val map = buildMap {
                        val args = call.arguments
                        if (args is Map<*, *>) {
                            putAll(args as Map<String, Any>)
                        }
                    }
                    callkitNotificationManager?.requestNotificationPermission(activity, map)
                    result.success(true)
                }

                "requestFullIntentPermission" -> {
                    callkitNotificationManager?.requestFullIntentPermission(activity)
                    result.success(true)
                }

                "canUseFullScreenIntent" -> {
                    result.success(callkitNotificationManager?.canUseFullScreenIntent() ?: true)
                }

                // EDIT - clear the incoming notification/ring (after accept/decline/timeout)
                "hideCallkitIncoming" -> {
                    val data = Data(call.arguments() ?: HashMap())
                    callkitSoundPlayerManager?.stop()
                    callkitNotificationManager?.clearIncomingNotification(data.toBundle(), false)
                    result.success(true)
                }

                "endNativeSubsystemOnly" -> {
                    result.success(true)
                }

                "setAudioRoute" -> {
                    result.success(true)
                }
            }
        } catch (error: Exception) {
            result.error("error", error.message, "")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannels.remove(binding.binaryMessenger)?.setMethodCallHandler(null)
        eventChannels.remove(binding.binaryMessenger)?.setStreamHandler(null)

        // Only destroy managers when all engine bindings are detached
        // This prevents issues when foreground services detach but main app is still running
        if (methodChannels.isEmpty() && eventChannels.isEmpty()) {
            instance.callkitSoundPlayerManager?.destroy()
            instance.callkitNotificationManager?.destroy()
            instance.callkitSoundPlayerManager = null
            instance.callkitNotificationManager = null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        instance.context = binding.activity.applicationContext
        instance.activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        instance.context = binding.activity.applicationContext
        instance.activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        // Keep applicationContext — FCM background isolate still needs native dismiss.
        instance.activity = null
    }

    class EventCallbackHandler : EventChannel.StreamHandler {

        private var eventSink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
            eventSink = sink
        }

        fun send(event: String, body: Map<String, Any?>) {
            val data = mapOf(
                "event" to event,
                "body" to body
            )
            Handler(Looper.getMainLooper()).post {
                eventSink?.success(data)
            }
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        instance.callkitNotificationManager?.onRequestPermissionsResult(
            instance.activity,
            requestCode,
            grantResults
        )
        return true
    }


}
