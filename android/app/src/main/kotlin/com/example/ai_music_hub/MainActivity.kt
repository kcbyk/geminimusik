package com.example.ai_music_hub

import android.content.Intent
import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "jarvis_assistant"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkJarvisIntent" -> {
                    val openJarvis = intent?.getBooleanExtra("open_jarvis", false) ?: false
                    result.success(openJarvis)
                }
                "downloadImage" -> {
                    val url = call.argument<String>("url")
                    val rawFileName = call.argument<String>("fileName") ?: "gorsel.jpg"
                    if (url.isNullOrBlank() || !url.startsWith("https://")) {
                        result.error("INVALID_URL", "Yalnızca HTTPS görseller indirilebilir.", null)
                        return@setMethodCallHandler
                    }
                    val fileName = rawFileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
                    val request = DownloadManager.Request(Uri.parse(url))
                        .setTitle(fileName)
                        .setDescription("Görsel indiriliyor")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
                    val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    manager.enqueue(request)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("open_jarvis", false)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("openJarvis", null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra("open_jarvis", false) == true) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("openJarvis", null)
            }
        }
    }
}
