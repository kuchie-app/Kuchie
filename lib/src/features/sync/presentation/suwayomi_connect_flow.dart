import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../global_providers/global_providers.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../../offline/data/background/background_download_controller_shim.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import '../../security/security_settings_screen.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../controller/connect_analysis.dart';
import '../controller/extension_sync.dart';
import '../controller/sync_controller.dart';
import '../data/suwayomi/suwayomi_reachability.dart';
import '../data/sync_state_store.dart';
import '../domain/diagram/sync_methods.dart';
import '../domain/diagram/sync_scene.dart';
import 'diagram/sync_diagram.dart';

/// Opens the Suwayomi connect flow; it returns the saved choice.
Future<ConnectChoice?> openSuwayomiConnect(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<ConnectChoice>(
        builder: (_) => const SuwayomiConnectFlow(),
      ),
    );

const _prefix = 'sync.connect';
const _signedInKey = '$_prefix.signedIn';

Future<void> _finishSyncSignIn(
  WidgetRef ref,
  Future<void> Function() signIn,
) async {
  final preferences = ref.read(sharedPreferencesProvider);
  await ref.read(backgroundDownloadControllerProvider).changeIdentity(() async {
    await signIn();
    await preferences.setBool(_signedInKey, true);
    await preferences.setString('$_prefix.pendingProbe', '');
    await preferences.setBool('$_prefix.advanceAfterProbe', false);
  });
}

bool _syncSignedIn(SharedPreferences preferences) =>
    preferences.getBool(_signedInKey) == true;

/// The onboarding server step, keeping its draft under `sync.connect.` so
/// onboarding's own state is never touched.
const syncServerStepHost = ServerStepHost(
  prefix: _prefix,
  finishSignIn: _finishSyncSignIn,
  signedIn: _syncSignedIn,
);

enum _Step { server, analysis, installing, saved }

/// Connecting Suwayomi (design 3.3): address, sign-in, then an analysis that
/// writes nothing and ends in a report. The final button saves what the
/// first sync will do; the engine (PR 8) carries it out.
class SuwayomiConnectFlow extends ConsumerStatefulWidget {
  const SuwayomiConnectFlow({super.key, this.skipServerStep = false});

  /// Starts at the analysis, for a server that is already signed in.
  final bool skipServerStep;

  @override
  ConsumerState<SuwayomiConnectFlow> createState() =>
      _SuwayomiConnectFlowState();
}

class _SuwayomiConnectFlowState extends ConsumerState<SuwayomiConnectFlow> {
  late _Step _step = widget.skipServerStep ? _Step.analysis : _Step.server;
  int _nextRequest = 0;
  String? _activity;
  ConnectChoice _choice = ConnectChoice.merge;
  ConnectChoice? _saved;
  String? _installingName;
  ServerExtensionsReport? _installed;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(sharedPreferencesProvider).remove(_signedInKey));
  }

  Future<void> _save(ConnectChoice choice, ConnectAnalysis analysis) async {
    await ref.read(syncStateStoreProvider).setConnectChoice(choice);
    // The server's extensions first, so the first sync brings in every
    // series it can read (design 3.5: both sides read the same series).
    if (analysis.extensions case final extensions?
        when analysis.toInstall.isNotEmpty) {
      if (mounted) setState(() => _step = _Step.installing);
      try {
        _installed = await ref
            .read(extensionSyncProvider)
            .installFromServer(
              extensions,
              syncAfter: false,
              onStep: (name) {
                if (mounted) setState(() => _installingName = name);
              },
            );
      } catch (error) {
        _installed = ServerExtensionsReport(failed: {'': '$error'});
      }
      ref.invalidate(extensionSuggestionsProvider);
    }
    // The first sync runs in the background; the Sync page shows it.
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
    if (mounted) {
      setState(() {
        _saved = choice;
        _step = _Step.saved;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SettingsListPage(
    title: localText(context, 'Connect Suwayomi', 'Hubungkan Suwayomi'),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: switch (_step) {
          _Step.server => _serverStep(context),
          _Step.analysis => _AnalysisStep(
            choice: _choice,
            onChoice: (choice) => setState(() => _choice = choice),
            onSave: _save,
            onSignInAgain: () => setState(() => _step = _Step.server),
          ),
          _Step.installing => _InstallingStep(name: _installingName),
          _Step.saved => _SavedStep(
            choice: _saved!,
            installed: _installed,
            onDone: () => Navigator.of(context).pop(_saved),
          ),
        },
      ),
    ],
  );

  Widget _serverStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ServerStep(
        host: syncServerStepHost,
        nextRequest: _nextRequest,
        onActivityChanged: (activity) {
          if (mounted) setState(() => _activity = activity);
        },
        onSignedIn: () {
          if (!mounted) return;
          ref.invalidate(connectAnalysisProvider);
          setState(() {
            _activity = null;
            _step = _Step.analysis;
          });
        },
      ),
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _activity == null
            ? () => setState(() => _nextRequest++)
            : null,
        child: Text(_activity ?? localText(context, 'Continue', 'Lanjut')),
      ),
    ],
  );
}

class _AnalysisStep extends ConsumerWidget {
  const _AnalysisStep({
    required this.choice,
    required this.onChoice,
    required this.onSave,
    required this.onSignInAgain,
  });

  final ConnectChoice choice;
  final ValueChanged<ConnectChoice> onChoice;
  final void Function(ConnectChoice choice, ConnectAnalysis analysis) onSave;
  final VoidCallback onSignInAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(connectAnalysisProvider);
    final theme = Theme.of(context);
    return analysis.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SyncDiagram(
            scene: sceneFor(suwayomiMethod, SyncStatusKind.analyzing),
          ),
          Text(
            localText(context, 'Checking the server…', 'Memeriksa server…'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            localText(
              context,
              'Comparing the library on this iPhone with the one on the '
                  'server. Nothing changes yet.',
              'Membandingkan library di iPhone dan di server. Belum ada yang '
                  'diubah.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      error: (error, _) {
        final signIn = error is ConnectFailure && error.signInNeeded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              signIn
                  ? localText(
                      context,
                      'The server asked to sign in again.',
                      'Server meminta masuk lagi.',
                    )
                  : error is ConnectFailure &&
                        error.reachability is SuwayomiUnreachable
                  ? localText(
                      context,
                      "The server can't be reached.",
                      'Server tidak terjangkau.',
                    )
                  : localText(
                      context,
                      "The server's library couldn't be read.",
                      'Library server tidak bisa dibaca.',
                    ),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: signIn
                  ? onSignInAgain
                  : () => ref.invalidate(connectAnalysisProvider),
              child: Text(
                signIn
                    ? localText(context, 'Sign in again', 'Masuk lagi')
                    : localText(context, 'Try again', 'Coba lagi'),
              ),
            ),
          ],
        );
      },
      data: (analysis) => ConnectReport(
        analysis: analysis,
        choice: choice,
        onChoice: onChoice,
        onSave: (choice) => onSave(choice, analysis),
      ),
    );
  }
}

/// The analysis numbers and, for libraries that differ, the three choices.
class ConnectReport extends StatelessWidget {
  const ConnectReport({
    super.key,
    required this.analysis,
    required this.choice,
    required this.onChoice,
    required this.onSave,
  });

  final ConnectAnalysis analysis;
  final ConnectChoice choice;
  final ValueChanged<ConnectChoice> onChoice;
  final ValueChanged<ConnectChoice> onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = analysis;
    String series(int count) =>
        localText(context, '$count series', '$count series');
    final (title, body) = switch (a.branch) {
      ConnectBranch.localEmpty => (
        localText(context, 'Copy the server library', 'Salin library server'),
        localText(
          context,
          'This iPhone has no series yet, so the first sync copies '
              '${series(a.remoteCount)} from the server.',
          'iPhone ini belum punya series, jadi sync pertama menyalin '
              '${series(a.remoteCount)} dari server.',
        ),
      ),
      ConnectBranch.remoteEmpty => (
        localText(context, 'Send this library', 'Kirim library ini'),
        localText(
          context,
          'The server has no series yet, so the first sync sends '
              '${series(a.sendable + a.matched)} from this iPhone. '
              '${a.unsendable} stay only on this iPhone.',
          'Server belum punya series, jadi sync pertama mengirim '
              '${series(a.sendable + a.matched)} dari iPhone. '
              '${a.unsendable} tetap hanya di iPhone.',
        ),
      ),
      ConnectBranch.allMatched => (
        localText(context, 'Already the same', 'Sudah sama'),
        localText(
          context,
          'Both libraries have the same ${series(a.matched)}. Sync keeps '
              'them that way.',
          'Kedua library punya ${series(a.matched)} yang sama. Sync '
              'menjaganya tetap sama.',
        ),
      ),
      ConnectBranch.differs => (
        localText(context, 'The libraries differ', 'Library berbeda'),
        localText(
          context,
          'Choose how the first sync puts them together.',
          'Pilih cara sync pertama menyatukannya.',
        ),
      ),
    };
    final implied = a.impliedChoice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(body, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        _Numbers(analysis: a),
        if (a.toInstall.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ExtensionsToInstall(analysis: a),
        ],
        if (implied == null) ...[
          const SizedBox(height: 16),
          RadioGroup<ConnectChoice>(
            groupValue: choice,
            onChanged: (value) {
              if (value != null) onChoice(value);
            },
            child: Column(
              children: [
                for (final option in ConnectChoice.values)
                  RadioListTile<ConnectChoice>(
                    contentPadding: EdgeInsets.zero,
                    value: option,
                    title: Text(_choiceTitle(context, option)),
                    subtitle: Text(_choiceNote(context, option, a)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => onSave(implied ?? choice),
          child: Text(localText(context, 'Start sync', 'Mulai sinkronisasi')),
        ),
      ],
    );
  }
}

String _choiceTitle(BuildContext context, ConnectChoice choice) =>
    switch (choice) {
      ConnectChoice.merge => localText(context, 'Merge', 'Gabungkan'),
      ConnectChoice.useServer => localText(
        context,
        'Use the server library',
        'Pakai data server',
      ),
      ConnectChoice.useLocal => localText(
        context,
        "Use this iPhone's library",
        'Pakai data iPhone',
      ),
    };

String _choiceNote(
  BuildContext context,
  ConnectChoice choice,
  ConnectAnalysis a,
) => switch (choice) {
  ConnectChoice.merge => localText(
    context,
    'Keep every series from both.',
    'Simpan semua series dari keduanya.',
  ),
  ConnectChoice.useServer => localText(
    context,
    '${a.onlyLocal} series leave the iPhone library. Downloads stay.',
    '${a.onlyLocal} series dihapus dari library iPhone. Unduhan tetap ada.',
  ),
  ConnectChoice.useLocal => localText(
    context,
    '${a.onlyRemote} series leave the server library.',
    '${a.onlyRemote} series dihapus dari library server.',
  ),
};

class _Numbers extends StatelessWidget {
  const _Numbers({required this.analysis});

  final ConnectAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    Widget row(String label, String value, {String? note}) => ListTile(
      dense: true,
      title: Text(label),
      subtitle: note == null ? null : Text(note),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return SettingsGroupCard(
      children: [
        row('iPhone', '${a.localCount}'),
        row(localText(context, 'Server', 'Server'), '${a.remoteCount}'),
        row(localText(context, 'Matched', 'Cocok'), '${a.matched}'),
        row(
          localText(context, 'Only on iPhone', 'Hanya di iPhone'),
          '${a.onlyLocal}',
          note: a.onlyLocal == 0
              ? null
              : localText(
                  context,
                  '${a.sendable} can be sent, ${a.unsendable} can\'t '
                      '(imports, Kuchie repo, or an extension the server lacks)',
                  '${a.sendable} bisa dikirim, ${a.unsendable} tidak bisa '
                      '(import, repo Kuchie, atau extension yang belum ada di server)',
                ),
        ),
        row(
          localText(context, 'Only on the server', 'Hanya di server'),
          '${a.onlyRemote}',
          note: a.onlyRemote == 0
              ? null
              : localText(
                  context,
                  '${a.readableHere} have their extension on this iPhone, '
                      '${a.notReadableHere} don\'t yet',
                  '${a.readableHere} extension terpasang di iPhone, '
                      '${a.notReadableHere} belum',
                ),
        ),
      ],
    );
  }
}

/// The server's extensions the first sync installs here, and why.
class _ExtensionsToInstall extends StatelessWidget {
  const _ExtensionsToInstall({required this.analysis});

  final ConnectAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extensions = analysis.toInstall;
    final waiting = analysis.extensions?.seriesWaiting ?? 0;
    return SettingsGroupCard(
      children: [
        ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: Text(
            localText(
              context,
              'Also installs ${extensions.length} extensions from the server',
              'Juga memasang ${extensions.length} extension dari server',
            ),
          ),
          subtitle: Text(
            '${localText(context, 'So this iPhone reads the same $waiting series as the server: ', 'Supaya iPhone ini bisa membaca $waiting series yang sama dengan server: ')}'
            '${extensions.map((extension) => extension.name).join(', ')}.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _InstallingStep extends StatelessWidget {
  const _InstallingStep({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SyncDiagram(scene: sceneFor(suwayomiMethod, SyncStatusKind.analyzing)),
        Text(
          localText(
            context,
            "Installing the server's extensions…",
            'Memasang extension dari server…',
          ),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          name ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SavedStep extends StatelessWidget {
  const _SavedStep({
    required this.choice,
    required this.onDone,
    this.installed,
  });

  final ConnectChoice choice;
  final VoidCallback onDone;

  /// What installing the server's extensions did, if it ran.
  final ServerExtensionsReport? installed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          localText(context, 'Sync started', 'Sinkronisasi dimulai'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          localText(
            context,
            'First sync: ${_choiceTitle(context, choice).toLowerCase()}. '
                'It runs in the background; the Sync page shows how it goes.',
            'Sync pertama: ${_choiceTitle(context, choice).toLowerCase()}. '
                'Berjalan di latar belakang; halaman Sinkronisasi '
                'menampilkan prosesnya.',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        if (installed case final report?) ...[
          const SizedBox(height: 12),
          Text(
            report.failed.isEmpty
                ? localText(
                    context,
                    '${report.installed.length} extensions installed from the server.',
                    '${report.installed.length} extension dari server terpasang.',
                  )
                : localText(
                    context,
                    '${report.installed.length} extensions installed. Not installed: '
                        '${report.failed.keys.where((name) => name.isNotEmpty).join(', ')}. '
                        'Their series are read through the server until they are.',
                    '${report.installed.length} extension terpasang. Tidak terpasang: '
                        '${report.failed.keys.where((name) => name.isNotEmpty).join(', ')}. '
                        'Series-nya dibaca lewat server sampai extension-nya terpasang.',
                  ),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: onDone,
          child: Text(localText(context, 'Done', 'Selesai')),
        ),
      ],
    );
  }
}
