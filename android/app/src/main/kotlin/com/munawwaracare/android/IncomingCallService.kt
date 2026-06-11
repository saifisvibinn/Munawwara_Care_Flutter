package com.munawwaracare.android

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
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
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

        const val ACTION_INCOMING = "com.munawwaracare.android.ACTION_INCOMING_CALL"
        const val ACTION_DECLINE = "com.munawwaracare.android.ACTION_DECLINE_CALL"
        const val ACTION_ACCEPT = "com.munawwaracare.android.ACTION_ACCEPT_CALL"
        const val ACTION_END = "com.munawwaracare.android.ACTION_END_CALL"
        const val ACTION_REMOTE_CANCEL =
            "com.munawwaracare.android.ACTION_REMOTE_CANCEL"
        /**
         * Remove duplicate tray entry; CallKit already shows incoming/ongoing UI.
         * Must match `${applicationId}.ACTION_DISMISS_FG_NOTIFICATION` from CallkitIncomingBroadcastReceiver.
         */
        const val ACTION_DISMISS_FG_NOTIFICATION =
            "com.munawwaracare.android.ACTION_DISMISS_FG_NOTIFICATION"

        const val EXTRA_CALLER_ID = "callerId"
        const val EXTRA_CALLER_NAME = "callerName"
        const val EXTRA_CHANNEL_NAME = "channelName"

        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_API_BASE_URL = "flutter.api_base_url"
        private const val KEY_DECLINER_ID = "flutter.user_id"
        private const val KEY_CALL_RECORD_ID = "flutter.pending_call_record_id"
        /** Keep the process alive for 30s after a call ends so the next
         *  FCM/socket arrives instantly instead of hitting Android's cold-wake throttle. */
        private const val LINGER_MS = 30_000L
        fun resolveBaseUrl(context: Context): String {
            return try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.getString(KEY_API_BASE_URL, null)
                    ?.takeIf { it.isNotBlank() }
                    ?: BackendConfig.API_BASE_URL_FALLBACK.takeIf { it.isNotBlank() }
                    .orEmpty()
            } catch (_: Exception) {
                BackendConfig.API_BASE_URL_FALLBACK
            }
        }

        /** @return true=ringing/in-progress, false=ended, null=network/parse error */
        fun isCallerStillActiveOnServer(context: Context, callerId: String): Boolean? {
            if (callerId.isBlank()) return null
            val base = resolveBaseUrl(context).trimEnd('/')
            if (base.isBlank()) {
                Log.w(TAG, "📞 check-active skipped — API base URL not configured")
                return null
            }
            return try {
                val url = URL("$base/call-history/check-active?callerId=$callerId")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.connectTimeout = 8000
                conn.readTimeout = 8000
                val code = conn.responseCode
                val stream = if (code in 200..299) {
                    conn.inputStream
                } else {
                    conn.errorStream
                }
                val body = BufferedReader(InputStreamReader(stream, "UTF-8")).use {
                    it.readText()
                }
                conn.disconnect()
                if (code !in 200..299) {
                    Log.w(TAG, "📞 check-active HTTP $code")
                    return null
                }
                JSONObject(body).optBoolean("active", false)
            } catch (e: Exception) {
                Log.w(TAG, "📞 check-active failed: ${e.message}")
                null
            }
        }

        /**
         * Drops the duplicate FGS tray entry by id. Safe when the service process
         * died without [stopForeground] (MIUI zombie "Connecting…" notifications).
         * Only call from teardown paths — never during [handleIncoming].
         */
        fun cancelStaleForegroundTray(context: Context) {
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                nm.cancel(NOTIFICATION_ID)
                Log.i(TAG, "📞 cancelStaleForegroundTray id=$NOTIFICATION_ID")
            } catch (e: Exception) {
                Log.w(TAG, "📞 cancelStaleForegroundTray: ${e.message}")
            }
        }

        /** Core-Telecom teardown only — must not call plugin dismiss (no recursion). */
        fun requestTeardown(context: Context) {
            val intent = Intent(context, IncomingCallService::class.java).apply {
                action = ACTION_REMOTE_CANCEL
            }
            try {
                context.startService(intent)
                Log.i(TAG, "📞 requestTeardown → ACTION_REMOTE_CANCEL")
            } catch (e: Exception) {
                Log.w(TAG, "📞 requestTeardown failed: ${e.message}")
                cancelStaleForegroundTray(context)
            }
        }
    }

    // Each call gets a fresh scope — never reuse a cancelled scope
    private var callScope: CoroutineScope? = null
    private var callControlScope: CallControlScope? = null
    private var currentCallerId: String? = null
    private var callJob: Job? = null
    private var activePollJob: Job? = null
    private var callWasAnswered = false
    private var suppressDeclineHttpOnDisconnect = false
    private var isTearingDown = false
    private var lingerJob: Job? = null

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
            ACTION_DECLINE -> handleDecline(
                intent,
                intent?.getBooleanExtra("noAnswer", false) == true,
            )
            ACTION_ACCEPT -> handleAccept()
            ACTION_END -> handleEnd()
            ACTION_REMOTE_CANCEL -> handleRemoteCancel()
            ACTION_DISMISS_FG_NOTIFICATION -> dismissForegroundNotificationOnly()
        }
        return START_NOT_STICKY
    }

    private fun handleIncoming(intent: Intent) {
        // Cancel pending linger so the service stays alive for the new call
        lingerJob?.cancel()
        lingerJob = null
        // Tear down any previous Core-Telecom session before starting a new one.
        tearDownCoreTelecomSession(cancelScopeAfterDisconnect = true)
        callWasAnswered = false

        val resolvedCallerId = intent.getStringExtra(EXTRA_CALLER_ID) ?: ""
        val callerName = intent.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"

        if (resolvedCallerId.isBlank()) {
            Log.w(TAG, "📞 No callerId in intent, reading from SharedPreferences")
            val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            currentCallerId = prefs.getString("flutter.pending_call_caller_id", null) ?: ""
        } else {
            currentCallerId = resolvedCallerId
        }

        if (currentCallerId.isNullOrBlank()) {
            Log.e(TAG, "📞 No callerId available at all — stopping")
            stopSelf()
            return
        }

        Log.i(TAG, "📞 Starting foreground for call from $callerName (id=$currentCallerId)")

        startForeground(NOTIFICATION_ID, buildForegroundNotification(callerName))

        val freshScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        callScope = freshScope

        startActiveCallPolling(currentCallerId!!, freshScope)

        callJob = freshScope.launch {
            val callerId = currentCallerId!!
            var stillActive = isCallerStillActiveOnServer(
                this@IncomingCallService,
                callerId,
            )
            if (stillActive == null) {
                delay(400)
                stillActive = isCallerStillActiveOnServer(
                    this@IncomingCallService,
                    callerId,
                )
            }
            if (stillActive != true) {
                Log.w(
                    TAG,
                    "📞 check-active not active before Core-Telecom — aborting ring",
                )
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return@launch
            }

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
                        callWasAnswered = true
                    },
                    onDisconnect = { disconnectCause ->
                        Log.i(TAG, "📞 Core-Telecom onDisconnect: ${disconnectCause.reason}")
                        val cid = currentCallerId
                        if (
                            !suppressDeclineHttpOnDisconnect &&
                            !cid.isNullOrBlank() &&
                            !callWasAnswered
                        ) {
                            sendDeclineHttp(cid, noAnswer = false)
                        } else if (callWasAnswered) {
                            Log.i(TAG, "📞 Skip decline HTTP — call was already answered")
                        } else if (suppressDeclineHttpOnDisconnect) {
                            Log.i(TAG, "📞 Skip decline HTTP — remote cancel / teardown")
                        }
                        suppressDeclineHttpOnDisconnect = false
                        resetCallState()
                    },
                    onSetActive = {
                        Log.i(TAG, "📞 Core-Telecom onSetActive")
                        callWasAnswered = true
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
                finishCallSession()
            } catch (e: Exception) {
                Log.e(TAG, "📞 Core-Telecom error: ${e.message}", e)
                finishCallSession()
            }
        }
    }

    private fun handleDecline(intent: Intent?, noAnswer: Boolean = false) {
        Log.i(TAG, "📞 handleDecline called noAnswer=$noAnswer")
        suppressDeclineHttpOnDisconnect = true
        var cid = currentCallerId
        if (cid.isNullOrBlank()) {
            cid = intent?.getStringExtra(EXTRA_CALLER_ID)
        }
        if (cid.isNullOrBlank()) {
            val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            cid = prefs.getString("flutter.pending_call_caller_id", null)
        }
        if (!cid.isNullOrBlank()) {
            val scope = callScope ?: CoroutineScope(Dispatchers.IO)
            scope.launch {
                sendDeclineHttp(cid, noAnswer = noAnswer)
            }
            tearDownCoreTelecomSession(
                disconnectCause = DisconnectCause(DisconnectCause.REJECTED),
            )
        } else {
            val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            val callRecordId = prefs.getString(KEY_CALL_RECORD_ID, null).orEmpty()
            if (callRecordId.isNotBlank()) {
                val scope = callScope ?: CoroutineScope(Dispatchers.IO)
                scope.launch {
                    sendDeclineHttp("", noAnswer = noAnswer)
                }
            } else {
                Log.w(TAG, "📞 handleDecline skipped — no callerId/callRecordId")
            }
        }
        scheduleLingerStop()
    }

    private fun handleAccept() {
        Log.i(TAG, "📞 handleAccept called")
        callWasAnswered = true
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
        handleRemoteCancel()
    }

    /** Pilgrim cancelled while mod is ringing — Core-Telecom teardown only. */
    private fun handleRemoteCancel() {
        if (isTearingDown) {
            Log.w(TAG, "📞 handleRemoteCancel skipped — already tearing down")
            return
        }
        isTearingDown = true
        Log.i(TAG, "📞 handleRemoteCancel called")
        suppressDeclineHttpOnDisconnect = true
        activePollJob?.cancel()
        activePollJob = null
        // Never cancel [callScope] before disconnect — that leaves
        // CallSessionLegacy's MuteStateReceiver registered (IntentReceiverLeaked).
        tearDownCoreTelecomSession(
            disconnectCause = DisconnectCause(DisconnectCause.REMOTE),
            onFinished = {
                isTearingDown = false
                scheduleLingerStop()
            },
        )
    }

    /**
     * End the active Core-Telecom call so [CallsManager.addCall] can finish and
     * unregister internal receivers. Cancelling [callScope] first causes leaks.
     */
    private fun tearDownCoreTelecomSession(
        disconnectCause: DisconnectCause = DisconnectCause(DisconnectCause.REMOTE),
        cancelScopeAfterDisconnect: Boolean = false,
        onFinished: (() -> Unit)? = null,
    ) {
        val control = callControlScope
        val scope = callScope ?: CoroutineScope(SupervisorJob() + Dispatchers.IO)
        if (control == null) {
            finishCallSession()
            onFinished?.invoke()
            return
        }
        scope.launch {
            try {
                control.disconnect(disconnectCause)
            } catch (e: Exception) {
                Log.w(TAG, "📞 Core-Telecom disconnect failed: ${e.message}")
            }
            // onDisconnect → resetCallState; finish if the session stalls.
            delay(500)
            if (callControlScope != null) {
                Log.w(TAG, "📞 Core-Telecom onDisconnect slow — forcing finish")
                finishCallSession()
            } else if (cancelScopeAfterDisconnect) {
                cancelCallCoroutines()
            }
            onFinished?.invoke()
        }
    }

    private fun cancelCallCoroutines() {
        callJob?.cancel()
        callJob = null
        callScope?.cancel()
        callScope = null
    }

    /** Removes the duplicate tray entry; does not stop the service or Core-Telecom. */
    private fun removeForegroundNotification() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "📞 removeForegroundNotification stopForeground: ${e.message}")
        }
        cancelStaleForegroundTray(this)
    }

    private fun scheduleLingerStop() {
        Log.i(
            TAG,
            "📞 Tray removed; delaying stopSelf by ${LINGER_MS}ms to prevent FCM throttle",
        )
        removeForegroundNotification()
        lingerJob?.cancel()
        lingerJob = CoroutineScope(Dispatchers.IO).launch {
            delay(LINGER_MS)
            stopSelf()
        }
    }

    /**
     * CallKit already shows the incoming / ongoing call notification.
     * This removes our duplicate FGS notification without cancelling Core-Telecom work.
     */
    private fun dismissForegroundNotificationOnly() {
        Log.i(TAG, "📞 Duplicate FGS dismiss — removing tray only (service stays alive)")
        removeForegroundNotification()
    }

    /**
     * Reset call state WITHOUT stopping the service.
     * This allows the service to handle subsequent incoming calls.
     */
    /**
     * When FCM [call_cancel] never reaches a killed mod app, poll the public
     * check-active endpoint so we still stop Core-Telecom ringing.
     */
    private fun startActiveCallPolling(callerId: String, scope: CoroutineScope) {
        activePollJob?.cancel()
        activePollJob = scope.launch {
            Log.i(TAG, "📞 check-active poll started for callerId=$callerId")
            delay(200)
            repeat(90) { tick ->
                if (!isActive || callWasAnswered) return@launch
                when (val active = isCallerStillActiveOnServer(this@IncomingCallService, callerId)) {
                    false -> {
                        Log.i(
                            TAG,
                            "📞 check-active poll: caller no longer active — remote cancel",
                        )
                        handleRemoteCancel()
                        return@launch
                    }
                    true -> {
                        if (tick == 0 || tick % 5 == 0) {
                            Log.i(TAG, "📞 check-active poll: still active (tick=$tick)")
                        }
                    }
                    null -> {
                        if (tick >= 2) {
                            Log.w(
                                TAG,
                                "📞 check-active poll: repeated errors — remote cancel",
                            )
                            handleRemoteCancel()
                            return@launch
                        }
                    }
                }
                delay(1000)
            }
            Log.w(TAG, "📞 check-active poll ended without remote cancel")
        }
    }

    /** Clears per-call fields only — safe from [onDisconnect] inside [addCall]. */
    private fun resetCallState() {
        Log.i(TAG, "📞 Resetting call state (service stays alive)")
        activePollJob?.cancel()
        activePollJob = null
        callControlScope = null
        currentCallerId = null
        callWasAnswered = false
    }

    /** Full teardown after [addCall] returns or when no session is active. */
    private fun finishCallSession() {
        resetCallState()
        cancelCallCoroutines()
    }

    private fun sendDeclineHttp(callerId: String, noAnswer: Boolean = false) {
        val baseUrl = resolveBaseUrl(this)
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val declinerId = prefs.getString(KEY_DECLINER_ID, null).orEmpty()
        val callRecordId = prefs.getString(KEY_CALL_RECORD_ID, null).orEmpty()
        if (baseUrl.isBlank()) {
            Log.w(TAG, "📞 Decline HTTP skipped — API base URL not configured")
            return
        }
        if (callerId.isBlank() && callRecordId.isBlank()) {
            Log.w(TAG, "📞 Decline HTTP skipped — no callerId/callRecordId")
            return
        }
        Log.i(
            TAG,
            "📞 Sending decline HTTP for callerId=$callerId callRecordId=$callRecordId noAnswer=$noAnswer to $baseUrl",
        )

        repeat(3) { attempt ->
            try {
                val url = URL("$baseUrl/call-history/decline")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 10000
                conn.readTimeout = 10000

                val body = buildString {
                    append("{\"callerId\":\"$callerId\"")
                    if (declinerId.isNotBlank()) {
                        append(",\"declinerId\":\"$declinerId\"")
                    }
                    if (callRecordId.isNotBlank()) {
                        append(",\"callRecordId\":\"$callRecordId\"")
                    }
                    if (noAnswer) {
                        append(",\"noAnswer\":true")
                    }
                    append("}")
                }
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Active Call",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Required for call management; CallKit shows the visible call UI"
                setShowBadge(false)
                setSound(null, null)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(callerName: String): Notification {
        // Short-lived: dismissed on accept/connected/end. CallKit shows the real call UI.
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(callerName.ifBlank { "Call" })
            .setContentText("Connecting…")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        activePollJob?.cancel()
        activePollJob = null
        lingerJob?.cancel()
        lingerJob = null
        tearDownCoreTelecomSession(
            disconnectCause = DisconnectCause(DisconnectCause.LOCAL),
            cancelScopeAfterDisconnect = true,
        )
        cancelStaleForegroundTray(this)
        super.onDestroy()
        Log.i(TAG, "📞 IncomingCallService destroyed")
    }
}
