package com.cytsa.dday_before

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.util.Calendar

object DdayNotificationManager {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val META_PREFS = "dday_alarm_meta"
    private const val KEY_REQUEST_CODES = "scheduled_request_codes"

    const val CHANNEL_REMINDERS = "dday_reminders"
    const val CHANNEL_ONGOING = "dday_ongoing"
    const val ONGOING_NOTIFICATION_ID = 1001
    const val MIDNIGHT_REQUEST_CODE = 9001

    const val ACTION_REMINDER = "com.cytsa.dday_before.ACTION_REMINDER"
    const val ACTION_MIDNIGHT_REFRESH = "com.cytsa.dday_before.ACTION_MIDNIGHT_REFRESH"
    const val EXTRA_TITLE = "extra_title"
    const val EXTRA_BODY = "extra_body"
    const val EXTRA_NOTIF_ID = "extra_notif_id"

    fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return NotificationManagerCompat.from(context).areNotificationsEnabled()
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val reminderChannel = NotificationChannel(
            CHANNEL_REMINDERS,
            "D-Day 提醒通知",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "當天或前幾天到期時的提醒通知"
        }

        val ongoingChannel = NotificationChannel(
            CHANNEL_ONGOING,
            "通知列常駐顯示",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "在通知列持續顯示最優先的 D-Day 倒數"
            setShowBadge(false)
        }

        manager.createNotificationChannel(reminderChannel)
        manager.createNotificationChannel(ongoingChannel)
    }

    fun syncAll(context: Context) {
        ensureChannels(context)
        val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val rawItems = flutterPrefs.getString("flutter.dday_items_v1", null)
        val sortMode = flutterPrefs.getString("flutter.dday_sort_mode", "nearest")
        val ongoingEnabled = flutterPrefs.getBoolean("flutter.dday_ongoing_notification", false)
        val reminderTimeRaw = flutterPrefs.getString("flutter.dday_reminder_time", "09:00")

        val items = DdayCalculator.parseItemsJson(rawItems)
        val today = DdayCalculator.localToday()
        val sorted = DdayCalculator.sortDdays(items, sortMode, today)

        updateOngoingNotification(context, ongoingEnabled, sorted, today)
        rescheduleAlarms(context, items, today, reminderTimeRaw)
        scheduleMidnightRefresh(context)
    }

    private fun updateOngoingNotification(
        context: Context,
        enabled: Boolean,
        sorted: List<KotlinDdayItem>,
        today: SimpleYmd,
    ) {
        val manager = NotificationManagerCompat.from(context)
        if (!enabled || sorted.isEmpty() || !hasNotificationPermission(context)) {
            manager.cancel(ONGOING_NOTIFICATION_ID)
            return
        }

        val top = sorted.first()
        val countdown = DdayCalculator.formatCountdown(top, today)
        val targetDate = DdayCalculator.effectiveTargetDate(top, today)
        val dateText = DdayCalculator.formatDisplayDateZh(targetDate)
        val subtitle = DdayCalculator.anniversarySubtitle(top, today)
        val contentText = if (subtitle != null) "$dateText・$subtitle" else dateText

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
            ?: Intent(context, MainActivity::class.java)

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ONGOING)
            .setSmallIcon(android.R.drawable.ic_menu_today)
            .setContentTitle("${top.title}：$countdown")
            .setContentText(contentText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()

        try {
            manager.notify(ONGOING_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Permission revoked concurrently
        }
    }

    private fun rescheduleAlarms(
        context: Context,
        items: List<KotlinDdayItem>,
        today: SimpleYmd,
        reminderTimeRaw: String?,
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val metaPrefs = context.getSharedPreferences(META_PREFS, Context.MODE_PRIVATE)

        // Cancel previously scheduled alarms
        val prevCodes = metaPrefs.getString(KEY_REQUEST_CODES, "")
            ?.split(",")
            ?.mapNotNull { it.trim().toIntOrNull() }
            ?: emptyList()
        for (code in prevCodes) {
            val cancelIntent = Intent(context, DdayAlarmReceiver::class.java).apply {
                action = ACTION_REMINDER
            }
            val pi = PendingIntent.getBroadcast(
                context,
                code,
                cancelIntent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )
            if (pi != null) {
                alarmManager.cancel(pi)
                pi.cancel()
            }
        }

        val (hour, minute) = DdayCalculator.parseReminderTime(reminderTimeRaw)
        val upcoming = DdayCalculator.computeScheduledReminders(
            items = items,
            today = today,
            nowMillis = System.currentTimeMillis(),
            hour = hour,
            minute = minute,
        )

        val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }

        val activeCodes = mutableListOf<Int>()
        for (reminder in upcoming) {
            val intent = Intent(context, DdayAlarmReceiver::class.java).apply {
                action = ACTION_REMINDER
                putExtra(EXTRA_TITLE, reminder.title)
                putExtra(EXTRA_BODY, reminder.body)
                putExtra(EXTRA_NOTIF_ID, reminder.requestCode)
            }
            val pi = PendingIntent.getBroadcast(
                context,
                reminder.requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            try {
                if (canExact) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        reminder.triggerAtMillis,
                        pi,
                    )
                } else {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        reminder.triggerAtMillis,
                        pi,
                    )
                }
                activeCodes.add(reminder.requestCode)
            } catch (_: SecurityException) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    reminder.triggerAtMillis,
                    pi,
                )
                activeCodes.add(reminder.requestCode)
            }
        }

        metaPrefs.edit()
            .putString(KEY_REQUEST_CODES, activeCodes.joinToString(","))
            .apply()
    }

    fun scheduleMidnightRefresh(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val cal = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }
        val intent = Intent(context, DdayAlarmReceiver::class.java).apply {
            action = ACTION_MIDNIGHT_REFRESH
        }
        val pi = PendingIntent.getBroadcast(
            context,
            MIDNIGHT_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC, cal.timeInMillis, pi)
    }

    fun postReminderNotification(
        context: Context,
        notifId: Int,
        title: String,
        body: String,
    ) {
        ensureChannels(context)
        if (!hasNotificationPermission(context)) return

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
            ?: Intent(context, MainActivity::class.java)

        val pi = PendingIntent.getActivity(
            context,
            notifId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_REMINDERS)
            .setSmallIcon(android.R.drawable.ic_menu_today)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pi)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(notifId, notification)
        } catch (_: SecurityException) {
            // Permission revoked
        }
    }
}
