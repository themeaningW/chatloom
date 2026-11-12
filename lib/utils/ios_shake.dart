// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// UIKit shake events, not an accelerometer stream. Older native runners keep
/// manual feedback available without a missing-plugin error on hot reload.
abstract final class IosShake {
  static const availability = MethodChannel('chatloom/ios_shake/availability');
  static const _events = EventChannel('chatloom/ios_shake');

  static Future<bool> available() async {
    try {
      return await availability
              .invokeMethod<bool>('isAvailable')
              .timeout(const Duration(seconds: 2)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Stream<void> get events {
    // A late event after cancellation must be dropped, not replayed at the next
    // foreground subscription (Flutter buffers channels with no listener).
    ServicesBinding.instance.channelBuffers
      ..allowOverflow(_events.name, true)
      ..resize(_events.name, 0);
    final subscription = const Uuid().v4();
    return _events
        .receiveBroadcastStream(subscription)
        .where(
          (event) =>
              event is Map &&
              event['type'] == 'shake' &&
              event['subscription'] == subscription,
        )
        .map<void>((_) {});
  }
}
