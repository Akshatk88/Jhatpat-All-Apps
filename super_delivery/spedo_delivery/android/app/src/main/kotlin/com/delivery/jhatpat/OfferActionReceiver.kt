package com.delivery.jhatpat

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The notification's Reject button, and the overlay card's buttons.
 *
 * A broadcast rather than an activity so declining opens nothing at all — not
 * even the trampoline card, which on a locked phone would have flashed over the
 * lock screen. The ringing stops at once (the notification is cancelled before
 * the network call), the card closes if it is up, and the answer is sent.
 *
 * The overlay card (Flutter, see order_overlay_service.dart) sends the
 * OFFER_ACCEPT / OFFER_REJECT / OFFER_MUTE / OFFER_UNMUTE actions here with
 * only the order id; the payload comes from [OfferOverlay]. Routing it through
 * the same native code as the notification keeps one accept-once guard and one
 * ringing source.
 */
class OfferActionReceiver : BroadcastReceiver() {

    companion object {
        private const val ACTION_REJECT = "com.delivery.jhatpat.OFFER_REJECT"
        private const val ACTION_ACCEPT = "com.delivery.jhatpat.OFFER_ACCEPT"
        private const val ACTION_MUTE = "com.delivery.jhatpat.OFFER_MUTE"
        private const val ACTION_UNMUTE = "com.delivery.jhatpat.OFFER_UNMUTE"
        private const val ACTION_DISMISS = "com.delivery.jhatpat.OFFER_DISMISS"
        private const val EXTRA_TYPE = "fsi_type"

        /**
         * After a Reject, brings the app forward so the driver is asked WHY.
         * The offer is already silenced and answered; MainActivity hands this
         * to Dart (action "reject_reason") which opens the reason sheet. If the
         * OS refuses a background start, the prompt is simply skipped.
         */
        fun launchReasonPrompt(
            context: Context,
            orderId: String,
            payload: HashMap<String, String>,
        ) {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(IncomingOrderNotifier.EXTRA_ORDER_ID, orderId)
                putExtra(IncomingOrderNotifier.EXTRA_ACTION, "reject_reason")
                putExtra(IncomingOrderNotifier.EXTRA_PAYLOAD, payload)
            }
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
            }
        }

        fun rejectIntent(
            context: Context,
            orderId: String,
            payload: HashMap<String, String>,
        ): PendingIntent {
            val intent = Intent(context, OfferActionReceiver::class.java).apply {
                action = ACTION_REJECT
                putExtra(IncomingOrderNotifier.EXTRA_ORDER_ID, orderId)
                putExtra(IncomingOrderNotifier.EXTRA_PAYLOAD, payload)
            }
            return PendingIntent.getBroadcast(
                context,
                IncomingOrderNotifier.requestCode(orderId, IncomingOrderNotifier.ACTION_REJECT),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val orderId = intent.getStringExtra(IncomingOrderNotifier.EXTRA_ORDER_ID).orEmpty()
        if (orderId.isEmpty()) return

        @Suppress("UNCHECKED_CAST", "DEPRECATION")
        val payload = (intent.getSerializableExtra(IncomingOrderNotifier.EXTRA_PAYLOAD)
            as? HashMap<String, String>)
            ?: OfferOverlay.payloadFor(context, orderId)
            ?: HashMap()
        // The overlay names the type itself, so a ride is never taken for food.
        intent.getStringExtra(EXTRA_TYPE)?.takeIf { it.isNotEmpty() }?.let {
            if (payload["type"].isNullOrEmpty()) payload["type"] = it
        }

        when (intent.action) {
            ACTION_REJECT -> reject(context, orderId, payload)
            ACTION_ACCEPT -> accept(context, orderId, payload)
            // The card expired, or the ride was gone when it was fetched.
            ACTION_DISMISS -> IncomingOrderNotifier.cancel(context, orderId)
            // The overlay's sound pill: re-post the same alert silently, or
            // loudly again. The offer itself is untouched.
            ACTION_MUTE, ACTION_UNMUTE -> if (payload.isNotEmpty()) {
                IncomingOrderNotifier.show(
                    context,
                    orderId,
                    payload,
                    silent = intent.action == ACTION_MUTE,
                    fullScreen = false,
                )
            }
        }
    }

    /**
     * Hands the accept to [IncomingOrderActivity] exactly as the notification's
     * Accept does: it claims the offer once, sends the food accept (rides go
     * over the socket from Dart), and opens the app on the job.
     */
    private fun accept(context: Context, orderId: String, payload: HashMap<String, String>) {
        val intent = Intent(context, IncomingOrderActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(IncomingOrderNotifier.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingOrderNotifier.EXTRA_ACTION, IncomingOrderNotifier.ACTION_ACCEPT)
            putExtra(IncomingOrderNotifier.EXTRA_PAYLOAD, payload)
        }
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            // Background start refused: answer here and leave the app closed.
            // The rider finds the job when they open it.
            if (!IncomingOrderNotifier.claimAnswer(orderId)) return
            IncomingOrderNotifier.cancel(context, orderId)
            if (!IncomingOrderNotifier.isRide(payload)) {
                val pending = goAsync()
                OrderResponder.respond(context.applicationContext, orderId, accept = true) {
                    pending.finish()
                }
            }
        }
    }

    private fun reject(context: Context, orderId: String, payload: HashMap<String, String>) {
        // Already answered on another surface; just make sure it is all down.
        if (!IncomingOrderNotifier.claimAnswer(orderId)) {
            IncomingOrderNotifier.cancel(context, orderId)
            return
        }

        IncomingOrderNotifier.cancel(context, orderId)
        val isRide = IncomingOrderNotifier.isRide(payload)
        MainActivity.notifyDart(
            "resolved",
            mapOf(
                "orderId" to orderId,
                "action" to IncomingOrderNotifier.ACTION_REJECT,
                "type" to (payload["type"] ?: ""),
            ),
        )

        // Rides are declined over the socket only; a running app does that on
        // the event above, and otherwise the ride lapses on dispatch's timer.
        if (isRide) {
            launchReasonPrompt(context, orderId, payload)
            return
        }

        val pending = goAsync()
        OrderResponder.respond(context.applicationContext, orderId, accept = false) {
            pending.finish()
        }
        launchReasonPrompt(context, orderId, payload)
    }
}
