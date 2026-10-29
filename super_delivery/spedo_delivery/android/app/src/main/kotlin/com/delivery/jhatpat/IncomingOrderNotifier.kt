package com.delivery.jhatpat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Collections
import java.util.Locale

/**
 * Posts the incoming-order alert as a call-style notification whose full-screen
 * intent opens [IncomingOrderActivity].
 *
 * Built natively rather than from Dart because this has to work when the app is
 * dead. The Dart path could only run after the background isolate had spun up a
 * Flutter engine; by then the rider has often missed the offer, and on ROMs that
 * refuse to start the isolate at all it never ran. A broadcast receiver plus a
 * plain Android notification has no such dependency.
 *
 * Android decides for itself whether a full-screen intent actually takes over
 * the screen: locked or otherwise idle, the activity launches; while the rider
 * is using the phone, the same notification shows as a heads-up banner instead.
 * That is the platform contract, not something the app can override — which is
 * why the notification carries the job summary and its own Accept / Reject.
 *
 * It rings until it is dealt with: FLAG_INSISTENT repeats the channel's sound
 * until the notification is cancelled — on accept, reject, expiry, or the offer
 * being withdrawn — or re-posted silently by the card's sound pill.
 */
object IncomingOrderNotifier {

    /**
     * A new id, not the `_v4` the Dart alert used.
     *
     * Android freezes a channel's sound, importance and DND behaviour the moment
     * it is first created and ignores every later edit — so on any phone that
     * already had `_v4`, the ringtone and call-importance set below would simply
     * not apply. The only way to change them is a channel the device has not
     * seen before. Bump this again if these settings ever change.
     */
    const val CHANNEL_ID = "incoming_orders_channel_v5"

    private const val CHANNEL_NAME = "Incoming Orders"

    /** Food offers: the push itself says "You have 60 seconds to accept". */
    private const val FOOD_OFFER_SECONDS = 60

    /** Ride pushes carry no window; the native alert has always used this. */
    private const val RIDE_OFFER_SECONDS = 45

    const val EXTRA_PAYLOAD = "fsi_payload"
    const val EXTRA_ORDER_ID = "fsi_order_id"
    const val EXTRA_ACTION = "fsi_action"

    const val ACTION_ACCEPT = "accept"
    const val ACTION_REJECT = "reject"
    const val ACTION_OPEN = "open"

    /**
     * Same arithmetic everywhere so an alert can be taken down by whoever learns
     * the offer is gone — the withdrawal push, or Dart once the rider has dealt
     * with it.
     *
     * Note this is Java's `String.hashCode`, which is not the same value Dart's
     * `String.hashCode` produces. Nothing may assume the two agree; Dart cancels
     * through the method channel so this function stays the only definition.
     */
    fun notificationId(orderId: String): Int = orderId.hashCode() and 0x7fffffff

    fun isRide(payload: Map<String, String>): Boolean = payload["type"] == "ride_request"

    /** How long the offer stays takeable, from the payload when it says. */
    fun offerSeconds(payload: Map<String, String>): Int {
        val sent = (payload["expiresInSec"] ?: payload["expiresInSeconds"])
            ?.toDoubleOrNull()?.toInt()
        if (sent != null && sent > 0) return sent.coerceAtMost(300)
        return if (isRide(payload)) RIDE_OFFER_SECONDS else FOOD_OFFER_SECONDS
    }

    /** The first positive figure among [keys], or null — never a made-up 0. */
    fun amount(payload: Map<String, String>, vararg keys: String): Double? =
        keys.asSequence()
            .mapNotNull { payload[it]?.trim()?.toDoubleOrNull() }
            .firstOrNull { it > 0 }

    fun money(value: Double): String =
        if (value == Math.floor(value)) value.toLong().toString() else String.format(Locale.US, "%.2f", value)

    /** Rider payout for the offer — food and ride name it differently. */
    fun payout(payload: Map<String, String>): Double? =
        amount(payload, "earningAmount", "riderEarning", "earnings", "fare", "price")

    fun bonus(payload: Map<String, String>): Double? =
        amount(payload, "bonus", "incentive", "tip")

    fun pickupText(payload: Map<String, String>): String? =
        listOf("restaurantName", "restaurantAddress", "pickupAddress")
            .firstNotNullOfOrNull { payload[it]?.takeIf { v -> v.isNotBlank() } }

    fun dropText(payload: Map<String, String>): String? =
        listOf("dropAddress", "customerAddress", "customerName")
            .firstNotNullOfOrNull { payload[it]?.takeIf { v -> v.isNotBlank() } }

    /** The push's own notification block, when the backend sent one. */
    fun pushTitle(payload: Map<String, String>): String? =
        (payload["gcm.notification.title"] ?: payload["gcm.n.title"])?.takeIf { it.isNotBlank() }

    fun pushBody(payload: Map<String, String>): String? =
        (payload["gcm.notification.body"] ?: payload["gcm.n.body"])?.takeIf { it.isNotBlank() }

    /**
     * The channel id the backend names on the FCM tray copy of a food offer
     * (order.helpers.js `androidChannelId`). The OS draws that copy against it
     * directly, and an id the device has never seen is dropped to the manifest
     * default, so it is created here — high importance, same tone — to keep the
     * backup alert loud on ROMs where nothing else of ours gets to run.
     */
    private const val BACKUP_CHANNEL_ID = "new_order_channel_v2"

    /**
     * What the rider has done to the offer channel in system settings, for the
     * setup screen. A channel's importance can be lowered by the user but never
     * raised by the app, so a lowered one is reported rather than "fixed".
     *
     * `ok` means the offer would actually ring and pop up: importance HIGH or
     * above and a sound still set.
     */
    fun channelStatus(context: Context): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf("exists" to true, "ok" to true, "importance" to 4)
        }
        ensureChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        val channel = manager.getNotificationChannel(CHANNEL_ID)
            ?: return mapOf("exists" to false, "ok" to false, "importance" to 0)
        val ok = channel.importance >= NotificationManager.IMPORTANCE_HIGH &&
            channel.sound != null
        return mapOf("exists" to true, "ok" to ok, "importance" to channel.importance)
    }

    /** True when the channel exists but the rider silenced or lowered it. */
    fun isChannelMuted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            val channel = manager.getNotificationChannel(CHANNEL_ID) ?: return false
            channel.importance < NotificationManager.IMPORTANCE_HIGH || channel.sound == null
        } catch (_: Exception) {
            false
        }
    }

    private fun ensureBackupChannel(context: Context, manager: NotificationManager) {
        if (manager.getNotificationChannel(BACKUP_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            BACKUP_CHANNEL_ID,
            "New order alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Backup alert for new orders when the app cannot start"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(
                soundUri(context),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        ensureBackupChannel(context, manager)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Full-screen incoming order alerts that require immediate action"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400)
            // Shown in full on the lock screen: the rider decides whether to
            // pick the job up without unlocking first.
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(
                soundUri(context),
                AudioAttributes.Builder()
                    // Not NOTIFICATION: this competes with whatever the rider is
                    // listening to while riding, and a ringtone-class stream is
                    // what the OS ducks other audio for.
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    private fun soundUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/tujh_bin1")

    /**
     * @param payload the push's data map, forwarded whole so the Dart side can
     *   read whatever it needs without this having to know the schema.
     * @param silent re-posts the same alert without sound — the card's mute.
     * @param fullScreen false when the card is already on screen, so a re-post
     *   does not relaunch it.
     */
    fun show(
        context: Context,
        orderId: String,
        payload: HashMap<String, String>,
        silent: Boolean = false,
        fullScreen: Boolean = true,
    ) {
        ensureChannel(context)

        val title = title(payload)
        val body = describe(payload)
        val open = activityIntent(context, orderId, payload, ACTION_OPEN)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            // The same icon the Dart alerts used, so both paths look like one app.
            .setSmallIcon(R.drawable.ic_stat_jhatpat)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            // CATEGORY_CALL is what earns the call-style treatment: heads-up
            // even in Do Not Disturb, and the right to a full-screen intent.
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            // `ongoing` makes this unswipeable, so it needs its own expiry or a
            // missed offer leaves a permanent, ringing notification for a job
            // that was reassigned within the minute.
            .setTimeoutAfter(offerSeconds(payload) * 1000L)
            .setAutoCancel(true)
            .setContentIntent(open)
            .addAction(
                0,
                "Accept",
                activityIntent(context, orderId, payload, ACTION_ACCEPT),
            )
            .addAction(
                0,
                "Reject",
                OfferActionReceiver.rejectIntent(context, orderId, payload),
            )

        if (silent) {
            builder.setSilent(true).setOnlyAlertOnce(true)
        } else {
            builder.setSound(soundUri(context))
        }
        if (fullScreen) builder.setFullScreenIntent(open, true)

        val notification = builder.build()
        // Repeat the sound until the alert is cancelled — answered, expired or
        // withdrawn. One play of the tone was easy to miss in a pocket.
        if (!silent) notification.flags = notification.flags or Notification.FLAG_INSISTENT

        // POST_NOTIFICATIONS may be refused on Android 13+; notify() then throws
        // rather than no-opping. Losing the alert is bad, crashing a broadcast
        // receiver is worse.
        try {
            NotificationManagerCompat.from(context)
                .notify(notificationId(orderId), notification)
        } catch (_: SecurityException) {
        }
        // Silent/vibrate mode mutes the tone above; ring on the alarm stream then.
        if (silent) {
            OfferRinger.stop(orderId)
        } else {
            // A channel the rider muted or lowered plays nothing of its own, so
            // the alarm-stream ring takes over there too (see OfferRinger).
            OfferRinger.startIfSilent(
                context,
                orderId,
                offerSeconds(payload),
                force = isChannelMuted(context),
            )
        }
        if (!silent) MainActivity.notifyDart("nativeAlertShown", mapOf("orderId" to orderId))
    }

    /**
     * Takes down the plain notification the FCM SDK draws for the same push.
     *
     * Offers are sent with a notification block, so with the app in the
     * background Android posts its own copy (no Accept/Reject, no ringing) next
     * to ours. It is posted by another receiver of the same broadcast, in no
     * guaranteed order, hence the delayed passes. Not done with goAsync: that
     * broadcast is ordered, and holding it would delay FCM's own handling. Only
     * FCM's auto-tagged notification whose title matches this push is touched.
     */
    fun removeFcmCopy(context: Context, payload: Map<String, String>) {
        val pushTitle = pushTitle(payload) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val appContext = context.applicationContext
        val sweep = Runnable {
            try {
                val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
                for (posted in manager.activeNotifications) {
                    val tag = posted.tag ?: continue
                    val title = posted.notification.extras
                        ?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                    if (posted.id == 0 && tag.startsWith("FCM-Notification") && title == pushTitle) {
                        manager.cancel(tag, 0)
                    }
                }
            } catch (_: Exception) {
            }
        }
        val handler = Handler(Looper.getMainLooper())
        handler.post(sweep)
        handler.postDelayed(sweep, 1_500L)
        handler.postDelayed(sweep, 5_000L)
    }

    /**
     * Offers already answered in this process, from any surface — the lock
     * screen card, the notification buttons or the overlay card. One offer can
     * be up on more than one of them, and each has its own button.
     */
    private val answered = Collections.synchronizedSet(HashSet<String>())

    /** True exactly once per offer: the caller that gets it sends the answer. */
    fun claimAnswer(orderId: String): Boolean = orderId.isEmpty() || answered.add(orderId)

    /** A new push for [orderId] is a new offer, answerable again. */
    fun clearAnswered(orderId: String) {
        answered.remove(orderId)
    }

    fun cancel(context: Context, orderId: String) {
        OfferRinger.stop(orderId)
        try {
            NotificationManagerCompat.from(context).cancel(notificationId(orderId))
        } catch (_: Exception) {
        }
        // The full-screen card is a separate surface from the notification;
        // withdrawing one without the other left a live-looking card behind.
        IncomingOrderActivity.closeFor(orderId)
        OfferOverlay.close(context, orderId)
        MainActivity.notifyDart("nativeAlertCleared", mapOf("orderId" to orderId))
    }

    /** "New order ₹30 • 2.3 km" — only the figures the payload actually has. */
    private fun title(payload: Map<String, String>): String {
        val parts = mutableListOf<String>()
        val pay = payout(payload)
        val extra = bonus(payload)
        if (pay != null) {
            parts += if (extra != null) "₹${money(pay)} + ₹${money(extra)}" else "₹${money(pay)}"
        }
        amount(payload, "tripDistanceKm", "distance")?.let { parts += "${String.format(Locale.US, "%.1f", it)} km" }

        val head = if (isRide(payload)) {
            pushTitle(payload) ?: "New ride request"
        } else {
            "New order"
        }
        return if (parts.isEmpty()) head else "$head ${parts.joinToString(" • ")}"
    }

    /** "Pickup → Drop", falling back to the push's own text. */
    private fun describe(payload: Map<String, String>): String {
        val pickup = pickupText(payload)
        val drop = dropText(payload)
        return when {
            pickup != null && drop != null -> "$pickup → $drop"
            pickup != null -> pickup
            drop != null -> "→ $drop"
            else -> pushBody(payload) ?: "Tap to view the offer"
        }
    }

    private fun activityIntent(
        context: Context,
        orderId: String,
        payload: HashMap<String, String>,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, IncomingOrderActivity::class.java).apply {
            // NEW_TASK is required to launch from a receiver; CLEAR_TOP keeps a
            // second offer from stacking a second alert screen behind the first.
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ORDER_ID, orderId)
            putExtra(EXTRA_ACTION, action)
            putExtra(EXTRA_PAYLOAD, payload)
        }

        return PendingIntent.getActivity(
            context,
            requestCode(orderId, action),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Per order *and* per action, or the intents would collide and Accept would
     * silently reuse Open's extras.
     */
    fun requestCode(orderId: String, action: String): Int =
        (notificationId(orderId) + action.hashCode()) and 0x7fffffff
}
