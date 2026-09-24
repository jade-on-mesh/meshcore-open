import 'dart:convert';

import '../models/otp_pad.dart';
import '../utils/app_logger.dart';
import 'prefs_manager.dart';

/// Persists OTP pads and their consumption offsets for contacts and
/// channels.
///
/// Follows the same self-identity scoping as [ContactSettingsStore] /
/// [ChannelSettingsStore] (keys are namespaced by a prefix of this device's
/// own public key, so switching companion radios doesn't mix pad state
/// between identities) but stores each pad as one JSON blob per target
/// rather than several scalar keys — a pad record is a single compound
/// object that's always read and written as a unit, so there's nothing to
/// gain from splitting it into separate booleans/ints the way the
/// Smaz/Cyr2Lat settings do.
///
/// Stored in plain SharedPreferences, unencrypted — a deliberate choice,
/// matching how every other per-contact/per-channel setting in this app is
/// already stored.
class OtpPadStore {
  static const String _contactKeyPrefix = 'contact_otp_pad_';
  static const String _channelKeyPrefix = 'channel_otp_pad_';

  String publicKeyHex = '';
  set setPublicKeyHex(String value) =>
      publicKeyHex = value.length > 10 ? value.substring(0, 10) : '';

  String _contactKey(String contactKeyHex) =>
      '$_contactKeyPrefix${publicKeyHex}_$contactKeyHex';

  String _channelKey(int channelIndex) =>
      '$_channelKeyPrefix${publicKeyHex}_$channelIndex';

  OtpPad? loadContactPad(String contactKeyHex) {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load OTP pad.');
      return null;
    }
    return _load(_contactKey(contactKeyHex));
  }

  Future<void> saveContactPad(String contactKeyHex, OtpPad pad) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save OTP pad.');
      return;
    }
    await _save(_contactKey(contactKeyHex), pad);
  }

  Future<void> clearContactPad(String contactKeyHex) async {
    if (publicKeyHex.isEmpty) return;
    await PrefsManager.instance.remove(_contactKey(contactKeyHex));
  }

  OtpPad? loadChannelPad(int channelIndex) {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot load OTP pad.');
      return null;
    }
    return _load(_channelKey(channelIndex));
  }

  Future<void> saveChannelPad(int channelIndex, OtpPad pad) async {
    if (publicKeyHex.isEmpty) {
      appLogger.warn('Public key hex is not set. Cannot save OTP pad.');
      return;
    }
    await _save(_channelKey(channelIndex), pad);
  }

  Future<void> clearChannelPad(int channelIndex) async {
    if (publicKeyHex.isEmpty) return;
    await PrefsManager.instance.remove(_channelKey(channelIndex));
  }

  OtpPad? _load(String key) {
    final raw = PrefsManager.instance.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return OtpPad.fromJson(json);
    } catch (e) {
      appLogger.warn('Failed to parse stored OTP pad for $key: $e');
      return null;
    }
  }

  Future<void> _save(String key, OtpPad pad) async {
    await PrefsManager.instance.setString(key, jsonEncode(pad.toJson()));
  }
}
