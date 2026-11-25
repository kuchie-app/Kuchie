// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:gap/gap.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../utils/theme/reader_overlay_colors.dart';
import '../../../../../widgets/kuchie_brush_loader.dart';

/// How long a page may go without new data before the reader offers a retry.
const kReaderPageTimeout = Duration(seconds: 20);

/// What a page shows while it loads: the muted Kuchie brush mark, the page
/// number, and once nothing has arrived for [timeout], a way to try again.
/// The page itself appears as soon as it is ready, with no reveal.
class ReaderPageLoader extends StatefulWidget {
  const ReaderPageLoader({
    super.key,
    this.progress,
    this.pageNumber,
    this.onRetry,
    this.timeout = kReaderPageTimeout,
    this.size = 44,
  });

  /// From 0 to 1, or null when the download size is unknown.
  final double? progress;

  /// One-based page number, shown under the mark.
  final int? pageNumber;

  /// Starts the load again; without it the timeout shows no button.
  final VoidCallback? onRetry;
  final Duration timeout;
  final double size;

  @override
  State<ReaderPageLoader> createState() => _ReaderPageLoaderState();
}

class _ReaderPageLoaderState extends State<ReaderPageLoader> {
  Timer? _timer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(ReaderPageLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Data still arriving means it is slow, not stuck.
    if ((widget.progress ?? 0) > (oldWidget.progress ?? 0)) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (mounted) setState(() => _timedOut = true);
    });
    if (_timedOut) setState(() => _timedOut = false);
  }

  void _retry() {
    widget.onRetry?.call();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas =
        Scaffold.maybeOf(context)?.widget.backgroundColor ??
        Theme.of(context).scaffoldBackgroundColor;
    final foreground = readerCanvasForeground(canvas);
    final caption = context.textTheme.labelSmall?.copyWith(
      color: foreground.withValues(alpha: .45),
    );
    return Semantics(
      label: context.l10n.readerLoadingChapter,
      liveRegion: _timedOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KuchieBrushLoader(
            progress: widget.progress,
            size: widget.size,
            color: foreground,
          ),
          if (widget.pageNumber case final page?) ...[
            const Gap(10),
            Text(context.l10n.readerPageLabel(page), style: caption),
          ],
          if (_timedOut) ...[
            const Gap(12),
            Text(context.l10n.readerPageSlow, style: caption),
            if (widget.onRetry != null)
              TextButton(
                onPressed: _retry,
                style: TextButton.styleFrom(
                  foregroundColor: foreground.withValues(alpha: .8),
                ),
                child: Text(context.l10n.retry),
              ),
          ],
        ],
      ),
    );
  }
}
