// SPDX-License-Identifier: AGPL-3.0-or-later
// Production sheet, offline media fixtures; no account sends or provider HTTP.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chatloom/config/setting_keys.dart';
import 'package:chatloom/pages/chat/chat_emoji_picker.dart';
import 'package:chatloom/pages/chat/conversation_source.dart';
import 'package:chatloom/personal/stickers/expanded_sticker_panel.dart';
import 'package:chatloom/personal/stickers/gif_result_tile.dart';
import 'package:chatloom/personal/stickers/gif_search.dart';
import 'package:chatloom/personal/stickers/online_gif_panel.dart';
import 'package:chatloom/personal/stickers/public_gif_search.dart';
import 'package:chatloom/personal/stickers/sticker_panel.dart';
import 'package:chatloom/ui/notion/notion.dart';
import 'package:chatloom/ui/notion/notion_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notion/conversation_test_support.dart';

class _Host implements ConversationComposerHost {
  _Host(this.room);
  @override
  Room room;
  @override
  final inputFocus = FocusNode();
  @override
  final sendController = TextEditingController(text: 'Preserved draft');
  @override
  bool showEmojiPicker = true;
  @override
  void hideEmojiPicker() => showEmojiPicker = false;
  void dispose() {
    inputFocus.dispose();
    sendController.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected host access: ${invocation.memberName}');
}

class _Source extends PublicGifSearch {
  _Source()
    : super(
        apiKey: 'fictional',
        client: MockClient((_) async => throw StateError('No HTTP')),
      );
  final queries = <String>[];
  List<Uint8List> previews = const [];
  @override
  Future<GifSearchPage> search(
    Room room,
    String query, {
    String? offset,
  }) async {
    queries.add(query);
    return GifSearchPage([
      for (var i = 0; i < 18; i++)
        GifSearchResult(
          id: 'fictional-$i',
          title: 'Fictional GIF $i',
          preview: previews.isEmpty ? null : previews[i % previews.length],
        ),
    ]);
  }
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(rootBundle.load('assets/notion/fonts/Roboto-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  late _Host host;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    StickerPanel.debugResetTab(StickerPanelTab.gifs);
    GifResultTile.debugSupportsPlayback = false;
    host = _Host(
      ConversationRoom(ConversationClient(), '!gif:example.invalid'),
    );
  });
  tearDown(() {
    host.dispose();
    StickerPanel.debugResetTab();
    GifResultTile.debugSupportsPlayback = null;
  });

  for (final size in [
    const Size(320, 760),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('expanded search keeps focus and results $size / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 21);
        addTearDown(tester.view.reset);
        final source = _Source();
        addTearDown(source.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: NotionTheme.build(
              Brightness.dark,
            ).copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => NotionButton(
                  label: 'Open GIFs',
                  onPressed: () => showNotionSheet<void>(
                    context: context,
                    builder: (_) => ExpandedStickerPanel(
                      host: host,
                      gifSource: source,
                      loadGifCredentials: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open GIFs'));
        await tester.pumpAndSettle();
        final panel = find.byKey(const ValueKey('expanded-media-panel'));
        expect(tester.getSize(panel).height, greaterThan(size.height * .6));
        final field = find.byKey(const ValueKey('klipy-search'));
        final state = tester.state(find.byType(OnlineGifPanel));
        await tester.enterText(field, 'cat');
        final keyboard = size.height < 500 ? 160.0 : 300.0;
        for (final inset in [keyboard, keyboard - 40, keyboard]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(OnlineGifPanel)), same(state));
        expect(tester.widget<TextField>(field).controller!.text, 'cat');
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(source.queries, ['cat']);
        expect(host.sendController.text, 'Preserved draft');
        expect(
          tester.getRect(field).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        expect(find.byType(GifResultTile), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
    'composer opens remembered GIF sheet once and clears visibility on close',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: NotionTheme.build(Brightness.dark),
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                ChatEmojiPicker(host),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ExpandedStickerPanel), findsOneWidget);
      await tester.pump();
      expect(find.byType(ExpandedStickerPanel), findsOneWidget);
      await tester.tap(
        find.widgetWithIcon(NotionIconButton, Icons.close).first,
      );
      await tester.pumpAndSettle();
      expect(host.showEmojiPicker, isFalse);
      expect(find.byType(ExpandedStickerPanel), findsNothing);
      expect(host.sendController.text, 'Preserved draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('expanded GIF production capture ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);
      final source = _Source();
      addTearDown(source.dispose);
      // Deliberately synthetic stills: this capture checks the production UI,
      // while gif_playback_recovery_test checks the player protocol separately.
      await tester.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            const Rect.fromLTWH(0, 0, 160, 160),
            Paint()
              ..color = [
                const Color(0xff355c7d),
                const Color(0xff6c5b7b),
                const Color(0xff92735b),
                const Color(0xff35756e),
                const Color(0xff8c5671),
                const Color(0xff536a8b),
              ][i],
          );
          final paragraph =
              (ui.ParagraphBuilder(
                  ui.ParagraphStyle(
                    fontFamily: 'Roboto',
                    fontSize: 48,
                    textAlign: TextAlign.center,
                  ),
                )..addText(['Hi!', 'YES', 'WOW', 'LOL', 'OK', 'NO'][i])).build()
                ..layout(const ui.ParagraphConstraints(width: 160));
          canvas.drawParagraph(paragraph, const Offset(0, 48));
          final picture = recorder.endRecording();
          final image = await picture.toImage(160, 160);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          source.previews = [...source.previews, bytes!.buffer.asUint8List()];
          image.dispose();
          picture.dispose();
        }
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture-expanded-gifs'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: NotionTheme.build(
              brightness,
            ).copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: Builder(
                builder: (context) => NotionButton(
                  label: 'Open GIFs',
                  onPressed: () => showNotionSheet<void>(
                    context: context,
                    builder: (_) => ExpandedStickerPanel(
                      host: host,
                      gifSource: source,
                      loadGifCredentials: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open GIFs'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('klipy-search'));
      await tester.enterText(field, 'happy');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(ExpandedStickerPanel));
        for (final bytes in source.previews) {
          await precacheImage(MemoryImage(bytes), context);
        }
      });
      await tester.pumpAndSettle();
      final tiles = find.byType(GifResultTile);
      expect(tester.getRect(tiles.at(0)).top, tester.getRect(tiles.at(2)).top);
      expect(
        tester.getRect(tiles.first).bottom,
        lessThan(tester.getRect(field).top),
      );
      final directory = Platform.environment['CHATLOOM_READABLE_CAPTURE_DIR'];
      if (directory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture-expanded-gifs')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/gif-expanded-${brightness.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
