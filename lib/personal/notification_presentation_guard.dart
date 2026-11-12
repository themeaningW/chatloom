// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/deleted_messages.dart';
import 'package:chatloom/personal/hidden_messages.dart';
import 'package:matrix/matrix.dart';

/// A merged conversation shows every source, while an explicitly opened source
/// only shows that room. Read loaded route/identity data; never mark anything read.
bool notificationConversationVisible({
  required Uri location,
  required bool sameAccount,
  required String roomId,
  String? groupId,
}) {
  if (!sameAccount) return false;
  final parts = location.pathSegments;
  if (parts.length < 2 || parts.first != 'rooms') return false;
  if (parts[1] != 'person') return parts[1] == roomId;
  if (parts.length < 3 || groupId == null || parts[2] != groupId) return false;
  return parts.length == 3 || parts[3] == roomId;
}

/// An in-flight alert belongs to exactly the session that produced it. Stream
/// cancellation on logout does not cancel asynchronous work already in flight.
/// Check this after asynchronous reads and immediately before OS presentation.
class NotificationPresentationGuard {
  final Event event;
  final bool Function()? ownerCurrent;
  final String? _user;
  final String? _device;
  final String? _token;
  final Uri? _server;
  NotificationPresentationGuard(this.event, {this.ownerCurrent})
    : _user = event.room.client.userID,
      _device = event.room.client.deviceID,
      _token = event.room.client.accessToken,
      _server = event.room.client.baseUri;

  bool get current {
    final client = event.room.client;
    return _user != null &&
        client.isLogged() &&
        client.userID == _user &&
        client.deviceID == _device &&
        client.accessToken == _token &&
        client.baseUri == _server &&
        (ownerCurrent?.call() ?? true) &&
        !isDeletedForDisplay(event) &&
        !HiddenMessages.hides(event);
  }

  @override
  String toString() => 'NotificationPresentationGuard(private)';
}
