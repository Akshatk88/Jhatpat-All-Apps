package com.restaurant.jhatpat

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        /**
         * True while the app is on screen (resumed). NewOrderReceiver leaves a
         * new order to the in-app request screen then — the same push reaches
         * it through FirebaseMessaging.onMessage — instead of raising the
         * overlay and the ringing notification on top of it.
         */
        @Volatile
        var isInForeground = false
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }
}
