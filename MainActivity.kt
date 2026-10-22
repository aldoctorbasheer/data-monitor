package com.example.data_usage_monitor

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager as PmPkg

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.provider.MediaStore
import android.provider.Settings
import android.util.Base64
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayList
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.data_usage_monitor/network_stats"
    private val VPN_REQUEST_CODE = 9011
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingBlockedPackages: ArrayList<String>? = null
    private var pendingVpnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkUsagePermission" -> {
                        result.success(hasUsageStatsPermission())
                    }
                    "openUsageAccessSettings" -> {
                        openUsageSettings()
                        result.success(true)
                    }
                    "getAppDataUsage" -> {
                        val startTime = call.argument<Number>("startTime")?.toLong() ?: 0L
                        val endTime = call.argument<Number>("endTime")?.toLong()
                            ?: System.currentTimeMillis()
                        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

                        if (!hasUsageStatsPermission()) {
                            result.error(
                                "PERMISSION_DENIED",
                                "صلاحية الوصول إلى بيانات الاستخدام غير ممنوحة",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        executor.execute {
                            try {
                                val usageList = queryPerAppUsage(startTime, endTime, includeIcons)
                                mainHandler.post {
                                    result.success(usageList)
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("QUERY_ERROR", e.localizedMessage, null)
                                }
                            }
                        }
                    }
                    "updateBlockedApps" -> {
                        val packages = call.argument<List<String>>("blockedPackages") ?: emptyList()
                        val pkgArrayList = ArrayList(packages)

                        if (pkgArrayList.isEmpty()) {
                            stopFirewallVpn()
                            result.success(
                                mapOf(
                                    "vpnActive" to false,
                                    "blockedCount" to 0
                                )
                            )
                            return@setMethodCallHandler
                        }

                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            pendingBlockedPackages = pkgArrayList
                            pendingVpnResult = result
                            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                        } else {
                            startFirewallVpn(pkgArrayList)
                            result.success(
                                mapOf(
                                    "vpnActive" to true,
                                    "blockedCount" to pkgArrayList.size
                                )
                            )
                        }
                    }
                    "getVpnStatus" -> {
                        result.success(
                            mapOf(
                                "vpnActive" to FirewallVpnService.isRunning,
                                "blockedPackages" to FirewallVpnService.currentBlockedPackages.toList()
                            )
                        )
                    }
                    "showSystemNotification" -> {
                        val title = call.argument<String>("title") ?: "تنبيه استهلاك البيانات"
                        val body = call.argument<String>("body") ?: ""
                        showNativeNotification(title, body)
                        result.success(true)
                    }
                    "exportReportToDownloads" -> {
                        val fileName = call.argument<String>("fileName")
                            ?: "DataUsage_Report.csv"
                        val csvContent = call.argument<String>("csvContent") ?: ""
                        executor.execute {
                            try {
                                val savedPath = saveCsvToDownloads(fileName, csvContent)
                                mainHandler.post {
                                    result.success(savedPath)
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("EXPORT_ERROR", e.localizedMessage, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val pkgs = pendingBlockedPackages
            val res = pendingVpnResult
            pendingBlockedPackages = null
            pendingVpnResult = null

            if (resultCode == Activity.RESULT_OK && pkgs != null) {
                startFirewallVpn(pkgs)
                res?.success(
                    mapOf(
                        "vpnActive" to true,
                        "blockedCount" to pkgs.size
                    )
                )
            } else {
                res?.success(
                    mapOf(
                        "vpnActive" to false,
                        "blockedCount" to 0,
                        "permissionDenied" to true
                    )
                )
            }
        }
    }


    /**
     * إرسال إشعار نظام أندرويد أصلي عند اقتراب أو تجاوز السقف أو قطع الإنترنت
     */
    private fun showNativeNotification(title: String, body: String) {
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                if (checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PmPkg.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 9022)
                    return
                }
            }
            val channelId = "data_usage_alerts_channel"
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "تنبيهات استهلاك وقطع البيانات",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "إشعارات عند اقتراب أو تجاوز التطبيقات للسقف اليومي أو قطع الإنترنت"
                }
                manager.createNotificationChannel(channel)
            }

            val launchIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingFlags)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(this)
            }

            builder.setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(android.app.Notification.BigTextStyle().bigText(body))
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            manager.notify(title.hashCode(), builder.build())
        } catch (_: Exception) {
        }
    }

    private fun startFirewallVpn(blockedPackages: ArrayList<String>) {
        val intent = Intent(this, FirewallVpnService::class.java).apply {
            action = FirewallVpnService.ACTION_START_OR_UPDATE
            putStringArrayListExtra(FirewallVpnService.EXTRA_BLOCKED_PACKAGES, blockedPackages)
        }
        startService(intent)
    }

    private fun stopFirewallVpn() {
        val intent = Intent(this, FirewallVpnService::class.java).apply {
            action = FirewallVpnService.ACTION_STOP
        }
        startService(intent)
    }

    /**
     * حفظ ملف تقرير الترحيل (CSV المتوافق مع Excel باللغة العربية) في مجلد التنزيلات (Downloads)
     */
    private fun saveCsvToDownloads(fileName: String, content: String): String {
        // إضافة BOM لضمان قراءة الحروف العربية بشكل سليم في برنامج Excel
        val bomBytes = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        val contentBytes = content.toByteArray(Charsets.UTF_8)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw Exception("تعذر إنشاء ملف الترحيل في مجلد التنزيلات")
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bomBytes)
                out.write(contentBytes)
                out.flush()
            }
            return "Download/$fileName"
        } else {
            @Suppress("DEPRECATION")
            val downloadsDir =
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val file = File(downloadsDir, fileName)
            FileOutputStream(file).use { out ->
                out.write(bomBytes)
                out.write(contentBytes)
                out.flush()
            }
            return file.absolutePath
        }
    }

    /**
     * التحقق مما إذا كان المستخدم قد منح صلاحية PACKAGE_USAGE_STATS للتطبيق
     */
    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * فتح شاشة إعدادات النظام لمنح صلاحية الوصول إلى بيانات الاستخدام
     */
    private fun openUsageSettings() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            val fallbackIntent = Intent(Settings.ACTION_SETTINGS)
            fallbackIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(fallbackIntent)
        }
    }

    /**
     * استعلام تفصيلي عن استهلاك كل تطبيق من الواي فاي وبيانات الهاتف
     * مع فصل التنزيل (RX / Download) عن الرفع (TX / Upload)
     */
    private fun queryPerAppUsage(
        startTime: Long,
        endTime: Long,
        includeIcons: Boolean
    ): List<Map<String, Any?>> {
        val networkStatsManager =
            getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
        val pm = applicationContext.packageManager

        data class UidTraffic(
            var wifiRx: Long = 0L,
            var wifiTx: Long = 0L,
            var mobileRx: Long = 0L,
            var mobileTx: Long = 0L
        )

        val uidTrafficMap = mutableMapOf<Int, UidTraffic>()

        // 1. قراءة استهلاك الواي فاي (Wi-Fi)
        try {
            val wifiStats = networkStatsManager.querySummary(
                ConnectivityManager.TYPE_WIFI,
                null,
                startTime,
                endTime
            )
            val bucket = NetworkStats.Bucket()
            while (wifiStats.hasNextBucket()) {
                wifiStats.getNextBucket(bucket)
                val uid = bucket.uid
                val record = uidTrafficMap.getOrPut(uid) { UidTraffic() }
                record.wifiRx += bucket.rxBytes
                record.wifiTx += bucket.txBytes
            }
            wifiStats.close()
        } catch (_: Exception) {
        }

        // 2. قراءة استهلاك بيانات الهاتف (Mobile Data)
        try {
            val mobileStats = networkStatsManager.querySummary(
                ConnectivityManager.TYPE_MOBILE,
                null,
                startTime,
                endTime
            )
            val bucket = NetworkStats.Bucket()
            while (mobileStats.hasNextBucket()) {
                mobileStats.getNextBucket(bucket)
                val uid = bucket.uid
                val record = uidTrafficMap.getOrPut(uid) { UidTraffic() }
                record.mobileRx += bucket.rxBytes
                record.mobileTx += bucket.txBytes
            }
            mobileStats.close()
        } catch (_: Exception) {
        }

        // 3. ربط كل UID بالتطبيق المثبت على الهاتف (الاسم، الحزمة، الأيقونة)
        val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val uidToAppInfo = mutableMapOf<Int, ApplicationInfo>()
        for (app in installedApps) {
            val existing = uidToAppInfo[app.uid]
            if (existing == null || (existing.flags and ApplicationInfo.FLAG_SYSTEM) != 0) {
                uidToAppInfo[app.uid] = app
            }
        }

        val results = mutableListOf<Map<String, Any?>>()

        for ((uid, traffic) in uidTrafficMap) {
            val totalBytes =
                traffic.wifiRx + traffic.wifiTx + traffic.mobileRx + traffic.mobileTx
            if (totalBytes <= 0L) continue

            val appInfo = uidToAppInfo[uid]
            val appName: String
            val pkgName: String
            val isSystem: Boolean
            var iconBase64: String? = null

            when {
                appInfo != null -> {
                    appName = pm.getApplicationLabel(appInfo).toString()
                    pkgName = appInfo.packageName
                    isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                    if (includeIcons) {
                        iconBase64 = drawableToBase64(pm.getApplicationIcon(appInfo))
                    }
                }
                uid == NetworkStats.Bucket.UID_REMOVED -> {
                    appName = "تطبيقات محذوفة"
                    pkgName = "android.uid.removed"
                    isSystem = true
                }
                uid == NetworkStats.Bucket.UID_TETHERING -> {
                    appName = "نقطة الاتصال والمشاركة (Hotspot)"
                    pkgName = "android.uid.tethering"
                    isSystem = true
                }
                uid == Process.SYSTEM_UID -> {
                    appName = "نظام أندرويد الأساسي"
                    pkgName = "android.uid.system"
                    isSystem = true
                }
                else -> {
                    appName = "خدمة نظام ($uid)"
                    pkgName = "android.uid.$uid"
                    isSystem = true
                }
            }

            results.add(
                mapOf(
                    "uid" to uid,
                    "packageName" to pkgName,
                    "appName" to appName,
                    "isSystemApp" to isSystem,
                    "wifiRxBytes" to traffic.wifiRx,
                    "wifiTxBytes" to traffic.wifiTx,
                    "mobileRxBytes" to traffic.mobileRx,
                    "mobileTxBytes" to traffic.mobileTx,
                    "iconBase64" to iconBase64
                )
            )
        }

        return results
    }

    private fun drawableToBase64(drawable: Drawable): String? {
        return try {
            val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                Bitmap.createScaledBitmap(drawable.bitmap, 64, 64, true)
            } else {
                val bmp = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bmp)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bmp
            }
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 85, outputStream)
            Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * خدمة جدار الحماية المحلي (Local Sinkhole VPN)
 * تقوم بقطع الإنترنت فعلياً عن التطبيقات المحددة أو المتجاوزة للسقف اليومي فقط
 * باستخدام addAllowedApplication دون التأثير على سرعة الإنترنت لباقي تطبيقات الهاتف.
 */
class FirewallVpnService : VpnService() {
    companion object {
        const val ACTION_START_OR_UPDATE = "com.example.data_usage_monitor.START_VPN"
        const val ACTION_STOP = "com.example.data_usage_monitor.STOP_VPN"
        const val EXTRA_BLOCKED_PACKAGES = "blocked_packages"

        @Volatile
        var isRunning: Boolean = false

        val currentBlockedPackages: MutableSet<String> = mutableSetOf()
    }

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopFirewall()
            return START_NOT_STICKY
        }

        val packages =
            intent?.getStringArrayListExtra(EXTRA_BLOCKED_PACKAGES) ?: arrayListOf()
        if (packages.isEmpty()) {
            stopFirewall()
            return START_NOT_STICKY
        }

        rebuildVpnTunnel(packages)
        return START_STICKY
    }

    private fun rebuildVpnTunnel(packages: List<String>) {
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (_: Exception) {
        }

        try {
            val builder = Builder()
                .setSession("جدار حماية البيانات - قطع الإنترنت عن التطبيقات المتجاوزة")
                .addAddress("10.215.173.1", 30)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)
                .setMtu(1500)

            var blockedCount = 0
            currentBlockedPackages.clear()

            for (pkg in packages) {
                if (pkg == applicationContext.packageName) continue
                try {
                    // توجيه حركة مرور التطبيق المحظور فقط إلى داخل النفق المغلق لقطع الإنترنت عنه
                    builder.addAllowedApplication(pkg)
                    currentBlockedPackages.add(pkg)
                    blockedCount++
                } catch (_: Exception) {
                }
            }

            if (blockedCount > 0) {
                vpnInterface = builder.establish()
                isRunning = vpnInterface != null
            } else {
                stopFirewall()
            }
        } catch (_: Exception) {
            stopFirewall()
        }
    }

    private fun stopFirewall() {
        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null
        currentBlockedPackages.clear()
        isRunning = false
        stopSelf()
    }

    override fun onDestroy() {
        stopFirewall()
        super.onDestroy()
    }
}