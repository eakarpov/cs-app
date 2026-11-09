import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';

class LexicalResult {
  LexicalResult(this.id, this.name, this.proposed, this.evidence);
  final String id, name;
  final bool proposed;
  final List<Json> evidence;
}

class LexicalSearchController extends ChangeNotifier {
  LexicalSearchController(this.repository);
  final DictionaryRepository repository;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false, suggesting = false, loading = false, searched = false;
  String query = '', type = 'synonym';
  String? error;
  SearchHit? selected;
  List<SearchHit> candidates = [];
  List<LexicalResult> results = [];
  void change(String value) {
    _timer?.cancel();
    final generation = ++_generation;
    query = value;
    selected = null;
    results = [];
    candidates = [];
    searched = false;
    error = null;
    loading = false;
    suggesting = value.trim().isNotEmpty;
    notifyListeners();
    if (!suggesting) return;
    _timer = Timer(const Duration(milliseconds: 200), () async {
      try {
        final page = await repository.search(value.trim(), 'cu-ru', limit: 5);
        if (_disposed || generation != _generation) return;
        candidates = page.items.take(5).toList();
      } catch (e) {
        if (_disposed || generation != _generation) return;
        error = e is DictionaryException
            ? e.message
            : 'Не удалось подобрать слова.';
      }
      if (_disposed || generation != _generation) return;
      suggesting = false;
      notifyListeners();
    });
  }

  void select(SearchHit hit) {
    _timer?.cancel();
    _generation++;
    selected = hit;
    query = hit.name;
    candidates = [];
    results = [];
    suggesting = false;
    loading = false;
    searched = false;
    error = null;
    notifyListeners();
  }

  void selectType(String value) {
    if (value == type || !{'synonym', 'antonym'}.contains(value)) return;
    if (selected == null) {
      type = value;
      change(query);
      return;
    }
    _generation++;
    type = value;
    results = [];
    loading = false;
    searched = false;
    error = null;
    notifyListeners();
  }

  Future<void> find() async {
    final source = selected;
    if (source == null || loading) return;
    _timer?.cancel();
    final generation = ++_generation;
    loading = true;
    error = null;
    results = [];
    searched = false;
    notifyListeners();
    try {
      final relations = await repository.lexicalRelations(source.id);
      if (_disposed || generation != _generation) return;
      final groups = <String, LexicalResult>{};
      for (final relation in relations) {
        final id = string(relation['targetId']),
            name = string(relation['targetName']);
        if (relation['type'] != type ||
            id.isEmpty ||
            name.isEmpty ||
            id == source.id ||
            !{'verified', 'proposed'}.contains(relation['status'])) {
          continue;
        }
        final proposed = relation['status'] != 'verified',
            key = '$id:$proposed';
        groups
            .putIfAbsent(key, () => LexicalResult(id, name, proposed, []))
            .evidence
            .add(relation);
      }
      results = groups.values.toList()
        ..sort(
          (a, b) => a.proposed != b.proposed
              ? (a.proposed ? 1 : -1)
              : a.name.compareTo(b.name),
        );
      searched = true;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e is DictionaryException ? e.message : 'Не удалось найти связи.';
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
