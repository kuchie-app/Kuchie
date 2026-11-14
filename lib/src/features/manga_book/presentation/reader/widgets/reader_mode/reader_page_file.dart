import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../utils/extensions/custom_extensions.dart';
import '../../../../../../widgets/custom_circular_progress_indicator.dart';

Widget readerPageRetry(BuildContext context, VoidCallback onRetry) => Center(
  child: TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
);

/// A temporary page becomes a local file when its first visible slot needs it.
class ReaderPageFile extends StatefulWidget {
  const ReaderPageFile({
    required this.uri,
    required this.prepare,
    required this.retryCount,
    required this.builder,
    super.key,
  });

  final String uri;
  final Future<File> Function(String uri) prepare;
  final ValueListenable<int> retryCount;
  final WidgetBuilder builder;

  @override
  State<ReaderPageFile> createState() => _ReaderPageFileState();
}

class _ReaderPageFileState extends State<ReaderPageFile> {
  late Future<File> _file = widget.prepare(widget.uri);

  @override
  void initState() {
    super.initState();
    widget.retryCount.addListener(_retry);
  }

  @override
  void didUpdateWidget(ReaderPageFile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retryCount != widget.retryCount) {
      oldWidget.retryCount.removeListener(_retry);
      widget.retryCount.addListener(_retry);
    }
    if (oldWidget.uri != widget.uri || oldWidget.prepare != widget.prepare) {
      _file = widget.prepare(widget.uri);
    }
  }

  void _retry() => setState(() => _file = widget.prepare(widget.uri));

  @override
  void dispose() {
    widget.retryCount.removeListener(_retry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: _file,
    builder: (context, snapshot) =>
        snapshot.connectionState != ConnectionState.done
        ? const Center(child: CenterKuchieShimmerIndicator())
        : snapshot.hasError
        ? readerPageRetry(context, _retry)
        : widget.builder(context),
  );
}
