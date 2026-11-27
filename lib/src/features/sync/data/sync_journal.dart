import 'dart:convert';

import 'package:drift/drift.dart';

import '../../local_collection/data/local_catalog.dart';
import '../domain/sync_change.dart';

/// The sync tables in the catalog database: the outbox the catalog fills,
/// links to remote ids, the last agreed state, and chapter transfers.
///
/// [backend] names one sync target, such as a Suwayomi server; links and base
/// values for one backend never mix with another's.
class SyncJournal {
  SyncJournal(this._catalog);

  final LocalCatalog _catalog;

  Future<T> _run<T>(Future<T> Function(DatabaseConnectionUser db) action) =>
      _catalog.withSyncTables(action);

  /// Outbox entries, oldest first.
  Future<List<SyncChange>> pending({int limit = 500}) => _run(
    (db) async => _changes(
      await db
          .customSelect(
            'SELECT * FROM sync_changes ORDER BY seq LIMIT ?',
            variables: [Variable.withInt(limit)],
          )
          .get(),
    ),
  );

  /// The newest entry for each changed key, in the order of those entries.
  /// The push reads current local state, so older entries add nothing.
  Future<List<SyncChange>> coalesced() => _run(
    (db) async => _changes(
      await db.customSelect('''
        SELECT * FROM sync_changes WHERE seq IN (
          SELECT MAX(seq) FROM sync_changes GROUP BY kind, key
        ) ORDER BY seq
        ''').get(),
    ),
  );

  /// Drops entries up to and including [seq], once they are pushed.
  Future<void> trimThrough(int seq) => _run(
    (db) =>
        db.customStatement('DELETE FROM sync_changes WHERE seq <= ?', [seq]),
  );

  /// Empties the outbox; a full scan replaces it when sync is turned on.
  Future<void> clearChanges() =>
      _run((db) => db.customStatement('DELETE FROM sync_changes'));

  List<SyncChange> _changes(List<QueryRow> rows) => [
    for (final row in rows)
      if ((
            SyncRecordKind.parse(row.read<String>('kind')),
            SyncChangeOp.parse(row.read<String>('op')),
          )
          case (final kind?, final op?))
        SyncChange(
          seq: row.read<int>('seq'),
          kind: kind,
          key: row.read<String>('key'),
          op: op,
          changedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('changed_at'),
            isUtc: true,
          ),
        ),
  ];

  /// Every link for [backend].
  Future<List<SyncLink>> links(String backend) => _run(
    (db) async => [
      for (final row
          in await db
              .customSelect(
                'SELECT * FROM sync_links WHERE backend = ? ORDER BY kind, local_key',
                variables: [Variable.withString(backend)],
              )
              .get())
        if (SyncLinkKind.parse(row.read<String>('kind')) case final kind?)
          SyncLink(
            kind: kind,
            localKey: row.read<String>('local_key'),
            remoteId: row.read<String>('remote_id'),
          ),
    ],
  );

  /// The local key linked to [remoteId], if any.
  Future<String?> localKeyFor(
    String backend,
    SyncLinkKind kind,
    String remoteId,
  ) => _run(
    (db) async =>
        (await db
                .customSelect(
                  'SELECT local_key FROM sync_links '
                  'WHERE backend = ? AND kind = ? AND remote_id = ? LIMIT 1',
                  variables: [
                    Variable.withString(backend),
                    Variable.withString(kind.name),
                    Variable.withString(remoteId),
                  ],
                )
                .getSingleOrNull())
            ?.read<String>('local_key'),
  );

  Future<void> putLink(String backend, SyncLink link) => _run(
    (db) => db.customStatement(
      '''
      INSERT INTO sync_links (backend, kind, local_key, remote_id)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(backend, kind, local_key) DO UPDATE SET
        remote_id = excluded.remote_id
      ''',
      [backend, link.kind.name, link.localKey, link.remoteId],
    ),
  );

  Future<void> removeLinks(String backend) => _run(
    (db) => db.customStatement('DELETE FROM sync_links WHERE backend = ?', [
      backend,
    ]),
  );

  /// The state of [key] that both sides last agreed on, or null before the
  /// first sync of it.
  Future<Map<String, Object?>?> base(
    String backend,
    SyncRecordKind kind,
    String key,
  ) => _run((db) async {
    final row = await db
        .customSelect(
          'SELECT value FROM sync_base WHERE backend = ? AND kind = ? AND key = ?',
          variables: [
            Variable.withString(backend),
            Variable.withString(kind.storedName),
            Variable.withString(key),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;
    try {
      return switch (jsonDecode(row.read<String>('value'))) {
        final Map<String, Object?> value => value,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  });

  Future<void> putBase(
    String backend,
    SyncRecordKind kind,
    String key,
    Map<String, Object?> value,
  ) => _run(
    (db) => db.customStatement(
      '''
      INSERT INTO sync_base (backend, kind, key, value) VALUES (?, ?, ?, ?)
      ON CONFLICT(backend, kind, key) DO UPDATE SET value = excluded.value
      ''',
      [backend, kind.storedName, key, jsonEncode(value)],
    ),
  );

  Future<void> removeBase(String backend, SyncRecordKind kind, String key) =>
      _run(
        (db) => db.customStatement(
          'DELETE FROM sync_base WHERE backend = ? AND kind = ? AND key = ?',
          [backend, kind.storedName, key],
        ),
      );

  /// Forgets links and agreed state for [backend], as when it is turned off
  /// or another server is chosen. The outbox and transfers stay.
  Future<void> clearBackend(String backend) => _run((db) async {
    await db.customStatement('DELETE FROM sync_links WHERE backend = ?', [
      backend,
    ]);
    await db.customStatement('DELETE FROM sync_base WHERE backend = ?', [
      backend,
    ]);
  });

  /// Transfers, oldest change first, optionally only those in [states].
  Future<List<SyncTransfer>> transfers({Set<SyncTransferState>? states}) =>
      _run((db) async {
        final rows = await db
            .customSelect('SELECT * FROM sync_transfers ORDER BY updated_at')
            .get();
        return [
          for (final row in rows)
            if (SyncTransferState.parse(row.read<String>('state'))
                case final state? when states == null || states.contains(state))
              SyncTransfer(
                seriesId: row.read<String>('series_id'),
                chapterId: row.read<String>('chapter_id'),
                remoteChapterId: row.readNullable<int>('remote_chapter_id'),
                keepLocal: row.read<int>('keep_local') != 0,
                state: state,
                error: row.readNullable<String>('error'),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  row.read<int>('updated_at'),
                  isUtc: true,
                ),
              ),
        ];
      });

  /// Adds [transfer] or replaces the one for the same chapter.
  Future<void> putTransfer(SyncTransfer transfer) => _run(
    (db) => db.customStatement(
      '''
      INSERT INTO sync_transfers
        (series_id, chapter_id, remote_chapter_id, keep_local, state, error, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(series_id, chapter_id) DO UPDATE SET
        remote_chapter_id = excluded.remote_chapter_id,
        keep_local = excluded.keep_local,
        state = excluded.state,
        error = excluded.error,
        updated_at = excluded.updated_at
      ''',
      [
        transfer.seriesId,
        transfer.chapterId,
        transfer.remoteChapterId,
        transfer.keepLocal ? 1 : 0,
        transfer.state.name,
        transfer.error,
        transfer.updatedAt.millisecondsSinceEpoch,
      ],
    ),
  );

  Future<void> removeTransfer(String seriesId, String chapterId) => _run(
    (db) => db.customStatement(
      'DELETE FROM sync_transfers WHERE series_id = ? AND chapter_id = ?',
      [seriesId, chapterId],
    ),
  );
}

class SyncLink {
  const SyncLink({
    required this.kind,
    required this.localKey,
    required this.remoteId,
  });

  final SyncLinkKind kind;
  final String localKey;
  final String remoteId;

  @override
  bool operator ==(Object other) =>
      other is SyncLink &&
      other.kind == kind &&
      other.localKey == localKey &&
      other.remoteId == remoteId;

  @override
  int get hashCode => Object.hash(kind, localKey, remoteId);

  @override
  String toString() => 'SyncLink(${kind.name}, $localKey, $remoteId)';
}

enum SyncTransferState {
  queued,
  requested,
  verified,
  done,
  failed;

  static SyncTransferState? parse(String name) =>
      values.where((state) => state.name == name).firstOrNull;
}

/// A chapter moving between this iPhone and a backend.
class SyncTransfer {
  const SyncTransfer({
    required this.seriesId,
    required this.chapterId,
    required this.keepLocal,
    required this.state,
    required this.updatedAt,
    this.remoteChapterId,
    this.error,
  });

  final String seriesId;
  final String chapterId;
  final int? remoteChapterId;

  /// Whether the saved copy here stays after the transfer is verified.
  final bool keepLocal;
  final SyncTransferState state;
  final String? error;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is SyncTransfer &&
      other.seriesId == seriesId &&
      other.chapterId == chapterId &&
      other.remoteChapterId == remoteChapterId &&
      other.keepLocal == keepLocal &&
      other.state == state &&
      other.error == error &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    seriesId,
    chapterId,
    remoteChapterId,
    keepLocal,
    state,
    error,
    updatedAt,
  );

  @override
  String toString() =>
      'SyncTransfer($seriesId, $chapterId, ${state.name}, '
      'remote: $remoteChapterId, keepLocal: $keepLocal, error: $error)';
}
