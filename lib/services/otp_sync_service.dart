/// Wire format for the OTP pad "sync-check" control message — a lightweight,
/// user-triggered exchange of PAD POSITION COUNTERS ONLY, never pad byte
/// content, so it never costs any pad bytes and reveals nothing about key
/// material. This has no Lua equivalent as a *feature*, but the wire format
/// below is wire-compatible with the Lua app's own copy (see the comment on
/// SYNC_MARKER/send_sync_check/handle_sync_message in OTP_3_RC1.lua).
///
/// Deliberately NOT OTP-encrypted (there's nothing secret in "how many
/// bytes have you consumed") but still needs to be recognizable as a
/// distinct control message rather than an ordinary chat message — this
/// follows the same convention as this app's other non-OTP structured
/// outbound-text markers (`g:`, `m:`, `V1|` — see
/// `MeshCoreConnector.prepareContactOutboundText`): a short ASCII prefix,
/// checked against those (and against the OTP chunk/ack markers, which are
/// binary and only ever appear post-decrypt, so there's no collision risk
/// there either).
///
/// Wire layout (v2, all ASCII):
///   `z1p<myOffset36>:<theirOffset36>`   (two-party pad, initial check)
///   `z1P<myOffset36>:<theirOffset36>`   (two-party pad, reply)
///   `z1s<offset36>`                      (shared/channel pad, initial check)
///   `z1S<offset36>`                      (shared/channel pad, reply)
/// where `<N36>` is N encoded in base 36 (`0-9a-z`), lowercase on send,
/// accepted case-insensitively on receive.
///
/// This is v2 of the format — shrunk from v1's `OTPSYNC1|2P|<flag>|
/// <myOffset>:<theirOffset>` / `OTPSYNC1|SS|<flag>|<offset>` (pipe-delimited
/// decimal, ~17-21 bytes per message) down to ~4-8 bytes: the mode and
/// reply-flag are folded into a single case-coded letter (`p`/`P`, `s`/`S`)
/// instead of a 2-char mode token plus a separate `0`/`1` flag field, and
/// counters are base-36 rather than decimal. `z1` is the format-version tag
/// (bump to `z2` if the payload shape ever needs to change again, so old
/// and new builds can tell each other's messages apart instead of silently
/// misparsing them) — chosen because it can't collide with real message
/// content (ciphertext is always pure hex `[0-9a-f]`), the other plaintext
/// markers above (`g:`, `m:`, `V1|`), or the start of an ordinary,
/// human-typed chat message. This is a BREAKING change from v1 — every
/// device sharing a pad needs the matching build.
///
/// `replyFlag` (the letter case) is initial for the message that triggers a
/// check and reply for the automatic reply it provokes — receiving a reply
/// message must never itself provoke another reply, or two devices
/// checking at the same moment (or a multi-party channel) would ping-pong
/// forever.
class OtpSyncPayload {
  final bool isSharedSequential;
  final bool isReply;

  /// Two-party ([isSharedSequential] false) only.
  final int? myOffset;

  /// Two-party ([isSharedSequential] false) only.
  final int? theirOffset;

  /// Shared-sequential ([isSharedSequential] true) only.
  final int? offset;

  const OtpSyncPayload.twoParty({
    required this.isReply,
    required int myOffset,
    required int theirOffset,
  }) : isSharedSequential = false,
       myOffset = myOffset,
       theirOffset = theirOffset,
       offset = null;

  const OtpSyncPayload.shared({required this.isReply, required int offset})
    : isSharedSequential = true,
      myOffset = null,
      theirOffset = null,
      offset = offset;
}

class OtpSyncService {
  OtpSyncService._();

  static const String marker = 'z1';

  static String buildTwoParty({
    required bool isReply,
    required int myOffset,
    required int theirOffset,
  }) => '$marker'
      '${isReply ? 'P' : 'p'}'
      '${myOffset.toRadixString(36)}:${theirOffset.toRadixString(36)}';

  static String buildShared({required bool isReply, required int offset}) =>
      '$marker'
      '${isReply ? 'S' : 's'}'
      '${offset.toRadixString(36)}';

  /// Cheap pre-check before bothering to [parse] — also what
  /// `prepareContactOutboundText`/`prepareChannelOutboundText` use to keep
  /// Smaz/Cyr2Lat from touching an outgoing sync-check message.
  static bool looksLikeSyncMessage(String text) => text.startsWith(marker);

  /// Parses a message already known to start with [marker]. Returns null
  /// for anything malformed — callers should still treat a null result as
  /// "this WAS a sync-check control message" (suppress it from chat
  /// display) even though there was nothing usable to act on, since a
  /// corrupted-in-transit control message is still not a chat message.
  static OtpSyncPayload? parse(String text) {
    if (!text.startsWith(marker)) return null;
    final rest = text.substring(marker.length);
    if (rest.isEmpty) return null;
    final modeChar = rest[0];
    final body = rest.substring(1);
    final isReply = modeChar == 'P' || modeChar == 'S';
    final isTwoParty = modeChar == 'p' || modeChar == 'P';
    final isShared = modeChar == 's' || modeChar == 'S';
    if (isTwoParty) {
      final fields = body.split(':');
      if (fields.length != 2) return null;
      final myOffset = int.tryParse(fields[0], radix: 36);
      final theirOffset = int.tryParse(fields[1], radix: 36);
      if (myOffset == null || theirOffset == null) return null;
      if (myOffset < 0 || theirOffset < 0) return null;
      return OtpSyncPayload.twoParty(
        isReply: isReply,
        myOffset: myOffset,
        theirOffset: theirOffset,
      );
    }
    if (isShared) {
      final offset = int.tryParse(body, radix: 36);
      if (offset == null || offset < 0) return null;
      return OtpSyncPayload.shared(isReply: isReply, offset: offset);
    }
    return null;
  }
}
