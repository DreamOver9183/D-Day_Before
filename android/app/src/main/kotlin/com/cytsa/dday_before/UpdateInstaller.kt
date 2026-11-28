package com.cytsa.dday_before

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest

/** Error codes reported to Dart; keep in sync with `update_service.dart`. */
object UpdateErrors {
    const val DOWNLOAD_FAILED = "DOWNLOAD_FAILED"
    const val CHECKSUM_MISMATCH = "CHECKSUM_MISMATCH"
    const val INSTALL_NOT_ALLOWED = "INSTALL_NOT_ALLOWED"
    const val BAD_REQUEST = "BAD_REQUEST"
}

class UpdateException(val code: String, message: String) : Exception(message)

/**
 * Downloads an update APK from GitHub over HTTPS, verifies its SHA-256 and
 * hands it to the system package installer. Android itself rejects an APK
 * that is not signed with the same key as the installed app.
 */
object UpdateInstaller {
    private const val UPDATE_DIR = "updates"
    private const val APK_NAME = "dday_before_update.apk"
    private const val MAX_APK_BYTES = 100L * 1024 * 1024
    private const val TIMEOUT_MS = 20_000

    private val ALLOWED_HOSTS = setOf(
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    )

    fun canInstallPackages(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()

    fun openInstallPermissionSettings(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** Only HTTPS downloads from GitHub release hosts are accepted. */
    fun isAllowedUrl(url: String): Boolean {
        val uri = try {
            URI(url)
        } catch (_: Exception) {
            return false
        }
        return uri.scheme == "https" && uri.host in ALLOWED_HOSTS && uri.userInfo == null
    }

    fun isValidSha256(value: String): Boolean = Regex("^[0-9a-f]{64}$").matches(value)

    /** Blocking: call off the UI thread. Returns the verified APK file. */
    fun download(context: Context, url: String, expectedSha256: String): File {
        if (!isAllowedUrl(url) || !isValidSha256(expectedSha256)) {
            throw UpdateException(UpdateErrors.BAD_REQUEST, "Rejected update source")
        }
        val dir = File(context.cacheDir, UPDATE_DIR).apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val target = File(dir, APK_NAME)
        val digest = MessageDigest.getInstance("SHA-256")

        var connection = open(url)
        try {
            // Follow GitHub's redirect to its asset host (same https scheme).
            var redirects = 0
            while (connection.responseCode in 300..399 && redirects < 5) {
                val next = connection.getHeaderField("Location")
                connection.disconnect()
                if (next == null || !isAllowedUrl(next)) {
                    throw UpdateException(UpdateErrors.DOWNLOAD_FAILED, "Unexpected redirect")
                }
                connection = open(next)
                redirects++
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw UpdateException(
                    UpdateErrors.DOWNLOAD_FAILED,
                    "HTTP ${connection.responseCode}",
                )
            }
            var total = 0L
            connection.inputStream.use { input ->
                FileOutputStream(target).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_APK_BYTES) {
                            throw UpdateException(UpdateErrors.DOWNLOAD_FAILED, "File too large")
                        }
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                    }
                }
            }
        } catch (e: UpdateException) {
            target.delete()
            throw e
        } catch (e: Exception) {
            target.delete()
            throw UpdateException(UpdateErrors.DOWNLOAD_FAILED, e.message ?: "Download failed")
        } finally {
            connection.disconnect()
        }

        val actual = toHex(digest.digest())
        if (actual != expectedSha256) {
            target.delete()
            throw UpdateException(UpdateErrors.CHECKSUM_MISMATCH, "Checksum mismatch")
        }
        return target
    }

    /** Opens the system installer for [apk]; the user confirms the update. */
    fun launchInstaller(context: Context, apk: File) {
        if (!canInstallPackages(context)) {
            throw UpdateException(UpdateErrors.INSTALL_NOT_ALLOWED, "Install permission missing")
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun toHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun open(url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = false
            connectTimeout = TIMEOUT_MS
            readTimeout = TIMEOUT_MS
            setRequestProperty("User-Agent", "D-Day-Before-Updater")
        }
}
