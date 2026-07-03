package com.clprince.ihope

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream

object PublicMediaSaver {
    fun save(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        isImage: Boolean,
    ): Map<String, String> {
        return if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q) {
            saveLegacy(bytes, fileName, isImage)
        } else {
            saveMediaStore(context, bytes, fileName, isImage)
        }
    }

    fun exists(context: Context, path: String): Boolean {
        if (path.startsWith("content://")) {
            return try {
                context.contentResolver
                    .openFileDescriptor(Uri.parse(path), "r")
                    ?.use { true } ?: false
            } catch (_: Exception) {
                false
            }
        }
        return File(path).exists()
    }

    private fun saveMediaStore(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        isImage: Boolean,
    ): Map<String, String> {
        val resolver = context.contentResolver
        val relativePath =
            if (isImage) Environment.DIRECTORY_PICTURES
            else Environment.DIRECTORY_DOWNLOADS
        val collection =
            if (isImage) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, guessMime(fileName, isImage))
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        val uri =
            resolver.insert(collection, values)
                ?: throw IllegalStateException("无法创建 MediaStore 条目")
        try {
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
            } ?: throw IllegalStateException("无法打开输出流")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        val label =
            if (isImage) "Pictures/$fileName" else "Download/$fileName"
        return mapOf(
            "openPath" to uri.toString(),
            "displayLabel" to label,
        )
    }

    private fun saveLegacy(
        bytes: ByteArray,
        fileName: String,
        isImage: Boolean,
    ): Map<String, String> {
        val sub = if (isImage) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS
        val dir =
            if (isImage) {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            } else {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            }
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("无法创建目录 $sub")
        }
        val file = File(dir, fileName)
        FileOutputStream(file).use { it.write(bytes) }
        if (!file.exists()) {
            throw IllegalStateException("写入 $sub 失败")
        }
        return mapOf(
            "openPath" to file.absolutePath,
            "displayLabel" to "$sub/$fileName",
        )
    }

    private fun guessMime(fileName: String, isImage: Boolean): String {
        val lower = fileName.lowercase()
        return when {
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".bmp") -> "image/bmp"
            lower.endsWith(".heic") -> "image/heic"
            isImage -> "image/jpeg"
            lower.endsWith(".pdf") -> "application/pdf"
            lower.endsWith(".txt") -> "text/plain"
            lower.endsWith(".zip") -> "application/zip"
            else -> "application/octet-stream"
        }
    }
}
