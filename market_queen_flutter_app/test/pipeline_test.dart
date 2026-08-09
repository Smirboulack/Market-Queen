import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/core/http_util.dart';
import 'package:market_queen/pipeline/shot_planner.dart';
import 'package:market_queen/providers/text_providers.dart';
import 'package:market_queen/providers/types.dart';
import 'package:market_queen/providers/voice_providers.dart';

/// The words of a script, whitespace and layout thrown away. What the shot list
/// has to preserve exactly.
List<String> _words(String text) =>
    text.trim().isEmpty ? const [] : text.trim().split(RegExp(r'\s+'));

/// The scenario that produced the eight-shot run: nine written beats, but only
/// eight full stops, because the first one ends on an ellipsis.
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
  group('ShotPlanner', () {
    test('keeps every word of the scenario, in order', () {
      for (final script in [
        _scenario,
        'Une seule phrase.',
        'Un.\nDeux.\nTrois.',
        'Pas de ponctuation du tout ici',
      ]) {
        expect(
          _words(ShotPlanner.split(script).join(' ')),
          _words(script),
          reason: 'the shot list is a cut of the script, never a rewrite',
        );
      }
    });

    test('an ellipsis ends a thought only when a new one starts', () {
      // The bug that welded two written beats into one shot: "…" was not a
      // boundary at all, so the first beat never closed.
      expect(ShotPlanner.sentences('Marre du célibat… Genre vraiment.'), [
        'Marre du célibat…',
        'Genre vraiment.',
      ]);
      // And the over-correction: most ellipses in written UGC are a breath,
      // not a stop. Cutting here would hand the engine half a thought.
      expect(ShotPlanner.sentences('Bon… pourquoi pas ?'), [
        'Bon… pourquoi pas ?',
      ]);
      expect(ShotPlanner.sentences('Un. Deux.'), ['Un.', 'Deux.']);
    });

    test('a blank line is a cut, however short the beats are', () {
      expect(ShotPlanner.split('Un.\n\nDeux.\n\nTrois.'), [
        'Un.',
        'Deux.',
        'Trois.',
      ]);
    });

    test('short sentences inside one beat are packed into one shot', () {
      // Otherwise "Bon… pourquoi pas ?" buys a one-second clip of a shrug.
      expect(ShotPlanner.split('Un. Deux. Trois.'), ['Un. Deux. Trois.']);
    });

    test('a long beat is cut on sentence boundaries', () {
      const long = 'Un deux trois quatre cinq six sept huit neuf dix. '
          'Onze douze treize quatorze quinze seize dix-sept dix-huit.';
      expect(ShotPlanner.split(long), [
        'Un deux trois quatre cinq six sept huit neuf dix.',
        'Onze douze treize quatorze quinze seize dix-sept dix-huit.',
      ]);
    });

    test('a sentence is never cut in half, however long it runs', () {
      // Each shot's audio is recorded from its own line, so half a sentence
      // would be read as half a thought.
      const sentence = 'a b c d e f g h i j k l m n o p q r s t u v w x y z.';
      expect(ShotPlanner.split(sentence), [sentence]);
    });

    test('the shot list is exactly the beats the user wrote', () {
      // Nine paragraphs in, nine shots out, each one whole. This is the run
      // that used to come back as eight, with the hook welded to the line
      // after it.
      final beats = _scenario
          .split(RegExp(r'\n[ \t]*\n'))
          .map((beat) => beat.trim())
          .where((beat) => beat.isNotEmpty)
          .toList();

      expect(beats.length, 9);
      expect(ShotPlanner.split(_scenario), beats);
    });

    test('an empty scenario is no shots at all', () {
      expect(ShotPlanner.split('   \n\n  '), isEmpty);
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

  group('shot kinds', () {
    test('only an explicit product shot is one', () {
      expect(ScriptTask.shotKind('broll'), 'broll');
      expect(ScriptTask.shotKind('BRoll'), 'broll');
      expect(ScriptTask.shotKind('talking'), 'talking');
      expect(ScriptTask.shotKind('b-roll'), 'talking');
      expect(ScriptTask.shotKind(null), 'talking');
      expect(ScriptTask.shotKind(''), 'talking');
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
