// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/ui/app_feedback_sheet.dart';
import 'package:chatloom/utils/ios_shake.dart';
import 'package:chatloom/widgets/app_lock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final _preferenceChanges = ValueNotifier<int>(0);
void shakeToReportPreferenceChanged(bool _) => _preferenceChanges.value++;

/// One disposable listener below the app lock, above the router. Reports can
/// help on login screens too; there is no account/chat-data prerequisite.
class ShakeToReportScope extends StatefulWidget {
  const ShakeToReportScope({
    super.key,
    required this.navigatorKey,
    required this.child,
    @visibleForTesting this.elapsed,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final Duration Function()? elapsed;
  static const cooldown = Duration(seconds: 3);
  @override
  State<ShakeToReportScope> createState() => _ShakeToReportScopeState();
}

class _ShakeToReportScopeState extends State<ShakeToReportScope>
    with WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  AppLockController? _lock;
  StreamSubscription<void>? _subscription;
  Future<void> _closing = Future.value();
  AppLifecycleState? _lifecycle;
  Duration? _lastShake;
  bool _starting = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _preferenceChanges.addListener(_refresh);
  }

  void _bind() {
    final lock = AppLock.of(context).controller;
    if (!identical(lock, _lock)) {
      _lock?.removeListener(_refresh);
      _lock = lock..addListener(_refresh);
    }
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(ShakeToReportScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  bool get _eligible =>
      mounted &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      AppSettings.personalShakeToReport.value &&
      _lifecycle == AppLifecycleState.resumed &&
      PersonalPrivacy.surfaceForeground &&
      PersonalPrivacy.surfaceUnlocked &&
      _lock?.isLocked != true;

  void _refresh() {
    if (!_eligible) {
      _stop();
      return;
    }
    if (_subscription != null || _starting) return;
    _starting = true;
    unawaited(_start(++_generation));
  }

  Future<void> _start(int generation) async {
    await _closing;
    if (!mounted || generation != _generation || !_eligible) return;
    final available = await IosShake.available();
    if (!mounted || generation != _generation || !_eligible) return;
    _starting = false;
    if (!available) return;
    _subscription = IosShake.events.listen((_) {
      if (generation == _generation) _shake();
    }, onError: (Object _) {});
  }

  void _stop() {
    _generation++;
    _starting = false;
    if (_subscription != null) {
      _closing = _subscription!.cancel().catchError((Object _) {});
      _subscription = null;
    }
  }

  void _shake() {
    if (!_eligible) return;
    final now = widget.elapsed?.call() ?? _clock.elapsed;
    if (appFeedbackOpen) {
      _lastShake = now;
      return;
    }
    if (_lastShake != null && now - _lastShake! < ShakeToReportScope.cooldown) {
      return;
    }
    final target = widget.navigatorKey.currentState?.overlay?.context;
    if (target == null || !target.mounted) return;
    _lastShake = now;
    unawaited(showAppFeedback(target).catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferenceChanges.removeListener(_refresh);
    _lock?.removeListener(_refresh);
    _stop();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
