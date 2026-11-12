// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/inbox_projection.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/personal/ui/chat_preferences_page.dart'
    show canEditChatPreferences;
import 'package:matrix/matrix.dart';
import 'package:personal_core/personal_core.dart';
import 'package:uuid/uuid.dart';

/// Personal views only: no native space, invite, room state or message writes.
/// Reuses the encrypted replica's existing label:/labels: entities.
class ChatLabels {
  const ChatLabels(this.personal);
  final PersonalClient personal;

  List<PersonalLabel> get all => read(personal.values);
  static List<PersonalLabel> read(Map<String, Map<String, dynamic>> values) {
    final result = <PersonalLabel>[];
    for (final entry in values.entries) {
      final name = entry.value['name'];
      if (!entry.key.startsWith('label:') ||
          entry.value['deleted'] == true ||
          name is! String ||
          name.trim().isEmpty) {
        continue;
      }
      result.add(
        PersonalLabel(
          id: entry.key,
          name: name.trim(),
          icon: entry.value['icon'] is String
              ? entry.value['icon'] as String
              : null,
          color: entry.value['color'] is int
              ? entry.value['color'] as int
              : null,
          showInInbox: entry.value['showInInbox'] != false,
        ),
      );
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Set<String> selected(Room room) => InboxProjection(
    personal,
  ).recordFor(room).labelKeys.intersection(all.map((l) => l.id).toSet());
  bool editable(String key) =>
      PersonalPrivacy.surfaceUnlocked &&
      PersonalPrivacy.surfaceForeground &&
      canEditChatPreferences(personal, key);
  void _require(String key) {
    if (!editable(key)) {
      throw StateError('Labels cannot be changed in this session.');
    }
  }

  String _name(String name, {String? except}) {
    final value = name.trim();
    if (value.isEmpty || value.runes.length > 64) {
      throw const FormatException('Use a name with 1–64 characters.');
    }
    if (all.any(
      (l) => l.id != except && l.name.toLowerCase() == value.toLowerCase(),
    )) {
      throw const FormatException('A label with this name already exists.');
    }
    return value;
  }

  Future<String> create(String name, {String? icon, int? color}) async {
    final normalized = _name(name);
    final id = 'label:${const Uuid().v4()}';
    _require(id);
    await personal.put(
      id,
      PersonalLabel(
        id: id,
        name: normalized,
        icon: icon,
        color: color == null ? null : color | 0xff000000,
      ).toJson().cast<String, dynamic>(),
    );
    return id;
  }

  Future<void> rename(String id, String name) async {
    final normalized = _name(name, except: id);
    _require(id);
    if (!all.any((l) => l.id == id)) {
      throw StateError('Label no longer exists.');
    }
    await personal.put(id, {...?personal.values[id], 'name': normalized});
  }

  Future<void> update(
    String id,
    String name, {
    required String icon,
    required int color,
  }) async {
    final normalized = _name(name, except: id);
    _require(id);
    if (!all.any((l) => l.id == id)) {
      throw StateError('Label no longer exists.');
    }
    await personal.put(id, {
      ...?personal.values[id],
      'name': normalized,
      'icon': icon,
      'color': color | 0xff000000,
    });
  }

  Future<void> remove(String id) async {
    _require(id);
    // One tombstone hides the definition everywhere. References are harmless;
    // no fanout rewrite can overwrite concurrent chat preference changes.
    await personal.put(id, {...?personal.values[id], 'deleted': true});
  }

  Future<void> assign(
    Room room, {
    required String entity,
    required Set<String> added,
    required Set<String> removed,
  }) async {
    final key = 'labels:$entity';
    _require(key);
    if (!identical(room.client, personal.client) ||
        InboxProjection(personal).entityFor(room) != entity) {
      throw StateError('This chat changed. Reopen labels.');
    }
    final valid = all.map((l) => l.id).toSet();
    final next = (selected(room)..addAll(added.intersection(valid)))
      ..removeAll(removed);
    await personal.put(key, {
      ...?personal.values[key],
      'labels': next.toList()..sort(),
    });
  }
}
