import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app/app.dart';
import 'core/personal_store.dart';
import 'features/dictionary/data/dictionary_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Monomakh Unicode',
      'Old Standard',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'Shafarik',
    ], await rootBundle.loadString('assets/fonts/Shafarik-OFL.txt'));
  });
  runApp(
    ChurchSlavonicApp(
      repository: DictionaryRepository(),
      personal: PersonalStore(DevicePreferences()),
    ),
  );
}
