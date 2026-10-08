package com.example.ai_music_hub

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.app.PendingIntent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.example.ai_music_hub.AgentDeviceChannel.Companion.TERMUX_PACKAGE
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * Termux'a komut devretme katmanı (resmî RUN_COMMAND protokolü).
 *
 * Komut **arka plan** komutu olarak gönderilir ve sonuç `PENDING_INTENT`
 * ile geri alınır: bu modda Termux `stdout`, `stderr` ve `exitCode` değerlerini
 * ayrı ayrı döndürür (ön plan komutlarında yalnızca oturum dökümü gelir).
 *
 * Extra adları termux-shared `TermuxConstants` sınıfından birebir alınmıştır.
 *
 * ÖNEMLİ: Termux, `~/.termux/termux.properties` içinde
 * `allow-external-apps=true` yazmıyorsa dış uygulamalardan gelen komutları
 * reddeder. Bu durumda sonuç hiç gelmez; kullanıcıya tek seferlik kurulum
 * adımları gösterilir (`termuxInfo`).
 */
class AgentTermuxChannel(private val context: Context) {

    private val requestCode = AtomicInteger(1000)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "run" -> run(call, result)
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("termux_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun run(call: MethodCall, result: MethodChannel.Result) {
        val command = (call.argument<String>("command") ?: "").trim()
        if (command.isEmpty()) {
            result.success(mapOf("ok" to false, "error" to "command boş olamaz"))
            return
        }
        if (command.length > MAX_COMMAND_CHARS) {
            result.success(
                mapOf(
                    "ok" to false,
                    "error" to "komut çok uzun (en fazla $MAX_COMMAND_CHARS karakter)"
                )
            )
            return
        }

        val timeoutSeconds = (call.argument<Int>("timeoutSeconds") ?: 60).coerceIn(1, 300)
        val workdir = (call.argument<String>("workdir") ?: "").trim()
            .ifEmpty { TERMUX_HOME }

        val id = requestCode.getAndIncrement()
        val resultAction = "$RESULT_ACTION_PREFIX$id"

        val payload = Bundle()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val bundle = intent?.getBundleExtra(EXTRA_RESULT_BUNDLE)
                synchronized(payload) {
                    if (bundle != null) {
                        payload.putString(KEY_STDOUT, bundle.getString(KEY_STDOUT) ?: "")
                        payload.putString(KEY_STDERR, bundle.getString(KEY_STDERR) ?: "")
                        payload.putInt(KEY_EXIT_CODE, bundle.getInt(KEY_EXIT_CODE, -1))
                        payload.putInt(KEY_ERR, bundle.getInt(KEY_ERR, 0))
                        payload.putString(KEY_ERRMSG, bundle.getString(KEY_ERRMSG) ?: "")
                        payload.putBoolean(KEY_DONE, true)
                    }
                }
            }
        }

        val filter = IntentFilter(resultAction)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                context.registerReceiver(receiver, filter)
            }
        } catch (e: Exception) {
            result.success(
                mapOf("ok" to false, "error" to "sonuç alıcısı kaydedilemedi: ${e.message}")
            )
            return
        }

        // Termux sonucu bu intent'i doldurarak geri gönderecek; bu yüzden
        // PendingIntent MUTABLE olmalı (IMMUTABLE ile bundle boş gelir).
        val resultIntent = Intent(resultAction).setPackage(context.packageName)
        val pendingFlags = PendingIntent.FLAG_ONE_SHOT or
            PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pendingIntent = PendingIntent.getBroadcast(
            context, id, resultIntent, pendingFlags
        )

        val intent = Intent().apply {
            setClassName(TERMUX_PACKAGE, RUN_COMMAND_SERVICE)
            action = ACTION_RUN_COMMAND
            putExtra(EXTRA_COMMAND_PATH, "$TERMUX_PREFIX/bin/bash")
            putExtra(EXTRA_ARGUMENTS, arrayOf("-c", command))
            putExtra(EXTRA_WORKDIR, workdir)
            putExtra(EXTRA_BACKGROUND, true)
            putExtra(EXTRA_PENDING_INTENT, pendingIntent)
            putExtra(EXTRA_COMMAND_LABEL, "Ajan komutu")
        }

        try {
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (e: Exception) {
            safeUnregister(receiver)
            result.success(
                mapOf(
                    "ok" to false,
                    "error" to "Termux komutu başlatılamadı: ${e.message}",
                    "hint" to "Termux kurulu mu ve allow-external-apps=true mı? " +
                        "device(action=\"termux\") ile ölç."
                )
            )
            return
        }

        // Sonucu bekle. Termux hiç yanıt vermezse (izin kapalı, Termux kapalı)
        // zaman aşımıyla dürüst bir hata döner.
        Thread {
            val start = System.currentTimeMillis()
            val deadline = start + timeoutSeconds * 1000L
            var done = false
            while (System.currentTimeMillis() < deadline) {
                synchronized(payload) { if (payload.getBoolean(KEY_DONE, false)) done = true }
                if (done) break
                try {
                    Thread.sleep(100)
                } catch (e: InterruptedException) {
                    break
                }
            }
            safeUnregister(receiver)

            val stdout: String
            val stderr: String
            val exitCode: Int
            val err: Int
            val errmsg: String
            synchronized(payload) {
                stdout = payload.getString(KEY_STDOUT) ?: ""
                stderr = payload.getString(KEY_STDERR) ?: ""
                exitCode = payload.getInt(KEY_EXIT_CODE, -1)
                err = payload.getInt(KEY_ERR, 0)
                errmsg = payload.getString(KEY_ERRMSG) ?: ""
            }

            val response: Map<String, Any?> = if (done) {
                mapOf(
                    "ok" to (err == 0 && exitCode == 0),
                    "exitCode" to exitCode,
                    "timedOut" to false,
                    "stdout" to clip(stdout),
                    "stderr" to clip(stderr),
                    "termuxErr" to err,
                    "termuxErrmsg" to errmsg,
                    "elapsedMs" to (System.currentTimeMillis() - start)
                )
            } else {
                mapOf(
                    "ok" to false,
                    "exitCode" to -1,
                    "timedOut" to true,
                    "stdout" to "",
                    "stderr" to "",
                    "elapsedMs" to (System.currentTimeMillis() - start),
                    "error" to "Termux ${timeoutSeconds} saniye içinde sonuç döndürmedi.",
                    "hint" to "Termux açık mı? ~/.termux/termux.properties içinde " +
                        "allow-external-apps=true var mı? device(action=\"termux\") ile ölç."
                )
            }
            // MethodChannel sonucu platform ana iş parçacığında dönmeli.
            Handler(Looper.getMainLooper()).post { result.success(response) }
        }.start()
    }

    private fun safeUnregister(receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (e: Exception) {
            // zaten kaldırılmış olabilir
        }
    }

    private fun clip(value: String): String =
        if (value.length <= MAX_OUTPUT) {
            value
        } else {
            value.substring(0, MAX_OUTPUT) +
                "\n… [${value.length - MAX_OUTPUT} karakter kısaltıldı]"
        }

    companion object {
        const val CHANNEL = "ai_music_hub/termux"
        const val MAX_OUTPUT = 16000
        const val MAX_COMMAND_CHARS = 4000

        // TermuxConstants (termux-shared) ile birebir aynı değerler.
        const val TERMUX_PREFIX = "/data/data/com.termux/files/usr"
        const val TERMUX_HOME = "/data/data/com.termux/files/home"
        const val RUN_COMMAND_SERVICE = "$TERMUX_PACKAGE.app.RunCommandService"
        const val ACTION_RUN_COMMAND = "$TERMUX_PACKAGE.RUN_COMMAND"
        const val EXTRA_COMMAND_PATH = "$TERMUX_PACKAGE.RUN_COMMAND_PATH"
        const val EXTRA_ARGUMENTS = "$TERMUX_PACKAGE.RUN_COMMAND_ARGUMENTS"
        const val EXTRA_WORKDIR = "$TERMUX_PACKAGE.RUN_COMMAND_WORKDIR"
        const val EXTRA_BACKGROUND = "$TERMUX_PACKAGE.RUN_COMMAND_BACKGROUND"
        const val EXTRA_PENDING_INTENT = "$TERMUX_PACKAGE.RUN_COMMAND_PENDING_INTENT"
        const val EXTRA_COMMAND_LABEL = "$TERMUX_PACKAGE.RUN_COMMAND_COMMAND_LABEL"

        // Sonuç bundle anahtarları (TERMUX_SERVICE.EXTRA_PLUGIN_RESULT_BUNDLE_*).
        const val EXTRA_RESULT_BUNDLE = "result"
        const val KEY_STDOUT = "stdout"
        const val KEY_STDERR = "stderr"
        const val KEY_EXIT_CODE = "exitCode"
        const val KEY_ERR = "err"
        const val KEY_ERRMSG = "errmsg"
        const val KEY_DONE = "done"

        const val RESULT_ACTION_PREFIX = "com.example.ai_music_hub.TERMUX_RESULT_"
    }
}
