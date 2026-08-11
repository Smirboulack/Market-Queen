import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/core/pricing.dart';
import 'package:market_queen/providers/capabilities.dart';
import 'package:market_queen/providers/model_schemas.dart';
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

  group('capabilities', () {
    final schemas = ModelSchemas();

    test('every video model states what it accepts', () {
      // The regression this exists for: the lengths and the resolutions used to
      // be read off fal's schema for every model, and when video moved to the
      // direct APIs that reader stopped answering. Nothing broke loudly -- the
      // settings column quietly fell back to "5 s or 10 s, no quality row", so
      // a model that can shoot thirty seconds at 1080p was being sold five at
      // whatever it defaulted to.
      for (final provider in registry.providers('video')) {
        for (final model in provider.models) {
          if (Registry.isAuto(model.id)) continue;

          // fal is the exception on purpose: its catalogue moves between our
          // releases, so those two are read at run time instead.
          if (ModelSchemas.fetches(provider.id)) continue;

          final caps = schemas.capabilities(provider.id, model.id);
          expect(
            caps.known,
            isTrue,
            reason: '${model.id} is offered but declares no capabilities, so '
                'the composer cannot offer its lengths or its quality',
          );
          expect(caps.durationChoices, isNotEmpty, reason: model.id);
          expect(caps.modes, isNotEmpty, reason: model.id);
        }
      }
    });

    test('a model is offered its own ceiling, not a house default', () {
      final seedance = schemas.capabilities(
        'bytedance-video',
        'dreamina-seedance-2-5-260628',
      );

      // Thirty seconds is the whole reason to reach for this one.
      expect(seedance.durationChoices.last, '30');
      expect(seedance.durationFor(30), '30');
      expect(seedance.resolutions, contains('720p'));

      // Hailuo takes 6 or 10 and nothing between, so 8 has to resolve rather
      // than being sent as-is and rejected.
      final hailuo = schemas.capabilities('minimax-video', 'MiniMax-Hailuo-2.3');
      expect(hailuo.durationChoices, ['6', '10']);
      expect(hailuo.durationFor(8), '10');
      expect(hailuo.durationFor(5), '6');

      // Luma spells the unit, and the token has to survive the round trip.
      final luma = schemas.capabilities('luma-video', 'ray-2');
      expect(luma.durationFor(9), '9s');
    });

    test('the mode follows what was dropped in, not which model was picked', () {
      final seedance = schemas.capabilities(
        'bytedance-video',
        'dreamina-seedance-2-5-260628',
      );

      // Nothing attached is a prompt; one still is an opening frame; anything
      // more is reference material. Same model, same endpoint, three requests.
      expect(seedance.modeFor(), VideoMode.textToVideo);
      expect(seedance.modeFor(images: 1), VideoMode.imageToVideo);
      expect(seedance.modeFor(images: 4), VideoMode.referenceToVideo);
      expect(seedance.modeFor(images: 1, videos: 1), VideoMode.referenceToVideo);

      // A model with no reference mode never gets handed one, however much is
      // attached: it falls back to animating the first still.
      final hailuo = schemas.capabilities('minimax-video', 'MiniMax-Hailuo-2.3');
      expect(hailuo.modeFor(images: 4), VideoMode.imageToVideo);
      expect(hailuo.modeFor(), VideoMode.textToVideo);

      // And one that only animates stills says so rather than claiming it can
      // shoot from a prompt.
      const stillsOnly = ModelCapabilities(
        modes: {VideoMode.imageToVideo},
        imageField: 'image_url',
        known: true,
      );
      expect(stillsOnly.modeFor(), VideoMode.imageToVideo);
    });

    test('the shaped request carries the choice, in the model\'s spelling', () {
      final seedance = schemas.capabilities(
        'bytedance-video',
        'dreamina-seedance-2-5-260628',
      );

      final shaped = seedance.videoInput(
        seconds: 30,
        resolution: '480p',
        audio: true,
        aspectRatio: '9:16',
      );

      expect(shaped.input['duration'], 30);
      expect(shaped.input['resolution'], '480p');
      expect(shaped.input['generate_audio'], isTrue);
      expect(shaped.input['aspect_ratio'], '9:16');

      // A resolution this model has never heard of is dropped rather than sent:
      // these APIs reject a value outside their enum.
      final bogus = seedance.videoInput(seconds: 5, resolution: '8k');
      expect(bogus.input.containsKey('resolution'), isFalse);
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
