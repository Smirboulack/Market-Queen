import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../core/settings_store.dart';

class LibraryProject {
  LibraryProject({
    required this.folderName,
    required this.productName,
    required this.hook,
    required this.createdAt,
    required this.dir,
    required this.finalVideo,
    required this.thumbnail,
    required this.success,
    required this.cost,
    required this.hasCost,
  });

  final String folderName;
  final String productName;
  final String hook;
  final String createdAt;
  final String dir;
  final String finalVideo;
  final String thumbnail;
  final bool success;
  final double cost;
  final bool hasCost;
}

/// Every run leaves a folder behind with a project.json manifest; the library is
/// just a listing of those folders, newest first.
class LibraryModel extends ChangeNotifier {
  LibraryModel(this._settings) {
    _settings.addListener(_onSettingsChanged);
    refresh();
  }

  final SettingsStore _settings;
  final List<LibraryProject> _projects = [];

  String _watchedDir = '';

  List<LibraryProject> get projects => List.unmodifiable(_projects);
  int get count => _projects.length;

  /// What every listed project cost, added up. Projects written before costs
  /// were recorded contribute nothing.
  double get totalCost =>
      _projects.fold(0.0, (total, project) => total + project.cost);

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (_settings.projectsDir == _watchedDir) return;
    refresh();
  }

  void refresh() {
    _watchedDir = _settings.projectsDir;
    _projects.clear();

    final root = Directory(_watchedDir);
    if (root.existsSync()) {
      final folders = root
          .listSync()
          .whereType<Directory>()
          .toList()
        // Newest first: the folder names start with a timestamp.
        ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));

      for (final folder in folders) {
        final project = _read(folder);
        if (project != null) _projects.add(project);
      }
    }

    notifyListeners();
  }

  LibraryProject? _read(Directory folder) {
    final manifestFile = File(p.join(folder.path, 'project.json'));
    if (!manifestFile.existsSync()) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(manifestFile.readAsStringSync());
    } on Exception {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    // Absent in projects made before costs were recorded: show nothing rather
    // than a confident "$0".
    var cost = 0.0;
    var hasCost = false;
    final costEntry = decoded['cost'];
    if (costEntry is Map) {
      cost = (costEntry['total'] as num?)?.toDouble() ?? 0.0;
      final lines = costEntry['lines'];
      hasCost = lines is List && lines.isNotEmpty;
    }

    final created = DateTime.tryParse('${decoded['createdAt'] ?? ''}') ??
        folder.statSync().changed;

    String resolve(Object? relative) {
      final value = '${relative ?? ''}';
      if (value.isEmpty) return '';
      final full = p.join(folder.path, value);
      return File(full).existsSync() ? full : '';
    }

    return LibraryProject(
      folderName: p.basename(folder.path),
      dir: folder.path,
      productName: '${decoded['productName'] ?? ''}',
      hook: '${decoded['hook'] ?? ''}',
      success: decoded['success'] == true,
      cost: cost,
      hasCost: hasCost,
      createdAt: DateFormat('d MMM yyyy, HH:mm').format(created),
      finalVideo: resolve(decoded['final']),
      thumbnail: resolve(decoded['frame']),
    );
  }
}
