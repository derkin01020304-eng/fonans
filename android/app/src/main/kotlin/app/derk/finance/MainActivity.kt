package app.derk.finance

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var permissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Screenshots are permitted at the owner's request. PIN/biometric locking remains.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.derk.finance/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) {
                                result.error("BUSY", "Permission request pending", null)
                            } else {
                                permissionResult = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 942)
                            }
                        } else result.success(true)
                    }
                    "scheduleReminders" -> {
                        val times = (call.arguments as? List<*>)?.mapNotNull { (it as? Number)?.toLong() } ?: emptyList()
                        ReminderScheduler.replace(this, times.take(90))
                        result.success(null)
                    }
                    "configureNotificationImport" -> {
                        val args = call.arguments as Map<*, *>
                        val packages = (args["packages"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                        if (packages.any { !it.matches(Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z0-9_]+)+")) }) {
                            result.error("PACKAGES", "Invalid package name", null)
                        } else {
                            getSharedPreferences("notification_import", MODE_PRIVATE).edit()
                                .putBoolean("enabled", args["enabled"] == true)
                                .putStringSet("packages", packages.toSet()).apply()
                            result.success(null)
                        }
                    }
                    "openNotificationAccess" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "setUnlocked" -> {
                        BankNotificationListener.unlocked = call.arguments == true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "app.derk.finance/bank_notifications")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { BankNotificationListener.sink = events }
                override fun onCancel(arguments: Any?) { BankNotificationListener.sink = null }
            })
    }
    override fun onPause() {
        BankNotificationListener.unlocked = false
        super.onPause()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 942) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}
