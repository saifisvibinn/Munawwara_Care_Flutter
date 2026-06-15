package com.munawwaracare.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.util.Log
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Native Android BroadcastReceiver that intercepts the flutter_callkit_incoming
 * DECLINE broadcast and immediately fires an HTTP POST to the backend.
 *
 * Works even when the Flutter app is completely KILLED — no Dart engine needed.
 *
 * flutter_callkit_incoming constructs the action as:
 *   "${context.packageName}.${CallkitConstants.ACTION_CALL_DECLINE}"
 * where ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
 * So the final action we listen for is:
 *   "com.munawwaracare.android.com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
 *
 * The data Bundle comes in the intent extra "EXTRA_CALLKIT_INCOMING_DATA".
 * Our callerId is stored inside that Bundle at "EXTRA_CALLKIT_EXTRA" → "callerId".
 */
class CallDeclineReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallDeclineReceiver"

        // The exact action string constructed by the plugin:
        // "${packageName}.${ACTION_CALL_DECLINE_CONSTANT}"
        private const val PACKAGE = "com.munawwaracare.android"
        private const val ACTION_DECLINE =
            "$PACKAGE.com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
        private const val ACTION_TIMEOUT =
            "$PACKAGE.com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"

        // Plugin bundle keys (from CallkitConstants.kt)
        private const val EXTRA_INCOMING_DATA = "EXTRA_CALLKIT_INCOMING_DATA"
        private const val EXTRA_CALLKIT_EXTRA = "EXTRA_CALLKIT_EXTRA"

        // SharedPreferences — Flutter's plugin writes using "FlutterSharedPreferences"
        // with a "flutter." prefix on every key.
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_CALLER_ID = "flutter.pending_call_caller_id"
        private const val KEY_CALL_RECORD_ID = "flutter.pending_call_record_id"
        private const val KEY_DECLINER_ID = "flutter.user_id"
        private const val KEY_API_BASE_URL = "flutter.api_base_url"

    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != ACTION_DECLINE && action != ACTION_TIMEOUT) return

        Log.i(TAG, "📵 $action received")

        val callerId = resolveCallerId(context, intent).orEmpty()
        val callRecordId = resolveCallRecordId(context)
        if (callerId.isBlank() && callRecordId.isBlank()) {
            Log.w(TAG, "📵 callerId/callRecordId not found — cannot notify backend")
            return
        }

        val baseUrl = resolveBaseUrl(context)
        if (baseUrl.isBlank()) {
            Log.w(
                TAG,
                "📵 API base URL missing — set API_BASE_URL in .env or " +
                    "--dart-define=API_BASE_URL=... and open the app once",
            )
            return
        }
        val declinerId = resolveDeclinerId(context)
        Log.i(TAG, "📵 Declining callerId=$callerId callRecordId=$callRecordId via $baseUrl")

        val pendingResult = goAsync()
        val noAnswer = action == ACTION_TIMEOUT
        thread(name = "CallDeclineHTTP") {
            try {
                sendDeclineHttp(
                    baseUrl,
                    callerId,
                    declinerId,
                    callRecordId,
                    noAnswer,
                )
            } finally {
                CallAudioCleanup.fullTeardown(context.applicationContext)
                pendingResult.finish()
            }
        }
    }

    private fun resolveCallerId(context: Context, intent: Intent): String? {
        // 1. Try the plugin's Bundle: EXTRA_CALLKIT_INCOMING_DATA → EXTRA_CALLKIT_EXTRA
        val bundle: Bundle? =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                intent.getBundleExtra(EXTRA_INCOMING_DATA)
            } else {
                @Suppress("DEPRECATION")
                intent.getBundleExtra(EXTRA_INCOMING_DATA)
            }

        if (bundle != null) {
            @Suppress("UNCHECKED_CAST", "DEPRECATION")
            val extraMap = bundle.getSerializable(EXTRA_CALLKIT_EXTRA)
                as? HashMap<String, Any?>
            val fromMap = extraMap?.get("callerId")?.toString()
            if (!fromMap.isNullOrBlank()) return fromMap

            val extraBundle = bundle.getBundle(EXTRA_CALLKIT_EXTRA)
            val fromExtra = extraBundle?.getString("callerId")
            if (!fromExtra.isNullOrBlank()) return fromExtra

            val flat = bundle.getString("callerId")
            if (!flat.isNullOrBlank()) return flat
        }

        // 2. Fall back to SharedPreferences written by Flutter when the call FCM arrived
        return try {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_CALLER_ID, null)
        } catch (e: Exception) {
            Log.e(TAG, "📵 SharedPrefs read error: ${e.message}")
            null
        }
    }

    private fun resolveBaseUrl(context: Context): String {
        return try {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_API_BASE_URL, null)?.takeIf { it.isNotBlank() }
                ?: BackendConfig.API_BASE_URL_FALLBACK.takeIf { it.isNotBlank() }
                .orEmpty()
        } catch (e: Exception) {
            BackendConfig.API_BASE_URL_FALLBACK
        }
    }

    private fun resolveDeclinerId(context: Context): String {
        return try {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_DECLINER_ID, null).orEmpty()
        } catch (e: Exception) {
            ""
        }
    }

    private fun resolveCallRecordId(context: Context): String {
        return try {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.getString(KEY_CALL_RECORD_ID, null).orEmpty()
        } catch (e: Exception) {
            ""
        }
    }

    private fun sendDeclineHttp(
        baseUrl: String,
        callerId: String,
        declinerId: String,
        callRecordId: String,
        noAnswer: Boolean,
    ) {
        repeat(2) { attempt -> // retry once on failure
            try {
                val url = URL("$baseUrl/call-history/decline")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 8000
                conn.readTimeout = 8000

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

                Log.i(TAG, "📵 Decline HTTP $code (attempt $attempt) for callerId=$callerId")
                if (code in 200..299) return // success
            } catch (e: Exception) {
                Log.e(TAG, "📵 Decline HTTP attempt $attempt failed: ${e.message}")
                if (attempt == 0) Thread.sleep(1500) // wait before retry
            }
        }
    }
}
