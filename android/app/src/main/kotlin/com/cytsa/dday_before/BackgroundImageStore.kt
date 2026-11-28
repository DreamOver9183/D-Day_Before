package com.cytsa.dday_before

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID

/**
 * Stores per-item background photos privately in `filesDir/backgrounds`.
 *
 * Items only keep the file name (`bg_<32 hex>.jpg`), never a path, so names
 * from backups or other devices cannot point outside this folder.
 */
object BackgroundImageStore {
    private const val DIR_NAME = "backgrounds"
    private val NAME_REGEX = Regex("""^bg_[0-9a-f]{32}\.jpg$""")

    /** Longest side of a stored photo, in pixels. */
    const val MAX_STORED_DIMENSION = 1600
    private const val JPEG_QUALITY = 85

    /** Files younger than this survive cleanup (a photo picked but not saved yet). */
    const val CLEANUP_GRACE_MS = 10 * 60 * 1000L

    fun isValidName(name: String?): Boolean = name != null && NAME_REGEX.matches(name)

    fun dir(context: Context): File = File(context.filesDir, DIR_NAME).apply { mkdirs() }

    fun fileFor(context: Context, name: String?): File? {
        if (!isValidName(name)) return null
        val file = File(dir(context), name!!)
        return if (file.isFile) file else null
    }

    /** Decodes, orients, downsizes and saves the photo; returns its new name. */
    fun importFromUri(context: Context, uri: Uri): String {
        val resolver = context.contentResolver
        return importImage(
            context,
            openStream = {
                resolver.openInputStream(uri) ?: throw IllegalStateException("Cannot open image")
            },
        )
    }

    /** Same pipeline for raw bytes (used by debug-build tests). */
    fun importFromBytes(context: Context, bytes: ByteArray): String =
        importImage(context, openStream = { ByteArrayInputStream(bytes) })

    private fun importImage(context: Context, openStream: () -> InputStream): String {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        openStream().use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("Not a supported image")
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = computeSampleSize(bounds.outWidth, bounds.outHeight, MAX_STORED_DIMENSION)
        }
        val decoded = openStream().use { BitmapFactory.decodeStream(it, null, options) }
            ?: throw IllegalArgumentException("Cannot decode image")

        val rotation = openStream().use { readRotationDegrees(it) }
        val oriented = rotateAndFit(decoded, rotation, MAX_STORED_DIMENSION)

        val name = "bg_${UUID.randomUUID().toString().replace("-", "")}.jpg"
        val target = File(dir(context), name)
        val temp = File(dir(context), "$name.tmp")
        try {
            FileOutputStream(temp).use { out ->
                if (!oriented.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)) {
                    throw IllegalStateException("Cannot encode image")
                }
            }
            if (!temp.renameTo(target)) throw IllegalStateException("Cannot save image")
        } finally {
            temp.delete()
            if (oriented !== decoded) oriented.recycle()
            decoded.recycle()
        }
        return name
    }

    /**
     * Deletes stored photos not listed in [keep], except files changed within
     * [graceMs] (a photo picked in an editor that has not been saved yet).
     */
    fun cleanup(
        context: Context,
        keep: Set<String>,
        nowMillis: Long = System.currentTimeMillis(),
        graceMs: Long = CLEANUP_GRACE_MS,
    ): Int {
        var deleted = 0
        dir(context).listFiles()?.forEach { file ->
            if (shouldDelete(file.name, file.lastModified(), keep, nowMillis, graceMs) && file.delete()) {
                deleted++
            }
        }
        return deleted
    }

    /** Pure decision used by [cleanup]; also removes stale temp files. */
    fun shouldDelete(
        name: String,
        lastModified: Long,
        keep: Set<String>,
        nowMillis: Long,
        graceMs: Long,
    ): Boolean {
        if (name in keep) return false
        val managed = isValidName(name) || name.endsWith(".tmp")
        if (!managed) return false
        return nowMillis - lastModified > graceMs
    }

    /**
     * Loads a small, center-cropped bitmap for the home-screen widget. RGB_565
     * keeps it well under the RemoteViews transaction size limit.
     */
    fun loadWidgetBitmap(context: Context, name: String?, targetWidth: Int, targetHeight: Int): Bitmap? {
        val file = fileFor(context, name) ?: return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            val options = BitmapFactory.Options().apply {
                inSampleSize = computeSampleSize(
                    bounds.outWidth,
                    bounds.outHeight,
                    maxOf(targetWidth, targetHeight),
                )
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            val decoded = BitmapFactory.decodeFile(file.path, options) ?: return null
            val crop = centerCropRect(decoded.width, decoded.height, targetWidth, targetHeight)
            val cropped = Bitmap.createBitmap(decoded, crop[0], crop[1], crop[2], crop[3])
            val scaled = Bitmap.createScaledBitmap(cropped, targetWidth, targetHeight, true)
            if (cropped !== decoded) cropped.recycle()
            if (scaled !== decoded) decoded.recycle()
            scaled
        } catch (_: Exception) {
            null
        } catch (_: OutOfMemoryError) {
            null
        }
    }

    /** Largest power-of-two sample size keeping the longest side >= [maxDimension]. */
    fun computeSampleSize(width: Int, height: Int, maxDimension: Int): Int {
        var sample = 1
        val longest = maxOf(width, height)
        while (longest / (sample * 2) >= maxDimension) {
            sample *= 2
        }
        return sample
    }

    /** `[x, y, width, height]` of the largest centered crop with the target aspect ratio. */
    fun centerCropRect(width: Int, height: Int, targetWidth: Int, targetHeight: Int): IntArray {
        val targetRatio = targetWidth.toDouble() / targetHeight
        val sourceRatio = width.toDouble() / height
        return if (sourceRatio > targetRatio) {
            val cropWidth = (height * targetRatio).toInt().coerceIn(1, width)
            intArrayOf((width - cropWidth) / 2, 0, cropWidth, height)
        } else {
            val cropHeight = (width / targetRatio).toInt().coerceIn(1, height)
            intArrayOf(0, (height - cropHeight) / 2, width, cropHeight)
        }
    }

    private fun readRotationDegrees(stream: InputStream): Int {
        return try {
            when (ExifInterface(stream).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (_: Exception) {
            0
        }
    }

    private fun rotateAndFit(source: Bitmap, degrees: Int, maxDimension: Int): Bitmap {
        val longest = maxOf(source.width, source.height)
        val scale = if (longest > maxDimension) maxDimension.toFloat() / longest else 1f
        if (degrees == 0 && scale == 1f) return source
        val matrix = Matrix().apply {
            if (scale != 1f) postScale(scale, scale)
            if (degrees != 0) postRotate(degrees.toFloat())
        }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }
}
