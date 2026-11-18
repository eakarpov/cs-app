import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/dictionary/domain/models.dart';

abstract interface class PreferencesStore {
  Future<String?> read();
  Future<void> write(String value);
}

class DevicePreferences implements PreferencesStore {
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => preferences.getString('personal-v1');
  @override
  Future<void> write(String value) =>
      preferences.setString('personal-v1', value);
}

class PersonalStore extends ChangeNotifier {
  PersonalStore(this.preferences) {
    initialized = _load();
  }
  final PreferencesStore preferences;
  late final Future<void> initialized;
  bool _readFailed = false;
  bool ready = false;
  bool get canEdit => ready && !_readFailed;
  bool _reading = false;
  String? error;
  List<SavedWord> favorites = [], history = [];
  ThemeMode themeMode = ThemeMode.system;
  double fontSize = 22;
  bool highlightEndings = true, showProposed = true;
  Future<void> _tail = Future.value();
  Future<void> retryPersistence() => _readFailed ? _load() : _save();
  Future<void> _load() async {
    if (_reading) return;
    _reading = true;
    ready = false;
    _readFailed = true;
    error = null;
    notifyListeners();
    try {
      final raw = await preferences.read();
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        final j = decoded;
        if (j['version'] != null && j['version'] != 1) {
          throw const FormatException();
        }
        for (final key in ['favorites', 'history']) {
          final values = j[key];
          if (values != null &&
              (values is! List ||
                  values.any(
                    (v) =>
                        v is! Map ||
                        v['id'] is! String ||
                        (v['id'] as String).isEmpty ||
                        v['name'] is! String,
                  ))) {
            throw const FormatException();
          }
        }
        if (j['fontSize'] != null &&
                (j['fontSize'] is! num || !(j['fontSize'] as num).isFinite) ||
            j['theme'] != null && j['theme'] is! String ||
            j['highlightEndings'] != null && j['highlightEndings'] is! bool ||
            j['showProposed'] != null && j['showProposed'] is! bool) {
          throw const FormatException();
        }
        favorites = array(j['favorites'])
            .map((v) => SavedWord.fromJson(object(v)))
            .where((w) => w.id.isNotEmpty)
            .toList();
        history = array(j['history'])
            .map((v) => SavedWord.fromJson(object(v)))
            .where((w) => w.id.isNotEmpty)
            .take(100)
            .toList();
        fontSize =
            (j['fontSize'] is num ? (j['fontSize'] as num).toDouble() : 22.0)
                .clamp(16.0, 36.0);
        themeMode = ThemeMode.values.firstWhere(
          (v) => v.name == j['theme'],
          orElse: () => ThemeMode.system,
        );
        highlightEndings = j['highlightEndings'] != false;
        showProposed = j['showProposed'] != false;
      }
      _readFailed = false;
    } catch (_) {
      _readFailed = true;
      error =
          'Не удалось прочитать сохранённые настройки. Данные не будут перезаписаны.';
    }
    ready = true;
    _reading = false;
    notifyListeners();
  }

  bool isFavorite(String id) => favorites.any((w) => w.id == id);
  Future<void> toggle(SavedWord word) async {
    if (!canEdit) return;
    if (isFavorite(word.id)) {
      favorites.removeWhere((w) => w.id == word.id);
    } else {
      favorites.insert(0, word);
    }
    await _save();
  }

  Future<void> opened(SavedWord word) async {
    if (!canEdit) return;
    final favoriteIndex = favorites.indexWhere((w) => w.id == word.id);
    if (favoriteIndex >= 0) favorites[favoriteIndex] = word;
    history.removeWhere((w) => w.id == word.id);
    history.insert(0, word);
    history = history.take(100).toList();
    await _save();
  }

  Future<void> settings({
    ThemeMode? theme,
    double? size,
    bool? endings,
    bool? proposed,
  }) async {
    if (!canEdit) return;
    themeMode = theme ?? themeMode;
    fontSize = (size ?? fontSize).clamp(16, 36);
    highlightEndings = endings ?? highlightEndings;
    showProposed = proposed ?? showProposed;
    await _save();
  }

  Future<void> clearHistory() async {
    if (!canEdit) return;
    history = [];
    await _save();
  }

  Future<void> _save() {
    if (_readFailed) {
      notifyListeners();
      return Future.value();
    }
    final raw = jsonEncode({
      'version': 1,
      'favorites': favorites.map((w) => w.toJson()).toList(),
      'history': history.map((w) => w.toJson()).toList(),
      'theme': themeMode.name,
      'fontSize': fontSize,
      'highlightEndings': highlightEndings,
      'showProposed': showProposed,
    });
    notifyListeners();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        await preferences.write(raw);
        error = null;
      } catch (_) {
        error = 'Не удалось сохранить изменения на устройстве.';
      }
      notifyListeners();
    });
    return _tail;
  }
}
