// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Deliberately allowlisted display/build context. No account, server, device
/// name/identifier, messages, tokens, log dump or automatic submission.
class AppFeedbackEnvironment {
  const AppFeedbackEnvironment({
    required this.version,
    required this.build,
    required this.platform,
    required this.systemVersion,
    required this.width,
    required this.height,
    required this.textScale,
    required this.dark,
    required this.reducedMotion,
  });
  final String version, build, platform, systemVersion;
  final int width, height;
  final double textScale;
  final bool dark, reducedMotion;

  static Future<AppFeedbackEnvironment> capture({
    required int width,
    required int height,
    required double textScale,
    required bool dark,
    required bool reducedMotion,
  }) async {
    var version = 'Unknown', build = 'Unknown', systemVersion = 'Unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        // Keep only the OS version, never a full system/device information map.
        systemVersion =
            RegExp(
              r'(?:Version |iOS )(\d+(?:\.\d+){1,3})',
            ).firstMatch(Platform.operatingSystemVersion)?.group(1) ??
            'Unknown';
      } catch (_) {}
    }
    return AppFeedbackEnvironment(
      version: version,
      build: build,
      platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      systemVersion: systemVersion,
      width: width,
      height: height,
      textScale: textScale,
      dark: dark,
      reducedMotion: reducedMotion,
    );
  }

  String get summary => 'ChatLoom $version ($build) · $platform';

  String report(String description) {
    final text = description.trim();
    if (text.isEmpty) {
      throw const FormatException('Describe the problem first.');
    }
    return '''ChatLoom feedback

$text

App: $version ($build)
Platform: $platform $systemVersion
Display: $width × $height logical pixels; ${dark ? 'dark' : 'light'}
Text scale: ${textScale.toStringAsFixed(2)}
Reduce Motion: ${reducedMotion ? 'on' : 'off'}

Attach a screenshot or screen recording if helpful. Check it for private content before sharing.
''';
  }
}
