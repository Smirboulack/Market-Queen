import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/app_state.dart';
import 'package:market_queen/models/canvas_feed.dart';
import 'package:market_queen/models/studio_runner.dart';

/// Asking for four goes out as four requests at once, not four one after
/// another.
///
/// It is the difference between waiting forty seconds and waiting ten, and it
/// is invisible from the outside until you time it -- so it is pinned here
/// instead. The proof is that `send` comes back with every tile still pending:
/// a runner that awaited each request before starting the next could only
/// return once they had all finished.
///
/// Nothing here reaches the network: the test binding answers every request
/// itself. The key is a fake one, and it is there only so the tasks get past
/// their own "no API key" guard and actually leave -- a task that refuses
/// before it opens a socket settles in the same microtask it was started in,
/// which would make a sequential runner and a parallel one look alike.
void main() {
  late AppState app;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    app = await AppState.create();
    // The stored language too, not just the translator. AppState reapplies
    // `settings.uiLanguage` on every preference write, so a test that changes
    // any setting would otherwise snap the interface back to whatever this
    // machine has saved -- and every label asserted below is the English one.
    app.settings.uiLanguage = 'en';
    await app.translator.applyLanguage('en');
    app.settings.setApiKey('gemini', 'test-key-not-a-real-one');
  });

  tearDownAll(() => app.settings.setApiKey('gemini', ''));

  setUp(() {
    app.project.feed.clear();
    app.settings
      ..setPref('imageProvider', 'gemini-image')
      ..setPref('imageModel', 'gemini-3.1-flash-image');
  });

  testWidgets('a batch of four leaves as four requests in flight', (
    tester,
  ) async {
    final batch = await app.runner.send(
      const GenerationOrder(
        kind: CanvasKind.image,
        category: 'image',
        prompt: 'a bottle on a windowsill',
        count: 4,
      ),
    );

    expect(batch.items, hasLength(4));
    // Every one of them is out, and none has come back yet: they were fired
    // together and the refusals land in the microtasks after this line. A
    // sequential runner would be reached here with four settled tiles, because
    // `send` itself would have had to wait for each of them.
    expect(
      batch.items.every((item) => item.status == CanvasStatus.pending),
      isTrue,
      reason: 'all four should still be in the air',
    );
    expect(app.runner.running, isTrue);

    // And they all settle, so nothing is left spinning.
    await tester.pump();
    expect(app.runner.running, isFalse);
    expect(
      batch.items.every((item) => item.status == CanvasStatus.failed),
      isTrue,
    );
  });

  testWidgets('the picture forge fires its whole round at once', (
    tester,
  ) async {
    // The actor and scene studio asks for three per press through the same
    // path, and has the same reason to want them at the same time.
    final forge = app.actorForge;
    await forge.generate(prompt: 'a woman in her thirties', count: 3);

    expect(forge.requested, 3);
    expect(forge.received, 0);
    expect(forge.running, isTrue);

    await tester.pump();
    expect(forge.running, isFalse);
  });
}
