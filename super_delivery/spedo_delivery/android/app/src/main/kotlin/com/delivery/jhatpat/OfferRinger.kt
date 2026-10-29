package com.delivery.jhatpat

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Rings an offer while the phone is on silent or vibrate.
 *
 * The offer notification's own tone ([IncomingOrderNotifier], FLAG_INSISTENT)
 * plays on a ringtone-class stream, which Android mutes in silent/vibrate mode:
 * riders on silent saw the card but heard nothing. In that mode this loops the
 * same tone on the ALARM stream, which the ringer switch does not mute. In
 * normal mode it does nothing, so the notification stays the one source of
 * sound and nothing ever rings twice.
 */
object OfferRinger {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var ringingFor: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { stopAll() }

    /** Starts for [orderId] if the ringer is not audible; stops after [seconds]. */
    fun startIfSilent(context: Context, orderId: String, seconds: Int, force: Boolean = false) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        // [force]: the offer channel is muted, so the notification makes no
        // sound even with the ringer on.
        if (!force && audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) return
        synchronized(this) {
            if (ringingFor == orderId && player != null) return
            stopLocked()
            ringingFor = orderId
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    setDataSource(
                        context.applicationContext,
                        Uri.parse("android.resource://${context.packageName}/raw/tujh_bin1"),
                    )
                    isLooping = true
                    prepare()
                    start()
                }
            } catch (_: Exception) {
                player?.release()
                player = null
            }
            vibrate(context)
            // Same window as the notification's own timeout, so a missed offer
            // never keeps ringing after it has expired.
            handler.removeCallbacks(timeout)
            handler.postDelayed(timeout, seconds.coerceIn(1, 300) * 1000L)
        }
    }

    /** Stops ringing for [orderId] (or whatever is ringing when null). */
    fun stop(orderId: String? = null) {
        synchronized(this) {
            if (orderId != null && ringingFor != null && ringingFor != orderId) return
            stopLocked()
        }
    }

    private fun stopAll() = synchronized(this) { stopLocked() }

    private fun stopLocked() {
        handler.removeCallbacks(timeout)
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
        ringingFor = null
    }

    private fun vibrate(context: Context) {
        try {
            val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                    .defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            val pattern = longArrayOf(0, 600, 400, 600, 1200)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
            vibrator = v
        } catch (_: Exception) {
        }
    }
}
