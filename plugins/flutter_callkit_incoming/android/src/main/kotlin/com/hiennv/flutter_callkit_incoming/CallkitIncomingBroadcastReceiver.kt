package com.hiennv.flutter_callkit_incoming

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.Log
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class CallkitIncomingBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallkitIncomingReceiver"
        var silenceEvents = false

        fun getIntent(context: Context, action: String, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                this.action = "${context.packageName}.${action}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentIncoming(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_INCOMING}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentStart(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_START}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentAccept(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_ACCEPT}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentDecline(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_DECLINE}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentEnded(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_ENDED}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentTimeout(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_TIMEOUT}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentCallback(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_CALLBACK}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentHeldByCell(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_HELD}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentUnHeldByCell(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_UNHELD}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }

        fun getIntentConnected(context: Context, data: Bundle?) =
            Intent(context, CallkitIncomingBroadcastReceiver::class.java).apply {
                action = "${context.packageName}.${CallkitConstants.ACTION_CALL_CONNECTED}"
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }
    }

    // Get notification manager dynamically to handle plugin lifecycle properly
    private fun getCallkitNotificationManager(): CallkitNotificationManager? {
        return FlutterCallkitIncomingPlugin.getInstance()?.getCallkitNotificationManager()
    }


    @SuppressLint("MissingPermission")
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val data = intent.extras?.getBundle(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA) ?: return
        when (action) {
            "${context.packageName}.${CallkitConstants.ACTION_CALL_INCOMING}" -> {
                try {
                    getCallkitNotificationManager()?.showIncomingNotification(data)
                    sendEventFlutter(CallkitConstants.ACTION_CALL_INCOMING, data)
                    addCall(context, Data.fromBundle(data))
                    // ── Start IncomingCallService (Core-Telecom) ──
                    startCallService(context, "com.munawwaracare.mcmobile.ACTION_INCOMING_CALL", data)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_START}" -> {
                try {
                    // start service and show ongoing call when call is accepted
                    CallkitNotificationService.startServiceWithAction(
                        context,
                        CallkitConstants.ACTION_CALL_START,
                        data
                    )
                    sendEventFlutter(CallkitConstants.ACTION_CALL_START, data)
                    addCall(context, Data.fromBundle(data), true)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_ACCEPT}" -> {
                try {
                    // Log.d(TAG, "[CALLKIT] 📱 ACTION_CALL_ACCEPT")
                    FlutterCallkitIncomingPlugin.notifyEventCallbacks(CallkitEventCallback.CallEvent.ACCEPT, data)
                    // start service and show ongoing call when call is accepted
                    CallkitNotificationService.startServiceWithAction(
                        context,
                        CallkitConstants.ACTION_CALL_ACCEPT,
                        data
                    )
                    sendEventFlutter(CallkitConstants.ACTION_CALL_ACCEPT, data)
                    addCall(context, Data.fromBundle(data), true)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_DECLINE}" -> {
                try {
                    // Log.d(TAG, "[CALLKIT] 📱 ACTION_CALL_DECLINE")           
                    // Notify native decline callbacks
                    FlutterCallkitIncomingPlugin.notifyEventCallbacks(CallkitEventCallback.CallEvent.DECLINE, data)
                    // clear notification
                    getCallkitNotificationManager()?.clearIncomingNotification(data, false)
                    sendEventFlutter(CallkitConstants.ACTION_CALL_DECLINE, data)
                    removeCall(context, Data.fromBundle(data))
                    // ── Signal IncomingCallService to fire HTTP decline ──
                    startCallService(context, "com.munawwaracare.mcmobile.ACTION_DECLINE_CALL", data)
                    // Also fire HTTP directly as a fallback (with goAsync)
                    sendDeclineToBackend(context, data)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_ENDED}" -> {
                try {
                    // clear notification and stop service
                    getCallkitNotificationManager()?.clearIncomingNotification(data, false)
                    CallkitNotificationService.stopService(context)
                    sendEventFlutter(CallkitConstants.ACTION_CALL_ENDED, data)
                    removeCall(context, Data.fromBundle(data))
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_TIMEOUT}" -> {
                try {
                    // clear notification and show miss notification
                    val notificationManager = getCallkitNotificationManager()
                    notificationManager?.clearIncomingNotification(data, false)
                    notificationManager?.showMissCallNotification(data)
                    sendEventFlutter(CallkitConstants.ACTION_CALL_TIMEOUT, data)
                    removeCall(context, Data.fromBundle(data))
                    // ── Signal IncomingCallService to fire HTTP decline ──
                    startCallService(context, "com.munawwaracare.mcmobile.ACTION_DECLINE_CALL", data)
                    // Also fire HTTP directly as a fallback
                    sendDeclineToBackend(context, data)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_CONNECTED}" -> {
                try {
                    // update notification on going connected
                    getCallkitNotificationManager()?.showOngoingCallNotification(data, true)
                    sendEventFlutter(CallkitConstants.ACTION_CALL_CONNECTED, data)
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }

            "${context.packageName}.${CallkitConstants.ACTION_CALL_CALLBACK}" -> {
                try {
                    getCallkitNotificationManager()?.clearMissCallNotification(data)
                    sendEventFlutter(CallkitConstants.ACTION_CALL_CALLBACK, data)
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                        val closeNotificationPanel = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
                        context.sendBroadcast(closeNotificationPanel)
                    }
                } catch (error: Exception) {
                    Log.e(TAG, null, error)
                }
            }
        }
    }

    private fun sendEventFlutter(event: String, data: Bundle) {
        if (silenceEvents) return

        val android = mapOf(
            "isCustomNotification" to data.getBoolean(
                CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_NOTIFICATION,
                false
            ),
            "isCustomSmallExNotification" to data.getBoolean(
                CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_SMALL_EX_NOTIFICATION,
                false
            ),
            "ringtonePath" to data.getString(CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH, ""),
            "backgroundColor" to data.getString(
                CallkitConstants.EXTRA_CALLKIT_BACKGROUND_COLOR,
                ""
            ),
            "backgroundUrl" to data.getString(CallkitConstants.EXTRA_CALLKIT_BACKGROUND_URL, ""),
            "actionColor" to data.getString(CallkitConstants.EXTRA_CALLKIT_ACTION_COLOR, ""),
            "textColor" to data.getString(CallkitConstants.EXTRA_CALLKIT_TEXT_COLOR, ""),
            "incomingCallNotificationChannelName" to data.getString(
                CallkitConstants.EXTRA_CALLKIT_INCOMING_CALL_NOTIFICATION_CHANNEL_NAME,
                ""
            ),
            "missedCallNotificationChannelName" to data.getString(
                CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_NOTIFICATION_CHANNEL_NAME,
                ""
            ),
            "isImportant" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_IS_IMPORTANT, true),
            "isBot" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_IS_BOT, false),
        )
        val missedCallNotification = mapOf(
            "id" to data.getInt(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_ID),
            "showNotification" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_SHOW),
            "count" to data.getInt(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_COUNT),
            "subtitle" to data.getString(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_SUBTITLE),
            "callbackText" to data.getString(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_CALLBACK_TEXT),
            "isShowCallback" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_MISSED_CALL_CALLBACK_SHOW),
        )
        val callingNotification = mapOf(
            "id" to data.getString(CallkitConstants.EXTRA_CALLKIT_CALLING_ID),
            "showNotification" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW),
            "subtitle" to data.getString(CallkitConstants.EXTRA_CALLKIT_CALLING_SUBTITLE),
            "callbackText" to data.getString(CallkitConstants.EXTRA_CALLKIT_CALLING_HANG_UP_TEXT),
            "isShowCallback" to data.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_HANG_UP_SHOW),
        )
        val forwardData = mapOf(
            "id" to data.getString(CallkitConstants.EXTRA_CALLKIT_ID, ""),
            "nameCaller" to data.getString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, ""),
            "avatar" to data.getString(CallkitConstants.EXTRA_CALLKIT_AVATAR, ""),
            "number" to data.getString(CallkitConstants.EXTRA_CALLKIT_HANDLE, ""),
            "type" to data.getInt(CallkitConstants.EXTRA_CALLKIT_TYPE, 0),
            "duration" to data.getLong(CallkitConstants.EXTRA_CALLKIT_DURATION, 0L),
            "textAccept" to data.getString(CallkitConstants.EXTRA_CALLKIT_TEXT_ACCEPT, ""),
            "textDecline" to data.getString(CallkitConstants.EXTRA_CALLKIT_TEXT_DECLINE, ""),
            "extra" to data.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA),
            "missedCallNotification" to missedCallNotification,
            "callingNotification" to callingNotification,
            "android" to android
        )
        FlutterCallkitIncomingPlugin.sendEvent(event, forwardData)
    }
    /**
     * Sends an Intent to the IncomingCallService in the main app.
     * On INCOMING: starts the foreground service.
     * On DECLINE/ACCEPT/END: delivers the intent to the running service.
     */
    @Suppress("UNCHECKED_CAST")
    private fun startCallService(context: Context, action: String, data: Bundle) {
        try {
            val serviceIntent = Intent()
            serviceIntent.component = ComponentName(
                context.packageName,
                "${context.packageName}.IncomingCallService"
            )
            serviceIntent.action = action

            // Extract callerId and callerName from the Bundle
            try {
                val extraMap = data.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA)
                    as? HashMap<*, *>
                serviceIntent.putExtra("callerId", extraMap?.get("callerId")?.toString() ?: "")
                serviceIntent.putExtra("callerName", extraMap?.get("callerName")?.toString() ?: "")
                serviceIntent.putExtra("channelName", extraMap?.get("channelName")?.toString() ?: "")
            } catch (_: Exception) {
                // Fall back to SharedPreferences
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                serviceIntent.putExtra("callerId", prefs.getString("flutter.pending_call_caller_id", "") ?: "")
            }

            if (action.contains("INCOMING")) {
                // Starting fresh — must use startForegroundService
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } else {
                // Service should already be running
                try {
                    context.startService(serviceIntent)
                } catch (e: Exception) {
                    // Service not running — try foreground start as fallback
                    Log.w(TAG, "startService failed, trying startForegroundService: ${e.message}")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    }
                }
            }
            Log.i(TAG, "📞 startCallService: $action sent")
        } catch (e: Exception) {
            Log.e(TAG, "📞 startCallService failed: ${e.message}")
        }
    }

    /**
     * Fires an HTTP POST to /call-history/decline (fallback path).
     * Uses goAsync() to keep the BroadcastReceiver alive for the HTTP thread.
     */
    @Suppress("UNCHECKED_CAST")
    private fun sendDeclineToBackend(context: Context, data: Bundle) {
        val pendingResult = goAsync() // Keep receiver alive for background work
        thread(name = "CallDeclineHTTP") {
            try {
                // 1. Try to get callerId from the Bundle's EXTRA_CALLKIT_EXTRA HashMap
                var callerId = ""
                try {
                    val extraMap = data.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA)
                        as? HashMap<*, *>
                    callerId = extraMap?.get("callerId")?.toString() ?: ""
                } catch (_: Exception) {}

                // 2. Fall back to SharedPreferences written by Flutter when the call FCM arrived
                if (callerId.isBlank()) {
                    val prefs: SharedPreferences = context.getSharedPreferences(
                        "FlutterSharedPreferences", Context.MODE_PRIVATE
                    )
                    callerId = prefs.getString("flutter.pending_call_caller_id", null) ?: ""
                }

                if (callerId.isBlank()) {
                    Log.w(TAG, "📵 sendDeclineToBackend: callerId not found")
                    return@thread
                }

                // 3. Resolve base URL
                val baseUrl = try {
                    val prefs: SharedPreferences = context.getSharedPreferences(
                        "FlutterSharedPreferences", Context.MODE_PRIVATE
                    )
                    prefs.getString("flutter.api_base_url", null)
                        ?.takeIf { it.isNotBlank() }
                        ?: "https://mcbackendapp-199324116788.europe-west8.run.app/api"
                } catch (_: Exception) {
                    "https://mcbackendapp-199324116788.europe-west8.run.app/api"
                }

                // 4. Send HTTP POST with retry
                Log.i(TAG, "📵 Declining callerId=$callerId to $baseUrl")
                repeat(2) { attempt ->
                    try {
                        val url = URL("$baseUrl/call-history/decline")
                        val conn = url.openConnection() as HttpURLConnection
                        conn.requestMethod = "POST"
                        conn.setRequestProperty("Content-Type", "application/json")
                        conn.doOutput = true
                        conn.connectTimeout = 8000
                        conn.readTimeout = 8000
                        OutputStreamWriter(conn.outputStream, "UTF-8").use {
                            it.write("""{"callerId":"$callerId"}""")
                        }
                        val code = conn.responseCode
                        conn.disconnect()
                        Log.i(TAG, "📵 Decline HTTP $code (attempt $attempt)")
                        if (code in 200..299) return@thread
                    } catch (e: Exception) {
                        Log.e(TAG, "📵 Decline HTTP attempt $attempt failed: ${e.message}")
                        if (attempt == 0) Thread.sleep(1500)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "📵 sendDeclineToBackend error: ${e.message}")
            } finally {
                pendingResult.finish() // Release the BroadcastReceiver
            }
        }
    }
}

