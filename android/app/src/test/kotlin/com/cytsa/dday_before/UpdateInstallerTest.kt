package com.cytsa.dday_before

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

class UpdateInstallerTest {
    @Test
    fun `only https GitHub release hosts are allowed`() {
        assertTrue(
            UpdateInstaller.isAllowedUrl(
                "https://github.com/DreamOver9183/D-Day_Before/releases/download/v1.0.1/a.apk",
            ),
        )
        assertTrue(UpdateInstaller.isAllowedUrl("https://objects.githubusercontent.com/x/y"))
        assertTrue(UpdateInstaller.isAllowedUrl("https://release-assets.githubusercontent.com/x"))

        assertFalse("plain http", UpdateInstaller.isAllowedUrl("http://github.com/a.apk"))
        assertFalse("other host", UpdateInstaller.isAllowedUrl("https://evil.example.com/a.apk"))
        assertFalse(
            "look-alike host",
            UpdateInstaller.isAllowedUrl("https://github.com.evil.example/a.apk"),
        )
        assertFalse(
            "credentials in URL",
            UpdateInstaller.isAllowedUrl("https://user@github.com/a.apk"),
        )
        assertFalse("file scheme", UpdateInstaller.isAllowedUrl("file:///sdcard/a.apk"))
        assertFalse("garbage", UpdateInstaller.isAllowedUrl("not a url"))
    }

    @Test
    fun `sha256 must be 64 lowercase hex chars`() {
        val valid = "a".repeat(64)
        assertTrue(UpdateInstaller.isValidSha256(valid))
        assertFalse(UpdateInstaller.isValidSha256("A".repeat(64)))
        assertFalse(UpdateInstaller.isValidSha256("a".repeat(63)))
        assertFalse(UpdateInstaller.isValidSha256("g".repeat(64)))
        assertFalse(UpdateInstaller.isValidSha256(""))
    }

    @Test
    fun `toHex matches the standard SHA-256 encoding`() {
        val digest = MessageDigest.getInstance("SHA-256").digest("abc".toByteArray())
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            UpdateInstaller.toHex(digest),
        )
    }
}
