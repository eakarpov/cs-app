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
  String? error;
  List<SavedWord> favorites = [], history = [];
  ThemeMode themeMode = ThemeMode.system;
  double fontSize = 22;
  bool highlightEndings = true, showProposed = true;
  Future<void> _tail = Future.value();
  Future<void> retryPersistence() => _readFailed ? _load() : _save();
  Future<void> _load() async {
    _readFailed = false;
    error = null;
    try {
      final raw = await preferences.read();
      if (raw != null) {
        final j = object(jsonDecode(raw));
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
    } catch (_) {
      _readFailed = true;
      error =
          'Не удалось прочитать сохранённые настройки. Данные не будут перезаписаны.';
    }
    ready = true;
    notifyListeners();
  }

  bool isFavorite(String id) => favorites.any((w) => w.id == id);
  Future<void> toggle(SavedWord word) async {
    if (!ready) return;
    if (isFavorite(word.id)) {
      favorites.removeWhere((w) => w.id == word.id);
    } else {
      favorites.insert(0, word);
    }
    await _save();
  }

  Future<void> opened(SavedWord word) async {
    if (!ready) return;
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
    if (!ready) return;
    themeMode = theme ?? themeMode;
    fontSize = (size ?? fontSize).clamp(16, 36);
    highlightEndings = endings ?? highlightEndings;
    showProposed = proposed ?? showProposed;
    await _save();
  }

  Future<void> clearHistory() async {
    if (!ready) return;
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
