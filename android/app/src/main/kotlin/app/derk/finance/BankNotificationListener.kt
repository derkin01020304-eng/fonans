package app.derk.finance

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import java.math.BigDecimal
import java.security.MessageDigest

class BankNotificationListener : NotificationListenerService() {
    companion object {
        @Volatile var sink: EventChannel.EventSink? = null
        @Volatile var unlocked = false
    }
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val listener = sink ?: return
        if (!unlocked) return
        val prefs = getSharedPreferences("notification_import", MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return
        if (!prefs.getStringSet("packages", emptySet())!!.contains(sbn.packageName)) return
        val text = sbn.notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
        if (text.length > 1000 || Regex("код|парол|otp|password|verification|подтверд|вход", RegexOption.IGNORE_CASE).containsMatchIn(text)) return
        val operation = Regex("(покупка|оплата|списание|поступление|зачисление)[^\\d]{0,30}(\\d[\\d\\s\\u00a0]{0,15}(?:[.,]\\d{1,2})?)\\s*(?:₽|руб|RUB)",
            RegexOption.IGNORE_CASE).find(text) ?: return
        val minor = try {
            BigDecimal(operation.groupValues[2].replace(Regex("[\\s\\u00a0]"), "").replace(',', '.'))
                .multiply(BigDecimal(100)).longValueExact()
        } catch (_: Exception) { return }
        if (minor <= 0 || minor > 99999999999999L) return
        val digest = MessageDigest.getInstance("SHA-256").digest(
            (sbn.packageName + "|" + sbn.key + "|" + sbn.postTime + "|" + minor).toByteArray())
            .joinToString("") { "%02x".format(it) }
        val income = operation.groupValues[1].lowercase() in setOf("поступление", "зачисление")
        listener.success(mapOf("id" to digest, "package" to sbn.packageName, "amountMinor" to minor, "income" to income))
    }
}
