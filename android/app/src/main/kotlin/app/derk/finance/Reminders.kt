package app.derk.finance

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray

object ReminderScheduler {
    private fun pending(context: Context, id: Int): PendingIntent =
        PendingIntent.getBroadcast(context, id, Intent(context, ReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun replace(context: Context, times: List<Long>) {
        val prefs = context.getSharedPreferences("reminders", Context.MODE_PRIVATE)
        val alarm = context.getSystemService(AlarmManager::class.java)
        val previous = JSONArray(prefs.getString("times", "[]"))
        for (i in 0 until previous.length()) alarm.cancel(pending(context, 2000 + i))
        prefs.edit().putString("times", JSONArray(times.distinct().sorted()).toString()).apply()
        rearm(context)
    }
    fun rearm(context: Context) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val times = JSONArray(context.getSharedPreferences("reminders", Context.MODE_PRIVATE).getString("times", "[]"))
        for (i in 0 until times.length()) {
            val time = times.getLong(i)
            if (time > System.currentTimeMillis()) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pending(context, 2000 + i))
            }
        }
    }
}
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = "finance_reminders"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channel, "Финансовые напоминания", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(context, 1, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
        manager.notify(900, builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Дэрк Финансы")
            .setContentText("Есть запланированные платежи или цели. Откройте приложение.")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(open).setAutoCancel(true).build())
    }
}
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            ReminderScheduler.rearm(context)
        }
    }
}
