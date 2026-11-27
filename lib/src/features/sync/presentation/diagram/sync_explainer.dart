import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/diagram/sync_methods.dart';
import '../../domain/diagram/sync_scene.dart';

/// The three-step "how it works" mode (design 3.9): local, connected, away.
///
/// Each step lasts about 3.8 seconds and a tap moves on. With Reduce Motion
/// the steps only move on a tap. After the last step the card goes back to
/// the real method and status.
class SyncExplainer extends ChangeNotifier {
  SyncExplainer({this.stepDuration = const Duration(milliseconds: 3800)});

  final Duration stepDuration;

  int? _step;
  Timer? _timer;
  bool _manual = false;

  /// The step on screen, 0 to 2, or null when the explainer is off.
  int? get step => _step;
  bool get active => _step != null;

  static int get stepCount => explainerSteps.length;

  /// The scene of the current step.
  SyncScene? get scene {
    final step = _step;
    if (step == null) return null;
    final (method, status, _) = explainerSteps[step];
    return sceneFor(method, status);
  }

  SyncCopy? get caption => _step == null ? null : explainerSteps[_step!].$3;

  /// Starts from the first step. [manual] waits for taps instead of a timer.
  void start({bool manual = false}) {
    _manual = manual;
    goTo(0);
  }

  void goTo(int step) {
    _timer?.cancel();
    _step = step;
    if (!_manual) _timer = Timer(stepDuration, next);
    notifyListeners();
  }

  /// The next step, or back to the real state after the last one.
  void next() {
    final step = _step;
    if (step == null) return;
    if (step < stepCount - 1) {
      goTo(step + 1);
    } else {
      stop();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_step == null) return;
    _step = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
