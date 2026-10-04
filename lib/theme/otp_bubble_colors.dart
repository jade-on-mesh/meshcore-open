import 'package:flutter/painting.dart';
import '../models/otp_theme.dart';

/// Ports OTP_3_RC1.lua's `darken_color`: scales r/g/b down by [factor]
/// (every palette color is already fully opaque, so alpha is untouched),
/// floor-rounded per channel exactly like the Lua integer math.
Color otpDarken(Color color, double factor) {
  final argb = color.toARGB32();
  int scale(int shift) {
    final c = (((argb >> shift) & 0xFF) * factor).floor();
    if (c < 0) return 0;
    if (c > 255) return 255;
    return c;
  }

  return Color(0xFF000000 | (scale(16) << 16) | (scale(8) << 8) | scale(0));
}

/// Ports OTP_3_RC1.lua's `contrast_of`: perceived-luminance threshold
/// deciding bubble text color against a fill - same formula, same 140
/// cutoff, same two fallback colors.
Color otpContrastOf(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  final lum = 0.299 * r + 0.587 * g + 0.114 * b;
  return lum > 140 ? const Color(0xFF14171C) : const Color(0xFFF5F5F5);
}

/// Ports OTP_3_RC1.lua's `color_for_sender`: assigns each distinct sender
/// name a round-robin palette bucket the first time it's seen, remembers
/// it thereafter, and evicts the oldest once more than [maxTracked]
/// senders are tracked (same 200-sender cap as Lua's `SENDER_COLORS_MAX`).
/// One global instance, matching Lua's single app-wide table - not scoped
/// per chat, so the same sender keeps the same color everywhere.
class OtpSenderColors {
  OtpSenderColors._();
  static final OtpSenderColors instance = OtpSenderColors._();

  static const int maxTracked = 200;
  final Map<String, int> _bucketBySender = {};
  final List<String> _order = [];
  int _nextBucket = 0;

  Color colorFor(String who, OtpTheme theme) {
    final fields = theme.senderColorFields;
    var bucket = _bucketBySender[who];
    if (bucket == null) {
      bucket = _nextBucket % fields.length;
      _nextBucket = bucket + 1;
      _bucketBySender[who] = bucket;
      _order.add(who);
      if (_order.length > maxTracked) {
        final oldest = _order.removeAt(0);
        _bucketBySender.remove(oldest);
      }
    }
    return fields[bucket % fields.length];
  }

  /// Test/debug only - how many distinct senders are currently tracked.
  int get trackedCount => _order.length;
}

/// The three colors one bubble needs, resolved for a single message's
/// state - mirrors `refresh_chat_view`'s per-bubble `outline_color`/
/// `fill_color`/`text_color` math in OTP_3_RC1.lua exactly, including the
/// 0.32-vs-0.35 darken factor for a still-in-flight send.
class OtpBubbleColors {
  final Color outline;
  final Color fill;
  final Color text;
  const OtpBubbleColors({
    required this.outline,
    required this.fill,
    required this.text,
  });
}

/// For a message THIS device sent. Exactly one of [failed]/[delivered]/
/// [waiting]/[retrying] should be true at once (checked in that priority
/// order, matching Lua's `kind` being a single state) - [pending] only
/// changes the darken factor, matching Lua's `(kind == "pending" or kind
/// == "retrying") and 0.32 or 0.35`.
OtpBubbleColors otpOutgoingBubbleColors({
  required OtpTheme theme,
  bool failed = false,
  bool delivered = false,
  bool waiting = false,
  bool retrying = false,
  bool pending = false,
}) {
  final Color outline;
  if (failed) {
    outline = theme.encrypt;
  } else if (delivered) {
    outline = theme.resultOk;
  } else if (retrying) {
    outline = theme.keyphrase;
  } else if (waiting) {
    outline = theme.ready;
  } else {
    outline = theme.channel; // sent or plain pending
  }
  final fill = otpDarken(outline, (pending || retrying) ? 0.32 : 0.35);
  return OtpBubbleColors(
    outline: outline,
    fill: fill,
    text: otpContrastOf(fill),
  );
}

/// For a message from someone else - colored by sender, round-robin, same
/// as Lua. [failed] is for a message that came through corrupted/
/// undecodable (Lua's "warn" bubble can be centered garbage from a peer,
/// not just a lost outgoing send); otherwise every received message gets
/// [senderName]'s assigned color.
OtpBubbleColors otpReceivedBubbleColors({
  required OtpTheme theme,
  required String senderName,
  bool failed = false,
}) {
  final outline = failed
      ? theme.encrypt
      : OtpSenderColors.instance.colorFor(senderName, theme);
  final fill = otpDarken(outline, 0.35);
  return OtpBubbleColors(
    outline: outline,
    fill: fill,
    text: otpContrastOf(fill),
  );
}
