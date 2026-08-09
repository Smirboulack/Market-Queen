import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class LanguageInfo {
  const LanguageInfo(this.code, this.label, this.englishLabel, this.rightToLeft);

  /// ISO code, "" meaning "follow the system".
  final String code;

  /// Written in the language itself.
  final String label;
  final String englishLabel;
  final bool rightToLeft;
}

/// Loads the translation maps and switches the whole UI at runtime.
///
/// The catalogues are the same flat `"english source": "translation"` JSON the
/// Qt build shipped -- much easier to review than Qt's XML, and now read
/// directly instead of being compiled into .qm files first. Arabic also flips
/// the layout direction.
class Translator extends ChangeNotifier {
  // Keep in sync with the files under assets/i18n.
  static const languages = <LanguageInfo>[
    LanguageInfo('en', 'English', 'English', false),
    LanguageInfo('fr', 'Français', 'French', false),
    LanguageInfo('es', 'Español', 'Spanish', false),
    LanguageInfo('de', 'Deutsch', 'German', false),
    LanguageInfo('it', 'Italiano', 'Italian', false),
    LanguageInfo('pt', 'Português', 'Portuguese', false),
    LanguageInfo('nl', 'Nederlands', 'Dutch', false),
    LanguageInfo('pl', 'Polski', 'Polish', false),
    LanguageInfo('ru', 'Русский', 'Russian', false),
    LanguageInfo('zh', '中文', 'Chinese (Simplified)', false),
    LanguageInfo('ar', 'العربية', 'Arabic', true),
  ];

  /// The one instance the `tr()` helper reads. Set once, at startup.
  static Translator instance = Translator();

  Map<String, String> _catalogue = const {};
  String _current = 'en';

  String get currentLanguage => _current;

  /// Endonym of the active language ("Français"), used as the default target
  /// language for the generated script.
  String get currentLabel => _find(_current)?.label ?? 'English';

  bool get rightToLeft => _find(_current)?.rightToLeft ?? false;

  static LanguageInfo? _find(String code) {
    for (final language in languages) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// An empty code picks the closest match for the system locale.
  Future<void> applyLanguage(String code) async {
    final target = code.isEmpty ? _resolveSystemLanguage() : code;
    if (_find(target) == null) return;

    // English is the source language: there is no catalogue to load.
    if (target == 'en') {
      _catalogue = const {};
    } else {
      try {
        final raw = await rootBundle.loadString('assets/i18n/$target.json');
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _catalogue = decoded.map((key, value) => MapEntry(key, '$value'));
      } on Exception {
        // A missing or broken catalogue leaves the UI in English rather than
        // half-translated.
        _catalogue = const {};
      }
    }

    _current = target;
    notifyListeners();
  }

  /// The translation of [source], or [source] itself when there is none.
  String translate(String source) => _catalogue[source] ?? source;

  static String _resolveSystemLanguage() {
    final locales = <String>[
      for (final locale in PlatformDispatcher.instance.locales) locale.languageCode,
      Platform.localeName,
    ];
    for (final tag in locales) {
      // "fr-CA" and "fr" both map to our "fr" catalogue.
      final base = tag.split(RegExp('[-_]')).first.toLowerCase();
      if (_find(base) != null) return base;
    }
    return 'en';
  }
}

/// Translate a source string. The literal passed here is the catalogue key, so
/// it must match `i18n/<lang>.json` exactly -- the same contract `qsTr()` had.
String tr(String source) => Translator.instance.translate(source);

extension TrArgs on String {
  /// Qt's `QString::arg`: substitutes the lowest-numbered `%n` still present,
  /// so chained calls fill the placeholders in order regardless of where they
  /// appear in the translated sentence.
  String arg(Object? value) {
    final matches = RegExp(r'%(\d+)').allMatches(this);
    if (matches.isEmpty) return this;

    var lowest = 1 << 30;
    for (final match in matches) {
      final index = int.parse(match.group(1)!);
      if (index < lowest) lowest = index;
    }
    return replaceAll('%$lowest', '$value');
  }
}
