import 'package:flutter/foundation.dart';

/// What a generation produced. The canvas draws each kind differently -- a
/// still shows itself, a clip shows a poster and a play badge, an ad shows the
/// cut with a way through to its render detail.
enum CanvasKind { image, video, ad, audio }

/// Where one result is in its life.
///
/// [pending] is the interesting one: it is what the skeleton tiles are drawn
/// from, and it is why a batch is written into the feed *before* the first
/// request leaves rather than after the last one lands. The canvas is the
/// progress indicator now; there is no separate loading screen to go to.
enum CanvasStatus { pending, done, failed }

/// One result: a file on disk, or the promise of one.
class CanvasItem {
  CanvasItem({
    required this.id,
    this.status = CanvasStatus.pending,
    this.path = '',
    this.error = '',
    this.seconds = 0,
  });

  factory CanvasItem.fromJson(Map<String, Object?> json) => CanvasItem(
    id: '${json['id'] ?? ''}',
    status: _statusFrom('${json['status'] ?? ''}'),
    path: '${json['path'] ?? ''}',
    error: '${json['error'] ?? ''}',
    seconds: (json['seconds'] as num?)?.toDouble() ?? 0,
  );

  final String id;
  CanvasStatus status;
  String path;
  String error;

  /// Clips only: how long the file runs, when the provider said so.
  double seconds;

  /// A pending item reopened from disk is a lie -- the request that would have
  /// filled it died with the process. Anything still pending when the document
  /// is read back is restored as a failure instead.
  static CanvasStatus _statusFrom(String value) => switch (value) {
    'done' => CanvasStatus.done,
    _ => CanvasStatus.failed,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'status': status.name,
    'path': path,
    'error': error,
    if (seconds > 0) 'seconds': seconds,
  };
}

/// Everything one press of the send button produced.
///
/// A batch, not a message: asking for ten images is one act with ten outcomes,
/// and drawing them as ten separate entries in the feed would bury the prompt
/// they all came from.
class CanvasBatch {
  CanvasBatch({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.createdAt,
    this.modelLabel = '',
    this.aspectRatio = '',
    this.references = const [],
    List<CanvasItem>? items,
  }) : items = items ?? <CanvasItem>[];

  factory CanvasBatch.fromJson(Map<String, Object?> json) {
    final items = json['items'];
    final references = json['references'];

    return CanvasBatch(
      id: '${json['id'] ?? ''}',
      kind: _kindFrom('${json['kind'] ?? ''}'),
      prompt: '${json['prompt'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
      modelLabel: '${json['modelLabel'] ?? ''}',
      aspectRatio: '${json['aspectRatio'] ?? ''}',
      references: [
        if (references is List)
          for (final entry in references) '$entry',
      ],
      items: [
        if (items is List)
          for (final entry in items)
            if (entry is Map) CanvasItem.fromJson(entry.cast<String, Object?>()),
      ],
    );
  }

  final String id;
  final CanvasKind kind;
  final String prompt;
  final DateTime createdAt;

  /// Readable, not the model id: the feed is a record of what you asked for,
  /// and "Nano Banana Pro" is what you asked for.
  final String modelLabel;

  final String aspectRatio;

  /// The pictures and clips that were in the bar when this was sent.
  final List<String> references;

  final List<CanvasItem> items;

  static CanvasKind _kindFrom(String value) => switch (value) {
    'video' => CanvasKind.video,
    'ad' => CanvasKind.ad,
    'audio' => CanvasKind.audio,
    _ => CanvasKind.image,
  };

  bool get running => items.any((item) => item.status == CanvasStatus.pending);

  List<CanvasItem> get delivered => [
    for (final item in items)
      if (item.status == CanvasStatus.done) item,
  ];

  /// Every request came back empty-handed. The batch then shows its reason
  /// instead of a row of broken tiles.
  bool get allFailed =>
      items.isNotEmpty &&
      items.every((item) => item.status == CanvasStatus.failed);

  /// The first thing that went wrong, which for a batch of identical requests
  /// is almost always what went wrong with all of them.
  String get firstError {
    for (final item in items) {
      if (item.error.isNotEmpty) return item.error;
    }
    return '';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'prompt': prompt,
    'createdAt': createdAt.toIso8601String(),
    'modelLabel': modelLabel,
    'aspectRatio': aspectRatio,
    'references': references,
    'items': [for (final item in items) item.toJson()],
  };
}

/// The canvas, as data: every batch this ad has produced, oldest first.
///
/// It belongs to the ad rather than to the session -- reopening a spot a week
/// later has to give back what was made in it, the same way reopening a
/// document gives back the document. The workspace writes it into the ad's
/// JSON along with everything else.
class CanvasFeed extends ChangeNotifier {
  final List<CanvasBatch> _batches = [];

  List<CanvasBatch> get batches => List.unmodifiable(_batches);

  bool get isEmpty => _batches.isEmpty;

  /// Whether anything at all is still out. The composer disables nothing on the
  /// strength of it -- a second batch may be sent while the first is running --
  /// but the window title and the send glyph read it.
  bool get running => _batches.any((batch) => batch.running);

  CanvasBatch? byId(String id) {
    for (final batch in _batches) {
      if (batch.id == id) return batch;
    }
    return null;
  }

  void add(CanvasBatch batch) {
    _batches.add(batch);
    notifyListeners();
  }

  void remove(String batchId) {
    final before = _batches.length;
    _batches.removeWhere((batch) => batch.id == batchId);
    if (_batches.length != before) notifyListeners();
  }

  /// Takes one result off the canvas.
  ///
  /// The unit the user acts on is the tile, not the press of send that produced
  /// it: asking for four pictures and wanting to be rid of the third is the
  /// ordinary case. A batch left with nothing in it goes too -- an empty row
  /// under a prompt is not a record of anything.
  ///
  /// The file on disk is left alone. Everything here is already saved, and the
  /// canvas is a view of what was made rather than the only copy of it.
  void removeItem(String batchId, String itemId) {
    final batch = byId(batchId);
    if (batch == null) return;

    final before = batch.items.length;
    batch.items.removeWhere((item) => item.id == itemId);
    if (batch.items.length == before) return;

    if (batch.items.isEmpty) {
      _batches.remove(batch);
    }
    notifyListeners();
  }

  void clear() {
    if (_batches.isEmpty) return;
    _batches.clear();
    notifyListeners();
  }

  /// Called by the runner as each request lands. Notifying on every one is the
  /// point: a batch of ten fills in tile by tile rather than all at once at the
  /// end, which is the difference between watching something work and watching
  /// a spinner.
  void settle(
    String batchId,
    String itemId, {
    required CanvasStatus status,
    String path = '',
    String error = '',
    double seconds = 0,
  }) {
    final batch = byId(batchId);
    if (batch == null) return;

    for (final item in batch.items) {
      if (item.id != itemId) continue;
      item
        ..status = status
        ..path = path
        ..error = error
        ..seconds = seconds;
      notifyListeners();
      return;
    }
  }

  // ---- Document ----------------------------------------------------------

  List<Map<String, Object?>> toJson() => [
    for (final batch in _batches) batch.toJson(),
  ];

  void load(Object? saved) {
    _batches.clear();
    if (saved is List) {
      for (final entry in saved) {
        if (entry is Map) {
          _batches.add(CanvasBatch.fromJson(entry.cast<String, Object?>()));
        }
      }
    }
    notifyListeners();
  }

  static int _counter = 0;

  /// Ids only have to be unique inside one ad, and they are generated far apart
  /// in time, so the clock plus a counter is enough.
  static String newId() {
    _counter += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '${stamp.substring(stamp.length - 6)}$_counter';
  }
}
