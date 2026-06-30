package com.ihope.ihope

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ihope.ihope/media_save",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToPublic" -> {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                        val isImage = call.argument<Boolean>("isImage") ?: false
                        if (bytes == null || fileName.isNullOrBlank()) {
                            result.error("INVALID", "缺少保存参数", null)
                            return@setMethodCallHandler
                        }
                        val saved = PublicMediaSaver.save(this, bytes, fileName, isImage)
                        result.success(saved)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                "existsAt" -> {
                    try {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID", "缺少路径", null)
                            return@setMethodCallHandler
                        }
                        result.success(PublicMediaSaver.exists(this, path))
                    } catch (e: Exception) {
                        result.error("EXISTS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
