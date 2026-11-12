// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum IosNotificationPermission { unknown, allowed, denied }

/// Local presentation only. This does not register with APNs, wake a suspended
/// app, or claim remote push delivery. Permission is requested by a settings tap.
class IosLocalNotifications {
  static final instance = IosLocalNotifications();
  static const testNotificationId = 0x434c4d;
  final FlutterLocalNotificationsPlugin _plugin;
  IosLocalNotifications({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void>? _initializing;
  Future<bool>? _requesting;
  void Function(NotificationResponse)? _onResponse;
  final _pendingResponses = <NotificationResponse>[];
  final _handled = <String>{};

  /// Repeated account setup shares initialization and uses the latest owner.
  /// Launch inspection is separate from permissions, so denied permission does
  /// not discard a previously delivered notification's routing information.
  Future<void> initialize({void Function(NotificationResponse)? onResponse}) {
    if (onResponse != null) {
      _onResponse = onResponse;
      final pending = List<NotificationResponse>.of(_pendingResponses);
      _pendingResponses.clear();
      for (final response in pending) {
        handleResponse(response);
      }
    }
    return _initializing ??= _initialize().catchError((Object error) {
      _initializing = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: handleResponse,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response != null) {
      handleResponse(response);
    }
  }

  @visibleForTesting
  void handleResponse(NotificationResponse response) {
    // The generic local test has no conversation to open.
    if (response.payload?.isNotEmpty != true) return;
    if (_onResponse == null) {
      if (_pendingResponses.length < 16) _pendingResponses.add(response);
      return;
    }
    final key = '${response.id}/${response.actionId}/${response.payload}';
    if (!_handled.add(key)) return;
    // Bounded process-local deduplication; no content or identifiers are logged.
    if (_handled.length > 128) _handled.remove(_handled.first);
    _onResponse!(response);
  }

  Future<IosNotificationPermission> permission() async {
    try {
      await initialize();
      final state = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (state == null) return IosNotificationPermission.unknown;
      return state.isEnabled || state.isProvisionalEnabled
          ? IosNotificationPermission.allowed
          : IosNotificationPermission.denied;
    } catch (_) {
      return IosNotificationPermission.unknown;
    }
  }

  Future<bool> requestPermission() =>
      _requesting ??= _request().whenComplete(() {
        _requesting = null;
      });

  Future<bool> _request() async {
    await initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true, badge: true) ??
        false;
  }

  Future<bool> openSettings() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.openAppNotificationSettings() ??
      false;

  /// Contains no account, chat, sender or message data. Never sends a message.
  Future<bool> showTest() async {
    if (await permission() != IosNotificationPermission.allowed) return false;
    await _plugin.show(
      id: testNotificationId,
      title: 'ChatLoom',
      body:
          'Local notifications are working. Background push is not enabled in this beta.',
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
    );
    return true;
  }
}
