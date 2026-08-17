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
