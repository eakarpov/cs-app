import 'dart:convert';
import 'dart:io';
import 'package:cs/features/reader/domain/reader_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture =
      jsonDecode(File('docs/pilot/reader-api-examples.json').readAsStringSync())
          as Map<String, dynamic>;
  final examples = fixture['examples'] as List;
  final read = examples.firstWhere(
    (e) => e['responseSchema'] == 'ReadResponse',
  )['response'];
  test('all success fixtures decode without dropping extended metadata', () {
    for (final example in examples) {
      final packet = ReaderEnvelope.decode(jsonEncode(example['response']));
      expect(packet.data, example['response']['data']);
    }
  });
  test('raw UTF16 offsets and local display offsets survive the wire', () {
    final packet = ReaderReadPacket.decode(jsonEncode(read));
    final projection = packet.projections.single;
    expect(projection['rawWindow'], [47, 51]);
    expect(projection['rawText'], 'бл҃г');
    expect(projection['tokens'].single['surfaceRanges'], [
      [0, 4],
    ]);
    expect(packet.address['sourceRevision'], isNotEmpty);
    expect(String.fromCharCode(0xf0023).length, 2);
  });
  test(
    'four semantic negative fixtures fail before a highlight can be applied',
    () {
      for (final item in fixture['semanticInvalidExamples'] as List) {
        expect(
          () => ReaderReadPacket.decode(jsonEncode(item['value'])),
          throwsFormatException,
          reason: item['id'] as String,
        );
      }
    },
  );
  test('unknown metadata and future fields are preserved verbatim', () {
    final wire = jsonDecode(jsonEncode(read)) as Map<String, dynamic>;
    wire['data']['futureMetadata'] = {
      'type': 'opaque',
      'raw': 'неизвестная атрибуция',
      'date': null,
    };
    final packet = ReaderReadPacket.decode(jsonEncode(wire));
    expect(packet.data['futureMetadata'], wire['data']['futureMetadata']);
  });
  test('unknown error codes are surfaced with their retryability', () {
    expect(
      () => ReaderEnvelope.decode(
        jsonEncode({
          'contract': 'cs-reader/1',
          'error': {
            'code': 'future_code',
            'message': 'Тест',
            'retryable': false,
          },
        }),
      ),
      throwsA(
        isA<ReaderApiFailure>().having((e) => e.code, 'code', 'future_code'),
      ),
    );
  });
  test('unsupported contract and mixed success/error envelope fail', () {
    expect(
      () => ReaderEnvelope.decode('{"contract":"future","data":{}}'),
      throwsFormatException,
    );
    expect(
      () => ReaderEnvelope.decode(
        '{"contract":"cs-reader/1","data":{},"error":{}}',
      ),
      throwsFormatException,
    );
  });
}
