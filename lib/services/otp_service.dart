import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart'
    show
        hex2Uint8List,
        maxContactMessageBytes,
        maxChannelMessageBytes;

/// Thrown when a message can't be OTP-encrypted because the sender's half
/// of the shared pad doesn't have enough unused bytes left to cover it.
///
/// This must always fail CLOSED: callers must never fall back to sending
/// plaintext when this is thrown. A user who has enabled OTP for a contact
/// or channel is trusting that nothing goes out unencrypted.
class OtpPadExhaustedException implements Exception {
  final int neededBytes;
  final int availableBytes;

  OtpPadExhaustedException({
    required this.neededBytes,
    required this.availableBytes,
  });

  @override
  String toString() =>
      'OtpPadExhaustedException: need $neededBytes bytes, only '
      '$availableBytes left in this pad';
}

/// Thrown when a received OTP payload can't be decrypted — the marker was
/// present but the pad's remaining bytes ran out, or the hex was malformed.
class OtpDecryptException implements Exception {
  final String message;
  OtpDecryptException(this.message);

  @override
  String toString() => 'OtpDecryptException: $message';
}

/// Pure one-time-pad encrypt/decrypt for MeshCore Open text messages.
///
/// This is a direct port of the XOR core proved out on real hardware in the
/// WADAMESH Lua OTP messenger, adapted to this app's transport constraints:
///
/// - The companion BLE text pipe is NOT byte-safe. `BufferWriter.writeString`
///   UTF-8-encodes its input and `BufferReader.readCString` stops dead at the
///   first 0x00 byte. Raw XOR ciphertext is uniformly random — it contains
///   0x00 bytes constantly and is not valid UTF-8 — so ciphertext is always
///   carried as lowercase hex, never as raw bytes, inside a `String`.
/// - Every OTP payload is prefixed with [marker] so it can be recognized
///   before Smaz compression or Cyr2Lat transliteration would otherwise try
///   to touch it (both would corrupt hex ciphertext, and compressing random
///   bytes never helps anyway).
class OtpService {
  OtpService._();

  /// Prefixes every OTP-encrypted payload actually placed on the wire.
  /// Chosen to line up with this app's existing structured-payload markers
  /// ("g:", "m:", "V1|") that already bypass Smaz/Cyr2Lat.
  static const String marker = 'OTP1|';

  static bool isOtpPayload(String text) => text.startsWith(marker);

  /// Encrypts [plaintext] against [keyBytes] (a slice already carved out of
  /// the sender's half of the pad, exactly [utf8.encode(plaintext).length]
  /// bytes long) and returns the full wire payload including [marker].
  ///
  /// Throws [OtpPadExhaustedException] if [keyBytes] is shorter than the
  /// plaintext requires — callers should check [plaintextByteLength] against
  /// remaining pad bytes *before* calling this, but this is the final,
  /// authoritative guard.
  static String encrypt(String plaintext, Uint8List keyBytes) {
    final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
    if (keyBytes.length < plainBytes.length) {
      throw OtpPadExhaustedException(
        neededBytes: plainBytes.length,
        availableBytes: keyBytes.length,
      );
    }
    final cipherBytes = Uint8List(plainBytes.length);
    for (var i = 0; i < plainBytes.length; i++) {
      cipherBytes[i] = plainBytes[i] ^ keyBytes[i];
    }
    return '$marker${_bytesToHex(cipherBytes)}';
  }

  /// Decrypts a full wire payload (including [marker]) against [keyBytes]
  /// (the receiver's own tracked slice of the *other* party's half of the
  /// pad, which must be at least as long as the ciphertext).
  ///
  /// Returns null if [payload] isn't an OTP payload at all (no marker) so
  /// callers can fall through to normal handling. Throws
  /// [OtpDecryptException] if it IS marked as OTP but can't actually be
  /// decrypted (malformed hex, or not enough pad left on our side — the
  /// latter usually means the two sides' pad offsets have drifted out of
  /// sync, e.g. from a dropped message).
  static String? decrypt(String payload, Uint8List keyBytes) {
    if (!isOtpPayload(payload)) return null;
    final hex = payload.substring(marker.length);
    Uint8List cipherBytes;
    try {
      cipherBytes = hex2Uint8List(hex);
    } catch (e) {
      throw OtpDecryptException('malformed ciphertext hex: $e');
    }
    if (keyBytes.length < cipherBytes.length) {
      throw OtpDecryptException(
        'not enough pad left to decrypt (need ${cipherBytes.length} '
        'bytes, have ${keyBytes.length}) — pad offsets may be out of sync',
      );
    }
    final plainBytes = Uint8List(cipherBytes.length);
    for (var i = 0; i < cipherBytes.length; i++) {
      plainBytes[i] = cipherBytes[i] ^ keyBytes[i];
    }
    return utf8.decode(plainBytes, allowMalformed: true);
  }

  /// How many plaintext UTF-8 bytes a message to [text] would need, i.e.
  /// how many pad bytes encrypting it will consume.
  static int plaintextByteLength(String text) => utf8.encode(text).length;

  /// Max plaintext bytes that fit in one OTP-encrypted contact message,
  /// after reserving space for [marker] and doubling for hex encoding.
  static int maxPlaintextBytesForContact() {
    final budget = maxContactMessageBytes() - marker.length;
    if (budget <= 0) return 0;
    return budget ~/ 2;
  }

  /// Max plaintext bytes that fit in one OTP-encrypted channel message,
  /// after reserving space for [marker], the "<name>: " prefix the firmware
  /// adds, and doubling for hex encoding.
  static int maxPlaintextBytesForChannel(String? senderName) {
    final budget = maxChannelMessageBytes(senderName) - marker.length;
    if (budget <= 0) return 0;
    return budget ~/ 2;
  }

  static String _bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
