// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/diagnostics.dart';
import 'package:chatloom/personal/inbox_projection.dart';
import 'package:chatloom/personal/ios_local_notifications.dart';
import 'package:chatloom/personal/message_notification.dart';
import 'package:chatloom/personal/message_preview.dart';
import 'package:chatloom/personal/notification_eligibility.dart';
import 'package:chatloom/personal/notification_presentation_guard.dart';
import 'package:chatloom/personal/notification_threads.dart';
import 'package:chatloom/personal/own_sender.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/reminder_notification.dart';
import 'package:chatloom/personal/round_video/telegram_media_protocol.dart';
import 'package:chatloom/utils/notification_client_routing.dart';
import 'package:chatloom/utils/platform_infos.dart';
import 'package:chatloom/utils/push_helper.dart';
import 'package:chatloom/widgets/chatloom_app.dart';
import 'package:chatloom/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.mp3'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    if (!PlatformInfos.supportsSystemNotifications) return;
    final client = event.room.client;
    final guard = NotificationPresentationGuard(
      event,
      ownerCurrent: () => mounted && widget.clients.contains(client),
    );
    if (!guard.current) return;
    if (PlatformInfos.isIOS) {
      if (!AppSettings.personalIosMessageAlerts.value) return;
      await IosLocalNotifications.instance.initialize();
      if (!guard.current) return;
    }
    if (isTelegramMediaControl(event.type)) return;
    if (PersonalPrivacy.isJournal(event.room)) {
      // Same presenter, claim and trust checks as the background paths.
      if (!kIsWeb) {
        await presentDueReminder(
          event,
          plugin: FlutterLocalNotificationsPlugin(),
        );
      }
      return;
    }
    if (event.senderId == client.userID ||
        OwnSenderResolver.of(client).isStronglyOwnEvent(event)) {
      return;
    }
    final personal = PersonalClient.of(client);
    try {
      // Eligibility needs local private metadata only, never the journal.
      await personal.loadLocal();
      if (!guard.current) return;
    } catch (_) {
      if (!kIsWeb) return;
    }
    if (!kIsWeb &&
        personal.syncFailure == PrivateSyncFailure.storageUnavailable) {
      return;
    }
    final projection = InboxProjection(personal);
    if (!await personalNotificationEligible(
      event,
      projection.metadataFor(event.room),
      notificationMode: projection.notificationModeFor(event.room),
      placement: projection.placementFor(event.room),
    )) {
      return;
    }

    if (!guard.current) return;
    final roomId = event.room.id;
    if (notificationConversationVisible(
      location: ChatLoomApp.router.routeInformationProvider.value.uri,
      sameAccount: identical(this.client, client),
      roomId: roomId,
      groupId: projection.groupFor(event.room)?.id,
    )) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    // The app lock hides names and previews even when previews are on.
    final locked = await personalAppLockConfigured();
    if (!guard.current) return;
    final previews = !locked && AppSettings.personalNotificationPreviews.value;
    final available = previews && notificationContentAvailable(event);
    final text = messageNotificationText(
      previews: previews,
      chatName: projection.displayName(event.room),
      senderName: event.senderFromMemoryOrFallback.calcDisplayname(),
      preview: available ? personalPreviewLabel(event) : null,
      group: !event.room.isDirectChat,
      locked: locked,
    );
    final title = text.title;
    final body = text.body;
    if (!guard.current) return;
    if (kIsWeb) {
      if (AppSettings.webNotificationSound.value) _audioPlayer.play();

      html.Notification(title, body: body, tag: event.room.id);
      return;
    }

    if (PlatformInfos.isIOS) {
      final surface = PersonalPrivacy.surfaceGeneration;
      final thread = notificationThreadOf(
        client.clientName,
        event.room,
        projection,
      );
      await IosLocalNotifications.instance.showMessage(
        id: thread.id,
        threadIdentifier: thread.threadIdentifier,
        eventIdentity: '${client.clientName}/$roomId/${event.eventId}',
        timestamp: event.originServerTs,
        title: title,
        body: body,
        payload: ChatLoomPushPayload(
          client.clientName,
          roomId,
          event.eventId,
        ).toString(),
        canPresent: () =>
            guard.current &&
            surface == PersonalPrivacy.surfaceGeneration &&
            AppSettings.personalIosMessageAlerts.value,
        playSound: AppSettings.personalIosNotificationSound.value,
      );
      return;
    }

    await FlutterLocalNotificationsPlugin().show(
      id: messageNotificationId(client.clientName, event.room.id),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        iOS: DarwinNotificationDetails(
          threadIdentifier: '${client.clientName}_${event.room.id}',
        ),
        macOS: DarwinNotificationDetails(
          threadIdentifier: '${client.clientName}_${event.room.id}',
        ),
      ),
      payload: ChatLoomPushPayload(
        client.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
  }
}
