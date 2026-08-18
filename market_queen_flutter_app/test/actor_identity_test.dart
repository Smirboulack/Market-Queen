import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/models/asset_library.dart';

import 'support/sandbox.dart';

/// How old an actor is, and who they read as, are facts about the person.
///
/// They used to be the voice's: an actor's age *was* `voiceAge`, one of the three
/// bands ElevenLabs sorts its library into, and their gender was `voiceGender`,
/// which is a search filter. So changing who read the ad changed how old the
/// actor was, and a woman of 22 and a woman of 29 were the same fact.
///
/// The two are separate now, and the direction of the remaining link is the whole
/// point: the person decides which voices are worth looking at, never the other
/// way round.
void main() {
  useSandboxConfig();

  LibraryAsset actor() => LibraryAsset(name: 'Sarah');

  group('the personality decides the read', () {
    // It used to decide the script and the frame and nothing else, so an actor
    // set to survoltée was read at exactly the same four values as a calm one
    // and the only way to find out was to listen to both.
    LibraryAsset energetic() {
      final sarah = actor();
      ActorPersona.setTraits(sarah, ['gen-z', 'playful']);
      sarah.setExtra(ActorPersona.energyKey, 1.0);
      return sarah;
    }

    LibraryAsset calm() {
      final max = LibraryAsset(name: 'Max');
      ActorPersona.setTraits(max, ['professional']);
      max.setExtra(ActorPersona.energyKey, 0.0);
      return max;
    }

    test('energy pulls stability down and expression up', () {
      final loud = ActorPersona.performanceOf(energetic());
      final quiet = ActorPersona.performanceOf(calm());

      // Stability runs backwards: low is expressive.
      expect(loud.stability, lessThan(quiet.stability));
      expect(loud.style, greaterThan(quiet.style));
      expect(loud.speed, greaterThan(quiet.speed));
    });

    test('an energetic actor lands where delivery tags are honoured', () {
      // Eleven v3 snaps stability to Creative / Natural / Robust, and only the
      // first two respond to tags at all. A survoltée actor has to reach
      // Creative or step 2 of this is bought and thrown away.
      final loud = ActorPersona.performanceOf(energetic());
      expect(loud.stability, lessThan(0.25));
    });

    test('an actor with no personality is read as they always were', () {
      expect(ActorPersona.performanceOf(actor()).stability,
          VoicePerformance.neutral.stability);
      expect(ActorPersona.performanceOf(actor()).style,
          VoicePerformance.neutral.style);
    });

    test('the dials are a starting point, not a lock', () {
      final sarah = energetic();
      expect(ActorPersona.followsPersona(sarah), isTrue);
      expect(ActorPersona.dialOf(sarah, 'voiceStyle', 0.35),
          ActorPersona.performanceOf(sarah).style);

      // What moving a slider does: the values are written down as they stood
      // and the actor stops following.
      sarah
        ..setExtra('voiceStyle', 0.2)
        ..setExtra(ActorPersona.followsKey, false);

      expect(ActorPersona.dialOf(sarah, 'voiceStyle', 0.35), 0.2);
    });

    test('the personality also says how they move', () {
      // The other half. It has to be its own sentence rather than the persona
      // brief pasted in: "Playful, Gen-Z, high energy" means something to a
      // script writer and nothing to a model animating a photograph.
      final loud = ActorPersona.movementOf(energetic());

      expect(loud, contains('lively'));
      expect(loud, isNot(contains('Gen-Z')));
      expect(ActorPersona.movementOf(calm()), contains('composed'));

      // An actor nobody described is given no direction rather than a made-up
      // one, so the model falls back on its own default.
      expect(ActorPersona.movementOf(actor()), isEmpty);
    });

    test('a motion typed by hand has the last word', () {
      final sarah = energetic()
        ..setExtra(ActorPersona.actionKey, 'Holds a coffee cup.');

      final motion = ActorPersona.motionOf(sarah);
      expect(motion, contains('lively'));
      expect(motion, endsWith('Holds a coffee cup.'));
    });

    test('the four defaults every actor was saved with are not a choice', () {
      // Every actor ever created was written out with 0.45 / 0.8 / 0.35 / 1.0
      // in their extras, so "untouched" cannot be read off the values. The flag
      // is what separates them, and its absence means following.
      final sarah = energetic()
        ..setExtra('voiceStability', 0.45)
        ..setExtra('voiceStyle', 0.35);

      expect(ActorPersona.followsPersona(sarah), isTrue);
      expect(ActorPersona.dialOf(sarah, 'voiceStability', 0.45),
          isNot(0.45));
    });
  });

  test('an age is a number of years, not a band', () {
    final sarah = actor();
    ActorIdentity.setAge(sarah, 22);

    expect(ActorIdentity.ageOf(sarah), 22);
    // A number that survives a round trip through the store's own shape.
    expect(ActorIdentity.ageOf(sarah.copy()), 22);
  });

  test('the voice band is worked out from the age, not stored beside it', () {
    final sarah = actor();

    ActorIdentity.setAge(sarah, 22);
    expect(ActorIdentity.bandOf(sarah), 'young');

    ActorIdentity.setAge(sarah, 38);
    expect(ActorIdentity.bandOf(sarah), 'middle_aged');

    ActorIdentity.setAge(sarah, 61);
    expect(ActorIdentity.bandOf(sarah), 'old');
  });

  test('changing the voice leaves the person alone', () {
    final sarah = actor();
    ActorIdentity.setAge(sarah, 22);
    ActorIdentity.setGender(sarah, 'female');

    // What picking a voice out of the library writes.
    sarah
      ..setExtra('voiceId', 'abc')
      ..setExtra('voiceName', 'Camille')
      ..setExtra('voiceGender', 'male')
      ..setExtra('voiceAge', 'old');

    expect(ActorIdentity.ageOf(sarah), 22);
    expect(ActorIdentity.genderOf(sarah), 'female');
    expect(ActorIdentity.bandOf(sarah), 'young');
  });

  test('an actor saved before the split still reports something', () {
    // All they carry is the voice's brief, and it is a better answer than
    // "not set" -- so both accessors fall back to it until somebody sets a
    // number.
    final old = actor()
      ..setExtra('voiceGender', 'female')
      ..setExtra('voiceAge', 'middle_aged');

    expect(ActorIdentity.ageOf(old), 0);
    expect(ActorIdentity.genderOf(old), 'female');
    expect(ActorIdentity.bandOf(old), 'middle_aged');

    // And the moment a real age is set, it wins.
    ActorIdentity.setAge(old, 24);
    expect(ActorIdentity.bandOf(old), 'young');
  });

  test('an age can be taken back off', () {
    final sarah = actor();
    ActorIdentity.setAge(sarah, 30);
    ActorIdentity.setAge(sarah, 0);

    expect(ActorIdentity.ageOf(sarah), 0);
    expect(sarah.extras.containsKey(ActorIdentity.ageKey), isFalse);
  });
}
