import 'package:flutter/material.dart';
import '../../../core/personal_store.dart';
import '../../dictionary/data/dictionary_repository.dart';
import '../domain/corpus.dart';
import 'corpus_widgets.dart';
import 'reader_screen.dart';

class ReaderLinkScreen extends StatefulWidget {
  const ReaderLinkScreen({
    super.key,
    required this.url,
    required this.dictionary,
    required this.personal,
  });
  final Uri url;
  final DictionaryRepository dictionary;
  final PersonalStore personal;
  @override
  State<ReaderLinkScreen> createState() => _ReaderLinkScreenState();
}

class _ReaderLinkScreenState extends State<ReaderLinkScreen> {
  late Future<CorpusSession> future;
  void load() {
    future = widget.dictionary.reader.session();
    future.ignore();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CorpusSession>(
    future: future,
    builder: (context, s) {
      if (s.hasData) {
        return ReaderScreen(
          repository: widget.dictionary.reader,
          dictionary: widget.dictionary,
          personal: widget.personal,
          session: s.data!,
          profile: s.data!.defaultProfile,
          url: widget.url.toString(),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Текст по ссылке')),
        body: Center(
          child: s.hasError
              ? CorpusErrorView(error: s.error!, retry: () => setState(load))
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
