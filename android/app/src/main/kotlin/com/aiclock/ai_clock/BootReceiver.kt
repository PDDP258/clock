package com.aiclock.ai_clock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * 开机恢复引导（US-C01，看板 #41）。
 *
 * Android 14 不允许从 BOOT_COMPLETED 直接启动 mediaPlayback 类型前台服务，
 * 可行形态 = 开机后检测到未完成的专注会话时发一条通知，用户点按回到 App，
 * 由 Dart 侧既有的时间戳恢复/跨天守卫/自动结束逻辑接管后续。
 *
 * 判据：Flutter shared_preferences（FlutterSharedPreferences 文件，
 * 键带 flutter. 前缀）里存在 `focus_session_start`——该键仅在有进行中/
 * 待继续会话时由 FocusController 持久化，会话结束即移除，零新增写入路径。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        // 键不存在 = 无未完成的会话，静默退出（开机零打扰原则）
        if (!prefs.contains("flutter.focus_session_start")) return

        // Android 13+ 通知运行时权限未授予时静默退出
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "专注恢复", NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pending = PendingIntent.getActivity(
            context, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_focus)
            .setContentTitle("MikuFocus")
            .setContentText("有未完成的专注，点按回来继续")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    companion object {
        private const val CHANNEL_ID = "focus_boot_recovery"
        private const val NOTIFICATION_ID = 42
    }
}
