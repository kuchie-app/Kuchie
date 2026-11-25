// Copyright (c) 2022 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';

import '../constants/app_sizes.dart';
import '../utils/extensions/custom_extensions.dart';
import 'kuchie_character_motion.dart';
import 'kuchie_face.dart';
import 'web_selection_area.dart';

class Emoticons extends HookWidget {
  const Emoticons({
    super.key,
    this.title,
    this.subTitle,
    this.button,
    this.iconData,
    this.illustration,
  });
  final String? title;
  final String? subTitle;
  final IconData? iconData;
  final Widget? button;
  final KuchieCharacterPhase? illustration;

  @override
  Widget build(BuildContext context) {
    final phase = illustration;
    final errorFace = useMemoized(() => KuchieFace.moods.getRandom!);
    final content = Padding(
      padding: KEdgeInsets.a8.size,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: phase != null
                  ? KuchieCharacterMotion(phase: phase)
                  : iconData != null
                  ? Icon(iconData, size: context.height * .2)
                  : KuchieFace(errorFace),
            ),
            if (title.isNotBlank)
              Text(
                title!,
                textAlign: TextAlign.center,
                style: context.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 3,
              ),
            if (subTitle.isNotBlank)
              Text(
                subTitle!,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ?button,
          ],
        ),
      ),
    );
    return WebSelectionArea(
      child: _NoIntrinsicSize(
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.hasBoundedHeight
              ? SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: content,
                  ),
                )
              : content,
        ),
      ),
    );
  }
}

/// Lets slivers that measure their child, such as the paged lists' first-page
/// SliverFillRemaining(hasScrollBody: false), hold Emoticons.
///
/// A LayoutBuilder cannot report intrinsic sizes, so measuring it threw on
/// every frame and the error or empty state never appeared. Reporting zero
/// makes those slivers fill the space left, where the content centers itself.
class _NoIntrinsicSize extends SingleChildRenderObjectWidget {
  const _NoIntrinsicSize({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNoIntrinsicSize();
}

class _RenderNoIntrinsicSize extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
}
