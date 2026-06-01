package com.munawwaracare.android

import android.content.Context
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/**
 * Dismisses tray notifications posted by FCM (Android tag) or the local plugin.
 */
object NotificationTrayHelper {
    private const val TAG = "NotificationTrayHelper"

    fun dismissByTag(context: Context, tag: String): Boolean {
        val t = tag.trim()
        if (t.isEmpty()) return false
        return try {
            NotificationManagerCompat.from(context).cancel(t, 0)
            Log.i(TAG, "Dismissed tray notification tag=$t")
            true
        } catch (e: Exception) {
            Log.w(TAG, "dismissByTag failed tag=$t: ${e.message}")
            false
        }
    }

    fun dismissByTags(context: Context, tags: Collection<String>) {
        for (tag in tags) {
            dismissByTag(context, tag)
        }
    }
}
