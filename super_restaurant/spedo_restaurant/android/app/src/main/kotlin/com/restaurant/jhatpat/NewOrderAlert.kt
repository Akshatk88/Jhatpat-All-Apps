package com.restaurant.jhatpat

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver

/**
 * The restaurant's new-order notification, posted natively off the FCM
 * broadcast so it does not depend on the Dart background handler (which never
 * runs for a push that carries an Android notification block, and may not run
 * at all on ROMs that freeze background apps).
 *
 * It is deliberately the SAME notification lib/core/services/
 * local_notification_service.dart posts, so every existing Dart path keeps
 * working on it unchanged:
 *  - identity: id 7001 + tag `new_order_<orderId>` — `cancelOrderAlert`,
 *    `dismissHandledOrderAlerts` and `activeOrderAlertIds` find and cancel it;
 *  - channel `new_order_channel_v2` (tujh_bin), insistent, alarm category;
 *  - tap / full-screen launch / Accept / Reject go through
 *    flutter_local_notifications' own intents (see [launchIntent]), so the
 *    app's `_handleNotificationResponse`, the cold-start launch details and
 *    `notificationBackgroundResponseHandler` (Reject, in a background isolate)
 *    handle them exactly as they handle the Dart-posted alert. No access token
 *    is needed natively.
 */
object NewOrderAlert {

    /** LocalNotificationService._newOrderChannel. Created by the app; never re-defined here. */
    private const val CHANNEL_ID = "new_order_channel_v2"
    private const val CHANNEL_NAME = "Order Alerts"
    private const val CHANNEL_DESCRIPTION = "High priority alerts for new orders."

    /** LocalNotificationService._newOrderNotificationId / _newOrderTagPrefix. */
    private const val NOTIFICATION_ID = 7001
    private const val TAG_PREFIX = "new_order_"

    /** order_notification_action_handler.dart orderAcceptActionId / orderRejectActionId. */
    private const val ACCEPT_ACTION_ID = "accept_order"
    private const val REJECT_ACTION_ID = "reject_order"

    // flutter_local_notifications 18.x intent contract
    // (FlutterLocalNotificationsPlugin.createNotification / extractNotificationResponseMap).
    private const val FLN_SELECT_NOTIFICATION = "SELECT_NOTIFICATION"
    private const val FLN_SELECT_FOREGROUND_ACTION = "SELECT_FOREGROUND_NOTIFICATION"
    private const val FLN_NOTIFICATION_ID = "notificationId"
    private const val FLN_NOTIFICATION_TAG = "notificationTag"
    private const val FLN_ACTION_ID = "actionId"
    private const val FLN_CANCEL_NOTIFICATION = "cancelNotification"
    private const val FLN_PAYLOAD = "payload"

    /** The backend's `androidTag` for the titled FCM copy. */
    private const val FCM_ORDER_TAG_PREFIX = "order_"

    /** What the FCM SDK tags a notification it draws without a tag. */
    private const val FCM_AUTO_TAG_PREFIX = "FCM-Notification"

    /** Channels the untitled FCM copy can land on (backend `default`, or FCM's fallback). */
    private val FCM_EMPTY_COPY_CHANNELS = setOf("default", "fcm_fallback_notification_channel")

    fun tagFor(orderId: String): String = TAG_PREFIX + orderId

    /**
     * Posts the alert. Returns false when it could not be posted (notifications
     * not allowed, or the post was refused).
     *
     * @param silent the overlay is up and ringing for this order: no sound,
     *   no insistent loop, no full-screen intent — one ringing source.
     * @param replace cancel first, so a re-post from silent to loud actually
     *   alerts (`onlyAlertOnce` would swallow it otherwise).
     */
    @SuppressLint("MissingPermission") // checked in canPost
    fun show(context: Context, order: NewOrder, silent: Boolean, replace: Boolean = false): Boolean {
        if (!canPost(context)) return false
        ensureChannel(context)

        val tag = tagFor(order.orderId)
        val payload = order.tapPayload()
        val title = order.title()
        val body = order.body()
        val fullScreen = !silent

        val open = PendingIntent.getActivity(
            context,
            requestCode(order.orderId, 0),
            launchIntent(context, FLN_SELECT_NOTIFICATION).apply {
                putExtra(FLN_NOTIFICATION_ID, NOTIFICATION_ID)
                putExtra(FLN_PAYLOAD, payload)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Accept opens the app (showsUserInterface: true in Dart): the app's
        // own isolate sends the accept with its own session, then lands on the
        // order — also from a cold start, through getNotificationAppLaunchDetails.
        val accept = PendingIntent.getActivity(
            context,
            requestCode(order.orderId, 1),
            launchIntent(context, FLN_SELECT_FOREGROUND_ACTION).apply {
                putActionExtras(this, tag, ACCEPT_ACTION_ID, payload)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Reject opens nothing: the plugin's ActionBroadcastReceiver cancels
        // this notification (by id + tag) and runs
        // notificationBackgroundResponseHandler in a background isolate.
        val reject = PendingIntent.getBroadcast(
            context,
            requestCode(order.orderId, 2),
            Intent(context, ActionBroadcastReceiver::class.java).apply {
                action = ActionBroadcastReceiver.ACTION_TAPPED
                putActionExtras(this, tag, REJECT_ACTION_ID, payload)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            // `alarm`, not `call` — see local_notification_service.dart: MIUI
            // re-skins call notifications and drops their action buttons.
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(fullScreen)
            .setAutoCancel(!fullScreen)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, "Accept", accept)
            .addAction(0, "Reject", reject)

        val remaining = order.deadlineMs - System.currentTimeMillis()
        if (remaining > 0) builder.setTimeoutAfter(remaining)

        if (silent) {
            builder.setSilent(true)
        } else {
            // Pre-O only; on O+ the channel's sound (tujh_bin) applies.
            builder.setSound(soundUri(context))
            if (canUseFullScreenIntent(context)) builder.setFullScreenIntent(open, true)
        }

        val notification = builder.build()
        // Rings until cancelled: accepted, rejected, expired (timeoutAfter) or
        // handled elsewhere (dismissHandledOrderAlerts / overlay).
        if (!silent) notification.flags = notification.flags or Notification.FLAG_INSISTENT

        return try {
            val manager = NotificationManagerCompat.from(context)
            if (replace) manager.cancel(tag, NOTIFICATION_ID)
            manager.notify(tag, NOTIFICATION_ID, notification)
            true
        } catch (_: Exception) {
            // SecurityException without POST_NOTIFICATIONS; never crash a receiver.
            false
        }
    }

    /** Whether this order's alert is still in the tray. */
    fun isShowing(context: Context, orderId: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val tag = tagFor(orderId)
            manager.activeNotifications.any { it.id == NOTIFICATION_ID && it.tag == tag }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Takes down the notifications the FCM SDK draws itself for this push —
     * the backend sends both copies of a new order with an Android
     * notification block, so with the app in the background Android shows:
     *  - the titled copy, tag `order_<orderMongoId>` (id 0), and
     *  - the "data-only" copy: no title/body (so it reads just "Jhatpat
     *    Restaurant"), no tag (the SDK tags it `FCM-Notification:<n>`, id 0),
     *    channel `default`.
     *
     * The SDK posts them from its own receiver of the same broadcast, in no
     * guaranteed order relative to this one, hence the delayed passes. Only
     * untitled, textless FCM copies on those channels, posted in the last
     * moments, are touched.
     */
    fun removeSystemCopies(context: Context, orderId: String) {
        val appContext = context.applicationContext
        val sweep = Runnable { sweepSystemCopies(appContext, orderId) }
        val handler = Handler(Looper.getMainLooper())
        handler.post(sweep)
        handler.postDelayed(sweep, 700L)
        handler.postDelayed(sweep, 2_000L)
        handler.postDelayed(sweep, 5_000L)
    }

    private fun sweepSystemCopies(context: Context, orderId: String) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(FCM_ORDER_TAG_PREFIX + orderId, 0)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

            val appLabel = try {
                context.applicationInfo.loadLabel(context.packageManager).toString().trim()
            } catch (_: Exception) {
                ""
            }
            val now = System.currentTimeMillis()
            for (posted in manager.activeNotifications) {
                if (posted.id != 0) continue
                val tag = posted.tag ?: continue
                if (!tag.startsWith(FCM_AUTO_TAG_PREFIX)) continue
                if (now - posted.postTime > 30_000L) continue
                val notification = posted.notification ?: continue
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    notification.channelId !in FCM_EMPTY_COPY_CHANNELS
                ) {
                    continue
                }
                val extras = notification.extras
                val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
                val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
                if (text.isEmpty() && (title.isEmpty() || title == appLabel)) {
                    manager.cancel(tag, 0)
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun putActionExtras(intent: Intent, tag: String, actionId: String, payload: String) {
        intent.putExtra(FLN_NOTIFICATION_ID, NOTIFICATION_ID)
        intent.putExtra(FLN_NOTIFICATION_TAG, tag)
        intent.putExtra(FLN_ACTION_ID, actionId)
        intent.putExtra(FLN_CANCEL_NOTIFICATION, true)
        intent.putExtra(FLN_PAYLOAD, payload)
    }

    /** The plugin's own launch intent: the launcher intent with its action. */
    private fun launchIntent(context: Context, action: String): Intent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.action = action
        return intent
    }

    /**
     * Per order and per surface, so two orders in the tray never share (and
     * overwrite) each other's intents.
     */
    private fun requestCode(orderId: String, slot: Int): Int =
        ((orderId.hashCode() and 0x0fffffff) * 4 + slot) and 0x7fffffff

    private fun canPost(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** Android 14+ revokes USE_FULL_SCREEN_INTENT by default; without it, a plain heads-up. */
    private fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.canUseFullScreenIntent()
        } catch (_: Exception) {
            false
        }
    }

    private fun soundUri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/raw/tujh_bin")

    /**
     * Only for a device where the app never created the channel yet (normally
     * LocalNotificationService.initialize has). Same id, name, importance and
     * sound as the Dart definition — never a different sound under this id,
     * since Android freezes a channel's sound on first creation.
     */
    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = CHANNEL_DESCRIPTION
                setSound(
                    soundUri(context),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .build(),
                )
            }
            manager.createNotificationChannel(channel)
        } catch (_: Exception) {
        }
    }
}
