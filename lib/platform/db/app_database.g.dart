// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
mixin _$FocusSessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $FocusSessionsTable get focusSessions => attachedDatabase.focusSessions;
  FocusSessionDaoManager get managers => FocusSessionDaoManager(this);
}

class FocusSessionDaoManager {
  final _$FocusSessionDaoMixin _db;
  FocusSessionDaoManager(this._db);
  $$FocusSessionsTableTableManager get focusSessions =>
      $$FocusSessionsTableTableManager(_db.attachedDatabase, _db.focusSessions);
}

class $FocusSessionsTable extends FocusSessions
    with TableInfo<$FocusSessionsTable, FocusSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FocusSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _startAtMeta =
      const VerificationMeta('startAt');
  @override
  late final GeneratedColumn<int> startAt = GeneratedColumn<int>(
      'start_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<int> endAt = GeneratedColumn<int>(
      'end_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _plannedFocusMillisMeta =
      const VerificationMeta('plannedFocusMillis');
  @override
  late final GeneratedColumn<int> plannedFocusMillis = GeneratedColumn<int>(
      'planned_focus_millis', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _actualFocusMillisMeta =
      const VerificationMeta('actualFocusMillis');
  @override
  late final GeneratedColumn<int> actualFocusMillis = GeneratedColumn<int>(
      'actual_focus_millis', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _roundsMeta = const VerificationMeta('rounds');
  @override
  late final GeneratedColumn<int> rounds = GeneratedColumn<int>(
      'rounds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
      'completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
      'mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pomodoro'));
  static const VerificationMeta _marksJsonMeta =
      const VerificationMeta('marksJson');
  @override
  late final GeneratedColumn<String> marksJson = GeneratedColumn<String>(
      'marks_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _intervalsJsonMeta =
      const VerificationMeta('intervalsJson');
  @override
  late final GeneratedColumn<String> intervalsJson = GeneratedColumn<String>(
      'intervals_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pausesJsonMeta =
      const VerificationMeta('pausesJson');
  @override
  late final GeneratedColumn<String> pausesJson = GeneratedColumn<String>(
      'pauses_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
      'tag', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        startAt,
        endAt,
        plannedFocusMillis,
        actualFocusMillis,
        rounds,
        completed,
        mode,
        marksJson,
        intervalsJson,
        pausesJson,
        tag
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'focus_session';
  @override
  VerificationContext validateIntegrity(Insertable<FocusSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start_at')) {
      context.handle(_startAtMeta,
          startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta));
    } else if (isInserting) {
      context.missing(_startAtMeta);
    }
    if (data.containsKey('end_at')) {
      context.handle(
          _endAtMeta, endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta));
    }
    if (data.containsKey('planned_focus_millis')) {
      context.handle(
          _plannedFocusMillisMeta,
          plannedFocusMillis.isAcceptableOrUnknown(
              data['planned_focus_millis']!, _plannedFocusMillisMeta));
    } else if (isInserting) {
      context.missing(_plannedFocusMillisMeta);
    }
    if (data.containsKey('actual_focus_millis')) {
      context.handle(
          _actualFocusMillisMeta,
          actualFocusMillis.isAcceptableOrUnknown(
              data['actual_focus_millis']!, _actualFocusMillisMeta));
    } else if (isInserting) {
      context.missing(_actualFocusMillisMeta);
    }
    if (data.containsKey('rounds')) {
      context.handle(_roundsMeta,
          rounds.isAcceptableOrUnknown(data['rounds']!, _roundsMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    if (data.containsKey('mode')) {
      context.handle(
          _modeMeta, mode.isAcceptableOrUnknown(data['mode']!, _modeMeta));
    }
    if (data.containsKey('marks_json')) {
      context.handle(_marksJsonMeta,
          marksJson.isAcceptableOrUnknown(data['marks_json']!, _marksJsonMeta));
    }
    if (data.containsKey('intervals_json')) {
      context.handle(
          _intervalsJsonMeta,
          intervalsJson.isAcceptableOrUnknown(
              data['intervals_json']!, _intervalsJsonMeta));
    }
    if (data.containsKey('pauses_json')) {
      context.handle(
          _pausesJsonMeta,
          pausesJson.isAcceptableOrUnknown(
              data['pauses_json']!, _pausesJsonMeta));
    }
    if (data.containsKey('tag')) {
      context.handle(
          _tagMeta, tag.isAcceptableOrUnknown(data['tag']!, _tagMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FocusSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FocusSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      startAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_at'])!,
      endAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_at']),
      plannedFocusMillis: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}planned_focus_millis'])!,
      actualFocusMillis: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}actual_focus_millis'])!,
      rounds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rounds'])!,
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completed'])!,
      mode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mode'])!,
      marksJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}marks_json']),
      intervalsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}intervals_json']),
      pausesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pauses_json']),
      tag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tag']),
    );
  }

  @override
  $FocusSessionsTable createAlias(String alias) {
    return $FocusSessionsTable(attachedDatabase, alias);
  }
}

class FocusSession extends DataClass implements Insertable<FocusSession> {
  final int id;

  /// 会话开始时间（毫秒时间戳）
  final int startAt;

  /// 会话结束时间；进行中为 null
  final int? endAt;

  /// 计划专注总毫秒
  final int plannedFocusMillis;

  /// 实际专注总毫秒（扣除暂停/休息）
  final int actualFocusMillis;

  /// 完成轮数
  final int rounds;

  /// 是否正常完成（false = 提前结束）
  final bool completed;

  /// 计时模式：pomodoro / countUp（schema v2 新增）
  final String mode;

  /// 正计时打点偏移毫秒列表（JSON 数组，schema v3 新增；番茄模式为 null）
  final String? marksJson;

  /// 各专注段的实际墙钟区间（JSON 数组 [[start,end],...]，schema v4 新增；
  /// 供时间轴「断断续续 + 休息空隙」渲染；老数据为 null 时回退整段渲染）
  final String? intervalsJson;

  /// 专注阶段内的暂停（中断）区间（JSON 数组 [[start,end],...]，end 可空
  /// 表示暂停中；schema v5 新增，US-D02）
  final String? pausesJson;

  /// 会话关联的任务/标签（schema v5 新增，US-B05；无标签为 null）
  final String? tag;
  const FocusSession(
      {required this.id,
      required this.startAt,
      this.endAt,
      required this.plannedFocusMillis,
      required this.actualFocusMillis,
      required this.rounds,
      required this.completed,
      required this.mode,
      this.marksJson,
      this.intervalsJson,
      this.pausesJson,
      this.tag});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start_at'] = Variable<int>(startAt);
    if (!nullToAbsent || endAt != null) {
      map['end_at'] = Variable<int>(endAt);
    }
    map['planned_focus_millis'] = Variable<int>(plannedFocusMillis);
    map['actual_focus_millis'] = Variable<int>(actualFocusMillis);
    map['rounds'] = Variable<int>(rounds);
    map['completed'] = Variable<bool>(completed);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || marksJson != null) {
      map['marks_json'] = Variable<String>(marksJson);
    }
    if (!nullToAbsent || intervalsJson != null) {
      map['intervals_json'] = Variable<String>(intervalsJson);
    }
    if (!nullToAbsent || pausesJson != null) {
      map['pauses_json'] = Variable<String>(pausesJson);
    }
    if (!nullToAbsent || tag != null) {
      map['tag'] = Variable<String>(tag);
    }
    return map;
  }

  FocusSessionsCompanion toCompanion(bool nullToAbsent) {
    return FocusSessionsCompanion(
      id: Value(id),
      startAt: Value(startAt),
      endAt:
          endAt == null && nullToAbsent ? const Value.absent() : Value(endAt),
      plannedFocusMillis: Value(plannedFocusMillis),
      actualFocusMillis: Value(actualFocusMillis),
      rounds: Value(rounds),
      completed: Value(completed),
      mode: Value(mode),
      marksJson: marksJson == null && nullToAbsent
          ? const Value.absent()
          : Value(marksJson),
      intervalsJson: intervalsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(intervalsJson),
      pausesJson: pausesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(pausesJson),
      tag: tag == null && nullToAbsent ? const Value.absent() : Value(tag),
    );
  }

  factory FocusSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FocusSession(
      id: serializer.fromJson<int>(json['id']),
      startAt: serializer.fromJson<int>(json['startAt']),
      endAt: serializer.fromJson<int?>(json['endAt']),
      plannedFocusMillis: serializer.fromJson<int>(json['plannedFocusMillis']),
      actualFocusMillis: serializer.fromJson<int>(json['actualFocusMillis']),
      rounds: serializer.fromJson<int>(json['rounds']),
      completed: serializer.fromJson<bool>(json['completed']),
      mode: serializer.fromJson<String>(json['mode']),
      marksJson: serializer.fromJson<String?>(json['marksJson']),
      intervalsJson: serializer.fromJson<String?>(json['intervalsJson']),
      pausesJson: serializer.fromJson<String?>(json['pausesJson']),
      tag: serializer.fromJson<String?>(json['tag']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startAt': serializer.toJson<int>(startAt),
      'endAt': serializer.toJson<int?>(endAt),
      'plannedFocusMillis': serializer.toJson<int>(plannedFocusMillis),
      'actualFocusMillis': serializer.toJson<int>(actualFocusMillis),
      'rounds': serializer.toJson<int>(rounds),
      'completed': serializer.toJson<bool>(completed),
      'mode': serializer.toJson<String>(mode),
      'marksJson': serializer.toJson<String?>(marksJson),
      'intervalsJson': serializer.toJson<String?>(intervalsJson),
      'pausesJson': serializer.toJson<String?>(pausesJson),
      'tag': serializer.toJson<String?>(tag),
    };
  }

  FocusSession copyWith(
          {int? id,
          int? startAt,
          Value<int?> endAt = const Value.absent(),
          int? plannedFocusMillis,
          int? actualFocusMillis,
          int? rounds,
          bool? completed,
          String? mode,
          Value<String?> marksJson = const Value.absent(),
          Value<String?> intervalsJson = const Value.absent(),
          Value<String?> pausesJson = const Value.absent(),
          Value<String?> tag = const Value.absent()}) =>
      FocusSession(
        id: id ?? this.id,
        startAt: startAt ?? this.startAt,
        endAt: endAt.present ? endAt.value : this.endAt,
        plannedFocusMillis: plannedFocusMillis ?? this.plannedFocusMillis,
        actualFocusMillis: actualFocusMillis ?? this.actualFocusMillis,
        rounds: rounds ?? this.rounds,
        completed: completed ?? this.completed,
        mode: mode ?? this.mode,
        marksJson: marksJson.present ? marksJson.value : this.marksJson,
        intervalsJson:
            intervalsJson.present ? intervalsJson.value : this.intervalsJson,
        pausesJson: pausesJson.present ? pausesJson.value : this.pausesJson,
        tag: tag.present ? tag.value : this.tag,
      );
  FocusSession copyWithCompanion(FocusSessionsCompanion data) {
    return FocusSession(
      id: data.id.present ? data.id.value : this.id,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      plannedFocusMillis: data.plannedFocusMillis.present
          ? data.plannedFocusMillis.value
          : this.plannedFocusMillis,
      actualFocusMillis: data.actualFocusMillis.present
          ? data.actualFocusMillis.value
          : this.actualFocusMillis,
      rounds: data.rounds.present ? data.rounds.value : this.rounds,
      completed: data.completed.present ? data.completed.value : this.completed,
      mode: data.mode.present ? data.mode.value : this.mode,
      marksJson: data.marksJson.present ? data.marksJson.value : this.marksJson,
      intervalsJson: data.intervalsJson.present
          ? data.intervalsJson.value
          : this.intervalsJson,
      pausesJson:
          data.pausesJson.present ? data.pausesJson.value : this.pausesJson,
      tag: data.tag.present ? data.tag.value : this.tag,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FocusSession(')
          ..write('id: $id, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('plannedFocusMillis: $plannedFocusMillis, ')
          ..write('actualFocusMillis: $actualFocusMillis, ')
          ..write('rounds: $rounds, ')
          ..write('completed: $completed, ')
          ..write('mode: $mode, ')
          ..write('marksJson: $marksJson, ')
          ..write('intervalsJson: $intervalsJson, ')
          ..write('pausesJson: $pausesJson, ')
          ..write('tag: $tag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      startAt,
      endAt,
      plannedFocusMillis,
      actualFocusMillis,
      rounds,
      completed,
      mode,
      marksJson,
      intervalsJson,
      pausesJson,
      tag);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FocusSession &&
          other.id == this.id &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.plannedFocusMillis == this.plannedFocusMillis &&
          other.actualFocusMillis == this.actualFocusMillis &&
          other.rounds == this.rounds &&
          other.completed == this.completed &&
          other.mode == this.mode &&
          other.marksJson == this.marksJson &&
          other.intervalsJson == this.intervalsJson &&
          other.pausesJson == this.pausesJson &&
          other.tag == this.tag);
}

class FocusSessionsCompanion extends UpdateCompanion<FocusSession> {
  final Value<int> id;
  final Value<int> startAt;
  final Value<int?> endAt;
  final Value<int> plannedFocusMillis;
  final Value<int> actualFocusMillis;
  final Value<int> rounds;
  final Value<bool> completed;
  final Value<String> mode;
  final Value<String?> marksJson;
  final Value<String?> intervalsJson;
  final Value<String?> pausesJson;
  final Value<String?> tag;
  const FocusSessionsCompanion({
    this.id = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.plannedFocusMillis = const Value.absent(),
    this.actualFocusMillis = const Value.absent(),
    this.rounds = const Value.absent(),
    this.completed = const Value.absent(),
    this.mode = const Value.absent(),
    this.marksJson = const Value.absent(),
    this.intervalsJson = const Value.absent(),
    this.pausesJson = const Value.absent(),
    this.tag = const Value.absent(),
  });
  FocusSessionsCompanion.insert({
    this.id = const Value.absent(),
    required int startAt,
    this.endAt = const Value.absent(),
    required int plannedFocusMillis,
    required int actualFocusMillis,
    this.rounds = const Value.absent(),
    this.completed = const Value.absent(),
    this.mode = const Value.absent(),
    this.marksJson = const Value.absent(),
    this.intervalsJson = const Value.absent(),
    this.pausesJson = const Value.absent(),
    this.tag = const Value.absent(),
  })  : startAt = Value(startAt),
        plannedFocusMillis = Value(plannedFocusMillis),
        actualFocusMillis = Value(actualFocusMillis);
  static Insertable<FocusSession> custom({
    Expression<int>? id,
    Expression<int>? startAt,
    Expression<int>? endAt,
    Expression<int>? plannedFocusMillis,
    Expression<int>? actualFocusMillis,
    Expression<int>? rounds,
    Expression<bool>? completed,
    Expression<String>? mode,
    Expression<String>? marksJson,
    Expression<String>? intervalsJson,
    Expression<String>? pausesJson,
    Expression<String>? tag,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (plannedFocusMillis != null)
        'planned_focus_millis': plannedFocusMillis,
      if (actualFocusMillis != null) 'actual_focus_millis': actualFocusMillis,
      if (rounds != null) 'rounds': rounds,
      if (completed != null) 'completed': completed,
      if (mode != null) 'mode': mode,
      if (marksJson != null) 'marks_json': marksJson,
      if (intervalsJson != null) 'intervals_json': intervalsJson,
      if (pausesJson != null) 'pauses_json': pausesJson,
      if (tag != null) 'tag': tag,
    });
  }

  FocusSessionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? startAt,
      Value<int?>? endAt,
      Value<int>? plannedFocusMillis,
      Value<int>? actualFocusMillis,
      Value<int>? rounds,
      Value<bool>? completed,
      Value<String>? mode,
      Value<String?>? marksJson,
      Value<String?>? intervalsJson,
      Value<String?>? pausesJson,
      Value<String?>? tag}) {
    return FocusSessionsCompanion(
      id: id ?? this.id,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      plannedFocusMillis: plannedFocusMillis ?? this.plannedFocusMillis,
      actualFocusMillis: actualFocusMillis ?? this.actualFocusMillis,
      rounds: rounds ?? this.rounds,
      completed: completed ?? this.completed,
      mode: mode ?? this.mode,
      marksJson: marksJson ?? this.marksJson,
      intervalsJson: intervalsJson ?? this.intervalsJson,
      pausesJson: pausesJson ?? this.pausesJson,
      tag: tag ?? this.tag,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<int>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<int>(endAt.value);
    }
    if (plannedFocusMillis.present) {
      map['planned_focus_millis'] = Variable<int>(plannedFocusMillis.value);
    }
    if (actualFocusMillis.present) {
      map['actual_focus_millis'] = Variable<int>(actualFocusMillis.value);
    }
    if (rounds.present) {
      map['rounds'] = Variable<int>(rounds.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (marksJson.present) {
      map['marks_json'] = Variable<String>(marksJson.value);
    }
    if (intervalsJson.present) {
      map['intervals_json'] = Variable<String>(intervalsJson.value);
    }
    if (pausesJson.present) {
      map['pauses_json'] = Variable<String>(pausesJson.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FocusSessionsCompanion(')
          ..write('id: $id, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('plannedFocusMillis: $plannedFocusMillis, ')
          ..write('actualFocusMillis: $actualFocusMillis, ')
          ..write('rounds: $rounds, ')
          ..write('completed: $completed, ')
          ..write('mode: $mode, ')
          ..write('marksJson: $marksJson, ')
          ..write('intervalsJson: $intervalsJson, ')
          ..write('pausesJson: $pausesJson, ')
          ..write('tag: $tag')
          ..write(')'))
        .toString();
  }
}

class $UsageStatDailiesTable extends UsageStatDailies
    with TableInfo<$UsageStatDailiesTable, UsageStatDaily> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsageStatDailiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
      'day', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _foregroundMillisMeta =
      const VerificationMeta('foregroundMillis');
  @override
  late final GeneratedColumn<int> foregroundMillis = GeneratedColumn<int>(
      'foreground_millis', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, day, packageName, foregroundMillis];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'usage_stat_daily';
  @override
  VerificationContext validateIntegrity(Insertable<UsageStatDaily> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('day')) {
      context.handle(
          _dayMeta, day.isAcceptableOrUnknown(data['day']!, _dayMeta));
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('foreground_millis')) {
      context.handle(
          _foregroundMillisMeta,
          foregroundMillis.isAcceptableOrUnknown(
              data['foreground_millis']!, _foregroundMillisMeta));
    } else if (isInserting) {
      context.missing(_foregroundMillisMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {day, packageName},
      ];
  @override
  UsageStatDaily map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UsageStatDaily(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      day: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day'])!,
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name'])!,
      foregroundMillis: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}foreground_millis'])!,
    );
  }

  @override
  $UsageStatDailiesTable createAlias(String alias) {
    return $UsageStatDailiesTable(attachedDatabase, alias);
  }
}

class UsageStatDaily extends DataClass implements Insertable<UsageStatDaily> {
  final int id;

  /// 日期，格式 yyyy-MM-dd
  final String day;

  /// 应用包名
  final String packageName;

  /// 当日前台总毫秒
  final int foregroundMillis;
  const UsageStatDaily(
      {required this.id,
      required this.day,
      required this.packageName,
      required this.foregroundMillis});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['day'] = Variable<String>(day);
    map['package_name'] = Variable<String>(packageName);
    map['foreground_millis'] = Variable<int>(foregroundMillis);
    return map;
  }

  UsageStatDailiesCompanion toCompanion(bool nullToAbsent) {
    return UsageStatDailiesCompanion(
      id: Value(id),
      day: Value(day),
      packageName: Value(packageName),
      foregroundMillis: Value(foregroundMillis),
    );
  }

  factory UsageStatDaily.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UsageStatDaily(
      id: serializer.fromJson<int>(json['id']),
      day: serializer.fromJson<String>(json['day']),
      packageName: serializer.fromJson<String>(json['packageName']),
      foregroundMillis: serializer.fromJson<int>(json['foregroundMillis']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'day': serializer.toJson<String>(day),
      'packageName': serializer.toJson<String>(packageName),
      'foregroundMillis': serializer.toJson<int>(foregroundMillis),
    };
  }

  UsageStatDaily copyWith(
          {int? id, String? day, String? packageName, int? foregroundMillis}) =>
      UsageStatDaily(
        id: id ?? this.id,
        day: day ?? this.day,
        packageName: packageName ?? this.packageName,
        foregroundMillis: foregroundMillis ?? this.foregroundMillis,
      );
  UsageStatDaily copyWithCompanion(UsageStatDailiesCompanion data) {
    return UsageStatDaily(
      id: data.id.present ? data.id.value : this.id,
      day: data.day.present ? data.day.value : this.day,
      packageName:
          data.packageName.present ? data.packageName.value : this.packageName,
      foregroundMillis: data.foregroundMillis.present
          ? data.foregroundMillis.value
          : this.foregroundMillis,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UsageStatDaily(')
          ..write('id: $id, ')
          ..write('day: $day, ')
          ..write('packageName: $packageName, ')
          ..write('foregroundMillis: $foregroundMillis')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, day, packageName, foregroundMillis);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UsageStatDaily &&
          other.id == this.id &&
          other.day == this.day &&
          other.packageName == this.packageName &&
          other.foregroundMillis == this.foregroundMillis);
}

class UsageStatDailiesCompanion extends UpdateCompanion<UsageStatDaily> {
  final Value<int> id;
  final Value<String> day;
  final Value<String> packageName;
  final Value<int> foregroundMillis;
  const UsageStatDailiesCompanion({
    this.id = const Value.absent(),
    this.day = const Value.absent(),
    this.packageName = const Value.absent(),
    this.foregroundMillis = const Value.absent(),
  });
  UsageStatDailiesCompanion.insert({
    this.id = const Value.absent(),
    required String day,
    required String packageName,
    required int foregroundMillis,
  })  : day = Value(day),
        packageName = Value(packageName),
        foregroundMillis = Value(foregroundMillis);
  static Insertable<UsageStatDaily> custom({
    Expression<int>? id,
    Expression<String>? day,
    Expression<String>? packageName,
    Expression<int>? foregroundMillis,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (day != null) 'day': day,
      if (packageName != null) 'package_name': packageName,
      if (foregroundMillis != null) 'foreground_millis': foregroundMillis,
    });
  }

  UsageStatDailiesCompanion copyWith(
      {Value<int>? id,
      Value<String>? day,
      Value<String>? packageName,
      Value<int>? foregroundMillis}) {
    return UsageStatDailiesCompanion(
      id: id ?? this.id,
      day: day ?? this.day,
      packageName: packageName ?? this.packageName,
      foregroundMillis: foregroundMillis ?? this.foregroundMillis,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (foregroundMillis.present) {
      map['foreground_millis'] = Variable<int>(foregroundMillis.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsageStatDailiesCompanion(')
          ..write('id: $id, ')
          ..write('day: $day, ')
          ..write('packageName: $packageName, ')
          ..write('foregroundMillis: $foregroundMillis')
          ..write(')'))
        .toString();
  }
}

class $AppRulesTable extends AppRules with TableInfo<$AppRulesTable, AppRule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _packageNameMeta =
      const VerificationMeta('packageName');
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
      'package_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _ruleTypeMeta =
      const VerificationMeta('ruleType');
  @override
  late final GeneratedColumn<String> ruleType = GeneratedColumn<String>(
      'rule_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dailyLimitMillisMeta =
      const VerificationMeta('dailyLimitMillis');
  @override
  late final GeneratedColumn<int> dailyLimitMillis = GeneratedColumn<int>(
      'daily_limit_millis', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns =>
      [id, packageName, ruleType, dailyLimitMillis, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_rule';
  @override
  VerificationContext validateIntegrity(Insertable<AppRule> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('package_name')) {
      context.handle(
          _packageNameMeta,
          packageName.isAcceptableOrUnknown(
              data['package_name']!, _packageNameMeta));
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('rule_type')) {
      context.handle(_ruleTypeMeta,
          ruleType.isAcceptableOrUnknown(data['rule_type']!, _ruleTypeMeta));
    } else if (isInserting) {
      context.missing(_ruleTypeMeta);
    }
    if (data.containsKey('daily_limit_millis')) {
      context.handle(
          _dailyLimitMillisMeta,
          dailyLimitMillis.isAcceptableOrUnknown(
              data['daily_limit_millis']!, _dailyLimitMillisMeta));
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppRule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppRule(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      packageName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}package_name'])!,
      ruleType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rule_type'])!,
      dailyLimitMillis: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}daily_limit_millis']),
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
    );
  }

  @override
  $AppRulesTable createAlias(String alias) {
    return $AppRulesTable(attachedDatabase, alias);
  }
}

class AppRule extends DataClass implements Insertable<AppRule> {
  final int id;

  /// 应用包名
  final String packageName;

  /// 规则类型：whitelist / blacklist / limit
  final String ruleType;

  /// 限时规则的每日上限毫秒（ruleType=limit 时使用）
  final int? dailyLimitMillis;

  /// 是否启用
  final bool enabled;
  const AppRule(
      {required this.id,
      required this.packageName,
      required this.ruleType,
      this.dailyLimitMillis,
      required this.enabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['package_name'] = Variable<String>(packageName);
    map['rule_type'] = Variable<String>(ruleType);
    if (!nullToAbsent || dailyLimitMillis != null) {
      map['daily_limit_millis'] = Variable<int>(dailyLimitMillis);
    }
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  AppRulesCompanion toCompanion(bool nullToAbsent) {
    return AppRulesCompanion(
      id: Value(id),
      packageName: Value(packageName),
      ruleType: Value(ruleType),
      dailyLimitMillis: dailyLimitMillis == null && nullToAbsent
          ? const Value.absent()
          : Value(dailyLimitMillis),
      enabled: Value(enabled),
    );
  }

  factory AppRule.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppRule(
      id: serializer.fromJson<int>(json['id']),
      packageName: serializer.fromJson<String>(json['packageName']),
      ruleType: serializer.fromJson<String>(json['ruleType']),
      dailyLimitMillis: serializer.fromJson<int?>(json['dailyLimitMillis']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'packageName': serializer.toJson<String>(packageName),
      'ruleType': serializer.toJson<String>(ruleType),
      'dailyLimitMillis': serializer.toJson<int?>(dailyLimitMillis),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  AppRule copyWith(
          {int? id,
          String? packageName,
          String? ruleType,
          Value<int?> dailyLimitMillis = const Value.absent(),
          bool? enabled}) =>
      AppRule(
        id: id ?? this.id,
        packageName: packageName ?? this.packageName,
        ruleType: ruleType ?? this.ruleType,
        dailyLimitMillis: dailyLimitMillis.present
            ? dailyLimitMillis.value
            : this.dailyLimitMillis,
        enabled: enabled ?? this.enabled,
      );
  AppRule copyWithCompanion(AppRulesCompanion data) {
    return AppRule(
      id: data.id.present ? data.id.value : this.id,
      packageName:
          data.packageName.present ? data.packageName.value : this.packageName,
      ruleType: data.ruleType.present ? data.ruleType.value : this.ruleType,
      dailyLimitMillis: data.dailyLimitMillis.present
          ? data.dailyLimitMillis.value
          : this.dailyLimitMillis,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppRule(')
          ..write('id: $id, ')
          ..write('packageName: $packageName, ')
          ..write('ruleType: $ruleType, ')
          ..write('dailyLimitMillis: $dailyLimitMillis, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, packageName, ruleType, dailyLimitMillis, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppRule &&
          other.id == this.id &&
          other.packageName == this.packageName &&
          other.ruleType == this.ruleType &&
          other.dailyLimitMillis == this.dailyLimitMillis &&
          other.enabled == this.enabled);
}

class AppRulesCompanion extends UpdateCompanion<AppRule> {
  final Value<int> id;
  final Value<String> packageName;
  final Value<String> ruleType;
  final Value<int?> dailyLimitMillis;
  final Value<bool> enabled;
  const AppRulesCompanion({
    this.id = const Value.absent(),
    this.packageName = const Value.absent(),
    this.ruleType = const Value.absent(),
    this.dailyLimitMillis = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  AppRulesCompanion.insert({
    this.id = const Value.absent(),
    required String packageName,
    required String ruleType,
    this.dailyLimitMillis = const Value.absent(),
    this.enabled = const Value.absent(),
  })  : packageName = Value(packageName),
        ruleType = Value(ruleType);
  static Insertable<AppRule> custom({
    Expression<int>? id,
    Expression<String>? packageName,
    Expression<String>? ruleType,
    Expression<int>? dailyLimitMillis,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (packageName != null) 'package_name': packageName,
      if (ruleType != null) 'rule_type': ruleType,
      if (dailyLimitMillis != null) 'daily_limit_millis': dailyLimitMillis,
      if (enabled != null) 'enabled': enabled,
    });
  }

  AppRulesCompanion copyWith(
      {Value<int>? id,
      Value<String>? packageName,
      Value<String>? ruleType,
      Value<int?>? dailyLimitMillis,
      Value<bool>? enabled}) {
    return AppRulesCompanion(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      ruleType: ruleType ?? this.ruleType,
      dailyLimitMillis: dailyLimitMillis ?? this.dailyLimitMillis,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (ruleType.present) {
      map['rule_type'] = Variable<String>(ruleType.value);
    }
    if (dailyLimitMillis.present) {
      map['daily_limit_millis'] = Variable<int>(dailyLimitMillis.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppRulesCompanion(')
          ..write('id: $id, ')
          ..write('packageName: $packageName, ')
          ..write('ruleType: $ruleType, ')
          ..write('dailyLimitMillis: $dailyLimitMillis, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

class $GoalsTable extends Goals with TableInfo<$GoalsTable, Goal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _targetValueMeta =
      const VerificationMeta('targetValue');
  @override
  late final GeneratedColumn<int> targetValue = GeneratedColumn<int>(
      'target_value', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _archivedMeta =
      const VerificationMeta('archived');
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
      'archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, type, targetValue, createdAt, archived];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goal';
  @override
  VerificationContext validateIntegrity(Insertable<Goal> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('target_value')) {
      context.handle(
          _targetValueMeta,
          targetValue.isAcceptableOrUnknown(
              data['target_value']!, _targetValueMeta));
    } else if (isInserting) {
      context.missing(_targetValueMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('archived')) {
      context.handle(_archivedMeta,
          archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Goal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Goal(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      targetValue: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}target_value'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      archived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}archived'])!,
    );
  }

  @override
  $GoalsTable createAlias(String alias) {
    return $GoalsTable(attachedDatabase, alias);
  }
}

class Goal extends DataClass implements Insertable<Goal> {
  final int id;

  /// 目标标题，如「每天专注 2 小时」
  final String title;

  /// 目标类型：dailyFocus / weeklyFocus / streak
  final String type;

  /// 目标值（毫秒或天数，按 type 解释）
  final int targetValue;
  final int createdAt;

  /// 归档（软删除）
  final bool archived;
  const Goal(
      {required this.id,
      required this.title,
      required this.type,
      required this.targetValue,
      required this.createdAt,
      required this.archived});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['type'] = Variable<String>(type);
    map['target_value'] = Variable<int>(targetValue);
    map['created_at'] = Variable<int>(createdAt);
    map['archived'] = Variable<bool>(archived);
    return map;
  }

  GoalsCompanion toCompanion(bool nullToAbsent) {
    return GoalsCompanion(
      id: Value(id),
      title: Value(title),
      type: Value(type),
      targetValue: Value(targetValue),
      createdAt: Value(createdAt),
      archived: Value(archived),
    );
  }

  factory Goal.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Goal(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      type: serializer.fromJson<String>(json['type']),
      targetValue: serializer.fromJson<int>(json['targetValue']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      archived: serializer.fromJson<bool>(json['archived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'type': serializer.toJson<String>(type),
      'targetValue': serializer.toJson<int>(targetValue),
      'createdAt': serializer.toJson<int>(createdAt),
      'archived': serializer.toJson<bool>(archived),
    };
  }

  Goal copyWith(
          {int? id,
          String? title,
          String? type,
          int? targetValue,
          int? createdAt,
          bool? archived}) =>
      Goal(
        id: id ?? this.id,
        title: title ?? this.title,
        type: type ?? this.type,
        targetValue: targetValue ?? this.targetValue,
        createdAt: createdAt ?? this.createdAt,
        archived: archived ?? this.archived,
      );
  Goal copyWithCompanion(GoalsCompanion data) {
    return Goal(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      type: data.type.present ? data.type.value : this.type,
      targetValue:
          data.targetValue.present ? data.targetValue.value : this.targetValue,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      archived: data.archived.present ? data.archived.value : this.archived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Goal(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('type: $type, ')
          ..write('targetValue: $targetValue, ')
          ..write('createdAt: $createdAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, type, targetValue, createdAt, archived);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Goal &&
          other.id == this.id &&
          other.title == this.title &&
          other.type == this.type &&
          other.targetValue == this.targetValue &&
          other.createdAt == this.createdAt &&
          other.archived == this.archived);
}

class GoalsCompanion extends UpdateCompanion<Goal> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> type;
  final Value<int> targetValue;
  final Value<int> createdAt;
  final Value<bool> archived;
  const GoalsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.type = const Value.absent(),
    this.targetValue = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.archived = const Value.absent(),
  });
  GoalsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String type,
    required int targetValue,
    required int createdAt,
    this.archived = const Value.absent(),
  })  : title = Value(title),
        type = Value(type),
        targetValue = Value(targetValue),
        createdAt = Value(createdAt);
  static Insertable<Goal> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? type,
    Expression<int>? targetValue,
    Expression<int>? createdAt,
    Expression<bool>? archived,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (type != null) 'type': type,
      if (targetValue != null) 'target_value': targetValue,
      if (createdAt != null) 'created_at': createdAt,
      if (archived != null) 'archived': archived,
    });
  }

  GoalsCompanion copyWith(
      {Value<int>? id,
      Value<String>? title,
      Value<String>? type,
      Value<int>? targetValue,
      Value<int>? createdAt,
      Value<bool>? archived}) {
    return GoalsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      targetValue: targetValue ?? this.targetValue,
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (targetValue.present) {
      map['target_value'] = Variable<int>(targetValue.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('type: $type, ')
          ..write('targetValue: $targetValue, ')
          ..write('createdAt: $createdAt, ')
          ..write('archived: $archived')
          ..write(')'))
        .toString();
  }
}

class $KeyMapPresetsTable extends KeyMapPresets
    with TableInfo<$KeyMapPresetsTable, KeyMapPreset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyMapPresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _mappingJsonMeta =
      const VerificationMeta('mappingJson');
  @override
  late final GeneratedColumn<String> mappingJson = GeneratedColumn<String>(
      'mapping_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, isActive, mappingJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'key_map_preset';
  @override
  VerificationContext validateIntegrity(Insertable<KeyMapPreset> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('mapping_json')) {
      context.handle(
          _mappingJsonMeta,
          mappingJson.isAcceptableOrUnknown(
              data['mapping_json']!, _mappingJsonMeta));
    } else if (isInserting) {
      context.missing(_mappingJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KeyMapPreset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyMapPreset(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      mappingJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mapping_json'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $KeyMapPresetsTable createAlias(String alias) {
    return $KeyMapPresetsTable(attachedDatabase, alias);
  }
}

class KeyMapPreset extends DataClass implements Insertable<KeyMapPreset> {
  final int id;

  /// 预设名称
  final String name;

  /// 是否为当前生效预设
  final bool isActive;

  /// KeyMapConfig.toJson() 的 JSON 字符串
  final String mappingJson;
  final int updatedAt;
  const KeyMapPreset(
      {required this.id,
      required this.name,
      required this.isActive,
      required this.mappingJson,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['is_active'] = Variable<bool>(isActive);
    map['mapping_json'] = Variable<String>(mappingJson);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  KeyMapPresetsCompanion toCompanion(bool nullToAbsent) {
    return KeyMapPresetsCompanion(
      id: Value(id),
      name: Value(name),
      isActive: Value(isActive),
      mappingJson: Value(mappingJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory KeyMapPreset.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeyMapPreset(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      mappingJson: serializer.fromJson<String>(json['mappingJson']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'isActive': serializer.toJson<bool>(isActive),
      'mappingJson': serializer.toJson<String>(mappingJson),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  KeyMapPreset copyWith(
          {int? id,
          String? name,
          bool? isActive,
          String? mappingJson,
          int? updatedAt}) =>
      KeyMapPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        isActive: isActive ?? this.isActive,
        mappingJson: mappingJson ?? this.mappingJson,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  KeyMapPreset copyWithCompanion(KeyMapPresetsCompanion data) {
    return KeyMapPreset(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      mappingJson:
          data.mappingJson.present ? data.mappingJson.value : this.mappingJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeyMapPreset(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('mappingJson: $mappingJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isActive, mappingJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KeyMapPreset &&
          other.id == this.id &&
          other.name == this.name &&
          other.isActive == this.isActive &&
          other.mappingJson == this.mappingJson &&
          other.updatedAt == this.updatedAt);
}

class KeyMapPresetsCompanion extends UpdateCompanion<KeyMapPreset> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> isActive;
  final Value<String> mappingJson;
  final Value<int> updatedAt;
  const KeyMapPresetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isActive = const Value.absent(),
    this.mappingJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  KeyMapPresetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.isActive = const Value.absent(),
    required String mappingJson,
    required int updatedAt,
  })  : name = Value(name),
        mappingJson = Value(mappingJson),
        updatedAt = Value(updatedAt);
  static Insertable<KeyMapPreset> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? isActive,
    Expression<String>? mappingJson,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isActive != null) 'is_active': isActive,
      if (mappingJson != null) 'mapping_json': mappingJson,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  KeyMapPresetsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<bool>? isActive,
      Value<String>? mappingJson,
      Value<int>? updatedAt}) {
    return KeyMapPresetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      mappingJson: mappingJson ?? this.mappingJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (mappingJson.present) {
      map['mapping_json'] = Variable<String>(mappingJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyMapPresetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isActive: $isActive, ')
          ..write('mappingJson: $mappingJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FocusSessionsTable focusSessions = $FocusSessionsTable(this);
  late final $UsageStatDailiesTable usageStatDailies =
      $UsageStatDailiesTable(this);
  late final $AppRulesTable appRules = $AppRulesTable(this);
  late final $GoalsTable goals = $GoalsTable(this);
  late final $KeyMapPresetsTable keyMapPresets = $KeyMapPresetsTable(this);
  late final FocusSessionDao focusSessionDao =
      FocusSessionDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [focusSessions, usageStatDailies, appRules, goals, keyMapPresets];
}

typedef $$FocusSessionsTableCreateCompanionBuilder = FocusSessionsCompanion
    Function({
  Value<int> id,
  required int startAt,
  Value<int?> endAt,
  required int plannedFocusMillis,
  required int actualFocusMillis,
  Value<int> rounds,
  Value<bool> completed,
  Value<String> mode,
  Value<String?> marksJson,
  Value<String?> intervalsJson,
  Value<String?> pausesJson,
  Value<String?> tag,
});
typedef $$FocusSessionsTableUpdateCompanionBuilder = FocusSessionsCompanion
    Function({
  Value<int> id,
  Value<int> startAt,
  Value<int?> endAt,
  Value<int> plannedFocusMillis,
  Value<int> actualFocusMillis,
  Value<int> rounds,
  Value<bool> completed,
  Value<String> mode,
  Value<String?> marksJson,
  Value<String?> intervalsJson,
  Value<String?> pausesJson,
  Value<String?> tag,
});

class $$FocusSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startAt => $composableBuilder(
      column: $table.startAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endAt => $composableBuilder(
      column: $table.endAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get plannedFocusMillis => $composableBuilder(
      column: $table.plannedFocusMillis,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get actualFocusMillis => $composableBuilder(
      column: $table.actualFocusMillis,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rounds => $composableBuilder(
      column: $table.rounds, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get marksJson => $composableBuilder(
      column: $table.marksJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get intervalsJson => $composableBuilder(
      column: $table.intervalsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pausesJson => $composableBuilder(
      column: $table.pausesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tag => $composableBuilder(
      column: $table.tag, builder: (column) => ColumnFilters(column));
}

class $$FocusSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startAt => $composableBuilder(
      column: $table.startAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endAt => $composableBuilder(
      column: $table.endAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get plannedFocusMillis => $composableBuilder(
      column: $table.plannedFocusMillis,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get actualFocusMillis => $composableBuilder(
      column: $table.actualFocusMillis,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rounds => $composableBuilder(
      column: $table.rounds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get marksJson => $composableBuilder(
      column: $table.marksJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get intervalsJson => $composableBuilder(
      column: $table.intervalsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pausesJson => $composableBuilder(
      column: $table.pausesJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tag => $composableBuilder(
      column: $table.tag, builder: (column) => ColumnOrderings(column));
}

class $$FocusSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FocusSessionsTable> {
  $$FocusSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<int> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<int> get plannedFocusMillis => $composableBuilder(
      column: $table.plannedFocusMillis, builder: (column) => column);

  GeneratedColumn<int> get actualFocusMillis => $composableBuilder(
      column: $table.actualFocusMillis, builder: (column) => column);

  GeneratedColumn<int> get rounds =>
      $composableBuilder(column: $table.rounds, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get marksJson =>
      $composableBuilder(column: $table.marksJson, builder: (column) => column);

  GeneratedColumn<String> get intervalsJson => $composableBuilder(
      column: $table.intervalsJson, builder: (column) => column);

  GeneratedColumn<String> get pausesJson => $composableBuilder(
      column: $table.pausesJson, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);
}

class $$FocusSessionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FocusSessionsTable,
    FocusSession,
    $$FocusSessionsTableFilterComposer,
    $$FocusSessionsTableOrderingComposer,
    $$FocusSessionsTableAnnotationComposer,
    $$FocusSessionsTableCreateCompanionBuilder,
    $$FocusSessionsTableUpdateCompanionBuilder,
    (
      FocusSession,
      BaseReferences<_$AppDatabase, $FocusSessionsTable, FocusSession>
    ),
    FocusSession,
    PrefetchHooks Function()> {
  $$FocusSessionsTableTableManager(_$AppDatabase db, $FocusSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FocusSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FocusSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FocusSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> startAt = const Value.absent(),
            Value<int?> endAt = const Value.absent(),
            Value<int> plannedFocusMillis = const Value.absent(),
            Value<int> actualFocusMillis = const Value.absent(),
            Value<int> rounds = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<String> mode = const Value.absent(),
            Value<String?> marksJson = const Value.absent(),
            Value<String?> intervalsJson = const Value.absent(),
            Value<String?> pausesJson = const Value.absent(),
            Value<String?> tag = const Value.absent(),
          }) =>
              FocusSessionsCompanion(
            id: id,
            startAt: startAt,
            endAt: endAt,
            plannedFocusMillis: plannedFocusMillis,
            actualFocusMillis: actualFocusMillis,
            rounds: rounds,
            completed: completed,
            mode: mode,
            marksJson: marksJson,
            intervalsJson: intervalsJson,
            pausesJson: pausesJson,
            tag: tag,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int startAt,
            Value<int?> endAt = const Value.absent(),
            required int plannedFocusMillis,
            required int actualFocusMillis,
            Value<int> rounds = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<String> mode = const Value.absent(),
            Value<String?> marksJson = const Value.absent(),
            Value<String?> intervalsJson = const Value.absent(),
            Value<String?> pausesJson = const Value.absent(),
            Value<String?> tag = const Value.absent(),
          }) =>
              FocusSessionsCompanion.insert(
            id: id,
            startAt: startAt,
            endAt: endAt,
            plannedFocusMillis: plannedFocusMillis,
            actualFocusMillis: actualFocusMillis,
            rounds: rounds,
            completed: completed,
            mode: mode,
            marksJson: marksJson,
            intervalsJson: intervalsJson,
            pausesJson: pausesJson,
            tag: tag,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FocusSessionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FocusSessionsTable,
    FocusSession,
    $$FocusSessionsTableFilterComposer,
    $$FocusSessionsTableOrderingComposer,
    $$FocusSessionsTableAnnotationComposer,
    $$FocusSessionsTableCreateCompanionBuilder,
    $$FocusSessionsTableUpdateCompanionBuilder,
    (
      FocusSession,
      BaseReferences<_$AppDatabase, $FocusSessionsTable, FocusSession>
    ),
    FocusSession,
    PrefetchHooks Function()>;
typedef $$UsageStatDailiesTableCreateCompanionBuilder
    = UsageStatDailiesCompanion Function({
  Value<int> id,
  required String day,
  required String packageName,
  required int foregroundMillis,
});
typedef $$UsageStatDailiesTableUpdateCompanionBuilder
    = UsageStatDailiesCompanion Function({
  Value<int> id,
  Value<String> day,
  Value<String> packageName,
  Value<int> foregroundMillis,
});

class $$UsageStatDailiesTableFilterComposer
    extends Composer<_$AppDatabase, $UsageStatDailiesTable> {
  $$UsageStatDailiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get foregroundMillis => $composableBuilder(
      column: $table.foregroundMillis,
      builder: (column) => ColumnFilters(column));
}

class $$UsageStatDailiesTableOrderingComposer
    extends Composer<_$AppDatabase, $UsageStatDailiesTable> {
  $$UsageStatDailiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get day => $composableBuilder(
      column: $table.day, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get foregroundMillis => $composableBuilder(
      column: $table.foregroundMillis,
      builder: (column) => ColumnOrderings(column));
}

class $$UsageStatDailiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsageStatDailiesTable> {
  $$UsageStatDailiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => column);

  GeneratedColumn<int> get foregroundMillis => $composableBuilder(
      column: $table.foregroundMillis, builder: (column) => column);
}

class $$UsageStatDailiesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UsageStatDailiesTable,
    UsageStatDaily,
    $$UsageStatDailiesTableFilterComposer,
    $$UsageStatDailiesTableOrderingComposer,
    $$UsageStatDailiesTableAnnotationComposer,
    $$UsageStatDailiesTableCreateCompanionBuilder,
    $$UsageStatDailiesTableUpdateCompanionBuilder,
    (
      UsageStatDaily,
      BaseReferences<_$AppDatabase, $UsageStatDailiesTable, UsageStatDaily>
    ),
    UsageStatDaily,
    PrefetchHooks Function()> {
  $$UsageStatDailiesTableTableManager(
      _$AppDatabase db, $UsageStatDailiesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsageStatDailiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsageStatDailiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsageStatDailiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> day = const Value.absent(),
            Value<String> packageName = const Value.absent(),
            Value<int> foregroundMillis = const Value.absent(),
          }) =>
              UsageStatDailiesCompanion(
            id: id,
            day: day,
            packageName: packageName,
            foregroundMillis: foregroundMillis,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String day,
            required String packageName,
            required int foregroundMillis,
          }) =>
              UsageStatDailiesCompanion.insert(
            id: id,
            day: day,
            packageName: packageName,
            foregroundMillis: foregroundMillis,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UsageStatDailiesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UsageStatDailiesTable,
    UsageStatDaily,
    $$UsageStatDailiesTableFilterComposer,
    $$UsageStatDailiesTableOrderingComposer,
    $$UsageStatDailiesTableAnnotationComposer,
    $$UsageStatDailiesTableCreateCompanionBuilder,
    $$UsageStatDailiesTableUpdateCompanionBuilder,
    (
      UsageStatDaily,
      BaseReferences<_$AppDatabase, $UsageStatDailiesTable, UsageStatDaily>
    ),
    UsageStatDaily,
    PrefetchHooks Function()>;
typedef $$AppRulesTableCreateCompanionBuilder = AppRulesCompanion Function({
  Value<int> id,
  required String packageName,
  required String ruleType,
  Value<int?> dailyLimitMillis,
  Value<bool> enabled,
});
typedef $$AppRulesTableUpdateCompanionBuilder = AppRulesCompanion Function({
  Value<int> id,
  Value<String> packageName,
  Value<String> ruleType,
  Value<int?> dailyLimitMillis,
  Value<bool> enabled,
});

class $$AppRulesTableFilterComposer
    extends Composer<_$AppDatabase, $AppRulesTable> {
  $$AppRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ruleType => $composableBuilder(
      column: $table.ruleType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dailyLimitMillis => $composableBuilder(
      column: $table.dailyLimitMillis,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));
}

class $$AppRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppRulesTable> {
  $$AppRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ruleType => $composableBuilder(
      column: $table.ruleType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dailyLimitMillis => $composableBuilder(
      column: $table.dailyLimitMillis,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));
}

class $$AppRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppRulesTable> {
  $$AppRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
      column: $table.packageName, builder: (column) => column);

  GeneratedColumn<String> get ruleType =>
      $composableBuilder(column: $table.ruleType, builder: (column) => column);

  GeneratedColumn<int> get dailyLimitMillis => $composableBuilder(
      column: $table.dailyLimitMillis, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$AppRulesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppRulesTable,
    AppRule,
    $$AppRulesTableFilterComposer,
    $$AppRulesTableOrderingComposer,
    $$AppRulesTableAnnotationComposer,
    $$AppRulesTableCreateCompanionBuilder,
    $$AppRulesTableUpdateCompanionBuilder,
    (AppRule, BaseReferences<_$AppDatabase, $AppRulesTable, AppRule>),
    AppRule,
    PrefetchHooks Function()> {
  $$AppRulesTableTableManager(_$AppDatabase db, $AppRulesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> packageName = const Value.absent(),
            Value<String> ruleType = const Value.absent(),
            Value<int?> dailyLimitMillis = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
          }) =>
              AppRulesCompanion(
            id: id,
            packageName: packageName,
            ruleType: ruleType,
            dailyLimitMillis: dailyLimitMillis,
            enabled: enabled,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String packageName,
            required String ruleType,
            Value<int?> dailyLimitMillis = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
          }) =>
              AppRulesCompanion.insert(
            id: id,
            packageName: packageName,
            ruleType: ruleType,
            dailyLimitMillis: dailyLimitMillis,
            enabled: enabled,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppRulesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AppRulesTable,
    AppRule,
    $$AppRulesTableFilterComposer,
    $$AppRulesTableOrderingComposer,
    $$AppRulesTableAnnotationComposer,
    $$AppRulesTableCreateCompanionBuilder,
    $$AppRulesTableUpdateCompanionBuilder,
    (AppRule, BaseReferences<_$AppDatabase, $AppRulesTable, AppRule>),
    AppRule,
    PrefetchHooks Function()>;
typedef $$GoalsTableCreateCompanionBuilder = GoalsCompanion Function({
  Value<int> id,
  required String title,
  required String type,
  required int targetValue,
  required int createdAt,
  Value<bool> archived,
});
typedef $$GoalsTableUpdateCompanionBuilder = GoalsCompanion Function({
  Value<int> id,
  Value<String> title,
  Value<String> type,
  Value<int> targetValue,
  Value<int> createdAt,
  Value<bool> archived,
});

class $$GoalsTableFilterComposer extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get targetValue => $composableBuilder(
      column: $table.targetValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get archived => $composableBuilder(
      column: $table.archived, builder: (column) => ColumnFilters(column));
}

class $$GoalsTableOrderingComposer
    extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get targetValue => $composableBuilder(
      column: $table.targetValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get archived => $composableBuilder(
      column: $table.archived, builder: (column) => ColumnOrderings(column));
}

class $$GoalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get targetValue => $composableBuilder(
      column: $table.targetValue, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);
}

class $$GoalsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $GoalsTable,
    Goal,
    $$GoalsTableFilterComposer,
    $$GoalsTableOrderingComposer,
    $$GoalsTableAnnotationComposer,
    $$GoalsTableCreateCompanionBuilder,
    $$GoalsTableUpdateCompanionBuilder,
    (Goal, BaseReferences<_$AppDatabase, $GoalsTable, Goal>),
    Goal,
    PrefetchHooks Function()> {
  $$GoalsTableTableManager(_$AppDatabase db, $GoalsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> targetValue = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<bool> archived = const Value.absent(),
          }) =>
              GoalsCompanion(
            id: id,
            title: title,
            type: type,
            targetValue: targetValue,
            createdAt: createdAt,
            archived: archived,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String title,
            required String type,
            required int targetValue,
            required int createdAt,
            Value<bool> archived = const Value.absent(),
          }) =>
              GoalsCompanion.insert(
            id: id,
            title: title,
            type: type,
            targetValue: targetValue,
            createdAt: createdAt,
            archived: archived,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$GoalsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $GoalsTable,
    Goal,
    $$GoalsTableFilterComposer,
    $$GoalsTableOrderingComposer,
    $$GoalsTableAnnotationComposer,
    $$GoalsTableCreateCompanionBuilder,
    $$GoalsTableUpdateCompanionBuilder,
    (Goal, BaseReferences<_$AppDatabase, $GoalsTable, Goal>),
    Goal,
    PrefetchHooks Function()>;
typedef $$KeyMapPresetsTableCreateCompanionBuilder = KeyMapPresetsCompanion
    Function({
  Value<int> id,
  required String name,
  Value<bool> isActive,
  required String mappingJson,
  required int updatedAt,
});
typedef $$KeyMapPresetsTableUpdateCompanionBuilder = KeyMapPresetsCompanion
    Function({
  Value<int> id,
  Value<String> name,
  Value<bool> isActive,
  Value<String> mappingJson,
  Value<int> updatedAt,
});

class $$KeyMapPresetsTableFilterComposer
    extends Composer<_$AppDatabase, $KeyMapPresetsTable> {
  $$KeyMapPresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mappingJson => $composableBuilder(
      column: $table.mappingJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$KeyMapPresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $KeyMapPresetsTable> {
  $$KeyMapPresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mappingJson => $composableBuilder(
      column: $table.mappingJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$KeyMapPresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KeyMapPresetsTable> {
  $$KeyMapPresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get mappingJson => $composableBuilder(
      column: $table.mappingJson, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KeyMapPresetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KeyMapPresetsTable,
    KeyMapPreset,
    $$KeyMapPresetsTableFilterComposer,
    $$KeyMapPresetsTableOrderingComposer,
    $$KeyMapPresetsTableAnnotationComposer,
    $$KeyMapPresetsTableCreateCompanionBuilder,
    $$KeyMapPresetsTableUpdateCompanionBuilder,
    (
      KeyMapPreset,
      BaseReferences<_$AppDatabase, $KeyMapPresetsTable, KeyMapPreset>
    ),
    KeyMapPreset,
    PrefetchHooks Function()> {
  $$KeyMapPresetsTableTableManager(_$AppDatabase db, $KeyMapPresetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeyMapPresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeyMapPresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeyMapPresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<String> mappingJson = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
          }) =>
              KeyMapPresetsCompanion(
            id: id,
            name: name,
            isActive: isActive,
            mappingJson: mappingJson,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<bool> isActive = const Value.absent(),
            required String mappingJson,
            required int updatedAt,
          }) =>
              KeyMapPresetsCompanion.insert(
            id: id,
            name: name,
            isActive: isActive,
            mappingJson: mappingJson,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KeyMapPresetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KeyMapPresetsTable,
    KeyMapPreset,
    $$KeyMapPresetsTableFilterComposer,
    $$KeyMapPresetsTableOrderingComposer,
    $$KeyMapPresetsTableAnnotationComposer,
    $$KeyMapPresetsTableCreateCompanionBuilder,
    $$KeyMapPresetsTableUpdateCompanionBuilder,
    (
      KeyMapPreset,
      BaseReferences<_$AppDatabase, $KeyMapPresetsTable, KeyMapPreset>
    ),
    KeyMapPreset,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FocusSessionsTableTableManager get focusSessions =>
      $$FocusSessionsTableTableManager(_db, _db.focusSessions);
  $$UsageStatDailiesTableTableManager get usageStatDailies =>
      $$UsageStatDailiesTableTableManager(_db, _db.usageStatDailies);
  $$AppRulesTableTableManager get appRules =>
      $$AppRulesTableTableManager(_db, _db.appRules);
  $$GoalsTableTableManager get goals =>
      $$GoalsTableTableManager(_db, _db.goals);
  $$KeyMapPresetsTableTableManager get keyMapPresets =>
      $$KeyMapPresetsTableTableManager(_db, _db.keyMapPresets);
}
