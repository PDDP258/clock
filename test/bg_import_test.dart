import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clock/core/background/bg_fit.dart';
import 'package:ai_clock/core/background/bg_image.dart';
import 'package:ai_clock/features/backgrounds/application/bg_import.dart';
import 'package:ai_clock/features/backgrounds/application/background_controller.dart';
import 'package:ai_clock/platform/files/background_import_channel.dart';
import 'package:ai_clock/platform/files/background_store.dart';

/// 假通道：只记下收到什么、返回预设结果，不碰真实原生实现。
class _FakeChannel extends BgImportChannel {
  _FakeChannel({
    this.picked = const <BgImportCandidate>[],
    this.result = const <BgImportedFile>[],
  }) : super();

  final List<BgImportCandidate> picked;
  final List<BgImportedFile> result;

  /// 收到的选图来源与入库指令（断言用）
  List<BgPickSource> seenSources = const <BgPickSource>[];
  List<BgImportSpec> seen = const <BgImportSpec>[];

  @override
  Future<List<BgImportCandidate>> pick({required BgPickSource source}) async {
    seenSources = [...seenSources, source];
    return picked;
  }

  @override
  Future<List<BgImportedFile>> process(List<BgImportSpec> specs) async {
    seen = specs;
    return result;
  }
}

BgImportCandidate _candidate(String name, int w, int h) => BgImportCandidate(
      uri: 'content://media/external/images/$name',
      name: name,
      width: w,
      height: h,
    );

BgImportedFile _imported(String id, int w, int h) => BgImportedFile(
      path: '/tmp/backgrounds/$id.webp',
      name: '$id.jpg',
      width: w,
      height: h,
      bytes: 1024,
      srcWidth: w * 2,
      srcHeight: h * 2,
    );

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bg_import_test');
  });
  tearDown(() async {
    // Windows 上偶发「文件被占用」：临时目录清不掉不该让测试失败
    try {
      if (temp.existsSync()) await temp.delete(recursive: true);
    } on FileSystemException {
      // 忽略
    }
  });

  ProviderContainer containerWith(_FakeChannel channel) {
    final container = ProviderContainer(overrides: <Override>[
      bgImportChannelProvider.overrideWithValue(channel),
      bgLibraryStoreProvider
          .overrideWithValue(BgLibraryStore(root: () async => temp)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  // ---------------------------------------------------------------- 纯函数

  group('入库指令', () {
    test('目标尺寸与预处理脚本同源（竖图按宽缩、超宽按高缩）', () {
      final specs = bgImportSpecsOf([
        _candidate('portrait.jpg', 2160, 3840), // 规则 2
        _candidate('ultra.jpg', 3000, 1000), // 规则 1
      ]);
      expect(specs, hasLength(2));

      // 2160×3840 → 宽铺满 1280，高按比例 3840×1280/2160 ≈ 2276
      expect(specs[0].outWidth, 1280);
      expect(specs[0].outHeight, 2276);
      expect(bgRuleOf(specs[0].outWidth, specs[0].outHeight),
          BgFitRule.fillWidth);

      // 3000×1000 比 16:9 更宽且高只有 1000 < 1080 → 只缩不放，原尺寸入库
      expect(specs[1].outWidth, 3000);
      expect(specs[1].outHeight, 1000);
    });

    test('探测不出尺寸的候选直接丢掉（坏图不该占一次编码）', () {
      final specs = bgImportSpecsOf([
        _candidate('broken.jpg', 0, 0),
        _candidate('ok.jpg', 1280, 720),
      ]);
      expect(specs, hasLength(1));
      expect(specs.single.candidate.name, 'ok.jpg');
    });
  });

  group('落盘结果 → 图库条目', () {
    test('用户条目：非内置、ref 是绝对路径、id 取文件名', () {
      final images = bgImagesFromImport([_imported('u_ab12cd34', 1280, 2276)]);
      expect(images, hasLength(1));
      final image = images.single;
      expect(image.id, 'u_ab12cd34');
      expect(image.bundled, isFalse);
      expect(image.ref, '/tmp/backgrounds/u_ab12cd34.webp');
      expect(image.width, 1280);
      expect(image.height, 2276);
      expect(image.rule, BgFitRule.fillWidth);
      // 原始尺寸只作展示，不参与判定
      expect(image.srcWidth, 2560);
    });
  });

  // ---------------------------------------------------------------- 服务

  group('导入服务', () {
    test('相册选图 → 落盘 → 清单多两条', () async {
      final channel = _FakeChannel(
        picked: [
          _candidate('a.jpg', 2160, 3840),
          _candidate('b.jpg', 3000, 1000),
        ],
        result: [
          _imported('u_aaaa0001', 1280, 2276),
          _imported('u_bbbb0002', 3000, 1000),
        ],
      );
      final container = containerWith(channel);

      final outcome =
          await container.read(bgImportServiceProvider).fromGallery();

      expect(outcome.picked, 2);
      expect(outcome.added, 2);
      expect(outcome.duplicate, 0);
      expect(outcome.failed, 0);
      expect(channel.seenSources, <BgPickSource>[BgPickSource.gallery]);
      expect(channel.seen, hasLength(2));

      final library =
          await container.read(bgLibraryStoreProvider).read();
      expect(library.length, 2);
      expect(library.images.map((i) => i.id).toList(),
          <String>['u_aaaa0001', 'u_bbbb0002']);
    });

    test('文件管理器入口与相册入口同一套链路，只差来源', () async {
      final channel = _FakeChannel(
        picked: [_candidate('a.jpg', 1280, 720)],
        result: [_imported('u_aaaa0001', 1280, 720)],
      );
      final container = containerWith(channel);

      final outcome =
          await container.read(bgImportServiceProvider).fromFileManager();

      expect(outcome.added, 1);
      expect(channel.seenSources, <BgPickSource>[BgPickSource.files]);
    });

    test('重复导入同一张 → 计入 duplicate，清单不涨', () async {
      final channel = _FakeChannel(
        picked: [_candidate('a.jpg', 2160, 3840)],
        result: [_imported('u_aaaa0001', 1280, 2276)],
      );
      final container = containerWith(channel);
      final service = container.read(bgImportServiceProvider);

      final first = await service.fromGallery();
      expect(first.added, 1);

      final second = await service.fromGallery();
      expect(second.added, 0);
      expect(second.duplicate, 1);

      final library = await container.read(bgLibraryStoreProvider).read();
      expect(library.length, 1);
    });

    test('部分失败：成功的进清单，失败只计数不拖垮整批', () async {
      final channel = _FakeChannel(
        picked: [
          _candidate('good.jpg', 1280, 720),
          _candidate('bad.jpg', 1920, 1080),
        ],
        result: [_imported('u_cccc0003', 1280, 720)],
      );
      final container = containerWith(channel);

      final outcome =
          await container.read(bgImportServiceProvider).fromGallery();

      expect(outcome.picked, 2);
      expect(outcome.added, 1);
      expect(outcome.failed, 1);
      expect(
          (await container.read(bgLibraryStoreProvider).read()).length, 1);
    });

    test('没选到图 / 原生不可用：空结果，不写清单', () async {
      final container = containerWith(_FakeChannel());
      final outcome =
          await container.read(bgImportServiceProvider).fromGallery();
      expect(outcome.isEmpty, isTrue);
      expect(outcome.message, isNotEmpty);
      expect(File('${temp.path}/backgrounds/user_manifest.json').existsSync(),
          isFalse);
    });

    test('全部候选探测失败时提示「读不出来」而不是「没有选到」', () async {
      final container = containerWith(
        _FakeChannel(picked: [_candidate('bad.jpg', 0, 0)]),
      );
      final outcome =
          await container.read(bgImportServiceProvider).fromGallery();
      expect(outcome.picked, 0);
      expect(outcome.failed, 1);
      expect(outcome.message, contains('读不出来'));
    });
  });

  // ---------------------------------------------------------------- 存储

  group('用户图库存储', () {
    test('写后读回：结构不变（往返）', () async {
      final store = BgLibraryStore(root: () async => temp);
      const source = BgLibrary([
        BgImage(
          id: 'u_1',
          ref: '/x/u_1.webp',
          bundled: false,
          width: 1280,
          height: 2276,
          srcWidth: 2160,
          srcHeight: 3840,
          bytes: 12345,
          sourceName: 'miku.jpg',
        ),
      ]);
      await store.write(source);
      final back = await store.read();

      expect(back.length, 1);
      final image = back.images.single;
      expect(image.id, 'u_1');
      expect(image.bundled, isFalse);
      expect(image.ref, '${temp.path}${Platform.pathSeparator}backgrounds'
          '${Platform.pathSeparator}u_1.webp');
      expect(image.width, 1280);
      expect(image.srcHeight, 3840);
      expect(image.sourceName, 'miku.jpg');
      expect(image.rule, BgFitRule.fillWidth);
    });

    test('清单不存在 → 空池（背景是装饰，读不到就退纯色）', () async {
      final store = BgLibraryStore(root: () async => temp);
      expect((await store.read()).isEmpty, isTrue);
    });

    test('清单坏 JSON → 空池，不抛', () async {
      final store = BgLibraryStore(root: () async => temp);
      final dir = Directory('${temp.path}/backgrounds')..createSync(recursive: true);
      File('${dir.path}/user_manifest.json').writeAsStringSync('{ not json');
      expect((await store.read()).isEmpty, isTrue);
    });

    test('remove：清单去条目 + 删素材文件；文件删不掉不阻塞', () async {
      final store = BgLibraryStore(root: () async => temp);
      const source = BgLibrary([
        BgImage(
          id: 'u_1',
          ref: '/x/u_1.webp',
          bundled: false,
          width: 1280,
          height: 720,
        ),
        BgImage(
          id: 'u_2',
          ref: '/x/u_2.webp',
          bundled: false,
          width: 1280,
          height: 720,
        ),
      ]);
      await store.write(source);
      final dir = Directory('${temp.path}/backgrounds')..createSync(recursive: true);
      final asset = File('${dir.path}/u_1.webp')..writeAsStringSync('x');

      await store.remove('u_1');

      expect(asset.existsSync(), isFalse);
      final ids = (await store.read()).images.map((i) => i.id).toList();
      expect(ids, <String>['u_2']);
    });
  });
}
