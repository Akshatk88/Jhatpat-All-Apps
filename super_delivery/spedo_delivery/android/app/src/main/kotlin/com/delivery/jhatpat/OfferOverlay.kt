package com.delivery.jhatpat

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
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.JSONMessageCodec
import org.json.JSONObject

/**
 * Opens the Flutter offer card (lib/core/services/order_overlay_service.dart,
 * the same `OfferRequestView` as the in-app screens) over other apps, straight
 * off the FCM broadcast.
 *
 * Driven from here rather than from the Dart background handler because this
 * receiver runs on every push, at once, with no engine to boot — the Dart
 * handler may not run at all on some ROMs. The overlay engine boots inside
 * `OverlayService.onCreate` when it does not exist yet.
 *
 * Only the plugin's public surface is used: its service class, its
 * `isRunning` flag, its cached-engine tag and its message channel name. The
 * window geometry is the plugin's default (full width and height), which is
 * what the card needs.
 *
 * The overlay is SILENT. The ringing comes from the offer notification
 * (FLAG_INSISTENT), which is posted next to it without a full-screen intent;
 * the card's sound pill re-posts that notification silently or loudly through
 * [OfferActionReceiver]. One source of sound, and it starts before Flutter has
 * drawn anything.
 */
object OfferOverlay {

    private const val PREFS = "FlutterSharedPreferences"

    /** Read by the overlay engine as `overlay_offer`; the names must match. */
    private const val PAYLOAD_KEY = "flutter.overlay_offer"

    /** flutter_overlay_window's own names (OverlayConstants); must match. */
    private const val ENGINE_TAG = "myCachedEngine"
    private const val MESSENGER = "x-slayer/overlay_messenger"
    private const val PLUGIN_CHANNEL_ID = "Overlay Channel"

    @Volatile
    private var shownOrderId: String? = null

    @Volatile
    private var shownPayload: HashMap<String, String>? = null

    /**
     * Whether the card can go over other apps right now. An overlay window is
     * never drawn above the keyguard, so a locked or dark phone keeps the
     * full-screen-intent path (IncomingOrderActivity over the lock screen).
     */
    fun canShow(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(context)
        ) {
            return false
        }
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isInteractive) return false
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return !keyguard.isKeyguardLocked
    }

    /** Puts [payload] on the overlay card. False when the window could not be started. */
    fun show(context: Context, orderId: String, payload: HashMap<String, String>): Boolean {
        val json = JSONObject().apply { for ((k, v) in payload) put(k, v) }.toString()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(PAYLOAD_KEY, json).commit()
        shownOrderId = orderId
        shownPayload = payload

        // Starting the service again while it is up makes the plugin tear the
        // window down (it calls stopSelf), so a live card only gets new data.
        if (OverlayService.isRunning) {
            sendWithRetries(orderId, json)
            return true
        }

        quietPluginChannel(context)
        return try {
            context.startService(Intent(context, OverlayService::class.java))
            sendWithRetries(orderId, json)
            true
        } catch (_: Exception) {
            // Background-start refused on this ROM: the caller falls back to
            // the native card.
            shownOrderId = null
            shownPayload = null
            false
        }
    }

    /** The payload of the offer on the card, for the card's own actions. */
    fun payloadFor(context: Context, orderId: String): HashMap<String, String>? {
        if (shownOrderId == orderId) shownPayload?.let { return it }
        return try {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(PAYLOAD_KEY, null) ?: return null
            val obj = JSONObject(raw)
            val map = HashMap<String, String>()
            for (key in obj.keys()) map[key] = obj.optString(key)
            map
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Takes the card down — the offer was answered, taken, expired, or the app
     * came to the front. With [orderId], only when the card shows that offer.
     */
    fun close(context: Context, orderId: String? = null) {
        val shown = shownOrderId
        if (orderId != null && shown != null && shown != orderId) return
        shownOrderId = null
        shownPayload = null
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(PAYLOAD_KEY).apply()
        if (!OverlayService.isRunning) return
        // Lets the overlay's Dart side drop its countdown and data, since its
        // engine is cached and outlives the window.
        send("{\"overlayCommand\":\"close\"}")
        try {
            context.stopService(Intent(context, OverlayService::class.java))
        } catch (_: Exception) {
        }
    }

    private fun send(json: String) {
        val engine = FlutterEngineCache.getInstance().get(ENGINE_TAG) ?: return
        try {
            BasicMessageChannel<Any>(engine.dartExecutor, MESSENGER, JSONMessageCodec.INSTANCE)
                .send(json)
        } catch (_: Exception) {
        }
    }

    /**
     * The overlay engine may still be booting, and a message sent before its
     * listener exists is dropped. The card also reads the payload from prefs
     * on start; these sends cover a warm engine whose widget is already up.
     */
    private fun sendWithRetries(orderId: String, json: String) {
        val handler = Handler(Looper.getMainLooper())
        for (delay in longArrayOf(0L, 400L, 1_000L, 2_000L, 3_500L)) {
            handler.postDelayed({
                if (shownOrderId == orderId && OverlayService.isRunning) send(json)
            }, delay)
        }
    }

    /**
     * The plugin posts its own foreground-service notification on a channel it
     * creates at default importance, which plays a ding of its own. Creating
     * the channel first, at minimum importance, keeps the offer notification
     * the only thing making a sound. (Android ignores importance changes to an
     * existing channel, so a phone that already has it keeps its old setting.)
     */
    private fun quietPluginChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            if (manager.getNotificationChannel(PLUGIN_CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                PLUGIN_CHANNEL_ID,
                "Offer card",
                NotificationManager.IMPORTANCE_MIN,
            ).apply { setSound(null, null) }
            manager.createNotificationChannel(channel)
        } catch (_: Exception) {
        }
    }

    /**
     * Mirrors the app-side module filter (WorkModeSet.payloadBelongsTo in
     * lib/features/work_mode/data/work_mode.dart — keep the two identical):
     * only the modules that are switched on ring (any combination).
     *
     * - `new_order` (food) rings only when Food is on.
     * - `ride_request` never rings in Food; a parcel (`serviceType` parcel or
     *   delivery) rings only in Parcel, anything else (ride, intercity) only
     *   in Rider.
     *
     * The module is the one WorkModeController last settled on, saved by
     * WorkModePreferenceStore as `work_module` (comma-separated, e.g. `food,parcel`). Food
     * vs taxi is not left to the server: its workMode filter only runs with
     * UNIFIED_DISPATCH_ENABLED, and an offer from a round that started before
     * the switch can still arrive. No saved module, an unknown module, or a
     * ride push that does not say its kind is let through as before — a real
     * offer is never dropped because the payload was thinner than expected.
     */
    fun belongsToModule(context: Context, type: String, payload: Map<String, String>): Boolean {
        val module = try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(MODULE_KEY, null)?.trim()?.lowercase()
        } catch (_: Exception) {
            null
        }
        // Comma-separated set of modules that are on, e.g. "food,parcel".
        val modules = module?.split(",")
            ?.map { it.trim() }
            ?.filter { it in KNOWN_MODULES }
            ?.toSet()
            .orEmpty()
        if (modules.isEmpty()) return true
        if (type == "new_order") return "food" in modules
        if (type != "ride_request") return true
        val ridesOn = "parcel" in modules || "rider" in modules
        if (!ridesOn) return false
        val kind = payload["serviceType"]?.trim()?.lowercase()
        if (kind.isNullOrEmpty()) return true
        val isParcel = kind == "parcel" || kind == "delivery"
        return if (isParcel) "parcel" in modules else "rider" in modules
    }

    /** WorkModePreferenceStore's key, as the shared_preferences plugin stores it. */
    private const val MODULE_KEY = "flutter.work_module"

    /** WorkMode.name values; anything else is treated as "no module saved". */
    private val KNOWN_MODULES = setOf("food", "parcel", "rider")

    /** Tells the Dart background handler this push was already dealt with here. */
    fun markSeen(context: Context, orderId: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString("flutter.native_offer_seen", orderId).commit()
    }
}
