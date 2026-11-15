// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';

import 'package:chatloom/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Independent iOS preferences; UI motion and animated media are not the same
/// setting. Null animatedImages means an older runner/platform has no signal.
@immutable
class NotionAccessibilitySettings {
  const NotionAccessibilitySettings({
    this.reduceMotion = false,
    this.reduceTransparency = false,
    this.animatedImages,
  });
  final bool reduceMotion;
  final bool reduceTransparency;
  final bool? animatedImages;

  factory NotionAccessibilitySettings.fromMap(Map<Object?, Object?> value) =>
      NotionAccessibilitySettings(
        reduceMotion: value['reduceMotion'] == true,
        reduceTransparency: value['reduceTransparency'] == true,
        animatedImages: value['animatedImages'] is bool
            ? value['animatedImages'] as bool
            : null,
      );

  @override
  bool operator ==(Object other) =>
      other is NotionAccessibilitySettings &&
      reduceMotion == other.reduceMotion &&
      reduceTransparency == other.reduceTransparency &&
      animatedImages == other.animatedImages;
  @override
  int get hashCode =>
      Object.hash(reduceMotion, reduceTransparency, animatedImages);
}

class NotionAccessibilityScope extends InheritedWidget {
  const NotionAccessibilityScope({
    super.key,
    required this.settings,
    required super.child,
  });
  final NotionAccessibilitySettings? settings;
  static NotionAccessibilitySettings? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NotionAccessibilityScope>()
      ?.settings;
  @override
  bool updateShouldNotify(NotionAccessibilityScope oldWidget) =>
      settings != oldWidget.settings;
}

/// One native subscription above the navigator. Refresh on resume as well as
/// native changes; a preference switch never remounts the editor or navigator.
class NotionAccessibility extends StatefulWidget {
  const NotionAccessibility({super.key, required this.child});
  final Widget child;
  static const channel = MethodChannel('chatloom/ios_accessibility');
  @override
  State<NotionAccessibility> createState() => _NotionAccessibilityState();
}

class _NotionAccessibilityState extends State<NotionAccessibility>
    with WidgetsBindingObserver {
  NotionAccessibilitySettings? _settings;
  @override
  void initState() {
    super.initState();
    if (!PlatformInfos.isIOS) return;
    WidgetsBinding.instance.addObserver(this);
    NotionAccessibility.channel.setMethodCallHandler((call) async {
      if (call.method == 'settingsChanged') _accept(call.arguments);
    });
    unawaited(_refresh());
  }

  void _accept(Object? value) {
    if (!mounted || value is! Map) return;
    final next = NotionAccessibilitySettings.fromMap(value);
    if (next != _settings) setState(() => _settings = next);
  }

  Future<void> _refresh() async {
    try {
      _accept(
        await NotionAccessibility.channel
            .invokeMethod<Object?>('snapshot')
            .timeout(const Duration(seconds: 2)),
      );
    } catch (_) {
      // Old native runners still use Flutter's conservative motion fallback.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    if (PlatformInfos.isIOS) {
      NotionAccessibility.channel.setMethodCallHandler(null);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotionAccessibilityScope(settings: _settings, child: widget.child);
}
