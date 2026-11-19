// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../constants/app_sizes.dart';
import '../../../../../routes/router_config.dart';
import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/misc/toast/toast.dart';
import '../../../../../widgets/ios/apple_glass_capability.dart';
import '../../../../../widgets/server_image.dart';
import '../../../../../widgets/web_route_link.dart';
import '../../../data/source_repository/source_repository.dart';
import '../../../domain/source/source_model.dart';
import '../controller/source_controller.dart';

class SourceListTile extends ConsumerWidget {
  const SourceListTile({super.key, required this.source});

  final SourceDto source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void remember() =>
        ref.read(sourceLastUsedProvider.notifier).update(source.id);
    final popular = SourceTypeRoute(
      sourceId: source.id,
      sourceType: SourceType.POPULAR,
    );
    final latest = SourceTypeRoute(
      sourceId: source.id,
      sourceType: SourceType.LATEST,
    );
    return SourceListTileView(
      name: source.name,
      language: source.language?.displayName,
      icon: ServerImage(imageUrl: source.iconUrl, size: const Size.square(48)),
      popularLocation: popular.location,
      latestLocation: source.supportsLatest.ifNull() ? latest.location : null,
      onOpen: () {
        remember();
        popular.go(context);
      },
      onOpenLatest: source.supportsLatest.ifNull()
          ? () {
              remember();
              latest.go(context);
            }
          : null,
      pin: _PinButton(source: source),
    );
  }
}

/// One source in the Sources list, for every collection: icon, name,
/// language, a Latest button and the pin. Server and on-device sources draw
/// the same row.
class SourceListTileView extends StatelessWidget {
  const SourceListTileView({
    super.key,
    required this.name,
    required this.icon,
    required this.onOpen,
    required this.pin,
    this.language,
    this.onOpenLatest,
    this.onOpenSettings,
    this.popularLocation,
    this.latestLocation,
  });

  final String name;
  final Widget icon;
  final String? language;
  final VoidCallback onOpen;

  /// Null when the source has no Latest listing.
  final VoidCallback? onOpenLatest;

  /// Null when the source has no settings of its own.
  final VoidCallback? onOpenSettings;
  final Widget pin;

  /// Web routes, so a modifier-click can open a new tab.
  final String? popularLocation;
  final String? latestLocation;

  /// Icon slot for sources without a server icon URL.
  static Widget iconFor(Uri? url) => url == null
      ? const SizedBox.square(
          dimension: 48,
          child: Icon(FluentIcons.puzzle_piece_24_regular, size: 28),
        )
      : ServerImage(imageUrl: url.toString(), size: const Size.square(48));

  @override
  Widget build(BuildContext context) {
    final glass = supportsAppleGlass(context);
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onOpenSettings case final openSettings?)
          IconButton(
            onPressed: openSettings,
            tooltip: context.l10n.settings,
            icon: const Icon(FluentIcons.settings_24_regular),
          ),
        pin,
        if (onOpenLatest case final openLatest?)
          WebRouteLink(
            location: latestLocation,
            builder: (context, openLatestInNewTab) {
              void open() =>
                  WebRouteLink.handleTap(openLatestInNewTab, openLatest);
              return glass
                  ? IconButton(
                      onPressed: open,
                      tooltip: context.l10n.latest,
                      icon: const Icon(FluentIcons.news_24_regular),
                    )
                  : TextButton(
                      onPressed: open,
                      child: Text(context.l10n.latest),
                    );
            },
          ),
      ],
    );
    Widget tile(VoidCallback? openInNewTab, Widget? trailing) => ListTile(
      onTap: () => WebRouteLink.handleTap(openInNewTab, onOpen),
      leading: ClipRRect(borderRadius: KBorderRadius.r8.radius, child: icon),
      title: Text(name, style: glass ? context.textTheme.titleMedium : null),
      subtitle: language.isNotBlank ? Text(language!) : null,
      trailing: trailing,
    );
    final popular = WebRouteLink(
      location: popularLocation,
      builder: (context, openInNewTab) =>
          tile(openInNewTab, kIsWeb ? null : actions),
    );
    if (!kIsWeb) return popular;
    // The Latest button cannot sit inside the row link: the anchor would cover it.
    return Row(
      children: [
        Expanded(child: popular),
        actions,
      ],
    );
  }
}

/// Pin toggle used by [SourceListTileView].
class SourcePinButton extends StatelessWidget {
  const SourcePinButton({
    super.key,
    required this.pinned,
    required this.onPressed,
  });

  final bool pinned;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: pinned ? context.l10n.unpinSource : context.l10n.pinSource,
    icon: Icon(pinned ? FluentIcons.pin_24_filled : FluentIcons.pin_24_regular),
    color: pinned ? context.theme.colorScheme.primary : null,
    onPressed: onPressed,
  );
}

class _PinButton extends ConsumerWidget {
  const _PinButton({required this.source});

  final SourceDto source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = source.isPinned;
    return SourcePinButton(
      pinned: pinned,
      onPressed: () async {
        try {
          await ref
              .read(sourceRepositoryProvider)
              .setSourcePinned(source.id, !pinned);
          ref.invalidate(sourceListProvider);
        } catch (e) {
          if (context.mounted) {
            ref.read(toastProvider)?.showError(e.toString());
          }
        }
      },
    );
  }
}
