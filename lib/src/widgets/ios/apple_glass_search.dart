// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'apple_glass_capability.dart';

const _viewType = 'kuchie/apple_glass/search';

class AppleGlassSearch extends StatelessWidget {
  const AppleGlassSearch({
    super.key,
    required this.fallback,
    required this.native,
  });

  final WidgetBuilder fallback;
  final WidgetBuilder native;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS ||
        !appleGlassEnabled(context)) {
      return fallback(context);
    }
    return native(context);
  }
}

class AppleGlassSearchControl extends StatefulWidget {
  const AppleGlassSearchControl.field({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.label,
    this.autofocus = false,
    this.keepFocusOnSubmit = false,
    this.onChanged,
    this.onSubmitted,
  }) : onOpen = null,
       displayText = '';

  const AppleGlassSearchControl.entry({
    super.key,
    required this.placeholder,
    required this.label,
    required this.displayText,
    required this.onOpen,
  }) : controller = null,
       focusNode = null,
       autofocus = false,
       keepFocusOnSubmit = false,
       onChanged = null,
       onSubmitted = null;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool keepFocusOnSubmit;
  final String placeholder;
  final String label;
  final String displayText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onOpen;

  static const double height = 44;

  @override
  State<AppleGlassSearchControl> createState() =>
      _AppleGlassSearchControlState();
}

class _AppleGlassSearchControlState extends State<AppleGlassSearchControl> {
  MethodChannel? _channel;
  bool _receivingInput = false;
  bool _nativeFocus = false;
  bool? _lastSentFocus;

  Map<String, Object> get _configuration {
    final value = widget.controller?.value;
    return {
      'entry': widget.onOpen != null,
      'autofocus': widget.autofocus,
      'keepFocusOnSubmit': widget.keepFocusOnSubmit,
      'placeholder': widget.placeholder,
      'label': widget.label,
      'text': value?.text ?? widget.displayText,
      'start': value?.selection.start ?? -1,
      'end': value?.selection.end ?? -1,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'rtl': Directionality.of(context) == TextDirection.rtl,
      'tint': Theme.of(context).colorScheme.primary.toARGB32(),
    };
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    widget.focusNode?.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateNative();
  }

  @override
  void didUpdateWidget(AppleGlassSearchControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      widget.focusNode?.addListener(_onFocusChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.label != widget.label ||
        oldWidget.placeholder != widget.placeholder ||
        oldWidget.displayText != widget.displayText ||
        oldWidget.keepFocusOnSubmit != widget.keepFocusOnSubmit) {
      _updateNative();
    }
  }

  void _onControllerChanged() {
    if (!_receivingInput) _updateNative();
  }

  void _onFocusChanged() {
    final hasFocus = widget.focusNode?.hasFocus ?? false;
    if (hasFocus != _nativeFocus && hasFocus != _lastSentFocus) {
      _lastSentFocus = hasFocus;
      _send('focus', hasFocus);
    }
  }

  void _send(String method, Object arguments) {
    final channel = _channel;
    if (channel != null) {
      unawaited(channel.invokeMethod<void>(method, arguments));
    }
  }

  void _updateNative() {
    if (_channel != null) _send('update', _configuration);
  }

  void _onCreated(int id) {
    if (!mounted) return;
    _channel = MethodChannel('$_viewType/$id')
      ..setMethodCallHandler(_handleCall);
    _updateNative();
    if (widget.focusNode?.hasFocus == true) _onFocusChanged();
  }

  Future<void> _handleCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'open':
        widget.onOpen?.call();
      case 'focusChanged':
        _nativeFocus = call.arguments == true;
        _lastSentFocus = _nativeFocus;
        if (_nativeFocus) {
          widget.focusNode?.requestFocus();
        } else if (widget.focusNode?.hasFocus == true) {
          widget.focusNode?.unfocus();
        }
      case 'submit':
        final text = call.arguments;
        if (text is String) widget.onSubmitted?.call(text);
      case 'input':
        final controller = widget.controller;
        final data = call.arguments;
        if (controller == null || data is! Map<Object?, Object?>) return;
        final text = data['text'];
        if (text is! String) return;
        int offset(String key) =>
            (data[key] as int? ?? text.length).clamp(0, text.length);
        final markedStart = data['markedStart'] as int? ?? -1;
        final markedEnd = data['markedEnd'] as int? ?? -1;
        final old = controller.value;
        _receivingInput = true;
        try {
          controller.value = TextEditingValue(
            text: text,
            selection: TextSelection(
              baseOffset: offset('start'),
              extentOffset: offset('end'),
            ),
            composing: markedStart < 0 || markedEnd < markedStart
                ? TextRange.empty
                : TextRange(
                    start: offset('markedStart'),
                    end: offset('markedEnd'),
                  ),
          );
        } finally {
          _receivingInput = false;
        }
        if (old.text != text) widget.onChanged?.call(text);
      default:
        throw MissingPluginException();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    _channel?.setMethodCallHandler(null);
    if (_nativeFocus || widget.autofocus) _send('focus', false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.textScalerOf(context).scale(17).clamp(17.0, 64.0) +
        (AppleGlassSearchControl.height - 17);
    final view = SizedBox(
      height: widget.onOpen != null ? AppleGlassSearchControl.height : height,
      child: UiKitView(
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: _configuration,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
      ),
    );
    if (widget.focusNode case final node?) {
      // Keep the caller's node out of traversal without writing its
      // skipTraversal: a useFocusNode owner resets that on every rebuild, and
      // the two writes notified each other on every frame, so the screen
      // never went idle.
      return ExcludeFocusTraversal(
        child: Focus.withExternalFocusNode(focusNode: node, child: view),
      );
    }
    return view;
  }
}
