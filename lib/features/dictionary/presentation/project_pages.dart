import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Titles and destinations checked against the publishers on 2026-11-05.
const projectResources = [
  (
    group: 'Наши проекты',
    title: 'Уставные чтения',
    description:
        'Тексты на церковнославянском и русском языках, чтения по церковному календарю. На портале доступно приложение для Android.',
    url: 'https://www.typikon.info/',
  ),
  (
    group: 'Учебники и справочники',
    title: 'Учебное руководство по церковнославянскому языку',
    description:
        'А. А. Плетнёва, А. Г. Кравецкий. Уроки, упражнения, тексты и грамматический справочник.',
    url:
        'https://azbyka.ru/otechnik/Aleksandr-Kraveckij/uchebnoe-rukovodstvo-po-tserkovnoslavjanskomu-jazyku/',
  ),
  (
    group: 'Учебники и справочники',
    title: 'Грамматика церковнославянского языка',
    description:
        'Иеромонах Алипий (Гаманович). Систематическое изложение грамматики.',
    url:
        'https://azbyka.ru/otechnik/Spravochniki/grammatika-tserkovnoslavjanskogo-jazyka-gamanovich/',
  ),
  (
    group: 'Учебники и справочники',
    title: 'Церковнославянский язык в таблицах',
    description:
        'Алфавит, надстрочные знаки, числовые обозначения и грамматические таблицы.',
    url: 'https://azbyka.ru/cerkovnoslavyanskij-yazyk-v-tablicax',
  ),
  (
    group: 'О языке и его истории',
    title: 'Церковнославянский язык',
    description:
        'Обзорная статья и подборка материалов в энциклопедии «Азбука веры».',
    url: 'https://azbyka.ru/cerkovnoslavyanskij-yazyk',
  ),
  (
    group: 'О языке и его истории',
    title: 'История церковнославянского языка в России. Введение',
    description:
        'А. Г. Кравецкий, А. А. Плетнёва. О церковнославянском языке и его изучении в конце XIX — начале XX века.',
    url:
        'https://azbyka.ru/otechnik/Aleksandr-Kraveckij/istorija-tserkovnoslavjanskogo-jazyka-v-rossii-konets-xix-nachalo-xx-v/1',
  ),
];

class UsefulResourcesScreen extends StatelessWidget {
  const UsefulResourcesScreen({super.key});

  Future<void> open(BuildContext context, String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Some devices have no browser or deny external intents.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку в браузере.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Полезные ресурсы')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Материалы для изучения языка и чтения текстов. Ссылки открываются в браузере.',
        ),
        for (var i = 0; i < projectResources.length; i++) ...[
          if (i == 0 ||
              projectResources[i].group != projectResources[i - 1].group)
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Text(
                projectResources[i].group,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(projectResources[i].title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${projectResources[i].description}\n${Uri.parse(projectResources[i].url).host}',
                ),
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => open(context, projectResources[i].url),
            ),
          ),
        ],
      ],
    ),
  );
}

class ProjectAboutScreen extends StatelessWidget {
  const ProjectAboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('О проекте')),
    body: SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/branding/app-icon.png',
                width: 96,
                height: 96,
                semanticLabel: 'Знак ЦС Словаря',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('ЦС Словарь', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Версия 0.1.2 · тестовый выпуск'),
          const SizedBox(height: 24),
          const Text(
            'Словарь помогает понимать церковнославянские тексты и изучать язык: находить слова и словоформы, читать толкования и разбирать словоизменение. Проект развивается вместе с «Уставными чтениями».',
          ),
          const SizedBox(height: 24),
          Text(
            'Как читать статьи',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Толкования разных словарей сохраняются отдельно, с указанием источника. Их формулировки могут различаться. Происхождение данных и пометы доступны по значку информации в статье.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Выписанные словоформы отличаются от расчётных. Если парадигма или граница окончания не установлена, приложение указывает это. Подтверждённые смысловые связи и предположительные сопоставления показываются раздельно.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Содержание статей загружается через интернет. Избранное, последние открытые статьи и настройки хранятся на устройстве без регистрации.',
          ),
          const SizedBox(height: 24),
          Text('Помочь словарю', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Заметили неточность? В статье можно отправить сообщение об ошибке, а после поиска — сообщить о недостающем слове.',
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Полезные ресурсы'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const UsefulResourcesScreen(),
              ),
            ),
          ),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'ЦС Словарь',
              applicationVersion: '0.1.2',
            ),
            child: const Text('Лицензии'),
          ),
        ],
      ),
    ),
  );
}
