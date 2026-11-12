// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/ios_local_notifications.dart';
import 'package:chatloom/personal/ui/notion_settings_body.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/widgets/settings_switch_list_tile.dart';
import 'package:material_ui/material_ui.dart';

/// Honest iOS capability and permission controls; never starts a network test.
class IosNotificationsPage extends StatefulWidget {
  const IosNotificationsPage({super.key});
  @override
  State<IosNotificationsPage> createState() => _IosNotificationsPageState();
}

class _IosNotificationsPageState extends State<IosNotificationsPage>
    with WidgetsBindingObserver {
  IosNotificationPermission _permission = IosNotificationPermission.unknown;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final permission = await IosLocalNotifications.instance.permission();
    if (mounted) {
      setState(() => _permission = permission);
    }
  }

  Future<void> _run(Future<bool> Function() action, {bool test = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final success = await action();
      await _refresh();
      if (!mounted) return;
      if (test || !success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Local test requested. Check Notification Center; background push is not tested.'
                  : 'Notifications are not available. Check permission in iPhone Settings.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access notification settings. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => NotionSettingsScaffold(
    title: 'Notifications',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NotionSectionHeader(title: 'On this iPhone'),
        NotionListRow(
          leading: const Icon(Icons.notifications_outlined),
          title: 'Notification permission',
          subtitle: switch (_permission) {
            IosNotificationPermission.allowed => 'Allowed by iOS',
            IosNotificationPermission.denied =>
              'Not allowed. Enable alerts in iPhone Settings.',
            IosNotificationPermission.unknown =>
              'Checking permission, or iOS settings are unavailable.',
          },
        ),
        NotionButton.ghost(
          label: 'Enable notifications',
          busy: _busy,
          onPressed: _busy
              ? null
              : () => _run(IosLocalNotifications.instance.requestPermission),
        ),
        NotionListRow(
          leading: const Icon(Icons.settings_outlined),
          title: 'Open iPhone Settings',
          subtitle: 'Change alerts, sounds and lock-screen previews',
          onTap: _busy
              ? null
              : () => _run(IosLocalNotifications.instance.openSettings),
        ),
        NotionListRow(
          key: const ValueKey('ios-notification-local-test'),
          leading: const Icon(Icons.notifications_active_outlined),
          title: 'Show local test',
          subtitle: 'A generic alert on this phone. No chat message is sent.',
          onTap: _busy || _permission != IosNotificationPermission.allowed
              ? null
              : () => _run(IosLocalNotifications.instance.showTest, test: true),
        ),
        SettingsSwitchListTile.adaptive(
          title: 'Show sender and message preview',
          subtitle:
              'Hidden while app lock is configured. iOS also controls lock-screen previews.',
          setting: AppSettings.personalNotificationPreviews,
        ),
        const NotionSectionHeader(title: 'Delivery in this beta'),
        const NotionListRow(
          leading: Icon(Icons.info_outline),
          title: 'While ChatLoom is open',
          subtitle:
              'New messages in other chats can show local alerts while this app is running and syncing.',
        ),
        const NotionListRow(
          leading: Icon(Icons.cloud_off_outlined),
          title: 'Background push is not connected',
          subtitle:
              'Messages will not reliably alert you while ChatLoom is suspended or closed. A local test cannot enable or verify background delivery.',
        ),
      ],
    ),
  );
}
