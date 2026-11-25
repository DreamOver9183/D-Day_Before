package com.cytsa.dday_before

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.cytsa.dday_before/native"
        private const val REQUEST_CREATE_BACKUP = 2001
        private const val REQUEST_OPEN_BACKUP = 2002
        private const val REQUEST_POST_NOTIFICATIONS = 2003
        private const val REQUEST_PICK_BACKGROUND = 2004
    }

    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingExportContent: String? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null

    /** Photo decoding and file I/O stay off the UI thread. */
    private val imageExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportJsonFile" -> {
                    val filename = call.argument<String>("filename") ?: "dday_before_backup.json"
                    val content = call.argument<String>("content") ?: ""
                    launchCreateDocument(filename, content, result)
                }
                "importJsonFile" -> {
                    launchOpenDocument(result)
                }
                "hasNotificationPermission" -> {
                    result.success(
                        DdayNotificationManager.hasNotificationPermission(applicationContext),
                    )
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission(result)
                }
                "syncNotifications" -> {
                    DdayNotificationManager.syncAll(applicationContext)
                    result.success(true)
                }
                "refreshWidgets" -> {
                    DdayAppWidgetProvider.updateAllWidgets(applicationContext)
                    result.success(true)
                }
                "pickBackgroundImage" -> {
                    launchBackgroundPicker(result)
                }

                "getBackgroundsDir" -> {
                    result.success(BackgroundImageStore.dir(applicationContext).absolutePath)
                }

                "cleanupBackgrounds" -> {
                    val keep = call.argument<List<String>>("keep")?.toSet() ?: emptySet()
                    imageExecutor.execute {
                        val deleted = BackgroundImageStore.cleanup(applicationContext, keep)
                        runOnUiThread { result.success(deleted) }
                    }
                }

                "getAppVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        info.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        info.versionCode.toLong()
                    }
                    result.success(
                        mapOf("versionName" to (info.versionName ?: ""), "versionCode" to code),
                    )
                }

                "canInstallUpdates" -> {
                    result.success(UpdateInstaller.canInstallPackages(applicationContext))
                }

                "openInstallPermissionSettings" -> {
                    UpdateInstaller.openInstallPermissionSettings(this)
                    result.success(true)
                }

                "downloadAndInstallUpdate" -> {
                    val url = call.argument<String>("url")
                    val sha256 = call.argument<String>("sha256")
                    if (url == null || sha256 == null) {
                        result.error(UpdateErrors.BAD_REQUEST, "Missing url or sha256", null)
                    } else {
                        imageExecutor.execute {
                            try {
                                val apk = UpdateInstaller.download(applicationContext, url, sha256)
                                runOnUiThread {
                                    try {
                                        UpdateInstaller.launchInstaller(this, apk)
                                        result.success(true)
                                    } catch (e: UpdateException) {
                                        result.error(e.code, e.message, null)
                                    } catch (e: Exception) {
                                        result.error(UpdateErrors.DOWNLOAD_FAILED, e.message, null)
                                    }
                                }
                            } catch (e: UpdateException) {
                                runOnUiThread { result.error(e.code, e.message, null) }
                            }
                        }
                    }
                }

                "debugImportBackground" -> {
                    // Lets debug-build tests run the real import pipeline without
                    // driving the system photo picker. Unavailable in release.
                    val debuggable =
                        (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
                    val bytes = call.argument<ByteArray>("bytes")
                    if (!debuggable || bytes == null) {
                        result.notImplemented()
                    } else {
                        imageExecutor.execute {
                            try {
                                val name = BackgroundImageStore.importFromBytes(applicationContext, bytes)
                                runOnUiThread { result.success(name) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("IMAGE_IMPORT_FAILED", e.message, null) }
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (DdayNotificationManager.hasNotificationPermission(applicationContext)) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(false)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "Permission request already in progress.", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_POST_NOTIFICATIONS) {
            val callback = pendingPermissionResult
            pendingPermissionResult = null
            if (callback != null) {
                val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                callback.success(granted)
            }
        }
    }

    private fun launchBackgroundPicker(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("BUSY", "Another image pick is in progress.", null)
            return
        }
        pendingPickResult = result
        // The system photo picker needs no storage permission.
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }
        try {
            startActivityForResult(intent, REQUEST_PICK_BACKGROUND)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICKER_UNAVAILABLE", e.message, null)
        }
    }

    override fun onDestroy() {
        imageExecutor.shutdown()
        super.onDestroy()
    }

    private fun launchCreateDocument(
        filename: String,
        content: String,
        result: MethodChannel.Result,
    ) {
        if (pendingExportResult != null) {
            result.error("BUSY", "Another export operation is in progress.", null)
            return
        }
        pendingExportResult = result
        pendingExportContent = content

        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, filename)
        }
        startActivityForResult(intent, REQUEST_CREATE_BACKUP)
    }

    private fun launchOpenDocument(result: MethodChannel.Result) {
        if (pendingImportResult != null) {
            result.error("BUSY", "Another import operation is in progress.", null)
            return
        }
        pendingImportResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/json", "text/plain"),
            )
        }
        startActivityForResult(intent, REQUEST_OPEN_BACKUP)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_CREATE_BACKUP -> {
                val callback = pendingExportResult
                val content = pendingExportContent
                pendingExportResult = null
                pendingExportContent = null
                if (callback == null) return

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    callback.success(false)
                    return
                }
                try {
                    val uri = data.data!!
                    contentResolver.openOutputStream(uri)?.use { stream ->
                        stream.write((content ?: "").toByteArray(StandardCharsets.UTF_8))
                        stream.flush()
                    } ?: throw IllegalStateException("Unable to open output stream")
                    callback.success(true)
                } catch (e: Exception) {
                    callback.error("EXPORT_FAILED", e.message, null)
                }
            }

            REQUEST_PICK_BACKGROUND -> {
                val callback = pendingPickResult
                pendingPickResult = null
                if (callback == null) return

                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    callback.success(null)
                    return
                }
                imageExecutor.execute {
                    try {
                        val name = BackgroundImageStore.importFromUri(applicationContext, uri)
                        runOnUiThread { callback.success(name) }
                    } catch (e: Exception) {
                        runOnUiThread { callback.error("IMAGE_IMPORT_FAILED", e.message, null) }
                    }
                }
            }

            REQUEST_OPEN_BACKUP -> {
                val callback = pendingImportResult
                pendingImportResult = null
                if (callback == null) return

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    callback.success(null)
                    return
                }
                try {
                    val uri = data.data!!
                    val content = contentResolver.openInputStream(uri)?.use { stream ->
                        BufferedReader(
                            InputStreamReader(stream, StandardCharsets.UTF_8),
                        ).readText()
                    } ?: throw IllegalStateException("Unable to open input stream")
                    callback.success(content)
                } catch (e: Exception) {
                    callback.error("IMPORT_FAILED", e.message, null)
                }
            }
        }
    }
}
