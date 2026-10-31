package com.aiclock.ai_clock

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/**
 * 背景图入库通道 `aiclock/backgrounds`（看板 #55/#61）。
 *
 * 为什么必须走原生：**入库要重编码**。Dart 侧只能编码 PNG，一张
 * 2480×3508 的图转出来是十几 MB，而目标是几百 KB 的 WebP；原生
 * `BitmapFactory` + `Bitmap.compress(WEBP)` 是唯一又快又小的路，
 * 且与既有 `aiclock/permissions` / `aiclock/audio` 同一风格（零新依赖）。
 *
 * 职责切分：**策略留 Dart，原生只当执行器**
 * - `pickImages` 只负责「选图（相册/文件管理器）+ 报出原始像素尺寸」；
 * - 目标尺寸由 Dart 用 [bgTargetSize] 算（与预处理脚本、判定规则同源，可单测）；
 * - `processImages` 照 Dart 给的 outWidth/outHeight 解码→旋转→缩放→编码→落盘。
 *
 * 选图来源（2026-10-05 用户需求，看板 #61）：
 * - `gallery`：`ACTION_PICK` + `MediaStore`——走系统相册，权限由相册
 *   稳定授予，**默认入口**；
 * - `files`：`ACTION_OPEN_DOCUMENT`——能进任意目录。
 *
 * 两个血泪细节：
 * - **不能包 `createChooser`**：chooser 转发会让部分文件管理器返回的
 *   URI 带不上读权限，探测直接 SecurityException——用户明明选了图，
 *   Dart 却收到空列表显示「没有选到图片」（#61 的根因）。两个 intent
 *   都必须直接 `startActivityForResult`。
 * - **探测失败要回报，不许静默丢**：Dart 靠「picked 但 width=0」区分
 *   「没选」和「选了但读不出来」，提示语完全不同。
 * - **EXIF 旋转**：相机拍的竖图像素是横着的、靠 EXIF 告诉看图软件转 90°。
 *   `BitmapFactory` 不看 EXIF，不处理就是躺着的背景。故探测阶段就按 EXIF
 *   把宽高**交换后上报**，这样 Dart 算的规则/目标尺寸与最终成图一致。
 * - **内容哈希去重**：落盘文件名 `u_<MD5(输出字节) 前 8 位>.webp`，
 *   同一张图反复导入只会有一份；MD5 算的是压缩后的小文件，开销可忽略。
 */
class BackgroundImportPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "aiclock/backgrounds"

        /// 用户图库目录名（与 Dart `kBgUserImageDirName` 一致）
        private const val DIR_NAME = "backgrounds"

        /// 用户图片 id 前缀（与 Dart `kBgUserIdPrefix` 一致）
        private const val ID_PREFIX = "u_"

        /// WebP 质量：背景只做氛围层（40%/30% 不透明度），82 足够
        private const val WEBP_QUALITY = 82

        /// 透明像素压到的底色：本 App 常驻深色主题，黑底最不显边
        private const val FLATTEN_COLOR = Color.BLACK

        private const val REQ_PICK = 4711
    }

    /// 选图是异步的：`pickImages` 把 result 存这里，等 `onActivityResult` 回填
    private var pendingPick: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickImages" -> pickImages(call.argument<String>("source"), result)
            "processImages" -> {
                @Suppress("UNCHECKED_CAST")
                val items = call.argument<List<Any>>("items") ?: emptyList()
                result.success(items.map { processOne(it) })
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------ 选图

    private fun pickImages(source: String?, result: MethodChannel.Result) {
        // 上一次还没回填（连点）：先把旧的用空结果收掉，避免 result 泄漏
        pendingPick?.success(emptyList<Any>())
        pendingPick = result
        val intent: Intent = if (source == "gallery") {
            // 相册：ACTION_PICK 天然带读权限，探测不会因权限翻车
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        } else {
            // 文件管理器：文档树任意目录。注意不能包 chooser（类注释）
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            activity.startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            // 没有可用选图器的 ROM（极罕见）：静默返回空列表，Dart 提示未选到
            pendingPick = null
            result.success(emptyList<Any>())
        }
    }

    /**
     * Activity 回调转发（MainActivity 里无条件调用本方法）。
     * 返回 true 表示这次结果被本插件消费了。
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val result = pendingPick ?: return false
        pendingPick = null

        val out = mutableListOf<Map<String, Any?>>()
        if (resultCode == Activity.RESULT_OK && data != null) {
            for (uri in collectUris(data)) {
                // 相册 URI 无持久授权这回事；文档 URI 立刻消费也不需要。
                // 这里只在「能持久化」时做，失败不影响本次导入
                runCatching {
                    activity.contentResolver.takePersistableUriPermission(
                        uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                }
                out.add(probeUri(uri))
            }
        }
        result.success(out)
        return true
    }

    private fun collectUris(data: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        return uris
    }

    // ------------------------------------------------------------------ 探测

    /// 三元组：原始宽、原始高、EXIF 旋转角（0/90/180/270）
    private data class Probe(val width: Int, val height: Int, val rotation: Int)

    /**
     * 探测一张候选图。**永不返回 null**：读不出尺寸就报 width=0，
     * 让 Dart 能说「这 N 张读不出来」而不是误导性的「没有选到图片」。
     */
    private fun probeUri(uri: Uri): Map<String, Any?> {
        val probe = probeOf(uri)
        val name = displayNameOf(uri) ?: ""
        val (w, h) = probe?.let { orientedSize(it) } ?: (0 to 0)
        return mapOf(
            "value" to uri.toString(),
            "name" to name,
            "width" to w,
            "height" to h,
        )
    }

    /** 读尺寸：先走文件描述符，失败（个别 provider 不给 fd）退回流。 */
    private fun probeOf(uri: Uri): Probe? {
        val viaFd = try {
            activity.contentResolver.openFileDescriptor(uri, "r")?.use { readProbe(it) }
        } catch (e: Exception) {
            null
        }
        if (viaFd != null) return viaFd
        return probeViaStream(uri)
    }

    /// 流兜底：`ExifInterface(InputStream)` 需 API 24；bounds 解码再开一条流
    private fun probeViaStream(uri: Uri): Probe? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        val rotation = try {
            activity.contentResolver.openInputStream(uri)?.use { exifRotationOf(it) }
                ?: return null
        } catch (e: Exception) {
            return null
        }
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        return try {
            activity.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            }
            if (opts.outWidth <= 0 || opts.outHeight <= 0) null
            else Probe(opts.outWidth, opts.outHeight, rotation)
        } catch (e: Exception) {
            null
        }
    }

    private fun readProbe(pfd: ParcelFileDescriptor): Probe? {
        val rotation = try {
            exifRotationOf(pfd.fileDescriptor)
        } catch (e: Exception) {
            0
        }
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor, null, opts)
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null
        return Probe(opts.outWidth, opts.outHeight, rotation)
    }

    private fun exifRotationOf(fd: java.io.FileDescriptor): Int =
        exifRotationOf(android.media.ExifInterface(fd))

    private fun exifRotationOf(stream: java.io.InputStream): Int =
        exifRotationOf(android.media.ExifInterface(stream))

    private fun exifRotationOf(exif: android.media.ExifInterface): Int =
        when (exif.getAttributeInt(
            android.media.ExifInterface.TAG_ORIENTATION,
            android.media.ExifInterface.ORIENTATION_NORMAL
        )) {
            android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90
            android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180
            android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }

    /// 旋转 90/270 会让「看图时长宽互换」——探测上报就必须用互换后的值
    private fun orientedSize(probe: Probe): Pair<Int, Int> =
        if (probe.rotation == 90 || probe.rotation == 270) {
            probe.height to probe.width
        } else {
            probe.width to probe.height
        }

    private fun displayNameOf(uri: Uri): String? {
        val cursor = try {
            activity.contentResolver.query(uri, null, null, null, null)
        } catch (e: Exception) {
            null
        } ?: return null
        return cursor.use { c ->
            val index = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && c.moveToFirst()) c.getString(index) else null
        }
    }

    // ------------------------------------------------------------------ 入库

    private fun processOne(raw: Any?): Map<String, Any?> {
        val item = raw as? Map<*, *> ?: return failed("")
        val value = item["value"] as? String
        val name = item["name"] as? String ?: ""
        val outW = (item["outWidth"] as? Number)?.toInt() ?: return failed(name)
        val outH = (item["outHeight"] as? Number)?.toInt() ?: return failed(name)
        if (value.isNullOrEmpty() || outW <= 0 || outH <= 0) return failed(name)

        val dir = File(activity.getExternalFilesDir(null), DIR_NAME)
        if (!dir.exists() && !dir.mkdirs()) return failed(name)

        return try {
            val uri = Uri.parse(value)
            val probe = probeOf(uri) ?: return failed(name)
            val bitmap = decodeScaled(uri, probe, outW, outH) ?: return failed(name)
            val flat = flatten(bitmap, outW, outH)
            if (flat !== bitmap) bitmap.recycle()
            val file = writeWebp(dir, flat)
            flat.recycle()
            mapOf(
                "ok" to true,
                "path" to file.absolutePath,
                "name" to name,
                "width" to outW,
                "height" to outH,
                // 原始尺寸（EXIF 旋转前）：登记表与设置页展示用，
                // 判定一律以上面旋转后的 width/height 为准
                "srcWidth" to probe.width,
                "srcHeight" to probe.height,
                "bytes" to file.length().toInt(),
            )
        } catch (e: Exception) {
            // 单张失败只丢这一张：批量导入里不该让一张坏图拖垮整批
            failed(name)
        }
    }

    /**
     * 采样解码 + 精确缩放。
     *
     * 先按 `inSampleSize` 粗降（省内存），再 `createScaledBitmap` 精缩到
     * Dart 指定的目标；旋转在缩放前做，保证长宽比与目标一致。
     * fd 读不了时退回流解码（与探测同一条兜底链）。
     */
    private fun decodeScaled(uri: Uri, probe: Probe, outW: Int, outH: Int): Bitmap? {
        val opts = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sampleSizeFor(probe.width, probe.height, outW, outH)
        }
        val decoded = try {
            activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor, null, opts)
            }
        } catch (e: Exception) {
            null
        } ?: try {
            activity.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, opts)
            }
        } catch (e: Exception) {
            null
        } ?: return null

        val rotated = if (probe.rotation == 0) {
            decoded
        } else {
            val matrix = Matrix().apply { postRotate(probe.rotation.toFloat()) }
            val spun = Bitmap.createBitmap(
                decoded, 0, 0, decoded.width, decoded.height, matrix, true
            )
            if (spun !== decoded) decoded.recycle()
            spun
        }
        val scaled = Bitmap.createScaledBitmap(rotated, outW, outH, true)
        if (scaled !== rotated) rotated.recycle()
        return scaled
    }

    /// 采样倍率：解码结果略大于目标即可（缩比放大更清晰），最小 1
    private fun sampleSizeFor(srcW: Int, srcH: Int, outW: Int, outH: Int): Int {
        if (srcW <= 0 || srcH <= 0 || outW <= 0 || outH <= 0) return 1
        val byWidth = srcW / outW
        val byHeight = srcH / outH
        return maxOf(1, minOf(byWidth, byHeight))
    }

    /// 压平到不透明底：WebP 有损不带 alpha 通道，透明区会变脏色
    private fun flatten(source: Bitmap, outW: Int, outH: Int): Bitmap {
        if (!source.hasAlpha()) return source
        val flat = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(flat)
        canvas.drawColor(FLATTEN_COLOR)
        canvas.drawBitmap(source, 0f, 0f, null)
        return flat
    }

    /**
     * 编码落盘，文件名取输出字节的 MD5 前 8 位（内容级去重）。
     * 已存在同名文件说明这张图入库过——直接复用，不覆盖不重复占空间。
     */
    private fun writeWebp(dir: File, bitmap: Bitmap): File {
        val tmp = File(dir, "tmp_${System.nanoTime()}.webp")
        FileOutputStream(tmp).use {
            bitmap.compress(Bitmap.CompressFormat.WEBP, WEBP_QUALITY, it)
        }
        val digest = MessageDigest.getInstance("MD5").digest(tmp.readBytes())
        val id = ID_PREFIX + digest.copyOfRange(0, 4)
            .joinToString("") { "%02x".format(it) }
        val target = File(dir, "$id.webp")
        if (target.exists()) {
            tmp.delete()
        } else if (!tmp.renameTo(target)) {
            tmp.delete()
            throw IllegalStateException("rename failed")
        }
        return target
    }

    private fun failed(name: String): Map<String, Any?> = mapOf(
        "ok" to false,
        "path" to "",
        "name" to name,
        "width" to 0,
        "height" to 0,
        "bytes" to 0,
    )
}
