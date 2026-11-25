package com.cytsa.dday_before

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

class DdayCalculatorTest {
    private val today = SimpleYmd(2026, 11, 25)

    @Test
    fun `toEpochDay and formatDisplayDateZh match Dart calculations`() {
        assertEquals("2026/12/25 (五)", DdayCalculator.formatDisplayDateZh(SimpleYmd(2026, 12, 25)))
        assertEquals("2026/11/25 (三)", DdayCalculator.formatDisplayDateZh(SimpleYmd(2026, 11, 25)))
        assertNull(DdayCalculator.parseIsoDate("2025-02-29"))
        assertEquals(SimpleYmd(2024, 2, 29), DdayCalculator.parseIsoDate("2024-02-29"))
    }

    @Test
    fun `formatCountdown handles default, countFromOne, and repeatYearly with Feb 29`() {
        val future = KotlinDdayItem("1", "期末考", "2026-12-25", false, false, "", false, null, emptyList())
        assertEquals("D-30", DdayCalculator.formatCountdown(future, today))

        val anniv = KotlinDdayItem("2", "交往", "2026-11-25", true, false, "", false, null, emptyList())
        assertEquals("1天", DdayCalculator.formatCountdown(anniv, today))

        val leap = KotlinDdayItem("3", "四年一度", "2024-02-29", false, false, "", true, null, emptyList())
        assertEquals("D-1", DdayCalculator.formatCountdown(leap, SimpleYmd(2025, 2, 27)))
        assertEquals("D-Day", DdayCalculator.formatCountdown(leap, SimpleYmd(2025, 2, 28)))
        assertEquals(SimpleYmd(2026, 2, 28), DdayCalculator.nextYearlyOccurrence("2024-02-29", SimpleYmd(2025, 3, 1)))
    }

    @Test
    fun `sortDdays keeps pinned first and sorts nearest properly`() {
        val items = listOf(
            KotlinDdayItem("past", "Past", "2026-11-20", false, false, "2026-11-01T00:00:00Z", false, null, emptyList()),
            KotlinDdayItem("future", "Future", "2026-12-01", false, false, "2026-11-01T00:00:00Z", false, null, emptyList()),
            KotlinDdayItem("pinnedPast", "Pinned", "2026-11-01", false, true, "2026-11-01T00:00:00Z", false, null, emptyList()),
        )
        val sorted = DdayCalculator.sortDdays(items, "nearest", today)
        assertEquals(listOf("pinnedPast", "future", "past"), sorted.map { it.id })
    }

    @Test
    fun `parseItemsJson and computeScheduledReminders handle valid and corrupt payloads`() {
        assertTrue(DdayCalculator.parseItemsJson("{bad json").isEmpty())

        val json = """
            {
              "schemaVersion": 1,
              "items": [
                {
                  "id": "r1",
                  "title": "期末考",
                  "date": "2026-12-25",
                  "countFromOne": false,
                  "pinned": true,
                  "createdAt": "2026-11-25T00:00:00Z",
                  "repeatYearly": false,
                  "colorKey": "indigo",
                  "reminderDaysBefore": [3, 0, 1]
                },
                {
                  "id": "bad",
                  "title": "Bad",
                  "date": "2025-02-29"
                }
              ]
            }
        """.trimIndent()

        val parsed = DdayCalculator.parseItemsJson(json)
        assertEquals(1, parsed.size)
        assertEquals(listOf(0, 1, 3), parsed.first().reminderDaysBefore)

        val tz = TimeZone.getTimeZone("Asia/Taipei")
        val nowMillis = 1795568400000L // ~2026-11-25
        val reminders = DdayCalculator.computeScheduledReminders(
            items = parsed,
            today = today,
            nowMillis = nowMillis,
            hour = 9,
            minute = 0,
            timeZone = tz,
        )
        assertEquals(3, reminders.size)
        assertEquals(listOf(3, 1, 0), reminders.map { it.daysBefore })
    }

    @Test
    fun `computeWidgetSummary handles empty list and pinned top item`() {
        val empty = DdayCalculator.computeWidgetSummary(null, "nearest", today)
        assertEquals("D-Day Before", empty.title)
        assertEquals("D-Day", empty.countdown)

        val json = """
            {
              "schemaVersion": 1,
              "items": [
                {
                  "id": "near",
                  "title": "近期事件",
                  "date": "2026-11-26",
                  "pinned": false
                },
                {
                  "id": "pin",
                  "title": "置頂生日",
                  "date": "2020-12-25",
                  "pinned": true,
                  "repeatYearly": true,
                  "colorKey": "rose"
                }
              ]
            }
        """.trimIndent()
        val summary = DdayCalculator.computeWidgetSummary(json, "nearest", today)
        assertEquals("📌 置頂生日", summary.title)
        assertEquals("D-30", summary.countdown)
        assertTrue(summary.subtitle.contains("每年重複・第 6 週年"))
        assertEquals(0xFFE11D48.toInt(), summary.accentColor)
        assertTrue(summary.isPinned)
    }

    private fun item(
        id: String,
        date: String,
        createdAt: String,
        pinned: Boolean = false,
        repeatYearly: Boolean = false,
    ) = KotlinDdayItem(id, id, date, false, pinned, createdAt, repeatYearly, null, emptyList())

    @Test
    fun `yearly item with future start date counts down to the original date first`() {
        val future = item("f", "2028-01-10", "", repeatYearly = true)
        assertEquals(SimpleYmd(2028, 1, 10), DdayCalculator.nextYearlyOccurrence("2028-01-10", today))
        assertEquals(SimpleYmd(2028, 1, 10), DdayCalculator.effectiveTargetDate(future, today))
        assertEquals("D-411", DdayCalculator.formatCountdown(future, today))
        assertEquals("每年重複", DdayCalculator.anniversarySubtitle(future, today))

        // 未來的 2/29 起始日不應被改成平年的 2/28。
        assertEquals(SimpleYmd(2028, 2, 29), DdayCalculator.nextYearlyOccurrence("2028-02-29", today))

        // 起始日就是今天。
        val todayStart = item("t", "2026-11-25", "", repeatYearly = true)
        assertEquals("D-Day", DdayCalculator.formatCountdown(todayStart, today))
        assertEquals("每年重複", DdayCalculator.anniversarySubtitle(todayStart, today))

        // 原始日期過後回到每年重複邏輯。
        val later = SimpleYmd(2028, 1, 11)
        assertEquals(SimpleYmd(2029, 1, 10), DdayCalculator.nextYearlyOccurrence("2028-01-10", later))
        assertEquals("每年重複・第 1 週年", DdayCalculator.anniversarySubtitle(future, later))

        val json = """
            {"schemaVersion": 1, "items": [
              {"id": "f", "title": "未來紀念日", "date": "2028-01-10", "repeatYearly": true}
            ]}
        """.trimIndent()
        val summary = DdayCalculator.computeWidgetSummary(json, "nearest", today)
        assertEquals("D-411", summary.countdown)
        assertEquals("2028/01/10 (一)・每年重複", summary.subtitle)
    }

    @Test
    fun `createdAtSortKey normalizes fraction to nine digits and degrades safely`() {
        assertEquals("2026-11-25T00:00:00.000000000Z", DdayCalculator.createdAtSortKey("2026-11-25T00:00:00Z"))
        assertEquals("2026-11-25T00:00:00.000000000Z", DdayCalculator.createdAtSortKey("2026-11-25T00:00:00.000Z"))
        assertEquals("2026-11-25T00:00:00.000123000Z", DdayCalculator.createdAtSortKey("2026-11-25T00:00:00.000123Z"))
        assertEquals("2026-11-25T00:00:00.123456789Z", DdayCalculator.createdAtSortKey("2026-11-25T00:00:00.1234567891234Z"))
        assertEquals("", DdayCalculator.createdAtSortKey(""))
        assertEquals("", DdayCalculator.createdAtSortKey("not a date"))
        assertEquals("", DdayCalculator.createdAtSortKey("2026-11-25T00:00:00+08:00"))
        assertEquals("", DdayCalculator.createdAtSortKey("2026-11-25T00:00:00.Z"))
        assertEquals("", DdayCalculator.createdAtSortKey("null"))
    }

    @Test
    fun `createdDesc sorts microseconds correctly and puts invalid createdAt last`() {
        val items = listOf(
            item("millis", "2026-12-01", "2026-11-25T00:00:00.000Z"),
            item("empty", "2026-12-01", ""),
            item("micros", "2026-12-01", "2026-11-25T00:00:00.000123Z"),
            item("garbage", "2026-12-01", "garbage"),
            item("noFraction", "2026-12-01", "2026-11-24T23:59:59Z"),
        )
        val sorted = DdayCalculator.sortDdays(items, "createdDesc", today)
        assertEquals(listOf("micros", "millis", "noFraction", "empty", "garbage"), sorted.map { it.id })

        // 主排序平手時，同樣以正規化後的 createdAt 排序。
        val nearest = DdayCalculator.sortDdays(items, "nearest", today)
        assertEquals(listOf("micros", "millis", "noFraction", "empty", "garbage"), nearest.map { it.id })
    }

    @Test
    fun `sortDdays orders fixed data for all three modes`() {
        val items = listOf(
            item("a", "2026-12-01", "2026-01-01T00:00:00.000Z"),
            item("b", "2026-11-20", "2026-03-01T00:00:00.000Z"),
            item("c", "2000-11-26", "2026-02-01T00:00:00.000Z", repeatYearly = true),
            item("d", "2026-10-01", "2026-04-01T00:00:00.000Z"),
            item("e", "2026-12-01", "2026-05-01T00:00:00.000Z"),
            item("p", "2027-06-01", "2025-01-01T00:00:00.000Z", pinned = true),
        )
        assertEquals(
            listOf("p", "c", "e", "a", "b", "d"),
            DdayCalculator.sortDdays(items, "nearest", today).map { it.id },
        )
        assertEquals(
            listOf("p", "c", "e", "a", "b", "d"),
            DdayCalculator.sortDdays(items, null, today).map { it.id },
        )
        assertEquals(
            listOf("p", "d", "b", "c", "e", "a"),
            DdayCalculator.sortDdays(items, "dateAsc", today).map { it.id },
        )
        assertEquals(
            listOf("p", "e", "d", "b", "c", "a"),
            DdayCalculator.sortDdays(items, "createdDesc", today).map { it.id },
        )
    }

    @Test
    fun `parseItemsJson falls back to legacy color when colorKey is null, missing or empty`() {
        val json = """
            {"schemaVersion": 1, "items": [
              {"id": "nullKey", "title": "t", "date": "2026-12-01", "colorKey": null, "color": "rose"},
              {"id": "missing", "title": "t", "date": "2026-12-01", "color": "teal"},
              {"id": "emptyKey", "title": "t", "date": "2026-12-01", "colorKey": "", "color": "amber"},
              {"id": "both", "title": "t", "date": "2026-12-01", "colorKey": "sky", "color": "rose"},
              {"id": "unknownKey", "title": "t", "date": "2026-12-01", "colorKey": "nope", "color": "rose"},
              {"id": "badLegacy", "title": "t", "date": "2026-12-01", "color": "notacolor"},
              {"id": "none", "title": "t", "date": "2026-12-01"}
            ]}
        """.trimIndent()
        val byId = DdayCalculator.parseItemsJson(json).associate { it.id to it.colorKey }
        assertEquals("rose", byId["nullKey"])
        assertEquals("teal", byId["missing"])
        assertEquals("amber", byId["emptyKey"])
        assertEquals("sky", byId["both"])
        assertNull(byId["unknownKey"])
        assertNull(byId["badLegacy"])
        assertNull(byId["none"])
        assertEquals(7, byId.size)
    }

    @Test
    fun `parseItemsJson skips non-integer, negative and oversized reminder values`() {
        val json = """
            {"schemaVersion": 1, "items": [
              {"id": "r", "title": "t", "date": "2026-12-25",
               "reminderDaysBefore": [1.5, "3", 2147483648, -1, 7, 2, 2, 0, null, true]}
            ]}
        """.trimIndent()
        val parsed = DdayCalculator.parseItemsJson(json)
        assertEquals(1, parsed.size)
        assertEquals(listOf(0, 2, 7), parsed.first().reminderDaysBefore)
    }
}
