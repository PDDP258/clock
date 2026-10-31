/// 时钟数字体系（竖屏「余光」布局，2026-10-05 PD 定稿）：
/// 辉光管逐位显示，可选阿拉伯 / 简体中文 / 中文大写三套数字；
/// 中文模式下冒号变句读 ○，暂停时变 ● 且缩至 80%。
library;

/// 数字体系。
enum ClockNumeral {
  /// 阿拉伯数字（默认，与横屏一致）。
  arabic,

  /// 简体中文数字（〇一二三四五六七八九）。
  simplified,

  /// 中文大写数字（零壹贰叁肆伍陆柒捌玖）。
  uppercase;

  /// 设置页展示名。
  String get label => switch (this) {
        ClockNumeral.arabic => '阿拉伯',
        ClockNumeral.simplified => '简体',
        ClockNumeral.uppercase => '大写',
      };
}

/// 各体系逐位数字字形（下标即数字）。
const _kDigits = <ClockNumeral, List<String>>{
  ClockNumeral.arabic: ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
  ClockNumeral.simplified: ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九'],
  ClockNumeral.uppercase: ['零', '壹', '贰', '叁', '肆', '伍', '陆', '柒', '捌', '玖'],
};

/// 竖排时钟的一位数字字符（辉光管逐管显示）。
String clockGlyph(int digit, ClockNumeral numeral) =>
    _kDigits[numeral]![digit.clamp(0, 9)];

/// 竖排时钟的分/秒两位字符。
List<String> clockGlyphPair(int value, ClockNumeral numeral) {
  final v = value.clamp(0, 99);
  return [
    clockGlyph(v ~/ 10, numeral),
    clockGlyph(v % 10, numeral),
  ];
}
