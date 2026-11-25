package com.cytsa.dday_before

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DdayAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            DdayNotificationManager.ACTION_REMINDER -> {
                val title = intent.getStringExtra(DdayNotificationManager.EXTRA_TITLE)
                    ?: "D-Day Before 提醒"
                val body = intent.getStringExtra(DdayNotificationManager.EXTRA_BODY) ?: return
                val notifId = intent.getIntExtra(DdayNotificationManager.EXTRA_NOTIF_ID, 20001)
                DdayNotificationManager.postReminderNotification(context, notifId, title, body)
            }
            DdayNotificationManager.ACTION_MIDNIGHT_REFRESH -> {
                DdayNotificationManager.syncAll(context)
            }
        }
    }
}
