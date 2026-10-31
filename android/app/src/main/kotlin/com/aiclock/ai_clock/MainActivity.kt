package com.aiclock.ai_clock

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：继承 audio_service 的 AudioServiceActivity（实体媒体键路由
 * 必须经它转发，ADR-0001），并挂载两个 MethodChannel——
 * `aiclock/permissions`：电池优化白名单等系统设置页跳转（US-H01，R3 接入）；
 * `aiclock/media_forward`：「音乐下一首」转发（看板 #33/#38）——
 *   软路径 dispatchNext：AudioManager.dispatchMediaKeyEvent（实测被
 *     M500 ROM 的媒体会话仲裁吞掉，无效，保留作回退）；
 *   硬路径 dispatchNextDirect：经通知监听权限拿到外部媒体会话，
 *     直接 transportControls.skipToNext()，绕过 ROM 路由。
 *
 * `aiclock/backgrounds`：背景图入库（看板 #55）——系统选图 → 原生解码/缩放/
 *   旋转/WebP 编码 → 落到应用专属外存 `backgrounds/`。策略（目标尺寸）由
 *   Dart 算好传下来，原生只当执行器（见 BackgroundImportPlugin.kt）。
 *
 * `aiclock/device`：机型标识上报（看板 #56）——Build.MODEL 等四个静态
 *   字段，供 Dart 判定「是否 M500」（见 DeviceProfilePlugin.kt）。
 *
 * `aiclock/audio`：自定义提示音（2026-10-05）——系统选音频拷入应用外存
 *   `tones/`、探测时长、解码 PCM 降采样波形（见 AudioToolsPlugin.kt）。
 *
 * `aiclock/lyrics`：歌词目录（2026-10-06）——SAF 目录选择器把用户的
 *   .lrc 文件夹永久授权给本应用，零权限递归读歌词（见 LyricsPlugin.kt；
 *   解决 Android/data 专属目录在新安卓上文件管理器写不进的问题）。
 *
 * 伴生原生组件：BootReceiver.kt（US-C01 开机恢复引导通知，看板 #41）。
 * 长按 key down/up 上报仍为预留项（M500 ROM 实测不上报长按，R1）。
 */
class MainActivity : AudioServiceActivity() {

    /// 背景导入：必须在 onCreate 前建好（持有选图回调的 pending result）
    private lateinit var backgroundImport: BackgroundImportPlugin

    /// 提示音导入：同上（持有选音频回调的 pending result）
    private lateinit var audioTools: AudioToolsPlugin

    /// 歌词目录（SAF）：同上（持有选目录回调的 pending result，2026-10-06）
    private lateinit var lyrics: LyricsPlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        // 竖屏开关必须在首帧前生效（PD 2026-10-06：打开 App 不再先
        // 闪一帧横屏再跳竖屏）——manifest 保持 fullUser（跟随传感器），
        // 这里在 super.onCreate 之前按开关锁定/放开；运行中的热切换仍由
        // Dart 侧 SystemChrome.setPreferredOrientations 负责。
        // 存储是 shared_preferences 的 FlutterSharedPreferences，
        // 键带 flutter. 前缀。
        val portraitEnabled = getSharedPreferences(
            "FlutterSharedPreferences", MODE_PRIVATE
        ).getBoolean("flutter.portrait_layout_enabled", false)
        requestedOrientation = if (portraitEnabled) {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        } else {
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceProfilePlugin.register(flutterEngine)
        backgroundImport = BackgroundImportPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BackgroundImportPlugin.CHANNEL
        ).setMethodCallHandler(backgroundImport)
        audioTools = AudioToolsPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AudioToolsPlugin.CHANNEL
        ).setMethodCallHandler(audioTools)
        lyrics = LyricsPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LyricsPlugin.CHANNEL
        ).setMethodCallHandler(lyrics)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiclock/permissions"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 跳转系统「忽略电池优化」名单页（直接请求授权需
                // REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 权限且上架审核敏感，
                // 故走名单页让用户手动勾选，dontkillmyapp 推荐路径）
                "openBatteryOptimizationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    )
                    result.success(true)
                }
                // 查询本应用是否已在电池优化白名单中
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aiclock/media_forward"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // 硬路径（看板 #38）：直控外部媒体会话，绕过 ROM 路由。
                // 返回是否找到并指挥了目标（false → Dart 回退软路径）
                "dispatchNextDirect" -> {
                    result.success(dispatchNextToExternalPlayer())
                }
                // 通知监听权限（硬路径前置）状态查询
                "isMusicControlGranted" -> {
                    val flat = Settings.Secure.getString(
                        contentResolver, "enabled_notification_listeners"
                    )
                    result.success(flat?.contains(packageName) == true)
                }
                // 跳转系统「通知读取权限」设置页
                "openMusicControlSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    )
                    result.success(true)
                }
                // 读取外部媒体会话的「正在播放」（竖屏歌词区，2026-10-05）：
                // 与硬路径同资格（通知监听权限 → getActiveSessions），
                // 返回 歌名/歌手/专辑/播放状态/播放位置；无外部会话/未授权
                // 返回 null，Dart 侧歌词区隐藏。
                "getNowPlaying" -> {
                    result.success(getNowPlaying())
                }
                // 软路径回退：向系统派发完整的「下一曲」按键（DOWN+UP 成对，
                // 部分 ROM 只认成对事件）。M500 实测无效，仅作降级兜底
                "dispatchNext" -> {
                    val am = getSystemService(AUDIO_SERVICE) as AudioManager
                    am.dispatchMediaKeyEvent(
                        KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_NEXT)
                    )
                    am.dispatchMediaKeyEvent(
                        KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_NEXT)
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 选图结果转发。无条件先交给 embedding（其它插件也要用），
     * 再问一次背景导入——它只认自己的 requestCode，认不出就返回 false。
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::backgroundImport.isInitialized) {
            backgroundImport.onActivityResult(requestCode, resultCode, data)
        }
        if (::audioTools.isInitialized) {
            audioTools.onActivityResult(requestCode, resultCode, data)
        }
        if (::lyrics.isInitialized) {
            lyrics.onActivityResult(requestCode, resultCode, data)
        }
    }

    /**
     * 硬路径：枚举活跃媒体会话，挑一个外部播放器直接 skipToNext()。
     * 优先正在播放的会话（音乐 App 后台播放场景）；都没有则取第一个
     * 外部会话。未授权通知监听 / 无外部会话 / 任何异常 → false。
     */
    private fun dispatchNextToExternalPlayer(): Boolean {
        return try {
            val manager =
                getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
            val component =
                ComponentName(this, MusicControlListenerService::class.java)
            val externals = manager.getActiveSessions(component)
                .filter { it.packageName != packageName }
            if (externals.isEmpty()) return false
            val target = externals.firstOrNull {
                it.playbackState?.state == PlaybackState.STATE_PLAYING
            } ?: externals.first()
            target.transportControls.skipToNext()
            true
        } catch (e: Exception) {
            // SecurityException（未授权）及一切 ROM 差异：静默降级软路径
            false
        }
    }

    /**
     * 竖屏歌词区数据源：取外部媒体会话的当前播放信息快照。
     * 优先正在播放的会话；歌名/歌手都空视为无效占位会话（返回 null）。
     * 未授权通知监听 / 无外部会话 / 任何异常 → null（Dart 侧隐藏歌词区）。
     */
    private fun getNowPlaying(): Map<String, Any>? {
        return try {
            val manager =
                getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
            val component =
                ComponentName(this, MusicControlListenerService::class.java)
            val externals = manager.getActiveSessions(component)
                // 双保险排除本 App 自己的 MediaSession（专注时我们在
                // 播静音 keep-alive，会话 title 固定「MikuFocus」；
                // startsWith 覆盖 applicationId 带后缀的变体）：
                // 包名相等之外再看标题——ROM 若把会话归属报歪也不会漏
                .filter {
                    it.packageName != packageName &&
                        !it.packageName.startsWith(packageName) &&
                        it.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) != "MikuFocus"
                }
            if (externals.isEmpty()) return null
            val target = externals.firstOrNull {
                it.playbackState?.state == PlaybackState.STATE_PLAYING
            } ?: externals.first()
            val md = target.metadata ?: return null
            val title = md.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
            val artist = md.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""
            if (title.isEmpty() && artist.isEmpty()) return null
            mapOf(
                "title" to title,
                "artist" to artist,
                "album" to (md.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""),
                "playing" to
                    (target.playbackState?.state == PlaybackState.STATE_PLAYING),
                "positionMs" to (target.playbackState?.position ?: 0L),
            )
        } catch (e: Exception) {
            null
        }
    }
}
