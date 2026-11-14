// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../routes/router_config.dart';
import '../../../../utils/extensions/custom_extensions.dart';
import '../../../../utils/misc/app_utils.dart';
import '../../../../utils/misc/toast/toast.dart';
import '../../../../widgets/app_bottom_sheet.dart';
import '../../../../widgets/server_image.dart';
import '../../controller/manga_track_records_controller.dart';
import '../../data/graphql/__generated__/query.graphql.dart';
import '../../data/tracker_repository.dart';
import 'widgets/track_editor.dart';
import 'widgets/tracker_search.dart';

Future<void> showTrackSheet(
  BuildContext context,
  int mangaId, {
  String mangaTitle = '',
}) async {
  await showAppBottomSheet<void>(
    context: context,
    builder: (_) => TrackSheetContent(
      mangaId: mangaId,
      mangaTitle: mangaTitle,
    ),
  );
}

class TrackSheetContent extends ConsumerWidget {
  const TrackSheetContent({
    super.key,
    required this.mangaId,
    this.mangaTitle = '',
  });

  final int mangaId;
  final String mangaTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetHeader(title: context.l10n.tracking),
        Flexible(child: _buildBody(context, ref)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    final trackersAsync = ref.watch(trackersProvider);
    final recordsAsync =
        ref.watch(mangaTrackRecordsProvider(mangaId: mangaId));

    if (trackersAsync.hasError || recordsAsync.hasError) {
      return _ErrorState(
        message: (trackersAsync.error ?? recordsAsync.error).toString(),
        onRetry: () {
          ref.invalidate(trackersProvider);
          ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
        },
      );
    }

    // Keep existing content visible during reloads; only initial loading needs a spinner.
    if (!trackersAsync.hasValue || !recordsAsync.hasValue) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final trackers = trackersAsync.value ?? [];
    final records = recordsAsync.value ?? [];
    final loggedIn = trackers.where((t) => t.isLoggedIn).toList();
    final loggedOutBound = trackers.where((t) => !t.isLoggedIn).where(
      (t) => records.any((r) => r.trackerId == t.id),
    ).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loggedIn.isEmpty && loggedOutBound.isEmpty)
            const _EmptyLoginState()
          else ...[
            ListTile(
              leading: const Icon(FluentIcons.person_accounts_24_regular),
              title: Text(context.l10n.manageTrackers),
              onTap: () {
                Navigator.of(context).pop();
                const TrackingSettingsRoute().push(context);
              },
            ),
            const Divider(height: 1),
            ...loggedIn.map((tracker) {
              final record = records
                  .firstWhereOrNull((r) => r.trackerId == tracker.id);
              return _TrackerCard(
                tracker: tracker,
                record: record,
                mangaId: mangaId,
                mangaTitle: mangaTitle,
              );
            }),

            ...loggedOutBound.map((tracker) {
              final record =
                  records.firstWhereOrNull((r) => r.trackerId == tracker.id);
              return _LoggedOutBoundCard(
                tracker: tracker,
                record: record!,
              );
            }),
          ],
        ],
      ),
    );
  }
}


class _EmptyLoginState extends StatelessWidget {
  const _EmptyLoginState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.arrow_sync_dismiss_24_regular, size: 48),
          const SizedBox(height: 12),
          Text(
            context.l10n.noTrackersLoggedIn,
            style: context.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              const TrackingSettingsRoute().push(context);
            },
            child: Text(context.l10n.manageTrackers),
          ),
        ],
      ),
    );
  }
}

class _TrackerCard extends ConsumerWidget {
  const _TrackerCard({
    required this.tracker,
    required this.record,
    required this.mangaId,
    required this.mangaTitle,
  });

  final Fragment$TrackerDto tracker;
  final Fragment$TrackRecordDto? record;
  final int mangaId;
  final String mangaTitle;

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final rec = record;
    if (rec == null) return;
    await AppUtils.guard(
      () => ref.read(trackerRepositoryProvider).fetch(rec.id),
      ref.read(toastProvider),
    );
    if (context.mounted) {
      ref.invalidate(mangaTrackRecordsProvider(mangaId: mangaId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = record;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                ServerImage(
                  imageUrl: tracker.icon,
                  size: const Size.square(24),
                  progressIndicatorBuilder: (_, _, _) =>
                      const Icon(FluentIcons.arrow_sync_24_regular, size: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tracker.name,
                    style: context.textTheme.titleSmall,
                  ),
                ),
                if (rec != null)
                  IconButton(
                    icon: const Icon(FluentIcons.arrow_clockwise_24_regular, size: 20),
                    tooltip: context.l10n.refresh,
                    onPressed: () => _refresh(context, ref),
                  ),
              ],
            ),
          ),

          if (rec == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: OutlinedButton(
                onPressed: () => showAppBottomSheet<void>(
                  context: context,
                  builder: (_) => TrackerSearch(
                    mangaId: mangaId,
                    mangaTitle: mangaTitle,
                    tracker: tracker,
                    title: context.l10n.addTracking,
                    onBound: () {
                      ref.invalidate(
                        mangaTrackRecordsProvider(mangaId: mangaId),
                      );
                    },
                  ),
                ),
                child: Text(context.l10n.addTracking),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
              child: TrackEditor(
                tracker: tracker,
                trackRecord: rec,
                mangaId: mangaId,
              ),
            ),
        ],
      ),
    );
  }
}

class _LoggedOutBoundCard extends StatelessWidget {
  const _LoggedOutBoundCard({
    required this.tracker,
    required this.record,
  });

  final Fragment$TrackerDto tracker;
  final Fragment$TrackRecordDto record;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                ServerImage(
                  imageUrl: tracker.icon,
                  size: const Size.square(24),
                  progressIndicatorBuilder: (_, _, _) =>
                      const Icon(FluentIcons.arrow_sync_24_regular, size: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tracker.name,
                    style: context.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  record.title,
                  style: context.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    const TrackingSettingsRoute().push(context);
                  },
                  child: Text(context.l10n.logInToEdit),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(context.l10n.refresh),
          ),
        ],
      ),
    );
  }
}
