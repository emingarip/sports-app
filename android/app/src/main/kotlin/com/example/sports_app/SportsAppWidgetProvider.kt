package com.example.sports_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SportsAppWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                // Background update using home_widget Key-Value store
                val homeTeam = widgetData.getString("widget_home_team", "Ev Sahibi")
                val awayTeam = widgetData.getString("widget_away_team", "Deplasman")
                val homeScore = widgetData.getInt("widget_home_score", 0)
                val awayScore = widgetData.getInt("widget_away_score", 0)

                setTextViewText(R.id.widget_home_team, homeTeam)
                setTextViewText(R.id.widget_away_team, awayTeam)
                setTextViewText(R.id.widget_home_score, homeScore.toString())
                setTextViewText(R.id.widget_away_score, awayScore.toString())
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
