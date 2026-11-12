// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/personal/chat_labels.dart';
import 'package:chatloom/personal/inbox_projection.dart';
import 'package:chatloom/personal/personal_client.dart';
import 'package:chatloom/personal/privacy.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:personal_core/personal_core.dart';

const chatLabelIcons = <String, IconData>{
  'label': Icons.label_outline,
  'school': Icons.school_outlined,
  'work': Icons.work_outline,
  'home': Icons.home_outlined,
  'people': Icons.people_outline,
  'favorite': Icons.favorite_outline,
  'star': Icons.star_outline,
  'book': Icons.menu_book_outlined,
  'code': Icons.code,
  'travel': Icons.flight_outlined,
  'sport': Icons.sports_soccer_outlined,
  'music': Icons.music_note_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'coffee': Icons.coffee_outlined,
  'health': Icons.health_and_safety_outlined,
  'pets': Icons.pets_outlined,
  'science': Icons.science_outlined,
  'math': Icons.calculate_outlined,
  'finance': Icons.account_balance_outlined,
  'calendar': Icons.calendar_today_outlined,
  'library': Icons.library_books_outlined,
  'writing': Icons.edit_note_outlined,
  'assignment': Icons.assignment_outlined,
  'tasks': Icons.task_alt,
  'computer': Icons.computer_outlined,
  'phone': Icons.smartphone_outlined,
  'mail': Icons.mail_outline,
  'chat': Icons.forum_outlined,
  'business': Icons.business_outlined,
  'team': Icons.groups_outlined,
  'tools': Icons.construction_outlined,
  'design': Icons.design_services_outlined,
  'art': Icons.palette_outlined,
  'camera': Icons.camera_alt_outlined,
  'photo': Icons.photo_outlined,
  'video': Icons.videocam_outlined,
  'movies': Icons.movie_outlined,
  'games': Icons.sports_esports_outlined,
  'fitness': Icons.fitness_center_outlined,
  'swimming': Icons.pool_outlined,
  'hiking': Icons.hiking_outlined,
  'cycling': Icons.directions_bike_outlined,
  'car': Icons.directions_car_outlined,
  'bus': Icons.directions_bus_outlined,
  'train': Icons.train_outlined,
  'world': Icons.public_outlined,
  'map': Icons.map_outlined,
  'beach': Icons.beach_access_outlined,
  'food': Icons.restaurant_outlined,
  'pizza': Icons.local_pizza_outlined,
  'cake': Icons.cake_outlined,
  'gift': Icons.card_giftcard_outlined,
  'celebration': Icons.celebration_outlined,
  'nature': Icons.park_outlined,
  'flowers': Icons.local_florist_outlined,
  'sun': Icons.wb_sunny_outlined,
  'moon': Icons.nightlight_outlined,
  'weather': Icons.cloud_outlined,
  'water': Icons.water_drop_outlined,
  'fire': Icons.local_fire_department_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'lightbulb': Icons.lightbulb_outline,
  'bolt': Icons.bolt_outlined,
  'target': Icons.flag_outlined,
  'trophy': Icons.emoji_events_outlined,
  'diamond': Icons.diamond_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'receipt': Icons.receipt_long_outlined,
  'cart': Icons.shopping_cart_outlined,
  'security': Icons.shield_outlined,
  'key': Icons.key_outlined,
  'lock': Icons.lock_outline,
  'bookmark': Icons.bookmark_outline,
  'folder': Icons.folder_outlined,
  'link': Icons.link_outlined,
  'attachment': Icons.attach_file_outlined,
  'microphone': Icons.mic_none_outlined,
  'headphones': Icons.headphones_outlined,
  'language': Icons.translate_outlined,
  'meditation': Icons.self_improvement_outlined,
};
const _quickLabelIconCount = 16;
IconData chatLabelIcon(String? name) =>
    chatLabelIcons[name] ?? Icons.label_outline;
Color chatLabelColor(BuildContext context, PersonalLabel label) =>
    label.color == null ? context.notion.colors.accent : Color(label.color!);

class ChatLabelGlyph extends StatelessWidget {
  const ChatLabelGlyph(this.label, {super.key});
  final PersonalLabel label;
  @override
  Widget build(BuildContext context) => Icon(
    chatLabelIcon(label.icon),
    size: NotionSize.icon,
    color: NotionContrast.readable(
      context.notion.colors.surface,
      chatLabelColor(context, label),
    ),
  );
}

Future<String?> showChatLabels(BuildContext context, PersonalClient personal) =>
    showNotionSheet<String>(
      context: context,
      title: 'Labels',
      builder: (_) => _LabelList(personal: personal),
    );
Future<void> showChatLabelPicker(
  BuildContext context,
  PersonalClient personal,
  Room room,
) => showNotionSheet<void>(
  context: context,
  title: 'Labels',
  builder: (_) => _LabelList(personal: personal, room: room),
);

class _LabelList extends StatefulWidget {
  const _LabelList({required this.personal, this.room});
  final PersonalClient personal;
  final Room? room;
  @override
  State<_LabelList> createState() => _LabelListState();
}

class _LabelListState extends State<_LabelList> {
  late final _owner = widget.personal;
  late final (String?, String?) _account;
  late final int _surface;
  late final String? _entity;
  late final Set<String> _initial;
  late final Set<String> _selected;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _account = (_owner.client.userID, _owner.client.accessToken);
    _surface = PersonalPrivacy.surfaceGeneration;
    _entity = widget.room == null
        ? null
        : InboxProjection(_owner).entityFor(widget.room!);
    _initial = widget.room == null
        ? <String>{}
        : ChatLabels(_owner).selected(widget.room!);
    _selected = {..._initial};
  }

  bool get _current =>
      mounted &&
      PersonalPrivacy.surfaceUnlocked &&
      PersonalPrivacy.surfaceForeground &&
      _surface == PersonalPrivacy.surfaceGeneration &&
      _account == (_owner.client.userID, _owner.client.accessToken);
  Future<void> _edit([PersonalLabel? label]) async {
    if (!_current) return;
    final created = await showNotionSheet<String>(
      context: context,
      title: label == null ? 'New label' : 'Edit label',
      builder: (_) => ChatLabelEditor(personal: _owner, label: label),
    );
    if (_current && widget.room != null && label == null && created != null) {
      setState(() => _selected.add(created));
    }
  }

  Future<void> _save() async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ChatLabels(_owner).assign(
        widget.room!,
        entity: _entity!,
        added: _selected.difference(_initial),
        removed: _initial.difference(_selected),
      );
      if (mounted && _current) Navigator.of(context).pop();
    } catch (_) {
      if (_current) {
        setState(
          () => _error =
              'Couldn’t save labels. Check private sync and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _owner,
    builder: (context, _) {
      final labels = ChatLabels(_owner).all;
      final editable =
          _current &&
          !_busy &&
          ChatLabels(
            _owner,
          ).editable(_entity == null ? 'label:new' : 'labels:$_entity');
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_owner.ready)
                const NotionListRow(
                  leading: Icon(Icons.lock_outline),
                  title: 'Connect private sync to edit labels',
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(NotionSpace.inset),
                  child: Text(
                    _error!,
                    style: context.notion.typography.calloutMuted,
                  ),
                ),
              for (final label in labels)
                NotionListRow(
                  key: ValueKey('label-row:${label.id}'),
                  leading: ChatLabelGlyph(label),
                  title: label.name,
                  trailing: widget.room == null
                      ? NotionIconButton(
                          icon: Icons.edit_outlined,
                          label: 'Edit ${label.name}',
                          onPressed: editable ? () => _edit(label) : null,
                        )
                      : Checkbox(
                          value: _selected.contains(label.id),
                          onChanged: editable
                              ? (checked) => setState(() {
                                  checked == true
                                      ? _selected.add(label.id)
                                      : _selected.remove(label.id);
                                })
                              : null,
                        ),
                  onTap: widget.room == null
                      ? () {
                          if (_current) Navigator.of(context).pop(label.id);
                        }
                      : editable
                      ? () => setState(() {
                          _selected.contains(label.id)
                              ? _selected.remove(label.id)
                              : _selected.add(label.id);
                        })
                      : null,
                ),
              NotionListRow(
                leading: const Icon(Icons.add),
                title: 'New label',
                onTap: editable ? _edit : null,
              ),
              if (widget.room != null)
                Padding(
                  padding: const EdgeInsets.all(NotionSpace.inset),
                  child: NotionButton.primary(
                    label: 'Save',
                    busy: _busy,
                    expand: true,
                    onPressed: editable ? _save : null,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Uses the existing PersonalLabel fields; no parallel folder representation.
class ChatLabelEditor extends StatefulWidget {
  const ChatLabelEditor({super.key, required this.personal, this.label});
  final PersonalClient personal;
  final PersonalLabel? label;
  @override
  State<ChatLabelEditor> createState() => _ChatLabelEditorState();
}

class _ChatLabelEditorState extends State<ChatLabelEditor> {
  bool _moreIcons = false;
  late final _name = TextEditingController(text: widget.label?.name ?? '');
  late String _icon = widget.label?.icon ?? 'label';
  HSVColor? _color;
  bool _customColor = false;
  bool _busy = false;
  String? _error;
  late final (String?, String?) _account;
  late final int _surface;
  @override
  void initState() {
    super.initState();
    _account = (
      widget.personal.client.userID,
      widget.personal.client.accessToken,
    );
    _surface = PersonalPrivacy.surfaceGeneration;
  }

  bool get _current =>
      mounted &&
      _account ==
          (widget.personal.client.userID, widget.personal.client.accessToken) &&
      _surface == PersonalPrivacy.surfaceGeneration &&
      PersonalPrivacy.surfaceUnlocked &&
      PersonalPrivacy.surfaceForeground;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _color ??= HSVColor.fromColor(
      widget.label?.color == null
          ? context.notion.colors.accent
          : Color(widget.label!.color!),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final labels = ChatLabels(widget.personal);
      final existing = widget.label;
      final String id;
      if (existing == null) {
        id = await labels.create(
          _name.text,
          icon: _icon,
          color: _color!.toColor().toARGB32(),
        );
      } else {
        id = existing.id;
        await labels.update(
          id,
          _name.text,
          icon: _icon,
          color: _color!.toColor().toARGB32(),
        );
      }
      if (mounted && _current) Navigator.of(context).pop(id);
    } catch (e) {
      if (_current) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Couldn’t save. Check private sync and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!_current || _busy || widget.label == null) return;
    final confirmed = await showNotionConfirmDialog(
      context: context,
      title: 'Delete label?',
      message: 'Your chats and messages will stay.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !_current) return;
    setState(() => _busy = true);
    try {
      await ChatLabels(widget.personal).remove(widget.label!.id);
      if (mounted && _current) Navigator.of(context).pop();
    } catch (_) {
      if (_current) {
        setState(() => _error = 'Couldn’t delete this label. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color!.toColor();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(NotionSpace.inset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(NotionSpace.md),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: NotionRadius.pillAll,
                    ),
                    child: Icon(
                      chatLabelIcon(_icon),
                      color: NotionContrast.on(color),
                      size: NotionSize.iconLg,
                    ),
                  ),
                ),
                const SizedBox(height: NotionSpace.md),
                NotionTextField(
                  key: const ValueKey('label-name'),
                  controller: _name,
                  maxLength: 64,
                  enabled: !_busy,
                  label: 'Name',
                  error: _error,
                ),
                const NotionSectionHeader(title: 'Icon'),
                Wrap(
                  spacing: NotionSpace.xxs,
                  runSpacing: NotionSpace.xxs,
                  children: [
                    for (final entry in chatLabelIcons.entries.where(
                      (entry) =>
                          _moreIcons ||
                          chatLabelIcons.keys
                              .take(_quickLabelIconCount)
                              .contains(entry.key) ||
                          entry.key == _icon,
                    ))
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _icon == entry.key
                              ? context.notion.colors.selected
                              : context.notion.colors.background,
                          borderRadius: NotionRadius.pillAll,
                        ),
                        child: Semantics(
                          selected: _icon == entry.key,
                          child: NotionIconButton(
                            icon: entry.value,
                            label: 'Icon ${entry.key}',
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _icon = entry.key;
                                    _moreIcons = false;
                                  }),
                          ),
                        ),
                      ),
                  ],
                ),
                NotionButton.ghost(
                  label: _moreIcons ? 'View less' : 'View more',
                  icon: _moreIcons ? Icons.expand_less : Icons.expand_more,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _moreIcons = !_moreIcons),
                ),
                const NotionSectionHeader(title: 'Color'),
                Wrap(
                  spacing: NotionSpace.xxs,
                  children: [
                    for (final hue in const [
                      0.0,
                      30.0,
                      60.0,
                      120.0,
                      180.0,
                      210.0,
                      260.0,
                      300.0,
                    ])
                      IconButton(
                        key: ValueKey('label-color:$hue'),
                        tooltip: 'Color ${hue.round()}',
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () =>
                                    _color = HSVColor.fromAHSV(1, hue, .7, .85),
                              ),
                        icon: Icon(
                          Icons.circle,
                          color: HSVColor.fromAHSV(1, hue, .7, .85).toColor(),
                          size: NotionSize.iconLg,
                        ),
                      ),
                  ],
                ),
                NotionListRow(
                  title: 'Custom color',
                  trailing: Icon(
                    _customColor ? Icons.expand_less : Icons.expand_more,
                  ),
                  onTap: _busy
                      ? null
                      : () => setState(() => _customColor = !_customColor),
                ),
                if (_customColor) ...[
                  const Text('Hue'),
                  Slider(
                    value: _color!.hue,
                    max: 360,
                    semanticFormatterCallback: (v) => 'Hue ${v.round()}',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _color = _color!.withHue(v)),
                  ),
                  const Text('Saturation'),
                  Slider(
                    value: _color!.saturation,
                    semanticFormatterCallback: (v) =>
                        'Saturation ${(v * 100).round()}%',
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => _color = _color!.withSaturation(v),
                          ),
                  ),
                  const Text('Brightness'),
                  Slider(
                    value: _color!.value,
                    semanticFormatterCallback: (v) =>
                        'Brightness ${(v * 100).round()}%',
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _color = _color!.withValue(v)),
                  ),
                ],
                NotionButton.primary(
                  label: 'Save',
                  busy: _busy,
                  onPressed: _busy ? null : _save,
                ),
                if (widget.label != null)
                  NotionButton.ghost(
                    label: 'Delete label',
                    onPressed: _busy ? null : _delete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
