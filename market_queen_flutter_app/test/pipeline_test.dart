import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:market_queen/core/pricing.dart';
import 'package:market_queen/core/http_util.dart';
import 'package:market_queen/providers/registry.dart';
import 'package:market_queen/providers/types.dart';
import 'package:market_queen/providers/voice_profile.dart';
import 'package:market_queen/providers/voice_providers.dart';

/// The scenario from the run this pipeline was rebuilt after: nine written
/// beats, which used to be bought as nine of everything.
const _scenario = '''
Oh les sœurs, j'en ai trop marre du célibat…

Genre vraiment, j'ai l'impression que je vais finir vieille fille à ce rythme.

À chaque fois que je parle à quelqu'un, soit on n'a absolument rien en commun, soit ça dure trois jours et puis plus rien.

Et là, une copine m'a parlé de NafSync.

En gros, c'est une appli de rencontre musulmane, mais le truc que j'ai bien aimé, c'est qu'ils mettent vraiment l'accent sur la compatibilité.

Tu remplis ton profil, tes valeurs, ce que tu recherches… et l'idée c'est de rencontrer quelqu'un avec qui t'es vraiment sur la même longueur d'onde.

Franchement, je me suis dit : bon… pourquoi pas ?

Donc voilà, je teste NafSync.

Les sœurs, si vous êtes célibataires aussi, allez voir, parce que là… moi j'ai donné assez de chances aux hommes de mon entourage.
''';

void main() {
  group('what one ad costs', () {
    // The estimate and the run are two readings of the same ad, and the whole
    // reason to show a number before Generate is that they agree. Every case
    // below is a way they came apart on a real run.
    late Pricing pricing;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      pricing = Pricing(Registry());
      await pricing.load();
    });

    Map<String, Object?> ad({
      String script = _scenario,
      String imageSize = '',
      String imageQuality = '',
    }) => {
      'script': script,
      'durationSeconds': 20,
      'aspectRatio': '9:16',
      'textProvider': 'openai-chat',
      'textModel': 'gpt-5-mini',
      'imageProvider': 'openai-image',
      'imageModel': 'gpt-image-2',
      'imageSize': imageSize,
      'imageQuality': imageQuality,
      'voiceProvider': 'elevenlabs',
      'voiceModel': 'eleven_multilingual_v2',
      'avatarProvider': 'heygen-avatar',
      'avatarModel': 'avatar_iv',
    };

    List<PriceLine> linesFor(String step, Map<String, Object?> request) =>
        pricing.estimate(request).lines.where((line) => line.step == step).toList();

    test('one take buys one frame, whatever the scenario is', () {
      // Nine written beats. It used to quote nine stills and nine clips.
      expect(linesFor('frames', ad()).length, 1);
      expect(linesFor('frames', ad()).single.units, 1);
      expect(linesFor('video', ad()).length, 1);
    });

    test('the frame is priced at the size actually asked for', () {
      // The 4K run: the frame preference said 3840x2160 and the estimate quoted
      // the 1024x1024 rate, so six stills came back around eight times dearer
      // than the number on the button.
      final small = linesFor('frames', ad(imageSize: '1024x1024', imageQuality: 'medium'));
      final large = linesFor('frames', ad(imageSize: '3840x2160', imageQuality: 'medium'));

      expect(small.single.amount, greaterThan(0));
      expect(
        large.single.amount,
        greaterThan(small.single.amount * 5),
        reason: 'a 4K frame is roughly eight times the area of the square',
      );
    });

    test('a scenario the user wrote is not sent to a writer', () {
      expect(linesFor('script', ad()), isEmpty);
      expect(linesFor('script', ad(script: '')).length, 1);
    });

    test('nothing is quoted for subtitles or for product shots', () {
      // Both options are gone. A line for either would be money quoted for a
      // call the pipeline no longer makes.
      final steps = pricing.estimate(ad()).lines.map((line) => line.step).toSet();
      expect(steps, {'voice', 'frames', 'video'});
    });

    test('the clip is quoted for as long as the read', () {
      final seconds = Pricing.speechSeconds(Pricing.wordCount(_scenario));
      expect(linesFor('video', ad()).single.units, closeTo(seconds, 0.001));
    });
  });

  group('ElevenLabs request body', () {
    VoiceRequest request(String model) => VoiceRequest(
      model: model,
      voiceId: 'voice',
      text: 'Oh les sœurs.',
      stability: 0.45,
      similarity: 0.8,
      style: 0.35,
      speed: 1.2,
      previousText: 'la réplique d\'avant',
      nextText: 'la réplique d\'après',
    );

    test('v3 is sent nothing it rejects', () {
      // The 400 that killed a whole run: v3 takes neither the continuity
      // fields nor a speed, and quantises its stability.
      final body = ElevenLabsModel.of('eleven_v3').body(request('eleven_v3'));
      final settings = body['voice_settings']! as Map<String, Object?>;

      expect(body.containsKey('previous_text'), isFalse);
      expect(body.containsKey('next_text'), isFalse);
      expect(settings.containsKey('speed'), isFalse);
      expect(settings['stability'], 0.5);
      expect(body['model_id'], 'eleven_v3');
      expect(body['text'], 'Oh les sœurs.');
    });

    test('the older engines keep everything they support', () {
      final body = ElevenLabsModel.of(
        'eleven_multilingual_v2',
      ).body(request('eleven_multilingual_v2'));
      final settings = body['voice_settings']! as Map<String, Object?>;

      expect(body['previous_text'], 'la réplique d\'avant');
      expect(body['next_text'], 'la réplique d\'après');
      expect(settings['speed'], 1.2);
      expect(settings['stability'], 0.45);
    });

    test('a v3 id from anywhere is recognised as v3', () {
      expect(ElevenLabsModel.of('eleven_v3').stitching, isFalse);
      expect(
        ElevenLabsModel.of('fal-ai/elevenlabs/tts/eleven-v3').stitching,
        isFalse,
      );
      expect(ElevenLabsModel.of('eleven_turbo_v2_5').stitching, isTrue);
      expect(ElevenLabsModel.of('eleven_flash_v2_5').stitching, isTrue);
    });

    test('stability snaps to the nearest setting v3 offers', () {
      const v3 = ElevenLabsModel.v3;
      expect(v3.snapStability(0.0), 0.0);
      expect(v3.snapStability(0.2), 0.0);
      expect(v3.snapStability(0.45), 0.5);
      expect(v3.snapStability(0.9), 1.0);
      // The classic engines take the continuum as it comes.
      expect(ElevenLabsModel.classic.snapStability(0.45), 0.45);
    });
  });

  group('casting brief', () {
    // What the brief becomes is a real Voice Library query, in the exact
    // spelling that search honours. It was verified against the live API:
    // `language=French`, `gender=Female` and `use_cases=Social Media` all
    // return zero voices where the lower-case snake_case forms return hundreds.
    test('the brief is a query, in the spelling the API answers to', () {
      const brief = VoiceProfile(
        locale: 'fr-FR',
        gender: 'female',
        age: 'young',
        useCase: 'social_media',
        tone: 'upbeat',
      );

      expect(brief.filters, {
        'language': 'fr',
        'locale': 'fr-FR',
        'gender': 'female',
        'age': 'young',
        'use_cases': 'social_media',
        'descriptives': 'upbeat',
      });
    });

    test('region travels as locale, never as accent', () {
      // The bug this whole file exists to prevent: ElevenLabs scopes `accent`
      // to the language a voice speaks, and its value "french" belongs to
      // English -- it means an English voice with a French accent. Asking for
      // language=fr&accent=french returns English voices. Region has to go as
      // `locale`, and `accent` must never appear in a query.
      const quebec = VoiceProfile(locale: 'fr-CA');
      const france = VoiceProfile(locale: 'fr-FR');

      expect(quebec.filters['locale'], 'fr-CA');
      expect(france.filters['locale'], 'fr-FR');
      expect(quebec.filters.containsKey('accent'), isFalse);
      expect(france.filters.containsKey('accent'), isFalse);
      expect(quebec.language, 'fr');
      expect(quebec.signature, isNot(france.signature));
    });

    test('an unset language is the language the ad is written in', () {
      // The tests never switch the interface, so that is English here. What
      // matters is that "unset" is a real language rather than "any": a French
      // ad read by an English voice was the whole complaint.
      const brief = VoiceProfile(gender: 'female');
      expect(brief.language, 'en');
      expect(brief.filters, {'language': 'en', 'gender': 'female'});
    });

    test('a brief widens in the order the criteria matter', () {
      // Language is not in the list at all: it is never given up.
      expect(VoiceProfile.relaxationOrder, [
        'descriptives',
        'use_cases',
        'age',
        'locale',
        'gender',
      ]);
      expect(VoiceProfile.relaxationOrder.contains('language'), isFalse);
    });

    test('it reads back out of an actor, and out of a run request', () {
      // The actor's extras and the pipeline's request map carry the same keys,
      // which is what lets the editor and the render cast the same voice.
      final brief = VoiceProfile.from(<String, Object?>{
        'voiceId': '',
        'voiceLocale': 'cmn-TW',
        'voiceGender': 'male',
        'voiceAge': 'middle_aged',
        'voiceUse': 'advertisement',
        'voiceTone': 'calm',
        'voiceStability': 0.45,
      });

      // Chinese is filed under cmn-* in the library, not zh-*.
      expect(brief.language, 'zh');
      expect(brief.filters['locale'], 'cmn-TW');
      expect(brief.isEmpty, isFalse);
      expect(const VoiceProfile().isEmpty, isTrue);
    });
  });

  group('pictures handed to a model', () {
    // The run that failed twice on one file: a product photo downloaded off a
    // shop page, in AVIF. It went up labelled "image/png" because that is what
    // the old code called anything it did not recognise, and OpenAI answered
    // "you uploaded an unsupported image" -- twice, without ever naming AVIF.
    final avif = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70, // ....ftyp
      0x61, 0x76, 0x69, 0x66, 0x00, 0x00, 0x00, 0x00, // avif....
      0x61, 0x76, 0x69, 0x66, 0x6d, 0x69, 0x66, 0x31, // avifmif1
      ...List<int>.filled(64, 0),
    ]);

    test('a format nothing can read is refused, not relabelled', () {
      final uri = Http.imageBytesToDataUri(avif);
      expect(uri, isEmpty);
      // The point is what it must never do: claim to be a PNG.
      expect(uri.startsWith('data:image/png'), isFalse);
    });

    test('a real picture goes through as what it is', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

      expect(Http.sniffMime(png), 'image/png');
      expect(Http.imageBytesToDataUri(png), startsWith('data:image/png;base64,'));
    });

    test('an oversized picture is re-encoded rather than refused', () {
      // Noise, so it cannot be compressed away to nothing.
      final big = img.Image(width: 900, height: 900);
      for (var y = 0; y < big.height; ++y) {
        for (var x = 0; x < big.width; ++x) {
          big.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
        }
      }
      final png = Uint8List.fromList(img.encodePng(big));
      expect(png.length, greaterThan(64 * 1024));

      final uri = Http.imageBytesToDataUri(png, maxBytes: 64 * 1024);
      expect(uri, startsWith('data:image/jpeg;base64,'));
    });

    test('a multipart part says what it is carrying', () {
      // `http` sends every part as application/octet-stream unless told
      // otherwise, and the OpenAI uploads reject that whatever the file is
      // called. This is the whole of that bug.
      expect(Http.mediaType('image/png').mimeType, 'image/png');
      expect(Http.mediaType('image/jpeg; charset=binary').subtype, 'jpeg');
      expect(Http.mediaType('').mimeType, 'application/octet-stream');
      expect(Http.mediaType('nonsense').mimeType, 'application/octet-stream');
    });
  });

  group('provider errors', () {
    test('an ElevenLabs message is read out of its envelope', () {
      // {"detail": {...}} used to fall through every case and dump the raw
      // JSON into the log.
      const body = '{"detail":{"type":"validation_error",'
          '"code":"unsupported_model",'
          '"message":"Providing previous_text or next_text is not yet '
          'supported with the \'eleven_v3\' model."}}';

      expect(
        Http.extractApiError(body),
        startsWith('Providing previous_text or next_text'),
      );
      expect(Http.describeError(400, body), startsWith('HTTP 400 - Providing'));
    });

    test('the shapes the other providers use still work', () {
      expect(
        Http.extractApiError('{"error":{"message":"insufficient quota"}}'),
        'insufficient quota',
      );
      expect(Http.extractApiError('{"detail":"not found"}'), 'not found');
      expect(
        Http.extractApiError('{"detail":[{"msg":"field required"}]}'),
        'field required',
      );
      expect(Http.extractApiError('not json at all'), isEmpty);
    });
  });
}
