import 'package:flutter/material.dart';
import '../../../core/external_link.dart';
import '../domain/content.dart';

class EncyclopediaHome extends StatelessWidget {
  const EncyclopediaHome({super.key, required this.textSize});
  final double textSize;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'Знакомимся с церковнославянским письмом.',
        style: TextStyle(fontSize: textSize),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.abc),
          title: const Text('Азбуки'),
          subtitle: const Text('Кириллица и глаголица'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AlphabetsScreen(textSize: textSize),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Диакритика'),
          subtitle: const Text('Надстрочные знаки и знаки чисел'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DiacriticsScreen(textSize: textSize),
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('Ждите обновлений', textAlign: TextAlign.center),
      ),
    ],
  );
}

class AlphabetsScreen extends StatelessWidget {
  const AlphabetsScreen({super.key, required this.textSize});
  final double textSize;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Азбуки')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final glagolitic in [false, true])
          Card(
            child: ListTile(
              title: Text(glagolitic ? 'Глаголица' : 'Кириллица'),
              subtitle: Text(
                glagolitic
                    ? 'Другая славянская азбука: знакомимся с буквами'
                    : 'Буквы церковной печати и их названия',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AlphabetScreen(
                    glagolitic: glagolitic,
                    textSize: textSize,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget references(BuildContext context, List<EncyclopediaSource> sources) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Источники и дальнейшее чтение',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final source in sources)
            TextButton.icon(
              onPressed: () => openExternalLink(context, source.url),
              icon: const Icon(Icons.open_in_new),
              label: Text(source.title),
            ),
        ],
      ),
    );

class AlphabetScreen extends StatelessWidget {
  const AlphabetScreen({
    super.key,
    required this.glagolitic,
    required this.textSize,
  });
  final bool glagolitic;
  final double textSize;
  @override
  Widget build(BuildContext context) {
    final letters = glagolitic ? glagoliticLetters : cyrillicLetters;
    return Scaffold(
      appBar: AppBar(title: Text(glagolitic ? 'Глаголица' : 'Кириллица')),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              glagolitic
                  ? 'Глаголица — одна из двух славянских азбук. Названия многих букв знакомы по кириллице, но их облик иной. Ниже — начальная подборка букв для знакомства; она не представляет весь исторический алфавит.'
                  : 'В церковнославянской кириллице есть знакомые по русскому письму и особые буквы. Ниже показаны буквы и варианты начертания, встречающиеся в церковной печати русского синодального извода.',
              style: TextStyle(fontSize: textSize),
            ),
            const SizedBox(height: 16),
            for (final letter in letters)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        letter.$1,
                        style: TextStyle(
                          fontFamily: glagolitic ? 'Shafarik' : 'Monomakh',
                          fontSize: textSize + 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(letter.$2, style: TextStyle(fontSize: textSize)),
                    ],
                  ),
                ),
              ),
            references(context, [
              if (glagolitic) glagoliticSource else alphabetSource,
            ]),
          ],
        ),
      ),
    );
  }
}

class DiacriticsScreen extends StatelessWidget {
  const DiacriticsScreen({super.key, required this.textSize});
  final double textSize;
  Widget note(EncyclopediaItem item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: TextStyle(fontSize: textSize, fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              item.sample,
              style: TextStyle(fontFamily: 'Monomakh', fontSize: textSize + 16),
            ),
          ),
          Text(item.explanation, style: TextStyle(fontSize: textSize)),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Диакритика')),
    body: SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Надстрочные знаки',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Краткий справочник по знакам церковной печати русского синодального извода. Пунктирный кружок в образцах показывает место буквы и не является частью знака.',
            style: TextStyle(fontSize: textSize),
          ),
          ...diacriticItems.map(note),
          const SizedBox(height: 24),
          Text('Знаки чисел', style: Theme.of(context).textTheme.titleLarge),
          ...numberItems.map(note),
          references(context, [marksSource, signsTableSource, numbersSource]),
        ],
      ),
    ),
  );
}
