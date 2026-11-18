import 'dart:convert';
import 'dart:io';
import 'package:cs/features/dictionary/data/dictionary_repository.dart';
import 'package:cs/features/reader/domain/corpus.dart';

Future<void> main() async {
  final dictionary = DictionaryRepository();
  final reader = dictionary.reader;
  final checks = <String, Object?>{};
  try {
    final session = await reader.session();
    checks['indexRevision'] = session.revision;
    checks['corpusRelease'] = session.release;
    checks['dictionaryVersion'] = session.dictionary;
    final catalog = await reader.catalog(session);
    final sources = wireList(catalog['items']).map(wireObject).toList();
    requireWire(sources.length == 5);
    checks['sources'] = <Object?>[];
    for (final source in sources) {
      final resolved = await reader.resolve(
        address: SourceAddress({'version': 2, 'sourceId': source['sourceId']}),
      );
      final address = SourceAddress(wireObject(resolved['resolvedAddress']));
      final profile = session.profiles.singleWhere(
        (p) => p['id'] == session.defaultProfile,
      );
      var packet = await reader.read(address, profile, limit: 20);
      var units = 0, projectionTokens = 0;
      final bodies = <String>{};
      while (true) {
        units += wireList(packet.data['units']).length;
        for (final raw in packet.projections) {
          final projection = CorpusProjection(
            wireObject(raw),
            profile: profile['id'],
          );
          bodies.add(projection.wire['bodyId']);
          projectionTokens += projection.tokens.length;
        }
        final cursor = packet.data['page']['nextCursor'] as String?;
        if (cursor == null) break;
        packet = await reader.read(address, profile, cursor: cursor, limit: 20);
      }
      final p = CorpusProjection(
        wireObject(packet.projections.first),
        profile: profile['id'],
      );
      (checks['sources'] as List).add({
        'sourceId': source['sourceId'],
        'addressPinned': address.pinned,
        'lastPageBody': p.wire['bodyId'],
        'lastPageTokenCount': p.tokens.length,
        'navigationUnits': units,
        'uniqueBodies': bodies.length,
        'projectedTokens': projectionTokens,
        'lastPageRawLengthUtf16': p.raw.length,
      });
      if (source['sourceId'] == 'src_9d0454d1a69b45939d7ebce42dd717ad' ||
          source['sourceId'] == 'src_3d81e2bf35684343ad079ff6ed83ec8b') {
        final passport = await reader.passport(address);
        checks[source['sourceId'] == 'src_9d0454d1a69b45939d7ebce42dd717ad'
                ? 'margaritFields'
                : 'irmosFields'] =
            passport['fields'];
      }
    }
    final page = await reader.search(
      session,
      session.defaultProfile,
      query: 'Христос',
    );
    requireWire(page.hits.length == 14);
    checks['surfaceHits'] = page.hits.length;
    final hit = page.hits.first;
    final profile = session.profiles.singleWhere(
      (p) => p['id'] == session.defaultProfile,
    );
    final context = await reader.read(
      hit.address,
      profile,
      window: {
        'bodyId': hit.wire['bodyId'],
        'rawRange': hit.snippet!.wire['rawWindow'],
      },
    );
    final projection = CorpusProjection(
      wireObject(context.projections.single),
      profile: session.defaultProfile,
    );
    hit.validateProjection(projection);
    final reviews = jsonDecode(
      File('data/corpus/m2-02-reviews.json').readAsStringSync(),
    );
    final rows = reviews is List ? reviews : reviews['reviews'];
    final lexeme =
        rows.firstWhere((r) => r['lexemeId'] != null)['lexemeId'] as String;
    final accepted = await reader.occurrences(
      session,
      session.defaultProfile,
      lexeme,
      session.dictionary,
    );
    checks['acceptedHits'] = accepted.hits.length;
    final token = projection.tokens.firstWhere(
      (t) => t['tokenId'] == hit.tokenIds.first,
    );
    final candidates = await dictionary.search(
      token['lookupKey']['value'],
      'cu-ru',
      version: session.dictionary,
      limit: 20,
    );
    requireWire(
      candidates.schemaVersion == 2 && candidates.version == session.dictionary,
    );
    checks['lookupPinnedD'] = true;
    checks['lookupExactCandidates'] = candidates.items
        .where((h) => h.exact)
        .length;
    final unicode = session.profiles.firstWhere(
      (p) => p['profiles']['display'] == 'display-unicode-r1',
    );
    final unicodeRead = await reader.read(
      hit.address,
      unicode,
      window: {
        'bodyId': hit.wire['bodyId'],
        'rawRange': hit.snippet!.wire['rawWindow'],
      },
    );
    hit.validateProjection(
      CorpusProjection(
        wireObject(unicodeRead.projections.single),
        profile: unicode['id'],
      ),
    );
    checks['profilesRoundTrip'] = true;
    final oldIrmos = await reader.resolve(
      url: 'https://www.typikon.info/chants/132',
    );
    requireWire(
      oldIrmos['resolvedAddress']['sourceId'] ==
          'src_3d81e2bf35684343ad079ff6ed83ec8b',
    );
    final permanent = await reader.resolve(url: hit.address.url.toString());
    for(final entry in hit.address.wire.entries) {
      requireWire(jsonEncode(permanent['resolvedAddress'][entry.key]) == jsonEncode(entry.value));
    }
    checks['legacyAndPermanentLinks'] = true;
    checks['status'] = 'passed';
  } finally {
    dictionary.close();
    File('qa/mobile/m2-mobile-live.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(checks)}\n',
    );
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(checks));
}
