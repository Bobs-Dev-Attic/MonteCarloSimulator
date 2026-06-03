import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/simulation_service.dart';

/// Shared singletons.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());
final simulationServiceProvider =
    Provider<SimulationService>((ref) => SimulationService());

/// Current auth state, drives the login gate.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// Live list of the signed-in user's saved simulations.
final savedSimulationsProvider =
    StreamProvider.autoDispose<List<SavedSimulation>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(firestoreServiceProvider).watchSimulations(user.uid);
});
