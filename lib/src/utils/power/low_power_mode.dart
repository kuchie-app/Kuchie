import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether iOS Low Power Mode is on, so decorative motion can stop.
/// False where the platform does not answer.
class LowPowerMode extends Notifier<bool> {
  static const channel = MethodChannel('kuchie/power');

  @override
  bool build() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'lowPowerModeChanged' && call.arguments is bool) {
        state = call.arguments as bool;
      }
    });
    ref.onDispose(() => channel.setMethodCallHandler(null));
    _read();
    return false;
  }

  Future<void> _read() async {
    try {
      final enabled = await channel.invokeMethod<bool>('isLowPowerModeEnabled');
      if (enabled != null) state = enabled;
    } on MissingPluginException {
      // Not iOS, or a test: assume full power.
    } on PlatformException {
      // Same.
    }
  }
}

final lowPowerModeProvider = NotifierProvider<LowPowerMode, bool>(
  LowPowerMode.new,
);
