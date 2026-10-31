/// 机型信息通道：向原生要 `Build.MODEL` 等标识，供 M500 识别用。
///
/// 零依赖（不引 device_info_plus，项目纪律：不为一个字段加插件）。
/// 通道不可用（平台不支持/未注册）时返回 null，调用方按「非 M500」
/// 之外的安全路径走——比例信号仍然有效，不会因此崩溃。
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/device_profile.dart';

/// 通道名（与 `android/.../DeviceProfilePlugin.kt` 对应）。
const _channel = MethodChannel('aiclock/device');

/// 原生机型标识（model/device/product/manufacturer 全小写化后返回）。
Future<DeviceIdentity?> readDeviceIdentity() async {
  try {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('info');
    if (raw == null) return null;
    String? str(String key) {
      final v = raw[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    return DeviceIdentity(
      model: str('model'),
      device: str('device'),
      product: str('product'),
      manufacturer: str('manufacturer'),
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// 原生上报的机型标识。
class DeviceIdentity {
  const DeviceIdentity({
    this.model,
    this.device,
    this.product,
    this.manufacturer,
  });

  final String? model;
  final String? device;
  final String? product;
  final String? manufacturer;

  /// 是否 M500 机型（任一字段含 m500）。
  bool get isM500 => looksLikeM500Model(
        model: model,
        device: device,
        product: product,
        manufacturer: manufacturer,
      );
}

/// 机型信息（一次性读取，进程内缓存）。
///
/// 加载中/失败都是 null-ish：UI 用 `valueOrNull?.isM500 ?? false`，
/// 未就绪时按「非 M500 机型」处理——比例信号先顶上，通道到达后
/// 自动修正（Riverpod 的 AsyncValue 天然支持这种先渲染后修正）。
final deviceIdentityProvider = FutureProvider<DeviceIdentity?>(
  (ref) => readDeviceIdentity(),
);
