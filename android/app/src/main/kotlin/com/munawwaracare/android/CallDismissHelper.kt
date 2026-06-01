package com.munawwaracare.android

import android.content.Context
import android.util.Log
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin

/**
 * Single entry to stop an incoming call on Android (FCM cancel, Dart teardown).
 * Plugin UI first, then Core-Telecom teardown — never recurses.
 *
 * [IncomingCallService.handleRemoteCancel] must not call dismiss again here;
 * only FCM / Dart / this helper should tear down plugin + telecom UI.
 */
object CallDismissHelper {
    private const val TAG = "CallDismissHelper"
    private const val PREFS_NAME = "FlutterSharedPreferences"

    @Volatile
    private var dismissing = false

    fun dismissIncomingCall(
        context: Context,
        callerId: String? = null,
        callRecordId: String? = null,
    ) {
        if (dismissing) {
            Log.w(TAG, "dismiss skipped — already in progress")
            return
        }
        val cancelId = callRecordId?.trim().orEmpty()
        if (cancelId.isNotEmpty() && !isCancelForCurrentSession(context, cancelId)) {
            val cid = callerId?.trim().orEmpty()
            if (cid.isNotEmpty()) {
                val stillActive = IncomingCallService.isCallerStillActiveOnServer(
                    context,
                    cid,
                )
                if (stillActive == true) {
                    Log.w(
                        TAG,
                        "dismiss skipped — stale cancel record=$cancelId, caller still active",
                    )
                    return
                }
            }
            Log.i(
                TAG,
                "stale cancel record=$cancelId but caller inactive — dismissing ring",
            )
        }
        dismissing = true
        try {
            Log.i(TAG, "dismissIncomingCall callerId=${callerId ?: ""} record=$cancelId")
            recordCancelTimestamp(context, callerId)
            FlutterCallkitIncomingPlugin.dismissPluginIncomingUi(context)
            IncomingCallService.requestTeardown(context)
        } catch (e: Exception) {
            Log.w(TAG, "dismissIncomingCall failed: ${e.message}")
        } finally {
            dismissing = false
        }
    }

    private fun isCancelForCurrentSession(context: Context, cancelRecordId: String): Boolean {
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pending = prefs.getString("flutter.pending_call_record_id", null)
                ?.trim()
                .orEmpty()
            if (pending.isEmpty()) true else pending == cancelRecordId
        } catch (e: Exception) {
            Log.w(TAG, "isCancelForCurrentSession: ${e.message}")
            true
        }
    }

    private fun recordCancelTimestamp(context: Context, callerId: String?) {
        try {
            val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong("flutter.last_call_cancel_ms", System.currentTimeMillis())
            val cid = callerId?.trim().orEmpty()
            if (cid.isNotEmpty()) {
                editor.putString("flutter.last_cancel_caller_id", cid)
            }
            editor.apply()
        } catch (e: Exception) {
            Log.w(TAG, "recordCancelTimestamp: ${e.message}")
        }
    }
}
