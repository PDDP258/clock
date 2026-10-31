/// 背景图库的清单解析、池策略与随机调度测试。
///
/// 最后一组「产物一致性」是本轮最关键的回归：它把**脚本生成的
/// `assets/backgrounds/manifest.json`** 与 **Dart 侧的规则实现** 对起来，
/// 一旦两边口径漂移（改了阈值、改了目标尺寸、判定用了浮点）就红——
/// 这正是 PD 在意的「验收看产物，不只看编译通过」。
library;

import 'dart:math';

import 'package:ai_clock/core/background/bg_fit.dart';
import 'package:ai_clock/core/background/bg_image.dart';
import 'package:ai_clock/features/backgrounds/application/background_controller.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// 一份最小可用清单。
String _manifest(List<Map<String, Object?>> images) {
  final entries = images
      .map((e) => '{'
          '"id":"${e['id']}",'
          '"width":${e['width']},"height":${e['height']},'
          '"srcWidth":${e['srcWidth'] ?? e['width']},'
          '"srcHeight":${e['srcHeight'] ?? e['height']},'
          '"source":"${e['source'] ?? ''}"'
          '}')
      .join(',');
  return '{"schema":"$kBgLibrarySchemaId","images":[$entries]}';
}

BgLibrary _decode(String raw, {bool bundled = true}) => BgLibrary.decode(
      raw,
      bundled: bundled,
      refOf: (id, entry) => bundled
          ? (entry['asset'] as String? ?? 'assets/backgrounds/$id.webp')
          : '/tmp/$id.webp',
    );

/// 两张规则 1、三张规则 2 的测试池（阈值 1.3）。
///
/// 权重（铺满 1280×720 后的纵向溢出）：
/// bg_tall 1136 / bg_square 560 / bg_shallow 280；规则 1 的两张恒为 0。
BgLibrary _fixture() => _decode(_manifest([
      {'id': 'bg_wide', 'width': 2160, 'height': 1080}, // 规则 1（2.0）
      {'id': 'bg_wide2', 'width': 1920, 'height': 1080}, // 规则 1（1.778）
      {'id': 'bg_tall', 'width': 1280, 'height': 1856}, // 规则 2（0.69）
      {'id': 'bg_square', 'width': 1280, 'height': 1280}, // 规则 2（1.0）
      {'id': 'bg_shallow', 'width': 1280, 'height': 1000}, // 规则 2（1.28）
    ]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BgLibrary.decode：容错解析', () {
    test('合法清单解析出条目，规则与分类按尺寸现算', () {
      final lib = _decode(_manifest([
        {'id': 'bg_a', 'width': 2160, 'height': 1080},
        {'id': 'bg_b', 'width': 1280, 'height': 1856},
      ]));
      expect(lib.length, 2);
      expect(lib.images[0].rule, BgFitRule.fillHeight);
      expect(lib.images[0].category, BgCategory.ultraWide);
      expect(lib.images[1].rule, BgFitRule.fillWidth);
      expect(lib.images[1].category, BgCategory.portrait);
      expect(lib.images[1].followsScroll, isTrue);
      expect(lib.images[0].ref, 'assets/backgrounds/bg_a.webp');
    });

    test('JSON 坏了整份作废（返回空池，渲染层退纯色）', () {
      expect(_decode('{不是 json').isEmpty, isTrue);
      expect(_decode('[]').isEmpty, isTrue);
      expect(_decode('{"schema":"x"}').isEmpty, isTrue);
      expect(_decode('{"images":"nope"}').isEmpty, isTrue);
    });

    test('单条目坏只丢这一条，其余照常可用', () {
      final lib = _decode('{"images":['
          '{"id":"bg_ok","width":2160,"height":1080},'
          '{"id":"","width":100,"height":100},'
          '{"width":100,"height":100},'
          '{"id":"bg_zero","width":0,"height":100},'
          '{"id":"bg_str","width":"1280","height":"1856"},'
          '"字符串不是对象",'
          '{"id":"bg_tail","width":1280,"height":900}'
          ']}');
      expect([for (final i in lib.images) i.id],
          ['bg_ok', 'bg_str', 'bg_tail']);
      // 字符串数字要能吃进来（外部程序手写清单不保证类型）
      expect(lib.images[1].width, 1280);
    });

    test('重复 id 只留第一条（内置先于用户时内置生效）', () {
      final lib = _decode(_manifest([
        {'id': 'bg_dup', 'width': 2160, 'height': 1080},
        {'id': 'bg_dup', 'width': 1280, 'height': 1856},
      ]));
      expect(lib.length, 1);
      expect(lib.images.single.rule, BgFitRule.fillHeight);
    });
  });

  group('BgCategory（阈值 1.3）', () {
    test('按尺寸判定三分类', () {
      expect(BgCategory.of(2160, 1080), BgCategory.ultraWide);
      // 1.42 ≥ 1.3 → 归 A（阈值调参前这里是 B）
      expect(BgCategory.of(1280, 900), BgCategory.ultraWide);
      // 1:1 与 1.28 都是横构图 B
      expect(BgCategory.of(1280, 1280), BgCategory.landscape);
      expect(BgCategory.of(1280, 1000), BgCategory.landscape);
      expect(BgCategory.of(1024, 2336), BgCategory.portrait);
    });

    test('清单字段认不出时回退按尺寸判（不信任字段）', () {
      expect(BgCategory.fromManifest('A-规则1·宽（≥1.3）', 1280, 1856),
          BgCategory.ultraWide);
      expect(BgCategory.fromManifest('随便什么', 1280, 1856),
          BgCategory.portrait);
      expect(BgCategory.fromManifest(null, 2160, 1080), BgCategory.ultraWide);
    });

    test('非法尺寸不抛', () {
      expect(BgCategory.of(0, 0), BgCategory.portrait);
    });
  });

  group('BgLibrary：合并与分池', () {
    test('merge 去重且内置在前', () {
      final bundled = _decode(_manifest([
        {'id': 'bg_a', 'width': 2160, 'height': 1080},
        {'id': 'bg_b', 'width': 1280, 'height': 1856},
      ]));
      final user = _decode(
          _manifest([
            {'id': 'u_x', 'width': 1280, 'height': 2000},
            {'id': 'bg_b', 'width': 100, 'height': 100},
          ]),
          bundled: false);
      final merged = BgLibrary.merge(bundled, user);
      expect([for (final i in merged.images) i.id], ['bg_a', 'bg_b', 'u_x']);
      expect(merged.images[1].bundled, isTrue); // 撞号时内置赢
    });

    test('分池：规则 2 池 / 规则 1 池', () {
      final lib = _fixture();
      expect([for (final i in lib.scrollablePool) i.id],
          ['bg_tall', 'bg_square', 'bg_shallow']);
      expect([for (final i in lib.fixedPool) i.id], ['bg_wide', 'bg_wide2']);
      expect(lib.scrollablePool.length + lib.fixedPool.length, lib.length);
    });

    test('encode 往返：字段守恒', () {
      final lib = _fixture();
      final again = _decode(lib.encode());
      expect(again.length, lib.length);
      for (var i = 0; i < lib.length; i++) {
        expect(again.images[i].id, lib.images[i].id);
        expect(again.images[i].width, lib.images[i].width);
        expect(again.images[i].height, lib.images[i].height);
        expect(again.images[i].rule, lib.images[i].rule);
      }
    });
  });

  group('随机间隔：5 分钟 ~ 5 小时', () {
    test('1 万次抽样都落在闭区间内', () {
      final random = Random(20260930);
      for (var i = 0; i < 10000; i++) {
        final d = bgRandomInterval(random);
        expect(d.inMinutes, greaterThanOrEqualTo(kBgMinIntervalMinutes));
        expect(d.inMinutes, lessThanOrEqualTo(kBgMaxIntervalMinutes));
      }
    });

    test('两端都取得到（不是写死的常量）', () {
      final seen = <int>{};
      final random = Random(7);
      for (var i = 0; i < 20000; i++) {
        seen.add(bgRandomInterval(random).inMinutes);
      }
      expect(seen.contains(kBgMinIntervalMinutes), isTrue);
      expect(seen.contains(kBgMaxIntervalMinutes), isTrue);
      expect(seen.length, greaterThan(250)); // 5..300 应基本铺满
    });

    test('常量就是需求里的 5 分钟与 5 小时', () {
      expect(kBgMinIntervalMinutes, 5);
      expect(kBgMaxIntervalMinutes, 5 * 60);
    });
  });

  group('抽完即放回：只排除当前这一张', () {
    test('相邻两次不会抽到同一张', () {
      final pool = _fixture().images;
      final random = Random(42);
      var current = 'bg_tall';
      for (var i = 0; i < 300; i++) {
        final next = bgPickImage(pool, random, excludeId: current)!;
        expect(next.id, isNot(current));
        current = next.id;
      }
    });

    test('抽过的那张下一次抽完就回到池里（不会越抽越少）', () {
      final pool = _fixture().images;
      final random = Random(2026);
      final seen = <String>{};
      var current = 'bg_tall';
      for (var i = 0; i < 300; i++) {
        current = bgPickImage(pool, random, excludeId: current)!.id;
        seen.add(current);
      }
      // 全部 5 张都还在循环里——包括最初被抽走的 bg_tall
      expect(seen.length, pool.length);
      expect(seen, contains('bg_tall'));
    });

    test('池只有 1 张时只能重复（不放回也没别的可抽）', () {
      final single = [_fixture().images.first];
      final random = Random(3);
      expect(bgPickImage(single, random, excludeId: single.first.id)!.id,
          single.first.id);
    });
  });

  group('各页抽图比例（2026-10-01 调参）', () {
    test('详细页：95% 规则 1 / 5% 规则 2，从不纯色', () {
      final lib = _fixture();
      final random = Random(20261001);
      const n = 20000;
      var fixed = 0;
      var scrollable = 0;
      for (var i = 0; i < n; i++) {
        final spec = bgRoll(lib, BgPage.statsDetail.policy, random);
        expect(spec.hasImage, isTrue); // solidProbability = 0
        if (spec.image!.followsScroll) {
          scrollable++;
        } else {
          fixed++;
        }
      }
      expect(fixed / n, closeTo(0.95, 0.02));
      expect(scrollable / n, closeTo(0.05, 0.02));
    });

    test('计时页：80% 规则 1 / 18% 纯色 / 2% 规则 2', () {
      final lib = _fixture();
      final random = Random(20261002);
      const n = 40000;
      var fixed = 0;
      var scrollable = 0;
      var solid = 0;
      for (var i = 0; i < n; i++) {
        final spec = bgRoll(lib, BgPage.focus.policy, random);
        if (spec.kind == BackdropKind.solid) {
          solid++;
        } else if (spec.image!.followsScroll) {
          scrollable++;
        } else {
          fixed++;
        }
      }
      expect(fixed / n, closeTo(0.80, 0.02));
      expect(solid / n, closeTo(0.18, 0.02));
      expect(scrollable / n, closeTo(0.02, 0.015));
    });

    test('使用统计页：全池均匀，5 张都抽得到', () {
      final lib = _fixture();
      final random = Random(9);
      final counts = <String, int>{};
      const n = 5000;
      for (var i = 0; i < n; i++) {
        final spec = bgRoll(lib, BgPage.stats.policy, random);
        expect(spec.hasImage, isTrue);
        counts[spec.image!.id] = (counts[spec.image!.id] ?? 0) + 1;
      }
      expect(counts.length, 5);
      for (final count in counts.values) {
        expect(count / n, closeTo(0.2, 0.05));
      }
    });

    test('命中池为空时换另一个池兜底（有图总比没图好）', () {
      final onlyTall = _decode(_manifest([
        {'id': 'bg_t', 'width': 1280, 'height': 1856},
      ]));
      // 只有规则 2 的图：计时页 80% 想抽规则 1 → 池空 → 兜底规则 2
      final random = Random(1);
      var images = 0;
      for (var i = 0; i < 500; i++) {
        final spec = bgRoll(onlyTall, BgPage.focus.policy, random);
        if (spec.hasImage) {
          images++;
          expect(spec.image!.id, 'bg_t');
        }
      }
      expect(images, greaterThan(300)); // 约 82% 是图，其余是纯色
      // 两个池都空 → 纯色
      expect(bgRoll(BgLibrary.empty, BgPage.stats.policy, Random(1)).kind,
          BackdropKind.solid);
    });
  });

  group('规则 2 池内加权：溢出越深越容易被抽中', () {
    test('权重 = 铺满屏幕后的纵向溢出量；规则 1 恒为 0', () {
      final lib = _fixture();
      final byId = {for (final i in lib.images) i.id: i};
      // bg_tall 1280x1856 → 溢出 1136；bg_square 1280x1280 → 560；
      // bg_shallow 1280x1000 → 280（阈值 1.3 下最浅的一档）
      expect(bgScrollDepthWeight(byId['bg_tall']!), 1136);
      expect(bgScrollDepthWeight(byId['bg_square']!), 560);
      expect(bgScrollDepthWeight(byId['bg_shallow']!), 280);
      expect(bgScrollDepthWeight(byId['bg_wide']!), 0); // 规则 1
    });

    test('统计分布：深图主导，浅图概率被压低但仍可能出现', () {
      final lib = _fixture();
      final random = Random(20261003);
      const n = 20000;
      final counts = <String, int>{};
      for (var i = 0; i < n; i++) {
        // 直接测规则 2 池内的加权抽取（详细页命中那 5% 时的行为）
        final picked = bgPickImage(lib.scrollablePool, random,
            weightOf: bgScrollDepthWeight)!;
        counts[picked.id] = (counts[picked.id] ?? 0) + 1;
      }
      final tall = counts['bg_tall']! / n;
      final square = counts['bg_square']! / n;
      final shallow = counts['bg_shallow']! / n;
      // 理论分布 1136 : 560 : 280 ≈ 57% : 28% : 14%
      expect(tall, greaterThan(0.50));
      expect(square, greaterThan(0.22));
      expect(tall, greaterThan(square));
      expect(square, greaterThan(shallow));
      expect(shallow, lessThan(0.20));
      expect(shallow, greaterThan(0)); // 不是硬剔除
    });

    test('权重全 0 时回退均匀（不能因为加权反而抽不出图）', () {
      final lib = _fixture();
      final policy = BgPagePolicy(
        opacity: 0.5,
        fixedProbability: 1,
        weightOf: (_) => 0,
      );
      final random = Random(4);
      for (var i = 0; i < 100; i++) {
        final spec = bgRoll(lib, policy, random);
        expect(spec.hasImage, isTrue);
        expect(spec.image!.followsScroll, isFalse);
      }
    });

    test('加权路径也遵守「只排除当前这一张」', () {
      final pool = _fixture().scrollablePool;
      final random = Random(8);
      for (var i = 0; i < 300; i++) {
        final picked = bgPickImage(pool, random,
            excludeId: 'bg_tall', weightOf: bgScrollDepthWeight);
        expect(picked!.id, isNot('bg_tall'));
      }
    });
  });

  group('bgRoll：不透明度与掺白', () {
    test('池空 → 纯色（宁可纯色，也不留一块加载不出来的空白）', () {
      final spec = bgRoll(BgLibrary.empty, BgPage.stats.policy, Random(1));
      expect(spec.kind, BackdropKind.solid);
      expect(spec.hasImage, isFalse);
      expect(spec.key, 'solid');
    });

    test('统计两页：图片 60%，不掺白', () {
      final lib = _fixture();
      for (var i = 0; i < 50; i++) {
        final spec = bgRoll(lib, BgPage.stats.policy, Random(i));
        expect(spec.kind, BackdropKind.image);
        expect(spec.opacity, kBgOpacityStats);
        expect(spec.opacity, 0.60);
        expect(spec.whiten, 0);
      }
    });

    test('计时页：图片 45% 且掺白 8%', () {
      final lib = _fixture();
      final random = Random(2026);
      for (var i = 0; i < 200; i++) {
        final spec = bgRoll(lib, BgPage.focus.policy, random);
        if (spec.hasImage) {
          expect(spec.opacity, kBgOpacityFocus);
          expect(spec.opacity, 0.45);
          expect(spec.whiten, kBgFocusWhiten);
          expect(spec.whiten, 0.08);
        }
      }
    });
  });

  group('BackdropNotifier：三页独立的调度器', () {
    test('池空 → 保持纯色，不排定时器也点不动', () {
      final notifier =
          BackdropNotifier(page: BgPage.stats, library: BgLibrary.empty);
      addTearDown(notifier.dispose);
      expect(notifier.state.kind, BackdropKind.solid);
      notifier.reroll(); // 不应抛
      expect(notifier.state.kind, BackdropKind.solid);
      expect(notifier.poolSize, 0);
    });

    test('池非空 → 立刻抽一张，透明度按页面策略', () {
      final notifier = BackdropNotifier(
          page: BgPage.stats, library: _fixture(), random: Random(5));
      addTearDown(notifier.dispose);
      expect(notifier.state.hasImage, isTrue);
      expect(notifier.state.opacity, kBgOpacityStats);
      expect(notifier.poolSize, 5);
    });

    test('reroll 换一张，且不与当前重复', () {
      final notifier = BackdropNotifier(
          page: BgPage.stats, library: _fixture(), random: Random(9));
      addTearDown(notifier.dispose);
      final first = notifier.state.image!.id;
      notifier.reroll();
      expect(notifier.state.image!.id, isNot(first));
    });

    test('连续 reroll 不会把池子抽空（抽完即放回）', () {
      final notifier = BackdropNotifier(
          page: BgPage.stats, library: _fixture(), random: Random(12));
      addTearDown(notifier.dispose);
      final seen = <String>{notifier.state.image!.id};
      var previous = notifier.state.image!.id;
      for (var i = 0; i < 200; i++) {
        notifier.reroll();
        final now = notifier.state.image!.id;
        expect(now, isNot(previous)); // 相邻不重复
        previous = now;
        seen.add(now);
      }
      expect(seen.length, 5); // 5 张全都还在循环里
    });

    test('dispose 后不再改状态（换背景是装饰，页面关掉就该停）', () {
      final notifier = BackdropNotifier(
          page: BgPage.stats, library: _fixture(), random: Random(1));
      final emitted = <String>[];
      // StateNotifier.addListener 默认 fireImmediately=true，必须显式关掉，
      // 否则注册瞬间就会收到当前状态、把「dispose 后无新通知」测成假失败
      notifier.addListener((spec) => emitted.add(spec.key),
          fireImmediately: false);
      expect(notifier.state.hasImage, isTrue);
      notifier.dispose();
      // 迟到的 reroll（UI 持有旧引用）必须被静默挡下而不是抛穿；
      // 且 state 在 dispose 后连读都会断言，故只能靠监听器证否
      notifier.reroll();
      expect(emitted, isEmpty);
    });

    test('同一张图的内容指纹（key）稳定，换图才变', () {
      final notifier = BackdropNotifier(
          page: BgPage.stats, library: _fixture(), random: Random(2));
      addTearDown(notifier.dispose);
      final key = notifier.state.key;
      expect(key, notifier.state.image!.id);
      expect(key, isNotEmpty);
    });
  });

  // ------------------------------------------------------------ 产物一致性

  group('产物一致性：assets/backgrounds/manifest.json ↔ bg_fit.dart', () {
    test('每张内置图的入库尺寸都与 Dart 策略一致（容 1px 舍入差）', () async {
      final raw = await rootBundle.loadString(kBgBundledManifestAsset);
      final lib = _decode(raw);
      expect(lib.isNotEmpty, isTrue, reason: '内置图库清单为空');

      for (final image in lib.images) {
        final target = bgTargetSize(image.srcWidth, image.srcHeight);
        expect(image.width, closeTo(target.width, 1),
            reason: '${image.id} 宽 ${image.width} 与策略 ${target.width} 不符');
        expect(image.height, closeTo(target.height, 1),
            reason: '${image.id} 高 ${image.height} 与策略 ${target.height} 不符');
        expect(image.rule, bgRuleOf(image.srcWidth, image.srcHeight),
            reason: '${image.id} 规则与尺寸不符');
      }
    });

    test('两类规则都有样本，且两个池都够抽', () async {
      final lib = _decode(await rootBundle.loadString(kBgBundledManifestAsset));
      expect(lib.fixedPool, isNotEmpty, reason: '没有规则 1 的图');
      expect(lib.scrollablePool, isNotEmpty, reason: '没有规则 2 的图');
      // 详细页 95%/5%、计时页 80%/2% 都要用得上这两个池
      expect(lib.fixedPool.length, greaterThanOrEqualTo(3));
      expect(lib.scrollablePool.length, greaterThanOrEqualTo(3));
    });

    test('规则 2 的图比例都 < 1.3、规则 1 都 >= 1.3', () async {
      final lib = _decode(await rootBundle.loadString(kBgBundledManifestAsset));
      for (final image in lib.scrollablePool) {
        expect(image.width * kBgRuleRatioDen,
            lessThan(image.height * kBgRuleRatioNum),
            reason: '${image.id} 被判成规则 2 但实际 ≥1.3');
      }
      for (final image in lib.fixedPool) {
        expect(image.width * kBgRuleRatioDen,
            greaterThanOrEqualTo(image.height * kBgRuleRatioNum),
            reason: '${image.id} 被判成规则 1 但实际 <1.3');
      }
    });

    test('登记表口径：屏幕基准、阈值与目标尺寸没被改过', () {
      // 这几条是 docs/10 里写死的口径，改了文档必须一起改，故此断言
      expect(kBgScreenWidth, 1280);
      expect(kBgScreenHeight, 720);
      expect(kBgRuleRatioNum, 13);
      expect(kBgRuleRatioDen, 10);
      expect(kBgRule1TargetHeight, 1080);
      expect(kBgRule2TargetWidth, 1280);
    });

    test('真实清单：规则 2 池里没有「浅溢出」的图了（阈值 1.3 的副产物）',
        () async {
      final lib = _decode(await rootBundle.loadString(kBgBundledManifestAsset));
      for (final image in lib.scrollablePool) {
        // 比例 < 1.3 ⇒ 按宽铺满后高度 > 1280/1.3 ≈ 985 ⇒ 溢出至少 265px
        expect(bgScrollDepthWeight(image), greaterThan(260),
            reason: '${image.id} 溢出太浅，说明阈值判定被改回去了');
      }
    });
  });
}
