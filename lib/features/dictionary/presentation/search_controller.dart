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
  String query = '', direction = 'cu-ru';
  String? error, nextCursor, version;
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

  void retry() => change(query, immediate: true);
  Future<void> _fetch(int generation, bool append) async {
    if (_disposed || generation != _generation) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await repository.search(
        query.trim(),
        direction,
        cursor: append ? nextCursor : null,
      );
      if (_disposed || generation != _generation) return;
      if (append && version != null && version != page.version) {
        loading = false;
        nextCursor = null;
        error = 'Словарь обновился. Повторите поиск.';
        notifyListeners();
        return;
      }
      items = append
          ? {
              for (final hit in [...items, ...page.items]) hit.id: hit,
            }.values.toList()
          : page.items;
      version = page.version;
      nextCursor = page.nextCursor;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e is DictionaryException
          ? e.message
          : 'Не удалось выполнить поиск.';
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
