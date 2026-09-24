import 'dart:typed_data';

import '../connector/meshcore_protocol.dart' show hex2Uint8List;

/// Which half of a shared pad this device sends from.
///
/// A shared pad is split in half at import time: Party A always sends from
/// the first half and Party B always sends from the second half. Each side
/// tracks its own two offsets — how far it has advanced into ITS OWN
/// sending half, and how far it has advanced into the OTHER party's half
/// (as messages from them are decrypted). A pad byte is used exactly once,
/// ever, by construction — there's no way for both sides to draw from the
/// same range, because each only ever writes into (encrypts with) its own
/// half and only ever reads from (decrypts with) the other's.
///
/// The two people sharing a pad must agree out of band on who is A and who
/// is B — get this wrong on either end and messages won't decrypt, but
/// nothing is silently reused, so it fails safely rather than dangerously.
enum OtpPadRole {
  a,
  b;

  String get label => this == OtpPadRole.a ? 'A' : 'B';

  static OtpPadRole fromLabel(String value) =>
      value.trim().toUpperCase() == 'B' ? OtpPadRole.b : OtpPadRole.a;
}

/// A shared one-time pad plus this device's consumption state for one
/// contact or one channel.
///
/// Deliberately stored unencrypted (matches every other per-contact /
/// per-channel setting in this app, which all live in plain
/// SharedPreferences) — this is a product decision, not an oversight.
class OtpPad {
  /// The full shared pad, as lowercase hex. Never transmitted after import;
  /// only ever consumed locally to derive per-message key material.
  final String padHex;

  final OtpPadRole role;

  /// Bytes already consumed from THIS device's own sending half.
  final int myOffset;

  /// Bytes already consumed from the OTHER party's half, i.e. how far this
  /// device has advanced while decrypting their incoming messages.
  final int theirOffset;

  final bool enabled;

  /// Optional human label shown in the pad manager ("Camp trip pad", etc.)
  final String? label;

  final DateTime importedAt;

  const OtpPad({
    required this.padHex,
    required this.role,
    this.myOffset = 0,
    this.theirOffset = 0,
    this.enabled = true,
    this.label,
    required this.importedAt,
  });

  int get totalBytes => padHex.length ~/ 2;
  int get halfBytes => totalBytes ~/ 2;

  int get myHalfStart => role == OtpPadRole.a ? 0 : halfBytes;
  int get myHalfLength =>
      role == OtpPadRole.a ? halfBytes : (totalBytes - halfBytes);

  int get theirHalfStart => role == OtpPadRole.a ? halfBytes : 0;
  int get theirHalfLength =>
      role == OtpPadRole.a ? (totalBytes - halfBytes) : halfBytes;

  int get myBytesRemaining => (myHalfLength - myOffset).clamp(0, myHalfLength);
  int get theirBytesRemaining =>
      (theirHalfLength - theirOffset).clamp(0, theirHalfLength);

  double get myUsageFraction =>
      myHalfLength == 0 ? 1.0 : (myOffset / myHalfLength).clamp(0.0, 1.0);
  double get theirUsageFraction => theirHalfLength == 0
      ? 1.0
      : (theirOffset / theirHalfLength).clamp(0.0, 1.0);

  /// True once either half is fully consumed — the pad needs replacing.
  bool get isExhausted => myBytesRemaining == 0 || theirBytesRemaining == 0;

  /// The next unused slice of THIS device's own sending half, [length]
  /// bytes long. Does not mutate state — call [advanceMyOffset] (via the
  /// store) once the bytes are actually spent on a sent message.
  Uint8List takeMyKeyBytes(int length) {
    final all = hex2Uint8List(padHex);
    final start = myHalfStart + myOffset;
    final end = (start + length).clamp(0, all.length);
    if (end <= start) return Uint8List(0);
    return all.sublist(start, end);
  }

  /// The next unused slice of the OTHER party's half, [length] bytes long,
  /// used to decrypt one of their incoming messages.
  Uint8List takeTheirKeyBytes(int length) {
    final all = hex2Uint8List(padHex);
    final start = theirHalfStart + theirOffset;
    final end = (start + length).clamp(0, all.length);
    if (end <= start) return Uint8List(0);
    return all.sublist(start, end);
  }

  OtpPad copyWith({
    String? padHex,
    OtpPadRole? role,
    int? myOffset,
    int? theirOffset,
    bool? enabled,
    Object? label = _unset,
    DateTime? importedAt,
  }) {
    return OtpPad(
      padHex: padHex ?? this.padHex,
      role: role ?? this.role,
      myOffset: myOffset ?? this.myOffset,
      theirOffset: theirOffset ?? this.theirOffset,
      enabled: enabled ?? this.enabled,
      label: label == _unset ? this.label : label as String?,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
    'padHex': padHex,
    'role': role.label,
    'myOffset': myOffset,
    'theirOffset': theirOffset,
    'enabled': enabled,
    'label': label,
    'importedAt': importedAt.millisecondsSinceEpoch,
  };

  static OtpPad? fromJson(Map<String, dynamic> json) {
    final padHex = json['padHex'];
    if (padHex is! String || padHex.isEmpty) return null;
    try {
      return OtpPad(
        padHex: padHex,
        role: OtpPadRole.fromLabel((json['role'] as String?) ?? 'A'),
        myOffset: (json['myOffset'] as num?)?.toInt() ?? 0,
        theirOffset: (json['theirOffset'] as num?)?.toInt() ?? 0,
        enabled: (json['enabled'] as bool?) ?? true,
        label: json['label'] as String?,
        importedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['importedAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
