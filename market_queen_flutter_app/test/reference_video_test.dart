import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:market_queen/providers/fal_schema.dart';
import 'package:market_queen/providers/registry.dart';
import 'package:market_queen/providers/types.dart';

/// Trimmed from the real Seedance 2.5 reference-to-video schema, keeping the
/// two shapes that have to be told apart: the plural inputs it does take, and
/// a singular `audio_url` it does not -- lip-sync models declare one of those,
/// and mistaking it for a list is a rejected request.
String get _referenceSchema => jsonEncode({
      'components': {
        'schemas': {
          'Seedance25ReferenceToVideoInput': {
            'properties': {
              'prompt': {'type': 'string'},
              'image_urls': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'video_urls': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'audio_urls': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'audio_url': {'type': 'string'},
              'resolution': {
                'type': 'string',
                'default': '720p',
                'enum': ['480p', '720p'],
              },
              'duration': {
                'type': 'string',
                'default': 'auto',
                'enum': ['auto', '4', '5', '10', '30'],
              },
              'aspect_ratio': {
                'type': 'string',
                'enum': ['auto', '16:9', '9:16'],
              },
              'generate_audio': {'type': 'boolean', 'default': true},
            },
          },
        },
      },
    });

/// An ordinary image-to-video endpoint, for the negative case.
String get _firstFrameSchema => jsonEncode({
      'components': {
        'schemas': {
          'KlingInput': {
            'properties': {
              'prompt': {'type': 'string'},
              'start_image_url': {'type': 'string'},
              'duration': {
                'type': 'string',
                'enum': ['5', '10'],
              },
            },
          },
        },
      },
    });

void main() {
  group('schema', () {
    test('a reference endpoint is read as lists, not as a first frame', () {
      final caps = FalSchemas.parseSchema(_referenceSchema)!;

      expect(caps.takesReferences, isTrue);
      expect(caps.imagesField, 'image_urls');
      expect(caps.videosField, 'video_urls');
      expect(caps.audiosField, 'audio_urls');

      // It has no opening frame at all. Sending one would be a field the
      // endpoint never declared.
      expect(caps.imageField, isEmpty);

      // And the ordinary options still come through.
      expect(caps.resolutions, ['480p', '720p']);
      expect(caps.durationFor(30), '30');
      expect(caps.audioField, 'generate_audio');
    });

    test('an image-to-video endpoint takes no references', () {
      final caps = FalSchemas.parseSchema(_firstFrameSchema)!;

      expect(caps.takesReferences, isFalse);
      expect(caps.imageField, 'start_image_url');
    });

    test('the cache is dropped when the reader learns a new field', () {
      // A cache written before the plural fields existed carries no version and
      // must not be trusted, or a reference model reads as an ordinary one for
      // a fortnight.
      final fresh = FalSchemas.parseSchema(_referenceSchema)!.toJson();
      expect(fresh['v'], FalCapabilities.cacheVersion);
      expect(fresh['videosField'], 'video_urls');
    });
  });

  group('references', () {
    test('only the declared, non-empty lists are sent', () {
      const refs = VideoReferences(
        images: ['https://cdn/face.png'],
        videos: ['https://cdn/ad.mp4'],
        imagesField: 'image_urls',
        videosField: 'video_urls',
        // The model has no audio list, so the empty one must not appear as
        // `null: []` or under a guessed name.
        audiosField: '',
      );

      expect(refs.toInput(), {
        'image_urls': ['https://cdn/face.png'],
        'video_urls': ['https://cdn/ad.mp4'],
      });
      expect(refs.isEmpty, isFalse);
      expect(VideoReferences.none.isEmpty, isTrue);
    });

    test('the handles are numbered per modality, images first', () {
      const refs = VideoReferences(
        images: ['a', 'b'],
        videos: ['c'],
        audios: ['d'],
      );
      expect(refs.handles, ['@Image1', '@Image2', '@Video1', '@Audio1']);
    });
  });

  group('catalogue', () {
    final registry = Registry();

    test('the reference models are offered', () {
      final ids = [
        for (final model in registry.provider('fal-video')!.models) model.id,
      ];
      expect(ids, contains('bytedance/seedance-2.5/reference-to-video'));
    });

    test('but Auto never picks one', () {
      // "Auto" takes the head of the list, and a reference model with nothing
      // dropped in is a guaranteed failure. It has to be chosen deliberately.
      for (final seconds in [5, 10, 30]) {
        expect(
          registry.resolveModel('fal-video', 'auto', seconds),
          isNot(contains('reference-to-video')),
        );
      }
    });
  });
}
