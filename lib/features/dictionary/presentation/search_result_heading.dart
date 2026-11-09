import 'package:flutter/material.dart';
import '../domain/models.dart';

class SearchResultHeading extends StatelessWidget {
  const SearchResultHeading({super.key, required this.hit, required this.size});

  final SearchHit hit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final word = Text(
      hit.name,
      style: TextStyle(fontFamily: 'Monomakh', fontSize: size),
    );
    final indicator = hit.indicator;
    if (indicator == null) return word;

    if (indicator == SearchIndicator.exact) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          word,
          Tooltip(
            message: 'Полное совпадение запроса',
            child: Semantics(
              label: 'Полное совпадение запроса',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '100%',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final translation = indicator == SearchIndicator.translation;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = translation
        ? (dark ? Colors.green.shade300 : Colors.green.shade700)
        : (dark ? Colors.blue.shade300 : Colors.blue.shade700);
    final label = translation
        ? 'Совпадение с переводом'
        : 'Совпадение по началу слова';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(fit: FlexFit.loose, child: word),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Icon(
              translation ? Icons.check_circle : Icons.arrow_forward_rounded,
              size: 20,
              color: color,
              semanticLabel: label,
            ),
          ),
        ),
      ],
    );
  }
}
