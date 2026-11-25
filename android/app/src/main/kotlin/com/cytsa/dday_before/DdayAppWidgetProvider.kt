package com.cytsa.dday_before

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class DdayAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DdayAppWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return
            for (id in ids) {
                updateWidget(context, manager, id)
            }
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val rawItems = prefs.getString("flutter.dday_items_v1", null)
            val sortMode = prefs.getString("flutter.dday_sort_mode", "nearest")
            val summary = DdayCalculator.computeWidgetSummary(
                rawItemsJson = rawItems,
                sortMode = sortMode,
                today = DdayCalculator.localToday(),
            )

            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                ?: Intent(context, MainActivity::class.java)

            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val views = RemoteViews(context.packageName, R.layout.dday_widget).apply {
                setTextViewText(R.id.widget_title, summary.title)
                setTextViewText(R.id.widget_subtitle, summary.subtitle)
                setTextViewText(R.id.widget_countdown, summary.countdown)
                setInt(R.id.widget_accent_bar, "setBackgroundColor", summary.accentColor)
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
