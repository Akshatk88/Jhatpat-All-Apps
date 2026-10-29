package com.restaurant.jhatpat

import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Removes the blank notifications Android draws for some backend pushes.
 *
 * The backend adds an `android.notification` block (channel, sound) even to
 * its data-only messages, so the system renders them itself with no title and
 * no text: an empty "app • now" row with a bell. This receiver runs for every
 * FCM message, even with the app killed, and sweeps away notifications that
 * FCM posted (tag "FCM-Notification…") which have neither title nor text.
 * Real notifications always carry a title, so they are never touched.
 *
 * Backend fix (makes this unnecessary): in firebase.service.js
 * buildMessagePayload, only add `android.notification` when !payload.dataOnly.
 */
class EmptyPushCleaner : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val appContext = context.applicationContext
        val sweep = Runnable { removeBlank(appContext) }
        // FCM's own receiver posts its notification in no guaranteed order
        // relative to this one, hence a few passes.
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed(sweep, 300L)
        handler.postDelayed(sweep, 1_200L)
        handler.postDelayed(sweep, 4_000L)
    }

    private fun removeBlank(context: Context) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            for (posted in manager.activeNotifications) {
                val tag = posted.tag ?: continue
                if (!tag.startsWith("FCM-Notification")) continue
                val extras = posted.notification.extras
                val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                if (title.isNullOrBlank() && text.isNullOrBlank()) {
                    manager.cancel(tag, posted.id)
                }
            }
        } catch (_: Exception) {
            // Best-effort cleanup; never crash a broadcast receiver.
        }
    }
}
