/// BackupCodec 单测（看板 #45 数据导出与备份）：
/// 往返一致、损坏/张冠李戴/版本过新/字段缺失全部给中文 FormatException。
library;

import 'package:ai_clock/core/backup/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = BackupSession(
    startAt: 1757000000000,
    endAt: 1757001800000,
    plannedFocusMillis: 1500000,
    actualFocusMillis: 1480000,
    rounds: 1,
    completed: true,
    mode: 'pomodoro',
    marksJson: null,
    intervalsJson: '[[1757000000000,1757001480000]]',
    pausesJson: '[[1757000100000,1757000120000]]',
    tag: '写作',
  );

  test('编码→解码往返一致（含可空字段）', () {
    final raw = BackupCodec.encode(const BackupData(
      exportedAtMillis: 1757003600000,
      sessions: [
        sample,
        BackupSession(
          startAt: 1757100000000,
          endAt: null, // 进行中会话
          plannedFocusMillis: 0,
          actualFocusMillis: 60000,
          rounds: 0,
          completed: false,
          mode: 'countUp',
          marksJson: '[30000]',
          intervalsJson: null,
          pausesJson: null,
          tag: null,
        ),
      ],
    ));
    final back = BackupCodec.decode(raw);
    expect(back.exportedAtMillis, 1757003600000);
    expect(back.sessions, hasLength(2));
    // 按 startAt 升序
    expect(back.sessions.first.startAt, 1757000000000);
    final s = back.sessions.first;
    expect(s.endAt, 1757001800000);
    expect(s.actualFocusMillis, 1480000);
    expect(s.tag, '写作');
    expect(back.sessions.last.endAt, isNull);
    expect(back.sessions.last.mode, 'countUp');
    expect(back.sessions.last.marksJson, '[30000]');
  });

  test('空记录列表可往返', () {
    final back = BackupCodec.decode(BackupCodec.encode(
        const BackupData(exportedAtMillis: 1, sessions: [])));
    expect(back.sessions, isEmpty);
  });

  test('非 JSON → 中文原因', () {
    expect(() => BackupCodec.decode('not json'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('JSON'))));
  });

  test('非本应用备份 → 中文原因', () {
    expect(() => BackupCodec.decode('{"app":"Other","version":1}'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('MikuFocus'))));
  });

  test('版本过新 → 拒绝导入', () {
    expect(
        () => BackupCodec.decode(
            '{"app":"MikuFocus","version":99,"exported_at":1,"sessions":[]}'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('版本'))));
  });

  test('记录缺字段/类型错误 → 指出第几条', () {
    const raw = '{"app":"MikuFocus","version":1,"exported_at":1,'
        '"sessions":[{"start_at":1,"planned_focus_millis":0}]}';
    expect(
        () => BackupCodec.decode(raw),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('第 1 条'))));
  });

  test('可空字段类型错误同样拒绝', () {
    const raw = '{"app":"MikuFocus","version":1,"exported_at":1,'
        '"sessions":[{"start_at":1,"end_at":"oops","planned_focus_millis":0,'
        '"actual_focus_millis":0,"rounds":0,"completed":false,'
        '"mode":"pomodoro"}]}';
    expect(() => BackupCodec.decode(raw), throwsA(isA<FormatException>()));
  });
}
