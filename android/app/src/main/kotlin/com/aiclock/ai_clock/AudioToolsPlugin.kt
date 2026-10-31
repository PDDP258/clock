package com.aiclock.ai_clock

import android.app.Activity
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/**
 * 自定义提示音通道 `aiclock/audio`（2026-10-05 用户需求）。
 *
 * 与 `aiclock/backgrounds` 同一风格（零新依赖，原生只当执行器）：
 * - `pickAudio`：系统文件选择器选一条音频（单选），拷贝进应用专属外存
 *   `tones/t_<内容哈希8位>.<扩展名>`（内容去重，来源 URI 不需持久授权——
 *   片段播放只认本地拷贝）；`MediaMetadataRetriever` 报总时长；
 * - `extractWaveform`：`MediaExtractor`+`MediaCodec` 解码出 PCM，
 *   按时间桶取峰值降采样成振幅数组（0..1），给编辑浮窗画波形。
 *   解码在后台线程跑（2 分钟的 mp3 也要几百毫秒），结果回主线程投递。
 */
class AudioToolsPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "aiclock/audio"

        /// 提示音目录名（与 Dart 侧展示路径一致）
        private const val DIR_NAME = "tones"

        /// 音频文件 id 前缀
        private const val ID_PREFIX = "t_"

        private const val REQ_PICK = 4713
    }

    /// 选音频是异步的：pick 时存 pending result，onActivityResult 回填
    private var pendingPick: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickAudio" -> pickAudio(result)
            "extractWaveform" -> {
                val path = call.argument<String>("path")
                val bars = (call.argument<Number>("bars")?.toInt() ?: 120)
                    .coerceIn(24, 400)
                if (path.isNullOrEmpty()) {
                    result.success(emptyList<Double>()); return
                }
                // 解码放后台线程；MethodChannel.Result 回主线程投递
                Thread {
                    val waveform = runCatching { extractWaveform(path, bars) }
                        .getOrElse { emptyList() }
                    mainHandler.post { result.success(waveform) }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------ 选音频

    private fun pickAudio(result: MethodChannel.Result) {
        pendingPick?.success(null) // 上一次未回填（连点）：先收掉防泄漏
        pendingPick = result
        // 注意不能包 createChooser：chooser 转发会让部分文件管理器返回的
        // URI 带不上读权限，拷贝直接失败（背景图选图踩过同款坑，看板 #61）
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            // 没有文件选择器的 ROM：静默返回 null，Dart 侧提示
            pendingPick = null
            result.success(null)
        }
    }

    /** Activity 回调转发（MainActivity 无条件调用）。返回 true = 已消费。 */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val result = pendingPick ?: return false
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        result.success(importAudio(data.data!!))
        return true
    }

    /**
     * 拷贝进应用外存并探测时长。文件名 = `t_<MD5(内容) 前 8 位>.<ext>`，
     * 同一条音频重复选择只存一份。任何一步失败返回 null（Dart 侧提示重试）。
     */
    private fun importAudio(uri: Uri): Map<String, Any?>? {
        return try {
            val name = displayNameOf(uri) ?: "audio"
            val dir = File(activity.getExternalFilesDir(null), DIR_NAME)
            if (!dir.exists() && !dir.mkdirs()) return null

            // 流式读两遍代价可接受（音频几 MB）：先拷临时文件再按内容定名
            val tmp = File(dir, "tmp_${System.nanoTime()}")
            activity.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tmp).use { output -> input.copyTo(output) }
            } ?: return null
            if (tmp.length() == 0L) {
                tmp.delete(); return null
            }

            val digest = MessageDigest.getInstance("MD5").digest(tmp.readBytes())
            val id = ID_PREFIX + digest.copyOfRange(0, 4)
                .joinToString("") { "%02x".format(it) }
            val ext = name.substringAfterLast('.', "").lowercase()
                .filter { it.isLetterOrDigit() }.take(5)
            val target = File(dir, if (ext.isNotEmpty()) "$id.$ext" else id)
            if (target.exists()) {
                tmp.delete()
            } else if (!tmp.renameTo(target)) {
                tmp.delete(); return null
            }

            val durationMs = durationOf(target.absolutePath)
            if (durationMs <= 0) {
                target.delete(); return null // 读不出时长 = 解不了码，拒收
            }
            mapOf(
                "ok" to true,
                "path" to target.absolutePath,
                "name" to name,
                "durationMs" to durationMs,
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun displayNameOf(uri: Uri): String? {
        val cursor = try {
            activity.contentResolver.query(uri, null, null, null, null)
        } catch (e: Exception) {
            null
        } ?: return null
        return cursor.use { c ->
            val index = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && c.moveToFirst()) c.getString(index) else null
        }
    }

    private fun durationOf(path: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val ms = retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_DURATION
            )?.toLongOrNull() ?: 0L
            ms.toInt()
        } catch (e: Exception) {
            0
        } finally {
            runCatching { retriever.release() }
        }
    }

    // ------------------------------------------------------------------ 波形

    /**
     * 解码整条音频 → 按时间桶取样本绝对值峰值 → 归一化到 0..1。
     *
     * 实现取舍：不做重采样，直接按输出缓冲的时间戳落桶（每缓冲 10~20ms，
     * 对 24~400 桶的波形精度绰绰有余）；多声道取首声道（波形只是可视化，
     * 不保真）；解码失败/无音轨返回空列表（Dart 侧退化为纯进度轴）。
     */
    private fun extractWaveform(path: String, bars: Int): List<Double> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var trackIndex = -1
            var format: MediaFormat? = null
            var mime: String? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME)
                if (m != null && m.startsWith("audio/")) {
                    trackIndex = i; format = f; mime = m; break
                }
            }
            if (trackIndex < 0 || format == null || mime == null) return emptyList()
            val durationUs = runCatching {
                format.getLong(MediaFormat.KEY_DURATION)
            }.getOrDefault(0L)
            if (durationUs <= 0) return emptyList()

            extractor.selectTrack(trackIndex)
            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val peaks = DoubleArray(bars)
            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var maxPeak = 0.0

            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(
                                inIndex, 0, size, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                if (outIndex >= 0) {
                    val pcm = codec.getOutputBuffer(outIndex)!!
                    pcm.order(java.nio.ByteOrder.LITTLE_ENDIAN)
                        .asShortBuffer().let { shorts ->
                            // ShortBuffer 内逐样本取绝对值峰值（首声道步进 1）
                            var peak = 0.0
                            for (i in 0 until shorts.remaining()) {
                                val v = Math.abs(shorts.get(i).toInt())
                                if (v > peak) peak = v.toDouble()
                            }
                            val bucket = ((bufferInfo.presentationTimeUs *
                                bars) / durationUs).toInt()
                                .coerceIn(0, bars - 1)
                            if (peak > peaks[bucket]) peaks[bucket] = peak
                            if (peak > maxPeak) maxPeak = peak
                        }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            if (maxPeak <= 0.0) return emptyList()
            // 峰值归一 + 轻微下限（全静音段不至于画成零高度的空轴）
            return List(bars) { i ->
                val v = peaks[i] / maxPeak
                if (v < 0.04) 0.04 else v
            }
        } catch (e: Exception) {
            return emptyList()
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor.release() }
        }
    }
}
