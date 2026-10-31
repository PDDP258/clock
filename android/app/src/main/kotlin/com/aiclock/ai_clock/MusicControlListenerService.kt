package com.aiclock.ai_clock

import android.service.notification.NotificationListenerService

/**
 * 通知监听权限载体（「音乐下一首」硬路径，看板 #38）。
 *
 * 本服务不读任何通知内容——`MediaSessionManager.getActiveSessions()`
 * 只接受持有通知监听权限的调用方，本服务的存在仅为让系统设置的
 * 「通知读取权限」列表里出现本 App 的开关。授权后 Dart 侧即可
 * 直接拿到音乐 App 的 MediaSession 并 skipToNext()，绕过 M500 ROM
 * 的媒体键路由（软路径 AudioManager.dispatchMediaKeyEvent 实测无效）。
 */
class MusicControlListenerService : NotificationListenerService()
