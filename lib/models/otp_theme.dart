import 'package:flutter/painting.dart';

/// One named color palette for OTP-active chats, ported byte-for-byte from
/// OTP_3_RC1.lua's `THEME_DATA` table (see `PALETTE_FIELDS`/`apply_theme`)
/// so the same named themes look the same on both platforms. There is
/// exactly one global theme choice for the whole app, same as Lua - no
/// per-contact/channel override - stored as `AppSettings.otpThemeIndex`
/// and picked from the OTP Pad screen.
///
/// Field names match Lua's semantic roles, not literal meanings - e.g.
/// [channel] colors a sent/pending bubble, not "channel chat" specifically;
/// [resultOk] colors a delivered (acked) bubble; [encrypt] colors a failed/
/// lost one. See `otp_bubble_colors.dart` for how these map onto an actual
/// message's state.
class OtpTheme {
  final String name;
  final Color encrypt;
  final Color decrypt;
  final Color ciphertext;
  final Color plaintext;
  final Color newpad;
  final Color channel;
  final Color resultOk;
  final Color keyphrase;
  final Color padinfo;
  final Color ready;
  final Color bg;

  const OtpTheme({
    required this.name,
    required this.encrypt,
    required this.decrypt,
    required this.ciphertext,
    required this.plaintext,
    required this.newpad,
    required this.channel,
    required this.resultOk,
    required this.keyphrase,
    required this.padinfo,
    required this.ready,
    required this.bg,
  });

  /// Round-robin bucket order for [OtpSenderColors] - a received message's
  /// bubble color is picked from this list by sender, matching Lua's
  /// `SENDER_COLOR_FIELDS = { "decrypt", "ciphertext", "newpad",
  /// "keyphrase", "result_ok" }`. Keep this order in sync with that list,
  /// not with [all]'s field order above (`channel`, `encrypt`, `padinfo`
  /// and [bg] are deliberately excluded - Lua reserves those for sent/
  /// failed bubbles, the chat background tint, and captions respectively,
  /// and never hands them out as a sender's bubble color).
  List<Color> get senderColorFields => [
    decrypt,
    ciphertext,
    newpad,
    keyphrase,
    resultOk,
  ];

  /// All named themes, in the same order as Lua's `THNAMES`/`THEME_DATA` -
  /// index order matters, since `AppSettings.otpThemeIndex` is a plain
  /// index into this list.
  static const List<OtpTheme> all = [
    OtpTheme(
      name: 'Default',
      encrypt: Color(0xFFFF6B4A),
      decrypt: Color(0xFF2DD4BF),
      ciphertext: Color(0xFFF97316),
      plaintext: Color(0xFF38BDF8),
      newpad: Color(0xFFA78BFA),
      channel: Color(0xFFEC4899),
      resultOk: Color(0xFF4ADE80),
      keyphrase: Color(0xFFFBBF24),
      padinfo: Color(0xFF22D3EE),
      ready: Color(0xFF94A3B8),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Cyberpunk',
      encrypt: Color(0xFFFF1493),
      decrypt: Color(0xFF39FF14),
      ciphertext: Color(0xFFBC13FE),
      plaintext: Color(0xFF00F5FF),
      newpad: Color(0xFFFF00FF),
      channel: Color(0xFFF5FF00),
      resultOk: Color(0xFF39FF14),
      keyphrase: Color(0xFFFFAA00),
      padinfo: Color(0xFF00FFEF),
      ready: Color(0xFF6B7280),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Trans',
      encrypt: Color(0xFFF5A9B8),
      decrypt: Color(0xFF5BCEFA),
      ciphertext: Color(0xFFFF8FAB),
      plaintext: Color(0xFFFFFFFF),
      newpad: Color(0xFF7DD3FC),
      channel: Color(0xFFF9A8D4),
      resultOk: Color(0xFFBAE6FD),
      keyphrase: Color(0xFFFBCFE8),
      padinfo: Color(0xFF38BDF8),
      ready: Color(0xFFE5E7EB),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Cascadia',
      encrypt: Color(0xFF60A5FA),
      decrypt: Color(0xFF93C5FD),
      ciphertext: Color(0xFF86EFAC),
      plaintext: Color(0xFFFFFFFF),
      newpad: Color(0xFF3B82F6),
      channel: Color(0xFF15803D),
      resultOk: Color(0xFF34D399),
      keyphrase: Color(0xFF1D4ED8),
      padinfo: Color(0xFF22C55E),
      ready: Color(0xFFCBD5E1),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Mono',
      encrypt: Color(0xFF00FF00),
      decrypt: Color(0xFF00DD00),
      ciphertext: Color(0xFF00BB00),
      plaintext: Color(0xFFDDFFDD),
      newpad: Color(0xFF22CC22),
      channel: Color(0xFF33FF33),
      resultOk: Color(0xFF11FF11),
      keyphrase: Color(0xFF88EE88),
      padinfo: Color(0xFF449944),
      ready: Color(0xFF336633),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'B&W',
      encrypt: Color(0xFFFFFFFF),
      decrypt: Color(0xFFE6E6E6),
      ciphertext: Color(0xFFCCCCCC),
      plaintext: Color(0xFFFFFFFF),
      newpad: Color(0xFFB3B3B3),
      channel: Color(0xFFD9D9D9),
      resultOk: Color(0xFFFFFFFF),
      keyphrase: Color(0xFF999999),
      padinfo: Color(0xFF808080),
      ready: Color(0xFF4D4D4D),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Acid',
      encrypt: Color(0xFFCCFF00),
      decrypt: Color(0xFFFF00FF),
      ciphertext: Color(0xFF00FFCC),
      plaintext: Color(0xFFFFFFFF),
      newpad: Color(0xFFFFFF00),
      channel: Color(0xFFFF0099),
      resultOk: Color(0xFF66FF00),
      keyphrase: Color(0xFFCCFF99),
      padinfo: Color(0xFF9933FF),
      ready: Color(0xFF666699),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Dark',
      encrypt: Color(0xFFFF4500),
      decrypt: Color(0xFFFFA500),
      ciphertext: Color(0xFFDC143C),
      plaintext: Color(0xFFFFFFFF),
      newpad: Color(0xFFFF6347),
      channel: Color(0xFFFF0000),
      resultOk: Color(0xFFFFD700),
      keyphrase: Color(0xFFFFDAB9),
      padinfo: Color(0xFF8B0000),
      ready: Color(0xFF696969),
      bg: Color(0xFF000000),
    ),
    OtpTheme(
      name: 'Ice Cream',
      encrypt: Color(0xFFFFB6C1),
      decrypt: Color(0xFFB4E7CE),
      ciphertext: Color(0xFFE6D5F7),
      plaintext: Color(0xFFFFF8E7),
      newpad: Color(0xFFFFDAB9),
      channel: Color(0xFFB0E0E6),
      resultOk: Color(0xFFA8E6CF),
      keyphrase: Color(0xFFDCC6E0),
      padinfo: Color(0xFFFFF9C4),
      ready: Color(0xFFFFB7B2),
      bg: Color(0xFF000000),
    ),
  ];
}
