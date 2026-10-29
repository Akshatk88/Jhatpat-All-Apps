package com.restaurant.jhatpat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

/**
 * Raises the new-order alert straight off the FCM broadcast.
 *
 * Android delivers `com.google.android.c2dm.intent.RECEIVE` to every receiver
 * registered for it, for EVERY push — notification or data, app alive or
 * killed — so this runs next to the firebase_messaging plugin's own receiver
 * without replacing it. It is needed because the backend sends both copies of
 * a new order with an Android notification block: for such a push, with the
 * app in the background, Android draws its own (empty) notification and the
 * Dart `onBackgroundMessage` handler never runs, so neither the overlay nor
 * the ringing Accept/Reject alert ever started.
 *
 * App in the foreground: nothing here — the in-app request screen
 * (FirebaseMessaging.onMessage) handles it.
 *
 * Otherwise, once per order (the two backend copies arrive moments apart):
 *  1. phone in use + "display over other apps" granted: the overlay card at
 *     the top, ringing on its own, plus a SILENT tray alert (Accept/Reject,
 *     lock screen) — one ringing source;
 *  2. locked / screen off / no permission / overlay refused: the insistent
 *     full-screen alert (rings until answered, expired or handled).
 * In both cases the notifications the FCM SDK drew for the push are removed.
 *
 * The Dart side is told via [markHandled] so its background / onMessage
 * handlers (still the fallback for true data-only pushes) do not alert twice.
 */
class NewOrderReceiver : BroadcastReceiver() {

    private companion object {
        /** Long enough to cover both backend copies (and a retry), short of a re-sent order. */
        const val DUPLICATE_WINDOW_MS = 2 * 60_000L

        /** Read by lib/core/services/fcm_service.dart (`native_new_order_<id>`). */
        const val PREFS = "FlutterSharedPreferences"
        const val HANDLED_PREFIX = "flutter.native_new_order_"

        /** Time for OverlayService.onStartCommand to put the window up. */
        const val OVERLAY_CHECK_DELAY_MS = 2_500L
    }

    override fun onReceive(context: Context, intent: Intent) {
        // A push must never crash the process.
        try {
            handle(context.applicationContext, intent)
        } catch (_: Exception) {
        }
    }

    private fun handle(context: Context, intent: Intent) {
        if (intent.getStringExtra("type") != NewOrder.TYPE) return
        if (MainActivity.isInForeground) return
        val order = NewOrder.from(intent.extras) ?: return

        if (wasHandledRecently(context, order.orderId)) {
            // The second backend copy: already alerting. Its own system-drawn
            // notification still has to go.
            NewOrderAlert.removeSystemCopies(context, order.orderId)
            return
        }

        val overlay = NewOrderOverlay.canShow(context) && NewOrderOverlay.show(context, order)
        val posted = NewOrderAlert.show(context, order, silent = overlay)
        if (!overlay && !posted) {
            // Nothing of ours is up (notifications blocked): leave the system
            // copies alone — they are all the restaurant has — and let the
            // Dart handler try if it gets to run.
            return
        }

        markHandled(context, order.orderId)
        NewOrderAlert.removeSystemCopies(context, order.orderId)
        if (overlay) ringIfOverlayFailed(context, order)
    }

    /**
     * The overlay is what rings while it is up. If its window never came up
     * (some ROMs refuse it even with the permission), the silent tray alert
     * would leave the order unheard — re-post it ringing.
     */
    private fun ringIfOverlayFailed(context: Context, order: NewOrder) {
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                if (!NewOrderOverlay.isRunning() &&
                    NewOrderAlert.isShowing(context, order.orderId) &&
                    order.deadlineMs > System.currentTimeMillis()
                ) {
                    NewOrderAlert.show(context, order, silent = false, replace = true)
                }
            } catch (_: Exception) {
            }
        }, OVERLAY_CHECK_DELAY_MS)
    }

    private fun wasHandledRecently(context: Context, orderId: String): Boolean {
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val at = prefs.getLong(HANDLED_PREFIX + orderId, 0L)
            at > 0L && System.currentTimeMillis() - at < DUPLICATE_WINDOW_MS
        } catch (_: Exception) {
            false
        }
    }

    /** Synchronous (commit): the second copy may be delivered right behind this one. */
    private fun markHandled(context: Context, orderId: String) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val editor = prefs.edit()
            for ((key, value) in prefs.all) {
                if (key.startsWith(HANDLED_PREFIX) && value is Long &&
                    now - value > 24 * 60 * 60_000L
                ) {
                    editor.remove(key)
                }
            }
            editor.putLong(HANDLED_PREFIX + orderId, now).commit()
        } catch (_: Exception) {
        }
    }
}
