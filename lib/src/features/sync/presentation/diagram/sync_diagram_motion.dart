import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/diagram/sync_methods.dart';
import '../../domain/diagram/sync_scene.dart';

/// The diagram's moving state: eased values, clocks, arrivals and labels.
/// The widget advances it every frame; the painter only reads it.
class DiagramMotion extends ChangeNotifier {
  DiagramMotion(SyncScene scene, {required bool reduce})
    : _scene = scene,
      _reduce = reduce,
      values = scene.values {
    _settle();
    _refreshScreens();
  }

  SyncScene _scene;
  SyncScene get scene => _scene;

  bool _reduce;
  bool get reduce => _reduce;

  /// Eased brightness, approaching [SyncScene.values].
  SceneValues values;

  /// Seconds since the diagram started, for ambient motion.
  double t = 0;

  /// Seconds since the scene started, for flows.
  double sceneT = 0;

  /// Orbit angle.
  double rotation = 0;

  /// Offset of the moving dashes.
  double march = 0;

  /// Tokens fade in after a scene change.
  double flowFade = 1;

  /// The whole diagram fades in after a method change.
  double topologyFade = 1;

  /// Lines drawing themselves in, while checking.
  double drawOn = 1;
  double _counter = 0;

  /// Scale of each device's check badge, popping in one after another.
  List<double> checkPop = [1, 1, 1, 1];

  /// Arrival feedback per node id, decaying to 0.
  final bumps = <String, double>{};
  final _cycles = <String, int>{};

  /// Ambient motion runs; off in Low Power Mode.
  bool ambient = true;

  late SceneScreens screens;

  /// Captions that change with time, for the label widgets.
  final captions = ValueNotifier<(SyncCopy?, SyncCopy)>((
    null,
    (en: '', id: ''),
  ));

  /// Steps of the scene's counter.
  int get counter {
    final spec = _scene.spec.counter;
    if (spec == null) return 0;
    if (_reduce) {
      return _scene.status == SyncStatusKind.moveToServer ? 34 : 24;
    }
    return math.min(spec.total, (spec.start + _counter).floor());
  }

  /// Statuses with flows run at full frame rate; the rest are ambient only.
  bool get busy => _scene.flows.isNotEmpty || _scene.spec.scan;

  /// Whether anything still changes without ambient motion.
  bool get settling =>
      sceneT < .8 || topologyFade < 1 || bumps.values.any((b) => b > 0);

  /// Shows [next]: a new method or status restarts the scene's clock; new
  /// figures for the same one only update the screens.
  void show(SyncScene next) {
    if (identical(next, _scene)) return;
    if (identical(next.method, _scene.method) && next.status == _scene.status) {
      _scene = next;
      _refreshScreens();
      notifyListeners();
      return;
    }
    apply(next);
  }

  void apply(SyncScene next) {
    final topologyChanged = !identical(next.method, _scene.method);
    _scene = next;
    sceneT = 0;
    flowFade = 0;
    drawOn = next.spec.drawOn ? 0 : 1;
    _counter = 0;
    _cycles.clear();
    if (topologyChanged) {
      topologyFade = 0;
      bumps.clear();
    }
    if (next.values.check > 0) checkPop = [.15, .15, .15, .15];
    if (_reduce) _settle();
    _refreshScreens();
    notifyListeners();
  }

  set reduce(bool value) {
    if (value == _reduce) return;
    _reduce = value;
    if (value) _settle();
    _refreshScreens();
    notifyListeners();
  }

  void _settle() {
    values = _scene.values;
    drawOn = 1;
    flowFade = 1;
    topologyFade = 1;
    checkPop = [1, 1, 1, 1];
    bumps.clear();
  }

  /// Advances [dt] seconds.
  void step(double dt) {
    dt = math.min(dt, .05);
    t += dt;
    sceneT += dt;
    final spec = _scene.spec;
    values = values.approach(_scene.values, 1 - math.exp(-dt / .09));
    flowFade = math.min(1, flowFade + dt / .4);
    topologyFade = math.min(1, topologyFade + dt / .35);
    rotation += dt * spec.spin;
    march += dt * spec.march.abs();
    for (final id in bumps.keys.toList()) {
      bumps[id] = math.max(0, bumps[id]! - dt * 3.2);
    }
    checkPop = [
      for (var i = 0; i < checkPop.length; i++)
        sceneT > i * .18 ? math.min(1, checkPop[i] + dt * 3.5) : checkPop[i],
    ];
    if (spec.drawOn) drawOn = math.min(1, drawOn + dt / 1.2);
    final counterSpec = spec.counter;
    if (counterSpec != null) {
      _counter += dt / counterSpec.step;
      if (counter >= counterSpec.total) _counter = 0;
    }
    _arrivals();
    _refreshScreens();
    notifyListeners();
  }

  void _hit(String node) => bumps[node] = math.min(1, (bumps[node] ?? 0) + .8);

  void _arrivals() {
    final flows = _scene.flows;
    for (var f = 0; f < flows.length; f++) {
      final flow = flows[f];
      if (flow.isPeriodic) {
        if (sceneT < flow.delay) continue;
        final phase = (sceneT - flow.delay) % flow.every!;
        final cycle = ((sceneT - flow.delay) / flow.every!).floor();
        final key = '$f';
        if (phase <= flow.travel! &&
            phase / flow.travel! > .96 &&
            _cycles[key] != cycle) {
          _hit(flow.to);
          _cycles[key] = cycle;
        }
        continue;
      }
      for (var i = 0; i < flow.count; i++) {
        final cycle = (sceneT * flow.speed + i / flow.count).floor();
        final key = '$f-$i';
        final previous = _cycles[key];
        if (previous != null && previous != cycle && flowFade > .5) {
          _hit(flow.to);
        }
        _cycles[key] = cycle;
      }
    }
  }

  void _refreshScreens() {
    screens = screensFor(_scene, counter, sceneT);
    final next = (screens.hubSub, screens.phoneSub);
    if (captions.value != next) captions.value = next;
  }

  @override
  void dispose() {
    captions.dispose();
    super.dispose();
  }
}
