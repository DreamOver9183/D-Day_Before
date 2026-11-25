package com.cytsa.dday_before

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundImageStoreTest {
    private val valid = "bg_0123456789abcdef0123456789abcdef.jpg"

    @Test
    fun `isValidName accepts only managed file names`() {
        assertTrue(BackgroundImageStore.isValidName(valid))
        assertFalse(BackgroundImageStore.isValidName(null))
        assertFalse(BackgroundImageStore.isValidName(""))
        assertFalse(BackgroundImageStore.isValidName("../$valid"))
        assertFalse(BackgroundImageStore.isValidName("/data/$valid"))
        assertFalse(BackgroundImageStore.isValidName("bg_0123.jpg"))
        assertFalse(BackgroundImageStore.isValidName(valid.uppercase()))
        assertFalse(BackgroundImageStore.isValidName("$valid.tmp"))
    }

    @Test
    fun `computeSampleSize keeps the longest side at or above the target`() {
        assertEquals(1, BackgroundImageStore.computeSampleSize(1200, 800, 1600))
        assertEquals(1, BackgroundImageStore.computeSampleSize(3000, 2000, 1600))
        assertEquals(2, BackgroundImageStore.computeSampleSize(4000, 3000, 1600))
        assertEquals(4, BackgroundImageStore.computeSampleSize(8000, 6000, 1600))
        assertEquals(4, BackgroundImageStore.computeSampleSize(3000, 4000, 720))
    }

    @Test
    fun `centerCropRect crops the long axis around the center`() {
        // Wide photo into 8:3 target -> crop width.
        assertArrayEquals(
            intArrayOf(200, 0, 1600, 600),
            BackgroundImageStore.centerCropRect(2000, 600, 720, 270),
        )
        // Tall photo into 8:3 target -> crop height.
        assertArrayEquals(
            intArrayOf(0, 625, 800, 300),
            BackgroundImageStore.centerCropRect(800, 1550, 720, 270),
        )
    }

    @Test
    fun `shouldDelete removes only old, unreferenced managed files`() {
        val now = 10_000_000L
        val grace = BackgroundImageStore.CLEANUP_GRACE_MS
        val old = now - grace - 1
        val fresh = now - 1_000

        assertTrue(BackgroundImageStore.shouldDelete(valid, old, emptySet(), now, grace))
        assertFalse(BackgroundImageStore.shouldDelete(valid, old, setOf(valid), now, grace))
        assertFalse(BackgroundImageStore.shouldDelete(valid, fresh, emptySet(), now, grace))
        assertTrue(BackgroundImageStore.shouldDelete("$valid.tmp", old, emptySet(), now, grace))
        assertFalse(
            "files the app did not create are never touched",
            BackgroundImageStore.shouldDelete("notes.txt", old, emptySet(), now, grace),
        )
    }

    @Test
    fun `parseItemsJson keeps only valid background names and widget summary carries it`() {
        val json = """
            {"schemaVersion":1,"items":[
              {"id":"a","title":"有照片","date":"2026-12-25","pinned":true,"backgroundImage":"$valid"},
              {"id":"b","title":"路徑攻擊","date":"2026-12-26","backgroundImage":"../../shared_prefs/x.xml"},
              {"id":"c","title":"型別錯誤","date":"2026-12-27","backgroundImage":42}
            ]}
        """.trimIndent()
        val items = DdayCalculator.parseItemsJson(json)
        assertEquals(valid, items.first { it.id == "a" }.backgroundImage)
        assertNull(items.first { it.id == "b" }.backgroundImage)
        assertNull(items.first { it.id == "c" }.backgroundImage)

        val summary = DdayCalculator.computeWidgetSummary(
            json,
            "nearest",
            SimpleYmd(2026, 11, 25),
        )
        assertEquals(valid, summary.backgroundImage)
    }
}
