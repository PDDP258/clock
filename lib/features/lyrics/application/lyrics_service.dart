/// 歌词文件（.lrc）解析、匹配与自定义字体（竖屏歌词区，2026-10-05/06）。
///
/// 数据源为应用专属外存 `files/lyrics/`（免权限，文件管理器可直接放入）：
/// 按「歌名-歌手.lrc」「歌名.lrc」候选名匹配当前播放曲目，匹配不到则
/// 歌词区退化为只显示「歌名 — 歌手」。匹配做归一化（忽略大小写/空白/
/// 常见标点），解析容忍 BOM、CRLF、一行多时间戳与 [hh:mm:ss] 格式。
///
/// 自定义歌词字体：把 `.ttf`/`.otf` 放入 `files/lyrics/fonts/` 即全局生效
///（取目录下第一个字体文件，经 [FontLoader] 注册为 `LyricFont`）；
/// 未放置时用系统默认字体。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart'
    show FontLoader, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../platform/prefs/prefs_provider.dart';

/// 一行歌词。
class LrcLine {
  const LrcLine({required this.at, required this.text});

  /// 起始时间戳。
  final Duration at;

  /// 歌词文本。
  final String text;
}

/// `[mm:ss.xx]` / `[mm:ss]` 时间戳。
final _mmssRe = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]');

/// `[hh:mm:ss.xx]` / `[hh:mm:ss]` 时间戳（少数歌词用完整时分秒）。
final _hhmmsRe =
    RegExp(r'\[(\d{1,2}):(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]');

int _fracMs(String? frac) {
  if (frac == null || frac.isEmpty) return 0;
  // 小数部分右对齐到毫秒三位：.5 → 500、.05 → 050、.005 → 005
  return int.parse('${frac}000'.substring(0, 3));
}

/// 歌词文本解码：网络下载的 .lrc 常见三种编码——严格 UTF-8 → GBK →
/// 容错 UTF-8（替换非法字节）。严格 UTF-8 一失败就整体返回 null 是
/// 「歌词只显示歌名」的历史根因之一（GBK 文件全部静默失败）。
String _decodeLrcBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on Object {
    // fall through
  }
  try {
    return gbk.decode(bytes);
  } on Object {
    // fall through
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// 解析 .lrc 文本为按时间排序的行列表。
///
/// 容忍：UTF-8 BOM、CR/LF 混用、一行挂多个时间戳（同一文本多行复用）、
/// 空文本间奏行（丢弃）、hh:mm:ss 完整格式。无时间戳行全部丢弃。
List<LrcLine> parseLrc(String content) {
  final cleaned = content.replaceAll('﻿', '');
  final lines = <LrcLine>[];
  for (final raw in cleaned.split(RegExp(r'\r\n|\r|\n'))) {
    final stamps = <Duration>[];
    for (final m in _hhmmsRe.allMatches(raw)) {
      stamps.add(Duration(
        hours: int.parse(m.group(1)!),
        minutes: int.parse(m.group(2)!),
        seconds: int.parse(m.group(3)!),
        milliseconds: _fracMs(m.group(4)),
      ));
    }
    if (stamps.isEmpty) {
      for (final m in _mmssRe.allMatches(raw)) {
        stamps.add(Duration(
          minutes: int.parse(m.group(1)!),
          seconds: int.parse(m.group(2)!),
          milliseconds: _fracMs(m.group(3)),
        ));
      }
    }
    if (stamps.isEmpty) continue;
    // 去掉全部时间戳标签，剩下的才是歌词文本
    final text = raw.replaceAll(_hhmmsRe, '').replaceAll(_mmssRe, '').trim();
    if (text.isEmpty) continue; // 纯音乐间奏行不展示
    for (final at in stamps) {
      lines.add(LrcLine(at: at, text: text));
    }
  }
  lines.sort((a, b) => a.at.compareTo(b.at));
  return lines;
}

/// 按播放位置取当前行（最后一条 at <= position 的歌词）；
/// 无匹配（位置在首行之前）返回 null。
LrcLine? lrcLineAt(List<LrcLine> lines, Duration position) {
  LrcLine? current;
  for (final line in lines) {
    if (line.at <= position) {
      current = line;
    } else {
      break;
    }
  }
  return current;
}

/// 歌词目录（应用专属外存 `files/lyrics/`）。
Future<Directory> lyricsDirectory() async {
  final base = await getExternalStorageDirectory();
  return Directory(p.join(base!.path, 'lyrics'));
}

/// 自定义歌词字体目录（`files/lyrics/fonts/`，放 .ttf/.otf）。
Future<Directory> lyricFontDirectory() async {
  final base = await getExternalStorageDirectory();
  return Directory(p.join(base!.path, 'lyrics', 'fonts'));
}

/// 文件名归一化：小写 + 去掉空白与常见标点（匹配用，不用于真实文件名）。
String _normalizeName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\-_·.,，。:：!！?？&＆+＋()（）\[\]【】]'), '');

/// 文件名净化：去掉路径非法字符（Windows/Android 共同子集），限长。
String _sanitizeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
  return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
}

bool _isFontFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext == '.ttf' || ext == '.otf';
}

/// 匹配分：越大越像；0 = 不沾边。
int _matchScore(String stem, String wantTitle, String wantFull) {
  if (stem.isEmpty || wantTitle.isEmpty) return 0;
  if (wantFull.isNotEmpty && stem == wantFull) return 5;
  if (stem == wantTitle) return 4;
  // 歌名包含在文件名里：「歌名 (Live)」← 「歌名.lrc」
  if (wantTitle.length >= 4 && stem.contains(wantTitle)) return 3;
  // 文件名包含在歌名里：「歌名」← 「歌名 - 专辑版.lrc」
  if (stem.length >= 4 && wantTitle.contains(stem)) return 2;
  // 退化方向兜底：文件名是歌名的前缀/后缀片（≥3 字，如「歌名Live」）
  if (wantTitle.length >= 3 && stem.length >= 3) {
    final common = _longestCommon(wantTitle, stem);
    if (common >= 3 && common >= wantTitle.length * 0.6) return 1;
  }
  return 0;
}

/// 最长公共子串长度（简单 O(n·m)，文件名几十个、歌名几十字，足够快）。
int _longestCommon(String a, String b) {
  var best = 0;
  final prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    for (var j = b.length; j >= 1; j--) {
      prev[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : 0;
      if (prev[j] > best) best = prev[j];
    }
  }
  return best;
}

/// 在文件名干列表里找最高分者（[_matchScore]），返回下标；全 0 返回 null。
int? _bestMatchIndex(List<String> stems, String wantTitle, String wantFull) {
  var bestIndex = -1;
  var bestScore = 0;
  for (var i = 0; i < stems.length; i++) {
    final score = _matchScore(stems[i], wantTitle, wantFull);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }
  return bestIndex < 0 ? null : bestIndex;
}

/// 加载指定曲目的 .lrc；未找到/读失败返回 null（歌词区退化显示歌名）。
///
/// 四轮查找：①应用专属目录精确候选名（保留原始大小写/标点）；
/// ②把媒体会话「歌名 - 歌手」连体标题拆开重试；③专属目录归一化
/// 模糊匹配；④SAF 授权目录（系统目录选择器授予，新安卓免 Android/data
/// 写入难题）同规则匹配，按文档 uri 读字节。①–③ 均为零权限，
/// ④ 依赖用户先在设置页选过歌词目录。
Future<List<LrcLine>?> loadLrcFor(String title, String artist) async {
  try {
    final dir = await lyricsDirectory();
    final wantTitle = _normalizeName(title);
    final wantFull =
        artist.isEmpty ? wantTitle : _normalizeName('$title-$artist');

    Future<List<LrcLine>?> tryExact(String t, String a) async {
      final ts = _sanitizeFileName(t);
      if (ts.isEmpty) return null;
      final as = _sanitizeFileName(a);
      final candidates = <String>[
        if (as.isNotEmpty) '$ts-$as.lrc',
        '$ts.lrc',
        if (as.isNotEmpty) '$as-$ts.lrc',
      ];
      if (!dir.existsSync()) return null;
      for (final name in candidates) {
        final file = File(p.join(dir.path, name));
        if (file.existsSync()) {
          return parseLrc(_decodeLrcBytes(await file.readAsBytes()));
        }
      }
      return null;
    }

    // 第 ①② 轮：原样 + 「歌名 - 歌手」连体拆开
    final exact = await tryExact(title, artist);
    if (exact != null) return exact;
    if (artist.isEmpty) {
      final m = RegExp(r'^(.*?)\s+[-–—~]\s+(.*)$').firstMatch(title);
      if (m != null) {
        final split = await tryExact(m.group(1)!, m.group(2)!);
        if (split != null) return split;
      }
    }
    if (wantTitle.isEmpty) return null;

    // 第 ③ 轮：专属目录归一化模糊匹配，取分最高者
    if (dir.existsSync()) {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.lrc'))
          .toList();
      final idx = _bestMatchIndex(
        files.map((f) => _normalizeName(p.basenameWithoutExtension(f.path))).toList(),
        wantTitle,
        wantFull,
      );
      if (idx != null) {
        return parseLrc(
            _decodeLrcBytes(await files[idx].readAsBytes()));
      }
    }

    // 第 ④ 轮：SAF 授权歌词目录（displayName 同规则匹配，读字节回 Dart）
    final saf = await _safLrcIndex();
    if (saf.isNotEmpty) {
      final idx = _bestMatchIndex(
        saf.map((e) => _normalizeName(e['name'] ?? '')).toList(),
        wantTitle,
        wantFull,
      );
      if (idx != null) {
        final bytes = await _readSafLrc(saf[idx]['uri'] ?? '');
        if (bytes != null && bytes.isNotEmpty) {
          return parseLrc(_decodeLrcBytes(bytes));
        }
      }
    }

    // 第 ⑤ 轮：在线歌词（开关持久化）。优先网易云（国内直达），
    // 失败回退 LRCLIB 公开歌词库（境外服务，国内可能超时）。用户
    // 不自备 .lrc 的常态路径：按歌名/歌手自动匹配逐行歌词并缓存。
    final onlineOn =
        (await SharedPreferences.getInstance()).getBool(kLyricOnlineKey) ?? true;
    if (onlineOn) {
      final online = await fetchNetEaseLrc(title, artist);
      if (online != null) return online;
      final lrclib = await fetchOnlineLrc(title, artist);
      if (lrclib != null) return lrclib;
    }
    return null;
  } on Object {
    return null;
  }
}

/// 按 (歌名, 歌手) 取该曲的歌词行列表；null = 无匹配歌词文件。
final lrcProvider =
    FutureProvider.family<List<LrcLine>?, (String, String)>((ref, key) =>
        loadLrcFor(key.$1, key.$2));

// ------------------------------------------------------------------ SAF 歌词目录

/// 与原生 LyricsPlugin 约定的通道（aiclock/lyrics）。
const MethodChannel _lyricsChannel = MethodChannel('aiclock/lyrics');

/// SAF 侧 .lrc 索引缓存（displayName + 文档 uri）。选目录后/手动刷新时清空。
List<Map<String, String>>? _safLrcCache;

/// 弹出系统目录选择器，把歌词文件夹永久授权给本应用。
/// 返回选中的 tree uri（取消/失败返回 null）。
Future<String?> pickLyricDir() async {
  try {
    final uri = await _lyricsChannel.invokeMethod<String>('pickLyricDir');
    _safLrcCache = null;
    if (uri == null || uri.isEmpty) return null;
    return uri;
  } on Object {
    return null;
  }
}

/// 已授权歌词目录的索引（带缓存）；未选过/遍历失败返回空列表。
Future<List<Map<String, String>>> _safLrcIndex() async {
  final cached = _safLrcCache;
  if (cached != null) return cached;
  try {
    final raw = await _lyricsChannel
        .invokeMethod<List<dynamic>>('listLrc');
    final list = (raw ?? const [])
        .map((e) => (e as Map).map(
            (k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
        .toList();
    _safLrcCache = list;
    return list;
  } on Object {
    return const [];
  }
}

/// 按文档 uri 读歌词字节（SAF 授权范围内，零权限）。
Future<Uint8List?> _readSafLrc(String uri) async {
  try {
    final bytes = await _lyricsChannel
        .invokeMethod<Uint8List>('readLrc', {'uri': uri});
    return bytes;
  } on Object {
    return null;
  }
}

/// 歌词来源状态（设置页展示）：应用专属目录路径 + SAF 目录 uri + .lrc 数。
final lyricDirStatusProvider = FutureProvider<LyricDirStatus>((ref) async {
  final appDir = (await lyricsDirectory()).path;
  final index = await _safLrcIndex();
  return LyricDirStatus(
    appDir: appDir,
    safTree: index.isNotEmpty ? '已授权（${index.length} 个 .lrc）' : null,
  );
});

/// 刷新歌词索引（设置页「重新扫描」用）。
void refreshLyricIndex() {
  _safLrcCache = null;
}

// ------------------------------------------------------------------ 在线歌词（LRCLIB）

/// 在线获取歌词开关（默认开）：从 LRCLIB 公开歌词库自动下载逐行歌词。
final lyricOnlineEnabledProvider =
    StateNotifierProvider<LyricOnlineNotifier, bool>(
        (ref) => LyricOnlineNotifier(ref.watch(sharedPreferencesProvider)));

/// 持久化键（loadLrcFor 里也要读，导出共用）。
const kLyricOnlineKey = 'lyric_online_enabled';

/// 在线歌词开关的读写与持久化。
class LyricOnlineNotifier extends StateNotifier<bool> {
  LyricOnlineNotifier(this._prefs) : super(_prefs.getBool(kLyricOnlineKey) ?? true);

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _prefs.setBool(kLyricOnlineKey, value);
  }
}

/// LRCLIB 公开歌词库（https://lrclib.net/docs）：免注册、无 key、支持
/// 逐行（LRC 时间轴）歌词——用户不需要自备 .lrc，按歌名+歌手自动匹配。
const _lrclibBase = 'lrclib.net';

/// 识别用 User-Agent（LRCLIB 官方建议带上应用名）。
const _lrclibUa = 'AI_clock pomodoro (local-focus-timer)';

/// 浏览器级 UA：网易云反爬只认浏览器（自定义 UA 会被判为爬虫）。
const _browserUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

/// 网易云音乐公开接口（第三方常用、无需登录）：先 search 拿 song id，
/// 再按 id 拉 LRC 逐行歌词。国内网络直达，作为 LRCLIB（境外服务，
/// 国内可能超时）之前的优先在线源。
const _neteaseBase = 'music.163.com';

/// 在线拉取网易云逐行歌词：search（歌名+歌手）→ 候选打分取最优 id
/// → lyric 接口取 lrc 文本 → 解析 + 缓存进应用专属目录。失败返回 null。
Future<List<LrcLine>?> fetchNetEaseLrc(String title, String artist) async {
  final t = title.trim();
  if (t.isEmpty) return null;
  final kw = artist.trim().isEmpty ? t : '$t ${artist.trim()}';

  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 6);

    Future<Map<String, dynamic>?> getJson(
        String path, Map<String, String> query) async {
      final req =
          await client!.getUrl(Uri.https(_neteaseBase, path, query));
      // 网易反爬：必须浏览器级 UA（自定义 UA 会被识别为爬虫拒服），
      // 加 Referer 与 X-Real-IP 规避 -460「Cheating」（2026-10-06 检索结论）
      req.headers.set(HttpHeaders.userAgentHeader, _browserUa);
      req.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
      req.headers.set('X-Real-IP', '211.161.244.70');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    }

    // 第 1 步：搜索（type=1 单曲）
    final search = await getJson('/api/search/get',
        {'s': kw, 'type': '1', 'limit': '8'});
    final songs = (search?['result'] as Map?)?['songs'];
    if (songs is! List || songs.isEmpty) return null;

    // 候选打分：歌名归一化相等/包含 + 歌手相符
    int scoreOf(Map<String, dynamic> r) {
      final rt = _normalizeName((r['name'] as String?) ?? '');
      final artists = (r['artists'] as List?) ?? const [];
      final ra = artists.isEmpty
          ? ''
          : _normalizeName(
              ((artists.first as Map?)?['name'] as String?) ?? '');
      final want = _normalizeName(t);
      var score = 0;
      if (rt == want) score += 40;
      if (rt.length >= 4 && rt.contains(want)) score += 20;
      if (want.length >= 4 && want.contains(rt) && rt.isNotEmpty) score += 15;
      if (artist.trim().isNotEmpty && ra == _normalizeName(artist)) {
        score += 10;
      }
      return score;
    }

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final s in songs) {
      if (s is Map<String, dynamic>) {
        final sc = scoreOf(s);
        if (sc > bestScore) {
          bestScore = sc;
          best = s;
        }
      }
    }
    final id = best?['id'];
    if (best == null || bestScore <= 0 || id == null) return null;

    // 第 2 步：按 id 取 LRC（lv=-1 原文+时间轴）
    final lyricJson = await getJson(
        '/api/song/lyric', {'os': 'pc', 'id': '$id', 'lv': '-1', 'kv': '-1', 'tv': '-1'});
    final lrcText =
        ((lyricJson?['lrc'] as Map?)?['lyric']) as String?;
    if (lrcText == null || lrcText.trim().isEmpty) return null;

    // 缓存落盘（应用专属目录）：文件名 = 净化后的「歌名-歌手.lrc」
    try {
      final dir = await lyricsDirectory();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final cacheName = _sanitizeFileName(
          artist.trim().isEmpty ? '$t.lrc' : '$t-${artist.trim()}.lrc');
      File(p.join(dir.path, cacheName))
          .writeAsBytesSync(utf8.encode(lrcText));
    } on Object {
      // 缓存失败不影响本次展示
    }
    return parseLrc(lrcText);
  } on Object {
    return null;
  } finally {
    client?.close(force: true);
  }
}

/// 在线拉取逐行歌词：search 接口按 歌名/歌手 查 → 取同步歌词最优候选
/// → 解析 + 缓存进应用专属目录（下次离线可用）。任何失败返回 null，
/// 歌词区退化为「歌名 · 歌手」。
Future<List<LrcLine>?> fetchOnlineLrc(String title, String artist) async {
  final t = title.trim();
  if (t.isEmpty) return null;

  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final uri = Uri.https(_lrclibBase, '/api/search', {
      'track_name': t,
      if (artist.trim().isNotEmpty) 'artist_name': artist.trim(),
    });
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, _lrclibUa);
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = await utf8.decoder.bind(res).join();
    final records = jsonDecode(body);
    if (records is! List || records.isEmpty) return null;

    // 候选排序：归一化歌名完全相等 > 包含 > 其它；同步歌词优先；器乐减分
    int scoreOf(Map<String, dynamic> r) {
      final rt = _normalizeName((r['trackName'] as String?) ?? '');
      final ra = _normalizeName((r['artistName'] as String?) ?? '');
      final want = _normalizeName(t);
      var score = 0;
      if (rt == want) score += 40;
      if (rt.length >= 4 && rt.contains(want)) score += 20;
      if (want.length >= 4 && want.contains(rt) && rt.isNotEmpty) score += 15;
      if (artist.trim().isNotEmpty && ra == _normalizeName(artist)) {
        score += 10;
      }
      if (r['syncedLyrics'] is String &&
          (r['syncedLyrics'] as String).isNotEmpty) {
        score += 5;
      }
      if (r['instrumental'] == true) score -= 100;
      return score;
    }

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final r in records) {
      if (r is Map<String, dynamic>) {
        final sc = scoreOf(r);
        if (sc > bestScore) {
          bestScore = sc;
          best = r;
        }
      }
    }
    final synced = best?['syncedLyrics'];
    if (best == null || synced is! String || synced.isEmpty) return null;

    // 缓存落盘（应用专属目录）：文件名 = 净化后的「歌名-歌手.lrc」
    try {
      final dir = await lyricsDirectory();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final cacheName = _sanitizeFileName(
          artist.trim().isEmpty ? '$t.lrc' : '$t-${artist.trim()}.lrc');
      File(p.join(dir.path, cacheName)).writeAsBytesSync(utf8.encode(synced));
    } on Object {
      // 缓存失败不影响本次展示
    }
    return parseLrc(synced);
  } on Object {
    return null;
  } finally {
    client?.close(force: true);
  }
}

/// 歌词来源状态快照。
class LyricDirStatus {
  const LyricDirStatus({required this.appDir, this.safTree});

  /// 应用专属歌词目录绝对路径（files/lyrics）。
  final String appDir;

  /// SAF 已授权目录概览（null = 未选过）。
  final String? safTree;
}

/// 自定义歌词字体（可选）：持久化选中文件名（'' = 默认字体）。
final lyricFontChoiceProvider =
    StateNotifierProvider<LyricFontChoiceNotifier, String>(
        (ref) => LyricFontChoiceNotifier(ref.watch(sharedPreferencesProvider)));

/// 歌词字体选中的读写与持久化（存字体文件名，缺失/文件被删回退默认）。
class LyricFontChoiceNotifier extends StateNotifier<String> {
  LyricFontChoiceNotifier(this._prefs)
      : super(_prefs.getString(_kKey) ?? '');

  static const _kKey = 'lyric_font_file';
  final SharedPreferences _prefs;

  Future<void> set(String value) async {
    state = value;
    await _prefs.setString(_kKey, value);
  }
}

/// 歌词字号（逻辑像素，10–28，默认 15）。
final lyricFontSizeProvider =
    StateNotifierProvider<LyricFontSizeNotifier, double>(
        (ref) => LyricFontSizeNotifier(ref.watch(sharedPreferencesProvider)));

/// 歌词字号的读写与持久化。
class LyricFontSizeNotifier extends StateNotifier<double> {
  LyricFontSizeNotifier(this._prefs)
      : super((_prefs.getDouble(_kKey) ?? 15).clamp(10.0, 28.0));

  static const _kKey = 'lyric_font_size';
  final SharedPreferences _prefs;

  Future<void> set(double value) async {
    final v = value.clamp(10.0, 28.0);
    state = v;
    await _prefs.setDouble(_kKey, v);
  }
}

/// 歌词颜色（ARGB int，默认白 90%）。
final lyricColorProvider = StateNotifierProvider<LyricColorNotifier, int>(
    (ref) => LyricColorNotifier(ref.watch(sharedPreferencesProvider)));

/// 歌词颜色的读写与持久化。
class LyricColorNotifier extends StateNotifier<int> {
  LyricColorNotifier(this._prefs) : super(_prefs.getInt(_kKey) ?? 0xE6FFFFFF);

  static const _kKey = 'lyric_color';
  final SharedPreferences _prefs;

  Future<void> set(int argb) async {
    state = argb;
    await _prefs.setInt(_kKey, argb);
  }
}

/// 歌词颜色同步辉光管（2026-10-06）：true = 歌词颜色跟随计时阶段色
/// （辉光管什么颜色就什么颜色，变阶段即变）；false = 用 [lyricColorProvider]
/// 的自定义色。默认关。
final lyricFollowClockProvider =
    StateNotifierProvider<LyricFollowClockNotifier, bool>(
        (ref) => LyricFollowClockNotifier(ref.watch(sharedPreferencesProvider)));

/// 同步开关的读写与持久化。
class LyricFollowClockNotifier extends StateNotifier<bool> {
  LyricFollowClockNotifier(this._prefs)
      : super(_prefs.getBool(_kKey) ?? false);

  static const _kKey = 'lyric_follow_clock';
  final SharedPreferences _prefs;

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setBool(_kKey, value);
  }
}

/// 扫描 `files/lyrics/fonts/` 下的 .ttf/.otf（名称列表，供设置页选择）。
Future<List<String>> listLyricFonts() async {
  try {
    final dir = await lyricFontDirectory();
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => _isFontFile(f.path))
        .map((f) => p.basename(f.path))
        .toList()
      ..sort();
  } on Object {
    return const [];
  }
}

/// 当前生效的自定义歌词字体：按 [lyricFontChoiceProvider] 选中的文件名
/// 注册为 `LyricFont` 字体族；选中为空或文件不存在则注册第一个字体文件
/// （历史行为）；目录为空返回 null（用系统默认）。
final lyricFontProvider = FutureProvider<String?>((ref) async {
  try {
    final choice = ref.watch(lyricFontChoiceProvider);
    final dir = await lyricFontDirectory();
    if (!dir.existsSync()) return null;
    final fonts = dir
        .listSync()
        .whereType<File>()
        .where((f) => _isFontFile(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (fonts.isEmpty) return null;
    final selected = choice.isEmpty
        ? fonts.first
        : (fonts.where((f) => p.basename(f.path) == choice).isEmpty
            ? fonts.first
            : fonts.firstWhere((f) => p.basename(f.path) == choice));
    final loader = FontLoader('LyricFont');
    loader.addFont(selected.readAsBytes().then(
          (bytes) => ByteData.sublistView(Uint8List.fromList(bytes)),
        ));
    return p.basename(selected.path);
  } on Object {
    return null;
  }
});
