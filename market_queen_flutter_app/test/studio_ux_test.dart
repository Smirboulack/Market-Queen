import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:market_queen/app_state.dart';
import 'package:market_queen/core/clipboard_media.dart';
import 'package:market_queen/models/canvas_feed.dart';
import 'package:market_queen/ui/studio/ad_editor_page.dart';
import 'package:market_queen/ui/studio/canvas_view.dart';
import 'package:market_queen/ui/studio/composer.dart';
import 'package:market_queen/ui/studio/composer_tabs.dart';
import 'package:market_queen/ui/studio/mentions.dart';
import 'package:market_queen/ui/theme.dart';
import 'package:market_queen/ui/widgets/skeleton.dart';

/// The six studio complaints, each pinned by the thing that was actually wrong.
///
/// Four of them are only visible in a laid-out tree -- a caption under a tile,
/// a padding that has to track a bar's height, a glyph on a skeleton -- which is
/// exactly the kind of thing that regresses silently. The clipboard and the
/// reveal-in-folder calls end in the operating system and are not asserted here;
/// what can be is the decision made before the call.
void main() {
  const window = Size(1420, 940);

  late AppState app;
  late Directory scratch;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    scratch = Directory.systemTemp.createTempSync('mq-studio-ux');
  });

  tearDownAll(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  setUp(() => app.project.feed.clear());

  // A real 1x1 PNG: the tiles put it through the image decoder, and a file of
  // random bytes turns the test into an exercise in error builders.
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKm'
    'MIQAAAABJRU5ErkJggg==',
  );

  String file(String name) {
    final path = p.join(scratch.path, name);
    File(path).writeAsBytesSync(pixel);
    return path;
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view
      ..physicalSize = window
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final theme = MqTheme(dark: false);
    await tester.pumpWidget(
      AppTheme(
        theme: theme,
        child: MaterialApp(
          theme: theme.material,
          home: Scaffold(
            backgroundColor: theme.background,
            body: AdEditorPage(
              app: app,
              onGenerate: () {},
              onOpenRender: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Switches to a tab by its pill.
  Future<void> pickTab(WidgetTester tester, ComposerTab tab) async {
    await tester.tap(find.text(ComposerSpec.of(tab).label));
    await tester.pump();
  }

  /// Fires the drop the composer is wrapped in, which is the only way into its
  /// session-local reference list from outside.
  Future<void> drop(WidgetTester tester, List<String> paths) async {
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [for (final path in paths) DropItemFile(path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
  }

  TextEditingController promptController(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText).first).controller;

  group('handles', () {
    test('are numbered within their own kind, in the order sent', () {
      // The order the runner uploads in: every picture, then every clip, then
      // every recording. Numbering them in drop order instead would point the
      // prompt at the wrong file, which is worse than not naming them.
      expect(
        referenceHandles([
          'a.png',
          'b.mp4',
          'c.jpg',
          'd.mp3',
          'e.mov',
        ]),
        ['@Image1', '@Video1', '@Image2', '@Audio1', '@Video2'],
      );
    });

    test('the longest name wins, and a handle ends where a word ends', () {
      const handles = ['@Image1', '@Image10', '@Marie', '@Marie Curie'];

      String lit(String text) {
        final found = findMentions(text, handles);
        return [
          for (final match in found)
            text.substring(match.start, match.start + match.length),
        ].join('|');
      }

      expect(lit('a shot of @Marie Curie in the lab'), '@Marie Curie');
      expect(lit('@Marie walks in'), '@Marie');
      expect(lit('use @Image10 not @Image1'), '@Image10|@Image1');
      // Not a handle: a longer word that merely starts like one.
      expect(lit('@Image1x is nothing'), '');
      expect(lit('@Mariette is somebody else'), '');
      // Punctuation closes it.
      expect(lit('put @Marie, then @Image1.'), '@Marie|@Image1');
    });

    test('a prompt that names nothing mentions nothing', () {
      expect(promptMentions('a red car', '@Image1'), isFalse);
      expect(promptMentions('a red car like @Image1', '@Image1'), isTrue);
    });
  });

  group('the prompt colours what it recognises', () {
    testWidgets('a known handle is blue and an unknown one is not', (
      tester,
    ) async {
      final controller = MentionController(text: 'put @Image1 next to @Nobody')
        ..handles = ['@Image1'];

      final theme = MqTheme(dark: false);
      late BuildContext captured;
      await tester.pumpWidget(
        AppTheme(
          theme: theme,
          child: MaterialApp(
            theme: theme.material,
            home: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final span = controller.buildTextSpan(
        context: captured,
        style: const TextStyle(color: Color(0xFF171717)),
        withComposing: false,
      );

      final coloured = <String, Color?>{};
      span.visitChildren((child) {
        if (child is TextSpan && child.text != null) {
          coloured[child.text!] = child.style?.color;
        }
        return true;
      });

      expect(coloured['@Image1'], theme.info);
      // Everything else is left exactly as the field styled it -- an @word that
      // points at nothing has to look like it points at nothing.
      expect(coloured.keys.where((text) => text.contains('@Nobody')), isNotEmpty);
      for (final entry in coloured.entries) {
        if (entry.key == '@Image1') continue;
        expect(entry.value, isNot(theme.info), reason: entry.key);
      }
    });
  });

  group('the composer names what is attached to it', () {
    testWidgets('a dropped picture and clip carry their handles', (
      tester,
    ) async {
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await drop(tester, [file('face.png'), file('take.mp4')]);

      expect(find.text('@Image1'), findsOneWidget);
      expect(find.text('@Video1'), findsOneWidget);

      // And the field knows them, which is what turns them blue as they are
      // typed rather than only labelling the tile.
      final controller = promptController(tester);
      expect(controller, isA<MentionController>());
      expect(
        (controller as MentionController).handles,
        containsAll(['@Image1', '@Video1']),
      );
    });

    testWidgets('pressing a reference types its handle into the prompt', (
      tester,
    ) async {
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);
      await drop(tester, [file('one.png')]);

      await tester.tap(find.text('@Image1'));
      await tester.pump();

      expect(promptController(tester).text.trim(), '@Image1');
    });

    testWidgets('the script tab names nothing, because it is spoken', (
      tester,
    ) async {
      // The one place a handle must never appear: the actor reads this field
      // out loud, so "@Image1" in the middle of it is a thing that gets said.
      await pumpEditor(tester);
      await drop(tester, [file('product.png')]);
      addTearDown(() => app.project.media.clear());

      expect(find.textContaining('@Image'), findsNothing);
      expect((promptController(tester) as MentionController).handles, isEmpty);
    });
  });

  group('the feed clears the bar', () {
    testWidgets('the canvas reserves exactly the height the composer took', (
      tester,
    ) async {
      await pumpEditor(tester);
      await pickTab(tester, ComposerTab.image);

      double reserve() =>
          tester.widget<CanvasView>(find.byType(CanvasView)).bottomInset;
      double covered() =>
          window.height - tester.getRect(find.byType(Composer)).top;

      expect(reserve(), moreOrLessEquals(covered(), epsilon: 0.5));

      // A reference row makes the bar taller. This is the bug: the reserve used
      // to be a constant, so anything that grew the bar grew it over the newest
      // result with no way to scroll it clear.
      final before = reserve();
      await drop(tester, [file('grow.png')]);
      await tester.pump();

      expect(reserve(), greaterThan(before));
      expect(reserve(), moreOrLessEquals(covered(), epsilon: 0.5));
    });

    testWidgets('opening the settings column widens the reserve too', (
      tester,
    ) async {
      await pumpEditor(tester);
      await tester.binding.setSurfaceSize(const Size(1040, 900));
      await tester.pump();

      final before = tester
          .widget<CanvasView>(find.byType(CanvasView))
          .bottomInset;

      // Narrow enough that the panel stacks over the bar rather than standing
      // beside it, which is the case where it costs height.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<CanvasView>(find.byType(CanvasView)).bottomInset,
        greaterThan(before),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });

  group('a pending tile says what it is waiting for', () {
    testWidgets('a clip on its way shows its kind and a mark that turns', (
      tester,
    ) async {
      await pumpEditor(tester);

      app.project.feed.add(
        CanvasBatch(
          id: 'batch',
          kind: CanvasKind.video,
          prompt: 'a cat on a windowsill',
          createdAt: DateTime.now(),
          aspectRatio: '9:16',
          items: [CanvasItem(id: 'item')],
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonTile), findsOneWidget);
      // The two things a wait has to say: what is coming, and that something is
      // still happening. A shimmer alone read as "stuck" for minutes at a time.
      expect(find.text('Filming...'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SkeletonTile),
          matching: find.byType(RotationTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a voice-over on its way gets the same treatment', (
      tester,
    ) async {
      await pumpEditor(tester);

      app.project.feed.add(
        CanvasBatch(
          id: 'voice',
          kind: CanvasKind.audio,
          prompt: 'read this',
          createdAt: DateTime.now(),
          items: [CanvasItem(id: 'item')],
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonBar), findsOneWidget);
      expect(find.text('Recording...'), findsOneWidget);
    });
  });

  group('pasted text that is really a file', () {
    test('a media path is picked out, prose is left alone', () {
      final picture = file('pasted.png');

      expect(ClipboardMedia.pathsIn(picture), [picture]);
      // Quoted the way a shell or a browser hands it over.
      expect(ClipboardMedia.pathsIn('"$picture"'), [picture]);
      expect(ClipboardMedia.pathsIn(Uri.file(picture).toString()), [picture]);

      expect(ClipboardMedia.pathsIn('a sentence about a cat'), isEmpty);
      // Right shape, no such file: still a sentence as far as the bar knows.
      expect(
        ClipboardMedia.pathsIn(p.join(scratch.path, 'missing.png')),
        isEmpty,
      );
      // A file that is not media stays text.
      expect(ClipboardMedia.pathsIn(file('notes.txt')), isEmpty);
    });
  });
}
