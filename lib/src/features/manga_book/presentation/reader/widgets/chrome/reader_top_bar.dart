// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../utils/platform/platform_runtime.dart';
import '../../../../../../utils/theme/brand.dart';
import '../../../../../../utils/theme/reader_overlay_colors.dart';
import '../../../../../../widgets/in_app_web_view.dart';
import '../../../../../../widgets/ios/apple_glass_toolbar.dart';
import '../../../../../../widgets/server_image.dart';
import '../../../../../security/app_security.dart';
import '../../../../../settings/presentation/koreader_sync/data/koreader_sync_repository.dart';
import '../../../../domain/chapter/chapter_model.dart';
import '../../../../domain/manga/manga_model.dart';
import '../../../manga_details/server_web_url.dart';
import '../../../manga_details/widgets/chapter_context_menu.dart';
import '../../utils/koreader_progress_actions.dart';
import 'reader_bookmark_button.dart';

/// Measure this bar together with ReaderUtilsBar so expanded controls are included in the top inset.
/// Server adapter: derives titles, links, bookmark and KOReader actions from
/// the server DTOs and renders the shared [ReaderTopBarView].
class ReaderTopBar extends HookConsumerWidget {
  const ReaderTopBar({
    super.key,
    required this.manga,
    required this.chapter,
    required this.onBack,
    required this.onJump,
    required this.pageCount,
    required this.currentPage,
    this.floating = false,
    this.onOpenChapters,
    this.onOpenReaderMode,
    this.onToggleAutoScrollControls,
    this.autoScrollLabel,
  });

  final MangaDto manga;
  final ChapterDto chapter;
  final VoidCallback onBack;
  final ValueChanged<int> onJump;
  final int pageCount;
  final int currentPage;
  final bool floating;
  final VoidCallback? onOpenChapters;
  final VoidCallback? onOpenReaderMode;
  final VoidCallback? onToggleAutoScrollControls;
  final String? autoScrollLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected =
        koSyncOnline(ref) &&
        ref.watch(koSyncStatusProvider).value?.isLoggedIn == true;
    final link = chapter.realUrl.isNotBlank ? chapter.realUrl : chapter.url;
    final serverMangaUrl = serverMangaWebUrl(ref, manga.id);
    final serverWebView = serverMangaUrl == null
        ? null
        : serverWebViewLink(
            '${serverMangaUrl.substring(0, serverMangaUrl.lastIndexOf('/manga/'))}/api/v1',
            link,
          );
    Future<void> sync({required bool push}) => syncKoReaderChapter(
      context: context,
      ref: ref,
      chapter: chapter,
      push: push,
      pageCount: pageCount,
      currentPage: currentPage,
      onJump: onJump,
    );
    return ReaderTopBarView(
      seriesTitle: manga.title,
      chapterTitle: chapter.name,
      sourceUrl: chapter.realUrl.isNotBlank ? chapter.realUrl : null,
      webLink: link.isNotBlank ? link : null,
      serverWebViewUrl: serverWebView,
      onBack: onBack,
      floating: floating,
      onOpenChapters: onOpenChapters,
      onOpenReaderMode: onOpenReaderMode,
      onToggleAutoScrollControls: onToggleAutoScrollControls,
      autoScrollLabel: autoScrollLabel,
      onRetry: () => retryFailedReaderPages(ref),
      bookmark: ReaderBookmarkButton(
        chapterId: chapter.id,
        fallbackIsBookmarked: chapter.user.isBookmarked,
      ),
      extraMenu: [
        if (connected) ...[
          AppleGlassToolbarMenuItem(
            id: 'push',
            title: context.l10n.pushKoReaderProgress,
            symbol: 'icloud.and.arrow.up',
            fallbackIcon: FluentIcons.cloud_arrow_up_24_regular,
            onSelected: () => sync(push: true),
          ),
          AppleGlassToolbarMenuItem(
            id: 'pull',
            title: context.l10n.pullKoReaderProgress,
            symbol: 'icloud.and.arrow.down',
            fallbackIcon: FluentIcons.cloud_arrow_down_24_regular,
            onSelected: () => sync(push: false),
          ),
        ],
      ],
    );
  }
}

/// The reader's top bar for every collection (server and on-device): the
/// floating Liquid Glass bar on iOS, the Material bar elsewhere, and one
/// overflow menu. Callers pass plain data, so the Local reader and the server
/// reader render exactly the same widget.
class ReaderTopBarView extends ConsumerWidget {
  const ReaderTopBarView({
    super.key,
    required this.seriesTitle,
    required this.chapterTitle,
    required this.onBack,
    required this.onRetry,
    this.sourceUrl,
    this.webLink,
    this.serverWebViewUrl,
    this.bookmark,
    this.extraMenu = const [],
    this.floating = false,
    this.onOpenChapters,
    this.onOpenReaderMode,
    this.onToggleAutoScrollControls,
    this.autoScrollLabel,
  });

  final String seriesTitle;
  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  /// The chapter on the source's own site; adds "Open in browser".
  final String? sourceUrl;

  /// Link for the in-app web view and sharing.
  final String? webLink;
  final String? serverWebViewUrl;

  /// Shown in the Material bar; the floating dock carries its own.
  final Widget? bookmark;

  /// Collection-specific entries appended to the overflow menu.
  final List<AppleGlassToolbarMenuItem> extraMenu;
  final bool floating;
  final VoidCallback? onOpenChapters;
  final VoidCallback? onOpenReaderMode;
  final VoidCallback? onToggleAutoScrollControls;
  final String? autoScrollLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = sourceUrl;
    final link = webLink;
    Future<void> share(String link) async {
      if (!contentSharingAllowed(context)) return;
      if (kIsWeb || isDesktopPlatform) {
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) {
          ref.read(toastProvider)?.show(context.l10n.copiedToClipboard);
        }
      } else {
        await SharePlus.instance.share(
          ShareParams(uri: Uri.parse(link), title: chapterTitle),
        );
      }
    }

    final menu = [
      if (onOpenReaderMode case final open?)
        AppleGlassToolbarMenuItem(
          id: 'readingMode',
          title: context.l10n.readerMode,
          symbol: 'book',
          fallbackIcon: FluentIcons.book_open_24_regular,
          onSelected: open,
        ),
      if (floating && source != null)
        AppleGlassToolbarMenuItem(
          id: 'source',
          title: context.l10n.openSourceInBrowser,
          symbol: 'safari',
          fallbackIcon: FluentIcons.globe_24_regular,
          onSelected: () =>
              launchUrlInWeb(context, source, ref.read(toastProvider)),
        ),
      if (onToggleAutoScrollControls case final toggle?)
        AppleGlassToolbarMenuItem(
          id: 'autoScrollControls',
          title: autoScrollLabel!,
          symbol: 'timer',
          fallbackIcon: FluentIcons.timer_24_regular,
          onSelected: toggle,
        ),
      AppleGlassToolbarMenuItem(
        id: 'retry',
        title: context.l10n.retryErroredPages,
        symbol: 'arrow.clockwise',
        fallbackIcon: FluentIcons.replay_24_regular,
        onSelected: onRetry,
      ),
      if (link != null) ...[
        AppleGlassToolbarMenuItem(
          id: 'web',
          title: context.l10n.openChapterInWebView,
          symbol: 'globe',
          fallbackIcon: FluentIcons.globe_24_regular,
          onSelected: () => openInAppWebView(
            context,
            link,
            serverWebViewUrl: serverWebViewUrl,
            toast: ref.read(toastProvider),
          ),
        ),
        AppleGlassToolbarMenuItem(
          id: 'share',
          title: context.l10n.shareChapterLink,
          symbol: 'square.and.arrow.up',
          fallbackIcon: FluentIcons.share_24_regular,
          onSelected: () => share(link),
        ),
      ],
      ...extraMenu,
    ];
    if (floating) {
      return FloatingReaderTopBar(
        chapterTitle: chapterTitle.isNotBlank ? chapterTitle : seriesTitle,
        onBack: onBack,
        onOpenChapters: onOpenChapters,
        menu: menu,
      );
    }
    final systemTopInset = MediaQuery.viewPaddingOf(context).top;
    return Material(
      color: readerNavSurface(context.theme.colorScheme),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.only(top: systemTopInset),
        child: Row(
          children: [
            ReaderToolbarBack(onBack: onBack),
            Expanded(
              child: ListTile(
                title: seriesTitle.isNotBlank
                    ? Text(seriesTitle, overflow: TextOverflow.ellipsis)
                    : null,
                subtitle: chapterTitle.isNotBlank
                    ? Text(chapterTitle, overflow: TextOverflow.ellipsis)
                    : null,
                contentPadding: EdgeInsets.zero,
                trailing: onOpenChapters == null
                    ? null
                    : const Icon(FluentIcons.chevron_down_16_regular),
                onTap: onOpenChapters,
              ),
            ),
            if (source != null)
              AppleGlassToolbarButton(
                id: 'reader-open-source',
                symbol: 'globe',
                label: context.l10n.openSourceInBrowser,
                onPressed: () =>
                    launchUrlInWeb(context, source, ref.read(toastProvider)),
                fallbackIcon: FluentIcons.globe_24_regular,
              ),
            ?bookmark,
            ReaderToolbarMore(floating: false, menu: menu),
          ],
        ),
      ),
    );
  }
}

class FloatingReaderTopBar extends StatelessWidget {
  const FloatingReaderTopBar({
    super.key,
    required this.chapterTitle,
    required this.onBack,
    required this.onOpenChapters,
    required this.menu,
  });

  final String chapterTitle;
  final VoidCallback onBack;
  final VoidCallback? onOpenChapters;
  final List<AppleGlassToolbarMenuItem> menu;

  @override
  Widget build(BuildContext context) {
    final systemTopInset = MediaQuery.viewPaddingOf(context).top;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: ReaderOverlayColors.topBarScrim,
          stops: [0, .7, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, systemTopInset + 4, 14, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pillWidth = (constraints.maxWidth - 108).clamp(48.0, 174.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ReaderToolbarBack(onBack: onBack, floating: true),
                AppleGlassToolbarButton(
                  id: 'reader-chapter-picker',
                  symbol: 'chevron.down',
                  title: chapterTitle,
                  label: '${context.l10n.includeChapters}: $chapterTitle',
                  width: pillWidth,
                  dark: true,
                  onPressed: onOpenChapters,
                  fallback: SizedBox(
                    width: pillWidth,
                    height: 48,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: OnImage.text,
                        backgroundColor:
                            ReaderOverlayColors.chapterPickerButtonSurface,
                      ),
                      onPressed: onOpenChapters,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            FluentIcons.chevron_down_16_regular,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ReaderToolbarMore(floating: true, menu: menu),
              ],
            );
          },
        ),
      ),
    );
  }
}

class ReaderToolbarBack extends StatelessWidget {
  const ReaderToolbarBack({
    super.key,
    required this.onBack,
    this.floating = false,
  });

  final VoidCallback onBack;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return AppleGlassToolbarButton(
      id: 'reader-back',
      symbol: 'chevron.backward',
      label: context.l10n.back,
      onPressed: onBack,
      dark: floating ? true : null,
      fallback: IconButton(
        onPressed: onBack,
        color: floating ? OnImage.text : null,
        icon: const BackButtonIcon(),
        tooltip: context.l10n.back,
      ),
    );
  }
}

class ReaderToolbarMore extends StatelessWidget {
  const ReaderToolbarMore({
    super.key,
    required this.floating,
    required this.menu,
  });

  final bool floating;
  final List<AppleGlassToolbarMenuItem> menu;

  @override
  Widget build(BuildContext context) {
    return floating
        ? AppleGlassToolbarButton(
            id: 'reader-more',
            symbol: 'ellipsis',
            label: context.l10n.more,
            dark: true,
            onPressed: null,
            fallbackIcon: FluentIcons.more_horizontal_24_regular,
            menu: menu,
          )
        : PopupMenuButton<AppleGlassToolbarMenuItem>(
            tooltip: context.l10n.more,
            icon: const Icon(FluentIcons.more_vertical_24_regular),
            onSelected: (item) => item.onSelected?.call(),
            itemBuilder: (_) => [
              for (final item in menu)
                PopupMenuItem(
                  value: item,
                  enabled: item.enabled,
                  child: ChapterMenuRow(
                    icon: item.fallbackIcon,
                    label: item.title,
                  ),
                ),
            ],
          );
  }
}
