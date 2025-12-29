package com.chijia.flutter_ezmap

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.chijia.flutter_ezmap/shared_file"
    private val EVENT_CHANNEL = "com.chijia.flutter_ezmap/shared_file_stream"
    private var eventSink: EventChannel.EventSink? = null
    private var pendingFilePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Method Channel: 獲取啟動時接收到的檔案
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialSharedFile") {
                val filePath = getSharedFilePath(intent)
                result.success(filePath)
            } else {
                result.notImplemented()
            }
        }

        // Event Channel: 處理運行時接收到的檔案
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // 如果有待處理的檔案，立即發送
                    pendingFilePath?.let { path ->
                        events?.success(path)
                        pendingFilePath = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        
        // 處理啟動時的 intent
        handleIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        val type = intent.type

        if (Intent.ACTION_SEND == action && type != null) {
            if (type.startsWith("application/gpx+xml") || 
                type.startsWith("application/xml") ||
                type.contains("xml")) {
                val filePath = getSharedFilePath(intent)
                if (filePath != null) {
                    if (eventSink != null) {
                        eventSink?.success(filePath)
                    } else {
                        // 如果 eventSink 還沒準備好，先保存起來
                        pendingFilePath = filePath
                    }
                }
            }
        } else if (Intent.ACTION_VIEW == action) {
            val filePath = getSharedFilePath(intent)
            if (filePath != null && filePath.endsWith(".gpx")) {
                if (eventSink != null) {
                    eventSink?.success(filePath)
                } else {
                    pendingFilePath = filePath
                }
            }
        }
    }

    private fun getSharedFilePath(intent: Intent?): String? {
        if (intent == null) return null

        val uri: Uri? = when {
            intent.action == Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            intent.action == Intent.ACTION_VIEW -> intent.data
            else -> null
        }

        if (uri == null) return null

        return when (uri.scheme) {
            "file" -> uri.path
            "content" -> {
                // 對於 content:// URI，需要從 ContentResolver 讀取
                // 這裡先嘗試直接獲取路徑，如果失敗則需要複製檔案
                try {
                    val cursor = contentResolver.query(uri, null, null, null, null)
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val index = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (index != -1) {
                                val fileName = it.getString(index)
                                // 創建臨時檔案
                                val tempFile = File(cacheDir, fileName)
                                contentResolver.openInputStream(uri)?.use { input ->
                                    tempFile.outputStream().use { output ->
                                        input.copyTo(output)
                                    }
                                }
                                return tempFile.absolutePath
                            }
                        }
                    }
                } catch (e: Exception) {
                    println("Error reading content URI: $e")
                }
                null
            }
            else -> null
        }
    }
}
