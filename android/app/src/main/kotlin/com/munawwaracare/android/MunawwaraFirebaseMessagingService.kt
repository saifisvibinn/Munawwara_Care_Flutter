package com.munawwaracare.android

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/**
 * Native path for [call_cancel] / [call_declined] when the app is killed.
 * [incoming_call] is always forwarded to Flutter via [onMessageReceived].
 */
class MunawwaraFirebaseMessagingService : FlutterFirebaseMessagingService() {

    companion object {
        private fun fcmControlType(data: Map<String, String>): String? {
            val type = data["type"]?.trim().orEmpty()
            if (type == "call_cancel" || type == "call_declined") return type
            val notificationType = data["notification_type"]?.trim().orEmpty()
            if (notificationType == "call_cancel" || notificationType == "call_declined") {
                return notificationType
            }
            return null
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        when (fcmControlType(data)) {
            "call_cancel" -> CallDismissHelper.dismissIncomingCall(
                applicationContext,
                data["callerId"],
                data["callRecordId"],
            )
            "call_declined" -> CallDismissHelper.dismissIncomingCall(
                applicationContext,
                data["callerId"],
            )
        }
        super.onMessageReceived(message)
    }
}
