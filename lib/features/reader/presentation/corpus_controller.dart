import 'package:flutter/foundation.dart';
import '../data/reader_repository.dart';
import '../domain/corpus.dart';

/// One query snapshot. A new query/profile invalidates every pending response.
class CorpusController extends ChangeNotifier {
  CorpusController(this.repository, {this.lexemeId, this.dictionaryVersion});
  final ReaderRepository repository;
  final String? lexemeId, dictionaryVersion;
  CorpusSession? session;
  String? profile;
  String query = '', mode = 'word';
  bool busy = false;
  Object? error;
  CorpusPage? page;
  final hits = <CorpusHit>[];
  int _generation = 0;
  bool _disposed = false;
  bool get restartRequired =>
      error is CorpusFailure && (error as CorpusFailure).restartRequired;
  Future<void> start({String? query, String? mode, String? profile}) async {
    final generation = ++_generation;
    if (query != null) this.query = query;
    if (mode != null) this.mode = mode;
    if (profile != null) this.profile = profile;
    busy = true;
    error = null;
    page = null;
    hits.clear();
    notifyListeners();
    try {
      final nextSession = await repository.session();
      if (_disposed || generation != _generation) return;
      session = nextSession;
      if (!nextSession.profiles.any((p) => p['id'] == this.profile)) {
        this.profile = nextSession.defaultProfile;
      }
      final result = await _fetch();
      if (_disposed || generation != _generation) return;
      page = result;
      hits.addAll(result.hits);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<CorpusPage> _fetch({String? cursor}) => lexemeId != null
      ? repository.occurrences(
          session!,
          profile!,
          lexemeId!,
          dictionaryVersion!,
          cursor: cursor,
        )
      : repository.search(
          session!,
          profile!,
          query: query,
          mode: mode,
          cursor: cursor,
        );
  Future<void> more() async {
    final cursor = page?.cursor;
    if (busy || cursor == null || restartRequired) return;
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final next = await _fetch(cursor: cursor);
      if (_disposed || generation != _generation) return;
      final existing = hits.map((h) => h.wire['hitId']).toSet();
      requireWire(!next.hits.any((h) => existing.contains(h.wire['hitId'])));
      page = next;
      hits.addAll(next.hits);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e is FormatException
          ? const CorpusFailure('Выдача изменилась. Начните поиск заново.')
          : e;
      if (restartRequired || e is CorpusFailure && e.status == 404) {
        hits.clear();
        page = null;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
