package com.medhistorygen.medhistory_app

import android.app.Activity
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "com.xinggue.docmasterPei/config_file"
    private var pendingSaveContent: String? = null
    private var pendingSaveSourcePath: String? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private val createDocRequestCode = 9401

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName") ?: "docmaster_config.txt"
                        val content = call.argument<String>("content") ?: ""
                        try {
                            val savedPath = saveTextToPublicDownloads(fileName, content)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    "saveWithSafPicker" -> {
                        val fileName = call.argument<String>("fileName") ?: "docmaster_config.txt"
                        val content = call.argument<String>("content") ?: ""
                        pendingSaveResult?.success(null)
                        pendingSaveContent = content
                        pendingSaveSourcePath = null
                        pendingSaveResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        }
                        startActivityForResult(intent, createDocRequestCode)
                    }
                    "saveFileWithSafPicker" -> {
                        val fileName = call.argument<String>("fileName") ?: "peipal_backup.zip"
                        val sourcePath = call.argument<String>("sourcePath")
                        val mimeType = call.argument<String>("mimeType") ?: "application/zip"
                        if (sourcePath.isNullOrBlank()) {
                            result.error("BAD_ARGS", "缺少源文件路径", null)
                            return@setMethodCallHandler
                        }
                        pendingSaveResult?.success(null)
                        pendingSaveContent = null
                        pendingSaveSourcePath = sourcePath
                        pendingSaveResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mimeType
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        }
                        startActivityForResult(intent, createDocRequestCode)
                    }
                    "shareTextFile" -> {
                        val rawName = call.argument<String>("fileName") ?: "peipal_export.txt"
                        val content = call.argument<String>("content")
                        val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                        val subject = call.argument<String>("subject")
                        if (content == null) {
                            result.error("BAD_ARGS", "缺少分享内容", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val targetFile = prepareShareFile(rawName)
                            targetFile.writeText(content, Charsets.UTF_8)
                            launchShareSheet(targetFile, mimeType, subject)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    "shareBinaryFile" -> {
                        val rawName = call.argument<String>("fileName") ?: "peipal_backup.zip"
                        val sourcePath = call.argument<String>("sourcePath")
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val subject = call.argument<String>("subject")
                        if (sourcePath.isNullOrBlank()) {
                            result.error("BAD_ARGS", "缺少源文件路径", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val srcFile = File(sourcePath)
                            if (!srcFile.exists()) {
                                result.error("FILE_NOT_FOUND", "分享源文件不存在", null)
                                return@setMethodCallHandler
                            }
                            val targetFile = prepareShareFile(rawName)
                            srcFile.copyTo(targetFile, overwrite = true)
                            launchShareSheet(targetFile, mimeType, subject)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepareShareFile(rawName: String): File {
        val shareRoot = File(cacheDir, "shared_exports")
        if (!shareRoot.exists()) {
            shareRoot.mkdirs()
        } else {
            val cutoff = System.currentTimeMillis() - 24L * 60L * 60L * 1000L
            shareRoot.listFiles()?.forEach { child ->
                if (child.lastModified() < cutoff) {
                    child.deleteRecursively()
                }
            }
        }
        val cleanName = File(rawName.trim()).name.ifEmpty { "peipal_export.txt" }
        val batchDir = File(shareRoot, UUID.randomUUID().toString())
        batchDir.mkdirs()
        return File(batchDir, cleanName)
    }

    private fun launchShareSheet(file: File, mimeType: String, subject: String?) {
        val authority = "${applicationContext.packageName}.fileprovider"
        val uri = FileProvider.getUriForFile(this, authority, file)
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            if (!subject.isNullOrBlank()) {
                putExtra(Intent.EXTRA_SUBJECT, subject)
            }
            clipData = ClipData.newRawUri("", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(sendIntent, subject ?: file.name)
        startActivity(chooser)
    }

    private fun saveTextToPublicDownloads(fileName: String, content: String): String {
        val bytes = content.toByteArray(Charsets.UTF_8)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("无法创建下载文件")
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Download/$fileName"
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, fileName)
            file.writeBytes(bytes)
            return file.absolutePath
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == createDocRequestCode) {
            val res = pendingSaveResult
            val content = pendingSaveContent
            val sourcePath = pendingSaveSourcePath
            pendingSaveResult = null
            pendingSaveContent = null
            pendingSaveSourcePath = null

            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                try {
                    val uri = data.data!!
                    if (sourcePath != null) {
                        val srcFile = File(sourcePath)
                        srcFile.inputStream().use { input ->
                            applicationContext.contentResolver.openOutputStream(uri)?.use { out ->
                                input.copyTo(out)
                                out.flush()
                            }
                        }
                    } else {
                        applicationContext.contentResolver.openOutputStream(uri, "wt")?.use { out ->
                            out.write((content ?: "").toByteArray(Charsets.UTF_8))
                            out.flush()
                        }
                    }
                    res?.success(uri.lastPathSegment ?: "已保存")
                } catch (e: Exception) {
                    res?.error("SAF_WRITE_ERROR", e.message, null)
                }
            } else {
                res?.success(null)
            }
        }
    }
}
