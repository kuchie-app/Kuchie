import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../utils/motion/reduce_motion.dart';
import '../../../utils/power/low_power_mode.dart';
import '../../local_collection/data/local_collection_providers.dart';
import '../../local_collection/presentation/local_ui.dart';
import '../../security/security_settings_screen.dart';
import '../../settings/widgets/settings_group_card/settings_group_card.dart';
import '../controller/sync_controller.dart';
import '../data/sync_state_store.dart';
import '../domain/diagram/sync_methods.dart';
import '../domain/diagram/sync_scene.dart';
import 'diagram/sync_explainer.dart';
import 'suwayomi_connect_flow.dart';
import 'sync_faq.dart';
import 'sync_hero_card.dart';
import 'sync_method_list.dart';

void openSyncSettings(BuildContext context) => unawaited(
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SyncSettingsScreen())),
);

/// Series in the Local library, for the diagram's numbers. Zero until the
/// collection has opened.
final syncLibrarySizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final services = await ref.watch(localCollectionServicesProvider.future);
  final series = await services.catalog.list();
  return series.where((item) => item.inLibrary).length;
});

/// More → Sync (design 3.2): the live diagram, the methods, and FAQ.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key, this.debugPreview = kDebugMode});

  /// Shows the menu that fakes every scene, until the engine exists.
  final bool debugPreview;

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _explainer = SyncExplainer();
  bool _celebrate = false;
  Timer? _celebrateTimer;

  @override
  void initState() {
    super.initState();
    final store = ref.read(syncStateStoreProvider);
    if (!store.explainerSeen) {
      unawaited(store.setExplainerSeen());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playExplainer();
      });
    }
  }

  @override
  void dispose() {
    _celebrateTimer?.cancel();
    _explainer.dispose();
    super.dispose();
  }

  void _playExplainer() => _explainer.start(manual: context.reduceMotion);

  void _celebrateFirstSync() {
    if (!mounted) return;
    setState(() => _celebrate = true);
    _celebrateTimer?.cancel();
    _celebrateTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _celebrate = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(syncControllerProvider);
    final librarySize = ref.watch(syncLibrarySizeProvider).value ?? 0;
    final scene = overview.scene(librarySize: librarySize);
    final previewing = overview.preview != null;
    final controller = ref.read(syncControllerProvider.notifier);
    return SettingsListPage(
      title: localText(context, 'Sync', 'Sinkronisasi'),
      actions: [
        IconButton(
          tooltip: localText(
            context,
            'Play how it works',
            'Putar penjelasan cara kerja',
          ),
          icon: const Icon(Icons.help_outline_rounded),
          onPressed: _playExplainer,
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SyncHeroCard(
            scene: scene,
            explainer: _explainer,
            lowPower: ref.watch(lowPowerModeProvider),
            stale: overview.isStale(DateTime.now()),
            lastSuccessAt: previewing
                ? DateTime.now().subtract(const Duration(days: 9))
                : scene.figures.lastSuccessAt,
            celebrate: _celebrate,
            // The preview plays what the action would do.
            onPrimary: previewing
                ? () => controller.playPreviewRun(
                    onFirstSync: _celebrateFirstSync,
                  )
                : switch (scene.cta) {
                    SyncCta.connect ||
                    SyncCta.signIn => () => openSuwayomiConnect(context),
                    SyncCta.syncNow ||
                    SyncCta.retry => () => unawaited(controller.syncNow()),
                    _ => null,
                  },
          ),
        ),
        SettingsGroupHeading(label: localText(context, 'Method', 'Metode')),
        SyncMethodList(
          selected: (overview.preview?.method ?? overview.methodSpec.kind),
          serverAddress: overview.serverAddress,
          onSelect: previewing
              ? (kind) => controller.setPreview(
                  SyncPreview(kind, syncMethods[kind]!.defaultStatus),
                )
              : (kind) {
                  // Turning sync off and the Suwayomi details come with
                  // the engine and Disconnect (PR 8, PR 17).
                  if (kind == SyncMethodKind.suwayomi &&
                      overview.methodSpec.kind == SyncMethodKind.local) {
                    openSuwayomiConnect(context);
                  }
                },
        ),
        SettingsGroupHeading(
          label: localText(context, 'Common questions', 'Pertanyaan umum'),
        ),
        const SyncFaq(),
        if (widget.debugPreview) ...[
          const SettingsGroupHeading(label: 'Preview (debug)'),
          _DebugPreview(overview: overview, controller: controller),
        ],
      ],
    );
  }
}

/// Debug builds only: pick any method and status, since the engine that
/// sets them arrives later.
class _DebugPreview extends StatelessWidget {
  const _DebugPreview({required this.overview, required this.controller});

  final SyncOverview overview;
  final SyncController controller;

  @override
  Widget build(BuildContext context) {
    final preview = overview.preview;
    final method = syncMethods[preview?.method ?? overview.methodSpec.kind]!;
    return SettingsGroupCard(
      children: [
        SwitchListTile(
          title: const Text('Fake status'),
          value: preview != null,
          onChanged: (on) => controller.setPreview(
            on ? SyncPreview(method.kind, method.defaultStatus) : null,
          ),
        ),
        if (preview != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final kind in SyncMethodKind.values)
                  ChoiceChip(
                    label: Text(syncCopy(context, syncMethods[kind]!.name)),
                    selected: preview.method == kind,
                    onSelected: (_) => controller.setPreview(
                      SyncPreview(kind, syncMethods[kind]!.defaultStatus),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final status in method.statuses)
                  ChoiceChip(
                    label: Text(status.name),
                    selected: preview.status == status,
                    onSelected: (_) => controller.setPreview(
                      SyncPreview(method.kind, status, stale: preview.stale),
                    ),
                  ),
              ],
            ),
          ),
          if (method.statuses.contains(SyncStatusKind.waiting))
            SwitchListTile(
              title: const Text('Waiting for over 7 days'),
              value: preview.stale,
              onChanged: (stale) => controller.setPreview(
                SyncPreview(method.kind, SyncStatusKind.waiting, stale: stale),
              ),
            ),
        ],
      ],
    );
  }
}
