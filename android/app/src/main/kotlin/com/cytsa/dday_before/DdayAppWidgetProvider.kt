package com.cytsa.dday_before

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
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

        // 4:3, close to the widget's default 3x2 cell size (centerCrop handles
        // other sizes); RGB_565 keeps the bitmap (~460 KB) under the
        // RemoteViews transaction limit.
        private const val WIDGET_PHOTO_WIDTH = 560
        private const val WIDGET_PHOTO_HEIGHT = 420

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
                setTextColor(R.id.widget_countdown, summary.accentColor)
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            val photo = BackgroundImageStore.loadWidgetBitmap(
                context,
                summary.backgroundImage,
                WIDGET_PHOTO_WIDTH,
                WIDGET_PHOTO_HEIGHT,
            )
            if (photo != null) {
                views.setImageViewBitmap(R.id.widget_bg_image, photo)
                views.setViewVisibility(R.id.widget_bg_image, View.VISIBLE)
                views.setViewVisibility(R.id.widget_scrim, View.VISIBLE)
                views.setTextColor(R.id.widget_title, Color.WHITE)
                views.setTextColor(R.id.widget_subtitle, 0xE6FFFFFF.toInt())
                views.setTextColor(R.id.widget_countdown, Color.WHITE)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
