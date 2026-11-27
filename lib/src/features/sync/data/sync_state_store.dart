import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../global_providers/global_providers.dart';
import '../domain/sync_method.dart';

/// What the reader chose to sync (Sync → Suwayomi → What to sync).
enum SyncDataKind {
  library,
  progress,
  bookmarks,
  readerMeta,
  seriesMeta;

  String get preferenceKey => 'sync.prefs.$name';
}

/// Sync's own small state, kept in SharedPreferences under `sync.`.
///
/// The server's address and credentials are not here: Sync uses the same
/// connection settings as the rest of the app (design decision 9.2). The
/// backup address is the existing LAN/external pair (`ServerLanUrl`,
/// `ServerExternalUrl`).
class SyncStateStore {
  SyncStateStore(this._prefs);

  final SharedPreferences _prefs;

  static const methodKey = 'sync.method';
  static const serverIdentityKey = 'sync.suwayomi.serverIdentity';
  static const userIdKey = 'sync.suwayomi.userId';
  static const lastSuccessAtKey = 'sync.lastSuccessAt';
  static const lastErrorKey = 'sync.lastError';
  static const chapterCursorKey = 'sync.cursor.chapters';

  /// Keys that belong to the connected server; cleared on disconnect.
  static const _serverKeys = [
    serverIdentityKey,
    userIdKey,
    lastSuccessAtKey,
    lastErrorKey,
    chapterCursorKey,
  ];

  SyncMethod get method => SyncMethod.fromName(_prefs.getString(methodKey));

  Future<void> setMethod(SyncMethod method) => method == SyncMethod.none
      ? _prefs.remove(methodKey)
      : _prefs.setString(methodKey, method.name);

  /// The Kuchie instance ID stored on the server (global meta
  /// `kKuchieServerIdMetaKey`) when it was connected. Another value at the
  /// same address means a different or reset server.
  String? get serverIdentity => _prefs.getString(serverIdentityKey);

  Future<void> setServerIdentity(String identity) =>
      _prefs.setString(serverIdentityKey, identity);

  /// The account synced as, on servers with several users.
  String? get userId => _prefs.getString(userIdKey);

  Future<void> setUserId(String? userId) => userId == null
      ? _prefs.remove(userIdKey)
      : _prefs.setString(userIdKey, userId);

  DateTime? get lastSuccessAt => switch (_prefs.getInt(lastSuccessAtKey)) {
    final int millis => DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ),
    null => null,
  };

  /// The last cycle's error, for the log; cleared by a successful cycle.
  String? get lastError => _prefs.getString(lastErrorKey);

  Future<void> recordSuccess(DateTime at) async {
    await _prefs.setInt(lastSuccessAtKey, at.millisecondsSinceEpoch);
    await _prefs.remove(lastErrorKey);
  }

  Future<void> recordError(String message) =>
      _prefs.setString(lastErrorKey, message);

  /// Server time, in seconds, of the newest `lastReadAt` already pulled
  /// (spike S2: Suwayomi stores seconds).
  int? get chapterCursor => _prefs.getInt(chapterCursorKey);

  Future<void> setChapterCursor(int seconds) =>
      _prefs.setInt(chapterCursorKey, seconds);

  /// Every kind is synced until the reader turns it off.
  bool includes(SyncDataKind kind) =>
      _prefs.getBool(kind.preferenceKey) ?? true;

  Future<void> setIncludes(SyncDataKind kind, bool include) =>
      _prefs.setBool(kind.preferenceKey, include);

  /// Disconnect: sync turns off and forgets the server, keeping the
  /// reader's choice of what to sync for next time.
  Future<void> forgetServer() async {
    await setMethod(SyncMethod.none);
    for (final key in _serverKeys) {
      await _prefs.remove(key);
    }
  }
}

final syncStateStoreProvider = Provider<SyncStateStore>(
  (ref) => SyncStateStore(ref.watch(sharedPreferencesProvider)),
);
