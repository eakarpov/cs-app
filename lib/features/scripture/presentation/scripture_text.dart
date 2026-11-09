import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/external_link.dart';
import '../domain/scripture_reference.dart';

/// Preserves source typography and selection; only recognized Scripture addresses are links.
class ScriptureText extends StatefulWidget {
  const ScriptureText(
    this.text, {
    super.key,
    this.style,
    this.spans,
    this.onOpen,
  });
  final String text;
  final TextStyle? style;
  final List<TextSpan>? spans;
  final void Function(Uri)? onOpen;
  @override
  State<ScriptureText> createState() => _ScriptureTextState();
}

class _ScriptureTextState extends State<ScriptureText> {
  final _recognizers = <TapGestureRecognizer>[];
  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final runs = widget.spans ?? [TextSpan(text: widget.text)];
    final text = runs.map((s) => s.text ?? '').join();
    final refs = scriptureReferences(text);
    final children = <TextSpan>[];
    var offset = 0;
    // Split at both source-style and citation boundaries, so references spanning runs work.
    for (final run in runs) {
      final value = run.text ?? '', end = offset + value.length;
      var position = offset;
      while (position < end) {
        ScriptureReference? active;
        var boundary = end;
        for (final ref in refs) {
          if (ref.start <= position && position < ref.end) {
            active = ref;
            boundary = ref.end < end ? ref.end : end;
            break;
          }
          if (ref.start > position && ref.start < boundary) {
            boundary = ref.start;
          }
        }
        TapGestureRecognizer? recognizer;
        if (active != null) {
          final uri = active.uri;
          recognizer = TapGestureRecognizer()
            ..onTap = () {
              if (widget.onOpen != null) {
                widget.onOpen!(uri);
              } else {
                openExternalLink(context, uri.toString());
              }
            };
          _recognizers.add(recognizer);
        }
        children.add(
          TextSpan(
            text: value.substring(position - offset, boundary - offset),
            style: active == null
                ? run.style
                : (run.style ?? const TextStyle()).copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
            recognizer: recognizer,
            mouseCursor: active == null ? null : SystemMouseCursors.click,
          ),
        );
        position = boundary;
      }
      offset = end;
    }
    return SelectableText.rich(
      TextSpan(children: children),
      style: widget.style,
    );
  }
}
