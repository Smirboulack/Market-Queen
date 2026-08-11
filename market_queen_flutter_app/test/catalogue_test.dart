import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/core/pricing.dart';
import 'package:market_queen/providers/registry.dart';
import 'package:market_queen/providers/types.dart';

/// The catalogue is now the map of who the app talks to, and three things about
/// it have to stay true or the Models menu quietly lies: every provider on a
/// shelf can actually be run, every key field belongs to a provider that is on
/// that shelf, and every model either has a price or is openly marked as having
/// none. None of those survive being checked by eye across seventeen entries.
void main() {
  final registry = Registry();

  group('panels', () {
    test('every provider lands on exactly one shelf', () {
      final placed = <String, String>{};

      for (final panel in Registry.panels) {
        for (final provider in registry.providersForPanel(panel.id)) {
          final already = placed[provider.id];
          expect(
            already,
            isNull,
            reason: '${provider.id} is on both $already and ${panel.id}',
          );
          placed[provider.id] = panel.id;
        }
      }

      for (final entry in registry.entries) {
        expect(
          placed.containsKey(entry.id),
          isTrue,
          reason: '${entry.id} is in the catalogue but on no shelf, so its '
              'models can be picked in the composer and never configured',
        );
      }
    });

    test('a shelf asks for exactly the keys its providers need', () {
      for (final panel in Registry.panels) {
        final needed = {
          for (final provider in registry.providersForPanel(panel.id))
            if (provider.credential.isNotEmpty) provider.credential,
        };
        final offered = {
          for (final credential in registry.credentialsForPanel(panel.id))
            credential.id,
        };
        expect(offered, needed, reason: 'panel ${panel.id}');
      }
    });

    test('every credential is reachable from some shelf', () {
      final reachable = {
        for (final panel in Registry.panels)
          for (final credential in registry.credentialsForPanel(panel.id))
            credential.id,
      };

      for (final credential in registry.credentials()) {
        expect(
          reachable,
          contains(credential.id),
          reason: '${credential.id} has a key field nobody can ever see, so '
              'the provider it unlocks can never be switched on',
        );
      }
    });
  });

  group('wiring', () {
    test('every provider resolves to a task', () {
      for (final entry in registry.entries) {
        final model = registry.resolveModel(entry.id, entry.defaultModel);
        expect(model, isNotEmpty, reason: '${entry.id} resolves to no model');

        final task = switch (entry.category) {
          'text' => ProviderFactory.script(entry.id, ScriptRequest()),
          'image' || 'upscale' => ProviderFactory.image(entry.id, ImageRequest()),
          'video' => ProviderFactory.video(entry.id, VideoRequest()),
          'avatar' => ProviderFactory.avatar(entry.id, AvatarRequest()),
          'voice' => ProviderFactory.voice(entry.id, VoiceRequest()),
          'captions' =>
            ProviderFactory.transcribe(entry.id, TranscribeRequest()),
          _ => null,
        };

        expect(
          task,
          isNotNull,
          reason: '${entry.id} is offered in the menu but the factory has no '
              'task for it, so picking it fails at run time',
        );
      }
    });
  });

  group('pricing', () {
    test('every model is priced or openly unpriced', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final pricing = Pricing(registry);
      await pricing.load();

      final missing = <String>[];
      for (final entry in registry.entries) {
        for (final model in entry.models) {
          if (Registry.isAuto(model.id)) continue;
          if (pricing.unitPrice(model.id) != null) continue;
          missing.add('${entry.id} / ${model.id}');
        }
      }

      // A model with no published price is fine and is reported as unknown in
      // the estimate. What is not fine is a model nobody looked at: the ones
      // below are the ones deliberately recorded as having no public figure,
      // and anything else appearing here means pricing.json fell behind the
      // catalogue.
      const knownUnpriced = {
        'gemini-3.1-pro-preview',
        'gemini-3-pro-image',
        'seedream-5-0-260128',
        'gpt-image-2',
        'gpt-image-1.5',
        'gpt-image-1-mini',
        'ray-2',
        'ray-flash-2',
        'speech-2.8-hd',
        'speech-2.8-turbo',
        'gemini-2.5-flash-preview-tts',
        'gemini-2.5-pro-preview-tts',
      };

      final unexpected = [
        for (final line in missing)
          if (!knownUnpriced.contains(line.split(' / ').last)) line,
      ];

      expect(unexpected, isEmpty);
    });
  });
}
