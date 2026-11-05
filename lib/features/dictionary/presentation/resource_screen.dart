import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/dictionary_repository.dart';
import '../domain/models.dart';

class ResourceScreen extends StatefulWidget {
  const ResourceScreen({
    super.key,
    required this.repository,
    required this.id,
    this.protoId,
    this.expectedBodyHash,
    this.lookup,
    required this.size,
  });
  final DictionaryRepository repository;
  final String id;
  final String? expectedBodyHash;
  final int? protoId;
  final double size;
  final void Function(String)? lookup;
  @override
  State<ResourceScreen> createState() => _ResourceScreenState();
}

class _ResourceScreenState extends State<ResourceScreen> {
  late Future<Json> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = widget.protoId != null
        ? widget.repository.etymology(widget.protoId!)
        : widget.repository.source(widget.id);
  }

  Future<void> openLink(String target) async {
    if (target.startsWith('lookup:')) {
      widget.lookup?.call(target.substring(7));
      return;
    }
    final uri = Uri.tryParse(target);
    if (uri != null && ['https', 'http'].contains(uri.scheme)) {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть ссылку.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.protoId == null ? 'Статья источника' : 'Этимология'),
    ),
    body: FutureBuilder<Json>(
      future: future,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.error.toString()),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(load),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final j = s.data!;
        if (widget.protoId != null) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                string(j['lemma']),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              if (widget.expectedBodyHash != null &&
                  string(j['bodySha256']) != widget.expectedBodyHash)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Этимологическая статья обновлена после проверки связи. Сверьте приведённое свидетельство с новой редакцией.',
                  ),
                ),
              SelectableText(
                string(j['body']),
                style: TextStyle(
                  fontSize: widget.size,
                  fontFamily: 'OldStandard',
                ),
              ),
              if (string(j['sourceUrl']).isNotEmpty)
                TextButton(
                  onPressed: () => openLink(string(j['sourceUrl'])),
                  child: const Text('Источник этимологической статьи'),
                ),
            ],
          );
        }
        final paragraphs = array(j['paragraphs']).map(object).toList();
        final targets = paragraphs
            .expand((p) => array(p['runs']))
            .map(object)
            .where((r) => string(r['target']).isNotEmpty)
            .map((r) => string(r['target']))
            .toSet();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              string(j['title']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            for (final p in paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  label: array(
                    p['runs'],
                  ).map((v) => string(object(v)['text'])).join(),
                  excludeSemantics: true,
                  child: SelectableText.rich(
                    TextSpan(
                      children: array(p['runs']).map((v) {
                        final r = object(v);
                        return TextSpan(
                          text: string(r['text']),
                          style: TextStyle(
                            fontFamily: r['kind'] == 'church'
                                ? 'Monomakh'
                                : 'OldStandard',
                            fontWeight: r['kind'] == 'strong'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontStyle: r['kind'] == 'emphasis'
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        );
                      }).toList(),
                    ),
                    style: TextStyle(fontSize: widget.size, height: 1.5),
                  ),
                ),
              ),
            if (targets.isNotEmpty) const Text('Ссылки в статье'),
            for (final t in targets)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => openLink(t),
                  child: Text(t.startsWith('lookup:') ? t.substring(7) : t),
                ),
              ),
          ],
        );
      },
    ),
  );
}
