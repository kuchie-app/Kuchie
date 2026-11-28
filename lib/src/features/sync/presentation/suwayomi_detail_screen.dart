import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../local_collection/presentation/local_ui.dart';
import '../../security/security_settings_screen.dart';
import '../../settings/data/server_connection/server_url.dart';
import '../../settings/presentation/connection/connection_screen.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../controller/sync_controller.dart';
import '../controller/unsynced_series.dart';
import '../data/sync_state_store.dart';
import 'extension_suggestions.dart';
import 'sync_status_icon.dart';

void _push(BuildContext context, Widget screen) => unawaited(
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
);

/// Sync → Suwayomi (design 3.4): only what needs attention up front; the
/// switches live in Advanced.
class SuwayomiDetailScreen extends ConsumerWidget {
  const SuwayomiDetailScreen({super.key, this.onDisconnect});

  /// Shown as the last row when set.
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unsynced = ref.watch(unsyncedSeriesProvider).value ?? const [];
    final address = ref.watch(serverUrlProvider);
    return SettingsListPage(
      title: localText(context, 'Suwayomi server', 'Server Suwayomi'),
      children: [
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: Icons.dns_outlined,
              title: localText(context, 'Address', 'Alamat'),
              subtitle: address,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const ConnectionScreen()),
            ),
            SettingsGroupRow(
              icon: Icons.sync_rounded,
              title: localText(context, 'Status', 'Status'),
              subtitle: syncSummary(context, ref.watch(syncControllerProvider)),
              onTap: () => unawaited(
                ref.read(syncControllerProvider.notifier).syncNow(),
              ),
            ),
          ],
        ),
        if (unsynced.isNotEmpty) ...[
          SettingsGroupHeading(
            label: localText(context, 'Needs attention', 'Perlu perhatian'),
          ),
          SettingsGroupCard(
            children: [
              SettingsGroupRow(
                icon: Icons.phone_iphone_outlined,
                title: localText(
                  context,
                  '${unsynced.length} series only on this iPhone',
                  '${unsynced.length} series hanya di iPhone',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _push(context, const UnsyncedSeriesScreen()),
              ),
            ],
          ),
        ],
        const ExtensionSuggestionsSection(),
        const SizedBox(height: 8),
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: Icons.tune_rounded,
              title: localText(context, 'Advanced', 'Lanjutan'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const SuwayomiAdvancedScreen()),
            ),
            SettingsGroupRow(
              icon: Icons.receipt_long_outlined,
              title: localText(context, 'Sync log', 'Log sinkronisasi'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const SyncLogScreen()),
            ),
          ],
        ),
        if (onDisconnect case final disconnect?) ...[
          const SizedBox(height: 8),
          SettingsGroupCard(
            children: [
              ListTile(
                leading: Icon(
                  Icons.link_off_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  localText(context, 'Disconnect', 'Putuskan koneksi'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: disconnect,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Sync → Suwayomi → Advanced: what to sync, and the connection.
class SuwayomiAdvancedScreen extends ConsumerStatefulWidget {
  const SuwayomiAdvancedScreen({super.key});

  @override
  ConsumerState<SuwayomiAdvancedScreen> createState() =>
      _SuwayomiAdvancedScreenState();
}

class _SuwayomiAdvancedScreenState
    extends ConsumerState<SuwayomiAdvancedScreen> {
  String _label(SyncDataKind kind) => switch (kind) {
    SyncDataKind.library => localText(
      context,
      'Library & categories',
      'Library & kategori',
    ),
    SyncDataKind.progress => localText(
      context,
      'Reading progress & history',
      'Progres baca & riwayat',
    ),
    SyncDataKind.bookmarks => localText(
      context,
      'Chapter bookmarks',
      'Bookmark chapter',
    ),
    SyncDataKind.readerMeta => localText(
      context,
      'Reader settings per series',
      'Setelan reader per series',
    ),
    SyncDataKind.seriesMeta => localText(
      context,
      'Rating, tags & notes',
      'Rating, tag & catatan',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(syncStateStoreProvider);
    return SettingsListPage(
      title: localText(context, 'Advanced', 'Lanjutan'),
      children: [
        SettingsGroupHeading(
          label: localText(context, 'What syncs', 'Yang disinkronkan'),
        ),
        SettingsGroupCard(
          children: [
            for (final kind in SyncDataKind.values)
              SwitchListTile(
                title: Text(_label(kind)),
                value: store.includes(kind),
                onChanged: (value) async {
                  await store.setIncludes(kind, value);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
        SettingsGroupHeading(
          label: localText(context, 'Connection', 'Koneksi'),
        ),
        SettingsGroupCard(
          children: [
            SettingsGroupRow(
              icon: Icons.public_rounded,
              title: localText(
                context,
                'Backup address (away from home)',
                'Alamat cadangan (di luar rumah)',
              ),
              subtitle: localText(
                context,
                'Tried when the main address does not answer.',
                'Dicoba kalau alamat utama tidak menjawab.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _push(context, const ConnectionScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

/// Needs attention → series only on this iPhone, by reason.
class UnsyncedSeriesScreen extends ConsumerWidget {
  const UnsyncedSeriesScreen({super.key});

  String _reason(BuildContext context, UnsyncedReason reason) =>
      switch (reason) {
        UnsyncedReason.importedFile => localText(
          context,
          'File imports: the server has no source for them',
          'File impor: server tidak punya source-nya',
        ),
        UnsyncedReason.kuchieRepo => localText(
          context,
          'Kuchie repo sources: Suwayomi cannot read them',
          'Source repo Kuchie: Suwayomi tidak bisa membacanya',
        ),
        UnsyncedReason.notOnServer => localText(
          context,
          "The server couldn't add them: install their extension there",
          'Server gagal menambahkannya: pasang extension-nya di server',
        ),
        UnsyncedReason.requestFailed => localText(
          context,
          'A request failed: sync tries again',
          'Permintaan gagal: sync mencoba lagi',
        ),
        UnsyncedReason.waiting => localText(
          context,
          'Waiting for the next sync',
          'Menunggu sync berikutnya',
        ),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unsynced = ref.watch(unsyncedSeriesProvider).value ?? const [];
    final byReason = <UnsyncedReason, List<UnsyncedSeries>>{};
    for (final entry in unsynced) {
      byReason.putIfAbsent(entry.reason, () => []).add(entry);
    }
    final retryable = byReason.keys.any((reason) => reason.retryable);
    return SettingsListPage(
      title: localText(context, 'Only on this iPhone', 'Hanya di iPhone'),
      actions: [
        if (retryable)
          TextButton(
            onPressed: () async {
              await ref.read(syncControllerProvider.notifier).syncNow();
              ref.invalidate(unsyncedSeriesProvider);
            },
            child: Text(localText(context, 'Try again', 'Coba lagi')),
          ),
      ],
      children: [
        if (unsynced.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              localText(
                context,
                'Every series is on the server.',
                'Semua series sudah ada di server.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        for (final MapEntry(key: reason, value: series)
            in byReason.entries) ...[
          SettingsGroupHeading(label: _reason(context, reason)),
          SettingsGroupCard(
            children: [
              for (final entry in series)
                ListTile(title: Text(entry.series.title)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Advanced → Sync log: the last 200 cycles.
class SyncLogScreen extends ConsumerWidget {
  const SyncLogScreen({super.key});

  String _outcome(BuildContext context, String outcome) => switch (outcome) {
    'synced' => localText(context, 'Synced', 'Tersinkron'),
    'unreachable' => localText(
      context,
      'Server not reachable',
      'Server tidak terjangkau',
    ),
    'actionNeeded' => localText(context, 'Needs you', 'Perlu tindakan'),
    'cancelled' => localText(context, 'Stopped', 'Dihentikan'),
    _ => localText(context, 'Failed', 'Gagal'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(syncStateStoreProvider).log;
    final local = MaterialLocalizations.of(context);
    return SettingsListPage(
      title: localText(context, 'Sync log', 'Log sinkronisasi'),
      children: [
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              localText(context, 'No syncs yet.', 'Belum ada sinkronisasi.'),
              textAlign: TextAlign.center,
            ),
          ),
        if (log.isNotEmpty)
          SettingsGroupCard(
            children: [
              for (final entry in log)
                ListTile(
                  dense: true,
                  title: Text(_outcome(context, entry.outcome)),
                  subtitle: Text(
                    [
                      '${local.formatShortDate(entry.at.toLocal())} '
                          '${local.formatTimeOfDay(TimeOfDay.fromDateTime(entry.at.toLocal()))}',
                      if (entry.pulled + entry.pushed > 0)
                        localText(
                          context,
                          '${entry.pulled} in, ${entry.pushed} out',
                          '${entry.pulled} masuk, ${entry.pushed} keluar',
                        ),
                      if (entry.serverOnly > 0)
                        localText(
                          context,
                          '${entry.serverOnly} read through the server',
                          '${entry.serverOnly} dibaca lewat server',
                        ),
                      if (entry.seriesErrors > 0)
                        localText(
                          context,
                          '${entry.seriesErrors} series not synced',
                          '${entry.seriesErrors} series tidak tersinkron',
                        ),
                      ?entry.message,
                    ].join(' · '),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
