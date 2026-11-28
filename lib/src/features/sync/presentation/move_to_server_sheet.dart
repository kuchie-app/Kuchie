import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../local_collection/presentation/local_ui.dart';
import '../controller/move_to_server.dart';
import '../data/sync_state_store.dart';

String formatMoveBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 || value >= 10 ? 0 : 1)} ${units[unit]}';
}

/// Plans a move and asks how (design 3.6): one sheet, delete from this
/// iPhone by default or keep the copy. Returns whether a move started.
Future<bool> showMoveToServerSheet(
  BuildContext context, {
  String? seriesId,
  Set<String>? chapterIds,
}) async {
  final mover = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(moveToServerProvider);
  if (!mover.enabled) return false;
  final plan = await mover.plan(seriesId: seriesId, chapterIds: chapterIds);
  if (!context.mounted) return false;
  if (plan.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          plan.excluded > 0
              ? localText(
                  context,
                  "These chapters can't go to the server: their series come from imports or a Kuchie repo.",
                  'Chapter ini tidak bisa dipindah ke server: series-nya dari impor atau repo Kuchie.',
                )
              : localText(
                  context,
                  'Nothing saved here to move.',
                  'Tidak ada unduhan di iPhone untuk dipindah.',
                ),
        ),
      ),
    );
    return false;
  }
  final keepLocal = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (_) => _MoveSheet(plan: plan),
  );
  if (keepLocal == null || !context.mounted) return false;
  unawaited(mover.start(plan, keepLocal: keepLocal));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        localText(
          context,
          'Moving to the server. Copies here go only once the server has them.',
          'Memindahkan ke server. Salinan di iPhone baru dihapus setelah server memilikinya.',
        ),
      ),
    ),
  );
  return true;
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.plan});

  final MovePlan plan;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  bool _keepLocal = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final count = plan.chapters.length;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localText(
                context,
                'Move $count chapters to the server',
                'Pindahkan $count chapter ke server',
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              localText(
                context,
                'The server downloads them from their sources.',
                'Server akan mengunduh chapter ini dari source-nya.',
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: _keepLocal,
              onChanged: (value) => setState(() => _keepLocal = value!),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text(
                      localText(
                        context,
                        'Delete from this iPhone',
                        'Hapus dari iPhone',
                      ),
                    ),
                    subtitle: Text(
                      localText(
                        context,
                        'Frees ${formatMoveBytes(plan.bytes)}, once the server has each chapter.',
                        'Melegakan ${formatMoveBytes(plan.bytes)}, setelah server memiliki tiap chapter.',
                      ),
                    ),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text(
                      localText(context, 'Keep them here too', 'Tetap simpan'),
                    ),
                  ),
                ],
              ),
            ),
            if (plan.excluded > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  localText(
                    context,
                    '${plan.excluded} chapters stay here: their series come from imports or a Kuchie repo.',
                    '${plan.excluded} chapter tetap di iPhone: series-nya dari impor atau repo Kuchie.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, _keepLocal),
              child: Text(localText(context, 'Move', 'Pindahkan')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Once, after connecting, when this iPhone holds downloads the server
/// could keep (design 3.6).
class MoveToServerCard extends ConsumerStatefulWidget {
  const MoveToServerCard({super.key});

  @override
  ConsumerState<MoveToServerCard> createState() => _MoveToServerCardState();
}

class _MoveToServerCardState extends ConsumerState<MoveToServerCard> {
  late final Future<MovePlan?> _plan = () async {
    final store = ref.read(syncStateStoreProvider);
    final mover = ref.read(moveToServerProvider);
    if (store.moveSuggested || !mover.enabled || store.lastSuccessAt == null) {
      return null;
    }
    try {
      return await mover.plan();
    } catch (_) {
      return null;
    }
  }();
  bool _answered = false;

  Future<void> _answer() async {
    await ref.read(syncStateStoreProvider).setMoveSuggested();
    if (mounted) setState(() => _answered = true);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MovePlan?>(
    future: _plan,
    builder: (context, snapshot) {
      final plan = snapshot.data;
      if (_answered || plan == null || plan.isEmpty) {
        return const SizedBox.shrink();
      }
      return Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localText(
                  context,
                  'There are ${formatMoveBytes(plan.bytes)} of downloads on this iPhone. Move them to the server?',
                  'Ada ${formatMoveBytes(plan.bytes)} unduhan di iPhone. Pindahkan ke server?',
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _answer,
                    child: Text(localText(context, 'Not now', 'Nanti saja')),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (await showMoveToServerSheet(context)) await _answer();
                    },
                    child: Text(localText(context, 'Move', 'Pindahkan')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
