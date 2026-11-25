package com.cytsa.dday_before

import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

data class SimpleYmd(
    val year: Int,
    val month: Int,
    val day: Int,
) {
    fun toIso(): String =
        "${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}"
}

data class KotlinDdayItem(
    val id: String,
    val title: String,
    val date: String,
    val countFromOne: Boolean,
    val pinned: Boolean,
    val createdAt: String,
    val repeatYearly: Boolean,
    val colorKey: String?,
    val reminderDaysBefore: List<Int>,
)

data class ScheduledReminder(
    val requestCode: Int,
    val triggerAtMillis: Long,
    val title: String,
    val body: String,
    val itemId: String,
    val daysBefore: Int,
)

data class WidgetSummary(
    val title: String,
    val subtitle: String,
    val countdown: String,
    val accentColor: Int,
    val isPinned: Boolean,
)

object DdayCalculator {
    private val ISO_DATE_REGEX = Regex("""^(\d{4})-(\d{2})-(\d{2})$""")
    private val ZH_WEEKDAYS = arrayOf("一", "二", "三", "四", "五", "六", "日")
    private val COLOR_HEX_MAP = mapOf(
        "indigo" to 0xFF3F51B5.toInt(),
        "rose" to 0xFFE11D48.toInt(),
        "amber" to 0xFFD97706.toInt(),
        "emerald" to 0xFF059669.toInt(),
        "sky" to 0xFF0284C7.toInt(),
        "violet" to 0xFF7C3AED.toInt(),
        "coral" to 0xFFEA580C.toInt(),
        "teal" to 0xFF0D9488.toInt(),
    )

    fun colorHexForKey(key: String?): Int {
        return COLOR_HEX_MAP[key] ?: 0xFF3F51B5.toInt()
    }

    fun isLeapYear(year: Int): Boolean {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }

    fun toEpochDay(year: Int, month: Int, day: Int): Long {
        val a = (14 - month) / 12
        val y = year + 4800 - a
        val m = month + 12 * a - 3
        val jdn = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        return jdn.toLong() - 2440588L
    }

    fun fromEpochDay(epochDay: Long): SimpleYmd {
        val jdn = epochDay + 2440588L
        val a = jdn + 32044L
        val b = (4 * a + 3) / 146097L
        val c = a - (146097L * b) / 4L
        val d = (4 * c + 3) / 1461L
        val e = c - (1461L * d) / 4L
        val m = (5 * e + 2) / 153L
        val day = (e - (153 * m + 2) / 5L + 1L).toInt()
        val month = (m + 3L - 12L * (m / 10L)).toInt()
        val year = (100L * b + d - 4800L + m / 10L).toInt()
        return SimpleYmd(year, month, day)
    }

    fun localToday(
        nowMillis: Long = System.currentTimeMillis(),
        timeZone: TimeZone = TimeZone.getDefault(),
    ): SimpleYmd {
        val cal = Calendar.getInstance(timeZone).apply {
            timeInMillis = nowMillis
        }
        return SimpleYmd(
            year = cal.get(Calendar.YEAR),
            month = cal.get(Calendar.MONTH) + 1,
            day = cal.get(Calendar.DAY_OF_MONTH),
        )
    }

    fun parseIsoDate(raw: String): SimpleYmd? {
        val match = ISO_DATE_REGEX.matchEntire(raw) ?: return null
        val y = match.groupValues[1].toIntOrNull() ?: return null
        val m = match.groupValues[2].toIntOrNull() ?: return null
        val d = match.groupValues[3].toIntOrNull() ?: return null
        if (m < 1 || m > 12 || d < 1 || d > 31) return null
        val roundTrip = fromEpochDay(toEpochDay(y, m, d))
        if (roundTrip.year != y || roundTrip.month != m || roundTrip.day != d) {
            return null
        }
        return roundTrip
    }

    fun resolveYearlyDateForYear(year: Int, month: Int, day: Int): SimpleYmd {
        return if (month == 2 && day == 29 && !isLeapYear(year)) {
            SimpleYmd(year, 2, 28)
        } else {
            SimpleYmd(year, month, day)
        }
    }

    fun nextYearlyOccurrence(isoDate: String, today: SimpleYmd): SimpleYmd {
        val orig = parseIsoDate(isoDate) ?: return today
        val thisYear = resolveYearlyDateForYear(today.year, orig.month, orig.day)
        return if (toEpochDay(thisYear.year, thisYear.month, thisYear.day) >=
            toEpochDay(today.year, today.month, today.day)
        ) {
            thisYear
        } else {
            resolveYearlyDateForYear(today.year + 1, orig.month, orig.day)
        }
    }

    fun effectiveTargetDate(item: KotlinDdayItem, today: SimpleYmd): SimpleYmd {
        return if (item.repeatYearly) {
            nextYearlyOccurrence(item.date, today)
        } else {
            parseIsoDate(item.date) ?: today
        }
    }

    fun effectiveDayDiff(item: KotlinDdayItem, today: SimpleYmd): Int {
        val target = effectiveTargetDate(item, today)
        val targetEpoch = toEpochDay(target.year, target.month, target.day)
        val todayEpoch = toEpochDay(today.year, today.month, today.day)
        return (targetEpoch - todayEpoch).toInt()
    }

    fun formatCountdown(item: KotlinDdayItem, today: SimpleYmd): String {
        val diff = effectiveDayDiff(item, today)
        if (item.repeatYearly) {
            return if (diff == 0) "D-Day" else "D-$diff"
        }
        if (item.countFromOne) {
            return if (diff <= 0) "第 ${-diff + 1} 天" else "D-$diff"
        }
        return when {
            diff > 0 -> "D-$diff"
            diff == 0 -> "D-Day"
            else -> "D+${-diff}"
        }
    }

    fun formatDisplayDateZh(ymd: SimpleYmd): String {
        val epochDay = toEpochDay(ymd.year, ymd.month, ymd.day)
        // 1970-01-01 was Thursday (index 3 in 0=Mon..6=Sun)
        val mod = (((epochDay + 3L) % 7L) + 7L) % 7L
        val weekday = ZH_WEEKDAYS[mod.toInt()]
        val y = ymd.year.toString().padStart(4, '0')
        val m = ymd.month.toString().padStart(2, '0')
        val d = ymd.day.toString().padStart(2, '0')
        return "$y/$m/$d ($weekday)"
    }

    fun anniversarySubtitle(item: KotlinDdayItem, today: SimpleYmd): String? {
        if (!item.repeatYearly) return null
        val orig = parseIsoDate(item.date) ?: return "每年重複"
        val next = nextYearlyOccurrence(item.date, today)
        val years = next.year - orig.year
        return if (years > 0) "每年重複・第 $years 週年" else "每年重複"
    }

    fun sortDdays(
        items: List<KotlinDdayItem>,
        sortMode: String?,
        today: SimpleYmd,
    ): List<KotlinDdayItem> {
        val mode = sortMode ?: "nearest"
        return items.sortedWith(Comparator { a, b ->
            if (a.pinned != b.pinned) {
                return@Comparator if (a.pinned) -1 else 1
            }

            val primary = when (mode) {
                "dateAsc" -> {
                    val da = effectiveTargetDate(a, today).toIso()
                    val db = effectiveTargetDate(b, today).toIso()
                    da.compareTo(db)
                }
                "createdDesc" -> b.createdAt.compareTo(a.createdAt)
                else -> {
                    val diffA = effectiveDayDiff(a, today)
                    val diffB = effectiveDayDiff(b, today)
                    val upA = diffA >= 0
                    val upB = diffB >= 0
                    when {
                        upA != upB -> if (upA) -1 else 1
                        upA -> diffA.compareTo(diffB)
                        else -> (-diffA).compareTo(-diffB)
                    }
                }
            }
            if (primary != 0) return@Comparator primary

            val tieCreated = b.createdAt.compareTo(a.createdAt)
            if (tieCreated != 0) return@Comparator tieCreated
            a.id.compareTo(b.id)
        })
    }

    fun parseItemsJson(rawJson: String?): List<KotlinDdayItem> {
        if (rawJson.isNullOrBlank()) return emptyList()
        return try {
            val root = JSONObject(rawJson)
            val arr: JSONArray = root.optJSONArray("items") ?: return emptyList()
            val result = ArrayList<KotlinDdayItem>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val id = obj.optString("id", "").trim()
                val title = obj.optString("title", "").trim()
                val date = obj.optString("date", "").trim()
                if (id.isEmpty() || title.isEmpty() || parseIsoDate(date) == null) {
                    continue
                }
                val repeatYearly = obj.optBoolean("repeatYearly", false)
                val countFromOne = !repeatYearly && obj.optBoolean("countFromOne", false)
                val pinned = obj.optBoolean("pinned", false)
                val createdAt = obj.optString("createdAt", "1970-01-01T00:00:00.000Z")
                val rawColor = obj.optString("colorKey", "").trim()
                val colorKey = if (rawColor.isEmpty() || !COLOR_HEX_MAP.containsKey(rawColor)) {
                    null
                } else {
                    rawColor
                }

                val reminders = mutableSetOf<Int>()
                val remArr = obj.optJSONArray("reminderDaysBefore")
                if (remArr != null) {
                    for (j in 0 until remArr.length()) {
                        val days = remArr.optInt(j, -1)
                        if (days >= 0) {
                            reminders.add(days)
                        }
                    }
                }

                result.add(
                    KotlinDdayItem(
                        id = id,
                        title = title,
                        date = date,
                        countFromOne = countFromOne,
                        pinned = pinned,
                        createdAt = createdAt,
                        repeatYearly = repeatYearly,
                        colorKey = colorKey,
                        reminderDaysBefore = reminders.sorted(),
                    ),
                )
            }
            result
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun parseReminderTime(raw: String?): Pair<Int, Int> {
        if (raw == null) return 9 to 0
        val parts = raw.split(":")
        if (parts.size != 2) return 9 to 0
        val h = parts[0].toIntOrNull() ?: return 9 to 0
        val m = parts[1].toIntOrNull() ?: return 9 to 0
        if (h !in 0..23 || m !in 0..59) return 9 to 0
        return h to m
    }

    fun computeScheduledReminders(
        items: List<KotlinDdayItem>,
        today: SimpleYmd,
        nowMillis: Long,
        hour: Int,
        minute: Int,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): List<ScheduledReminder> {
        val scheduled = mutableListOf<ScheduledReminder>()
        for (item in items) {
            if (item.reminderDaysBefore.isEmpty()) continue
            val target = effectiveTargetDate(item, today)
            val targetEpoch = toEpochDay(target.year, target.month, target.day)
            for (daysBefore in item.reminderDaysBefore) {
                val triggerYmd = fromEpochDay(targetEpoch - daysBefore.toLong())
                val cal = Calendar.getInstance(timeZone).apply {
                    clear()
                    set(Calendar.YEAR, triggerYmd.year)
                    set(Calendar.MONTH, triggerYmd.month - 1)
                    set(Calendar.DAY_OF_MONTH, triggerYmd.day)
                    set(Calendar.HOUR_OF_DAY, hour)
                    set(Calendar.MINUTE, minute)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                val triggerMillis = cal.timeInMillis
                if (triggerMillis <= nowMillis) continue

                val body = when (daysBefore) {
                    0 -> "今天就是「${item.title}」（${formatDisplayDateZh(target)}）"
                    else -> "距離「${item.title}」還有 $daysBefore 天（${formatDisplayDateZh(target)}）"
                }
                val requestCode = ("${item.id}:$daysBefore".hashCode() and 0x0FFFFFFF) + 10000
                scheduled.add(
                    ScheduledReminder(
                        requestCode = requestCode,
                        triggerAtMillis = triggerMillis,
                        title = "D-Day Before 提醒",
                        body = body,
                        itemId = item.id,
                        daysBefore = daysBefore,
                    ),
                )
            }
        }
        return scheduled.sortedBy { it.triggerAtMillis }.take(50)
    }

    fun computeWidgetSummary(
        rawItemsJson: String?,
        sortMode: String?,
        today: SimpleYmd,
    ): WidgetSummary {
        val items = parseItemsJson(rawItemsJson)
        if (items.isEmpty()) {
            return WidgetSummary(
                title = "D-Day Before",
                subtitle = "點擊新增重要日子",
                countdown = "D-Day",
                accentColor = colorHexForKey(null),
                isPinned = false,
            )
        }
        val top = sortDdays(items, sortMode, today).first()
        val countdown = formatCountdown(top, today)
        val targetDate = effectiveTargetDate(top, today)
        val dateText = formatDisplayDateZh(targetDate)
        val repeatText = anniversarySubtitle(top, today)
        val subtitle = if (repeatText != null) "$dateText・$repeatText" else dateText
        val title = if (top.pinned) "📌 ${top.title}" else top.title
        return WidgetSummary(
            title = title,
            subtitle = subtitle,
            countdown = countdown,
            accentColor = colorHexForKey(top.colorKey),
            isPinned = top.pinned,
        )
    }
}
