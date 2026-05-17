package com.munawwaracare.andriod

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import java.lang.ref.WeakReference

/**
 * After opening system settings, polls until the target permission/state is
 * satisfied, then brings the app task back to the foreground.
 */
object SettingsReturnWatcher {

    private const val TAG = "SettingsReturnWatcher"
    private const val POLL_MS = 800L
    private const val MAX_POLLS = 450

    private val handler = Handler(Looper.getMainLooper())
    private var activityRef: WeakReference<Activity>? = null
    private var watchKind: String? = null
    private var pollCount = 0
    private var running = false

    fun start(activity: Activity, kind: String) {
        when (kind) {
            "battery", "notifications" -> Unit
            else -> return
        }
        stop()
        activityRef = WeakReference(activity)
        watchKind = kind
        pollCount = 0
        running = true
        Log.i(TAG, "Watching for $kind satisfaction")
        handler.post(pollRunnable)
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        watchKind = null
        activityRef = null
        pollCount = 0
    }

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            val activity = activityRef?.get()
            if (activity == null || activity.isFinishing || activity.isDestroyed) {
                stop()
                return
            }
            val kind = watchKind ?: run {
                stop()
                return
            }
            if (isSatisfied(activity, kind)) {
                Log.i(TAG, "$kind satisfied — bringing app to foreground")
                stop()
                bringTaskToFront(activity)
                return
            }
            pollCount++
            if (pollCount >= MAX_POLLS) {
                Log.i(TAG, "Watch timeout for $kind")
                stop()
                return
            }
            handler.postDelayed(this, POLL_MS)
        }
    }

    private fun isSatisfied(context: Context, kind: String): Boolean =
        when (kind) {
            "battery" -> OemSettingsHelper.isBatteryUnrestricted(context)
            "notifications" ->
                NotificationManagerCompat.from(context).areNotificationsEnabled()
            else -> false
        }

    private fun bringTaskToFront(activity: Activity) {
        try {
            val am = activity.getSystemService(Context.ACTIVITY_SERVICE)
                as ActivityManager
            am.moveTaskToFront(activity.taskId, ActivityManager.MOVE_TASK_WITH_HOME)
        } catch (e: Exception) {
            Log.w(TAG, "moveTaskToFront failed, trying activity intent", e)
            val intent = Intent(activity, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            activity.startActivity(intent)
        }
    }
}
