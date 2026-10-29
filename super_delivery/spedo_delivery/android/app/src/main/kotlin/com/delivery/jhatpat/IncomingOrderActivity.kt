package com.delivery.jhatpat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import java.lang.ref.WeakReference
import java.util.Locale

/**
 * The screen a rider sees when an offer arrives on a locked or idle phone, or
 * over other apps when "display over other apps" is granted.
 *
 * Deliberately native. Its whole job is to be on screen *immediately*: it draws
 * from the intent extras with no Flutter engine and no network call, because
 * the offer window is under a minute and a cold Flutter start on a budget phone
 * can eat a meaningful part of it. Laid out like the in-app captain-style offer
 * card so the rider sees one design everywhere.
 *
 * It answers the offer itself, through [OrderResponder], rather than handing
 * the choice to Dart. That is forced by Reject: a rider declining a job must be
 * left where they were, so nothing may launch — which rules out doing the work
 * in Dart, since Dart only runs once the app is open. Accept goes the same way
 * for speed, and then opens the app so the rider lands on the job.
 *
 * The app is told what happened but does not repeat the call; see
 * `IncomingAlertChannel` on the Dart side.
 */
class IncomingOrderActivity : Activity() {

    companion object {
        private const val GREEN = 0xFF1E9E5A.toInt()
        private const val RED = 0xFFF04438.toInt()
        private const val GREY = 0xFF6B7280.toInt()

        /** The card on screen, if any, so a withdrawal can close it. */
        private var current: WeakReference<IncomingOrderActivity>? = null

        /**
         * Closes the card if it is showing [orderId]. Called whenever the alert
         * is cancelled — taken by another rider, or answered in the app — so the
         * card does not sit there looking live for an offer that is gone.
         */
        fun closeFor(orderId: String) {
            val activity = current?.get() ?: return
            if (activity.shownOrderId != orderId) return
            activity.runOnUiThread { activity.finish() }
        }
    }

    private var countdown: CountDownTimer? = null
    private var shownOrderId: String = ""
    private var soundOn = true
    private var answered = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Reached through the notification's Accept: the rider has already
        // chosen, so nothing is drawn — straight to the answer.
        if (isAnswer(intent)) {
            answerFrom(intent)
            return
        }
        showOverLockScreen()
        setContentView(R.layout.activity_incoming_order)
        bind(intent)
    }

    /**
     * A full-screen intent launches this while the device is locked, so it has
     * to ask for the lock screen to be shown over — and to wake the screen,
     * since an offer that arrives on a dark phone is one the rider never sees.
     */
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            // Dismisses only a swipe keyguard; with a PIN or pattern set the
            // screen stays above the lock, which is the intended behaviour.
            keyguard.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
    }

    /** A second offer arriving replaces the one on screen rather than stacking. */
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent == null) return
        setIntent(intent)
        if (isAnswer(intent)) {
            answerFrom(intent)
            return
        }
        bind(intent)
    }

    private fun isAnswer(source: Intent): Boolean {
        val action = source.getStringExtra(IncomingOrderNotifier.EXTRA_ACTION)
        return action == IncomingOrderNotifier.ACTION_ACCEPT ||
            action == IncomingOrderNotifier.ACTION_REJECT
    }

    private fun answerFrom(source: Intent) {
        handOff(
            source.getStringExtra(IncomingOrderNotifier.EXTRA_ORDER_ID).orEmpty(),
            payloadOf(source),
            source.getStringExtra(IncomingOrderNotifier.EXTRA_ACTION)
                ?: IncomingOrderNotifier.ACTION_OPEN,
        )
    }

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    private fun payloadOf(source: Intent): HashMap<String, String> =
        (source.getSerializableExtra(IncomingOrderNotifier.EXTRA_PAYLOAD)
            as? HashMap<String, String>) ?: HashMap()

    private fun bind(source: Intent) {
        val payload = payloadOf(source)
        val orderId = source.getStringExtra(IncomingOrderNotifier.EXTRA_ORDER_ID).orEmpty()
        val isRide = IncomingOrderNotifier.isRide(payload)

        shownOrderId = orderId
        answered = false
        soundOn = true
        current = WeakReference(this)

        findViewById<TextView>(R.id.incoming_subtitle).text = when {
            !isRide -> "Food delivery"
            payload["serviceType"] == "parcel" -> "Parcel"
            else -> "Ride"
        }

        // Payout, with the bonus in green when there is one. Hidden rather than
        // shown as ₹0 when the push carries none.
        val pay = IncomingOrderNotifier.payout(payload)
        val bonus = IncomingOrderNotifier.bonus(payload)
        val fareView = findViewById<TextView>(R.id.incoming_fare)
        val railFare = findViewById<TextView>(R.id.incoming_rail_fare)
        val railBonus = findViewById<TextView>(R.id.incoming_rail_bonus)
        if (pay != null) {
            val text = SpannableStringBuilder("₹${IncomingOrderNotifier.money(pay)}")
            if (bonus != null) {
                val start = text.length
                text.append(" + ₹${IncomingOrderNotifier.money(bonus)}")
                text.setSpan(ForegroundColorSpan(GREEN), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            fareView.text = text
            fareView.visibility = View.VISIBLE
            railFare.text = "₹${IncomingOrderNotifier.money(pay)}"
        } else {
            fareView.visibility = View.GONE
            railFare.text = ""
        }
        if (bonus != null) {
            railBonus.text = "+₹${IncomingOrderNotifier.money(bonus)}"
            railBonus.visibility = View.VISIBLE
        } else {
            railBonus.visibility = View.GONE
        }

        // Stop 1: how far *this* rider is from the pickup. Only the socket
        // payload carries it; the push is one message for every rider.
        val pickupKm = IncomingOrderNotifier.amount(payload, "pickupDistanceKm")
        setLeg(
            findViewById(R.id.incoming_pickup_distance),
            pickupKm?.let { km -> km to "(${minsFor(km)} mins)" },
            "PICKUP",
        )
        val restaurant = payload["restaurantName"]?.takeIf { it.isNotBlank() }
        val pickupAddress = (payload["restaurantAddress"]?.takeIf { it.isNotBlank() }
            ?: payload["pickupAddress"]?.takeIf { it.isNotBlank() }).orEmpty()
        findViewById<TextView>(R.id.incoming_pickup).text = if (restaurant != null) {
            place(restaurant, pickupAddress)
        } else {
            // The ride push carries no address field, only "Pickup: <address>"
            // as its notification text.
            placeFromAddress(pickupAddress.ifEmpty {
                IncomingOrderNotifier.pushBody(payload)
                    ?.takeIf { isRide && it.startsWith("Pickup:") }
                    ?.removePrefix("Pickup:")?.trim()
                    ?: "Pickup location"
            })
        }

        // Stop 2: the trip itself.
        val tripKm = IncomingOrderNotifier.amount(payload, "tripDistanceKm", "distance")
        val tripMins = IncomingOrderNotifier.amount(payload, "tripDurationMins")
        setLeg(
            findViewById(R.id.incoming_drop_distance),
            tripKm?.let { km -> km to tripMins?.let { "(${it.toLong()} mins)" } },
            "DROP",
        )
        val dropAddress = payload["dropAddress"]?.takeIf { it.isNotBlank() }
            ?: payload["customerAddress"]?.takeIf { it.isNotBlank() }
        findViewById<TextView>(R.id.incoming_drop).text = if (dropAddress != null) {
            placeFromAddress(dropAddress)
        } else {
            place(payload["customerName"]?.takeIf { it.isNotBlank() } ?: "Drop location", "")
        }

        val accept = findViewById<Button>(R.id.incoming_accept)
        accept.isEnabled = true
        accept.setOnClickListener {
            handOff(orderId, payload, IncomingOrderNotifier.ACTION_ACCEPT)
        }
        findViewById<View>(R.id.incoming_reject).setOnClickListener {
            handOff(orderId, payload, IncomingOrderNotifier.ACTION_REJECT)
        }

        val sound = findViewById<TextView>(R.id.incoming_sound)
        renderSound(sound)
        sound.setOnClickListener {
            soundOn = !soundOn
            renderSound(sound)
            // Re-posting the same alert silently stops the insistent ringing;
            // re-posting it normally starts it again. The offer is untouched.
            IncomingOrderNotifier.show(
                this,
                orderId,
                payload,
                silent = !soundOn,
                fullScreen = false,
            )
        }

        startCountdown(IncomingOrderNotifier.offerSeconds(payload))
        IncomingOrderNotifier.removeFcmCopy(this, payload)
    }

    private fun renderSound(view: TextView) {
        view.text = if (soundOn) "Sound ON" else "Sound OFF"
        view.setTextColor(if (soundOn) Color.parseColor("#111111") else Color.WHITE)
        view.backgroundTintList = ColorStateList.valueOf(
            if (soundOn) Color.parseColor("#FFEDB5") else Color.parseColor("#B9BEC9"),
        )
    }

    /** Distance in bold with the minutes in grey, or a PICKUP/DROP label. */
    private fun setLeg(view: TextView, figures: Pair<Double, String?>?, label: String) {
        if (figures == null) {
            view.text = label
            view.textSize = 11f
            view.setTextColor(GREY)
            view.setTypeface(null, Typeface.BOLD)
            view.letterSpacing = 0.08f
            return
        }
        val text = SpannableStringBuilder(String.format(Locale.US, "%.1f km", figures.first))
        text.setSpan(StyleSpan(Typeface.BOLD), 0, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        figures.second?.let {
            val start = text.length
            text.append(" $it")
            text.setSpan(ForegroundColorSpan(GREY), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            text.setSpan(AbsoluteSizeSpan(13, true), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        view.text = text
        view.textSize = 20f
        view.setTextColor(Color.parseColor("#111111"))
        view.letterSpacing = 0f
    }

    /** Place name in bold, then " - rest of the address" in grey. */
    private fun place(name: String, detail: String): CharSequence {
        val text = SpannableStringBuilder(name)
        text.setSpan(StyleSpan(Typeface.BOLD), 0, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (detail.isNotBlank()) {
            val start = text.length
            text.append(" - ${detail.trim()}")
            text.setSpan(ForegroundColorSpan(GREY), start, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return text
    }

    private fun placeFromAddress(address: String): CharSequence {
        val comma = address.indexOf(',')
        return if (comma > 0) {
            place(address.substring(0, comma).trim(), address.substring(comma + 1))
        } else {
            place(address, "")
        }
    }

    private fun minsFor(km: Double): Long = Math.ceil(km / 20 * 60).toLong().coerceIn(1L, 999L)

    /**
     * Drives both countdown rings and closes the card — and silences the alert
     * — when the window runs out. The window comes from the push when it names
     * one, else 60s for food (what the push text promises) and 45s for rides.
     */
    private fun startCountdown(seconds: Int) {
        val rings = listOf(
            findViewById<ProgressBar>(R.id.incoming_rail_ring),
            findViewById<ProgressBar>(R.id.incoming_reject_ring),
        )
        val totalMs = seconds * 1000L
        rings.forEach {
            it.progress = it.max
            it.progressTintList = ColorStateList.valueOf(GREEN)
        }

        countdown?.cancel()
        countdown = object : CountDownTimer(totalMs, 250L) {
            override fun onTick(remaining: Long) {
                rings.forEach {
                    it.progress = (it.max * remaining / totalMs).toInt()
                    if (remaining <= 5_000L) it.progressTintList = ColorStateList.valueOf(RED)
                }
            }

            override fun onFinish() {
                // Gone to someone else by now. Closing — and stopping the ring —
                // beats leaving a card that looks live and fails on tap.
                if (shownOrderId.isNotEmpty()) {
                    IncomingOrderNotifier.cancel(this@IncomingOrderActivity, shownOrderId)
                }
                finish()
            }
        }.also { it.start() }
    }

    override fun onDestroy() {
        countdown?.cancel()
        countdown = null
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    /**
     * Sends the rider's answer, then gets out of the way.
     *
     * The call goes out from here rather than from Dart because Reject must not
     * open the app — a rider declining a job should be left doing whatever they
     * were doing. Accept is sent the same way so the answer is in flight while
     * the app is still starting, which on a cold start is several seconds of a
     * short offer window.
     *
     * The alert is cancelled first: the offer has been answered either way, and
     * leaving a notification ringing behind the rider's decision would be the
     * most confusing possible outcome.
     */
    private fun handOff(orderId: String, payload: HashMap<String, String>, action: String) {
        // A double tap, or the notification's Accept racing the card's, must not
        // answer the same offer twice.
        if (answered) return
        answered = true
        countdown?.cancel()
        // Same guard across every surface (this card, the notification, the
        // overlay card): whoever answered first wins, the rest just close.
        if (action != IncomingOrderNotifier.ACTION_OPEN &&
            !IncomingOrderNotifier.claimAnswer(orderId)
        ) {
            if (orderId.isNotEmpty()) IncomingOrderNotifier.cancel(this, orderId)
            finish()
            return
        }
        if (orderId.isNotEmpty()) IncomingOrderNotifier.cancel(this, orderId)

        val accepted = action == IncomingOrderNotifier.ACTION_ACCEPT
        val isRide = IncomingOrderNotifier.isRide(payload)
        if (action != IncomingOrderNotifier.ACTION_OPEN) {
            // A running app clears its own copy of the offer on this, so the
            // same job cannot be answered a second time from inside it.
            MainActivity.notifyDart(
                "resolved",
                mapOf("orderId" to orderId, "action" to action, "type" to (payload["type"] ?: "")),
            )
        }
        // Rides are claimed over the socket only — OrderResponder's
        // /food/delivery/orders/:id/accept knows nothing of a ride id. The
        // choice is handed to Dart (IncomingAlertChannel), which claims it once;
        // a declined ride is told to the server by a running app, or lapses on
        // the dispatch timer.
        if (action != IncomingOrderNotifier.ACTION_OPEN && !isRide) {
            OrderResponder.respond(applicationContext, orderId, accept = accepted)
        }

        // Rejecting is the whole point of not launching anything: the app stays
        // closed and the rider keeps their screen. Tapping the card itself
        // (ACTION_OPEN) still opens the app without answering for them.
        if (!accepted && action != IncomingOrderNotifier.ACTION_OPEN) {
            // Rejected: the offer is answered, but the driver is asked why in-app.
            OfferActionReceiver.launchReasonPrompt(this, orderId, payload)
            finish()
            return
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(IncomingOrderNotifier.EXTRA_ORDER_ID, orderId)
            putExtra(IncomingOrderNotifier.EXTRA_ACTION, action)
            putExtra(IncomingOrderNotifier.EXTRA_PAYLOAD, payload)
        }
        startActivity(intent)
        finish()
    }
}
