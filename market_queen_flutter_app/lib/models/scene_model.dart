import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/signal.dart';

/// One scene: a line, what kind of shot it is, and the visuals for it.
class Scene {
  Scene({
    required this.id,
    this.line = '',
    this.kind = 'talking',
    this.imagePrompt = '',
    this.videoPrompt = '',
  });

  factory Scene.fromJson(Map<String, Object?> json) => Scene(
        id: '${json['id'] ?? _newId()}',
        line: '${json['line'] ?? ''}',
        kind: '${json['kind'] ?? 'talking'}',
        imagePrompt: '${json['imagePrompt'] ?? ''}',
        videoPrompt: '${json['videoPrompt'] ?? ''}',
      );

  final String id;
  String line;

  /// "talking" | "broll".
  String kind;
  String imagePrompt;
  String videoPrompt;

  /// Whether this scene has visual prompts yet.
  bool get directed => imagePrompt.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
        'id': id,
        'line': line,
        'kind': kind,
        'imagePrompt': imagePrompt,
        'videoPrompt': videoPrompt,
      };

  static int _counter = 0;

  static String _newId() {
    _counter += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '${stamp.substring(math.max(0, stamp.length - 6))}$_counter';
  }
}

/// The ad's scenes.
///
/// Rows carry a stable [Scene.id] so the widget list can key its delegates:
/// editing one line must not rebuild -- and so unfocus -- the field being typed
/// into. That was the reason this was a QAbstractListModel rather than a plain
/// list property, and it is still the reason now.
class SceneModel extends ChangeNotifier {
  // The same figure the pipeline plans against, so what the editor shows and
  // what the ad runs to are one number.
  static const _wordsPerSecond = 2.6;

  final List<Scene> _scenes = [];

  /// Any edit at all, including visual prompts: what the draft has to save.
  final Signal dirtied = Signal();

  List<Scene> get scenes => List.unmodifiable(_scenes);
  int get count => _scenes.length;

  static int _wordCount(String text) =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  void add([String line = '']) {
    _scenes.add(Scene(id: Scene._newId(), line: line));
    notifyListeners();
    dirtied.emit();
  }

  void remove(int row) {
    if (row < 0 || row >= _scenes.length) return;
    _scenes.removeAt(row);
    notifyListeners();
    dirtied.emit();
  }

  void move(int from, int to) {
    if (from < 0 || from >= _scenes.length) return;
    if (to < 0 || to >= _scenes.length || from == to) return;
    _scenes.insert(to, _scenes.removeAt(from));
    notifyListeners();
    dirtied.emit();
  }

  void setField(int row, String key, Object? value) {
    if (row < 0 || row >= _scenes.length) return;
    final scene = _scenes[row];

    switch (key) {
      case 'line':
        if (scene.line == value) return;
        scene.line = '$value';
      case 'kind':
        if (scene.kind == value) return;
        scene.kind = '$value';
      case 'imagePrompt':
        if (scene.imagePrompt == value) return;
        scene.imagePrompt = '$value';
      case 'videoPrompt':
        if (scene.videoPrompt == value) return;
        scene.videoPrompt = '$value';
      default:
        return;
    }

    notifyListeners();
    dirtied.emit();
  }

  /// Applies a director's answer positionally, leaving every line untouched.
  ///
  /// Only as far as both lists reach: a short answer must not shift everyone's
  /// visuals up by one.
  void applyDirection(List<Map<String, Object?>> shots) {
    final count = math.min(shots.length, _scenes.length);
    for (var i = 0; i < count; ++i) {
      _scenes[i].imagePrompt = '${shots[i]['imagePrompt'] ?? ''}'.trim();
      _scenes[i].videoPrompt = '${shots[i]['videoPrompt'] ?? ''}'.trim();
    }
    if (count > 0) {
      notifyListeners();
      dirtied.emit();
    }
  }

  /// How long this line takes to say.
  double seconds(int row) {
    if (row < 0 || row >= _scenes.length) return 0.0;
    return _wordCount(_scenes[row].line) / _wordsPerSecond;
  }

  double get totalSeconds {
    var total = 0.0;
    for (var row = 0; row < _scenes.length; ++row) {
      total += seconds(row);
    }
    return total;
  }

  bool get hasSpokenLine =>
      _scenes.any((scene) => scene.line.trim().isNotEmpty);

  /// Every line, joined: what the voice-over says in one take.
  String get spokenScript => _scenes
      .map((scene) => scene.line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ');

  List<Map<String, Object?>> toList() =>
      [for (final scene in _scenes) scene.toJson()];

  void setList(List<Object?> scenes) {
    _scenes
      ..clear()
      ..addAll([
        for (final entry in scenes)
          if (entry is Map) Scene.fromJson(entry.cast<String, Object?>()),
      ]);
    notifyListeners();
  }
}
