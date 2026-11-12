// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chatloom/personal/privacy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Snapshots the Flutter surface on demand, before the report route is pushed.
/// Lives below the app lock. No periodic captures, permissions or disk writes.
class AppFeedbackCaptureScope extends StatefulWidget {
  const AppFeedbackCaptureScope({
    super.key,
    required this.child,
    @visibleForTesting this.captureImage,
  });
  final Widget child;
  final Future<Uint8List?> Function(RenderRepaintBoundary, double)?
  captureImage;

  static Future<Uint8List?> capture(BuildContext context) async {
    final scope = context
        .findAncestorStateOfType<_AppFeedbackCaptureScopeState>();
    if (scope == null) return null;
    try {
      return await scope.capture().timeout(const Duration(seconds: 2));
    } catch (_) {
      // A failed screenshot must not prevent a text report.
      return null;
    }
  }

  @override
  State<AppFeedbackCaptureScope> createState() =>
      _AppFeedbackCaptureScopeState();
}

class _AppFeedbackCaptureScopeState extends State<AppFeedbackCaptureScope> {
  final _boundary = GlobalKey();
  static const _maxSide = 2048.0;
  static const _maxBytes = 8 * 1024 * 1024;

  bool current(int generation) =>
      mounted &&
      generation == PersonalPrivacy.surfaceGeneration &&
      PersonalPrivacy.surfaceUnlocked &&
      PersonalPrivacy.surfaceForeground &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<Uint8List?> capture() async {
    final generation = PersonalPrivacy.surfaceGeneration;
    if (!current(generation)) return null;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !current(generation)) return null;
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.attached ||
        !boundary.hasSize ||
        boundary.size.isEmpty) {
      return null;
    }
    final ratio = math.min(
      math.min(MediaQuery.devicePixelRatioOf(context), 2.0),
      _maxSide / boundary.size.longestSide,
    );
    final Uint8List? bytes;
    if (widget.captureImage case final capture?) {
      bytes = await capture(boundary, ratio);
    } else {
      final image = await boundary.toImage(pixelRatio: ratio);
      try {
        if (!current(generation)) return null;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data?.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } finally {
        image.dispose();
      }
    }
    return current(generation) &&
            bytes != null &&
            bytes.isNotEmpty &&
            bytes.length <= _maxBytes
        ? bytes
        : null;
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: _boundary, child: widget.child);
}
