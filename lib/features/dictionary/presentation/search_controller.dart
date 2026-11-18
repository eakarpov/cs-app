import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';

class WordSearchController extends ChangeNotifier {
  WordSearchController(this.repository);
  final DictionaryRepository repository;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false, loading = false;
  bool loadingMore = false, restartRequired = false;
  int schemaVersion = 2;
  String query = '', direction = 'cu-ru';
  String? error, nextCursor, version;
  Object? failure;
  List<SearchHit> items = [];
  void change(String value, {String? mode, bool immediate = false}) {
    _timer?.cancel();
    query = value;
    direction = mode ?? direction;
    _generation++;
    items = [];
    nextCursor = null;
    version = null;
    error = null;
    failure = null;
    loadingMore = false;
    restartRequired = false;
    schemaVersion = 2;
    loading = value.trim().isNotEmpty;
    notifyListeners();
    if (value.trim().isEmpty) return;
    final generation = _generation;
    if (immediate) {
      _fetch(generation, false);
    } else {
      _timer = Timer(
        const Duration(milliseconds: 250),
        () => _fetch(generation, false),
      );
    }
  }

  Future<void> more() async {
    if (loading || nextCursor == null) return;
    await _fetch(_generation, true);
  }

  void retry() {
    if (loading) return;
    if (!restartRequired && items.isNotEmpty && nextCursor != null) {
      more();
    } else {
      change(query, immediate: true);
    }
  }

  Future<void> _fetch(int generation, bool append) async {
    if (_disposed || generation != _generation) return;
    loading = true;
    loadingMore = append;
    error = null;
    failure = null;
    notifyListeners();
    try {
      final page = await repository.search(
        query.trim(),
        direction,
        cursor: append ? nextCursor : null,
        version: append && schemaVersion == 2 ? version : null,
        schema: append ? schemaVersion : 2,
      );
      if (_disposed || generation != _generation) return;
      if (append && version != null && version != page.version) {
        loading = false;
        nextCursor = null;
        error = 'Словарь обновился. Повторите поиск.';
        restartRequired = true;
        loadingMore = false;
        notifyListeners();
        return;
      }
      items = append
          ? {
              for (final hit in [...items, ...page.items]) hit.id: hit,
            }.values.toList()
          : page.items;
      version = page.version;
      schemaVersion = page.schemaVersion;
      nextCursor = page.nextCursor;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      failure = e;
      error = e is DictionaryException
          ? e.message
          : 'Не удалось выполнить поиск.';
      if (e is DictionaryException &&
          (e.status == 409 ||
              e.code == 'bad_cursor' ||
              e.code == 'invalid_contract' && append)) {
        restartRequired = true;
        nextCursor = null;
      }
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    loadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
