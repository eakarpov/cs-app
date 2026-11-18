import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../data/reader_repository.dart';
import '../domain/corpus.dart';

class CorpusErrorView extends StatefulWidget {
  const CorpusErrorView({
    super.key,
    required this.error,
    required this.retry,
    this.current,
  });
  final Object error;
  final VoidCallback retry;
  final VoidCallback? current;
  @override
  State<CorpusErrorView> createState() => _CorpusErrorViewState();
}

class _CorpusErrorViewState extends State<CorpusErrorView> {
  Timer? timer;
  int get remaining =>
      widget.error is CorpusFailure &&
          (widget.error as CorpusFailure).retryAt != null
      ? ((widget.error as CorpusFailure).retryAt!
                    .difference(DateTime.now())
                    .inMilliseconds /
                1000)
            .ceil()
            .clamp(0, 2147483647)
      : 0;
  void schedule() {
    timer?.cancel();
    if (remaining > 0) {
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (remaining == 0) t.cancel();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(CorpusErrorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.error.toString()),
        TextButton(
          onPressed: remaining > 0 ? null : widget.retry,
          child: Text(
            remaining > 0 ? 'Повторить через $remaining с' : 'Повторить',
          ),
        ),
        if (widget.current != null)
          TextButton(
            onPressed: remaining > 0 ? null : widget.current,
            child: const Text('Открыть текущую версию'),
          ),
      ],
    ),
  );
}

/// Uses server UTF-16 surface ranges; no normalization or substring relocation.
class ProjectionText extends StatefulWidget {
  const ProjectionText({
    super.key,
    required this.projection,
    this.highlight = const [],
    required this.size,
    this.onToken,
  });
  final CorpusProjection projection;
  final List<String> highlight;
  final double size;
  final void Function(Wire)? onToken;
  @override
  State<ProjectionText> createState() => _ProjectionTextState();
}

class _ProjectionTextState extends State<ProjectionText> {
  final recognizers = <TapGestureRecognizer>[];
  void clear() {
    for (final r in recognizers) {
      r.dispose();
    }
    recognizers.clear();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    clear();
    final p = widget.projection;
    final spans = <InlineSpan>[];
    final ranges = <({int a, int b, Wire token})>[];
    for (final t in p.tokens) {
      for (final r in wireRanges(t['surfaceRanges'], max: p.text.length)) {
        ranges.add((a: r.$1, b: r.$2, token: t));
      }
    }
    ranges.sort((a, b) => a.a.compareTo(b.a));
    var at = 0;
    for (final r in ranges) {
      if (r.a < at) continue;
      if (r.a > at) spans.add(TextSpan(text: p.text.substring(at, r.a)));
      final isWord = [
        'word',
        'numberCandidate',
        'unresolved',
      ].contains(r.token['type']);
      TapGestureRecognizer? recognizer;
      if (isWord && widget.onToken != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onToken!(r.token);
        recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: p.text.substring(r.a, r.b),
          recognizer: recognizer,
          style: TextStyle(
            backgroundColor: widget.highlight.contains(r.token['tokenId'])
                ? Theme.of(context).colorScheme.tertiaryContainer
                : null,
            decoration: isWord && widget.onToken != null
                ? TextDecoration.underline
                : null,
            decorationStyle: TextDecorationStyle.dotted,
          ),
        ),
      );
      at = r.b;
    }
    if (at < p.text.length) spans.add(TextSpan(text: p.text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontFamily: 'Monomakh',
        fontFamilyFallback: const ['Shafarik'],
        fontSize: widget.size,
      ),
    );
  }
}
