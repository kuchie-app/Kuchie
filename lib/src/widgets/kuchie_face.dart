// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'package:material_ui/material_ui.dart';

/// Kuchie drawn in text: the hood as brackets and the scarf as the trailing
/// `>`, which takes the accent colour.
class KuchieFace extends StatelessWidget {
  const KuchieFace(this.face, {super.key, this.width});

  /// Kuchie faces end with the scarf, `>`, and may add a mark after it.
  final String face;

  /// Scales the face down to fit; null keeps the display size.
  final double? width;

  static const empty = '( ` ` )>';
  static const noResults = '( ` ` )>?';
  static const paused = '( - - )>';

  /// For errors and other empty states.
  static const moods = [empty, '( ; ; )>', '( ° ° )>', '( ` ` )>…'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displaySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .8),
      height: 1,
    );
    final scarf = face.lastIndexOf('>');
    final text = Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: scarf < 0 ? face : face.substring(0, scarf)),
          if (scarf >= 0)
            TextSpan(
              text: face.substring(scarf),
              style: TextStyle(color: theme.colorScheme.primary),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
    );
    final sized = width == null
        ? text
        : SizedBox(
            width: width,
            child: FittedBox(fit: BoxFit.scaleDown, child: text),
          );
    return ExcludeSemantics(child: sized);
  }
}
