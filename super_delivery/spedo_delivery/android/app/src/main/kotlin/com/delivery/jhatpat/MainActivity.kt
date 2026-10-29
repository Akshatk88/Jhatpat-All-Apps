package com.delivery.jhatpat

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /**
         * True while the app is on screen (resumed). IncomingOrderReceiver uses
         * it to leave an offer to the in-app alert, which the same push raises
         * through FirebaseMessaging.onMessage — otherwise the rider got the
         * Flutter offer screen AND the native card over it for one order, two
         * ringtones, and two Accept buttons for the same job.
         */
        @Volatile
        var isInForeground = false

        /** The live engine's incoming-alert channel, while there is one. */
        @Volatile
        private var incomingChannel: MethodChannel? = null

        /**
         * Tells a running Dart side what the native alert did — that it is
         * ringing for an offer, or that the rider answered it — so the in-app
         * copy of the same offer stops ringing and is cleared. A no-op when the
         * app is dead; the pending-action handoff covers that case.
         */
        fun notifyDart(method: String, args: Map<String, String>) {
            val channel = incomingChannel ?: return
            Handler(Looper.getMainLooper()).post {
                try {
                    channel.invokeMethod(method, args)
                } catch (_: Exception) {
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
        // The app is in front: the in-app offer screen takes over from the
        // over-other-apps card. The notification is left to the Dart side,
        // which takes it down once its own copy of the offer is showing.
        OfferOverlay.close(applicationContext)
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }

    // onPause always precedes these, but the flag is what silences the native
    // alert, so it is cleared on every way out rather than trusted to one.
    override fun onStop() {
        isInForeground = false
        super.onStop()
    }

    override fun onDestroy() {
        isInForeground = false
        super.onDestroy()
    }
    private val CHANNEL = "app.fooddelivery/unlock"
    private val ONLINE_CHANNEL = "app.fooddelivery/rider_online"
    private val READINESS_CHANNEL = "app.fooddelivery/device_readiness"
    private val INCOMING_CHANNEL = "app.fooddelivery/incoming_alert"

    /**
     * What the rider tapped on the lock-screen alert, waiting to be collected.
     *
     * Held rather than pushed because the launch almost always beats Dart to it:
     * the activity is created from the notification long before the Flutter side
     * has a listener attached, and an event sent into the void would be an offer
     * silently dropped. Dart pulls this on startup and on resume instead.
     */
    private var pendingAlertAction: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        capturePendingAlert(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        capturePendingAlert(intent)
    }

    /** Reads the extras [IncomingOrderActivity] hands over, if this launch carried any. */
    private fun capturePendingAlert(source: Intent?) {
        val action = source?.getStringExtra(IncomingOrderNotifier.EXTRA_ACTION) ?: return
        val orderId = source.getStringExtra(IncomingOrderNotifier.EXTRA_ORDER_ID).orEmpty()
        if (orderId.isEmpty()) return

        @Suppress("UNCHECKED_CAST")
        val payload = (source.getSerializableExtra(IncomingOrderNotifier.EXTRA_PAYLOAD)
            as? HashMap<String, String>) ?: HashMap()

        pendingAlertAction = mapOf(
            "action" to action,
            "orderId" to orderId,
            "payload" to payload,
        )

        // Consumed: a configuration change re-delivers the same intent, and
        // replaying it would accept the same order twice.
        source.removeExtra(IncomingOrderNotifier.EXTRA_ACTION)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        incomingChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Created up front so the setup screen can read it, and so a rider who
        // opens the app before the first offer already has the channel.
        IncomingOrderNotifier.ensureChannel(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INCOMING_CHANNEL)
            .also { incomingChannel = it }
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Returns null when the app was opened normally.
                    "consumePendingAction" -> {
                        val pending = pendingAlertAction
                        pendingAlertAction = null
                        result.success(pending)
                    }
                    // Lets Dart take the alert down once it has handled the
                    // offer — the id is computed here so the two sides cannot
                    // disagree about which notification that is.
                    "dismiss" -> {
                        val orderId = call.argument<String>("orderId").orEmpty()
                        if (orderId.isNotEmpty()) {
                            IncomingOrderNotifier.cancel(applicationContext, orderId)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "unlockScreen") {
                unlockScreen()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, READINESS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
                    "notificationsEnabled" ->
                        result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                    "incomingChannelStatus" ->
                        result.success(IncomingOrderNotifier.channelStatus(applicationContext))
                    "openIncomingChannelSettings" -> result.success(openIncomingChannelSettings())
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" ->
                        result.success(openFullScreenIntentSettings())
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations())
                    }
                    "hasAutoStartSettings" -> result.success(resolveAutoStartIntent() != null)
                    "openAutoStartSettings" -> result.success(openAutoStartSettings())
                    "openAppSettings" -> {
                        startActivitySafely(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName"),
                            )
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ONLINE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Failures are reported rather than thrown: going online must
                    // not be blocked by the service. A rider whose OEM refuses the
                    // foreground service still needs to take orders — they just
                    // lose the keep-alive guarantee.
                    "start" -> {
                        try {
                            RiderOnlineService.start(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        try {
                            RiderOnlineService.stop(applicationContext)
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 14 revokes full-screen intents by default for apps that are not
     * calling/alarm apps; without the grant an offer is only a banner. Before
     * 14 the manifest permission is all there is.
     */
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        return try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .canUseFullScreenIntent()
        } catch (_: Exception) {
            true
        }
    }

    private fun openFullScreenIntentSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Literal rather than Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT:
            // identical value, no dependence on the compile SDK exposing it.
            val direct = Intent(
                "android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",
                Uri.parse("package:$packageName"),
            )
            if (startActivitySafely(direct)) return true
        }
        return openAppDetails()
    }

    /** The offer channel's own settings page (sound, importance), else the app's notification page. */
    private fun openIncomingChannelSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, IncomingOrderNotifier.CHANNEL_ID)
            if (startActivitySafely(channel)) return true
            val app = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            if (startActivitySafely(app)) return true
        }
        return openAppDetails()
    }

    private fun openAppDetails(): Boolean = startActivitySafely(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
    )

    /**
     * Whether the OS has been told to stop dozing this app.
     *
     * Without the exemption Android puts the process into Doze when the screen has
     * been off for a while and defers our work regardless of the foreground
     * service, which is how riders "went online" and then quietly stopped being
     * offered orders overnight.
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (isIgnoringBatteryOptimizations()) return true

        // The direct-request dialog is the one-tap path, but Play policy makes it
        // available only to apps that justify it, and some ROMs remove it outright.
        // Fall back to the battery-optimisation list, then to app details, so the
        // button always lands the rider somewhere useful instead of doing nothing.
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        if (startActivitySafely(direct)) return true
        if (startActivitySafely(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) return true
        return startActivitySafely(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        )
    }

    /**
     * The OEM "autostart" / "background run" screen, which is a separate thing from
     * battery optimisation and is the single biggest reason a foreground service
     * still gets killed on Xiaomi, Oppo, Vivo, Realme and Huawei.
     *
     * There is no public API for it. These component names are the documented-by-
     * community paths per vendor, and they move between ROM versions — hence
     * resolving before launching, and reporting honestly when none exists so the UI
     * can hide the step rather than offering a button that does nothing.
     */
    private fun resolveAutoStartIntent(): Intent? {
        val candidates = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            // OnePlus (OxygenOS / ColorOS builds) and newer Oppo/Realme (OPlus).
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            "com.oplus.battery" to "com.oplus.powermanager.fuelgaue.PowerUsageModelActivity",
            "com.oplus.battery" to "com.oplus.battery.BatteryOptimizeActivity",
            "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.asus.mobilemanager" to "com.asus.mobilemanager.entry.FunctionActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
        )

        for ((pkg, cls) in candidates) {
            val intent = Intent().setComponent(ComponentName(pkg, cls))
            if (packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        return null
    }

    private fun openAutoStartSettings(): Boolean {
        val intent = resolveAutoStartIntent() ?: return false
        return startActivitySafely(intent)
    }

    /**
     * Settings screens vary wildly by ROM and some throw on launch even after
     * resolving. Never let that take the app down — the caller reports failure and
     * the UI tells the rider to find the setting manually.
     */
    private fun startActivitySafely(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun unlockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            window.addFlags(
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or 
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }
}
