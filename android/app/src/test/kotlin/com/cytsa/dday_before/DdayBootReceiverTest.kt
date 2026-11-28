package com.cytsa.dday_before

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DdayBootReceiverTest {
    @Test
    fun `shouldResync accepts boot, time, timezone, date and package replaced actions`() {
        listOf(
            "android.intent.action.BOOT_COMPLETED",
            "android.intent.action.TIME_SET",
            "android.intent.action.TIMEZONE_CHANGED",
            "android.intent.action.DATE_CHANGED",
            "android.intent.action.MY_PACKAGE_REPLACED",
        ).forEach { action ->
            assertTrue(action, DdayBootReceiver.shouldResync(action))
        }
    }

    @Test
    fun `shouldResync rejects other actions and null`() {
        assertFalse(DdayBootReceiver.shouldResync(null))
        listOf(
            "",
            "android.intent.action.PACKAGE_REPLACED",
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            "android.appwidget.action.APPWIDGET_UPDATE",
            "android.intent.action.MAIN",
        ).forEach { action ->
            assertFalse(action, DdayBootReceiver.shouldResync(action))
        }
    }
}
