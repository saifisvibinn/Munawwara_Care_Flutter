package com.munawwaracare.android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.work.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    companion object {
        private const val INCOMING_CALL_CHANNEL =
            "com.munawwaracare.android/incoming_call"
        private const val OEM_SETTINGS_CHANNEL =
            "com.munawwaracare.android/oem_settings"
        private const val NOTIFICATION_TRAY_CHANNEL =
            "com.munawwaracare.android/notification_tray"
        private const val WORK_MANAGER_CHANNEL =
            "com.munawwaracare/workmanager"
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OEM_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAutostartSettings" -> {
                    val opened = OemSettingsHelper.openAutostartSettings(this)
                    result.success(opened)
                }
                "openBatterySettings" -> {
                    val opened = OemSettingsHelper.openBatterySettings(this)
                    if (opened) {
                        SettingsReturnWatcher.start(this, "battery")
                    }
                    result.success(opened)
                }
                "openLocationPermissionSettings" -> {
                    val opened = OemSettingsHelper.openLocationPermissionSettings(this)
                    result.success(opened)
                }
                "openLockScreenCallSettings" -> {
                    val opened = OemSettingsHelper.openLockScreenCallSettings(this)
                    result.success(opened)
                }
                "openNotificationSettings" -> {
                    val opened = OemSettingsHelper.openNotificationSettings(this)
                    if (opened) {
                        SettingsReturnWatcher.start(this, "notifications")
                    }
                    result.success(opened)
                }
                "openAppSettings" -> {
                    val opened = OemSettingsHelper.openAppDetails(this)
                    val watchKind = call.argument<String>("watchKind")
                    if (opened && watchKind != null) {
                        SettingsReturnWatcher.start(this, watchKind)
                    }
                    result.success(opened)
                }
                "openTtsSettings" -> {
                    val intent = android.content.Intent("com.android.settings.TTS_SETTINGS")
                    intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getDeviceOemHaystack" ->
                    result.success(OemSettingsHelper.deviceOemHaystack())
                "isBatteryUnrestricted" ->
                    result.success(OemSettingsHelper.isBatteryUnrestricted(this))
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_TRAY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "dismissNotificationByTag" -> {
                    val tag = call.argument<String>("tag") ?: ""
                    result.success(NotificationTrayHelper.dismissByTag(this, tag))
                }
                "dismissNotificationByTags" -> {
                    @Suppress("UNCHECKED_CAST")
                    val tags =
                        call.argument<List<String>>("tags") ?: emptyList()
                    NotificationTrayHelper.dismissByTags(this, tags)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WORK_MANAGER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPeriodicLocation" -> {
                    val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 60
                    startPeriodicLocationWork(intervalMinutes.toLong())
                    result.success(true)
                }
                "stopPeriodicLocation" -> {
                    stopPeriodicLocationWork()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannels()
        }
    }

    override fun onResume() {
        super.onResume()
        SettingsReturnWatcher.stop()
    }

    override fun onDestroy() {
        SettingsReturnWatcher.stop()
        super.onDestroy()
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

    private fun startPeriodicLocationWork(intervalMinutes: Long) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        
        val workRequest = PeriodicWorkRequestBuilder<LocationHeartbeatWorker>(
            intervalMinutes, TimeUnit.MINUTES,
            15, TimeUnit.MINUTES
        )
            .setConstraints(constraints)
            .addTag(LocationHeartbeatWorker.WORK_NAME)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 15, TimeUnit.MINUTES)
            .build()
        
        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            LocationHeartbeatWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            workRequest
        )
    }
    
    private fun stopPeriodicLocationWork() {
        WorkManager.getInstance(applicationContext)
            .cancelUniqueWork(LocationHeartbeatWorker.WORK_NAME)
    }
}
