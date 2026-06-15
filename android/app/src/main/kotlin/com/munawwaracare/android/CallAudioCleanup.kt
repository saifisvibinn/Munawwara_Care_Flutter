package com.munawwaracare.android

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.util.Log

/**
 * Resets Android audio mode after call decline/end.
 * Prevents ghost in-call mode where volume keys appear unresponsive.
 */
object CallAudioCleanup {
    private const val TAG = "CallAudioCleanup"
    private const val PREFS_NAME = "FlutterSharedPreferences"

    fun resetAudioMode(context: Context) {
        try {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    am.clearCommunicationDevice()
                } catch (e: Exception) {
                    Log.w(TAG, "clearCommunicationDevice: ${e.message}")
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .build()
                am.abandonAudioFocusRequest(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(null)
            }
            am.mode = AudioManager.MODE_NORMAL
            am.isSpeakerphoneOn = false
            Log.i(TAG, "reset mode=NORMAL")
        } catch (e: Exception) {
            Log.w(TAG, "resetAudioMode failed: ${e.message}")
        }
    }

    fun clearPendingCallPrefs(context: Context) {
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove("flutter.pending_call_caller_id")
                .remove("flutter.pending_call_caller_name")
                .remove("flutter.pending_call_caller_role")
                .remove("flutter.pending_call_caller_gender")
                .remove("flutter.pending_call_caller_profile_picture")
                .remove("flutter.pending_call_channel_name")
                .remove("flutter.pending_call_created_at_ms")
                .remove("flutter.pending_call_uuid")
                .remove("flutter.pending_call_record_id")
                .remove("flutter.last_incoming_call_ring_claim")
                .apply()
            Log.i(TAG, "cleared pending call prefs")
        } catch (e: Exception) {
            Log.w(TAG, "clearPendingCallPrefs: ${e.message}")
        }
    }

    fun fullTeardown(context: Context) {
        resetAudioMode(context)
        clearPendingCallPrefs(context)
    }
}
