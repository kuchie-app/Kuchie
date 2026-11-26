import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../widgets/emoticons.dart';
import '../../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../../widgets/scroll_bottom_inset.dart';
import '../../../../../widgets/shell/detail_navigation_shell_screen.dart';
import '../../../../local_collection/presentation/local_ui.dart';

/// A title in the Recently Downloaded list, from either collection.
typedef DownloadedItem = ({
  Widget cover,
  String title,
  int chapters,

  /// When its newest chapter finished, or null when unknown.
  DateTime? downloadedAt,
  VoidCallback? onTap,

  /// Offers to delete the title's downloads; true when they were removed.
  Future<bool> Function()? onLongPress,
});

String _recentlyDownloaded(BuildContext context) =>
    localText(context, 'Recently Downloaded', 'Baru Diunduh');

/// The row at the top of Downloads that opens [RecentlyDownloadedPage].
class RecentlyDownloadedRow extends StatelessWidget {
  const RecentlyDownloadedRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: const Icon(FluentIcons.arrow_download_24_regular),
        title: Text(_recentlyDownloaded(context)),
        trailing: Icon(
          FluentIcons.chevron_right_24_regular,
          color: context.theme.colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
      const Divider(height: 1),
    ],
  );
}

/// Resume or pause the queue, and how many chapters download at once.
class DownloadsQueueActions extends StatelessWidget {
  const DownloadsQueueActions({
    super.key,
    required this.running,
    required this.onToggle,
    required this.concurrency,
    required this.onConcurrency,
  });

  final bool running;

  /// Null disables the button, such as with an empty queue.
  final VoidCallback? onToggle;
  final int concurrency;
  final VoidCallback? onConcurrency;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: FilledButton.icon(
              style: style,
              onPressed: onToggle,
              icon: Icon(
                running
                    ? FluentIcons.pause_24_filled
                    : FluentIcons.play_24_filled,
                size: 18,
              ),
              label: Text(running ? context.l10n.pause : context.l10n.resume),
            ),
          ),
          Expanded(
            child: FilledButton.icon(
              style: style,
              onPressed: onConcurrency,
              icon: const Icon(FluentIcons.flash_24_filled, size: 18),
              label: Text(
                localText(
                  context,
                  'Concurrent: $concurrency',
                  'Bersamaan: $concurrency',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Titles with saved chapters, newest download first, grouped by day.
class RecentlyDownloadedPage extends StatefulWidget {
  const RecentlyDownloadedPage({super.key, required this.load});

  /// Reads the list again; called on open and on pull to refresh.
  final Future<List<DownloadedItem>> Function() load;

  @override
  State<RecentlyDownloadedPage> createState() => _RecentlyDownloadedPageState();
}

class _RecentlyDownloadedPageState extends State<RecentlyDownloadedPage> {
  late Future<List<DownloadedItem>> _items = widget.load();

  Future<void> _refresh() {
    final next = widget.load();
    setState(() => _items = next);
    return next.then<void>((_) {}, onError: (Object _) {});
  }

  String _dayLabel(BuildContext context, DateTime? date) {
    if (date == null) return localText(context, 'Earlier', 'Sebelumnya');
    final today = DateTime.now().startOfDay;
    final day = date.startOfDay;
    if (day == today) return context.l10n.today;
    if (day == today.subtract(const Duration(days: 1))) {
      return context.l10n.yesterday;
    }
    return date.toDateString;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // Pushed with Navigator, so the back button pops this route rather than
    // following the router.
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: detailNavigationBar(
        context,
        (leading) =>
            AppBar(leading: leading, title: Text(_recentlyDownloaded(context))),
        back: detailBackButton(() => Navigator.of(context).maybePop()),
      ),
    ),
    body: FutureBuilder<List<DownloadedItem>>(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Emoticons(
            title: localText(
              context,
              'Couldn\'t load downloads',
              'Gagal memuat unduhan',
            ),
            button: TextButton(
              onPressed: _refresh,
              child: Text(context.l10n.retry),
            ),
          );
        }
        final items = snapshot.data;
        if (items == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Emoticons(title: context.l10n.noDownloads),
                ),
              ),
            ),
          );
        }
        final rows = <Widget>[];
        String? group;
        for (final item in items) {
          final label = _dayLabel(context, item.downloadedAt);
          if (label != group) {
            group = label;
            rows.add(_DayHeading(label: label, first: rows.isEmpty));
          }
          rows.add(_DownloadedRow(item: item, onRemoved: _refresh));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.only(bottom: scrollBottomInset(context)),
            children: rows,
          ),
        );
      },
    ),
  );
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, first ? 8 : 20, 20, 4),
    child: Text(
      label,
      style: context.textTheme.labelLarge?.copyWith(
        color: context.theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _DownloadedRow extends StatelessWidget {
  const _DownloadedRow({required this.item, required this.onRemoved});

  final DownloadedItem item;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 62,
        child: ColoredBox(
          color: context.theme.colorScheme.surfaceContainerHighest,
          child: item.cover,
        ),
      ),
    ),
    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      localText(
        context,
        '${item.chapters} ${item.chapters == 1 ? 'chapter' : 'chapters'}',
        '${item.chapters} chapter',
      ),
    ),
    trailing: item.onTap == null
        ? null
        : Icon(
            FluentIcons.chevron_right_24_regular,
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
    onTap: item.onTap,
    onLongPress: item.onLongPress == null
        ? null
        : () async {
            if (await item.onLongPress!()) onRemoved();
          },
  );
}

/// One choice in [pickDownloadOption].
typedef DownloadOption<T> = ({T value, String label, String? description});

/// A sheet listing [options] with the [current] one checked.
Future<T?> pickDownloadOption<T>(
  BuildContext context, {
  required String title,
  required List<DownloadOption<T>> options,
  required T current,
  String? note,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(title, style: sheet.textTheme.titleMedium),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              note,
              style: sheet.textTheme.bodySmall?.copyWith(
                color: sheet.theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text(option.label),
                  subtitle: option.description == null
                      ? null
                      : Text(option.description!),
                  trailing: option.value == current
                      ? Icon(
                          FluentIcons.checkmark_24_regular,
                          color: sheet.theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheet, option.value),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);

/// Picks how many chapters download at once, from 1 to [max].
Future<int?> pickDownloadConcurrency(
  BuildContext context, {
  required int current,
  required int max,
  String? note,
}) => pickDownloadOption<int>(
  context,
  title: localText(context, 'Concurrent downloads', 'Unduhan bersamaan'),
  note: note,
  current: current,
  options: [
    for (var value = 1; value <= max; value++)
      (value: value, label: '$value', description: null),
  ],
);

/// Turns background downloads on or off.
Future<bool?> pickBackgroundDownloads(
  BuildContext context, {
  required bool current,
}) => pickDownloadOption<bool>(
  context,
  title: localText(context, 'Background Download', 'Unduh di Latar Belakang'),
  current: current,
  options: [
    (
      value: true,
      label: localText(context, 'Enable', 'Aktif'),
      description: localText(
        context,
        'Keep going for the short time iOS allows after you leave Kuchie',
        'Lanjut selama waktu singkat yang diizinkan iOS setelah keluar Kuchie',
      ),
    ),
    (
      value: false,
      label: localText(context, 'Disable', 'Nonaktif'),
      description: localText(
        context,
        'Pause as soon as you leave Kuchie',
        'Jeda begitu keluar dari Kuchie',
      ),
    ),
  ],
);

/// Explains the three download settings, for the help button.
Future<void> showDownloadSettingsHelp(
  BuildContext context, {
  required bool server,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) {
    Widget entry(IconData icon, String title, String body) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(icon, color: sheet.theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(body),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                localText(sheet, 'Download settings', 'Setelan unduhan'),
                style: sheet.textTheme.titleMedium,
              ),
            ),
            entry(
              FluentIcons.flash_24_regular,
              localText(sheet, 'Concurrent downloads', 'Unduhan bersamaan'),
              server
                  ? localText(
                      sheet,
                      'How many sources the server downloads from at once, '
                          'one chapter each. Higher is faster, but some '
                          'sources block many requests.',
                      'Jumlah sumber yang diunduh server sekaligus, satu '
                          'chapter per sumber. Lebih tinggi lebih cepat, tapi '
                          'beberapa sumber memblokir banyak permintaan.',
                    )
                  : localText(
                      sheet,
                      'How many chapters download at the same time. Higher '
                          'is faster, but some sources block many requests.',
                      'Jumlah chapter yang diunduh bersamaan. Lebih tinggi '
                          'lebih cepat, tapi beberapa sumber memblokir banyak '
                          'permintaan.',
                    ),
            ),
            entry(
              FluentIcons.arrow_sync_24_regular,
              localText(
                sheet,
                'Background Download',
                'Unduh di Latar Belakang',
              ),
              server
                  ? localText(
                      sheet,
                      'The server keeps downloading when Kuchie is closed, so '
                          'this is always on.',
                      'Server tetap mengunduh saat Kuchie ditutup, jadi '
                          'setelan ini selalu aktif.',
                    )
                  : localText(
                      sheet,
                      'iOS lets Kuchie keep downloading for a short time after '
                          'you leave. When that ends, or when this is off, '
                          'downloads pause and resume when you come back.',
                      'iOS mengizinkan Kuchie mengunduh sebentar setelah '
                          'keluar. Setelah itu, atau jika nonaktif, unduhan '
                          'dijeda lalu lanjut saat kembali.',
                    ),
            ),
            entry(
              FluentIcons.delete_24_regular,
              localText(
                sheet,
                'Delete download after reading',
                'Hapus unduhan setelah dibaca',
              ),
              server
                  ? localText(
                      sheet,
                      'Removes the chapter you just finished from the server '
                          'once you move on. Pick an older chapter below under '
                          'Server.',
                      'Menghapus chapter yang baru selesai dibaca dari server '
                          'saat lanjut. Pilih chapter yang lebih lama di '
                          'bagian Server di bawah.',
                    )
                  : localText(
                      sheet,
                      'Removes a saved chapter from this iPhone once you '
                          'finish it and close the reader.',
                      'Menghapus chapter tersimpan dari iPhone ini setelah '
                          'selesai dibaca dan reader ditutup.',
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  },
);

/// The help button for the download settings app bar.
Widget downloadSettingsHelpButton(
  BuildContext context, {
  required bool server,
}) => AppleGlassToolbarButton(
  id: 'download-settings-help',
  symbol: 'questionmark.circle',
  label: context.l10n.help,
  fallbackIcon: FluentIcons.question_circle_24_regular,
  onPressed: () => showDownloadSettingsHelp(context, server: server),
);
