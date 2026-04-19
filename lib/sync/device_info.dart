import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEVICE INFO
// Persistent device_id (generated on first boot) + static app metadata.
// The device_id is sent in every API call via X-Device-Id header and helps
// the backend correlate sync batches, logs, and conflicts per install.
// ─────────────────────────────────────────────────────────────────────────────

class DeviceInfo {
  DeviceInfo._();
  static final instance = DeviceInfo._();

  static const String appVersion = '1.0.0';
  static const _prefsKey = 'ecoflow.device_id';

  String? _cachedId;

  Future<String> deviceId() async {
    if (_cachedId != null) return _cachedId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _cachedId = id;
    return id;
  }

  /// Dev-only: clears the persisted device_id. Next call regenerates it.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _cachedId = null;
  }
}
