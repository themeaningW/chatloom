// SPDX-License-Identifier: AGPL-3.0-or-later
// The real emoji catalogue behind every picker: search quality on the
// words people type, the shared recents (and their old preference) and
// remembered skin tones. Offline; no account.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/personal/emoji/emoji_picker.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as data;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _captureEmojiFont = false;

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['CHATLOOM_FREQUENT_EMOJI_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('frequent-emoji-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (Platform.environment['CHATLOOM_FREQUENT_EMOJI_CAPTURE_DIR'] != null) {
      final text = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        text.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
      }
      await text.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final path in [
        '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
        r'C:\Windows\Fonts\seguiemj.ttf',
      ]) {
        final font = File(path);
        if (!font.existsSync()) continue;
        final bytes = await font.readAsBytes();
        await (FontLoader(
          'ChatLoom capture emoji',
        )..addFont(Future.value(bytes.buffer.asByteData()))).load();
        _captureEmojiFont = true;
        break;
      }
    }
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });
  setUp(() async {
    await AppSettings.store.remove(EmojiRecents.key);
    await AppSettings.store.remove(EmojiSkinTones.key);
    await AppSettings.reactionsFrequentlyUsed.setItem(false);
    EmojiRecents.debugReset();
    EmojiSkinTones.debugReset();
  });

  List<String> top(String query, [int n = 3]) => [
    for (final e in EmojiCatalog.search.search(query).take(n)) e.emoji,
  ];

  test('the whole set, eight categories, tones where Unicode has them', () {
    final categories = EmojiCatalog.categories;
    expect(categories.map((c) => c.title), [
      'Smileys & people',
      'Animals & nature',
      'Food & drink',
      'Travel & places',
      'Activities',
      'Objects',
      'Symbols',
      'Flags',
    ]);
    final all = [for (final c in categories) ...c.emoji];
    expect(all.length, greaterThan(1500));
    expect(EmojiCatalog.lookup('👍')!.tones, isTrue);
    expect(EmojiCatalog.lookup('❤')!.tones, isFalse);
    // One search entry per emoji identity (spellings and tones fold).
    expect(EmojiCatalog.search.length, greaterThan(all.length - 30));
  });

  test('search finds what people type, best first', () {
    expect(top('heart').first, '❤️');
    expect(top('lol').first, '😂');
    expect(top('thumbs').first, '👍');
    expect(top('thumbs up').first, '👍');
    expect(top('fire').first, '🔥');
    expect(top('ok').first, '👌');
    expect(top('party').first, '🎉');
    expect(top('party', 2), contains('🥳'));
    expect(top('cry').toSet(), containsAll(['😭', '😢']));
    expect(top('sad', 5), contains('😭'));
    expect(top('<3').first, '❤️');
    expect(top('Thumbs UP').first, '👍');
    expect(top('café').first, '☕');
    expect(top(':joy:').first, '😂');
    expect(top('👍\u{FE0F}').first, '👍');
    expect(top('zzqx'), isEmpty);
    // Prefix: "pizz" → 🍕; substring still found at the end.
    expect(top('pizz').first, '🍕');
  });

  test('search is instant on the whole set', () {
    EmojiCatalog.search.search('warm-up');
    final watch = Stopwatch()..start();
    for (final q in ['h', 'he', 'hea', 'hear', 'heart', 'a b', 'smile']) {
      EmojiCatalog.search.search(q);
    }
    // Seven keystrokes well under one frame each, even in debug mode.
    expect(watch.elapsedMilliseconds, lessThan(7 * 16 * 4));
  });

  test('recents: newest first, counted, in the old preference format', () {
    // A list written by emoji_picker_flutter before wave 11 carries over.
    AppSettings.store.setString(
      EmojiRecents.key,
      jsonEncode([
        {
          'emoji': {'emoji': '🔥', 'name': 'fire', 'hasSkinTone': false},
          'counter': 4,
        },
      ]),
    );
    EmojiRecents.debugReset();
    expect(EmojiRecents.emoji, ['🔥']);
    EmojiRecents.add('😂');
    EmojiRecents.add('🔥');
    expect(EmojiRecents.emoji, ['🔥', '😂']);
    expect(EmojiRecents.usage, {'🔥': 5, '😂': 1});
    final stored = jsonDecode(AppSettings.store.getString(EmojiRecents.key)!);
    expect((stored as List).first['emoji']['emoji'], '🔥');
    for (var i = 0; i < 40; i++) {
      EmojiRecents.add(String.fromCharCode(0x1F400 + i));
    }
    expect(EmojiRecents.emoji, hasLength(EmojiRecents.limit));
    EmojiRecents.add('mxc://example.invalid/x');
    expect(EmojiRecents.emoji, isNot(contains('mxc://example.invalid/x')));
  });

  test('skin tones are remembered per emoji', () {
    EmojiSkinTones.remember('👍', '🏽');
    EmojiSkinTones.debugReset();
    expect(EmojiSkinTones.all, {NotionEmojiSearch.key('👍'): '🏽'});
    EmojiSkinTones.remember('👍🏽', null);
    expect(EmojiSkinTones.all, isEmpty);
  });

  test(
    'frequent ranks counts, then recency, folding presentation variants',
    () async {
      await AppSettings.store.setString(
        EmojiRecents.key,
        jsonEncode([
          for (final item in [
            ('😂', 2),
            ('👍\u{FE0F}', 2),
            ('🔥', 4),
            ('👍', 2),
            ('👍🏽', 1),
          ])
            {
              'emoji': {'emoji': item.$1},
              'counter': item.$2,
            },
        ]),
      );
      EmojiRecents.debugReset();
      expect(EmojiRecents.frequent, ['👍\u{FE0F}', '🔥', '😂', '👍🏽']);
      EmojiRecents.add('🔥');
      EmojiRecents.debugReset();
      expect(EmojiRecents.frequent, ['🔥', '👍\u{FE0F}', '😂', '👍🏽']);
    },
  );

  test(
    'reset clears usage only, preserving picker mode and skin tones',
    () async {
      expect(AppSettings.reactionsFrequentlyUsed.defaultValue, isFalse);
      await AppSettings.reactionsFrequentlyUsed.setItem(true);
      EmojiRecents.add('🔥');
      EmojiSkinTones.remember('👍', '🏽');
      await EmojiRecents.clear();
      EmojiRecents.debugReset();
      expect(EmojiRecents.emoji, isEmpty);
      expect(EmojiRecents.usage, isEmpty);
      expect(AppSettings.store.getString(EmojiRecents.key), isNull);
      expect(AppSettings.reactionsFrequentlyUsed.value, isTrue);
      expect(EmojiSkinTones.all, {NotionEmojiSearch.key('👍'): '🏽'});
    },
  );

  testWidgets('frequent reaction view has one section and full search', (
    tester,
  ) async {
    await AppSettings.reactionsFrequentlyUsed.setItem(true);
    EmojiRecents.add('🔥');
    EmojiRecents.add('🔥');
    EmojiRecents.add('😂');
    final picked = <String>[];
    final query = TextEditingController();
    addTearDown(query.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(
          body: ChatLoomEmojiPicker(
            reactions: const EmojiReactionChoices(quick: ['❤️']),
            recordUsage: false,
            controller: query,
            onSelected: picked.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<NotionEmojiPicker>(
      find.byType(NotionEmojiPicker),
    );
    expect(picker.sections.map((section) => section.title), [
      'Frequently used',
    ]);
    expect(picker.sections.single.emoji.map((emoji) => emoji.emoji), [
      '🔥',
      '😂',
    ]);
    expect(picker.categoryBar, isFalse);
    expect(find.text('Quick reactions'), findsNothing);
    expect(find.text('Recently used'), findsNothing);
    expect(find.text('Frequently used'), findsOneWidget);
    query.text = 'pizza';
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('🍕').first);
    await tester.pump();
    expect(picked, ['🍕']);
    // Real message menus record only the transport's accepted add.
    expect(EmojiRecents.usage, {'😂': 1, '🔥': 2});
  });

  testWidgets(
    'frequent respects network spelling, selected state and allowed search',
    (tester) async {
      await AppSettings.reactionsFrequentlyUsed.setItem(true);
      EmojiRecents.add('🍕');
      EmojiRecents.add('👍');
      EmojiSkinTones.remember('👍', '🏽');
      final query = TextEditingController();
      addTearDown(query.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(Brightness.dark),
          home: Scaffold(
            body: ChatLoomEmojiPicker(
              reactions: const EmojiReactionChoices(
                allowed: ['👍\u{FE0F}', '🔥'],
                own: {'👍'},
              ),
              controller: query,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picker = tester.widget<NotionEmojiPicker>(
        find.byType(NotionEmojiPicker),
      );
      expect(picker.sections.single.emoji.map((emoji) => emoji.emoji), [
        '👍\u{FE0F}',
      ]);
      expect(picker.selected, {'👍'});
      expect(picker.tones, isEmpty);
      expect(picker.onTone, isNull);
      query.text = 'pizza';
      await tester.pumpAndSettle();
      expect(find.text('No matching reaction in this chat'), findsOneWidget);
      query.text = 'fire';
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('🔥'), findsOneWidget);
    },
  );

  testWidgets('Reset keeps a useful frequent view; composer remains complete', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await AppSettings.reactionsFrequentlyUsed.setItem(true);
    EmojiRecents.add('😂');
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ChatLoomEmojiPicker(
              reactions: const EmojiReactionChoices(),
              onSelected: picked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('emoji-reset-usage')));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(EmojiRecents.usage, isEmpty);
    expect(find.text('Choose an emoji with Search.'), findsOneWidget);
    expect(AppSettings.reactionsFrequentlyUsed.value, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(body: ChatLoomEmojiPicker(onSelected: picked.add)),
      ),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<NotionEmojiPicker>(
      find.byType(NotionEmojiPicker),
    );
    expect(picker.categoryBar, isTrue);
    expect(
      picker.sections.map((section) => section.title),
      contains('Smileys & people'),
    );
    expect(find.text('Frequently used'), findsNothing);
  });

  testWidgets('a pick is recent everywhere; tones show in the grid', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 640);
    addTearDown(tester.view.reset);
    EmojiSkinTones.remember('👋', '🏾');
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(body: ChatLoomEmojiPicker(onSelected: picked.add)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recently used'), findsNothing);
    await tester.tap(find.bySemanticsLabel('😂').first);
    await tester.pump();
    expect(picked, ['😂']);
    expect(EmojiRecents.emoji.first, '😂');
    // Stored in emoji_picker_flutter's own format and key.
    final stored = jsonDecode(AppSettings.store.getString(EmojiRecents.key)!);
    expect(data.RecentEmoji.fromJson((stored as List).first).emoji.emoji, '😂');
    // The reaction picker of a fixed network set opens with it on top.
    await tester.pumpWidget(
      MaterialApp(
        theme: NotionTheme.build(Brightness.dark),
        home: Scaffold(
          body: ChatLoomEmojiPicker(
            reactions: const EmojiReactionChoices(
              allowed: ['👍\u{FE0F}', '😂', '🔥'],
              quick: ['👍'],
              own: {'🔥'},
            ),
            onSelected: picked.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quick reactions'), findsOneWidget);
    expect(find.text('Recently used'), findsOneWidget);
    expect(find.text('Reactions in this chat'), findsOneWidget);
    // No category bar for a short fixed set; no skin tones.
    expect(find.byKey(const ValueKey('emoji-category-allowed')), findsNothing);
    await tester.tap(find.bySemanticsLabel('👍\u{FE0F}').first);
    await tester.pump();
    expect(picked.last, '👍\u{FE0F}');
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'capture frequent reaction sheet ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 650);
        addTearDown(tester.view.reset);
        await AppSettings.reactionsFrequentlyUsed.setItem(true);
        const frequent = [
          '❤️',
          '👍',
          '😮',
          '💪',
          '😆',
          '😢',
          '😭',
          '😍',
          '😂',
          '🔥',
          '🥹',
          '🎉',
        ];
        for (var index = 0; index < frequent.length; index++) {
          for (var count = 0; count < frequent.length - index; count++) {
            EmojiRecents.add(frequent[index]);
          }
        }
        var theme = NotionTheme.build(brightness);
        if (_captureEmojiFont) {
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamilyFallback: const ['ChatLoom capture emoji'],
            ),
          );
        }
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('frequent-emoji-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: NotionButton(
                      label: 'Reactions',
                      onPressed: () => showEmojiPickerSheet(
                        context,
                        title: 'Reactions',
                        reactions: const EmojiReactionChoices(own: {'👍'}),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Reactions'));
        await tester.pumpAndSettle();
        expect(find.text('Frequently used'), findsOneWidget);
        expect(find.text('Reset'), findsOneWidget);
        expect(find.text('Search emoji'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'frequent-emoji-${brightness.name}-390');
      },
      skip: Platform.environment['CHATLOOM_FREQUENT_EMOJI_CAPTURE_DIR'] == null,
    );
  }
}
