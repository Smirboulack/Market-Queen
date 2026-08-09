import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';
import '../i18n/translator.dart';
import 'ad_project.dart';
import 'asset_library.dart';

/// One UGC ad, as the studio lists it: a name, two dates, and the document the
/// editor opens.
class AdEntry {
  AdEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    Map<String, Object?>? document,
  }) : document = document ?? <String, Object?>{};

  factory AdEntry.fromJson(Map<String, Object?> json) {
    final created =
        DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now();
    final document = json['document'];

    return AdEntry(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? created,
      document: document is Map ? document.cast<String, Object?>() : null,
    );
  }

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  Map<String, Object?> document;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'document': document,
  };
}

/// A folder of ads for one product, one client, one campaign -- whatever the
/// user decides a project is.
class StudioProject {
  StudioProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    List<AdEntry>? ads,
  }) : ads = ads ?? <AdEntry>[];

  factory StudioProject.fromJson(Map<String, Object?> json) {
    final created =
        DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now();
    final ads = json['ads'];

    return StudioProject(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      createdAt: created,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? created,
      ads: [
        if (ads is List)
          for (final entry in ads)
            if (entry is Map && '${entry['id'] ?? ''}'.isNotEmpty)
              AdEntry.fromJson(entry.cast<String, Object?>()),
      ],
    );
  }

  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<AdEntry> ads;

  AdEntry? ad(String adId) {
    for (final entry in ads) {
      if (entry.id == adId) return entry;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'ads': [for (final ad in ads) ad.toJson()],
  };
}

/// Everything the studio holds: the projects, their ads, and which one is open.
///
/// One file on disk, written 400ms after the last keystroke. The open ad lives
/// in [AdProject]; this class is what puts a document into it and takes the
/// edits back out, so nothing else in the app has to know that an ad is a row
/// in a tree rather than the only thing there is.
class Workspace extends ChangeNotifier {
  /// [_actors] is only reached for once, to rehouse the actor a pre-projects
  /// draft carried inline.
  Workspace(this._project, this._actors) {
    _load();
    _project.addListener(_onDocumentEdited);
  }

  static const _fileName = 'workspace.json';
  static const _schemaVersion = 1;

  // Long enough that a burst of keystrokes writes once, short enough that the
  // file on disk is never far behind what is on screen.
  static const _autosaveDelay = Duration(milliseconds: 400);

  final AdProject _project;

  final ActorLibrary _actors;

  final List<StudioProject> _projects = [];

  Timer? _autosave;
  bool _loading = false;

  List<StudioProject> get projects => List.unmodifiable(_projects);
  int get count => _projects.length;

  /// The ad the editor is on, or null when the studio is showing a list.
  String get openProjectId => _project.projectId;
  String get openAdId => _project.id;

  @override
  void dispose() {
    _autosave?.cancel();
    _project.removeListener(_onDocumentEdited);
    super.dispose();
  }

  // ---- Lookup ------------------------------------------------------------

  StudioProject? project(String id) {
    if (id.isEmpty) return null;
    for (final entry in _projects) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  AdEntry? ad(String projectId, String adId) => project(projectId)?.ad(adId);

  /// Newest first, which is how both lists are drawn.
  List<StudioProject> get byRecency {
    final sorted = List<StudioProject>.of(_projects)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  List<AdEntry> adsByRecency(String projectId) {
    final owner = project(projectId);
    if (owner == null) return const [];
    final sorted = List<AdEntry>.of(owner.ads)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  /// A name that is not taken yet, for the "New project" field to start from.
  String suggestedProjectName() => tr('Project %1').arg(_projects.length + 1);

  String suggestedAdName(String projectId) =>
      tr('Ad %1').arg((project(projectId)?.ads.length ?? 0) + 1);

  // ---- Structure ---------------------------------------------------------

  StudioProject createProject(String name) {
    final now = DateTime.now();
    final entry = StudioProject(
      id: _newId(),
      name: name.trim().isEmpty ? suggestedProjectName() : name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _projects.insert(0, entry);
    _changed();
    return entry;
  }

  void renameProject(String id, String name) {
    final entry = project(id);
    if (entry == null || name.trim().isEmpty || entry.name == name.trim()) {
      return;
    }
    entry.name = name.trim();
    entry.updatedAt = DateTime.now();
    _changed();
  }

  void removeProject(String id) {
    final index = _projects.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    // Closing first: the editor must not be left pointing at a deleted ad.
    if (_project.projectId == id) closeAd();
    _projects.removeAt(index);
    _changed();
  }

  AdEntry createAd(String projectId, String name) {
    final owner = project(projectId);
    if (owner == null) {
      throw StateError('No project $projectId');
    }

    final now = DateTime.now();
    final entry = AdEntry(
      id: _newId(),
      name: name.trim().isEmpty ? suggestedAdName(projectId) : name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    owner.ads.insert(0, entry);
    owner.updatedAt = now;
    _changed();
    return entry;
  }

  void renameAd(String projectId, String adId, String name) {
    final entry = ad(projectId, adId);
    if (entry == null || name.trim().isEmpty || entry.name == name.trim()) {
      return;
    }
    entry.name = name.trim();
    entry.updatedAt = DateTime.now();
    project(projectId)?.updatedAt = entry.updatedAt;
    if (_project.id == adId) _project.name = entry.name;
    _changed();
  }

  void removeAd(String projectId, String adId) {
    final owner = project(projectId);
    if (owner == null) return;
    final index = owner.ads.indexWhere((entry) => entry.id == adId);
    if (index < 0) return;
    if (_project.id == adId) closeAd();
    owner.ads.removeAt(index);
    owner.updatedAt = DateTime.now();
    _changed();
  }

  /// Duplicates an ad, document and all. The cheapest way to try a second angle
  /// on the same product.
  AdEntry? duplicateAd(String projectId, String adId) {
    final owner = project(projectId);
    final source = owner?.ad(adId);
    if (owner == null || source == null) return null;

    final now = DateTime.now();
    final copy = AdEntry(
      id: _newId(),
      //: %1 is the name of the ad being copied
      name: tr('%1 (copy)').arg(source.name),
      createdAt: now,
      updatedAt: now,
      document: jsonDecode(jsonEncode(source.document)) as Map<String, Object?>,
    );
    owner.ads.insert(0, copy);
    owner.updatedAt = now;
    _changed();
    return copy;
  }

  // ---- The open ad -------------------------------------------------------

  void openAd(String projectId, String adId) {
    final entry = ad(projectId, adId);
    if (entry == null) return;
    if (_project.id == adId && _project.projectId == projectId) return;

    _loading = true;
    _project.load(
      id: entry.id,
      projectId: projectId,
      name: entry.name,
      document: entry.document,
    );
    _loading = false;
    notifyListeners();
  }

  void closeAd() {
    if (_project.id.isEmpty) return;
    _syncDocument();
    _loading = true;
    _project.close();
    _loading = false;
    notifyListeners();
  }

  /// Copies the open document back into its row and schedules a save.
  ///
  /// No [notifyListeners] here: this runs on every keystroke, and the lists
  /// that would rebuild are not on screen while an ad is open.
  void _onDocumentEdited() {
    if (_loading) return;
    if (!_syncDocument()) return;
    _scheduleSave();
  }

  bool _syncDocument() {
    if (_project.id.isEmpty) return false;
    final owner = project(_project.projectId);
    final entry = owner?.ad(_project.id);
    if (owner == null || entry == null) return false;

    entry.document = _project.toJson();
    entry.updatedAt = DateTime.now();
    owner.updatedAt = entry.updatedAt;
    return true;
  }

  /// Called when an actor or a décor is deleted: no ad may point at one that is
  /// gone.
  void forgetAsset({String actorId = '', String decorId = ''}) {
    var changed = false;

    for (final owner in _projects) {
      for (final entry in owner.ads) {
        if (entry.id == _project.id) continue;

        final actors = entry.document['actorIds'];
        if (actorId.isNotEmpty && actors is List && actors.contains(actorId)) {
          entry.document['actorIds'] = [
            for (final id in actors)
              if ('$id' != actorId) '$id',
          ];
          changed = true;
        }
        if (decorId.isNotEmpty && '${entry.document['decorId'] ?? ''}' == decorId) {
          entry.document['decorId'] = '';
          changed = true;
        }
      }
    }

    _project.forget(actorId: actorId, decorId: decorId);
    if (changed) _changed();
  }

  // ---- Persistence -------------------------------------------------------

  String get _storeFile => p.join(Paths.configDir, _fileName);

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (_loading) return;
    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, save);
  }

  void save() {
    if (Paths.ensureDir(Paths.configDir).isEmpty) return;

    final root = {
      'schemaVersion': _schemaVersion,
      'projects': [for (final entry in _projects) entry.toJson()],
    };

    try {
      File(_storeFile).writeAsStringSync(
        const JsonEncoder.withIndent('    ').convert(root),
      );
    } on FileSystemException {
      // The next edit tries again.
    }
  }

  void _load() {
    final file = File(_storeFile);
    if (!file.existsSync()) {
      _importOldDraft();
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Exception {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    final saved = decoded['projects'];
    if (saved is! List) return;

    _loading = true;
    _projects
      ..clear()
      ..addAll([
        for (final entry in saved)
          if (entry is Map && '${entry['id'] ?? ''}'.isNotEmpty)
            StudioProject.fromJson(entry.cast<String, Object?>()),
      ]);
    _loading = false;
  }

  /// Brings across the single draft older builds kept.
  ///
  /// There was one ad and no projects, so it lands as one project holding one
  /// ad. The actor it carried was inline; it is saved into the actor library on
  /// the way through, which is where actors live now.
  void _importOldDraft() {
    final file = File(p.join(Paths.configDir, 'draft.json'));
    if (!file.existsSync()) return;

    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Exception {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded.isEmpty) return;

    final product = decoded['product'];
    final productMap = product is Map
        ? product.cast<String, Object?>()
        : <String, Object?>{};

    // The words: whatever the old scene list said, joined, or the plain script
    // a draft older still would have carried.
    final scenes = decoded['scenes'];
    final lines = <String>[
      if (scenes is List)
        for (final scene in scenes)
          if (scene is Map && '${scene['line'] ?? ''}'.trim().isNotEmpty)
            '${scene['line']}'.trim(),
    ];
    final script = lines.isEmpty ? '${decoded['script'] ?? ''}' : lines.join(' ');

    final images = productMap.remove('images');

    final actorIds = <String>[];
    final actor = decoded['actor'];
    if (actor is Map) {
      final saved = LibraryAsset.fromJson(actor.cast<String, Object?>());
      if (!saved.isEmpty) {
        if (saved.name.trim().isEmpty) saved.name = _actors.suggestedName();
        actorIds.add(_actors.save(saved));
      }
    }

    final now = DateTime.now();
    final entry = AdEntry(
      id: _newId(),
      name: tr('Ad 1'),
      createdAt: now,
      updatedAt: now,
      document: {
        'product': productMap,
        'media': [
          if (images is List)
            for (final image in images) '$image',
        ],
        'actorIds': actorIds,
        'decorId': '',
        'script': script,
        'aspectRatio': '${decoded['aspectRatio'] ?? '9:16'}',
        'captions': decoded['captions'] != false,
        'maxSeconds': (decoded['targetSeconds'] as num?)?.toInt() ?? 0,
      },
    );

    _projects.add(
      StudioProject(
        id: _newId(),
        name: tr('My first project'),
        createdAt: now,
        updatedAt: now,
        ads: [entry],
      ),
    );

    save();
  }

  static int _counter = 0;

  static String _newId() {
    _counter += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '${stamp.substring(stamp.length - 6)}$_counter';
  }
}
