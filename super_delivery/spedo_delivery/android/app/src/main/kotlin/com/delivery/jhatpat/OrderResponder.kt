package com.delivery.jhatpat

import android.content.Context
import android.util.Log
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Answers an offer from the lock-screen card, without the app.
 *
 * Reject in particular must not open anything — a rider declining a job should
 * be left where they were — so the call cannot wait for a Flutter engine. Accept
 * goes the same way for speed: the offer window is short and a cold start can
 * eat a meaningful part of it, so the answer is sent first and the app opens
 * afterwards.
 *
 * Credentials come from the mirror `TokenStorage` keeps in ordinary
 * SharedPreferences, because flutter_secure_storage is not readable from here.
 */
object OrderResponder {

    private const val TAG = "OrderResponder"

    /** Written by `TokenStorage._mirrorForNative`; the names must match. */
    private const val PREFS = "FlutterSharedPreferences"
    private const val TOKEN_KEY = "flutter.native_access_token"
    private const val HOST_KEY = "flutter.native_api_base_url"

    private val io = Executors.newSingleThreadExecutor()

    /**
     * PATCHes accept or reject, off the main thread.
     *
     * [onDone] reports whether the server took it, on a background thread. It is
     * advisory: the card has already closed by then, because holding a rider on
     * a spinner while the network decides is worse than letting them go and
     * finding the order in the app.
     */
    fun respond(
        context: Context,
        orderId: String,
        accept: Boolean,
        onDone: ((Boolean) -> Unit)? = null,
    ) {
        if (orderId.isEmpty()) {
            onDone?.invoke(false)
            return
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString(TOKEN_KEY, null)
        val host = prefs.getString(HOST_KEY, null)

        // Not signed in on this device, or an app old enough to predate the
        // mirror. Either way there is nothing to authenticate with.
        if (token.isNullOrEmpty() || host.isNullOrEmpty()) {
            Log.w(TAG, "no stored credentials; cannot answer offer natively")
            onDone?.invoke(false)
            return
        }

        val verb = if (accept) "accept" else "reject"
        val url = "${host.trimEnd('/')}/food/delivery/orders/$orderId/$verb"

        io.execute {
            var connection: HttpURLConnection? = null
            try {
                connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "PATCH"
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Accept", "application/json")
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    doOutput = true
                }
                // An empty body: both endpoints take the order from the path and
                // the rider from the token.
                connection.outputStream.use { it.write("{}".toByteArray()) }

                val code = connection.responseCode
                val ok = code in 200..299
                if (!ok) {
                    val detail = connection.errorStream
                        ?.bufferedReader()
                        ?.use(BufferedReader::readText)
                        .orEmpty()
                    Log.w(TAG, "$verb order $orderId failed: HTTP $code $detail")
                }
                onDone?.invoke(ok)
            } catch (e: Exception) {
                Log.w(TAG, "$verb order $orderId failed: ${e.message}")
                onDone?.invoke(false)
            } finally {
                connection?.disconnect()
            }
        }
    }
}
