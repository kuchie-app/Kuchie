import 'dart:async';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/extensions/custom_extensions.dart';
import '../../widgets/kuchie_logo.dart';

/// How long Kuchie may stay in the background before App lock asks again.
enum AppLockDelay {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15)),
  oneHour(Duration(hours: 1));

  const AppLockDelay(this.duration);

  final Duration duration;
}

/// How an attempt to verify the owner ended.
enum AppAuthResult {
  success,

  /// The reader cancelled or failed the check.
  failed,

  /// The device has no passcode or biometrics to check with.
  unavailable,
}

/// App lock and screen privacy, shared by the Server and Local collections.
class AppSecurityPreferences {
  AppSecurityPreferences._();

  static final instance = AppSecurityPreferences._();

  static const _appLockKey = 'security.appLock';
  static const _lockDelayKey = 'security.appLockDelay';
  static const _secureScreenKey = 'security.secureScreen';
  static const _disableSharingKey = 'security.disableSharing';

  /// Requires Face ID, Touch ID or the device passcode to open Kuchie.
  final appLock = ValueNotifier<bool>(false);
  final lockDelay = ValueNotifier<AppLockDelay>(AppLockDelay.immediately);

  /// Covers Kuchie's content in the app switcher.
  final secureScreen = ValueNotifier<bool>(false);

  /// Blocks sharing manga links, pages and covers, so nothing is shared by
  /// accident.
  final disableSharing = ValueNotifier<bool>(false);

  Future<void>? _loading;

  Future<void> load() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    appLock.value = prefs.getBool(_appLockKey) ?? false;
    lockDelay.value = AppLockDelay.values.firstWhere(
      (delay) => delay.name == prefs.getString(_lockDelayKey),
      orElse: () => AppLockDelay.immediately,
    );
    secureScreen.value = prefs.getBool(_secureScreenKey) ?? false;
    disableSharing.value = prefs.getBool(_disableSharingKey) ?? false;
  }();

  Future<void> setDisableSharing(bool value) async {
    await load();
    disableSharing.value = value;
    await (await SharedPreferences.getInstance()).setBool(
      _disableSharingKey,
      value,
    );
  }

  /// Turns App lock on only after the reader proves they can unlock, so a
  /// device without a passcode cannot lock itself out.
  Future<AppAuthResult> setAppLock(bool value, {required String reason}) async {
    await load();
    if (value) {
      final result = await verify(reason);
      if (result != AppAuthResult.success) return result;
    }
    appLock.value = value;
    await (await SharedPreferences.getInstance()).setBool(_appLockKey, value);
    return AppAuthResult.success;
  }

  Future<void> setLockDelay(AppLockDelay delay) async {
    await load();
    lockDelay.value = delay;
    await (await SharedPreferences.getInstance()).setString(
      _lockDelayKey,
      delay.name,
    );
  }

  Future<void> setSecureScreen(bool value) async {
    await load();
    secureScreen.value = value;
    await (await SharedPreferences.getInstance()).setBool(
      _secureScreenKey,
      value,
    );
  }

  /// Whether this device can verify the owner (biometrics or a passcode).
  Future<bool> available() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> authenticate(String reason) async =>
      await verify(reason) == AppAuthResult.success;

  Future<AppAuthResult> verify(String reason) async {
    try {
      return await LocalAuthentication().authenticate(
            localizedReason: reason,
            persistAcrossBackgrounding: true,
          )
          ? AppAuthResult.success
          : AppAuthResult.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable => AppAuthResult.unavailable,
        _ => AppAuthResult.failed,
      };
    } on PlatformException {
      return AppAuthResult.unavailable;
    } on MissingPluginException {
      return AppAuthResult.unavailable;
    }
  }
}

/// Whether sharing may go ahead; explains why not when the reader turned
/// content sharing off.
bool contentSharingAllowed(BuildContext context) {
  if (!AppSecurityPreferences.instance.disableSharing.value) return true;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(context.l10n.contentSharingDisabled)),
    );
  return false;
}

/// Shows the lock screen while App lock is on and the reader has not
/// unlocked, and a privacy cover in the app switcher when asked to.
class AppSecurityGate extends StatefulWidget {
  const AppSecurityGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppSecurityGate> createState() => _AppSecurityGateState();
}

class _AppSecurityGateState extends State<AppSecurityGate>
    with WidgetsBindingObserver {
  final _preferences = AppSecurityPreferences.instance;
  bool _locked = false;
  bool _obscured = false;
  bool _authenticating = false;
  bool _loaded = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    await _preferences.load();
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _locked = _preferences.appLock.value;
    });
    if (_locked) unawaited(_unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Face ID itself makes the app inactive; keep the lock screen as is.
        if (!_authenticating && _preferences.secureScreen.value) {
          setState(() => _obscured = true);
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_authenticating) return;
        _backgroundedAt ??= DateTime.now();
        if (_preferences.secureScreen.value) setState(() => _obscured = true);
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        final lock =
            _preferences.appLock.value &&
            since != null &&
            DateTime.now().difference(since) >=
                _preferences.lockDelay.value.duration;
        setState(() {
          _obscured = false;
          if (lock) _locked = true;
        });
        if (_locked && !_authenticating) unawaited(_unlock());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final reason = mounted ? context.l10n.appLockReason : 'Unlock Kuchie';
      final unlocked = await _preferences.authenticate(reason);
      if (mounted && unlocked) setState(() => _locked = false);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = !_loaded && _preferences.appLock.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keeps routes and state alive underneath, without painting or
        // taking input, while locked.
        Offstage(offstage: _locked || cover, child: widget.child),
        if (_locked || cover)
          _LockScreen(onUnlock: cover ? null : _unlock)
        else if (_obscured)
          const _PrivacyCover(),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KuchieLogo(size: 96),
            const SizedBox(height: 24),
            Text(
              context.l10n.appLockLocked,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(context.l10n.appLockUnlock),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: const Center(child: KuchieLogo(size: 96)),
  );
}
