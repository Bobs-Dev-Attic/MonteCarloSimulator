import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

/// Set to true to route Firebase calls to the local emulator suite
/// (`firebase emulators:start`). Toggle via --dart-define=USE_EMULATOR=true.
const bool _useEmulator =
    bool.fromEnvironment('USE_EMULATOR', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (_useEmulator && !kReleaseMode) {
    const host = 'localhost';
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  }

  runApp(const ProviderScope(child: MonteCarloApp()));
}
