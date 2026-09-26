import 'dart:typed_data';

import '../connector/meshcore_protocol.dart' show hex2Uint8List;

/// Which half of a shared pad this device sends from.
///
/// Only meaningful when [OtpPad.mode] is [OtpPadMode.twoPartyHalfSplit]. A
/// shared pad is split in half at import time: Party A always sends from
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

/// Deterministic, symmetric Party A/B tie-break shared byte-for-byte with
/// the Lua app's `resolve_dm_role`: whichever side's own public-key hex
/// sorts lexicographically lower (ASCII, lowercased first) is Party A, the
/// other is Party B. Equal keys (should never happen for two distinct
/// devices) default to A.
///
/// Returns `null` — never a guess — when either side's public key isn't
/// available yet (e.g. the radio hasn't reported this device's own key).
/// Callers must fall back to letting the person pick manually rather than
/// defaulting to a role, since a same-role collision on both sides is not
/// detectable by the sync-check (it only catches a pad-length mismatch).
OtpPadRole? resolveDmRole({
  required String? selfPublicKeyHex,
  required String? contactPublicKeyHex,
}) {
  if (selfPublicKeyHex == null || selfPublicKeyHex.isEmpty) return null;
  if (contactPublicKeyHex == null || contactPublicKeyHex.isEmpty) return null;
  final mine = selfPublicKeyHex.toLowerCase();
  final theirs = contactPublicKeyHex.toLowerCase();
  return mine.compareTo(theirs) <= 0 ? OtpPadRole.a : OtpPadRole.b;
}

/// How a pad's bytes are consumed as messages are sent and received.
///
/// This mirrors WADAMESH OTP_2_RC15.lua's `pmi_v` party-mode setting and
/// its `pdib()` ("pad direction is back?") function:
///
///  - Two-party pads (`pmi_v` 2 or 3 in Lua) split the pad into a front
///    half and a back half: each side always sends from its own half and
///    decrypts incoming messages with the other's half. `pdib()` returns
///    true only for the party reading from the back.
///
///  - Multi/channel pads (`pmi_v` 1 in Lua — and Lua *forces* this mode
///    whenever the destination is a channel, via
///    `sync_party_mode_to_destination()`) have no role split at all:
///    `pdib()` always returns false, so sending AND receiving both consume
///    bytes from the same front of one shared pad. This is the only scheme
///    that generalizes past two parties — every participant must process
///    every channel message (their own included) in true chronological
///    order and consume the exact same bytes, or the group desyncs.
enum OtpPadMode {
  /// A/B half-split — exactly the two-party scheme this app already
  /// implemented. Used for contact (DM) pads.
  twoPartyHalfSplit,

  /// One shared front-of-pad counter, consumed identically by every send
  /// and every receive. Used for channel pads — forced, mirroring Lua's
  /// `sync_party_mode_to_destination()`.
  sharedSequential;

  static OtpPadMode fromName(String? value) {
    switch (value) {
      case 'sharedSequential':
        return OtpPadMode.sharedSequential;
      case 'twoPartyHalfSplit':
      default:
        // Also the correct default for pads persisted before this field
        // existed — they were all two-party contact pads.
        return OtpPadMode.twoPartyHalfSplit;
    }
  }
}

/// A shared one-time pad plus this device's consumption state for one
/// contact or one channel.
///
/// Stored unencrypted by default (matches every other per-contact /
/// per-channel setting in this app, which all live in plain
/// SharedPreferences) — a deliberate product decision, not an oversight —
/// UNLESS the OTP passphrase-lock feature has been enabled, in which case
/// [OtpPadStore] transparently wraps the persisted JSON in real
/// authenticated encryption (see `OtpPadStore`/`PassphraseLockCrypto`).
/// Nothing about this in-memory class changes either way; only how the
/// store serializes it does.
class OtpPad {
  /// The full shared pad, as lowercase hex. Never transmitted after import;
  /// only ever consumed locally to derive per-message key material.
  final String padHex;

  final OtpPadMode mode;

  /// Only meaningful when [mode] is [OtpPadMode.twoPartyHalfSplit].
  final OtpPadRole role;

  /// Bytes already consumed from THIS device's own sending half.
  /// [OtpPadMode.twoPartyHalfSplit] only — see [offset] for
  /// [OtpPadMode.sharedSequential].
  final int myOffset;

  /// Bytes already consumed from the OTHER party's half, i.e. how far this
  /// device has advanced while decrypting their incoming messages.
  /// [OtpPadMode.twoPartyHalfSplit] only — see [offset] for
  /// [OtpPadMode.sharedSequential].
  final int theirOffset;

  /// Bytes already consumed from the front of the ONE shared pad, by
  /// either sending or receiving — [OtpPadMode.sharedSequential] only.
  /// There is deliberately only one counter here: sending and receiving
  /// are the exact same consumption operation in this mode (see
  /// [takeSharedKeyBytes]/[advanceShared]), not two branches that happen
  /// to compute the same thing.
  final int offset;

  final bool enabled;

  /// Optional human label shown in the pad manager ("Camp trip pad", etc.)
  final String? label;

  final DateTime importedAt;

  const OtpPad({
    required this.padHex,
    this.mode = OtpPadMode.twoPartyHalfSplit,
    this.role = OtpPadRole.a,
    this.myOffset = 0,
    this.theirOffset = 0,
    this.offset = 0,
    this.enabled = true,
    this.label,
    required this.importedAt,
  });

  bool get isSharedSequential => mode == OtpPadMode.sharedSequential;

  int get totalBytes => padHex.length ~/ 2;
  int get halfBytes => totalBytes ~/ 2;

  int get myHalfStart =>
      isSharedSequential ? 0 : (role == OtpPadRole.a ? 0 : halfBytes);
  int get myHalfLength => isSharedSequential
      ? totalBytes
      : (role == OtpPadRole.a ? halfBytes : (totalBytes - halfBytes));

  int get theirHalfStart =>
      isSharedSequential ? 0 : (role == OtpPadRole.a ? halfBytes : 0);
  int get theirHalfLength => isSharedSequential
      ? totalBytes
      : (role == OtpPadRole.a ? (totalBytes - halfBytes) : halfBytes);

  /// The offset actually driving "my" consumption — [offset] in shared
  /// mode, [myOffset] in two-party mode.
  int get _myOffsetEffective => isSharedSequential ? offset : myOffset;
  int get _theirOffsetEffective => isSharedSequential ? offset : theirOffset;

  int get myBytesRemaining =>
      (myHalfLength - _myOffsetEffective).clamp(0, myHalfLength);
  int get theirBytesRemaining =>
      (theirHalfLength - _theirOffsetEffective).clamp(0, theirHalfLength);

  double get myUsageFraction => myHalfLength == 0
      ? 1.0
      : (_myOffsetEffective / myHalfLength).clamp(0.0, 1.0);
  double get theirUsageFraction => theirHalfLength == 0
      ? 1.0
      : (_theirOffsetEffective / theirHalfLength).clamp(0.0, 1.0);

  /// True once the pad (or, for two-party mode, either half) is fully
  /// consumed — the pad needs replacing.
  bool get isExhausted => myBytesRemaining == 0 || theirBytesRemaining == 0;

  Uint8List _takeBytes(int start, int length) {
    final all = hex2Uint8List(padHex);
    final end = (start + length).clamp(0, all.length);
    if (end <= start) return Uint8List(0);
    return all.sublist(start, end);
  }

  /// The next unused slice of THIS device's own sending half, [length]
  /// bytes long ([OtpPadMode.twoPartyHalfSplit] only). Does not mutate
  /// state — call [copyWith] (via the store) once the bytes are actually
  /// spent on a sent message.
  Uint8List takeMyKeyBytes(int length) =>
      _takeBytes(myHalfStart + myOffset, length);

  /// The next unused slice of the OTHER party's half, [length] bytes long,
  /// used to decrypt one of their incoming messages
  /// ([OtpPadMode.twoPartyHalfSplit] only).
  Uint8List takeTheirKeyBytes(int length) =>
      _takeBytes(theirHalfStart + theirOffset, length);

  /// The next unused slice of the ONE shared pad, [length] bytes long
  /// ([OtpPadMode.sharedSequential] only). Used identically for both
  /// sending and receiving — see the class doc on [offset].
  Uint8List takeSharedKeyBytes(int length) => _takeBytes(offset, length);

  /// Returns a copy with [offset] advanced by [length] bytes
  /// ([OtpPadMode.sharedSequential] only).
  OtpPad advanceShared(int length) => copyWith(offset: offset + length);

  OtpPad copyWith({
    String? padHex,
    OtpPadMode? mode,
    OtpPadRole? role,
    int? myOffset,
    int? theirOffset,
    int? offset,
    bool? enabled,
    Object? label = _unset,
    DateTime? importedAt,
  }) {
    return OtpPad(
      padHex: padHex ?? this.padHex,
      mode: mode ?? this.mode,
      role: role ?? this.role,
      myOffset: myOffset ?? this.myOffset,
      theirOffset: theirOffset ?? this.theirOffset,
      offset: offset ?? this.offset,
      enabled: enabled ?? this.enabled,
      label: label == _unset ? this.label : label as String?,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
    'padHex': padHex,
    'mode': mode.name,
    'role': role.label,
    'myOffset': myOffset,
    'theirOffset': theirOffset,
    'offset': offset,
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
        // Pads persisted before `mode` existed have no field here at all —
        // they were all two-party contact pads, which is exactly what
        // OtpPadMode.fromName(null) defaults to.
        mode: OtpPadMode.fromName(json['mode'] as String?),
        role: OtpPadRole.fromLabel((json['role'] as String?) ?? 'A'),
        myOffset: (json['myOffset'] as num?)?.toInt() ?? 0,
        theirOffset: (json['theirOffset'] as num?)?.toInt() ?? 0,
        offset: (json['offset'] as num?)?.toInt() ?? 0,
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
