package com.displaymac.client.feedback

import android.content.Context
import android.content.Intent
import android.net.Uri

object FeedbackHelper {
    const val FEEDBACK_EMAIL = "sumitranjanhisu@gmail.com"

    fun sendFeedback(context: Context, userMessage: String = "") {
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("mailto:$FEEDBACK_EMAIL")
            putExtra(Intent.EXTRA_SUBJECT, "DisplayMac Feedback & Support")
            putExtra(Intent.EXTRA_TEXT, "Hi Sumit,\n\n$userMessage\n\n---\nSent from DisplayMac Android Client")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to generic ACTION_SEND if no direct mailto handler
            val fallback = Intent(Intent.ACTION_SEND).apply {
                type = "message/rfc822"
                putExtra(Intent.EXTRA_EMAIL, arrayOf(FEEDBACK_EMAIL))
                putExtra(Intent.EXTRA_SUBJECT, "DisplayMac Feedback & Support")
                putExtra(Intent.EXTRA_TEXT, userMessage)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(Intent.createChooser(fallback, "Send Feedback via..."))
        }
    }
}
