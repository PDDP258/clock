/// LlmProvider / OpenAI 兼容实现单测（V0.5 云端解读的唯一网络接缝）。
///
/// 语义要点：
/// - 未配置 Key：generateInsight 返回 null（不可用），不发请求；
/// - system/user 分消息、token 预算按 AiPrompt 分档、采样温度 0.6
///   （08-A4/A5；温度由 0.3 回调见看板 #53）；
/// - 失败分类映射：401→unauthorized、429→quota、5xx→network、
///   传输层 TimeoutException→timeout、SocketException→network、
///   响应结构非法→badResponse；全部失败都不抛穿为非 LlmFailure 异常；
/// - ping 仅在 200 且结构合法时 true。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_clock/core/ai/ai_prompt.dart';
import 'package:ai_clock/core/ai/llm_provider.dart';
import 'package:ai_clock/core/ai/deepseek_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vendor = LlmVendorConfig(
    id: 'deepseek',
    displayName: 'DeepSeek',
    endpoint: 'https://api.deepseek.com/chat/completions',
    model: 'deepseek-chat',
  );

  /// 由假传输构造 provider。[handler] 收请求体，返回 (状态码, 响应体)。
  OpenAiCompatibleLlmProvider provider(
    Future<(int, String)> Function(String body) handler,
  ) =>
      OpenAiCompatibleLlmProvider(
        vendor: vendor,
        apiKey: 'sk-test',
        transport: (uri, body, headers) => handler(body),
      );

  String okBody(String text) =>
      '{"choices":[{"message":{"content":"$text"}}]}';

  test('成功：返回 message.content 文本', () async {
    final p = provider((_) async => (200, okBody('复盘文案')));
    expect(await p.generateInsight(const AiPrompt('prompt')), '复盘文案');
  });

  test('system 与 user 分消息：system 存在时发两条 message', () async {
    late Map<String, dynamic> sent;
    final p = provider((body) async {
      sent = (jsonDecode(body) as Map).cast<String, dynamic>();
      return (200, okBody('ok'));
    });
    await p.generateInsight(
        const AiPrompt('用户消息', system: '系统消息', maxTokens: 120));
    final messages = (sent['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages, hasLength(2));
    expect(messages.first['role'], 'system');
    expect(messages.first['content'], '系统消息');
    expect(messages.last['role'], 'user');
    expect(messages.last['content'], '用户消息');
  });

  test('无 system 时只发一条 user message', () async {
    late Map<String, dynamic> sent;
    final p = provider((body) async {
      sent = (jsonDecode(body) as Map).cast<String, dynamic>();
      return (200, okBody('ok'));
    });
    await p.generateInsight(const AiPrompt('只有用户消息'));
    final messages = (sent['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages, hasLength(1));
    expect(messages.single['role'], 'user');
  });

  test('token 预算按 AiPrompt 分档下发（08-A4）', () async {
    late Map<String, dynamic> sent;
    final p = provider((body) async {
      sent = (jsonDecode(body) as Map).cast<String, dynamic>();
      return (200, okBody('ok'));
    });
    await p.generateInsight(const AiPrompt('x', maxTokens: kDailyMaxTokens));
    expect(sent['max_tokens'], 120);
    await p.generateInsight(const AiPrompt('x', maxTokens: kWeeklyMaxTokens));
    expect(sent['max_tokens'], 600);
  });

  test('采样温度 0.6：给措辞留多样性，但不到创作档（看板 #53）', () async {
    late Map<String, dynamic> sent;
    final p = provider((body) async {
      sent = (jsonDecode(body) as Map).cast<String, dynamic>();
      return (200, okBody('ok'));
    });
    await p.generateInsight(const AiPrompt('x'));
    // 0.3（08-A5）把表达压成了千篇一律的句式，用户反馈「太枯燥」；
    // 0.6 留出措辞多样性，同时远低于创作档（0.8+）——数字确定性由
    // 硬约束 + 本地算数保证，不靠温度换。
    expect(sent['temperature'], 0.6);
  });

  test('未配置 Key：返回 null 且不发请求', () async {
    var called = false;
    final p = OpenAiCompatibleLlmProvider(
      vendor: vendor,
      apiKey: '',
      transport: (_, __, ___) async {
        called = true;
        return (200, okBody('x'));
      },
    );
    expect(await p.generateInsight(const AiPrompt('prompt')), isNull);
    expect(called, isFalse);
  });

  test('401 → LlmUnauthorized', () {
    final p = provider((_) async => (401, '{}'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.unauthorized)));
  });

  test('429 → quota', () {
    final p = provider((_) async => (429, '{}'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.quota)));
  });

  test('402 → quota（DeepSeek 余额不足，Key 正确未充值即此码）', () {
    final p = provider((_) async => (402, '{}'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.quota)));
  });

  test('422 → badResponse（参数错误属我方请求问题，不归网络）', () {
    final p = provider((_) async => (422, '{}'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.badResponse)));
  });

  test('500 → network', () {
    final p = provider((_) async => (500, '{}'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.network)));
  });

  test('传输层 TimeoutException → timeout', () {
    final p = provider(
        (_) async => throw TimeoutException('read timeout'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.timeout)));
  });

  test('传输层 SocketException → network', () {
    final p = provider(
        (_) async => throw const SocketException('no route'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.network)));
  });

  test('响应结构非法 → badResponse', () {
    final p = provider((_) async => (200, '{"unexpected":true}'));
    expect(p.generateInsight(const AiPrompt('p')),
        throwsA(isA<LlmFailure>().having((e) => e.kind, 'kind',
            LlmFailureKind.badResponse)));
  });

  test('ping：200 且结构合法 → true；401 → false', () async {
    final ok = provider((_) async => (200, okBody('pong')));
    expect(await ok.ping(), isTrue);
    final bad = provider((_) async => (401, '{}'));
    expect(await bad.ping(), isFalse);
  });

  test('厂商预设三家齐全且端点互不相同', () {
    expect(LlmVendor.presets.map((v) => v.id).toSet(),
        {'deepseek', 'kimi', 'qwen'});
    expect(
        LlmVendor.presets.map((v) => v.endpoint).toSet().length, 3);
  });
}
