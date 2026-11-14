// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../../utils/avif/avif_codec.dart';
import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../utils/launch_url_in_web.dart';
import '../../../../../../utils/misc/toast/toast.dart';
import '../../../../../../widgets/app_bottom_sheet.dart';
import '../../../../../../widgets/cover_cache/cover_cache.dart';
import '../../../../../../widgets/server_image.dart';
import '../../../../../auth/data/auth_credentials_store.dart';
import '../../../../domain/chapter_page/chapter_page_model.dart';
import 'image_clipboard.dart';

Future<void> showReaderPageActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required ChapterPagesDto chapterPages,
  required int pageIndex,
  int? secondaryPageIndex,
  List<int>? spreadPageIndexes,
  CacheManager? cacheManager,
}) => showReaderImageActionsSheet(
  context: context,
  ref: ref,
  pages: chapterPages.pages,
  pageIndex: pageIndex,
  secondaryPageIndex: secondaryPageIndex,
  spreadPageIndexes: spreadPageIndexes,
  cacheManager: cacheManager,
);

Future<void> showReaderImageActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<String> pages,
  required int pageIndex,
  int? secondaryPageIndex,
  List<int>? spreadPageIndexes,
  CacheManager? cacheManager,
  Future<File> Function(String uri)? preparePage,
}) {
  bool isValidPage(int index) => index >= 0 && index < pages.length;
  bool canResolvePage(int index) {
    if (!isValidPage(index)) return false;
    final relative = pages[index];
    if (relative.startsWith('file:')) return true;
    return serverImageRequest(ref, relative).fetchUrl.isNotEmpty;
  }

  if (!canResolvePage(pageIndex)) {
    ref
        .read(toastProvider)
        ?.showError(context.l10n.errorSomethingWentWrong, instantShow: true);
    return Future<void>.value();
  }

  List<int> actionPageIndexes() {
    final spreadIndexes = spreadPageIndexes;
    if (spreadIndexes != null &&
        spreadIndexes.length == 2 &&
        spreadIndexes[0] != spreadIndexes[1] &&
        spreadIndexes.every(canResolvePage)) {
      return spreadIndexes;
    }
    if (secondaryPageIndex != null &&
        secondaryPageIndex != pageIndex &&
        canResolvePage(secondaryPageIndex)) {
      return [pageIndex, secondaryPageIndex];
    }
    return [pageIndex];
  }

  final pageActionIndexes = actionPageIndexes();
  final firstPageIndex = pageActionIndexes.first;
  final extraPageIndex = pageActionIndexes.length == 2
      ? pageActionIndexes.last
      : null;

  final allLocal = pageActionIndexes.every(
    (index) => pages[index].startsWith('file:'),
  );
  final sessionCurrent = allLocal
      ? null
      : ref.read(authCredentialsStoreProvider.notifier).captureSession();
  bool current() => context.mounted && (sessionCurrent?.call() ?? true);
  final requests = {
    for (final index in pageActionIndexes)
      index: serverImageRequest(ref, pages[index]),
  };
  Future<File> resolvePageFile(int index) async {
    if (!current()) throw StateError('Account session changed');
    final request = requests[index]!;
    if (request.localPath != null) {
      return preparePage == null
          ? File(request.localPath!)
          : preparePage(pages[index]);
    }
    final manager = cacheManager ?? ref.read(serverPageCacheManagerProvider);
    if (manager == null) throw StateError('Reader image cache unavailable');
    return manager.getSingleFile(
      request.fetchUrl,
      key: request.cacheKey,
      headers: request.headers ?? const {},
    );
  }

  Future<File> resolveSpreadFile() async => _combineSpreadImages(
    await resolvePageFile(firstPageIndex),
    await resolvePageFile(extraPageIndex!),
  );

  // Native image actions require Android/iOS; defaultTargetPlatform also permits platform-specific tests.
  final isMobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final openUrl = allLocal
      ? null
      : serverImageBrowserUrl(ref, requests[firstPageIndex]!.fetchUrl);

  return showAppBottomSheet<void>(
    context: context,
    isScrollControlled: extraPageIndex != null,
    constraints: extraPageIndex != null
        ? BoxConstraints(maxWidth: 640, maxHeight: context.height * 0.85)
        : null,
    builder: (sheetContext) {
      VoidCallback? copyAction(Future<File> Function() resolve) {
        if (!imageClipboardSupported) return null;
        return () async {
          final toast = ref.read(toastProvider);
          final copiedMsg = context.l10n.copiedImage;
          final errorMsg = context.l10n.errorSomethingWentWrong;
          Navigator.pop(sheetContext);
          try {
            final file = await resolve();
            if (!current()) return;
            final copied = await copyImageToClipboard(file.path);
            if (!current()) return;
            if (copied) {
              toast?.show(copiedMsg, instantShow: true);
            } else {
              toast?.showError(errorMsg, instantShow: true);
            }
          } catch (_) {
            if (current()) toast?.showError(errorMsg, instantShow: true);
          }
        };
      }

      VoidCallback? shareAction(Future<File> Function() resolve) {
        if (!isMobile) return null;
        return () async {
          final toast = ref.read(toastProvider);
          final errorMsg = context.l10n.errorSomethingWentWrong;
          Navigator.pop(sheetContext);
          try {
            final file = await resolve();
            if (!current()) return;
            await SharePlus.instance.share(
              ShareParams(files: [XFile(file.path)]),
            );
          } catch (_) {
            if (current()) toast?.showError(errorMsg, instantShow: true);
          }
        };
      }

      VoidCallback? saveAction(Future<File> Function() resolve) {
        if (!isMobile) return null;
        return () async {
          final toast = ref.read(toastProvider);
          final savedMsg = context.l10n.savedToGallery;
          final errorMsg = context.l10n.errorSomethingWentWrong;
          Navigator.pop(sheetContext);
          try {
            final file = await resolve();
            if (!current()) return;
            if (!await Gal.requestAccess()) {
              toast?.showError(errorMsg, instantShow: true);
              return;
            }
            if (!current()) return;
            await Gal.putImage(file.path);
            toast?.show(savedMsg, instantShow: true);
          } catch (_) {
            if (current()) toast?.showError(errorMsg, instantShow: true);
          }
        };
      }

      final hasSpread = extraPageIndex != null;
      final rows = <List<_PageAction>>[];

      void addMobileRow({
        required String copyLabel,
        required String shareLabel,
        required String saveLabel,
        required Key copyKey,
        required Key shareKey,
        required Key saveKey,
        required Future<File> Function() resolve,
      }) {
        final actions = [
          _PageAction(
            key: copyKey,
            icon: FluentIcons.copy_24_regular,
            label: copyLabel,
            onTap: copyAction(resolve),
          ),
          _PageAction(
            key: shareKey,
            icon: FluentIcons.share_24_regular,
            label: shareLabel,
            onTap: shareAction(resolve),
          ),
          _PageAction(
            key: saveKey,
            icon: FluentIcons.arrow_circle_down_24_regular,
            label: saveLabel,
            onTap: saveAction(resolve),
          ),
        ].where((action) => action.onTap != null).toList();
        if (actions.isNotEmpty) rows.add(actions);
      }

      if (isMobile || imageClipboardSupported) {
        addMobileRow(
          copyLabel: hasSpread
              ? context.l10n.copyFirstPage
              : context.l10n.copyImageToClipboard,
          shareLabel: hasSpread
              ? context.l10n.shareFirstPage
              : context.l10n.shareImage,
          saveLabel: hasSpread
              ? context.l10n.saveFirstPage
              : context.l10n.saveToGallery,
          copyKey: const ValueKey('reader-page-action-copy-image'),
          shareKey: const ValueKey('reader-page-action-share'),
          saveKey: const ValueKey('reader-page-action-save'),
          resolve: () => resolvePageFile(firstPageIndex),
        );
        if (hasSpread) {
          addMobileRow(
            copyLabel: context.l10n.copySecondPage,
            shareLabel: context.l10n.shareSecondPage,
            saveLabel: context.l10n.saveSecondPage,
            copyKey: const ValueKey('reader-page-action-copy-image-second'),
            shareKey: const ValueKey('reader-page-action-share-second'),
            saveKey: const ValueKey('reader-page-action-save-second'),
            resolve: () => resolvePageFile(extraPageIndex),
          );
          addMobileRow(
            copyLabel: context.l10n.copySpread,
            shareLabel: context.l10n.shareSpread,
            saveLabel: context.l10n.saveSpread,
            copyKey: const ValueKey('reader-page-action-copy-spread'),
            shareKey: const ValueKey('reader-page-action-share-spread'),
            saveKey: const ValueKey('reader-page-action-save-spread'),
            resolve: resolveSpreadFile,
          );
        }
      }

      if (!isMobile && openUrl != null) {
        rows.add([
          _PageAction(
            key: const ValueKey('reader-page-action-open-web'),
            icon: FluentIcons.globe_24_regular,
            label: context.l10n.openInWeb,
            onTap: () {
              if (!current()) return;
              Navigator.pop(sheetContext);
              launchUrlInWeb(context, openUrl, ref.read(toastProvider));
            },
          ),
        ]);
      }

      return _PageActionsSheet(
        title: hasSpread
            ? context.l10n.readerGroupActions
            : context.l10n.page(firstPageIndex + 1),
        rows: rows,
      );
    },
  );
}

Future<File> _combineSpreadImages(File firstFile, File secondFile) async {
  final tempDir = await getTemporaryDirectory();
  await _cleanStaleSpreadTemps(tempDir);
  final outputPath =
      '${tempDir.path}/kuchie-spread-${DateTime.now().microsecondsSinceEpoch}.png';
  await compute(_combineSpreadImagesSync, [
    firstFile.path,
    secondFile.path,
    outputPath,
  ]);
  return File(outputPath);
}

Future<void> _cleanStaleSpreadTemps(Directory tempDir) async {
  try {
    await for (final entity in tempDir.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('kuchie-spread-') &&
          entity.path.endsWith('.png')) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Best-effort — cleanup must never break a share/save.
  }
}

void _combineSpreadImagesSync(List<String> paths) {
  final first = img.decodeImage(
    normalizeAvifBytesSync(File(paths[0]).readAsBytesSync()),
  );
  final second = img.decodeImage(
    normalizeAvifBytesSync(File(paths[1]).readAsBytesSync()),
  );
  if (first == null || second == null) {
    throw const FormatException('Could not decode spread image');
  }

  final height = math.max(first.height, second.height);
  final canvas = img.Image(
    width: first.width + second.width,
    height: height,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 255));
  img.compositeImage(
    canvas,
    first,
    dstX: 0,
    dstY: (height - first.height) ~/ 2,
    blend: img.BlendMode.direct,
  );
  img.compositeImage(
    canvas,
    second,
    dstX: first.width,
    dstY: (height - second.height) ~/ 2,
    blend: img.BlendMode.direct,
  );

  File(paths[2]).writeAsBytesSync(img.encodePng(canvas), flush: true);
}

class _PageActionsSheet extends StatelessWidget {
  const _PageActionsSheet({required this.title, required this.rows});

  final String title;
  final List<List<_PageAction>> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: title),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              children: [
                for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
                  if (rowIndex > 0)
                    const Divider(height: 16, indent: 12, endIndent: 12),
                  for (final action in rows[rowIndex])
                    ListTile(
                      key: action.key,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(action.icon, size: 22),
                      title: Text(action.label),
                      onTap: action.onTap,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PageAction {
  const _PageAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}
