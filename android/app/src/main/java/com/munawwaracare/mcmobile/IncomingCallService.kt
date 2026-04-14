package com.munawwaracare.mcmobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.telecom.DisconnectCause
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import kotlinx.coroutines.*
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Foreground service that manages incoming calls via Core-Telecom.
 *
 * Key design: each incoming call gets a FRESH coroutine scope so that
 * previous call cleanup never breaks subsequent calls.
 */
class IncomingCallService : Service() {

    companion object {
        private const val TAG = "IncomingCallService"
        private const val CHANNEL_ID = "incoming_call_service"
        private const val NOTIFICATION_ID = 9999

        const val ACTION_INCOMING = "com.munawwaracare.mcmobile.ACTION_INCOMING_CALL"
        const val ACTION_DECLINE = "com.munawwaracare.mcmobile.ACTION_DECLINE_CALL"
        const val ACTION_ACCEPT = "com.munawwaracare.mcmobile.ACTION_ACCEPT_CALL"
        const val ACTION_END = "com.munawwaracare.mcmobile.ACTION_END_CALL"

        const val EXTRA_CALLER_ID = "callerId"
        const val EXTRA_CALLER_NAME = "callerName"
        const val EXTRA_CHANNEL_NAME = "channelName"

        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_API_BASE_URL = "flutter.api_base_url"
        private const val FALLBACK_URL =
            "https://mcbackendapp-199324116788.europe-west8.run.app/api"
    }

    // Each call gets a fresh scope — never reuse a cancelled scope
    private var callScope: CoroutineScope? = null
    private var callControlScope: CallControlScope? = null
    private var currentCallerId: String? = null
    private var callJob: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.i(TAG, "📞 onStartCommand action=$action")

        when (action) {
            ACTION_INCOMING -> handleIncoming(intent)
            ACTION_DECLINE -> handleDecline()
            ACTION_ACCEPT -> handleAccept()
            ACTION_END -> handleEnd()
        }
        return START_NOT_STICKY
    }

    private fun handleIncoming(intent: Intent) {
        // Cancel any previous call that wasn't cleaned up
        callJob?.cancel()
        callScope?.cancel()
        callControlScope = null

        val callerId = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"

        if (callerId.isBlank()) {
            Log.w(TAG, "📞 No callerId in intent, reading from SharedPreferences")
            val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            currentCallerId = prefs.getString("flutter.pending_call_caller_id", null) ?: ""
        } else {
            currentCallerId = callerId
        }

        if (currentCallerId.isNullOrBlank()) {
            Log.e(TAG, "📞 No callerId available at all — stopping")
            stopSelf()
            return
        }

        Log.i(TAG, "📞 Starting foreground for call from $callerName (id=$currentCallerId)")

        // Start as foreground service immediately (must happen within 5 seconds)
        startForeground(NOTIFICATION_ID, buildForegroundNotification(callerName))

        // Create a FRESH coroutine scope for this call
        val freshScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        callScope = freshScope

        // Register with Core-Telecom
        callJob = freshScope.launch {
            try {
                val callsManager = CallsManager(this@IncomingCallService)
                try {
                    callsManager.registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)
                } catch (e: Exception) {
                    // Already registered — that's fine
                    Log.w(TAG, "📞 registerAppWithTelecom: ${e.message}")
                }

                val attributes = CallAttributesCompat(
                    displayName = callerName,
                    address = Uri.parse("munawwara:$currentCallerId"),
                    direction = CallAttributesCompat.DIRECTION_INCOMING,
                    callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL
                )

                callsManager.addCall(
                    attributes,
                    onAnswer = { callType ->
                        Log.i(TAG, "📞 Core-Telecom onAnswer")
                    },
                    onDisconnect = { disconnectCause ->
                        Log.i(TAG, "📞 Core-Telecom onDisconnect: ${disconnectCause.reason}")
                        val cid = currentCallerId
                        if (!cid.isNullOrBlank()) {
                            sendDeclineHttp(cid)
                        }
                        resetCallState()
                    },
                    onSetActive = {
                        Log.i(TAG, "📞 Core-Telecom onSetActive")
                    },
                    onSetInactive = {
                        Log.i(TAG, "📞 Core-Telecom onSetInactive")
                    }
                ) {
                    callControlScope = this
                    Log.i(TAG, "📞 Core-Telecom call registered successfully")
                }

                // addCall returned — call is over
                Log.i(TAG, "📞 Core-Telecom addCall completed")
                resetCallState()
            } catch (e: Exception) {
                Log.e(TAG, "📞 Core-Telecom error: ${e.message}", e)
                // Core-Telecom failed — service still stays alive for HTTP decline
            }
        }
    }

    private fun handleDecline() {
        Log.i(TAG, "📞 handleDecline called")
        val cid = currentCallerId
        if (!cid.isNullOrBlank()) {
            // Use the call's scope if available, otherwise create a temporary one
            val scope = callScope ?: CoroutineScope(Dispatchers.IO)

            // 1. HTTP POST to backend — this is the critical part
            scope.launch {
                sendDeclineHttp(cid)
            }
            // 2. Disconnect from Core-Telecom
            scope.launch {
                try {
                    callControlScope?.disconnect(DisconnectCause(DisconnectCause.REJECTED))
                } catch (e: Exception) {
                    Log.w(TAG, "📞 Core-Telecom disconnect failed: ${e.message}")
                }
            }
        }
        // Give HTTP time to complete, then reset
        val scope = callScope ?: CoroutineScope(Dispatchers.IO)
        scope.launch {
            delay(3000)
            resetCallState()
        }
    }

    private fun handleAccept() {
        Log.i(TAG, "📞 handleAccept called")
        val scope = callScope ?: return
        scope.launch {
            try {
                callControlScope?.answer(CallAttributesCompat.CALL_TYPE_AUDIO_CALL)
            } catch (e: Exception) {
                Log.w(TAG, "📞 Core-Telecom answer failed: ${e.message}")
            }
        }
    }

    private fun handleEnd() {
        Log.i(TAG, "📞 handleEnd called")
        val scope = callScope ?: CoroutineScope(Dispatchers.IO)
        scope.launch {
            try {
                callControlScope?.disconnect(DisconnectCause(DisconnectCause.LOCAL))
            } catch (e: Exception) {
                Log.w(TAG, "📞 Core-Telecom end failed: ${e.message}")
            }
            resetCallState()
        }
    }

    /**
     * Reset call state WITHOUT stopping the service.
     * This allows the service to handle subsequent incoming calls.
     */
    private fun resetCallState() {
        Log.i(TAG, "📞 Resetting call state (service stays alive)")
        callJob?.cancel()
        callJob = null
        callControlScope = null
        currentCallerId = null
        // Remove foreground notification but DON'T stop the service
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun sendDeclineHttp(callerId: String) {
        val baseUrl = resolveBaseUrl()
        Log.i(TAG, "📞 Sending decline HTTP for callerId=$callerId to $baseUrl")

        repeat(3) { attempt ->
            try {
                val url = URL("$baseUrl/call-history/decline")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 10000
                conn.readTimeout = 10000

                val body = """{"callerId":"$callerId"}"""
                OutputStreamWriter(conn.outputStream, "UTF-8").use { it.write(body) }

                val code = conn.responseCode
                conn.disconnect()

                Log.i(TAG, "📞 Decline HTTP response: $code (attempt $attempt)")
                if (code in 200..299) return // Success!
            } catch (e: Exception) {
                Log.e(TAG, "📞 Decline HTTP attempt $attempt failed: ${e.message}")
                if (attempt < 2) Thread.sleep(2000)
            }
        }
        Log.e(TAG, "📞 All decline HTTP attempts failed")
    }

    private fun resolveBaseUrl(): String {
        return try {
            val prefs: SharedPreferences =
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            prefs.getString(KEY_API_BASE_URL, null)
                ?.takeIf { it.isNotBlank() } ?: FALLBACK_URL
        } catch (_: Exception) {
            FALLBACK_URL
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Active Call",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when a call is being managed"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(callerName: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Incoming Call")
            .setContentText("Call from $callerName")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        callScope?.cancel()
        callScope = null
        Log.i(TAG, "📞 IncomingCallService destroyed")
    }
}
