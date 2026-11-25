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
        assertEquals("第 1 天", DdayCalculator.formatCountdown(anniv, today))

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
}
