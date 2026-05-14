import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../env/env_check.dart';

/// Loads Firebase, localization, and env before [runApp] without blocking
/// each subsystem on the others.
Future<void> prepareCoreRuntime() async {
  await Future.wait<void>([
    Firebase.initializeApp(),
    EasyLocalization.ensureInitialized(),
    _loadEnvironment(),
  ]);
}

Future<void> _loadEnvironment() async {
  await dotenv.load(fileName: '.env');
  await verifyEnv();
}
