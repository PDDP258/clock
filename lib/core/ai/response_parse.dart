/// 响应解析加固层（08-A3）：模型排版差异不应把好答案判成坏答案。
///
/// 背景：原实现用 `\n\s*\n` 精确切段 + `startsWith('建议：')` 精确匹配，
/// 而 Kimi/通义常以单换行分段、并习惯输出 `**建议：**` 这类 Markdown 装饰——
/// 任一差异都会让整块降级为「解读结果异常」，尽管模型答得完全正确。
///
/// 本层做三件事（全部纯 Dart 可测）：
/// 1. [cleanLine] 去 Markdown 装饰与列表/引用/标题前缀；
/// 2. [splitBlocks] 按空行切段，无空行时回退按单行切段（并让「建议」自起一段）；
/// 3. [firstMeaningfulLine] 取首个有意义的行，跳过模型客套开场白。
library;

import 'dart:convert';

/// 「建议」段起始标记：允许前导装饰，冒号后可选。
final RegExp _suggestionStart = RegExp(
  r'^(?:建议|我的建议|下周建议|下步建议)\s*(?:[:：,，.。]|$)',
);

/// 客套开场白特征词（短句才判定，避免误伤正文）。
const List<String> _preambleStarters = <String>[
  '好的',
  '好，',
  '根据',
  '以下是',
  '下面是',
  '从数据看',
  '从你的数据',
  '明白了',
  '收到',
];

/// 去 Markdown 装饰：列表/引用前缀、标题井号、有序列表号、加粗与行内代码。
/// 只处理行首前缀与成对标记，不改动正文用词。
String cleanLine(String raw) {
  var t = raw.trim();
  t = t.replaceAll(RegExp(r'^[>\-*+•]\s+'), ''); // 引用 / 无序列表
  t = t.replaceAll(RegExp(r'^#{1,6}\s*'), ''); // 标题
  t = t.replaceAll(RegExp(r'^\d+[.)、]\s*'), ''); // 有序列表
  t = t.replaceAll('**', '').replaceAll('__', ''); // 加粗
  t = t.replaceAll('`', ''); // 行内代码
  return t.trim();
}

/// 该行（已 [cleanLine]）是否为「建议」段的起始。
bool isSuggestionStart(String line) => _suggestionStart.hasMatch(line);

/// 剥掉「建议：」类前缀，返回建议正文；非建议段返回空串。
String suggestionBody(String line) {
  final m = _suggestionStart.firstMatch(line);
  if (m == null) return '';
  var rest = line.substring(m.end);
  rest = rest.replaceFirst(RegExp(r'^[:：,，.。]\s*'), '');
  return rest.trim();
}

/// 段落切分：有空行时按空行分段（段内换行并成一句）；
/// 无空行时按单行分段——模型只用单换行排版也能解析。
/// 「建议」行始终自起一段，保证它不会被吞进上一段的正文里。
List<String> splitBlocks(String raw) {
  final blankSeparated = RegExp(r'\n\s*\n').hasMatch(raw);
  final out = <String>[];
  final buf = <String>[];
  void flush() {
    final t = buf.join(' ').trim();
    if (t.isNotEmpty) out.add(t);
    buf.clear();
  }

  for (final rawLine in raw.split('\n')) {
    final line = cleanLine(rawLine);
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (isSuggestionStart(line)) {
      flush();
      buf.add(line);
      continue;
    }
    buf.add(line);
    if (!blankSeparated) flush();
  }
  flush();
  return out;
}

/// 取首个有意义的非空行：跳过空行与客套开场白，去 Markdown、
/// 去 [prefixes] 中的答话前缀。全部无可取内容返回 null。
///
/// 用意：模型常先来一句「好的，根据你的数据：」，若直接取首行，
/// 用户在 chip 上看到的就只是这句寒暄。
String? firstMeaningfulLine(String raw, List<String> prefixes) {
  for (final rawLine in const LineSplitter().convert(raw)) {
    final line = cleanLine(rawLine);
    if (line.isEmpty) continue;
    if (_isPreamble(line)) continue;
    var content = line;
    for (final prefix in prefixes) {
      if (content.startsWith(prefix)) {
        content = content.substring(prefix.length).trim();
      }
    }
    if (content.isEmpty) continue;
    return content;
  }
  return null;
}

/// 短引导句判定：特征词起头，或以冒号结尾（「好的，根据数据：」）。
bool _isPreamble(String line) {
  if (line.length > 24) return false;
  for (final s in _preambleStarters) {
    if (line.startsWith(s)) return true;
  }
  return line.endsWith('：') || line.endsWith(':');
}
