// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:material_ui/material_ui.dart';

import '../../../constants/app_sizes.dart';
import '../../../constants/enum.dart';
import '../../../features/browse_center/domain/source/source_model.dart';
import '../../../features/manga_book/domain/manga/manga_model.dart';
import '../../../routes/router_config.dart';
import '../../../utils/extensions/custom_extensions.dart';
import '../../../utils/misc/copy_with_feedback.dart';
import '../../web_route_link.dart';
import '../grid/manga_cover_grid_tile.dart';
import '../widgets/manga_badges.dart';
import '../widgets/manga_chips.dart';

class MangaCoverDescriptiveListTile extends StatefulWidget {
  const MangaCoverDescriptiveListTile({
    super.key,
    this.manga,
    this.titleOverride,
    this.authorOverride,
    this.statusOverride,
    this.sourceNameOverride,
    this.onSourcePressed,
    this.coverImage,
    this.fallbackCoverImage,
    this.onPressed,
    this.onCoverPressed,
    this.onLongPress,
    this.onContinueReading,
    this.onTitleClicked,
    this.showBadges = true,
    this.showCountBadges = true,
    this.selected = false,
    this.belowStatus,
    this.outlineOnCovers = false,
    this.scale = 1.0,
    this.titleMaxLines = 2,
    this.linkLocation,
  });
  final String? linkLocation;
  /// Null for on-device series, which pass the overrides below instead.
  final MangaDto? manga;
  final String? titleOverride;
  final String? authorOverride;
  final MangaStatus? statusOverride;
  final String? sourceNameOverride;

  /// Opens the source when there is no server source route.
  final VoidCallback? onSourcePressed;
  final ImageProvider? coverImage;
  final ImageProvider? fallbackCoverImage;
  final bool showBadges;
  final bool showCountBadges;
  final VoidCallback? onPressed;
  final VoidCallback? onCoverPressed;
  final VoidCallback? onLongPress;

  /// Non-null adds a button opening the next unread chapter.
  final VoidCallback? onContinueReading;
  final ValueChanged<String?>? onTitleClicked;
  final bool selected;
  final Widget? belowStatus;

  final bool outlineOnCovers;

  /// Scale covers here; callers must scale row text through MediaQuery.
  final double scale;

  /// Null allows the title to wrap fully.
  final int? titleMaxLines;

  @override
  State<MangaCoverDescriptiveListTile> createState() =>
      _MangaCoverDescriptiveListTileState();
}

class _MangaCoverDescriptiveListTileState
    extends State<MangaCoverDescriptiveListTile> {
  var _hovered = false;
  var _focused = false;
  var _pointerFocused = false;
  late final _focusNode = FocusNode(onKeyEvent: _onKeyEvent);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    if (_focused) setState(() {});
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_pointerFocused && event is KeyDownEvent) {
      setState(() => _pointerFocused = false);
    }
    return KeyEventResult.ignored;
  }

  bool get _keyboardFocused =>
      _focused &&
      !_pointerFocused &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  Widget build(BuildContext context) {
    final manga = widget.manga;
    final title = widget.titleOverride ?? manga?.title ?? '';
    final author = widget.authorOverride ?? manga?.author;
    final status =
        widget.statusOverride ??
        (manga == null
            ? MangaStatus.unknown
            : MangaStatus.fromJson(manga.status.name));
    final sourceId = manga?.source?.id;
    final sourceName =
        widget.sourceNameOverride ?? manga?.source?.displayName;
    final sourceLocation = sourceId.isNotBlank
        ? SourceTypeRoute(
            sourceId: sourceId!,
            sourceType: SourceType.POPULAR,
          ).location
        : null;
    return ColoredBox(
      color: widget.selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
          : Colors.transparent,
      child: WebRouteLink(
        location: widget.linkLocation,
        builder: (context, openInNewTab) => InkWell(
          focusNode: _focusNode,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          focusColor: Colors.transparent,
          onTapDown: (_) => setState(() => _pointerFocused = true),
          onHover: (hovered) => setState(() => _hovered = hovered),
          onFocusChange: (focused) => setState(() {
            _focused = focused;
            if (!focused) _pointerFocused = false;
          }),
          onTap: widget.onPressed == null
              ? null
              : () {
                  _focusNode.requestFocus();
                  WebRouteLink.handleTap(openInNewTab, widget.onPressed!);
                },
          onLongPress: widget.onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(kListTilePadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: kDescriptiveCoverWidth * widget.scale,
                  height: mangaCoverBoxHeight(
                  kDescriptiveCoverWidth * widget.scale),
                  child: MangaCoverGridTile(
                    manga: manga,
                    titleOverride: widget.titleOverride,
                    coverImage: widget.coverImage,
                    fallbackCoverImage: widget.fallbackCoverImage,
                    onPressed: widget.onCoverPressed,
                    showBadges: false,
                    showTitle: false,
                    showDarkOverlay: false,
                    selected: widget.selected,
                    highlighted: _hovered || _keyboardFocused,
                    onContinueReading: widget.onContinueReading,
                    outlineOnCovers: widget.outlineOnCovers,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tap copies; press and hold searches.
                        InkWell(
                          onTap: widget.onTitleClicked != null
                              ? () => copyWithFeedback(context, title)
                              : null,
                          onLongPress: widget.onTitleClicked != null
                              ? () => widget.onTitleClicked!(title)
                              : null,
                          // Skia uncapped ellipsis collapses to one line; use clip for wrapping.
                          child: Text(
                            title,
                            style: context.textTheme.titleLarge,
                            softWrap: true,
                            overflow: widget.titleMaxLines == null
                                ? TextOverflow.clip
                                : TextOverflow.ellipsis,
                            maxLines: widget.titleMaxLines,
                            semanticsLabel: title,
                          ),
                        ),
                        Gap(8),
                        InkWell(
                          onTap: widget.onTitleClicked != null &&
                              author.isNotBlank
                              ? () => copyWithFeedback(context, author!)
                              : null,
                          onLongPress: widget.onTitleClicked != null &&
                              author.isNotBlank
                              ? () => widget.onTitleClicked!(author)
                              : null,
                          child: Text(
                            author.isNotBlank
                                ? author!
                                : context.l10n.unknownAuthor,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                        Gap(8),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              status.icon,
                              size: 16,
                              color: context.textTheme.bodySmall?.color,
                            ),
                            Text(
                              " ${status.toLocale(context)}",
                              style: context.textTheme.bodySmall,
                            ),
                            if (sourceName != null) ...[
                              Text(" • "),
                              WebRouteLink(
                                location: sourceLocation,
                                enabled: widget.linkLocation == null,
                                builder: (context, openSourceInNewTab) =>
                                    InkWell(
                                      onTap: sourceLocation != null
                                          ? () => WebRouteLink.handleTap(
                                              openSourceInNewTab,
                                              () => SourceTypeRoute(
                                                sourceId: sourceId!,
                                                sourceType: SourceType.POPULAR,
                                              ).go(context),
                                            )
                                          : widget.onSourcePressed,
                                      child: Text(
                                        sourceName,
                                        style: context.textTheme.bodySmall,
                                      ),
                                    ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.belowStatus != null) ...[
                          Gap(4),
                          widget.belowStatus!,
                        ],
                        if (widget.showBadges && manga != null)
                          context.windowSizeClass >= WindowSizeClass.medium
                              ? MangaChipsRow(
                                  manga: manga,
                                  showCountBadges: widget.showCountBadges,
                                )
                              : MangaBadgesRow(
                                  padding: KEdgeInsets.v8.size,
                                  manga: manga,
                                  showCountBadges: widget.showCountBadges,
                                ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
