/// Wire format for the OTP pad "sync-check" control message — a lightweight,
/// user-triggered exchange of PAD POSITION COUNTERS ONLY, never pad byte
/// content, so it never costs any pad bytes and reveals nothing about key
/// material. This has no Lua equivalent; it's new to this port.
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
/// Wire layout (all ASCII, `|`-delimited):
///   `OTPSYNC1|2P|<replyFlag>|<myOffset>:<theirOffset>`   (two-party pad)
///   `OTPSYNC1|SS|<replyFlag>|<offset>`                    (shared/channel pad)
///
/// `1` in the marker is a format version — bump it (`OTPSYNC2|`, ...) if the
/// payload shape ever needs to change; old and new builds can then tell
/// each other's messages apart instead of silently misparsing them.
///
/// `replyFlag` is `0` for the message that triggers a check and `1` for the
/// automatic reply it provokes — receiving a `1` message must never itself
/// provoke another reply, or two devices checking at the same moment (or a
/// multi-party channel) would ping-pong forever.
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

  static const String marker = 'OTPSYNC1|';

  static String buildTwoParty({
    required bool isReply,
    required int myOffset,
    required int theirOffset,
  }) => '$marker'
      '2P|'
      '${isReply ? 1 : 0}|'
      '$myOffset:$theirOffset';

  static String buildShared({required bool isReply, required int offset}) =>
      '$marker'
      'SS|'
      '${isReply ? 1 : 0}|'
      '$offset';

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
    final parts = rest.split('|');
    if (parts.length != 3) return null;
    final mode = parts[0];
    final replyFlagRaw = parts[1];
    if (replyFlagRaw != '0' && replyFlagRaw != '1') return null;
    final isReply = replyFlagRaw == '1';
    if (mode == '2P') {
      final fields = parts[2].split(':');
      if (fields.length != 2) return null;
      final myOffset = int.tryParse(fields[0]);
      final theirOffset = int.tryParse(fields[1]);
      if (myOffset == null || theirOffset == null) return null;
      if (myOffset < 0 || theirOffset < 0) return null;
      return OtpSyncPayload.twoParty(
        isReply: isReply,
        myOffset: myOffset,
        theirOffset: theirOffset,
      );
    }
    if (mode == 'SS') {
      final offset = int.tryParse(parts[2]);
      if (offset == null || offset < 0) return null;
      return OtpSyncPayload.shared(isReply: isReply, offset: offset);
    }
    return null;
  }
}
