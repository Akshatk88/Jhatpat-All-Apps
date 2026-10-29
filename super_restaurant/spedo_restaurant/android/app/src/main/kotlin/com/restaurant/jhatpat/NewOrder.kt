package com.restaurant.jhatpat

import android.os.Bundle
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONObject

/**
 * One `new_order` push, read straight off the FCM broadcast's extras.
 *
 * FCM flattens the message's data keys into the intent extras next to its own
 * bookkeeping (`google.*`, `gcm.*`, `from`, `collapse_key`); only the data keys
 * are kept, so [data] is the same map Dart sees as `RemoteMessage.data`.
 *
 * The text helpers mirror lib/core/services/fcm_service.dart
 * (buildOrderNotificationTitle / buildOrderNotificationBody / _encodeTapPayload)
 * so the native alert reads exactly like the one Dart posts.
 */
class NewOrder private constructor(
    /** orderMongoId, else orderId — the Dart side's `_orderIdFromData`. */
    val orderId: String,
    val data: HashMap<String, String>,
    /** When the order stops being acceptable (epoch ms). */
    val deadlineMs: Long,
) {
    companion object {
        const val TYPE = "new_order"

        /** Same as the in-app screen and the overlay (`_defaultAcceptWindow`). */
        private const val DEFAULT_WINDOW_MS = 60_000L

        /** `_kRequestCardKeys` in fcm_service.dart. */
        private val REQUEST_CARD_KEYS = listOf(
            "orderDisplayId",
            "customerName",
            "itemCount",
            "itemsList",
            "address",
            "total",
            "paymentMethod",
            "acceptanceDeadlineAt",
        )

        private val FCM_KEYS = setOf("from", "collapse_key", "message_type")

        fun from(extras: Bundle?): NewOrder? {
            if (extras == null) return null
            val data = HashMap<String, String>()
            for (key in extras.keySet()) {
                if (key.startsWith("google.") || key.startsWith("gcm.") ||
                    key.startsWith("androidx.") || key in FCM_KEYS
                ) {
                    continue
                }
                @Suppress("DEPRECATION")
                val value = extras.get(key)
                if (value is String) data[key] = value
            }
            if (data["type"] != TYPE) return null

            val id = data["orderMongoId"]?.takeIf { it.isNotBlank() }
                ?: data["orderId"]?.takeIf { it.isNotBlank() }
                ?: return null

            // A deadline already behind the device clock is more likely clock
            // skew than a dead order — same rule as OrderOverlayService.
            val now = System.currentTimeMillis()
            val server = parseIsoMillis(data["acceptanceDeadlineAt"])
            val deadline = if (server != null && server > now) server else now + DEFAULT_WINDOW_MS
            return NewOrder(id, data, deadline)
        }

        /**
         * ISO-8601 to epoch ms: `…Z`, an explicit offset, or no zone at all
         * (Dart's `toIso8601String()` of a local DateTime), read as local time.
         */
        fun parseIsoMillis(raw: String?): Long? {
            val text = raw?.trim().orEmpty()
            if (text.isEmpty()) return null
            try {
                return Instant.parse(text).toEpochMilli()
            } catch (_: Exception) {
            }
            try {
                return OffsetDateTime.parse(text).toInstant().toEpochMilli()
            } catch (_: Exception) {
            }
            try {
                return LocalDateTime.parse(text).atZone(ZoneId.systemDefault())
                    .toInstant().toEpochMilli()
            } catch (_: Exception) {
            }
            return null
        }

        /** UTC ISO-8601 that Dart's `DateTime.tryParse` reads back exactly. */
        fun formatIsoUtc(millis: Long): String {
            val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            format.timeZone = TimeZone.getTimeZone("UTC")
            return format.format(Date(millis))
        }

        private fun nonEmpty(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

        /** `orderPaymentLabel` in incoming_order_request_view.dart. */
        private fun paymentLabel(method: String?): String? {
            val m = method?.trim()?.lowercase(Locale.ROOT).orEmpty()
            if (m.isEmpty()) return null
            if (m.contains("cash") || m == "cod") return "Cash"
            return "Online"
        }
    }

    /** "New order ₹total", else the server's title. */
    fun title(): String {
        val total = nonEmpty(data["total"])?.toDoubleOrNull()
        if (total != null && total > 0) {
            val amount = if (total == Math.rint(total)) {
                String.format(Locale.US, "%.0f", total)
            } else {
                String.format(Locale.US, "%.2f", total)
            }
            return "New order ₹$amount"
        }
        return nonEmpty(data["title"]) ?: "New order received"
    }

    /** Customer (and payment), items, address — or the server's body. */
    fun body(): String {
        val lines = mutableListOf<String>()
        val customer = nonEmpty(data["customerName"])
        val payment = paymentLabel(nonEmpty(data["paymentMethod"]))
        val items = nonEmpty(data["itemsList"])
        val address = nonEmpty(data["address"])
        if (customer != null) lines += if (payment != null) "$customer  ·  $payment" else customer
        if (items != null) lines += items
        if (address != null) lines += address
        if (lines.isNotEmpty()) return lines.joinToString("\n")

        nonEmpty(data["body"])?.let { return it }
        val ref = nonEmpty(data["orderDisplayId"]) ?: nonEmpty(data["orderId"])
        return if (ref != null) "Order #$ref is waiting for review." else ""
    }

    /**
     * The notification payload the Dart side decodes (`_decodeTapPayload`):
     * the tap and the full-screen launch open the request screen from it,
     * and Accept/Reject read `orderId` from it.
     */
    fun tapPayload(): String {
        val card = JSONObject()
        for (key in REQUEST_CARD_KEYS) {
            nonEmpty(data[key])?.let { card.put(key, data[key]) }
        }
        return JSONObject()
            .put("type", TYPE)
            .put("orderId", orderId)
            .put("data", card)
            .toString()
    }
}
