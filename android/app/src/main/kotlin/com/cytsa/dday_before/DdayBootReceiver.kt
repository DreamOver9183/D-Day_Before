package com.cytsa.dday_before

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DdayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (shouldResync(intent.action)) {
            DdayNotificationManager.syncAll(context)
            DdayAppWidgetProvider.updateAllWidgets(context)
        }
    }

    companion object {
        private val RESYNC_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )

        /** 開機、時間／時區／日期變更、App 更新後需重新排程提醒並更新小工具。 */
        fun shouldResync(action: String?): Boolean = action != null && action in RESYNC_ACTIONS
    }
}
