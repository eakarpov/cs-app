import 'package:flutter/material.dart';
import '../../../core/app_version.dart';
import '../../../core/personal_store.dart';
import '../../../core/personal_store_banner.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.personal});
  final PersonalStore personal;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: personal,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PersonalStoreBanner(personal: personal),
          Text('Тема', style: Theme.of(context).textTheme.titleMedium),
          DropdownButton<ThemeMode>(
            value: personal.themeMode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('Как в системе'),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text('Светлая тема'),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text('Тёмная тема'),
              ),
            ],
            onChanged: (value) => personal.settings(theme: value),
          ),
          const SizedBox(height: 20),
          Text('Размер текста: ${personal.fontSize.round()}'),
          Slider(
            value: personal.fontSize,
            min: 16,
            max: 36,
            divisions: 20,
            label: personal.fontSize.round().toString(),
            onChanged: (value) => personal.settings(size: value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Выделять окончания'),
            value: personal.highlightEndings,
            onChanged: (value) => personal.settings(endings: value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Показывать предположительные связи'),
            value: personal.showProposed,
            onChanged: (value) => personal.settings(proposed: value),
          ),
          const SizedBox(height: 20),
          const Text(
            'Приложение работает при наличии сети. Избранное, история и настройки хранятся на этом устройстве.',
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Лексикон ЦС',
              applicationVersion: appVersion,
            ),
            child: const Text('Лицензии'),
          ),
        ],
      ),
    ),
  );
}
