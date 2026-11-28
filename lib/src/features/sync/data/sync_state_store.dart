import 'dart:convert';

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

/// What the first sync does with two different libraries (design 3.3).
enum ConnectChoice {
  /// Keep everything from both.
  merge,

  /// The server's library replaces this iPhone's. Downloads stay.
  useServer,

  /// This iPhone's library replaces the server's.
  useLocal;

  static ConnectChoice? fromName(String? name) =>
      values.where((choice) => choice.name == name).firstOrNull;
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
  static const explainerSeenKey = 'sync.explainerSeen';
  static const connectChoiceKey = 'sync.suwayomi.connectChoice';
  static const lastFullSyncAtKey = 'sync.lastFullSyncAt';
  static const logKey = 'sync.log';
  static const seriesErrorsKey = 'sync.seriesErrors';
  static const moveSuggestedKey = 'sync.moveSuggested';

  /// Cycles the sync log keeps (design 3.2, Advanced → Sync log).
  static const logLength = 200;

  /// Keys that belong to the connected server; cleared on disconnect.
  static const _serverKeys = [
    connectChoiceKey,
    serverIdentityKey,
    userIdKey,
    lastSuccessAtKey,
    lastErrorKey,
    chapterCursorKey,
    lastFullSyncAtKey,
    logKey,
    seriesErrorsKey,
    moveSuggestedKey,
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

  /// The last cycle that compared every chapter, not just recent reads.
  DateTime? get lastFullSyncAt => switch (_prefs.getInt(lastFullSyncAtKey)) {
    final int millis => DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ),
    null => null,
  };

  Future<void> setLastFullSyncAt(DateTime at) =>
      _prefs.setInt(lastFullSyncAtKey, at.millisecondsSinceEpoch);

  /// Every kind is synced until the reader turns it off, except rating,
  /// tags and notes, which start off (design 3.4) until the reader turns
  /// them on or the server turns out to hold them already.
  bool includes(SyncDataKind kind) =>
      _prefs.getBool(kind.preferenceKey) ?? kind != SyncDataKind.seriesMeta;

  /// Whether [kind] was set, by the reader or by sync, rather than default.
  bool choseIncludes(SyncDataKind kind) =>
      _prefs.containsKey(kind.preferenceKey);

  Future<void> setIncludes(SyncDataKind kind, bool include) =>
      _prefs.setBool(kind.preferenceKey, include);

  /// The last cycles, newest first.
  List<SyncLogEntry> get log {
    final stored = _prefs.getStringList(logKey) ?? const [];
    return [for (final line in stored) ?SyncLogEntry.decode(line)];
  }

  Future<void> appendLog(SyncLogEntry entry) => _prefs.setStringList(logKey, [
    entry.encode(),
    ...(_prefs.getStringList(logKey) ?? const []).take(logLength - 1),
  ]);

  /// Local series id → why the last cycle could not sync it.
  Map<String, String> get seriesErrors {
    final stored = _prefs.getString(seriesErrorsKey);
    if (stored == null) return const {};
    try {
      return switch (jsonDecode(stored)) {
        final Map<String, Object?> map => {
          for (final MapEntry(:key, :value) in map.entries)
            if (value is String) key: value,
        },
        _ => const {},
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> setSeriesErrors(Map<String, String> errors) => errors.isEmpty
      ? _prefs.remove(seriesErrorsKey)
      : _prefs.setString(seriesErrorsKey, jsonEncode(errors));

  /// What the first sync will do, chosen when connecting; the engine reads
  /// it.
  ConnectChoice? get connectChoice =>
      ConnectChoice.fromName(_prefs.getString(connectChoiceKey));

  Future<void> setConnectChoice(ConnectChoice choice) =>
      _prefs.setString(connectChoiceKey, choice.name);

  /// Whether the one-time "Move to server" card was answered.
  bool get moveSuggested => _prefs.getBool(moveSuggestedKey) ?? false;

  Future<void> setMoveSuggested() => _prefs.setBool(moveSuggestedKey, true);

  /// Whether the Sync page has played its three-step explainer once.
  bool get explainerSeen => _prefs.getBool(explainerSeenKey) ?? false;

  Future<void> setExplainerSeen() => _prefs.setBool(explainerSeenKey, true);

  /// Disconnect: sync turns off and forgets the server, keeping the
  /// reader's choice of what to sync for next time.
  Future<void> forgetServer() async {
    await setMethod(SyncMethod.none);
    for (final key in _serverKeys) {
      await _prefs.remove(key);
    }
  }
}

/// One cycle in the sync log.
class SyncLogEntry {
  const SyncLogEntry({
    required this.at,
    required this.outcome,
    this.pulled = 0,
    this.pushed = 0,
    this.seriesErrors = 0,
    this.message,
  });

  final DateTime at;

  /// A `SyncOutcome` name: synced, unreachable, actionNeeded, failed,
  /// cancelled.
  final String outcome;
  final int pulled;
  final int pushed;
  final int seriesErrors;
  final String? message;

  String encode() => jsonEncode({
    'at': at.millisecondsSinceEpoch,
    'outcome': outcome,
    'pulled': pulled,
    'pushed': pushed,
    'errors': seriesErrors,
    'message': ?message,
  });

  static SyncLogEntry? decode(String line) {
    try {
      return switch (jsonDecode(line)) {
        {'at': final int at, 'outcome': final String outcome} &&
            final Map map =>
          SyncLogEntry(
            at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
            outcome: outcome,
            pulled: map['pulled'] as int? ?? 0,
            pushed: map['pushed'] as int? ?? 0,
            seriesErrors: map['errors'] as int? ?? 0,
            message: map['message'] as String?,
          ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

final syncStateStoreProvider = Provider<SyncStateStore>(
  (ref) => SyncStateStore(ref.watch(sharedPreferencesProvider)),
);
