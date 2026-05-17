package com.munawwaracare.andriod

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val INCOMING_CALL_CHANNEL =
            "com.munawwaracare.andriod/incoming_call"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCOMING_CALL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "stopRinging" -> {
                    val callerId = call.argument<String>("callerId")
                    val callRecordId = call.argument<String>("callRecordId")
                    CallDismissHelper.dismissIncomingCall(
                        this,
                        callerId,
                        callRecordId,
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannels()
        }
    }

    private fun createNotificationChannels() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ─ Default channel ───────────────────────────────────────────
        if (nm.getNotificationChannel("default") == null) {
            val def = NotificationChannel(
                "default",
                "General Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "General app notifications" }
            nm.createNotificationChannel(def)
        }

        // ─ Urgent / SOS channel ─────────────────────────────────
        // Uses alarm/ringtone volume so it plays even in silent DND on many devices
        if (nm.getNotificationChannel("urgent") == null) {
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val audioAttr = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val urgent = NotificationChannel(
                "urgent",
                "SOS & Emergency Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High-priority SOS alerts for moderators"
                setSound(alarmUri, audioAttr)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                setBypassDnd(true)          // bypass Do-Not-Disturb
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(urgent)
        }
    }
}
