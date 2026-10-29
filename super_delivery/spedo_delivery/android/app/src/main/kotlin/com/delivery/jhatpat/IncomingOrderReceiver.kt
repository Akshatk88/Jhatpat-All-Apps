package com.delivery.jhatpat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Raises the offer alert straight off the FCM broadcast.
 *
 * Sits alongside the firebase_messaging plugin's own receiver rather than
 * replacing it: Android delivers `c2dm.intent.RECEIVE` to every registered
 * receiver, so the plugin keeps waking Dart exactly as before and this only adds
 * the alert. Subclassing or overriding the plugin's service would have coupled
 * the alert to a plugin internal that has already moved once (its
 * `onMessageReceived` is an empty stub today — the work happens in its receiver).
 *
 * The point of doing it here is latency and reach: a receiver runs in a process
 * Android will start for the broadcast, with no Flutter engine to boot first.
 * That is the difference between an alert on a locked phone at second one and
 * one at second eight, and on ROMs that never let the Dart isolate start, the
 * difference between an alert and silence.
 */
class IncomingOrderReceiver : BroadcastReceiver() {

    private companion object {
        /** Pushes that mean "an offer is on the table". */
        val OFFER_TYPES = setOf("new_order", "ride_request")

        /** Someone else took it, or it was withdrawn. */
        const val WITHDRAWN_TYPE = "order_taken"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return

        // FCM flattens a data message's keys into the intent extras. Anything
        // non-string (FCM's own bookkeeping) is not ours to forward.
        val payload = HashMap<String, String>()
        for (key in extras.keySet()) {
            val value = extras.get(key)
            if (value is String) payload[key] = value
        }

        val type = payload["type"] ?: return
        val orderId = orderIdOf(payload) ?: return

        when {
            type == WITHDRAWN_TYPE -> IncomingOrderNotifier.cancel(context, orderId)
            // App open: the in-app offer screen (FirebaseMessaging.onMessage)
            // handles it, with its own ringtone and Accept.
            OFFER_TYPES.contains(type) && appIsOnScreen(context) -> Unit
            OFFER_TYPES.contains(type) -> {
                // Recorded either way, so the Dart background handler does not
                // raise a second alert (or one this filter just dropped).
                OfferOverlay.markSeen(context, orderId)
                // Not the rider's active module (a food order outside Food, a
                // ride/parcel in Food, a parcel in Rider, a passenger in
                // Parcel): the app ignores these — not shown, not rung, never
                // rejected — so the native alert does too. No ring, no
                // notification, no overlay, no full-screen card.
                if (!OfferOverlay.belongsToModule(context, type, payload)) {
                    IncomingOrderNotifier.removeFcmCopy(context, payload)
                    return
                }
                // A fresh offer, even for an id answered before, may be answered.
                IncomingOrderNotifier.clearAnswered(orderId)

                // Phone in use and "display over other apps" granted: the
                // Flutter card over whatever is open. Locked/dark phone, no
                // permission, or the window refused: the native path below.
                val overlay = OfferOverlay.canShow(context) &&
                    OfferOverlay.show(context, orderId, payload)

                // Always post it: this is what makes the sound (the overlay is
                // silent), what survives if the card cannot be shown, and what
                // the lock screen uses. With the overlay up it carries no
                // full-screen intent, which would otherwise pin a sticky
                // heads-up over the top of the card.
                IncomingOrderNotifier.show(context, orderId, payload, fullScreen = !overlay)
                if (!overlay) openCardIfAllowed(context, orderId, payload)
                IncomingOrderNotifier.removeFcmCopy(context, payload)
            }
        }
    }

    /**
     * The in-app screen is only trusted to show the offer when the app is
     * really in front: resumed AND the display on. A flag left true by a
     * resumed activity on a dark screen would otherwise swallow the alert.
     */
    private fun appIsOnScreen(context: Context): Boolean {
        if (!MainActivity.isInForeground) return false
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isInteractive
    }

    /**
     * Puts the offer card on screen even when the rider is using the phone.
     *
     * A full-screen intent alone is not enough. Android only lets one take over
     * the screen while the device is locked or idle; with the phone in use it is
     * downgraded to a heads-up banner, which is why the card appeared on the
     * lock screen but never over the home screen.
     *
     * Starting the activity directly is normally forbidden from the background
     * — except for an app the user has granted "display over other apps", which
     * is the documented exemption this relies on and the reason
     * SYSTEM_ALERT_WINDOW is declared. Without the grant this does nothing and
     * the notification above is what the rider gets, so the permission is worth
     * asking for but never required.
     */
    private fun openCardIfAllowed(
        context: Context,
        orderId: String,
        payload: HashMap<String, String>,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(context)
        ) {
            return
        }
        // Reached with the permission only when the overlay could not be used
        // (locked or dark phone, or the window was refused).

        val intent = Intent(context, IncomingOrderActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(IncomingOrderNotifier.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingOrderNotifier.EXTRA_ACTION, IncomingOrderNotifier.ACTION_OPEN)
            putExtra(IncomingOrderNotifier.EXTRA_PAYLOAD, payload)
        }

        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // Some OEM builds refuse it anyway. The notification still stands.
        }
    }

    /** Matches the Dart side's key order so both name the same order. */
    private fun orderIdOf(payload: Map<String, String>): String? {
        val id = payload["orderMongoId"]
            ?: payload["orderId"]
            ?: payload["_id"]
            ?: payload["rideId"]
        return if (id.isNullOrEmpty()) null else id
    }
}
