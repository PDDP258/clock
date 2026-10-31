package com.aiclock.ai_clock

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 歌词目录通道 `aiclock/lyrics`（2026-10-06）。
 *
 * 背景：.lrc 原方案限定应用专属外存 `Android/data/<pkg>/files/lyrics/`，
 * 免权限但新安卓（11+）的文件管理器写不进 Android/data，用户放文件
 * 极难——真机反馈「歌词一直只有歌名」。联网核定的标准解法 = SAF
 * （Storage Access Framework）：用户用系统目录选择器把歌词文件夹授给
 * 本应用一次，takePersistableUriPermission 永久持有，之后零权限递归
 * 读全部 .lrc。Android 5.0+ 全版本通用，无需任何存储权限。
 *
 * 三个方法：
 * - `pickLyricDir`：弹 ACTION_OPEN_DOCUMENT_TREE 选目录，持久授权并
 *   记住 tree uri（原生 SharedPreferences），返回 uri 字符串（取消返回 ""）；
 * - `listLrc`：递归遍历授权目录树，返回全部 .lrc 的 {name, uri}；
 * - `readLrc`：按 uri 读文件字节回 Dart（ByteArray 传输，编码在 Dart
 *   侧按 UTF-8 → GBK → 容错 UTF-8 三级解码，原生不沾字符集）。
 *
 * 与应用专属目录并行存在（Dart 侧先查专属目录再查 SAF），
 * 老用户已放进 files/lyrics/ 的歌词不受影响。
 */
class LyricsPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "aiclock/lyrics"

        private const val REQ_PICK_DIR = 4713

        /// 记住已授权歌词目录的偏好文件名（原生私有，仅本插件读）
        private const val PREFS = "lyrics_plugin"
        private const val KEY_TREE = "tree_uri"
    }

    /// 选目录是异步的：`pickLyricDir` 把 result 存这里，等 onActivityResult 回填
    private var pendingPick: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickLyricDir" -> pickDir(result)
            "listLrc" -> result.success(listLrc())
            "readLrc" -> {
                val uri = call.argument<String>("uri")
                result.success(readLrc(uri))
            }
            "clearDir" -> {
                prefs().edit().remove(KEY_TREE).apply()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------ 选目录

    private fun pickDir(result: MethodChannel.Result) {
        pendingPick?.success("")
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQ_PICK_DIR)
        } catch (e: Exception) {
            pendingPick = null
            result.success("")
        }
    }

    /**
     * Activity 回调转发（MainActivity 里无条件调用本方法）。
     * 返回 true 表示这次结果被本插件消费了。
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK_DIR) return false
        val result = pendingPick ?: return false
        pendingPick = null

        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success("")
            return true
        }
        // 持久授权：应用重启后无需再选。个别 ROM 不支持持久化时
        // 退化为本次进程内有效（takePersistableUriPermission 抛异常不影响返回）
        runCatching {
            activity.contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        prefs().edit().putString(KEY_TREE, tree.toString()).apply()
        result.success(tree.toString())
        return true
    }

    private fun prefs() =
        activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)

    // ------------------------------------------------------------ 遍历 / 读取

    /// 已授权目录树（未选过返回 null）
    private fun treeUri(): Uri? {
        val raw = prefs().getString(KEY_TREE, null) ?: return null
        return runCatching { Uri.parse(raw) }.getOrNull()
    }

    /**
     * 递归收集目录树下全部 .lrc（不区分大小写），返回
     * [{name: 显示名, uri: 文档 uri}, …]。遍历失败/未授权返回空列表。
     */
    private fun listLrc(): List<Map<String, String>> {
        val root = treeUri() ?: return emptyList()
        val out = mutableListOf<Map<String, String>>()
        runCatching { walk(root, out) }
        return out
    }

    private fun walk(tree: Uri, out: MutableList<Map<String, String>>) {
        val docId = DocumentsContract.getTreeDocumentId(tree)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
        val cursor = activity.contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null, null, null
        ) ?: return
        cursor.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0) ?: continue
                val name = c.getString(1) ?: continue
                val mime = c.getString(2) ?: continue
                val docUri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    walk(docUri, out)
                } else if (name.endsWith(".lrc", ignoreCase = true)) {
                    out.add(mapOf("name" to name, "uri" to docUri.toString()))
                }
            }
        }
    }

    /// 读文件字节；任何失败（权限失效/文件被移走）返回 null
    private fun readLrc(uri: String?): ByteArray? {
        if (uri.isNullOrEmpty()) return null
        return runCatching {
            activity.contentResolver.openInputStream(Uri.parse(uri))?.use {
                it.readBytes()
            }
        }.getOrNull()
    }
}
