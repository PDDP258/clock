/// OpenAI 兼容的 LLM 服务商实现（V0.5）：DeepSeek / Kimi / 通义千问。
///
/// 三家同为 OpenAI `/chat/completions` 形态，单实现 + 厂商预设即可
/// 「切换只改设置，不改业务代码」（06-Implementation Decisions §2）。
/// 不引 http/dio 依赖：dart:io HttpClient 足够，且经 [transport] 注入
/// 可在单测中替换为假传输（TDD 接缝）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_prompt.dart';
import 'llm_provider.dart';

/// 厂商配置（端点 + 模型 + 展示名）。
class LlmVendorConfig {
  const LlmVendorConfig({
    required this.id,
    required this.displayName,
    required this.endpoint,
    required this.model,
  });

  /// 服务商标识
  final String id;

  /// 中文展示名（设置页用）
  final String displayName;

  /// OpenAI 兼容 chat/completions 端点
  final String endpoint;

  /// 默认模型
  final String model;
}

/// 厂商预设（设置页切换的数据源）。
abstract final class LlmVendor {
  static const deepseek = LlmVendorConfig(
    id: 'deepseek',
    displayName: 'DeepSeek',
    endpoint: 'https://api.deepseek.com/chat/completions',
    model: 'deepseek-chat',
  );
  static const kimi = LlmVendorConfig(
    id: 'kimi',
    displayName: 'Kimi',
    endpoint: 'https://api.moonshot.cn/v1/chat/completions',
    model: 'moonshot-v1-8k',
  );
  static const qwen = LlmVendorConfig(
    id: 'qwen',
    displayName: '通义千问',
    endpoint:
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
    model: 'qwen-plus',
  );

  /// 全部预设
  static const presets = <LlmVendorConfig>[deepseek, kimi, qwen];

  /// 按 id 查预设；未知 id 回退 DeepSeek（首选，05 §4）
  static LlmVendorConfig byId(String? id) =>
      presets.firstWhere((v) => v.id == id, orElse: () => deepseek);
}

/// 传输层抽象：POST [uri]（JSON 体 + 头），返回 (状态码, 响应体)。
/// 默认实现用 dart:io HttpClient；测试注入假传输。
typedef LlmTransport = Future<(int, String)> Function(
  Uri uri,
  String body,
  Map<String, String> headers,
);

/// OpenAI 兼容服务商实现。
class OpenAiCompatibleLlmProvider implements LlmProvider {
  OpenAiCompatibleLlmProvider({
    required this.vendor,
    required this.apiKey,
    LlmTransport? transport,
  }) : _transport = transport ?? _defaultTransport;

  /// 厂商配置
  final LlmVendorConfig vendor;

  /// API Key（存 shared_preferences，不日志、不上报）
  final String apiKey;

  final LlmTransport _transport;

  /// 连接超时
  static const connectTimeout = Duration(seconds: 10);

  /// 读取超时（真机教训 2026-09-09：非流式请求要等整段生成完成才返回，
  /// 周报 600 tokens 在服务商负载下可达 30s+，15s 会大面积误报超时）
  static const readTimeout = Duration(seconds: 60);

  /// 采样温度：本模块的任务是「引用给定数字做复盘」，不是创作。
  ///
  /// 2026-09-26 由 0.3 回调到 0.6：0.3 的代价是把表达压成了**千篇一律的
  /// 句式**（08-A5 只考虑了「防编造」，没考虑「读起来像同一个人写的废话」，
  /// 用户反馈「太枯燥」）。数字确定性由硬约束 + 本地算数保证，
  /// 不靠温度换——温度只管**措辞的多样性**。
  static const temperature = 0.6;

  @override
  String get id => vendor.id;

  @override
  Future<String?> generateInsight(AiPrompt prompt) async {
    if (apiKey.isEmpty) return null; // 未配置 Key：不可用，不发请求
    final body = jsonEncode(<String, dynamic>{
      'model': vendor.model,
      'messages': <Map<String, String>>[
        // system/user 分消息：角色与硬约束走 system，指令遵循度更高（08-A5）
        if (prompt.system != null && prompt.system!.isNotEmpty)
          <String, String>{'role': 'system', 'content': prompt.system!},
        <String, String>{'role': 'user', 'content': prompt.user},
      ],
      'temperature': temperature,
      'max_tokens': prompt.maxTokens,
    });
    final (status, responseBody) = await _send(body);
    return _extractContent(status, responseBody);
  }

  @override
  Future<bool> ping() async {
    if (apiKey.isEmpty) return false;
    try {
      final body = jsonEncode(<String, dynamic>{
        'model': vendor.model,
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': 'ping'},
        ],
        'max_tokens': 1,
      });
      final (status, responseBody) = await _send(body);
      _extractContent(status, responseBody);
      return true;
    } on LlmFailure {
      return false;
    }
  }

  Future<(int, String)> _send(String body) async {
    try {
      return await _transport(
        Uri.parse(vendor.endpoint),
        body,
        <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      );
    } on TimeoutException {
      throw LlmFailure(LlmFailureKind.timeout, vendor.id);
    } on SocketException catch (e) {
      throw LlmFailure(LlmFailureKind.network, e.message);
    } on HttpException catch (e) {
      throw LlmFailure(LlmFailureKind.network, e.message);
    }
  }

  String _extractContent(int status, String responseBody) {
    if (status == 401 || status == 403) {
      throw LlmFailure(LlmFailureKind.unauthorized, 'HTTP $status');
    }
    // DeepSeek 错误码（api-docs.deepseek.com/quick_start/error_codes）：
    // 402=余额不足（无免费额度，Key 正确未充值即此码）、429=速率上限
    if (status == 402) {
      throw const LlmFailure(LlmFailureKind.quota, 'HTTP 402 余额不足');
    }
    if (status == 429) {
      throw const LlmFailure(LlmFailureKind.quota, 'HTTP 429 速率上限');
    }
    // 400=请求体格式错误、422=参数错误：属我方请求问题，归 badResponse 便于区分
    if (status == 400 || status == 422) {
      throw LlmFailure(LlmFailureKind.badResponse, 'HTTP $status 参数错误');
    }
    if (status != 200) {
      throw LlmFailure(LlmFailureKind.network, 'HTTP $status');
    }
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>;
      final message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>;
      final content = message['content'] as String;
      if (content.trim().isEmpty) throw const FormatException('empty');
      return content;
    } on Object {
      throw const LlmFailure(LlmFailureKind.badResponse, 'HTTP 200 结构非法');
    }
  }

  static Future<(int, String)> _defaultTransport(
    Uri uri,
    String body,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      // 显式 Content-Length：不设时 HttpClient 走 chunked 传输编码，
      // 部分 API 网关对 chunked 兼容性差（连接被掐/400）
      final bytes = utf8.encode(body);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(readTimeout);
      final responseBody = await response.transform(utf8.decoder).join();
      return (response.statusCode, responseBody);
    } finally {
      client.close();
    }
  }
}
