package com.munawwaracare.mcmobile

import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Native-first call action handler.
 * Registers plugin callbacks for ACCEPT/DECLINE so backend signaling works
 * even when Flutter UI is not opened.
 */
class CallDeclineApplication : Application() {
    companion object {
        private const val TAG = "CallDecline"
        private const val TAG_ACTION = "NATIVE_CALL_ACTION"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FALLBACK_BASE_URL =
            "https://mcbackendapp-199324116788.europe-west8.run.app/api"
    }

    private val nativeCallEventCallback = object : CallkitEventCallback {
        override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
            val payload = extractPayload(this@CallDeclineApplication, callData)
            when (event) {
                CallkitEventCallback.CallEvent.ACCEPT -> {
                    Log.i(
                        TAG_ACTION,
                        "ACCEPT event callerId=${payload.callerId} callRecordId=${payload.callRecordId}",
                    )
                    postAnswer(payload)
                }

                CallkitEventCallback.CallEvent.DECLINE -> {
                    Log.i(
                        TAG_ACTION,
                        "DECLINE event callerId=${payload.callerId} callRecordId=${payload.callRecordId}",
                    )
                    postDecline(payload)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()

        // Pre-warm Flutter loader and register native callback as early as possible.
        try {
            io.flutter.FlutterInjector.instance()
                .flutterLoader()
                .startInitialization(this)
        } catch (e: Exception) {
            Log.w(TAG, "Flutter loader pre-init failed (non-fatal)", e)
        }

        FlutterCallkitIncomingPlugin.registerEventCallback(nativeCallEventCallback)
        Log.i(TAG, "Registered native CallkitEventCallback (accept/decline)")
    }

    private data class NativePayload(
        val callerId: String,
        val callRecordId: String,
        val currentUserId: String,
        val apiBaseUrl: String,
    )

    private fun extractPayload(context: Context, callData: Bundle): NativePayload {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)

        @Suppress("UNCHECKED_CAST", "DEPRECATION")
        val extraMap = callData.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA)
            as? HashMap<String, Any?>

        val callerId = (extraMap?.get("callerId") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: prefs.getString("flutter.pending_call_caller_id", "")
            .orEmpty()

        val callRecordId = (extraMap?.get("callRecordId") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: prefs.getString("flutter.pending_call_record_id", "")
            .orEmpty()

        val currentUserId = prefs.getString("flutter.user_id", "")
            .orEmpty()

        val apiBaseUrl = ((extraMap?.get("apiBaseUrl") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: prefs.getString("flutter.api_base_url", "")
            .orEmpty())
            .ifBlank { FALLBACK_BASE_URL }

        return NativePayload(
            callerId = callerId,
            callRecordId = callRecordId,
            currentUserId = currentUserId,
            apiBaseUrl = apiBaseUrl,
        )
    }

    private fun postDecline(payload: NativePayload) {
        if (payload.callerId.isBlank() && payload.callRecordId.isBlank()) {
            Log.w(TAG, "Decline skipped: no callerId/callRecordId")
            return
        }

        Log.i(
            TAG,
            "Native DECLINE -> ${payload.apiBaseUrl} callerId=${payload.callerId} callRecordId=${payload.callRecordId}",
        )
        thread(name = "NativeDeclineHTTP") {
            postJson(
                "${payload.apiBaseUrl}/call-history/decline",
                JSONObject().apply {
                    put("callerId", payload.callerId)
                    put("callRecordId", payload.callRecordId)
                    put("declinerId", payload.currentUserId)
                },
                "decline",
            )
        }
    }

    private fun postAnswer(payload: NativePayload) {
        if (payload.callerId.isBlank() && payload.callRecordId.isBlank()) {
            Log.w(TAG, "Answer skipped: no callerId/callRecordId")
            return
        }

        Log.i(
            TAG,
            "Native ACCEPT -> ${payload.apiBaseUrl} callerId=${payload.callerId} userId=${payload.currentUserId}",
        )
        thread(name = "NativeAnswerHTTP") {
            postJson(
                "${payload.apiBaseUrl}/call-history/answer",
                JSONObject().apply {
                    put("callerId", payload.callerId)
                    put("answererId", payload.currentUserId)
                },
                "answer",
            )
        }
    }

    private fun postJson(url: String, body: JSONObject, label: String) {
        try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000

            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use {
                it.write(body.toString())
            }

            val code = conn.responseCode
            Log.i(TAG, "Native $label POST response: $code")
            Log.i(TAG_ACTION, "HTTP $label response=$code url=$url")
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Native $label POST failed", e)
            Log.e(TAG_ACTION, "HTTP $label failed: ${e.message}")
        }
    }
}
