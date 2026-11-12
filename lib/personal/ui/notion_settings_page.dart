// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';

final notionSettingsRevision = ValueNotifier<int>(0);

/// One navigation catalogue for both the mobile index and desktop sidebar.
///
/// Order is the order on screen: the account row, the everyday settings,
/// the ChatLoom tools, then Advanced (private sync, app information and
/// developer options) last.
enum NotionSettingsCategory {
  account('Account', Icons.person_outline, 'account', 'Profile and sign out'),
  appearance(
    'Appearance',
    Icons.palette_outlined,
    'style',
    'Theme, colours and wallpaper',
  ),
  notifications(
    'Notifications',
    Icons.notifications_none_outlined,
    'notifications',
    'Previews, sound and troubleshooting',
  ),
  security(
    'Privacy & security',
    Icons.shield_outlined,
    'security',
    'Incognito, app lock, devices and recovery',
  ),
  chats(
    'Chats',
    Icons.forum_outlined,
    'chat',
    'Gestures, messages, voice and merged chats',
  ),
  networks(
    'Networks',
    Icons.hub_outlined,
    'networks',
    'Connection status, groups and notifications',
  ),
  transcription(
    'Transcription',
    Icons.subtitles_outlined,
    'transcriptions',
    'Automatic transcripts, language and limits',
  ),
  reminders(
    'Reminders',
    Icons.alarm_outlined,
    'reminders',
    'Bring chats back at the right time',
  ),
  scheduled(
    'Scheduled messages',
    Icons.schedule_outlined,
    'scheduled',
    'Messages waiting to be sent',
  ),
  bookmarks(
    'Bookmarks',
    Icons.bookmarks_outlined,
    'bookmarks',
    'Find your saved messages',
  ),
  advanced(
    'Advanced',
    Icons.tune,
    'advanced',
    'Private sync, app information and developer options',
  );

  final String title, path, summary;
  final IconData icon;
  const NotionSettingsCategory(this.title, this.icon, this.path, this.summary);
  String get route => '/rooms/settings/$path';
  bool get isTool => index >= reminders.index && index <= bookmarks.index;

  static NotionSettingsCategory forPath(String path) {
    final parts = Uri.parse(path).path.split('/').skip(3).toList();
    final leaf = parts.firstOrNull;
    return switch (leaf) {
      'devices' || 'recovery' => security,
      'people' => chats,
      'sync' || 'developer' => advanced,
      'push' => notifications,
      _ =>
        values.where((category) => category.path == leaf).firstOrNull ??
            account,
    };
  }
}

class NotionSettingsData {
  final String name;
  final Widget avatar;
  final String selectedPath;
  final Map<NotionSettingsCategory, String> summaries;
  final String? status;
  final bool notificationsAvailable;
  const NotionSettingsData({
    required this.name,
    required this.avatar,
    this.selectedPath = '/rooms/settings',
    this.summaries = const {},
    this.status,
    this.notificationsAvailable = true,
  });
}

class NotionSettingsActions {
  final VoidCallback? back;
  final ValueChanged<String>? open;
  const NotionSettingsActions({this.back, this.open});
}

class NotionSettingsPage extends StatelessWidget {
  final NotionSettingsData data;
  final NotionSettingsActions actions;
  const NotionSettingsPage({
    super.key,
    required this.data,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) {
    final tokens = context.notion;
    final wide = MediaQuery.sizeOf(context).width > NotionSize.contentMaxWidth;
    final selected = NotionSettingsCategory.forPath(data.selectedPath);
    Widget row(NotionSettingsCategory category) {
      final account = category == NotionSettingsCategory.account;
      return Semantics(
        selected: wide && category == selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NotionSpace.md,
            vertical: NotionSpace.xxs,
          ),
          child: NotionListRow(
            leadingWidth: account ? NotionSize.touchTarget : NotionSize.iconLg,
            leading: account
                ? SizedBox.square(
                    dimension: NotionSize.touchTarget,
                    child: ClipRRect(
                      borderRadius: NotionRadius.avatarAll,
                      child: data.avatar,
                    ),
                  )
                : Icon(category.icon, color: tokens.colors.accent),
            title: account ? data.name : category.title,
            subtitle: account && data.status != null
                ? data.status
                : data.summaries[category] ?? category.summary,
            trailing: Icon(
              Icons.chevron_right,
              size: NotionSize.icon,
              color: tokens.colors.textTertiary,
            ),
            onTap: actions.open == null
                ? null
                : () => actions.open!(category.route),
          ),
        ),
      );
    }

    Widget group(Iterable<NotionSettingsCategory> categories) {
      final entries = categories.toList();
      return DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface,
          borderRadius: NotionRadius.mdAll,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: NotionSize.touchTarget + NotionSpace.lg,
                    end: NotionSpace.md,
                  ),
                  child: Divider(height: NotionSize.border),
                ),
              row(entries[i]),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: NotionIconButton(
          icon: Icons.chevron_left,
          label: 'Back to chats',
          onPressed: actions.back,
        ),
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: NotionSize.contentMaxWidth,
          ),
          child: ListView(
            key: const PageStorageKey('notion-settings'),
            padding: const EdgeInsets.fromLTRB(
              NotionSpace.md,
              NotionSpace.md,
              NotionSpace.md,
              NotionSpace.xxl,
            ),
            children: [
              group([NotionSettingsCategory.account]),
              const SizedBox(height: NotionSpace.xl),
              group(
                NotionSettingsCategory.values.where(
                  (c) =>
                      c.index > 0 &&
                      c.index < NotionSettingsCategory.reminders.index &&
                      (data.notificationsAvailable ||
                          c != NotionSettingsCategory.notifications),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  NotionSpace.md,
                  NotionSpace.xl,
                  NotionSpace.md,
                  NotionSpace.xs,
                ),
                child: NotionSettingsGroupLabel('Tools'),
              ),
              group(NotionSettingsCategory.values.where((c) => c.isTool)),
              const SizedBox(height: NotionSpace.xl),
              group([NotionSettingsCategory.advanced]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muted group label on the settings index ("Tools").
class NotionSettingsGroupLabel extends StatelessWidget {
  final String text;
  const NotionSettingsGroupLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: context.notion.typography.sectionLabel),
  );
}
