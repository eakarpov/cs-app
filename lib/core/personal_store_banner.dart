import 'package:flutter/material.dart';
import 'personal_store.dart';

class PersonalStoreBanner extends StatelessWidget {
  const PersonalStoreBanner({super.key, required this.personal});
  final PersonalStore personal;

  @override
  Widget build(BuildContext context) => personal.error == null
      ? const SizedBox.shrink()
      : MaterialBanner(
          content: Text(personal.error!),
          actions: [
            TextButton(
              onPressed: personal.retryPersistence,
              child: const Text('Повторить'),
            ),
          ],
        );
}
