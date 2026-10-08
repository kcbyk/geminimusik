package com.example.ai_music_hub

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Ajanın "cihaz" katmanı.
 *
 * Dart tarafındaki `pm list packages` / `am start` komutları sıradan bir
 * uygulamada genelde "Permission Denial" ile döner. Burada gerçek Android
 * API'leri (PackageManager) kullanılıyor; manifest'teki QUERY_ALL_PACKAGES
 * izni sayesinde kurulu uygulamaların tamamı görülebilir.
 */
class AgentDeviceChannel(private val context: Context) {

    private val pm: PackageManager get() = context.packageManager

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "listApps" -> result.success(listApps(call))
                "isInstalled" -> result.success(isInstalled(call))
                "resolvePackage" -> result.success(resolvePackage(call))
                "appInfo" -> result.success(appInfo(call))
                "openApp" -> result.success(openApp(call))
                "openAppSettings" -> result.success(openAppSettings(call))
                "isTermuxInstalled" -> result.success(isTermuxInstalled())
                "termuxInfo" -> result.success(termuxInfo())
                "termuxOpenSettings" -> result.success(termuxOpenSettings())
                "termuxOpenStore" -> result.success(termuxOpenStore())
                "deviceInfo" -> result.success(deviceInfo())
                "permissionStatus" -> result.success(permissionStatus(call))
                "openPermissionSettings" ->
                    result.success(openPermissionSettings(call))
                "batteryOptimization" -> result.success(batteryOptimization())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("native_error", e.message ?: e.javaClass.simpleName, null)
        }
    }

    // ------------------------------------------------------------------ apps

    private fun listApps(call: MethodCall): Map<String, Any> {
        val query = (call.argument<String>("query") ?: "").trim().lowercase()
        val onlyUser = call.argument<Boolean>("thirdParty") ?: false
        val onlyLaunchable = call.argument<Boolean>("launchable") ?: false
        val limit = (call.argument<Int>("limit") ?: 300).coerceIn(1, 800)

        @Suppress("DEPRECATION")
        val packages: List<PackageInfo> = pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)

        val rows = ArrayList<Map<String, Any?>>()
        for (info in packages) {
            val pkg = info.packageName ?: continue
            val appInfo = info.applicationInfo ?: continue

            val system = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            if (onlyUser && system) continue

            val label = pm.getApplicationLabel(appInfo).toString()
            if (query.isNotEmpty() &&
                !label.lowercase().contains(query) &&
                !pkg.lowercase().contains(query)
            ) {
                continue
            }
            if (onlyLaunchable && pm.getLaunchIntentForPackage(pkg) == null) continue

            rows.add(
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "system" to system,
                    "launchable" to (pm.getLaunchIntentForPackage(pkg) != null),
                    "version" to versionName(info),
                    "enabled" to appInfo.enabled,
                    "permissionCount" to (info.requestedPermissions?.size ?: 0)
                )
            )
            if (rows.size >= limit) break
            if (query.isNotEmpty() && rows.size >= 25) break
        }

        rows.sortWith(compareBy<Map<String, Any?>> { it["label"]?.toString() ?: "" })
        return mapOf(
            "apps" to rows,
            "count" to rows.size,
            "truncated" to (rows.size >= limit),
            "visibleTotal" to packages.size
        )
    }

    private fun isInstalled(call: MethodCall): Boolean {
        val pkg = call.argument<String>("package") ?: return false
        return isPackage(pkg)
    }

    /** Verilen ipucunu (ad veya paket) kurulu bir pakete eşler. */
    private fun resolvePackage(call: MethodCall): Map<String, Any?> {
        val query = (call.argument<String>("query") ?: "").trim()
        if (query.isEmpty()) {
            return mapOf("ok" to false, "error" to "query boş olamaz")
        }

        // 1) doğrudan paket adı
        if (query.contains('.') && isPackage(query)) {
            return mapOf("ok" to true, "package" to query, "label" to labelOf(query))
        }

        val q = query.lowercase()
        val all: List<PackageInfo> = try {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(0)
        } catch (e: Exception) {
            emptyList()
        }

        data class Match(val pkg: String, val label: String, val score: Int)

        val matches = ArrayList<Match>()
        for (info in all) {
            val pkg = info.packageName ?: continue
            val label = labelOf(pkg)
            val labelKey = label.lowercase()
            val score = when {
                pkg.equals(query, ignoreCase = true) -> 100
                labelKey.equals(q) -> 95
                pkg.endsWith(".$q") -> 80
                labelKey.startsWith(q) -> 70
                labelKey.contains(q) -> 60
                pkg.contains(q) -> 50
                else -> -1
            }
            if (score >= 0) matches.add(Match(pkg, label, score))
        }

        if (matches.isEmpty()) {
            return mapOf(
                "ok" to false,
                "error" to "\"$query\" için kurulu uygulama bulunamadı",
                "hint" to "list_apps ile gerçek adı/paketi ara"
            )
        }
        matches.sortWith(compareByDescending<Match> { it.score }.thenBy { it.label })
        val best = matches.first()
        return mapOf(
            "ok" to true,
            "package" to best.pkg,
            "label" to best.label,
            "candidates" to matches.take(5).map {
                mapOf("package" to it.pkg, "label" to it.label)
            }
        )
    }

    private fun appInfo(call: MethodCall): Map<String, Any?> {
        val pkg = call.argument<String>("package") ?: ""
        if (pkg.isEmpty()) return mapOf("ok" to false, "error" to "package boş")
        val info: PackageInfo = try {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS)
        } catch (e: PackageManager.NameNotFoundException) {
            return mapOf("ok" to false, "error" to "$pkg kurulu değil")
        }
        val appInfo = info.applicationInfo
        val system = appInfo != null &&
            ((appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0)

        return mapOf(
            "ok" to true,
            "package" to pkg,
            "label" to labelOf(pkg),
            "version" to versionName(info),
            "versionCode" to versionCode(info),
            "system" to system,
            "enabled" to (appInfo?.enabled ?: true),
            "launchable" to (pm.getLaunchIntentForPackage(pkg) != null),
            "firstInstall" to (info.firstInstallTime / 1000L),
            "lastUpdate" to (info.lastUpdateTime / 1000L),
            "permissions" to (info.requestedPermissions?.take(60)?.toList()
                ?: emptyList<String>())
        )
    }

    private fun openApp(call: MethodCall): Map<String, Any?> {
        val pkg = call.argument<String>("package") ?: ""
        if (pkg.isEmpty()) return mapOf("ok" to false, "error" to "package boş")

        val intent = pm.getLaunchIntentForPackage(pkg)
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return try {
                context.startActivity(intent)
                mapOf("ok" to true, "via" to "launchIntent", "package" to pkg)
            } catch (e: ActivityNotFoundException) {
                monkey(pkg)
            } catch (e: SecurityException) {
                mapOf("ok" to false, "error" to "Android açılışı engelledi: ${e.message}")
            }
        }
        return monkey(pkg)
    }

    /** Launcher aktivitesi olmayan paketler için yedek yol. */
    private fun monkey(pkg: String): Map<String, Any?> {
        return try {
            val proc = Runtime.getRuntime().exec(
                arrayOf("monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1")
            )
            proc.waitFor()
            if (proc.exitValue() == 0) {
                mapOf("ok" to true, "via" to "monkey", "package" to pkg)
            } else {
                mapOf(
                    "ok" to false,
                    "error" to "$pkg açılamadı (launcher aktivitesi yok, exit=${proc.exitValue()})"
                )
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to "$pkg açılamadı: ${e.message}")
        }
    }

    private fun openAppSettings(call: MethodCall): Map<String, Any?> {
        val pkg = call.argument<String>("package") ?: context.packageName
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", pkg, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            mapOf("ok" to true)
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to "Ayarlar açılamadı: ${e.message}")
        }
    }

    // ---------------------------------------------------------------- termux

    private fun isTermuxInstalled(): Boolean = isPackage(TERMUX_PACKAGE)

    /**
     * Termux kurulu mu, dış uygulamalardan komut kabul ediyor mu?
     * Termux varsayılan olarak dışarıdan gelen RUN_COMMAND intent'lerini
     * REDDEDER; bunun için ~/.termux/termux.properties içinde
     * `allow-external-apps=true` gerekir. Bu bilgi kullanıcıya adım adım
     * gösterilir.
     */
    private fun termuxInfo(): Map<String, Any?> {
        val installed = isTermuxInstalled()
        if (!installed) {
            return mapOf(
                "installed" to false,
                "externalAppsAllowed" to false,
                "message" to "Termux kurulu değil.",
                "storeIntent" to true
            )
        }

        val props = readTermuxProperties()
        val allowLine = props?.lines()?.firstOrNull {
            it.trim().startsWith("allow-external-apps")
        }
        val allowed = allowLine != null &&
            allowLine.substringAfter('=', "false").trim().equals("true", true)

        val steps = listOf(
            "Termux'u aç.",
            "Şu komutu yapıştır ve çalıştır: mkdir -p ~/.termux && " +
                "echo \"allow-external-apps=true\" >> ~/.termux/termux.properties",
            "Ardından şunu çalıştır: termux-reload-settings",
            "Termux'u tamamen kapat (bildirim çubuğundaki bildirimden Exit) ve tekrar aç.",
            "Sonra bu uygulamaya dön; ajan Termux'ta komut çalıştırabilir."
        )

        return mapOf(
            "installed" to true,
            "externalAppsAllowed" to allowed,
            "propertiesReadable" to (props != null),
            "allowLine" to allowLine,
            "runCommandPermission" to hasRunCommandPermission(),
            "prefixExists" to java.io.File("$TERMUX_PREFIX/bin").exists(),
            "message" to if (allowed) {
                "Termux hazır: dışarıdan komut kabul ediyor."
            } else {
                "Termux kurulu ama dış uygulamalardan komut kabul etmiyor. " +
                    "Tek seferlik ayar gerekiyor."
            },
            "setupSteps" to steps,
            "storeIntent" to true
        )
    }

    private fun hasRunCommandPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= 23) {
            context.checkSelfPermission("com.termux.permission.RUN_COMMAND") ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /**
     * termux.properties'i okumayı dener. Termux'un veri klasörü başka bir
     * UID'ye ait olduğu için bu genelde okunamaz; null döner ve "bilinmiyor"
     * olarak raporlanır (yanlış negatif üretmemek için).
     */
    private fun readTermuxProperties(): String? {
        val paths = listOf(
            "$TERMUX_HOME/.termux/termux.properties",
            "/data/data/$TERMUX_PACKAGE/files/home/.termux/termux.properties"
        )
        for (path in paths) {
            try {
                val f = java.io.File(path)
                if (f.canRead()) return f.readText()
            } catch (e: Exception) {
                // yut: okunamaması normal
            }
        }
        return null
    }

    /**
     * Termux'u ön plana getirir: tek seferlik ayar Termux'un kendi kabuğunda
     * komut çalıştırılarak yapılıyor, o yüzden kullanıcı oraya gönderilir.
     */
    private fun termuxOpenSettings(): Map<String, Any?> {
        if (!isTermuxInstalled()) {
            return mapOf("ok" to false, "error" to "Termux kurulu değil")
        }
        val intent = pm.getLaunchIntentForPackage(TERMUX_PACKAGE)
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return try {
                context.startActivity(intent)
                mapOf("ok" to true, "via" to "launchIntent")
            } catch (e: Exception) {
                mapOf("ok" to false, "error" to "Termux açılamadı: ${e.message}")
            }
        }
        return mapOf("ok" to false, "error" to "Termux başlatma aktivitesi bulunamadı")
    }

    private fun termuxOpenStore(): Map<String, Any?> {
        val candidates = listOf(
            Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$TERMUX_PACKAGE")),
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://f-droid.org/packages/$TERMUX_PACKAGE/")
            )
        )
        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return mapOf("ok" to true)
            } catch (e: Exception) {
                // sıradakini dene
            }
        }
        return mapOf("ok" to false, "error" to "Mağaza açılamadı")
    }

    // ------------------------------------------------------------- permissions

    private fun permissionStatus(call: MethodCall): Map<String, Any?> {
        val requested = call.argument<List<String>>("permissions") ?: emptyList()
        val out = LinkedHashMap<String, Any?>()
        for (key in requested) {
            out[key] = statusOf(key)
        }
        return out
    }

    private fun statusOf(key: String): String {
        val android = androidPermissionFor(key)
        if (android == null) return specialStatus(key)
        return if (isGranted(android)) "granted" else "denied"
    }

    private fun specialStatus(key: String): String = when (key) {
        "allFiles" ->
            if (Build.VERSION.SDK_INT >= 30 &&
                android.os.Environment.isExternalStorageManager()
            ) {
                "granted"
            } else if (Build.VERSION.SDK_INT < 30) {
                "notRequired"
            } else {
                "denied"
            }

        "battery" ->
            if (isIgnoringBatteryOptimizations()) "granted" else "denied"

        "overlay" ->
            if (Build.VERSION.SDK_INT >= 23 && Settings.canDrawOverlays(context)) {
                "granted"
            } else if (Build.VERSION.SDK_INT < 23) {
                "notRequired"
            } else {
                "denied"
            }

        else -> "unknown"
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return try {
            val pms = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            pms?.isIgnoringBatteryOptimizations(context.packageName) ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun isGranted(permission: String): Boolean {
        return if (Build.VERSION.SDK_INT >= 23) {
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    /**
     * İzin ekranını açar. Gerçek çalışma zamanı izinleri permission_handler
     * ile Dart tarafından istenir; burada yalnızca "Ayarlardan ver" gereken
     * özel izinler (tüm dosyalar, pil, üzerinde çizim) ele alınır.
     */
    private fun openPermissionSettings(call: MethodCall): Map<String, Any?> {
        val key = call.argument<String>("permission") ?: ""
        val pkg = context.packageName
        val intent: Intent? = when (key) {
            "allFiles" ->
                if (Build.VERSION.SDK_INT >= 30) {
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.fromParts("package", pkg, null)
                    )
                } else {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", pkg, null)
                    }
                }

            "battery" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)

            "overlay" ->
                if (Build.VERSION.SDK_INT >= 23) {
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.fromParts("package", pkg, null)
                    )
                } else {
                    null
                }

            "appSettings" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", pkg, null)
            }

            "settings" -> Intent(Settings.ACTION_SETTINGS)
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", pkg, null)
            }
        }

        if (intent == null) {
            return mapOf("ok" to false, "error" to "$key için ayar ekranı yok")
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            mapOf("ok" to true, "screen" to key)
        } catch (e: ActivityNotFoundException) {
            // Bazı üreticiler özel ekranları kaldırmış olabilir.
            try {
                val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", pkg, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallback)
                mapOf("ok" to true, "screen" to "appSettings", "fallback" to true)
            } catch (e2: Exception) {
                mapOf("ok" to false, "error" to "Ayarlar açılamadı: ${e2.message}")
            }
        }
    }

    private fun batteryOptimization(): Map<String, Any?> {
        val ignoring = isIgnoringBatteryOptimizations()
        return mapOf(
            "ignoring" to ignoring,
            "opened" to openPermissionSettings(
                MethodCall("openPermissionSettings", mapOf("permission" to "battery"))
            )["ok"]
        )
    }

    // ------------------------------------------------------------- device info

    private fun deviceInfo(): Map<String, Any?> {
        val runtime = Runtime.getRuntime()
        val freeMb = runtime.freeMemory() / 1048576L
        val totalMb = runtime.totalMemory() / 1048576L
        val maxMb = runtime.maxMemory() / 1048576L

        val storage = context.getExternalFilesDir(null)
        val freeGb = if (storage != null) {
            storage.freeSpace / 1073741824.0
        } else {
            -1.0
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "package" to context.packageName,
            "pid" to Process.myPid(),
            "uid" to Process.myUid(),
            "appVersion" to versionName(
                try {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(context.packageName, 0)
                } catch (e: Exception) {
                    null
                }
            ),
            "abi" to Build.SUPPORTED_ABIS.toList(),
            "javaHeap" to mapOf(
                "freeMb" to freeMb,
                "totalMb" to totalMb,
                "maxMb" to maxMb
            ),
            "externalFreeGb" to freeGb,
            "externalDir" to storage?.absolutePath,
            "isExternalStorageManager" to
                (Build.VERSION.SDK_INT >= 30 &&
                    android.os.Environment.isExternalStorageManager()),
            "canDrawOverlays" to
                (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(context))
        )
    }

    // --------------------------------------------------------------- helpers

    private fun isPackage(pkg: String): Boolean {
        return try {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(pkg, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun labelOf(pkg: String): String {
        return try {
            @Suppress("DEPRECATION")
            val ai = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(ai).toString()
        } catch (e: Exception) {
            pkg
        }
    }

    private fun versionName(info: PackageInfo?): String =
        info?.versionName ?: "bilinmiyor"

    private fun versionCode(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    companion object {
        const val CHANNEL = "ai_music_hub/device"
        const val TERMUX_PACKAGE = "com.termux"
        const val TERMUX_PREFIX = "/data/data/com.termux/files/usr"
        const val TERMUX_HOME = "/data/data/com.termux/files/home"
    }
}
