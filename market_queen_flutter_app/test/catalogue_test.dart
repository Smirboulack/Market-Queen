import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/core/pricing.dart';
import 'package:market_queen/providers/capabilities.dart';
import 'package:market_queen/providers/model_schemas.dart';
import 'package:market_queen/providers/registry.dart';
import 'package:market_queen/providers/types.dart';

/// The catalogue is the map of who the app talks to, and three things about it
/// have to stay true or the app quietly lies: every provider can actually be
/// run, every provider is bought from an account that has a key field, and
/// every model either has a price or is openly marked as having none. None of
/// those survive being checked by eye across seventeen entries.
void main() {
  final registry = Registry();

  group('the dials an engine actually reads', () {
    // The panel draws ElevenLabs' voice_settings. A provider with no equivalent
    // field drops them silently, so a slider drawn for it is the interface
    // promising a change that costs a read to disprove.
    test('MiniMax takes a speed and nothing else', () {
      final minimax = VoiceCapabilities.of('minimax-tts', 'speech-2.8-hd');

      expect(minimax.honours('voiceSpeed'), isTrue);
      expect(minimax.honours('voiceStability'), isFalse);
      expect(minimax.honours('voiceSimilarity'), isFalse);
      expect(minimax.honours('voiceStyle'), isFalse);
    });

    test('Eleven v3 has no speed, and three stability settings', () {
      final v3 = VoiceCapabilities.of('elevenlabs', 'eleven_v3');

      expect(v3.honours('voiceSpeed'), isFalse);
      expect(v3.honours('voiceStability'), isTrue);
      expect(v3.stabilitySteps, [0.0, 0.5, 1.0]);
    });

    test('the classic engines take all four, on a continuum', () {
      final classic = VoiceCapabilities.of('elevenlabs', 'eleven_multilingual_v2');

      for (final dial in const [
        'voiceSpeed',
        'voiceStability',
        'voiceSimilarity',
        'voiceStyle',
      ]) {
        expect(classic.honours(dial), isTrue, reason: dial);
      }
      expect(classic.stabilitySteps, isEmpty);
    });

    test('every engine on the shelf is described', () {
      // An engine nobody has written down draws all four, which is the safe
      // default -- but it is a default, and the shelf is two entries long.
      for (final provider in registry.providers('voice')) {
        for (final model in provider.models) {
          expect(
            VoiceCapabilities.of(provider.id, model.id).known,
            isTrue,
            reason: '${provider.id} / ${model.id}',
          );
        }
      }
    });
  });

  group('the frame an ad is drawn at', () {
    // The run that started this: the picture shelf was set to 3840x2160 and the
    // ad to 9:16, and gpt-image-2 takes an explicit size over a ratio -- so six
    // stills came back 4K landscape for a vertical ad, and were quoted at the
    // 1024x1024 rate on the way out.
    final gptImage = ImageCapabilities.of('gpt-image-2');

    test('a saved frame of the wrong shape is dropped, not honoured', () {
      expect(gptImage.frameFor('3840x2160', '9:16'), '');
      expect(gptImage.frameFor('1536x1024', '9:16'), '');
      expect(gptImage.frameFor('1024x1024', '9:16'), '');

      // Portrait, but 2:3 rather than 9:16. Dropped too, and deliberately: an
      // empty frame is the provider deriving one from the ratio, and it knows
      // which frames it actually sells better than a near-enough guess does.
      expect(gptImage.frameFor('1024x1536', '9:16'), '');
    });

    test('a saved frame of the right shape is kept', () {
      expect(gptImage.frameFor('2160x3840', '9:16'), '2160x3840');
      expect(gptImage.frameFor('1024x1024', '1:1'), '1024x1024');
      expect(gptImage.frameFor('2048x2048', '1:1'), '2048x2048');
      expect(gptImage.frameFor('3840x2160', '16:9'), '3840x2160');
    });

    test('a frame that is not a pixel pair is left alone', () {
      // "auto" and the shorthand tokens have no shape to disagree with.
      expect(gptImage.frameFor('auto', '9:16'), 'auto');
      expect(
        ImageCapabilities.of('gemini-3-pro-image').frameFor('2K', '9:16'),
        '2K',
      );
    });
  });

  group('shelves', () {
    // The Models page is two shelves now -- keys, and what those keys buy --
    // and neither is filtered by category: both list every account there is.
    // So the thing worth asserting moved. It used to be that no provider fell
    // between the five category shelves; it is now that no provider is bought
    // from an account the keys shelf does not offer, which is the same
    // failure -- a model you can pick in the studio and never pay for -- from
    // the other end.
    test('every provider is bought from an account with a key field', () {
      final accounts = {
        for (final credential in registry.credentials()) credential.id,
      };

      for (final entry in registry.entries) {
        expect(
          accounts,
          contains(entry.credential),
          reason: '${entry.id} is bought from "${entry.credential}", which has '
              'no key field, so its models can be picked and never paid for',
        );
      }
    });

    test('every account sells something', () {
      final sold = {for (final entry in registry.entries) entry.credential};

      for (final credential in registry.credentials()) {
        expect(
          sold,
          contains(credential.id),
          reason: '${credential.id} asks for a key and nothing in the '
              'catalogue spends it',
        );
      }
    });

    test('every provider category is one the composer asks for', () {
      // The shelves no longer carry categories, so nothing else checks these
      // strings -- and a typo in one is a provider the studio never offers.
      const asked = {
        'text',
        'avatar',
        'image',
        'upscale',
        'video',
        'voice',
        'captions',
      };

      for (final entry in registry.entries) {
        expect(asked, contains(entry.category), reason: entry.id);
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
          if (pricing.unitPrice(model.id) != null) continue;
          missing.add('${entry.id} / ${model.id}');
        }
      }

      // A model with no published price is fine and is reported as unknown in
      // the estimate. What is not fine is a model nobody looked at: the two
      // below are the ones deliberately recorded as having no public figure,
      // and anything else appearing here means pricing.json fell behind the
      // catalogue.
      // Empty, and that is the state to keep it in: every model the app
      // offers has a published per-request price. An id landing here means
      // pricing.json fell behind the catalogue.
      const knownUnpriced = <String>{};

      final unexpected = [
        for (final line in missing)
          if (!knownUnpriced.contains(line.split(' / ').last)) line,
      ];

      expect(unexpected, isEmpty);

      // And the other way round, so the exemption list cannot outlive the
      // reason for it: a model that has since been priced must come off it.
      final stale = [
        for (final id in knownUnpriced)
          if (pricing.unitPrice(id) != null) id,
      ];
      expect(stale, isEmpty, reason: 'now priced -- drop from knownUnpriced');
    });

    test('BytePlus prices follow the published table', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final pricing = Pricing(registry);
      await pricing.load();

      // Every figure below is a worked example off the ModelArk pricing page,
      // divided out to the unit this app bills in. They are checked here
      // because they are the numbers a user reconciles against a real invoice:
      // a resolution silently priced at the wrong tier is a fourfold error
      // that nothing else in the app would notice.
      double? perSecond(String model, String resolution, {bool audio = false}) =>
          pricing
              .unitPrice(model, resolution: resolution, audio: audio)
              ?.amount;

      // Seedance 2.5: 1.156 per 5s clip at 720p, 2.843 at 1080p.
      expect(
        perSecond('dreamina-seedance-2-5-260628', '720p'),
        closeTo(0.2311, 0.0005),
      );
      expect(
        perSecond('dreamina-seedance-2-5-260628', '1080p'),
        closeTo(0.5686, 0.0005),
      );
      // Seedance 2.0: 0.35 / 0.76 / 1.87 / 3.89 per 5s clip, 480p to 4K. The
      // steps are not multiples of one another -- 1080p and 4K are billed at
      // different rates per token -- which is the whole reason the resolution
      // has to reach the price at all.
      expect(
        perSecond('dreamina-seedance-2-0-260128', '480p'),
        closeTo(0.0673, 0.0005),
      );
      expect(
        perSecond('dreamina-seedance-2-0-260128', '4k'),
        closeTo(0.7776, 0.0005),
      );
      // A soundtrack doubles Seedance 1.5 Pro: 0.13 silent against 0.26 with,
      // per 5s clip at 720p.
      expect(
        perSecond('seedance-1-5-pro-251215', '720p'),
        closeTo(0.0259, 0.0005),
      );
      expect(
        perSecond('seedance-1-5-pro-251215', '720p', audio: true),
        closeTo(0.0518, 0.0005),
      );
      // A resolution the model does not list falls back to its headline rate
      // rather than to nothing.
      expect(
        perSecond('dreamina-seedance-2-0-mini-260615', '1080p'),
        closeTo(0.0756, 0.0005),
      );

      // Seedream 5.0 Pro steps at 2.61 megapixels: a 2K frame is under it, a
      // 4K frame is over. Everything else is flat whatever the size.
      double? perImage(String model, double megapixels) =>
          pricing.unitPrice(model, megapixels: megapixels)?.amount;

      expect(perImage('dola-seedream-5-0-pro-260628', 2.36), 0.045);
      expect(perImage('dola-seedream-5-0-pro-260628', 8.85), 0.09);
      expect(perImage('seedream-4-5-251128', 8.85), 0.04);

      // And the receipt side: the first reference image is free, the rest are
      // three tenths of a cent each.
      final charged = pricing.charged(
        modelId: 'dola-seedream-5-0-pro-260628',
        megapixels: 2.36,
        extraInputImages: 2,
      );
      expect(charged.known, isTrue);
      expect(charged.amount, closeTo(0.045 + 0.006, 1e-9));

      // A token count the provider reported prices the clip outright, and is
      // reported as exact rather than as an estimate.
      final billed = pricing.charged(
        modelId: 'dreamina-seedance-2-5-260628',
        tokens: 108000,
        seconds: 5,
        resolution: '720p',
      );
      expect(billed.exact, isTrue);
      expect(billed.amount, closeTo(1.156, 0.001));
    });
  });
}
