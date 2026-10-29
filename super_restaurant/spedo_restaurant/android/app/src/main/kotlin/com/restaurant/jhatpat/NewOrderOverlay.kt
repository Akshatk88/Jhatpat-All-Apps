package com.restaurant.jhatpat

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import flutter.overlay.window.flutter_overlay_window.NativeOverlayWindowSetup
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.JSONMessageCodec
import org.json.JSONArray
import org.json.JSONObject

/**
 * Opens the over-other-apps new-order request (the Dart `OrderOverlayApp`,
 * entry point `overlayMain`) straight off the FCM broadcast — the native twin
 * of `OrderOverlayService.showForOrder` in
 * lib/core/services/order_overlay_service.dart, for when no Dart isolate
 * runs for the push.
 *
 * The overlay's single source of truth is its pending list in
 * SharedPreferences (`overlay_pending_orders`, i.e. `flutter.`-prefixed in the
 * `FlutterSharedPreferences` file the shared_preferences plugin uses, stored
 * as a plain JSON string). This writes the order there in the exact
 * `OverlayOrder.toJson` shape, starts the plugin's OverlayService (which boots
 * the overlay engine itself when there is none) and nudges the engine with the
 * same `sync` message the app sends. The overlay rings (looped tujh_bin) —
 * the caller posts the tray notification silent.
 */
object NewOrderOverlay {

    private const val PREFS = "FlutterSharedPreferences"

    /** `_pendingKey` in order_overlay_service.dart, with the plugin's prefix. */
    private const val PENDING_KEY = "flutter.overlay_pending_orders"

    /** `overlaySyncMessage` in order_overlay_service.dart. */
    private const val SYNC_MESSAGE = "sync"

    /** flutter_overlay_window 0.5.0 OverlayConstants (package-private there). */
    private const val ENGINE_TAG = "myCachedEngine"
    private const val MESSENGER = "x-slayer/overlay_messenger"
    private const val PLUGIN_CHANNEL_ID = "Overlay Channel"

    /** Same initial window as showForOrder (`height: 360`, dp here); the overlay then fits it to the card. */
    private const val INITIAL_HEIGHT_DP = 360

    /** Where OrderOverlayApp._fitWindowToCard puts the window: just below the status bar. */
    private const val TOP_DP = 32

    /**
     * An overlay window is never drawn above the keyguard: a locked or dark
     * phone gets the full-screen notification instead.
     */
    fun canShow(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(context)
        ) {
            return false
        }
        return try {
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            power.isInteractive && !keyguard.isKeyguardLocked
        } catch (_: Exception) {
            false
        }
    }

    /** Queues [order] on the overlay and shows it. False when the window could not be started. */
    fun show(context: Context, order: NewOrder): Boolean {
        if (!writePending(context, order)) return false

        // Starting the service again while it is up makes the plugin tear the
        // window down and rebuild it; a live overlay only needs to re-read.
        if (OverlayService.isRunning) {
            syncWithRetries()
            return true
        }

        quietPluginChannel(context)
        val density = context.resources.displayMetrics.density
        // Started from here the plugin's window settings are its defaults
        // (CENTER gravity, full screen) — set the ones the Dart side uses, so
        // the card opens at the top and _fitWindowToCard's moveOverlay(0, 32)
        // means the same thing on both start paths.
        NativeOverlayWindowSetup.configureTopCard(
            (INITIAL_HEIGHT_DP * density).toInt(),
            "New order",
            "A new order is waiting for you",
        )
        return try {
            val intent = Intent(context, OverlayService::class.java).apply {
                putExtra("startX", 0)
                putExtra("startY", TOP_DP)
            }
            context.startService(intent)
            syncWithRetries()
            true
        } catch (_: Exception) {
            // Background service start refused on this ROM: the caller falls
            // back to the ringing notification.
            false
        }
    }

    fun isRunning(): Boolean = OverlayService.isRunning

    /**
     * Same edit as showForOrder: drop this order's previous entry and any
     * expired one, append the new one.
     */
    private fun writePending(context: Context, order: NewOrder): Boolean {
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val pending = JSONArray()
            val raw = prefs.getString(PENDING_KEY, null)
            if (!raw.isNullOrEmpty()) {
                val existing = try {
                    JSONArray(raw)
                } catch (_: Exception) {
                    JSONArray()
                }
                for (i in 0 until existing.length()) {
                    val entry = existing.optJSONObject(i) ?: continue
                    if (entry.optString("orderId") == order.orderId) continue
                    val deadline = NewOrder.parseIsoMillis(entry.optString("deadline"))
                    if (deadline != null && deadline <= now) continue
                    pending.put(entry)
                }
            }

            val windowSeconds = ((order.deadlineMs - now) / 1000L).coerceIn(1L, 3600L)
            val data = JSONObject()
            for ((key, value) in order.data) data.put(key, value)
            pending.put(
                JSONObject()
                    .put("orderId", order.orderId)
                    .put("data", data)
                    .put("deadline", NewOrder.formatIsoUtc(order.deadlineMs))
                    .put("window", windowSeconds.toInt()),
            )
            prefs.edit().putString(PENDING_KEY, pending.toString()).commit()
        } catch (_: Exception) {
            false
        }
    }

    private fun sendSync() {
        val engine = FlutterEngineCache.getInstance().get(ENGINE_TAG) ?: return
        try {
            BasicMessageChannel<Any>(engine.dartExecutor, MESSENGER, JSONMessageCodec.INSTANCE)
                .send(SYNC_MESSAGE)
        } catch (_: Exception) {
        }
    }

    /**
     * The overlay engine may still be booting and drops a message sent before
     * its listener exists. It also re-reads on its own (first frame, window
     * size change, every few seconds), so these only make it quicker.
     */
    private fun syncWithRetries() {
        val handler = Handler(Looper.getMainLooper())
        for (delay in longArrayOf(0L, 400L, 1_000L, 2_000L, 3_500L)) {
            handler.postDelayed({
                if (OverlayService.isRunning) sendSync()
            }, delay)
        }
    }

    /**
     * The plugin posts its foreground-service notification on a channel it
     * creates at default importance, with a ding of its own. Creating it first
     * at minimum importance keeps the overlay the only thing making a sound.
     * (Android ignores later importance changes, so an existing channel keeps
     * its setting.)
     */
    private fun quietPluginChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(PLUGIN_CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                PLUGIN_CHANNEL_ID,
                "New order window",
                NotificationManager.IMPORTANCE_MIN,
            ).apply { setSound(null, null) }
            manager.createNotificationChannel(channel)
        } catch (_: Exception) {
        }
    }
}
